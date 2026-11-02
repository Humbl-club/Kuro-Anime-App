// Run orchestration for bulk-import-manga. index.ts checks IMPORT_SECRET, builds the
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
// The page loop stays a single for-loop bounded by pagesPerBatch, which is how this
// job already differs from bulk-import-anime.
// A GraphQL error or a response without data.Page throws in the transport: it is an
// error (no cursor advance, no wrap), never an empty page. When the limiter cannot fit
// another request in the run budget no request is sent; the run stops cleanly and
// commits the pages it fully persisted. Tracked presets each have their own upstream
// query and cursor (../bulk-import-anime/tracks.ts).
import { processMangaItem } from "./mapping.ts";
import {
  acquireImportLock,
  finishImportRun,
  finishUnacquiredLock,
  readTrackedCursorState,
  releaseImportLock,
  sleep,
  startImportRun,
  writeTrackedCursorState,
} from "../bulk-import-anime/persistence.ts";
import {
  advanceSweep,
  compatibleCursor,
  completeSweep,
  type CursorMeta,
  cursorMetaFor,
  DEFAULT_INITIAL_SWEEP_PAGES,
  normalizeTrackPreset,
  type PageQueryOptions,
  querySpecFor,
  type SweepState,
  type TrackPresetName,
} from "../bulk-import-anime/tracks.ts";
import { isCleanStop, pastAniListPageDepth } from "../_shared/anilist_client.ts";

const DEFAULT_DELAY_MS = 670; // ms
const DEFAULT_PER_PAGE = 25;
const DEFAULT_RETRIES = 3;
const ITEM_BATCH_SIZE = 5;
// AniList only gives chapter/volume counts for most manga, not per-row data.
// Use conservative non-zero defaults so imports materialize useful placeholders
// without exploding row count on long-running series.
const DEFAULT_MAX_PLACEHOLDER_CHAPTERS = 120;
const DEFAULT_MAX_PLACEHOLDER_VOLUMES = 24;

type TrackPresetDefaults = {
  useCursor: boolean;
  runToEnd: boolean;
  lightweight: boolean;
  includeRelations: boolean;
  includeChapters: boolean;
  includeVolumes: boolean;
  pagesPerBatch: number;
  maxPagesPerRun: number;
  perPage: number;
  delayMs: number;
  scheduleSafe: boolean;
};

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
        includeChapters: false,
        includeVolumes: false,
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
        includeChapters: true,
        includeVolumes: true,
        pagesPerBatch: 1,
        maxPagesPerRun: 6,
        perPage: 20,
        delayMs: 120,
        scheduleSafe: true,
      };
    case 'recent_updates':
    case 'new_titles':
      return {
        useCursor: true,
        runToEnd: false,
        lightweight: false,
        includeRelations: true,
        includeChapters: false,
        includeVolumes: false,
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
        includeChapters: true,
        includeVolumes: true,
        pagesPerBatch: 10,
        maxPagesPerRun: 200,
        perPage: 25,
        delayMs: 250,
        scheduleSafe: false,
      };
  }
}

export interface MangaImportDeps {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  fetchPage: (
    page: number,
    perPage: number,
    includeRelations: boolean,
    retries: number,
    query: PageQueryOptions,
    // deno-lint-ignore no-explicit-any
  ) => Promise<any[]>;
  heavyImportsEnabled: boolean;
}

