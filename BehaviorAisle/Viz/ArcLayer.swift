import RealityKit
import UIKit
import simd

/// Floor-to-shelf ribbons from each shopper to its top-3 predicted items. Width and opacity scale with p.
@MainActor
struct ArcLayer {
    let root = Entity()
    private var groups: [String: Entity] = [:]

    mutating func update(_ s: ShopperAgent, catalog: [Product], visible: Bool) {
        groups[s.id]?.removeFromParent()
        let g = Entity()
        g.name = "arcs:" + s.id
        groups[s.id] = g
        guard visible else { return }
        let start = s.position + SIMD3(0, 0.05, 0)
        for pred in s.predictions {
            let end: SIMD3<Float>
            if pred.itemId == Prediction.checkoutId { end = StoreLayout.checkout + SIMD3(0, 0.9, 0) }
            else if let p = catalog.first(where: { $0.id == pred.itemId }) { end = p.anchor } else { continue }
            guard let mesh = Self.ribbon(from: start, to: end, width: 0.015 + Float(pred.p) * 0.09) else { continue }
            var m = UnlitMaterial(color: UIColor(hex: s.persona.color))
            m.blending = .transparent(opacity: .init(floatLiteral: Float(0.25 + 0.7 * pred.p)))
            m.faceCulling = .none
            g.addChild(ModelEntity(mesh: mesh, materials: [m]))
        }
        root.addChild(g)
    }

    /// Keeps arcs anchored at their prediction origin; nothing per frame beyond visibility.
    func follow(_ shoppers: [ShopperAgent]) {
        for s in shoppers {
            guard let g = groups[s.id] else { continue }
            let on = s.phase != .done
            if g.isEnabled != on { g.isEnabled = on }
        }
    }

    func clearAll() { root.children.removeAll() }

    /// Quadratic bezier ribbon on the floor rising to the shelf point, facing up.
    static func ribbon(from a: SIMD3<Float>, to b: SIMD3<Float>, width: Float, segments: Int = 28) -> MeshResource? {
        let mid = (a + b) / 2 + SIMD3(0, 0.6 + simd_distance(a, b) * 0.12, 0)
        var pos: [SIMD3<Float>] = [], idx: [UInt32] = []
        for i in 0...segments {
            let t = Float(i) / Float(segments)
            let p = (1 - t) * (1 - t) * a + 2 * (1 - t) * t * mid + t * t * b
            let tan = simd_normalize(2 * (1 - t) * (mid - a) + 2 * t * (b - mid))
            var side = simd_cross(tan, [0, 1, 0])
            if simd_length(side) < 1e-3 { side = [1, 0, 0] }
            side = simd_normalize(side) * width * 0.5
            pos += [p - side, p + side]
            if i > 0 {
                let k = UInt32(i * 2)
                idx += [k - 2, k - 1, k, k - 1, k + 1, k]
            }
        }
        var d = MeshDescriptor(name: "arc")
        d.positions = MeshBuffers.Positions(pos)
        d.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [d])
    }
}

/// Red shelf talker shown on items with a promo.
@MainActor
enum SaleSign {
    static func make(price: Double) -> Entity {
        let e = Entity()
        e.name = "sale"
        let card = ModelEntity(mesh: .generateBox(size: [0.012, 0.09, 0.16], cornerRadius: 0.004),
                               materials: [SimpleMaterial(color: UIColor(hex: 0xD7261E), roughness: 0.5, isMetallic: false)])
        card.position = [0, 0.32, 0]
        e.addChild(card)
        let label = String(format: "SALE $%.2f", price * 0.8)
        let text = ModelEntity(mesh: .generateText(label, extrusionDepth: 0.001, font: .boldSystemFont(ofSize: 0.022)),
                               materials: [UnlitMaterial(color: .white)])
        let tb = text.visualBounds(relativeTo: nil)
        text.position = [0, 0.32 - tb.extents.y / 2, 0]
        text.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        let inner = Entity(); inner.addChild(text)
        inner.position = [0.008, 0, tb.extents.x / 2]
        e.addChild(inner)
        let twin = inner.clone(recursive: true)
        twin.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        twin.position = [-0.008, 0, -tb.extents.x / 2]
        e.addChild(twin)
        return e
    }
}
