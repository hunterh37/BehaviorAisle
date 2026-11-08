# Behavior Aisle PRD

Immersive grocery store where BehaviorGPT shoppers walk, decide and buy on Apple Vision Pro.

Built for Sundai Hack 148 (Behavioral Models: Predict the next action), MIT, 8 Nov 2026.
Spec page: https://claude.ai/artifact/EzsxMS9Br9osXxcbUH6Eew

## Problem

A store change (moving a product to an endcap, adding a sale sign, swapping aisles) costs labor, shelf
downtime and weeks of sales data before anyone knows whether it worked. Planogram tools show numbers on a
flat floor plan and never show the shopper deciding.

## Product

A 1:1 scale supermarket in a full ImmersiveSpace. HumanHD characters shop it. Each shopper has a persona and a
seed history of past actions. BehaviorGPT (Unbox AI Large Behavioral Model, trained on about 150B retail,
engagement and payment actions) takes that history and returns ranked next actions. The shopper executes one,
the result is appended to its history, and the model is called again. The user changes the store and watches
the predictions and the walking shoppers change.

Users: retail merchandisers and category managers, store planners, hackathon judges.

## Features (v1, built)

| Feature | Behavior | Code |
|---|---|---|
| Lifesize store | RealityHD `grocery-store` scene and grocery props; procedural fallback shell and gondolas when the package lacks them | Store/StoreBuilder.swift |
| Shoppers | 5 HumanHD characters, one per persona, walking the aisle grid | Shopper/ShopperAgent.swift, Model/Persona.swift |
| Prediction loop | predict, sample one of top 3 by probability, walk, pick or view, append event, predict again | Model/AppModel.swift |
| Prediction cards | Billboarded card over each shopper: phase, top 3 actions with probability bars, cart count, source | UI/PredictionCard.swift |
| Probability arcs | Ribbons from shopper to each predicted shelf; width and opacity scale with p | Viz/ArcLayer.swift |
| Fork view | Tap a shopper to freeze it; 3 translucent ghosts walk the 3 branches with % labels | Viz/GhostLayer.swift |
| What-if merchandising | Drag a product to a new shelf slot or long-press for a sale sign (20% off); all shoppers re-query | AppModel.moveProduct, toggleSale |
| Heatmap | 50 simulated shoppers, 14 steps each, accumulated into a 0.25 m floor grid texture | Viz/HeatmapLayer.swift |
| Checkout anomaly | Red badge when the basket is unusual for the persona (model score, or share of off-affinity items) | PredictionCard, HeuristicPredictor.anomaly |
| What-if effect | Paired simulation (same seeds, base vs changed store) reports carts per 100 shoppers per SKU with 95% CI | Predict/Experiment.swift, ControlView.WhatIfEffects |
| Evidence panel | Basket timeline with each pick's predicted rank, top-1 hit count, heuristic baseline agreement | UI/IntentPanel.swift |
| Experiments | Next-action hit@k/MRR vs random and popularity, term ablations, anomaly AUROC; writes demo/results.json | BehaviorAisleTests/ExperimentTests.swift, tools/make_paper_pdf.py |
| Prediction sources | BehaviorGPT via proxy, replay log, local heuristic; live falls back to replay, then heuristic | Predict/ |

## Prediction contract

App to proxy, POST JSON (snake_case):

```
{ persona_id, history: [{action, item_id}], cart: [item_id], catalog: [{id, name, category, price, anchor, stand, on_sale}] }
```

Proxy to app:

```
{ predictions: [{ item_id, action: "view" | "add_to_cart" | "checkout", p }], anomaly: 0..1 | null }
```

`proxy/worker.js` (Cloudflare Worker) holds `UNBOX_API_KEY` and maps this to the Unbox endpoint. The Unbox
field names in the worker are placeholders until confirmed at the Unbox workshop. The app stores only the proxy
URL (UserDefaults) and proxy token (Keychain). Live results append to Documents/predictions.jsonl; replay mode
reads it and a bundled predictions.jsonl when present.

Heuristic model (offline and heatmap): category affinity, price sensitivity, promo boost, eye-level boost,
basket complements, viewed-before boost, in-cart penalty, walking distance; softmax with a checkout logit that
rises as the cart fills toward the persona's basket size.

## Store layout (meters)

Viewer at origin facing -Z. Gondola rows at x = -3, -1, 1, 3; aisles at x = -4, -2, 0, 2, 4; runs from z -3 to
-10 in 1.2 m sections; shelf levels 0.15, 0.55, 0.95, 1.35. Cross aisles at z -1.8 and -10.8. Entrance
(-4, 0, -1.2). Checkout at (4.8, 0, -1.5). Matches RealityHD docs/scenes/grocery-store.md.

Personas: Budget Parent, Home Chef, Late-Night Student, Fitness Regular, Party Host.
Catalog: 32 SKUs across produce, dairy, bakery, pantry, snacks, beverages, frozen, household.

## Dependencies

RealityHD (local ../RealityHD; grocery props and scene in the `grocery-store` PR), HumanHD (local ../HumanHD),
visionOS 26, Swift 6 strict concurrency. Bundle org.dicyaninlabs.behavioraisle.

## Demo script (3 min)

1. Enter store. Five shoppers leave the entrance; cards and arcs appear.
2. Point at a card: top 3 next actions with probabilities from BehaviorGPT.
3. Tap the Late-Night Student: three ghosts walk to chips, soda and checkout.
4. Long-press paper towels for a sale sign. Budget Parent's arcs shift and it turns toward household.
5. Drag cereal to eye level on an endcap. Shoppers re-route.
6. Run the heatmap. Hot aisles light up on the floor.
7. Pitch: retailers test layouts and promotions on predicted shoppers before moving a shelf.

## Success metrics

Hackathon: full demo runs live without a crash; live BehaviorGPT calls under 1 s median; a what-if change
visibly moves at least one shopper. Product: predicted per-aisle traffic and SKU units correlate with real store
data on a pilot layout change.

## Open questions

Unbox API schema, rate limits for 50 parallel shoppers, synthetic persona histories without real user ids,
spatial inputs (aisle, dwell time, eye level), access after the hackathon.

## Out of scope (v1)

Real store import (LiDAR or planogram files), multi-user SharePlay, crowding and queue simulation, revenue
dashboards, hand-tracked pick-up.

## Status

Builds for visionOS Simulator. Not yet run on device or simulator. Unit tests written, not run.
Polish steps pending: design, walkthrough, icon, screenshots, ASC, demo video, optimize.
