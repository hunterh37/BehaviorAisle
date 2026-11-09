"""Builds demo/BehaviorAisle-Demo-Plan.pdf: event fit, feature coverage, must-finish list, demo run sheet.
Usage: python3 tools/make_plan_pdf.py"""
import os
from PIL import Image, ImageDraw
from make_demo_pdf import font, W, H, BG, FG, DIM, ACC

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "demo", "BehaviorAisle-Demo-Plan.pdf")
RAW = os.path.join(ROOT, "screenshots", "raw")
OK, PART, MISS = ACC, (240, 196, 80), (240, 96, 96)

EVENT = ("Sundai Hack 148, MIT, 8 Nov 2026", [
    "Theme: Behavioral Models, predict the next action (Unbox AI BehaviorGPT).",
    "Source: PRD.md. sundai.club event pages load client-side and /hacks needs sign-in;",
    "theme, sponsors and judging rubric were not readable by fetch on 2026-11-08.",
    "",
    "What judges of a behavior-model hack check:",
    "1. The model is live and visibly drives behavior (not scripted).",
    "2. Next action is legible: item, probability, and why.",
    "3. A change to the world changes the prediction (cause -> effect).",
    "4. Some proof it is right: accuracy, hit rate, or a baseline comparison.",
    "5. A buyer and a use case: who pays, what decision it replaces.",
])

COVERAGE = [
    ("Live BehaviorGPT next-action calls via proxy", "built", "Predict/BehaviorGPTPredictor.swift, proxy/"),
    ("Offline fallback: replay log, then heuristic", "built", "RoutedPredictor"),
    ("Lifesize store with stocked shelves", "partial", "StoreBuilder + StoreDensity (uncommitted)"),
    ("Shoppers act on predictions in a loop", "built", "AppModel.request/execute/finishPick"),
    ("Top-3 next actions with probability", "built", "PredictionCard, IntentPanel"),
    ("Reason per prediction (interest -> item)", "built", "IntentExplainer"),
    ("Destination shown in space: path, beacon", "built", "Viz/IntentLayer.swift"),
    ("Branch view: ghosts walk top 3", "built", "Viz/GhostLayer.swift"),
    ("What-if: move product, sale sign, re-query", "built", "moveProduct, toggleSale"),
    ("Store heatmap", "built", "Viz/HeatmapLayer.swift"),
    ("Anomaly flag at checkout", "built", "anomaly badge"),
    ("Real person in: X profile -> persona", "built", "Profile/, ProfileImportView"),
    ("Basket timeline + top-1 hit counter", "built", "IntentPanel.BasketTimeline (this pass)"),
    ("Before/after metric for a what-if", "built", "Experiment.whatIf, paired 95% CI"),
    ("Live vs heuristic side by side", "built", "IntentPanel.BaselineRow"),
    ("Accuracy vs baselines + ablations", "built", "Experiment.accuracy (simulated truth)"),
    ("Run on device / simulator end to end", "partial", "PRD status: not yet run"),
]

MUST = [
    ("P0", "Run the full demo route on simulator once; fix any crash.", "demo blocker"),
    ("P0", "Confirm Unbox field names in proxy/worker.js at workshop; one live call.", "theme fit"),
    ("P0", "Commit StoreDensity + intent layer; restock to packed preset.", "store reads finished"),
    ("P1", "What-if delta chip: 'Paper towels +38% picks' after sale toggle.", "proof of effect"),
    ("P1", "Source toggle on one shopper: BehaviorGPT vs heuristic top 3.", "model value"),
    ("P1", "Bundle predictions.jsonl from a live run so replay works offline.", "wifi risk"),
    ("P2", "Personal heatmap for the imported profile.", "nice to have"),
    ("P2", "Record 60 s backup video via /vision-record-demo.", "fallback"),
]

PLAN = [
    ("0:00", "Hook", "A shelf move costs weeks of sales data. We predict it in minutes."),
    ("0:15", "Real person", "Paste an X handle. Interests -> persona -> likely basket."),
    ("0:45", "Enter store", "Shopper walks in; panel shows top 3 next actions, %, reason."),
    ("1:05", "Destination", "Floor path and beacon on the rank-1 shelf; shopper walks it."),
    ("1:25", "Branches", "Tap shopper: 3 ghosts walk the 3 futures with probabilities."),
    ("1:45", "What-if", "Sale sign on paper towels; Budget Parent re-routes live."),
    ("2:10", "Proof", "Basket timeline, Top-1 hits 7/9; heatmap over 50 shoppers."),
    ("2:40", "Ask", "Merchandisers test planograms on predicted shoppers first."),
]


def base(title):
    im = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(im)
    d.text((100, 70), title, font=font(64, True), fill=FG)
    return im, d


def p_title():
    im, d = base("")
    d.text((120, 320), "Shelfcast demo plan", font=font(96, True), fill=FG)
    d.text((120, 450), "Sundai Hack 148 · Behavioral Models · 8 Nov 2026", font=font(44), fill=ACC)
    d.text((120, 520), "Coverage of expected features, must-finish list, 3-minute run sheet.", font=font(36), fill=DIM)
    shot = os.path.join(RAW, "06-aisle.png")
    if os.path.exists(shot):
        s = Image.open(shot).convert("RGB"); s.thumbnail((700, 400))
        im.paste(s, (W - s.width - 100, H - s.height - 100))
    return im


def p_event():
    im, d = base(EVENT[0])
    y = 190
    for l in EVENT[1]:
        d.text((100, y), l, font=font(38), fill=FG if l[:1].isdigit() else DIM); y += 60
    return im


def p_cov():
    im, d = base("Expected features vs built")
    y, f, fs = 175, font(31), font(25)
    for name, st, where in COVERAGE:
        c = {"built": OK, "partial": PART, "missing": MISS}[st]
        d.rounded_rectangle((100, y + 4, 250, y + 42), 10, fill=c)
        d.text((175, y + 23), st.upper(), font=fs, fill=BG, anchor="mm")
        d.text((280, y + 6), name, font=f, fill=FG)
        d.text((1180, y + 10), where, font=fs, fill=DIM)
        y += 47
    b = sum(1 for r in COVERAGE if r[1] == "built")
    d.text((100, H - 60), f"{b}/{len(COVERAGE)} built", font=font(30, True), fill=ACC)
    return im


def p_must():
    im, d = base("Must finish before demo")
    y = 200
    for pr, task, why in MUST:
        c = MISS if pr == "P0" else PART if pr == "P1" else DIM
        d.text((100, y), pr, font=font(40, True), fill=c)
        d.text((210, y), task, font=font(36), fill=FG)
        d.text((210, y + 46), why, font=font(26), fill=DIM)
        y += 102
    return im


def p_plan():
    im, d = base("Ideal 3-minute demo")
    y = 200
    for t, step, say in PLAN:
        d.text((100, y), t, font=font(40, True), fill=ACC)
        d.text((260, y), step, font=font(40, True), fill=FG)
        d.text((620, y + 6), say, font=font(32), fill=DIM)
        y += 96
    d.text((100, H - 80), "Fallback: replay mode + bundled predictions.jsonl if wifi or proxy fails.", font=font(28), fill=PART)
    return im


pages = [p_title(), p_event(), p_cov(), p_must(), p_plan()]
os.makedirs(os.path.dirname(OUT), exist_ok=True)
pages[0].save(OUT, save_all=True, append_images=pages[1:], resolution=144)
print(OUT)
