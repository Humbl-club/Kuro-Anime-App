/*
  Genre + tag audit for Kuro's Supabase dataset.

  Goal:
  - Verify what "genres" exist on anime/manga (TEXT[] columns).
  - Verify whether "sub-genres" exist as tags (tags + anime_tags/manga_tags join tables).
  - Give concrete counts + top values so we can drive Discover/Browse UI from real data.

  Notes:
  - Read-only (PostgREST) via service role key.
  - Does NOT print secrets.
*/

const { createClient } = require('@supabase/supabase-js');
const { getProjectUrl } = require('./lib/project_config');

// Allow piping to `head` without crashing on EPIPE.
process.stdout.on('error', (err) => {
  if (err && err.code === 'EPIPE') process.exit(0);
});

const SUPABASE_URL = getProjectUrl();
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY env var.');
}

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

function fmtInt(n) {
  return (n ?? 0).toLocaleString('en-US');
}

function topNFromMap(map, n) {
  return [...map.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, n);
}

async function countTable(table) {
  const { error, count } = await supabase
    .from(table)
    .select('*', { count: 'exact', head: true });
  if (error) throw new Error(`${table}: ${error.message}`);
  return count ?? 0;
}

async function fetchGenreFrequencies({ table, limitRows = 25000, pageSize = 1000 }) {
  const freq = new Map();
  let rowsScanned = 0;
  let rowsWithGenres = 0;
  let rowsEmptyGenres = 0;

  for (let offset = 0; offset < limitRows; offset += pageSize) {
    const { data, error } = await supabase
      .from(table)
      .select('id,genres')
      .range(offset, offset + pageSize - 1);

    if (error) throw new Error(`${table} genres fetch: ${error.message}`);
    if (!data || data.length === 0) break;

    for (const row of data) {
      rowsScanned += 1;
      const genres = row.genres;
      if (Array.isArray(genres) && genres.length > 0) {
        rowsWithGenres += 1;
        for (const g of genres) {
          if (!g || typeof g !== 'string') continue;
          freq.set(g, (freq.get(g) ?? 0) + 1);
        }
      } else {
        rowsEmptyGenres += 1;
      }
    }
  }

  return { freq, rowsScanned, rowsWithGenres, rowsEmptyGenres, limitRows };
}

async function fetchTagsCatalog({ pageSize = 1000 }) {
  const categories = new Map();
  const isAdultCounts = { adult: 0, safe: 0, unknown: 0 };
  const tags = [];

  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await supabase
      .from('tags')
      .select('id,name,category,is_adult,rank')
      .order('id', { ascending: true })
      .range(offset, offset + pageSize - 1);

    if (error) throw new Error(`tags fetch: ${error.message}`);
    if (!data || data.length === 0) break;

    for (const t of data) {
      const cat = t.category ?? 'UNKNOWN';
      categories.set(cat, (categories.get(cat) ?? 0) + 1);
      if (t.is_adult === true) isAdultCounts.adult += 1;
      else if (t.is_adult === false) isAdultCounts.safe += 1;
      else isAdultCounts.unknown += 1;
      tags.push(t);
    }
  }

  return { tags, categories, isAdultCounts };
}

async function sampleTagAssociations({ mediaTable, joinAlias, limit = 30 }) {
  // Requires FK relationships for PostgREST embedding.
  // Example: from("anime").select("..., anime_tags(rank, tag:tags(name,category,rank,is_adult))")
  const select = [
    'id',
    'title_english',
    'title_romaji',
    'genres',
    `${joinAlias}:${joinAlias}(rank,tag:tags(name,category,rank,is_adult))`,
  ].join(',');

  const { data, error } = await supabase
    .from(mediaTable)
    .select(select)
    .order('popularity', { ascending: false })
    .limit(limit);

  if (error) throw new Error(`${mediaTable} tag embed: ${error.message}`);
  return data ?? [];
}

