// Anime News Network (anime long tail). Terms verified 2026-11-18 (docs/catalogue-sources-2026-11/
// sources/ann.md): free API, ANN must be named as the source with a link to the encyclopedia entry
// on pages that show its data, at most 50 titles per api.xml request, rate limit 1 request per
// second per IP (Kuro spaces requests 1.1 s), details cached for about a week.
//
// Flow of one run (cursor `catalogue-intake:ann:anime`: { match_after_id, fetch_after_link,
// match_done_for_report }):
//  1. the title report (one request, cached as record `report:anime`, refreshed weekly). A fresh cached report is
//     identified by its stored hash and fetched_at only; its multi-MB payload is read only when matching is pending;
//  2. matching: Kuro titles without an accepted ANN link are scored against the report. A unique
//     match >= 0.92 is accepted (method title_match); ambiguous ones are proposed. A Wikidata-derived
//     proposed ANN id is promoted only when the matcher picks the same key; a different pick keeps
//     both proposed and lists a conflict (link trust rule 2, see wikidata.ts);
//  3. records: accepted ANN links are fetched 50 ids per request (missing or older than a week).
// No XML regexes: parsing uses _shared/catalogue/xml.ts. ANN plot text is deliberately not stored.
// One bad item never stalls the run (item_failures.ts): a batch ANN rejects (4xx) or cannot parse is bisected down to
// the failing id, which is recorded and skipped; a 5xx / timeout stops the run and counts against that page, and a
// page that failed three consecutive runs is skipped (recorded).
import { PoliteFetchError, type PoliteClient } from "../_shared/polite_fetch.ts";
import { classifyFailure, exhausted, type FailedItem, isItemRejection, noteFailedItem, readFailureCounts } from "./item_failures.ts";
import type { SupabaseLike } from "../_shared/catalogue/intake_persistence.ts";
import { normaliseTitle, titleTokens } from "../_shared/catalogue/normalise_title.ts";
import { childrenNamed, firstChild, parseXml, type XmlNode } from "../_shared/catalogue/xml.ts";
import { readKuroRows, type HandlerOutcome, type RunContext } from "./context.ts";
import {
  applyLinks,
  chunk,
  clampInt,
  type Conflict,
  cursorKey,
  type LinkCandidate,
  readCursor,
  payloadHash,
  readExistingRecords,
  selectAll,
  upsertRecords,
  writeCursor,
} from "./store.ts";

export const ANN_REPORT_URL = "https://www.animenewsnetwork.com/encyclopedia/reports.xml?id=155&type=anime&nlist=all";
export const ANN_API = "https://cdn.animenewsnetwork.com/encyclopedia/api.xml";
export const ANN_LICENCE = "ANN-credit-link";
export const ANN_BATCH = 50;
const WEEK_MS = 7 * 86_400_000;

// ---------------------------------------------------------------------------------------------
// Report

export type AnnReportRow = { id: number; type: string | null; name: string; vintage: string | null };

export function parseAnnReport(xml: string): AnnReportRow[] {
  const root = parseXml(xml);
  const rows: AnnReportRow[] = [];
  for (const item of childrenNamed(root, "item")) {
    const id = Number(firstChild(item, "id")?.text);
    const name = firstChild(item, "name")?.text ?? "";
    if (!Number.isInteger(id) || id <= 0 || !name) continue;
    rows.push({
      id,
      type: firstChild(item, "type")?.text || null,
      name,
      vintage: firstChild(item, "vintage")?.text || null,
    });
  }
  return rows;
}

// ---------------------------------------------------------------------------------------------
// Matching

export type AnnKuroTitle = { id: number; titles: string[]; year: number | null; format: string | null };

export const ACCEPT_SCORE = 0.92;
export const RUNNER_UP_MAX = 0.8;
export const PROPOSE_FLOOR = 0.8;
const UNKNOWN_YEAR_FACTOR = 0.9;
const TYPE_MISMATCH_FACTOR = 0.7;
const OFF_YEAR_FACTOR = 0.5;
const MAX_TOKEN_DF = 300;
const MAX_CANDIDATES = 40;
const MAX_PROPOSED = 3;

