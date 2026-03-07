// Deployed from local patch of 07_manga_edge_function_with_chapters.js
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const ANILIST_API = 'https://graphql.anilist.co';
const DEFAULT_DELAY_MS = 670; // ms
const DEFAULT_PER_PAGE = 25;
const DEFAULT_RETRIES = 3;
// AniList only gives chapter/volume counts for most manga, not per-row data.
// Use conservative non-zero defaults so imports materialize useful placeholders
// without exploding row count on long-running series.
const DEFAULT_MAX_PLACEHOLDER_CHAPTERS = 120;
const DEFAULT_MAX_PLACEHOLDER_VOLUMES = 24;
const SUPPORTED_MEDIA_RELATIONS = new Set(['SOURCE', 'ADAPTATION', 'PREQUEL', 'SEQUEL', 'SIDE_STORY', 'SPIN_OFF']);

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
  let startPage: number | null = payload?.startPage ?? null;
  let pagesPerBatch: number = payload?.pagesPerBatch ?? 5;
  const useCursor: boolean = payload?.useCursor ?? true;
  let runToEnd: boolean = payload?.runToEnd ?? false;
  let maxPagesPerRun: number = payload?.maxPagesPerRun ?? 200;
  let perPage: number = payload?.perPage ?? DEFAULT_PER_PAGE;
  let delayMs: number = payload?.delayMs ?? DEFAULT_DELAY_MS;
  const retries: number = payload?.retries ?? DEFAULT_RETRIES;
  const lightweight: boolean = payload?.lightweight ?? false;
  const includeRelations: boolean = payload?.includeRelations ?? !lightweight;
  // Default to non-destructive imports. Placeholder rows must be explicitly requested.
  const includeChapters: boolean = payload?.includeChapters ?? false;
  const includeVolumes: boolean = payload?.includeVolumes ?? false;
  const forceRefresh: boolean = payload?.forceRefresh ?? false;
  const lockTtlSeconds: number = payload?.lockTtlSeconds ?? 1800;
  const maxPlaceholderChapters: number = payload?.maxPlaceholderChapters ?? DEFAULT_MAX_PLACEHOLDER_CHAPTERS;
  const maxPlaceholderVolumes: number = payload?.maxPlaceholderVolumes ?? DEFAULT_MAX_PLACEHOLDER_VOLUMES;
  const scheduleSafe: boolean = payload?.scheduleSafe ?? false;

  if (scheduleSafe && !lightweight) {
    perPage = Math.max(1, Math.min(perPage, 10));
    pagesPerBatch = Math.max(1, Math.min(pagesPerBatch, 2));
    maxPagesPerRun = Math.max(1, Math.min(maxPagesPerRun, 10));
    if (runToEnd) runToEnd = false;
    delayMs = Math.max(0, Math.min(delayMs, 250));
  }
  if (useCursor && (!startPage || startPage < 1)) {
    const { data } = await supabase.from('import_state').select('last_page').eq('media_type', 'MANGA').single();
    const last = data?.last_page ?? 0;
    startPage = last + 1;
  }
  if (!startPage || startPage < 1) startPage = 1;

  const results = { manga: 0, chapters: 0, volumes: 0, characters: 0, authors: 0, staff: 0, tags: 0, relationships: 0, errors: 0 };
  const runType = lightweight ? 'core' : 'heavy';
  const heavyImportsEnabled = parseBooleanEnv(Deno.env.get("IMPORT_HEAVY_ENABLED"), true);
  const tRunStart = Date.now();
  let runId: number | null = await startImportRun(supabase, 'MANGA', runType, payload);
  let lockAcquired = false;

  if (!lightweight && !heavyImportsEnabled) {
    await finishImportRun(supabase, runId, 'skipped', results, 'heavy_disabled', tRunStart);
    return new Response(
      JSON.stringify({ success: true, skipped: true, reason: 'heavy_disabled', results }),
      { headers: { 'Content-Type': 'application/json' } },
    );
  }

  try {
    lockAcquired = await acquireImportLock(supabase, 'manga', lockTtlSeconds);
    if (!lockAcquired) {
      await finishImportRun(supabase, runId, 'skipped', results, 'locked', tRunStart);
      return new Response(JSON.stringify({ success: true, skipped: true, reason: 'locked', results }), { headers: { 'Content-Type': 'application/json' } });
    }
    let lastProcessed = startPage - 1;
    let processedPages = 0;
    const timeBudgetMs = payload?.timeBudgetMs ?? 55_000;
    const t0 = Date.now();
    for (let page = startPage; page < startPage + pagesPerBatch; page++) {
      const manga = await fetchAniListMangaData(page, perPage, includeRelations, retries);
      if (!manga.length) {
        // Cursor wrap-around: if we hit the end, reset so the next run starts from page 1.
        if (useCursor && page === startPage) lastProcessed = 0;
        break;
      }
      for (const item of manga) {
        try {
          await processMangaItem(
            supabase,
            item,
            results,
            includeRelations,
            includeChapters,
            includeVolumes,
            forceRefresh,
            maxPlaceholderChapters,
            maxPlaceholderVolumes
          );
        } catch (e) {
          console.error(e);
          results.errors++;
        }
      }
      lastProcessed = page;
      processedPages++;
      await sleep(delayMs);
      if (!runToEnd && processedPages >= pagesPerBatch) break;
      if (runToEnd && (processedPages >= maxPagesPerRun || (Date.now() - t0) > timeBudgetMs)) break;
    }
    if (useCursor) {
      await supabase
        .from('import_state')
        .upsert({ media_type: 'MANGA', last_page: lastProcessed, updated_at: new Date().toISOString() }, { onConflict: 'media_type' });
    }
    await finishImportRun(supabase, runId, 'success', results, null, tRunStart);
    return new Response(JSON.stringify({ success: true, results, nextStartPage: (lastProcessed + 1) }), { headers: { 'Content-Type': 'application/json' } });
  } catch (e) {
    await finishImportRun(supabase, runId, 'error', results, (e as Error).message, tRunStart);
    return new Response(JSON.stringify({ success: false, error: (e as Error).message }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  } finally {
    if (lockAcquired) {
      await releaseImportLock(supabase, 'manga');
    }
  }
});

