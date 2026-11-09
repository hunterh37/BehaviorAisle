import SwiftUI

/// BehaviorGPT live console: each network call as request, response, shopper update.
struct APIConsoleView: View {
    static let windowId = "behaviorgpt"
    @Environment(AppModel.self) private var model
    @State private var trace = APITrace.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            stats
            if let c = trace.featured {
                pipeline(c)
            } else {
                Text("Open the store to start shoppers")
                    .font(.title2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            feed
        }
        .padding(32)
        .frame(minWidth: 980, minHeight: 1000)
        .glassBackgroundEffect()
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 16) {
            Pulse(active: trace.inFlight > 0)
            Text("BehaviorGPT").font(.system(size: 44, weight: .bold))
            Spacer()
            Picker("Source", selection: Binding(get: { model.mode }, set: { model.mode = $0 })) {
                ForEach(PredictorMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 420)
        }
    }

    private var stats: some View {
        HStack(spacing: 14) {
            Stat(value: "\(trace.total)", label: "calls")
            Stat(value: "\(trace.live)", label: "live replies", color: Theme.accent)
            Stat(value: trace.avgLatency.map { "\($0) ms" } ?? "–", label: "avg latency")
            Stat(value: "\(trace.inFlight)", label: "in flight", color: Theme.amber)
            Stat(value: "\(trace.failed)", label: "failed", color: trace.failed > 0 ? Theme.alert : .secondary)
        }
    }

    // MARK: Pipeline

