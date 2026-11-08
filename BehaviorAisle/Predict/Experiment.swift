import Foundation
import simd

/// Deterministic 64-bit RNG (SplitMix64).
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func nextDouble() -> Double { Double(next() >> 11) / Double(1 << 53) }
    /// Standard normal (Box-Muller).
    mutating func gaussian() -> Double {
        let u = max(nextDouble(), 1e-12), v = nextDouble()
        return sqrt(-2 * log(u)) * cos(2 * .pi * v)
    }
}

/// Headless experiments behind the paper: counterfactual what-if, next-action accuracy with baselines
/// and ablations, and anomaly detection AUROC. All run on the heuristic model; the same harness accepts
/// BehaviorGPT results once they are logged.
enum Experiment {
    struct Trip: Sendable {
        var events: [BehaviorEvent] = []
        var cart: [String] = []
        var meters: Float = 0
        /// (context before the step, chosen action) pairs for next-action evaluation.
        var steps: [(history: [BehaviorEvent], cart: [String], position: SIMD3<Float>, truth: Prediction)] = []
    }

    /// One shopper walks `maxSteps` sampled actions from `model`'s full distribution.
    static func trip(_ persona: Persona, catalog: [Product], model: HeuristicPredictor, maxSteps: Int = 14, rng: inout SplitMix) -> Trip {
        let catalog = catalog.filter(\.inStock)
        var m = model
        m.topK = catalog.count + 1
        var t = Trip()
        var pos = StoreLayout.entrance
        var history = persona.seedHistory
        for _ in 0..<maxSteps {
            let r = m.rank(PredictionRequest(personaId: persona.id, history: history, cart: t.cart, catalog: catalog), from: pos)
            var x = rng.nextDouble() * r.predictions.reduce(0) { $0 + $1.p }
            var pick = r.predictions[0]
            for p in r.predictions { x -= p.p; if x <= 0 { pick = p; break } }
            t.steps.append((history, t.cart, pos, pick))
            let dest = pick.itemId == Prediction.checkoutId ? StoreLayout.checkoutStand
                : (catalog.first { $0.id == pick.itemId }?.stand ?? pos)
            t.meters += simd_distance(pos, dest)
            pos = dest
            if pick.action == .checkout { break }
            let e = BehaviorEvent(pick.action, pick.itemId)
            history.append(e)
            t.events.append(e)
            if pick.action == .addToCart { t.cart.append(pick.itemId) }
        }
        return t
    }

    // MARK: Counterfactual what-if

    struct Effect: Codable, Sendable, Hashable {
        var itemId: String
        var base: Double
        var variant: Double
        /// Mean paired difference in carts per 100 shoppers and its 95% CI half-width.
        var delta: Double
        var ci: Double
        var relative: Double { base > 0 ? delta / base : 0 }
    }

    struct WhatIf: Codable, Sendable {
        var effects: [Effect]
        var metersBase: Double
        var metersVariant: Double
        var basketBase: Double
        var basketVariant: Double
        var replicates: Int
        var shoppers: Int
        /// Revenue per 100 shoppers (sale items at 80% of price) and the paired change with its 95% CI.
        var revenueBase = 0.0
        var revenueDelta = 0.0
        var revenueCI = 0.0
        /// Discount given away on sale items per 100 shoppers in the variant.
        var promoCost = 0.0
        /// Gross margin per 100 shoppers and the paired change with its 95% CI.
        var marginBase = 0.0
        var marginDelta = 0.0
        var marginCI = 0.0

        /// Margin return per discount dollar; nil when no discount was given.
        var promoROI: Double? { promoCost > 0.01 ? marginDelta / promoCost : nil }
        /// Verdict scale: shoppers per store per week and stores in the chain.
        static let shoppersPerWeek = 12_000.0
        static let chainStores = 500.0
        var marginPerStoreWeek: Double { marginDelta / 100 * Self.shoppersPerWeek }
        var marginCIPerStoreWeek: Double { marginCI / 100 * Self.shoppersPerWeek }
        var marginChainYear: Double { marginPerStoreWeek * Self.chainStores * 52 }
        var significant: Bool { abs(marginDelta) > marginCI }

        /// Units gained by `item` and units lost by same-category SKUs (significant changes only), per 100 shoppers.
        func netLift(_ item: String, catalog: [Product]) -> (gain: Double, cannibal: Double, losers: [Effect]) {
            let cat = catalog.first { $0.id == item }?.category
            let gain = effects.first { $0.itemId == item }?.delta ?? 0
            let losers = effects.filter { e in
                e.itemId != item && e.delta < -e.ci && catalog.first { $0.id == e.itemId }?.category == cat
            }
            return (gain, losers.reduce(0) { $0 + $1.delta }, losers)
        }

