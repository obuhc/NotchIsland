import SwiftUI

/// 行式布局用的水平用量条：轨道 + 按「已用%」填充并按阈值变色。
struct UsageBar: View {
    let usedPercent: Double?
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(Threshold.color(usedPercent))
                    .frame(width: geo.size.width * CGFloat(min(max((usedPercent ?? 0) / 100, 0), 1)))
                    .animation(.easeInOut(duration: 0.6), value: usedPercent)
            }
        }
        .frame(height: height)
    }
}
