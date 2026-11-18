// Types shared by handler.ts and the source handlers (kept apart so they never import each other).
import type { PoliteClient } from "../_shared/polite_fetch.ts";
import type { SupabaseLike } from "../_shared/catalogue/intake_persistence.ts";
import type { Medium } from "./store.ts";

export type IntakeClients = {
  wikidata: PoliteClient;
  ann: PoliteClient;
  mangaupdates: PoliteClient;
  pageviews: PoliteClient;
};

export type IntakeDeps = {
  supabase: SupabaseLike;
  clients: IntakeClients;
  now?: () => number;
};

export type RunContext = {
  supabase: SupabaseLike;
  clients: IntakeClients;
  medium: Medium;
  /** Per-run work cap (rows / titles); each handler clamps and defaults it. */
  limit: number | undefined;
  /** Absolute ms deadline for the whole invocation (timeBudgetMs). */
  deadlineMs: number;
  now: () => number;
};

export type HandlerOutcome = {
  results: Record<string, unknown>;
  /** Set when the run ended on a clean stop (budget or provider pause); the cursor was kept. */
  stoppedEarly?: string;
};

/** Reads Kuro rows after `afterId` in id order, paging below PostgREST's 1,000-row default cap. */
export async function readKuroRows<T extends { id: number }>(
  supabase: SupabaseLike,
  table: Medium,
  columns: string,
  afterId: number,
  limit: number,
  notNullColumn?: string,
): Promise<T[]> {
  const out: T[] = [];
  let last = afterId;
  while (out.length < limit) {
    const pageSize = Math.min(1000, limit - out.length);
    let q = supabase.from(table).select(columns).gt("id", last);
    if (notNullColumn) q = q.not(notNullColumn, "is", null);
    const { data, error } = await q.order("id", { ascending: true }).limit(pageSize);
    if (error) throw new Error(`${table} read failed: ${error.message ?? error}`);
    const page = (data ?? []) as T[];
    out.push(...page);
    if (page.length < pageSize) break;
    last = page[page.length - 1].id;
  }
  return out;
}
