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

export function createSourceClient(source: CatalogueSource, limiter: PoliteLimiter, deps: SourceClientDeps = {}): PoliteClient {
  return createPoliteClient({
    ...deps,
    limiter,
    userAgent: CATALOGUE_USER_AGENT,
    responseType: source === "ann" ? "text" : "json",
    maxBytes: deps.maxBytes ?? MAX_BYTES[source],
  });
}
