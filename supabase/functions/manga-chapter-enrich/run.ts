// manga-chapter-enrich run (F51). index.ts checks the import secret and builds
// the service-role client, then calls runChapterEnrich. This file is the run:
// lock, time budget, and the candidate loop. Title selection is matching.ts,
// MangaDex HTTP is mangadex.ts, and table/RPC writes are repository.ts.
// Tests inject fetch and sleep; production leaves them unset.
import { createMangaDexClient, type MangaDexClient } from "./mangadex.ts";
import {
  allCandidateTitles,
  applyCollisionCoverage,
  chooseEnglishPreferredCollisionCandidate,
  COLLISION_TIEBREAK_MIN_MARGIN,
  COLLISION_TIEBREAK_MIN_SCORE,
  computeBestTitleSimilarity,
  DEFAULT_TITLE_SIMILARITY_FLOOR,
  evaluateHardConflict,
  mangaDexNormalizedTitles,
  normalizeLinkedExternalId,
  preferredMangaDexTitle,
  primaryTitle,
  scoreFuzzyCandidates,
  selectTitleMatch,
  type CandidateRow,
  type CollisionCandidateScore,
  type MangaDexManga,
  type MappingMethod,
  type MappingResolution,
  type MatcherMode,
} from "./matching.ts";
import {
  acquireImportLock,
  enqueueMappingReview,
  fetchCandidates,
  fetchChapterCount,
  fetchExistingMapping,
  filterMatchesWithAliasMemory,
  finishImportRun,
  persistMangaChapterEnrichState,
  persistVerifyState,
  releaseImportLock,
  rememberAliasDecision,
  resolveRuntimeMatcherConfig,
  startImportRun,
  updateMangaSyncFields,
  upsertChapterRows,
  upsertMapping,
  type CandidateProcessResult,
  type MappingRow,
  type RuntimeMatcherConfig,
} from "./repository.ts";

const DEFAULT_LIMIT = 20;
const DEFAULT_TIME_BUDGET_MS = 45_000;
const DEFAULT_LOCK_TTL_SECONDS = 900;
const DEFAULT_MATCHER_MODE = "fuzzy_v2";
const DEFAULT_FUZZY_MIN_CONFIDENCE = 0.95;
const DEFAULT_FUZZY_MIN_MARGIN = 0.10;
const DEFAULT_VERIFY_ENABLED = true;
const DEFAULT_COLLISION_TIEBREAK_ENABLED = true;
const DEFAULT_WRONG_MAP_PROXY_RATE_LIMIT = 0.3;

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

export type ChapterEnrichRuntime = {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  payload: EnrichPayload;
  /** Offline tests inject these. Production leaves them unset (global fetch, real timers). */
  fetch?: typeof globalThis.fetch;
  sleep?: (ms: number) => Promise<void>;
};

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function runChapterEnrich(runtime: ChapterEnrichRuntime): Promise<Response> {
  const dex = createMangaDexClient({
    fetch: runtime.fetch ?? ((input, init) => globalThis.fetch(input, init)),
    sleep: runtime.sleep ?? sleep,
    withinBudget,
  });
  return await runChapterEnrichBody(runtime.supabase, runtime.payload, dex);
}

async function runChapterEnrichBody(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  payload: EnrichPayload,
  dex: MangaDexClient,
): Promise<Response> {
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
    const lockOutcome = await acquireImportLock(
      supabase,
      "manga-chapter-enrich",
      normalizedPayload.lockTtlSeconds,
    );
    if (lockOutcome !== "acquired") {
      const reason = lockOutcome === "busy" ? "locked" : "unavailable";
      await finishImportRun(supabase, runId, "skipped", metrics, reason, startedMs);
      return json({ success: true, skipped: true, reason, results: metrics }, 200);
    }
    lockAcquired = true;

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
          dex,
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
        await persistMangaChapterEnrichState(supabase, candidate, result, runId, startedMs);
      } catch (error) {
        metrics.errors += 1;
        console.error(`manga-chapter-enrich candidate ${candidate.id} failed:`, error);
        await persistMangaChapterEnrichState(supabase, candidate, {
          unresolved: true,
          unresolvedReason: "worker_error",
          insertedCount: 0,
          fractionalSkipped: 0,
        }, runId, startedMs, String((error as Error).message ?? error));
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
}

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
  const matcherMode = normalizeMatcherMode(payload.matcherMode ?? readEnv("MANGA_MATCHER_MODE"));
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

