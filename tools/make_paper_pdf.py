"""Builds demo/BehaviorAisle-Paper.pdf, a research-paper style report, from demo/results.json
(written by BehaviorAisleTests/ExperimentTests.testWriteResults).
Usage: python3 tools/make_paper_pdf.py"""
import json, os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = json.load(open(os.path.join(ROOT, "demo", "results.json")))
OUT = os.path.join(ROOT, "demo", "BehaviorAisle-Paper.pdf")
RAW = os.path.join(ROOT, "screenshots", "raw")
W, H, M = 1275, 1650, 110  # US letter at 150 dpi
SUP = "/System/Library/Fonts/Supplemental/"
INK, GREY, RULE, ACC, NEG = (20, 20, 20), (95, 95, 95), (170, 170, 170), (30, 120, 90), (190, 90, 40)
NAMES = {"towels": "Paper Towels", "cereal": "Oat Cereal", "checkout": "Checkout"}


def F(size, style=""):
    name = {"": "Times New Roman.ttf", "b": "Times New Roman Bold.ttf", "i": "Times New Roman Italic.ttf"}[style]
    return ImageFont.truetype(SUP + name, size)


class Doc:
    def __init__(self):
        self.pages, self.fig, self.tab = [], 0, 0
        self.new()

    def new(self):
        self.im = Image.new("RGB", (W, H), "white")
        self.d = ImageDraw.Draw(self.im)
        self.y = M
        self.pages.append(self.im)
        n = len(self.pages)
        self.d.text((W / 2, H - 60), str(n), font=F(20), fill=GREY, anchor="mm")
        if n > 1:
            self.d.text((M, 55), "Shelfcast · Sundai Hack 148", font=F(18, "i"), fill=GREY)

    def need(self, h):
        if self.y + h > H - M:
            self.new()

    def para(self, text, size=23, style="", color=INK, indent=0, gap=12):
        f = F(size, style)
        words, line, lines = text.split(), "", []
        for w in words:
            t = (line + " " + w).strip()
            if self.d.textlength(t, font=f) > W - 2 * M - indent:
                lines.append(line); line = w
            else:
                line = t
        if line: lines.append(line)
        lh = int(size * 1.32)
        for l in lines:
            self.need(lh)
            self.d.text((M + indent, self.y), l, font=f, fill=color)
            self.y += lh
        self.y += gap

    def head(self, text):
        self.need(80)
        self.y += 14
        self.d.text((M, self.y), text, font=F(30, "b"), fill=INK)
        self.y += 48

    def sub(self, text):
        self.need(60)
        self.d.text((M, self.y), text, font=F(24, "b"), fill=INK)
        self.y += 36

    def caption(self, kind, text):
        if kind == "Figure": self.fig += 1; n = self.fig
        else: self.tab += 1; n = self.tab
        self.para(f"{kind} {n}. {text}", size=19, style="i", color=GREY, gap=18)

    def table(self, cols, rows, widths, bold_row=None):
        rh = 34
        self.need(rh * (len(rows) + 2))
        x0, x1 = M, M + sum(widths)
        self.d.line((x0, self.y, x1, self.y), fill=INK, width=2)
        self.y += 6
        x = x0
        for c, w in zip(cols, widths):
            self.d.text((x + 6, self.y), c, font=F(20, "b"), fill=INK); x += w
        self.y += rh - 4
        self.d.line((x0, self.y, x1, self.y), fill=INK, width=1)
        self.y += 6
        for i, r in enumerate(rows):
            x = x0
            st = "b" if i == bold_row else ""
            for c, w in zip(r, widths):
                self.d.text((x + 6, self.y), str(c), font=F(20, st), fill=INK); x += w
            self.y += rh
        self.d.line((x0, self.y, x1, self.y), fill=INK, width=2)
        self.y += 14

    def bars(self, items, vmax, unit="", h=26, ci=None, signed=False):
        """items: [(label, value, err)]"""
        lab_w, bar_w = 260, W - 2 * M - 260 - 140
        self.need(len(items) * (h + 10) + 20)
        zero = M + lab_w + (bar_w / 2 if signed else 0)
        scale = (bar_w / 2 if signed else bar_w) / vmax
        for lab, v, e in items:
            self.d.text((M, self.y + 2), lab, font=F(20), fill=INK)
            x2 = zero + v * scale
            col = ACC if v >= 0 else NEG
            self.d.rectangle((min(zero, x2), self.y + 3, max(zero, x2), self.y + h - 3), fill=col)
            if e:
                self.d.line((zero + (v - e) * scale, self.y + h / 2, zero + (v + e) * scale, self.y + h / 2), fill=INK, width=2)
                for xx in (v - e, v + e):
                    self.d.line((zero + xx * scale, self.y + 6, zero + xx * scale, self.y + h - 6), fill=INK, width=2)
            txt = (f"{v:+.1f}" if signed else f"{v:.2f}") + (f" ± {e:.1f}" if e else "") + unit
            self.d.text((M + lab_w + bar_w + 14, self.y + 2), txt, font=F(20), fill=INK)
            self.y += h + 10
        if signed:
            self.d.line((zero, self.y - len(items) * (h + 10), zero, self.y), fill=RULE, width=1)
        self.y += 8

    def image(self, path, w):
        if not os.path.exists(path): return False
        s = Image.open(path).convert("RGB")
        s = s.resize((w, int(s.height * w / s.width)))
        self.need(s.height + 10)
        self.im.paste(s, (int((W - w) / 2), self.y))
        self.d.rectangle((int((W - w) / 2), self.y, int((W + w) / 2), self.y + s.height), outline=RULE)
        self.y += s.height + 10
        return True


