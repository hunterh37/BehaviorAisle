// Local proxy for the simulator and demos. Key from ~/.config/behavioraisle/env, never from the repo.
// Run: node proxy/server.mjs   (listens on 127.0.0.1:8787, POST /predict)
import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import { predict } from "./core.mjs";

const envFile = `${os.homedir()}/.config/behavioraisle/env`;
if (!process.env.UNBOXAI_API_KEY && fs.existsSync(envFile)) {
  for (const l of fs.readFileSync(envFile, "utf8").split("\n")) {
    const m = l.match(/^(\w+)=(.*)$/);
    if (m) process.env[m[1]] = m[2];
  }
}
const key = process.env.UNBOXAI_API_KEY;
if (!key) { console.error("UNBOXAI_API_KEY missing"); process.exit(1); }

http.createServer(async (req, res) => {
  if (req.method !== "POST" || !req.url.startsWith("/predict")) { res.writeHead(404).end(); return; }
  let raw = "";
  for await (const c of req) raw += c;
  const t = Date.now();
  try {
    const out = await predict(JSON.parse(raw), key, process.env.BEHAVIORAISLE_CATALOG_ID);
    res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(out));
    console.log(`${Date.now() - t}ms`, out.predictions.map((p) => `${p.item_id}:${p.p.toFixed(2)}`).join(" "));
  } catch (e) {
    console.error(e.message);
    res.writeHead(502).end(String(e.message));
  }
}).listen(8787, "127.0.0.1", () => console.log("BehaviorAisle proxy on http://127.0.0.1:8787/predict"));
