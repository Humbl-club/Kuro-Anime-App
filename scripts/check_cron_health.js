/*
  Cron / Edge Function health check (Supabase).

  What it does:
  - Verifies scheduled functions respond: bulk-import-anime, bulk-import-manga, manga-chapter-enrich, mirror-images
  - Checks DB-side evidence that schedules are doing work:
    - import_state rows + timestamps
    - optional import_runs recent rows (if table exists)
    - manga chapter enrichment metrics + review queue depth
    - last_synced_at coverage on anime/manga

  Notes:
  - Uses service role key + IMPORT_SECRET (per current repo auth). Do not print secrets.
  - Read-only except for function invocations.
*/

const { createClient } = require("@supabase/supabase-js");

process.stdout.on("error", (err) => {
  if (err && err.code === "EPIPE") process.exit(0);
});

const SUPABASE_URL = "https://bkdifromsqxkndnllmdj.supabase.co";
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const IMPORT_SECRET = process.env.IMPORT_SECRET ?? process.env.SUPABASE_IMPORT_SECRET;
if (!SERVICE_ROLE_KEY) {
  throw new Error("Missing SUPABASE_SERVICE_ROLE_KEY env var.");
}
if (!IMPORT_SECRET) {
  throw new Error("Missing IMPORT_SECRET (or SUPABASE_IMPORT_SECRET) env var.");
}

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
      "x-import-secret": IMPORT_SECRET,
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

async function getRecentChapterEnrichRuns(limit = 5) {
  const exists = await tableExists("import_runs");
  if (!exists) return { missing: true, rows: [] };
  const { data, error } = await supabase
    .from("import_runs")
    .select("id,status,message,started_at,finished_at,duration_ms,results")
    .eq("media_type", "MANGA")
    .eq("run_type", "chapter_enrich")
    .order("started_at", { ascending: false })
    .limit(limit);
  if (error) return { error: error.message, rows: [] };
  return { rows: data ?? [] };
}

async function getMangaChapterEnrichMetrics(hours = 24) {
  const { data, error } = await supabase.rpc("get_manga_chapter_enrich_metrics", { p_hours: hours });
  if (error) return { error: error.message, row: null };
  const row = Array.isArray(data) ? data[0] : data;
  return { row: row ?? null };
}

