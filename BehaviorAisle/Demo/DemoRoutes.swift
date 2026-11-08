#if DEBUG
import DicyaninStageDirector
import RealityKit
import SwiftUI

/// StageDirector routes for the X profile import flow. Uses a fixture profile + classifier result
/// so captures do not need X or OpenRouter keys.
enum DemoRoutes {
    @MainActor static func register(_ b: RouteBook, model: AppModel) {
        b.group("profile") { b in
            b.route("fetching", "Analysis sheet, scanner spinning", duration: 4) { t in
                model.mode = .heuristic
                model.importStage = .fetching
                model.showAnalysis = true
                await t.wait(1.2)
                await t.ready(); await t.wait(3); t.done()
            }
            b.route("reading", "Posts streaming in", duration: 5) { t in
                model.mode = .heuristic
                model.importStage = .fetching
                model.showAnalysis = true
                await t.wait(0.8)
                model.importedProfile = Fixture.profile
                model.importStage = .reading
                await t.wait(t.param("hold", default: 1.6))
                await t.ready(); await t.wait(3); t.done()
            }
            b.route("result", "Traits, affinity bars, likely-to-buy list", duration: 5) { t in
                model.mode = .heuristic
                model.importStage = .fetching
                model.showAnalysis = true
                await t.wait(0.6)
                model.importedProfile = Fixture.profile
                model.importStage = .reading
                await t.wait(2.6)
                model.importStage = .classifying
                await t.wait(t.param("classify", default: 1.2))
                if t.param("stop") == "classifying" { await t.ready(); await t.wait(3); t.done(); return }
                model.importedTraits = Fixture.traits
                model.importStage = .done
                await t.wait(2.0)
                await t.ready(); await t.wait(3); t.done()
            }
        }
        b.group("store") { b in
            b.route("shopper", "Imported shopper with thought cloud, close", duration: 6, tags: ["hero"]) { t in
                model.mode = .heuristic
                model.showCards = t.param("cards") == "1"
                model.showArcs = t.param("arcs") == "1"
                await t.openImmersive(StoreSpace.id)
                while model.store == nil || model.loadProgress != nil { await t.wait(0.3) }
                if t.param("window") != "1" { t.dismissWindow("control") }
                await model.spawnImported(Fixture.profile, Fixture.traits)
                guard let s = model.shoppers.last else { throw DemoError.missing }
                let dist = Float(t.param("dist", default: 2.6))
                let x = Float(t.param("x", default: 0))
                if t.param("walk") != "1" {
                    s.frozen = true
                    s.path = []
                    s.root.setPosition([x, 0, -dist], relativeTo: nil)
                    s.root.setOrientation(simd_quatf(angle: Float(t.param("yaw", default: 0)) * .pi / 180, axis: [0, 1, 0]), relativeTo: nil)
                    s.express(.smile)
                    s.look(at: [0, 1.6, 0])
                }
                await t.wait(t.param("settle", default: 6))
                await t.ready(); await t.wait(4); t.done()
            }
        }
    }
}

enum DemoError: Error { case missing }

enum Fixture {
    static let profile = TwitterProfile(
        handle: "maya_cooks", name: "Maya Ortiz",
        bio: "Home cook and Saturday farmers market regular. Sourdough nerd. Training for my second half marathon.",
        location: "Austin, TX", avatarUrl: nil, followers: 18_400,
        tweets: [
            "Market haul: heirloom tomatoes, lemons and the best romaine of the season",
            "Sourdough loaf #41. Open crumb finally. Butter and sea salt, nothing else",
            "Long run done, 14 miles. Greek yogurt, banana, honey. Every single Sunday",
            "Weeknight penne with olive oil, garlic and a lot of parmesan",
            "Cold brew at 6am or I am not a person",
            "Avocado toast is a personality and I am fine with that",
        ])

    static let traits = ProfileTraits(
        body: .init(gender: 0.05, age: 31, height: 0.55, weight: 0.4, muscle: 0.6,
                    african: 0.15, asian: 0.05, caucasian: 0.8, skinTone: 0.42, undertone: 0.45,
                    hairStyle: "curly", hairColor: "#2A1A10", eyeColor: "hazel",
                    facialHair: 0, freckles: 0.1, outfit: "casual", confidence: 0.9),
        affinity: ["produce": 0.95, "dairy": 0.75, "bakery": 0.85, "pantry": 0.8,
                   "snacks": 0.15, "beverages": 0.45, "frozen": 0.1, "household": 0.3],
        priceSensitivity: 0.35, basketSize: 7,
        wishlist: ["bread", "tomato", "yogurt", "avocado", "oil"],
        interests: ["home cooking", "sourdough", "farmers market", "running", "coffee"],
        summary: "Cooks from scratch, buys fresh produce and bakery weekly, protein after long runs.")
}
#endif
