#!/usr/bin/env node

/*
  AniList community recommendation edges importer — Realm Graph Stage 3a (probationary).
  Spec: docs/superpowers/specs/2026-07-31-realm-graph-master-plan.md §7

  For every title in the visible pool (average_score >= 70, not adult) in our
  catalog, fetches AniList "users who liked X also recommend Y" recommendations
  and bulk-upserts edges into public.media_rec_edges via the upsert_rec_edges RPC
  (migration 20260731140000_media_rec_edges_v1.sql). Edge ids are Kuro-internal
  (anime.id / manga.id); AniList target ids are resolved through our REST.

  Usage:
    node scripts/import_anilist_rec_edges.js [--limit N] [--offset N] [--dry-run]

    --dry-run   Fetch 2 pool titles from the live AniList API and print the edges
                that WOULD be sent. No RPC calls, no checkpoint writes.
    --limit N   Process at most N pool titles (after --offset and resume skips).
    --offset N  Skip the first N pool titles (pool order: anime then manga,
                each popularity.desc).

  Env:
    KURO_TEST_JWT        Bearer token (test account) for the upsert_rec_edges RPC.
                         Required for a real import; NOT required for --dry-run.
    SUPABASE_URL         Optional override; default parsed from Config/Shared.xcconfig.
    SUPABASE_ANON_KEY    Optional override; default parsed from Config/Shared.xcconfig.

  Mechanics:
    - AniList pacing: ~700ms between GraphQL requests (<= ~85 req/min, under the
      90 req/min limit). 429 responses honor the Retry-After header with backoff.
    - RPC batching: edges are buffered and flushed in chunks of <= 500 rows per
      upsert_rec_edges call (the RPC hard-validates <= 500).
    - RPC rate limit: 200 calls/hour/user (fixed hourly windows). On RATE_LIMITED
      the script sleeps until the next window opens, up to 3 waits, then aborts —
      the checkpoint file makes restarts/resumes lossless.
    - Checkpoint: appends one JSON line per completed title to
      scripts/.rec_edges_progress.json; on start, completed titles are skipped.
      Progress is written only after the covering RPC flush succeeds.

  Run (lead, tonight):
    KURO_TEST_JWT=<test-account-jwt> node scripts/import_anilist_rec_edges.js
*/

const fs = require('fs');
const path = require('path');

const ANILIST_API = 'https://graphql.anilist.co';
const ANILIST_REQUEST_DELAY_MS = 700; // ~85 req/min, under AniList's 90 req/min
const ANILIST_TIMEOUT_MS = 20000;
const RPC_BATCH_SIZE = 500;
const POOL_PAGE_SIZE = 1000;
const RECS_PER_TITLE = 25;
const PROGRESS_PATH = path.join(__dirname, '.rec_edges_progress.json');
const XCCONFIG_PATH = path.join(__dirname, '..', 'Config', 'Shared.xcconfig');
const RATE_LIMIT_MAX_WAITS = 3;

let lastAniListRequestAt = 0;

function sleep(ms) { return new Promise(resolve => setTimeout(resolve, ms)); }

function nowIso() { return new Date().toISOString(); }

function parseArgs() {
  const args = { limit: null, offset: 0, dryRun: false };
  const argv = process.argv.slice(2);
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--dry-run') {
      args.dryRun = true;
    } else if (argv[i] === '--limit' && argv[i + 1]) {
      args.limit = parsePositiveInt(argv[++i], null);
    } else if (argv[i] === '--offset' && argv[i + 1]) {
      args.offset = parsePositiveInt(argv[++i], 0);
    } else {
      throw new Error(`Unknown argument: ${argv[i]}`);
    }
  }
  return args;
}

function parsePositiveInt(raw, fallback) {
  const value = Number.parseInt(raw ?? '', 10);
  return Number.isFinite(value) && value >= 0 ? value : fallback;
}

