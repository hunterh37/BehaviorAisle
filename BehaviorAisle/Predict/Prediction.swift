import Foundation

/// One ranked next action. `itemId` is "checkout" for the checkout action.
struct Prediction: Codable, Sendable, Hashable, Identifiable {
    var itemId: String
    var action: BehaviorAction
    var p: Double
    var id: String { "\(action.rawValue):\(itemId)" }
    static let checkoutId = "checkout"
}

struct PredictionRequest: Codable, Sendable {
    var personaId: String
    var history: [BehaviorEvent]
    var cart: [String]
    /// Catalog with current placement and promos, so what-if changes reach the model.
    var catalog: [Product]
}

struct PredictionResult: Codable, Sendable {
    var predictions: [Prediction]
    /// 0...1, higher = unusual for this person. Nil when the source gives none.
    var anomaly: Double?
    var source: String
}

protocol Predictor: Sendable {
    func predict(_ req: PredictionRequest) async throws -> PredictionResult
}

enum PredictorMode: String, CaseIterable, Identifiable, Sendable {
    case live, replay, heuristic
    var id: String { rawValue }
    var label: String {
        switch self {
        case .live: "BehaviorGPT"
        case .replay: "Replay log"
        case .heuristic: "Local heuristic"
        }
    }
}
