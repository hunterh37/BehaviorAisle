import Foundation

/// One predicted destination with the profile signal that explains it.
struct IntentLine: Identifiable, Hashable, Sendable {
    var id: String { itemId }
    let itemId: String
    let name: String
    let p: Double
    let action: BehaviorAction
    /// Profile interest or signal that drives the prediction, e.g. "sourdough".
    let reason: String
    /// "Aisle 2 · Bakery" or "Checkout".
    let place: String
}

/// Maps ranked predictions to readable "interest -> item -> aisle" lines.
enum IntentExplainer {
    static let categoryWords: [Category: [String]] = [
        .produce: ["farmers", "market", "vegan", "salad", "garden", "plant", "smoothie", "produce"],
        .dairy: ["protein", "running", "yogurt", "cheese", "latte", "gym"],
        .bakery: ["sourdough", "bread", "baking", "croissant", "bakery"],
        .pantry: ["cooking", "cook", "chef", "recipe", "pasta", "coffee", "kitchen"],
        .snacks: ["gaming", "movie", "snack", "netflix", "stream"],
        .beverages: ["coffee", "party", "drinks", "festival"],
        .frozen: ["late night", "busy", "pizza"],
        .household: ["parent", "kids", "home", "clean"],
    ]

    static func explain(_ preds: [Prediction], traits: ProfileTraits?, catalog: [Product]) -> [IntentLine] {
        preds.sorted { $0.p > $1.p }.map { pred in
            if pred.itemId == Prediction.checkoutId {
                return IntentLine(itemId: pred.itemId, name: "Checkout", p: pred.p, action: pred.action,
                                  reason: "basket full", place: "Checkout")
            }
            let product = catalog.first { $0.id == pred.itemId }
            let name = product?.name ?? pred.itemId
            return IntentLine(itemId: pred.itemId, name: name, p: pred.p, action: pred.action,
                              reason: product.map { reason(for: $0, traits: traits) } ?? "browsing",
                              place: product.map(place) ?? "")
        }
    }

    /// Interest tag whose words match the product name or category; wishlist and affinity as fallback.
    static func reason(for p: Product, traits: ProfileTraits?) -> String {
        guard let t = traits else { return "\(p.category.label.lowercased()) habit" }
        let name = p.name.lowercased()
        let words = categoryWords[p.category] ?? []
        if let hit = t.interests.first(where: { tag in
            let tag = tag.lowercased()
            return name.split(separator: " ").contains { tag.contains($0) } || words.contains { tag.contains($0) }
        }) { return hit }
        if t.wishlist.contains(p.id) { return "in their posts" }
        if (t.affinity[p.category.rawValue] ?? 0) >= 0.6 { return "loves \(p.category.label.lowercased())" }
        return "nearby"
    }

    /// Aisle number (1...5, left to right) from the walk-to point, plus category.
    static func place(_ p: Product) -> String {
        let i = StoreLayout.aisles.enumerated().min { abs($0.1 - p.stand.x) < abs($1.1 - p.stand.x) }?.0 ?? 0
        return "Aisle \(i + 1) · \(p.category.label)"
    }
}
