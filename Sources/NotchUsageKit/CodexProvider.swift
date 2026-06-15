import Foundation

/// 从 Codex 最新会话 rollout 里读取官方限流数据。
/// 数据形如：
/// "rate_limits":{"primary":{"used_percent":2.0,"window_minutes":300,"resets_at":1781416940},
///                "secondary":{"used_percent":28.0,"window_minutes":10080,"resets_at":1781748331}}
public struct CodexProvider {
    let sessionsDir: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.sessionsDir = home.appending(path: ".codex/sessions")
    }

    public func snapshot() -> UsageSnapshot {
        func fail(_ msg: String) -> UsageSnapshot {
            UsageSnapshot(provider: "Codex", source: .official, windows: [], error: msg)
        }

        guard let rl = bestRateLimits() else { return fail("找不到会话 rate_limits") }

        var windows: [UsageWindow] = []
        if let p = rl["primary"] as? [String: Any] { windows.append(window(from: p, label: "5h")) }
        if let s = rl["secondary"] as? [String: Any] { windows.append(window(from: s, label: "周")) }
        guard !windows.isEmpty else { return fail("rate_limits 为空") }

        return UsageSnapshot(provider: "Codex", source: .official, windows: windows)
    }

    // MARK: - 内部实现

    private func window(from dict: [String: Any], label: String) -> UsageWindow {
        let used = (dict["used_percent"] as? NSNumber)?.doubleValue
        let mins = (dict["window_minutes"] as? NSNumber)?.intValue
        let reset = (dict["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return UsageWindow(label: label, usedPercent: used, resetsAt: reset, windowMinutes: mins)
            .rolledOver()
    }

    /// 跨近期会话挑「最该展示」的 rate_limits。
    /// 多账号/多凭证时不同会话的 rate_limits 会冲突（如一个 0%、一个 34%），
    /// 取**周用量最高**的那条（即你实际在消耗的额度），避免被刚开新周的 0% 盖掉。
    private func bestRateLimits() -> [String: Any]? {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: sessionsDir,
                                     includingPropertiesForKeys: [.contentModificationDateKey],
                                     options: [.skipsHiddenFiles]) else { return nil }
        let cutoff = Date().addingTimeInterval(-18 * 3600)   // 只看近 18h 活跃会话
        var recent: [(URL, Date)] = []
        for case let url as URL in en where url.pathExtension == "jsonl" {
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if mod >= cutoff { recent.append((url, mod)) }
        }
        recent.sort { $0.1 > $1.1 }

        var best: [String: Any]?
        var bestSecondary = -1.0
        var bestMtime = Date.distantPast
        for (url, mod) in recent.prefix(12) {                // 最多看 12 个最近文件
            guard let rl = lastRateLimits(in: url) else { continue }
            let sec = ((rl["secondary"] as? [String: Any])?["used_percent"] as? NSNumber)?.doubleValue ?? 0
            if sec > bestSecondary || (sec == bestSecondary && mod > bestMtime) {
                best = rl; bestSecondary = sec; bestMtime = mod
            }
        }
        return best
    }

    /// 从文件末尾向前找最后一条带 rate_limits 的事件。
    private func lastRateLimits(in file: URL) -> [String: Any]? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() {
            guard line.contains("rate_limits"),
                  let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let found = findRateLimits(in: obj) { return found }
        }
        return nil
    }

    /// 递归在任意嵌套结构里找 "rate_limits" 字典。
    private func findRateLimits(in any: Any) -> [String: Any]? {
        if let dict = any as? [String: Any] {
            if let rl = dict["rate_limits"] as? [String: Any] { return rl }
            for v in dict.values { if let r = findRateLimits(in: v) { return r } }
        } else if let arr = any as? [Any] {
            for v in arr { if let r = findRateLimits(in: v) { return r } }
        }
        return nil
    }
}
