// Data boundary of mirror-images (F66, 2026-10-05): every catalog / priority-queue / report / lock
// read and write of a mirror run goes through `MirrorRepository`. `createMirrorRepository` binds it to
// a service-role supabase-js client; the queries are moved verbatim from the former index.ts closure.
// No remote imports (index.ts owns supabase-js).
//
// Error contract (unchanged from the former index.ts):
//   - remoteWindow THROWS on a database error (the run then ends as `error`, HTTP 500);
//   - pendingPriority / liveRows return [] on error (logged), so a broken queue never fails a sweep;
//   - updateCatalogRow RETURNS its error (the run decides what the report says);
//   - startRun / finishRun / recordState / clearPriority are best-effort (errors logged, swallowed);
//   - acquireLock maps an RPC error or exception to "unavailable" (the run proceeds, fail-open as
//     before) and never to "acquired": only a lock this run actually took is released.

export type MediaType = "ANIME" | "MANGA" | "CHARACTER" | "STAFF";
export const MEDIA_TYPES: readonly MediaType[] = ["ANIME", "MANGA", "CHARACTER", "STAFF"];

export type MirrorState = "mirrored" | "skipped" | "failed";
export type MirrorVisibility = "public" | "remote" | "hidden";

/** Image columns a mirror run may read and rewrite, per media type (also the priority-queue asset keys). */
export const ASSET_KEYS: Record<MediaType, readonly string[]> = {
  ANIME: ["cover_image_large", "cover_image_medium", "banner_image"],
  MANGA: ["cover_image_large", "cover_image_medium", "banner_image"],
  CHARACTER: ["image_large"],
  STAFF: ["image_large"],
};

export function tableFor(mediaType: MediaType): string {
  switch (mediaType) {
    case "ANIME": return "anime";
    case "MANGA": return "manga";
    case "CHARACTER": return "characters";
    case "STAFF": return "staff";
  }
}

export type MirrorStateInput = {
  mediaType: MediaType;
  mediaId: number;
  assetKey: string;
  sourceUrl: string | null;
  mirroredUrl: string | null;
  state: MirrorState;
  visibility: MirrorVisibility;
  message?: string | null;
  details?: Record<string, unknown>;
};

export type PendingPriority = { media_type: MediaType; media_id: number; asset_key: string };
/** A catalog row: `id` plus the image columns of its media type. */
export type CatalogRow = { id: number } & Record<string, unknown>;
export type LockOutcome = "acquired" | "busy" | "unavailable";
export type DbError = { message: string; code?: string } | null;

export interface MirrorRepository {
  startRun(payload: unknown, startedAtIso: string): Promise<number | null>;
  finishRun(runId: number | null, status: string, results: Record<string, number>, message: string | null, finishedAtIso: string, durationMs: number): Promise<void>;
  acquireLock(key: string, ttlSeconds: number): Promise<LockOutcome>;
  releaseLock(key: string): Promise<void>;
  /** Oldest rows flagged by `enqueue_image_mirror` (mirror-on-view), at most `limit`. */
  pendingPriority(limit: number): Promise<PendingPriority[]>;
  /** Current image columns of the given ids. */
  liveRows(mediaType: MediaType, ids: number[]): Promise<CatalogRow[]>;
  /** The cursor window: remote-only rows (large cover / image not on our Storage), visibility-ordered. */
  remoteWindow(mediaType: MediaType, offset: number, limit: number): Promise<CatalogRow[]>;
  updateCatalogRow(mediaType: MediaType, id: number, updates: Record<string, string>): Promise<{ error: DbError }>;
  clearPriority(mediaType: MediaType, mediaId: number, assetKey: string, nowIso: string): Promise<void>;
  recordState(input: MirrorStateInput, bucket: string, nowIso: string): Promise<void>;
}

/** Supabase-js client (structurally untyped, as before). */
// deno-lint-ignore no-explicit-any
export type SupabaseLike = any;

