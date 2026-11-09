"""Builds demo/BehaviorAisle-BehaviorGPT-Console.pdf from screenshots/raw/p*.png (StageDirector captures).
Usage: python3 tools/make_promo_pdf.py"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "screenshots", "raw")
OUT = os.path.join(ROOT, "demo", "BehaviorAisle-BehaviorGPT-Console.pdf")
W, H = 1920, 1080
BG, FG, DIM, ACC = (12, 14, 18), (240, 240, 240), (150, 155, 165), (94, 230, 168)

# (file, crop window only, title, lines)
PAGES = [
    ("title", False, "Shelfcast x BehaviorGPT", [
        "Every shopper step is a live call to Unbox AI BehaviorGPT, shown on a large console window.",
        "Request, ranked reply and the shopper update appear side by side as the store runs.",
        "Captured from the app on the visionOS simulator with real network calls, 8 Nov 2026.",
    ]),
    ("a1-console-live.png", True, "1. Live calls, one per shopper step", [
        "Party Host: history of 3 views sent to portal.unboxai.com/api/v1/shop/recommend.",
        "HTTP 200 in 592 ms. BehaviorGPT ranks Cheddar Block, Frozen Pizza, Butter.",
        "Shopper adds Cheddar Block; history 3 to 4. Six calls, five live replies, zero failures.",
    ]),
    ("a2-console-raw.png", True, "2. Raw JSON on demand", [
        "Raw JSON toggle shows the exact body sent (catalog_id, history events) and the reply items.",
        "Judges can read the wire format; nothing is mocked between the model and the shopper.",
    ]),
    ("text", False, "What the console proves", [
        "Request card: endpoint and the history events actually sent.",
        "Response card: HTTP status, network latency, BehaviorGPT rank order.",
        "Shopper update card: probabilities, chosen action, history and cart counters after apply.",
        "Source tag per call: BEHAVIORGPT LIVE, BEHAVIORGPT REPLAY or heuristic fallback.",
        "Offline safety: 692 recorded BehaviorGPT replies bundled (tools/record_replay.mjs).",
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
        shot = shot.crop((cx - 820, cy - 1000, cx + 820, cy + 700))
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
