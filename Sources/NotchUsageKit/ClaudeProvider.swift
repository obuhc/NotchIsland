import Foundation

/// Claude 用量。优先级：
/// 1. 官方端点（仅在用户在设置里显式授权 officialEnabled 后；60s 节流缓存）
/// 2. statusLine 采集文件（CLI 场景）
/// 3. ccusage token 估算
///
/// 官方路径会读取本地 Claude OAuth token 并调用 Anthropic 用量接口，
/// 因此默认关闭，必须由用户主动授权（见 AppSettings.claudeOfficialEnabled）。
public struct ClaudeProvider {
    let harvestFile: URL
    let apiCache: URL
    let backoffFile: URL
    let tokenLimit: Int?
    /// 用户是否已授权官方用量（读本地 token + 调端点）。默认关闭。
    let officialEnabled: Bool
    /// true=用户查看时实时拉；false=后台拉，命中缓存就不打网络。
    let forceFresh: Bool

    /// 后台拉的缓存有效期（秒）。端点限流很紧，平时拉得很慢（省心档：30 分钟）。
    public static let backgroundCacheTTL: TimeInterval = 1800
    /// 命中 429 时默认退避时长（秒），无 Retry-After 时用。
    static let defaultBackoff: TimeInterval = 1800

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                tokenLimit: Int? = nil,
                officialEnabled: Bool = false,
                forceFresh: Bool = false) {
        self.harvestFile = home.appending(path: ".notchisland/claude-usage.json")
        self.apiCache = home.appending(path: ".notchisland/claude-usage-api.json")
        self.backoffFile = home.appending(path: ".notchisland/claude-429-until")
        self.tokenLimit = tokenLimit
        self.officialEnabled = officialEnabled
        self.forceFresh = forceFresh
    }

    public func snapshot() -> UsageSnapshot {
        if officialEnabled, let official = officialViaAPI() { return official }
        if let harvest = readHarvest() { return harvest }
        return ccusageFallback()
    }

    // MARK: - 官方端点（需用户授权）

    private func officialViaAPI() -> UsageSnapshot? {
        // 1) 退避期内：不调，用上次成功缓存并标注限流恢复时间。
        if let until = backoffUntil(), Date() < until {
            return readAPICache(maxAge: .greatestFiniteMagnitude)?.markedRateLimited(until: until)
        }
        // 2) 缓存够新直接用。
        let maxAge: TimeInterval = forceFresh ? 0 : Self.backgroundCacheTTL
        if let fresh = readAPICache(maxAge: maxAge) { return fresh }
        // 3) 拉新；失败时回退旧缓存（若此刻刚触发 429 则一并标注）。
        guard let data = fetchUsage(),
              let snap = parseUtilization(data), snap.isOK
        else {
            let stale = readAPICache(maxAge: .greatestFiniteMagnitude)
            if let until = backoffUntil(), Date() < until {
                return stale?.markedRateLimited(until: until)
            }
            return stale
        }
        try? data.write(to: apiCache)
        return snap
    }

    /// 读本地 OAuth token，调 Anthropic 官方用量端点，返回原始 JSON。
    /// 命中 429 时按 Retry-After 退避，期间完全不再调用（保护账号、不再触发限流）。
    private func fetchUsage() -> Data? {
        // 退避期内：直接不调。
        if let until = backoffUntil(), Date() < until { return nil }

        guard let token = OAuthToken.claude(),
              let url = URL(string: "https://api.anthropic.com/api/oauth/usage")
        else { return nil }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.timeoutInterval = 12

        var result: Data?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            if let http = resp as? HTTPURLResponse {
                if http.statusCode == 200 {
                    result = data
                    self.clearBackoff()
                } else if http.statusCode == 429 {
                    let ra = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(Double.init)
                        ?? Self.defaultBackoff
                    // 多等 2 分钟余量：不卡在窗口边界重试、又被 429，避免死循环。
                    self.setBackoff(Date().addingTimeInterval(ra + 120))
                }
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 13)
        return result
    }

    // MARK: - 429 退避状态（落盘，跨轮询/重启保持）

    private func backoffUntil() -> Date? {
        guard let s = try? String(contentsOf: backoffFile, encoding: .utf8),
              let t = TimeInterval(s.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    private func setBackoff(_ until: Date) {
        try? "\(until.timeIntervalSince1970)".write(to: backoffFile, atomically: true, encoding: .utf8)
    }

    private func clearBackoff() {
        try? FileManager.default.removeItem(at: backoffFile)
    }

    private func readAPICache(maxAge: TimeInterval) -> UsageSnapshot? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: apiCache.path),
              let mtime = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(mtime) <= maxAge,
              let data = try? Data(contentsOf: apiCache)
        else { return nil }
        return parseUtilization(data)
    }

    /// 官方端点返回：five_hour/seven_day → utilization(0-100) + resets_at(ISO)。
    private func parseUtilization(_ data: Data) -> UsageSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let windows = utilizationWindows(root)
        guard !windows.isEmpty else { return nil }
        return UsageSnapshot(provider: "Claude", source: .official, windows: windows)
    }

    private func utilizationWindows(_ root: [String: Any]) -> [UsageWindow] {
        func make(_ key: String, _ label: String, _ minutes: Int) -> UsageWindow? {
            guard let d = root[key] as? [String: Any] else { return nil }
            let used = (d["utilization"] as? NSNumber)?.doubleValue
            let reset = (d["resets_at"] as? String).flatMap(Self.isoFlexible)
            guard used != nil || reset != nil else { return nil }
            // 官方端点是实时权威数据，直接用，不做 rolledOver（那是给 Codex 旧快照的）。
            return UsageWindow(label: label, usedPercent: used, resetsAt: reset, windowMinutes: minutes)
        }
        return [make("five_hour", "5h", 300), make("seven_day", "周", 10080)].compactMap { $0 }
    }

    // MARK: - statusLine 采集文件（CLI 场景）

    private func readHarvest() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: harvestFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rl = root["rate_limits"] as? [String: Any]
        else { return nil }

        let captured = (root["capturedAt"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue) } ?? Date()

        var windows: [UsageWindow] = []
        if let fh = rl["five_hour"] as? [String: Any] {
            windows.append(harvestWindow(from: fh, label: "5h", minutes: 300, since: captured))
        }
        if let sd = rl["seven_day"] as? [String: Any] {
            windows.append(harvestWindow(from: sd, label: "周", minutes: 10080, since: captured))
        }
        guard !windows.isEmpty else { return nil }
        return UsageSnapshot(provider: "Claude", source: .official, windows: windows, capturedAt: captured)
    }

    private func harvestWindow(from d: [String: Any], label: String, minutes: Int, since: Date) -> UsageWindow {
        let used = (d["used_percentage"] as? NSNumber)?.doubleValue
        let reset = (d["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        let stale = Date().timeIntervalSince(since) > 1800
        return UsageWindow(label: label, usedPercent: used, resetsAt: reset,
                           windowMinutes: minutes, detail: stale ? "截至 \(Self.hm(since))" : nil)
            .rolledOver()
    }

    // MARK: - 回退：ccusage 估算（仅 5h）

    private func ccusageFallback() -> UsageSnapshot {
        func fail(_ msg: String) -> UsageSnapshot {
            UsageSnapshot(provider: "Claude", source: .estimate, windows: [], error: msg)
        }
        guard let data = runCCUsage(),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = root["blocks"] as? [[String: Any]],
              let block = blocks.first(where: { ($0["isActive"] as? Bool) == true }) ?? blocks.last
        else { return fail("拿不到官方用量，且 ccusage 无可用窗口") }

        let total = (block["totalTokens"] as? NSNumber)?.intValue ?? 0
        let reset = (block["endTime"] as? String).flatMap(Self.iso)
        let pct = tokenLimit.map { min(100, Double(total) / Double($0) * 100) }
        let window = UsageWindow(label: "5h", usedPercent: pct, resetsAt: reset,
                                 windowMinutes: 300, detail: "\(Self.compact(total)) tokens·估算")
        return UsageSnapshot(provider: "Claude", source: .estimate, windows: [window])
    }

    private func runCCUsage() -> Data? {
        let attempts: [[String]] = [
            ["ccusage", "blocks", "--json", "--active"],
            ["npx", "--yes", "ccusage@latest", "blocks", "--json", "--active"],
        ]
        for args in attempts {
            if let out = Self.shell(args), !out.isEmpty { return out }
        }
        return nil
    }

    // MARK: - 工具

    private static func shell(_ args: [String]) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? data : nil
    }

    private static func iso(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    /// 容错 ISO8601：处理 6 位微秒 + 时区偏移（如 ...204393+00:00）。
    static func isoFlexible(_ s: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let stripped = s.replacingOccurrences(of: "\\.\\d+", with: "", options: .regularExpression)
        return plain.date(from: stripped) ?? plain.date(from: s)
    }

    private static func hm(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }

    private static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return "\(n / 1000)K" }
        return "\(n)"
    }
}

/// 读取本地 Claude OAuth access token（仅在用户授权官方用量后才被调用）。
enum OAuthToken {
    static func claude() -> String? {
        fromCredentialsFile() ?? fromSecurityCLI()
    }

    /// ~/.claude/.credentials.json（CLI 场景，无 keychain 弹窗）。
    private static func fromCredentialsFile() -> String? {
        let p = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/.credentials.json")
        guard let data = try? Data(contentsOf: p) else { return nil }
        return accessToken(from: data)
    }

    /// macOS Keychain（桌面客户端场景）。首次访问会弹一次系统授权框。
    private static func fromSecurityCLI() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return accessToken(from: data)
    }

    private static func accessToken(from data: Data) -> String? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = o["claudeAiOauth"] as? [String: Any],
              let t = oauth["accessToken"] as? String else { return nil }
        return t
    }
}
