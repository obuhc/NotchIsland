import ServiceManagement

/// 用 SMAppService 管理"开机自动启动"。需 App 为正常 bundle（建议装到 /Applications）。
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ on: Bool) -> Bool {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("[NotchIsland] LoginItem 设置失败: \(error.localizedDescription)")
            return false
        }
    }
}
