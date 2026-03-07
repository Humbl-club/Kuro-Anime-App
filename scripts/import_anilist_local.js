/*
  Local AniList → Supabase importer (ANIME/MANGA)
  - Uses service role key to upsert into Postgres directly
  - Fetches AniList pages (perPage=50) sorted by POPULARITY_DESC
  - For ANIME: upserts anime; streaming episodes; studios; tags; characters; staff
  - For MANGA: upserts manga; placeholder chapters/volumes from counts; authors (from staff nodes); tags; characters; staff
  WARNING: Full backfill across all pages can take many hours due to API rate limits.
*/

const { createClient } = require('@supabase/supabase-js');
const { getProjectUrl } = require('./lib/project_config');

const SUPABASE_URL = getProjectUrl();
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY env var.');
}
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

const ANILIST_API = 'https://graphql.anilist.co';
const DELAY_BETWEEN_PAGES_MS = 700; // rate limit friendly

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
          ${isAnime ? 'episodes duration season seasonYear nextAiringEpisode { episode airingAt timeUntilAiring }' : 'chapters volumes'}
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
  const res = await fetch(ANILIST_API, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ query, variables: { page } }),
  });
  if (!res.ok) throw new Error(`AniList HTTP ${res.status}`);
  const data = await res.json();
  const p = data?.data?.Page;
  return { list: p?.media ?? [], pageInfo: p?.pageInfo ?? {} };
}

async function upsertAnime(item) {
  const animeData = {
    anilist_id: item.id,
    mal_id: item.idMal,
    title_english: item.title?.english,
    title_romaji: item.title?.romaji,
    title_native: item.title?.native,
    title_synonyms: item.synonyms,
    cover_image_large: item.coverImage?.large,
    cover_image_medium: item.coverImage?.medium,
    cover_image_color: item.coverImage?.color,
    banner_image: item.bannerImage,
    format: item.format,
    status: item.status,
    description: item.description,
    episodes: item.episodes,
    duration: item.duration,
    total_duration: item.episodes && item.duration ? item.episodes * item.duration : null,
    season: item.season,
    season_year: item.seasonYear,
    next_episode_number: item.nextAiringEpisode?.episode ?? null,
    next_airing_at: item.nextAiringEpisode?.airingAt ? new Date(item.nextAiringEpisode.airingAt * 1000).toISOString() : null,
    start_date_year: item.startDate?.year,
    start_date_month: item.startDate?.month,
    start_date_day: item.startDate?.day,
    end_date_year: item.endDate?.year,
    end_date_month: item.endDate?.month,
    end_date_day: item.endDate?.day,
    average_score: item.averageScore,
    mean_score: item.meanScore,
    popularity: item.popularity,
    trending: item.trending,
    favourites: item.favourites,
    genres: item.genres,
    source: item.source,
    country_of_origin: item.countryOfOrigin,
    is_adult: item.isAdult,
    site_url: item.siteUrl,
    updated_at_anilist: item.updatedAt ? new Date(item.updatedAt * 1000).toISOString() : null,
    last_synced_at: new Date().toISOString(),
  };
  let { data, error } = await supabase.from('anime').upsert(animeData, { onConflict: 'anilist_id' }).select('id').single();
  if (error && /anime_mal_id_key/.test(error.message || '')) {
    const retry = { ...animeData, mal_id: null };
    ({ data, error } = await supabase.from('anime').upsert(retry, { onConflict: 'anilist_id' }).select('id').single());
  }
  if (error) throw error;
  const animeId = data.id;

  // Episodes from streamingEpisodes (if any)
  if (item.streamingEpisodes && item.streamingEpisodes.length > 0) {
    await supabase.from('episodes').delete().eq('anime_id', animeId);
    const seenUrls = new Set();
    const rows = [];
    item.streamingEpisodes.forEach((ep, idx) => {
      if (ep.url) {
        const key = ep.url;
        if (seenUrls.has(key)) return;
        seenUrls.add(key);
      }
      const match = ep.title?.match(/Episode\s+(\d+)/i);
      const number = match ? parseInt(match[1]) : (idx + 1);
      rows.push({
        anime_id: animeId,
        number,
        title: ep.title,
        thumbnail: ep.thumbnail,
        duration: item.duration || null,
        stream_url: ep.url || null,
        stream_site: ep.site || null
      });
    });
    if (rows.length) await supabase.from('episodes').insert(rows);
  }

  // Studios
  if (item.studios?.nodes) {
    for (const studio of item.studios.nodes) {
      const { data: st } = await supabase
        .from('studios')
        .upsert({ anilist_id: studio.id, name: studio.name, is_animation_studio: studio.isAnimationStudio, site_url: studio.siteUrl, favourites: studio.favourites }, { onConflict: 'anilist_id' })
        .select('id').single();
      if (st) await supabase.from('anime_studios').upsert({ anime_id: animeId, studio_id: st.id });
    }
  }

  // Tags
  if (item.tags) {
    for (const tag of item.tags) {
      const { data: tg } = await supabase
        .from('tags')
        .upsert({ anilist_id: tag.id, name: tag.name, description: tag.description, category: tag.category, is_general_spoiler: tag.isGeneralSpoiler, is_media_spoiler: tag.isMediaSpoiler, is_adult: tag.isAdult }, { onConflict: 'anilist_id' })
        .select('id').single();
      if (tg) await supabase.from('anime_tags').upsert({ anime_id: animeId, tag_id: tg.id, rank: tag.rank ?? 0 });
    }
  }

  // Characters
  if (item.characters?.nodes && item.characters?.edges) {
    for (let i = 0; i < item.characters.nodes.length; i++) {
      const char = item.characters.nodes[i];
      const edge = item.characters.edges[i];
      const { data: ch } = await supabase
        .from('characters')
        .upsert({ anilist_id: char.id, name_full: char.name?.full, name_native: char.name?.native, image_large: char.image?.large, description: char.description, gender: char.gender, age: char.age }, { onConflict: 'anilist_id' })
        .select('id').single();
      if (ch) await supabase.from('anime_characters').upsert({ anime_id: animeId, character_id: ch.id, role: edge?.role });
    }
  }

  // Staff
  if (item.staff?.nodes && item.staff?.edges) {
    for (let i = 0; i < item.staff.nodes.length; i++) {
      const person = item.staff.nodes[i];
      const edge = item.staff.edges[i];
      const { data: stf } = await supabase
        .from('staff')
        .upsert({ anilist_id: person.id, name_full: person.name?.full, name_native: person.name?.native, image_large: person.image?.large, description: person.description, primary_occupations: person.primaryOccupations }, { onConflict: 'anilist_id' })
        .select('id').single();
      if (stf) await supabase.from('anime_staff').upsert({ anime_id: animeId, staff_id: stf.id, role: edge?.role });
    }
  }

  const streamingLinks = (item.externalLinks || []).filter(link => isStreamingLink(true, link));
  if (streamingLinks.length) {
    const seen = new Set();
    const rows = [];
    streamingLinks.forEach((link, idx) => {
      if (!link.url) return;
      if (seen.has(link.url)) return;
      seen.add(link.url);
      rows.push({
        media_type: 'ANIME',
        media_id: animeId,
        site: link.site || null,
        url: link.url,
        language: link.language || null,
        color: link.color || null,
        priority: idx + 1,
        is_disabled: !!link.isDisabled
      });
    });
    if (rows.length) {
      await supabase.from('external_links').upsert(rows, { onConflict: 'media_type,media_id,url' });
    }
  }
}

