import AppKit
import SwiftUI

/// 管理贴合刘海的透明无边框面板。
@MainActor
final class NotchPanelController {
    private var panel: NSPanel?
    private let store: UsageStore
    private let actions: IslandActions

    init(store: UsageStore, actions: IslandActions) {
        self.store = store
        self.actions = actions
    }

    func show() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar                 // 浮于菜单栏内容之上
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true                   // 窗口按圆角 alpha 投阴影（避免材质方形阴影）
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let geo = NotchGeometry.current()
        let notchHeight = geo?.notchRect.height ?? 32
        let notchWidth = geo?.notchRect.width ?? 180
        let hosting = NSHostingView(
            rootView: IslandRootView(store: store, notchHeight: notchHeight,
                                     notchWidth: notchWidth, actions: actions)
        )
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        panel.contentView = hosting

        self.panel = panel
        reposition()
        panel.orderFrontRegardless()
    }

    /// 按当前刘海几何重新定位（屏幕变化时调用）。
    /// 面板按展开态外形预留尺寸，水平居中于刘海中心、顶沿贴屏顶；
    /// 折叠/展开的形变在 SwiftUI 内部完成，窗口本身不缩放。
    func reposition() {
        guard let panel, let geo = NotchGeometry.current() else { return }
        let w = IslandRootView.expandedWidth
        let h = IslandRootView.expandedHeight
        let frame = CGRect(
            x: geo.notchRect.midX - w / 2,
            y: geo.screen.frame.maxY - h,
            width: w,
            height: h
        )
        panel.setFrame(frame, display: true)
    }
}