const FORMAT_TO_ANN: Record<string, string[]> = {
  TV: ["tv"],
  TV_SHORT: ["tv"],
  MOVIE: ["movie"],
  OVA: ["oav"],
  ONA: ["ona"],
  SPECIAL: ["special"],
};

type Indexed = { row: AnnReportRow; tokens: Set<string>; norm: string; year: number | null };
type Index = { entries: Indexed[]; exact: Map<string, number[]>; byToken: Map<string, number[]> };
const indexCache = new WeakMap<AnnReportRow[], Index>();

function yearOf(vintage: string | null): number | null {
  if (!vintage || vintage.length < 4) return null;
  const y = Number(vintage.slice(0, 4));
  return Number.isInteger(y) && y > 1800 ? y : null;
}

function buildIndex(report: AnnReportRow[]): Index {
  const cached = indexCache.get(report);
  if (cached) return cached;
  const entries: Indexed[] = report.map((row) => {
    const norm = normaliseTitle(row.name);
    return { row, norm, tokens: new Set(titleTokens(norm)), year: yearOf(row.vintage) };
  });
  const exact = new Map<string, number[]>();
  const byToken = new Map<string, number[]>();
  entries.forEach((e, i) => {
    if (!e.norm) return;
    exact.set(e.norm, [...(exact.get(e.norm) ?? []), i]);
    for (const t of e.tokens) byToken.set(t, [...(byToken.get(t) ?? []), i]);
  });
  const index = { entries, exact, byToken };
  indexCache.set(report, index);
  return index;
}

export function jaccard(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 || b.size === 0) return 0;
  let inter = 0;
  for (const t of a) if (b.has(t)) inter++;
  return inter / (a.size + b.size - inter);
}

function similarity(kuroNorms: { norm: string; tokens: Set<string> }[], e: Indexed): number {
  let best = 0;
  for (const k of kuroNorms) {
    const s = k.norm === e.norm ? 1 : jaccard(k.tokens, e.tokens);
    if (s > best) best = s;
  }
  return best;
}

function scoreCandidate(kuro: AnnKuroTitle, norms: { norm: string; tokens: Set<string> }[], e: Indexed): number {
  let score = similarity(norms, e);
  if (kuro.year === null || e.year === null) score *= UNKNOWN_YEAR_FACTOR;
  else if (Math.abs(kuro.year - e.year) > 1) score *= OFF_YEAR_FACTOR;
  const allowed = kuro.format ? FORMAT_TO_ANN[kuro.format.toUpperCase()] : undefined;
  if (!allowed || !e.row.type || !allowed.includes(e.row.type.toLowerCase())) score *= TYPE_MISMATCH_FACTOR;
  return score;
}

export function annMatch(kuro: AnnKuroTitle[], report: AnnReportRow[]): { accepted: LinkCandidate[]; proposed: LinkCandidate[] } {
  const index = buildIndex(report);
  const accepted: LinkCandidate[] = [];
  const proposed: LinkCandidate[] = [];
  for (const k of kuro) {
    const norms = [...new Set(k.titles.map(normaliseTitle).filter(Boolean))].map((norm) => ({ norm, tokens: new Set(titleTokens(norm)) }));
    if (norms.length === 0) continue;
    // Candidate generation: exact normalised hits plus rows sharing uncommon tokens.
    const shared = new Map<number, number>();
    for (const { norm, tokens } of norms) {
      for (const i of index.exact.get(norm) ?? []) shared.set(i, Number.MAX_SAFE_INTEGER);
      for (const t of tokens) {
        const hits = index.byToken.get(t);
        if (!hits || hits.length > MAX_TOKEN_DF) continue;
        for (const i of hits) if ((shared.get(i) ?? 0) !== Number.MAX_SAFE_INTEGER) shared.set(i, (shared.get(i) ?? 0) + 1);
      }
    }
    const ids = [...shared.entries()].sort((a, b) => b[1] - a[1]).slice(0, MAX_CANDIDATES).map(([i]) => i);
    const scored = ids
      .map((i) => ({ e: index.entries[i], score: scoreCandidate(k, norms, index.entries[i]) }))
      .sort((a, b) => b.score - a.score || a.e.row.id - b.e.row.id);
    if (scored.length === 0) continue;
    const link = (s: { e: Indexed; score: number }, status: "accepted" | "proposed"): LinkCandidate => ({
      kuroId: k.id,
      source: "ann",
      sourceKey: String(s.e.row.id),
      method: "title_match",
      confidence: Math.round(s.score * 1000) / 1000,
      status,
    });
    if (scored[0].score >= ACCEPT_SCORE && (scored[1]?.score ?? 0) < RUNNER_UP_MAX) {
      accepted.push(link(scored[0], "accepted"));
    } else {
      for (const s of scored.filter((x) => x.score >= PROPOSE_FLOOR).slice(0, MAX_PROPOSED)) proposed.push(link(s, "proposed"));
    }
  }
  return { accepted, proposed };
}

