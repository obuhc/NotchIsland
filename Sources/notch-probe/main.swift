import Foundation
import NotchUsageKit

// P0 验证：把两边真实用量打印出来，确认数据层稳定。

func bar(_ pct: Double?) -> String {
    guard let pct else { return "·········· (官方%不可得)" }
    let filled = Int((pct / 100 * 10).rounded())
    return String(repeating: "█", count: filled) + String(repeating: "░", count: 10 - filled)
        + String(format: " %5.1f%%", pct)
}

func render(_ s: UsageSnapshot) {
    let tag = s.source == .official ? "官方" : "估算"
    print("\n  \(s.provider)  [\(tag)]")
    if let err = s.error { print("    ⚠️  \(err)"); return }
    for w in s.windows {
        let reset = w.resetCountdown.map { "重置 \($0) 后" } ?? "重置时间未知"
        let extra = w.detail.map { " · \($0)" } ?? ""
        print("    \(w.label.padding(toLength: 3, withPad: " ", startingAt: 0))  \(bar(w.usedPercent))  \(reset)\(extra)")
    }
}

print("═══════════════  NotchIsland · 用量探针  ═══════════════")
render(CodexProvider().snapshot())
render(ClaudeProvider(officialEnabled: true).snapshot())
print("\n────────────────────────────────────────────────────────")
print("采样时间：\(Date().formatted(date: .omitted, time: .standard))")
