/*
  Cron / Edge Function health check (Supabase).

  What it does:
  - Verifies the three scheduled functions respond: bulk-import-anime, bulk-import-manga, mirror-images
  - Checks DB-side evidence that schedules are doing work:
    - import_state rows + timestamps
    - optional import_runs recent rows (if table exists)
    - last_synced_at coverage on anime/manga

  Notes:
  - Uses service role key (per current repo approach). Do not print secrets.
  - Read-only except for function invocations.
*/

const { createClient } = require("@supabase/supabase-js");

process.stdout.on("error", (err) => {
  if (err && err.code === "EPIPE") process.exit(0);
});

const SUPABASE_URL = "https://bkdifromsqxkndnllmdj.supabase.co";
const SERVICE_ROLE_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJrZGlmcm9tc3F4a25kbmxsbWRqIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1MjU5ODY2MywiZXhwIjoyMDY4MTc0NjYzfQ.qmEd0lxjs_cVIa4GRisDY9sNz35foJBEIQcs8XRrA9E";

const FUNCTIONS_BASE = `https://${new URL(SUPABASE_URL).host.replace(
  ".supabase.co",
  ".functions.supabase.co"
)}`;

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

function fmtDate(d) {
  if (!d) return "n/a";
  const dt = typeof d === "string" ? new Date(d) : d;
  return isNaN(dt.getTime()) ? String(d) : dt.toISOString();
}

async function tableExists(table) {
  const { error } = await supabase.from(table).select("*", { head: true, count: "exact" }).limit(1);
  if (!error) return true;
  const msg = (error.message || "").toLowerCase();
  return !(
    msg.includes("does not exist") ||
    msg.includes("relation") ||
    msg.includes("not found")
  );
}

async function callFunction(name, payload) {
  const url = `${FUNCTIONS_BASE}/${name}`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify(payload ?? {}),
  });
  const text = await res.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {
    // ignore
  }
  return { status: res.status, ok: res.ok, json, text: json ? null : text };
}

async function getImportState() {
  const { data, error } = await supabase
    .from("import_state")
    .select("media_type,last_page,updated_at")
    .order("media_type", { ascending: true });
  if (error) return { error: error.message, rows: [] };
  return { rows: data ?? [] };
}

async function getRecentImportRuns(limit = 10) {
  const exists = await tableExists("import_runs");
  if (!exists) return { missing: true, rows: [] };
  const { data, error } = await supabase
    .from("import_runs")
    .select("id,media_type,run_type,status,message,started_at,finished_at,duration_ms,results")
    .order("started_at", { ascending: false })
    .limit(limit);
  if (error) return { error: error.message, rows: [] };
  return { rows: data ?? [] };
}

async function getSyncRecency(table, days = 2) {
  const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
  const { count, error } = await supabase
    .from(table)
    .select("*", { head: true, count: "exact" })
    .gte("last_synced_at", cutoff);
  if (error) return { error: error.message, count: 0, cutoff };
  return { count: count ?? 0, cutoff };
}

async function run() {
  console.log(`# Cron Health Check (${new Date().toISOString()})`);
  console.log(`- Project: ${SUPABASE_URL}`);
  console.log(`- Functions base: ${FUNCTIONS_BASE}`);

  console.log(`\n## DB Evidence`);
  const importStateExists = await tableExists("import_state");
  console.log(`- import_state table: ${importStateExists ? "YES" : "NO"}`);
  if (importStateExists) {
    const st = await getImportState();
    if (st.error) console.log(`- import_state error: ${st.error}`);
    for (const row of st.rows) {
      console.log(
        `- import_state ${row.media_type}: last_page=${row.last_page} updated_at=${fmtDate(
          row.updated_at
        )}`
      );
    }
  }

  const recentRuns = await getRecentImportRuns(12);
  if (recentRuns.missing) {
    console.log(`- import_runs table: NO (functions will still work, but you won't see run history)`);
  } else if (recentRuns.error) {
    console.log(`- import_runs query error: ${recentRuns.error}`);
  } else {
    console.log(`- import_runs recent: ${recentRuns.rows.length} rows`);
    for (const r of recentRuns.rows.slice(0, 5)) {
      console.log(
        `  - ${r.media_type} ${r.run_type} ${r.status} started=${fmtDate(r.started_at)} finished=${fmtDate(
          r.finished_at
        )}${r.message ? ` msg=${String(r.message).slice(0, 120)}` : ""}`
      );
    }
  }

  const animeRecent = await getSyncRecency("anime", 2);
  const mangaRecent = await getSyncRecency("manga", 2);
  if (!animeRecent.error) console.log(`- anime last_synced_at >= ${animeRecent.cutoff}: ${animeRecent.count}`);
  if (!mangaRecent.error) console.log(`- manga last_synced_at >= ${mangaRecent.cutoff}: ${mangaRecent.count}`);

  console.log(`\n## Function Smoke Tests`);
  // Keep payload tiny to avoid timeouts. These should always return quickly if the deployed functions are healthy.
  const tinyImportPayload = {
    startPage: 1,
    pagesPerBatch: 1,
    runToEnd: false,
    useCursor: false,
    perPage: 10,
    delayMs: 0,
    retries: 2,
    lightweight: true,
    includeRelations: false,
    includeEpisodes: false,
    timeBudgetMs: 8000,
  };

  for (const fn of ["bulk-import-anime", "bulk-import-manga"]) {
    const res = await callFunction(fn, tinyImportPayload);
    console.log(`- ${fn}: ${res.status}${res.ok ? " OK" : " FAIL"}`);
    if (!res.ok) {
      console.log(`  - body: ${res.text ? res.text.slice(0, 240) : JSON.stringify(res.json).slice(0, 240)}`);
    } else if (res.json) {
      if (res.json.skipped) {
        console.log(`  - skipped: ${res.json.reason ?? "unknown"}`);
      } else {
        console.log(`  - results.errors: ${res.json?.results?.errors ?? "n/a"}`);
      }
    }
  }

  const mirror = await callFunction("mirror-images", {
    bucket: "media",
    mediaTypes: ["ANIME", "MANGA", "CHARACTER", "STAFF"],
    limit: 10,
    offset: 0,
    overwrite: false,
    timeBudgetMs: 8000,
  });
  console.log(`- mirror-images: ${mirror.status}${mirror.ok ? " OK" : " FAIL"}`);
  if (mirror.ok && mirror.json) {
    const r = mirror.json.results ?? {};
    console.log(
      `  - mirrored: anime=${r.anime ?? 0} manga=${r.manga ?? 0} characters=${r.characters ?? 0} staff=${r.staff ?? 0}`
    );
  } else if (!mirror.ok) {
    console.log(`  - body: ${mirror.text ? mirror.text.slice(0, 240) : JSON.stringify(mirror.json).slice(0, 240)}`);
  }

  console.log("\nEND");
}

run().catch((e) => {
  console.error("Failed:", e?.message ?? String(e));
  process.exit(1);
});
