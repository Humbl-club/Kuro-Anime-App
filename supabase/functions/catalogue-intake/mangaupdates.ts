// MangaUpdates (manga backbone). The public API asks for reasonable spacing and caching; Kuro uses
// one request per 1.1 s through one limiter and never overlaps release-intake's MangaUpdates run
// (schedule guard: Task 15 cron). release-intake/manga.ts documents the id rule used here: the
// slug on mangaupdates.com is the series id in base 36.
//
// One run (cursor `catalogue-intake:mangaupdates:manga`: { after_id, fetch_after_link }):
//  1. matching, at most half the request budget: manga rows without an accepted MangaUpdates link
//     are searched by title (POST /v1/series/search, perpage 10) and scored with the same rule as
//     ANN (accept >= 0.92 with runner-up < 0.80, else propose). A Wikidata-derived proposed id is
//     accepted ONLY when this same search matching (with its runner-up margin) picks the same key;
//     on any disagreement both stay proposed and a conflict is listed (link trust rule 2, see
//     wikidata.ts). A single-record score never accepts a Wikidata-derived id;
//  2. records: accepted links without a record, or older than 30 days, are fetched
//     (GET /v1/series/{id}).
// MangaUpdates descriptions, images and scanlation release data are deliberately not stored.
// One bad item never stalls the run (item_failures.ts): a per-item 4xx or unreadable body is recorded and skipped,
// a 5xx / timeout stops the run, and an item that failed three consecutive runs is skipped (recorded).
import { PoliteFetchError, type PoliteClient } from "../_shared/polite_fetch.ts";
import { classifyFailure, exhausted, type FailedItem, isItemRejection, noteFailedItem, readFailureCounts } from "./item_failures.ts";
import type { SupabaseLike } from "../_shared/catalogue/intake_persistence.ts";
import { normaliseTitle, titleTokens } from "../_shared/catalogue/normalise_title.ts";
import { ACCEPT_SCORE, jaccard, PROPOSE_FLOOR, RUNNER_UP_MAX } from "./ann.ts";
import { type HandlerOutcome, readKuroRows, type RunContext } from "./context.ts";
import {
  applyLinks,
  chunk,
  clampInt,
  type Conflict,
  cursorKey,
  type LinkCandidate,
  readCursor,
  readExistingRecords,
  selectAll,
  upsertRecords,
  writeCursor,
} from "./store.ts";

export const MU_API = "https://api.mangaupdates.com/v1";
export const MU_LICENCE = "MU-API";
const MONTH_MS = 30 * 86_400_000;
const UNKNOWN_YEAR_FACTOR = 0.9;
const OFF_YEAR_FACTOR = 0.5;
const TYPE_MISMATCH_FACTOR = 0.7;
const MAX_PROPOSED = 3;
const MAX_CATEGORIES = 300;

// ---------------------------------------------------------------------------------------------
// Matching

export type MuHit = { seriesId: number; titles: string[]; year: number | null; type: string | null };
export type MuKuro = { id: number; titles: string[]; year: number | null; format: string | null; country: string | null };

const asYear = (v: unknown): number | null => {
  const n = typeof v === "number" ? v : typeof v === "string" ? Number(v) : NaN;
  return Number.isInteger(n) && n > 1800 ? n : null;
};

export function parseMuSearch(json: unknown): MuHit[] {
  const results = (json as { results?: unknown } | null)?.results;
  if (!Array.isArray(results)) return [];
  const hits: MuHit[] = [];
  for (const r of results) {
    const rec = (r as { record?: Record<string, unknown> }).record;
    const seriesId = Number(rec?.series_id);
    if (!rec || !Number.isSafeInteger(seriesId) || seriesId <= 0 || typeof rec.title !== "string") continue;
    const hitTitle = (r as { hit_title?: unknown }).hit_title;
    hits.push({
      seriesId,
      titles: [rec.title, ...(typeof hitTitle === "string" ? [hitTitle] : [])],
      year: asYear(rec.year),
      type: typeof rec.type === "string" ? rec.type : null,
    });
  }
  return hits;
}

/** MangaUpdates types a Kuro format (plus country of origin) may match. */
function allowedTypes(format: string | null, country: string | null): string[] | null {
  const c = (country ?? "").toUpperCase();
  const byCountry = c === "KR" ? ["manhwa"] : c === "CN" || c === "TW" ? ["manhua"] : c === "JP" ? ["manga"] : ["manga", "manhwa", "manhua"];
  switch ((format ?? "").toUpperCase()) {
    case "MANGA":
      return byCountry;
    case "ONE_SHOT":
      return ["one-shot", ...byCountry];
    case "NOVEL":
      return ["novel"];
    default:
      return null;
  }
}

