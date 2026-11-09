// Profile import routes. Three independent calls so the app can run them in parallel:
//   twitterProfile  X API v2 when X_BEARER_TOKEN is set, else the keyless api.fxtwitter.com mirror
//   classifyBody    avatar photo -> HumanHD body traits (vision model)
//   classifyShop    bio + posts + catalog -> shopping traits (text model)
// Env: OPENROUTER_API_KEY, OPENROUTER_BODY_MODEL, OPENROUTER_SHOP_MODEL (defaults below).
export const DEFAULT_MODEL = "anthropic/claude-sonnet-5.5";
export const BODY_MODEL = "google/gemini-3.8-flash";
export const SHOP_MODEL = "anthropic/claude-haiku-5.5";

export async function twitterProfile(handle, bearer) {
  if (!/^\w{1,15}$/.test(handle)) throw new Error("bad handle");
  return bearer ? xApiProfile(handle, bearer) : fxProfile(handle);
}

async function xApiProfile(handle, bearer) {
  const h = { Authorization: `Bearer ${bearer}` };
  const u = await fetch(`https://api.x.com/2/users/by/username/${handle}?user.fields=description,location,profile_image_url,public_metrics`, { headers: h });
  if (!u.ok) throw new Error(`x user ${u.status} ${await u.text()}`);
  const { data } = await u.json();
  if (!data) throw new Error("x user not found");
  let tweets = [];
  const t = await fetch(`https://api.x.com/2/users/${data.id}/tweets?max_results=20&exclude=retweets,replies`, { headers: h });
  if (t.ok) tweets = ((await t.json()).data ?? []).map((x) => x.text);
  return {
    handle: data.username, name: data.name, bio: data.description ?? "", location: data.location ?? null,
    avatar_url: data.profile_image_url ?? null, followers: data.public_metrics?.followers_count ?? null,
    tweets, source: "x-api",
  };
}

// The mirror returns sporadic 404s (~40%): 6 tries, 150 ms apart. Results cached 10 min for demo re-runs.
const fxCache = new Map();
async function fxGet(url) {
  let r;
  for (let i = 0; i < 6; i++) {
    r = await fetch(url, { headers: { "user-agent": "BehaviorAisle/1.0" }, signal: AbortSignal.timeout(6000) });
    if (r.ok) return r;
    await new Promise((ok) => setTimeout(ok, 150));
  }
  return r;
}

// Profile and posts fetched in parallel. Own posts first, reposts fill the rest.
async function fxProfile(handle) {
  const key = handle.toLowerCase();
  const hit = fxCache.get(key);
  if (hit && Date.now() - hit.at < 600000) return hit.value;
  const value = await fxFetch(handle);
  if (value.tweets.length) fxCache.set(key, { at: Date.now(), value });
  return value;
}

async function fxFetch(handle) {
  const get = fxGet;
  const [u, t] = await Promise.all([
    get(`https://api.fxtwitter.com/${handle}`),
    get(`https://api.fxtwitter.com/2/profile/${handle}/statuses`).catch(() => null),
  ]);
  if (u.status === 404) throw new Error("x user not found");
  if (!u.ok) throw new Error(`x user ${u.status}`);
  const user = (await u.json()).user;
  if (!user) throw new Error("x user not found");
  let tweets = [];
  if (t?.ok) {
    const rows = (await t.json()).results ?? [];
    const own = rows.filter((r) => !r.reposted_by && !r.replying_to);
    tweets = [...own, ...rows.filter((r) => !own.includes(r))].map((r) => r.text).filter(Boolean).slice(0, 20);
  }
  return {
    handle: user.screen_name, name: user.name, bio: user.description ?? "", location: user.location || null,
    avatar_url: user.avatar_url ?? null, followers: user.followers ?? null, tweets, source: "fxtwitter",
  };
}


const num = (min, max) => ({ type: "number", minimum: min, maximum: max });
const SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["body", "affinity", "price_sensitivity", "basket_size", "wishlist", "interests", "summary"],
  properties: {
    body: {
      type: "object",
      additionalProperties: false,
      required: ["gender", "age", "height", "weight", "muscle", "african", "asian", "caucasian", "skin_tone", "undertone",
        "hair_style", "hair_color", "eye_color", "facial_hair", "freckles", "outfit", "confidence"],
      properties: {
        gender: num(0, 1), age: num(18, 85), height: num(0, 1), weight: num(0, 1), muscle: num(0, 1),
        african: num(0, 1), asian: num(0, 1), caucasian: num(0, 1), skin_tone: num(0, 1), undertone: num(-0.3, 0.7),
        hair_style: { type: "string", enum: ["bald", "buzz", "short", "crop", "bob", "long", "wavy", "ponytail", "bun", "curly", "afro", "braids", "locs"] },
        hair_color: { type: "string", pattern: "^#[0-9A-Fa-f]{6}$" },
        eye_color: { type: "string", enum: ["brown", "darkBrown", "hazel", "green", "blue", "grey"] },
        facial_hair: num(0, 1.5), freckles: num(0, 1),
        outfit: { type: "string", enum: ["casual", "smart", "business", "winter", "outdoor", "athletic", "biker", "summerDress"] },
        confidence: num(0, 1),
      },
    },
    affinity: {
      type: "object",
      additionalProperties: false,
      required: ["produce", "dairy", "bakery", "pantry", "snacks", "beverages", "frozen", "household"],
      properties: Object.fromEntries(["produce", "dairy", "bakery", "pantry", "snacks", "beverages", "frozen", "household"].map((k) => [k, num(0, 1)])),
    },
    price_sensitivity: num(0, 1),
    basket_size: { type: "integer", minimum: 3, maximum: 14 },
    wishlist: { type: "array", items: { type: "string" }, maxItems: 5 },
    interests: { type: "array", items: { type: "string" }, maxItems: 6 },
    summary: { type: "string" },
  },
};


