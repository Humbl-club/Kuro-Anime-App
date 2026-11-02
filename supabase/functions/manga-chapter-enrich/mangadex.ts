// MangaDex HTTP for manga-chapter-enrich: URL, the run's time budget (one
// AbortSignal for the fetch and its body), rate limit, retries, and response
// parsing. Fetch and sleep are injected. Retry delays and the 429 cooldown
// are unchanged; waits are clamped to the budget still left.
import type { MangaDexManga } from "./matching.ts";

const MANGADEX_API = "https://api.mangadex.org";
const MAX_RETRIES = 3;
const DEFAULT_MANGADEX_MAX_RPS = 3;
const DEFAULT_MANGADEX_429_COOLDOWN_MS = 2_500;
const BURST_429_THRESHOLD = 2;

interface MangaDexRateLimiterState {
  minIntervalMs: number;
  nextAllowedAt: number;
  cooldownUntil: number;
  consecutive429: number;
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

// Process-local and deliberate: one isolate shares this limiter across runs.
const mangaDexRateLimiter: MangaDexRateLimiterState = {
  minIntervalMs: Math.max(
    1,
    Math.round(1000 / Math.max(0.1, parseFloatEnv("MANGADEX_MAX_RPS", DEFAULT_MANGADEX_MAX_RPS))),
  ),
  nextAllowedAt: 0,
  cooldownUntil: 0,
  consecutive429: 0,
};

/** One MangaDex volume from /aggregate: integer volume number and its integer chapter range. */
export interface AggregateVolume {
  volume: number;
  firstChapter: number;
  lastChapter: number;
  chapterCount: number;
}

export interface AggregateChapters {
  chapterNumbers: number[];
  fractionalSkipped: number;
  /** Volume grouping kept from the same aggregate (chapters without a volume are not grouped). */
  volumes: AggregateVolume[];
}

export interface MangaDexCallMetrics {
  api_429_count: number;
  rate_limiter_wait_ms: number;
  "429_cooldown_count": number;
}

export type MangaDexClient = {
  searchMangaDex(
    title: string,
    metrics: MangaDexCallMetrics,
    startedMs: number,
    timeBudgetMs: number,
    searchCache: Map<string, MangaDexManga[]>,
  ): Promise<MangaDexManga[]>;
  fetchMappedMangaDexTitle(
    mangaDexId: string,
    metrics: MangaDexCallMetrics,
    startedMs: number,
    timeBudgetMs: number,
  ): Promise<{ manga: MangaDexManga | null; notFound: boolean; rateLimited: boolean }>;
  fetchAggregateChapterNumbers(args: {
    mangaDexId: string;
    languages: string[];
    includeFallbackAllLanguages: boolean;
    metrics: MangaDexCallMetrics;
    startedMs: number;
    timeBudgetMs: number;
  }): Promise<AggregateChapters>;
};

function budgetRemainingMs(startedMs: number, timeBudgetMs: number): number {
  return startedMs + timeBudgetMs - Date.now();
}

function isBudgetError(error: unknown): boolean {
  return error instanceof Error && error.message === "Time budget reached";
}

function openRunDeadline(startedMs: number, timeBudgetMs: number): { signal: AbortSignal; close: () => void } {
  const controller = new AbortController();
  const remaining = budgetRemainingMs(startedMs, timeBudgetMs);
  if (remaining <= 0) {
    controller.abort();
    return { signal: controller.signal, close() {} };
  }
  const timer = setTimeout(() => controller.abort(), remaining);
  return {
    signal: controller.signal,
    close() {
      clearTimeout(timer);
    },
  };
}

function cancelResponseBody(response: Response): void {
  response.body?.cancel().catch(() => {});
}

async function consumeBody(response: Response, signal: AbortSignal, kind: "json" | "text"): Promise<unknown> {
  // response.json() locks the body, so a later body.cancel() cannot abort it.
  // Own the reader and cancel that on the run deadline.
  if (!response.body) {
    if (signal.aborted) throw new Error("Time budget reached");
    return kind === "json" ? await response.json() : await response.text();
  }
  const reader = response.body.getReader();
  const budgetError = () => {
    reader.cancel().catch(() => {});
    return new Error("Time budget reached");
  };
  if (signal.aborted) throw budgetError();

  let onAbort: () => void = () => {};
  const aborted = new Promise<void>((resolve) => {
    onAbort = () => {
      reader.cancel().catch(() => {});
      resolve();
    };
  });
  signal.addEventListener("abort", onAbort);

  const readAll = readBodyText(reader, signal).then((text) => kind === "json" ? JSON.parse(text) : text);
  const settled = readAll.then(
    (value) => ({ status: "value" as const, value }),
    (error: unknown) => ({ status: "error" as const, error }),
  );
  try {
    const winner = await Promise.race([
      settled,
      aborted.then(() => ({ status: "aborted" as const })),
    ]);
    if (winner.status === "value" && !signal.aborted) return winner.value;
    if (winner.status === "error" && !signal.aborted) throw winner.error;
    throw budgetError();
  } finally {
    signal.removeEventListener("abort", onAbort);
  }
}

async function readBodyText(reader: ReadableStreamDefaultReader<Uint8Array>, signal: AbortSignal): Promise<string> {
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (signal.aborted) throw new Error("Time budget reached");
    if (done) break;
    chunks.push(value);
    total += value.byteLength;
  }
  if (signal.aborted) throw new Error("Time budget reached");
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

/**
 * /manga/{id}/aggregate -> integer chapter numbers (fractional chapters skipped and counted) and
 * the volume grouping MangaDex already returns: { volumes: { "<vol>": { chapters: { "<ch>": ... } } } }.
 * Only integer volume keys > 0 with at least one integer chapter become volume groups; the
 * "none" bucket (chapters not yet collected) is not a volume.
 */
// deno-lint-ignore no-explicit-any
export function parseAggregatePayload(payload: any): AggregateChapters {
  const volumes = payload?.volumes;
  if (!volumes || typeof volumes !== "object") {
    return { chapterNumbers: [], fractionalSkipped: 0, volumes: [] };
  }

  const chapterSet = new Set<number>();
  let fractionalSkipped = 0;
  const groups = new Map<number, Set<number>>();

  // deno-lint-ignore no-explicit-any
  for (const [volumeKey, volume] of Object.entries(volumes as Record<string, any>)) {
    const chapters = volume?.chapters;
    if (!chapters || typeof chapters !== "object") continue;
    const volumeNumber = /^\d+$/.test(String(volumeKey).trim()) ? Number.parseInt(String(volumeKey).trim(), 10) : null;
    for (const key of Object.keys(chapters)) {
      const chapterKey = String(key).trim();
      if (/^\d+$/.test(chapterKey)) {
        const parsed = Number.parseInt(chapterKey, 10);
        if (Number.isFinite(parsed) && parsed > 0) {
          chapterSet.add(parsed);
          if (volumeNumber !== null && volumeNumber > 0) {
            if (!groups.has(volumeNumber)) groups.set(volumeNumber, new Set());
            groups.get(volumeNumber)?.add(parsed);
          }
        }
        continue;
      }
      if (/^\d+\.\d+$/.test(chapterKey)) {
        fractionalSkipped += 1;
      }
    }
  }

  const volumeGroups: AggregateVolume[] = [...groups.entries()]
    .map(([volume, set]) => {
      const list = [...set];
      return { volume, firstChapter: Math.min(...list), lastChapter: Math.max(...list), chapterCount: list.length };
    })
    .sort((a, b) => a.volume - b.volume);

  return {
    chapterNumbers: Array.from(chapterSet).sort((a, b) => a - b),
    fractionalSkipped,
    volumes: volumeGroups,
  };
}

export function createMangaDexClient(deps: {
  fetch: typeof globalThis.fetch;
  sleep: (ms: number) => Promise<void>;
  withinBudget: (startedMs: number, timeBudgetMs: number) => boolean;
}): MangaDexClient {
  const activeFetch = deps.fetch;
  const activeSleep = deps.sleep;
  const withinBudget = deps.withinBudget;

  async function sleepWithinBudget(ms: number, startedMs: number, timeBudgetMs: number): Promise<void> {
    const remaining = budgetRemainingMs(startedMs, timeBudgetMs);
    if (remaining <= 0) throw new Error("Time budget reached");
    const clamped = Math.min(Math.max(0, ms), remaining);
    if (clamped > 0) await activeSleep(clamped);
    if (budgetRemainingMs(startedMs, timeBudgetMs) <= 0) throw new Error("Time budget reached");
  }

  function budgetEnded(startedMs: number, timeBudgetMs: number, signal: AbortSignal): boolean {
    return signal.aborted || !withinBudget(startedMs, timeBudgetMs) || budgetRemainingMs(startedMs, timeBudgetMs) <= 0;
  }

  async function waitForMangaDexBudget(metrics: MangaDexCallMetrics, startedMs: number, timeBudgetMs: number) {
    const now = Date.now();
    const blockedUntil = Math.max(mangaDexRateLimiter.nextAllowedAt, mangaDexRateLimiter.cooldownUntil);
    const waitMs = Math.max(0, blockedUntil - now);
    const remaining = budgetRemainingMs(startedMs, timeBudgetMs);
    if (remaining <= 0 || !withinBudget(startedMs, timeBudgetMs)) {
      throw new Error("Time budget reached");
    }
    const clamped = Math.min(waitMs, remaining);
    if (clamped > 0) {
      metrics.rate_limiter_wait_ms += clamped;
      await activeSleep(clamped);
      if (budgetRemainingMs(startedMs, timeBudgetMs) <= 0 || !withinBudget(startedMs, timeBudgetMs)) {
        throw new Error("Time budget reached");
      }
    }
    mangaDexRateLimiter.nextAllowedAt = Date.now() + mangaDexRateLimiter.minIntervalMs;
  }

  function registerMangaDex429(metrics: MangaDexCallMetrics) {
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

  // deno-lint-ignore no-explicit-any
  async function fetchJsonWithRetry(
    url: string,
    init: RequestInit,
    metrics: MangaDexCallMetrics,
    startedMs: number,
    timeBudgetMs: number,
  ): Promise<any> {
    const deadline = openRunDeadline(startedMs, timeBudgetMs);
    try {
      let attempt = 0;
      while (true) {
        if (budgetEnded(startedMs, timeBudgetMs, deadline.signal)) {
          throw new Error("Time budget reached");
        }

        try {
          await waitForMangaDexBudget(metrics, startedMs, timeBudgetMs);
          const response = await activeFetch(url, {
            method: "GET",
            headers: { "Content-Type": "application/json" },
            ...init,
            signal: deadline.signal,
          });
          if (budgetEnded(startedMs, timeBudgetMs, deadline.signal)) {
            cancelResponseBody(response);
            throw new Error("Time budget reached");
          }

          if (response.ok) {
            markMangaDexSuccess();
            return await consumeBody(response, deadline.signal, "json");
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
            await sleepWithinBudget(backoff, startedMs, timeBudgetMs);
            attempt += 1;
            continue;
          }

          let bodyText = "";
          try {
            const text = await consumeBody(response, deadline.signal, "text");
            bodyText = typeof text === "string" ? text : "";
          } catch (error) {
            if (isBudgetError(error) || budgetEnded(startedMs, timeBudgetMs, deadline.signal)) throw error;
            bodyText = "";
          }
          throw new Error(`MangaDex ${response.status}: ${bodyText.slice(0, 240)}`);
        } catch (error) {
          if (isBudgetError(error) || budgetEnded(startedMs, timeBudgetMs, deadline.signal)) {
            throw new Error("Time budget reached");
          }
          if (attempt >= MAX_RETRIES) throw error;
          await sleepWithinBudget((300 * (2 ** attempt)) + Math.floor(Math.random() * 250), startedMs, timeBudgetMs);
          attempt += 1;
        }
      }
    } finally {
      deadline.close();
    }
  }

  async function fetchMangaDexEntity(
    url: string,
    metrics: MangaDexCallMetrics,
    startedMs: number,
    timeBudgetMs: number,
    // deno-lint-ignore no-explicit-any
  ): Promise<{ payload: any; notFound: boolean; rateLimited: boolean }> {
    const deadline = openRunDeadline(startedMs, timeBudgetMs);
    try {
      let attempt = 0;
      while (true) {
        if (budgetEnded(startedMs, timeBudgetMs, deadline.signal)) {
          throw new Error("Time budget reached");
        }
        try {
          await waitForMangaDexBudget(metrics, startedMs, timeBudgetMs);
          const response = await activeFetch(url, {
            method: "GET",
            headers: { "Content-Type": "application/json" },
            signal: deadline.signal,
          });
          if (budgetEnded(startedMs, timeBudgetMs, deadline.signal)) {
            cancelResponseBody(response);
            throw new Error("Time budget reached");
          }

          if (response.ok) {
            markMangaDexSuccess();
            return { payload: await consumeBody(response, deadline.signal, "json"), notFound: false, rateLimited: false };
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
            await sleepWithinBudget((300 * (2 ** attempt)) + Math.floor(Math.random() * 250), startedMs, timeBudgetMs);
            attempt += 1;
            continue;
          }
          let bodyText = "";
          try {
            const text = await consumeBody(response, deadline.signal, "text");
            bodyText = typeof text === "string" ? text : "";
          } catch (error) {
            if (isBudgetError(error) || budgetEnded(startedMs, timeBudgetMs, deadline.signal)) throw error;
            bodyText = "";
          }
          throw new Error(`MangaDex ${response.status}: ${bodyText.slice(0, 240)}`);
        } catch (error) {
          if (isBudgetError(error) || budgetEnded(startedMs, timeBudgetMs, deadline.signal)) {
            throw new Error("Time budget reached");
          }
          if (attempt >= MAX_RETRIES) throw error;
          await sleepWithinBudget((300 * (2 ** attempt)) + Math.floor(Math.random() * 250), startedMs, timeBudgetMs);
          attempt += 1;
        }
      }
    } finally {
      deadline.close();
    }
  }

  async function fetchMappedMangaDexTitle(
    mangaDexId: string,
    metrics: MangaDexCallMetrics,
    startedMs: number,
    timeBudgetMs: number,
  ): Promise<{ manga: MangaDexManga | null; notFound: boolean; rateLimited: boolean }> {
    const url = `${MANGADEX_API}/manga/${encodeURIComponent(mangaDexId)}`;
    const outcome = await fetchMangaDexEntity(url, metrics, startedMs, timeBudgetMs);
    if (outcome.rateLimited) return { manga: null, notFound: false, rateLimited: true };
    if (outcome.notFound || !outcome.payload?.data) return { manga: null, notFound: true, rateLimited: false };
    return { manga: outcome.payload.data as MangaDexManga, notFound: false, rateLimited: false };
  }

  async function searchMangaDex(
    title: string,
    metrics: MangaDexCallMetrics,
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

  // deno-lint-ignore no-explicit-any
  function parseAggregateChapters(payload: any): AggregateChapters {
    return parseAggregatePayload(payload);
  }

  async function fetchMangaDexAggregate(
    mangaDexId: string,
    languages: string[] | null,
    metrics: MangaDexCallMetrics,
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

  async function fetchAggregateChapterNumbers(args: {
    mangaDexId: string;
    languages: string[];
    includeFallbackAllLanguages: boolean;
    metrics: MangaDexCallMetrics;
    startedMs: number;
    timeBudgetMs: number;
  }): Promise<AggregateChapters> {
    const { mangaDexId, languages, includeFallbackAllLanguages, metrics, startedMs, timeBudgetMs } = args;
    let fractionalSkipped = 0;

    for (const language of languages) {
      if (!withinBudget(startedMs, timeBudgetMs)) break;
      const aggregate = await fetchMangaDexAggregate(mangaDexId, [language], metrics, startedMs, timeBudgetMs);
      const parsed = parseAggregateChapters(aggregate);
      fractionalSkipped += parsed.fractionalSkipped;
      if (parsed.chapterNumbers.length > 0) {
        return { chapterNumbers: parsed.chapterNumbers, fractionalSkipped, volumes: parsed.volumes };
      }
    }

    if (includeFallbackAllLanguages && withinBudget(startedMs, timeBudgetMs)) {
      const aggregate = await fetchMangaDexAggregate(mangaDexId, null, metrics, startedMs, timeBudgetMs);
      const parsed = parseAggregateChapters(aggregate);
      fractionalSkipped += parsed.fractionalSkipped;
      return { chapterNumbers: parsed.chapterNumbers, fractionalSkipped, volumes: parsed.volumes };
    }

    return { chapterNumbers: [], fractionalSkipped, volumes: [] };
  }

  return {
    searchMangaDex,
    fetchMappedMangaDexTitle,
    fetchAggregateChapterNumbers,
  };
}
