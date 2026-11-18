// Wikimedia pageviews (CC0): popularity and trend signal for the Kuro popularity index (Task 10).
// One call per article per project returns 365 daily rows (days without views are absent, so the
// windows are computed from the timestamps, never from row counts):
//   total365 = the whole window, last30 = the 30 days ending yesterday (UTC),
//   prev30 = the 30 days before that. The record is one per Kuro title (source_key = Kuro id) and
//   sums the English and Japanese articles. A 404 means no data: zeros, not an error.
// Articles come from the Wikidata records of titles with an accepted Wikidata link
// (props sitelink:enwiki / sitelink:jawiki). Titles without an article store nothing.
// Cursor `catalogue-intake:pageviews:<medium>`: { after_link } over accepted Wikidata link ids.
// Refresh: weekly (a record older than 7 days is fetched again).
import { PoliteFetchError, type PoliteClient } from "../_shared/polite_fetch.ts";
import { classifyFailure, exhausted, type FailedItem, isItemRejection, noteFailedItem, readFailureCounts } from "./item_failures.ts";
import { type HandlerOutcome, type RunContext } from "./context.ts";
import { chunk, clampInt, cursorKey, readCursor, readExistingRecords, upsertRecords, writeCursor } from "./store.ts";

export const PAGEVIEWS_BASE = "https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article";
export const PAGEVIEWS_LICENCE = "CC0-1.0";
const DAY_MS = 86_400_000;
const WEEK_MS = 7 * DAY_MS;
const PAGE = 25;

export type PageviewsProject = "en.wikipedia" | "ja.wikipedia";
export type PageviewsArticle = { mediaKey: string; project: PageviewsProject; title: string };
export type PageviewsResult = { mediaKey: string; total365: number; last30: number; prev30: number };

const ymd = (ms: number): string => new Date(ms).toISOString().slice(0, 10).replaceAll("-", "");

export function pageviewsUrl(project: string, title: string, start: string, end: string): string {
  const article = encodeURIComponent(title.replaceAll(" ", "_"));
  return `${PAGEVIEWS_BASE}/${project}/all-access/user/${article}/daily/${start}/${end}`;
}

export type PageviewsDeps = { client: PoliteClient; nowMs: number; deadlineMs?: number };

/**
 * Fetches the articles in order. A title (mediaKey) is returned only once all of its articles are
 * done; a clean stop (budget / provider pause) returns the completed titles and `stoppedEarly`.
 */
export async function pageviewsFetch(
  deps: PageviewsDeps,
  articles: PageviewsArticle[],
): Promise<{ results: PageviewsResult[]; requests: number; failed: FailedItem[]; errorKey?: string; stoppedEarly?: "budget" | "rate_limited" | "source_error" }> {
  const endMs = deps.nowMs - DAY_MS;
  const end = ymd(endMs);
  const start = ymd(endMs - 364 * DAY_MS);
  const last30From = `${ymd(endMs - 29 * DAY_MS)}00`;
  const prev30From = `${ymd(endMs - 59 * DAY_MS)}00`;

  const expected = new Map<string, number>();
  for (const a of articles) expected.set(a.mediaKey, (expected.get(a.mediaKey) ?? 0) + 1);
  const agg = new Map<string, PageviewsResult & { done: number }>();
  const results: PageviewsResult[] = [];
  let requests = 0;
  let stoppedEarly: "budget" | "rate_limited" | "source_error" | undefined;
  const failed: FailedItem[] = [];
  const failedKeys = new Set<string>();
  let errorKey: string | undefined;

  for (const a of articles) {
    if (failedKeys.has(a.mediaKey)) continue; // one article of this title already failed: the title stores nothing
    let items: { timestamp?: unknown; views?: unknown }[] = [];
    try {
      const res = await deps.client.request(pageviewsUrl(a.project, a.title, start, end), {}, deps.deadlineMs);
      requests++;
      if (res.status === 404) {
        items = [];
      } else if (isItemRejection(res.status)) {
        // The article itself is rejected (400 and the like): that title is recorded as failed and the run goes on.
        failedKeys.add(a.mediaKey);
        noteFailedItem(failed, a.mediaKey, `http ${res.status} for ${a.project}`);
        continue;
      } else if (res.status !== 200) {
        throw new PoliteFetchError("http", `pageviews http ${res.status}`, res.status);
      } else {
        const raw = (res.json as { items?: unknown } | null)?.items;
        items = Array.isArray(raw) ? raw : [];
      }
    } catch (e) {
      const action = classifyFailure(e);
      if (action === "clean") {
        stoppedEarly = (e as { kind: "budget" | "rate_limited" }).kind;
        break;
      }
      if (action === "skip") {
        failedKeys.add(a.mediaKey);
        noteFailedItem(failed, a.mediaKey, `unreadable response for ${a.project}`);
        continue;
      }
      if (action === "stop") {
        // 5xx / timeout after retries: stop the run; the caller counts this title's failure.
        stoppedEarly = "source_error";
        errorKey = a.mediaKey;
        break;
      }
      throw e;
    }
    const cur = agg.get(a.mediaKey) ?? { mediaKey: a.mediaKey, total365: 0, last30: 0, prev30: 0, done: 0 };
    for (const it of items) {
      const views = typeof it.views === "number" && Number.isFinite(it.views) ? it.views : 0;
      const ts = typeof it.timestamp === "string" ? it.timestamp : "";
      cur.total365 += views;
      if (ts >= last30From) cur.last30 += views;
      else if (ts >= prev30From) cur.prev30 += views;
    }
    cur.done++;
    agg.set(a.mediaKey, cur);
    if (cur.done === expected.get(a.mediaKey)) {
      results.push({ mediaKey: cur.mediaKey, total365: cur.total365, last30: cur.last30, prev30: cur.prev30 });
    }
  }
  return { results, requests, failed, errorKey, stoppedEarly };
}

