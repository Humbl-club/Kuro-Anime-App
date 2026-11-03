// Per-track AniList queries and cursors for bulk-import-anime and bulk-import-manga
// (manga imports this file by relative path, like persistence.ts).
//
// Each tracked preset now has its own upstream query:
//   popularity_core, catalog_backfill  -> sort POPULARITY_DESC, page cursor (stable crawl)
//   airing_or_releasing                -> status_in [RELEASING, NOT_YET_RELEASED], sort UPDATED_AT_DESC
//   recent_updates                     -> sort UPDATED_AT_DESC
//   new_titles                         -> sort ID_DESC (newly added AniList entries)
// The head of an UPDATED_AT_DESC / ID_DESC list moves between runs, so those tracks do not use a
// page cursor. A sweep starts at page 1 and walks down until it reaches the watermark (the highest
// key the previous completed sweep saw, minus an overlap); a sweep that does not finish in one run
// resumes at the next page. The query version is stored with the cursor (import_track_state
// last_results.cursor); a different version resets the cursor so pages of one query are never
// resumed against another.
//
// import_track_state.track_preset has a CHECK constraint with the four original presets, so
// new_titles is persisted as 'recent_updates' in that column; the real preset is the track key
// (default `<medium>:new_titles`) plus last_results.cursor.preset. See persistedPresetColumn.

export type TrackPresetName =
  | "popularity_core"
  | "airing_or_releasing"
  | "recent_updates"
  | "catalog_backfill"
  | "new_titles";

export type LegacyPresetColumn = "popularity_core" | "airing_or_releasing" | "recent_updates" | "catalog_backfill";

export type MediaSort = "POPULARITY_DESC" | "UPDATED_AT_DESC" | "ID_DESC";
export type CursorMode = "page" | "updated_watermark" | "id_watermark";

export type MediaQuerySpec = {
  sort: MediaSort;
  statusIn: string[] | null;
  mode: CursorMode;
  version: string;
};

/** Options the run passes to fetchPage. */
export type PageQueryOptions = {
  sort: MediaSort;
  statusIn: string[] | null;
  deadlineMs?: number;
  /** Anime only: also request JAPANESE voice actors per character edge (default off). */
  includeVoiceActors?: boolean;
};

/** Stored in import_track_state.last_results.cursor. */
export type CursorMeta = {
  query_version: string;
  preset: TrackPresetName;
  mode: CursorMode;
  /** Highest key (updatedAt seconds or AniList id) covered by the last completed sweep. */
  watermark: number | null;
  /** Highest key seen so far in the sweep in progress. */
  sweep_top: number | null;
};

export const UPDATED_OVERLAP_SECONDS = 600;
export const DEFAULT_INITIAL_SWEEP_PAGES = 4;

const LEGACY_POPULARITY_VERSION = "popularity_desc:v1";

export function normalizeTrackPreset(raw: unknown): TrackPresetName {
  const value = String(raw ?? "").trim().toLowerCase();
  if (
    value === "popularity_core" || value === "airing_or_releasing" || value === "recent_updates" ||
    value === "catalog_backfill" || value === "new_titles"
  ) {
    return value;
  }
  return "catalog_backfill";
}

export function persistedPresetColumn(preset: TrackPresetName): LegacyPresetColumn {
  return preset === "new_titles" ? "recent_updates" : preset;
}

/** Untracked runs keep the legacy popularity page crawl. */
export function querySpecFor(preset: TrackPresetName | null): MediaQuerySpec {
  switch (preset) {
    case "airing_or_releasing":
      return {
        sort: "UPDATED_AT_DESC",
        statusIn: ["RELEASING", "NOT_YET_RELEASED"],
        mode: "updated_watermark",
        version: "updated_at_desc+status_releasing:v2",
      };
    case "recent_updates":
      return { sort: "UPDATED_AT_DESC", statusIn: null, mode: "updated_watermark", version: "updated_at_desc:v2" };
    case "new_titles":
      return { sort: "ID_DESC", statusIn: null, mode: "id_watermark", version: "id_desc:v1" };
    case "popularity_core":
    case "catalog_backfill":
    default:
      return { sort: "POPULARITY_DESC", statusIn: null, mode: "page", version: LEGACY_POPULARITY_VERSION };
  }
}

/**
 * The stored cursor is reusable only for the same query. A legacy row without a version was
 * written by the popularity crawl, so it stays valid for page-mode popularity tracks only.
 */
export function compatibleCursor(
  spec: MediaQuerySpec,
  stored: { lastPage: number; cursor: CursorMeta | null } | null,
): { lastPage: number; cursor: CursorMeta | null } {
  if (!stored) return { lastPage: 0, cursor: null };
  const version = stored.cursor?.query_version ?? LEGACY_POPULARITY_VERSION;
  if (version !== spec.version) return { lastPage: 0, cursor: null };
  return stored;
}

// deno-lint-ignore no-explicit-any
export function itemKey(mode: CursorMode, item: any): number | null {
  const raw = mode === "id_watermark" ? item?.id : item?.updatedAt;
  const n = Number(raw);
  return Number.isFinite(n) ? n : null;
}

export type SweepState = {
  watermark: number | null;
  sweepTop: number | null;
  /** Pages completed in the current sweep (the resume page is this + 1). */
  sweepPages: number;
};

/**
 * After one fully persisted page: returns whether the sweep reached older territory (or the
 * initial bound when no watermark exists yet) and the updated sweep top.
 */
export function advanceSweep(
  mode: CursorMode,
  state: SweepState,
  // deno-lint-ignore no-explicit-any
  items: any[],
  initialSweepPages: number,
): { complete: boolean; state: SweepState } {
  const keys = items.map((item) => itemKey(mode, item)).filter((k): k is number => k !== null);
  const pageMax = keys.length ? Math.max(...keys) : null;
  const pageMin = keys.length ? Math.min(...keys) : null;
  const sweepTop = pageMax === null ? state.sweepTop : Math.max(state.sweepTop ?? pageMax, pageMax);
  const next: SweepState = { watermark: state.watermark, sweepTop, sweepPages: state.sweepPages + 1 };
  const overlap = mode === "updated_watermark" ? UPDATED_OVERLAP_SECONDS : 0;
  let complete = false;
  if (state.watermark !== null) {
    complete = pageMin !== null && pageMin <= state.watermark - overlap;
  } else {
    complete = next.sweepPages >= Math.max(1, initialSweepPages);
  }
  return { complete, state: next };
}

/** Sweep finished (watermark reached or list exhausted): adopt the new top and restart at page 1. */
export function completeSweep(state: SweepState): SweepState {
  return { watermark: state.sweepTop ?? state.watermark, sweepTop: null, sweepPages: 0 };
}

export function cursorMetaFor(spec: MediaQuerySpec, preset: TrackPresetName, state: SweepState | null): CursorMeta {
  return {
    query_version: spec.version,
    preset,
    mode: spec.mode,
    watermark: state?.watermark ?? null,
    sweep_top: state?.sweepTop ?? null,
  };
}
