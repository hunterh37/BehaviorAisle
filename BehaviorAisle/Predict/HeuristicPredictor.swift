import Foundation
import simd

/// Offline next-action model: category affinity, price, promo, eye level, basket complements, distance.
struct HeuristicPredictor: Predictor {
    var personas: [String: Persona] = Dictionary(uniqueKeysWithValues: Persona.all.map { ($0.id, $0) })
    /// Model terms; removing one gives an ablation.
    enum Term: String, CaseIterable, Sendable { case affinity, price, promo, eyeLevel, complements, revisit, distance, fitted }
    var ablate: Set<Term> = []
    /// Number of ranked actions returned (3 in the app; the full list for evaluation).
    var topK = 3
    /// Overrides persona affinity (simulated ground-truth shoppers).
    var affinityNoise: [Category: Double] = [:]
    /// Item popularity and co-occurrence fitted on real Instacart baskets (tools/validate_instacart.py). Nil in tests.
    var fitted: FittedTerms? = FittedTerms.bundled
    /// Scale of the fitted log terms against the persona terms.
    var fitWeight = 0.5

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
            var s = 0.0
            if !ablate.contains(.affinity) { s += ((persona.affinity[p.category] ?? 0.2) + (affinityNoise[p.category] ?? 0)) * 2.2 }
            if !ablate.contains(.price) { s -= persona.priceSensitivity * (p.price / maxPrice) * 1.4 }
            if p.onSale, !ablate.contains(.promo) { s += 0.9 + persona.priceSensitivity * 0.6 }
            if (0.8...1.6).contains(p.anchor.y), !ablate.contains(.eyeLevel) { s += 0.25 }
            if !ablate.contains(.complements), let last, Self.complements[last.category]?.contains(p.category) == true { s += 0.35 }
            if viewed.contains(p.id), !ablate.contains(.revisit) { s += 0.4 }
            if inCart.contains(p.id) { s -= 3 }
            if let fitted, !ablate.contains(.fitted) { s += fitWeight * fitted.score(p.id, cart: req.cart) }
            if let position, !ablate.contains(.distance) { s -= Double(simd_distance(position, p.stand)) * 0.06 }
            logits.append((p.id, s))
        }
        let fill = Double(req.cart.count) / Double(max(persona.basketSize, 1))
        logits.append((Prediction.checkoutId, -2.5 + 4.5 * fill))
        let m = logits.map(\.1).max() ?? 0
        let ex = logits.map { ($0.0, exp($0.1 - m)) }
        let z = ex.reduce(0) { $0 + $1.1 }
        let top = ex.map { ($0.0, $0.1 / z) }.sorted { $0.1 > $1.1 }.prefix(topK)
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

/// Log popularity and log P(next | item in cart), fitted on the Instacart train split.
struct FittedTerms: Codable, Sendable {
    var source: String
    var w_co: Double
    var logpop: [String: Double]
    var cond: [String: [String: Double]]

    static let bundled: FittedTerms? = Bundle.main.url(forResource: "fitted_terms", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode(FittedTerms.self, from: $0) }

    func score(_ id: String, cart: [String]) -> Double {
        let pop = logpop[id] ?? (logpop.values.min() ?? 0)
        let co = cart.compactMap { cond[$0]?[id] }
        return pop + (co.isEmpty ? 0 : w_co * co.reduce(0, +) / Double(co.count))
    }
}
