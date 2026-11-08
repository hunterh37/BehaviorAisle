import Foundation

/// How full the store shelves are. Maps onto RealityHD `GroceryStore` stock params.
struct StoreDensity: Codable, Equatable, Sendable {
    /// Share of shelf slots holding stock, 0 empty ... 1 full.
    var fill: Float = 0.96
    /// Facings deep per slot, 1...6.
    var depth: Int = 4
    /// 0 loose gaps between facings ... 1 shoulder to shoulder.
    var packing: Float = 0.85
    /// Case packs on gondola tops and stocking carts in the back aisle.
    var overstock = false
    /// Facings per catalog SKU slot, 1...7.
    var skuFacings: Int = 3

    enum Preset: String, CaseIterable, Identifiable {
        case sparse, stocked, packed, overstock
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var density: StoreDensity {
            switch self {
            case .sparse: StoreDensity(fill: 0.45, depth: 2, packing: 0.4, overstock: false, skuFacings: 2)
            case .stocked: StoreDensity(fill: 0.9, depth: 4, packing: 0.75, overstock: false, skuFacings: 3)
            case .packed: StoreDensity(fill: 1, depth: 6, packing: 1, overstock: false, skuFacings: 5)
            case .overstock: StoreDensity(fill: 1, depth: 6, packing: 1, overstock: true, skuFacings: 7)
            }
        }
    }

    static let `default` = Preset.packed.density

    var preset: Preset? { Preset.allCases.first { $0.density == self } }

    static func load(_ d: UserDefaults = .standard) -> StoreDensity {
        guard let data = d.data(forKey: "storeDensity"),
              let v = try? JSONDecoder().decode(StoreDensity.self, from: data) else { return .default }
        return v.clamped
    }

    func save(_ d: UserDefaults = .standard) {
        d.set(try? JSONEncoder().encode(self), forKey: "storeDensity")
    }

    var clamped: StoreDensity {
        var c = self
        c.fill = min(max(fill, 0), 1)
        c.depth = min(max(depth, 1), 6)
        c.packing = min(max(packing, 0), 1)
        c.skuFacings = min(max(skuFacings, 1), 7)
        return c
    }
}
