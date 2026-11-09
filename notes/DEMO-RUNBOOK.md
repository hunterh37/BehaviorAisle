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

BehaviorGPT console window (UI/APIConsoleView.swift, Predict/APITrace.swift):
- Opens with the immersive store (StoreSpace onAppear). Single-instance `Window` id `behaviorgpt`.
- Cards: Request (endpoint, history events), Response (HTTP, ms, BehaviorGPT rank), Shopper update (p, choice, history/cart).
- Tap a row in Recent calls to pin that shopper. Raw JSON toggle shows wire bodies.
- Capture: `ONLY=a1-console-live bash ~/.claude/skills/vision-screenshot/scripts/shoot.sh screenshots/api.json`.
- PDF: `python3 tools/make_api_pdf.py` -> demo/BehaviorAisle-BehaviorGPT-Console.pdf.

Demo Flow 1 (@handle -> HumanHD shopper + shopping preferences, 20 s budget):
- Button `Demo Flow 1` at the top of the control window opens UI/Flow1View.swift; state in Model/Flow1.swift.
- Lanes are separate proxy calls: GET /twitter (keyless api.fxtwitter.com when X_BEARER_TOKEN is unset, 6 retries,
  10 min cache), then POST /classify/body (gemini-3.8-flash, avatar) and POST /classify/shop (claude-haiku-5.5, posts)
  in parallel, then Human.make as soon as the body lands, then spawnImported.
- Fallbacks: body fails -> seeded HumanHD body (amber lane); shop fails -> keyword match. Fetch failure stops the flow.
- E2E: `node tools/e2e_profile.mjs [handles]` -> notes/e2e-flow1.json. `FALLBACK_OK=1` accepts classifier fallbacks.
- Live run 2026-11-08: @jack 10.7 s total (fetch 2.4, body 7.0, shop 8.3). OpenRouter key then hit 402 (credits 130/130 used).