acc = {a["name"]: a for a in RES["accuracy"]}
full, rnd, pop = acc["Full model"], acc["Random"], acc["Popularity"]
sale, move, null = RES["sale_towels"], RES["move_cereal"], RES["null"]
towel = next(e for e in sale["effects"] if e["item"] == "towels")
cer = next((e for e in move["effects"] if e["item"] == "cereal"), None)
auroc = RES["anomaly"]["auroc"]
nm = lambda i: NAMES.get(i, i.capitalize())

d = Doc()
d.y = 150
for line, f in [("Shelfcast: Testing Store Changes on", F(44, "b")), ("Predicted Shoppers Before Moving a Shelf", F(44, "b"))]:
    d.d.text((W / 2, d.y), line, font=f, fill=INK, anchor="mt"); d.y += 58
d.y += 10
d.d.text((W / 2, d.y), "Cadence Dev Studio · Dicyanin Labs", font=F(24), fill=INK, anchor="mt"); d.y += 34
d.d.text((W / 2, d.y), "Sundai Hack 148, Behavioral Models: Predict the Next Action · MIT IHQ · 8 November 2026",
         font=F(20, "i"), fill=GREY, anchor="mt"); d.y += 60
d.sub("Abstract")
d.para(
    "Large Behavioral Models such as BehaviorGPT-v4 predict a person's next action from a short history of actions. "
    "We ask whether next-action predictions can replace the weeks of sales data a retailer waits for after a "
    "merchandising change. Shelfcast places model-driven shoppers in a 1:1 immersive grocery store on Apple "
    "Vision Pro. Each shopper sends its history to the model, acts on a sampled prediction, appends the result and asks "
    "again. The user moves products or adds promotions and watches predictions and paths change. We report three "
    f"experiments on the local model that backs the live BehaviorGPT path. Next-action hit@3 is {full['hit3']:.2f} "
    f"against {rnd['hit3']:.2f} for random and {pop['hit3']:.2f} for popularity (n = {full['n']}). A 20% sale on paper "
    f"towels raises predicted carts by {towel['delta']:+.1f} ± {towel['ci']:.1f} per 100 shoppers in a paired design "
    f"whose null control returns exactly zero. An off-persona basket detector reaches AUROC {auroc:.2f}. Accuracy "
    "against real shopper logs and against BehaviorGPT itself remain open and are listed as gaps.", size=21)

d.head("1  Introduction")
d.para("A planogram change (an endcap, a sale sign, an aisle swap) costs labor and shelf downtime, then takes weeks of "
       "sales before anyone knows if it worked. Planogram software shows numbers on a flat plan and never shows a "
       "shopper deciding. Behavioral models learn from what people do rather than what they say, and one model covers "
       "search, recommendation and fraud. If such a model predicts the next action well, a store can be tested on "
       "predicted shoppers first.")
d.para("Hypotheses.", style="b", gap=4)
for h in [
    "H1. The next-action model ranks the true next action above random and popularity baselines, and each model term contributes.",
    "H2. A merchandising change produces a measurable shift in predicted demand for the changed item; an unchanged store produces none.",
    "H3. The basket anomaly score separates a person's own basket from another person's basket on the same account.",
]:
    d.para(h, indent=24, gap=6)
d.y += 6