async function upsertManga(item) {
  const mangaData = {
    anilist_id: item.id,
    mal_id: item.idMal,
    title_english: item.title?.english,
    title_romaji: item.title?.romaji,
    title_native: item.title?.native,
    title_synonyms: item.synonyms,
    cover_image_large: item.coverImage?.large,
    cover_image_medium: item.coverImage?.medium,
    cover_image_color: item.coverImage?.color,
    banner_image: item.bannerImage,
    format: item.format,
    status: item.status,
    description: item.description,
    chapters: item.chapters,
    volumes: item.volumes,
    next_chapter_number: null,
    next_chapter_at: null,
    start_date_year: item.startDate?.year,
    start_date_month: item.startDate?.month,
    start_date_day: item.startDate?.day,
    end_date_year: item.endDate?.year,
    end_date_month: item.endDate?.month,
    end_date_day: item.endDate?.day,
    average_score: item.averageScore,
    mean_score: item.meanScore,
    popularity: item.popularity,
    trending: item.trending,
    favourites: item.favourites,
    genres: item.genres,
    source: item.source,
    country_of_origin: item.countryOfOrigin,
    is_adult: item.isAdult,
    site_url: item.siteUrl,
    updated_at_anilist: item.updatedAt ? new Date(item.updatedAt * 1000).toISOString() : null,
    last_synced_at: new Date().toISOString(),
  };
  let { data, error } = await supabase.from('manga').upsert(mangaData, { onConflict: 'anilist_id' }).select('id').single();
  if (error && /manga_mal_id_key/.test(error.message || '')) {
    const retry = { ...mangaData, mal_id: null };
    ({ data, error } = await supabase.from('manga').upsert(retry, { onConflict: 'anilist_id' }).select('id').single());
  }
  if (error) throw error;
  const mangaId = data.id;

  // Chapters
  if (item.chapters && item.chapters > 0) {
    await supabase.from('chapters').delete().eq('manga_id', mangaId);
    const rows = Array.from({ length: item.chapters }, (_, i) => ({ manga_id: mangaId, number: i + 1, title: `Chapter ${i + 1}` }));
    if (rows.length > 0) await supabase.from('chapters').insert(rows);
  }

  // Volumes
  if (item.volumes && item.volumes > 0) {
    await supabase.from('volumes').delete().eq('manga_id', mangaId);
    const rows = Array.from({ length: item.volumes }, (_, i) => ({ manga_id: mangaId, number: i + 1, title: `Volume ${i + 1}` }));
    if (rows.length > 0) await supabase.from('volumes').insert(rows);
  }

  // Authors (from staff nodes)
  if (item.staff?.nodes && item.staff?.edges) {
    for (let i = 0; i < item.staff.nodes.length; i++) {
      const person = item.staff.nodes[i];
      const edge = item.staff.edges[i];
      const { data: au } = await supabase
        .from('authors')
        .upsert({ anilist_id: person.id, name_full: person.name?.full, name_native: person.name?.native, image_large: person.image?.large, description: person.description, primary_occupations: person.primaryOccupations }, { onConflict: 'anilist_id' })
        .select('id').single();
      if (au) await supabase.from('manga_authors').upsert({ manga_id: mangaId, author_id: au.id, role: edge?.role });
    }
  }

  // Tags
  if (item.tags) {
    for (const tag of item.tags) {
      const { data: tg } = await supabase
        .from('tags')
        .upsert({ anilist_id: tag.id, name: tag.name, description: tag.description, category: tag.category, is_general_spoiler: tag.isGeneralSpoiler, is_media_spoiler: tag.isMediaSpoiler, is_adult: tag.isAdult }, { onConflict: 'anilist_id' })
        .select('id').single();
      if (tg) await supabase.from('manga_tags').upsert({ manga_id: mangaId, tag_id: tg.id, rank: tag.rank ?? 0 });
    }
  }

  // Characters
  if (item.characters?.nodes && item.characters?.edges) {
    for (let i = 0; i < item.characters.nodes.length; i++) {
      const char = item.characters.nodes[i];
      const edge = item.characters.edges[i];
      const { data: ch } = await supabase
        .from('characters')
        .upsert({ anilist_id: char.id, name_full: char.name?.full, name_native: char.name?.native, image_large: char.image?.large, description: char.description, gender: char.gender, age: char.age }, { onConflict: 'anilist_id' })
        .select('id').single();
      if (ch) await supabase.from('manga_characters').upsert({ manga_id: mangaId, character_id: ch.id, role: edge?.role });
    }
  }

  // Staff
  if (item.staff?.nodes && item.staff?.edges) {
    for (let i = 0; i < item.staff.nodes.length; i++) {
      const person = item.staff.nodes[i];
      const edge = item.staff.edges[i];
      const { data: stf } = await supabase
        .from('staff')
        .upsert({ anilist_id: person.id, name_full: person.name?.full, name_native: person.name?.native, image_large: person.image?.large, description: person.description, primary_occupations: person.primaryOccupations }, { onConflict: 'anilist_id' })
        .select('id').single();
      if (stf) await supabase.from('manga_staff').upsert({ manga_id: mangaId, staff_id: stf.id, role: edge?.role });
    }
  }

  const readerLinks = (item.externalLinks || []).filter(link => isStreamingLink(false, link));
  if (readerLinks.length) {
    const seen = new Set();
    const rows = [];
    readerLinks.forEach((link, idx) => {
      if (!link.url) return;
      if (seen.has(link.url)) return;
      seen.add(link.url);
      rows.push({
        media_type: 'MANGA',
        media_id: mangaId,
        site: link.site || null,
        url: link.url,
        language: link.language || null,
        color: link.color || null,
        priority: idx + 1,
        is_disabled: !!link.isDisabled
      });
    });
    if (rows.length) {
      await supabase.from('external_links').upsert(rows, { onConflict: 'media_type,media_id,url' });
    }
  }
}

