import Foundation

/// 数据来源：官方精确限额，还是本地 token 估算。
public enum UsageSource: String, Sendable {
    case official   // Codex rate_limits / Claude 官方接口
    case estimate   // ccusage token 聚合
}

/// 一个限流窗口（5 小时滚动 / 每周）。
public struct UsageWindow: Sendable, Equatable {
    public let label: String        // "5h" / "周"
    public let usedPercent: Double?  // 0–100，nil 表示官方百分比不可得
    public let resetsAt: Date?       // 该窗口重置时间
    public let windowMinutes: Int?   // 窗口长度（分钟）
    public let detail: String?       // 补充文案，如 "355K tokens"

    public init(label: String, usedPercent: Double?, resetsAt: Date?,
                windowMinutes: Int? = nil, detail: String? = nil) {
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowMinutes = windowMinutes
        self.detail = detail
    }

    /// 若窗口已过重置时刻（数据是上次会话的过期快照），视为已滚动重置：
    /// 用量归 0，重置时间 = 当前时间 + 窗口长度（与 Codex 空闲时的显示一致）。
    public func rolledOver(now: Date = Date()) -> UsageWindow {
        guard let reset = resetsAt, let mins = windowMinutes, mins > 0, reset < now else { return self }
        let next = now.addingTimeInterval(TimeInterval(mins * 60))
        return UsageWindow(label: label, usedPercent: 0, resetsAt: next,
                           windowMinutes: mins, detail: nil)
    }

    /// 距离重置的可读倒计时，如 "2h 13m"。
    public var resetCountdown: String? {
        guard let resetsAt else { return nil }
        let secs = max(0, Int(resetsAt.timeIntervalSinceNow))
        let h = secs / 3600, m = (secs % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "<1m"
    }
}

/// 单个 Provider（Codex / Claude）的一次用量快照。
public struct UsageSnapshot: Sendable, Equatable {
    public let provider: String
    public let source: UsageSource
    public let windows: [UsageWindow]
    public let capturedAt: Date
    public let error: String?
    /// 非 nil 表示官方接口正被限流（429），到该时刻前不可刷新；下方窗口为上次数据。
    public let rateLimitedUntil: Date?

    public init(provider: String, source: UsageSource, windows: [UsageWindow],
                capturedAt: Date = Date(), error: String? = nil,
                rateLimitedUntil: Date? = nil) {
        self.provider = provider
        self.source = source
        self.windows = windows
        self.capturedAt = capturedAt
        self.error = error
        self.rateLimitedUntil = rateLimitedUntil
    }

    public var isOK: Bool { error == nil && !windows.isEmpty }

    /// 标注为限流中（保留窗口数据，附带恢复时间）。
    public func markedRateLimited(until: Date) -> UsageSnapshot {
        UsageSnapshot(provider: provider, source: source, windows: windows,
                      capturedAt: capturedAt, error: error, rateLimitedUntil: until)
    }
}