function loadSupabaseConfig() {
  const values = {};
  if (fs.existsSync(XCCONFIG_PATH)) {
    for (const line of fs.readFileSync(XCCONFIG_PATH, 'utf8').split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('//')) continue;
      const idx = trimmed.indexOf('=');
      if (idx <= 0) continue;
      const key = trimmed.slice(0, idx).trim();
      // xcconfig escapes a literal "/" as "$()/" — strip the escape.
      const value = trimmed.slice(idx + 1).trim().replace(/\$\(\)/g, '');
      values[key] = value;
    }
  }
  const url = process.env.SUPABASE_URL || values.SUPABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY || values.SUPABASE_ANON_KEY;
  if (!url || !anonKey) {
    throw new Error('Missing SUPABASE_URL / SUPABASE_ANON_KEY (env or Config/Shared.xcconfig).');
  }
  return { url: url.replace(/\/+$/, ''), anonKey };
}

async function rateLimitAniList() {
  const elapsed = Date.now() - lastAniListRequestAt;
  if (elapsed < ANILIST_REQUEST_DELAY_MS) {
    await sleep(ANILIST_REQUEST_DELAY_MS - elapsed);
  }
  lastAniListRequestAt = Date.now();
}

// ---------------------------------------------------------------------------
// Supabase REST (read-only pool + id resolution, anon key)
// ---------------------------------------------------------------------------

async function restGet(config, pathAndQuery) {
  const response = await fetch(`${config.url}/rest/v1/${pathAndQuery}`, {
    headers: {
      apikey: config.anonKey,
      Authorization: `Bearer ${config.anonKey}`,
    },
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`REST GET ${pathAndQuery.slice(0, 80)} failed: HTTP ${response.status}: ${text.slice(0, 300)}`);
  }
  return response.json();
}

async function fetchPool(config) {
  const pool = [];
  for (const mediaType of ['ANIME', 'MANGA']) {
    const table = mediaType === 'ANIME' ? 'anime' : 'manga';
    let offset = 0;
    for (;;) {
      const rows = await restGet(
        config,
        `${table}?average_score=gte.70&is_adult=eq.false` +
        `&select=id,anilist_id,title_english,title_romaji,popularity` +
        `&order=popularity.desc&limit=${POOL_PAGE_SIZE}&offset=${offset}`
      );
      for (const row of rows) {
        if (!Number.isInteger(row.anilist_id)) continue; // cannot query AniList without it
        pool.push({
          media_type: mediaType,
          id: row.id,
          anilist_id: row.anilist_id,
          title: row.title_english || row.title_romaji || `${mediaType} ${row.id}`,
        });
      }
      if (rows.length < POOL_PAGE_SIZE) break;
      offset += POOL_PAGE_SIZE;
    }
    console.log(`[pool] ${mediaType}: fetched pages up to offset ${offset}, running total ${pool.length}`);
  }
  return pool;
}

const targetIdCache = new Map(); // `${type}:${anilistId}` -> internal id | null
const targetTitleCache = new Map(); // `${type}:${internalId}` -> title string | null

async function resolveTargets(config, mediaType, anilistIds) {
  const missing = anilistIds.filter(id => !targetIdCache.has(`${mediaType}:${id}`));
  const table = mediaType === 'ANIME' ? 'anime' : 'manga';
  // Chunk the in.(...) filter to keep request URLs short.
  for (let i = 0; i < missing.length; i += 100) {
    const chunk = missing.slice(i, i + 100);
    if (chunk.length === 0) continue;
    const rows = await restGet(
      config,
      `${table}?anilist_id=in.(${chunk.join(',')})&select=id,anilist_id,title_english,title_romaji`
    );
    const found = new Set();
    for (const row of rows) {
      targetIdCache.set(`${mediaType}:${row.anilist_id}`, row.id);
      targetTitleCache.set(`${mediaType}:${row.id}`, row.title_english || row.title_romaji || null);
      found.add(row.anilist_id);
    }
    for (const id of chunk) {
      if (!found.has(id)) {
        targetIdCache.set(`${mediaType}:${id}`, null);
      }
    }
  }
  return anilistIds.map(id => targetIdCache.get(`${mediaType}:${id}`) ?? null);
}

