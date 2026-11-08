import Foundation
import simd

/// Offline next-action model: category affinity, price, promo, eye level, basket complements, distance.
struct HeuristicPredictor: Predictor {
    var personas: [String: Persona] = Dictionary(uniqueKeysWithValues: Persona.all.map { ($0.id, $0) })

    func predict(_ req: PredictionRequest) async throws -> PredictionResult {
        rank(req, from: nil)
    }

    static let complements: [Category: Set<Category>] = [
        .produce: [.dairy, .pantry], .pantry: [.produce, .dairy], .snacks: [.beverages, .frozen],
        .beverages: [.snacks], .bakery: [.dairy], .dairy: [.bakery, .produce], .frozen: [.snacks],
    ]

    func rank(_ req: PredictionRequest, from position: SIMD3<Float>?) -> PredictionResult {
        let persona = personas[req.personaId] ?? Persona.all[0]
        let byId = Dictionary(uniqueKeysWithValues: req.catalog.map { ($0.id, $0) })
        let last = req.history.last.flatMap { byId[$0.itemId] }
        let viewed = Set(req.history.filter { $0.action == .view }.map(\.itemId))
        let inCart = Set(req.cart)
        let maxPrice = req.catalog.map(\.price).max() ?? 1
        var logits: [(String, Double)] = []
        for p in req.catalog {
            var s = (persona.affinity[p.category] ?? 0.2) * 2.2
            s -= persona.priceSensitivity * (p.price / maxPrice) * 1.4
            if p.onSale { s += 0.9 + persona.priceSensitivity * 0.6 }
            if (0.8...1.6).contains(p.anchor.y) { s += 0.25 }
            if let last, Self.complements[last.category]?.contains(p.category) == true { s += 0.35 }
            if viewed.contains(p.id) { s += 0.4 }
            if inCart.contains(p.id) { s -= 3 }
            if let position { s -= Double(simd_distance(position, p.stand)) * 0.06 }
            logits.append((p.id, s))
        }
        let fill = Double(req.cart.count) / Double(max(persona.basketSize, 1))
        logits.append((Prediction.checkoutId, -2.5 + 4.5 * fill))
        let m = logits.map(\.1).max() ?? 0
        let ex = logits.map { ($0.0, exp($0.1 - m)) }
        let z = ex.reduce(0) { $0 + $1.1 }
        let top = ex.map { ($0.0, $0.1 / z) }.sorted { $0.1 > $1.1 }.prefix(3)
        let preds = top.map { id, p -> Prediction in
            if id == Prediction.checkoutId { return Prediction(itemId: id, action: .checkout, p: p) }
            let item = byId[id]
            let buy = (persona.affinity[item?.category ?? .pantry] ?? 0.3) + (item?.onSale == true ? 0.3 : 0)
            return Prediction(itemId: id, action: buy > 0.55 ? .addToCart : .view, p: p)
        }
        return PredictionResult(predictions: preds, anomaly: anomaly(req, persona: persona, byId: byId), source: "heuristic")
    }

    /// Share of cart items in categories the persona rarely buys.
    func anomaly(_ req: PredictionRequest, persona: Persona, byId: [String: Product]) -> Double? {
        guard !req.cart.isEmpty else { return nil }
        let odd = req.cart.filter { (persona.affinity[byId[$0]?.category ?? .pantry] ?? 0) < 0.3 }.count
        return Double(odd) / Double(req.cart.count)
    }
}
