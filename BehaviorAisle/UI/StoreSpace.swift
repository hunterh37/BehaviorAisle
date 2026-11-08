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
            _ = await model.buildScene(into: content)
            updates = content.subscribe(to: SceneEvents.Update.self) { event in
                let dt = Float(min(event.deltaTime, 0.05))
                MainActor.assumeIsolated { model.tick(dt) }
            }
            attachCards(attachments)
        } update: { _, attachments in
            attachCards(attachments)
        } attachments: {
            ForEach(model.shoppers) { s in
                Attachment(id: s.id) { PredictionCard(shopper: s) }
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
            card.isEnabled = model.showCards
            if card.parent !== s.root {
                s.root.addChild(card)
                card.position = [0, 2.15, 0]
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

    static func tagged(_ e: Entity, prefix: String) -> String? {
        var cur: Entity? = e
        while let c = cur {
            if c.name.hasPrefix(prefix) { return String(c.name.dropFirst(prefix.count)) }
            cur = c.parent
        }
        return nil
    }
}