async function getMangaMatchQualityMetrics(hours = 24) {
  const { data, error } = await supabase.rpc("get_manga_match_quality_metrics", { p_hours: hours });
  if (error) return { error: error.message, row: null };
  const row = Array.isArray(data) ? data[0] : data;
  return { row: row ?? null };
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

  console.log(`\n## Manga Chapter Enrichment`);
  const enrichMetrics = await getMangaChapterEnrichMetrics(24);
  if (enrichMetrics.error) {
    console.log(`- metrics rpc unavailable: ${enrichMetrics.error}`);
  } else if (!enrichMetrics.row) {
    console.log(`- metrics rpc returned no rows`);
  } else {
    const m = enrichMetrics.row;
    console.log(`- mangas with chapters IS NULL: ${m.manga_chapters_null}`);
    console.log(`- mangas with 0 chapter rows: ${m.manga_zero_chapter_rows}`);
    console.log(
      `- chapter_enrich runs (24h): total=${m.recent_runs} success=${m.success_runs} error=${m.error_runs} skipped=${m.skipped_runs}`
    );
    console.log(`- fractional chapter keys skipped (24h): ${m.fractional_skipped}`);
    console.log(`- unresolved mapping queue (pending): ${m.unresolved_pending}`);
  }

  const chapterRuns = await getRecentChapterEnrichRuns(5);
  if (chapterRuns.missing) {
    console.log(`- chapter_enrich run history: unavailable (import_runs missing)`);
  } else if (chapterRuns.error) {
    console.log(`- chapter_enrich run history error: ${chapterRuns.error}`);
  } else if (chapterRuns.rows.length === 0) {
    console.log(`- chapter_enrich run history: no rows yet`);
  } else {
    for (const r of chapterRuns.rows) {
      const fractionalSkipped = Number(r?.results?.fractional_skipped ?? 0);
      const unresolved = Number(r?.results?.unresolved_mappings ?? 0);
      const tiebreakResolved = Number(r?.results?.collision_tiebreak_resolved ?? 0);
      const tiebreakAmbiguous = Number(r?.results?.collision_tiebreak_ambiguous ?? 0);
      const retries = Number(r?.results?.auto_retry_enqueued ?? 0);
      console.log(
        `  - chapter_enrich ${r.status} started=${fmtDate(r.started_at)} finished=${fmtDate(
          r.finished_at
        )} fractional=${fractionalSkipped} unresolved=${unresolved} tiebreak_resolved=${tiebreakResolved} tiebreak_ambiguous=${tiebreakAmbiguous} retries=${retries}${r.message ? ` msg=${String(r.message).slice(0, 120)}` : ""}`
      );
      if (r?.results?.unresolved_reason_counts) {
        console.log(`    unresolved reasons: ${JSON.stringify(r.results.unresolved_reason_counts)}`);
      }
    }
  }

  console.log(`\n## Manga Match Quality (24h)`);
  const quality24 = await getMangaMatchQualityMetrics(24);
  if (quality24.error) {
    console.log(`- quality metrics rpc unavailable: ${quality24.error}`);
  } else if (!quality24.row) {
    console.log(`- quality metrics rpc returned no rows`);
  } else {
    const q = quality24.row;
    console.log(
      `- auto-resolve rate: ${Number(q.auto_resolve_rate_pct ?? 0).toFixed(3)}% (${q.auto_resolved ?? 0}/${q.processed ?? 0})`
    );
    console.log(`- wrong-map proxy rate: ${Number(q.wrong_map_proxy_rate_pct ?? 0).toFixed(3)}%`);
    console.log(`- unresolved in window: ${q.unresolved ?? 0}`);
    console.log(`- verify checked/deactivated: ${q.verify_checked ?? 0}/${q.verify_deactivated ?? 0}`);
    console.log(`- fuzzy auto-share of auto-resolved: ${Number(q.fuzzy_auto_rate_pct ?? 0).toFixed(3)}%`);
    console.log(`- pending review rows (audit only): ${q.pending_review_count ?? 0}`);

    const quality48 = await getMangaMatchQualityMetrics(48);
    if (!quality48.error && quality48.row) {
      const unresolved24 = Number(q.unresolved ?? 0);
      const unresolved48 = Number(quality48.row.unresolved ?? 0);
      const unresolvedPrev24 = Math.max(0, unresolved48 - unresolved24);
      const trend = unresolved24 - unresolvedPrev24;
      const trendLabel = trend > 0 ? "up" : trend < 0 ? "down" : "flat";
      console.log(
        `- unresolved trend (24h vs prev24h): current=${unresolved24} prev=${unresolvedPrev24} (${trendLabel} ${Math.abs(trend)})`
      );
    }

    if (chapterRuns.rows?.length) {
      const latest = chapterRuns.rows[0];
      const modeUsed = latest?.results?.mode_used ?? "unknown";
      const modeDegraded = Boolean(latest?.results?.mode_degraded ?? false);
      console.log(`- matcher mode (latest run): ${modeUsed}${modeDegraded ? " (degraded-to-strict)" : ""}`);
    }
  }

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

  const chapterEnrich = await callFunction("manga-chapter-enrich", {
    limit: 1,
    scheduleSafe: true,
    timeBudgetMs: 8000,
    languages: ["en", "de"],
    includeFallbackAllLanguages: false,
    lockTtlSeconds: 900,
  });
  console.log(`- manga-chapter-enrich: ${chapterEnrich.status}${chapterEnrich.ok ? " OK" : " FAIL"}`);
  if (!chapterEnrich.ok) {
    console.log(
      `  - body: ${chapterEnrich.text ? chapterEnrich.text.slice(0, 240) : JSON.stringify(chapterEnrich.json).slice(0, 240)}`
    );
  } else if (chapterEnrich.json?.results) {
    const r = chapterEnrich.json.results;
    console.log(
      `  - processed=${r.manga_processed ?? 0} unresolved=${r.unresolved_mappings ?? 0} chapters_upserted=${r.chapters_upserted ?? 0}`
    );
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
