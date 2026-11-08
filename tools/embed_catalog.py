# Uploads the BehaviorAisle SKUs (parsed from Catalog.swift) as a BehaviorGPT catalog.
# Run: set -a; source ~/.config/behavioraisle/env; set +a; uv run --with behaviorgpt --with pyarrow tools/embed_catalog.py
import csv, re, pathlib
from behaviorgpt import UnboxAIClient, catalog_from_csv

root = pathlib.Path(__file__).resolve().parent.parent
src = (root / "BehaviorAisle/Model/Catalog.swift").read_text()
rows = re.findall(r'Product\(id: "([^"]+)", name: "([^"]+)", asset: "[^"]+", category: \.(\w+), price: ([\d.]+)\)', src)
out = root / "build/behavioraisle_grocery.csv"
out.parent.mkdir(exist_ok=True)
cols = ["id","name","brand","categories","image_url","event_type","group","sales_since","timestamp","frequency","market","price","currency","search_keywords","keywords"]
with out.open("w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=cols)
    w.writeheader()
    for i, n, c, p in rows:
        w.writerow({"id": i, "name": n, "brand": "Aisle Market", "categories": f"Grocery, {c.capitalize()}",
                    "event_type": "product", "group": "product", "market": "US", "price": p, "currency": "USD"})
print(len(rows), "rows")
client = UnboxAIClient(market="US")
job = client.embed(catalog_from_csv(str(out)), wait=True, timeout=1500.0)
print("CATALOG_ID", job.catalog_id)
