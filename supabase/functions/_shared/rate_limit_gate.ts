// The one interpretation of `check_concierge_rate_limit` results (F32).
//
// The limiter is a REQUIRED gate for protected work (list writes, paid provider calls, catalog scans):
// a missing or errored result must never be read as "allowed". Handlers keep their own RPC call (the
// arguments differ per function) and pass the raw `{ data, error }` result through here.
//
//   const decision = interpretRateLimit(await client.rpc("check_concierge_rate_limit", {...}));
//   const blocked = rateLimitBlockedResponse(decision, json);
//   if (blocked) return blocked;
//
// Contract:
//   allowed     -> `{ allowed: true }` returned by the RPC; the request proceeds.
//   denied      -> `{ allowed: false, retry_after_s? }`; HTTP 429 `{ error: "Rate limited", retry_after_s }` + Retry-After.
//   unavailable -> the RPC returned an error, no data, or a shape without a boolean `allowed`; HTTP 503
//                  `{ error: "Rate limiter unavailable", retry_after_s }` + Retry-After. No write, no provider charge.

export type RateLimitDecision =
  | { kind: "allowed" }
  | { kind: "denied"; retryAfterSeconds: number }
  | { kind: "unavailable"; retryAfterSeconds: number };

/** Retry hint when the limiter does not give one. */
export const DEFAULT_RETRY_AFTER_SECONDS = 30;

/** The raw result of `client.rpc(...)` (supabase-js shape), structurally typed. */
export interface RpcResultLike {
  data?: unknown;
  error?: unknown;
}

function retryAfter(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? Math.ceil(value)
    : DEFAULT_RETRY_AFTER_SECONDS;
}

/** Pure: turns a limiter RPC result into a decision. An error or an unrecognised shape is `unavailable`. */
export function interpretRateLimit(result: RpcResultLike | null | undefined): RateLimitDecision {
  if (!result || result.error) return { kind: "unavailable", retryAfterSeconds: DEFAULT_RETRY_AFTER_SECONDS };
  const data = result.data;
  if (!data || typeof data !== "object") return { kind: "unavailable", retryAfterSeconds: DEFAULT_RETRY_AFTER_SECONDS };
  const row = data as { allowed?: unknown; retry_after_s?: unknown };
  if (row.allowed === true) return { kind: "allowed" };
  if (row.allowed === false) return { kind: "denied", retryAfterSeconds: retryAfter(row.retry_after_s) };
  return { kind: "unavailable", retryAfterSeconds: DEFAULT_RETRY_AFTER_SECONDS };
}

/**
 * Awaits a limiter RPC and returns the blocking response, or null when the request may proceed.
 * A thrown call is the same as `{ data: null, error }` (fail closed). Handlers pass their own `json`.
 */
export async function gateRateLimit(
  rpc: PromiseLike<RpcResultLike>,
  json: (body: unknown, init?: ResponseInit) => Response,
): Promise<Response | null> {
  let result: RpcResultLike;
  try {
    result = await rpc;
  } catch (error) {
    result = { data: null, error };
  }
  return rateLimitBlockedResponse(interpretRateLimit(result), json);
}

/** The response that stops a request, or null when it may proceed. `json` is the handler's own helper. */
export function rateLimitBlockedResponse(
  decision: RateLimitDecision,
  json: (body: unknown, init?: ResponseInit) => Response,
): Response | null {
  if (decision.kind === "allowed") return null;
  const headers = { "Retry-After": String(decision.retryAfterSeconds) };
  if (decision.kind === "denied") {
    return json({ error: "Rate limited", retry_after_s: decision.retryAfterSeconds }, { status: 429, headers });
  }
  return json({ error: "Rate limiter unavailable", retry_after_s: decision.retryAfterSeconds }, { status: 503, headers });
}