// deno-lint-ignore no-explicit-any
export async function run(payload: any, deps: MangaImportDeps): Promise<Response> {
  const supabase = deps.supabase;
  const requestedTrackKey = String(payload?.trackKey ?? '').trim();
  const hasTrackRouting = Boolean(requestedTrackKey || payload?.trackPreset);
  const trackPreset = normalizeTrackPreset(payload?.trackPreset);
  const resolvedTrackKey = hasTrackRouting ? (requestedTrackKey || trackKeyFor('MANGA', trackPreset)) : '';
  const trackDefaults = hasTrackRouting ? trackPresetDefaults(trackPreset) : null;
  const spec = querySpecFor(hasTrackRouting ? trackPreset : null);
  let startPage: number | null = payload?.startPage ?? null;
  let pagesPerBatch: number = payload?.pagesPerBatch ?? (trackDefaults?.pagesPerBatch ?? 5);
  const useCursor: boolean = payload?.useCursor ?? (trackDefaults?.useCursor ?? true);
  let runToEnd: boolean = payload?.runToEnd ?? (trackDefaults?.runToEnd ?? false);
  let maxPagesPerRun: number = payload?.maxPagesPerRun ?? (trackDefaults?.maxPagesPerRun ?? 200);
  let perPage: number = payload?.perPage ?? (trackDefaults?.perPage ?? DEFAULT_PER_PAGE);
  let delayMs: number = payload?.delayMs ?? (trackDefaults?.delayMs ?? DEFAULT_DELAY_MS);
  const retries: number = payload?.retries ?? DEFAULT_RETRIES;
  const lightweight: boolean = payload?.lightweight ?? (trackDefaults?.lightweight ?? false);
  const includeRelations: boolean = payload?.includeRelations ?? (trackDefaults?.includeRelations ?? !lightweight);
  // Default to non-destructive imports. Placeholder rows must be explicitly requested.
  const includeChapters: boolean = payload?.includeChapters ?? (trackDefaults?.includeChapters ?? false);
  const includeVolumes: boolean = payload?.includeVolumes ?? (trackDefaults?.includeVolumes ?? false);
  const forceRefresh: boolean = payload?.forceRefresh ?? false;
  const lockTtlSeconds: number = payload?.lockTtlSeconds ?? 1800;
  const maxPlaceholderChapters: number = payload?.maxPlaceholderChapters ?? DEFAULT_MAX_PLACEHOLDER_CHAPTERS;
  const maxPlaceholderVolumes: number = payload?.maxPlaceholderVolumes ?? DEFAULT_MAX_PLACEHOLDER_VOLUMES;
  const scheduleSafe: boolean = payload?.scheduleSafe ?? (trackDefaults?.scheduleSafe ?? false);
  const initialSweepPages: number = payload?.initialSweepPages ?? DEFAULT_INITIAL_SWEEP_PAGES;

  if (scheduleSafe && !lightweight) {
    perPage = Math.max(1, Math.min(perPage, 10));
    pagesPerBatch = Math.max(1, Math.min(pagesPerBatch, 2));
    maxPagesPerRun = Math.max(1, Math.min(maxPagesPerRun, 10));
    if (runToEnd) runToEnd = false;
    delayMs = Math.max(0, Math.min(delayMs, 250));
  }
  // Cursor. Tracked runs read only their own row; untracked runs keep the legacy per-medium cursor.
  const watermarkMode = spec.mode !== 'page';
  let sweep: SweepState | null = null;
  let priorCursor: CursorMeta | null = null;
  if (useCursor && (!startPage || startPage < 1) && resolvedTrackKey) {
    const stored = compatibleCursor(spec, await readTrackedCursorState(supabase, resolvedTrackKey));
    priorCursor = stored.cursor;
    startPage = stored.lastPage + 1;
    if (watermarkMode) {
      sweep = { watermark: stored.cursor?.watermark ?? null, sweepTop: stored.cursor?.sweep_top ?? null, sweepPages: stored.lastPage };
    }
  } else if (useCursor && (!startPage || startPage < 1)) {
    const { data } = await supabase.from('import_state').select('last_page').eq('media_type', 'MANGA').maybeSingle();
    const last = data?.last_page ?? 0;
    startPage = last + 1;
  }
  if (!startPage || startPage < 1) startPage = 1;
  if (watermarkMode && !sweep) sweep = { watermark: null, sweepTop: null, sweepPages: startPage - 1 };
  const priorMeta: CursorMeta | null = hasTrackRouting ? (priorCursor ?? cursorMetaFor(spec, trackPreset, watermarkMode ? sweep : null)) : null;

  const results = { manga: 0, chapters: 0, volumes: 0, characters: 0, authors: 0, staff: 0, tags: 0, relationships: 0, errors: 0 };
  const runType = lightweight ? 'core' : 'heavy';
  const heavyImportsEnabled = deps.heavyImportsEnabled;
  const tRunStart = Date.now();
  let runId: number | null = await startImportRun(supabase, 'MANGA', runType, payload);
  let lockAcquired = false;

  if (!lightweight && !heavyImportsEnabled) {
    if (useCursor) {
      await writeTrackedCursorState(supabase, {
        mediaType: 'MANGA',
        trackKey: resolvedTrackKey || null,
        trackPreset,
        lastPage: Math.max(0, (startPage ?? 1) - 1),
        status: 'skipped',
        visibility: 'paused',
        results,
        message: 'heavy_disabled',
        cursor: priorMeta,
      });
    }
    await finishImportRun(supabase, runId, 'skipped', results, 'heavy_disabled', tRunStart);
    return new Response(
      JSON.stringify({ success: true, skipped: true, reason: 'heavy_disabled', results }),
      { headers: { 'Content-Type': 'application/json' } },
    );
  }

  try {
    const lock = await acquireImportLock(supabase, 'manga', lockTtlSeconds);
    if (lock.status !== "acquired") {
      return finishUnacquiredLock(supabase, {
        mediaType: 'MANGA',
        trackKey: resolvedTrackKey || null,
        trackPreset,
        useCursor,
        lastPage: Math.max(0, (startPage ?? 1) - 1),
        runId,
        results,
        startedAtMs: tRunStart,
        lock,
        cursor: priorMeta,
      });
    }
    lockAcquired = true;
    let lastProcessed = startPage - 1;
    let processedPages = 0;
    const timeBudgetMs = payload?.timeBudgetMs ?? 55_000;
    const t0 = Date.now();
    const deadlineMs = t0 + timeBudgetMs;
    let stoppedEarly: string | null = null;
    let sweepCompleted = false;
    for (let page = startPage; page < startPage + pagesPerBatch; page++) {
      let manga: any[] = [];
      // A page past AniList's depth limit is never requested: it ends the list like an empty page.
      if (!pastAniListPageDepth(page, perPage)) {
        try {
          manga = await deps.fetchPage(page, perPage, includeRelations, retries, {
            sort: spec.sort,
            statusIn: spec.statusIn,
            deadlineMs,
          });
        } catch (e) {
          // No request was sent for this page: commit what this run fully persisted and stop.
          if (isCleanStop(e)) {
            stoppedEarly = (e as { kind: string }).kind;
            break;
          }
          throw e;
        }
      }
      if (!manga.length) {
        // A real empty page (the transport throws on errors) or the depth limit: the list is exhausted.
        if (watermarkMode) sweepCompleted = true;
        // Cursor wrap-around: if we hit the end, reset so the next run starts from page 1.
        else if (useCursor && page === startPage) lastProcessed = 0;
        break;
      }
      let primaryFailure: unknown = null;
      for (let bi = 0; bi < manga.length; bi += ITEM_BATCH_SIZE) {
        const chunk = manga.slice(bi, bi + ITEM_BATCH_SIZE);
        await Promise.all(chunk.map(async (item: any) => {
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
            if (!primaryFailure) primaryFailure = e;
          }
        }));
      }
      // Do not acknowledge a page whose primary catalog write failed. The catch
      // keeps the pre-run checkpoint so this page is replayed.
      if (primaryFailure) throw primaryFailure;
      lastProcessed = page;
      processedPages++;
      if (watermarkMode && sweep) {
        const advanced = advanceSweep(spec.mode, sweep, manga, initialSweepPages);
        sweep = advanced.state;
        if (advanced.complete) {
          sweepCompleted = true;
          break;
        }
      }
      await sleep(delayMs);
      if (!runToEnd && processedPages >= pagesPerBatch) break;
      if (runToEnd && (processedPages >= maxPagesPerRun || (Date.now() - t0) > timeBudgetMs)) break;
    }
    let cursorMeta: CursorMeta | null = null;
    if (watermarkMode && sweep) {
      if (sweepCompleted) sweep = completeSweep(sweep);
      lastProcessed = sweep.sweepPages;
      cursorMeta = cursorMetaFor(spec, trackPreset, sweep);
    } else if (hasTrackRouting) {
      cursorMeta = cursorMetaFor(spec, trackPreset, null);
    }
    if (useCursor) {
      await writeTrackedCursorState(supabase, {
        mediaType: 'MANGA',
        trackKey: resolvedTrackKey || null,
        trackPreset,
        lastPage: lastProcessed,
        status: 'success',
        visibility: 'active',
        results,
        message: stoppedEarly ? `stopped_early:${stoppedEarly}` : null,
        cursor: cursorMeta,
      });
    }
    await finishImportRun(supabase, runId, 'success', results, stoppedEarly ? `stopped_early:${stoppedEarly}` : null, tRunStart);
    return new Response(JSON.stringify({ success: true, results, nextStartPage: (lastProcessed + 1), trackKey: hasTrackRouting ? resolvedTrackKey : null, trackPreset: hasTrackRouting ? trackPreset : null, stoppedEarly, sweepCompleted: watermarkMode ? sweepCompleted : null }), { headers: { 'Content-Type': 'application/json' } });
  } catch (e) {
    if (useCursor) {
      await writeTrackedCursorState(supabase, {
        mediaType: 'MANGA',
        trackKey: resolvedTrackKey || null,
        trackPreset,
        lastPage: Math.max(0, (startPage ?? 1) - 1),
        status: 'error',
        visibility: 'paused',
        results,
        message: (e as Error).message,
        cursor: priorMeta,
      });
    }
    await finishImportRun(supabase, runId, 'error', results, (e as Error).message, tRunStart);
    return new Response(JSON.stringify({ success: false, error: (e as Error).message }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  } finally {
    if (lockAcquired) {
      await releaseImportLock(supabase, 'manga');
    }
  }
}
