// release-intake run orchestration (prepared, NOT deployed, NOT scheduled; licensing D11).
// index.ts checks IMPORT_SECRET and builds the service-role client; everything else is injected
// so the run is testable offline.
//
// Payload:
//   mode            'airing' | 'manga' (required)
//   dryRun          true: read sources and compute rows, write nothing (rows sampled in the reply)
//   timeBudgetMs    default 50_000
//   airing: perPage (<= 50, default 50), maxPages (default 25), staleSweep (default true),
//           staleLimit (<= 50, default 50)
//   manga:  limit (default 15, <= 40), offset (default: rotates hourly), mangaIds (explicit
//           local ids), confirmedPastLimit (default 10). The official MangaUpdates group
//           allowlist is deployment config (deps.muOfficialGroupIds, from MU_OFFICIAL_GROUP_IDS),
//           never taken from the payload; empty = no release rows/estimates (open D11 decision).
// Lock: acquire_import_lock('release-intake:<mode>'), released only when acquired (fail closed,
// same contract as bulk-import). Bookkeeping: import_runs (run_type 'release_intake_<mode>').
import type { AniListClient } from "../_shared/anilist_client.ts";
import type { PoliteClient } from "../_shared/polite_fetch.ts";
import {
  acquireImportLock,
  finishImportRun,
  releaseImportLock,
  startImportRun,
} from "../bulk-import-anime/persistence.ts";
import { runAiringWindow } from "./airing.ts";
import { type MangaDexLinkReader, runMangaReleases } from "./manga.ts";

export interface ReleaseIntakeDeps {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  anilist: AniListClient;
  mangaUpdates: PoliteClient;
  readMangaDexLinks: MangaDexLinkReader;
  /** Official-publisher MangaUpdates group ids whose release dates may be used (default none). */
  muOfficialGroupIds?: number[];
  now?: () => number;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function clampInt(raw: unknown, fallback: number, min: number, max: number): number {
  const n = Number(raw);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, Math.floor(n)));
}

// deno-lint-ignore no-explicit-any
export async function run(payload: any, deps: ReleaseIntakeDeps): Promise<Response> {
  const mode = String(payload?.mode ?? "").trim().toLowerCase();
  if (mode !== "airing" && mode !== "manga") {
    return json({ success: false, error: "mode must be 'airing' or 'manga'" }, 400);
  }
  const now = deps.now ?? Date.now;
  const supabase = deps.supabase;
  const dryRun = payload?.dryRun === true;
  const timeBudgetMs = clampInt(payload?.timeBudgetMs, 50_000, 5_000, 140_000);
  const startedMs = now();
  const deadlineMs = startedMs + timeBudgetMs;
  const lockKey = `release-intake:${mode}`;
  const mediaType = mode === "airing" ? "ANIME" : "MANGA";
  const runId = dryRun ? null : await startImportRun(supabase, mediaType, `release_intake_${mode}`, payload);

  const lock = await acquireImportLock(supabase, lockKey, clampInt(payload?.lockTtlSeconds, 900, 60, 3600));
  if (lock.status !== "acquired") {
    const unavailable = lock.status === "unavailable";
    const message = unavailable ? lock.reason : "locked";
    await finishImportRun(supabase, runId, unavailable ? "error" : "skipped", {}, message, startedMs);
    return json(
      unavailable
        ? { success: false, skipped: true, reason: "lock_unavailable", error: message }
        : { success: true, skipped: true, reason: "locked" },
      unavailable ? 500 : 200,
    );
  }

  try {
    let results: Record<string, unknown>;
    if (mode === "airing") {
      results = await runAiringWindow(supabase, deps.anilist, {
        perPage: clampInt(payload?.perPage, 50, 1, 50),
        maxPages: clampInt(payload?.maxPages, 25, 1, 60),
        staleSweep: payload?.staleSweep !== false,
        staleLimit: clampInt(payload?.staleLimit, 50, 0, 50),
        dryRun,
        deadlineMs,
        nowMs: startedMs,
      });
    } else {
      const ids = Array.isArray(payload?.mangaIds)
        ? payload.mangaIds.map(Number).filter((n: number) => Number.isInteger(n) && n > 0).slice(0, 40)
        : null;
      const limit = clampInt(payload?.limit, 15, 1, 40);
      results = await runMangaReleases(supabase, deps.mangaUpdates, deps.readMangaDexLinks, {
        limit,
        offset: clampInt(payload?.offset, Math.floor(startedMs / 3_600_000) * limit, 0, Number.MAX_SAFE_INTEGER),
        mangaIds: ids && ids.length > 0 ? ids : null,
        confirmedPastLimit: clampInt(payload?.confirmedPastLimit, 10, 0, 40),
        officialGroupIds: deps.muOfficialGroupIds ?? [],
        dryRun,
        deadlineMs,
        nowMs: startedMs,
      });
    }
    const { sampleRows, ...summary } = results as Record<string, unknown> & { sampleRows?: unknown };
    const message = summary.stoppedEarly ? `stopped_early:${summary.stoppedEarly}` : null;
    await finishImportRun(supabase, runId, "success", summary, message, startedMs);
    return json({ success: true, mode, dryRun, results: summary, ...(dryRun ? { sampleRows } : {}) });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    await finishImportRun(supabase, runId, "error", {}, message, startedMs);
    return json({ success: false, mode, error: message }, 500);
  } finally {
    await releaseImportLock(supabase, lockKey);
  }
}
