// Retrieve-assist run. index.ts has already authenticated and rate-limited.
// Pure helpers + the cache/RPC steps live here so Deno tests can call `runRetrieveAssist`
// with injected clients. RPC failures keep the graceful empty response but are not cached.
import { normalizeForSearch } from "../_shared/normalization.ts";

export type MediaType = "ANIME" | "MANGA";

export type Constraints = {
  excluded_genres?: string[];
  format?: string | null;
  year_min?: number | null;
  year_max?: number | null;
};

export type EntityCandidate = {
  entity_id: string;
  anilist_id: number;
  media_type: MediaType;
  title: string;
  year: number | null;
  score: number;
  why: string[];
};

export type RetrieveResponse = {
  confidence: number;
  entity_candidates: EntityCandidate[];
  mode_hints: { mode_id: string; score: number; why: string[] }[];
  constraint_hints: Record<string, unknown>;
  needs_clarification: boolean;
  clarify_kind: string | null;
  source_version: string;
};

export const SOURCE_VERSION = "rag-v2";
export const CACHE_TTL_MS = 60 * 60 * 1000;
export const MIN_CONFIDENCE_THRESHOLD = 0.3;
export const MAX_CANDIDATES = 10;

/** Strip common LLM prompt-injection patterns from user-supplied text. */
export function sanitizeInput(text: string): string {
  return text
    .replace(
      /\b(ignore|disregard|forget)\s+(all\s+)?(previous|above|prior)\s+(instructions?|prompts?|rules?|context)/gi,
      "[filtered]",
    )
    .replace(
      /\b(you\s+are\s+now|new\s+instructions?|system\s*:)/gi,
      "[filtered]",
    )
    .replace(
      /\b(act\s+as|pretend\s+(to\s+be|you\s+are)|role\s*play)/gi,
      "[filtered]",
    )
    .replace(/```[\s\S]*?```/g, "")
    .replace(/<[^>]+>/g, "")
    .slice(0, 2000)
    .trim();
}

/**
 * Include source version and media scope so old or differently scoped answers cannot be reused.
 * Uses FNV-1a 32-bit hash for fast, low-collision key generation.
 */
export function generateCacheKey(
  normalizedQuery: string,
  locale: string,
  constraints: Constraints,
  mediaType: MediaType | null = null,
): string {
  const constraintsStr = JSON.stringify(
    constraints,
    Object.keys(constraints).sort(),
  );
  const scope = mediaType ?? "BOTH";
  const raw = JSON.stringify([
    SOURCE_VERSION,
    scope,
    normalizedQuery,
    locale,
    constraintsStr,
  ]);
  let hash = 0x811c9dc5;
  for (let i = 0; i < raw.length; i++) {
    hash ^= raw.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return `rag:${SOURCE_VERSION}:${scope}:${
    (hash >>> 0).toString(16).padStart(8, "0")
  }:${normalizedQuery.slice(0, 40)}`;
}

type RetrievalRow = {
  entity_id: string;
  anilist_id: number;
  media_type: MediaType;
  canonical_title: string;
  year?: number | null;
  final_score: number;
  popularity?: number | null;
  match_source?: string;
};

function validRow(
  row: unknown,
  mediaType: MediaType | null,
): row is RetrievalRow {
  if (!row || typeof row !== "object") return false;
  const r = row as Record<string, unknown>;
  return typeof r.entity_id === "string" && r.entity_id.length > 0 &&
    typeof r.anilist_id === "number" && Number.isInteger(r.anilist_id) &&
    r.anilist_id > 0 &&
    (r.media_type === "ANIME" || r.media_type === "MANGA") &&
    (mediaType === null || r.media_type === mediaType) &&
    typeof r.canonical_title === "string" &&
    r.canonical_title.trim().length > 0 &&
    typeof r.final_score === "number" && Number.isFinite(r.final_score);
}

export function serializeConstraints(constraints: Constraints): string {
  return JSON.stringify(constraints, Object.keys(constraints).sort());
}

function json(res: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(res), {
    ...init,
    headers: { "Content-Type": "application/json", ...(init.headers ?? {}) },
  });
}

/** Supabase-js client (structurally untyped, as before). */
// deno-lint-ignore no-explicit-any
export type SupabaseLike = any;

export type RetrieveDeps = {
  serviceClient: SupabaseLike;
};

