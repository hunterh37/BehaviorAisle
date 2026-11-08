// Records real BehaviorGPT results into BehaviorAisle/Resources/predictions.jsonl, keyed the way
// PredictionLog.key builds keys (persona|last 4 "action:item"). Walks every persona from its seed
// history, branching on the top 3 predictions to DEPTH, then greedy to checkout.
// Run: node tools/record_replay.mjs   (reads UNBOXAI_API_KEY from env or ~/.config/behavioraisle/env)
import { readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { predict, CATALOG_ID } from "../proxy/core.mjs";

const DEPTH = Number(process.env.DEPTH ?? 3);
const GREEDY = 10;
let key = process.env.UNBOXAI_API_KEY;
if (!key) key = readFileSync(`${homedir()}/.config/behavioraisle/env`, "utf8").match(/UNBOXAI_API_KEY=["']?([^"'\n]+)/)[1];

const src = readFileSync(new URL("../BehaviorAisle/Model/Persona.swift", import.meta.url), "utf8");
const personas = [...src.matchAll(/Persona\(id: "([^"]+)"[\s\S]*?seedHistory: \[([^\]]*)\]/g)].map((m) => ({
  id: m[1],
  seed: [...m[2].matchAll(/\.init\(\.(\w+), "([^"]+)"\)/g)].map((e) => ({
    action: e[1] === "addToCart" ? "add_to_cart" : e[1], item_id: e[2],
  })),
}));

// Catalog ids come from the uploaded BehaviorGPT catalog (empty history returns many of them).
const probe = await fetch("https://portal.unboxai.com/api/v1/shop/recommend", {
  method: "POST",
  headers: { Authorization: `Bearer ${key}`, "content-type": "application/json" },
  body: JSON.stringify({ catalog_id: CATALOG_ID, kind: "for_you", limit: 100, history: [], user: { market: "US" } }),
});
const catSrc = readFileSync(new URL("../BehaviorAisle/Model/Catalog.swift", import.meta.url), "utf8");
const ids = new Set([...catSrc.matchAll(/id: "([a-z0-9_-]+)"/g)].map((m) => m[1]));
for (const it of (await probe.json()).items ?? []) ids.add(it.id);
const catalog = [...ids].map((id) => ({ id, on_sale: false, anchor: [0, 1.2, 0] }));

const out = new Map();
let calls = 0;
const keyOf = (pid, h) => pid + "|" + h.slice(-4).map((e) => `${e.action}:${e.item_id}`).join(",");

async function step(pid, history, cart) {
  const k = keyOf(pid, history);
  if (out.has(k)) return out.get(k);
  calls++;
  const r = await predict({ history, cart, catalog }, key);
  const result = {
    predictions: r.predictions.map((p) => ({ itemId: p.item_id, action: p.action, p: p.p })),
    ...(r.anomaly == null ? {} : { anomaly: r.anomaly }),
    source: "behaviorgpt",
  };
  out.set(k, result);
  return result;
}

const apply = (h, c, p) => [[...h, { action: p.action, item_id: p.itemId }], p.action === "add_to_cart" ? [...c, p.itemId] : c];

async function walk(pid, h, c, depth) {
  const r = await step(pid, h, c);
  const items = r.predictions.filter((p) => p.action !== "checkout");
  if (depth < DEPTH) {
    for (const p of items) await walk(pid, ...apply(h, c, p), depth + 1);
  } else {
    let [hh, cc] = [h, c];
    for (let i = 0; i < GREEDY; i++) {
      const g = (await step(pid, hh, cc)).predictions.find((p) => p.action !== "checkout");
      if (!g) break;
      [hh, cc] = apply(hh, cc, g);
    }
  }
}

await Promise.all(personas.map((p) => walk(p.id, p.seed, [], 0)));
const lines = [...out].map(([k, result]) => JSON.stringify({ key: k, result })).join("\n") + "\n";
writeFileSync(new URL("../BehaviorAisle/Resources/predictions.jsonl", import.meta.url), lines);
console.log(`personas ${personas.length} calls ${calls} keys ${out.size}`);