const BODY_SCHEMA = SCHEMA.properties.body;
const SHOP_SCHEMA = {
  ...SCHEMA,
  required: SCHEMA.required.filter((k) => k !== "body"),
  properties: Object.fromEntries(Object.entries(SCHEMA.properties).filter(([k]) => k !== "body")),
};

const BODY_SYSTEM = `You build a realistic 3D human avatar from one profile photo.
Describe only what is visible: apparent age, build, skin tone, hair, eyes, facial hair, clothing style.
Ancestry weights (african, asian, caucasian) only drive the face/body morph blend to match the photo; set them from visible facial features.
If the photo is not a clear photo of one person (logo, cartoon, group, missing), set confidence below 0.2 and use neutral middle values.`;

const SHOP_SYSTEM = `You build a grocery shopping profile from a public X profile.
Infer grocery category affinity, price sensitivity, basket size and interests from the bio and posts only.
interests: up to 6 short tags of 1-2 words. wishlist: up to 5 ids from the given catalog the person is most likely to buy, best first.
summary: one sentence, no protected traits.`;

export const NEUTRAL_BODY = {
  gender: 0.5, age: 30, height: 0.5, weight: 0.5, muscle: 0.5, african: 0.33, asian: 0.33, caucasian: 0.33,
  skin_tone: 0.4, undertone: 0.2, hair_style: "short", hair_color: "#2A1A10", eye_color: "brown",
  facial_hair: 0, freckles: 0, outfit: "casual", confidence: 0,
};

async function chat(apiKey, model, system, parts, name, schema, maxTokens) {
  const res = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    signal: AbortSignal.timeout(14000),
    headers: {
      Authorization: `Bearer ${apiKey}`, "content-type": "application/json",
      "HTTP-Referer": "https://dicyaninlabs.org", "X-Title": "Shelfcast",
    },
    body: JSON.stringify({
      model, temperature: 0.2, max_tokens: maxTokens,
      messages: [{ role: "system", content: system }, { role: "user", content: parts }],
      response_format: { type: "json_schema", json_schema: { name, strict: true, schema } },
    }),
  });
  if (!res.ok) throw new Error(`openrouter ${res.status} ${(await res.text()).slice(0, 200)}`);
  const out = await res.json();
  const raw = out.choices?.[0]?.message?.content ?? "";
  return JSON.parse(raw.replace(/^```(?:json)?\s*|\s*```$/g, ""));
}

const withFallback = (fn, model) => fn(model).catch((e) => (model === DEFAULT_MODEL ? Promise.reject(e) : fn(DEFAULT_MODEL)));

/** Avatar photo -> HumanHD body traits. Body: {avatar_url}. No avatar -> neutral body, confidence 0. */
export async function classifyBody(body, apiKey, model = BODY_MODEL) {
  if (!apiKey) throw new Error("OPENROUTER_API_KEY missing");
  const url = body.avatar_url?.replace("_normal", "_400x400");
  if (!url) return { ...NEUTRAL_BODY };
  const parts = [{ type: "text", text: "Profile photo:" }, { type: "image_url", image_url: { url } }];
  return withFallback((m) => chat(apiKey, m, BODY_SYSTEM, parts, "human_body", BODY_SCHEMA, 300), model);
}

/** Bio + posts + catalog -> shopping traits. Body: {profile, catalog}. */
export async function classifyShop(body, apiKey, model = SHOP_MODEL) {
  if (!apiKey) throw new Error("OPENROUTER_API_KEY missing");
  const p = body.profile;
  const text = [
    `Name: ${p.name} (@${p.handle})`, `Bio: ${p.bio}`, p.location ? `Location: ${p.location}` : "",
    `Posts:\n${(p.tweets ?? []).slice(0, 20).map((t) => `- ${t.replace(/\s+/g, " ").slice(0, 280)}`).join("\n")}`,
    `Catalog:\n${body.catalog.map((c) => `${c.id} | ${c.name} | ${c.category} | $${c.price}`).join("\n")}`,
  ].filter(Boolean).join("\n\n");
  const parts = [{ type: "text", text }];
  const json = await withFallback((m) => chat(apiKey, m, SHOP_SYSTEM, parts, "shopping_traits", SHOP_SCHEMA, 450), model);
  const ids = new Set(body.catalog.map((c) => c.id));
  json.wishlist = (json.wishlist ?? []).filter((id) => ids.has(id));
  return json;
}

/** Combined route for older builds: both classifiers in parallel. */
export async function classify(body, apiKey) {
  const [b, shop] = await Promise.all([
    classifyBody({ avatar_url: body.profile.avatar_url }, apiKey).catch(() => ({ ...NEUTRAL_BODY })),
    classifyShop(body, apiKey),
  ]);
  return { body: b, ...shop };
}
