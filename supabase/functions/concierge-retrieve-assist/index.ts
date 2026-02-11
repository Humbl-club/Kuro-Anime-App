import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { normalizeForSearch } from "../_shared/normalization.ts";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type MediaType = "ANIME" | "MANGA";

type Constraints = {
  excluded_genres?: string[];
  format?: string | null;
  year_min?: number | null;
  year_max?: number | null;
};

type EntityCandidate = {
  entity_id: string;
  anilist_id: number;
  media_type: MediaType;
  title: string;
  year: number | null;
  score: number;
  why: string[];
};

type RetrieveResponse = {
  confidence: number;
  entity_candidates: EntityCandidate[];
  mode_hints: { mode_id: string; score: number; why: string[] }[];
  constraint_hints: Record<string, unknown>;
  needs_clarification: boolean;
  clarify_kind: string | null;
  source_version: string;
};

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const SOURCE_VERSION = "rag-v1";
const CACHE_TTL_MS = 60 * 60 * 1000; // 1 hour
const MIN_CONFIDENCE_THRESHOLD = 0.3;
const MAX_CANDIDATES = 10;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function json(res: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(res), {
    ...init,
    headers: { "Content-Type": "application/json", ...(init.headers ?? {}) },
  });
}

/** Strip common LLM prompt-injection patterns from user-supplied text. */
function sanitizeInput(text: string): string {
  return text
    .replace(
      /\b(ignore|disregard|forget)\s+(all\s+)?(previous|above|prior)\s+(instructions?|prompts?|rules?|context)/gi,
      "[filtered]",
    )
    .replace(/\b(you\s+are\s+now|new\s+instructions?|system\s*:)/gi, "[filtered]")
    .replace(/\b(act\s+as|pretend\s+(to\s+be|you\s+are)|role\s*play)/gi, "[filtered]")
    .replace(/```[\s\S]*?```/g, "")
    .replace(/<[^>]+>/g, "")
    .slice(0, 2000)
    .trim();
}

/**
 * Generate a deterministic cache key from normalized query + locale + constraints.
 * Uses FNV-1a 32-bit hash for fast, low-collision key generation.
 */
function generateCacheKey(
  normalizedQuery: string,
  locale: string,
  constraints: Constraints,
): string {
  const constraintsStr = JSON.stringify(constraints, Object.keys(constraints).sort());
  const raw = `${normalizedQuery}|${locale}|${constraintsStr}`;
  let hash = 0x811c9dc5;
  for (let i = 0; i < raw.length; i++) {
    hash ^= raw.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return `rag:${(hash >>> 0).toString(16).padStart(8, "0")}:${normalizedQuery.slice(0, 40)}`;
}

function serializeConstraints(constraints: Constraints): string {
  return JSON.stringify(constraints, Object.keys(constraints).sort());
}

function clientIp(req: Request): string | null {
  const xf = req.headers.get("x-forwarded-for");
  if (xf) {
    const first = xf.split(",")[0]?.trim();
    if (first) return first;
  }
  const real = req.headers.get("x-real-ip")?.trim();
  if (real) return real;
  const cf = req.headers.get("cf-connecting-ip")?.trim();
  if (cf) return cf;
  return null;
}

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------

serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, { status: 405 });
  }

  // Warmup: short-circuit to warm the Deno isolate
  const url = new URL(req.url);
  if (url.searchParams.get("warmup") === "true") {
    return json({ ok: true });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceKey) {
    return json(
      { error: "Missing SUPABASE_URL, SUPABASE_ANON_KEY, or SUPABASE_SERVICE_ROLE_KEY" },
      { status: 500 },
    );
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader) {
    return json({ error: "Authorization required" }, { status: 401 });
  }

  // Verify caller is an authenticated user before allowing retrieval.
  const authClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: authData, error: authError } = await authClient.auth.getUser();
  if (authError || !authData?.user) {
    return json({ error: "Authentication required" }, { status: 401 });
  }

  // Independent rate-limit bucket for RAG retrieval to prevent abuse.
  const ip = clientIp(req);
  const { data: rl } = await authClient.rpc("check_concierge_rate_limit", {
    p_kind: "rag",
    p_ip: ip,
    p_window_seconds: null,
    p_max_user: null,
    p_max_ip: null,
  });
  if (rl && rl.allowed === false) {
    return json(
      { error: "Rate limited", retry_after_s: rl.retry_after_s ?? 30 },
      { status: 429, headers: { "Retry-After": String(rl.retry_after_s ?? 30) } },
    );
  }

  // Service client for cache reads/writes and retrieval RPC
  // (cache table has no anon policies, retrieval RPC needs catalog access)
  const serviceClient = createClient(supabaseUrl, supabaseServiceKey);

  // Parse request body
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, { status: 400 });
  }

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

  // Sanitize and normalize
  const sanitized = sanitizeInput(rawQuery);
  const normalizedQuery = normalizeForSearch(sanitized, locale);

  if (!normalizedQuery) {
    return json({
      confidence: 0,
      entity_candidates: [],
      mode_hints: [],
      constraint_hints: {},
      needs_clarification: true,
      clarify_kind: "empty_query",
      source_version: SOURCE_VERSION,
    } satisfies RetrieveResponse);
  }

  // Parse constraints
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

  // -----------------------------------------------------------------------
  // 1. Cache check
  // -----------------------------------------------------------------------

  const cacheKey = generateCacheKey(normalizedQuery, locale, constraints);

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

  // -----------------------------------------------------------------------
  // 2. Lexical retrieval via rag_retrieve_candidates RPC
  // -----------------------------------------------------------------------

  // Normalize excluded genres for matching against normalized_tag in DB
  const normalizedExcludedGenres = (constraints.excluded_genres ?? []).map((g) =>
    normalizeForSearch(g, "en"),
  );

  let candidates: EntityCandidate[] = [];

  try {
    const { data: rows, error } = await serviceClient.rpc("rag_retrieve_candidates", {
      p_query: normalizedQuery,
      p_media_type: mediaType,
      p_year_min: constraints.year_min ?? null,
      p_year_max: constraints.year_max ?? null,
      p_format: constraints.format ?? null,
      p_excluded_genres: normalizedExcludedGenres,
      p_limit: MAX_CANDIDATES,
    });

    if (error) {
      // Return empty on retrieval error — never fabricate results
    } else if (Array.isArray(rows)) {
      candidates = rows.map(
        (row: {
          entity_id: string;
          anilist_id: number;
          media_type: string;
          canonical_title: string;
          year: number | null;
          final_score: number;
          popularity: number | null;
          match_source: string;
        }) => ({
          entity_id: row.entity_id,
          anilist_id: row.anilist_id,
          media_type: row.media_type as MediaType,
          title: row.canonical_title,
          year: row.year ?? null,
          score:
            typeof row.final_score === "number"
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

  // -----------------------------------------------------------------------
  // 3. Build response
  // -----------------------------------------------------------------------

  const topScore = candidates.length > 0 ? candidates[0].score : 0;
  const confidence = Math.min(1, topScore);
  const needsClarification =
    topScore < MIN_CONFIDENCE_THRESHOLD || candidates.length === 0;

  const response: RetrieveResponse = {
    confidence,
    entity_candidates: candidates,
    mode_hints: [],
    constraint_hints: {},
    needs_clarification: needsClarification,
    clarify_kind: needsClarification ? "low_confidence" : null,
    source_version: SOURCE_VERSION,
  };

  // -----------------------------------------------------------------------
  // 4. Cache the result (best-effort, upsert to avoid conflicts)
  // -----------------------------------------------------------------------

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
});