        /// Stock-out: share of the item's lost units recaptured by other SKUs; the rest walked away.
        func recapture(_ item: String) -> (lost: Double, recaptured: Double) {
            let lost = effects.first { $0.itemId == item }.map { -$0.delta } ?? 0
            let rec = effects.filter { $0.itemId != item && $0.delta > 0 }.reduce(0) { $0 + $1.delta }
            return (lost, min(rec, lost))
        }
    }

    /// Paired design: each replicate runs the same seeds on both layouts, so the difference isolates the change.
    static func whatIf(base: [Product], variant: [Product], replicates: Int = 20, shoppers: Int = 50, model: HeuristicPredictor = .init()) -> WhatIf {
        let ids = base.map(\.id)
        var diffs: [String: [Double]] = [:], bases: [String: [Double]] = [:]
        var mb = 0.0, mv = 0.0, bb = 0.0, bv = 0.0
        var revB: [Double] = [], revD: [Double] = [], promo = 0.0
        var marB: [Double] = [], marD: [Double] = []
        func price(_ p: Product) -> Double { p.onSale ? p.price * 0.8 : p.price }
        for r in 0..<replicates {
            var cb: [String: Double] = [:], cv: [String: Double] = [:]
            for i in 0..<shoppers {
                let persona = Persona.all[i % Persona.all.count]
                let seed = UInt64(r * 10_007 + i) &* 2_654_435_761
                var r1 = SplitMix(seed: seed), r2 = SplitMix(seed: seed)
                let a = trip(persona, catalog: base, model: model, rng: &r1)
                let b = trip(persona, catalog: variant, model: model, rng: &r2)
                for c in a.cart { cb[c, default: 0] += 1 }
                for c in b.cart { cv[c, default: 0] += 1 }
                mb += Double(a.meters); mv += Double(b.meters)
                bb += Double(a.cart.count); bv += Double(b.cart.count)
            }
            let scale = 100 / Double(shoppers)
            let rb = base.reduce(0) { $0 + (cb[$1.id] ?? 0) * price($1) } * scale
            let rv = variant.reduce(0) { $0 + (cv[$1.id] ?? 0) * price($1) } * scale
            revB.append(rb); revD.append(rv - rb)
            let gb = base.reduce(0) { $0 + (cb[$1.id] ?? 0) * $1.unitMargin } * scale
            let gv = variant.reduce(0) { $0 + (cv[$1.id] ?? 0) * $1.unitMargin } * scale
            marB.append(gb); marD.append(gv - gb)
            promo += variant.filter(\.onSale).reduce(0) { $0 + (cv[$1.id] ?? 0) * $1.price * 0.2 } * scale
            for id in ids {
                diffs[id, default: []].append(((cv[id] ?? 0) - (cb[id] ?? 0)) * scale)
                bases[id, default: []].append((cb[id] ?? 0) * scale)
            }
        }
        let n = Double(replicates * shoppers)
        let effects = ids.map { id -> Effect in
            let d = diffs[id] ?? [], b = bases[id] ?? []
            let (md, ci) = meanCI(d)
            let mbase = b.reduce(0, +) / Double(max(b.count, 1))
            return Effect(itemId: id, base: mbase, variant: mbase + md, delta: md, ci: ci)
        }.sorted { abs($0.delta) > abs($1.delta) }
        let (rd, rci) = meanCI(revD)
        let (gd, gci) = meanCI(marD)
        return WhatIf(effects: effects, metersBase: mb / n, metersVariant: mv / n, basketBase: bb / n, basketVariant: bv / n,
                      replicates: replicates, shoppers: shoppers,
                      revenueBase: revB.reduce(0, +) / Double(max(revB.count, 1)), revenueDelta: rd, revenueCI: rci,
                      promoCost: promo / Double(max(replicates, 1)),
                      marginBase: marB.reduce(0, +) / Double(max(marB.count, 1)), marginDelta: gd, marginCI: gci)
    }

    static func meanCI(_ x: [Double]) -> (Double, Double) {
        guard x.count > 1 else { return (x.first ?? 0, 0) }
        let m = x.reduce(0, +) / Double(x.count)
        let v = x.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(x.count - 1)
        return (m, 1.96 * sqrt(v / Double(x.count)))
    }

    // MARK: Next-action accuracy

