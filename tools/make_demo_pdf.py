"""Builds demo/BehaviorAisle-Intent-Demo.pdf: one 1920x1080 page per frame with a title and notes.
Usage: python3 tools/make_demo_pdf.py"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "screenshots", "raw")
OUT = os.path.join(ROOT, "demo", "BehaviorAisle-Intent-Demo.pdf")
W, H = 1920, 1080
BG, FG, DIM, ACC = (12, 14, 18), (240, 240, 240), (150, 155, 165), (94, 230, 168)

PAGES = [
    ("title", "Shelfcast: predicted intent", [
        "X profile -> interests -> predicted groceries -> the shelf they walk to.",
        "New since the X profile demo: intent panel, shelf beacon, floor path, reason per item.",
    ]),
    ("04-result.png", "1. Profile read", ["Interests and category affinity from @maya_cooks bio and posts."]),
    ("07-intent-hero.png", "2. Interest to item", [
        "Panel ties each predicted item to the interest that explains it (farmers market -> Roma Tomatoes).",
        "Probability, aisle and rank per item. Rank 1 highlighted in the shopper color.",
    ]),
    ("07b-intent-panel.png", "2b. Panel close-up", [
        "Roma Tomatoes, Red Apples, Navel Oranges, each traced to 'farmers market', Aisle 1 Produce.",
    ]),
    ("08-intent-path.png", "3. Where they go next", [
        "Marching dotted path on the floor from the shopper toward the aisle spot.",
        "Light beam and pulsing ring on the rank-1 product, quieter rings on ranks 2-3.",
    ]),
    ("gaps", "Blindspots left", [
        "Packed density hangs store generation in the simulator at 2%; captures use stocked.",
        "Probabilities are flat (7-8%) over 32 SKUs; show share vs. uniform 3% or top-3 mass.",
        "Panel and beacon too small at 3 m; needs a viewer-facing HUD or closer camera route.",
        "Rank-1 shelf (Aisle 1) sits off-frame from the center aisle; camera should pan to it.",
        "Viewer has no store-level answer: which shelves this profile will hit (aisle heat for one person).",
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


def page(kind, title, lines):
    im = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(im)
    if kind in ("title", "gaps"):
        d.text((120, 300 if kind == "title" else 140), title, font=font(84, True), fill=FG)
        y = 440 if kind == "title" else 300
        for l in lines:
            d.text((120, y), ("- " if kind == "gaps" else "") + l, font=font(40), fill=DIM)
            y += 80
        d.rectangle((120, 260 if kind == "title" else 110, 260, 268 if kind == "title" else 118), fill=ACC)
        return im
    path = os.path.join(RAW, kind)
    if not os.path.exists(path):
        d.text((120, 500), f"missing {kind}", font=font(48), fill=(255, 93, 93))
        return im
    shot = Image.open(path).convert("RGB")
    shot.thumbnail((W, 860))
    im.paste(shot, ((W - shot.width) // 2, 0))
    y = 875
    d.text((80, y), title, font=font(48, True), fill=FG)
    for i, l in enumerate(lines):
        d.text((80, y + 68 + i * 46), l, font=font(32), fill=DIM)
    return im


pages = [page(*p) for p in PAGES]
pages[0].save(OUT, save_all=True, append_images=pages[1:], resolution=144)
print(OUT, len(pages), "pages")