export async function runRetrieveAssist(
  body: Record<string, unknown>,
  deps: RetrieveDeps,
): Promise<Response> {
  const rawQuery = typeof body.query === "string" ? body.query : "";
  const locale = typeof body.locale === "string" ? body.locale : "en";
  const mediaType: MediaType | null =
    body.media_type === "ANIME" || body.media_type === "MANGA"
      ? (body.media_type as MediaType)
      : null;

  if (!rawQuery || rawQuery.length === 0) {
    return json({ error: "query is required" }, { status: 400 });
  }

  if (rawQuery.length > 500) {
    return json({ error: "query too long (max 500 chars)" }, { status: 400 });
  }

  const sanitized = sanitizeInput(rawQuery);
  const normalizedQuery = normalizeForSearch(sanitized, locale);

  if (!normalizedQuery) {
    return json(
      {
        confidence: 0,
        entity_candidates: [],
        mode_hints: [],
        constraint_hints: {},
        needs_clarification: true,
        clarify_kind: "empty_query",
        source_version: SOURCE_VERSION,
      } satisfies RetrieveResponse,
    );
  }

  const constraints: Constraints = {};
  if (Array.isArray(body.excluded_genres)) {
    constraints.excluded_genres = (body.excluded_genres as unknown[])
      .filter((g): g is string => typeof g === "string")
      .map((g) => g.trim())
      .filter(Boolean);
  }
  if (typeof body.format === "string" && body.format) {
    const fmt = body.format.toUpperCase();
    if (fmt === "MOVIE" || fmt === "ONA" || fmt === "OVA") {
      constraints.format = fmt;
    }
  }
  if (typeof body.year_min === "number" && Number.isFinite(body.year_min)) {
    constraints.year_min = body.year_min;
  }
  if (typeof body.year_max === "number" && Number.isFinite(body.year_max)) {
    constraints.year_max = body.year_max;
  }

  const cacheKey = generateCacheKey(
    normalizedQuery,
    locale,
    constraints,
    mediaType,
  );
  const serviceClient = deps.serviceClient;

  try {
    const { data: cached } = await serviceClient
      .from("rag_retrieval_cache")
      .select("result_json, config_version, expires_at")
      .eq("cache_key", cacheKey)
      .gt("expires_at", new Date().toISOString())
      .eq("config_version", SOURCE_VERSION)
      .maybeSingle();

    if (cached?.result_json) {
      return json(cached.result_json);
    }
  } catch {
    // Cache miss or error — proceed with retrieval
  }

  const normalizedExcludedGenres = (constraints.excluded_genres ?? []).map((
    g,
  ) => normalizeForSearch(g, "en"));

  let candidates: EntityCandidate[] = [];
  let retrievalSucceeded = false;

  try {
    const { data: rows, error } = await serviceClient.rpc(
      "rag_retrieve_candidates",
      {
        p_query: normalizedQuery,
        p_media_type: mediaType,
        p_year_min: constraints.year_min ?? null,
        p_year_max: constraints.year_max ?? null,
        p_format: constraints.format ?? null,
        p_excluded_genres: normalizedExcludedGenres,
        p_limit: MAX_CANDIDATES,
      },
    );

    if (error) {
      // Return empty on retrieval error — never fabricate results
    } else if (
      Array.isArray(rows) && rows.every((row) => validRow(row, mediaType))
    ) {
      // An empty successful result is cacheable; an error or malformed payload is not.
      retrievalSucceeded = true;
      candidates = rows.map(
        (row: RetrievalRow) => ({
          entity_id: row.entity_id,
          anilist_id: row.anilist_id,
          media_type: row.media_type as MediaType,
          title: row.canonical_title,
          year: row.year ?? null,
          score: typeof row.final_score === "number"
            ? Math.round(row.final_score * 1000) / 1000
            : 0,
          why: [
            row.match_source === "alias" ? "alias match" : "title match",
            ...(row.popularity ? [`popularity: ${row.popularity}`] : []),
          ],
        }),
      );
    }
  } catch {
    // If RPC fails, candidates stays empty — never fabricate
  }

  const topScore = candidates.length > 0 ? candidates[0].score : 0;
  const confidence = Math.min(1, topScore);
  const needsClarification = topScore < MIN_CONFIDENCE_THRESHOLD ||
    candidates.length === 0;

  const response: RetrieveResponse = {
    confidence,
    entity_candidates: candidates,
    mode_hints: [],
    constraint_hints: {},
    needs_clarification: needsClarification,
    clarify_kind: needsClarification ? "low_confidence" : null,
    source_version: SOURCE_VERSION,
  };

  if (!retrievalSucceeded) return json(response);

  try {
    const expiresAt = new Date(Date.now() + CACHE_TTL_MS).toISOString();
    await serviceClient.from("rag_retrieval_cache").upsert({
      cache_key: cacheKey,
      query: sanitized,
      normalized_query: normalizedQuery,
      locale,
      constraints_hash: serializeConstraints(constraints),
      result_json: response,
      config_version: SOURCE_VERSION,
      expires_at: expiresAt,
    });
  } catch {
    // best-effort caching
  }

  return json(response);
}