d.head("2  System")
d.para("Figure 1 shows the store with an imported shopper. Components built for the hack:")
for b in [
    "Store: RealityHD grocery-store scene, four gondola rows, 32 SKUs in 8 categories, adjustable stock density.",
    "Shoppers: HumanHD characters, five personas plus any X profile turned into a persona (interests, category affinity).",
    "Prediction loop: predict, sample one of the top 3, walk the aisle grid, view or add to cart, append, predict again.",
    "Sources: BehaviorGPT via proxy (Unbox portal catalog), replay log, local model; failures fall back in that order.",
    "Legibility: cards with top-3 probabilities, reasons tied to profile interests, floor path and shelf beacon, three ghost branches.",
    "What-if: drag a product or toggle a sale; every shopper re-queries and a paired simulation reports per-SKU effects with 95% CI.",
    "Evidence on screen: basket timeline with the rank each pick had, top-1 hit count, heuristic-baseline agreement, 50-shopper heatmap.",
    "Fraud: anomaly badge when a basket is unusual for the persona.",
]:
    d.para("• " + b, size=21, indent=16, gap=4)
d.y += 8
if d.image(os.path.join(RAW, "06-aisle.png"), 820):
    d.caption("Figure", "Imported shopper in the aisle with its thought cloud of predicted items (visionOS simulator).")

d.head("3  Methods")
d.sub("3.1  Prediction contract")
d.para("The app sends {persona_id, history[action, item_id], cart, catalog[id, category, price, position, on_sale]} and "
       "receives ranked {item_id, action, p} plus an optional anomaly score. Catalog position and promotion travel with "
       "every request, so store changes reach the model.")
d.sub("3.2  Local model")
d.para("For persona u, item i, history h and position x the logit is s(i) = 2.2 a_u(c_i) − 1.4 λ_u price_i / max price "
       "+ promo_i (0.9 + 0.6 λ_u) + 0.25 eye_i + 0.35 comp(c_last, c_i) + 0.4 viewed_i − 3 inCart_i − 0.06 ‖x − stand_i‖. "
       "Checkout has logit −2.5 + 4.5 · cart / basket size. Probabilities are a softmax over all items and checkout.")
d.sub("3.3  Ground truth by perturbation")
d.para("Without public shopper logs, true shoppers are simulated as the same model with each category affinity shifted by "
       "ε ~ N(0, σ²), σ = 0.25. The predictor sees only unperturbed personas, so it must generalize to unseen preferences. "
       f"40 trips per persona, up to 14 actions each, give n = {full['n']} next-action decisions. Metrics: hit@1, hit@3 and "
       "mean reciprocal rank (MRR). Baselines: random order and global popularity fit on the evaluation data (optimistic). "
       "Ablations remove one term at a time.")
d.sub("3.4  Paired counterfactual")
d.para(f"Each what-if runs R = {sale['replicates']} replicates of N = {sale['shoppers']} shoppers on the base and the changed "
       "store with identical random seeds, so the per-replicate difference isolates the change. Effects are carts per 100 "
       "shoppers; the interval is mean ± 1.96 · sd / √R of paired differences. A null run (base vs base) checks the design.")
d.sub("3.5  Anomaly")
d.para("Normal baskets come from the claimed persona; anomalous baskets come from another persona scored against the "
       "claimed one, as with a shared account or stolen card. Score: share of cart items in categories with affinity < 0.3. "
       "Metric: AUROC.")

d.head("4  Results")
d.sub("4.1  Next-action accuracy (H1)")
rows = [[a["name"], f"{a['hit1']:.3f}", f"{a['hit3']:.3f}", f"{a['mrr']:.3f}"] for a in RES["accuracy"]]
d.table(["Model", "hit@1", "hit@3", "MRR"], rows, [420, 200, 200, 200], bold_row=2)
d.caption("Table", f"Next-action ranking on {full['n']} simulated decisions (σ = 0.25). Rows starting with − remove one term.")
abl = sorted([(a["name"][2:], full["mrr"] - a["mrr"]) for a in RES["accuracy"] if a["name"].startswith("- ")], key=lambda t: -t[1])
d.para("MRR lost when each term is removed (larger means the term matters more):", size=21, gap=6)
mx = max(max(abs(v) for _, v in abl), 1e-3)
d.bars([(n, v * 100, None) for n, v in abl], mx * 100 * 1.1, unit=" pts", signed=True)
d.caption("Figure", "Ablation. Drop in MRR (×100) relative to the full model. Promo shows zero because the base catalog has no sale items; its effect is measured in 4.2.")
d.para("Robustness to preference drift: hit@3 of the full model as true preferences move further from the persona.", size=21, gap=6)
d.bars([(f"σ = {r['sigma']:.2f}", r["hit3"], None) for r in RES["noise"]], 1.0)
d.caption("Figure", "hit@3 against ground-truth perturbation σ (20 trips per persona per σ). σ = 0 is an upper bound.")

d.sub("4.2  Merchandising counterfactuals (H2)")
d.para(f"Sale on paper towels (20% off). Basket size {sale['basketBase']:.2f} → {sale['basketVariant']:.2f} items; "
       f"walking {sale['metersBase']:.1f} → {sale['metersVariant']:.1f} m per shopper.", size=21, gap=6)
