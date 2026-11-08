# Demo runbook (BehaviorGPT)

Preflight, 10 min before stage:
1. Run `node tools/record_replay.mjs` (47 s, 692 real calls).
   Success line `personas 5 calls N keys N` proves the Unbox key and catalog `cat_aad381c2766331790c3efaa8` are live,
   and refreshes BehaviorAisle/Resources/predictions.jsonl.
2. `Support/Secrets.xcconfig` (gitignored) holds `UNBOXAI_API_KEY`; Info.plist `UnboxAPIKey` reads it.
   Empty proxy URL in Settings = app calls Unbox directly (Predict/UnboxPredictor.swift). Works on device and simulator.
3. Mode `BehaviorGPT` (live). Card source tag must read `behaviorgpt`.

Failure ladder (automatic, RoutedPredictor):
- live call fails (venue Wi-Fi) -> bundled replay of real BehaviorGPT outputs, tag `replay`.
  Covers every persona from seed history, all top-3 branches 3 deep, then 10 greedy steps.
- no replay key -> heuristic, tag `heuristic (live failed)`.
- Wi-Fi known bad: switch mode to `Replay log` before going on stage; tags stay `replay`.

Talk track for the source tag: item ranking = BehaviorGPT; probabilities = rank prior x sale x eye-level (proxy/core.mjs).
