import RealityKit
import UIKit
import CoreGraphics
import simd

/// Floor grid of predicted foot traffic. 0.25 m cells over the store bounds.
struct HeatGrid: Sendable {
    static let cell: Float = 0.25
    let w: Int, h: Int
    var counts: [Float]
    init() {
        let b = StoreLayout.bounds
        w = Int((b.max.x - b.min.x) / Self.cell)
        h = Int((b.max.y - b.min.y) / Self.cell)
        counts = Array(repeating: 0, count: w * h)
    }
    mutating func add(_ p: SIMD3<Float>, _ v: Float = 1) {
        let b = StoreLayout.bounds
        let x = Int((p.x - b.min.x) / Self.cell), z = Int((p.z - b.min.y) / Self.cell)
        guard x >= 0, z >= 0, x < w, z < h else { return }
        counts[z * w + x] += v
    }
}

/// Headless 50-shopper run on the heuristic model (fast, no API quota).
enum HeatmapSim {
    static func run(catalog: [Product], shoppers: Int) -> HeatGrid {
        var grid = HeatGrid()
        let model = HeuristicPredictor()
        var rng = SplitMix(seed: 2026)
        for i in 0..<shoppers {
            let persona = Persona.all[i % Persona.all.count]
            var pos = StoreLayout.entrance
            var history = persona.seedHistory, cart: [String] = []
            for _ in 0..<14 {
                let r = model.rank(PredictionRequest(personaId: persona.id, history: history, cart: cart, catalog: catalog), from: pos)
                let total = r.predictions.reduce(0) { $0 + $1.p }
                var x = rng.nextDouble() * total
                var pick = r.predictions[0]
                for p in r.predictions { x -= p.p; if x <= 0 { pick = p; break } }
                let dest = pick.itemId == Prediction.checkoutId ? StoreLayout.checkoutStand
                    : (catalog.first(where: { $0.id == pick.itemId })?.stand ?? pos)
                var a = pos
                for b in StoreLayout.path(from: pos, to: dest) {
                    let n = max(1, Int(simd_distance(a, b) / 0.2))
                    for k in 0..<n { grid.add(a + (b - a) * Float(k) / Float(n)) }
                    a = b
                }
                grid.add(dest, 6)
                pos = dest
                if pick.action == .checkout { break }
                history.append(BehaviorEvent(pick.action, pick.itemId))
                if pick.action == .addToCart { cart.append(pick.itemId) }
            }
        }
        return grid
    }
}

@MainActor
struct HeatmapLayer {
    let root = Entity()

    func show(_ g: HeatGrid) async {
        root.children.removeAll()
        let maxV = max(g.counts.max() ?? 1, 1)
        var px = [UInt8](repeating: 0, count: g.w * g.h * 4)
        for i in 0..<(g.w * g.h) {
            let t = sqrt(g.counts[i] / maxV)
            let (r, gg, b) = Self.ramp(t)
            px[i * 4] = r; px[i * 4 + 1] = gg; px[i * 4 + 2] = b
            px[i * 4 + 3] = UInt8(min(255, t * 230))
        }
        guard let ctx = CGContext(data: &px, width: g.w, height: g.h, bitsPerComponent: 8, bytesPerRow: g.w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let img = ctx.makeImage(),
              let tex = try? await TextureResource(image: img, options: .init(semantic: .color)) else { return }
        var m = UnlitMaterial()
        m.color = .init(tint: .white, texture: .init(tex))
        m.blending = .transparent(opacity: 0.9)
        let b = StoreLayout.bounds
        let size = SIMD2(b.max.x - b.min.x, b.max.y - b.min.y)
        let plane = ModelEntity(mesh: .generatePlane(width: size.x, depth: size.y), materials: [m])
        plane.position = [b.min.x + size.x / 2, 0.012, b.min.y + size.y / 2]
        root.addChild(plane)
    }

    static func ramp(_ t: Float) -> (UInt8, UInt8, UInt8) {
        let c: SIMD3<Float> = t < 0.5 ? mix([0.1, 0.3, 1.0], [0.1, 0.9, 0.5], t: t * 2) : mix([0.1, 0.9, 0.5], [1.0, 0.25, 0.1], t: (t - 0.5) * 2)
        return (UInt8(c.x * 255), UInt8(c.y * 255), UInt8(c.z * 255))
    }

    static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> { a + (b - a) * t }
}
