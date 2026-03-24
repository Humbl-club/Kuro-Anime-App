// Deployed from local patch of scripts/legacy/06_anime_edge_function_with_episodes.js
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const ANILIST_API = 'https://graphql.anilist.co';
const DEFAULT_DELAY_MS = 670; // ms
const DEFAULT_PER_PAGE = 25;
const DEFAULT_RETRIES = 3;
const ITEM_BATCH_SIZE = 5;
const SUPPORTED_MEDIA_RELATIONS = new Set(['SOURCE', 'ADAPTATION', 'PREQUEL', 'SEQUEL', 'SIDE_STORY', 'SPIN_OFF']);
type TrackPresetName = 'popularity_core' | 'airing_or_releasing' | 'recent_updates' | 'catalog_backfill';

type TrackPresetDefaults = {
  useCursor: boolean;
  runToEnd: boolean;
  lightweight: boolean;
  includeRelations: boolean;
  includeEpisodes: boolean;
  pagesPerBatch: number;
  maxPagesPerRun: number;
  perPage: number;
  delayMs: number;
  scheduleSafe: boolean;
};

function normalizeTrackPreset(raw: unknown): TrackPresetName {
  const value = String(raw ?? '').trim().toLowerCase();
  if (value === 'popularity_core' || value === 'airing_or_releasing' || value === 'recent_updates' || value === 'catalog_backfill') {
    return value;
  }
  return 'catalog_backfill';
}

function trackKeyFor(mediaType: string, preset: TrackPresetName): string {
  return `${mediaType.toLowerCase()}:${preset}`;
}

function trackPresetDefaults(preset: TrackPresetName): TrackPresetDefaults {
  switch (preset) {
    case 'popularity_core':
      return {
        useCursor: true,
        runToEnd: false,
        lightweight: true,
        includeRelations: false,
        includeEpisodes: false,
        pagesPerBatch: 2,
        maxPagesPerRun: 4,
        perPage: 25,
        delayMs: 0,
        scheduleSafe: true,
      };
    case 'airing_or_releasing':
      return {
        useCursor: true,
        runToEnd: false,
        lightweight: false,
        includeRelations: true,
        includeEpisodes: true,
        pagesPerBatch: 1,
        maxPagesPerRun: 6,
        perPage: 20,
        delayMs: 120,
        scheduleSafe: true,
      };
    case 'recent_updates':
      return {
        useCursor: true,
        runToEnd: false,
        lightweight: false,
        includeRelations: true,
        includeEpisodes: false,
        pagesPerBatch: 2,
        maxPagesPerRun: 8,
        perPage: 25,
        delayMs: 100,
        scheduleSafe: true,
      };
    case 'catalog_backfill':
    default:
      return {
        useCursor: true,
        runToEnd: true,
        lightweight: false,
        includeRelations: true,
        includeEpisodes: true,
        pagesPerBatch: 10,
        maxPagesPerRun: 200,
        perPage: 25,
        delayMs: 250,
        scheduleSafe: false,
      };
  }
}

