Blindspot analysis of demo/BehaviorAisle-XProfile-Demo.pdf (frames 01-06)

Gaps in the old frames
1. Prediction was invisible as a destination. Frame 06 shows cards about 4 cm tall at 3 m; the text is unreadable and nothing points from the shopper to a shelf. Viewers saw a person and a cloud, with no "they are going there".
2. Interests and items were split across two screens. Frame 04 lists interests and "likely to buy"; the store frames drop the interests, so the causal chain (profile -> interest -> item) breaks at the moment it matters.
3. No reason per prediction. Percentages had no "because".
4. Thought cloud products are 11 cm and float against a bright ceiling; they read as noise at demo distance.
5. Shelves are sparse (empty white gondolas); the predicted item does not stand out because nothing is around it, and the store reads as unfinished.
6. Arcs default off in captures; with them on, they are thin and hit the ceiling area.

Built this pass
- Predict/IntentExplainer.swift: maps each prediction to the profile interest that explains it, plus aisle label ("Aisle 3 · Bakery"). Unit test testIntentExplainerTiesInterestToItem.
- UI/IntentPanel.swift: 440 pt panel beside the imported shopper. Interest chips, then "Predicted next" rows: rank, item, %, reason, aisle. Rank 1 large and tinted. BeaconLabel: "% · @handle next · item" tag above the shelf product.
- Viz/IntentLayer.swift: marching dotted floor path to the aisle spot, pulsing floor pad, light beam and ring on the rank-1 product, smaller rings on ranks 2-3. Rebuilt on every prediction and target choice.
- AppModel.showIntent, ornament toggle "Intent", demo route param intent=1.
- tools/make_demo_pdf.py -> demo/BehaviorAisle-Intent-Demo.pdf.

Still missing for a strong demo (ranked)
1. Dense stock: another session is landing StoreDensity (packed preset); recapture after it lands.
2. Hit-rate counter: predicted rank-1 vs actual pick, live per shopper ("7/9 correct").
3. Basket timeline: picks in order with the reason each was predicted.
4. Live vs heuristic side by side for one profile to show what BehaviorGPT adds.
5. Personal heatmap: the 50-shopper heatmap filtered to one profile's predicted aisles.
6. Camera route that dollies from profile window into the aisle for the video cut.
