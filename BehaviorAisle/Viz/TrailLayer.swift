import RealityKit
import UIKit
import simd

/// Floor breadcrumbs of where each shopper walked. One dot every 0.35 m, max 120 per shopper.
@MainActor
final class TrailLayer {
    let root = Entity()
    private var last: [String: SIMD3<Float>] = [:]
    private var dots: [String: [Entity]] = [:]
    private var meshes: [String: (MeshResource, UnlitMaterial)] = [:]
    static let spacing: Float = 0.35
    static let maxDots = 120

    var visible = true { didSet { root.isEnabled = visible } }

    func tick(_ shoppers: [ShopperAgent]) {
        for s in shoppers {
            let p = s.position
            guard let l = last[s.id] else { last[s.id] = p; continue }
            guard simd_distance(SIMD2(p.x, p.z), SIMD2(l.x, l.z)) >= Self.spacing else { continue }
            last[s.id] = p
            let look = meshes[s.id] ?? {
                var m = UnlitMaterial(color: UIColor(hex: s.persona.color))
                m.blending = .transparent(opacity: 0.55)
                let v = (MeshResource.generateCylinder(height: 0.004, radius: 0.045), m)
                meshes[s.id] = v
                return v
            }()
            let e = ModelEntity(mesh: look.0, materials: [look.1])
            e.position = [p.x, 0.008, p.z]
            root.addChild(e)
            var list = dots[s.id, default: []]
            list.append(e)
            if list.count > Self.maxDots { list.removeFirst().removeFromParent() }
            dots[s.id] = list
        }
    }

    func clear() {
        root.children.removeAll()
        dots.removeAll()
        last.removeAll()
    }
}
