import RealityKit
import UIKit
import RealKit
import RealLibrary

/// Builds the lifesize store. Uses the RealityHD `grocery-store` scene and grocery props when the package has them,
/// otherwise a procedural fallback shell so the app runs on any RealityHD revision.
@MainActor
enum StoreBuilder {
    static let skuPrefix = "sku:"

    struct Built {
        let root: Entity
        var slots: [String: Entity]
        var env: RealEnvironment?
    }

    static func build(catalog: [Product]) async -> Built {
        let root = Entity()
        root.name = "store"
        var env: RealEnvironment?
        if let shell = try? await RealityHD.scene("grocery-store") {
            root.addChild(shell)
        } else {
            root.addChild(fallbackShell())
            await addFixtures(to: root)
        }
        env = try? RealityHD.environment(SunSky(), skybox: false)
        if let env { root.addChild(env.root) }
        var slots: [String: Entity] = [:]
        var protos: [String: Entity] = [:]
        for p in catalog {
            let proto: Entity
            if let e = protos[p.asset] { proto = e } else {
                proto = (try? await RealityHD.entity(p.asset, grabbable: false)) ?? placeholder(p)
                protos[p.asset] = proto
            }
            let slot = makeSlot(p, proto: proto)
            root.addChild(slot)
            slots[p.id] = slot
        }
        env?.illuminate(root)
        addLights(to: root)
        return Built(root: root, slots: slots, env: env)
    }

    /// Container named sku:<id> holding three facings, tappable and draggable.
    static func makeSlot(_ p: Product, proto: Entity) -> Entity {
        let slot = Entity()
        slot.name = skuPrefix + p.id
        slot.position = p.anchor - SIMD3(0, 0.12, 0)
        let face: Float = p.anchor.x > p.stand.x ? -1 : 1
        let b = proto.visualBounds(relativeTo: nil)
        let w = max(b.extents.z, 0.06) + 0.02
        for i in -1...1 {
            let c = proto.clone(recursive: true)
            c.position = SIMD3(0, -b.min.y, Float(i) * w)
            c.orientation = simd_quatf(angle: face > 0 ? .pi / 2 : -.pi / 2, axis: [0, 1, 0])
            slot.addChild(c)
        }
        let size = SIMD3<Float>(0.3, max(b.extents.y, 0.1) + 0.05, w * 3)
        slot.components.set(CollisionComponent(shapes: [.generateBox(size: size).offsetBy(translation: [0, size.y / 2, 0])]))
        slot.components.set(InputTargetComponent())
        slot.components.set(HoverEffectComponent())
        return slot
    }

    static func placeholder(_ p: Product) -> Entity {
        let hue = CGFloat(abs(p.id.hashValue % 360)) / 360
        let m = SimpleMaterial(color: UIColor(hue: hue, saturation: 0.55, brightness: 0.85, alpha: 1), roughness: 0.5, isMetallic: false)
        let e = ModelEntity(mesh: .generateBox(size: [0.08, 0.16, 0.06], cornerRadius: 0.006), materials: [m])
        e.position.y = 0.08
        let wrap = Entity()
        wrap.addChild(e)
        return wrap
    }

    static func addFixtures(to root: Entity) async {
        let gondola = try? await RealityHD.entity("grocery-gondola", grabbable: false)
        for x in StoreLayout.gondolaRows {
            for z in StoreLayout.sectionZ {
                let g = gondola?.clone(recursive: true) ?? fallbackGondola()
                g.position = [x, 0, z]
                g.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
                root.addChild(g)
            }
        }
        let checkout = (try? await RealityHD.entity("checkout-lane", grabbable: false)) ?? box([0.9, 0.9, 2.2], 0x3A3F45)
        checkout.position = StoreLayout.checkout
        root.addChild(checkout)
        if let cart = try? await RealityHD.entity("shopping-cart", grabbable: false) {
            for i in 0..<4 {
                let c = cart.clone(recursive: true)
                c.position = StoreLayout.entrance + SIMD3(-1.0, 0, Float(i) * 0.35)
                root.addChild(c)
            }
        }
    }

    static func fallbackGondola() -> Entity {
        let g = Entity()
        let len = StoreLayout.sectionLength, depth = StoreLayout.gondolaDepth
        let spine = box([len, 1.8, 0.04], 0xD9DCDF); spine.position.y = 0.9; g.addChild(spine)
        for y in StoreLayout.shelfLevels {
            let s = box([len - 0.02, 0.025, depth], 0xE6E8EA); s.position.y = y; g.addChild(s)
            for side: Float in [-1, 1] {
                let tag = box([len - 0.02, 0.035, 0.005], 0xF2D21B)
                tag.position = [0, y - 0.01, side * depth / 2]; g.addChild(tag)
            }
        }
        let base = box([len, 0.12, depth], 0x3B3F44); base.position.y = 0.06; g.addChild(base)
        return g
    }

    static func fallbackShell() -> Entity {
        let shell = Entity()
        let w: Float = 14, d: Float = 13, h: Float = 4.2
        let cx: Float = 0.5, cz: Float = -6
        let floor = box([w, 0.02, d], 0xCFCBC4, rough: 0.25); floor.position = [cx, -0.01, cz]; shell.addChild(floor)
        let ceil = box([w, 0.05, d], 0xF4F4F2); ceil.position = [cx, h, cz]; shell.addChild(ceil)
        for (pos, size) in [([cx, h / 2, cz - d / 2], [w, h, 0.1]), ([cx - w / 2, h / 2, cz], [0.1, h, d]),
                            ([cx + w / 2, h / 2, cz], [0.1, h, d]), ([cx, h / 2, 0.5], [w, h, 0.1])] as [([Float], [Float])] {
            let wall = box(SIMD3(size[0], size[1], size[2]), 0xEDEBE6); wall.position = SIMD3(pos[0], pos[1], pos[2]); shell.addChild(wall)
        }
        for x in stride(from: Float(-5), through: 6, by: 2) {
            for z in stride(from: Float(-1), through: -11, by: -2) {
                let m = UnlitMaterial(color: UIColor(white: 1, alpha: 1))
                let panel = ModelEntity(mesh: .generatePlane(width: 1.2, depth: 0.6), materials: [m])
                panel.position = [x, h - 0.03, z]
                panel.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
                shell.addChild(panel)
            }
        }
        return shell
    }

    static func addLights(to root: Entity) {
        for z in stride(from: Float(-2), through: -10, by: -4) {
            for x: Float in [-3, 1, 5] {
                let l = Entity()
                var p = PointLightComponent(color: .white, intensity: 26000, attenuationRadius: 9)
                p.attenuationFalloffExponent = 1.6
                l.components.set(p)
                l.position = [x, 3.8, z]
                root.addChild(l)
            }
        }
    }

    static func box(_ size: SIMD3<Float>, _ hex: UInt32, rough: Float = 0.6) -> ModelEntity {
        ModelEntity(mesh: .generateBox(size: size, cornerRadius: 0.004),
                    materials: [SimpleMaterial(color: UIColor(hex: hex), roughness: .float(rough), isMetallic: false)])
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
