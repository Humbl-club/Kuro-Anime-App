// Run orchestration for bulk-import-anime. index.ts checks IMPORT_SECRET, builds the
// service-role client and calls run(). Page fetch is injected so a provider failure
// can be tested without the network.
// A thrown fetch does not checkpoint that page: the cursor is written as the page
// before this run (pages persisted earlier in the same run are not committed to the
// cursor either) and the lock is released in finally.
// A failed primary catalog write uses that same checkpoint. The failed page is
// replayed; upserts on anilist_id stay idempotent. The run is not success.
// Only an acquired lock is released. Busy keeps the locked skip. An RPC error or
// throw is unavailable: no provider calls, no catalog writes, no cursor advance,
// and no release.
import { processAnimeItem } from "./mapping.ts";
import {
  acquireImportLock,
  finishImportRun,
  finishUnacquiredLock,
  readTrackedCursorPage,
  releaseImportLock,
  sleep,
  startImportRun,
  writeTrackedCursorState,
  type TrackPresetName,
} from "./persistence.ts";

const DEFAULT_DELAY_MS = 670; // ms
const DEFAULT_PER_PAGE = 25;
const DEFAULT_RETRIES = 3;
const ITEM_BATCH_SIZE = 5;

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

export interface AnimeImportDeps {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  fetchPage: (
    page: number,
    perPage: number,
    includeRelations: boolean,
    includeEpisodes: boolean,
    retries: number,
    // deno-lint-ignore no-explicit-any
  ) => Promise<any[]>;
  heavyImportsEnabled: boolean;
}

// deno-lint-ignore no-explicit-any
export async function run(payload: any, deps: AnimeImportDeps): Promise<Response> {
  const supabase = deps.supabase;
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
  const heavyImportsEnabled = deps.heavyImportsEnabled;
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
    const lock = await acquireImportLock(supabase, 'anime', lockTtlSeconds);
    if (lock.status !== "acquired") {
      return finishUnacquiredLock(supabase, {
        mediaType: 'ANIME',
        trackKey: resolvedTrackKey || null,
        trackPreset,
        useCursor,
        lastPage: Math.max(0, startPage - 1),
        runId,
        results,
        startedAtMs: tRunStart,
        lock,
      });
    }
    lockAcquired = true;
    let lastProcessed = startPage - 1;
    const timeBudgetMs = payload?.timeBudgetMs ?? 55_000; // typical function budget safety
    const t0 = Date.now();
    let processedPages = 0;
    let page = startPage;
    const step = Math.max(1, pagesPerBatch);
    outer: while (true) {
      for (let p = page; p < page + step; p++) {
        const anime = await deps.fetchPage(p, perPage, includeRelations, includeEpisodes, retries);
        if (!anime.length) {
          // Cursor wrap-around: if we hit the end, reset so the next run starts from page 1.
          lastProcessed = (useCursor && p === startPage) ? 0 : (p - 1);
          break outer;
        }
        let primaryFailure: unknown = null;
        for (let bi = 0; bi < anime.length; bi += ITEM_BATCH_SIZE) {
          const chunk = anime.slice(bi, bi + ITEM_BATCH_SIZE);
          await Promise.all(chunk.map(async (item: any) => {
            try {
              await processAnimeItem(supabase, item, results, includeRelations, includeEpisodes, forceRefresh);
            } catch (e) {
              console.error(e);
              results.errors++;
              if (!primaryFailure) primaryFailure = e;
            }
          }));
        }
        // Do not acknowledge a page whose primary catalog write failed. The catch
        // keeps the pre-run checkpoint so this page is replayed.
        if (primaryFailure) throw primaryFailure;
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
}
