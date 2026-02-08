/*
  Router eval: calls the live concierge-recommend edge function and checks mode routing.

  Reads router_eval_corpus.json, sends each prompt to the endpoint, compares
  the returned primary mode against the expected mode.

  Reports pass/fail per case, total pass rate.
  Exit 1 if pass rate < 90%.

  Requires an authenticated Supabase session (anon key + user JWT).
  If SUPABASE_USER_JWT is not set, tries to sign in with SUPABASE_TEST_EMAIL / SUPABASE_TEST_PASSWORD.

  Usage:
    node scripts/eval_router.js
    # or with env overrides:
    SUPABASE_USER_JWT=<jwt> node scripts/eval_router.js
*/

const fs = require("fs");
const path = require("path");
const { createClient } = require("@supabase/supabase-js");

// ---------------------------------------------------------------------------
// Config extraction (reuses same pattern as audit script)
// ---------------------------------------------------------------------------

function extractSupabaseConfigFromSwift() {
  const swiftPath = path.join(__dirname, "..", "Kuro", "Services", "SupabaseService.swift");
  const text = fs.readFileSync(swiftPath, "utf8");
  const urlMatch = text.match(/fallbackURL\s*=\s*URL\(string:\s*"([^"]+)"\)/);
  const keyMatch = text.match(/fallbackKey\s*=\s*"([^"]+)"/);
  const urlFallback = text.match(new RegExp("https://[a-z0-9]+\\.supabase\\.co", "i"));
  const keyFallback = text.match(new RegExp("eyJhbGci[0-9A-Za-z._-]+"));
  const url = urlMatch?.[1] ?? (urlFallback ? urlFallback[0] : null);
  const anonKey = keyMatch?.[1] ?? (keyFallback ? keyFallback[0] : null);
  if (!url || !anonKey) throw new Error("Could not extract Supabase config from SupabaseService.swift");
  return { url, anonKey };
}

// ---------------------------------------------------------------------------
// Auth helper
// ---------------------------------------------------------------------------

async function getAccessToken(supabaseUrl, anonKey) {
  // If a JWT is provided directly, use it.
  if (process.env.SUPABASE_USER_JWT) {
    return process.env.SUPABASE_USER_JWT;
  }

  // Try email/password sign-in if provided.
  const email = process.env.SUPABASE_TEST_EMAIL;
  const password = process.env.SUPABASE_TEST_PASSWORD;
  if (email && password) {
    const client = createClient(supabaseUrl, anonKey);
    const { data, error } = await client.auth.signInWithPassword({ email, password });
    if (error) throw new Error(`Auth failed: ${error.message}`);
    return data.session.access_token;
  }

  // Fallback: anonymous sign-in (matches existing eval patterns).
  console.log("  No credentials provided, using anonymous sign-in...");
  const client = createClient(supabaseUrl, anonKey);
  const { data, error } = await client.auth.signInAnonymously();
  if (error) throw new Error(`Anonymous auth failed: ${error.message}`);
  return data.session.access_token;
}

// ---------------------------------------------------------------------------
// Call the concierge-recommend endpoint
// ---------------------------------------------------------------------------

async function callRecommend(supabaseUrl, anonKey, accessToken, prompt) {
  const url = `${supabaseUrl}/functions/v1/concierge-recommend`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
      apikey: anonKey,
    },
    body: JSON.stringify({
      text: prompt,
      scope: "both",
      limit: 3,
      narrate: false,
    }),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    return { error: `HTTP ${res.status}: ${body.slice(0, 200)}` };
  }

  const json = await res.json();
  if (!json.success) {
    return { error: json.error || json.message || "unknown error" };
  }

  // Primary mode is the first entry in modes[] or sets[].
  const primaryMode =
    json.modes?.[0]?.id ??
    json.sets?.[0]?.modeId ??
    null;

  return { primaryMode, modes: json.modes, sets: json.sets?.map((s) => s.modeId) };
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const corpusPath = path.join(__dirname, "router_eval_corpus.json");
  const corpus = JSON.parse(fs.readFileSync(corpusPath, "utf8"));
  console.log(`\nRouter eval: ${corpus.length} test cases\n`);

  const { url: supabaseUrl, anonKey } = extractSupabaseConfigFromSwift();
  let accessToken;
  try {
    accessToken = await getAccessToken(supabaseUrl, anonKey);
  } catch (e) {
    console.error(`Auth error: ${e.message}`);
    process.exit(1);
  }

  let passed = 0;
  let failed = 0;
  let errors = 0;
  const failures = [];

  // Throttle: 2 concurrent requests max to avoid rate limits.
  const CONCURRENCY = 2;
  const results = new Array(corpus.length);

  for (let i = 0; i < corpus.length; i += CONCURRENCY) {
    const batch = corpus.slice(i, i + CONCURRENCY);
    const promises = batch.map(async (tc, j) => {
      const idx = i + j;
      const result = await callRecommend(supabaseUrl, anonKey, accessToken, tc.prompt);
      results[idx] = { tc, result };
    });
    await Promise.all(promises);

    // Small delay between batches to be friendly to the endpoint.
    if (i + CONCURRENCY < corpus.length) {
      await new Promise((r) => setTimeout(r, 300));
    }
  }

  // Report results.
  for (let idx = 0; idx < results.length; idx++) {
    const { tc, result } = results[idx];
    const num = String(idx + 1).padStart(2, " ");

    if (result.error) {
      console.log(`  ${num}. ERROR  "${tc.prompt}"`);
      console.log(`          ${result.error}`);
      errors++;
      failures.push({ ...tc, actual: "ERROR", detail: result.error });
      continue;
    }

    const actual = result.primaryMode;
    const expected = tc.expectedMode;
    const ok = actual === expected;

    if (ok) {
      console.log(`  ${num}. PASS   "${tc.prompt}" -> ${actual}`);
      passed++;
    } else {
      console.log(`  ${num}. FAIL   "${tc.prompt}"`);
      console.log(`          expected: ${expected}  got: ${actual}  (${tc.note})`);
      failed++;
      failures.push({ ...tc, actual });
    }
  }

  // Summary.
  const total = passed + failed + errors;
  const passRate = total > 0 ? ((passed / total) * 100).toFixed(1) : "0.0";
  console.log(`\n${"=".repeat(60)}`);
  console.log(`  Results: ${passed} passed, ${failed} failed, ${errors} errors out of ${total}`);
  console.log(`  Pass rate: ${passRate}%`);
  console.log(`${"=".repeat(60)}`);

  if (failures.length > 0) {
    console.log(`\nFailures:`);
    for (const f of failures) {
      console.log(`  - "${f.prompt}" expected=${f.expectedMode} got=${f.actual} (${f.note})`);
    }
  }

  const MIN_PASS_RATE = 90;
  if (parseFloat(passRate) < MIN_PASS_RATE) {
    console.log(`\nFAIL: Pass rate ${passRate}% is below threshold ${MIN_PASS_RATE}%`);
    process.exit(1);
  } else {
    console.log(`\nOK: Pass rate ${passRate}% meets threshold ${MIN_PASS_RATE}%`);
    process.exit(0);
  }
}

main().catch((e) => {
  console.error(`Fatal: ${e.message}`);
  process.exit(1);
});
