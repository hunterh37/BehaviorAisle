import SwiftUI

/// Floating card above a shopper: persona, phase, top-3 predicted next actions with probability bars.
/// Rank 1 is large; ranks 2-3 are compact.
struct PredictionCard: View {
    @Environment(AppModel.self) private var model
    let shopper: ShopperAgent

    var body: some View {
        let c = Color(hex: shopper.persona.color)
        let ranked = shopper.predictions.sorted { $0.p > $1.p }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(c).frame(width: 12, height: 12).shadow(color: c, radius: 5)
                Text(shopper.persona.name).font(.title3.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 6)
                Chip(text: shopper.frozen ? "fork" : shopper.phase.label,
                     color: shopper.frozen ? Theme.amber : .secondary)
            }
            if let first = ranked.first {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(model.actionName(first)).font(.headline).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(first.p, format: .percent.precision(.fractionLength(0)))
                            .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                    }
                    PBar(p: first.p, color: c, height: 8)
                }
                .opacity(isTarget(first) ? 1 : 0.85)
            }
            ForEach(ranked.dropFirst().prefix(2)) { p in
                HStack(spacing: 10) {
                    Text(model.actionName(p)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 6)
                    PBar(p: p.p, color: c.opacity(0.7), height: 4).frame(width: 64)
                    Text(p.p, format: .percent.precision(.fractionLength(0)))
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                .opacity(isTarget(p) ? 1 : 0.75)
            }
            HStack {
                Label("\(shopper.cart.count)", systemImage: "cart.fill")
                Spacer()
                Text(shopper.source)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.tertiary)
            if model.showAnomaly, let a = shopper.anomaly, a >= 0.5 {
                Label("Unusual basket  \(Int(a * 100))%", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Theme.alert.gradient, in: .rect(cornerRadius: 12))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(18)
        .frame(width: 320)
        .glassBackgroundEffect(in: .rect(cornerRadius: Theme.corner))
        .overlay(alignment: .top) {
            Capsule().fill(c).frame(width: 60, height: 3).padding(.top, 1)
        }
        .animation(.smooth, value: shopper.anomaly)
    }

    private func isTarget(_ p: Prediction) -> Bool { shopper.target?.id == p.id }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
