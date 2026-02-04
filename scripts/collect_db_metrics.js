/*
  Collects live database metrics using Supabase PostgREST and prints a Markdown-friendly snapshot.
  Safe: read-only queries using service role key from test_supabase_connection.js (project constants here to avoid env juggling).
*/

const { createClient } = require('@supabase/supabase-js');

// Project constants (mirroring test_supabase_connection.js)
const SUPABASE_URL = 'https://bkdifromsqxkndnllmdj.supabase.co';
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY env var.');
}

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

function nowIso() {
  return new Date().toISOString();
}

async function countTable(table) {
  const { error, count } = await supabase
    .from(table)
    .select('*', { count: 'exact', head: true });
  if (error) return { table, error: error.message };
  return { table, count: count ?? 0 };
}

async function countWhere(table, filters) {
  let q = supabase.from(table).select('*', { count: 'exact', head: true });
  for (const [col, op, val] of filters) {
    if (op === 'not_is_null') q = q.not(col, 'is', null);
    else if (op === 'is_null') q = q.is(col, null);
    else if (op === 'ilike') q = q.ilike(col, val);
    else if (op === 'like') q = q.like(col, val);
    else if (op === 'gte') q = q.gte(col, val);
    else if (op === 'lt') q = q.lt(col, val);
    else if (op === 'or') q = q.or(val); // pass raw or string, e.g. 'a.not.is.null,b.not.is.null'
  }
  const { error, count } = await q;
  if (error) return { error: error.message };
  return { count: count ?? 0 };
}

async function run() {
  const startTs = nowIso();
  const tables = [
    'anime','manga','episodes','chapters','volumes',
    'characters','studios','authors','staff','tags',
    'anime_characters','manga_characters','anime_studios','manga_authors','anime_staff','manga_staff',
    'anime_tags','manga_tags','anime_user_lists','manga_user_lists','anime_comments','manga_comments',
    'import_state'
  ];

  const counts = {};
  for (const t of tables) {
    try {
      const res = await countTable(t);
      if (res.error) counts[t] = { error: res.error };
      else counts[t] = res.count;
    } catch (e) {
      counts[t] = { error: String(e && e.message || e) };
    }
  }

  // Airing windows (anime)
  const now = new Date();
  const in24h = new Date(now.getTime() + 24*60*60*1000);
  const airingNext24h = await countWhere('anime', [['next_airing_at','gte', now.toISOString()], ['next_airing_at','lt', in24h.toISOString()]]);
  const airingWithTimestamp = await countWhere('anime', [['next_airing_at','not_is_null']]);

  // Manga next chapter presence
  const mangaNextChapterKnown = await countWhere('manga', [['or','next_chapter_at.not.is.null,next_chapter_number.not.is.null']]);

  // Mirroring coverage & remote leftovers
  const animeCoverStorage = await countWhere('anime', [['cover_image_medium','like','%/storage/v1/object/public/%']]);
  const mangaCoverStorage = await countWhere('manga', [['cover_image_medium','like','%/storage/v1/object/public/%']]);
  const charactersImageStorage = await countWhere('characters', [['image_large','like','%/storage/v1/object/public/%']]);
  const staffImageStorage = await countWhere('staff', [['image_large','like','%/storage/v1/object/public/%']]);

  const animeCoverRemote = await countWhere('anime', [['cover_image_medium','ilike','http%'], ['cover_image_medium','not_is_null'], ['cover_image_medium','like','%']]);
  // adjust remote not mirrored: http(s) and NOT storage — emulate with OR and negation not easily supported; approximate via http% minus storage count if needed
  const mangaCoverRemote = await countWhere('manga', [['cover_image_medium','ilike','http%'], ['cover_image_medium','not_is_null'], ['cover_image_medium','like','%']]);

  // User list breakdowns (known enums from schema comments)
  const animeListTypes = ['WATCHING','COMPLETED','PLANNING','DROPPED','PAUSED'];
  const mangaListTypes = ['READING','COMPLETED','PLANNING','DROPPED','PAUSED'];
  const animeUserListCounts = {};
  const mangaUserListCounts = {};
  for (const lt of animeListTypes) {
    const { count } = await countWhere('anime_user_lists', [['list_type','like', lt]]);
    animeUserListCounts[lt] = count;
  }
  for (const lt of mangaListTypes) {
    const { count } = await countWhere('manga_user_lists', [['list_type','like', lt]]);
    mangaUserListCounts[lt] = count;
  }

  // Basic missingness coverage for core entities
  async function coverage(table, fields) {
    const total = typeof counts[table] === 'number' ? counts[table] : 0;
    const res = { total };
    for (const f of fields) {
      const have = await countWhere(table, [[f,'not_is_null']]);
      res[f] = have.count;
    }
    return res;
  }

  const animeCoverage = await coverage('anime', ['title_english','cover_image_medium','banner_image','description','genres','average_score','episodes']);
  const mangaCoverage = await coverage('manga', ['title_english','cover_image_medium','banner_image','description','genres','volumes','chapters']);
  const characterCoverage = await coverage('characters', ['name_full','image_large','description']);
  const staffCoverage = await coverage('staff', ['name_full','image_large','description']);
  const authorCoverage = await coverage('authors', ['name_full','image_large','description']);

  // Output snapshot in a CSV-like blocks under headings for easy paste into knowledge file.
  console.log(`Snapshot: ${startTs}`);
  console.log('table,rows');
  for (const t of tables) {
    const v = counts[t];
    if (typeof v === 'number') console.log(`${t},${v}`);
    else console.log(`${t},ERROR:${v && v.error ? v.error.replace(/\n/g,' ') : 'unknown'}`);
  }

  function metric(k, v) { console.log(`metric,${k},${v}`); }
  metric('airing_next_24h', airingNext24h.count ?? 0);
  metric('airing_with_timestamp', airingWithTimestamp.count ?? 0);
  metric('manga_next_chapter_known', mangaNextChapterKnown.count ?? 0);
  metric('anime_cover_medium_storage', animeCoverStorage.count ?? 0);
  metric('manga_cover_medium_storage', mangaCoverStorage.count ?? 0);
  metric('characters_image_storage', charactersImageStorage.count ?? 0);
  metric('staff_image_storage', staffImageStorage.count ?? 0);
  metric('anime_cover_medium_http_like', animeCoverRemote.count ?? 0);
  metric('manga_cover_medium_http_like', mangaCoverRemote.count ?? 0);

  for (const [lt, c] of Object.entries(animeUserListCounts)) metric(`anime_user_lists_${lt}`, c);
  for (const [lt, c] of Object.entries(mangaUserListCounts)) metric(`manga_user_lists_${lt}`, c);

  function coverageBlock(name, cov) {
    console.log(`coverage,${name},total,${cov.total}`);
    for (const [k,v] of Object.entries(cov)) {
      if (k === 'total') continue;
      console.log(`coverage,${name},${k},${v}`);
    }
  }
  coverageBlock('anime', animeCoverage);
  coverageBlock('manga', mangaCoverage);
  coverageBlock('characters', characterCoverage);
  coverageBlock('staff', staffCoverage);
  coverageBlock('authors', authorCoverage);

  console.log('END');
}

run().catch(e => {
  console.error('Failed to collect metrics:', e);
  process.exit(1);
});
