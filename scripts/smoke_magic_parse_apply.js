/*
  Smoke test the "magic" pipeline:
  - concierge-parse extracts status/progress (English + German)
  - season parsing is present in parsed fields
  - concierge-apply writes the list row and computes progress for "last episode"/"caught up"
  - concierge-undo reverts

  Usage:
    node scripts/smoke_magic_parse_apply.js
*/

const fs = require("fs");
const path = require("path");
const { createClient } = require("@supabase/supabase-js");
const { getPublicProjectConfig } = require("./lib/project_config");

function extractSupabaseConfigFromSwift() {
  return getPublicProjectConfig();
}

async function callFn(url, anonKey, accessToken, name, payload) {
  const res = await fetch(`${url}/functions/v1/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${accessToken}`, apikey: anonKey },
    body: JSON.stringify(payload),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`${name} failed (${res.status}): ${JSON.stringify(json)}`);
  return json;
}

async function main() {
  const { url, anonKey } = extractSupabaseConfigFromSwift();
  const supabase = createClient(url, anonKey, { auth: { persistSession: false } });

  const { data: authData, error: authErr } = await supabase.auth.signInAnonymously();
  if (authErr) throw new Error(`Anonymous sign-in failed: ${authErr.message}`);
  const token = authData?.session?.access_token;
  if (!token) throw new Error("Missing access token");

  const tests = [
    { label: "EN completed last episode", text: "I watched all of One Piece until the last episode" },
    { label: "EN season progress", text: "I'm watching My Hero Academia season 2 episode 5" },
    { label: "DE season progress", text: "Ich schaue My Hero Academia Staffel 2 Folge 5" },
    { label: "DE completed", text: "Ich habe Vagabond komplett gelesen" },
    {
      label: "EN multi + noisy",
      text:
        "I watched Hopi Faraka May Academia My Academia completely and I just watched Naruto until season three episode five",
    },
  ];

  for (const t of tests) {
    const parsed = await callFn(url, anonKey, token, "concierge-parse", { text: t.text, scope: "both", limitPerItem: 8 });
    const item = parsed.items?.[0];
    const top = item?.candidates?.[0];
    console.log(`\n## ${t.label}`);
    console.log("parsed:", item?.parsed);
    console.log("top:", top ? { media_type: top.media_type, media_id: top.media_id, title_raw: top.title_raw, score: top.score } : null);

    if (!top) continue;

    const applyPayload = [{
      raw: item.raw,
      mediaType: top.media_type,
      mediaId: top.media_id,
      status: (item.parsed?.status || "PLANNING"),
      progressEpisodes: item.parsed?.progressEpisodes ?? null,
      progressChapters: item.parsed?.progressChapters ?? null,
      progressVolumes: item.parsed?.progressVolumes ?? null,
      seasonNumber: item.parsed?.seasonNumber ?? null,
      episodeInSeason: item.parsed?.episodeInSeason ?? null,
      caughtUp: item.parsed?.caughtUp ?? null,
      lastEpisode: item.parsed?.lastEpisode ?? null,
      completed: item.parsed?.completed ?? null,
      confidence: top.score,
      candidates: (item.candidates || []).slice(0, 6),
    }];

    const apply = await callFn(url, anonKey, token, "concierge-apply", { items: applyPayload });
    console.log("apply:", { success: apply.success, applied: apply.applied?.length, errors: apply.errors?.length, sessionId: apply.sessionId });

    if (apply.sessionId) {
      const undo = await callFn(url, anonKey, token, "concierge-undo", { sessionId: apply.sessionId });
      console.log("undo:", { success: undo.success, reverted: undo.reverted?.length, errors: undo.errors?.length });
    }
  }
}

main().catch((e) => {
  console.error(e?.message || String(e));
  process.exit(1);
});
