"""Builds demo/BehaviorAisle-Promo.pdf from screenshots/raw/p*.png (StageDirector captures).
Usage: python3 tools/make_promo_pdf.py"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "screenshots", "raw")
OUT = os.path.join(ROOT, "demo", "BehaviorAisle-Promo.pdf")
W, H = 1920, 1080
BG, FG, DIM, ACC = (12, 14, 18), (240, 240, 240), (150, 155, 165), (94, 230, 168)

# (file, crop window only, title, lines)
PAGES = [
    ("title", False, "Shelfcast", [
        "Test a store change on simulated shoppers before moving a single box.",
        "BehaviorGPT predicts each shopper's next action; paired simulation prices the change.",
        "Apple Vision Pro, 1:1 grocery store.",
    ]),
    ("p1-store.png", False, "1. Shoppers you can watch decide", [
        "Each HumanHD shopper walks a full-scale store; the panel shows its top predicted items and why.",
        "@maya_cooks: Bananas 10%, Red Apples 8%, Sourdough 7%, each traced to an interest.",
    ]),
    ("p2-profile.png", True, "2. A shopper from a real profile", [
        "Bio and posts become category affinity and a likely-to-buy list.",
        "Sourdough, tomatoes, yogurt, avocado, olive oil for a home cook who runs.",
    ]),
    ("p3-move.png", True, "3. Move a product, read the answer in dollars", [
        "Coffee moved to the front of aisle 3: +$196 margin / store / week, but ±$391.",
        "Verdict reads No clear effect. The tool refuses to call noise a win.",
    ]),
    ("p4-sale.png", True, "4. A promotion that loses money", [
        "Chips 20% off: +17.4 units per 100 shoppers, almost double.",
        "Margin: −$2,595 / store / week (±$886). Do not ship. Cola, ice cream lose units to chips.",
    ]),
    ("p5-stockout.png", True, "5. Price a stock-out", [
        "Cola out of stock: 88% of lost units move to other SKUs, 12% walk away.",
        "Tells a buyer which gaps cost money and which ones shoppers absorb.",
    ]),
    ("p6-plan.png", True, "6. Test the whole plan before reset night", [
        "Move + sale + stock-out together on 2,000 paired shoppers.",
        "−$2,041 margin / store / week, −$53M a year across 500 stores. Promo ROI −0.6x.",
    ]),
    ("p7-validation.png", True, "7. Checked on real baskets", [
        "600 held-out Instacart baskets, next-item hit@3.",
        "Fitted model 25.2% vs popularity 23.8% and random 9.3%. BehaviorGPT 12.5% on this mapping.",
    ]),
    ("text", False, "Assumptions in the numbers", [
        "Margins are category averages (produce 35%, dairy 25%, snacks 40% ...); sale = 20% off, cost fixed.",
        "12,000 shoppers / store / week, 500 stores. Effects from the fitted heuristic shopper model.",
        "Shelf position, sale and walking-distance terms have no real-data fit yet.",
        "BehaviorGPT drives live shoppers; paired simulation runs the heuristic for speed.",
    ]),
]


def font(size, bold=False):
    for p in ["/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc"]:
        if os.path.exists(p):
            try:
                f = ImageFont.truetype(p, size)
                if bold:
                    try: f.set_variation_by_name("Bold")
                    except Exception: pass
                return f
            except Exception:
                pass
    return ImageFont.load_default()


def page(kind, crop, title, lines):
    im = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(im)
    if kind in ("title", "text"):
        top = 300 if kind == "title" else 140
        d.rectangle((120, top - 40, 260, top - 32), fill=ACC)
        d.text((120, top), title, font=font(84, True), fill=FG)
        y = top + 150
        for l in lines:
            d.text((120, y), l, font=font(38), fill=DIM)
            y += 72
        return im
    shot = Image.open(os.path.join(RAW, kind)).convert("RGB")
    if crop:  # window region: center 1700x1500 of the 3840x2160 still, shown left; text right
        cx, cy = shot.width // 2, shot.height // 2
        shot = shot.crop((cx - 850, cy - 700, cx + 850, cy + 800))
        shot.thumbnail((1000, H - 80))
        im.paste(shot, (60, (H - shot.height) // 2))
        x, y, wrap = 1120, 260, 34
    else:
        shot.thumbnail((W, 860))
        im.paste(shot, ((W - shot.width) // 2, 0))
        x, y, wrap = 80, 875, 200
    d.text((x, y), title if crop is False else "", font=font(48, True), fill=FG)
    if crop:
        y = draw_wrapped(d, title, x, y, font(52, True), FG, 26, 64)
        y += 30
        for l in lines:
            y = draw_wrapped(d, l, x, y, font(34), DIM, wrap, 48) + 24
    else:
        for i, l in enumerate(lines):
            d.text((x, y + 68 + i * 46), l, font=font(32), fill=DIM)
    return im


def draw_wrapped(d, text, x, y, f, fill, width, step):
    words, line = text.split(), ""
    for w in words:
        if len(line) + len(w) + 1 > width and line:
            d.text((x, y), line, font=f, fill=fill); y += step; line = w
        else:
            line = (line + " " + w).strip()
    if line:
        d.text((x, y), line, font=f, fill=fill); y += step
    return y


pages = [page(*p) for p in PAGES]
pages[0].save(OUT, save_all=True, append_images=pages[1:], resolution=144)
print(OUT, len(pages), "pages")
