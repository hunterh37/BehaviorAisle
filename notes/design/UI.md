# Shelfcast UI

Hackathon demo: judges watch 2-3 minutes, often on a mirrored screen. The window must read from across a room
and the immersive store carries the story. Pattern chosen: single glass dashboard window plus a bottom ornament,
following visionOS HIG (glass material, system fonts, ornaments for persistent controls, no nested Forms).

## Window (UI/ControlView.swift)
1. Header: wordmark, live source pill (green dot when BehaviorGPT, amber for replay/heuristic), gear for settings.
2. Primary capsule button Enter store / Leave store, load bar under it while the scene builds.
3. Stat tiles: shoppers, items in carts, model calls, unusual baskets. Large rounded monospaced numerals with numeric transitions.
4. Shopper rows: persona color bar, name, top prediction and its %, phase chip. Tap forks the shopper.
5. Bring yourself in: X handle field, 4-step progress (fetch, read, classify, build), interest tags and summary.
6. What-if: last change, on-sale chips.
## Ornament
Overlay toggles (cards, arcs, anomaly, heatmap) and restart as icon buttons.
## Settings sheet
Source picker, proxy URL, token.
## Prediction card (UI/PredictionCard.swift)
Rank 1 large, ranks 2-3 small, gradient bars in persona color, phase chip, anomaly banner.
