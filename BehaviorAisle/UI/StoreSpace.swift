import SwiftUI
import RealityKit
import RealKit

/// Lifesize store: shoppers, prediction cards, arcs, ghosts, heatmap. Tap shopper = fork view,
/// drag product = move it, long-press product = toggle sale.
struct StoreSpace: View {
    static let id = "store"
    @Environment(AppModel.self) private var model
    @State private var updates: EventSubscription?
    @State private var dragStart: [String: SIMD3<Float>] = [:]

    var body: some View {
        RealityView { content, attachments in
            if let bar = attachments.entity(for: Self.loadingId) {
                bar.position = [0, 1.4, -1.2]
                content.add(bar)
            }
            _ = await model.buildScene(into: content)
            attachments.entity(for: Self.loadingId)?.removeFromParent()
            updates = content.subscribe(to: SceneEvents.Update.self) { event in
                let dt = Float(min(event.deltaTime, 0.05))
                MainActor.assumeIsolated { model.tick(dt) }
            }
            attachCards(attachments)
        } update: { _, attachments in
            attachCards(attachments)
        } attachments: {
            Attachment(id: Self.loadingId) { LoadingBar() }
            ForEach(model.shoppers) { s in
                Attachment(id: s.id) {
                    if s.traits != nil && model.showIntent { IntentPanel(shopper: s) } else { PredictionCard(shopper: s) }
                }
                if s.traits != nil {
                    Attachment(id: Self.beaconId(s)) { BeaconLabel(shopper: s) }
                }
            }
        }
        .gesture(tap)
        .gesture(drag)
        .gesture(longPress)
        .task { await RealViewerTracker.shared.start() }
        .onAppear { model.immersiveOpen = true }
        .onDisappear { model.immersiveOpen = false }
    }

    private func attachCards(_ attachments: RealityViewAttachments) {
        for s in model.shoppers {
            guard let card = attachments.entity(for: s.id) else { continue }
            card.isEnabled = model.showCards || (s.traits != nil && model.showIntent)
            if s.traits != nil, card.scale.x < 1.5 { card.scale = .init(repeating: 1.8) }
            if let tag = attachments.entity(for: Self.beaconId(s)) {
                let beacon = model.intents.beacon(s.id)
                tag.isEnabled = model.showIntent && beacon != nil
                if let beacon, tag.parent !== beacon {
                    beacon.addChild(tag)
                    tag.position = .zero
                    tag.scale = .init(repeating: 2)
                    tag.components.set(BillboardComponent())
                }
            }
            if card.parent !== s.root {
                s.root.addChild(card)
                card.position = s.traits != nil ? [0, 3.1, 0] : [0, 2.15, 0]
                card.components.set(BillboardComponent())
            }
        }
    }

    private var tap: some Gesture {
        SpatialTapGesture().targetedToAnyEntity().onEnded { v in
            if let id = Self.tagged(v.entity, prefix: "shopper:") { model.toggleFreeze(id) }
        }
    }

    private var longPress: some Gesture {
        LongPressGesture(minimumDuration: 0.6).targetedToAnyEntity().onEnded { v in
            if let id = Self.tagged(v.entity, prefix: StoreBuilder.skuPrefix) { model.toggleSale(id) }
        }
    }

    private var drag: some Gesture {
        DragGesture().targetedToAnyEntity()
            .onChanged { v in
                guard let id = Self.tagged(v.entity, prefix: StoreBuilder.skuPrefix),
                      let slot = model.store?.slots[id], let parent = slot.parent else { return }
                let p = v.convert(v.location3D, from: .local, to: parent)
                slot.position = p
                dragStart[id] = p
            }
            .onEnded { v in
                guard let id = Self.tagged(v.entity, prefix: StoreBuilder.skuPrefix), let p = dragStart[id] else { return }
                dragStart[id] = nil
                model.moveProduct(id, to: p + SIMD3(0, 0.12, 0))
            }
    }

    static let loadingId = "loading"
    static func beaconId(_ s: ShopperAgent) -> String { "beacon:" + s.id }

    static func tagged(_ e: Entity, prefix: String) -> String? {
        var cur: Entity? = e
        while let c = cur {
            if c.name.hasPrefix(prefix) { return String(c.name.dropFirst(prefix.count)) }
            cur = c.parent
        }
        return nil
    }
}

/// Scene generation progress shown in front of the viewer while the store builds.
struct LoadingBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let f = model.loadProgress ?? 1
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.loadStage.isEmpty ? "Loading store" : model.loadStage).font(.headline)
                Spacer()
                Text("\(Int(f * 100))%").font(.headline.monospacedDigit())
            }
            ProgressView(value: f).animation(.easeOut(duration: 0.25), value: f)
        }
        .padding(24)
        .frame(width: 420)
        .glassBackgroundEffect()
    }
}
