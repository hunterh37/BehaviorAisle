import Foundation
import simd

/// Store geometry in meters. Viewer stands at the origin facing -Z, at the front cross aisle.
/// Matches docs/scenes/grocery-store.md in RealityHD: gondola rows at x = -3,-1,1,3, aisles at x = -4,-2,0,2,4, runs z -3...-10.
enum StoreLayout {
    static let gondolaRows: [Float] = [-3, -1, 1, 3]
    static let aisles: [Float] = [-4, -2, 0, 2, 4]
    static let runStart: Float = -3
    static let runEnd: Float = -10
    static let frontCross: Float = -1.8
    static let backCross: Float = -10.8
    static let sectionLength: Float = 1.2
    static let gondolaDepth: Float = 0.9
    static let shelfLevels: [Float] = [0.15, 0.55, 0.95, 1.35]
    static let entrance = SIMD3<Float>(-4, 0, -1.2)
    static let checkout = SIMD3<Float>(4.8, 0, -1.5)
    static let checkoutStand = SIMD3<Float>(4, 0, -1.5)
    static let bounds = (min: SIMD2<Float>(-6, -12), max: SIMD2<Float>(7, 0))

    /// Section centers along one gondola run.
    static var sectionZ: [Float] {
        stride(from: runStart - sectionLength / 2, through: runEnd + sectionLength / 2, by: -sectionLength).map { $0 }
    }

    /// Category per gondola face, front to back. Index = row * 2 + (side < 0 ? 0 : 1).
    static let faceCategories: [Category] = [.produce, .pantry, .pantry, .snacks, .beverages, .bakery, .dairy, .frozen]

    /// Assigns each product a shelf slot on the face for its category, eye level first.
    static func place(_ products: [Product]) -> [Product] {
        var used: [Int: Int] = [:]
        let levelOrder = [2, 1, 3, 0]
        return products.map { p in
            var q = p
            let face = faceCategories.firstIndex(of: p.category) ?? faceForOverflow(p.category)
            let n = used[face, default: 0]
            used[face] = n + 1
            let row = face / 2
            let side: Float = face % 2 == 0 ? -1 : 1
            let zs = sectionZ
            let z = zs[n % zs.count]
            let level = shelfLevels[levelOrder[(n / zs.count) % levelOrder.count]]
            let x = gondolaRows[row] + side * gondolaDepth / 2
            q.anchor = SIMD3(x, level + 0.12, z)
            q.stand = SIMD3(gondolaRows[row] + side * 1.0, 0, z)
            return q
        }
    }

    static func faceForOverflow(_ c: Category) -> Int {
        switch c {
        case .household: return 5
        default: return 1
        }
    }

    /// Walk path on the aisle grid from `a` to `b` (both on floor).
    static func path(from a: SIMD3<Float>, to b: SIMD3<Float>) -> [SIMD3<Float>] {
        if abs(a.x - b.x) < 0.3 { return [b] }
        let cross = abs(a.z - frontCross) + abs(b.z - frontCross) <= abs(a.z - backCross) + abs(b.z - backCross)
            ? frontCross : backCross
        return [SIMD3(a.x, 0, cross), SIMD3(b.x, 0, cross), b]
    }

    static func length(_ pts: [SIMD3<Float>], from a: SIMD3<Float>) -> Float {
        var d: Float = 0, p = a
        for q in pts { d += simd_distance(p, q); p = q }
        return d
    }
}