export function createMirrorRepository(supabase: SupabaseLike): MirrorRepository {
  return {
    async startRun(payload, startedAtIso) {
      try {
        const { data, error } = await supabase
          .from("mirror_runs")
          .insert({ payload, status: "running", started_at: startedAtIso })
          .select("id")
          .single();
        if (error) {
          console.error("mirror_runs insert error:", error);
          return null;
        }
        return data?.id ?? null;
      } catch (e) {
        console.error("mirror_runs insert exception:", e);
        return null;
      }
    },

    async finishRun(runId, status, results, message, finishedAtIso, durationMs) {
      if (!runId) return;
      try {
        const { error } = await supabase
          .from("mirror_runs")
          .update({ status, results, message, finished_at: finishedAtIso, duration_ms: durationMs })
          .eq("id", runId);
        if (error) console.error("mirror_runs update error:", error);
      } catch (e) {
        console.error("mirror_runs update exception:", e);
      }
    },

    async acquireLock(key, ttlSeconds) {
      try {
        const { data, error } = await supabase.rpc("acquire_import_lock", { p_key: key, p_ttl_seconds: ttlSeconds });
        if (error) {
          console.error("Acquire lock error:", error);
          return "unavailable";
        }
        return data === true ? "acquired" : "busy";
      } catch (e) {
        console.error("Acquire lock exception:", e);
        return "unavailable";
      }
    },

    async releaseLock(key) {
      try {
        const { error } = await supabase.rpc("release_import_lock", { p_key: key });
        if (error) console.error("Release lock error:", error);
      } catch (e) {
        console.error("Release lock exception:", e);
      }
    },

    async pendingPriority(limit) {
      const { data, error } = await supabase
        .from("image_mirror_state")
        .select("media_type, media_id, asset_key")
        .not("priority_at", "is", null)
        .order("priority_at", { ascending: true })
        .limit(limit);
      if (error) {
        console.error("priority drain select error:", error);
        return [];
      }
      return (data ?? []) as PendingPriority[];
    },

    async liveRows(mediaType, ids) {
      const query = (mediaType === "ANIME" || mediaType === "MANGA")
        ? supabase.from(tableFor(mediaType)).select("id, cover_image_large, cover_image_medium, banner_image")
        : supabase.from(tableFor(mediaType)).select("id, image_large");
      const { data, error } = await query.in("id", ids);
      if (error) {
        console.error(`priority drain live fetch error (${mediaType}):`, error);
        return [];
      }
      return (data ?? []) as CatalogRow[];
    },

    async remoteWindow(mediaType, offset, limit) {
      // In this schema, `id` is the AniList id (no separate `anilist_id` column).
      const query = mediaType === "ANIME" || mediaType === "MANGA"
        ? supabase
          .from(tableFor(mediaType))
          .select("id, cover_image_large, cover_image_medium, banner_image")
          // Remote-only: rows already on our Storage CDN are out of the window.
          .not("cover_image_large", "like", "%/storage/v1/%")
          .order("popularity", { ascending: false })
        : supabase
          .from(mediaType === "CHARACTER" ? "image_mirror_character_candidates" : "image_mirror_staff_candidates")
          // Visibility-ordered (catalog join count) + remote-only, via the service_role view.
          .select("id, image_large")
          .not("image_large", "like", "%/storage/v1/%")
          .order("visibility_count", { ascending: false });
      const { data, error } = await query.range(offset, offset + limit - 1);
      if (error) throw error;
      return (data ?? []) as CatalogRow[];
    },

    async updateCatalogRow(mediaType, id, updates) {
      const { error } = await supabase.from(tableFor(mediaType)).update(updates).eq("id", id);
      return { error: error ?? null };
    },

    async clearPriority(mediaType, mediaId, assetKey, nowIso) {
      const { error } = await supabase
        .from("image_mirror_state")
        .update({ priority_at: null, updated_at: nowIso })
        .eq("media_type", mediaType)
        .eq("media_id", mediaId)
        .eq("asset_key", assetKey);
      if (error) console.error("priority_at clear error:", error);
    },

    async recordState(input, bucket, nowIso) {
      try {
        const { error } = await supabase.from("image_mirror_state").upsert({
          media_type: input.mediaType,
          media_id: input.mediaId,
          asset_key: input.assetKey,
          source_url: input.sourceUrl,
          mirrored_url: input.mirroredUrl,
          state: input.state,
          visibility: input.visibility,
          last_run_at: nowIso,
          last_message: input.message ?? null,
          details: {
            ...(input.details ?? {}),
            bucket,
          },
          updated_at: nowIso,
        }, { onConflict: "media_type,media_id,asset_key" });
        if (error) console.error("image_mirror_state upsert error:", error);
      } catch (e) {
        console.error("image_mirror_state upsert exception:", e);
      }
    },
  };
}
