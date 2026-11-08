# Held-out next-item validation on the Instacart Market Basket dataset (real baskets, add-to-cart order).
# Maps Instacart products onto the 32 BehaviorAisle SKUs, then scores each model on "given the items added so
# far, which SKU is added next". Writes demo/validation.json and BehaviorAisle/Resources/validation.json.
#
# Data: https://huggingface.co/datasets/attik/Instacart-Market-Basket-Analysis (mirror of the Kaggle files).
#   products.csv, order_products__train.csv into $INSTACART_DIR (default ~/Dev/BehaviorAisle-data/instacart).
# Run:  set -a; source ~/.config/behavioraisle/env; set +a; python3 tools/validate_instacart.py [--n 400]
import argparse, csv, json, math, os, pathlib, random, re, urllib.request, zlib
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = pathlib.Path(os.environ.get("INSTACART_DIR", pathlib.Path.home() / "Dev/BehaviorAisle-data/instacart"))
W_CO = 2.0
CATALOG_ID = "cat_aad381c2766331790c3efaa8"

# Instacart aisle id -> SKU, optionally gated by a product-name regex.
AISLE_SKU = {84: "milk", 120: "yogurt", 21: "cheese", 2: "cheese", 86: "eggs", 36: "butter", 112: "bread",
             121: "cereal", 131: "pasta", 69: "soup", 19: "oil", 88: "pb", 63: "rice", 26: "coffee",
             107: "chips", 61: "cookies", 45: "chocolate", 77: "soda", 115: "water", 98: "juice", 79: "pizza",
             37: "icecream", 114: "spray", 54: "towels"}
NAMED = [(24, r"\bbanana", "banana"), (24, r"\bapple", "apple"), (24, r"\borange", "orange"),
         (24, r"\blemon|\blime", "lemon"), (24, r"\bavocado", "avocado"), (83, r"\bavocado", "avocado"),
         (83, r"\bbroccoli", "broccoli"), (123, r"\bbroccoli", "broccoli"),
         (83, r"lettuce|romaine|spinach", "lettuce"), (123, r"lettuce|romaine|spinach|salad", "lettuce"),
         (83, r"tomato", "tomato"), (72, r"ketchup", "ketchup")]


def parse_catalog():
    src = (ROOT / "BehaviorAisle/Model/Catalog.swift").read_text()
    rows = re.findall(r'Product\(id: "([^"]+)", name: "[^"]+", asset: "[^"]+", category: \.(\w+), price: ([\d.]+)\)', src)
    return {i: {"category": c, "price": float(p)} for i, c, p in rows}


def parse_personas():
    src = (ROOT / "BehaviorAisle/Model/Persona.swift").read_text()
    out = []
    for m in re.finditer(r'id: "([^"]+)".*?affinity: \[(.*?)\],\s*priceSensitivity: ([\d.]+), basketSize: (\d+)', src, re.S):
        aff = {k: float(v) for k, v in re.findall(r"\.(\w+): ([\d.]+)", m.group(2))}
        out.append({"id": m.group(1), "affinity": aff, "price": float(m.group(3)), "basket": int(m.group(4))})
    return out


def load_baskets():
    sku = {}
    for r in csv.DictReader(open(DATA / "products.csv")):
        a, name = int(r["aisle_id"]), r["product_name"].lower()
        s = next((k for aisle, rx, k in NAMED if aisle == a and re.search(rx, name)), None) or AISLE_SKU.get(a)
        if s: sku[r["product_id"]] = s
    orders = defaultdict(list)
    for r in csv.DictReader(open(DATA / "order_products__train.csv")):
        s = sku.get(r["product_id"])
        if s: orders[r["order_id"]].append((int(r["add_to_cart_order"]), s))
    baskets = {}
    for oid, rows in orders.items():
        seq = []
        for _, s in sorted(rows):
            if s not in seq: seq.append(s)
        if len(seq) >= 3: baskets[oid] = seq
    return baskets, len(orders), len(sku)


