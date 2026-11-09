import Foundation
import Observation

/// Live record of every prediction call: what was sent to BehaviorGPT, what came back,
/// how the reply became probabilities, and what the shopper did with it. Drives APIConsoleView.
@MainActor @Observable
final class APITrace {
    static let shared = APITrace()

    /// Set by RoutedPredictor so predictors can attach raw wire data to the current call.
    @TaskLocal nonisolated static var currentId: UUID?

    enum Stage: Int, Comparable {
        case sending, received, applied, failed
        static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
    }

    struct Call: Identifiable {
        let id: UUID
        let personaId: String
        let started: Date
        var stage: Stage = .sending
        var endpoint = ""
        /// Events in the wire body, e.g. "view · Whole Milk", "order · 3 items".
        var sentEvents: [String] = []
        var cartNames: [String] = []
        var historyCount = 0
        var requestJSON = ""
        var httpStatus: Int?
        var latencyMs: Int?
        var sentAt: Date?
        /// BehaviorGPT ranked item ids, in order.
        var ranked: [String] = []
        var responseJSON = ""
        var predictions: [Prediction] = []
        var source = ""
        var error: String?
        /// Shopper update after the reply: chosen action, new target.
        var choice: Prediction?
        var cartAfter = 0
    }

    private(set) var calls: [Call] = []
    var focusedPersona: String?
    var showRaw = false
    private(set) var total = 0
    private(set) var live = 0
    private(set) var failed = 0
    private var latencySum = 0
    private var latencyN = 0
    var names: [String: String] = [:]

    var avgLatency: Int? { latencyN > 0 ? latencySum / latencyN : nil }
    var inFlight: Int { calls.prefix(12).filter { $0.stage == .sending }.count }

    /// Call to show in the large view: newest for the focused persona, else newest overall.
    var featured: Call? {
        if let f = focusedPersona, let c = calls.first(where: { $0.personaId == f }) { return c }
        return calls.first(where: { $0.stage >= .received && $0.stage != .failed }) ?? calls.first
    }

    func name(_ id: String) -> String { id == Prediction.checkoutId ? "Checkout" : names[id] ?? id }

    func begin(_ id: UUID, _ req: PredictionRequest) {
        for p in req.catalog { names[p.id] = p.name }
        var c = Call(id: id, personaId: req.personaId, started: Date())
        c.historyCount = req.history.count
        c.cartNames = req.cart.map(name)
        calls.insert(c, at: 0)
        if calls.count > 60 { calls.removeLast(calls.count - 60) }
        total += 1
    }

    func wire(_ id: UUID, endpoint: String, events: [String], body: Data?) {
        update(id) {
            $0.endpoint = endpoint
            $0.sentAt = Date()
            $0.sentEvents = events
            $0.requestJSON = Self.pretty(body)
        }
    }

    func reply(_ id: UUID, status: Int, ranked: [String], body: Data?) {
        update(id) {
            $0.httpStatus = status
            $0.latencyMs = Int(Date().timeIntervalSince($0.sentAt ?? $0.started) * 1000)
            $0.ranked = ranked
            $0.responseJSON = Self.pretty(body, maxItems: 8)
        }
    }

    func finish(_ id: UUID, _ r: PredictionResult) {
        update(id) { c in
            if c.latencyMs == nil { c.latencyMs = Int(Date().timeIntervalSince(c.started) * 1000) }
            c.predictions = r.predictions
            c.source = r.source
            c.stage = .received
            if r.source == "behaviorgpt", let ms = c.latencyMs { latencySum += ms; latencyN += 1 }
        }
        if r.source == "behaviorgpt" { live += 1 }
    }

    func fail(_ id: UUID, _ error: Error) {
        failed += 1
        update(id) { $0.error = String(describing: error).prefix(120).description }
    }

    /// Called by AppModel after the result reaches the shopper.
    func applied(_ personaId: String, choice: Prediction?, cart: Int) {
        guard let i = calls.firstIndex(where: { $0.personaId == personaId && $0.stage == .received }) else { return }
        calls[i].choice = choice
        calls[i].cartAfter = cart
        calls[i].stage = .applied
    }

    private func update(_ id: UUID, _ f: (inout Call) -> Void) {
        guard let i = calls.firstIndex(where: { $0.id == id }) else { return }
        f(&calls[i])
    }

    nonisolated static func pretty(_ data: Data?, maxItems: Int? = nil) -> String {
        guard let data, var obj = try? JSONSerialization.jsonObject(with: data) else { return "" }
        if let n = maxItems, var d = obj as? [String: Any], let items = d["items"] as? [[String: Any]] {
            d["items"] = items.prefix(n).map { $0.filter { ["id", "name", "price"].contains($0.key) } }
            obj = d
        }
        guard let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else { return "" }
        return String(decoding: out, as: UTF8.self)
    }
}