// ---------------------------------------------------------------------------
// AniList GraphQL
// ---------------------------------------------------------------------------

async function fetchRecommendations(anilistId) {
  const query = `
    query ($id: Int) {
      Media(id: $id) {
        id
        type
        recommendations(sort: RATING_DESC, perPage: ${RECS_PER_TITLE}) {
          nodes {
            rating
            mediaRecommendation { id type }
          }
        }
      }
    }
  `;

  for (let attempt = 0;; attempt++) {
    await rateLimitAniList();
    let response;
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), ANILIST_TIMEOUT_MS);
      try {
        response = await fetch(ANILIST_API, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
          body: JSON.stringify({ query, variables: { id: anilistId } }),
          signal: controller.signal,
        });
      } finally {
        clearTimeout(timeout);
      }
    } catch (error) {
      if (attempt < 4) {
        await sleep(500 * Math.pow(2, attempt));
        continue;
      }
      throw error;
    }

    if (response.ok) {
      const payload = await response.json();
      if (payload?.errors && !payload?.data?.Media) {
        if (attempt < 4) {
          await sleep(500 * Math.pow(2, attempt));
          continue;
        }
        throw new Error(`AniList GraphQL errors for media ${anilistId}: ${JSON.stringify(payload.errors).slice(0, 300)}`);
      }
      return payload?.data?.Media ?? null;
    }

    if (response.status === 429) {
      if (attempt >= 6) throw new Error(`AniList HTTP 429 persisted for media ${anilistId}`);
      const retryAfter = Number.parseInt(response.headers.get('retry-after') || '', 10);
      const wait = Number.isFinite(retryAfter) && retryAfter > 0
        ? retryAfter * 1000 + 500
        : 15000 * (attempt + 1);
      console.log(`[anilist] 429 rate limited — waiting ${Math.round(wait / 1000)}s (attempt ${attempt + 1})`);
      await sleep(wait);
      continue;
    }

    if (response.status >= 500 && attempt < 4) {
      await sleep(500 * Math.pow(2, attempt));
      continue;
    }

    if (response.status === 404) {
      // Stale anilist_id in our catalog (deleted/merged upstream) — skip, don't crash the run.
      console.log(`[anilist] 404 for media ${anilistId} — skipping (stale id)`);
      return null;
    }

    const text = await response.text();
    throw new Error(`AniList HTTP ${response.status} for media ${anilistId}: ${text.slice(0, 300)}`);
  }
}

// ---------------------------------------------------------------------------
// RPC upsert with hourly-window rate-limit handling
// ---------------------------------------------------------------------------

async function upsertEdges(config, jwt, rows) {
  for (let waits = 0;;) {
    const response = await fetch(`${config.url}/rest/v1/rpc/upsert_rec_edges`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: config.anonKey,
        Authorization: `Bearer ${jwt}`,
      },
      body: JSON.stringify({ p_rows: rows }),
    });

    if (response.ok) {
      const text = await response.text();
      const count = Number.parseInt(text, 10);
      return Number.isFinite(count) ? count : 0;
    }

    const body = await response.text();
    if (body.includes('RATE_LIMITED')) {
      waits += 1;
      if (waits > RATE_LIMIT_MAX_WAITS) {
        throw new Error('upsert_rec_edges RATE_LIMITED persisted across 3 hourly windows — aborting (checkpoint intact, rerun to resume).');
      }
      // rate_limit_hit uses fixed epoch-aligned hourly windows.
      const waitMs = 3600000 - (Date.now() % 3600000) + 5000;
      console.log(`[rpc] RATE_LIMITED (200 calls/hour) — sleeping ${Math.round(waitMs / 60000)}min until next window (wait ${waits}/${RATE_LIMIT_MAX_WAITS})`);
      await sleep(waitMs);
      continue;
    }
    if (response.status >= 500) {
      await sleep(2000);
      continue;
    }
    throw new Error(`upsert_rec_edges failed: HTTP ${response.status}: ${body.slice(0, 500)}`);
  }
}

