// Catalog / cache boundary of concierge-recommend (F51, 2026-10-05): every read and write of a
// recommendation run besides auth, the rate-limit gate and narration budgets. Queries are moved
// verbatim from the former index.ts closures and run over the caller's own supabase-js client
// (RLS applies; the user id is the verified JWT user, never the body). No remote imports.
//
// Error contract per read (unchanged):
//   - premiumCandidates and mediaContext THROW on a database error (the rail builder then falls back or
//     the candidate rail is dropped; an error on the primary rail fails the request with 500);
//   - every other read degrades: config/tag boosts -> null/[], tag mapping/similar ids/top genres -> [],
//     curated cards -> the RPC `data` as returned, flag -> false, cache -> miss;
//   - cache save and run logs are best-effort (errors swallowed).
// `ragSeed` asks concierge-retrieve-assist (only behind rag_assist_v1) with the caller's Authorization
// header and a 5 s abort; a non-2xx, malformed or low-score answer is "no seed".
import type { MediaType, SeedOverride } from "./router.ts";
import { type CandidateRow, emptyMediaContext, type MediaContext, type RouterDecision, stableBucket } from "./rail_policy.ts";
import { uniq } from "./router.ts";

/** Supabase-js client bound to one request's Authorization header (structurally untyped). */
// deno-lint-ignore no-explicit-any
export type SupabaseLike = any;
// deno-lint-ignore no-explicit-any
type Row = any;

export type RagSeedQuery = {
  query: string;
  locale: "de" | "en";
  mediaType: MediaType | null;
  excludedGenres: string[];
  format: string | null;
  yearMin: number | null;
  yearMax: number | null;
};
export type RagSeed = SeedOverride & { entityId: string | null };

export interface CatalogRepository {
  conciergeConfig(): Promise<Row>;
  /** AniList tag ids -> internal tag ids (no query for an empty list). */
  tagIdsForAnilistIds(anilistIds: number[]): Promise<number[]>;
  editorialTagBoosts(): Promise<Row[] | null>;
  featureFlagEnabled(flagName: string, userId: string, market: string): Promise<boolean>;
  /** The caller's five most frequent list genres (Hentai/Ecchi/Kids ignored). */
  userTopGenres(userId: string): Promise<string[]>;
  loadModeCache(userId: string, promptNorm: string, ttlDays: number): Promise<RouterDecision | null>;
  saveModeCache(userId: string, promptNorm: string, dec: RouterDecision, ttlDays: number): Promise<void>;
  searchTitles(query: string | null, mt: MediaType, limit: number): PromiseLike<{ data: Row; error: Row }>;
  premiumCandidates(mt: MediaType, categories: string[] | null, allowGimmicks: boolean, focusTagIds: number[]): Promise<CandidateRow[]>;
  similarCandidates(mt: MediaType, seedId: number, allowGimmicks: boolean): Promise<CandidateRow[]>;
  mediaContext(mt: MediaType, idList: number[], tagBoostByTag: Map<number, Row>): Promise<MediaContext>;
  curatedRailCards(railId: string, limit: number): Promise<Row>;
  ragSeed(q: RagSeedQuery): Promise<RagSeed | null>;
  logRecommendRun(args: { inputChars: number; itemsCount: number; secondaryItemsCount: number; routerTelemetry: string }): Promise<void>;
}

export type CatalogRepositoryDeps = {
  client: SupabaseLike;
  /** SUPABASE_URL (for the retrieve-assist function URL). */
  supabaseUrl: string;
  authHeader: string;
  fetch: (url: string, init: RequestInit) => Promise<Response>;
  now: () => number;
};