    private func pipeline(_ c: APITrace.Call) -> some View {
        let shopper = model.shoppers.first { $0.persona.id == c.personaId }
        let tint = shopper.map { Color(hex: $0.persona.color) } ?? Theme.accent
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Circle().fill(tint).frame(width: 18, height: 18)
                Text(shopper?.persona.name ?? c.personaId).font(.system(size: 30, weight: .semibold))
                SourceTag(source: c.source, stage: c.stage)
                Spacer()
                Toggle("Raw JSON", isOn: $trace.showRaw).toggleStyle(.button).font(.title3)
            }
            HStack(alignment: .top, spacing: 16) {
                StageCard(n: 1, title: "Request", on: true, tint: tint) { request(c) }
                StageCard(n: 2, title: "Response", on: c.stage >= .received, tint: tint) { response(c) }
                StageCard(n: 3, title: "Shopper update", on: c.stage == .applied, tint: tint) { update(c, shopper) }
            }
            .frame(maxHeight: 470)
            .animation(.smooth(duration: 0.35), value: c.stage)
        }
    }

    @ViewBuilder private func request(_ c: APITrace.Call) -> some View {
        Text(c.endpoint.isEmpty ? (c.source == "replay" ? "Recorded BehaviorGPT reply" : "Local model") : c.endpoint)
            .font(.system(size: 17, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
        if trace.showRaw, !c.requestJSON.isEmpty {
            JSONBlock(text: c.requestJSON)
        } else {
            Text("History sent · \(c.historyCount) events").font(.title3.weight(.semibold))
            ForEach(Array(c.sentEvents.suffix(7).enumerated()), id: \.offset) { _, e in
                Text(e).font(.system(size: 21)).lineLimit(1)
            }
        }
    }

    @ViewBuilder private func response(_ c: APITrace.Call) -> some View {
        HStack {
            if let s = c.httpStatus {
                Text("HTTP \(s)").font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle((200..<300).contains(s) ? Theme.accent : Theme.alert)
            }
            if let ms = c.latencyMs { Text("\(ms) ms").font(.system(size: 22, weight: .bold, design: .monospaced)) }
        }
        if trace.showRaw, !c.responseJSON.isEmpty {
            JSONBlock(text: c.responseJSON)
        } else if !c.ranked.isEmpty {
            Text("Ranked by BehaviorGPT").font(.title3.weight(.semibold))
            ForEach(Array(c.ranked.prefix(6).enumerated()), id: \.offset) { i, id in
                HStack(spacing: 10) {
                    Text("\(i + 1)").font(.system(size: 20, weight: .bold, design: .rounded))
                        .frame(width: 30, height: 30).background(.white.opacity(0.12), in: .circle)
                    Text(trace.name(id)).font(.system(size: 21)).lineLimit(1)
                }
            }
        } else if let e = c.error {
            Text(e).font(.system(size: 17, design: .monospaced)).foregroundStyle(Theme.alert)
        } else if c.stage == .sending {
            ProgressView().controlSize(.large)
        }
    }

    @ViewBuilder private func update(_ c: APITrace.Call, _ s: ShopperAgent?) -> some View {
        Text("Next action").font(.title3.weight(.semibold))
        ForEach(c.predictions) { p in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(trace.name(p.itemId)).font(.system(size: 21, weight: p.id == c.choice?.id ? .bold : .regular))
                    Spacer()
                    Text("\(Int((p.p * 100).rounded()))%").font(.system(size: 21, weight: .bold, design: .rounded))
                }
                PBar(p: p.p, color: p.id == c.choice?.id ? Theme.accent : .white.opacity(0.6), height: 10)
            }
        }
        if let ch = c.choice {
            Divider()
            Text(ch.action == .checkout ? "→ walks to checkout" : "→ \(ch.action == .addToCart ? "adds" : "looks at") \(trace.name(ch.itemId))")
                .font(.system(size: 23, weight: .bold)).foregroundStyle(Theme.accent)
            Text("history \(c.historyCount) → \(c.historyCount + 1) · cart \(c.cartAfter)")
                .font(.system(size: 18, design: .monospaced)).foregroundStyle(.secondary)
        }
    }

    // MARK: Feed

    private var feed: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent calls").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(trace.calls.prefix(6)) { c in
                Button { trace.focusedPersona = trace.focusedPersona == c.personaId ? nil : c.personaId } label: {
                    HStack(spacing: 14) {
                        Text(c.started, format: .dateTime.hour().minute().second())
                            .font(.system(size: 17, design: .monospaced)).foregroundStyle(.secondary)
                        Text(model.shoppers.first { $0.persona.id == c.personaId }?.persona.name ?? c.personaId)
                            .font(.system(size: 19, weight: .semibold)).frame(width: 220, alignment: .leading)
                        Text(c.predictions.first.map { trace.name($0.itemId) } ?? "…").font(.system(size: 19)).lineLimit(1)
                        Spacer()
                        Text(c.latencyMs.map { "\($0) ms" } ?? "…").font(.system(size: 17, design: .monospaced))
                        SourceTag(source: c.source, stage: c.stage)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct Pulse: View {
    let active: Bool
    @State private var on = false
    var body: some View {
        Circle().fill(active ? Theme.accent : .white.opacity(0.3))
            .frame(width: 22, height: 22)
            .overlay(Circle().stroke(Theme.accent, lineWidth: 3).scaleEffect(on ? 2.2 : 1).opacity(on || !active ? 0 : 0.9))
            .onAppear { withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) { on = true } }
    }
}

private struct Stat: View {
    let value: String
    let label: String
    var color: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(color)
                .contentTransition(.numericText())
            Text(label).font(.system(size: 16)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 18))
    }
}

private struct SourceTag: View {
    let source: String
    let stage: APITrace.Stage
    var body: some View {
        let (text, color): (String, Color) = switch (stage, source) {
        case (.sending, _): ("sending", Theme.amber)
        case (_, "behaviorgpt"): ("BehaviorGPT live", Theme.accent)
        case (_, "replay"): ("BehaviorGPT replay", Theme.amber)
        default: (source.isEmpty ? "–" : source, .secondary)
        }
        Text(text).font(.system(size: 16, weight: .bold)).textCase(.uppercase)
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(color.opacity(0.16), in: .capsule)
    }
}

private struct StageCard<Content: View>: View {
    let n: Int
    let title: String
    let on: Bool
    let tint: Color
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(n)").font(.system(size: 20, weight: .heavy, design: .rounded))
                    .frame(width: 34, height: 34).background(on ? tint : .white.opacity(0.15), in: .circle)
                Text(title).font(.system(size: 26, weight: .bold))
            }
            content
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(on ? 0.09 : 0.03), in: .rect(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(on ? tint.opacity(0.7) : .clear, lineWidth: 2))
        .opacity(on ? 1 : 0.45)
    }
}

private struct JSONBlock: View {
    let text: String
    var body: some View {
        ScrollView {
            Text(text).font(.system(size: 14, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
