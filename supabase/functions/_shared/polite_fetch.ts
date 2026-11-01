// Small polite JSON client for third-party REST sources without a published rate limit
// (MangaUpdates: "use reasonable spacing between requests ... employ caching").
//   - one request per `minIntervalMs` (+ jitter) per limiter, Kuro User-Agent on every call;
//   - 429 honours Retry-After (else 60 s) and pauses the whole limiter;
//   - 5xx / network / timeout retried with backoff; other 4xx returned to the caller;
//   - a wait that would pass the caller deadline throws PoliteFetchError kind "budget" before
//     sending, so the caller can stop cleanly.
// Fetch, sleep, clock and random are injected for offline tests.
import { INTAKE_USER_AGENT, parseRetryAfter } from "./anilist_client.ts";

export type PoliteErrorKind = "budget" | "rate_limited" | "http" | "network" | "timeout" | "parse";

export class PoliteFetchError extends Error {
  constructor(public kind: PoliteErrorKind, message: string, public status: number | null = null) {
    super(message);
    this.name = "PoliteFetchError";
  }
}

/// Reads the body as UTF-8 without ever buffering more than `maxBytes`: a declared
/// Content-Length over the cap is rejected before reading, and the stream is cancelled as
/// soon as the running byte count passes it.
export async function readBounded(response: Response, maxBytes: number): Promise<string> {
  const tooLarge = () => new PoliteFetchError("parse", "source response exceeds byte limit", response.status);
  const declared = Number(response.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > maxBytes) {
    await response.body?.cancel().catch(() => {});
    throw tooLarge();
  }
  if (!response.body) return "";
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel().catch(() => {});
      throw tooLarge();
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

export function isPoliteCleanStop(error: unknown): boolean {
  return error instanceof PoliteFetchError && (error.kind === "budget" || error.kind === "rate_limited");
}

export class PoliteLimiter {
  nextAllowedAt = 0;
  pausedUntil = 0;
  constructor(public minIntervalMs: number) {}
}

export type PoliteClientOptions = {
  limiter: PoliteLimiter;
  fetch?: typeof globalThis.fetch;
  sleep?: (ms: number) => Promise<void>;
  now?: () => number;
  random?: () => number;
  timeoutMs?: number;
  maxRetries?: number;
  jitterMs?: number;
  maxPauseMs?: number;
  /** Largest accepted response body in bytes. */
  maxBytes?: number;
};

export type PoliteResponse = { status: number; json: unknown };

export type PoliteClient = {
  request(url: string, init: { method?: "GET" | "POST"; body?: unknown }, deadlineMs?: number): Promise<PoliteResponse>;
};

export function createPoliteClient(options: PoliteClientOptions): PoliteClient {
  const doFetch = options.fetch ?? globalThis.fetch.bind(globalThis);
  const sleep = options.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
  const now = options.now ?? Date.now;
  const random = options.random ?? Math.random;
  const limiter = options.limiter;
  const timeoutMs = options.timeoutMs ?? 15_000;
  const maxRetries = options.maxRetries ?? 2;
  const jitterMs = options.jitterMs ?? 250;
  const maxPauseMs = options.maxPauseMs ?? 65_000;
  const maxBytes = options.maxBytes ?? 2 * 1024 * 1024;

  async function waitTurn(deadlineMs?: number) {
    const t = now();
    const wait = Math.max(0, Math.max(limiter.nextAllowedAt, limiter.pausedUntil) - t) + Math.floor(random() * jitterMs);
    if (deadlineMs !== undefined && t + wait >= deadlineMs) {
      const paused = limiter.pausedUntil > t;
      throw new PoliteFetchError(paused ? "rate_limited" : "budget", paused ? "source pause outlasts the run budget" : "request would exceed the run budget");
    }
    if (wait > 0) await sleep(wait);
    limiter.nextAllowedAt = now() + limiter.minIntervalMs;
  }

  async function backoff(attempt: number, deadlineMs?: number) {
    const delay = 1000 * 2 ** attempt + Math.floor(random() * jitterMs);
    if (deadlineMs !== undefined && now() + delay >= deadlineMs) {
      throw new PoliteFetchError("budget", "retry backoff would exceed the run budget");
    }
    await sleep(delay);
  }

  async function request(url: string, init: { method?: "GET" | "POST"; body?: unknown }, deadlineMs?: number): Promise<PoliteResponse> {
    let attempt = 0;
    while (true) {
      await waitTurn(deadlineMs);
      const controller = new AbortController();
      const remaining = deadlineMs === undefined ? timeoutMs : Math.max(1, deadlineMs - now());
      const timer = setTimeout(() => controller.abort(), Math.min(timeoutMs, remaining));
      try {
        const response = await doFetch(url, {
          method: init.method ?? "GET",
          headers: {
            "Accept": "application/json",
            "User-Agent": INTAKE_USER_AGENT,
            ...(init.body !== undefined ? { "Content-Type": "application/json" } : {}),
          },
          body: init.body !== undefined ? JSON.stringify(init.body) : undefined,
          signal: controller.signal,
        });
        if (response.status === 429) {
          await response.body?.cancel().catch(() => {});
          const retryAfter = parseRetryAfter(response.headers.get("retry-after"), now()) ?? 60_000;
          limiter.pausedUntil = Math.max(limiter.pausedUntil, now() + Math.min(retryAfter, maxPauseMs));
          if (attempt >= maxRetries) throw new PoliteFetchError("rate_limited", "source 429 after retries", 429);
          attempt++;
          continue;
        }
        if (response.status >= 500) {
          await response.body?.cancel().catch(() => {});
          if (attempt >= maxRetries) throw new PoliteFetchError("http", `source error ${response.status}`, response.status);
          await backoff(attempt, deadlineMs);
          attempt++;
          continue;
        }
        const text = await readBounded(response, maxBytes);
        let json: unknown = null;
        if (text.trim()) {
          try {
            json = JSON.parse(text);
          } catch {
            throw new PoliteFetchError("parse", "source returned unreadable JSON", response.status);
          }
        }
        return { status: response.status, json };
      } catch (error) {
        if (error instanceof PoliteFetchError) throw error;
        const aborted = controller.signal.aborted;
        if (attempt >= maxRetries) {
          throw new PoliteFetchError(aborted ? "timeout" : "network", aborted ? "source request timed out" : `source request failed: ${(error as Error)?.message ?? error}`);
        }
        await backoff(attempt, deadlineMs);
        attempt++;
      } finally {
        clearTimeout(timer);
      }
    }
  }

  return { request };
}