// ---------------------------------------------------------------------------------------------
// Handler run

export const PAGEVIEWS_DEFAULT_TITLES = 225;

type WikidataLink = { id: number; kuro_id: number; source_key: string };

export async function runPageviews(ctx: RunContext): Promise<HandlerOutcome> {
  const medium = ctx.medium;
  const key = cursorKey("pageviews", medium);
  const cursor = (await readCursor<{ after_link?: number; fails?: Record<string, number> }>(ctx.supabase, key)) ?? {};
  let afterLink = cursor.after_link ?? 0;
  const fails = readFailureCounts(cursor);
  const failedItems: FailedItem[] = [];
  const maxTitles = clampInt(ctx.limit, PAGEVIEWS_DEFAULT_TITLES, 1, 1000);
  const nowMs = ctx.now();
  const nowIso = new Date(nowMs).toISOString();
  const stats = { requests: 0, titles_stored: 0, skipped_fresh: 0, no_article: 0, items_failed: 0, pass_completed: false };
  let stoppedEarly: "budget" | "rate_limited" | "source_error" | undefined;
  let considered = 0;
  let guard = 0;

  while (!stoppedEarly && considered < maxTitles && guard++ < 400) {
    const { data, error } = await ctx.supabase
      .from("catalogue_id_links")
      .select("id, kuro_id, source_key")
      .eq("kind", medium)
      .eq("source", "wikidata")
      .eq("status", "accepted")
      .gt("id", afterLink)
      .order("id", { ascending: true })
      .limit(PAGE);
    if (error) throw new Error(`catalogue_id_links read failed: ${error.message ?? error}`);
    const links = (data ?? []) as WikidataLink[];
    if (links.length === 0) {
      afterLink = 0;
      stats.pass_completed = true;
      break;
    }
    considered += links.length;

    const props = new Map<string, Record<string, string[]>>();
    for (const part of chunk(links.map((l) => String(l.source_key)), 500)) {
      const { data: recs, error: recError } = await ctx.supabase
        .from("catalogue_source_records")
        .select("source_key, payload")
        .eq("source", "wikidata")
        .eq("medium", medium)
        .in("source_key", part);
      if (recError) throw new Error(`catalogue_source_records read failed: ${recError.message ?? recError}`);
      for (const r of recs ?? []) props.set(String(r.source_key), (r.payload?.props ?? {}) as Record<string, string[]>);
    }
    const existing = await readExistingRecords(ctx.supabase, "pageviews", medium, links.map((l) => String(l.kuro_id)));

    const articles: PageviewsArticle[] = [];
    for (const l of links) {
      const e = existing.get(String(l.kuro_id));
      if (e?.fetched_at && nowMs - Date.parse(e.fetched_at) < WEEK_MS) {
        stats.skipped_fresh++;
        continue;
      }
      if (exhausted(fails, String(l.kuro_id))) {
        // Failed MAX_ITEM_FAILURES consecutive runs: skipped (recorded) so it cannot block the pass.
        stats.items_failed++;
        noteFailedItem(failedItems, String(l.kuro_id), "skipped_after_repeated_failures");
        continue;
      }
      const p = props.get(String(l.source_key)) ?? {};
      const en = p["sitelink:enwiki"]?.[0];
      const ja = p["sitelink:jawiki"]?.[0];
      if (!en && !ja) {
        stats.no_article++;
        continue;
      }
      if (en) articles.push({ mediaKey: String(l.kuro_id), project: "en.wikipedia", title: en });
      if (ja) articles.push({ mediaKey: String(l.kuro_id), project: "ja.wikipedia", title: ja });
    }

    const fetched = await pageviewsFetch({ client: ctx.clients.pageviews, nowMs, deadlineMs: ctx.deadlineMs }, articles);
    stats.requests += fetched.requests;
    stats.items_failed += fetched.failed.length;
    failedItems.push(...fetched.failed.slice(0, Math.max(0, 20 - failedItems.length)));
    for (const r of fetched.results) delete fails[r.mediaKey];
    if (fetched.errorKey !== undefined) fails[fetched.errorKey] = (fails[fetched.errorKey] ?? 0) + 1;
    if (fetched.results.length > 0) {
      await upsertRecords(
        ctx.supabase,
        fetched.results.map((r) => ({
          source: "pageviews" as const,
          sourceKey: r.mediaKey,
          medium,
          payload: { total365: r.total365, last30: r.last30, prev30: r.prev30 },
          licence: PAGEVIEWS_LICENCE,
        })),
        nowIso,
        { touch: true },
      );
      stats.titles_stored += fetched.results.length;
    }
    if (fetched.stoppedEarly) {
      stoppedEarly = fetched.stoppedEarly; // the cursor stays before this page; finished titles are fresh next run
      break;
    }
    if (links.length < PAGE) {
      afterLink = 0;
      stats.pass_completed = true;
      break;
    }
    afterLink = links[links.length - 1].id;
  }

  // A finished pass forgets the failure counts (a skipped title gets three fresh tries next pass).
  const nextFails = stats.pass_completed ? {} : fails;
  await writeCursor(ctx.supabase, key, medium, { after_link: afterLink, fails: nextFails }, { ...stats, failed_items: failedItems }, stoppedEarly ? `stopped_early:${stoppedEarly}` : null, nowIso);
  return { results: { ...stats, failed_items: failedItems }, stoppedEarly };
}