export function muScore(kuro: MuKuro, hit: MuHit): number {
  const kuroNorms = [...new Set(kuro.titles.map(normaliseTitle).filter(Boolean))];
  const hitNorms = [...new Set(hit.titles.map(normaliseTitle).filter(Boolean))];
  let score = 0;
  for (const k of kuroNorms) {
    const kt = new Set(titleTokens(k));
    for (const h of hitNorms) score = Math.max(score, k === h ? 1 : jaccard(kt, new Set(titleTokens(h))));
  }
  if (kuro.year === null || hit.year === null) score *= UNKNOWN_YEAR_FACTOR;
  else if (Math.abs(kuro.year - hit.year) > 1) score *= OFF_YEAR_FACTOR;
  const allowed = allowedTypes(kuro.format, kuro.country);
  if (!allowed || !hit.type || !allowed.includes(hit.type.toLowerCase())) score *= TYPE_MISMATCH_FACTOR;
  return score;
}

export function muMatch(kuro: MuKuro, hits: MuHit[]): { accepted: LinkCandidate[]; proposed: LinkCandidate[] } {
  const seen = new Set<number>();
  const scored = hits
    .filter((h) => (seen.has(h.seriesId) ? false : (seen.add(h.seriesId), true)))
    .map((h) => ({ h, score: muScore(kuro, h) }))
    .sort((a, b) => b.score - a.score || a.h.seriesId - b.h.seriesId);
  const link = (s: { h: MuHit; score: number }, status: "accepted" | "proposed"): LinkCandidate => ({
    kuroId: kuro.id,
    source: "mangaupdates",
    sourceKey: String(s.h.seriesId),
    method: "title_match",
    confidence: Math.round(s.score * 1000) / 1000,
    status,
  });
  if (scored.length > 0 && scored[0].score >= ACCEPT_SCORE && (scored[1]?.score ?? 0) < RUNNER_UP_MAX) {
    return { accepted: [link(scored[0], "accepted")], proposed: [] };
  }
  return { accepted: [], proposed: scored.filter((s) => s.score >= PROPOSE_FLOOR).slice(0, MAX_PROPOSED).map((s) => link(s, "proposed")) };
}

// ---------------------------------------------------------------------------------------------
// Records

export type MuRecord = {
  seriesId: number;
  title: string;
  /** Kuro-built credit link (series id in base 36), never the response's own url. */
  url: string;
  associated: string[];
  type: string | null;
  year: number | null;
  /** First line of MangaUpdates' status text ("43 Volumes (Ongoing)"). */
  status: string;
  completed: boolean;
  genres: string[];
  categories: { category: string; votes: number; votesPlus: number; votesMinus: number }[];
  authors: { authorId: number; name: string; type: string }[];
  publishers: { publisherId: number; name: string; type: string }[];
  related: { relationType: string; seriesId: number; name: string }[];
  bayesianRating: number | null;
  ratingVotes: number | null;
  /** Optional anime adaptation span strings reported by MangaUpdates (`d.anime.start` / `d.anime.end`). */
  animeStart?: string | null;
  animeEnd?: string | null;
};

type J = Record<string, unknown>;
const arr = (v: unknown): J[] => (Array.isArray(v) ? v.filter((x): x is J => !!x && typeof x === "object") : []);
const str = (v: unknown): string => (typeof v === "string" ? v : "");
const numOrNull = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);

