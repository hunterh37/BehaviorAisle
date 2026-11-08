import SwiftUI

/// Floating card above a shopper: persona, phase, top-3 predicted next actions with probability bars.
struct PredictionCard: View {
    @Environment(AppModel.self) private var model
    let shopper: ShopperAgent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(Color(hex: shopper.persona.color)).frame(width: 12, height: 12)
                Text(shopper.persona.name).font(.headline)
                Spacer()
                Text(phase).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            ForEach(shopper.predictions) { p in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(name(p)).font(.callout).lineLimit(1)
                        Spacer()
                        Text(p.p, format: .percent.precision(.fractionLength(0))).font(.callout.monospacedDigit())
                    }
                    GeometryReader { g in
                        Capsule().fill(Color(hex: shopper.persona.color).opacity(0.85))
                            .frame(width: g.size.width * CGFloat(p.p))
                    }
                    .frame(height: 5)
                }
                .opacity(shopper.target?.id == p.id ? 1 : 0.7)
            }
            HStack {
                Label("\(shopper.cart.count)", systemImage: "cart")
                Spacer()
                Text(shopper.source).foregroundStyle(.secondary)
            }
            .font(.caption)
            if model.showAnomaly, let a = shopper.anomaly, a >= 0.5 {
                Label("Unusual basket \(Int(a * 100))%", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.bold()).foregroundStyle(.white)
                    .padding(6).background(.red, in: .rect(cornerRadius: 8))
            }
        }
        .padding(14)
        .frame(width: 300)
        .glassBackgroundEffect()
    }

    private var phase: String {
        if shopper.frozen { return "FORK" }
        switch shopper.phase {
        case .thinking: return "predicting"
        case .walking: return "walking"
        case .picking: return "at shelf"
        case .checkingOut: return "checkout"
        case .done: return "done"
        }
    }

    private func name(_ p: Prediction) -> String {
        if p.itemId == Prediction.checkoutId { return "Check out" }
        let n = model.product(p.itemId)?.name ?? p.itemId
        return p.action == .addToCart ? "Buy \(n)" : "Look at \(n)"
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
