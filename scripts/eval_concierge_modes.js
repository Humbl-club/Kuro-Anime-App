/*
  Evaluate Concierge mode routing (no feedback loop):
  - Anonymous auth (requires anonymous enabled)
  - Calls Edge Function `concierge-recommend`
  - Prints selected rails + whether LLM router was used (from `modes[].reason`)

  Usage:
    node scripts/eval_concierge_modes.js
*/

const fs = require("fs");
const path = require("path");
const { createClient } = require("@supabase/supabase-js");

function extractSupabaseConfigFromSwift() {
  const swiftPath = path.join(__dirname, "..", "Kuro", "Services", "SupabaseService.swift");
  const text = fs.readFileSync(swiftPath, "utf8");

  const urlMatch = text.match(/fallbackURL\\s*=\\s*URL\\(string:\\s*\"([^\"]+)\"\\)/);
  const keyMatch = text.match(/fallbackKey\\s*=\\s*\"([^\"]+)\"/);

  const urlFallback = text.match(new RegExp("https://[a-z0-9]+\\.supabase\\.co", "i"));
  const keyFallback = text.match(new RegExp("eyJhbGci[0-9A-Za-z._-]+"));

  const url = urlMatch?.[1] ?? (urlFallback ? urlFallback[0] : null);
  const anonKey = keyMatch?.[1] ?? (keyFallback ? keyFallback[0] : null);
  if (!url || !anonKey) {
    throw new Error("Could not extract `fallbackURL` / `fallbackKey` from SupabaseService.swift");
  }
  return { url, anonKey };
}

async function callConciergeRecommend(url, anonKey, accessToken, text) {
  const res = await fetch(`${url}/functions/v1/concierge-recommend`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
      apikey: anonKey,
    },
    body: JSON.stringify({ text, scope: "both", limit: 8, narrate: false }),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(`concierge-recommend failed (${res.status}): ${JSON.stringify(json)}`);
  }
  return json;
}

async function main() {
  const { url, anonKey } = extractSupabaseConfigFromSwift();
  const supabase = createClient(url, anonKey, { auth: { persistSession: false } });

  const { data: authData, error: authErr } = await supabase.auth.signInAnonymously();
  if (authErr) throw new Error(`Anonymous sign-in failed: ${authErr.message}`);
  const accessToken = authData?.session?.access_token;
  if (!accessToken) throw new Error("Missing session access token.");

  const prompts = [
    "classic anime",
    "must watch manga",
    "something good",
    "recommend something",
    "funny but not childish",
    "dark psychological thriller",
    "cozy slice of life",
    "hidden gems",
    "anime like Vagabond",
    "first anime where do i start",
  ];

  for (const p of prompts) {
    const out = await callConciergeRecommend(url, anonKey, accessToken, p);
    const modes = Array.isArray(out.modes) ? out.modes : [];
    const sets = Array.isArray(out.sets) ? out.sets : [];
    console.log(`\n## ${p}`);
    console.log(`modes=${modes.map((m) => `${m.id}(${Math.round((m.confidence ?? 0) * 100)}%:${m.reason || ""})`).join(" | ")}`);
    console.log(`sets=${sets.map((s) => `${s.title}(${(s.items || []).length})`).join(" + ")}`);
  }
}

main().catch((e) => {
  console.error(e?.message || String(e));
  process.exit(1);
});
