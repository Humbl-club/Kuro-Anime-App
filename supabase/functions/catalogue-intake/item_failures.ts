// One bad item must not stall a handler (review 2026-11-18).
//   - a per-item 4xx (not 429) or an unreadable body is that item's own fault: record it as failed and advance;
//   - 5xx, timeout or network error after the polite client's retries is the source's fault: stop the run (cursor kept),
//     count the failure against the item, and once the SAME item has failed MAX_ITEM_FAILURES consecutive runs,
//     skip it (recorded) so one poisoned item cannot block the pass forever;
//   - budget / 429 pauses stay clean stops that count against nothing.
// Failure counts live in the handler's cursor (`fails`), keyed by item; an item's count is dropped when it succeeds.
import { PoliteFetchError } from "../_shared/polite_fetch.ts";

export const MAX_ITEM_FAILURES = 3;

export type FailureAction = "skip" | "stop" | "clean" | "throw";

export function classifyFailure(e: unknown): FailureAction {
  if (!(e instanceof PoliteFetchError)) return "throw";
  if (e.kind === "budget" || e.kind === "rate_limited") return "clean";
  if (e.kind === "parse") return "skip";
  return "stop"; // http (5xx after retries), timeout, network
}

/** A response that is neither success nor a handler-specific "no data" status: the item itself is rejected (4xx other than 429). */
export function isItemRejection(status: number): boolean {
  return status !== 200 && status < 500;
}

export type FailureCounts = Record<string, number>;
export type FailedItem = { key: string; reason: string };

export function readFailureCounts(cursor: { fails?: unknown } | null | undefined): FailureCounts {
  const raw = cursor?.fails;
  const out: FailureCounts = {};
  if (raw && typeof raw === "object") {
    for (const [k, v] of Object.entries(raw as Record<string, unknown>)) if (typeof v === "number" && v > 0) out[k] = v;
  }
  return out;
}

/** True when the item already failed MAX_ITEM_FAILURES consecutive runs and must be skipped. */
export function exhausted(counts: FailureCounts, key: string): boolean {
  return (counts[key] ?? 0) >= MAX_ITEM_FAILURES;
}

export function noteFailedItem(list: FailedItem[], key: string, reason: string): void {
  if (list.length < 20) list.push({ key, reason });
}

export type StopReason = "source_error";