# Port of HeuristicPredictor.rank (no store position: Instacart has none; no promos).
COMPLEMENTS = {"produce": {"dairy", "pantry"}, "pantry": {"produce", "dairy"}, "snacks": {"beverages", "frozen"},
               "beverages": {"snacks"}, "bakery": {"dairy"}, "dairy": {"bakery", "produce"}, "frozen": {"snacks"}}


def heuristic_rank(cart, persona, cat):
    maxp = max(p["price"] for p in cat.values())
    last = cat[cart[-1]]["category"] if cart else None
    scores = {}
    for i, p in cat.items():
        if i in cart: continue
        s = persona["affinity"].get(p["category"], 0.2) * 2.2 - persona["price"] * p["price"] / maxp * 1.4
        if last and p["category"] in COMPLEMENTS.get(last, ()): s += 0.35
        scores[i] = s
    return sorted(scores, key=lambda k: -scores[k])


def pick_persona(cart, personas, cat):
    return max(personas, key=lambda q: sum(math.log(max(q["affinity"].get(cat[c]["category"], 0.2), 0.02)) for c in cart))


def behaviorgpt_rank(cart, key, cache):
    k = ",".join(cart)
    if k in cache: return cache[k]
    history = [{"type": "view", "item_id": c} for c in cart] + [{"type": "order", "item_ids": cart}]
    body = json.dumps({"catalog_id": CATALOG_ID, "kind": "for_you", "limit": 24, "history": history, "user": {"market": "US"}})
    req = urllib.request.Request("https://portal.unboxai.com/api/v1/shop/recommend", body.encode(),
                                 {"Authorization": f"Bearer {key}", "content-type": "application/json"})
    for _ in range(3):
        try:
            items = json.load(urllib.request.urlopen(req, timeout=20))["items"]
            cache[k] = [i["id"] for i in items]
            return cache[k]
        except Exception as e:
            err = e
    raise err


def score(name, samples, ranker):
    h1 = h3 = rr = 0.0
    for cart, truth in samples:
        r = ranker(cart)
        if truth in r:
            i = r.index(truth)
            h1 += i == 0; h3 += i < 3; rr += 1 / (i + 1)
    n = len(samples)
    return {"name": name, "hit1": h1 / n, "hit3": h3 / n, "mrr": rr / n, "n": n}


