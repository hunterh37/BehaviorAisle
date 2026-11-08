import XCTest

/// Runs the paper's experiments and writes demo/results.json (path from the source file location).
final class ExperimentTests: XCTestCase {
    func testWriteResults() throws {
        let base = Catalog.laidOut()
        var sale = base
        sale[sale.firstIndex { $0.id == "towels" }!].onSale = true
        var moved = base
        let cereal = moved.firstIndex { $0.id == "cereal" }!
        let eye = base.first { $0.anchor.y > 0.9 && $0.anchor.y < 1.2 && $0.id != "cereal" }!
        moved[cereal].anchor = eye.anchor + SIMD3(0, 0, 0.3)
        moved[cereal].stand = eye.stand + SIMD3(0, 0, 0.3)

        let saleR = Experiment.whatIf(base: base, variant: sale)
        let moveR = Experiment.whatIf(base: base, variant: moved)
        let nullR = Experiment.whatIf(base: base, variant: base)
        let acc = Experiment.accuracy()
        let noise = [0.0, 0.25, 0.5, 1.0].map { s -> [String: Double] in
            let full = Experiment.accuracy(sigma: s, tripsPerPersona: 20).first { $0.name == "Full model" }!
            return ["sigma": s, "hit1": full.hit1, "hit3": full.hit3, "mrr": full.mrr]
        }
        let anom = Experiment.anomalyAUROC()

        XCTAssertGreaterThan(saleR.effects.first { $0.itemId == "towels" }!.delta, 0)
        XCTAssertTrue(nullR.effects.allSatisfy { $0.delta == 0 })
        let full = acc.first { $0.name == "Full model" }!, rnd = acc.first { $0.name == "Random" }!
        XCTAssertGreaterThan(full.hit3, rnd.hit3)

        func enc(_ w: Experiment.WhatIf) -> [String: Any] {
            ["replicates": w.replicates, "shoppers": w.shoppers, "metersBase": w.metersBase, "metersVariant": w.metersVariant,
             "basketBase": w.basketBase, "basketVariant": w.basketVariant,
             "effects": w.effects.prefix(8).map { ["item": $0.itemId, "base": $0.base, "delta": $0.delta, "ci": $0.ci] }]
        }
        let out: [String: Any] = [
            "sale_towels": enc(saleR), "move_cereal": enc(moveR), "null": enc(nullR),
            "moved_to": eye.id,
            "accuracy": acc.map { ["name": $0.name, "hit1": $0.hit1, "hit3": $0.hit3, "mrr": $0.mrr, "n": $0.n] },
            "noise": noise,
            "anomaly": ["auroc": anom.auroc, "n": anom.n],
        ]
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("demo/results.json")
        try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]).write(to: url)
    }
}
