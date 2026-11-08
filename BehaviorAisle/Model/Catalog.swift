import Foundation
import simd

enum Category: String, Codable, Sendable, CaseIterable {
    case produce, dairy, bakery, pantry, snacks, beverages, frozen, household

    var label: String { rawValue.capitalized }
}

/// One SKU. `asset` is a RealityHD catalog id; `anchor` is the shelf-front point, `stand` the aisle point a shopper walks to.
struct Product: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let asset: String
    let category: Category
    var price: Double
    var anchor: SIMD3<Float> = .zero
    var stand: SIMD3<Float> = .zero
    var onSale = false
    var inStock = true
    /// Gross margin share of shelf price by category (US grocery averages).
    var marginRate: Double {
        switch category {
        case .produce: 0.35
        case .dairy: 0.25
        case .bakery: 0.45
        case .pantry: 0.30
        case .snacks: 0.40
        case .beverages: 0.30
        case .frozen: 0.28
        case .household: 0.32
        }
    }
    /// Margin per unit sold at the current price (sale is 20% off shelf, cost unchanged).
    var unitMargin: Double { onSale ? price * (marginRate - 0.2) : price * marginRate }
}

enum Catalog {
    /// Base SKUs before layout. Prices in USD.
    static let base: [Product] = [
        Product(id: "banana", name: "Bananas", asset: "banana-bunch", category: .produce, price: 1.49),
        Product(id: "apple", name: "Red Apples", asset: "apple", category: .produce, price: 0.89),
        Product(id: "orange", name: "Navel Oranges", asset: "orange", category: .produce, price: 0.99),
        Product(id: "avocado", name: "Avocado", asset: "avocado", category: .produce, price: 1.79),
        Product(id: "broccoli", name: "Broccoli", asset: "broccoli-head", category: .produce, price: 2.29),
        Product(id: "lettuce", name: "Romaine", asset: "lettuce-head", category: .produce, price: 2.49),
        Product(id: "tomato", name: "Roma Tomatoes", asset: "roma-tomato", category: .produce, price: 0.59),
        Product(id: "lemon", name: "Lemons", asset: "lemon", category: .produce, price: 0.69),
        Product(id: "milk", name: "Whole Milk 1 gal", asset: "milk-jug", category: .dairy, price: 4.29),
        Product(id: "yogurt", name: "Greek Yogurt", asset: "yogurt-cup", category: .dairy, price: 1.39),
        Product(id: "cheese", name: "Cheddar Block", asset: "cheese-block", category: .dairy, price: 5.49),
        Product(id: "eggs", name: "Eggs, dozen", asset: "egg-carton", category: .dairy, price: 3.99),
        Product(id: "butter", name: "Butter", asset: "butter-block", category: .dairy, price: 4.79),
        Product(id: "bread", name: "Sourdough Loaf", asset: "bread-loaf", category: .bakery, price: 5.99),
        Product(id: "cereal", name: "Oat Cereal", asset: "cereal-box", category: .pantry, price: 4.49),
        Product(id: "pasta", name: "Penne", asset: "pasta-box", category: .pantry, price: 1.99),
        Product(id: "soup", name: "Tomato Soup", asset: "canned-soup", category: .pantry, price: 2.19),
        Product(id: "oil", name: "Olive Oil", asset: "olive-oil-bottle", category: .pantry, price: 9.99),
        Product(id: "ketchup", name: "Ketchup", asset: "ketchup-bottle", category: .pantry, price: 3.29),
        Product(id: "pb", name: "Peanut Butter", asset: "peanut-butter-jar", category: .pantry, price: 3.79),
        Product(id: "rice", name: "Jasmine Rice", asset: "rice-bag", category: .pantry, price: 6.49),
        Product(id: "coffee", name: "Ground Coffee", asset: "coffee-bag", category: .pantry, price: 10.99),
        Product(id: "chips", name: "Potato Chips", asset: "potato-chip-bag", category: .snacks, price: 3.99),
        Product(id: "cookies", name: "Choc Chip Cookies", asset: "cookie-pack", category: .snacks, price: 3.49),
        Product(id: "chocolate", name: "Dark Chocolate", asset: "chocolate-bar", category: .snacks, price: 2.99),
        Product(id: "soda", name: "Cola Can", asset: "soda-can", category: .beverages, price: 1.25),
        Product(id: "water", name: "Water 24 pk", asset: "water-bottle-pack", category: .beverages, price: 5.99),
        Product(id: "juice", name: "Orange Juice", asset: "juice-carton", category: .beverages, price: 3.89),
        Product(id: "pizza", name: "Frozen Pizza", asset: "frozen-pizza-box", category: .frozen, price: 6.99),
        Product(id: "icecream", name: "Ice Cream Pint", asset: "ice-cream-pint", category: .frozen, price: 4.99),
        Product(id: "spray", name: "Cleaning Spray", asset: "cleaning-spray", category: .household, price: 4.29),
        Product(id: "towels", name: "Paper Towels", asset: "paper-towel-pack", category: .household, price: 8.99),
    ]

    /// Base SKUs placed into the store layout.
    static func laidOut() -> [Product] { StoreLayout.place(base) }
}
