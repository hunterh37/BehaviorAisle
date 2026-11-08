// Shared mapping from the BehaviorAisle contract to the BehaviorGPT portal API (/api/v1/shop/recommend).
// BehaviorGPT returns a ranked list without probabilities; p is a rank prior blended with app-side
// in-store signals (sale sign, eye-level shelf) that the API has no input for.
export const CATALOG_ID = "cat_aad381c2766331790c3efaa8";
const RANK_PRIOR = [0.32, 0.22, 0.15, 0.11, 0.08, 0.06, 0.04, 0.02];

export async function predict(body, apiKey, catalogId = CATALOG_ID) {
  const history = [];
  for (const e of body.history.slice(-19)) {
    if (e.action === "view") history.push({ type: "view", item_id: e.item_id });
    else if (e.action === "add_to_cart" || e.action === "purchase") history.push({ type: "view", item_id: e.item_id });
  }
  if (body.cart.length) history.push({ type: "order", item_ids: body.cart.slice(-20) });
  const res = await fetch("https://portal.unboxai.com/api/v1/shop/recommend", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "content-type": "application/json" },
    body: JSON.stringify({ catalog_id: catalogId, kind: "for_you", limit: 8, history, user: { market: "US" } }),
  });
  if (!res.ok) throw new Error(`behaviorgpt ${res.status} ${await res.text()}`);
  const { items } = await res.json();
  const byId = Object.fromEntries(body.catalog.map((p) => [p.id, p]));
  let rows = items.filter((it) => byId[it.id]).map((it, i) => {
    const p = byId[it.id];
    let w = RANK_PRIOR[i] ?? 0.01;
    if (p.on_sale) w *= 1.8;
    const y = p.anchor?.[1] ?? 1;
    if (y > 0.8 && y < 1.6) w *= 1.15;
    return { item_id: it.id, action: i < 2 || p.on_sale ? "add_to_cart" : "view", w };
  });
  const fill = body.cart.length / 7;
  rows.push({ item_id: "checkout", action: "checkout", w: Math.max(0.01, Math.min(0.6, -0.1 + fill * 0.55)) });
  rows.sort((a, b) => b.w - a.w);
  rows = rows.slice(0, 3);
  const z = rows.reduce((s, r) => s + r.w, 0) || 1;
  const predictions = rows.map((r) => ({ item_id: r.item_id, action: r.action, p: r.w / z }));
  // Anomaly: share of cart items BehaviorGPT does not rank for this history.
  const ranked = new Set(items.map((i) => i.id));
  const anomaly = body.cart.length >= 3 ? body.cart.filter((c) => !ranked.has(c)).length / body.cart.length * 0.5 : null;
  return { predictions, anomaly };
}
