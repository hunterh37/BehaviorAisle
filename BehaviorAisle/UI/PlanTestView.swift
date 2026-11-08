import SwiftUI

/// Whole-plan test: opening layout vs current plan, revenue and units per 100 shoppers with paired 95% CIs.
struct PlanTestSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let changes = model.planChanges
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(changes == 0 ? "Opening layout" : "\(changes) SKU\(changes == 1 ? "" : "s") changed")
                    .font(.callout).foregroundStyle(changes == 0 ? .secondary : .primary)
                Spacer()
                Button("Reset", systemImage: "arrow.uturn.backward") { model.resetPlan() }
                    .disabled(changes == 0)
                Button("Test plan", systemImage: "flask") { model.runPlanTest() }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    .disabled(changes == 0 || model.planBusy)
            }
            if model.planBusy {
                HStack { ProgressView(); Text("Simulating 2,000 paired shoppers").foregroundStyle(.secondary) }.font(.callout)
            } else if let r = model.planResult {
                PlanResult(result: r)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.05), in: .rect(cornerRadius: 18))
    }
}

private struct PlanResult: View {
    @Environment(AppModel.self) private var model
    let result: Experiment.WhatIf

    var body: some View {
        let r = result
        let net = r.revenueDelta
        let sig = abs(net) > r.revenueCI
        VStack(alignment: .leading, spacing: 10) {
            VerdictCard(result: r, title: "Plan")
            HStack(spacing: 12) {
                tile(String(format: "%+.0f", net), "Revenue $ / 100", sig ? (net > 0 ? Theme.accent : Theme.alert) : .secondary,
                     String(format: "± %.0f", r.revenueCI))
                tile(String(format: "%+.2f", r.basketVariant - r.basketBase), "Items / basket", .white,
                     String(format: "%.2f → %.2f", r.basketBase, r.basketVariant))
                tile(r.promoROI.map { String(format: "%.1f×", $0) } ?? "–", "Promo ROI", Theme.amber,
                     String(format: "$%.0f discount / 100", r.promoCost))
            }
            ForEach(r.effects.filter { abs($0.delta) > $0.ci }.prefix(5), id: \.itemId) { e in
                HStack {
                    Text(model.product(e.itemId)?.name ?? e.itemId).lineLimit(1)
                    Spacer()
                    Text(String(format: "%.1f → %.1f", e.base, e.variant)).foregroundStyle(.secondary).monospacedDigit()
                    Text(String(format: "%+.1f ± %.1f", e.delta, e.ci)).monospacedDigit()
                        .foregroundStyle(e.delta > 0 ? Theme.accent : Theme.amber)
                        .frame(width: 110, alignment: .trailing)
                }
                .font(.callout)
            }
        }
    }

    private func tile(_ value: String, _ label: String, _ color: Color, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption)
            Text(detail).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 14))
    }
}

/// Held-out next-item accuracy on real Instacart baskets (Resources/validation.json from tools/validate_instacart.py).
struct Validation: Codable, Sendable {
    struct Score: Codable, Sendable, Hashable { var name: String; var hit1: Double; var hit3: Double; var mrr: Double; var n: Int }
    struct Delta: Codable, Sendable { var delta: Double; var lo: Double; var hi: Double }
    var dataset: String
    var baskets: Int
    var test_prefixes: Int
    var scores: [Score]
    var behaviorgpt_minus_heuristic_hit3: Delta?
    var fitted_minus_heuristic_hit3: Delta?

    static let bundled: Validation? = Bundle.main.url(forResource: "validation", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode(Validation.self, from: $0) }
}

struct ValidationSection: View {
    var body: some View {
        if let v = Validation.bundled {
            let top = v.scores.map(\.hit3).max() ?? 1
            VStack(alignment: .leading, spacing: 10) {
                Text("Next item in \(v.test_prefixes) held-out Instacart baskets. Hit@3.")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(v.scores, id: \.name) { s in
                    HStack(spacing: 10) {
                        Text(s.name).font(.callout).frame(width: 140, alignment: .leading)
                        PBar(p: s.hit3 / max(top, 0.01), color: color(s.name), height: 10)
                            .frame(height: 10)
                        Text(String(format: "%.1f%%", s.hit3 * 100)).font(.callout.monospacedDigit())
                            .frame(width: 60, alignment: .trailing)
                    }
                }
                if let d = v.behaviorgpt_minus_heuristic_hit3 {
                    Text(String(format: "BehaviorGPT − heuristic: %+.1f pts (95%% CI %+.1f to %+.1f)", d.delta * 100, d.lo * 100, d.hi * 100))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if let d = v.fitted_minus_heuristic_hit3 {
                    Text(String(format: "Fitted − hand-set heuristic: %+.1f pts (95%% CI %+.1f to %+.1f)", d.delta * 100, d.lo * 100, d.hi * 100))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text("\(v.baskets.formatted()) baskets mapped to 32 SKUs. Shelf, sale and distance terms have no real data yet.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.05), in: .rect(cornerRadius: 18))
        }
    }

    private func color(_ name: String) -> Color {
        switch name {
        case "BehaviorGPT": Color(hex: 0x8AB4FF)
        case "Fitted heuristic": Theme.accent
        case "Heuristic": Theme.amber
        default: .white.opacity(0.5)
        }
    }
}

/// One-line answer a buyer reads: gross margin change per store per week with its 95% CI, and the chain total.
struct VerdictCard: View {
    let result: Experiment.WhatIf
    let title: String

    var body: some View {
        let r = result
        let w = r.marginPerStoreWeek
        let color: Color = !r.significant ? .white : (w > 0 ? Theme.accent : Color(hex: 0xFF8C8C))
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text(r.significant ? (w > 0 ? "Ship it" : "Do not ship") : "No clear effect")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(r.significant ? Color.black : .secondary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(r.significant ? color : .white.opacity(0.08), in: .capsule)
            }
            Text(String(format: "%@$%@ margin / store / week", w >= 0 ? "+" : "−", abs(w).formatted(.number.precision(.fractionLength(0)))))
                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
            Text(String(format: "± $%.0f (95%% CI) · %@ across %d stores / year", r.marginCIPerStoreWeek,
                        Self.money(r.marginChainYear), Int(Experiment.WhatIf.chainStores)))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.18), in: .rect(cornerRadius: 16))
    }

    static func money(_ x: Double) -> String {
        let a = abs(x), sign = x < 0 ? "−" : "+"
        if a >= 1_000_000 { return String(format: "%@$%.1fM", sign, a / 1_000_000) }
        if a >= 1_000 { return String(format: "%@$%.0fK", sign, a / 1_000) }
        return String(format: "%@$%.0f", sign, a)
    }
}
