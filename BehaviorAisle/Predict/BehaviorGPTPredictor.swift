import Foundation

/// Calls the BehaviorAisle proxy (proxy/worker.js), which holds the Unbox AI key and forwards to BehaviorGPT.
/// Contract: POST JSON PredictionRequest (snake_case) -> { predictions: [{item_id, action, p}], anomaly? }.
struct BehaviorGPTPredictor: Predictor {
    var endpoint: URL
    var token: String?

    func predict(_ req: PredictionRequest) async throws -> PredictionResult {
        var r = URLRequest(url: endpoint, timeoutInterval: 6)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        r.httpBody = try enc.encode(req)
        let traceId = APITrace.currentId
        if let traceId {
            let names = Dictionary(req.catalog.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
            var events = req.history.suffix(19).map { "view · \(names[$0.itemId] ?? $0.itemId)" }
            if !req.cart.isEmpty { events.append("order · \(req.cart.count) items in cart") }
            await APITrace.shared.wire(traceId, endpoint: "POST \(endpoint.host ?? "proxy")\(endpoint.path) → BehaviorGPT", events: events, body: nil)
        }
        let (data, resp) = try await URLSession.shared.data(for: r)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if let traceId { await APITrace.shared.reply(traceId, status: status, ranked: [], body: data) }
            throw URLError(.badServerResponse)
        }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        struct Wire: Decodable { var predictions: [Prediction]; var anomaly: Double? }
        let w = try dec.decode(Wire.self, from: data)
        let known = Set(req.catalog.map(\.id)).union([Prediction.checkoutId])
        let preds = Array(w.predictions.filter { known.contains($0.itemId) }.sorted { $0.p > $1.p }.prefix(3))
        guard !preds.isEmpty else { throw URLError(.cannotParseResponse) }
        if let traceId { await APITrace.shared.reply(traceId, status: status, ranked: w.predictions.map(\.itemId), body: data) }
        return PredictionResult(predictions: preds, anomaly: w.anomaly, source: "behaviorgpt")
    }
}

/// Appends live results to Documents/predictions.jsonl and replays them by persona + recent history.
actor PredictionLog {
    static let shared = PredictionLog()
    private var table: [String: PredictionResult] = [:]
    private var loaded = false

    private var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("predictions.jsonl")
    }

    static func key(_ req: PredictionRequest) -> String {
        req.personaId + "|" + req.history.suffix(4).map { "\($0.action.rawValue):\($0.itemId)" }.joined(separator: ",")
    }

    struct Line: Codable { var key: String; var result: PredictionResult }

    func record(_ req: PredictionRequest, _ result: PredictionResult) {
        let line = Line(key: Self.key(req), result: result)
        table[line.key] = result
        guard var data = try? JSONEncoder().encode(line) else { return }
        data.append(0x0A)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    func lookup(_ req: PredictionRequest) -> PredictionResult? {
        if !loaded {
            loaded = true
            let sources = [url, Bundle.main.url(forResource: "predictions", withExtension: "jsonl")].compactMap { $0 }
            for u in sources {
                guard let text = try? String(contentsOf: u, encoding: .utf8) else { continue }
                for l in text.split(separator: "\n") {
                    if let line = try? JSONDecoder().decode(Line.self, from: Data(l.utf8)) { table[line.key] = line.result }
                }
            }
        }
        guard var r = table[Self.key(req)] else { return nil }
        r.source = "replay"
        return r
    }
}

/// Mode router: live -> record, fall back to replay then heuristic.
struct RoutedPredictor: Predictor {
    var mode: PredictorMode
    var live: (any Predictor)?
    var heuristic = HeuristicPredictor()

    func predict(_ req: PredictionRequest) async throws -> PredictionResult {
        let id = UUID()
        await APITrace.shared.begin(id, req)
        let r = try await APITrace.$currentId.withValue(id) { try await route(req, id) }
        await APITrace.shared.finish(id, r)
        return r
    }

    private func route(_ req: PredictionRequest, _ id: UUID) async throws -> PredictionResult {
        if mode == .live, let live {
            do {
                let r = try await live.predict(req)
                await PredictionLog.shared.record(req, r)
                return r
            } catch {
                await APITrace.shared.fail(id, error)
            }
        }
        if mode != .heuristic, let r = await PredictionLog.shared.lookup(req) { return r }
        var r = try await heuristic.predict(req)
        if mode == .live { r.source = "heuristic (live failed)" }
        return r
    }
}
