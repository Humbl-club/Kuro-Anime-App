#!/usr/bin/env node

/*
  Fetch context bundles for media_realm_llm rows with confidence < threshold
  (Stage 2 QA pass). Writes JSON array to stdout.

    node scripts/realm_llm_qa_fetch.js [--max-confidence 0.7] > /tmp/qa_items.json

  Env: SUPABASE_SERVICE_ROLE_KEY (or KURO_TEST_JWT) + xcconfig URL/anon.
*/

const fs = require('fs');
const path = require('path');

const XCCONFIG_PATH = path.join(__dirname, '..', 'Config', 'Shared.xcconfig');
const SYNOPSIS_TRIM = 600;
const TOP_TAGS = 8;

function log(...args) { console.error('[qa-fetch]', ...args); }

function loadConfig() {
  const values = {};
  if (fs.existsSync(XCCONFIG_PATH)) {
    for (const line of fs.readFileSync(XCCONFIG_PATH, 'utf8').split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('//')) continue;
      const idx = trimmed.indexOf('=');
      if (idx <= 0) continue;
      values[trimmed.slice(0, idx).trim()] =
        trimmed.slice(idx + 1).trim().replace(/\$\(\)/g, '');
    }
  }
  const url = (process.env.SUPABASE_URL || values.SUPABASE_URL || '').replace(/\/+$/, '');
  const anonKey = process.env.SUPABASE_ANON_KEY || values.SUPABASE_ANON_KEY;
  const bearer = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.KURO_TEST_JWT;
  if (!url || !anonKey) throw new Error('Missing SUPABASE_URL / SUPABASE_ANON_KEY');
  if (!bearer) throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY or KURO_TEST_JWT');
  return { url, anonKey, bearer };
}

function parseArgs(argv) {
  let maxConfidence = 0.7;
  const list = argv.slice(2);
  for (let i = 0; i < list.length; i++) {
    if (list[i] === '--max-confidence' && list[i + 1]) {
      maxConfidence = Number.parseFloat(list[++i]);
    } else {
      throw new Error(`Unknown arg: ${list[i]}`);
    }
  }
  return { maxConfidence };
}

async function restGet(cfg, pathAndQuery) {
  const res = await fetch(`${cfg.url}/rest/v1/${pathAndQuery}`, {
    headers: {
      apikey: cfg.anonKey,
      Authorization: `Bearer ${cfg.bearer}`,
    },
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`GET ${pathAndQuery} → ${res.status}: ${text}`);
  return text ? JSON.parse(text) : [];
}

function trimText(s, n) {
  if (!s) return null;
  const t = String(s).trim();
  if (!t) return null;
  return [...t].length <= n ? t : [...t].slice(0, n).join('');
}

async function hydrateAnime(cfg, ids) {
  if (!ids.length) return new Map();
  const map = new Map();
  for (let i = 0; i < ids.length; i += 80) {
    const chunk = ids.slice(i, i + 80);
    const rows = await restGet(
      cfg,
      `anime?id=in.(${chunk.join(',')})&select=id,title_romaji,title_english,genres,average_score,season_year,start_date_year,format,episodes,source,description_normalized,is_adult`
    );
    for (const r of rows) map.set(r.id, r);
  }
  return map;
}

async function hydrateManga(cfg, ids) {
  if (!ids.length) return new Map();
  const map = new Map();
  for (let i = 0; i < ids.length; i += 80) {
    const chunk = ids.slice(i, i + 80);
    const rows = await restGet(
      cfg,
      `manga?id=in.(${chunk.join(',')})&select=id,title_romaji,title_english,genres,average_score,start_date_year,format,chapters,source,description_normalized,is_adult`
    );
    for (const r of rows) map.set(r.id, r);
  }
  return map;
}

async function membershipFor(cfg, mediaType, ids) {
  if (!ids.length) return new Map();
  const map = new Map();
  for (let i = 0; i < ids.length; i += 80) {
    const chunk = ids.slice(i, i + 80);
    const rows = await restGet(
      cfg,
      `media_realm_membership?media_type=eq.${mediaType}&media_id=in.(${chunk.join(',')})&select=media_id,realm,weight&order=weight.desc`
    );
    for (const r of rows) {
      const key = r.media_id;
      if (!map.has(key)) map.set(key, []);
      map.get(key).push({ realm: r.realm, weight: r.weight });
    }
  }
  return map;
}

async function topTags(cfg, mediaType, ids) {
  if (!ids.length) return new Map();
  const map = new Map();
  const joinTable = mediaType === 'ANIME' ? 'anime_tags' : 'manga_tags';
  const idCol = mediaType === 'ANIME' ? 'anime_id' : 'manga_id';
  for (let i = 0; i < ids.length; i += 40) {
    const chunk = ids.slice(i, i + 40);
    const rows = await restGet(
      cfg,
      `${joinTable}?${idCol}=in.(${chunk.join(',')})&select=${idCol},rank,tags(name)&order=rank.asc&limit=1000`
    );
    for (const r of rows) {
      const mid = r[idCol];
      if (!map.has(mid)) map.set(mid, []);
      const arr = map.get(mid);
      if (arr.length >= TOP_TAGS) continue;
      const name = r.tags && r.tags.name;
      if (name) arr.push(name);
    }
  }
  return map;
}

async function main() {
  const args = parseArgs(process.argv);
  const cfg = loadConfig();
  log(`loading llm rows with confidence < ${args.maxConfidence}`);

  const llm = await restGet(
    cfg,
    `media_realm_llm?confidence=lt.${args.maxConfidence}&select=media_type,media_id,realms,tone,register,pacing,confidence,descriptor,model&order=confidence.asc&limit=1000`
  );
  log(`found ${llm.length} rows`);

  const animeIds = llm.filter((r) => r.media_type === 'ANIME').map((r) => r.media_id);
  const mangaIds = llm.filter((r) => r.media_type === 'MANGA').map((r) => r.media_id);

  const [anime, manga, aMem, mMem, aTags, mTags] = await Promise.all([
    hydrateAnime(cfg, animeIds),
    hydrateManga(cfg, mangaIds),
    membershipFor(cfg, 'ANIME', animeIds),
    membershipFor(cfg, 'MANGA', mangaIds),
    topTags(cfg, 'ANIME', animeIds),
    topTags(cfg, 'MANGA', mangaIds),
  ]);

  const items = llm.map((row) => {
    const cat = row.media_type === 'ANIME' ? anime.get(row.media_id) : manga.get(row.media_id);
    const title = cat
      ? (cat.title_english || cat.title_romaji || `#${row.media_id}`)
      : `#${row.media_id}`;
    return {
      media_type: row.media_type,
      media_id: row.media_id,
      title,
      genres: (cat && cat.genres) || [],
      tags: (row.media_type === 'ANIME' ? aTags : mTags).get(row.media_id) || [],
      average_score: cat && cat.average_score,
      year: cat && (cat.season_year || cat.start_date_year),
      format: cat && cat.format,
      episodes: cat && cat.episodes,
      chapters: cat && cat.chapters,
      source: cat && cat.source,
      description_normalized: trimText(cat && cat.description_normalized, SYNOPSIS_TRIM),
      membership: (row.media_type === 'ANIME' ? aMem : mMem).get(row.media_id) || [],
      existing: {
        realms: row.realms,
        tone: row.tone,
        register: row.register,
        pacing: row.pacing,
        confidence: row.confidence,
        descriptor: row.descriptor,
        model: row.model,
      },
    };
  });

  console.log(JSON.stringify(items, null, 2));
  log(`wrote ${items.length} QA work items`);
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
