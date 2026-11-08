import XCTest

final class PredictorTests: XCTestCase {
    func testHeuristicReturnsTop3SumBelowOne() {
        let req = PredictionRequest(personaId: "student", history: Persona.all[2].seedHistory, cart: [], catalog: Catalog.laidOut())
        let r = HeuristicPredictor().rank(req, from: StoreLayout.entrance)
        XCTAssertEqual(r.predictions.count, 3)
        XCTAssertLessThanOrEqual(r.predictions.reduce(0) { $0 + $1.p }, 1.0001)
    }

    func testSaleRaisesProbability() {
        var cat = Catalog.laidOut()
        let base = HeuristicPredictor().rank(PredictionRequest(personaId: "budget-parent", history: [], cart: [], catalog: cat), from: nil)
        let i = cat.firstIndex { $0.id == "spray" }!
        cat[i].onSale = true
        let sale = HeuristicPredictor().rank(PredictionRequest(personaId: "budget-parent", history: [], cart: [], catalog: cat), from: nil)
        let pBase = base.predictions.first { $0.itemId == "spray" }?.p ?? 0
        let pSale = sale.predictions.first { $0.itemId == "spray" }?.p ?? 0
        XCTAssertGreaterThanOrEqual(pSale, pBase)
    }

    func testPathEndsAtTarget() {
        let to = SIMD3<Float>(3, 0, -7)
        XCTAssertEqual(StoreLayout.path(from: StoreLayout.entrance, to: to).last, to)
    }
}
