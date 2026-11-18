// HTTP client for the catalogue sources (Wikidata, ANN, MangaUpdates, Wikimedia pageviews).
// A thin wrapper over createPoliteClient that sets the catalogue User-Agent on every request
// and picks the response type per source: ANN answers XML (text mode), the others JSON.
// Spacing, Retry-After and run-budget handling come from the shared PoliteLimiter; each handler
// passes the limiter that carries its own source limit (see plan Global Constraints).
import { createPoliteClient, type PoliteClient, type PoliteLimiter } from "../polite_fetch.ts";
import { CATALOGUE_USER_AGENT } from "./field_groups.ts";

export type CatalogueSource = "wikidata" | "ann" | "mangaupdates" | "pageviews";

export type SourceClientDeps = {
  fetch?: typeof globalThis.fetch;
  sleep?: (ms: number) => Promise<void>;
  now?: () => number;
  random?: () => number;
  timeoutMs?: number;
  maxRetries?: number;
  jitterMs?: number;
  maxPauseMs?: number;
  /** Overrides the per-source byte cap. */
  maxBytes?: number;
};

// ANN's full title report (nlist=all) is a multi-megabyte XML document; the others stay small.
const MAX_BYTES: Record<CatalogueSource, number> = {
  wikidata: 8 * 1024 * 1024,
  ann: 24 * 1024 * 1024,
  mangaupdates: 2 * 1024 * 1024,
  pageviews: 1024 * 1024,
};

// Per-request timeout. WDQS: one 500-id query with the real query shape measured 2.7 s and 2.7 MB on 2026-11-18
// (fixtures/README.md); 45 s leaves ~16x headroom for a cold or busy server and stays under WDQS's own 60 s limit.
export const TIMEOUT_MS: Partial<Record<CatalogueSource, number>> = { wikidata: 45_000 };

export function createSourceClient(source: CatalogueSource, limiter: PoliteLimiter, deps: SourceClientDeps = {}): PoliteClient {
  return createPoliteClient({
    ...deps,
    limiter,
    userAgent: CATALOGUE_USER_AGENT,
    responseType: source === "ann" ? "text" : "json",
    maxBytes: deps.maxBytes ?? MAX_BYTES[source],
    timeoutMs: deps.timeoutMs ?? TIMEOUT_MS[source],
  });
}
