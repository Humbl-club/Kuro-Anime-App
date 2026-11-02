#!/usr/bin/env node

/*
  Realm Graph Stage 2b — LLM descriptor pass: work-item fetcher.
  Spec: docs/superpowers/specs/2026-07-31-realm-graph-master-plan.md §6

  Prints a JSON array of pending work items (one object per title, everything
  the writing agent needs to produce a descriptor) to STDOUT. Progress and
  errors go to STDERR so stdout stays pipeable:

    node scripts/realm_llm_pass_fetch.js --limit 50 [--offset 0] > items.json

  The queue is media_realm_llm_pending (migration 20260731170000): visible-pool
  titles (average_score >= 70, not adult, has cover, ancillary anime formats
  excluded) with no media_realm_llm row yet, popularity desc. Read pages of 50.

  Per item:
    media_type, media_id, title, genres,
    tags                  top 8 by rank from anime_tags/manga_tags join tags
    average_score, year, format, episodes, chapters, source,
    description_normalized trimmed to 600 chars,
    synopsis_enhanced     trimmed to 600 chars, only when state = 'ready' (else null),
    membership            current rules-based realms from media_realm_membership
                          ([{realm, weight}] weight desc) — the LLM confirms or
                          corrects these, it does not start from a blank page.

  Env:
    KURO_TEST_JWT        Bearer token (test account). REQUIRED — the pending
                         view is revoked from anon (ops queue, not app surface).
    SUPABASE_URL         Optional override; default parsed from Config/Shared.xcconfig.
    SUPABASE_ANON_KEY    Optional override; default parsed from Config/Shared.xcconfig.

  No dependencies beyond node >= 18 (global fetch).
*/

const fs = require('fs');
const path = require('path');

const QUEUE_PAGE_SIZE = 50;      // spec: batches of 50
const REST_PAGE_SIZE = 1000;     // PostgREST default max-rows; paginate joins
const SYNOPSIS_TRIM = 600;
const TOP_TAGS = 8;
const XCCONFIG_PATH = path.join(__dirname, '..', 'Config', 'Shared.xcconfig');

function log(...args) { console.error('[fetch]', ...args); }

function parseArgs(argv) {
  const args = { limit: QUEUE_PAGE_SIZE, offset: 0 };
  const list = argv.slice(2);
  for (let i = 0; i < list.length; i++) {
    if (list[i] === '--limit' && list[i + 1]) {
      args.limit = parseNonNegativeInt(list[++i], null);
    } else if (list[i] === '--offset' && list[i + 1]) {
      args.offset = parseNonNegativeInt(list[++i], 0);
    } else {
      throw new Error(`Unknown argument: ${list[i]} (usage: --limit N [--offset M])`);
    }
  }
  if (!Number.isInteger(args.limit) || args.limit < 1) {
    throw new Error('--limit must be a positive integer');
  }
  return args;
}

function parseNonNegativeInt(raw, fallback) {
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
      values[key] = trimmed.slice(idx + 1).trim().replace(/\$\(\)/g, '');
    }
  }
  const url = process.env.SUPABASE_URL || values.SUPABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY || values.SUPABASE_ANON_KEY;
  if (!url || !anonKey) {
    throw new Error('Missing SUPABASE_URL / SUPABASE_ANON_KEY (env or Config/Shared.xcconfig).');
  }
  return { url: url.replace(/\/+$/, ''), anonKey, jwt: process.env.KURO_TEST_JWT || null };
}

// ---------------------------------------------------------------------------
// Supabase REST. With a JWT we authenticate as the test user (required for
// media_realm_llm_pending); without one we fall back to the anon bearer, which
// covers every other table this script reads.
// ---------------------------------------------------------------------------

async function restGet(config, pathAndQuery) {
  const response = await fetch(`${config.url}/rest/v1/${pathAndQuery}`, {
    headers: {
      apikey: config.anonKey,
      Authorization: `Bearer ${config.jwt || config.anonKey}`,
    },
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`REST GET ${pathAndQuery.slice(0, 100)} failed: HTTP ${response.status}: ${text.slice(0, 300)}`);
  }
  return response.json();
}

