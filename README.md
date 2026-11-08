# Behavior Aisle

Lifesize visionOS supermarket where HumanHD shoppers act out next-action predictions from BehaviorGPT (Unbox AI).
Store and grocery props from RealityHD (`grocery-store` scene and grocery ids; procedural fallback when absent).

Features: prediction cards (top 3), probability arcs to shelves, walk/pick loop that re-queries on arrival,
tap a shopper for fork view (3 ghost branches), drag a product or long-press for a sale sign (what-if re-query),
50-shopper floor heatmap, checkout anomaly badge. Sources: BehaviorGPT via proxy, replay log, local heuristic.

Run: `xcodegen`, open BehaviorAisle.xcodeproj, run on Apple Vision Pro. Proxy: deploy proxy/worker.js with
UNBOX_API_KEY, UNBOX_ENDPOINT, APP_TOKEN; paste URL and token in the app. Keys never ship in the app.
Live results are logged to Documents/predictions.jsonl and replayed offline.

BehaviorGPT: catalog `cat_aad381c2766331790c3efaa8` (32 SKUs, uploaded by tools/embed_catalog.py).
Key lives in ~/.config/behavioraisle/env as UNBOXAI_API_KEY. Simulator: `node proxy/server.mjs`, app defaults
to http://127.0.0.1:8787/predict in live mode. Device: deploy proxy/worker.js with the key as a secret.

## X profile import

Control window, X profile, Import profile. The proxy fetches the profile (`GET /twitter?handle=`, X API v2) and
classifies it (`POST /classify`, OpenRouter, JSON schema, default `anthropic/claude-sonnet-5.5`). Body traits come
from the profile photo and map to a HumanHD `HumanSpec` (`Profile/HumanTraitsMapper.swift`); grocery affinity and the
wishlist come from bio and posts. The shopper joins the store with a thought cloud of wishlist products overhead.
Add `X_BEARER_TOKEN` and `OPENROUTER_API_KEY` (optional `OPENROUTER_MODEL`) to `~/.config/behavioraisle/env` or the
Worker secrets. Without OpenRouter the app falls back to a keyword classifier and a seeded random human.
