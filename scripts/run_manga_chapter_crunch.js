/*
  Continuous zero-row manga chapter crunch worker.

  Behavior:
  - calls manga-chapter-enrich in crunch mode (zero-row only)
  - prints per-cycle progress and rolling 1h zero-row burn-down
  - stops at reachable-zero criteria:
      * zero rows reaches 0, or
      * over last 6h: no zero-row decrease, no chapter upserts, no pending-queue improvement
*/

const { createClient } = require("@supabase/supabase-js");
const { getProjectUrl } = require("./lib/project_config");

process.stdout.on("error", (err) => {
  if (err && err.code === "EPIPE") process.exit(0);
});

const SUPABASE_URL = process.env.SUPABASE_URL ?? getProjectUrl();
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const IMPORT_SECRET = process.env.IMPORT_SECRET ?? process.env.SUPABASE_IMPORT_SECRET;
if (!SERVICE_ROLE_KEY) throw new Error("Missing SUPABASE_SERVICE_ROLE_KEY env var.");
if (!IMPORT_SECRET) throw new Error("Missing IMPORT_SECRET (or SUPABASE_IMPORT_SECRET) env var.");

const FUNCTIONS_BASE = process.env.SUPABASE_FUNCTIONS_BASE
  ?? `https://${new URL(SUPABASE_URL).host.replace(".supabase.co", ".functions.supabase.co")}`;

const LOOP_LIMIT = clampInt(process.env.CRUNCH_LIMIT, 40, 1, 200);
const LOOP_SLEEP_MS = clampInt(process.env.CRUNCH_SLEEP_MS, 30_000, 1_000, 300_000);
const LOOP_TIME_BUDGET_MS = clampInt(process.env.CRUNCH_TIME_BUDGET_MS, 45_000, 8_000, 120_000);
const PLATEAU_HOURS = clampInt(process.env.CRUNCH_PLATEAU_HOURS, 6, 1, 48);
const MAX_CONSECUTIVE_ERRORS = clampInt(process.env.CRUNCH_MAX_CONSECUTIVE_ERRORS, 8, 1, 50);

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

function clampInt(raw, fallback, min, max) {
  const parsed = Number.parseInt(String(raw ?? ""), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function fmtIso(value) {
  return new Date(value).toISOString();
}

async function callEnrichCrunch() {
  const res = await fetch(`${FUNCTIONS_BASE}/manga-chapter-enrich`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      "x-import-secret": IMPORT_SECRET,
    },
    body: JSON.stringify({
      zeroRowOnly: true,
      crunchMode: true,
      limit: LOOP_LIMIT,
      scheduleSafe: true,
      timeBudgetMs: LOOP_TIME_BUDGET_MS,
      languages: ["en", "de"],
      includeFallbackAllLanguages: true,
    }),
  });

  const bodyText = await res.text();
  let body = null;
  try {
    body = JSON.parse(bodyText);
  } catch {
    // ignored
  }
  if (!res.ok) {
    throw new Error(`manga-chapter-enrich ${res.status}: ${bodyText.slice(0, 300)}`);
  }
  return body ?? {};
}

async function getCrunchMetrics() {
  const { data, error } = await supabase.rpc("get_manga_chapter_enrich_metrics", { p_hours: 24 });
  if (error) throw new Error(`get_manga_chapter_enrich_metrics failed: ${error.message}`);
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) throw new Error("get_manga_chapter_enrich_metrics returned no row");
  return {
    zeroRows: Number(row.manga_zero_chapter_rows ?? 0),
    unresolvedPending: Number(row.unresolved_pending ?? 0),
  };
}

function computeRollingOneHourDelta(samples) {
  const now = Date.now();
  const windowStart = now - (60 * 60 * 1000);
  const window = samples.filter((sample) => sample.ts >= windowStart);
  if (window.length < 2) return 0;
  return window[0].zeroRows - window[window.length - 1].zeroRows;
}