d.bars([(nm(e["item"]), e["delta"], e["ci"]) for e in sale["effects"][:6]],
       max(abs(e["delta"]) + e["ci"] for e in sale["effects"][:6]) * 1.1, signed=True)
d.caption("Figure", "Change in carts per 100 shoppers with 95% CI. Negative bars are items the promotion pulls demand from.")
d.para(f"Oat cereal moved to eye level next to {nm(RES['moved_to'])}. Basket {move['basketBase']:.2f} → {move['basketVariant']:.2f}; "
       f"walking {move['metersBase']:.1f} → {move['metersVariant']:.1f} m.", size=21, gap=6)
d.bars([(nm(e["item"]), e["delta"], e["ci"]) for e in move["effects"][:6]],
       max(max(abs(e["delta"]) + e["ci"] for e in move["effects"][:6]), 0.1) * 1.1, signed=True)
d.caption("Figure", "Placement effect, same design. " + (f"Oat cereal {cer['delta']:+.1f} ± {cer['ci']:.1f}." if cer else "Oat cereal is not among the 8 largest effects: an eye-level move changes its logit by only +0.25, below the noise of 20 replicates.") )
zmax = max(abs(e["delta"]) for e in null["effects"])
d.para(f"Null control: largest absolute effect across all SKUs = {zmax:.3f} carts per 100 shoppers, as expected for identical seeds.", size=21)

d.sub("4.3  Off-persona baskets (H3)")
d.para(f"AUROC = {auroc:.3f} over {RES['anomaly']['n']} baskets. The score ignores order and quantity; "
       "BehaviorGPT's sequence-level anomaly output is the planned replacement.")

d.head("5  Gap analysis")
gaps = [
    ("Built", "Live BehaviorGPT path, replay, local fallback"),
    ("Built", "Prediction loop, cards, reasons, path, beacon, ghost branches"),
    ("Built", "What-if with paired effect and 95% CI in the control window"),
    ("Built", "Basket timeline, top-1 hits, heuristic-baseline agreement"),
    ("Built", "Experiment harness and this report from one unit test"),
    ("Gap", "Accuracy on real logs (Unbox sample sessions or a pilot store)"),
    ("Gap", "Same harness run against BehaviorGPT; needs logged live calls"),
    ("Gap", "Calibration: predicted p against observed frequency"),
    ("Gap", "Deployed web demo per Sundai 'ship' principle; app is visionOS only"),
    ("Gap", "End-to-end run of the demo route on device"),
]
d.table(["Status", "Item"], gaps, [160, 870])
d.caption("Table", "Coverage after this pass.")

d.head("6  Threats to validity")
for t in [
    "Ground truth is generated by a perturbed copy of the predictor, so accuracy is an upper bound on real behavior; it tests generalization to unseen preferences, not model fit to people.",
    "Effect sizes follow from hand-set weights (promo +0.9). They show the pipeline detects a change, not the true lift.",
    "Popularity is fit on the test data and is optimistic; random is a floor.",
    "Five personas and 32 SKUs. Real catalogs have thousands of items and long-tail behavior.",
]:
    d.para("• " + t, size=21, indent=16, gap=4)

d.head("7  Demo protocol (3 minutes)")
for t, s in [("0:00", "Problem: a shelf change takes weeks to evaluate."), ("0:20", "Paste an X handle; profile becomes a persona."),
             ("0:45", "Shopper enters; top 3 next actions with p and reason; path and beacon."),
             ("1:10", "Tap shopper: three ghosts walk the three futures."),
             ("1:30", f"Sale on paper towels: shoppers re-route; panel shows {towel['delta']:+.1f} ± {towel['ci']:.1f} carts/100."),
             ("2:00", "Basket timeline and top-1 hits; heuristic vs BehaviorGPT agreement."),
             ("2:20", "Heatmap of 50 shoppers. Close on Table 1 and the null control."),
             ("2:45", "Ask: merchandisers test planograms on predicted shoppers first.")]:
    d.para(f"{t}   {s}", size=21, gap=4)

d.head("References")
d.para("[1] Brüel-Gabrielsson R. et al. BehaviorGPT-v4: One Large Behavioral Model. Unbox AI, 2026. "
       "research.unboxai.com/behaviorgpt-v4-one-large-behavioral-model.pdf", size=19)
d.para("[2] Sundai Hack 148, Behavioral Models: Predict the Next Action. Sundai Club, MIT IHQ, 8 Nov 2026.", size=19)

d.pages[0].save(OUT, save_all=True, append_images=d.pages[1:], resolution=150)
print(OUT, len(d.pages), "pages")