async function fetchAniListMangaData(page: number, perPage: number, includeRelations: boolean, retries: number) {
  const relationsFragment = includeRelations ? `
          relations {
            edges {
              relationType(version: 2)
              node { id type format title { romaji english native userPreferred } coverImage { large } }
            }
          }
          staff(sort: RELEVANCE, perPage: 10) { edges { role } nodes { id name { full native } image { large } description primaryOccupations } }
          tags { id name description category rank isGeneralSpoiler isMediaSpoiler isAdult }
          characters(sort: ROLE, perPage: 10) { edges { role } nodes { id name { full native } image { large } description gender age } }
  ` : ``;
  const externalLinksFragment = `
          externalLinks { site url language color }`;
  const query = `
    query ($page: Int, $perPage: Int) {
      Page(page: $page, perPage: $perPage) {
        media(sort: POPULARITY_DESC, type: MANGA) {
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
          chapters volumes
          averageScore meanScore popularity trending favourites
          genres
          siteUrl updatedAt
          ${externalLinksFragment}
          ${relationsFragment}
        }
      }
    }
  `;
  const data = await fetchJsonWithRetry(query, { page, perPage }, retries);
  return data?.data?.Page?.media ?? [];
}

async function processMangaItem(
  supabase: any,
  manga: any,
  results: any,
  includeRelations: boolean,
  includeChapters: boolean,
  includeVolumes: boolean,
  forceRefresh: boolean,
  maxPlaceholderChapters: number,
  maxPlaceholderVolumes: number
) {
  const updatedAtAnilist = manga.updatedAt ? new Date(manga.updatedAt * 1000).toISOString() : null;
  const { data: existing, error: existingError } = await supabase
    .from('manga')
    .select('id, updated_at_anilist')
    .eq('anilist_id', manga.id)
    .maybeSingle();
  if (existingError) {
    console.error('Existing manga lookup failed:', existingError);
  }
  const isStale = forceRefresh || !existing || !existing.updated_at_anilist || (updatedAtAnilist && existing.updated_at_anilist !== updatedAtAnilist);
  if (existing && !isStale) {
    await supabase.from('manga').update({ last_synced_at: new Date().toISOString() }).eq('id', existing.id);
    return;
  }

  const mangaData = {
    anilist_id: manga.id,
    mal_id: manga.idMal,
    title_english: manga.title?.english,
    title_romaji: manga.title?.romaji,
    title_native: manga.title?.native,
    title_synonyms: manga.synonyms,
    cover_image_large: manga.coverImage?.large,
    cover_image_medium: manga.coverImage?.medium,
    cover_image_color: manga.coverImage?.color,
    banner_image: manga.bannerImage,
    format: manga.format,
    status: manga.status,
    description: manga.description,
    chapters: manga.chapters,
    volumes: manga.volumes,
    next_chapter_number: null as number | null,
    next_chapter_at: null as string | null,
    start_date_year: manga.startDate?.year,
    start_date_month: manga.startDate?.month,
    start_date_day: manga.startDate?.day,
    end_date_year: manga.endDate?.year,
    end_date_month: manga.endDate?.month,
    end_date_day: manga.endDate?.day,
    average_score: manga.averageScore,
    mean_score: manga.meanScore,
    popularity: manga.popularity,
    trending: manga.trending,
    favourites: manga.favourites,
    genres: manga.genres,
    source: manga.source,
    country_of_origin: manga.countryOfOrigin,
    is_adult: manga.isAdult,
    site_url: manga.siteUrl,
    synopsis_enhanced_state: 'pending',
    updated_at_anilist: updatedAtAnilist,
    last_synced_at: new Date().toISOString()
  };
  const { data: insertedManga, error: mangaError } = await supabase.from('manga').upsert(mangaData, { onConflict: 'anilist_id' }).select('id').single();
  if (mangaError) throw mangaError; results.manga++;

  // External links (read on...) from AniList externalLinks
  if (Array.isArray(manga.externalLinks) && manga.externalLinks.length > 0) {
    for (const link of manga.externalLinks) {
      const url = link?.url;
      if (!url || typeof url !== 'string' || !url.startsWith('http')) continue;
      const payload = {
        media_type: 'MANGA',
        media_id: insertedManga.id,
        site: link?.site ?? null,
        url,
        language: link?.language ?? null,
        color: link?.color ?? null,
        is_disabled: false,
      };
      const { error } = await supabase.from('external_links').upsert(payload, { onConflict: 'media_type,media_id,url' });
      if (error) console.error('external_links upsert error:', error);
    }
  }

  // Chapters
  // AniList does not provide per-chapter rows; only materialize placeholders when explicitly requested.
  // Never delete existing rows here because chapter enrichment owns canonical chapter coverage.
  if (includeChapters && maxPlaceholderChapters > 0 && manga.chapters && manga.chapters > 0) {
    const { count: existingCount, error: countError } = await supabase
      .from('chapters')
      .select('*', { count: 'exact', head: true })
      .eq('manga_id', insertedManga.id);
    if (countError) {
      console.error('chapters count failed:', countError);
    }
    if ((existingCount ?? 0) === 0) {
      const count = Math.min(manga.chapters, maxPlaceholderChapters);
      const rows = Array.from({ length: count }, (_, i) => ({ manga_id: insertedManga.id, number: i + 1, title: `Chapter ${i + 1}` }));
      const { error } = await supabase.from('chapters').insert(rows);
      if (!error) results.chapters += rows.length;
    }
  }

  // Volumes
  // AniList does not provide per-volume rows; only materialize placeholders when explicitly requested.
  // Never delete existing rows here because downstream enrichment can provide richer data.
  if (includeVolumes && maxPlaceholderVolumes > 0 && manga.volumes && manga.volumes > 0) {
    const { count: existingCount, error: countError } = await supabase
      .from('volumes')
      .select('*', { count: 'exact', head: true })
      .eq('manga_id', insertedManga.id);
    if (countError) {
      console.error('volumes count failed:', countError);
    }
    if ((existingCount ?? 0) === 0) {
      const count = Math.min(manga.volumes, maxPlaceholderVolumes);
      const rows = Array.from({ length: count }, (_, i) => ({ manga_id: insertedManga.id, number: i + 1, title: `Volume ${i + 1}`, cover_image_large: null, cover_image_medium: null }));
      const { error } = await supabase.from('volumes').insert(rows);
      if (!error) results.volumes += rows.length;
    }
  }

  // Authors (from staff nodes)
  if (includeRelations && manga.staff?.nodes && manga.staff?.edges) {
    for (let i = 0; i < manga.staff.nodes.length; i++) {
      const person = manga.staff.nodes[i];
      const edge = manga.staff.edges[i];
      const { data: au, error: e } = await supabase
        .from('authors')
        .upsert({ anilist_id: person.id, name_full: person.name?.full, name_native: person.name?.native, image_large: person.image?.large, description: person.description, primary_occupations: person.primaryOccupations }, { onConflict: 'anilist_id' })
        .select('id')
        .single();
      if (!e && au) {
        await supabase.from('manga_authors').upsert({ manga_id: insertedManga.id, author_id: au.id, role: edge?.role });
        results.relationships++; results.authors++;
      }
    }
  }

  // Tags
  if (includeRelations && manga.tags) {
    for (const tag of manga.tags) {
      const { data: tg, error: e } = await supabase
        .from('tags')
        .upsert({ anilist_id: tag.id, name: tag.name, description: tag.description, category: tag.category, is_general_spoiler: tag.isGeneralSpoiler, is_media_spoiler: tag.isMediaSpoiler, is_adult: tag.isAdult }, { onConflict: 'anilist_id' })
        .select('id')
        .single();
      if (!e && tg) {
        await supabase.from('manga_tags').upsert({ manga_id: insertedManga.id, tag_id: tg.id, rank: tag.rank ?? 0 });
        results.relationships++; results.tags++;
      }
    }
  }

  // Characters
  if (includeRelations && manga.characters?.nodes && manga.characters?.edges) {
    for (let i = 0; i < manga.characters.nodes.length; i++) {
      const char = manga.characters.nodes[i];
      const edge = manga.characters.edges[i];
      const { data: ch, error: e } = await supabase
        .from('characters')
        .upsert({ anilist_id: char.id, name_full: char.name?.full, name_native: char.name?.native, image_large: char.image?.large, description: char.description, gender: char.gender, age: char.age }, { onConflict: 'anilist_id' })
        .select('id')
        .single();
      if (!e && ch) {
        await supabase.from('manga_characters').upsert({ manga_id: insertedManga.id, character_id: ch.id, role: edge?.role });
        results.relationships++; results.characters++;
      }
    }
  }

  // Staff (editors/publishers/etc.)
  if (includeRelations && manga.staff?.nodes && manga.staff?.edges) {
    for (let i = 0; i < manga.staff.nodes.length; i++) {
      const person = manga.staff.nodes[i];
      const edge = manga.staff.edges[i];
      const { data: stf, error: e } = await supabase
        .from('staff')
        .upsert({ anilist_id: person.id, name_full: person.name?.full, name_native: person.name?.native, image_large: person.image?.large, description: person.description, primary_occupations: person.primaryOccupations }, { onConflict: 'anilist_id' })
        .select('id')
        .single();
      if (!e && stf) {
        await supabase.from('manga_staff').upsert({ manga_id: insertedManga.id, staff_id: stf.id, role: edge?.role });
        results.relationships++; results.staff++;
      }
    }
  }

  if (includeRelations) {
    await replaceMediaRelationsForSource(supabase, 'MANGA', insertedManga.id, manga.relations?.edges, results);
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
      return true;
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