def bootstrap_ci(samples, ra, rb, reps=1000, seed=3):
    """95% CI of hit@3(a) - hit@3(b), paired bootstrap over test prefixes."""
    da = [int(t in ra(c)[:3]) - int(t in rb(c)[:3]) for c, t in samples]
    rng, n, means = random.Random(seed), len(da), []
    for _ in range(reps):
        means.append(sum(da[rng.randrange(n)] for _ in range(n)) / n)
    means.sort()
    return sum(da) / n, means[int(reps * 0.025)], means[int(reps * 0.975)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=400, help="held-out baskets scored with BehaviorGPT")
    a = ap.parse_args()
    cat, personas = parse_catalog(), parse_personas()
    baskets, n_orders, n_products = load_baskets()
    # 80/20 split by order id hash; baselines fit on train only.
    train = [b for o, b in baskets.items() if zlib.crc32(o.encode()) % 5]
    test = [b for o, b in baskets.items() if not zlib.crc32(o.encode()) % 5]
    rng = random.Random(11)
    rng.shuffle(test)
    test = test[:a.n]
    samples = []
    for b in test:
        k = rng.randrange(1, len(b))
        samples.append((b[:k], b[k]))

    freq = Counter(s for b in train for s in b)
    pop = [s for s, _ in freq.most_common()] + [s for s in cat if s not in freq]
    co = defaultdict(Counter)
    for b in train:
        for i, x in enumerate(b):
            for y in b[i + 1:]:
                co[x][y] += 1; co[y][x] += 1

    def popularity(cart): return [s for s in pop if s not in cart]
    def cooccur(cart):
        sc = Counter()
        for c in cart:
            tot = sum(co[c].values()) or 1
            for y, v in co[c].items(): sc[y] += v / tot
        return sorted((s for s in cat if s not in cart), key=lambda s: (-sc[s], pop.index(s)))
    def heuristic(cart): return heuristic_rank(cart, pick_persona(cart, personas, cat), cat)
    # Fitted: the app heuristic's fitted terms (log popularity + log P(next | cart) from train co-occurrence).
    total = sum(freq.values())
    logpop = {s: math.log((freq[s] + 1) / (total + len(cat))) for s in cat}
    cond = {x: {y: (co[x][y] + 0.5) / (sum(co[x].values()) + 0.5 * len(cat)) for y in cat} for x in cat}
    def fitted_score(cart, s): return logpop[s] + W_CO * sum(math.log(cond[c][s]) for c in cart) / max(len(cart), 1)
    def fitted(cart): return sorted((s for s in cat if s not in cart), key=lambda s: -fitted_score(cart, s))
    def random_rank(cart):
        r = [s for s in cat if s not in cart]
        random.Random(",".join(cart)).shuffle(r)
        return r

    key = os.environ.get("UNBOXAI_API_KEY")
    cache_path = DATA / "behaviorgpt_cache.json"
    cache = json.loads(cache_path.read_text()) if cache_path.exists() else {}
    models = [("Random", random_rank), ("Popularity", popularity), ("Co-occurrence", cooccur), ("Heuristic", heuristic), ("Fitted heuristic", fitted)]
    if key:
        with ThreadPoolExecutor(8) as ex:
            list(ex.map(lambda s: behaviorgpt_rank(s[0], key, cache), samples))
        cache_path.write_text(json.dumps(cache))
        # API returns at most 24 SKUs; unranked SKUs follow in popularity order so MRR is defined.
        def bgpt(cart):
            r = [s for s in cache[",".join(cart)] if s in cat and s not in cart]
            return r + [s for s in pop if s not in cart and s not in r]
        models.append(("BehaviorGPT", bgpt))
    scores = [score(n, samples, f) for n, f in models]
    out = {"dataset": "Instacart Market Basket (order_products__train)", "orders": n_orders, "mapped_products": n_products,
           "baskets": len(baskets), "train_baskets": len(train), "test_prefixes": len(samples),
           "task": "next new SKU added to cart, given the SKUs added before it (32 SKUs)",
           "scores": scores, "category_share": {c: round(sum(v for s, v in freq.items() if cat[s]["category"] == c) / sum(freq.values()), 4)
                                                 for c in sorted({p["category"] for p in cat.values()})}}
    if key:
        d, lo, hi = bootstrap_ci(samples, bgpt, heuristic)
        out["behaviorgpt_minus_heuristic_hit3"] = {"delta": d, "lo": lo, "hi": hi}
    d, lo, hi = bootstrap_ci(samples, fitted, heuristic)
    out["fitted_minus_heuristic_hit3"] = {"delta": d, "lo": lo, "hi": hi}
    (ROOT / "BehaviorAisle/Resources").mkdir(exist_ok=True)
    (ROOT / "BehaviorAisle/Resources/fitted_terms.json").write_text(json.dumps(
        {"source": "Instacart train split", "w_co": W_CO, "logpop": logpop,
         "cond": {x: {y: math.log(v) for y, v in r.items()} for x, r in cond.items()}}, indent=1))
    for p in (ROOT / "demo/validation.json", ROOT / "BehaviorAisle/Resources/validation.json"):
        p.parent.mkdir(exist_ok=True)
        p.write_text(json.dumps(out, indent=2))
    for s in scores: print(f"{s['name']:14} hit1 {s['hit1']:.3f}  hit3 {s['hit3']:.3f}  mrr {s['mrr']:.3f}  n {s['n']}")
    print("fitted-heuristic hit3", out["fitted_minus_heuristic_hit3"])
    if key: print("BGPT-heuristic hit3", out["behaviorgpt_minus_heuristic_hit3"])


if __name__ == "__main__":
    main()