serve(async (req) => {
  // Secret header auth: pg_cron/pg_net can't send JWTs, so verify a shared secret instead.
  const IMPORT_SECRET = Deno.env.get("IMPORT_SECRET");
  if (!IMPORT_SECRET) {
    return new Response(JSON.stringify({ error: "Server misconfigured" }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
  const authHeader = req.headers.get("x-import-secret");
  if (authHeader !== IMPORT_SECRET) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: { "Content-Type": "application/json" } });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const supabase = createClient(supabaseUrl, supabaseKey);
  const payload = await req.json().catch(() => ({} as any));
  const requestedTrackKey = String(payload?.trackKey ?? '').trim();
  const hasTrackRouting = Boolean(requestedTrackKey || payload?.trackPreset);
  const trackPreset = normalizeTrackPreset(payload?.trackPreset);
  const resolvedTrackKey = hasTrackRouting ? (requestedTrackKey || trackKeyFor('ANIME', trackPreset)) : '';
  const trackDefaults = hasTrackRouting ? trackPresetDefaults(trackPreset) : null;
  // NOTE: For cursor-driven schedules, omit startPage (or set it to 0) to advance from import_state / import_track_state.
  let startPage: number = payload?.startPage ?? 0;
  let pagesPerBatch: number = payload?.pagesPerBatch ?? (trackDefaults?.pagesPerBatch ?? 5);
  const useCursor: boolean = payload?.useCursor ?? (trackDefaults?.useCursor ?? false); // default off per request
  let runToEnd: boolean = payload?.runToEnd ?? (trackDefaults?.runToEnd ?? false);    // continuous until no more pages or time budget
  let maxPagesPerRun: number = payload?.maxPagesPerRun ?? (trackDefaults?.maxPagesPerRun ?? 200); // safety cap
  let perPage: number = payload?.perPage ?? (trackDefaults?.perPage ?? DEFAULT_PER_PAGE);
  let delayMs: number = payload?.delayMs ?? (trackDefaults?.delayMs ?? DEFAULT_DELAY_MS);
  const retries: number = payload?.retries ?? DEFAULT_RETRIES;
  const lightweight: boolean = payload?.lightweight ?? (trackDefaults?.lightweight ?? false);
  const includeRelations: boolean = payload?.includeRelations ?? (trackDefaults?.includeRelations ?? !lightweight);
  const includeEpisodes: boolean = payload?.includeEpisodes ?? (trackDefaults?.includeEpisodes ?? !lightweight);
  const forceRefresh: boolean = payload?.forceRefresh ?? false;
  const lockTtlSeconds: number = payload?.lockTtlSeconds ?? 1800;
  const scheduleSafe: boolean = payload?.scheduleSafe ?? false;

  // Guard rails: avoid schedules timing out and leaving locks behind.
  // Full backfills should be orchestrated from a client (see scripts/run_full_import.js),
  // while scheduled runs should be small + cursor-driven.
  if (scheduleSafe && !lightweight) {
    perPage = Math.max(1, Math.min(perPage, 10));
    pagesPerBatch = Math.max(1, Math.min(pagesPerBatch, 2));
    maxPagesPerRun = Math.max(1, Math.min(maxPagesPerRun, 10));
    if (runToEnd) runToEnd = false;
    delayMs = Math.max(0, Math.min(delayMs, 250));
  }
  if (useCursor && startPage < 1 && resolvedTrackKey) {
    const trackedLastPage = await readTrackedCursorPage(supabase, resolvedTrackKey);
    if (trackedLastPage !== null) {
      startPage = trackedLastPage + 1;
    }
  }
  if (useCursor && startPage < 1) {
    const { data } = await supabase.from('import_state').select('last_page').eq('media_type', 'ANIME').maybeSingle();
    const last = data?.last_page ?? 0;
    startPage = last + 1;
  }
  if (startPage < 1) startPage = 1;

  const results = { anime: 0, episodes: 0, characters: 0, studios: 0, staff: 0, tags: 0, relationships: 0, errors: 0 };
  const runType = lightweight ? 'core' : 'heavy';
  const heavyImportsEnabled = parseBooleanEnv(Deno.env.get("IMPORT_HEAVY_ENABLED"), true);
  const tRunStart = Date.now();
  let runId: number | null = await startImportRun(supabase, 'ANIME', runType, payload);
  let lockAcquired = false;

  if (!lightweight && !heavyImportsEnabled) {
    if (useCursor) {
      await writeTrackedCursorState(supabase, {
        mediaType: 'ANIME',
        trackKey: resolvedTrackKey || null,
        trackPreset,
        lastPage: Math.max(0, startPage - 1),
        status: 'skipped',
        visibility: 'paused',
        results,
        message: 'heavy_disabled',
      });
    }
    await finishImportRun(supabase, runId, 'skipped', results, 'heavy_disabled', tRunStart);
    return new Response(
      JSON.stringify({ success: true, skipped: true, reason: 'heavy_disabled', results }),
      { headers: { 'Content-Type': 'application/json' } },
    );
  }

  try {
    lockAcquired = await acquireImportLock(supabase, 'anime', lockTtlSeconds);
    if (!lockAcquired) {
      if (useCursor) {
        await writeTrackedCursorState(supabase, {
          mediaType: 'ANIME',
          trackKey: resolvedTrackKey || null,
          trackPreset,
          lastPage: Math.max(0, startPage - 1),
          status: 'skipped',
          visibility: 'paused',
          results,
          message: 'locked',
        });
      }
      await finishImportRun(supabase, runId, 'skipped', results, 'locked', tRunStart);
      return new Response(JSON.stringify({ success: true, skipped: true, reason: 'locked', results }), { headers: { 'Content-Type': 'application/json' } });
    }
    let lastProcessed = startPage - 1;
    const timeBudgetMs = payload?.timeBudgetMs ?? 55_000; // typical function budget safety
    const t0 = Date.now();
    let processedPages = 0;
    let page = startPage;
    const step = Math.max(1, pagesPerBatch);
    outer: while (true) {
      for (let p = page; p < page + step; p++) {
        const anime = await fetchAniListAnimeData(p, perPage, includeRelations, includeEpisodes, retries);
        if (!anime.length) {
          // Cursor wrap-around: if we hit the end, reset so the next run starts from page 1.
          lastProcessed = (useCursor && p === startPage) ? 0 : (p - 1);
          break outer;
        }
        for (let bi = 0; bi < anime.length; bi += ITEM_BATCH_SIZE) {
          const chunk = anime.slice(bi, bi + ITEM_BATCH_SIZE);
          await Promise.all(chunk.map(async (item: any) => {
            try { await processAnimeItem(supabase, item, results, includeRelations, includeEpisodes, forceRefresh); } catch (e) { console.error(e); results.errors++; }
          }));
        }
        lastProcessed = p; processedPages++;
        await sleep(delayMs);
        if (!runToEnd && processedPages >= pagesPerBatch) break outer;
        if (runToEnd && (processedPages >= maxPagesPerRun || (Date.now() - t0) > timeBudgetMs)) break outer;
      }
      page += step;
    }
    if (useCursor) {
      await writeTrackedCursorState(supabase, {
        mediaType: 'ANIME',
        trackKey: resolvedTrackKey || null,
        trackPreset,
        lastPage: lastProcessed,
        status: 'success',
        visibility: 'active',
        results,
        message: null,
      });
    }
    await finishImportRun(supabase, runId, 'success', results, null, tRunStart);
    return new Response(JSON.stringify({ success: true, results, nextStartPage: (lastProcessed + 1), trackKey: hasTrackRouting ? resolvedTrackKey : null, trackPreset: hasTrackRouting ? trackPreset : null }), { headers: { 'Content-Type': 'application/json' } });
  } catch (e) {
    if (useCursor) {
      await writeTrackedCursorState(supabase, {
        mediaType: 'ANIME',
        trackKey: resolvedTrackKey || null,
        trackPreset,
        lastPage: Math.max(0, startPage - 1),
        status: 'error',
        visibility: 'paused',
        results,
        message: (e as Error).message,
      });
    }
    await finishImportRun(supabase, runId, 'error', results, (e as Error).message, tRunStart);
    return new Response(JSON.stringify({ success: false, error: (e as Error).message }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  } finally {
    if (lockAcquired) {
      await releaseImportLock(supabase, 'anime');
    }
  }
});

async function fetchAniListAnimeData(page: number, perPage: number, includeRelations: boolean, includeEpisodes: boolean, retries: number) {
  const episodesFragment = includeEpisodes ? `streamingEpisodes { title thumbnail url site }` : ``;
  const externalLinksFragment = `
          externalLinks { site url language color }`;
  const relationsFragment = includeRelations ? `
          relations {
            edges {
              relationType(version: 2)
              node { id type format title { romaji english native userPreferred } coverImage { large } }
            }
          }
          studios { nodes { id name isAnimationStudio siteUrl favourites } }
          tags { id name description category rank isGeneralSpoiler isMediaSpoiler isAdult }
          # Keep character ingestion intentionally compact: AniList ROLE sort puts mains first.
          characters(sort: ROLE, perPage: 10) { edges { role } nodes { id name { full native } image { large } description gender age } }
          staff(sort: RELEVANCE, perPage: 10) { edges { role } nodes { id name { full native } image { large } description primaryOccupations } }
  ` : ``;
  const query = `
    query ($page: Int, $perPage: Int) {
      Page(page: $page, perPage: $perPage) {
        media(sort: POPULARITY_DESC, type: ANIME) {
          id idMal
          title { romaji english native userPreferred }
          synonyms hashtag
          coverImage { extraLarge large medium color }
          bannerImage
          type format status
          description(asHtml: false)
          source countryOfOrigin isAdult
          startDate { year month day }
          endDate { year month day }
          episodes duration
          season seasonYear
          nextAiringEpisode { episode airingAt timeUntilAiring }
          averageScore meanScore popularity trending favourites
          genres
          siteUrl updatedAt
          ${episodesFragment}
          ${externalLinksFragment}
          ${relationsFragment}
        }
      }
    }
  `;
  const data = await fetchJsonWithRetry(query, { page, perPage }, retries);
  return data?.data?.Page?.media ?? [];
}

async function processAnimeItem(supabase: any, anime: any, results: any, includeRelations: boolean, includeEpisodes: boolean, forceRefresh: boolean) {
  const updatedAtAnilist = anime.updatedAt ? new Date(anime.updatedAt * 1000).toISOString() : null;
  const derivedEpisodes =
    anime.episodes ??
    (anime.nextAiringEpisode?.episode && anime.nextAiringEpisode.episode > 1
      ? Math.max(0, Number(anime.nextAiringEpisode.episode) - 1)
      : null);

  const { data: existing, error: existingError } = await supabase
    .from('anime')
    .select('id, updated_at_anilist, episodes, duration')
    .eq('anilist_id', anime.id)
    .maybeSingle();
  if (existingError) {
    console.error('Existing anime lookup failed:', existingError);
  }
  const isStale = forceRefresh || !existing || !existing.updated_at_anilist || (updatedAtAnilist && existing.updated_at_anilist !== updatedAtAnilist);
  if (existing && !isStale) {
    // Even when the AniList payload hasn't changed, airing metadata can drift (next episode),
    // and long-running shows may be missing a total episode count. Keep these fields fresh.
    const patch: any = {
      last_synced_at: new Date().toISOString(),
      next_episode_number: anime.nextAiringEpisode?.episode ?? null,
      next_airing_at: anime.nextAiringEpisode?.airingAt ? new Date(anime.nextAiringEpisode.airingAt * 1000).toISOString() : null,
    };
    if (derivedEpisodes && (!existing.episodes || Number(existing.episodes) < derivedEpisodes)) {
      patch.episodes = derivedEpisodes;
      const dur = anime.duration ?? existing.duration;
      patch.total_duration = dur ? derivedEpisodes * dur : null;
    }
    await supabase.from('anime').update(patch).eq('id', existing.id);
    return;
  }

  const animeData = {
    anilist_id: anime.id,
    mal_id: anime.idMal,
    title_english: anime.title?.english,
    title_romaji: anime.title?.romaji,
    title_native: anime.title?.native,
    title_synonyms: anime.synonyms,
    cover_image_large: anime.coverImage?.large,
    cover_image_medium: anime.coverImage?.medium,
    cover_image_color: anime.coverImage?.color,
    banner_image: anime.bannerImage,
    format: anime.format,
    status: anime.status,
    description: anime.description,
    // AniList sometimes leaves `episodes` null for long-running RELEASING shows.
    // For UX (and for our card metadata), derive a best-effort "episodes so far" from
    // `nextAiringEpisode.episode - 1` when available.
    episodes: derivedEpisodes,
    duration: anime.duration,
    total_duration: derivedEpisodes && anime.duration ? derivedEpisodes * anime.duration : null,
    season: anime.season,
    season_year: anime.seasonYear,
    next_episode_number: anime.nextAiringEpisode?.episode,
    next_airing_at: anime.nextAiringEpisode?.airingAt ? new Date(anime.nextAiringEpisode.airingAt * 1000).toISOString() : null,
    start_date_year: anime.startDate?.year,
    start_date_month: anime.startDate?.month,
    start_date_day: anime.startDate?.day,
    end_date_year: anime.endDate?.year,
    end_date_month: anime.endDate?.month,
    end_date_day: anime.endDate?.day,
    average_score: anime.averageScore,
    mean_score: anime.meanScore,
    popularity: anime.popularity,
    trending: anime.trending,
    favourites: anime.favourites,
    genres: anime.genres,
    source: anime.source,
    country_of_origin: anime.countryOfOrigin,
    is_adult: anime.isAdult,
    site_url: anime.siteUrl,
    synopsis_enhanced_state: 'pending',
    updated_at_anilist: updatedAtAnilist,
    last_synced_at: new Date().toISOString()
  };
  const { data: insertedAnime, error: animeError } = await supabase.from('anime').upsert(animeData, { onConflict: 'anilist_id' }).select('id').single();
  if (animeError) throw animeError; results.anime++;

  // External links (watch on...) from AniList externalLinks
  if (Array.isArray(anime.externalLinks) && anime.externalLinks.length > 0) {
    for (const link of anime.externalLinks) {
      const url = link?.url;
      if (!url || typeof url !== 'string' || !url.startsWith('http')) continue;
      const payload = {
        media_type: 'ANIME',
        media_id: insertedAnime.id,
        site: link?.site ?? null,
        url,
        language: link?.language ?? null,
        color: link?.color ?? null,
        is_disabled: false,
      };
      const { error } = await supabase.from('external_links').upsert(payload, { onConflict: 'media_type,media_id,url' });
      if (error) {
        // Do not fail the import over external link issues.
        console.error('external_links upsert error:', error);
      }
    }
  }

  if (includeEpisodes && anime.streamingEpisodes && anime.streamingEpisodes.length > 0) {
    await supabase.from('episodes').delete().eq('anime_id', insertedAnime.id);
    for (let i = 0; i < anime.streamingEpisodes.length; i++) {
      const ep = anime.streamingEpisodes[i];
      const match = ep.title?.match(/Episode\s+(\d+)/i);
      const number = match ? parseInt(match[1]) : (i + 1);
      const episodeData = {
        anime_id: insertedAnime.id,
        number,
        title: ep.title,
        thumbnail: ep.thumbnail,
        duration: anime.duration || null,
        stream_url: ep.url ?? null,
        stream_site: ep.site ?? null,
      };
      const { error: e } = await supabase.from('episodes').insert(episodeData);
      if (!e) results.episodes++;
    }
  }
  // Studios
  if (includeRelations && anime.studios?.nodes) {
    for (const studio of anime.studios.nodes) {
      const { data: st, error: e } = await supabase
        .from('studios')
        .upsert({ anilist_id: studio.id, name: studio.name, is_animation_studio: studio.isAnimationStudio, site_url: studio.siteUrl, favourites: studio.favourites }, { onConflict: 'anilist_id' })
        .select('id')
        .single();
      if (!e && st) {
        await supabase.from('anime_studios').upsert({ anime_id: insertedAnime.id, studio_id: st.id });
        results.relationships++; results.studios++;
      }
    }
  }
  // Tags
  if (includeRelations && anime.tags) {
    for (const tag of anime.tags) {
      const { data: tg, error: e } = await supabase
        .from('tags')
        .upsert({ anilist_id: tag.id, name: tag.name, description: tag.description, category: tag.category, is_general_spoiler: tag.isGeneralSpoiler, is_media_spoiler: tag.isMediaSpoiler, is_adult: tag.isAdult }, { onConflict: 'anilist_id' })
        .select('id')
        .single();
      if (!e && tg) {
        await supabase.from('anime_tags').upsert({ anime_id: insertedAnime.id, tag_id: tg.id, rank: tag.rank ?? 0 });
        results.relationships++; results.tags++;
      }
    }
  }
  // Characters
  if (includeRelations && anime.characters?.nodes && anime.characters?.edges) {
    for (let i = 0; i < anime.characters.nodes.length; i++) {
      const char = anime.characters.nodes[i];
      const edge = anime.characters.edges[i];
      const { data: ch, error: e } = await supabase
        .from('characters')
        .upsert({ anilist_id: char.id, name_full: char.name?.full, name_native: char.name?.native, image_large: char.image?.large, description: char.description, gender: char.gender, age: char.age }, { onConflict: 'anilist_id' })
        .select('id')
        .single();
      if (!e && ch) {
        await supabase.from('anime_characters').upsert({ anime_id: insertedAnime.id, character_id: ch.id, role: edge?.role });
        results.relationships++; results.characters++;
      }
    }
  }
  // Staff
  if (includeRelations && anime.staff?.nodes && anime.staff?.edges) {
    for (let i = 0; i < anime.staff.nodes.length; i++) {
      const person = anime.staff.nodes[i];
      const edge = anime.staff.edges[i];
      const { data: stf, error: e } = await supabase
        .from('staff')
        .upsert({ anilist_id: person.id, name_full: person.name?.full, name_native: person.name?.native, image_large: person.image?.large, description: person.description, primary_occupations: person.primaryOccupations }, { onConflict: 'anilist_id' })
        .select('id')
        .single();
      if (!e && stf) {
        await supabase.from('anime_staff').upsert({ anime_id: insertedAnime.id, staff_id: stf.id, role: edge?.role });
        results.relationships++; results.staff++;
      }
    }
  }

  if (includeRelations) {
    await replaceMediaRelationsForSource(supabase, 'ANIME', insertedAnime.id, anime.relations?.edges, results);
  }
}

function normalizeRelationType(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const normalized = raw.trim().toUpperCase();
  return SUPPORTED_MEDIA_RELATIONS.has(normalized) ? normalized : null;
}

function normalizeAniListMediaType(raw: unknown): 'ANIME' | 'MANGA' | null {
  if (typeof raw !== 'string') return null;
  const normalized = raw.trim().toUpperCase();
  if (normalized === 'ANIME' || normalized === 'MANGA') return normalized;
  return null;
}

async function resolveLocalMediaId(supabase: any, mediaType: 'ANIME' | 'MANGA', anilistId: number): Promise<number | null> {
  const table = mediaType === 'ANIME' ? 'anime' : 'manga';
  const { data, error } = await supabase
    .from(table)
    .select('id')
    .eq('anilist_id', anilistId)
    .maybeSingle();
  if (error) {
    console.error('media_relations target lookup failed:', error);
    return null;
  }
  return data?.id ?? null;
}

async function replaceMediaRelationsForSource(
  supabase: any,
  fromMediaType: 'ANIME' | 'MANGA',
  fromMediaId: number,
  relationEdges: any[] | undefined,
  results: any
) {
  const { error: deleteError } = await supabase
    .from('media_relations')
    .delete()
    .eq('from_media_type', fromMediaType)
    .eq('from_media_id', fromMediaId)
    .eq('source', 'anilist');
  if (deleteError) throw deleteError;

  if (!Array.isArray(relationEdges) || relationEdges.length == 0) {
    return;
  }

  for (const edge of relationEdges) {
    const relationType = normalizeRelationType(edge?.relationType);
    const targetType = normalizeAniListMediaType(edge?.node?.type);
    const targetAniListId = Number(edge?.node?.id);
    if (!relationType || !targetType || !Number.isFinite(targetAniListId)) {
      continue;
    }

    const targetMediaId = await resolveLocalMediaId(supabase, targetType, targetAniListId);
    if (!targetMediaId) {
      continue;
    }

    const { error } = await supabase
      .from('media_relations')
      .upsert(
        {
          from_media_type: fromMediaType,
          from_media_id: fromMediaId,
          relation_type: relationType,
          to_media_type: targetType,
          to_media_id: targetMediaId,
          source: 'anilist',
        },
        { onConflict: 'from_media_type,from_media_id,relation_type,to_media_type,to_media_id,source' }
      );
    if (!error) {
      results.relationships++;
    } else {
      console.error('media_relations upsert failed:', error);
    }
  }
}

async function fetchJsonWithRetry(query: string, variables: Record<string, unknown>, retries: number) {
  let attempt = 0;
  while (true) {
    try {
      const res = await fetch(ANILIST_API, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ query, variables })
      });
      if (res.ok) return await res.json();
      if ((res.status === 429 || res.status >= 500) && attempt < retries) {
        await sleep(500 * Math.pow(2, attempt));
        attempt++;
        continue;
      }
      throw new Error(`AniList error ${res.status}`);
    } catch (e) {
      if (attempt < retries) {
        await sleep(500 * Math.pow(2, attempt));
        attempt++;
        continue;
      }
      throw e;
    }
  }
}

