import SwiftUI

/// Main window: enter the store, pick the prediction source, overlays, heatmap, what-if log, settings.
struct ControlView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openSpace
    @Environment(\.dismissImmersiveSpace) private var dismissSpace
    @State private var tokenDraft = ""

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Button(model.immersiveOpen ? "Leave store" : "Enter store") {
                        Task {
                            if model.immersiveOpen { await dismissSpace() } else { _ = await openSpace(id: StoreSpace.id) }
                        }
                    }
                    .font(.title3.bold())
                    Text(model.status).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Section("Prediction source") {
                    Picker("Source", selection: $model.mode) {
                        ForEach(PredictorMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("Calls: \(model.callCount)").font(.caption.monospacedDigit())
                }
                Section("Overlays") {
                    Toggle("Prediction cards", isOn: $model.showCards)
                    Toggle("Probability arcs", isOn: $model.showArcs)
                    Toggle("Checkout anomaly", isOn: $model.showAnomaly)
                    if model.heatmapOn {
                        Button("Hide heatmap") { model.hideHeatmap() }
                    } else {
                        Button(model.heatmapBusy ? "Simulating 50 shoppers" : "Heatmap: 50 shoppers") { model.runHeatmap() }
                            .disabled(model.heatmapBusy || !model.immersiveOpen)
                    }
                }
                Section("Shoppers") {
                    ForEach(model.shoppers) { s in
                        Button { model.toggleFreeze(s.id) } label: {
                            HStack {
                                Circle().fill(Color(hex: s.persona.color)).frame(width: 10, height: 10)
                                Text(s.persona.name)
                                Spacer()
                                Text(s.frozen ? "fork" : "\(s.cart.count) items").foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("Restart shoppers") { model.reset() }
                }
                Section("What-if") {
                    Text(model.lastWhatIf ?? "Drag a product to move it. Long-press for a sale sign.")
                        .font(.callout)
                    if let first = model.catalog.first(where: \.onSale) {
                        Text("On sale: \(model.catalog.filter(\.onSale).map(\.name).joined(separator: ", "))")
                            .font(.caption).foregroundStyle(.secondary).id(first.id)
                    }
                }
                Section("BehaviorGPT proxy") {
                    TextField("https://proxy.example.workers.dev/predict", text: $model.proxyURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Proxy token", text: $tokenDraft)
                        .onSubmit { model.token = tokenDraft }
                    Button("Save token") { model.token = tokenDraft; tokenDraft = "" }
                        .disabled(tokenDraft.isEmpty)
                }
            }
            .navigationTitle("Behavior Aisle")
        }
    }
}