export function parseMuSeries(json: unknown): MuRecord | null {
  const d = json as J | null;
  const seriesId = Number(d?.series_id);
  if (!d || !Number.isSafeInteger(seriesId) || seriesId <= 0 || typeof d.title !== "string") return null;
  const dedupe = <T extends { type: string }>(items: T[], idOf: (t: T) => number): T[] => {
    const seen = new Set<string>();
    return items.filter((i) => (seen.has(`${idOf(i)}|${i.type}`) ? false : (seen.add(`${idOf(i)}|${i.type}`), true)));
  };
  return {
    seriesId,
    title: d.title,
    url: `https://www.mangaupdates.com/series/${seriesId.toString(36)}`,
    associated: arr(d.associated).map((a) => str(a.title)).filter(Boolean),
    type: typeof d.type === "string" ? d.type : null,
    year: asYear(d.year),
    status: str(d.status).split("\n")[0].trim(),
    completed: d.completed === true,
    genres: arr(d.genres).map((g) => str(g.genre)).filter(Boolean),
    categories: arr(d.categories)
      .slice(0, MAX_CATEGORIES)
      .map((c) => ({ category: str(c.category), votes: numOrNull(c.votes) ?? 0, votesPlus: numOrNull(c.votes_plus) ?? 0, votesMinus: numOrNull(c.votes_minus) ?? 0 }))
      .filter((c) => c.category),
    authors: dedupe(
      arr(d.authors).map((a) => ({ authorId: Number(a.author_id), name: str(a.name), type: str(a.type) })).filter((a) => Number.isSafeInteger(a.authorId) && a.name),
      (a) => a.authorId,
    ),
    publishers: dedupe(
      arr(d.publishers).map((p) => ({ publisherId: Number(p.publisher_id), name: str(p.publisher_name), type: str(p.type) })).filter((p) => Number.isSafeInteger(p.publisherId) && p.name),
      (p) => p.publisherId,
    ),
    related: arr(d.related_series)
      .map((r) => ({ relationType: str(r.relation_type), seriesId: Number(r.related_series_id), name: str(r.related_series_name) }))
      .filter((r) => r.relationType && Number.isSafeInteger(r.seriesId)),
    bayesianRating: numOrNull(d.bayesian_rating),
    ratingVotes: numOrNull(d.rating_votes),
    animeStart: str((d.anime as J | undefined)?.start).trim() || null,
    animeEnd: str((d.anime as J | undefined)?.end).trim() || null,
  };
}

export type MuFetchDeps = { client: PoliteClient; deadlineMs?: number; onRecord?: (record: MuRecord) => Promise<void> };

export async function muFetch(
  deps: MuFetchDeps,
  seriesIds: number[],
): Promise<{ records: MuRecord[]; missing: string[]; failed: FailedItem[]; errorId?: number; requests: number; stoppedEarly?: "budget" | "rate_limited" | "source_error" }> {
  const out = {
    records: [] as MuRecord[],
    missing: [] as string[],
    failed: [] as FailedItem[],
    errorId: undefined as number | undefined,
    requests: 0,
    stoppedEarly: undefined as "budget" | "rate_limited" | "source_error" | undefined,
  };
  for (const id of seriesIds) {
    try {
      const res = await deps.client.request(`${MU_API}/series/${id}`, {}, deps.deadlineMs);
      out.requests++;
      if (res.status === 404) {
        out.missing.push(String(id));
        continue;
      }
      if (isItemRejection(res.status)) {
        // This series itself is rejected (400 and the like): recorded as failed, the rest still run.
        noteFailedItem(out.failed, `f:${id}`, `http ${res.status}`);
        continue;
      }
      if (res.status !== 200) throw new PoliteFetchError("http", `mangaupdates http ${res.status}`, res.status);
      const rec = parseMuSeries(res.json);
      if (!rec) {
        out.missing.push(String(id));
        continue;
      }
      await deps.onRecord?.(rec);
      out.records.push(rec);
    } catch (e) {
      const action = classifyFailure(e);
      if (action === "clean") {
        out.stoppedEarly = (e as { kind: "budget" | "rate_limited" }).kind;
        break;
      }
      if (action === "skip") {
        noteFailedItem(out.failed, `f:${id}`, "unreadable response");
        continue;
      }
      if (action === "stop") {
        out.stoppedEarly = "source_error";
        out.errorId = id;
        break;
      }
      throw e;
    }
  }
  return out;
}

// ---------------------------------------------------------------------------------------------
// Handler run

type MuCursor = { after_id?: number; fetch_after_link?: number; fails?: Record<string, number> };
const KURO_COLUMNS = "id, title_english, title_romaji, title_native, title_synonyms, start_date_year, format, country_of_origin";
const MATCH_PAGE = 40;
const FETCH_PAGE = 20;
const MAX_REQUESTS = 45;

function kuroManga(row: Record<string, unknown>): MuKuro {
  const synonyms = Array.isArray(row.title_synonyms) ? row.title_synonyms : typeof row.title_synonyms === "string" ? [row.title_synonyms] : [];
  const titles = [row.title_romaji, row.title_english, row.title_native, ...synonyms].filter((t): t is string => typeof t === "string" && t.trim() !== "");
  return {
    id: Number(row.id),
    titles,
    year: typeof row.start_date_year === "number" ? row.start_date_year : null,
    format: typeof row.format === "string" ? row.format : null,
    country: typeof row.country_of_origin === "string" ? row.country_of_origin : null,
  };
}

