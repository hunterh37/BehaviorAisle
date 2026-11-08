// Cloudflare Worker for device builds. Secrets: UNBOXAI_API_KEY, APP_TOKEN (matches the app's proxy token).
import { predict } from "./core.mjs";
export default {
  async fetch(req, env) {
    if (req.method !== "POST") return new Response("POST only", { status: 405 });
    if (env.APP_TOKEN && req.headers.get("Authorization") !== `Bearer ${env.APP_TOKEN}`)
      return new Response("unauthorized", { status: 401 });
    try {
      return Response.json(await predict(await req.json(), env.UNBOXAI_API_KEY, env.BEHAVIORAISLE_CATALOG_ID));
    } catch (e) {
      return new Response(String(e.message), { status: 502 });
    }
  },
};
