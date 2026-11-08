import RealityKit
import UIKit
import simd

/// Fork view: translucent ghosts walk each of the frozen shopper's top-3 branches at once.
@MainActor
struct GhostLayer {
    let root = Entity()
    private var ghosts: [(entity: Entity, path: [SIMD3<Float>])] = []
    private var time: Float = 0

    mutating func clear() {
        root.children.removeAll()
        ghosts.removeAll()
    }

    mutating func spawn(for s: ShopperAgent, catalog: [Product]) {
        clear()
        for pred in s.predictions {
            let stand: SIMD3<Float>
            if pred.itemId == Prediction.checkoutId { stand = StoreLayout.checkoutStand }
            else if let p = catalog.first(where: { $0.id == pred.itemId }) { stand = p.stand } else { continue }
            let e = Self.ghost(color: s.persona.color, p: pred.p)
            e.position = s.position
            root.addChild(e)
            ghosts.append((e, StoreLayout.path(from: s.position, to: stand)))
        }
    }

    mutating func tick(_ dt: Float) {
        time += dt
        for i in ghosts.indices {
            var g = ghosts[i]
            if let next = g.path.first {
                let d = next - g.entity.position
                let dist = simd_length(SIMD2(d.x, d.z))
                let move = ShopperAgent.walkSpeed * 1.4 * dt
                if dist <= move { g.entity.position = next; g.path.removeFirst() }
                else {
                    g.entity.position += SIMD3(d.x, 0, d.z) / dist * move
                    g.entity.orientation = simd_quatf(angle: atan2(d.x, d.z), axis: [0, 1, 0])
                }
            } else {
                let s = 1 + 0.04 * sin(time * 4)
                g.entity.scale = [s, s, s]
            }
            ghosts[i] = g
        }
    }

    static func ghost(color: UInt32, p: Double) -> Entity {
        let e = Entity()
        var m = UnlitMaterial(color: UIColor(hex: color))
        m.blending = .transparent(opacity: .init(floatLiteral: Float(0.2 + 0.5 * p)))
        let body = ModelEntity(mesh: .generateCylinder(height: 1.1, radius: 0.2), materials: [m])
        body.position.y = 0.85
        let head = ModelEntity(mesh: .generateSphere(radius: 0.12), materials: [m])
        head.position.y = 1.58
        let ring = ModelEntity(mesh: .generateCylinder(height: 0.005, radius: 0.35), materials: [m])
        ring.position.y = 0.01
        e.addChild(body); e.addChild(head); e.addChild(ring)
        let label = ModelEntity(mesh: .generateText(String(format: "%.0f%%", p * 100), extrusionDepth: 0.002,
                                                    font: .boldSystemFont(ofSize: 0.12)), materials: [UnlitMaterial(color: .white)])
        let b = label.visualBounds(relativeTo: nil)
        label.position = [-b.extents.x / 2, 1.8, 0]
        e.addChild(label)
        return e
    }
}
