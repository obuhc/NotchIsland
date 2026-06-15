import SwiftUI
import NotchUsageKit

/// 右键菜单触发的动作（由 AppDelegate 提供实现）。
struct IslandActions {
    var refresh: () -> Void
    var openSettings: () -> Void
    var quit: () -> Void
}

/// 灵动岛根视图：折叠态（贴刘海左右两翼的 5h 小环）↔ 展开态（毛玻璃行式列表）
/// 之间用尺寸形变 + 透明度过渡。悬停/点击展开，右键弹出菜单。真实数据来自 UsageStore。
struct IslandRootView: View {
    let store: UsageStore
    let notchHeight: CGFloat
    let notchWidth: CGFloat
    let actions: IslandActions

    /// 折叠态：刘海每侧机翼宽度。
    static let wing: CGFloat = 96
    /// 展开态外形尺寸（面板按此预留）。
    static let expandedWidth: CGFloat = 384
    static let expandedHeight: CGFloat = 190

    @State private var expanded = false
    @State private var breathe = false

    /// 折叠态宽度 = 刘海宽 + 两侧机翼，停留在菜单栏高度内。
    private var collapsedWidth: CGFloat { notchWidth + Self.wing * 2 }
    private var collapsedHeight: CGFloat { notchHeight + 4 }   // 三段内容缩小后基本塞在菜单栏内，仅微露

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear.allowsHitTesting(false)          // 透明区不挡鼠标
            island
                .onHover { hovering in
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                        expanded = hovering
                    }
                    if hovering && !store.isPaused { store.refresh(force: true) }   // 一看就拉新的
                }
                .onTapGesture {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                        expanded.toggle()
                    }
                    if expanded && !store.isPaused { store.refresh(force: true) }
                }
                .contextMenu {
                    Button(store.isPaused ? "继续刷新" : "暂停刷新") { store.togglePause() }
                    Button("立即刷新") { actions.refresh() }
                    Button("设置…") { actions.openSettings() }
                    Divider()
                    Button("退出 NotchIsland") { actions.quit() }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    private var island: some View {
        ZStack(alignment: .top) {
            if expanded {
                glassBackground.transition(.opacity)
                expandedContent.transition(.opacity)
            } else {
                collapsedContent.transition(.opacity)
            }
        }
        .frame(
            width: expanded ? Self.expandedWidth : collapsedWidth,
            height: expanded ? Self.expandedHeight : collapsedHeight
        )
    }

    /// 展开态的毛玻璃黑底（折叠态不画背景，机翼直接浮在菜单栏上）。
    private var glassBackground: some View {
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28)
        // 不在此处加 .shadow（材质背衬是矩形，会投出方形阴影）。
        // 阴影交给 NSPanel.hasShadow 由窗口服务器按圆角 alpha 投出。
        return shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(.black.opacity(0.42)))
            .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
    }

    // MARK: - 折叠态（贴刘海左右两翼，停在菜单栏高度内）

    private var collapsedContent: some View {
        HStack(spacing: 0) {
            wing(store.codex, "Codex")                   // 左 = Codex
                .frame(maxWidth: .infinity, alignment: .trailing)
            Color.clear.frame(width: notchWidth)         // 物理刘海缺口
            wing(store.claude, "Claude")                 // 右 = Claude
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: collapsedHeight)
        .offset(y: 2)                                             // 整体微微下移
        .opacity(store.isPaused ? 0.4 : (breathe ? 1.0 : 0.9))   // 只用淡入淡出呼吸，不缩放（避免两翼左右摇摆）
    }

    /// 折叠态机翼：环在菜单栏内（垂直居中），名称 + 5h 重置倒计时在刘海下方紧凑竖排。
    private func wing(_ snapshot: UsageSnapshot?, _ name: String) -> some View {
        VStack(spacing: 0) {
            ProgressRing(usedPercent: snapshot?.fiveHour?.usedPercent, diameter: 14, lineWidth: 2.2)
            Text(name)
                .font(.system(size: 6.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize()
            if let reset = snapshot?.fiveHour?.resetCountdown {
                Text("↻ \(reset)")
                    .font(.system(size: 6, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
                    .fixedSize()
            }
        }
        .padding(.horizontal, 6)
        .opacity(snapshot?.rateLimitedUntil != nil ? 0.5 : 1)   // 限流时淡化
    }

    // MARK: - 展开态

    private var expandedContent: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)       // 刘海遮挡区
            VStack(alignment: .leading, spacing: 12) {
                providerSection(provider: "Codex", snapshot: store.codex)
                providerSection(provider: "Claude", snapshot: store.claude)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func providerSection(provider: String, snapshot: UsageSnapshot?) -> some View {
        let limitedUntil = snapshot?.rateLimitedUntil
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(provider)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if let src = snapshot?.source {
                    Text(src == .official ? "官方" : "估算")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Capsule().fill(.white.opacity(0.10)))
                }
                Spacer(minLength: 0)
            }

            if let until = limitedUntil {
                Text("⏳ 接口限流中 · 约 \(Self.hm(until)) 恢复")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color(red: 1.0, green: 0.76, blue: 0.30))
            }

            if let windows = snapshot?.windows, !windows.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(windows, id: \.label) { usageRow($0) }
                }
                .opacity(limitedUntil != nil ? 0.4 : 1)   // 限流时下方为上次数据，淡化
            } else {
                Text(snapshot?.error ?? "无数据")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    @ViewBuilder
    private func usageRow(_ w: UsageWindow) -> some View {
        HStack(spacing: 10) {
            Text(w.label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 20, alignment: .leading)

            if let pct = w.usedPercent {
                UsageBar(usedPercent: pct)
                Text("\(Int(pct.rounded()))%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 34, alignment: .trailing)
            } else {
                // 无官方百分比（ccusage 估算）：直接展示 token 估算，不留空条。
                Text(w.detail ?? "无官方数据")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Text(resetValue(w))
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 88, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// 5h 等短窗口用倒计时；周窗口显示具体重置日期时间（几月几号几点）。
    private func resetValue(_ w: UsageWindow) -> String {
        let isLong = (w.windowMinutes ?? 0) >= 1440 || w.label == "周"
        if isLong, let r = w.resetsAt {
            return Self.absoluteFormatter.string(from: r)
        }
        if let c = w.resetCountdown { return "重置 \(c)" }
        return "—"
    }

    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()

    private static func hm(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
}
