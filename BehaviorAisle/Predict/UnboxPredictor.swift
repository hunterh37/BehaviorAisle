import Foundation

/// Calls BehaviorGPT (Unbox AI /shop/recommend) directly from the app. Port of proxy/core.mjs.
/// BehaviorGPT returns a ranked list without probabilities; p is a rank prior blended with
/// in-store signals (sale sign, eye-level shelf) that the API has no input for.
struct UnboxPredictor: Predictor {
    var apiKey: String
    var catalogId = UnboxPredictor.defaultCatalogId

    static let defaultCatalogId = "cat_aad381c2766331790c3efaa8"
    static let endpoint = URL(string: "https://portal.unboxai.com/api/v1/shop/recommend")!
    static let rankPrior: [Double] = [0.32, 0.22, 0.15, 0.11, 0.08, 0.06, 0.04, 0.02]

    /// Key baked in at build time from Secrets.xcconfig (gitignored) via Info.plist.
    static var bundledKey: String {
        let k = Bundle.main.object(forInfoDictionaryKey: "UnboxAPIKey") as? String ?? ""
        return k.hasPrefix("$(") ? "" : k
    }

    private struct Body: Encodable {
        struct Event: Encodable {
            var type: String
            var item_id: String?
            var item_ids: [String]?
        }
        var catalog_id: String
        var kind = "for_you"
        var limit = 8
        var history: [Event]
        var user = ["market": "US"]
    }

    private struct Reply: Decodable {
        struct Item: Decodable { var id: String }
        var items: [Item]
    }

    func predict(_ req: PredictionRequest) async throws -> PredictionResult {
        var history = req.history.suffix(19).compactMap { e -> Body.Event? in
            e.action == .checkout ? nil : Body.Event(type: "view", item_id: e.itemId)
        }
        if !req.cart.isEmpty { history.append(Body.Event(type: "order", item_ids: Array(req.cart.suffix(20)))) }

        var r = URLRequest(url: Self.endpoint, timeoutInterval: 6)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        r.httpBody = try JSONEncoder().encode(Body(catalog_id: catalogId, history: history))
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let items = try JSONDecoder().decode(Reply.self, from: data).items

        let byId = Dictionary(req.catalog.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var rows: [(id: String, action: BehaviorAction, w: Double)] = []
        for (i, it) in items.filter({ byId[$0.id] != nil }).enumerated() {
            let p = byId[it.id]!
            var w = i < Self.rankPrior.count ? Self.rankPrior[i] : 0.01
            if p.onSale { w *= 1.8 }
            if p.anchor.y > 0.8 && p.anchor.y < 1.6 { w *= 1.15 }
            rows.append((it.id, i < 2 || p.onSale ? .addToCart : .view, w))
        }
        let fill = Double(req.cart.count) / 7
        rows.append((Prediction.checkoutId, .checkout, max(0.01, min(0.6, -0.1 + fill * 0.55))))
        rows = Array(rows.sorted { $0.w > $1.w }.prefix(3))
        let z = rows.reduce(0) { $0 + $1.w }
        let preds = rows.map { Prediction(itemId: $0.id, action: $0.action, p: $0.w / (z > 0 ? z : 1)) }

        let ranked = Set(items.map(\.id))
        let anomaly: Double? = req.cart.count >= 3
            ? Double(req.cart.filter { !ranked.contains($0) }.count) / Double(req.cart.count) * 0.5
            : nil
        return PredictionResult(predictions: preds, anomaly: anomaly, source: "behaviorgpt")
    }
}
