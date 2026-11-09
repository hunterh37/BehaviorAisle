import RealityKit
import UIKit
import simd

/// Shelf demand: a glowing column above each SKU, height = summed predicted probability across
/// all live shoppers, plus a units-sold count. Rebuilt on each prediction, not per frame.
@MainActor
final class DemandLayer {
    let root = Entity()
    private var bars: [String: ModelEntity] = [:]
    private let mesh = MeshResource.generateBox(size: [0.06, 1, 0.06], cornerRadius: 0.01)

    var visible = false { didSet { root.isEnabled = visible } }

    init() { root.isEnabled = false }

    /// Summed p per SKU over every shopper's current top 3.
    static func demand(_ shoppers: [ShopperAgent]) -> [String: Double] {
        var d: [String: Double] = [:]
        for s in shoppers where s.phase != .done {
            for p in s.predictions where p.itemId != Prediction.checkoutId { d[p.itemId, default: 0] += p.p }
        }
        return d
    }

    func update(_ shoppers: [ShopperAgent], catalog: [Product]) {
        let d = Self.demand(shoppers)
        let peak = max(d.values.max() ?? 1, 0.01)
        for p in catalog {
            let v = Float((d[p.id] ?? 0) / peak)
            let bar = bars[p.id] ?? {
                let b = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .clear)])
                root.addChild(b)
                bars[p.id] = b
                return b
            }()
            guard v > 0.02 else { bar.isEnabled = false; continue }
            bar.isEnabled = true
            let h = 0.05 + v * 0.6
            let (r, g, b) = HeatmapLayer.ramp(v)
            var m = UnlitMaterial(color: UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1))
            m.blending = .transparent(opacity: .init(floatLiteral: 0.45 + 0.45 * v))
            bar.model?.materials = [m]
            bar.scale = [1, h, 1]
            bar.position = p.anchor + SIMD3(0, 0.35 + h / 2, 0)
        }
    }
}
