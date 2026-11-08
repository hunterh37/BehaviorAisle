import RealityKit
import UIKit
import simd

/// Where an imported shopper is predicted to go: a marching dotted floor path to the top item's aisle spot,
/// a light beam and pulsing ring on that product, and smaller rings on ranks 2-3.
@MainActor
final class IntentLayer {
    let root = Entity()
    @MainActor private final class Group {
        let root = Entity()
        let beacon = Entity()
        var dots: [ModelEntity] = []
        var rings: [(ModelEntity, Float)] = []
    }
    private var groups: [String: Group] = [:]
    private var t: Float = 0

    init() { root.name = "intent" }

    /// Beacon entity above the rank-1 product; StoreSpace parents the label attachment here.
    func beacon(_ shopperId: String) -> Entity? { groups[shopperId]?.beacon }

    func update(_ s: ShopperAgent, catalog: [Product], visible: Bool) {
        groups[s.id]?.root.removeFromParent()
        groups[s.id] = nil
        guard visible, s.traits != nil else { return }
        let ranked = s.predictions.sorted { $0.p > $1.p }
        let first = s.target.flatMap { t in ranked.first { $0.id == t.id } } ?? ranked.first
        guard let first else { return }
        let g = Group()
        g.root.name = "intent:" + s.id
        let color = UIColor(hex: s.persona.color)

        // Rank-1 destination.
        let end: SIMD3<Float>, anchor: SIMD3<Float>
        if first.itemId == Prediction.checkoutId {
            end = StoreLayout.checkoutStand
            anchor = StoreLayout.checkout + SIMD3(0, 0.9, 0)
        } else if let p = catalog.first(where: { $0.id == first.itemId }) {
            end = p.stand
            anchor = p.anchor
        } else { return }

        // Dotted floor path.
        let start = s.position
        let pts = [start] + StoreLayout.path(from: start, to: end)
        var dotMat = UnlitMaterial(color: color)
        dotMat.blending = .transparent(opacity: 0.9)
        let dotMesh = Self.dotMesh
        var carried: Float = 0.3
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            let len = simd_distance(a, b)
            var d = carried
            while d < len {
                let e = ModelEntity(mesh: dotMesh, materials: [dotMat])
                e.position = a + (b - a) * (d / len) + SIMD3(0, 0.012, 0)
                g.root.addChild(e)
                g.dots.append(e)
                d += 0.28
            }
            carried = d - len
        }
        // Floor target disc at the stand.
        var padMat = UnlitMaterial(color: color)
        padMat.blending = .transparent(opacity: 0.35)
        padMat.faceCulling = .none
        let pad = ModelEntity(mesh: Self.ring(inner: 0.22, outer: 0.34), materials: [padMat])
        pad.position = end + SIMD3(0, 0.015, 0)
        g.root.addChild(pad)
        g.rings.append((pad, 0))

        // Beam and ring on the product.
        var beamMat = UnlitMaterial(color: color)
        beamMat.blending = .transparent(opacity: 0.28)
        let beam = ModelEntity(mesh: .generateCylinder(height: 1.6, radius: 0.025), materials: [beamMat])
        beam.position = anchor + SIMD3(0, 0.95, 0)
        g.root.addChild(beam)
        g.rings.append((Self.halo(at: anchor, color: color, size: 1, opacity: 0.85, parent: g.root), 0.5))
        g.beacon.position = anchor + SIMD3(0, 0.42, 0)
        g.root.addChild(g.beacon)

        // Ranks 2-3: quieter rings.
        for (i, pred) in ranked.filter({ $0.id != first.id }).prefix(2).enumerated() {
            guard let p = catalog.first(where: { $0.id == pred.itemId }) else { continue }
            g.rings.append((Self.halo(at: p.anchor, color: color, size: 0.7, opacity: 0.45, parent: g.root), Float(i + 1)))
        }
        root.addChild(g.root)
        groups[s.id] = g
    }

    func tick(_ dt: Float) {
        t += dt
        for g in groups.values {
            let n = Float(max(g.dots.count, 1))
            for (i, d) in g.dots.enumerated() {
                // Bright pulse marching toward the destination.
                let ph = (t * 1.4 - Float(i) / n * 3).truncatingRemainder(dividingBy: 1)
                let k = ph < 0 ? ph + 1 : ph
                let s = 0.75 + 0.5 * max(0, 1 - abs(k - 0.5) * 4)
                d.scale = [s, 1, s]
            }
            for (r, ph) in g.rings {
                let s = 1 + 0.12 * sin(t * 3 + ph)
                r.scale = [s, 1, s]
            }
        }
    }

    func clear(_ id: String) { groups[id]?.root.removeFromParent(); groups[id] = nil }

    /// Horizontal ring just under the product's shelf point.
    private static func halo(at p: SIMD3<Float>, color: UIColor, size: Float, opacity: Float, parent: Entity) -> ModelEntity {
        var m = UnlitMaterial(color: color)
        m.blending = .transparent(opacity: .init(floatLiteral: opacity))
        m.faceCulling = .none
        let e = ModelEntity(mesh: ring(inner: 0.11 * size, outer: 0.15 * size), materials: [m])
        e.position = p - SIMD3(0, 0.1, 0)
        parent.addChild(e)
        return e
    }

    /// Flat annulus in the XZ plane, double sided.
    private static let dotMesh = MeshResource.generateCylinder(height: 0.006, radius: 0.045)
    private static var ringCache: [SIMD3<Float>: MeshResource] = [:]

    /// Cached: intent groups rebuild on every prediction, the ring sizes are fixed.
    static func ring(inner: Float, outer: Float, segments: Int = 48) -> MeshResource {
        let key = SIMD3(inner, outer, Float(segments))
        if let m = ringCache[key] { return m }
        let m = makeRing(inner: inner, outer: outer, segments: segments)
        ringCache[key] = m
        return m
    }

    private static func makeRing(inner: Float, outer: Float, segments: Int) -> MeshResource {
        var pos: [SIMD3<Float>] = [], idx: [UInt32] = []
        for i in 0...segments {
            let a = Float(i) / Float(segments) * 2 * .pi
            let c = SIMD3(cos(a), 0, sin(a))
            pos += [c * inner, c * outer]
            if i > 0 {
                let k = UInt32(i * 2)
                idx += [k - 2, k - 1, k, k - 1, k + 1, k]
            }
        }
        var d = MeshDescriptor(name: "ring")
        d.positions = MeshBuffers.Positions(pos)
        d.primitives = .triangles(idx)
        return (try? MeshResource.generate(from: [d])) ?? .generatePlane(width: outer, depth: outer)
    }
}
