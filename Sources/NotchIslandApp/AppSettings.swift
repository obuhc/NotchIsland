import Foundation
import Observation

/// 用户设置，持久化到 UserDefaults。
@MainActor
@Observable
final class AppSettings {
    /// 轮询间隔（秒）。
    var refreshInterval: Double {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: Keys.refreshInterval)
            onIntervalChange?(refreshInterval)
        }
    }

    /// 开机自动启动。
    var launchAtLogin: Bool {
        didSet { LoginItem.setEnabled(launchAtLogin) }
    }

    /// 用户是否授权 Claude 官方用量（读本地 token + 调 Anthropic 端点）。默认关闭。
    var claudeOfficialEnabled: Bool {
        didSet {
            UserDefaults.standard.set(claudeOfficialEnabled, forKey: Keys.claudeOfficial)
            onClaudeOfficialChange?(claudeOfficialEnabled)
        }
    }

    /// 间隔变化回调（用于重启轮询）。
    var onIntervalChange: ((Double) -> Void)?
    /// 官方授权变化回调（用于立即生效 + 刷新）。
    var onClaudeOfficialChange: ((Bool) -> Void)?

    init() {
        let stored = UserDefaults.standard.double(forKey: Keys.refreshInterval)
        refreshInterval = stored > 0 ? stored : 10
        launchAtLogin = LoginItem.isEnabled
        claudeOfficialEnabled = UserDefaults.standard.bool(forKey: Keys.claudeOfficial)   // 默认 false
    }

    private enum Keys {
        static let refreshInterval = "refreshInterval"
        static let claudeOfficial = "claudeOfficialEnabled"
    }
}
