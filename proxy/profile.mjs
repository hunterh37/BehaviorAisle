// Profile import routes: X profile fetch (X API v2) and trait classification (OpenRouter).
// Env: X_BEARER_TOKEN, OPENROUTER_API_KEY, OPENROUTER_MODEL (vision-capable; default below).
export const DEFAULT_MODEL = "anthropic/claude-sonnet-5.5";

export async function twitterProfile(handle, bearer) {
  if (!/^\w{1,15}$/.test(handle)) throw new Error("bad handle");
  if (!bearer) throw new Error("X_BEARER_TOKEN missing");
  const h = { Authorization: `Bearer ${bearer}` };
  const u = await fetch(`https://api.x.com/2/users/by/username/${handle}?user.fields=description,location,profile_image_url,public_metrics`, { headers: h });
  if (!u.ok) throw new Error(`x user ${u.status} ${await u.text()}`);
  const { data } = await u.json();
  if (!data) throw new Error("x user not found");
  let tweets = [];
  const t = await fetch(`https://api.x.com/2/users/${data.id}/tweets?max_results=20&exclude=retweets,replies`, { headers: h });
  if (t.ok) tweets = ((await t.json()).data ?? []).map((x) => x.text);
  return {
    handle: data.username,
    name: data.name,
    bio: data.description ?? "",
    location: data.location ?? null,
    avatar_url: data.profile_image_url ?? null,
    followers: data.public_metrics?.followers_count ?? null,
    tweets,
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

const SYSTEM = `You build a realistic 3D grocery shopper avatar and shopping profile from a public X profile.
Body fields: describe only what is visible in the profile photo (apparent age, build, skin tone, hair, eyes, facial hair, clothing style).
Ancestry weights (african, asian, caucasian) only drive the face/body morph blend to match the photo; set them from visible facial features, never from names, language, location or post content.
If the photo is not a clear photo of one person (logo, cartoon, group, missing), set confidence below 0.2 and use neutral middle values.
Shopping fields: infer grocery category affinity, price sensitivity, basket size and interests from the bio and posts only.
wishlist: up to 5 ids from the given catalog the person is most likely to buy, best first. summary: one sentence, no protected traits.`;

export async function classify(body, apiKey, model = DEFAULT_MODEL) {
  if (!apiKey) throw new Error("OPENROUTER_API_KEY missing");
  const p = body.profile;
  const text = [
    `Name: ${p.name} (@${p.handle})`, `Bio: ${p.bio}`, p.location ? `Location: ${p.location}` : "",
    `Posts:\n${(p.tweets ?? []).slice(0, 20).map((t) => `- ${t}`).join("\n")}`,
    `Catalog:\n${body.catalog.map((c) => `${c.id} | ${c.name} | ${c.category} | $${c.price}`).join("\n")}`,
  ].filter(Boolean).join("\n\n");
  const content = [{ type: "text", text }];
  if (p.avatar_url) content.push({ type: "image_url", image_url: { url: p.avatar_url.replace("_normal", "_400x400") } });
  const call = (parts) => fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`, "content-type": "application/json",
      "HTTP-Referer": "https://dicyaninlabs.org", "X-Title": "Behavior Aisle",
    },
    body: JSON.stringify({
      model,
      temperature: 0.2,
      max_tokens: 1000,
      messages: [{ role: "system", content: SYSTEM }, { role: "user", content: parts }],
      response_format: { type: "json_schema", json_schema: { name: "shopper_traits", strict: true, schema: SCHEMA } },
    }),
  });
  let res = await call(content);
  // Unreachable avatar: classify from text only (body confidence comes back low).
  if (res.status === 400 && content.length > 1) res = await call(content.slice(0, 1));
  if (!res.ok) throw new Error(`openrouter ${res.status} ${await res.text()}`);
  const out = await res.json();
  const raw = out.choices?.[0]?.message?.content ?? "";
  const json = JSON.parse(raw.replace(/^```(?:json)?\s*|\s*```$/g, ""));
  const ids = new Set(body.catalog.map((c) => c.id));
  json.wishlist = (json.wishlist ?? []).filter((id) => ids.has(id));
  return json;
}
