/*
  Smoke test Concierge recommendations end-to-end:
  - signs in anonymously (Supabase Auth must have anonymous enabled)
  - calls Edge Function `concierge-recommend` with a few prompts

  Usage:
    node scripts/smoke_concierge_recommend.js
*/

const fs = require("fs");
const path = require("path");
const { createClient } = require("@supabase/supabase-js");
const { getPublicProjectConfig } = require("./lib/project_config");

function extractSupabaseConfigFromSwift() {
  return getPublicProjectConfig();
}

async function callConciergeRecommend(url, anonKey, accessToken, text) {
  const res = await fetch(`${url}/functions/v1/concierge-recommend`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
      apikey: anonKey,
    },
    body: JSON.stringify({ text, scope: "both", limit: 8 }),
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
  if (authErr) {
    throw new Error(`Anonymous sign-in failed: ${authErr.message}`);
  }
  const accessToken = authData?.session?.access_token;
  if (!accessToken) throw new Error("Missing session access token from anonymous sign-in.");

  const prompts = [
    "masterpiece manga",
    "story manga like Vagabond",
    "funny anime",
    "isekai anime",
  ];

  for (const p of prompts) {
    const out = await callConciergeRecommend(url, anonKey, accessToken, p);
    const items = Array.isArray(out.items) ? out.items : [];
    console.log(`\n## ${p}`);
    console.log(`categories=${JSON.stringify(out.categories || [])} items=${items.length}`);
    for (const it of items.slice(0, 8)) {
      console.log(`- ${it.mediaType} ${it.title} (${it.year || "?"}) score=${it.averageScore ?? "?"}`);
    }
  }
}

main().catch((e) => {
  console.error(e?.message || String(e));
  process.exit(1);
});