function parseBooleanEnv(raw: string | undefined, fallback: boolean): boolean {
  if (!raw) return fallback;
  const normalized = raw.trim().toLowerCase();
  if (["1", "true", "yes", "on"].includes(normalized)) return true;
  if (["0", "false", "no", "off"].includes(normalized)) return false;
  return fallback;
}

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function acquireImportLock(supabase: any, key: string, ttlSeconds: number): Promise<boolean> {
  try {
    const { data, error } = await supabase.rpc('acquire_import_lock', { p_key: key, p_ttl_seconds: ttlSeconds });
    if (error) {
      console.error('Acquire lock error:', error);
      return true; // fail open to avoid blocking if RPC missing
    }
    return Boolean(data);
  } catch (e) {
    console.error('Acquire lock exception:', e);
    return true;
  }
}

async function releaseImportLock(supabase: any, key: string): Promise<void> {
  try {
    const { error } = await supabase.rpc('release_import_lock', { p_key: key });
    if (error) console.error('Release lock error:', error);
  } catch (e) {
    console.error('Release lock exception:', e);
  }
}

async function startImportRun(supabase: any, mediaType: string, runType: string, payload: any): Promise<number | null> {
  try {
    const { data, error } = await supabase
      .from('import_runs')
      .insert({ media_type: mediaType, run_type: runType, payload, status: 'running', started_at: new Date().toISOString() })
      .select('id')
      .single();
    if (error) {
      console.error('import_runs insert error:', error);
      return null;
    }
    return data?.id ?? null;
  } catch (e) {
    console.error('import_runs insert exception:', e);
    return null;
  }
}

