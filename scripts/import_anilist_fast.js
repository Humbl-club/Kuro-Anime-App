/*
  High-throughput AniList → Supabase importer
  - Bulk upserts per page to cut network calls
  - Resolves MAL ID unique conflicts by nulling duplicates before upsert
  - Optional multi-page concurrency
*/

const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = 'https://bkdifromsqxkndnllmdj.supabase.co';
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY env var.');
}
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

const ANILIST_API = 'https://graphql.anilist.co';
const PAGE_DELAY_MS = 250; // minimal backoff between waves

const STREAMING_SITE_PRIORITY = [
  'crunchyroll',
  'netflix',
  'hidive',
  'disney',
  'amazon',
  'prime video',
  'hulu',
  'youtube',
  'apple tv',
  'max'
];

const MANGA_READER_PRIORITY = [
  'manga plus',
  'viz',
  'bookwalker',
  'comixology',
  'kindle',
  'kodansha',
  'yen press',
  'azuki'
];

const STREAMING_DOMAIN_HINTS = [
  'crunchyroll.com',
  'hidive.com',
  'netflix.com',
  'disneyplus.com',
  'disney.nl',
  'amazon.com',
  'primevideo.com',
  'hulu.com',
  'youtube.com',
  'tv.apple.com',
  'hbomax.com',
  'play.google.com',
  'itunes.apple.com'
];

const MANGA_DOMAIN_HINTS = [
  'mangaplus.shueisha.co.jp',
  'mangaplus.shueisha.co',
  'viz.com',
  'bookwalker.jp',
  'bookwalker.com',
  'comixology.com',
  'kindle',
  'kodansha.us',
  'yenpress.com',
  'azuki.co'
];

function isStreamingLink(isAnime, link) {
  if (!link || !link.url) return false;
  const url = link.url.toLowerCase();
  if (!url.startsWith('http')) return false;
  const site = (link.site || '').toLowerCase();
  const priorityList = isAnime ? STREAMING_SITE_PRIORITY : MANGA_READER_PRIORITY;
  const domainHints = isAnime ? STREAMING_DOMAIN_HINTS : MANGA_DOMAIN_HINTS;
  if (priorityList.some(name => site.includes(name))) return true;
  return domainHints.some(domain => url.includes(domain));
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }
function chunk(arr, n) { const r=[]; for (let i=0;i<arr.length;i+=n) r.push(arr.slice(i,i+n)); return r; }
function uniqueBy(arr, key) { const m=new Map(); for (const x of arr) { const k=key(x); if (!m.has(k)) m.set(k,x);} return [...m.values()]; }

async function fetchPage(kind, page) {
  const isAnime = kind === 'ANIME';
  const mediaType = isAnime ? 'ANIME' : 'MANGA';
  const query = `
    query ($page: Int) {
      Page(page: $page, perPage: 50) {
        pageInfo { currentPage hasNextPage }
        media(sort: POPULARITY_DESC, type: ${mediaType}) {
          id idMal
          title { romaji english native userPreferred }
          synonyms
          coverImage { extraLarge large medium color }
          bannerImage
          type format status
          description(asHtml: false)
          source countryOfOrigin isAdult
          startDate { year month day }
          endDate { year month day }
          ${isAnime ? 'episodes duration season seasonYear nextAiringEpisode { episode airingAt }' : 'chapters volumes'}
          averageScore meanScore popularity trending favourites
          genres
          siteUrl updatedAt
          externalLinks { url site language color isDisabled }
          ${isAnime ? 'streamingEpisodes { title thumbnail url site }' : ''}
          studios { nodes { id name isAnimationStudio siteUrl favourites } }
          tags { id name description category rank isGeneralSpoiler isMediaSpoiler isAdult }
          characters(sort: ROLE, perPage: 50) { edges { role } nodes { id name { full native } image { large } description gender age } }
          staff(sort: RELEVANCE, perPage: 50) { edges { role } nodes { id name { full native } image { large } description primaryOccupations } }
        }
      }
    }
  `;
  const res = await fetch(ANILIST_API, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ query, variables: { page } }) });
  if (!res.ok) throw new Error(`AniList HTTP ${res.status}`);
  const data = await res.json();
  return data?.data?.Page ?? { pageInfo: {}, media: [] };
}