    struct Score: Codable, Sendable, Hashable {
        var name: String
        var hit1: Double
        var hit3: Double
        var mrr: Double
        var n: Int
    }

    /// Ground-truth shoppers are the heuristic with each persona's category affinity perturbed by N(0, sigma),
    /// so the predictor never sees the true preferences. Scores rank the true next action.
    static func accuracy(sigma: Double = 0.25, tripsPerPersona: Int = 40, seed: UInt64 = 7) -> [Score] {
        let catalog = Catalog.laidOut()
        var rng = SplitMix(seed: seed)
        var samples: [(Persona, [BehaviorEvent], [String], SIMD3<Float>, Prediction)] = []
        for persona in Persona.all {
            for _ in 0..<tripsPerPersona {
                var truth = HeuristicPredictor()
                for c in Category.allCases { truth.affinityNoise[c] = rng.gaussian() * sigma }
                let t = trip(persona, catalog: catalog, model: truth, rng: &rng)
                for s in t.steps { samples.append((persona, s.history, s.cart, s.position, s.truth)) }
            }
        }
        // Popularity baseline: frequency of each item over all samples (fit on the data, so it is optimistic).
        var freq: [String: Int] = [:]
        for s in samples { freq[s.4.itemId, default: 0] += 1 }
        let popular = freq.sorted { $0.value > $1.value }.map(\.key)

        func score(_ name: String, _ ranker: (Persona, [BehaviorEvent], [String], SIMD3<Float>) -> [String]) -> Score {
            var h1 = 0.0, h3 = 0.0, rr = 0.0
            for s in samples {
                let ranked = ranker(s.0, s.1, s.2, s.3)
                if let i = ranked.firstIndex(of: s.4.itemId) {
                    if i == 0 { h1 += 1 }
                    if i < 3 { h3 += 1 }
                    rr += 1 / Double(i + 1)
                }
            }
            let n = Double(samples.count)
            return Score(name: name, hit1: h1 / n, hit3: h3 / n, mrr: rr / n, n: samples.count)
        }

        func model(_ m: HeuristicPredictor) -> (Persona, [BehaviorEvent], [String], SIMD3<Float>) -> [String] {
            var m = m
            m.topK = catalog.count + 1
            return { p, h, c, pos in
                m.rank(PredictionRequest(personaId: p.id, history: h, cart: c, catalog: catalog), from: pos).predictions.map(\.itemId)
            }
        }

        var out: [Score] = []
        var shuffle = SplitMix(seed: seed &+ 1)
        let ids = catalog.map(\.id) + [Prediction.checkoutId]
        out.append(score("Random") { _, _, _, _ in
            var a = ids
            for i in stride(from: a.count - 1, to: 0, by: -1) { a.swapAt(i, Int(shuffle.next() % UInt64(i + 1))) }
            return a
        })
        out.append(score("Popularity") { _, _, cart, _ in popular.filter { !cart.contains($0) } })
        out.append(score("Full model", model(HeuristicPredictor())))
        for term in HeuristicPredictor.Term.allCases {
            var m = HeuristicPredictor()
            m.ablate = [term]
            out.append(score("- \(term.rawValue)", model(m)))
        }
        return out
    }

    // MARK: Anomaly detection

    /// Normal carts come from the persona; anomalous carts come from a different persona but are scored
    /// against the claimed one (a stolen card or shared account). Returns AUROC of the anomaly score.
    static func anomalyAUROC(trips: Int = 60, seed: UInt64 = 11) -> (auroc: Double, n: Int) {
        let catalog = Catalog.laidOut()
        let model = HeuristicPredictor()
        let byId = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        var rng = SplitMix(seed: seed)
        var pos: [Double] = [], neg: [Double] = []
        for (k, persona) in Persona.all.enumerated() {
            let other = Persona.all[(k + 2) % Persona.all.count]
            for _ in 0..<trips {
                let a = trip(persona, catalog: catalog, model: model, rng: &rng)
                let b = trip(other, catalog: catalog, model: model, rng: &rng)
                func s(_ cart: [String]) -> Double? {
                    model.anomaly(PredictionRequest(personaId: persona.id, history: [], cart: cart, catalog: catalog), persona: persona, byId: byId)
                }
                if let x = s(a.cart) { neg.append(x) }
                if let x = s(b.cart) { pos.append(x) }
            }
        }
        var wins = 0.0
        for p in pos { for n in neg { wins += p > n ? 1 : p == n ? 0.5 : 0 } }
        return (wins / Double(max(pos.count * neg.count, 1)), pos.count + neg.count)
    }
}
