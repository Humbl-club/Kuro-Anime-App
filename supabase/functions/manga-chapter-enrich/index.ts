import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { normalizeText } from "../_shared/normalization.ts";

const MANGADEX_API = "https://api.mangadex.org";
const DEFAULT_LIMIT = 20;
const DEFAULT_TIME_BUDGET_MS = 45_000;
const DEFAULT_LOCK_TTL_SECONDS = 900;
const MAX_RETRIES = 3;
const DEFAULT_MATCHER_MODE = "fuzzy_v2";
const DEFAULT_FUZZY_MIN_CONFIDENCE = 0.95;
const DEFAULT_FUZZY_MIN_MARGIN = 0.10;
const DEFAULT_TITLE_SIMILARITY_FLOOR = 0.85;
const COLLISION_TIEBREAK_MIN_SCORE = 0.82;
const COLLISION_TIEBREAK_MIN_MARGIN = 0.03;
const COLLISION_ENGLISH_HIGH_SIM = 0.93;
const COLLISION_ENGLISH_MED_SIM = 0.86;
const DEFAULT_VERIFY_ENABLED = true;
const DEFAULT_COLLISION_TIEBREAK_ENABLED = true;
const DEFAULT_WRONG_MAP_PROXY_RATE_LIMIT = 0.3;
const DEFAULT_MANGADEX_MAX_RPS = 3;
const DEFAULT_MANGADEX_429_COOLDOWN_MS = 2_500;
const BURST_429_THRESHOLD = 2;

type MappingMethod = "al_link" | "mal_link" | "title_strict" | "title_fuzzy";
type MatcherMode = "strict" | "fuzzy_v2";

interface EnrichPayload {
  limit?: number;
  scheduleSafe?: boolean;
  timeBudgetMs?: number;
  languages?: string[];
  includeFallbackAllLanguages?: boolean;
  forceMangaId?: number | null;
  lockTtlSeconds?: number;
  zeroRowOnly?: boolean;
  crunchMode?: boolean;
  matcherMode?: MatcherMode;
  minConfidence?: number;
  minMargin?: number;
  verifyMappings?: boolean;
  collisionTieBreakEnabled?: boolean;
  wrongMapProxyRateLimit?: number;
}

interface CandidateRow {
  id: number;
  anilist_id: number | null;
  mal_id: number | null;
  title_english: string | null;
  title_romaji: string | null;
  title_native: string | null;
  title_synonyms: string[] | null;
  status: string | null;
  chapters: number | null;
  last_synced_at: string | null;
  chapter_row_count: number;
  priority_class: number;
}

interface MangaDexManga {
  id: string;
  attributes?: {
    title?: Record<string, string>;
    altTitles?: Array<Record<string, string>>;
    links?: Record<string, string>;
  };
}

interface MappingResolution {
  mapped: boolean;
  method?: MappingMethod;
  confidence?: number;
  mangaDexId?: string;
  rejectedMangaDexIds?: string[];
  providerUrl?: string;
  queryTitle?: string | null;
  reason?: string;
  sample?: unknown[];
}

interface MappingRow {
  provider_media_id: string;
  next_verify_at?: string | null;
  verify_status?: string | null;
  verify_fail_count?: number | null;
  last_mismatch_at?: string | null;
}

interface RuntimeMatcherConfig {
  mode: MatcherMode;
  modeDegraded: boolean;
}

interface RunMetrics {
  manga_processed: number;
  mapped_by_al: number;
  mapped_by_mal: number;
  mapped_by_title_strict: number;
  unresolved_mappings: number;
  chapters_upserted: number;
  fractional_skipped: number;
  api_429_count: number;
  errors: number;
  fuzzy_attempted: number;
  fuzzy_auto_mapped: number;
  skipped_low_confidence: number;
  skipped_ambiguous: number;
  verify_checked: number;
  verify_mismatch: number;
  verify_deactivated: number;
  wrong_map_proxy_count: number;
  collision_tiebreak_attempted: number;
  collision_tiebreak_resolved: number;
  collision_tiebreak_ambiguous: number;
  alias_memory_hits: number;
  auto_retry_enqueued: number;
  auto_retry_due_processed: number;
  unresolved_reason_counts: Record<string, number>;
  rate_limiter_wait_ms: number;
  "429_cooldown_count": number;
  mode_used: MatcherMode;
  mode_degraded: boolean;
  timed_out?: boolean;
}

interface MangaDexRateLimiterState {
  minIntervalMs: number;
  nextAllowedAt: number;
  cooldownUntil: number;
  consecutive429: number;
}

const mangaDexRateLimiter: MangaDexRateLimiterState = {
  minIntervalMs: Math.max(
    1,
    Math.round(1000 / Math.max(0.1, parseFloatEnv("MANGADEX_MAX_RPS", DEFAULT_MANGADEX_MAX_RPS))),
  ),
  nextAllowedAt: 0,
  cooldownUntil: 0,
  consecutive429: 0,
};

