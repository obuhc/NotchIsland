import Foundation
import Observation
import NotchUsageKit

/// 轮询两个 Provider，把快照发布给 UI。
@MainActor
@Observable
final class UsageStore {
    var codex: UsageSnapshot?
    var claude: UsageSnapshot?
    var lastRefresh: Date?
    /// 暂停：停掉后台轮询，不再自动调端点（不在用软件时省心）。
    var isPaused = false
    /// 是否已授权 Claude 官方用量（来自设置）。
    var claudeOfficialEnabled = false

    private var timer: Timer?
    private var interval: TimeInterval = 10
    /// 上次「强制实时拉 Claude」的时刻，用于给查看触发的刷新限频。
    private var lastForced: Date?
    private let forcedFloor: TimeInterval = 300   // 省心档：查看时实时拉限频 5 分钟

    func start(interval: TimeInterval = 10) {
        self.interval = interval
        guard !isPaused else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func restart(interval: TimeInterval) {
        timer?.invalidate()
        start(interval: interval)
    }

    /// 暂停 / 继续后台轮询。
    func togglePause() {
        isPaused.toggle()
        if isPaused {
            timer?.invalidate()
            timer = nil
        } else {
            start(interval: interval)
        }
    }

    /// force=true：用户查看时触发，实时拉 Claude（限频 forcedFloor 秒，避免反复悬停狂打端点）。
    func refresh(force: Bool = false) {
        let claudeForce = force && (lastForced == nil || Date().timeIntervalSince(lastForced!) > forcedFloor)
        if claudeForce { lastForced = Date() }
        let officialEnabled = claudeOfficialEnabled
        Task.detached(priority: .utility) {
            let codex = CodexProvider().snapshot()
            let claude = ClaudeProvider(officialEnabled: officialEnabled, forceFresh: claudeForce).snapshot()
            await MainActor.run {
                self.codex = codex
                self.claude = claude
                self.lastRefresh = Date()
            }
        }
    }
}

extension UsageSnapshot {
    /// 折叠态展示用：优先 5h 窗口（即时额度），没有则退第一个。
    var fiveHour: UsageWindow? {
        windows.first { $0.label == "5h" } ?? windows.first
    }
}