async function finishImportRun(
  supabase: any,
  runId: number | null,
  status: string,
  results: any,
  message: string | null,
  startedAtMs: number
): Promise<void> {
  if (!runId) return;
  try {
    const durationMs = Date.now() - startedAtMs;
    const { error } = await supabase
      .from('import_runs')
      .update({ status, results, message, finished_at: new Date().toISOString(), duration_ms: durationMs })
      .eq('id', runId);
    if (error) console.error('import_runs update error:', error);
  } catch (e) {
    console.error('import_runs update exception:', e);
  }
}

async function readTrackedCursorPage(supabase: any, trackKey: string): Promise<number | null> {
  try {
    const { data, error } = await supabase
      .from('import_track_state')
      .select('last_page')
      .eq('track_key', trackKey)
      .maybeSingle();
    if (!error && data && typeof data.last_page === 'number') {
      return data.last_page;
    }
  } catch (e) {
    console.error('import_track_state read error:', e);
  }
  return null;
}

async function writeTrackedCursorState(
  supabase: any,
  args: {
    mediaType: string;
    trackKey: string | null;
    trackPreset: TrackPresetName;
    lastPage: number;
    status: string;
    visibility: string;
    results: unknown;
    message: string | null;
  }
): Promise<void> {
  const updatedAt = new Date().toISOString();
  const legacyPayload = {
    media_type: args.mediaType,
    last_page: args.lastPage,
    updated_at: updatedAt,
  };
  const trackPayload = args.trackKey ? {
    track_key: args.trackKey,
    media_type: args.mediaType,
    track_preset: args.trackPreset,
    last_page: args.lastPage,
    state: args.status,
    visibility: args.visibility,
    last_run_at: updatedAt,
    last_message: args.message,
    last_results: args.results ?? {},
    updated_at: updatedAt,
  } : null;

  if (trackPayload) {
    try {
      const { error } = await supabase
        .from('import_track_state')
        .upsert(trackPayload, { onConflict: 'track_key' });
      if (error) console.error('import_track_state upsert error:', error);
    } catch (e) {
      console.error('import_track_state upsert exception:', e);
    }
  }

  try {
    const { error } = await supabase
      .from('import_state')
      .upsert(legacyPayload, { onConflict: 'media_type' });
    if (error) console.error('import_state upsert error:', error);
  } catch (e) {
    console.error('import_state upsert exception:', e);
  }
}
