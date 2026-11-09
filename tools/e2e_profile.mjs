// Demo Flow 1 end-to-end test: @handle -> profile -> (body || shop) -> checks, through the running proxy.
// Mirrors AppModel.runFlow1: fetch, then body and shop classifiers in parallel. Budget 20 s per handle.
// Run: node proxy/server.mjs &  then  node tools/e2e_profile.mjs [handle ...]
// Output: per-handle stage ms, pass/fail; writes notes/e2e-flow1.json. Exit 1 on any failure.
// FALLBACK_OK=1 accepts classifier fallbacks (e.g. OpenRouter out of credits) as passes.
import { readFileSync, writeFileSync } from "node:fs";

const BASE = process.env.PROXY ?? "http://127.0.0.1:8787";
const BUDGET = 20000;
const handles = process.argv.slice(2).length ? process.argv.slice(2) : ["jack", "levelsio", "MKBHD", "nasa", "tim_cook"];

const src = readFileSync(new URL("../BehaviorAisle/Model/Catalog.swift", import.meta.url), "utf8");
const catalog = [...src.matchAll(/Product\(id: "([^"]+)", name: "([^"]+)", asset: "[^"]+", category: \.(\w+), price: ([\d.]+)/g)]
  .map(([, id, name, category, price]) => ({ id, name, category, price: +price }));
if (catalog.length < 20) throw new Error(`catalog parse ${catalog.length}`);
const ids = new Set(catalog.map((c) => c.id));
const CATS = ["produce", "dairy", "bakery", "pantry", "snacks", "beverages", "frozen", "household"];
const HAIR = ["bald", "buzz", "short", "crop", "bob", "long", "wavy", "ponytail", "bun", "curly", "afro", "braids", "locs"];

async function call(path, body) {
  const t = Date.now();
  const r = await fetch(BASE + path, body ? { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) } : {});
  if (!r.ok) throw new Error(`${path} ${r.status} ${(await r.text()).slice(0, 120)}`);
  return { json: await r.json(), ms: Date.now() - t };
}

async function run(handle) {
  const t0 = Date.now();
  const errs = [];
  const prof = await call(`/twitter?handle=${handle}`);
  const p = prof.json;
  // Same degradation as Flow1.swift: a failed lane falls back, the flow still completes.
  const lane = (path, body) => call(path, body).catch((e) => ({ json: null, ms: 0, err: e.message.slice(0, 90) }));
  const [body, shop] = await Promise.all([
    lane("/classify/body", { avatar_url: p.avatar_url }),
    lane("/classify/shop", { profile: p, catalog }),
  ]);
  const total = Date.now() - t0;
  const fallback = [body.err && `body: ${body.err}`, shop.err && `shop: ${shop.err}`].filter(Boolean);
  if (fallback.length && !process.env.FALLBACK_OK) errs.push(...fallback);
  const b = body.json ?? { confidence: 0, hair_style: "short", hair_color: "#2A1A10", age: 30 };
  const s = shop.json ?? { affinity: Object.fromEntries(CATS.map((c) => [c, 0.3])), wishlist: [catalog[0].id], summary: "keyword fallback" };
  if (!p.name || !Array.isArray(p.tweets)) errs.push("profile shape");
  if (!(b.confidence >= 0 && b.confidence <= 1)) errs.push("body.confidence");
  if (!HAIR.includes(b.hair_style)) errs.push(`hair ${b.hair_style}`);
  if (!/^#[0-9A-Fa-f]{6}$/.test(b.hair_color)) errs.push("hair_color");
  if (b.age < 18 || b.age > 85) errs.push("age");
  for (const c of CATS) if (!(s.affinity?.[c] >= 0 && s.affinity[c] <= 1)) errs.push(`affinity.${c}`);
  if (!s.wishlist?.length || !s.wishlist.every((id) => ids.has(id))) errs.push("wishlist");
  if (!s.summary) errs.push("summary");
  if (total > BUDGET) errs.push(`over budget ${total}ms`);
  return {
    handle, ok: errs.length === 0, errs, total_ms: total, fallback,
    ms: { fetch: prof.ms, body: body.ms, shop: shop.ms },
    source: p.source, posts: p.tweets.length, avatar: !!p.avatar_url,
    body: { conf: b.confidence, age: b.age, hair: b.hair_style, outfit: b.outfit },
    wishlist: s.wishlist, interests: s.interests,
  };
}

const results = [];
for (const h of handles) {
  try {
    const r = await run(h);
    results.push(r);
    console.log(`${r.ok ? "PASS" : "FAIL"} @${h} ${r.total_ms}ms fetch=${r.ms.fetch} body=${r.ms.body} shop=${r.ms.shop} posts=${r.posts} conf=${r.body.conf} wish=${r.wishlist.join(",")} ${r.fallback.length ? "[fallback]" : "[live]"} ${r.errs.join("; ")}`);
  } catch (e) {
    results.push({ handle: h, ok: false, errs: [e.message] });
    console.log(`FAIL @${h} ${e.message}`);
  }
}
const passed = results.filter((r) => r.ok).length;
const times = results.filter((r) => r.total_ms).map((r) => r.total_ms).sort((a, b) => a - b);
console.log(`flow1 ${passed}/${results.length} pass, max ${times.at(-1) ?? "-"}ms, median ${times[times.length >> 1] ?? "-"}ms, budget ${BUDGET}ms`);
writeFileSync(new URL("../notes/e2e-flow1.json", import.meta.url), JSON.stringify({ at: new Date().toISOString(), results }, null, 2));
process.exit(passed === results.length ? 0 : 1);
