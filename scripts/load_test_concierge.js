/*
  Lightweight load test for Concierge Edge Functions.

  Usage:
    node scripts/load_test_concierge.js

  Env:
    CONCURRENCY=20
    DURATION_SECONDS=25
    MIX=parse,recommend   (comma-separated)
    NARRATE=0|1           (recommend only; default 0 to avoid LLM spend)
    MULTI_USER=0|1        (default 0; if 1, each worker signs in separately)
    FAKE_IP=0|1           (default 0; if 1, sends randomized x-forwarded-for per request)
*/

const fs = require("fs");
const path = require("path");
const { createClient } = require("@supabase/supabase-js");

function extractSupabaseConfigFromSwift() {
  const swiftPath = path.join(__dirname, "..", "Kuro", "Services", "SupabaseService.swift");
  const text = fs.readFileSync(swiftPath, "utf8");
  const urlMatch = text.match(/fallbackURL\s*=\s*URL\(string:\s*"([^"]+)"\)/);
  const keyMatch = text.match(/fallbackKey\s*=\s*"([^"]+)"/);
  const url = urlMatch?.[1];
  const anonKey = keyMatch?.[1];
  if (!url || !anonKey) throw new Error("Could not extract Supabase URL/key from SupabaseService.swift");
  return { url, anonKey };
}

async function callFn(url, anonKey, accessToken, name, payload, extraHeaders = {}) {
  const res = await fetch(`${url}/functions/v1/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
      apikey: anonKey,
      ...extraHeaders,
    },
    body: JSON.stringify(payload),
  });
  const body = await res.text();
  let json;
  try {
    json = JSON.parse(body);
  } catch {
    json = { raw: body };
  }
  return { ok: res.ok, status: res.status, json };
}

function pct(values, p) {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const idx = Math.min(sorted.length - 1, Math.max(0, Math.floor((p / 100) * sorted.length)));
  return sorted[idx];
}

function pick(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

async function main() {
  const { url, anonKey } = extractSupabaseConfigFromSwift();
  const concurrency = Number(process.env.CONCURRENCY || 20);
  const durationSeconds = Number(process.env.DURATION_SECONDS || 25);
  const mix = String(process.env.MIX || "parse,recommend")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  const narrate = String(process.env.NARRATE || "0") === "1";
  const multiUser = String(process.env.MULTI_USER || "0") === "1";
  const fakeIp = String(process.env.FAKE_IP || "0") === "1";

  const supabase = createClient(url, anonKey, { auth: { persistSession: false } });
  const { data: authData, error: authErr } = await supabase.auth.signInAnonymously();
  if (authErr) throw new Error(`Anonymous sign-in failed: ${authErr.message}`);
  const rootToken = authData?.session?.access_token;
  if (!rootToken) throw new Error("Missing access token");

  const parsePrompts = [
    "I watched AoT (completed), JJK up to ep 12",
    "Ich habe Vagabond komplett gelesen und ich schaue Naruto Staffel 3 Folge 5",
    "I'm watching My Hero Academia season 2 episode 5",
    "I read Berserk up to chapter 100",
  ];

  const recPrompts = [
    "something funny but not childish",
    "premium action anime",
    "cozy slice of life",
    "sad but hopeful",
  ];

  const latMs = [];
  const statusCounts = new Map();
  let total = 0;

  const endAt = Date.now() + durationSeconds * 1000;

  async function worker() {
    let token = rootToken;
    if (multiUser) {
      const tmp = createClient(url, anonKey, { auth: { persistSession: false } });
      const { data, error } = await tmp.auth.signInAnonymously();
      if (error) throw new Error(`Anonymous sign-in failed: ${error.message}`);
      token = data?.session?.access_token || rootToken;
    }

    while (Date.now() < endAt) {
      const kind = pick(mix);
      const t0 = Date.now();
      const extraHeaders = fakeIp
        ? {
            "x-forwarded-for": `100.64.${Math.floor(Math.random() * 255)}.${Math.floor(Math.random() * 255)}`,
          }
        : {};
      let res;
      if (kind === "recommend") {
        res = await callFn(
          url,
          anonKey,
          token,
          "concierge-recommend",
          {
            text: pick(recPrompts),
            scope: "both",
            limit: 8,
            narrate,
          },
          extraHeaders
        );
      } else {
        // parse
        res = await callFn(
          url,
          anonKey,
          token,
          "concierge-parse",
          {
            text: pick(parsePrompts),
            scope: "both",
            limitPerItem: 10,
          },
          extraHeaders
        );
      }
      const dt = Date.now() - t0;
      latMs.push(dt);
      total++;
      statusCounts.set(res.status, (statusCounts.get(res.status) || 0) + 1);
    }
  }

  await Promise.all(Array.from({ length: Math.max(1, concurrency) }, () => worker()));

  console.log("CONCIERGE LOAD TEST");
  console.log(`total_requests=${total}`);
  console.log(
    `concurrency=${concurrency} duration_s=${durationSeconds} mix=${mix.join(",")} narrate=${narrate ? 1 : 0} multi_user=${
      multiUser ? 1 : 0
    } fake_ip=${fakeIp ? 1 : 0}`
  );
  for (const [k, v] of [...statusCounts.entries()].sort((a, b) => a[0] - b[0])) {
    console.log(`status_${k}=${v}`);
  }
  console.log(
    `lat_ms_p50=${pct(latMs, 50)} lat_ms_p90=${pct(latMs, 90)} lat_ms_p95=${pct(latMs, 95)} lat_ms_p99=${pct(
      latMs,
      99
    )}`
  );
}

main().catch((e) => {
  console.error(e?.message || String(e));
  process.exit(1);
});
