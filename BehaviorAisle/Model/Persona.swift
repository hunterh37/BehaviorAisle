import Foundation

/// A synthetic shopper profile: category affinity, price sensitivity and a seed history sent to the model.
struct Persona: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let affinity: [Category: Double]
    let priceSensitivity: Double
    let basketSize: Int
    let seedHistory: [BehaviorEvent]
    let skinSeed: UInt64
    let color: UInt32

    static let all: [Persona] = [
        Persona(id: "budget-parent", name: "Budget Parent",
                affinity: [.produce: 0.7, .dairy: 0.9, .bakery: 0.6, .pantry: 0.8, .snacks: 0.5, .beverages: 0.4, .frozen: 0.6, .household: 0.7],
                priceSensitivity: 0.9, basketSize: 8,
                seedHistory: [.init(.purchase, "milk"), .init(.purchase, "cereal"), .init(.view, "pizza"), .init(.purchase, "towels")],
                skinSeed: 11, color: 0x3FA7D6),
        Persona(id: "home-chef", name: "Home Chef",
                affinity: [.produce: 1.0, .dairy: 0.6, .bakery: 0.7, .pantry: 0.9, .snacks: 0.1, .beverages: 0.2, .frozen: 0.05, .household: 0.2],
                priceSensitivity: 0.2, basketSize: 7,
                seedHistory: [.init(.purchase, "oil"), .init(.purchase, "tomato"), .init(.view, "cheese"), .init(.purchase, "pasta")],
                skinSeed: 23, color: 0xE07A2E),
        Persona(id: "student", name: "Late-Night Student",
                affinity: [.produce: 0.1, .dairy: 0.2, .bakery: 0.3, .pantry: 0.5, .snacks: 1.0, .beverages: 0.9, .frozen: 0.9, .household: 0.05],
                priceSensitivity: 0.8, basketSize: 5,
                seedHistory: [.init(.purchase, "chips"), .init(.purchase, "soda"), .init(.view, "icecream")],
                skinSeed: 37, color: 0xB45CD6),
        Persona(id: "athlete", name: "Fitness Regular",
                affinity: [.produce: 1.0, .dairy: 0.8, .bakery: 0.2, .pantry: 0.5, .snacks: 0.05, .beverages: 0.6, .frozen: 0.1, .household: 0.1],
                priceSensitivity: 0.4, basketSize: 6,
                seedHistory: [.init(.purchase, "yogurt"), .init(.purchase, "banana"), .init(.purchase, "eggs"), .init(.view, "avocado")],
                skinSeed: 41, color: 0x3DBE7A),
        Persona(id: "host", name: "Party Host",
                affinity: [.produce: 0.5, .dairy: 0.5, .bakery: 0.8, .pantry: 0.4, .snacks: 0.9, .beverages: 1.0, .frozen: 0.7, .household: 0.4],
                priceSensitivity: 0.3, basketSize: 9,
                seedHistory: [.init(.purchase, "water"), .init(.view, "chips"), .init(.purchase, "cookies")],
                skinSeed: 59, color: 0xE4C22E),
    ]
}

enum BehaviorAction: String, Codable, Sendable { case view, addToCart = "add_to_cart", purchase, checkout }

struct BehaviorEvent: Codable, Sendable, Hashable {
    var action: BehaviorAction
    var itemId: String
    init(_ action: BehaviorAction, _ itemId: String) { self.action = action; self.itemId = itemId }
}
