/*
  Generates curated rail expansion candidates from the live catalog.
  Queries anime/manga tables for titles that match "classic" or "gateway"
  criteria but are NOT already in curated_rail_items.

  Criteria (aligned with curated rails quality bar):
    Classics: pre-2020, score >= 76, favourites >= 2000 (anime) / >= 500 (manga),
              NOT ecchi/hentai, NOT adult.
    Gateway:  any year, score >= 78, sorted by popularity DESC (most popular first),
              NOT ecchi/hentai, NOT adult, standalone entries preferred.

  Usage:
    SUPABASE_SERVICE_ROLE_KEY="..." node scripts/generate_curated_rail_candidates.js
*/

const { createClient } = require('@supabase/supabase-js');
const { getProjectUrl } = require('./lib/project_config');

const SUPABASE_URL = getProjectUrl();
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY env var.');
}

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

// Genres to exclude from all curated rails
const EXCLUDED_GENRES = ['Ecchi', 'Hentai'];

async function getExistingRailItems() {
  const { data, error } = await supabase
    .from('curated_rail_items')
    .select('rail_id, media_type, anilist_id');
  if (error) throw error;

  const sets = {};
  for (const item of data) {
    const key = `${item.rail_id}`;
    if (!sets[key]) sets[key] = new Set();
    sets[key].add(item.anilist_id);
  }
  return sets;
}

function hasExcludedGenre(genres) {
  if (!genres || !Array.isArray(genres)) return false;
  return genres.some(g => EXCLUDED_GENRES.includes(g));
}

async function queryAnime(filters, orderBy, limit = 300) {
  let q = supabase
    .from('anime')
    .select('anilist_id, title_english, title_romaji, format, status, start_date_year, average_score, popularity, favourites, genres');

  for (const [col, op, val] of filters) {
    q = q.filter(col, op, val);
  }

  for (const [col, opts] of orderBy) {
    q = q.order(col, opts);
  }

  const { data, error } = await q.limit(limit);
  if (error) throw error;
  return (data || []).filter(a => !hasExcludedGenre(a.genres));
}

async function queryManga(filters, orderBy, limit = 300) {
  let q = supabase
    .from('manga')
    .select('anilist_id, title_english, title_romaji, format, status, start_date_year, average_score, popularity, favourites, genres');

  for (const [col, op, val] of filters) {
    q = q.filter(col, op, val);
  }

  for (const [col, opts] of orderBy) {
    q = q.order(col, opts);
  }

  const { data, error } = await q.limit(limit);
  if (error) throw error;
  return (data || []).filter(m => !hasExcludedGenre(m.genres));
}

function displayName(item) {
  return item.title_english || item.title_romaji || `AniList#${item.anilist_id}`;
}

