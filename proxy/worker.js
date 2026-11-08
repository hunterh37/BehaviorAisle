// Cloudflare Worker for device builds.
// Secrets: UNBOXAI_API_KEY, X_BEARER_TOKEN, OPENROUTER_API_KEY, APP_TOKEN (matches the app's proxy token).
// Optional vars: BEHAVIORAISLE_CATALOG_ID, OPENROUTER_MODEL.
import { predict } from "./core.mjs";
import { twitterProfile, classify } from "./profile.mjs";
export default {
  async fetch(req, env) {
    if (env.APP_TOKEN && req.headers.get("Authorization") !== `Bearer ${env.APP_TOKEN}`)
      return new Response("unauthorized", { status: 401 });
    const url = new URL(req.url);
    try {
      if (req.method === "GET" && url.pathname.endsWith("/twitter"))
        return Response.json(await twitterProfile(url.searchParams.get("handle") ?? "", env.X_BEARER_TOKEN));
      if (req.method !== "POST") return new Response("POST only", { status: 405 });
      if (url.pathname.endsWith("/classify"))
        return Response.json(await classify(await req.json(), env.OPENROUTER_API_KEY, env.OPENROUTER_MODEL));
      return Response.json(await predict(await req.json(), env.UNBOXAI_API_KEY, env.BEHAVIORAISLE_CATALOG_ID));
    } catch (e) {
      return new Response(String(e.message), { status: 502 });
    }
  },
};
