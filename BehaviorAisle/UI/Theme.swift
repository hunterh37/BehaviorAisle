import SwiftUI

enum Theme {
    static let accent = Color(hex: 0x5EE6A8)
    static let amber = Color(hex: 0xFFC857)
    static let alert = Color(hex: 0xFF5D5D)
    static let corner: CGFloat = 22
}

/// Small capsule label, e.g. phase or source.
struct Chip: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.16), in: .capsule)
    }
}

/// Probability bar in a persona color.
struct PBar: View {
    let p: Double
    let color: Color
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.55), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, g.size.width * CGFloat(min(1, max(0, p)))))
            }
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.45), value: p)
    }
}

extension ShopperAgent.Phase {
    var label: String {
        switch self {
        case .thinking: "predicting"
        case .walking: "walking"
        case .picking: "at shelf"
        case .checkingOut: "checkout"
        case .done: "done"
        }
    }
}
