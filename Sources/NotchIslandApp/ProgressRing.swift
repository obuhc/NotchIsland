import SwiftUI

/// 折叠态的迷你进度环：环按「已用%」填充并按阈值变色，中心直接显示百分比数字。
struct ProgressRing: View {
    let usedPercent: Double?
    var diameter: CGFloat = 20
    var lineWidth: CGFloat = 2.6

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max((usedPercent ?? 0) / 100, 0), 1)))
                .stroke(
                    Threshold.color(usedPercent),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: usedPercent)
            Text(usedPercent.map { "\(Int($0.rounded()))" } ?? "–")
                .font(.system(size: diameter * 0.40, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(usedPercent == nil ? 0.45 : 0.96))
                .minimumScaleFactor(0.6)
                .fixedSize()
        }
        .frame(width: diameter, height: diameter)
    }
}
