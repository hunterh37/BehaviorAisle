import SwiftUI

/// Main-window card that shows the latest BehaviorGPT call as three steps:
/// what the shopper did -> what BehaviorGPT ranked next -> what the shopper does now.
struct BehaviorGPTFlowCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    private var trace: APITrace { .shared }

    var body: some View {
        let call = trace.featured
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("BehaviorGPT").font(.title3.weight(.semibold))
                if let call { Text(personaName(call.personaId)).font(.callout).foregroundStyle(.secondary) }
                Spacer()
                if let call, !call.source.isEmpty { Chip(text: call.source, color: call.source == "behaviorgpt" ? Theme.accent : Theme.amber) }
                Button("Console", systemImage: "terminal") { openWindow(id: APIConsoleView.windowId) }
                    .labelStyle(.iconOnly).buttonBorderShape(.circle)
            }
            if let call {
                HStack(alignment: .top, spacing: 10) {
                    step("1  Did", items: Array(call.sentEvents.suffix(4)), empty: "No history yet")
                    arrow
                    step("2  BehaviorGPT ranks", items: ranked(call), empty: "Waiting")
                    arrow
                    step("3  Does", items: call.choice.map { [model.actionName($0) + String(format: "  %.0f%%", $0.p * 100)] } ?? [],
                         empty: "Deciding", highlight: true)
                }
                Text(footer(call)).font(.caption.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
            } else {
                Text("Enter the store to see live calls.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.white.opacity(0.05), in: .rect(cornerRadius: 20))
        .animation(.snappy, value: call?.id)
    }

    private var arrow: some View {
        Image(systemName: "arrow.right").foregroundStyle(.tertiary).padding(.top, 26)
    }

    private func step(_ title: String, items: [String], empty: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if items.isEmpty {
                Text(empty).font(.callout).foregroundStyle(.tertiary)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, s in
                    Text(s).font(highlight ? .headline : .callout).lineLimit(1)
                        .foregroundStyle(highlight ? Theme.accent : .primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(highlight ? 0.08 : 0.04), in: .rect(cornerRadius: 14))
    }

    private func ranked(_ c: APITrace.Call) -> [String] {
        let ids = c.ranked.isEmpty ? c.predictions.map(\.itemId) : c.ranked
        return ids.prefix(4).enumerated().map { "#\($0.offset + 1)  \(trace.name($0.element))" }
    }

    private func footer(_ c: APITrace.Call) -> String {
        var s = "\(c.historyCount) events sent"
        if let st = c.httpStatus { s += " · HTTP \(st)" }
        if let ms = c.latencyMs { s += " · \(ms) ms" }
        s += " · \(trace.total) calls"
        return s
    }

    private func personaName(_ id: String) -> String {
        model.shoppers.first { $0.persona.id == id }?.persona.name ?? id
    }
}