async function main() {
  const existing = await getExistingRailItems();
  const classicsAnimeSet = existing['classics_anime'] || new Set();
  const classicsMangaSet = existing['classics_manga'] || new Set();
  const gatewayAnimeSet = existing['gateway_anime'] || new Set();
  const gatewayMangaSet = existing['gateway_manga'] || new Set();

  console.log('# Curated Rail Expansion Candidates');
  console.log(`Generated: ${new Date().toISOString()}`);
  console.log('');

  // ═══════════════════════════════════════════
  // CLASSICS ANIME CANDIDATES
  // ═══════════════════════════════════════════
  console.log('## CLASSICS ANIME CANDIDATES');
  console.log('Criteria: pre-2020, score >= 76, favourites >= 2000, NOT ecchi/hentai, NOT adult');
  console.log('');

  const classicsAnimeCandidates = await queryAnime(
    [
      ['start_date_year', 'lte', 2019],
      ['start_date_year', 'gt', 0],
      ['favourites', 'gte', 2000],
      ['average_score', 'gte', 76],
      ['is_adult', 'eq', false],
    ],
    [['favourites', { ascending: false }]],
    400
  );

  const classicsAnimeNew = classicsAnimeCandidates.filter(
    a => a.anilist_id && !classicsAnimeSet.has(a.anilist_id)
  );

  for (const a of classicsAnimeNew.slice(0, 80)) {
    console.log(`- [${a.anilist_id}] **${displayName(a)}** (${a.start_date_year || '?'}) — Score: ${a.average_score}, Fav: ${a.favourites}, Pop: ${a.popularity}, Genres: ${(a.genres || []).join(', ')}`);
  }
  console.log('');
  console.log(`**Total candidates: ${classicsAnimeNew.length}**`);
  console.log('');

  // ═══════════════════════════════════════════
  // CLASSICS MANGA CANDIDATES
  // ═══════════════════════════════════════════
  console.log('## CLASSICS MANGA CANDIDATES');
  console.log('Criteria: pre-2020, score >= 76, favourites >= 500, NOT ecchi/hentai, NOT adult');
  console.log('');

  const classicsMangaCandidates = await queryManga(
    [
      ['start_date_year', 'lte', 2019],
      ['start_date_year', 'gt', 0],
      ['favourites', 'gte', 500],
      ['average_score', 'gte', 76],
      ['is_adult', 'eq', false],
    ],
    [['favourites', { ascending: false }]],
    400
  );

  const classicsMangaNew = classicsMangaCandidates.filter(
    m => m.anilist_id && !classicsMangaSet.has(m.anilist_id)
  );

  for (const m of classicsMangaNew.slice(0, 80)) {
    console.log(`- [${m.anilist_id}] **${displayName(m)}** (${m.start_date_year || '?'}) — Score: ${m.average_score}, Fav: ${m.favourites}, Pop: ${m.popularity}, Genres: ${(m.genres || []).join(', ')}`);
  }
  console.log('');
  console.log(`**Total candidates: ${classicsMangaNew.length}**`);
  console.log('');

  // ═══════════════════════════════════════════
  // GATEWAY ANIME CANDIDATES
  // ═══════════════════════════════════════════
  console.log('## GATEWAY ANIME CANDIDATES');
  console.log('Criteria: score >= 78, sorted by popularity DESC, NOT ecchi/hentai, NOT adult');
  console.log('');

  const gatewayAnimeCandidates = await queryAnime(
    [
      ['average_score', 'gte', 78],
      ['is_adult', 'eq', false],
    ],
    [['popularity', { ascending: false }]],
    300
  );

  const gatewayAnimeNew = gatewayAnimeCandidates.filter(
    a => a.anilist_id && !gatewayAnimeSet.has(a.anilist_id)
  );

  for (const a of gatewayAnimeNew.slice(0, 80)) {
    console.log(`- [${a.anilist_id}] **${displayName(a)}** (${a.start_date_year || '?'}) — Score: ${a.average_score}, Pop: ${a.popularity}, Fav: ${a.favourites}, Genres: ${(a.genres || []).join(', ')}`);
  }
  console.log('');
  console.log(`**Total candidates: ${gatewayAnimeNew.length}**`);
  console.log('');

  // ═══════════════════════════════════════════
  // GATEWAY MANGA CANDIDATES
  // ═══════════════════════════════════════════
  console.log('## GATEWAY MANGA CANDIDATES');
  console.log('Criteria: score >= 78, sorted by popularity DESC, NOT ecchi/hentai, NOT adult');
  console.log('');

  const gatewayMangaCandidates = await queryManga(
    [
      ['average_score', 'gte', 78],
      ['is_adult', 'eq', false],
    ],
    [['popularity', { ascending: false }]],
    300
  );

  const gatewayMangaNew = gatewayMangaCandidates.filter(
    m => m.anilist_id && !gatewayMangaSet.has(m.anilist_id)
  );

  for (const m of gatewayMangaNew.slice(0, 80)) {
    console.log(`- [${m.anilist_id}] **${displayName(m)}** (${m.start_date_year || '?'}) — Score: ${m.average_score}, Pop: ${m.popularity}, Fav: ${m.favourites}, Genres: ${(m.genres || []).join(', ')}`);
  }
  console.log('');
  console.log(`**Total candidates: ${gatewayMangaNew.length}**`);
  console.log('');

  // ═══════════════════════════════════════════
  // SUMMARY
  // ═══════════════════════════════════════════
  console.log('## SUMMARY');
  console.log(`| Rail | Currently | New candidates |`);
  console.log(`|------|-----------|----------------|`);
  console.log(`| classics_anime | ${classicsAnimeSet.size} | ${classicsAnimeNew.length} |`);
  console.log(`| classics_manga | ${classicsMangaSet.size} | ${classicsMangaNew.length} |`);
  console.log(`| gateway_anime | ${gatewayAnimeSet.size} | ${gatewayAnimeNew.length} |`);
  console.log(`| gateway_manga | ${gatewayMangaSet.size} | ${gatewayMangaNew.length} |`);
}

main().catch(e => { console.error(e); process.exit(1); });