serve(async (req) => {
  const importSecret = Deno.env.get("IMPORT_SECRET");
  const requestSecret = req.headers.get("x-import-secret");
  if (!importSecret || requestSecret !== importSecret) {
    return json({ error: "Unauthorized" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "Server misconfigured" }, 500);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);
  const payload = await req.json().catch(() => ({} as EnrichPayload));
  const normalizedPayload = normalizePayload(payload);

  const metrics: RunMetrics = {
    manga_processed: 0,
    mapped_by_al: 0,
    mapped_by_mal: 0,
    mapped_by_title_strict: 0,
    unresolved_mappings: 0,
    chapters_upserted: 0,
    fractional_skipped: 0,
    api_429_count: 0,
    errors: 0,
    fuzzy_attempted: 0,
    fuzzy_auto_mapped: 0,
    skipped_low_confidence: 0,
    skipped_ambiguous: 0,
    verify_checked: 0,
    verify_mismatch: 0,
    verify_deactivated: 0,
    wrong_map_proxy_count: 0,
    collision_tiebreak_attempted: 0,
    collision_tiebreak_resolved: 0,
    collision_tiebreak_ambiguous: 0,
    alias_memory_hits: 0,
    auto_retry_enqueued: 0,
    auto_retry_due_processed: 0,
    unresolved_reason_counts: {},
    rate_limiter_wait_ms: 0,
    "429_cooldown_count": 0,
    mode_used: normalizedPayload.matcherMode,
    mode_degraded: false,
  };

  const startedMs = Date.now();
  const runId = await startImportRun(supabase, "MANGA", "chapter_enrich", normalizedPayload);
  let lockAcquired = false;

  try {
    lockAcquired = await acquireImportLock(
      supabase,
      "manga-chapter-enrich",
      normalizedPayload.lockTtlSeconds,
    );
    if (!lockAcquired) {
      await finishImportRun(supabase, runId, "skipped", metrics, "locked", startedMs);
      return json({ success: true, skipped: true, reason: "locked", results: metrics }, 200);
    }

    const matcherConfig = await resolveRuntimeMatcherConfig(
      supabase,
      normalizedPayload.matcherMode,
      normalizedPayload.wrongMapProxyRateLimit,
    );
    metrics.mode_used = matcherConfig.mode;
    metrics.mode_degraded = matcherConfig.modeDegraded;

    const candidates = await fetchCandidates(
      supabase,
      normalizedPayload.limit,
      normalizedPayload.forceMangaId,
      normalizedPayload.zeroRowOnly || normalizedPayload.crunchMode,
    );

    const searchCache = new Map<string, MangaDexManga[]>();
    for (const candidate of candidates) {
      if (!withinBudget(startedMs, normalizedPayload.timeBudgetMs)) {
        metrics.timed_out = true;
        break;
      }

      try {
        const result = await processCandidate({
          supabase,
          candidate,
          payload: normalizedPayload,
          matcherConfig,
          metrics,
          startedMs,
          searchCache,
        });
        metrics.manga_processed += 1;
        metrics.chapters_upserted += result.insertedCount;
        metrics.fractional_skipped += result.fractionalSkipped;

        if (result.mappingMethod === "al_link") metrics.mapped_by_al += 1;
        if (result.mappingMethod === "mal_link") metrics.mapped_by_mal += 1;
        if (result.mappingMethod === "title_strict" || result.mappingMethod === "title_fuzzy") {
          metrics.mapped_by_title_strict += 1;
        }
        if (result.unresolved) {
          metrics.unresolved_mappings += 1;
          bumpReasonCount(metrics.unresolved_reason_counts, result.unresolvedReason ?? "unknown");
        }
      } catch (error) {
        metrics.errors += 1;
        console.error(`manga-chapter-enrich candidate ${candidate.id} failed:`, error);
      }
    }

    const message = metrics.timed_out ? "time_budget_reached" : null;
    await finishImportRun(supabase, runId, "success", metrics, message, startedMs);
    return json({ success: true, results: metrics }, 200);
  } catch (error) {
    const message = (error as Error).message ?? "Unknown error";
    await finishImportRun(supabase, runId, "error", metrics, message, startedMs);
    return json({ success: false, error: message, results: metrics }, 500);
  } finally {
    if (lockAcquired) {
      await releaseImportLock(supabase, "manga-chapter-enrich");
    }
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function normalizePayload(payload: EnrichPayload): Required<EnrichPayload> {
  let limit = clampNumber(payload.limit, DEFAULT_LIMIT, 1, 200);
  let timeBudgetMs = clampNumber(payload.timeBudgetMs, DEFAULT_TIME_BUDGET_MS, 8_000, 120_000);
  const scheduleSafe = payload.scheduleSafe ?? true;
  const crunchMode = payload.crunchMode ?? false;
  const zeroRowOnly = payload.zeroRowOnly ?? crunchMode;
  if (scheduleSafe) {
    timeBudgetMs = Math.min(timeBudgetMs, DEFAULT_TIME_BUDGET_MS);
  }

  const normalizedLanguages = normalizeLanguages(payload.languages);
  const matcherMode = normalizeMatcherMode(payload.matcherMode ?? Deno.env.get("MANGA_MATCHER_MODE"));
  const minConfidence = clampFloat(
    payload.minConfidence ?? parseFloatEnv("MANGA_FUZZY_MIN_CONFIDENCE", DEFAULT_FUZZY_MIN_CONFIDENCE),
    0.5,
    1.0,
    DEFAULT_FUZZY_MIN_CONFIDENCE,
  );
  const minMargin = clampFloat(
    payload.minMargin ?? parseFloatEnv("MANGA_FUZZY_MIN_MARGIN", DEFAULT_FUZZY_MIN_MARGIN),
    0.01,
    0.5,
    DEFAULT_FUZZY_MIN_MARGIN,
  );
  const verifyMappings = payload.verifyMappings
    ?? parseBooleanEnv("MANGA_VERIFY_ENABLED", DEFAULT_VERIFY_ENABLED);
  const collisionTieBreakEnabled = payload.collisionTieBreakEnabled
    ?? parseBooleanEnv("MANGA_COLLISION_TIEBREAK_ENABLED", DEFAULT_COLLISION_TIEBREAK_ENABLED);
  const wrongMapProxyRateLimit = clampFloat(
    payload.wrongMapProxyRateLimit
      ?? parseFloatEnv("MANGA_WRONG_MAP_PROXY_RATE_LIMIT", DEFAULT_WRONG_MAP_PROXY_RATE_LIMIT),
    0.05,
    5.0,
    DEFAULT_WRONG_MAP_PROXY_RATE_LIMIT,
  );

  return {
    limit,
    scheduleSafe,
    timeBudgetMs,
    languages: normalizedLanguages,
    includeFallbackAllLanguages: payload.includeFallbackAllLanguages ?? true,
    forceMangaId: payload.forceMangaId ?? null,
    lockTtlSeconds: clampNumber(payload.lockTtlSeconds, DEFAULT_LOCK_TTL_SECONDS, 60, 3_600),
    zeroRowOnly,
    crunchMode,
    matcherMode,
    minConfidence,
    minMargin,
    verifyMappings,
    collisionTieBreakEnabled,
    wrongMapProxyRateLimit,
  };
}

function normalizeMatcherMode(raw: unknown): MatcherMode {
  const normalized = String(raw ?? DEFAULT_MATCHER_MODE).trim().toLowerCase();
  return normalized === "strict" ? "strict" : "fuzzy_v2";
}

function parseFloatEnv(name: string, fallback: number): number {
  const raw = Deno.env.get(name);
  if (!raw) return fallback;
  const parsed = Number.parseFloat(raw);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function parseBooleanEnv(name: string, fallback: boolean): boolean {
  const raw = Deno.env.get(name);
  if (!raw) return fallback;
  const normalized = raw.trim().toLowerCase();
  if (["1", "true", "yes", "on"].includes(normalized)) return true;
  if (["0", "false", "no", "off"].includes(normalized)) return false;
  return fallback;
}

function normalizeLanguages(input?: string[]): string[] {
  const source = Array.isArray(input) ? input : ["en", "de"];
  const normalized = source
    .map((value) => String(value ?? "").trim().toLowerCase())
    .map((value) => value.slice(0, 2))
    .filter((value) => value.length === 2);
  const unique = Array.from(new Set(normalized));
  return unique.length > 0 ? unique : ["en", "de"];
}

function clampNumber(value: unknown, fallback: number, min: number, max: number): number {
  if (typeof value !== "number" || Number.isNaN(value)) return fallback;
  return Math.max(min, Math.min(max, Math.trunc(value)));
}

function clampFloat(value: unknown, min: number, max: number, fallback: number): number {
  if (typeof value !== "number" || Number.isNaN(value)) return fallback;
  return Math.max(min, Math.min(max, value));
}

function bumpReasonCount(bucket: Record<string, number>, reason: string) {
  const key = String(reason || "unknown");
  bucket[key] = (bucket[key] ?? 0) + 1;
}

function computeNextRetryAt(retryCount: number): string {
  let delayMs = 24 * 60 * 60 * 1000;
  if (retryCount <= 1) delayMs = 15 * 60 * 1000;
  else if (retryCount == 2) delayMs = 60 * 60 * 1000;
  else if (retryCount == 3) delayMs = 6 * 60 * 60 * 1000;
  return new Date(Date.now() + delayMs).toISOString();
}

function withinBudget(startedMs: number, timeBudgetMs: number): boolean {
  return Date.now() - startedMs < Math.max(0, timeBudgetMs - 250);
}

async function resolveRuntimeMatcherConfig(
  supabase: any,
  configuredMode: MatcherMode,
  wrongMapProxyRateLimit: number,
): Promise<RuntimeMatcherConfig> {
  if (configuredMode !== "fuzzy_v2") {
    return { mode: configuredMode, modeDegraded: false };
  }

  try {
    const { data, error } = await supabase.rpc("get_manga_match_quality_metrics", { p_hours: 24 });
    if (error) {
      console.warn("manga matcher mode guard rpc unavailable:", error.message);
      return { mode: configuredMode, modeDegraded: false };
    }

    const row = Array.isArray(data) ? data[0] : data;
    const wrongProxy = Number(row?.wrong_map_proxy_rate_pct ?? 0);
    if (Number.isFinite(wrongProxy) && wrongProxy > wrongMapProxyRateLimit) {
      return { mode: "strict", modeDegraded: true };
    }
  } catch (error) {
    console.warn("manga matcher mode guard failed:", error);
  }

  return { mode: configuredMode, modeDegraded: false };
}

async function fetchCandidates(
  supabase: any,
  limit: number,
  forceMangaId: number | null,
  zeroRowOnly: boolean,
): Promise<CandidateRow[]> {
  const next = await supabase.rpc("get_manga_chapter_enrich_candidates", {
    p_limit: limit,
    p_force_manga_id: forceMangaId,
    p_zero_row_only: zeroRowOnly,
  });
  if (!next.error) return (next.data ?? []) as CandidateRow[];

  // Backward-compatible fallback while some deployments still expose the 2-arg RPC.
  console.warn("candidate RPC without p_zero_row_only fallback:", next.error.message);
  const legacy = await supabase.rpc("get_manga_chapter_enrich_candidates", {
    p_limit: limit,
    p_force_manga_id: forceMangaId,
  });
  if (legacy.error) throw legacy.error;
  const rows = (legacy.data ?? []) as CandidateRow[];
  if (!zeroRowOnly) return rows;
  return rows.filter((row) => Number(row.chapter_row_count ?? 0) === 0);
}

async function processCandidate(args: {
  supabase: any;
  candidate: CandidateRow;
  payload: Required<EnrichPayload>;
  matcherConfig: RuntimeMatcherConfig;
  metrics: RunMetrics;
  startedMs: number;
  searchCache: Map<string, MangaDexManga[]>;
}): Promise<{
  mappingMethod?: MappingMethod;
  unresolved: boolean;
  unresolvedReason?: string;
  insertedCount: number;
  fractionalSkipped: number;
}> {
  const { supabase, candidate, payload, matcherConfig, metrics, startedMs, searchCache } = args;
  if ((payload.zeroRowOnly || payload.crunchMode) && (candidate.chapter_row_count ?? 0) > 0) {
    // Defensive guard: crunch mode must never mutate already-covered manga.
    return { unresolved: false, insertedCount: 0, fractionalSkipped: 0 };
  }
  if (candidate.priority_class === 5) {
    metrics.auto_retry_due_processed += 1;
  }

  let existingMapping = await fetchExistingMapping(supabase, candidate.id);
  let mappingMethod: MappingMethod | undefined;
  let mangaDexId = existingMapping?.provider_media_id ?? null;

  if (existingMapping && payload.verifyMappings && isMappingVerificationDue(existingMapping.next_verify_at)) {
    const verification = await verifyExistingMapping({
      supabase,
      candidate,
      mapping: existingMapping,
      metrics,
      startedMs,
      timeBudgetMs: payload.timeBudgetMs,
    });
    if (verification.deactivated) {
      existingMapping = null;
      mangaDexId = null;
    } else if (verification.skipCurrentRun) {
      return { unresolved: true, unresolvedReason: "mapping_verification_pending", insertedCount: 0, fractionalSkipped: 0 };
    } else if (verification.mapping) {
      existingMapping = verification.mapping;
      mangaDexId = verification.mapping.provider_media_id;
    }
  }

  if (!mangaDexId) {
    const resolution = await resolveMapping({
      supabase,
      candidate,
      payload,
      matcherMode: matcherConfig.mode,
      metrics,
      startedMs,
      timeBudgetMs: payload.timeBudgetMs,
      searchCache,
    });

    if (!resolution.mapped || !resolution.mangaDexId || !resolution.method || !resolution.confidence) {
      const reason = resolution.reason ?? "no_confident_match";
      await enqueueMappingReview(supabase, candidate, {
        provider: "mangadex",
        queryTitle: resolution.queryTitle ?? primaryTitle(candidate),
        reason,
        sample: resolution.sample ?? [],
      });
      metrics.auto_retry_enqueued += 1;
      return { unresolved: true, unresolvedReason: reason, insertedCount: 0, fractionalSkipped: 0 };
    }

    const upserted = await upsertMapping(supabase, candidate.id, {
      mangaDexId: resolution.mangaDexId,
      providerUrl: resolution.providerUrl ?? `https://mangadex.org/title/${resolution.mangaDexId}`,
      method: resolution.method,
      confidence: resolution.confidence,
      nextVerifyAt: nextVerifyAtForStatus(candidate.status),
    });
    if (!upserted) {
      await enqueueMappingReview(supabase, candidate, {
        provider: "mangadex",
        queryTitle: resolution.queryTitle ?? primaryTitle(candidate),
        reason: "mapping_conflict",
        sample: resolution.sample ?? [],
      });
      metrics.auto_retry_enqueued += 1;
      return { unresolved: true, unresolvedReason: "mapping_conflict", insertedCount: 0, fractionalSkipped: 0 };
    }

    mappingMethod = resolution.method;
    mangaDexId = resolution.mangaDexId;
    await rememberAliasDecision(
      supabase,
      candidate.id,
      "mangadex",
      resolution.mangaDexId,
      "accepted",
      "selected_canonical",
    );
    for (const rejectedId of resolution.rejectedMangaDexIds ?? []) {
      await rememberAliasDecision(
        supabase,
        candidate.id,
        "mangadex",
        rejectedId,
        "rejected_collision",
        "collision_tiebreak_loser",
      );
    }
  }

  const aggregate = await fetchAggregateChapterNumbers({
    mangaDexId,
    languages: payload.languages,
    includeFallbackAllLanguages: payload.includeFallbackAllLanguages,
    metrics,
    startedMs,
    timeBudgetMs: payload.timeBudgetMs,
  });

  const beforeCount = candidate.chapter_row_count ?? 0;
  if (aggregate.chapterNumbers.length > 0) {
    await upsertChapterRows(supabase, candidate.id, aggregate.chapterNumbers);
  }

  const afterCount = await fetchChapterCount(supabase, candidate.id);
  const insertedCount = Math.max(0, afterCount - beforeCount);
  const maxImportedNumber = aggregate.chapterNumbers.length > 0
    ? aggregate.chapterNumbers[aggregate.chapterNumbers.length - 1]
    : null;

  await updateMangaSyncFields(supabase, candidate, maxImportedNumber);

  return {
    mappingMethod,
    unresolved: false,
    insertedCount,
    fractionalSkipped: aggregate.fractionalSkipped,
  };
}

async function fetchExistingMapping(supabase: any, mangaId: number): Promise<MappingRow | null> {
  let { data, error } = await supabase
    .from("manga_source_links")
    .select("provider_media_id,next_verify_at,verify_status,verify_fail_count,last_mismatch_at")
    .eq("manga_id", mangaId)
    .eq("provider", "mangadex")
    .eq("status", "active")
    .maybeSingle();

  // Backward-compatible fallback in case new verification columns are not present yet.
  if (error) {
    const fallback = await supabase
      .from("manga_source_links")
      .select("provider_media_id")
      .eq("manga_id", mangaId)
      .eq("provider", "mangadex")
      .eq("status", "active")
      .maybeSingle();
    data = fallback.data;
    error = fallback.error;
  }

  if (error) return null;
  return data as MappingRow | null;
}

function isMappingVerificationDue(nextVerifyAt: string | null | undefined): boolean {
  if (!nextVerifyAt) return true;
  const ts = Date.parse(nextVerifyAt);
  if (!Number.isFinite(ts)) return true;
  return ts <= Date.now();
}

function nextVerifyAtForStatus(status: string | null | undefined): string {
  const normalized = String(status ?? "").toUpperCase();
  const hours = normalized === "RELEASING" ? 24 : 14 * 24;
  return new Date(Date.now() + (hours * 60 * 60 * 1000)).toISOString();
}

function canDeactivateAfterMismatch(lastMismatchAt: string | null | undefined): boolean {
  if (!lastMismatchAt) return false;
  const ts = Date.parse(lastMismatchAt);
  if (!Number.isFinite(ts)) return false;
  return (Date.now() - ts) >= (6 * 60 * 60 * 1000);
}

async function persistVerifyState(
  supabase: any,
  mangaId: number,
  payload: Record<string, unknown>,
) {
  const { error } = await supabase
    .from("manga_source_links")
    .update(payload)
    .eq("manga_id", mangaId)
    .eq("provider", "mangadex");

  if (error) {
    // Backward-compatible fallback for environments where verification columns are not migrated yet.
    const fallbackPayload: Record<string, unknown> = {};
    if (payload.status !== undefined) fallbackPayload.status = payload.status;
    if (Object.keys(fallbackPayload).length > 0) {
      await supabase
        .from("manga_source_links")
        .update(fallbackPayload)
        .eq("manga_id", mangaId)
        .eq("provider", "mangadex");
    }
  }
}

async function verifyExistingMapping(args: {
  supabase: any;
  candidate: CandidateRow;
  mapping: MappingRow;
  metrics: RunMetrics;
  startedMs: number;
  timeBudgetMs: number;
}): Promise<{ deactivated: boolean; skipCurrentRun: boolean; mapping?: MappingRow }> {
  const { supabase, candidate, mapping, metrics, startedMs, timeBudgetMs } = args;
  metrics.verify_checked += 1;

  const verifyResult = await fetchMappedMangaDexTitle(
    mapping.provider_media_id,
    metrics,
    startedMs,
    timeBudgetMs,
  );

  if (verifyResult.rateLimited) {
    await persistVerifyState(supabase, candidate.id, {
      verify_status: "rate_limited",
      last_verify_reason: "rate_limited",
      next_verify_at: new Date(Date.now() + 6 * 60 * 60 * 1000).toISOString(),
    });
    return { deactivated: false, skipCurrentRun: false, mapping };
  }

  if (verifyResult.notFound || !verifyResult.manga) {
    const failedCount = Number(mapping.verify_fail_count ?? 0) + 1;
    metrics.verify_mismatch += 1;
    metrics.wrong_map_proxy_count += 1;
    if (failedCount >= 2 && canDeactivateAfterMismatch(mapping.last_mismatch_at)) {
      metrics.verify_deactivated += 1;
      await persistVerifyState(supabase, candidate.id, {
        verify_status: "mismatch",
        verify_fail_count: failedCount,
        status: "inactive",
        last_verify_reason: "not_found",
        last_mismatch_at: new Date().toISOString(),
        next_verify_at: new Date().toISOString(),
      });
      return { deactivated: true, skipCurrentRun: false };
    }
    await persistVerifyState(supabase, candidate.id, {
      verify_status: "not_found",
      verify_fail_count: failedCount,
      last_verify_reason: "not_found",
      last_mismatch_at: new Date().toISOString(),
      next_verify_at: new Date(Date.now() + 6 * 60 * 60 * 1000).toISOString(),
    });
    // Avoid potentially wrong chapter writes until we get a second signal.
    return { deactivated: false, skipCurrentRun: true, mapping };
  }

  const conflict = evaluateHardConflict(candidate, verifyResult.manga);
  const candidateTitles = allCandidateTitles(candidate);
  const dexTitles = mangaDexNormalizedTitles(verifyResult.manga);
  const titleSimilarity = computeBestTitleSimilarity(candidateTitles, dexTitles);

  if (conflict || titleSimilarity < DEFAULT_TITLE_SIMILARITY_FLOOR) {
    const failedCount = Number(mapping.verify_fail_count ?? 0) + 1;
    metrics.verify_mismatch += 1;
    metrics.wrong_map_proxy_count += 1;
    if (failedCount >= 2 && canDeactivateAfterMismatch(mapping.last_mismatch_at)) {
      metrics.verify_deactivated += 1;
      await persistVerifyState(supabase, candidate.id, {
        verify_status: "mismatch",
        verify_fail_count: failedCount,
        status: "inactive",
        last_verify_reason: conflict ? "external_id_conflict" : "title_similarity_low",
        last_mismatch_at: new Date().toISOString(),
        next_verify_at: new Date().toISOString(),
      });
      return { deactivated: true, skipCurrentRun: false };
    }
    await persistVerifyState(supabase, candidate.id, {
      verify_status: "mismatch",
      verify_fail_count: failedCount,
      last_verify_reason: conflict ? "external_id_conflict" : "title_similarity_low",
      last_mismatch_at: new Date().toISOString(),
      next_verify_at: new Date(Date.now() + 6 * 60 * 60 * 1000).toISOString(),
    });
    return { deactivated: false, skipCurrentRun: true, mapping };
  }

  await persistVerifyState(supabase, candidate.id, {
    verify_status: "ok",
    verify_fail_count: 0,
    last_verified_at: new Date().toISOString(),
    last_verify_reason: null,
    last_mismatch_at: null,
    next_verify_at: nextVerifyAtForStatus(candidate.status),
  });

  return {
    deactivated: false,
    skipCurrentRun: false,
    mapping: {
      ...mapping,
      verify_status: "ok",
      verify_fail_count: 0,
      next_verify_at: nextVerifyAtForStatus(candidate.status),
    },
  };
}

async function upsertMapping(
  supabase: any,
  mangaId: number,
  mapping: {
    mangaDexId: string;
    providerUrl: string;
    method: MappingMethod;
    confidence: number;
    nextVerifyAt: string;
  },
): Promise<boolean> {
  const { error } = await supabase
    .from("manga_source_links")
    .upsert({
      manga_id: mangaId,
      provider: "mangadex",
      provider_media_id: mapping.mangaDexId,
      provider_url: mapping.providerUrl,
      mapping_method: mapping.method,
      confidence: mapping.confidence,
      status: "active",
      verify_status: "unverified",
      verify_fail_count: 0,
      last_verify_reason: null,
      last_mismatch_at: null,
      next_verify_at: mapping.nextVerifyAt,
    }, { onConflict: "manga_id,provider" });
  if (error) {
    const fallback = await supabase
      .from("manga_source_links")
      .upsert({
        manga_id: mangaId,
        provider: "mangadex",
        provider_media_id: mapping.mangaDexId,
        provider_url: mapping.providerUrl,
        mapping_method: mapping.method,
        confidence: mapping.confidence,
        status: "active",
      }, { onConflict: "manga_id,provider" });
    if (fallback.error) {
      console.error("manga_source_links upsert failed:", fallback.error);
      return false;
    }
    return true;
  }
  return true;
}

async function enqueueMappingReview(
  supabase: any,
  candidate: CandidateRow,
  input: { provider: string; queryTitle: string; reason: string; sample: unknown[] },
) {
  const { data: existing } = await supabase
    .from("manga_source_link_review")
    .select("id,retry_count")
    .eq("provider", input.provider)
    .eq("manga_id", candidate.id)
    .eq("status", "pending")
    .limit(1);
  if ((existing ?? []).length > 0) {
    const row = existing[0] as { id: number; retry_count?: number | null };
    const retryCount = Number(row.retry_count ?? 0) + 1;
    const nextRetryAt = computeNextRetryAt(retryCount);
    let updateError = (await supabase
      .from("manga_source_link_review")
      .update({
        reason: input.reason,
        retry_count: retryCount,
        next_retry_at: nextRetryAt,
      })
      .eq("id", row.id)).error;
    if (updateError) {
      updateError = (await supabase
        .from("manga_source_link_review")
        .update({ reason: input.reason })
        .eq("id", row.id)).error;
      if (updateError) {
        console.error("manga_source_link_review update failed:", updateError);
      }
    }
    return;
  }

  const payload = {
    candidate: {
      id: candidate.id,
      anilist_id: candidate.anilist_id,
      mal_id: candidate.mal_id,
      title_english: candidate.title_english,
      title_romaji: candidate.title_romaji,
      title_native: candidate.title_native,
      title_synonyms: candidate.title_synonyms ?? [],
    },
    sample: input.sample,
  };

  const { error } = await supabase
    .from("manga_source_link_review")
    .insert({
      provider: input.provider,
      manga_id: candidate.id,
      query_title: input.queryTitle,
      candidate_payload: payload,
      reason: input.reason,
      status: "pending",
      retry_count: 1,
      next_retry_at: computeNextRetryAt(1),
    });
  if (!error) return;

  const fallback = await supabase
    .from("manga_source_link_review")
    .insert({
      provider: input.provider,
      manga_id: candidate.id,
      query_title: input.queryTitle,
      candidate_payload: payload,
      reason: input.reason,
      status: "pending",
    });
  if (fallback.error) {
    console.error("manga_source_link_review insert failed:", fallback.error);
  }
}

function primaryTitle(candidate: CandidateRow): string {
  return candidate.title_english
    ?? candidate.title_romaji
    ?? candidate.title_native
    ?? "Unknown title";
}

function allCandidateTitles(candidate: CandidateRow): string[] {
  const raw = [
    candidate.title_english,
    candidate.title_romaji,
    candidate.title_native,
    ...(candidate.title_synonyms ?? []),
  ];
  return Array.from(
    new Set(
      raw
        .map((value) => String(value ?? "").trim())
        .filter((value) => value.length > 0),
    ),
  );
}

async function resolveMapping(args: {
  supabase: any;
  candidate: CandidateRow;
  payload: Required<EnrichPayload>;
  matcherMode: MatcherMode;
  metrics: RunMetrics;
  startedMs: number;
  timeBudgetMs: number;
  searchCache: Map<string, MangaDexManga[]>;
}): Promise<MappingResolution> {
  const { supabase, candidate, payload, matcherMode, metrics, startedMs, timeBudgetMs, searchCache } = args;
  const queryTitles = allCandidateTitles(candidate).slice(0, 8);
  if (queryTitles.length === 0) {
    return { mapped: false, queryTitle: null, reason: "missing_titles", sample: [] };
  }

  const resultMap = new Map<string, MangaDexManga>();
  for (const title of queryTitles) {
    if (!withinBudget(startedMs, timeBudgetMs)) break;
    const rows = await searchMangaDex(title, metrics, startedMs, timeBudgetMs, searchCache);
    for (const row of rows) resultMap.set(row.id, row);
  }

  const results = Array.from(resultMap.values());
  const sample = results.slice(0, 8).map((item) => ({
    id: item.id,
    title: preferredMangaDexTitle(item),
    links: item.attributes?.links ?? {},
  }));

  if (results.length === 0) {
    return { mapped: false, queryTitle: queryTitles[0], reason: "no_candidates", sample };
  }

  const anilistId = candidate.anilist_id ? String(candidate.anilist_id) : null;
  if (anilistId) {
    const matches = results.filter((item) => normalizeLinkedExternalId(item.attributes?.links?.al) === anilistId);
    const externalResolution = await resolveAmbiguousExternalMatches({
      supabase,
      candidate,
      matches,
      matcherMode,
      payload,
      metrics,
      startedMs,
      timeBudgetMs,
      sample,
      queryTitle: queryTitles[0],
      reasonPrefix: "al",
    });
    if (externalResolution) {
      return externalResolution;
    }
  }

  const malId = candidate.mal_id ? String(candidate.mal_id) : null;
  if (malId) {
    const matches = results.filter((item) => normalizeLinkedExternalId(item.attributes?.links?.mal) === malId);
    const externalResolution = await resolveAmbiguousExternalMatches({
      supabase,
      candidate,
      matches,
      matcherMode,
      payload,
      metrics,
      startedMs,
      timeBudgetMs,
      sample,
      queryTitle: queryTitles[0],
      reasonPrefix: "mal",
    });
    if (externalResolution) {
      return externalResolution;
    }
  }

  if (matcherMode === "strict") {
    const candidateTitleSet = new Set(
      queryTitles
        .map((title) => normalizeStrictTitle(title))
        .filter((title) => title.length > 0),
    );
    const strictMatches = results.filter((item) => {
      const dexTitles = mangaDexNormalizedTitles(item);
      return dexTitles.some((title) => candidateTitleSet.has(title));
    });

    if (strictMatches.length === 1) {
      return {
        mapped: true,
        method: "title_strict",
        confidence: 0.92,
        mangaDexId: strictMatches[0].id,
        providerUrl: `https://mangadex.org/title/${strictMatches[0].id}`,
        queryTitle: queryTitles[0],
        sample,
      };
    }
    if (strictMatches.length > 1) {
      metrics.skipped_ambiguous += 1;
      return { mapped: false, queryTitle: queryTitles[0], reason: "ambiguous_title_strict", sample };
    }

    metrics.skipped_low_confidence += 1;
    return { mapped: false, queryTitle: queryTitles[0], reason: "no_confident_match", sample };
  }

  metrics.fuzzy_attempted += 1;
  const scored = scoreFuzzyCandidates(candidate, results);
  const viable = scored.filter((row) => !row.hardConflict);

  if (viable.length === 0) {
    metrics.skipped_low_confidence += 1;
    return { mapped: false, queryTitle: queryTitles[0], reason: "hard_conflict", sample };
  }

  const sorted = viable.sort((a, b) => b.score - a.score);
  const top = sorted[0];
  const second = sorted[1];
  const margin = second ? top.score - second.score : 1;

  if (top.titleSimilarity < DEFAULT_TITLE_SIMILARITY_FLOOR) {
    metrics.skipped_low_confidence += 1;
    return { mapped: false, queryTitle: queryTitles[0], reason: "title_similarity_low", sample };
  }
  if (top.score < payload.minConfidence) {
    metrics.skipped_low_confidence += 1;
    return { mapped: false, queryTitle: queryTitles[0], reason: "fuzzy_score_low", sample };
  }
  if (margin < payload.minMargin) {
    metrics.skipped_ambiguous += 1;
    return { mapped: false, queryTitle: queryTitles[0], reason: "fuzzy_margin_low", sample };
  }

  metrics.fuzzy_auto_mapped += 1;
  return {
    mapped: true,
    method: "title_fuzzy",
    confidence: Math.min(0.98, Math.max(0.90, Number(top.score.toFixed(3)))),
    mangaDexId: top.manga.id,
    providerUrl: `https://mangadex.org/title/${top.manga.id}`,
    queryTitle: queryTitles[0],
    sample,
  };
}

async function resolveAmbiguousExternalMatches(args: {
  supabase: any;
  candidate: CandidateRow;
  matches: MangaDexManga[];
  matcherMode: MatcherMode;
  payload: Required<EnrichPayload>;
  metrics: RunMetrics;
  startedMs: number;
  timeBudgetMs: number;
  sample: Array<Record<string, unknown>>;
  queryTitle: string;
  reasonPrefix: "al" | "mal";
}): Promise<MappingResolution | null> {
  if (args.matches.length === 0) {
    return null;
  }

  const {
    supabase,
    matches,
    matcherMode,
    payload,
    sample,
    queryTitle,
    reasonPrefix,
    candidate,
    metrics,
    startedMs,
    timeBudgetMs,
  } = args;

  if (matches.length === 1) {
    const primary = matches[0];
    return {
      mapped: true,
      method: reasonPrefix === "al" ? "al_link" : "mal_link",
      confidence: reasonPrefix === "al" ? 1.0 : 0.99,
      mangaDexId: primary.id,
      providerUrl: `https://mangadex.org/title/${primary.id}`,
      queryTitle,
      sample,
    };
  }

  let filteredMatches = matches;
  const aliasFiltered = await filterMatchesWithAliasMemory(
    supabase,
    candidate.id,
    "mangadex",
    matches,
  );
  if (aliasFiltered.aliasHit) {
    metrics.alias_memory_hits += 1;
  }
  if (aliasFiltered.matches.length > 0) {
    filteredMatches = aliasFiltered.matches;
  }
  if (filteredMatches.length === 1) {
    const winner = filteredMatches[0];
    return {
      mapped: true,
      method: reasonPrefix === "al" ? "al_link" : "mal_link",
      confidence: reasonPrefix === "al" ? 1.0 : 0.99,
      mangaDexId: winner.id,
      providerUrl: `https://mangadex.org/title/${winner.id}`,
      queryTitle,
      sample,
    };
  }

  if (matcherMode !== "fuzzy_v2" || !payload.collisionTieBreakEnabled) {
    return {
      mapped: false,
      queryTitle,
      reason: `multiple_${reasonPrefix}_matches`,
      sample,
    };
  }

  if (!withinBudget(startedMs, timeBudgetMs)) {
    return {
      mapped: false,
      queryTitle,
      reason: `${reasonPrefix}_time_budget_exceeded`,
      sample,
    };
  }

  metrics.collision_tiebreak_attempted += 1;
  const scored = await scoreCollisionCandidates({
    candidate,
    candidates: filteredMatches,
    languages: payload.languages,
    metrics,
    startedMs,
    timeBudgetMs,
  });
  const viable = scored.filter((row) => !row.hardConflict).sort((a, b) => b.score - a.score);

  if (viable.length === 0) {
    metrics.skipped_low_confidence += 1;
    metrics.collision_tiebreak_ambiguous += 1;
    return {
      mapped: false,
      queryTitle,
      reason: "external_collision_ambiguous",
      sample,
    };
  }

  const top = chooseEnglishPreferredCollisionCandidate(viable) ?? viable[0];
  const second = viable.find((row) => row.manga.id !== top.manga.id);
  const margin = second ? top.score - second.score : 1;

  if (
    top.titleSimilarity < DEFAULT_TITLE_SIMILARITY_FLOOR ||
    top.score < COLLISION_TIEBREAK_MIN_SCORE ||
    margin < COLLISION_TIEBREAK_MIN_MARGIN
  ) {
    metrics.skipped_low_confidence += 1;
    metrics.collision_tiebreak_ambiguous += 1;
    return {
      mapped: false,
      queryTitle,
      reason: "external_collision_ambiguous",
      sample,
    };
  }

  metrics.collision_tiebreak_resolved += 1;
  const rejectedIds = filteredMatches
    .map((item) => item.id)
    .filter((id) => id !== top.manga.id);
  return {
    mapped: true,
    method: reasonPrefix === "al" ? "al_link" : "mal_link",
    confidence: Math.min(0.999, Math.max(0.90, Number(top.score.toFixed(3)))),
    mangaDexId: top.manga.id,
    rejectedMangaDexIds: rejectedIds,
    providerUrl: `https://mangadex.org/title/${top.manga.id}`,
    queryTitle,
    sample,
  };
}

function chooseEnglishPreferredCollisionCandidate(
  candidates: CollisionCandidateScore[],
): CollisionCandidateScore | null {
  if (candidates.length === 0) return null;

  // Prefer a strong English-title match when available, but avoid edition variants.
  const strongEnglish = candidates
    .filter((row) => row.englishTitleSimilarity >= COLLISION_ENGLISH_HIGH_SIM && row.editionPenalty === 0)
    .sort((a, b) => b.score - a.score);
  if (strongEnglish.length > 0) return strongEnglish[0];

  const mediumEnglish = candidates
    .filter((row) => row.englishTitleSimilarity >= COLLISION_ENGLISH_MED_SIM && row.editionPenalty === 0)
    .sort((a, b) => b.score - a.score);
  if (mediumEnglish.length > 0) return mediumEnglish[0];

  return null;
}

interface CollisionCandidateScore extends FuzzyCandidateScore {
  integerChapterCoverage: number;
  integerChapterCoverageScore: number;
  editionPenalty: number;
  languagePenalty: number;
  englishTitleSimilarity: number;
  englishTitleBoost: number;
}

async function scoreCollisionCandidates(args: {
  candidate: CandidateRow;
  candidates: MangaDexManga[];
  languages: string[];
  metrics: RunMetrics;
  startedMs: number;
  timeBudgetMs: number;
}): Promise<CollisionCandidateScore[]> {
  const { candidate, candidates, languages, metrics, startedMs, timeBudgetMs } = args;
  const base = scoreFuzzyCandidates(candidate, candidates);
  const coverageValues: number[] = [];

  for (const row of base) {
    if (!withinBudget(startedMs, timeBudgetMs)) {
      coverageValues.push(0);
      continue;
    }
    const coverage = await fetchIntegerChapterCoverage(
      row.manga.id,
      languages,
      metrics,
      startedMs,
      timeBudgetMs,
    );
    coverageValues.push(coverage);
  }

  const maxCoverage = Math.max(1, ...coverageValues);
  return base.map((row, index) => {
    const coverage = coverageValues[index] ?? 0;
    const coverageScore = Math.min(1, coverage / maxCoverage);
    const editionPenalty = computeEditionPenalty(row.manga);
    const languagePenalty = computeLanguageMismatchPenalty(candidate, row.manga);
    const englishTitleSimilarity = computeBestEnglishTitleSimilarity(candidate, row.manga);
    const englishTitleBoost = computeEnglishTitleBoost(englishTitleSimilarity);
    const score = (
      (0.45 * row.titleSimilarity) +
      (0.18 * row.tokenOverlap) +
      (0.29 * coverageScore) +
      (0.08 * row.aliasExact) +
      englishTitleBoost
    ) - editionPenalty - languagePenalty;
    return {
      ...row,
      integerChapterCoverage: coverage,
      integerChapterCoverageScore: coverageScore,
      editionPenalty,
      languagePenalty,
      englishTitleSimilarity,
      englishTitleBoost,
      score,
    };
  });
}

async function fetchIntegerChapterCoverage(
  mangaDexId: string,
  languages: string[],
  metrics: RunMetrics,
  startedMs: number,
  timeBudgetMs: number,
): Promise<number> {
  const aggregate = await fetchAggregateChapterNumbers({
    mangaDexId,
    languages,
    includeFallbackAllLanguages: true,
    metrics,
    startedMs,
    timeBudgetMs,
  });
  return aggregate.chapterNumbers.length;
}

function computeEditionPenalty(manga: MangaDexManga): number {
  const haystack = [
    preferredMangaDexTitle(manga),
    ...mangaDexNormalizedTitles(manga),
  ].join(" ").toLowerCase();
  const markers = [
    "webtoon version",
    "oneshot",
    "one shot",
    "promo",
    "pilot",
  ];
  return markers.some((marker) => haystack.includes(marker)) ? 0.08 : 0;
}

function computeLanguageMismatchPenalty(candidate: CandidateRow, manga: MangaDexManga): number {
  const localPrimary = normalizeStrictTitle(primaryTitle(candidate));
  const remotePrimary = normalizeStrictTitle(preferredMangaDexTitle(manga));
  if (!localPrimary || !remotePrimary) return 0;
  return jaroWinkler(localPrimary, remotePrimary) < 0.75 ? 0.05 : 0;
}

function computeBestEnglishTitleSimilarity(candidate: CandidateRow, manga: MangaDexManga): number {
  const localEnglish = normalizeStrictTitle(candidate.title_english ?? "");
  if (!localEnglish) return 0;

  const remoteEnglish = mangaDexEnglishTitles(manga);
  if (remoteEnglish.length === 0) return 0;

  let best = 0;
  for (const title of remoteEnglish) {
    const similarity = jaroWinkler(localEnglish, title);
    if (similarity > best) best = similarity;
  }
  return best;
}

function computeEnglishTitleBoost(similarity: number): number {
  if (similarity >= COLLISION_ENGLISH_HIGH_SIM) return 0.09;
  if (similarity >= COLLISION_ENGLISH_MED_SIM) return 0.05;
  return 0;
}

async function filterMatchesWithAliasMemory(
  supabase: any,
  mangaId: number,
  provider: string,
  matches: MangaDexManga[],
): Promise<{ matches: MangaDexManga[]; aliasHit: boolean }> {
  const candidateIds = Array.from(new Set(matches.map((item) => item.id)));
  if (candidateIds.length === 0) return { matches, aliasHit: false };

  const { data, error } = await supabase
    .from("manga_mapping_alias_memory")
    .select("provider_media_id,decision")
    .eq("manga_id", mangaId)
    .eq("provider", provider)
    .in("provider_media_id", candidateIds);

  if (error) {
    return { matches, aliasHit: false };
  }

  const decisionById = new Map<string, string>();
  for (const row of data ?? []) {
    const typed = row as { provider_media_id?: string; decision?: string };
    if (typed.provider_media_id && typed.decision) {
      decisionById.set(typed.provider_media_id, typed.decision);
    }
  }

  const accepted = matches.filter((item) => decisionById.get(item.id) == "accepted");
  if (accepted.length === 1) {
    return { matches: accepted, aliasHit: true };
  }

  const filtered = matches.filter((item) => {
    const decision = decisionById.get(item.id);
    return decision !== "rejected_collision" && decision !== "rejected_conflict";
  });
  if (filtered.length > 0 && filtered.length < matches.length) {
    return { matches: filtered, aliasHit: true };
  }
  return { matches, aliasHit: false };
}

async function rememberAliasDecision(
  supabase: any,
  mangaId: number,
  provider: string,
  providerMediaId: string,
  decision: "accepted" | "rejected_collision" | "rejected_conflict",
  reason: string,
) {
  const { error } = await supabase
    .from("manga_mapping_alias_memory")
    .upsert({
      manga_id: mangaId,
      provider,
      provider_media_id: providerMediaId,
      decision,
      reason,
      created_at: new Date().toISOString(),
    }, { onConflict: "manga_id,provider,provider_media_id" });
  if (error) {
    // Backward-compatible no-op if table is not migrated yet.
    return;
  }
}

interface FuzzyCandidateScore {
  manga: MangaDexManga;
  score: number;
  titleSimilarity: number;
  tokenOverlap: number;
  aliasExact: number;
  hardConflict: boolean;
}

function scoreFuzzyCandidates(candidate: CandidateRow, candidates: MangaDexManga[]): FuzzyCandidateScore[] {
  const candidateTitles = allCandidateTitles(candidate);
  const candidateTitleSet = new Set(
    candidateTitles.map((title) => normalizeStrictTitle(title)).filter((title) => title.length > 0),
  );
  const candidateTokenSet = tokensFromTitles(candidateTitles);

  return candidates.map((manga) => {
    const dexTitles = mangaDexNormalizedTitles(manga);
    const dexTitleSet = new Set(dexTitles);
    const dexTokenSet = tokensFromNormalizedTitles(dexTitles);
    const titleSimilarity = computeBestTitleSimilarity(candidateTitles, dexTitles);
    const tokenOverlap = jaccardSets(candidateTokenSet, dexTokenSet);
    const aliasExact = hasExactAlias(candidateTitleSet, dexTitleSet) ? 1 : 0;
    const hardConflict = evaluateHardConflict(candidate, manga);
    const score = (0.55 * titleSimilarity) + (0.30 * tokenOverlap) + (0.15 * aliasExact);
    return {
      manga,
      score,
      titleSimilarity,
      tokenOverlap,
      aliasExact,
      hardConflict,
    };
  });
}

function hasExactAlias(left: Set<string>, right: Set<string>): boolean {
  for (const key of left) {
    if (right.has(key)) return true;
  }
  return false;
}

function evaluateHardConflict(candidate: CandidateRow, manga: MangaDexManga): boolean {
  const linkedAl = normalizeLinkedExternalId(manga.attributes?.links?.al);
  const linkedMal = normalizeLinkedExternalId(manga.attributes?.links?.mal);
  const localAl = candidate.anilist_id ? String(candidate.anilist_id) : null;
  const localMal = candidate.mal_id ? String(candidate.mal_id) : null;

  if (localAl && linkedAl && linkedAl !== localAl) return true;
  if (localMal && linkedMal && linkedMal !== localMal) return true;
  return false;
}

function computeBestTitleSimilarity(candidateTitles: string[], dexNormalizedTitles: string[]): number {
  if (candidateTitles.length === 0 || dexNormalizedTitles.length === 0) return 0;
  let best = 0;
  for (const candidateTitle of candidateTitles) {
    const normalizedCandidate = normalizeStrictTitle(candidateTitle);
    if (!normalizedCandidate) continue;
    for (const dexTitle of dexNormalizedTitles) {
      const similarity = jaroWinkler(normalizedCandidate, dexTitle);
      if (similarity > best) best = similarity;
    }
  }
  return best;
}

function tokensFromTitles(titles: string[]): Set<string> {
  return tokensFromNormalizedTitles(titles.map((title) => normalizeStrictTitle(title)));
}

function tokensFromNormalizedTitles(titles: string[]): Set<string> {
  const tokens = new Set<string>();
  for (const title of titles) {
    const normalized = String(title ?? "").trim();
    if (!normalized) continue;
    for (const token of normalized.split(" ")) {
      if (token.length >= 2) tokens.add(token);
    }
  }
  return tokens;
}

function jaccardSets(left: Set<string>, right: Set<string>): number {
  if (left.size === 0 || right.size === 0) return 0;
  let intersection = 0;
  for (const value of left) {
    if (right.has(value)) intersection += 1;
  }
  const union = left.size + right.size - intersection;
  if (union <= 0) return 0;
  return intersection / union;
}

function jaroWinkler(a: string, b: string): number {
  if (a === b) return 1;
  if (!a || !b) return 0;
  const jaro = jaroSimilarity(a, b);
  const prefixLength = commonPrefixLength(a, b, 4);
  const scalingFactor = 0.1;
  return jaro + (prefixLength * scalingFactor * (1 - jaro));
}

function jaroSimilarity(a: string, b: string): number {
  const aLen = a.length;
  const bLen = b.length;
  if (aLen === 0 && bLen === 0) return 1;
  if (aLen === 0 || bLen === 0) return 0;

  const matchDistance = Math.max(0, Math.floor(Math.max(aLen, bLen) / 2) - 1);
  const aMatches = new Array<boolean>(aLen).fill(false);
  const bMatches = new Array<boolean>(bLen).fill(false);

  let matches = 0;
  for (let i = 0; i < aLen; i += 1) {
    const start = Math.max(0, i - matchDistance);
    const end = Math.min(i + matchDistance + 1, bLen);
    for (let j = start; j < end; j += 1) {
      if (bMatches[j]) continue;
      if (a[i] !== b[j]) continue;
      aMatches[i] = true;
      bMatches[j] = true;
      matches += 1;
      break;
    }
  }

  if (matches === 0) return 0;

  let transpositions = 0;
  let k = 0;
  for (let i = 0; i < aLen; i += 1) {
    if (!aMatches[i]) continue;
    while (!bMatches[k]) k += 1;
    if (a[i] !== b[k]) transpositions += 1;
    k += 1;
  }

  return (
    (matches / aLen) +
    (matches / bLen) +
    ((matches - (transpositions / 2)) / matches)
  ) / 3;
}

function commonPrefixLength(a: string, b: string, maxLength: number): number {
  const limit = Math.min(maxLength, a.length, b.length);
  let length = 0;
  while (length < limit && a[length] === b[length]) {
    length += 1;
  }
  return length;
}

async function fetchMappedMangaDexTitle(
  mangaDexId: string,
  metrics: RunMetrics,
  startedMs: number,
  timeBudgetMs: number,
): Promise<{ manga: MangaDexManga | null; notFound: boolean; rateLimited: boolean }> {
  const url = `${MANGADEX_API}/manga/${encodeURIComponent(mangaDexId)}`;
  const outcome = await fetchMangaDexEntity(url, metrics, startedMs, timeBudgetMs);
  if (outcome.rateLimited) return { manga: null, notFound: false, rateLimited: true };
  if (outcome.notFound || !outcome.payload?.data) return { manga: null, notFound: true, rateLimited: false };
  return { manga: outcome.payload.data as MangaDexManga, notFound: false, rateLimited: false };
}

async function fetchMangaDexEntity(
  url: string,
  metrics: RunMetrics,
  startedMs: number,
  timeBudgetMs: number,
): Promise<{ payload: any; notFound: boolean; rateLimited: boolean }> {
  let attempt = 0;
  while (true) {
    if (!withinBudget(startedMs, timeBudgetMs)) {
      throw new Error("Time budget reached");
    }
    try {
      await waitForMangaDexBudget(metrics);
      const response = await fetch(url, {
        method: "GET",
        headers: { "Content-Type": "application/json" },
      });

      if (response.ok) {
        markMangaDexSuccess();
        return { payload: await response.json(), notFound: false, rateLimited: false };
      }
      if (response.status === 404) {
        markMangaDexSuccess();
        return { payload: null, notFound: true, rateLimited: false };
      }
      if (response.status === 429) {
        registerMangaDex429(metrics);
        return { payload: null, notFound: false, rateLimited: true };
      }
      markMangaDexSuccess();
      if (response.status >= 500 && attempt < MAX_RETRIES) {
        await sleep((300 * (2 ** attempt)) + Math.floor(Math.random() * 250));
        attempt += 1;
        continue;
      }
      const body = await response.text().catch(() => "");
      throw new Error(`MangaDex ${response.status}: ${body.slice(0, 240)}`);
    } catch (error) {
      if (attempt >= MAX_RETRIES) throw error;
      await sleep((300 * (2 ** attempt)) + Math.floor(Math.random() * 250));
      attempt += 1;
    }
  }
}

function normalizeLinkedExternalId(value: string | undefined): string | null {
  if (!value) return null;
  const digits = String(value).match(/\d+/);
  return digits?.[0] ?? null;
}

function normalizeStrictTitle(value: string): string {
  return normalizeText(value).toLowerCase().replace(/\s+/g, " ").trim();
}

function preferredMangaDexTitle(item: MangaDexManga): string {
  const titles = item.attributes?.title;
  if (!titles) return item.id;
  return titles.en
    ?? titles["en-us"]
    ?? Object.values(titles)[0]
    ?? item.id;
}

function mangaDexNormalizedTitles(item: MangaDexManga): string[] {
  const values: string[] = [];
  const title = item.attributes?.title ?? {};
  values.push(...Object.values(title));
  const altTitles = item.attributes?.altTitles ?? [];
  for (const alt of altTitles) values.push(...Object.values(alt));

  return Array.from(
    new Set(
      values
        .map((value) => normalizeStrictTitle(value))
        .filter((value) => value.length > 0),
      ),
  );
}

function mangaDexEnglishTitles(item: MangaDexManga): string[] {
  const values: string[] = [];
  const title = item.attributes?.title ?? {};
  for (const [lang, value] of Object.entries(title)) {
    if (lang.toLowerCase().startsWith("en")) values.push(value);
  }

  const altTitles = item.attributes?.altTitles ?? [];
  for (const alt of altTitles) {
    for (const [lang, value] of Object.entries(alt)) {
      if (lang.toLowerCase().startsWith("en")) values.push(value);
    }
  }

  return Array.from(
    new Set(
      values
        .map((value) => normalizeStrictTitle(value))
        .filter((value) => value.length > 0),
    ),
  );
}

async function searchMangaDex(
  title: string,
  metrics: RunMetrics,
  startedMs: number,
  timeBudgetMs: number,
  searchCache: Map<string, MangaDexManga[]>,
): Promise<MangaDexManga[]> {
  const cacheKey = title.toLowerCase();
  if (searchCache.has(cacheKey)) {
    return searchCache.get(cacheKey) ?? [];
  }

  const url = new URL(`${MANGADEX_API}/manga`);
  url.searchParams.set("title", title);
  url.searchParams.set("limit", "10");
  url.searchParams.append("includes[]", "cover_art");

  const data = await fetchJsonWithRetry(url.toString(), {}, metrics, startedMs, timeBudgetMs);
  const rows = Array.isArray(data?.data) ? (data.data as MangaDexManga[]) : [];
  searchCache.set(cacheKey, rows);
  return rows;
}

async function fetchAggregateChapterNumbers(args: {
  mangaDexId: string;
  languages: string[];
  includeFallbackAllLanguages: boolean;
  metrics: RunMetrics;
  startedMs: number;
  timeBudgetMs: number;
}): Promise<{ chapterNumbers: number[]; fractionalSkipped: number }> {
  const { mangaDexId, languages, includeFallbackAllLanguages, metrics, startedMs, timeBudgetMs } = args;
  let fractionalSkipped = 0;

  for (const language of languages) {
    if (!withinBudget(startedMs, timeBudgetMs)) break;
    const aggregate = await fetchMangaDexAggregate(mangaDexId, [language], metrics, startedMs, timeBudgetMs);
    const parsed = parseAggregateChapters(aggregate);
    fractionalSkipped += parsed.fractionalSkipped;
    if (parsed.chapterNumbers.length > 0) {
      return { chapterNumbers: parsed.chapterNumbers, fractionalSkipped };
    }
  }

  if (includeFallbackAllLanguages && withinBudget(startedMs, timeBudgetMs)) {
    const aggregate = await fetchMangaDexAggregate(mangaDexId, null, metrics, startedMs, timeBudgetMs);
    const parsed = parseAggregateChapters(aggregate);
    fractionalSkipped += parsed.fractionalSkipped;
    return { chapterNumbers: parsed.chapterNumbers, fractionalSkipped };
  }

  return { chapterNumbers: [], fractionalSkipped };
}

async function fetchMangaDexAggregate(
  mangaDexId: string,
  languages: string[] | null,
  metrics: RunMetrics,
  startedMs: number,
  timeBudgetMs: number,
) {
  const url = new URL(`${MANGADEX_API}/manga/${encodeURIComponent(mangaDexId)}/aggregate`);
  if (languages && languages.length > 0) {
    for (const language of languages) {
      url.searchParams.append("translatedLanguage[]", language);
    }
  }
  return fetchJsonWithRetry(url.toString(), {}, metrics, startedMs, timeBudgetMs);
}

function parseAggregateChapters(payload: any): { chapterNumbers: number[]; fractionalSkipped: number } {
  const volumes = payload?.volumes;
  if (!volumes || typeof volumes !== "object") {
    return { chapterNumbers: [], fractionalSkipped: 0 };
  }

  const chapterSet = new Set<number>();
  let fractionalSkipped = 0;

  for (const volume of Object.values(volumes as Record<string, any>)) {
    const chapters = volume?.chapters;
    if (!chapters || typeof chapters !== "object") continue;
    for (const key of Object.keys(chapters)) {
      const chapterKey = String(key).trim();
      if (/^\d+$/.test(chapterKey)) {
        const parsed = Number.parseInt(chapterKey, 10);
        if (Number.isFinite(parsed) && parsed > 0) {
          chapterSet.add(parsed);
        }
        continue;
      }
      if (/^\d+\.\d+$/.test(chapterKey)) {
        fractionalSkipped += 1;
      }
    }
  }

  return {
    chapterNumbers: Array.from(chapterSet).sort((a, b) => a - b),
    fractionalSkipped,
  };
}

async function upsertChapterRows(supabase: any, mangaId: number, chapterNumbers: number[]) {
  const chunkSize = 400;
  for (let i = 0; i < chapterNumbers.length; i += chunkSize) {
    const chunk = chapterNumbers.slice(i, i + chunkSize);
    const { data: existingRows, error: existingError } = await supabase
      .from("chapters")
      .select("number")
      .eq("manga_id", mangaId)
      .in("number", chunk);
    if (existingError) throw existingError;

    const existingNumbers = new Set<number>(
      (existingRows ?? [])
        .map((row: { number?: number | null }) => Number(row?.number))
        .filter((value: number) => Number.isFinite(value)),
    );
    const missing = chunk.filter((number) => !existingNumbers.has(number));
    if (missing.length === 0) continue;

    const payload = missing.map((number) => ({
      manga_id: mangaId,
      number,
      title: `Chapter ${number}`,
    }));

    const { error } = await supabase.from("chapters").insert(payload);
    if (error?.code === "23505") {
      // In rare race windows, another worker may insert between read+insert.
      for (const row of payload) {
        const { error: singleError } = await supabase.from("chapters").insert(row);
        if (singleError && singleError.code !== "23505") throw singleError;
      }
      continue;
    }
    if (error) throw error;
  }
}

async function fetchChapterCount(supabase: any, mangaId: number): Promise<number> {
  const { count, error } = await supabase
    .from("chapters")
    .select("id", { head: true, count: "exact" })
    .eq("manga_id", mangaId);
  if (error) throw error;
  return count ?? 0;
}

async function updateMangaSyncFields(
  supabase: any,
  candidate: CandidateRow,
  maxImportedNumber: number | null,
) {
  const updatePayload: Record<string, unknown> = {
    last_synced_at: new Date().toISOString(),
  };

  if (maxImportedNumber && maxImportedNumber > 0) {
    const existing = candidate.chapters ?? 0;
    updatePayload.chapters = Math.max(existing, maxImportedNumber);
  }

  const { error } = await supabase
    .from("manga")
    .update(updatePayload)
    .eq("id", candidate.id);
  if (error) throw error;
}

async function fetchJsonWithRetry(
  url: string,
  init: RequestInit,
  metrics: RunMetrics,
  startedMs: number,
  timeBudgetMs: number,
) {
  let attempt = 0;
  while (true) {
    if (!withinBudget(startedMs, timeBudgetMs)) {
      throw new Error("Time budget reached");
    }

    try {
      await waitForMangaDexBudget(metrics);
      const response = await fetch(url, {
        method: "GET",
        headers: { "Content-Type": "application/json" },
        ...init,
      });

      if (response.ok) {
        markMangaDexSuccess();
        return await response.json();
      }

      const shouldRetry = response.status === 429 || response.status >= 500;
      if (response.status === 429) {
        registerMangaDex429(metrics);
      } else {
        markMangaDexSuccess();
      }

      if (shouldRetry && attempt < MAX_RETRIES) {
        const retryAfter = Number(response.headers.get("retry-after") ?? "0");
        const backoff = retryAfter > 0
          ? retryAfter * 1000
          : (300 * (2 ** attempt)) + Math.floor(Math.random() * 250);
        await sleep(backoff);
        attempt += 1;
        continue;
      }

      const body = await response.text().catch(() => "");
      throw new Error(`MangaDex ${response.status}: ${body.slice(0, 240)}`);
    } catch (error) {
      if (attempt >= MAX_RETRIES) throw error;
      await sleep((300 * (2 ** attempt)) + Math.floor(Math.random() * 250));
      attempt += 1;
    }
  }
}

async function waitForMangaDexBudget(metrics: RunMetrics) {
  const now = Date.now();
  const blockedUntil = Math.max(mangaDexRateLimiter.nextAllowedAt, mangaDexRateLimiter.cooldownUntil);
  const waitMs = Math.max(0, blockedUntil - now);
  if (waitMs > 0) {
    metrics.rate_limiter_wait_ms += waitMs;
    await sleep(waitMs);
  }
  mangaDexRateLimiter.nextAllowedAt = Date.now() + mangaDexRateLimiter.minIntervalMs;
}

function registerMangaDex429(metrics: RunMetrics) {
  metrics.api_429_count += 1;
  mangaDexRateLimiter.consecutive429 += 1;
  if (mangaDexRateLimiter.consecutive429 < BURST_429_THRESHOLD) return;

  const cooldownMs = DEFAULT_MANGADEX_429_COOLDOWN_MS
    * Math.max(1, mangaDexRateLimiter.consecutive429 - BURST_429_THRESHOLD + 1);
  mangaDexRateLimiter.cooldownUntil = Math.max(
    mangaDexRateLimiter.cooldownUntil,
    Date.now() + cooldownMs,
  );
  metrics["429_cooldown_count"] += 1;
  mangaDexRateLimiter.consecutive429 = 0;
}

function markMangaDexSuccess() {
  mangaDexRateLimiter.consecutive429 = 0;
}

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function acquireImportLock(supabase: any, key: string, ttlSeconds: number): Promise<boolean> {
  try {
    const { data, error } = await supabase.rpc("acquire_import_lock", {
      p_key: key,
      p_ttl_seconds: ttlSeconds,
    });
    if (error) {
      console.error("Acquire lock error:", error);
      return true;
    }
    return Boolean(data);
  } catch (error) {
    console.error("Acquire lock exception:", error);
    return true;
  }
}

async function releaseImportLock(supabase: any, key: string): Promise<void> {
  try {
    const { error } = await supabase.rpc("release_import_lock", { p_key: key });
    if (error) console.error("Release lock error:", error);
  } catch (error) {
    console.error("Release lock exception:", error);
  }
}

async function startImportRun(
  supabase: any,
  mediaType: string,
  runType: string,
  payload: unknown,
): Promise<number | null> {
  try {
    const { data, error } = await supabase
      .from("import_runs")
      .insert({
        media_type: mediaType,
        run_type: runType,
        payload,
        status: "running",
        started_at: new Date().toISOString(),
      })
      .select("id")
      .single();
    if (error) {
      console.error("import_runs insert error:", error);
      return null;
    }
    return data?.id ?? null;
  } catch (error) {
    console.error("import_runs insert exception:", error);
    return null;
  }
}

async function finishImportRun(
  supabase: any,
  runId: number | null,
  status: string,
  results: unknown,
  message: string | null,
  startedAtMs: number,
) {
  if (!runId) return;
  try {
    const durationMs = Date.now() - startedAtMs;
    const { error } = await supabase
      .from("import_runs")
      .update({
        status,
        results,
        message,
        finished_at: new Date().toISOString(),
        duration_ms: durationMs,
      })
      .eq("id", runId);
    if (error) {
      console.error("import_runs update error:", error);
    }
  } catch (error) {
    console.error("import_runs update exception:", error);
  }
}