async function resolveIdMap(table, keyField, ids) {
  if (ids.length === 0) return new Map();
  const { data, error } = await supabase.from(table).select(`id, ${keyField}`).in(keyField, ids);
  if (error) throw error;
  const map = new Map();
  for (const row of data) map.set(row[keyField], row.id);
  return map;
}

async function fixMalConflicts(table, rows) {
  const malKey = 'mal_id';
  const malIds = uniqueBy(rows.filter(r => r[malKey]), r => r[malKey]).map(r => r[malKey]);
  if (malIds.length === 0) return rows;
  const { data, error } = await supabase.from(table).select(`id, anilist_id, ${malKey}`).in(malKey, malIds);
  if (error) return rows; // best-effort
  const existingByMal = new Map();
  for (const r of data) existingByMal.set(r[malKey], r.anilist_id);
  return rows.map(r => {
    const existing = existingByMal.get(r.mal_id);
    if (existing && existing !== r.anilist_id) return { ...r, mal_id: null };
    return r;
  });
}

async function upsertBulk(table, rows, onConflict) {
  if (rows.length === 0) return;
  for (const c of chunk(rows, 1000)) {
    const { error } = await supabase.from(table).upsert(c, { onConflict });
    if (error) throw error;
  }
}

async function processPage(kind, page) {
  const isAnime = kind === 'ANIME';
  // retry with backoff for 429s
  let pageData;
  for (let attempt = 0;; attempt++) {
    try {
      pageData = await fetchPage(kind, page);
      break;
    } catch (e) {
      const msg = String(e && e.message || e);
      if (msg.includes('429') && attempt < 3) {
        const wait = 15000 * (attempt + 1);
        await sleep(wait);
        continue;
      }
      throw e;
    }
  }
  const media = pageData.media || [];
  if (media.length === 0) return { page, processed: 0 };

  // Build base entity rows
  const baseRows = media.map(m => ({
    anilist_id: m.id,
    mal_id: m.idMal,
    title_english: m.title?.english,
    title_romaji: m.title?.romaji,
    title_native: m.title?.native,
    title_synonyms: m.synonyms,
    cover_image_large: m.coverImage?.large,
    cover_image_medium: m.coverImage?.medium,
    cover_image_color: m.coverImage?.color,
    banner_image: m.bannerImage,
    format: m.format,
    status: m.status,
    description: m.description,
    ...(isAnime ? { episodes: m.episodes, duration: m.duration, total_duration: m.episodes && m.duration ? m.episodes * m.duration : null, season: m.season, season_year: m.seasonYear, next_episode_number: m.nextAiringEpisode?.episode ?? null, next_airing_at: m.nextAiringEpisode?.airingAt ? new Date(m.nextAiringEpisode.airingAt * 1000).toISOString() : null } : { chapters: m.chapters, volumes: m.volumes, next_chapter_number: null, next_chapter_at: null }),
    start_date_year: m.startDate?.year,
    start_date_month: m.startDate?.month,
    start_date_day: m.startDate?.day,
    end_date_year: m.endDate?.year,
    end_date_month: m.endDate?.month,
    end_date_day: m.endDate?.day,
    average_score: m.averageScore,
    mean_score: m.meanScore,
    popularity: m.popularity,
    trending: m.trending,
    favourites: m.favourites,
    genres: m.genres,
    source: m.source,
    country_of_origin: m.countryOfOrigin,
    is_adult: m.isAdult,
    site_url: m.siteUrl,
    updated_at_anilist: m.updatedAt ? new Date(m.updatedAt * 1000).toISOString() : null,
    last_synced_at: new Date().toISOString(),
  }));

  // Fix MAL duplicates before upsert
  const table = isAnime ? 'anime' : 'manga';
  const preppedRows = await fixMalConflicts(table, baseRows);
  await upsertBulk(table, preppedRows, 'anilist_id');

  // Resolve internal IDs for media
  const mediaIdMap = await resolveIdMap(table, 'anilist_id', media.map(m => m.id));

  // Studios/Authors/Staff/Characters/Tags
  const studios = isAnime ? media.flatMap(m => (m.studios?.nodes || []).map(s => ({ anilist_id: s.id, name: s.name, is_animation_studio: s.isAnimationStudio, site_url: s.siteUrl, favourites: s.favourites }))) : [];
  const authors = !isAnime ? media.flatMap(m => (m.staff?.nodes || []).map(p => ({ anilist_id: p.id, name_full: p.name?.full, name_native: p.name?.native, image_large: p.image?.large, description: p.description }))) : [];
  const staff = media.flatMap(m => (m.staff?.nodes || []).map(p => ({ anilist_id: p.id, name_full: p.name?.full, name_native: p.name?.native, image_large: p.image?.large, description: p.description, primary_occupations: p.primaryOccupations })));
  const characters = media.flatMap(m => (m.characters?.nodes || []).map(c => {
    const ageStr = c.age;
    let age = null;
    if (typeof ageStr === 'number') age = ageStr;
    else if (typeof ageStr === 'string') {
      const n = parseInt(ageStr, 10);
      age = Number.isFinite(n) ? n : null;
    }
    return { anilist_id: c.id, name_full: c.name?.full, name_native: c.name?.native, image_large: c.image?.large, description: c.description, gender: c.gender, age };
  }));
  const tags = media.flatMap(m => (m.tags || []).map(t => ({ anilist_id: t.id, name: t.name, description: t.description, category: t.category, is_general_spoiler: t.isGeneralSpoiler, is_media_spoiler: t.isMediaSpoiler, is_adult: t.isAdult, rank: t.rank ?? 0 })));

  await upsertBulk('tags', uniqueBy(tags, x => x.anilist_id).slice(0), 'anilist_id');
  if (studios.length) await upsertBulk('studios', uniqueBy(studios, x => x.anilist_id), 'anilist_id');
  if (authors.length) await upsertBulk('authors', uniqueBy(authors, x => x.anilist_id), 'anilist_id');
  await upsertBulk('staff', uniqueBy(staff, x => x.anilist_id), 'anilist_id');
  await upsertBulk('characters', uniqueBy(characters, x => x.anilist_id), 'anilist_id');

  // Resolve mappings for relation tables
  const studioMap = studios.length ? await resolveIdMap('studios', 'anilist_id', uniqueBy(studios, x => x.anilist_id).map(x => x.anilist_id)) : new Map();
  const authorMap = authors.length ? await resolveIdMap('authors', 'anilist_id', uniqueBy(authors, x => x.anilist_id).map(x => x.anilist_id)) : new Map();
  const staffMap = await resolveIdMap('staff', 'anilist_id', uniqueBy(staff, x => x.anilist_id).map(x => x.anilist_id));
  const charMap = await resolveIdMap('characters', 'anilist_id', uniqueBy(characters, x => x.anilist_id).map(x => x.anilist_id));
  const tagMap = await resolveIdMap('tags', 'anilist_id', uniqueBy(tags, x => x.anilist_id).map(x => x.anilist_id));

  // Build relation rows
  const anime_studios = [];
  const anime_tags = [];
  const anime_characters = [];
  const anime_staff = [];
  const manga_authors = [];
  const manga_tags = [];
  const manga_characters = [];
  const manga_staff = [];
  const externalLinkRows = [];

  for (const m of media) {
    const mediaId = mediaIdMap.get(m.id);
    if (!mediaId) continue;
    const filteredExternal = (m.externalLinks || []).filter(link => isStreamingLink(isAnime, link));
    if (filteredExternal.length) {
      const seenUrls = new Set();
      filteredExternal.forEach((link, idx) => {
        if (!link.url) return;
        const key = `${mediaId}-${link.url}`;
        if (seenUrls.has(key)) return;
        seenUrls.add(key);
        externalLinkRows.push({
          media_type: isAnime ? 'ANIME' : 'MANGA',
          media_id: mediaId,
          site: link.site || null,
          url: link.url,
          language: link.language || null,
          color: link.color || null,
          priority: idx + 1,
          is_disabled: !!link.isDisabled
        });
      });
    }

    if (isAnime) {
      for (const s of (m.studios?.nodes || [])) {
        const sid = studioMap.get(s.id); if (sid) anime_studios.push({ anime_id: mediaId, studio_id: sid });
      }
      for (const t of (m.tags || [])) {
        const tid = tagMap.get(t.id); if (tid) anime_tags.push({ anime_id: mediaId, tag_id: tid, rank: t.rank ?? 0 });
      }
      if (m.characters?.nodes && m.characters?.edges) {
        for (let i=0;i<m.characters.nodes.length;i++) {
          const n = m.characters.nodes[i]; const e = m.characters.edges[i]; const cid = charMap.get(n.id); if (cid) anime_characters.push({ anime_id: mediaId, character_id: cid, role: e?.role });
        }
      }
      if (m.staff?.nodes && m.staff?.edges) {
        for (let i=0;i<m.staff.nodes.length;i++) {
          const n = m.staff.nodes[i]; const e = m.staff.edges[i]; const sid = staffMap.get(n.id); if (sid) anime_staff.push({ anime_id: mediaId, staff_id: sid, role: e?.role });
        }
      }
    } else {
      for (const t of (m.tags || [])) {
        const tid = tagMap.get(t.id); if (tid) manga_tags.push({ manga_id: mediaId, tag_id: tid, rank: t.rank ?? 0 });
      }
      if (m.characters?.nodes && m.characters?.edges) {
        for (let i=0;i<m.characters.nodes.length;i++) {
          const n = m.characters.nodes[i]; const e = m.characters.edges[i]; const cid = charMap.get(n.id); if (cid) manga_characters.push({ manga_id: mediaId, character_id: cid, role: e?.role });
        }
      }
      if (m.staff?.nodes && m.staff?.edges) {
        for (let i=0;i<m.staff.nodes.length;i++) {
          const n = m.staff.nodes[i]; const e = m.staff.edges[i];
          const aid = authorMap.get(n.id); if (aid) manga_authors.push({ manga_id: mediaId, author_id: aid, role: e?.role });
          const sid = staffMap.get(n.id); if (sid) manga_staff.push({ manga_id: mediaId, staff_id: sid, role: e?.role });
        }
      }
    }
  }

  function dedupeByKeys(rows, keys) {
    const seen = new Set();
    const out = [];
    for (const r of rows) {
      const k = keys.map(k => r[k]).join('|');
      if (!seen.has(k)) { seen.add(k); out.push(r); }
    }
    return out;
  }
  const asRows = isAnime ? dedupeByKeys(anime_studios, ['anime_id','studio_id']) : dedupeByKeys(manga_authors, ['manga_id','author_id']);
  const atRows = isAnime ? dedupeByKeys(anime_tags, ['anime_id','tag_id']) : dedupeByKeys(manga_tags, ['manga_id','tag_id']);
  const acRows = isAnime ? dedupeByKeys(anime_characters, ['anime_id','character_id']) : dedupeByKeys(manga_characters, ['manga_id','character_id']);
  const astRows = isAnime ? dedupeByKeys(anime_staff, ['anime_id','staff_id']) : dedupeByKeys(manga_staff, ['manga_id','staff_id']);

  await upsertBulk(isAnime ? 'anime_studios' : 'manga_authors', asRows, isAnime ? 'anime_id,studio_id' : 'manga_id,author_id');
  await upsertBulk(isAnime ? 'anime_tags' : 'manga_tags', atRows, isAnime ? 'anime_id,tag_id' : 'manga_id,tag_id');
  await upsertBulk(isAnime ? 'anime_characters' : 'manga_characters', acRows, isAnime ? 'anime_id,character_id' : 'manga_id,character_id');
  await upsertBulk(isAnime ? 'anime_staff' : 'manga_staff', astRows, isAnime ? 'anime_id,staff_id' : 'manga_id,staff_id');

  // Episodes / Chapters / Volumes
  if (isAnime) {
    const epDeletes = []; const epRows = [];
    const seenStreamUrls = new Set();
    for (const m of media) {
      const id = mediaIdMap.get(m.id); if (!id) continue;
      const eps = m.streamingEpisodes || [];
      const uniqueEps = [];
      for (let i=0;i<eps.length;i++) {
        const ep = eps[i];
        const url = ep.url || null;
        if (url) {
          const key = `${id}-${url}`;
          if (seenStreamUrls.has(key)) continue;
          seenStreamUrls.add(key);
        }
        uniqueEps.push({ ep, index: i });
      }
      if (uniqueEps.length > 0) epDeletes.push(id);
      for (const { ep, index } of uniqueEps) {
        const match = ep.title?.match(/Episode\s+(\d+)/i);
        const number = match ? parseInt(match[1]) : (index + 1);
        epRows.push({
          anime_id: id,
          number,
          title: ep.title,
          thumbnail: ep.thumbnail,
          duration: m.duration || null,
          stream_url: ep.url || null,
          stream_site: ep.site || null
        });
      }
    }
    if (epDeletes.length) { await supabase.from('episodes').delete().in('anime_id', epDeletes); }
    if (epRows.length) await upsertBulk('episodes', epRows);
  } else {
    const cDeletes = []; const cRows = []; const vDeletes = []; const vRows = [];
    for (const m of media) {
      const id = mediaIdMap.get(m.id); if (!id) continue;
      if (m.chapters && m.chapters > 0) { cDeletes.push(id); for (let i=0;i<m.chapters;i++) cRows.push({ manga_id: id, number: i+1, title: `Chapter ${i+1}` }); }
      if (m.volumes && m.volumes > 0) { vDeletes.push(id); for (let i=0;i<m.volumes;i++) vRows.push({ manga_id: id, number: i+1, title: `Volume ${i+1}` }); }
    }
    if (cDeletes.length) await supabase.from('chapters').delete().in('manga_id', cDeletes);
    if (vDeletes.length) await supabase.from('volumes').delete().in('manga_id', vDeletes);
    if (cRows.length) await upsertBulk('chapters', cRows);
    if (vRows.length) await upsertBulk('volumes', vRows);
  }

  if (externalLinkRows.length) {
    const dedupedLinks = dedupeByKeys(externalLinkRows, ['media_type','media_id','url']);
    await upsertBulk('external_links', dedupedLinks, 'media_type,media_id,url');
  }

  return { page, processed: media.length };
}

async function main() {
  const kind = (process.argv[2] || 'ANIME').toUpperCase();
  const startPage = parseInt(process.argv[3] || '1', 10);
  const endPage = parseInt(process.argv[4] || String(startPage), 10);
  const concurrency = parseInt(process.argv[5] || '3', 10);
  console.log(`Fast import ${kind} pages ${startPage}..${endPage} (concurrency=${concurrency})`);

  let running = 0; let cursor = startPage; let completed = 0;
  const inFlight = new Set();
  async function launch(p) {
    running++; const pr = processPage(kind, p).then(r => { running--; completed++; console.log(`✓ page ${r.page} (${r.processed})`); inFlight.delete(pr); }).catch(e => { running--; console.error(`✗ page ${p}`, e.message || e); inFlight.delete(pr); });
    inFlight.add(pr);
  }

  while (cursor <= endPage || running > 0) {
    while (running < concurrency && cursor <= endPage) { await launch(cursor++); }
    await sleep(PAGE_DELAY_MS);
  }
  console.log(`Done. Completed ${completed} pages.`);
}

main().catch(e => { console.error(e); process.exit(1); });
