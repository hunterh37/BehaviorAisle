// Local proxy for the simulator and demos. Keys from ~/.config/behavioraisle/env, never from the repo.
// Run: node proxy/server.mjs   (listens on 127.0.0.1:8787)
// Routes: POST /predict, GET /twitter?handle= (X_BEARER_TOKEN optional, keyless mirror otherwise),
// POST /classify/body (avatar -> body), POST /classify/shop (posts -> shopping), POST /classify (both)
import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import { predict } from "./core.mjs";
import { twitterProfile, classify, classifyBody, classifyShop } from "./profile.mjs";

const envFile = `${os.homedir()}/.config/behavioraisle/env`;
if (fs.existsSync(envFile)) {
  for (const l of fs.readFileSync(envFile, "utf8").split("\n")) {
    const m = l.match(/^(\w+)=(.*)$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
  }
}
const env = process.env;
for (const k of ["UNBOXAI_API_KEY", "OPENROUTER_API_KEY"]) if (!env[k]) console.warn(`${k} missing`);

http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://127.0.0.1");
  let raw = "";
  for await (const c of req) raw += c;
  const t = Date.now();
  try {
    let out;
    if (req.method === "POST" && url.pathname === "/predict") {
      out = await predict(JSON.parse(raw), env.UNBOXAI_API_KEY, env.BEHAVIORAISLE_CATALOG_ID);
      console.log(`${Date.now() - t}ms`, out.predictions.map((p) => `${p.item_id}:${p.p.toFixed(2)}`).join(" "));
    } else if (req.method === "GET" && url.pathname === "/twitter") {
      out = await twitterProfile(url.searchParams.get("handle") ?? "", env.X_BEARER_TOKEN);
      console.log(`${Date.now() - t}ms twitter @${out.handle} ${out.tweets.length} posts`);
    } else if (req.method === "POST" && url.pathname === "/classify/body") {
      out = await classifyBody(JSON.parse(raw), env.OPENROUTER_API_KEY, env.OPENROUTER_BODY_MODEL);
      console.log(`${Date.now() - t}ms body conf=${out.confidence} hair=${out.hair_style}`);
    } else if (req.method === "POST" && url.pathname === "/classify/shop") {
      out = await classifyShop(JSON.parse(raw), env.OPENROUTER_API_KEY, env.OPENROUTER_SHOP_MODEL);
      console.log(`${Date.now() - t}ms shop wishlist=${out.wishlist.join(",")}`);
    } else if (req.method === "POST" && url.pathname === "/classify") {
      out = await classify(JSON.parse(raw), env.OPENROUTER_API_KEY);
      console.log(`${Date.now() - t}ms classify wishlist=${out.wishlist.join(",")} conf=${out.body.confidence}`);
    } else {
      res.writeHead(404).end();
      return;
    }
    res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(out));
  } catch (e) {
    console.error(url.pathname, e.message);
    res.writeHead(502).end(String(e.message));
  }
}).listen(8787, "127.0.0.1", () => console.log("Shelfcast proxy on http://127.0.0.1:8787"));
