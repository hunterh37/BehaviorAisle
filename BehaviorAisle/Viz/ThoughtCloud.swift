import Foundation
import RealityKit
import RealLibrary
import UIKit

/// Thought cloud above an imported shopper: soft puffs, a trail of bubbles down to the head,
/// and the wishlist products floating inside. Animated from AppModel.tick.
@MainActor
final class ThoughtCloud {
    let root = Entity()
    private var items: [(Entity, Float)] = []
    private var puffs: [(Entity, Float)] = []
    private var t: Float = 0
    private var grow: Float = 0

    static let height: Float = 2.08

    init() {
        root.name = "thought-cloud"
        root.position = [0.25, Self.height, 0]
        root.scale = .init(repeating: 0.001)
        root.components.set(BillboardComponent())
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: .white)
        m.roughness = 0.9
        m.blending = .transparent(opacity: 0.55)
        m.emissiveColor = .init(color: .white)
        m.emissiveIntensity = 0.4
        let layout: [(SIMD3<Float>, Float)] = [
            ([0, 0, 0], 0.17), ([-0.2, -0.02, 0], 0.13), ([0.2, -0.01, 0], 0.14),
            ([-0.1, 0.1, -0.02], 0.12), ([0.11, 0.1, -0.02], 0.12), ([0, -0.08, 0.02], 0.12),
        ]
        for (i, (p, r)) in layout.enumerated() {
            let e = ModelEntity(mesh: .generateSphere(radius: r), materials: [m])
            e.position = p
            e.scale = [1.25, 0.85, 0.55]
            root.addChild(e)
            puffs.append((e, Float(i) * 1.1))
        }
        // Bubbles from head to cloud.
        for (i, r) in [Float(0.035), 0.022, 0.014].enumerated() {
            let e = ModelEntity(mesh: .generateSphere(radius: r), materials: [m])
            e.position = [-0.17 + Float(i) * 0.03, -0.2 - Float(i) * 0.12, 0]
            root.addChild(e)
            puffs.append((e, Float(i) * 2))
        }
    }

    /// Loads up to 4 product models into the cloud, scaled to 11 cm.
    func show(_ products: [Product]) async {
        items.forEach { $0.0.removeFromParent() }
        items = []
        let slots: [SIMD3<Float>] = [[-0.16, 0.0, 0.1], [-0.05, 0.03, 0.12], [0.06, 0.03, 0.12], [0.17, 0.0, 0.1]]
        for (i, p) in products.prefix(4).enumerated() {
            let holder = Entity()
            holder.position = slots[i]
            if let e = try? await RealityHD.entity(p.asset, grabbable: false) {
                let b = e.visualBounds(relativeTo: nil).extents
                let s = 0.14 / max(0.01, max(b.x, b.y, b.z))
                e.scale = .init(repeating: s)
                e.position = -e.visualBounds(relativeTo: nil).center * s
                holder.addChild(e)
            } else {
                let m = SimpleMaterial(color: .systemPink, roughness: 0.4, isMetallic: false)
                holder.addChild(ModelEntity(mesh: .generateBox(size: 0.07, cornerRadius: 0.01), materials: [m]))
            }
            root.addChild(holder)
            items.append((holder, Float(i) * 1.7))
        }
        grow = 0
    }

    func tick(_ dt: Float) {
        t += dt
        grow = min(1, grow + dt * 1.6)
        // Ease-out-back pop on appear.
        let g = grow - 1
        root.scale = .init(repeating: max(0.001, 1 + 2.2 * g * g * g + 1.2 * g * g))
        root.position.y = Self.height + sin(t * 1.2) * 0.015
        for (e, ph) in puffs { e.position.z = sin(t * 0.9 + ph) * 0.008 }
        for (e, ph) in items {
            e.position.y = 0.02 + sin(t * 1.8 + ph) * 0.012
            e.orientation = simd_quatf(angle: t * 0.7 + ph, axis: [0, 1, 0])
        }
    }
}
