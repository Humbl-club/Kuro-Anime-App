// Shared AniList GraphQL transport for the service-role intake functions
// (bulk-import-anime, bulk-import-manga, release-intake). One limiter per isolate.
//
// Contract:
//   - Spacing: at most `targetPerMinute` requests per minute (default 25, below AniList's
//     degraded 30/min), plus 0..jitterMs random jitter per request.
//   - Rate headers: a 429 honours `Retry-After` (seconds or HTTP date), else
//     `X-RateLimit-Reset`, else 60 s, and pauses the WHOLE limiter, not just this call.
//     `X-RateLimit-Remaining` <= 3 pauses the limiter until `X-RateLimit-Reset`.
//   - Every request has its own timeout (AbortController), clipped to the caller deadline.
//   - A wait that would end after the caller deadline is not slept: it throws
//     AniListError kind "budget" (or "rate_limited" when a 429 pause caused it) BEFORE any
//     request, so callers can stop cleanly without a half-processed page.
//   - A 200 response with `errors[]`, or without the required data path (e.g. `Page`), is an
//     AniListError kind "graphql" / "missing_data". It is never an empty page.
//   - 5xx, timeouts and network errors are retried with exponential backoff plus jitter.
//     Other 4xx are not retried.
// Fetch, sleep, clock and random are injected so tests run offline.

export const ANILIST_GRAPHQL_URL = "https://graphql.anilist.co";
export const DEFAULT_ANILIST_PER_MINUTE = 25;
export const INTAKE_USER_AGENT = "Kuro-Intake/1.0 (+https://kuro.app)";

export type AniListErrorKind =
  | "graphql"
  | "missing_data"
  | "http"
  | "timeout"
  | "network"
  | "budget"
  | "rate_limited";

export class AniListError extends Error {
  constructor(
    public kind: AniListErrorKind,
    message: string,
    public status: number | null = null,
  ) {
    super(message);
    this.name = "AniListError";
  }
}

/** True when no request was sent and nothing was half-processed: the caller may stop cleanly. */
export function isCleanStop(error: unknown): boolean {
  return error instanceof AniListError && (error.kind === "budget" || error.kind === "rate_limited");
}

/** Process-local spacing state. Share one instance between every AniList caller in an isolate. */
export class AniListLimiter {
  nextAllowedAt = 0;
  pausedUntil = 0;
  pauseReason: "rate_limited" | "remaining" | null = null;
  constructor(public minIntervalMs: number) {}

  static perMinute(n: number): AniListLimiter {
    return new AniListLimiter(Math.ceil(60_000 / Math.max(1, n)));
  }
}

/** The isolate-wide limiter used when a caller does not inject one. */
export const sharedAniListLimiter = AniListLimiter.perMinute(DEFAULT_ANILIST_PER_MINUTE);

export type AniListClientOptions = {
  fetch?: typeof globalThis.fetch;
  sleep?: (ms: number) => Promise<void>;
  now?: () => number;
  random?: () => number;
  limiter?: AniListLimiter;
  timeoutMs?: number;
  maxRetries?: number;
  jitterMs?: number;
  /** Upper bound for a single 429 / remaining pause. */
  maxPauseMs?: number;
  url?: string;
};

export type AniListQueryOptions = {
  /** Absolute epoch ms. Waits that would end after it throw kind "budget" / "rate_limited". */
  deadlineMs?: number;
  /** Path under `data` that must be a non-null object, e.g. ["Page"]. */
  require?: string[];
  /** Overrides the client retry count for this call. */
  retries?: number;
};

export type AniListClient = {
  // deno-lint-ignore no-explicit-any
  query(query: string, variables: Record<string, unknown>, options?: AniListQueryOptions): Promise<any>;
};

function defaultSleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Retry-After is either delta-seconds or an HTTP date. Returns ms, or null when absent/invalid. */
export function parseRetryAfter(raw: string | null, nowMs: number): number | null {
  if (!raw) return null;
  const trimmed = raw.trim();
  if (/^\d+(\.\d+)?$/.test(trimmed)) return Math.round(Number(trimmed) * 1000);
  const at = Date.parse(trimmed);
  if (Number.isFinite(at)) return Math.max(0, at - nowMs);
  return null;
}

function headerNumber(headers: Headers, name: string): number | null {
  const raw = headers.get(name);
  if (raw == null || raw.trim() === "") return null;
  const n = Number(raw);
  return Number.isFinite(n) ? n : null;
}

function hasPath(data: unknown, path: string[]): boolean {
  let cursor: unknown = data;
  for (const key of path) {
    if (!cursor || typeof cursor !== "object") return false;
    cursor = (cursor as Record<string, unknown>)[key];
  }
  return cursor != null && typeof cursor === "object";
}

