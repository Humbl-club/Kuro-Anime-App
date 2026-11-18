// MangaUpdates new series (catalogue Task 15c, manga half). Nothing else fetches series Kuro does not hold, so the
// manga candidate set of `create` was empty. This handler reads MangaUpdates' newest-first list
// (POST /v1/series/search { orderby: "date_added", perpage: 100, page }, no search text) and stores the full record
// (GET /v1/series/{id}) of every unseen manga-type series from `minYear` on. It writes records only: no link, no
// title row. `create` (report mode by default) reads them as its manga candidates and decides link, review or row.
//
// Politeness: the same shared MangaUpdates client (>= 1.1 s spacing, one limiter per isolate); the cron expressions
// sit on odd minutes outside 03:30-04:20 UTC so no other MangaUpdates run (matcher: even minutes; release-intake:
// 03:50) is active, and handler.ts skips the quiet window for a manual or late call. One list page costs one request;
// a run reads at most MU_NEW_MAX_PAGES pages, and the whole run at most MAX_REQUESTS requests within the time budget.
//
// Cursor (`catalogue-intake:mangaupdates_new:manga`): { seen: [series ids] }, newest first, at most SEEN_MAX. Paging stops
// at the first page whose ids are all seen or already stored. Series ids are not ordered by time, so the cursor is a
// seen list, not a high-water mark. An id that was a candidate but was not fetched (budget, rate limit, source error)
// is never added to `seen`, so the next run offers it again.
import { PoliteFetchError } from "../_shared/polite_fetch.ts";
import { type HandlerOutcome, type RunContext } from "./context.ts";
import { muFormat } from "./map_mangaupdates.ts";
import { MU_API, MU_LICENCE, type MuHit, type MuRecord, muFetch, parseMuSearch } from "./mangaupdates.ts";
import { chunk, clampInt, cursorKey, readCursor, readExistingRecords, selectAll, upsertRecords, writeCursor } from "./store.ts";
import { classifyFailure } from "./item_failures.ts";

/** Series that started before this year are not fetched by default (create's own minYear applies on top). */
export const MU_NEW_DEFAULT_MIN_YEAR = 2024;
export const MU_NEW_MAX_PAGES = 3;
const PER_PAGE = 100;
const MAX_REQUESTS = 40;
const SEEN_MAX = 400;

type NewCursor = { seen?: string[] };

async function acceptedKeys(supabase: RunContext["supabase"], keys: string[]): Promise<Set<string>> {
  const out = new Set<string>();
  for (const part of chunk(keys, 500)) {
    const rows = await selectAll<{ source_key: string }>(
      () => supabase.from("catalogue_id_links").select("id, source_key").eq("kind", "manga").eq("source", "mangaupdates").eq("status", "accepted").in("source_key", part),
      ["id"],
      "catalogue_id_links",
    );
    for (const r of rows) out.add(String(r.source_key));
  }
  return out;
}

export async function runMangaUpdatesNew(ctx: RunContext, opts: { minYear?: number } = {}): Promise<HandlerOutcome> {
  const key = cursorKey("mangaupdates_new", "manga");
  const cursor = (await readCursor<NewCursor>(ctx.supabase, key)) ?? {};
  const seenBefore = Array.isArray(cursor.seen) ? cursor.seen.map(String) : [];
  const seenSet = new Set(seenBefore);
  const nowIso = new Date(ctx.now()).toISOString();
  const minYear = Number.isInteger(opts.minYear) && Number(opts.minYear) > 1800 ? Number(opts.minYear) : MU_NEW_DEFAULT_MIN_YEAR;
  const maxRequests = clampInt(ctx.limit, MAX_REQUESTS, 1, MAX_REQUESTS);
  const results: Record<string, number> = { requests: 0, pages: 0, listed: 0, candidates: 0, records_fetched: 0, records_written: 0, missing_ids: 0, items_failed: 0 };
  let stoppedEarly: "budget" | "rate_limited" | "source_error" | undefined;

  // 1. The newest list, page by page, until a page holds nothing new.
  const listed: string[] = [];
  const candidates: MuHit[] = [];
  for (let page = 1; page <= MU_NEW_MAX_PAGES && !stoppedEarly && results.requests < maxRequests; page++) {
    let hits: MuHit[];
    try {
      const res = await ctx.clients.mangaupdates.request(`${MU_API}/series/search`, { method: "POST", body: { orderby: "date_added", perpage: PER_PAGE, page } }, ctx.deadlineMs);
      results.requests++;
      if (res.status !== 200) throw new PoliteFetchError("http", `mangaupdates http ${res.status}`, res.status);
      hits = parseMuSearch(res.json);
    } catch (e) {
      const action = classifyFailure(e);
      if (action === "clean") stoppedEarly = (e as { kind: "budget" | "rate_limited" }).kind;
      else if (action === "stop") stoppedEarly = "source_error";
      else if (action === "skip") results.items_failed++;
      else throw e;
      break;
    }
    results.pages++;
    results.listed += hits.length;
    const ids = hits.map((h) => String(h.seriesId));
    const stored = new Set<string>();
    for (const part of chunk(ids, 500)) for (const k of (await readExistingRecords(ctx.supabase, "mangaupdates", "manga", part)).keys()) stored.add(k);
    const linked = await acceptedKeys(ctx.supabase, ids);
    let anyNew = false;
    for (const h of hits) {
      const id = String(h.seriesId);
      listed.push(id);
      if (seenSet.has(id) || stored.has(id)) continue;
      anyNew = true;
      if (linked.has(id)) continue; // an existing Kuro title: the matcher handler keeps its record fresh
      if (muFormat(h.type) === null || h.year === null || h.year < minYear) continue;
      candidates.push(h);
    }
    if (!anyNew || hits.length < PER_PAGE) break; // caught up, or the list ended
  }
  results.candidates = candidates.length;

  // 2. Full records of the candidates, within the request cap and the time budget.
  const unfinished = new Set(candidates.map((c) => String(c.seriesId)));
  if (!stoppedEarly && candidates.length > 0) {
    const room = Math.max(0, maxRequests - results.requests);
    const batch = candidates.slice(0, room).map((c) => c.seriesId);
    const persist = async (r: MuRecord) => {
      const w = await upsertRecords(ctx.supabase, [{ source: "mangaupdates", sourceKey: String(r.seriesId), medium: "manga", payload: r, licence: MU_LICENCE }], nowIso, { touch: true });
      results.records_written += w.written;
      unfinished.delete(String(r.seriesId));
    };
    const f = await muFetch({ client: ctx.clients.mangaupdates, deadlineMs: ctx.deadlineMs, onRecord: persist }, batch);
    results.requests += f.requests;
    results.records_fetched += f.records.length;
    results.missing_ids += f.missing.length;
    results.items_failed += f.failed.length;
    for (const m of f.missing) unfinished.delete(m); // gone or unreadable at the source: settled
    for (const x of f.failed) unfinished.delete(x.key.replace(/^f:/, "")); // a rejected series is recorded in failed items, not retried every run
    if (f.stoppedEarly) stoppedEarly = f.stoppedEarly;
  }

  // 3. Cursor: remember what was listed, except candidates that are still unfetched.
  const remembered = [...new Set([...listed.filter((id) => !unfinished.has(id)), ...seenBefore])].slice(0, SEEN_MAX);
  await writeCursor(ctx.supabase, key, "manga", { seen: remembered }, { ...results, unfetched: unfinished.size }, stoppedEarly ? `stopped_early:${stoppedEarly}` : null, nowIso);
  return { results: { ...results, unfetched: unfinished.size, min_year: minYear }, stoppedEarly };
}
