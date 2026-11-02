// Lock, run bookkeeping and cursor checkpoint for bulk-import-anime and bulk-import-manga.
// Manga imports this file by relative path. These writes are the same in both jobs
// (acquire/release_import_lock, import_runs, import_state, import_track_state).
// AniList queries and medium row mapping stay in each function.
//
// Lock contract: data === true is acquired, data === false or null is busy, and an
// RPC error or throw is unavailable. Only acquired may import, and only that run
// releases the lock. Busy keeps the existing locked skip. Unavailable does not
// grant the run.

import { type CursorMeta, persistedPresetColumn, type TrackPresetName } from "./tracks.ts";
export type { TrackPresetName } from "./tracks.ts";

// deno-lint-ignore no-explicit-any
export type SupabaseLike = any;

export function parseBooleanEnv(raw: string | undefined, fallback: boolean): boolean {
  if (!raw) return fallback;
  const normalized = raw.trim().toLowerCase();
  if (["1", "true", "yes", "on"].includes(normalized)) return true;
  if (["0", "false", "no", "off"].includes(normalized)) return false;
  return fallback;
}

export function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export type ImportLockResult =
  | { status: "acquired" }
  | { status: "busy" }
  | { status: "unavailable"; reason: string };

function lockFailureReason(value: unknown): string {
  if (typeof value === "string" && value.trim()) return value.trim();
  if (value instanceof Error && value.message.trim()) return value.message;
  if (value && typeof value === "object" && "message" in value) {
    const message = (value as { message: unknown }).message;
    if (typeof message === "string" && message.trim()) return message.trim();
  }
  return "lock_unavailable";
}

export async function acquireImportLock(supabase: SupabaseLike, key: string, ttlSeconds: number): Promise<ImportLockResult> {
  try {
    const { data, error } = await supabase.rpc('acquire_import_lock', { p_key: key, p_ttl_seconds: ttlSeconds });
    if (error) {
      console.error('Acquire lock error:', error);
      return { status: "unavailable", reason: lockFailureReason(error) };
    }
    if (data === true) return { status: "acquired" };
    return { status: "busy" };
  } catch (e) {
    console.error('Acquire lock exception:', e);
    return { status: "unavailable", reason: lockFailureReason(e) };
  }
}

// Busy preserves the locked skip. Unavailable reports the RPC/throw reason and
// leaves the cursor on the previous page. Neither outcome acquired the lock.
export async function finishUnacquiredLock(
  supabase: SupabaseLike,
  args: {
    mediaType: string;
    trackKey: string | null;
    trackPreset: TrackPresetName;
    useCursor: boolean;
    lastPage: number;
    runId: number | null;
    results: unknown;
    startedAtMs: number;
    lock: ImportLockResult;
    cursor?: CursorMeta | null;
  }
): Promise<Response> {
  const unavailable = args.lock.status === "unavailable";
  const message = args.lock.status === "unavailable" ? args.lock.reason : "locked";
  const runStatus = unavailable ? "error" : "skipped";
  if (args.useCursor) {
    await writeTrackedCursorState(supabase, {
      mediaType: args.mediaType,
      trackKey: args.trackKey,
      trackPreset: args.trackPreset,
      lastPage: args.lastPage,
      status: runStatus,
      visibility: "paused",
      results: args.results,
      message,
      cursor: args.cursor ?? null,
    });
  }
  await finishImportRun(supabase, args.runId, runStatus, args.results, message, args.startedAtMs);
  const body = args.lock.status === "unavailable"
    ? { success: false, skipped: true, reason: "lock_unavailable", error: args.lock.reason, results: args.results }
    : { success: true, skipped: true, reason: "locked", results: args.results };
  return new Response(JSON.stringify(body), {
    status: args.lock.status === "unavailable" ? 500 : 200,
    headers: { "Content-Type": "application/json" },
  });
}

export async function releaseImportLock(supabase: SupabaseLike, key: string): Promise<void> {
  try {
    const { error } = await supabase.rpc('release_import_lock', { p_key: key });
    if (error) console.error('Release lock error:', error);
  } catch (e) {
    console.error('Release lock exception:', e);
  }
}

export async function startImportRun(supabase: SupabaseLike, mediaType: string, runType: string, payload: unknown): Promise<number | null> {
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

export async function finishImportRun(
  supabase: SupabaseLike,
  runId: number | null,
  status: string,
  results: unknown,
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

/**
 * Tracked cursor: last_page plus the query cursor stored in last_results.cursor. Null when the
 * row is missing or unreadable (the run then starts a fresh sweep / page 1).
 */
export async function readTrackedCursorState(
  supabase: SupabaseLike,
  trackKey: string,
): Promise<{ lastPage: number; cursor: CursorMeta | null } | null> {
  try {
    const { data, error } = await supabase
      .from('import_track_state')
      .select('last_page, last_results')
      .eq('track_key', trackKey)
      .maybeSingle();
    if (!error && data && typeof data.last_page === 'number') {
      const raw = data.last_results?.cursor;
      const cursor = raw && typeof raw === 'object' && typeof raw.query_version === 'string' ? raw as CursorMeta : null;
      return { lastPage: data.last_page, cursor };
    }
  } catch (e) {
    console.error('import_track_state read error:', e);
  }
  return null;
}

export async function writeTrackedCursorState(
  supabase: SupabaseLike,
  args: {
    mediaType: string;
    trackKey: string | null;
    trackPreset: TrackPresetName;
    lastPage: number;
    status: string;
    visibility: string;
    results: unknown;
    message: string | null;
    /** Query cursor kept next to last_page (tracked runs only). */
    cursor?: CursorMeta | null;
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
    track_preset: persistedPresetColumn(args.trackPreset),
    last_page: args.lastPage,
    state: args.status,
    visibility: args.visibility,
    last_run_at: updatedAt,
    last_message: args.message,
    last_results: { ...((args.results ?? {}) as Record<string, unknown>), cursor: args.cursor ?? null },
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

  // The legacy per-medium cursor belongs to untracked runs only. A tracked run (with its own
  // query and sort) must not overwrite it, or an untracked run would resume a foreign cursor.
  if (trackPayload) return;
  try {
    const { error } = await supabase
      .from('import_state')
      .upsert(legacyPayload, { onConflict: 'media_type' });
    if (error) console.error('import_state upsert error:', error);
  } catch (e) {
    console.error('import_state upsert exception:', e);
  }
}
