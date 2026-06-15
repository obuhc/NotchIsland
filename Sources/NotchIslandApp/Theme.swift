import SwiftUI

/// 用量阈值配色（用「已用百分比」判断）。
enum Threshold {
    static func color(_ usedPercent: Double?) -> Color {
        guard let p = usedPercent else { return Color.white.opacity(0.35) }
        switch p {
        case ..<60:  return Color(red: 0.36, green: 0.85, blue: 0.60)   // 薄荷绿：充裕
        case ..<85:  return Color(red: 1.00, green: 0.76, blue: 0.30)   // 琥珀：偏紧
        default:     return Color(red: 1.00, green: 0.42, blue: 0.42)   // 红：吃紧
        }
    }
}