async function inferStartPageFromCount(kind) {
  const table = kind === 'ANIME' ? 'anime' : 'manga';
  const { count } = await supabase.from(table).select('*', { count: 'exact', head: true });
  const pages = count ? Math.floor(count / 50) : 0;
  return Math.max(1, pages + 1);
}

async function main() {
  const kind = (process.argv[2] || 'ANIME').toUpperCase();
  if (!['ANIME','MANGA'].includes(kind)) throw new Error('Usage: node scripts/import_anilist_local.js ANIME|MANGA [startPage] [endPage]');
  const argStart = process.argv[3] ? parseInt(process.argv[3], 10) : null;
  const argEnd = process.argv[4] ? parseInt(process.argv[4], 10) : null;
  const startPage = argStart || await inferStartPageFromCount(kind);
  const endPage = argEnd || (startPage + 9); // default 10 pages per run
  console.log(`Importing ${kind} pages ${startPage}..${endPage}`);

  let processed = 0;
  for (let p = startPage; p <= endPage; p++) {
    console.log(`\nFetching page ${p}…`);
    const { list, pageInfo } = await fetchPage(kind, p);
    if (!list || list.length === 0) { console.log('No more results.'); break; }
    for (const item of list) {
      try {
        if (kind === 'ANIME') await upsertAnime(item);
        else await upsertManga(item);
        processed++;
      } catch (e) {
        console.error('Upsert error:', e?.message || e);
      }
    }
    console.log(`Done page ${p}. hasNextPage=${pageInfo?.hasNextPage}`);
    await sleep(DELAY_BETWEEN_PAGES_MS);
  }
  console.log(`\nImported ${processed} ${kind} records (plus relationships).`);
}

main().catch(e => { console.error(e); process.exit(1); });