// ---------------------------------------------------------------------------
// Checkpoint (JSONL, one line per completed title)
// ---------------------------------------------------------------------------

function loadDoneSet() {
  const done = new Set();
  if (!fs.existsSync(PROGRESS_PATH)) return done;
  for (const line of fs.readFileSync(PROGRESS_PATH, 'utf8').split(/\r?\n/)) {
    if (!line.trim()) continue;
    try {
      const row = JSON.parse(line);
      if (row.media_type && Number.isInteger(row.anilist_id)) {
        done.add(`${row.media_type}:${row.anilist_id}`);
      }
    } catch {
      // ignore malformed tail line from an interrupted write
    }
  }
  return done;
}

function appendProgress(lines) {
  if (lines.length === 0) return;
  fs.appendFileSync(PROGRESS_PATH, lines.map(l => JSON.stringify(l)).join('\n') + '\n', 'utf8');
}

// ---------------------------------------------------------------------------
// Edge mapping
// ---------------------------------------------------------------------------

function mediaTypeOf(raw) {
  return raw === 'ANIME' || raw === 'MANGA' ? raw : null;
}

async function edgesForTitle(config, title) {
  const media = await fetchRecommendations(title.anilist_id);
  const stats = { edges: 0, skipped: 0, unresolved: 0, missing: !media };
  if (!media) return { edges: [], stats };

  const nodes = (media.recommendations?.nodes || []).filter(n => n && n.mediaRecommendation);
  const candidates = [];
  const seenTargets = new Set();
  for (const node of nodes) {
    const rec = node.mediaRecommendation;
    const toType = mediaTypeOf(rec.type);
    const rating = Number.isInteger(node.rating) ? node.rating : 0;
    if (!toType || !Number.isInteger(rec.id) || rating < 0 || rating > 100000) {
      stats.skipped += 1;
      continue;
    }
    if (rec.id === title.anilist_id && toType === title.media_type) {
      stats.skipped += 1; // self-recommendation
      continue;
    }
    const key = `${toType}:${rec.id}`;
    if (seenTargets.has(key)) continue; // same target twice in one page; keep first (highest-rated, sorted desc)
    seenTargets.add(key);
    candidates.push({ toType, anilistId: rec.id, rating });
  }

  // Resolve AniList target ids -> Kuro-internal ids (anime.id / manga.id), cached.
  const byType = { ANIME: [], MANGA: [] };
  for (const c of candidates) byType[c.toType].push(c.anilistId);
  const resolved = {
    ANIME: await resolveTargets(config, 'ANIME', byType.ANIME),
    MANGA: await resolveTargets(config, 'MANGA', byType.MANGA),
  };
  const internalId = new Map();
  for (const t of ['ANIME', 'MANGA']) {
    byType[t].forEach((anilistId, i) => internalId.set(`${t}:${anilistId}`, resolved[t][i]));
  }

  const edges = [];
  for (const c of candidates) {
    const toId = internalId.get(`${c.toType}:${c.anilistId}`);
    if (!toId) {
      stats.unresolved += 1; // target not in our catalog — edge is useless to the app
      continue;
    }
    edges.push({
      from_media_type: title.media_type,
      from_media_id: title.id,
      to_media_type: c.toType,
      to_media_id: toId,
      rating: c.rating,
    });
  }
  stats.edges = edges.length;
  return { edges, stats };
}

// ---------------------------------------------------------------------------
// Modes
// ---------------------------------------------------------------------------

async function dryRun(config, pool, offset) {
  const sample = pool.slice(offset, offset + 2);
  if (sample.length === 0) throw new Error('Pool is empty at the requested offset.');
  console.log(`[dry-run] sampling ${sample.length} titles from pool of ${pool.length} (offset ${offset})\n`);

  for (const title of sample) {
    const { edges, stats } = await edgesForTitle(config, title);
    console.log(`${title.media_type} anilist_id=${title.anilist_id} internal_id=${title.id} — ${title.title}`);
    console.log(`  edges=${stats.edges} skipped=${stats.skipped} unresolved=${stats.unresolved}`);
    for (const e of edges.slice(0, 5)) {
      const targetTitle = targetTitleCache.get(`${e.to_media_type}:${e.to_media_id}`) || '(title unknown)';
      console.log(`  -> ${e.to_media_type} #${e.to_media_id} rating=${e.rating}  ${targetTitle}`);
    }
    if (edges.length > 0) {
      console.log('  sample RPC payload row:');
      console.log('  ' + JSON.stringify(edges[0]));
    }
    console.log('');
  }
  console.log('[dry-run] no RPC calls made, no checkpoint written.');
}