// Paginated GET: follows limit/offset pages until a short page, so a 50-title
// batch's joined tag rows (~2-3k) are not silently clipped at the server cap.
async function restGetAll(config, pathAndQuery) {
  const rows = [];
  let offset = 0;
  for (;;) {
    const sep = pathAndQuery.includes('?') ? '&' : '?';
    const page = await restGet(config, `${pathAndQuery}${sep}limit=${REST_PAGE_SIZE}&offset=${offset}`);
    rows.push(...page);
    if (page.length < REST_PAGE_SIZE) return rows;
    offset += REST_PAGE_SIZE;
  }
}

// ---------------------------------------------------------------------------
// Queue
// ---------------------------------------------------------------------------

async function fetchPendingItems(config, limit, offset) {
  const items = [];
  let cursor = offset;
  while (items.length < limit) {
    const pageSize = Math.min(QUEUE_PAGE_SIZE, limit - items.length);
    const page = await restGet(
      config,
      `media_realm_llm_pending?select=media_type,media_id,title,popularity` +
      `&order=popularity.desc,media_type.asc,media_id.asc&limit=${pageSize}&offset=${cursor}`
    );
    if (page.length === 0) break;
    items.push(...page);
    cursor += page.length;
    if (page.length < pageSize) break; // queue exhausted
  }
  return items;
}

// ---------------------------------------------------------------------------
// Enrichment
// ---------------------------------------------------------------------------

function inList(ids) {
  return `in.(${ids.join(',')})`;
}

function trim600(text) {
  if (!text) return null;
  return [...text].length > SYNOPSIS_TRIM ? [...text].slice(0, SYNOPSIS_TRIM).join('') : text;
}

async function fetchBaseRows(config, mediaType, ids) {
  if (ids.length === 0) return new Map();
  const table = mediaType === 'ANIME' ? 'anime' : 'manga';
  const cols = mediaType === 'ANIME'
    ? 'id,title_english,title_romaji,genres,average_score,season_year,start_date_year,format,episodes,source,description_normalized,synopsis_enhanced,synopsis_enhanced_state'
    : 'id,title_english,title_romaji,genres,average_score,start_date_year,format,chapters,source,description_normalized,synopsis_enhanced,synopsis_enhanced_state';
  const rows = await restGet(config, `${table}?select=${cols}&id=${inList(ids)}`);
  return new Map(rows.map(r => [r.id, r]));
}

async function fetchTopTags(config, mediaType, ids) {
  // Returns Map<mediaId, [{name, rank}]> — top TOP_TAGS by rank desc.
  const result = new Map(ids.map(id => [id, []]));
  if (ids.length === 0) return result;
  const table = mediaType === 'ANIME' ? 'anime_tags' : 'manga_tags';
  const fkCol = mediaType === 'ANIME' ? 'anime_id' : 'manga_id';
  const rows = await restGetAll(
    config,
    `${table}?select=${fkCol},rank,tags(name)&${fkCol}=${inList(ids)}`
  );
  const byId = new Map();
  for (const row of rows) {
    const mediaId = row[fkCol];
    const name = row.tags && row.tags.name;
    if (!name) continue;
    if (!byId.has(mediaId)) byId.set(mediaId, []);
    byId.get(mediaId).push({ name, rank: row.rank == null ? 0 : row.rank });
  }
  for (const [mediaId, tags] of byId) {
    tags.sort((a, b) => b.rank - a.rank || a.name.localeCompare(b.name));
    result.set(mediaId, tags.slice(0, TOP_TAGS));
  }
  return result;
}

async function fetchMembership(config, mediaType, ids) {
  // Returns Map<mediaId, [{realm, weight}]> — weight desc (matview keeps
  // top-4 + anything >= threshold, so this is the full stored membership).
  const result = new Map(ids.map(id => [id, []]));
  if (ids.length === 0) return result;
  const rows = await restGetAll(
    config,
    `media_realm_membership?select=media_id,realm,weight&media_type=eq.${mediaType}&media_id=${inList(ids)}&order=weight.desc`
  );
  for (const row of rows) {
    if (!result.has(row.media_id)) result.set(row.media_id, []);
    result.get(row.media_id).push({ realm: row.realm, weight: row.weight });
  }
  return result;
}

