# Store KPIs and demo changes

## KPIs store owners and category managers track

| KPI | Definition | Current state in Shelfcast |
|---|---|---|
| Sales per sq ft / per linear shelf ft | Revenue per unit of fixture space | Missing. Revenue delta exists (`Experiment.WhatIf.revenueDelta`), not normalized by space |
| Average basket size (units, $) | Items and dollars per transaction | Units only (`basketBase/Variant`). Add $ |
| Conversion (aisle/category) | Shoppers who pass a zone vs shoppers who buy from it | Missing. Heatmap has passes, picks are known; ratio is cheap to add |
| Gross margin $ (GMROI) | Margin, not revenue, decides planograms | Missing. Add `cost` per `Product`; report margin delta |
| Promo lift and cannibalization | Incremental units for promoted SKU minus losses from substitutes | Lift exists per SKU with CI. Cannibalization (negative deltas on same-category SKUs) is computed but not surfaced as a net number |
| Promo ROI | (Incremental margin - promo cost) / promo cost | `promoCost` exists. Compute and show one ROI number |
| Attach rate | Share of baskets with item B given item A (chips + salsa) | `complements` term exists; no attach metric shown |
| Out-of-stock / lost sales | Demand that hit an empty slot | Missing. Add "remove SKU" what-if; show substitution vs walkaway |
| Dwell / trip time | Time in store, path length | `metersBase/Variant` exists. Express as minutes |
| Impulse purchase rate | Unplanned picks / total | Seed history vs picks gives planned vs unplanned |

Top three for a buyer pitch: margin $ per change, net promo lift after cannibalization, sales per linear foot.

## BehaviorGPT optimization

Current numbers (`demo/results.json`, n=2459): hit@1 0.111, hit@3 0.259, MRR 0.256 vs popularity 0.048 / 0.156 / 0.170. `- promo` ablation equals the full model, so the promo term contributes 0 to accuracy; a sale-sign what-if then rests on an unvalidated term. Options:

1. Calibrate promo against Instacart reorder data (`tools/validate_instacart.py`) or fit elasticity from a public price dataset; else label the sale effect as an assumption in the UI.
2. Cache BehaviorGPT responses keyed by (history hash, catalog hash). Paired simulations call the model 20x50x14 times; the heuristic runs offline and BehaviorGPT only for the visible 5 shoppers.
3. Report BehaviorGPT vs heuristic hit@k on the same held-out steps. Without that number, judges cannot tell what the LBM adds.
4. Calibration plot (predicted p vs observed frequency, 10 bins). A ranked list with good MRR and bad calibration gives wrong revenue deltas, since effects come from sampled probabilities.
5. Add a "leave store" action so conversion and walkaway are modeled.

## Demo changes, ranked

1. One verdict card after a what-if: "Endcap move: +$X margin / week / store, 95% CI, ROI Y". Single number, top of `ControlView.WhatIfEffects`.
2. A/B split view: base store and variant store side by side (or a toggle), same seeds, ghosts diverge.
3. Net lift line showing cannibalized SKUs in red.
4. Out-of-stock what-if (remove a SKU, show where demand goes).
5. Scale line: per store/week multiplied to chain (e.g. 500 stores). Buyers think in chain dollars.
6. Validation slide: hit@3 2.6x popularity, anomaly AUROC, Instacart check.

Skip: more personas, more visual effects. The gap is the money number.