function reachedReachableZeroPlateau(samples, plateauHours) {
  const plateauMs = plateauHours * 60 * 60 * 1000;
  const now = Date.now();
  const window = samples.filter((sample) => sample.ts >= (now - plateauMs));
  if (window.length < 2) return false;
  const elapsed = window[window.length - 1].ts - window[0].ts;
  if (elapsed < plateauMs) return false;

  const zeroRowDecrease = window[0].zeroRows - window[window.length - 1].zeroRows;
  const cumulativeUpserts = window.reduce((sum, sample) => sum + sample.chaptersUpserted, 0);
  const pendingImprovement = window[0].unresolvedPending - window[window.length - 1].unresolvedPending;

  return zeroRowDecrease <= 0 && cumulativeUpserts === 0 && pendingImprovement <= 0;
}

async function run() {
  const startedAt = Date.now();
  const samples = [];
  let cycle = 0;
  let totalUpserted = 0;
  let totalUnresolvedFromRuns = 0;
  let stopReason = "unknown";
  let consecutiveErrors = 0;

  console.log(`# manga chapter crunch started ${fmtIso(startedAt)}`);
  console.log(`- functions base: ${FUNCTIONS_BASE}`);
  console.log(`- profile: limit=${LOOP_LIMIT} sleep_ms=${LOOP_SLEEP_MS} time_budget_ms=${LOOP_TIME_BUDGET_MS}`);
  console.log(`- stop policy: reachable zero (${PLATEAU_HOURS}h plateau window)`);

  while (true) {
    cycle += 1;
    const cycleStarted = Date.now();
    try {
      const before = await getCrunchMetrics();
      const response = await callEnrichCrunch();
      const results = response?.results ?? {};
      const after = await getCrunchMetrics();

      const chaptersUpserted = Number(results.chapters_upserted ?? 0);
      const unresolvedRun = Number(results.unresolved_mappings ?? 0);
      totalUpserted += chaptersUpserted;
      totalUnresolvedFromRuns += unresolvedRun;
      consecutiveErrors = 0;

      samples.push({
        ts: Date.now(),
        zeroRows: after.zeroRows,
        unresolvedPending: after.unresolvedPending,
        chaptersUpserted,
      });

      const cycleDelta = before.zeroRows - after.zeroRows;
      const oneHourDelta = computeRollingOneHourDelta(samples);
      const durationMs = Date.now() - cycleStarted;
      console.log(
        `[cycle ${cycle}] zero_rows=${after.zeroRows} cycle_delta=${cycleDelta} ` +
          `upserted=${chaptersUpserted} unresolved_run=${unresolvedRun} ` +
          `unresolved_pending=${after.unresolvedPending} rolling_1h_delta=${oneHourDelta} ` +
          `duration_ms=${durationMs}`,
      );

      if (after.zeroRows === 0) {
        stopReason = "zero_reached";
        break;
      }
      if (reachedReachableZeroPlateau(samples, PLATEAU_HOURS)) {
        stopReason = "reachable_zero_plateau";
        break;
      }
    } catch (error) {
      consecutiveErrors += 1;
      console.error(`[cycle ${cycle}] error: ${(error && error.message) ? error.message : String(error)}`);
      if (consecutiveErrors >= MAX_CONSECUTIVE_ERRORS) {
        stopReason = "consecutive_errors";
        break;
      }
    }

    await sleep(LOOP_SLEEP_MS);
  }

  const endedAt = Date.now();
  const latest = samples[samples.length - 1] ?? null;
  const summary = {
    success: stopReason === "zero_reached" || stopReason === "reachable_zero_plateau",
    stop_reason: stopReason,
    started_at: fmtIso(startedAt),
    ended_at: fmtIso(endedAt),
    duration_ms: endedAt - startedAt,
    cycles,
    final_zero_rows: latest ? latest.zeroRows : null,
    final_unresolved_pending: latest ? latest.unresolvedPending : null,
    total_chapters_upserted: totalUpserted,
    total_unresolved_from_runs: totalUnresolvedFromRuns,
    rolling_1h_zero_row_delta: computeRollingOneHourDelta(samples),
  };

  console.log("\n# crunch summary");
  console.log(JSON.stringify(summary, null, 2));
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