function readEnv(name: string): string | undefined {
  try {
    return Deno.env.get(name);
  } catch {
    // Offline tests have no env permission. Production grants it; a missing var still returns undefined.
    return undefined;
  }
}

function parseFloatEnv(name: string, fallback: number): number {
  const raw = readEnv(name);
  if (!raw) return fallback;
  const parsed = Number.parseFloat(raw);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function parseBooleanEnv(name: string, fallback: boolean): boolean {
  const raw = readEnv(name);
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

function withinBudget(startedMs: number, timeBudgetMs: number): boolean {
  return Date.now() - startedMs < Math.max(0, timeBudgetMs - 250);
}

async function processCandidate(args: {
  dex: MangaDexClient;
  // deno-lint-ignore no-explicit-any
  supabase: any;
  candidate: CandidateRow;
  payload: Required<EnrichPayload>;
  matcherConfig: RuntimeMatcherConfig;
  metrics: RunMetrics;
  startedMs: number;
  searchCache: Map<string, MangaDexManga[]>;
}): Promise<CandidateProcessResult> {
  const { dex, supabase, candidate, payload, matcherConfig, metrics, startedMs, searchCache } = args;
  if ((payload.zeroRowOnly || payload.crunchMode) && (candidate.chapter_row_count ?? 0) > 0) {
    // Defensive guard: crunch mode must never mutate already-covered manga.
    return { unresolved: false, providerMediaId: null, insertedCount: 0, fractionalSkipped: 0 };
  }
  if (candidate.priority_class === 5) {
    metrics.auto_retry_due_processed += 1;
  }

  let existingMapping = await fetchExistingMapping(supabase, candidate.id);
  let mappingMethod: MappingMethod | undefined;
  let mangaDexId = existingMapping?.provider_media_id ?? null;

  if (existingMapping && payload.verifyMappings && isMappingVerificationDue(existingMapping.next_verify_at)) {
    const verification = await verifyExistingMapping({
      dex,
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
      return { unresolved: true, providerMediaId: mangaDexId, unresolvedReason: "mapping_verification_pending", insertedCount: 0, fractionalSkipped: 0 };
    } else if (verification.mapping) {
      existingMapping = verification.mapping;
      mangaDexId = verification.mapping.provider_media_id;
    }
  }

  if (!mangaDexId) {
    const resolution = await resolveMapping({
      dex,
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
      return { unresolved: true, providerMediaId: null, unresolvedReason: reason, insertedCount: 0, fractionalSkipped: 0 };
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
      return { unresolved: true, providerMediaId: null, unresolvedReason: "mapping_conflict", insertedCount: 0, fractionalSkipped: 0 };
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

  const aggregate = await dex.fetchAggregateChapterNumbers({
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
    providerMediaId: mangaDexId,
    unresolved: false,
    insertedCount,
    fractionalSkipped: aggregate.fractionalSkipped,
  };
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

async function verifyExistingMapping(args: {
  dex: MangaDexClient;
  // deno-lint-ignore no-explicit-any
  supabase: any;
  candidate: CandidateRow;
  mapping: MappingRow;
  metrics: RunMetrics;
  startedMs: number;
  timeBudgetMs: number;
}): Promise<{ deactivated: boolean; skipCurrentRun: boolean; mapping?: MappingRow }> {
  const { dex, supabase, candidate, mapping, metrics, startedMs, timeBudgetMs } = args;
  metrics.verify_checked += 1;

  const verifyResult = await dex.fetchMappedMangaDexTitle(
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
      await persistVerifyState(supabase, candidate.id, {
        verify_status: "mismatch",
        verify_fail_count: failedCount,
        status: "inactive",
        last_verify_reason: "not_found",
        last_mismatch_at: new Date().toISOString(),
        next_verify_at: new Date().toISOString(),
      });
      metrics.verify_deactivated += 1;
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
      await persistVerifyState(supabase, candidate.id, {
        verify_status: "mismatch",
        verify_fail_count: failedCount,
        status: "inactive",
        last_verify_reason: conflict ? "external_id_conflict" : "title_similarity_low",
        last_mismatch_at: new Date().toISOString(),
        next_verify_at: new Date().toISOString(),
      });
      metrics.verify_deactivated += 1;
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

async function resolveMapping(args: {
  dex: MangaDexClient;
  // deno-lint-ignore no-explicit-any
  supabase: any;
  candidate: CandidateRow;
  payload: Required<EnrichPayload>;
  matcherMode: MatcherMode;
  metrics: RunMetrics;
  startedMs: number;
  timeBudgetMs: number;
  searchCache: Map<string, MangaDexManga[]>;
}): Promise<MappingResolution> {
  const { dex, supabase, candidate, payload, matcherMode, metrics, startedMs, timeBudgetMs, searchCache } = args;
  const queryTitles = allCandidateTitles(candidate).slice(0, 8);
  if (queryTitles.length === 0) {
    return { mapped: false, queryTitle: null, reason: "missing_titles", sample: [] };
  }

  const resultMap = new Map<string, MangaDexManga>();
  for (const title of queryTitles) {
    if (!withinBudget(startedMs, timeBudgetMs)) break;
    const rows = await dex.searchMangaDex(title, metrics, startedMs, timeBudgetMs, searchCache);
    for (const row of rows) resultMap.set(row.id, row);
  }

  // Human-reviewed alias decisions apply before either external-id or title selection,
  // including single candidates and the case where every candidate was rejected.
  const aliasFiltered = await filterMatchesWithAliasMemory(
    supabase, candidate.id, "mangadex", Array.from(resultMap.values()),
  );
  if (aliasFiltered.aliasHit) metrics.alias_memory_hits += 1;
  const results = aliasFiltered.matches;
  const sample = results.slice(0, 8).map((item) => ({
    id: item.id,
    title: preferredMangaDexTitle(item),
    links: item.attributes?.links ?? {},
  }));

  if (results.length === 0) {
    return { mapped: false, queryTitle: queryTitles[0], reason: aliasFiltered.aliasHit ? "alias_rejected" : "no_candidates", sample };
  }

  const anilistId = candidate.anilist_id ? String(candidate.anilist_id) : null;
  if (anilistId) {
    const matches = results.filter((item) => normalizeLinkedExternalId(item.attributes?.links?.al) === anilistId);
    const externalResolution = await resolveAmbiguousExternalMatches({
      dex,
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
      dex,
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

  return selectTitleMatch({
    candidate,
    results,
    queryTitles,
    matcherMode,
    minConfidence: payload.minConfidence,
    minMargin: payload.minMargin,
    sample,
    metrics,
  });
}

async function resolveAmbiguousExternalMatches(args: {
  dex: MangaDexClient;
  // deno-lint-ignore no-explicit-any
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
    dex,
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
    dex,
    candidate,
    candidates: matches,
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
  const rejectedIds = matches
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

async function scoreCollisionCandidates(args: {
  dex: MangaDexClient;
  candidate: CandidateRow;
  candidates: MangaDexManga[];
  languages: string[];
  metrics: RunMetrics;
  startedMs: number;
  timeBudgetMs: number;
}): Promise<CollisionCandidateScore[]> {
  const { dex, candidate, candidates, languages, metrics, startedMs, timeBudgetMs } = args;
  const base = scoreFuzzyCandidates(candidate, candidates);
  const coverageValues: number[] = [];

  for (const row of base) {
    if (!withinBudget(startedMs, timeBudgetMs)) {
      coverageValues.push(0);
      continue;
    }
    const coverage = await fetchIntegerChapterCoverage(
      dex,
      row.manga.id,
      languages,
      metrics,
      startedMs,
      timeBudgetMs,
    );
    coverageValues.push(coverage);
  }

  return applyCollisionCoverage(candidate, base, coverageValues);
}

async function fetchIntegerChapterCoverage(
  dex: MangaDexClient,
  mangaDexId: string,
  languages: string[],
  metrics: RunMetrics,
  startedMs: number,
  timeBudgetMs: number,
): Promise<number> {
  const aggregate = await dex.fetchAggregateChapterNumbers({
    mangaDexId,
    languages,
    includeFallbackAllLanguages: true,
    metrics,
    startedMs,
    timeBudgetMs,
  });
  return aggregate.chapterNumbers.length;
}
