import AppKit

/// 计算刘海几何。坐标系为 AppKit 全局坐标（左下原点）。
struct NotchGeometry {
    let screen: NSScreen
    /// 物理刘海矩形（全局坐标，左下原点）。无刘海屏时为顶部中央的模拟区域。
    let notchRect: CGRect
    let hasNotch: Bool

    static func current() -> NotchGeometry? {
        let screens = NSScreen.screens
        // 优先带刘海的屏（safeAreaInsets.top > 0），否则主屏。
        let target = screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
        guard let screen = target else { return nil }

        let frame = screen.frame
        let topInset = screen.safeAreaInsets.top
        let hasNotch = topInset > 0

        let leftW = screen.auxiliaryTopLeftArea?.width ?? 0
        let rightW = screen.auxiliaryTopRightArea?.width ?? 0

        let notchHeight: CGFloat = hasNotch ? topInset : 32   // 无刘海屏用经典菜单栏高度
        let notchWidth: CGFloat
        if hasNotch, leftW > 0 || rightW > 0 {
            notchWidth = frame.width - leftW - rightW
        } else {
            notchWidth = 220   // 无刘海屏：模拟一个居中岛宽
        }

        let originX = hasNotch ? frame.minX + leftW : frame.midX - notchWidth / 2
        let originY = frame.maxY - notchHeight
        let rect = CGRect(x: originX, y: originY, width: notchWidth, height: notchHeight)

        return NotchGeometry(screen: screen, notchRect: rect, hasNotch: hasNotch)
    }
}