export function createAniListClient(options: AniListClientOptions = {}): AniListClient {
  const doFetch = options.fetch ?? globalThis.fetch.bind(globalThis);
  const sleep = options.sleep ?? defaultSleep;
  const now = options.now ?? Date.now;
  const random = options.random ?? Math.random;
  const limiter = options.limiter ?? sharedAniListLimiter;
  const timeoutMs = options.timeoutMs ?? 15_000;
  const maxRetries = options.maxRetries ?? 3;
  const jitterMs = options.jitterMs ?? 250;
  const maxPauseMs = options.maxPauseMs ?? 65_000;
  const url = options.url ?? ANILIST_GRAPHQL_URL;

  function pause(untilMs: number, reason: "rate_limited" | "remaining") {
    const capped = Math.min(untilMs, now() + maxPauseMs);
    if (capped > limiter.pausedUntil) {
      limiter.pausedUntil = capped;
      limiter.pauseReason = reason;
    }
  }

  async function waitTurn(deadlineMs: number | undefined) {
    const t = now();
    const blockedUntil = Math.max(limiter.nextAllowedAt, limiter.pausedUntil);
    const jitter = Math.floor(random() * jitterMs);
    const wait = Math.max(0, blockedUntil - t) + jitter;
    if (deadlineMs !== undefined && t + wait >= deadlineMs) {
      const pausedByRate = limiter.pausedUntil > t && limiter.pauseReason === "rate_limited";
      throw new AniListError(
        pausedByRate ? "rate_limited" : "budget",
        pausedByRate ? "AniList rate limit pause outlasts the run budget" : "AniList request would exceed the run budget",
      );
    }
    if (wait > 0) await sleep(wait);
    limiter.nextAllowedAt = now() + limiter.minIntervalMs;
  }

  async function backoff(attempt: number, deadlineMs: number | undefined) {
    const delay = 500 * 2 ** attempt + Math.floor(random() * jitterMs);
    if (deadlineMs !== undefined && now() + delay >= deadlineMs) {
      throw new AniListError("budget", "AniList retry backoff would exceed the run budget");
    }
    await sleep(delay);
  }

  async function query(
    queryText: string,
    variables: Record<string, unknown>,
    queryOptions: AniListQueryOptions = {},
    // deno-lint-ignore no-explicit-any
  ): Promise<any> {
    const deadlineMs = queryOptions.deadlineMs;
    const retries = queryOptions.retries ?? maxRetries;
    let attempt = 0;
    while (true) {
      await waitTurn(deadlineMs);
      const controller = new AbortController();
      const remaining = deadlineMs === undefined ? timeoutMs : Math.max(1, deadlineMs - now());
      const timer = setTimeout(() => controller.abort(), Math.min(timeoutMs, remaining));
      let response: Response;
      let body: unknown;
      try {
        response = await doFetch(url, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": INTAKE_USER_AGENT,
          },
          body: JSON.stringify({ query: queryText, variables }),
          signal: controller.signal,
        });
        const remainingHeader = headerNumber(response.headers, "x-ratelimit-remaining");
        const resetHeader = headerNumber(response.headers, "x-ratelimit-reset");
        if (response.status === 429) {
          await response.body?.cancel().catch(() => {});
          const retryAfter = parseRetryAfter(response.headers.get("retry-after"), now());
          const untilMs = retryAfter != null
            ? now() + retryAfter
            : resetHeader != null
            ? resetHeader * 1000
            : now() + 60_000;
          pause(untilMs, "rate_limited");
          if (attempt >= retries) throw new AniListError("rate_limited", "AniList 429 after retries", 429);
          attempt++;
          continue;
        }
        if (remainingHeader != null && remainingHeader <= 3) {
          pause(resetHeader != null ? resetHeader * 1000 : now() + 60_000, "remaining");
        }
        if (response.status >= 500) {
          await response.body?.cancel().catch(() => {});
          if (attempt >= retries) throw new AniListError("http", `AniList error ${response.status}`, response.status);
          await backoff(attempt, deadlineMs);
          attempt++;
          continue;
        }
        try {
          body = await response.json();
        } catch {
          if (!response.ok) throw new AniListError("http", `AniList error ${response.status}`, response.status);
          if (attempt >= retries) throw new AniListError("http", "AniList returned unreadable JSON", response.status);
          await backoff(attempt, deadlineMs);
          attempt++;
          continue;
        }
      } catch (error) {
        if (error instanceof AniListError) throw error;
        const aborted = controller.signal.aborted;
        if (attempt >= retries) {
          throw new AniListError(aborted ? "timeout" : "network", aborted ? "AniList request timed out" : `AniList request failed: ${(error as Error)?.message ?? error}`);
        }
        await backoff(attempt, deadlineMs);
        attempt++;
        continue;
      } finally {
        clearTimeout(timer);
      }

      // deno-lint-ignore no-explicit-any
      const json = body as any;
      const errors = Array.isArray(json?.errors) ? json.errors : [];
      if (errors.length > 0) {
        const first = String(errors[0]?.message ?? "unknown GraphQL error").slice(0, 200);
        throw new AniListError("graphql", `AniList GraphQL error: ${first}`, response.status);
      }
      if (!response.ok) throw new AniListError("http", `AniList error ${response.status}`, response.status);
      const data = json?.data;
      if (!data || typeof data !== "object") {
        throw new AniListError("missing_data", "AniList response has no data", response.status);
      }
      if (queryOptions.require && !hasPath(data, queryOptions.require)) {
        throw new AniListError("missing_data", `AniList response is missing data.${queryOptions.require.join(".")}`, response.status);
      }
      return data;
    }
  }

  return { query };
}
