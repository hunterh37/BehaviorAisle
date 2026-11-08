// Cloudflare Worker: keeps the Unbox AI key server side and maps BehaviorAisle requests to BehaviorGPT.
// Secrets: UNBOX_API_KEY, UNBOX_ENDPOINT (from portal.unboxai.com), APP_TOKEN (matches the app's proxy token).
// Request (snake_case): { persona_id, history: [{action, item_id}], cart: [item_id], catalog: [{id, name, category, price, on_sale, ...}] }
// Response: { predictions: [{ item_id, action: "view"|"add_to_cart"|"checkout", p }], anomaly?: 0..1 }
// The Unbox request/response field names below are placeholders until confirmed at the Unbox workshop.
export default {
  async fetch(req, env) {
    if (req.method !== "POST") return new Response("POST only", { status: 405 });
    if (env.APP_TOKEN && req.headers.get("Authorization") !== `Bearer ${env.APP_TOKEN}`)
      return new Response("unauthorized", { status: 401 });
    const body = await req.json();
    const upstream = await fetch(env.UNBOX_ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${env.UNBOX_API_KEY}` },
      body: JSON.stringify({
        user_id: body.persona_id,
        events: body.history.map((e, i) => ({ type: e.action, item_id: e.item_id, index: i })),
        candidates: body.catalog.map((p) => ({ item_id: p.id, title: p.name, category: p.category, price: p.on_sale ? p.price * 0.8 : p.price })),
        top_k: 3,
      }),
    });
    if (!upstream.ok) return new Response(await upstream.text(), { status: 502 });
    const out = await upstream.json();
    const rows = out.predictions ?? out.results ?? [];
    const predictions = rows.slice(0, 3).map((r) => ({
      item_id: r.item_id ?? r.id,
      action: r.action ?? (r.event_type === "purchase" ? "add_to_cart" : "view"),
      p: r.p ?? r.probability ?? r.score ?? 0,
    }));
    return Response.json({ predictions, anomaly: out.anomaly ?? out.anomaly_score ?? null });
  },
};
