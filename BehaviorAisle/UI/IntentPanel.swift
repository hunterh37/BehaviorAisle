import SwiftUI

/// Panel over an imported shopper: interests on top, then the predicted items each tied to the interest
/// that explains it, with probability and aisle.
struct IntentPanel: View {
    @Environment(AppModel.self) private var model
    let shopper: ShopperAgent

    var body: some View {
        let c = Color(hex: shopper.persona.color)
        let lines = IntentExplainer.explain(shopper.predictions, traits: shopper.traits, catalog: model.catalog)
        let next = shopper.target?.itemId ?? lines.first?.itemId
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle().fill(c).frame(width: 14, height: 14).shadow(color: c, radius: 6)
                Text(shopper.persona.name).font(.title2.weight(.bold)).lineLimit(1)
                Spacer(minLength: 8)
                Chip(text: shopper.phase.label, color: Theme.accent)
            }
            if let tags = shopper.traits?.interests, !tags.isEmpty {
                FlowTags(tags: Array(tags.prefix(5)), color: c)
            }
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                Text("Predicted next")
            }
            .font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
            ForEach(Array(lines.prefix(3).enumerated()), id: \.element.id) { i, l in
                IntentRow(line: l, rank: i, color: c, isNext: l.itemId == next)
            }
            if lines.isEmpty {
                HStack { ProgressView(); Text("Predicting").foregroundStyle(.secondary) }
            }
        }
        .padding(22)
        .frame(width: 440)
        .glassBackgroundEffect(in: .rect(cornerRadius: Theme.corner))
        .overlay(alignment: .top) { Capsule().fill(c).frame(width: 80, height: 4).padding(.top, 1) }
        .animation(.smooth, value: lines)
    }
}

private struct IntentRow: View {
    let line: IntentLine
    let rank: Int
    let color: Color
    let isNext: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(rank + 1)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(isNext ? .black : .secondary)
                    .frame(width: 26, height: 26)
                    .background(isNext ? color : .white.opacity(0.1), in: .circle)
                Text(line.name).font(rank == 0 ? .title3.weight(.semibold) : .headline).lineLimit(1)
                Spacer(minLength: 6)
                Text(line.p, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: rank == 0 ? 30 : 20, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
            }
            PBar(p: line.p, color: color.opacity(rank == 0 ? 1 : 0.6), height: rank == 0 ? 8 : 5)
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text(line.reason).lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: "mappin.and.ellipse")
                Text(line.place).lineLimit(1)
            }
            .font(.callout).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(isNext ? color.opacity(0.14) : .clear, in: .rect(cornerRadius: 14))
    }
}

/// Wrapping interest chips.
struct FlowTags: View {
    let tags: [String]
    let color: Color
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips(tags) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) { chips(Array(tags.prefix(3))) }
                HStack(spacing: 6) { chips(Array(tags.dropFirst(3))) }
            }
        }
    }

    private func chips(_ t: [String]) -> some View {
        ForEach(t, id: \.self) { tag in
            Text(tag)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(color.opacity(0.22), in: .capsule)
        }
    }
}

/// Floating tag over the predicted product on the shelf.
struct BeaconLabel: View {
    @Environment(AppModel.self) private var model
    let shopper: ShopperAgent

    var body: some View {
        let lines = IntentExplainer.explain(shopper.predictions, traits: shopper.traits, catalog: model.catalog)
        let next = shopper.target.flatMap { t in lines.first { $0.itemId == t.itemId } } ?? lines.first
        if let l = next {
            let c = Color(hex: shopper.persona.color)
            HStack(spacing: 10) {
                Text(l.p, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(c, in: .capsule)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(shopper.persona.name) next").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(l.name).font(.headline).lineLimit(1)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glassBackgroundEffect(in: .capsule)
        }
    }
}