export function supabaseCatalogRepository(deps: CatalogRepositoryDeps): CatalogRepository {
  const { client } = deps;
  return {
    async conciergeConfig() {
      const { data } = await client.rpc("get_concierge_config");
      return data;
    },

    async tagIdsForAnilistIds(anilistIds) {
      const ids = uniq(anilistIds).filter((x) => Number.isFinite(x) && x > 0);
      if (!ids.length) return [];
      const { data, error } = await client.from("tags").select("id,anilist_id").in("anilist_id", ids);
      if (error || !Array.isArray(data)) return [];
      return uniq(data.map((r: Row) => Number(r.id)).filter((x: number) => Number.isFinite(x) && x > 0));
    },

    async editorialTagBoosts() {
      const { data } = await client.from("editorial_tag_boosts").select("tag_id,boost,reason");
      return data;
    },

    async featureFlagEnabled(flagName, userId, market) {
      try {
        const { data, error } = await client
          .from("feature_flags")
          .select("enabled,rollout_percentage,target_markets")
          .eq("flag_name", flagName)
          .maybeSingle();
        if (error || !data) return false;

        const enabled = Boolean(data.enabled);
        if (!enabled) return false;

        const targetMarkets = Array.isArray(data.target_markets) ? data.target_markets.map((x: Row) => String(x).toUpperCase()) : [];
        if (targetMarkets.length > 0 && !targetMarkets.includes("*") && !targetMarkets.includes(market.toUpperCase())) {
          return false;
        }

        const rollout = Number(data.rollout_percentage ?? 0);
        if (!Number.isFinite(rollout) || rollout <= 0) return false;
        if (rollout >= 100) return true;

        const bucket = stableBucket(`${userId}:${flagName}`);
        return bucket < rollout;
      } catch {
        return false;
      }
    },

    async userTopGenres(userId) {
      try {
        const { data: ul, error: ulErr } = await client
          .from("user_lists")
          .select("media_type,media_id")
          .eq("user_id", userId)
          .limit(120);
        if (ulErr || !Array.isArray(ul) || ul.length === 0) return [];

        const animeIds = ul.filter((r: Row) => String(r.media_type ?? "").toLowerCase() === "anime").map((r: Row) => Number(r.media_id)).filter((x: number) => Number.isFinite(x) && x > 0).slice(0, 80);
        const mangaIds = ul.filter((r: Row) => String(r.media_type ?? "").toLowerCase() === "manga").map((r: Row) => Number(r.media_id)).filter((x: number) => Number.isFinite(x) && x > 0).slice(0, 80);

        const [aRes, mRes] = await Promise.all([
          animeIds.length ? client.from("anime").select("id,genres").in("id", animeIds) : Promise.resolve({ data: [] as Row[], error: null }),
          mangaIds.length ? client.from("manga").select("id,genres").in("id", mangaIds) : Promise.resolve({ data: [] as Row[], error: null }),
        ]);

        const counts = new Map<string, number>();
        const bump = (g: string) => counts.set(g, (counts.get(g) ?? 0) + 1);
        const ingest = (rows: Row[]) => {
          for (const r of rows) {
            const gs = Array.isArray(r?.genres) ? r.genres.map((x: Row) => String(x)) : [];
            for (const g of gs) {
              if (!g) continue;
              if (g === "Hentai" || g === "Ecchi" || g === "Kids") continue;
              bump(g);
            }
          }
        };

        if (Array.isArray(aRes.data)) ingest(aRes.data);
        if (Array.isArray(mRes.data)) ingest(mRes.data);

        return Array.from(counts.entries())
          .sort((a, b) => b[1] - a[1])
          .map(([g]) => g)
          .slice(0, 5);
      } catch {
        return [];
      }
    },

    async loadModeCache(userId, promptNorm, ttlDays) {
      if (!ttlDays || ttlDays <= 0) return null;
      const { data, error } = await client
        .from("concierge_mode_cache")
        .select("primary_mode_id,secondary_mode_id,used_llm,updated_at")
        .eq("user_id", userId)
        .eq("prompt_norm", promptNorm)
        .maybeSingle();
      if (error || !data) return null;
      const updatedAt = Date.parse(String(data.updated_at ?? ""));
      if (!Number.isFinite(updatedAt)) return null;
      const ageDays = (deps.now() - updatedAt) / (1000 * 60 * 60 * 24);
      if (ageDays > ttlDays) return null;
      const primaryId = String(data.primary_mode_id ?? "").trim();
      const secondaryId = String(data.secondary_mode_id ?? "").trim();
      if (!primaryId || !secondaryId) return null;
      return {
        primaryId,
        secondaryId,
        secondaryCandidates: [secondaryId],
        primaryConfidence: 0.75,
        primaryReason: "cache",
        usedLLM: Boolean(data.used_llm ?? false),
        topScore: 999,
      };
    },

    async saveModeCache(userId, promptNorm, dec, ttlDays) {
      if (!ttlDays || ttlDays <= 0) return;
      try {
        await client
          .from("concierge_mode_cache")
          .upsert(
            {
              user_id: userId,
              prompt_norm: promptNorm,
              primary_mode_id: dec.primaryId,
              secondary_mode_id: dec.secondaryId,
              used_llm: dec.usedLLM,
            },
            { onConflict: "user_id,prompt_norm" },
          );
      } catch {
        // best-effort
      }
    },

    searchTitles(query, mt, limit) {
      return client.rpc("search_titles", { p_query: query, p_media_type: mt, p_limit: limit });
    },

    async premiumCandidates(mt, pCategories, allowGimmicks, focusTagIds) {
      const { data: ids, error } = await client.rpc("recommend_ids_premium", {
        p_media_type: mt,
        p_categories: pCategories && pCategories.length ? pCategories : null,
        p_limit: 50,
        p_allow_gimmicks: allowGimmicks,
        p_focus_tag_ids: focusTagIds.length ? focusTagIds : null,
      });
      if (error) throw error;
      const rows = Array.isArray(ids) ? ids : [];
      return rows.map((r: Row) => ({
        media_id: Number(r.media_id),
        match_count: r.match_count ?? r.overlap_count ?? 0,
        score: r.score ?? null,
      }));
    },

    async similarCandidates(mt, seedId, allowGimmicks) {
      const { data: sim, error: simErr } = await client.rpc("recommend_ids_similar_to_seeds", {
        p_media_type: mt,
        p_seed_ids: [seedId],
        p_limit: 50,
        p_allow_gimmicks: allowGimmicks,
      });
      if (simErr || !Array.isArray(sim)) return [] as CandidateRow[];
      return sim.map((r: Row) => ({
        media_id: Number(r.media_id),
        match_count: r.overlap_count ?? r.match_count ?? 0,
        score: r.score ?? null,
      }));
    },

    async mediaContext(mt, idList, tagBoostByTag) {
      const ids = uniq(idList).filter((x) => Number.isFinite(x) && x > 0);
      if (ids.length === 0) return emptyMediaContext();
      const boostTagIds = Array.from(tagBoostByTag.keys());

      const table = mt === "ANIME" ? "anime" : "manga";
      const linkTable = mt === "ANIME" ? "anime_tags" : "manga_tags";
      const idCol = mt === "ANIME" ? "anime_id" : "manga_id";
      const mediaSelect = mt === "ANIME"
        ? "id,title_english,title_romaji,title_native,cover_image_medium,average_score,popularity,start_date_year,format,status,site_url,is_adult,genres,episodes"
        : "id,title_english,title_romaji,title_native,cover_image_medium,average_score,popularity,start_date_year,format,status,site_url,is_adult,genres,chapters";

      // All three queries depend only on `ids` — run in parallel.
      const [mediaRes, boostsRes, tagLinksRes] = await Promise.all([
        client
          .from(table)
          .select(mediaSelect)
          .in("id", ids),
        client
          .from("editorial_boosts")
          .select("media_id,label,weight")
          .eq("media_type", mt)
          .in("media_id", ids),
        boostTagIds.length > 0
          ? client
            .from(linkTable)
            .select(`${idCol},tag_id`)
            .in(idCol, ids)
            .in("tag_id", boostTagIds)
          : Promise.resolve({ data: [] as Row[], error: null }),
      ]);

      if (mediaRes.error) throw mediaRes.error;
      const rows = Array.isArray(mediaRes.data) ? mediaRes.data : [];
      const normalizedRows = rows.map((r: Row) => {
        if (mt === "MANGA" && r?.episodes == null && r?.chapters != null) {
          r.episodes = r.chapters;
        }
        return r;
      });
      const byId = new Map<number, Row>(normalizedRows.map((r: Row) => [r.id, r]));
      const boostById = new Map<number, Row>((boostsRes.data ?? []).map((b: Row) => [b.media_id, b]));
      const tagLinks = !tagLinksRes.error ? (tagLinksRes.data ?? []) : [];

      const boostedReasonsById = new Map<number, string[]>();
      for (const row of tagLinks) {
        const mediaId = Number(row[idCol]);
        const tagId = Number(row.tag_id);
        const tb = tagBoostByTag.get(tagId);
        const reason = String(tb?.reason ?? "").trim();
        if (!reason) continue;
        const arr = boostedReasonsById.get(mediaId) ?? [];
        if (!arr.includes(reason)) arr.push(reason);
        boostedReasonsById.set(mediaId, arr);
      }

      return { byId, boostById, boostedReasonsById };
    },

    curatedRailCards(railId, limit) {
      return client.rpc("curated_rail_cards", { p_rail_id: railId, p_limit: limit, p_exclude_seen: true }).then((r: Row) => r.data);
    },

    async ragSeed(q) {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 5000);
      try {
        const ragUrl = `${deps.supabaseUrl}/functions/v1/concierge-retrieve-assist`;
        const res = await deps.fetch(ragUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            ...(deps.authHeader ? { Authorization: deps.authHeader } : {}),
          },
          body: JSON.stringify({
            query: q.query,
            locale: q.locale,
            media_type: q.mediaType,
            excluded_genres: q.excludedGenres,
            format: q.format,
            year_min: q.yearMin,
            year_max: q.yearMax,
          }),
          signal: controller.signal,
        });
        if (!res.ok) return null;
        const payload = await res.json().catch(() => null);
        const candidates = Array.isArray(payload?.entity_candidates) ? payload.entity_candidates : [];
        const top = candidates[0];
        if (!top) return null;

        const mt = String(top.media_type ?? "").toUpperCase();
        const mediaId = Number(top.anilist_id ?? 0);
        const score = Number(top.score ?? 0);
        const title = String(top.title ?? "").trim();
        const entityId = typeof top.entity_id === "string" ? top.entity_id : null;
        if (!Number.isSafeInteger(mediaId) || mediaId <= 0) return null;
        if (!Number.isFinite(score) || score < 0.45) return null;
        if (mt !== "ANIME" && mt !== "MANGA") return null;
        if (q.mediaType !== null && mt !== q.mediaType) return null;
        return { mt, mediaId, title: title || q.query, entityId };
      } catch {
        return null;
      } finally {
        clearTimeout(timeout);
      }
    },

    async logRecommendRun(args) {
      try {
        await client.rpc("log_concierge_run", {
          p_kind: "recommend",
          p_status: "success",
          p_input_chars: args.inputChars,
          p_items_count: args.itemsCount,
        });

        // Router quality telemetry for secondary-rail diversity and overlap monitoring.
        await client.rpc("log_concierge_run", {
          p_kind: "recommend_router_v2",
          p_status: "success",
          p_input_chars: args.inputChars,
          p_items_count: args.secondaryItemsCount,
          p_error: args.routerTelemetry,
        });
      } catch {
        // best-effort
      }
    },
  };
}