async function readLinks(supabase: SupabaseLike, ids: number[], status: "accepted" | "proposed"): Promise<{ kuro_id: number; source_key: string; method: string }[]> {
  const out: { kuro_id: number; source_key: string; method: string }[] = [];
  for (const part of chunk(ids, 500)) {
    // A title can hold several proposed links, so this read pages past the 1,000-row cap.
    out.push(
      ...(await selectAll<{ kuro_id: number; source_key: string; method: string }>(
        () => supabase.from("catalogue_id_links").select("kuro_id, source_key, method").eq("kind", "manga").eq("source", "mangaupdates").eq("status", status).in("kuro_id", part),
        ["id"],
        "catalogue_id_links",
      )),
    );
  }
  return out;
}

export async function runMangaUpdates(ctx: RunContext): Promise<HandlerOutcome> {
  const key = cursorKey("mangaupdates", "manga");
  const cursor: MuCursor = (await readCursor<MuCursor>(ctx.supabase, key)) ?? {};
  const next: MuCursor = { after_id: cursor.after_id ?? 0, fetch_after_link: cursor.fetch_after_link ?? 0 };
  const fails = readFailureCounts(cursor);
  const failedItems: FailedItem[] = [];
  const nowMs = ctx.now();
  const nowIso = new Date(nowMs).toISOString();
  const maxRequests = clampInt(ctx.limit, 40, 1, MAX_REQUESTS);
  const matchBudget = Math.ceil(maxRequests / 2);
  const results: Record<string, number> = { requests: 0, matched: 0, corroborated: 0, proposed: 0, conflicts: 0, searched: 0, records_fetched: 0, records_written: 0, missing_ids: 0, items_failed: 0 };
  let stoppedEarly: "budget" | "rate_limited" | "source_error" | undefined;
  const conflicts: Conflict[] = [];
  const persistRecord = async (r: MuRecord) => {
    const w = await upsertRecords(ctx.supabase, [{ source: "mangaupdates", sourceKey: String(r.seriesId), medium: "manga", payload: r, licence: MU_LICENCE }], nowIso, { touch: true });
    results.records_written += w.written;
  };

  // 1. Matching.
  let matchDone = false;
  while (!stoppedEarly && !matchDone && results.requests < matchBudget) {
    const rows = await readKuroRows<Record<string, unknown> & { id: number }>(ctx.supabase, "manga", KURO_COLUMNS, next.after_id ?? 0, MATCH_PAGE);
    const ids = rows.map((r) => r.id);
    const linked = new Set((await readLinks(ctx.supabase, ids, "accepted")).map((l) => l.kuro_id));
    const wikidataKeys = new Map<number, string>();
    for (const l of await readLinks(ctx.supabase, ids, "proposed")) if (l.method === "wikidata" && !wikidataKeys.has(l.kuro_id)) wikidataKeys.set(l.kuro_id, String(l.source_key));

    const candidates: LinkCandidate[] = [];
    let lastProcessed: number | null = null;
    let corroborated = 0;
    for (const row of rows) {
      if (results.requests >= matchBudget) break;
      // The deadline is checked per title, not only inside a request.
      if (ctx.now() >= ctx.deadlineMs) {
        stoppedEarly = "budget";
        break;
      }
      const kuro = kuroManga(row);
      const failKey = `m:${row.id}`;
      try {
        if (linked.has(row.id) || kuro.titles.length === 0) {
          // nothing to do
        } else if (exhausted(fails, failKey)) {
          // Failed three consecutive runs: skipped (recorded) so it cannot block the pass.
          results.items_failed++;
          noteFailedItem(failedItems, failKey, "skipped_after_repeated_failures");
        } else {
          const res = await ctx.clients.mangaupdates.request(`${MU_API}/series/search`, { method: "POST", body: { search: kuro.titles[0], perpage: 10 } }, ctx.deadlineMs);
          results.requests++;
          results.searched++;
          if (isItemRejection(res.status)) {
            results.items_failed++;
            noteFailedItem(failedItems, failKey, `http ${res.status}`);
          } else if (res.status !== 200) {
            throw new PoliteFetchError("http", `mangaupdates http ${res.status}`, res.status);
          } else {
            delete fails[failKey];
            const m = muMatch(kuro, parseMuSearch(res.json));
            const wdKey = wikidataKeys.get(row.id);
            const pick = m.accepted[0];
            if (wdKey === undefined) {
              candidates.push(...m.accepted, ...m.proposed);
            } else if (pick && pick.sourceKey === wdKey) {
              // The Wikidata-derived id is accepted only because this search matching, with its runner-up margin, picked it too.
              corroborated++;
              candidates.push({ ...pick, method: "wikidata" });
            } else {
              // Disagreement (a different pick, or no confident pick): both stay proposed and a conflict is listed.
              conflicts.push({ kind: "manga", source: "mangaupdates", sourceKey: wdKey, kuroIds: [row.id], reason: "wikidata_id_disagrees_with_title_match" });
              candidates.push(...m.accepted.map((c) => ({ ...c, status: "proposed" as const })), ...m.proposed);
            }
          }
        }
      } catch (e) {
        const action = classifyFailure(e);
        if (action === "clean") {
          stoppedEarly = (e as { kind: "budget" | "rate_limited" }).kind;
          break;
        }
        if (action === "skip") {
          results.items_failed++;
          noteFailedItem(failedItems, failKey, "unreadable response");
          lastProcessed = row.id;
          continue;
        }
        if (action === "stop") {
          // 5xx / timeout after retries: stop the run and count it against this title; three runs in a row skip it.
          fails[failKey] = (fails[failKey] ?? 0) + 1;
          stoppedEarly = "source_error";
          break;
        }
        throw e;
      }
      lastProcessed = row.id;
    }
    const applied = await applyLinks(ctx.supabase, "manga", candidates, nowIso);
    conflicts.push(...applied.conflicts);
    results.matched += applied.accepted - corroborated;
    results.corroborated += corroborated;
    results.proposed += applied.proposed;
    if (lastProcessed !== null) next.after_id = lastProcessed;
    if (!stoppedEarly && lastProcessed === (rows[rows.length - 1]?.id ?? null) && rows.length < MATCH_PAGE) {
      next.after_id = 0; // pass finished
      matchDone = true;
    } else if (rows.length === 0) {
      next.after_id = 0;
      matchDone = true;
    } else if (lastProcessed !== rows[rows.length - 1]?.id) {
      break; // request budget reached inside the page
    }
  }

  // 2. Records for accepted links.
  let guard = 0;
  while (!stoppedEarly && guard++ < 100 && results.requests < maxRequests) {
    const { data: page, error } = await ctx.supabase
      .from("catalogue_id_links")
      .select("id, source_key")
      .eq("kind", "manga")
      .eq("source", "mangaupdates")
      .eq("status", "accepted")
      .gt("id", next.fetch_after_link ?? 0)
      .order("id", { ascending: true })
      .limit(FETCH_PAGE);
    if (error) throw new Error(`catalogue_id_links read failed: ${error.message ?? error}`);
    if (!page || page.length === 0) {
      next.fetch_after_link = 0;
      break;
    }
    const keys = page.map((p: { source_key: string }) => String(p.source_key));
    const existing = await readExistingRecords(ctx.supabase, "mangaupdates", "manga", keys);
    const stale = (k: string) => {
      const e = existing.get(k);
      return !e || !e.fetched_at || nowMs - Date.parse(e.fetched_at) >= MONTH_MS;
    };
    const needAll: string[] = [];
    for (const k of keys.filter(stale)) {
      if (exhausted(fails, `f:${k}`)) {
        results.items_failed++;
        noteFailedItem(failedItems, `f:${k}`, "skipped_after_repeated_failures");
      } else needAll.push(k);
    }
    const need = needAll
      .map(Number)
      .filter((n: number) => Number.isSafeInteger(n) && n > 0)
      .slice(0, Math.max(0, maxRequests - results.requests));
    const complete = need.length === needAll.length;
    if (need.length > 0) {
      const f = await muFetch({ client: ctx.clients.mangaupdates, deadlineMs: ctx.deadlineMs, onRecord: persistRecord }, need);
      results.requests += f.requests;
      results.records_fetched += f.records.length;
      results.missing_ids += f.missing.length;
      results.items_failed += f.failed.length;
      for (const x of f.failed) noteFailedItem(failedItems, x.key, x.reason);
      for (const r of f.records) delete fails[`f:${r.seriesId}`];
      if (f.errorId !== undefined) fails[`f:${f.errorId}`] = (fails[`f:${f.errorId}`] ?? 0) + 1;
      if (f.stoppedEarly) {
        stoppedEarly = f.stoppedEarly;
        break;
      }
    }
    if (!complete) break; // budget ended inside the page; it is retried next run
    if (page.length < FETCH_PAGE) {
      next.fetch_after_link = 0;
      break;
    }
    next.fetch_after_link = page[page.length - 1].id;
  }

  results.conflicts = conflicts.length;
  next.fails = fails;
  await writeCursor(ctx.supabase, key, "manga", next as Record<string, unknown>, { ...results, failed_items: failedItems }, stoppedEarly ? `stopped_early:${stoppedEarly}` : null, nowIso);
  return { results: { ...results, failed_items: failedItems, conflict_sample: conflicts.slice(0, 20) }, stoppedEarly };
}
