import SwiftUI

/// Main window: glass dashboard. Enter the store, live stats, shoppers, profile import, what-if.
/// Overlay toggles live in the bottom ornament; source and proxy live in the settings sheet.
struct ControlView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openSpace
    @Environment(\.dismissImmersiveSpace) private var dismissSpace
    @State private var showSettings = false
    @State private var handle = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                enterButton
                stats
                shoppersSection
                importSection
                whatIfSection
            }
            .padding(28)
        }
        .ornament(attachmentAnchor: .scene(.bottom)) { overlayBar }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .sheet(isPresented: Binding(get: { model.showAnalysis }, set: { model.showAnalysis = $0 })) {
            NavigationStack { ProfileImportView() }
                .environment(model)
                .frame(width: 640, height: 900)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "cart.fill")
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .frame(width: 48, height: 48)
                .background(Theme.accent.opacity(0.15), in: .circle)
            Text("Behavior Aisle").font(.extraLargeTitle2.weight(.bold))
            Spacer()
            sourcePill
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .buttonBorderShape(.circle)
                .help("Settings")
        }
    }

    private var sourcePill: some View {
        let live = model.mode == .live
        let c = live ? Theme.accent : Theme.amber
        return HStack(spacing: 6) {
            Circle().fill(c).frame(width: 8, height: 8)
                .shadow(color: c, radius: 4)
            Text(model.mode.label).font(.callout.weight(.semibold))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(c.opacity(0.14), in: .capsule)
    }

    // MARK: Enter

    private var enterButton: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Task {
                    if model.immersiveOpen { await dismissSpace() } else { _ = await openSpace(id: StoreSpace.id) }
                }
            } label: {
                Label(model.immersiveOpen ? "Leave store" : "Enter store",
                      systemImage: model.immersiveOpen ? "xmark" : "door.left.hand.open")
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.immersiveOpen ? .secondary : Theme.accent)
            .buttonBorderShape(.capsule)
            if let f = model.loadProgress {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(model.loadStage).font(.callout)
                        Spacer()
                        Text("\(Int(f * 100))%").font(.callout.monospacedDigit())
                    }
                    PBar(p: f, color: Theme.accent, height: 6)
                }
                .foregroundStyle(.secondary)
            } else {
                Text(model.status).font(.caption.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
    }

    // MARK: Stats

    private var stats: some View {
        let items = model.shoppers.reduce(0) { $0 + $1.cart.count }
        let unusual = model.shoppers.filter { ($0.anomaly ?? 0) >= 0.5 }.count
        return HStack(spacing: 12) {
            StatTile(value: model.shoppers.count, label: "Shoppers", icon: "person.2.fill", color: .white)
            StatTile(value: items, label: "In carts", icon: "cart.fill", color: Theme.accent)
            StatTile(value: model.callCount, label: "Predictions", icon: "sparkles", color: Color(hex: 0x8AB4FF))
            StatTile(value: unusual, label: "Unusual", icon: "exclamationmark.triangle.fill",
                     color: unusual > 0 ? Theme.alert : .secondary)
        }
    }

    // MARK: Shoppers

    private var shoppersSection: some View {
        Section {
            if model.shoppers.isEmpty {
                Text("Shoppers appear when the store opens.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(.white.opacity(0.04), in: .rect(cornerRadius: 16))
            } else {
                VStack(spacing: 8) {
                    ForEach(model.shoppers) { ShopperRow(shopper: $0) }
                }
            }
        } header: {
            SectionHeader("Shoppers")
        }
    }

    // MARK: Import

    private var importSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "at").foregroundStyle(.secondary)
                    TextField("X handle", text: $handle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(startImport)
                    Button("Shop as them", action: startImport)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .disabled(handle.isEmpty || busy)
                }
                if model.importStage != .idle { ImportProgress() }
            }
            .padding(16)
            .background(.white.opacity(0.05), in: .rect(cornerRadius: 18))
        } header: {
            SectionHeader("Add a shopper")
        }
    }

    private var busy: Bool {
        switch model.importStage {
        case .fetching, .reading, .classifying, .building: true
        default: false
        }
    }

    private func startImport() {
        guard !handle.isEmpty, !busy else { return }
        model.importProfile(handle)
        model.showAnalysis = true
    }

    // MARK: What-if

    private var whatIfSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.lastWhatIf ?? "Drag a product to move it. Long-press for a sale sign.")
                    .font(.callout)
                    .foregroundStyle(model.lastWhatIf == nil ? .secondary : .primary)
                let sale = model.catalog.filter(\.onSale)
                if !sale.isEmpty {
                    FlowChips(items: sale.map { "\($0.name) −20%" }, color: Theme.amber)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.05), in: .rect(cornerRadius: 18))
        } header: {
            SectionHeader("What-if")
        }
    }

    // MARK: Ornament

    private var overlayBar: some View {
        @Bindable var model = model
        return HStack(spacing: 6) {
            OrnamentToggle(icon: "rectangle.on.rectangle", label: "Cards", isOn: $model.showCards)
            OrnamentToggle(icon: "point.topleft.down.to.point.bottomright.curvepath", label: "Arcs", isOn: $model.showArcs)
            OrnamentToggle(icon: "exclamationmark.triangle", label: "Anomaly", isOn: $model.showAnomaly)
            OrnamentToggle(icon: "scope", label: "Intent", isOn: $model.showIntent)
            Divider().frame(height: 28)
            Button {
                if model.heatmapOn { model.hideHeatmap() } else { model.runHeatmap() }
            } label: {
                Label(model.heatmapBusy ? "Simulating" : "Heatmap",
                      systemImage: model.heatmapBusy ? "hourglass" : "square.grid.3x3.fill")
            }
            .tint(model.heatmapOn ? Theme.amber : nil)
            .disabled(model.heatmapBusy || (!model.heatmapOn && !model.immersiveOpen))
            Button { model.reset() } label: { Label("Restart", systemImage: "arrow.counterclockwise") }
        }
        .labelStyle(.iconOnly)
        .padding(10)
        .glassBackgroundEffect(in: .capsule)
    }
}