async function run(config, jwt, pool, { limit, offset }) {
  const done = loadDoneSet();
  const sliced = pool.slice(offset, limit == null ? undefined : offset + limit);
  const pending = sliced.filter(t => !done.has(`${t.media_type}:${t.anilist_id}`));
  console.log(`[import] pool=${pool.length} slice=${sliced.length} (offset=${offset}, limit=${limit ?? 'none'}) already_done=${sliced.length - pending.length} to_process=${pending.length}`);

  let edgeBuffer = []; // { edge } — edges awaiting upsert
  const pendingProgress = new Map(); // titleKey -> progress line, checkpointed on flush
  let processed = 0;
  let totalEdges = 0;
  let totalUpserted = 0;

  async function flush() {
    if (edgeBuffer.length === 0 && pendingProgress.size === 0) return;
    // Dedupe within the flush group by edge PK, keep max rating.
    const byKey = new Map();
    for (const item of edgeBuffer) {
      const k = `${item.edge.from_media_type}|${item.edge.from_media_id}|${item.edge.to_media_type}|${item.edge.to_media_id}`;
      const prev = byKey.get(k);
      if (!prev || item.edge.rating > prev.edge.rating) byKey.set(k, item);
    }
    const rows = [...byKey.values()].map(item => item.edge);
    for (let i = 0; i < rows.length; i += RPC_BATCH_SIZE) {
      totalUpserted += await upsertEdges(config, jwt, rows.slice(i, i + RPC_BATCH_SIZE));
    }
    // Checkpoint only after every covering RPC chunk succeeded. flush() is only
    // called between titles, so each pending title's edges are fully covered.
    appendProgress([...pendingProgress.values()]);
    edgeBuffer = [];
    pendingProgress.clear();
  }

  for (const title of pending) {
    const titleKey = `${title.media_type}:${title.anilist_id}`;
    try {
      const { edges, stats } = await edgesForTitle(config, title);
      pendingProgress.set(titleKey, {
        media_type: title.media_type,
        anilist_id: title.anilist_id,
        internal_id: title.id,
        edges: stats.edges,
        skipped: stats.skipped,
        unresolved: stats.unresolved,
        missing: stats.missing,
        at: nowIso(),
      });
      for (const edge of edges) edgeBuffer.push({ edge });
      totalEdges += edges.length;
    } catch (error) {
      console.error(`[import] ERROR on ${titleKey} (${title.title}): ${error.message || error}`);
      console.error('[import] aborting; rerun the same command to resume from checkpoint.');
      await flush();
      throw error;
    }

    processed += 1;
    if (edgeBuffer.length >= RPC_BATCH_SIZE) await flush();
    if (processed % 25 === 0 || processed === pending.length) {
      console.log(`[import] progress ${processed}/${pending.length} titles, edges fetched=${totalEdges}, upserted=${totalUpserted}`);
    }
  }
  await flush();
  console.log(`[import] done. titles=${processed} edges_sent=${totalEdges} rows_affected=${totalUpserted}`);
}

async function main() {
  const args = parseArgs();
  const config = loadSupabaseConfig();
  const jwt = process.env.KURO_TEST_JWT;
  if (!args.dryRun && !jwt) {
    throw new Error('Missing KURO_TEST_JWT env var (bearer token for upsert_rec_edges). Only --dry-run works without it.');
  }

  const pool = await fetchPool(config);
  if (args.dryRun) {
    await dryRun(config, pool, args.offset);
  } else {
    await run(config, jwt, pool, args);
  }
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