// ---------------------------------------------------------------------------------------------
// Records (api.xml)

export type AnnRecord = {
  id: number;
  type: string | null;
  name: string;
  precision: string | null;
  titles: { main: string; alternatives: { title: string; lang: string | null }[] };
  genres: string[];
  themes: string[];
  episodes: number | null;
  runningTime: string | null;
  vintage: string | null;
  vintageYear: number | null;
  /** ANN's age rating ("Objectionable content": TA, MA, AO, ...). */
  objectionable: string | null;
  ratings: { votes: number | null; weighted: number | null; bayesian: number | null } | null;
  related: { rel: string; id: number; direction: "prev" | "next" }[];
  staff: { task: string; personId: number; name: string }[];
  /** Japanese and English cast only (dubs in other languages are dropped to bound payload size). */
  cast: { role: string; personId: number; name: string; lang: string }[];
  companies: { task: string; companyId: number; name: string }[];
  url: string;
};

const num = (v: string | undefined): number | null => {
  if (v === undefined || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
};

function parseAnnAnime(node: XmlNode): AnnRecord | null {
  const id = num(node.attrs.id);
  if (id === null || !Number.isInteger(id)) return null;
  const infos = childrenNamed(node, "info");
  const ofType = (t: string) => infos.filter((i) => (i.attrs.type ?? "").toLowerCase() === t.toLowerCase());
  const first = (t: string) => ofType(t)[0]?.text || null;
  const vintage = first("Vintage");
  const ratingsNode = firstChild(node, "ratings");
  const related: AnnRecord["related"] = [];
  for (const c of node.children) {
    if (c.name !== "related-prev" && c.name !== "related-next") continue;
    const rid = num(c.attrs.id);
    if (rid !== null && c.attrs.rel) related.push({ rel: c.attrs.rel, id: rid, direction: c.name === "related-prev" ? "prev" : "next" });
  }
  const person = (n: XmlNode) => {
    const p = firstChild(n, "person");
    const pid = num(p?.attrs.id);
    return p && pid !== null ? { personId: pid, name: p.text } : null;
  };
  const staff: AnnRecord["staff"] = [];
  for (const s of childrenNamed(node, "staff")) {
    const p = person(s);
    if (p) staff.push({ task: firstChild(s, "task")?.text ?? "", ...p });
  }
  const cast: AnnRecord["cast"] = [];
  for (const c of childrenNamed(node, "cast")) {
    const lang = (c.attrs.lang ?? "").toUpperCase();
    if (lang !== "JA" && lang !== "EN") continue;
    const p = person(c);
    if (p) cast.push({ role: firstChild(c, "role")?.text ?? "", lang, ...p });
  }
  const companies: AnnRecord["companies"] = [];
  for (const c of childrenNamed(node, "credit")) {
    const co = firstChild(c, "company");
    const cid = num(co?.attrs.id);
    if (co && cid !== null) companies.push({ task: firstChild(c, "task")?.text ?? "", companyId: cid, name: co.text });
  }
  return {
    id,
    type: node.attrs.type || null,
    name: node.attrs.name ?? "",
    precision: node.attrs.precision || null,
    titles: {
      main: first("Main title") ?? node.attrs.name ?? "",
      alternatives: ofType("Alternative title").map((i) => ({ title: i.text, lang: i.attrs.lang ? i.attrs.lang.toUpperCase() : null })),
    },
    genres: ofType("Genres").map((i) => i.text).filter(Boolean),
    themes: ofType("Themes").map((i) => i.text).filter(Boolean),
    episodes: num(first("Number of episodes") ?? undefined),
    runningTime: first("Running time"),
    vintage,
    vintageYear: yearOf(vintage),
    objectionable: first("Objectionable content"),
    ratings: ratingsNode
      ? { votes: num(ratingsNode.attrs.nb_votes), weighted: num(ratingsNode.attrs.weighted_score), bayesian: num(ratingsNode.attrs.bayesian_score) }
      : null,
    related,
    staff,
    cast,
    companies,
    url: `https://www.animenewsnetwork.com/encyclopedia/anime.php?id=${id}`,
  };
}

export function parseAnnApi(xml: string): { records: AnnRecord[]; missing: string[] } {
  const root = parseXml(xml);
  const records: AnnRecord[] = [];
  for (const a of childrenNamed(root, "anime")) {
    const rec = parseAnnAnime(a);
    if (rec) records.push(rec);
  }
  const missing: string[] = [];
  for (const w of childrenNamed(root, "warning")) {
    const eq = w.text.lastIndexOf("=");
    if (w.text.startsWith("no result for") && eq >= 0) missing.push(w.text.slice(eq + 1).trim());
  }
  return { records, missing };
}

export type AnnFetchDeps = {
  client: PoliteClient;
  deadlineMs?: number;
  /** Awaited after each successful batch (persist before the next request). */
  onBatch?: (records: AnnRecord[], ids: number[]) => Promise<void>;
};

export async function annFetch(
  deps: AnnFetchDeps,
  ids: number[],
): Promise<{ records: AnnRecord[]; requests: number; missing: string[]; failed: FailedItem[]; errorIds?: number[]; stoppedEarly?: "budget" | "rate_limited" | "source_error" }> {
  const out = {
    records: [] as AnnRecord[],
    requests: 0,
    missing: [] as string[],
    failed: [] as FailedItem[],
    errorIds: undefined as number[] | undefined,
    stoppedEarly: undefined as "budget" | "rate_limited" | "source_error" | undefined,
  };
  // One request for a group of ids. A group ANN rejects or that cannot be parsed is bisected until the single bad id
  // is found, so one poisoned id cannot hide the 49 good ones next to it.
  const attempt = async (group: number[]): Promise<void> => {
    let text = "";
    let rejected: string | null = null;
    try {
      const res = await deps.client.request(`${ANN_API}?anime=${group.join("/")}`, {}, deps.deadlineMs);
      if (res.status === 200) text = res.text ?? "";
      else if (isItemRejection(res.status)) rejected = `http ${res.status}`;
      else throw new PoliteFetchError("http", `ann http ${res.status}`, res.status);
    } catch (e) {
      const action = classifyFailure(e);
      if (action === "clean") {
        out.stoppedEarly = (e as { kind: "budget" | "rate_limited" }).kind;
        return;
      }
      if (action === "stop") {
        out.stoppedEarly = "source_error";
        out.errorIds = group;
        return;
      }
      if (action === "skip") rejected = "unreadable response";
      else throw e;
    }
    out.requests++;
    let parsed: ReturnType<typeof parseAnnApi> | null = null;
    if (rejected === null) {
      try {
        parsed = parseAnnApi(text);
      } catch {
        rejected = "unreadable XML";
      }
    }
    if (rejected !== null || parsed === null) {
      if (group.length === 1) {
        noteFailedItem(out.failed, `ann:${group[0]}`, rejected ?? "unreadable XML");
        return;
      }
      const mid = Math.ceil(group.length / 2);
      await attempt(group.slice(0, mid));
      if (out.stoppedEarly) return;
      await attempt(group.slice(mid));
      return;
    }
    await deps.onBatch?.(parsed.records, group);
    out.records.push(...parsed.records);
    out.missing.push(...parsed.missing);
  };
  for (const batch of chunk(ids, ANN_BATCH)) {
    await attempt(batch);
    if (out.stoppedEarly) break;
  }
  return out;
}

// ---------------------------------------------------------------------------------------------
// Handler run

type AnnCursor = { match_after_id?: number; fetch_after_link?: number; match_done_for_report?: string | null; fails?: Record<string, number> };

const KURO_COLUMNS = "id, title_english, title_romaji, title_native, title_synonyms, start_date_year, format";

function kuroTitles(row: Record<string, unknown>): AnnKuroTitle {
  const synonyms = Array.isArray(row.title_synonyms) ? row.title_synonyms : typeof row.title_synonyms === "string" ? [row.title_synonyms] : [];
  const titles = [row.title_english, row.title_romaji, row.title_native, ...synonyms].filter((t): t is string => typeof t === "string" && t.trim() !== "");
  return {
    id: Number(row.id),
    titles,
    year: typeof row.start_date_year === "number" ? row.start_date_year : null,
    format: typeof row.format === "string" ? row.format : null,
  };
}

async function readLinks(supabase: SupabaseLike, ids: number[], status: "accepted" | "proposed"): Promise<{ kuro_id: number; source_key: string; method: string }[]> {
  const out: { kuro_id: number; source_key: string; method: string }[] = [];
  for (const part of chunk(ids, 500)) {
    // A title can hold several proposed links, so this read pages past the 1,000-row cap.
    out.push(
      ...(await selectAll<{ kuro_id: number; source_key: string; method: string }>(
        () => supabase.from("catalogue_id_links").select("kuro_id, source_key, method").eq("kind", "anime").eq("source", "ann").eq("status", status).in("kuro_id", part),
        ["id"],
        "catalogue_id_links",
      )),
    );
  }
  return out;
}

export async function runAnn(ctx: RunContext): Promise<HandlerOutcome> {
  const key = cursorKey("ann", "anime");
  const cursor: AnnCursor = (await readCursor<AnnCursor>(ctx.supabase, key)) ?? {};
  const next: AnnCursor = {
    match_after_id: cursor.match_after_id ?? 0,
    fetch_after_link: cursor.fetch_after_link ?? 0,
    match_done_for_report: cursor.match_done_for_report ?? null,
  };
  const fails = readFailureCounts(cursor);
  const failedItems: FailedItem[] = [];
  const nowMs = ctx.now();
  const nowIso = new Date(nowMs).toISOString();
  const results: Record<string, number | boolean | string | null> = {
    report_fetched: false,
    matched: 0,
    corroborated: 0,
    proposed: 0,
    conflicts: 0,
    records_fetched: 0,
    records_written: 0,
    requests: 0,
    missing_ids: 0,
    items_failed: 0,
  };
  let stoppedEarly: "budget" | "rate_limited" | "source_error" | undefined;
  const conflicts: Conflict[] = [];

  // 1. Report (cached, weekly). Freshness and version come from fetched_at and the stored hash alone; the payload
  //    (several MB) is downloaded from the database only when matching actually needs it.
  const { data: cachedReport, error: reportError } = await ctx.supabase
    .from("catalogue_source_records")
    .select("payload_hash, fetched_at")
    .eq("source", "ann")
    .eq("source_key", "report:anime")
    .eq("medium", "anime")
    .maybeSingle();
  if (reportError) throw new Error(`ann report read failed: ${reportError.message ?? reportError}`);
  let reportVersion: string | null = cachedReport?.payload_hash ?? null;
  const reportFetchedAt: string | null = cachedReport?.fetched_at ?? null;
  let reportRows: AnnReportRow[] | null = null;
  const reportFresh = reportVersion !== null && reportFetchedAt !== null && nowMs - Date.parse(reportFetchedAt) < WEEK_MS;
  if (!reportFresh) {
    if (exhausted(fails, "report")) {
      // The report failed three consecutive runs: skipped (recorded); matching uses the cached copy if there is one.
      results.items_failed = (results.items_failed as number) + 1;
      noteFailedItem(failedItems, "report", "skipped_after_repeated_failures");
    } else {
      try {
        const res = await ctx.clients.ann.request(ANN_REPORT_URL, {}, ctx.deadlineMs);
        if (isItemRejection(res.status)) {
          results.items_failed = (results.items_failed as number) + 1;
          noteFailedItem(failedItems, "report", `http ${res.status}`);
        } else if (res.status !== 200) {
          throw new PoliteFetchError("http", `ann report http ${res.status}`, res.status);
        } else {
          reportRows = parseAnnReport(res.text ?? "");
          results.requests = (results.requests as number) + 1;
          await upsertRecords(ctx.supabase, [{ source: "ann", sourceKey: "report:anime", medium: "anime", payload: { items: reportRows }, licence: ANN_LICENCE }], nowIso, { touch: true });
          reportVersion = await payloadHash({ items: reportRows });
          results.report_fetched = true;
          delete fails.report;
        }
      } catch (e) {
        const action = classifyFailure(e);
        if (action === "clean") stoppedEarly = (e as { kind: "budget" | "rate_limited" }).kind;
        else if (action === "skip") {
          // An unreadable report is the item's own fault: recorded, and the run goes on without it.
          results.items_failed = (results.items_failed as number) + 1;
          noteFailedItem(failedItems, "report", "unreadable response");
        } else if (action === "stop") {
          fails.report = (fails.report ?? 0) + 1;
          stoppedEarly = "source_error";
        } else throw e;
      }
    }
  }

  // 2. Matching, once per report version.
  if (reportVersion !== null && !stoppedEarly && next.match_done_for_report !== reportVersion) {
    if (!reportRows) {
      const { data: full, error: fullError } = await ctx.supabase
        .from("catalogue_source_records")
        .select("payload")
        .eq("source", "ann")
        .eq("source_key", "report:anime")
        .eq("medium", "anime")
        .maybeSingle();
      if (fullError) throw new Error(`ann report read failed: ${fullError.message ?? fullError}`);
      reportRows = (full?.payload as { items?: AnnReportRow[] } | undefined)?.items ?? null;
    }
    const limit = clampInt(ctx.limit, 3000, 1, 5000);
    const rows = await readKuroRows<Record<string, unknown> & { id: number }>(ctx.supabase, "anime", KURO_COLUMNS, next.match_after_id ?? 0, limit);
    const ids = rows.map((r) => r.id);
    const linked = new Set((await readLinks(ctx.supabase, ids, "accepted")).map((l) => l.kuro_id));
    const wikidataKeys = new Map<number, Set<string>>();
    for (const l of await readLinks(ctx.supabase, ids, "proposed")) {
      if (l.method !== "wikidata") continue;
      (wikidataKeys.get(l.kuro_id) ?? wikidataKeys.set(l.kuro_id, new Set()).get(l.kuro_id)!).add(String(l.source_key));
    }
    const match = annMatch(rows.filter((r) => !linked.has(r.id)).map(kuroTitles), reportRows ?? []);

    let corroborated = 0;
    const candidates: LinkCandidate[] = [];
    for (const c of match.accepted) {
      const w = wikidataKeys.get(c.kuroId);
      if (!w) candidates.push(c);
      else if (w.has(c.sourceKey)) {
        corroborated++;
        candidates.push(c); // applyLinks promotes the existing proposed link
      } else {
        conflicts.push({ kind: "anime", source: "ann", sourceKey: c.sourceKey, kuroIds: [c.kuroId], reason: "wikidata_id_disagrees_with_title_match" });
        candidates.push({ ...c, status: "proposed" });
      }
    }
    candidates.push(...match.proposed);
    const applied = await applyLinks(ctx.supabase, "anime", candidates, nowIso);
    conflicts.push(...applied.conflicts);
    results.matched = applied.accepted - corroborated;
    results.corroborated = corroborated;
    results.proposed = applied.proposed;
    if (rows.length < limit) {
      next.match_after_id = 0;
      next.match_done_for_report = reportVersion;
    } else {
      next.match_after_id = rows[rows.length - 1].id;
    }
  }

  // 3. Records for accepted links.
  let guard = 0;
  while (!stoppedEarly && guard++ < 200 && (results.requests as number) < 45) {
    const { data: page, error } = await ctx.supabase
      .from("catalogue_id_links")
      .select("id, source_key")
      .eq("kind", "anime")
      .eq("source", "ann")
      .eq("status", "accepted")
      .gt("id", next.fetch_after_link ?? 0)
      .order("id", { ascending: true })
      .limit(ANN_BATCH);
    if (error) throw new Error(`catalogue_id_links read failed: ${error.message ?? error}`);
    if (!page || page.length === 0) {
      next.fetch_after_link = 0;
      break;
    }
    const keys = page.map((p: { source_key: string }) => String(p.source_key));
    const pageKey = `page:${next.fetch_after_link ?? 0}`;
    if (exhausted(fails, pageKey)) {
      // This page failed three consecutive runs (server errors): skipped, recorded, and the pass moves on.
      results.items_failed = (results.items_failed as number) + keys.length;
      noteFailedItem(failedItems, pageKey, "skipped_after_repeated_failures");
      delete fails[pageKey];
      if (page.length < ANN_BATCH) {
        next.fetch_after_link = 0;
        break;
      }
      next.fetch_after_link = page[page.length - 1].id;
      continue;
    }
    const existing = await readExistingRecords(ctx.supabase, "ann", "anime", keys);
    const need = keys.filter((k: string) => {
      const e = existing.get(k);
      return !e || !e.fetched_at || nowMs - Date.parse(e.fetched_at) >= WEEK_MS;
    }).map(Number).filter((n: number) => Number.isInteger(n) && n > 0);
    if (need.length > 0) {
      const fetched = await annFetch(
        {
          client: ctx.clients.ann,
          deadlineMs: ctx.deadlineMs,
          onBatch: async (records) => {
            const w = await upsertRecords(
              ctx.supabase,
              records.map((r) => ({ source: "ann" as const, sourceKey: String(r.id), medium: "anime" as const, payload: r, licence: ANN_LICENCE })),
              nowIso,
              { touch: true },
            );
            results.records_written = (results.records_written as number) + w.written;
          },
        },
        need,
      );
      results.requests = (results.requests as number) + fetched.requests;
      results.records_fetched = (results.records_fetched as number) + fetched.records.length;
      results.missing_ids = (results.missing_ids as number) + fetched.missing.length;
      results.items_failed = (results.items_failed as number) + fetched.failed.length;
      for (const f of fetched.failed) noteFailedItem(failedItems, f.key, f.reason);
      if (fetched.stoppedEarly) {
        stoppedEarly = fetched.stoppedEarly;
        if (fetched.stoppedEarly === "source_error") fails[pageKey] = (fails[pageKey] ?? 0) + 1;
        break; // the page is retried next run: the cursor stays before it
      }
      delete fails[pageKey];
    }
    if (page.length < ANN_BATCH) {
      next.fetch_after_link = 0;
      break;
    }
    next.fetch_after_link = page[page.length - 1].id;
  }

  results.conflicts = conflicts.length;
  next.fails = fails;
  await writeCursor(ctx.supabase, key, "anime", next as Record<string, unknown>, { ...results, failed_items: failedItems }, stoppedEarly ? `stopped_early:${stoppedEarly}` : null, nowIso);
  return { results: { ...results, failed_items: failedItems, conflict_sample: conflicts.slice(0, 20) }, stoppedEarly };
}