async function run() {
  const started = new Date().toISOString();
  console.log(`# Genre/Tag Audit (${started})`);
  console.log('');

  const counts = {
    anime: await countTable('anime'),
    manga: await countTable('manga'),
    tags: await countTable('tags'),
    anime_tags: await countTable('anime_tags'),
    manga_tags: await countTable('manga_tags'),
  };

  console.log('## Table Counts');
  console.log(`- anime: ${fmtInt(counts.anime)}`);
  console.log(`- manga: ${fmtInt(counts.manga)}`);
  console.log(`- tags: ${fmtInt(counts.tags)}`);
  console.log(`- anime_tags (relations): ${fmtInt(counts.anime_tags)}`);
  console.log(`- manga_tags (relations): ${fmtInt(counts.manga_tags)}`);
  console.log('');

  console.log('## Genre Coverage (TEXT[] column)');
  const animeGenres = await fetchGenreFrequencies({ table: 'anime' });
  const mangaGenres = await fetchGenreFrequencies({ table: 'manga' });

  console.log(`- anime scanned: ${fmtInt(animeGenres.rowsScanned)} (cap ${fmtInt(animeGenres.limitRows)})`);
  console.log(`  - with genres: ${fmtInt(animeGenres.rowsWithGenres)}`);
  console.log(`  - empty/null genres: ${fmtInt(animeGenres.rowsEmptyGenres)}`);
  console.log(`  - unique genres (in scanned set): ${fmtInt(animeGenres.freq.size)}`);
  console.log(`- manga scanned: ${fmtInt(mangaGenres.rowsScanned)} (cap ${fmtInt(mangaGenres.limitRows)})`);
  console.log(`  - with genres: ${fmtInt(mangaGenres.rowsWithGenres)}`);
  console.log(`  - empty/null genres: ${fmtInt(mangaGenres.rowsEmptyGenres)}`);
  console.log(`  - unique genres (in scanned set): ${fmtInt(mangaGenres.freq.size)}`);
  console.log('');

  console.log('### Top Anime Genres (by frequency, scanned set)');
  for (const [g, c] of topNFromMap(animeGenres.freq, 25)) {
    console.log(`- ${g}: ${fmtInt(c)}`);
  }
  console.log('');

  console.log('### Top Manga Genres (by frequency, scanned set)');
  for (const [g, c] of topNFromMap(mangaGenres.freq, 25)) {
    console.log(`- ${g}: ${fmtInt(c)}`);
  }
  console.log('');

  console.log('## Tags Catalog (potential sub-genres)');
  const tagCatalog = await fetchTagsCatalog({});
  console.log(`- tags total: ${fmtInt(tagCatalog.tags.length)}`);
  console.log(`- tags is_adult: safe=${fmtInt(tagCatalog.isAdultCounts.safe)}, adult=${fmtInt(tagCatalog.isAdultCounts.adult)}, unknown=${fmtInt(tagCatalog.isAdultCounts.unknown)}`);
  console.log('- tag categories:');
  for (const [cat, c] of topNFromMap(tagCatalog.categories, 30)) {
    console.log(`  - ${cat}: ${fmtInt(c)}`);
  }
  console.log('');

  // Top tags by rank (not usage) to see if we imported meaningful tag metadata.
  const topRankedSafe = tagCatalog.tags
    .filter(t => t && t.name && t.is_adult === false)
    .sort((a, b) => (b.rank ?? 0) - (a.rank ?? 0))
    .slice(0, 25);

  console.log('### Top Tag Names (by tag.rank, safe only)');
  for (const t of topRankedSafe) {
    const cat = t.category ?? 'UNKNOWN';
    console.log(`- ${t.name} (${cat}) rank=${t.rank ?? 0}`);
  }
  console.log('');

  console.log('## Sample: Tag Associations on Top Titles (by popularity)');
  const topAnime = await sampleTagAssociations({ mediaTable: 'anime', joinAlias: 'anime_tags', limit: 20 });
  const topManga = await sampleTagAssociations({ mediaTable: 'manga', joinAlias: 'manga_tags', limit: 20 });

  function summarizeSample(rows, kind) {
    const counts = rows.map(r => (r && Array.isArray(r[`${kind}_tags`]) ? r[`${kind}_tags`].length : 0));
    const avg = counts.length ? counts.reduce((a, b) => a + b, 0) / counts.length : 0;
    const nonZero = counts.filter(n => n > 0).length;
    return { avg, nonZero, total: counts.length };
  }

  const animeSample = summarizeSample(topAnime, 'anime');
  const mangaSample = summarizeSample(topManga, 'manga');

  console.log(`- anime sample: ${fmtInt(animeSample.total)} titles, ${fmtInt(animeSample.nonZero)} with tags, avg tags/title=${animeSample.avg.toFixed(1)}`);
  console.log(`- manga sample: ${fmtInt(mangaSample.total)} titles, ${fmtInt(mangaSample.nonZero)} with tags, avg tags/title=${mangaSample.avg.toFixed(1)}`);
  console.log('');

  function printOne(rows, label, joinKey) {
    const pick = rows.find(r => Array.isArray(r[joinKey]) && r[joinKey].length > 0) || rows[0];
    if (!pick) return;
    const title = pick.title_english || pick.title_romaji || `id=${pick.id}`;
    const g = Array.isArray(pick.genres) ? pick.genres.join(', ') : '';
    const tags = Array.isArray(pick[joinKey])
      ? pick[joinKey]
          .slice(0, 10)
          .map(x => x && x.tag && x.tag.name ? `${x.tag.name}${x.tag.category ? ` (${x.tag.category})` : ''}` : null)
          .filter(Boolean)
          .join(', ')
      : '';

    console.log(`### Example ${label}`);
    console.log(`- title: ${title}`);
    console.log(`- genres: ${g || '(none)'}`);
    console.log(`- tags: ${tags || '(none)'}`);
    console.log('');
  }

  printOne(topAnime, 'Anime', 'anime_tags');
  printOne(topManga, 'Manga', 'manga_tags');

  console.log('## Notes');
  console.log('- `genres` is a broad TEXT[] list (good for simple filtering, not great for discovery).');
  console.log('- `tags` + `anime_tags`/`manga_tags` are the real "sub-genre" system; if we drive UI from tags, genres will feel much more specific.');
}

run().catch((e) => {
  console.error('Audit failed:', e && e.message ? e.message : e);
  process.exit(1);
});
