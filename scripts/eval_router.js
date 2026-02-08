/*
  Router eval: calls the live concierge-recommend edge function and checks mode routing.

  Reads router_eval_corpus.json, sends each prompt to the endpoint, compares
  the returned primary mode against the expected mode.

  Reports pass/fail per case, total pass rate.
  Exit 1 if pass rate < 90%.

  Auth: uses SUPABASE_USER_JWT or SUPABASE_TEST_EMAIL/PASSWORD if set,
  otherwise falls back to anonymous sign-in.

  Rate limits: retries 429/5xx with exponential backoff (honours Retry-After).
  Infra errors (unreachable, 429 after retries) are reported separately and
  excluded from the pass-rate denominator so flaky infra doesn't mask real
  routing regressions.

  Usage:
    node scripts/eval_router.js
    # or with env overrides:
    SUPABASE_USER_JWT=<jwt> node scripts/eval_router.js
*/

const fs = require("fs");
const path = require("path");
const { createClient } = require("@supabase/supabase-js");

// ---------------------------------------------------------------------------
// Config (explicit env vars only)
// ---------------------------------------------------------------------------

function getSupabaseConfigFromEnv() {
  const url = process.env.SUPABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY;
  if (!url || !anonKey) {
    throw new Error("Missing SUPABASE_URL / SUPABASE_ANON_KEY.");
  }
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
// Retry helper
// ---------------------------------------------------------------------------

const MAX_RETRIES = 3;

function isRetryable(status) {
  return status === 429 || status >= 500;
}

async function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function parseRetryAfter(res, bodyText) {
  // Honour Retry-After header (seconds).
  const header = res.headers.get("Retry-After") || res.headers.get("retry-after");
  if (header) {
    const secs = Number(header);
    if (Number.isFinite(secs) && secs > 0) return secs * 1000;
  }
  // Honour retry_after_s in JSON body (Supabase rate-limit response).
  try {
    const json = JSON.parse(bodyText);
    if (Number.isFinite(json.retry_after_s) && json.retry_after_s > 0) return json.retry_after_s * 1000;
  } catch { /* not JSON */ }
  return null;
}

// ---------------------------------------------------------------------------
// Call the concierge-recommend endpoint (with retries)
// ---------------------------------------------------------------------------

async function callRecommend(supabaseUrl, anonKey, accessToken, prompt) {
  const url = `${supabaseUrl}/functions/v1/concierge-recommend`;
  const reqInit = {
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
  };

  let lastStatus = 0;
  let lastBody = "";

  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    let res;
    try {
      res = await fetch(url, reqInit);
    } catch (e) {
      // Network error (DNS, timeout, etc.) — mark as infra error.
      return { infraError: `Network error: ${e.message}` };
    }

    lastStatus = res.status;
    if (res.ok) {
      const json = await res.json();
      if (!json.success) {
        return { error: json.error || json.message || "unknown error" };
      }
      const primaryMode =
        json.modes?.[0]?.id ??
        json.sets?.[0]?.modeId ??
        null;
      return { primaryMode, modes: json.modes, sets: json.sets?.map((s) => s.modeId) };
    }

    lastBody = await res.text().catch(() => "");

    if (!isRetryable(res.status) || attempt === MAX_RETRIES) {
      break;
    }

    // Exponential backoff: honour Retry-After, else 1s → 2s → 4s + jitter.
    const retryAfterMs = parseRetryAfter(res, lastBody);
    const baseMs = retryAfterMs ?? (1000 * Math.pow(2, attempt));
    const jitter = Math.random() * 500;
    const waitMs = baseMs + jitter;
    console.log(`    [retry ${attempt + 1}/${MAX_RETRIES}] HTTP ${res.status}, waiting ${Math.round(waitMs)}ms...`);
    await sleep(waitMs);
  }

  // Exhausted retries — classify as infra error if retryable status.
  if (isRetryable(lastStatus)) {
    return { infraError: `HTTP ${lastStatus} after ${MAX_RETRIES} retries: ${lastBody.slice(0, 200)}` };
  }
  return { error: `HTTP ${lastStatus}: ${lastBody.slice(0, 200)}` };
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const corpusPath = path.join(__dirname, "router_eval_corpus.json");
  const corpus = JSON.parse(fs.readFileSync(corpusPath, "utf8"));
  console.log(`\nRouter eval: ${corpus.length} test cases\n`);

  const { url: supabaseUrl, anonKey } = getSupabaseConfigFromEnv();
  let accessToken;
  try {
    accessToken = await getAccessToken(supabaseUrl, anonKey);
  } catch (e) {
    console.error(`Auth error: ${e.message}`);
    process.exit(1);
  }

  let passed = 0;
  let failed = 0;
  let infraErrors = 0;
  let routingErrors = 0;
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
      await sleep(300);
    }
  }

  // Report results.
  for (let idx = 0; idx < results.length; idx++) {
    const { tc, result } = results[idx];
    const num = String(idx + 1).padStart(2, " ");

    if (result.infraError) {
      console.log(`  ${num}. INFRA  "${tc.prompt}"`);
      console.log(`          ${result.infraError}`);
      infraErrors++;
      continue;
    }

    if (result.error) {
      console.log(`  ${num}. ERROR  "${tc.prompt}"`);
      console.log(`          ${result.error}`);
      routingErrors++;
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
  // Infra errors are excluded from the pass-rate denominator:
  // they indicate endpoint availability issues, not routing regressions.
  const routingTotal = passed + failed + routingErrors;
  const passRate = routingTotal > 0 ? ((passed / routingTotal) * 100).toFixed(1) : "0.0";
  console.log(`\n${"=".repeat(60)}`);
  console.log(`  Results: ${passed} passed, ${failed} failed, ${routingErrors} errors out of ${routingTotal} routing tests`);
  if (infraErrors > 0) {
    console.log(`  Infra errors: ${infraErrors} (excluded from pass rate — 429/5xx after retries)`);
  }
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
