import Foundation
import Observation
import RealityKit
import simd
import HumanCore
import HumanKit

/// One simulated shopper: HumanHD body, persona, history, current predictions and a walk/pick state machine.
@MainActor
@Observable
final class ShopperAgent: Identifiable {
    struct Pick: Identifiable, Hashable {
        let id = UUID()
        let itemId: String
        let action: BehaviorAction
        let p: Double
        let rank: Int
        let source: String
    }

    enum Phase: Equatable { case thinking, walking, picking, checkingOut, done }

    let id: String
    let persona: Persona
    let root = Entity()
    var character: HumanCharacter?
    var history: [BehaviorEvent]
    var cart: [String] = []
    var predictions: [Prediction] = []
    var source = ""
    var anomaly: Double?
    var phase: Phase = .thinking
    var target: Prediction?
    /// Executed actions in order with the rank and probability they had when chosen.
    var log: [Pick] = []
    /// Heuristic top 3 for the same context, shown beside the live model to show what it adds.
    var baseline: [Prediction] = []
    var topHits: Int { log.filter { $0.rank == 0 }.count }
    var frozen = false
    /// Set for shoppers imported from an X profile.
    let spec: HumanSpec?
    var traits: ProfileTraits?
    var profile: TwitterProfile?
    @ObservationIgnored var cloud: ThoughtCloud?
    @ObservationIgnored var path: [SIMD3<Float>] = []
    @ObservationIgnored var timer: Float = 0
    @ObservationIgnored var requestId = 0
    @ObservationIgnored var rng: SplitMix

    static let walkSpeed: Float = 1.05

    init(persona: Persona, index: Int, spec: HumanSpec? = nil) {
        id = "\(persona.id)-\(index)"
        self.persona = persona
        self.spec = spec
        history = persona.seedHistory
        rng = SplitMix(seed: persona.skinSeed &+ UInt64(index) &* 977)
        root.name = "shopper:" + id
        root.position = StoreLayout.entrance + SIMD3(Float(index) * 0.5, 0, 0)
        root.components.set(CollisionComponent(shapes: [.generateCapsule(height: 1.75, radius: 0.3).offsetBy(translation: [0, 0.875, 0])]))
        root.components.set(InputTargetComponent())
        root.components.set(HoverEffectComponent())
    }

    var position: SIMD3<Float> { root.position(relativeTo: nil) }

    func loadBody() async {
        let spec = self.spec ?? HumanSpec.random(seed: persona.skinSeed)
        guard let c = try? await Human.make(spec, seed: persona.skinSeed) else {
            let m = SimpleMaterial(color: .init(hex: persona.color), roughness: 0.6, isMetallic: false)
            let cap = ModelEntity(mesh: .generateCylinder(height: 1.7, radius: 0.22), materials: [m])
            cap.position.y = 0.85
            root.addChild(cap)
            return
        }
        c.animator?.rootMotion = false
        root.addChild(c.entity)
        character = c
    }

    /// Picks the action to execute from the ranked list (sampled by p).
    func choose() -> Prediction? {
        guard !predictions.isEmpty else { return nil }
        let total = predictions.reduce(0) { $0 + $1.p }
        var r = rng.nextDouble() * total
        for p in predictions { r -= p.p; if r <= 0 { return p } }
        return predictions[0]
    }

    func walk(to stand: SIMD3<Float>) {
        path = StoreLayout.path(from: position, to: stand)
        phase = .walking
    }

    /// Advances movement. Returns true on arrival.
    func step(_ dt: Float) -> Bool {
        guard phase == .walking, !frozen, let next = path.first else {
            setSpeed(0)
            return false
        }
        var p = root.position
        let d = next - p
        let dist = simd_length(SIMD2(d.x, d.z))
        let move = Self.walkSpeed * dt
        if dist <= move {
            p = next
            path.removeFirst()
        } else {
            p += SIMD3(d.x, 0, d.z) / dist * move
        }
        root.position = p
        if dist > 0.01 { root.orientation = simd_quatf(angle: atan2(d.x, d.z), axis: [0, 1, 0]) }
        setSpeed(path.isEmpty ? 0 : Self.walkSpeed)
        return path.isEmpty
    }

    /// Writes the animator speed only on change; idle shoppers otherwise touch the animator every frame.
    private func setSpeed(_ v: Float) {
        guard let anim = character?.animator, anim.core.speed != v else { return }
        anim.core.speed = v
    }

    func look(at p: SIMD3<Float>?) { character?.animator?.look(atWorld: p) }

    func express(_ e: FacialExpression) { character?.animator?.core.expression = e }
}

/// Deterministic RNG.