// MARK: Pieces

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(.title3.weight(.semibold)).padding(.bottom, 2)
    }
}

private struct StatTile: View {
    let value: Int
    let label: String
    let icon: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.callout).foregroundStyle(color)
            Text("\(value)")
                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText(value: Double(value)))
                .animation(.snappy, value: value)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 18))
    }
}

private struct ShopperRow: View {
    @Environment(AppModel.self) private var model
    let shopper: ShopperAgent

    var body: some View {
        let c = Color(hex: shopper.persona.color)
        let top = shopper.predictions.max { $0.p < $1.p }
        Button { model.toggleFreeze(shopper.id) } label: {
            HStack(spacing: 14) {
                Capsule().fill(c).frame(width: 5, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(shopper.persona.name).font(.headline)
                        Chip(text: shopper.frozen ? "fork" : shopper.phase.label,
                             color: shopper.frozen ? Theme.amber : .secondary)
                        if let a = shopper.anomaly, a >= 0.5, model.showAnomaly {
                            Chip(text: "unusual", color: Theme.alert)
                        }
                    }
                    if let top {
                        HStack(spacing: 8) {
                            Text(model.actionName(top)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(top.p, format: .percent.precision(.fractionLength(0)))
                                .font(.callout.monospacedDigit().weight(.semibold))
                                .contentTransition(.numericText())
                        }
                        PBar(p: top.p, color: c, height: 4)
                    }
                }
                Label("\(shopper.cart.count)", systemImage: "cart")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .trailing)
            }
            .padding(.vertical, 10).padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shopper.frozen ? Theme.amber.opacity(0.1) : .white.opacity(0.05), in: .rect(cornerRadius: 18))
            .contentShape(.hoverEffect, .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .hoverEffect()
    }
}

private struct ImportProgress: View {
    @Environment(AppModel.self) private var model
    private let steps = ["Fetch", "Read", "Classify", "Build"]

    private var index: Int {
        switch model.importStage {
        case .idle, .failed: -1
        case .fetching: 0
        case .reading: 1
        case .classifying: 2
        case .building: 3
        case .done: 4
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if case .failed(let msg) = model.importStage {
                Label(msg, systemImage: "exclamationmark.octagon.fill")
                    .font(.callout).foregroundStyle(Theme.alert)
            } else {
                HStack(spacing: 6) {
                    ForEach(steps.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 6) {
                            Capsule()
                                .fill(i < index ? Theme.accent : i == index ? Theme.accent.opacity(0.5) : .white.opacity(0.1))
                                .frame(height: 4)
                            Text(steps[i]).font(.caption2)
                                .foregroundStyle(i <= index ? .primary : .tertiary)
                        }
                    }
                }
                .animation(.smooth, value: index)
            }
            if let p = model.importedProfile {
                Text(p.name.isEmpty ? "@\(p.handle)" : "\(p.name)  @\(p.handle)").font(.headline)
            }
            if let t = model.importedTraits {
                if !t.interests.isEmpty { FlowChips(items: Array(t.interests.prefix(6)), color: Theme.accent) }
                if !t.summary.isEmpty {
                    Text(t.summary).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                }
            }
        }
    }
}

private struct FlowChips: View {
    let items: [String]
    let color: Color
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { Chip(text: $0, color: color) }
            }
        }
    }
}

private struct OrnamentToggle: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) { Label(label, systemImage: icon) }
            .toggleStyle(.button)
            .help(label)
    }
}

private struct SettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var tokenDraft = ""

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Prediction source") {
                    Picker("Source", selection: $model.mode) {
                        ForEach(PredictorMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Shelf stock") {
                    Picker("Preset", selection: Binding(
                        get: { model.density.preset },
                        set: { if let p = $0 { model.density = p.density } })) {
                        ForEach(StoreDensity.Preset.allCases) { Text($0.label).tag(Optional($0)) }
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("Fill \(Int(model.density.fill * 100))%") {
                        Slider(value: $model.density.fill, in: 0...1)
                    }
                    LabeledContent("Packing \(Int(model.density.packing * 100))%") {
                        Slider(value: $model.density.packing, in: 0...1)
                    }
                    Stepper("Depth \(model.density.depth) deep", value: $model.density.depth, in: 1...6)
                    Stepper("Facings per item \(model.density.skuFacings)", value: $model.density.skuFacings, in: 1...7)
                    Toggle("Overstock", isOn: $model.density.overstock)
                    Button("Restock store") { Task { await model.applyDensity() } }
                        .disabled(model.store == nil || model.loadProgress != nil)
                }
                Section("BehaviorGPT proxy") {
                    TextField("https://proxy.example.workers.dev/predict", text: $model.proxyURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Proxy token", text: $tokenDraft)
                        .onSubmit { model.token = tokenDraft; tokenDraft = "" }
                    Button("Save token") { model.token = tokenDraft; tokenDraft = "" }
                        .disabled(tokenDraft.isEmpty)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .frame(width: 560, height: 680)
    }
}

extension AppModel {
    /// "Buy Milk", "Look at Bread", "Check out".
    func actionName(_ p: Prediction) -> String {
        if p.itemId == Prediction.checkoutId { return "Check out" }
        let n = product(p.itemId)?.name ?? p.itemId
        return p.action == .addToCart ? "Buy \(n)" : "Look at \(n)"
    }
}
