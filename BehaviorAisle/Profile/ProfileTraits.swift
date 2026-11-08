import Foundation

/// Public X/Twitter profile as returned by the proxy `/twitter` route.
struct TwitterProfile: Codable, Sendable, Hashable {
    var handle: String
    var name: String
    var bio: String
    var location: String?
    var avatarUrl: String?
    var followers: Int?
    var tweets: [String]
}

/// Classifier output from the proxy `/classify` route (OpenRouter LLM, JSON schema).
/// Body traits come from the profile photo; interests and wishlist from bio and posts.
struct ProfileTraits: Codable, Sendable, Hashable {
    struct Body: Codable, Sendable, Hashable {
        /// 0 female ... 1 male.
        var gender: Double
        var age: Double
        /// 0...1 each.
        var height: Double
        var weight: Double
        var muscle: Double
        /// Ancestry blend weights for the body morph, 0...1 each.
        var african: Double
        var asian: Double
        var caucasian: Double
        /// 0 fair ... 1 deep.
        var skinTone: Double
        /// -0.3 cool ... 0.7 warm/olive.
        var undertone: Double
        /// bald, buzz, short, crop, bob, long, wavy, ponytail, bun, curly, afro, braids, locs.
        var hairStyle: String
        /// "#RRGGBB".
        var hairColor: String
        /// brown, darkBrown, hazel, green, blue, grey.
        var eyeColor: String
        /// 0 clean shaven ... 1.5 full stubble.
        var facialHair: Double
        var freckles: Double
        /// casual, smart, business, winter, outdoor, athletic, biker, summerDress.
        var outfit: String
        /// 0...1, low when the avatar is not a photo of a person.
        var confidence: Double
    }

    var body: Body
    /// Category raw value -> 0...1.
    var affinity: [String: Double]
    var priceSensitivity: Double
    var basketSize: Int
    /// Catalog ids, most wanted first.
    var wishlist: [String]
    /// Short interest tags shown during analysis.
    var interests: [String]
    var summary: String
}

extension ProfileTraits {
    /// Persona for the predictor loop. Seed history = viewing the top wishlist items.
    func persona(for profile: TwitterProfile) -> Persona {
        var aff: [Category: Double] = [:]
        for c in Category.allCases { aff[c] = min(1, max(0, affinity[c.rawValue] ?? 0.3)) }
        // FNV-1a: stable across launches (hashValue is not).
        let seed = profile.handle.lowercased().utf8.reduce(UInt64(0xcbf29ce484222325)) { ($0 ^ UInt64($1)) &* 0x100000001b3 } | 1
        let palette: [UInt32] = [0x1D9BF0, 0xF91880, 0x00BA7C, 0xFFD400, 0x7856FF]
        return Persona(id: "x-" + profile.handle.lowercased(), name: "@" + profile.handle,
                       affinity: aff, priceSensitivity: min(1, max(0, priceSensitivity)),
                       basketSize: min(14, max(3, basketSize)),
                       seedHistory: wishlist.prefix(3).map { BehaviorEvent(.view, $0) },
                       skinSeed: seed, color: palette[Int(seed % UInt64(palette.count))])
    }

    /// Offline fallback: keyword scan of bio + posts. Body stays nil so the agent uses a seeded random human.
    static func heuristic(_ p: TwitterProfile, catalog: [Product]) -> ProfileTraits {
        let text = ([p.bio] + p.tweets).joined(separator: " ").lowercased()
        let keys: [Category: [String]] = [
            .produce: ["vegan", "salad", "garden", "farmers", "plant", "smoothie"],
            .dairy: ["cheese", "latte", "yogurt", "protein"],
            .bakery: ["bread", "sourdough", "baking", "croissant"],
            .pantry: ["cook", "chef", "recipe", "pasta", "coffee", "kitchen"],
            .snacks: ["gaming", "stream", "movie", "snack", "chips", "netflix"],
            .beverages: ["party", "drinks", "soda", "beer", "dj", "festival"],
            .frozen: ["pizza", "late night", "icecream", "ice cream", "busy"],
            .household: ["parent", "mom", "dad", "kids", "home", "clean"],
        ]
        var aff: [String: Double] = [:]
        var tags: [String] = []
        for (c, words) in keys {
            let hits = words.filter { text.contains($0) }
            aff[c.rawValue] = min(1, 0.25 + Double(hits.count) * 0.25)
            tags += hits.prefix(1)
        }
        let ranked = catalog.sorted { (aff[$0.category.rawValue] ?? 0) > (aff[$1.category.rawValue] ?? 0) }
        return ProfileTraits(body: .neutral, affinity: aff, priceSensitivity: 0.5, basketSize: 6,
                             wishlist: ranked.prefix(5).map(\.id), interests: Array(tags.prefix(5)),
                             summary: "Keyword match (offline)")
    }
}

extension ProfileTraits.Body {
    static let neutral = Self(gender: 0.5, age: 30, height: 0.5, weight: 0.5, muscle: 0.5,
                              african: 0.33, asian: 0.33, caucasian: 0.33, skinTone: 0.4, undertone: 0.2,
                              hairStyle: "short", hairColor: "#2A1A10", eyeColor: "brown",
                              facialHair: 0, freckles: 0, outfit: "casual", confidence: 0)
}