function buildItem(config, pending, base, tags, membership) {
  const title = pending.title || (base && (base.title_english || base.title_romaji)) || null;
  const item = {
    media_type: pending.media_type,
    media_id: pending.media_id,
    title,
    genres: (base && base.genres) || [],
    tags: tags || [],
    average_score: base ? base.average_score : null,
    year: base ? (pending.media_type === 'ANIME'
      ? (base.season_year ?? base.start_date_year ?? null)
      : (base.start_date_year ?? null)) : null,
    format: base ? base.format : null,
    episodes: pending.media_type === 'ANIME' ? (base ? base.episodes : null) : null,
    chapters: pending.media_type === 'MANGA' ? (base ? base.chapters : null) : null,
    source: base ? base.source : null,
    description_normalized: base ? trim600(base.description_normalized) : null,
    synopsis_enhanced: base && base.synopsis_enhanced_state === 'ready'
      ? trim600(base.synopsis_enhanced)
      : null,
    membership: membership || [],
  };
  return item;
}

async function enrichItems(config, pendingItems) {
  const out = [];
  for (let i = 0; i < pendingItems.length; i += QUEUE_PAGE_SIZE) {
    const batch = pendingItems.slice(i, i + QUEUE_PAGE_SIZE);
    const animeIds = batch.filter(x => x.media_type === 'ANIME').map(x => x.media_id);
    const mangaIds = batch.filter(x => x.media_type === 'MANGA').map(x => x.media_id);

    const [animeBase, mangaBase, animeTags, mangaTags, animeMembership, mangaMembership] = await Promise.all([
      fetchBaseRows(config, 'ANIME', animeIds),
      fetchBaseRows(config, 'MANGA', mangaIds),
      fetchTopTags(config, 'ANIME', animeIds),
      fetchTopTags(config, 'MANGA', mangaIds),
      fetchMembership(config, 'ANIME', animeIds),
      fetchMembership(config, 'MANGA', mangaIds),
    ]);

    for (const pending of batch) {
      const isAnime = pending.media_type === 'ANIME';
      out.push(buildItem(
        config,
        pending,
        (isAnime ? animeBase : mangaBase).get(pending.media_id) || null,
        (isAnime ? animeTags : mangaTags).get(pending.media_id) || [],
        (isAnime ? animeMembership : mangaMembership).get(pending.media_id) || []
      ));
    }
    log(`enriched ${Math.min(i + QUEUE_PAGE_SIZE, pendingItems.length)}/${pendingItems.length}`);
  }
  return out;
}

// ---------------------------------------------------------------------------

async function main() {
  const args = parseArgs(process.argv);
  const config = loadSupabaseConfig();
  if (!config.jwt) {
    throw new Error('Missing KURO_TEST_JWT env var — media_realm_llm_pending is revoked from anon (ops queue). Set it to the test-account JWT.');
  }

  const pending = await fetchPendingItems(config, args.limit, args.offset);
  log(`queue: ${pending.length} pending item(s) (limit=${args.limit}, offset=${args.offset})`);
  if (pending.length === 0) {
    process.stdout.write('[]\n');
    return;
  }
  const items = await enrichItems(config, pending);
  process.stdout.write(JSON.stringify(items, null, 2) + '\n');
}

if (require.main === module) {
  main().catch(error => {
    console.error(error.message || error);
    process.exit(1);
  });
}

// Exported for the test harness (and future checkpointed runners): the queue
// page fetch is the only piece a harness needs to stub; enrichment runs
// unchanged against public catalog data.
module.exports = {
  parseArgs,
  loadSupabaseConfig,
  restGet,
  restGetAll,
  fetchPendingItems,
  enrichItems,
};
