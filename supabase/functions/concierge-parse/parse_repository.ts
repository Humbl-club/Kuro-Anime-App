// Data boundary of concierge-parse (F51): every read/write the parse run makes besides auth and the
// rate-limit gate goes through this interface, over the caller's own supabase-js client (RLS applies;
// user ids come from the verified JWT, never from the body). No remote imports: index.ts owns
// supabase-js. Error policy is the repository's contract, unchanged from the former index.ts:
//   - searchTitles returns `{ rows, error }` (the handler reports the first error as candidateError);
//   - findAlias / existingEntry / feedbackConfig return null on any error (best-effort reads);
//   - logParseFeedback / logRun swallow errors (best-effort telemetry, never fail a parse).
import type { MediaType } from "./rules.ts";
import type { AliasTarget, SearchRow } from "./search_plan.ts";

/** Supabase-js client bound to one request's Authorization header (structurally untyped). */
// deno-lint-ignore no-explicit-any
export type SupabaseLike = any;

/** The caller's list row for a candidate, projected for import reconciliation (response `existing_entry`). */
export type ExistingEntry = {
  media_type: "ANIME" | "MANGA";
  media_id: number;
  status: string;
  progress_episodes: number | null;
  progress_chapters: number | null;
  progress_volumes: number | null;
  rating: number | null;
  updated_at: string;
};

export type ParseFeedback = {
  raw: string;
  normalized: string;
  aliasNorm: string;
  bestScore: number | null;
  candidatesCount: number;
  topMediaType: string | null;
  topMediaId: number | null;
};

export interface ParseRepository {
  /** `get_concierge_config()` (the parse_feedback block is read by search_plan.feedbackSettings). */
  feedbackConfig(): Promise<unknown>;
  /**
   * The caller's alias for a line. `keys` are in preference order (aliasLookupKeys: strong key, then the
   * legacy Apply key); a row of an earlier key wins over a later key, then more hits win.
   */
  findAlias(userId: string, keys: string[], mediaType: MediaType | null): Promise<AliasTarget | null>;
  searchTitles(query: string, mediaType: MediaType | null, limit: number): Promise<{ rows: SearchRow[]; error: string | null }>;
  existingEntry(userId: string, mediaType: string, mediaId: number): Promise<ExistingEntry | null>;
  logParseFeedback(feedback: ParseFeedback): Promise<void>;
  logRun(inputChars: number, itemsCount: number): Promise<void>;
}

/** Rows per alias lookup: UNIQUE (user_id, alias_norm, media_type) gives at most keys x 2 media types. */
const ALIAS_ROWS_PER_KEY = 2;

export function supabaseParseRepository(client: SupabaseLike, now: () => Date = () => new Date()): ParseRepository {
  return {
    async feedbackConfig() {
      try {
        const { data } = await client.rpc("get_concierge_config");
        return data ?? null;
      } catch {
        return null; // best-effort
      }
    },

    async findAlias(userId, keys, mediaType) {
      if (keys.length === 0) return null;
      let q = client
        .from("title_aliases")
        .select("alias_norm,media_type,media_id,title_raw,hits")
        .eq("user_id", userId)
        .in("alias_norm", keys);
      if (mediaType) q = q.eq("media_type", mediaType);
      const res = await q.order("hits", { ascending: false }).limit(keys.length * ALIAS_ROWS_PER_KEY);
      if (res.error || !Array.isArray(res.data)) return null;
      // deno-lint-ignore no-explicit-any
      const rows = (res.data as any[]).filter((r) => r?.media_id && r?.media_type && keys.includes(String(r.alias_norm)));
      rows.sort((a, b) => keys.indexOf(String(a.alias_norm)) - keys.indexOf(String(b.alias_norm)) || Number(b.hits ?? 0) - Number(a.hits ?? 0));
      const best = rows[0];
      return best ? { media_type: best.media_type, media_id: best.media_id, title_raw: best.title_raw ?? null } : null;
    },

    async searchTitles(query, mediaType, limit) {
      const res = await client.rpc("search_titles", { p_query: query, p_media_type: mediaType, p_limit: limit });
      if (res.error) return { rows: [], error: res.error.message ?? "search error" };
      return { rows: Array.isArray(res.data) ? res.data : [], error: null };
    },

    async existingEntry(userId, mediaType, mediaId) {
      // user_id in anime_user_lists/manga_user_lists is TEXT, auth.uid() is UUID: cast to text.
      const userIdText = String(userId);
      try {
        if (mediaType === "ANIME") {
          const { data: row } = await client
            .from("anime_user_lists")
            .select("list_type,progress,rating,updated_at")
            .eq("user_id", userIdText)
            .eq("anime_id", mediaId)
            .maybeSingle();
          if (!row) return null;
          return {
            media_type: "ANIME",
            media_id: mediaId,
            status: row.list_type ?? "PLANNING",
            progress_episodes: row.progress ?? null,
            progress_chapters: null,
            progress_volumes: null,
            rating: row.rating ?? null,
            updated_at: row.updated_at ?? now().toISOString(),
          };
        }
        if (mediaType === "MANGA") {
          const { data: row } = await client
            .from("manga_user_lists")
            .select("list_type,progress,rating,updated_at")
            .eq("user_id", userIdText)
            .eq("manga_id", mediaId)
            .maybeSingle();
          if (!row) return null;
          return {
            media_type: "MANGA",
            media_id: mediaId,
            status: row.list_type ?? "PLANNING",
            progress_episodes: null,
            progress_chapters: row.progress ?? null,
            progress_volumes: null,
            rating: row.rating ?? null,
            updated_at: row.updated_at ?? now().toISOString(),
          };
        }
        return null;
      } catch {
        return null; // best-effort: a failed lookup is treated as no existing entry
      }
    },

    async logParseFeedback(f) {
      try {
        await client.rpc("log_concierge_parse_feedback", {
          p_raw: f.raw,
          p_normalized: f.normalized,
          p_alias_norm: f.aliasNorm,
          p_best_score: f.bestScore,
          p_candidates_count: f.candidatesCount,
          p_top_media_type: f.topMediaType,
          p_top_media_id: f.topMediaId,
        });
      } catch {
        // best-effort
      }
    },

    async logRun(inputChars, itemsCount) {
      try {
        await client.rpc("log_concierge_run", {
          p_kind: "parse",
          p_status: "success",
          p_input_chars: inputChars,
          p_items_count: itemsCount,
        });
      } catch {
        // Best-effort metrics only.
      }
    },
  };
}
