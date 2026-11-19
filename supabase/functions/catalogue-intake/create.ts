// create (catalogue Task 15c): new titles from allowed sources, now that AniList no longer adds them.
//
// Candidates
//   anime  ANN encyclopedia report rows (catalogue_source_records `report:anime`) with no accepted ANN link;
//   manga  MangaUpdates series records (catalogue_source_records source 'mangaupdates') with no accepted link.
//          The `mangaupdates_new` handler (mangaupdates_new.ts) stores the full record of every recently added series
//          Kuro does not hold, so these records are the set of new manga; the matcher handler only fetches linked ones.
//   Wikidata items carrying ANN/MangaUpdates ids but no Kuro title are not stored by the wikidata handler either
//   (it queries by Kuro AniList ids), so they are not candidates yet.
// For each candidate (spec section 3 identity rule, the same thresholds as the ann/mangaupdates matchers):
//   1. an accepted link means skip;
//   2. a title match against existing Kuro rows that meets the rule means add a link (never a row);
//   3. an ambiguous candidate (proposed matches only) goes to the review list as proposed links, never a row;
//   4. otherwise, in `insert` mode, catalogue_create_title_v1 inserts the row (anilist_id null, visible), its accepted
//      link and its shadow values in one transaction. `report` mode writes nothing but the result (the handler stores
//      it in import_runs.results) and the cursor.
// Values for a new row come from what the source gives now: the ANN report row (title, type, vintage) or the stored
// MangaUpdates record. compose later fills the rest once the ann/mangaupdates handlers fetch the record of the new
// accepted link. `minYear` bounds the candidates by start year; insert mode requires it (owner decision: the ANN
// encyclopedia holds many entries AniList never had).
import type { SupabaseLike } from "../_shared/catalogue/intake_persistence.ts";
import { normaliseTitle, titleTokens } from "../_shared/catalogue/normalise_title.ts";
import { ACCEPT_SCORE, type AnnKuroTitle, annMatch, type AnnReportRow, PROPOSE_FLOOR, RUNNER_UP_MAX } from "./ann.ts";
import { annDates, annFormat } from "./map_ann.ts";
import { muFormat, toSourceValues as muValues } from "./map_mangaupdates.ts";
import { muScore, type MuHit, type MuKuro, type MuRecord } from "./mangaupdates.ts";
import { applyLinks, chunk, clampInt, cursorKey, readCursor, writeCursor, type LinkCandidate, type Medium } from "./store.ts";
import { readKuroRows } from "./context.ts";
import type { HandlerOutcome, RunContext } from "./context.ts";

export type CreateMode = "report" | "insert";
export type CreateDeps = { supabase: SupabaseLike; now?: () => number };
export type CreateOptions = {
  mode: CreateMode;
  /** Only candidates that started in this year or later (insert mode requires it). */
  minYear?: number;
  /** Candidates scanned per call (default 300). */
  limit?: number;
  /** Cursor: the last report id / series key scanned by the previous call. */
  after?: string | null;
  /** Sample size in the result (default 25). */
  sample?: number;
};

export type CreateSample = { source: string; key: string; title: string; year: number | null; format: string | null };
export type CreateResult = {
  mode: CreateMode;
  medium: Medium;
  scanned: number;
  skippedLinked: number;
  skippedUnusable: number;
  skippedYear: number;
  /** Matched an existing title (accepted by the identity rule): a link, not a row. */
  linked: number;
  /** Ambiguous: stored as proposed links for review. */
  review: number;
  wouldCreate: number;
  created: number;
  alreadyExisted: number;
  sample: CreateSample[];
  /** Last key scanned, or null when the end of the candidate list was reached. */
  next: string | null;
};

type Candidate = {
  source: "ann" | "mangaupdates";
  key: string;
  title: string;
  titles: string[];
  year: number | null;
  format: string | null;
  /** The source's own type text (ANN type), used by the matcher. */
  type: string | null;
  /** Whitelisted columns of the new row. */
  row: Record<string, unknown>;
  /** Shadow fields (field -> value). */
  shadow: Record<string, unknown>;
};

const SOURCE_FOR: Record<Medium, "ann" | "mangaupdates"> = { anime: "ann", manga: "mangaupdates" };
const KURO_COLUMNS: Record<Medium, string> = {
  anime: "id, title_english, title_romaji, title_native, title_synonyms, start_date_year, format",
  manga: "id, title_english, title_romaji, title_native, title_synonyms, start_date_year, format, country_of_origin",
};

function titlesOf(row: Record<string, unknown>): string[] {
  const synonyms = Array.isArray(row.title_synonyms) ? row.title_synonyms : typeof row.title_synonyms === "string" ? [row.title_synonyms] : [];
  return [row.title_english, row.title_romaji, row.title_native, ...synonyms].filter((t): t is string => typeof t === "string" && t.trim() !== "");
}

function emptyResult(mode: CreateMode, medium: Medium): CreateResult {
  return { mode, medium, scanned: 0, skippedLinked: 0, skippedUnusable: 0, skippedYear: 0, linked: 0, review: 0, wouldCreate: 0, created: 0, alreadyExisted: 0, sample: [], next: null };
}

async function acceptedKeys(supabase: SupabaseLike, medium: Medium, source: string, keys: string[]): Promise<Set<string>> {
  const out = new Set<string>();
  for (const part of chunk(keys, 500)) {
    const { data, error } = await supabase.from("catalogue_id_links").select("source_key").eq("kind", medium).eq("source", source).eq("status", "accepted").in("source_key", part);
    if (error) throw new Error(`catalogue_id_links read failed: ${error.message ?? error}`);
    for (const r of (data ?? []) as { source_key: string }[]) out.add(String(r.source_key));
  }
  return out;
}

// ---- candidate sources --------------------------------------------------------------------

async function annCandidates(supabase: SupabaseLike, after: number, limit: number): Promise<{ rows: AnnReportRow[]; scanned: number; last: number | null; reportMissing: boolean }> {
  const { data, error } = await supabase.from("catalogue_source_records").select("payload").eq("source", "ann").eq("source_key", "report:anime").eq("medium", "anime").maybeSingle();
  if (error) throw new Error(`ann report read failed: ${error.message ?? error}`);
  const items = (data?.payload as { items?: AnnReportRow[] } | undefined)?.items;
  if (!Array.isArray(items)) return { rows: [], scanned: 0, last: null, reportMissing: true };
  const sorted = items.filter((r) => Number.isInteger(r.id) && r.id > after).sort((a, b) => a.id - b.id).slice(0, limit);
  return { rows: sorted, scanned: sorted.length, last: sorted.length > 0 ? sorted[sorted.length - 1].id : null, reportMissing: false };
}

function annCandidate(r: AnnReportRow): Candidate | null {
  const format = annFormat(r.type);
  if (!format || !r.name?.trim()) return null;
  const start = annDates(r.vintage).start;
  const row: Record<string, unknown> = { title_romaji: r.name.trim(), format, data_sources: ["ann"] };
  if (start) {
    row.start_date_year = start.year;
    if (start.month) row.start_date_month = start.month;
    if (start.day) row.start_date_day = start.day;
  }
  return { source: "ann", key: String(r.id), title: r.name.trim(), titles: [r.name], year: start?.year ?? null, format, type: r.type, row, shadow: { ...row } };
}

function muCandidate(key: string, rec: MuRecord): Candidate | null {
  const format = muFormat(rec.type);
  if (!format || !rec.title?.trim()) return null;
  const v = muValues(rec);
  const row: Record<string, unknown> = { ...v, data_sources: ["mangaupdates"] };
  return { source: "mangaupdates", key, title: rec.title.trim(), titles: [rec.title, ...rec.associated], year: rec.year, format, type: rec.type, row, shadow: { ...row } };
}

// ---- matching against existing Kuro rows ------------------------------------------------------

type Matched = { accepted: LinkCandidate[]; proposed: LinkCandidate[] };
type Scored = { kuroId: number; score: number };

/** Edge workers OOM if create loads the whole catalogue (~42k manga) into one match index.
 *  Page Kuro rows and keep only the top scores per candidate (few candidates per run). */
/** Keep pages small: a 1k-row manga page of titles/synonyms is already heavy on Edge. */
const KURO_MATCH_PAGE = 500;
const TOP_SCORES = 40;
/** Manga matching is heavier than ANN; Edge OOMs above ~50 candidates per run. */
const MANGA_CREATE_LIMIT_MAX = 40;

function mergeTop(into: Map<string, Scored[]>, key: string, add: Scored[]): void {
  if (add.length === 0) return;
  const merged = [...(into.get(key) ?? []), ...add].sort((a, b) => b.score - a.score || a.kuroId - b.kuroId);
  const seen = new Set<number>();
  const top: Scored[] = [];
  for (const s of merged) {
    if (seen.has(s.kuroId)) continue;
    seen.add(s.kuroId);
    top.push(s);
    if (top.length >= TOP_SCORES) break;
  }
  into.set(key, top);
}

function decideFromScores(
  cands: Candidate[],
  tops: Map<string, Scored[]>,
  source: "ann" | "mangaupdates",
): Matched {
  const accepted: LinkCandidate[] = [];
  const proposed: LinkCandidate[] = [];
  for (const c of cands) {
    const scored = tops.get(c.key) ?? [];
    const link = (s: Scored, status: "accepted" | "proposed"): LinkCandidate => ({
      kuroId: s.kuroId,
      source,
      sourceKey: c.key,
      method: "title_match",
      confidence: Math.round(s.score * 1000) / 1000,
      status,
    });
    if (scored.length > 0 && scored[0].score >= ACCEPT_SCORE && (scored[1]?.score ?? 0) < RUNNER_UP_MAX) {
      accepted.push(link(scored[0], "accepted"));
    } else {
      for (const s of scored.filter((x) => x.score >= PROPOSE_FLOOR).slice(0, 3)) proposed.push(link(s, "proposed"));
    }
  }
  return { accepted, proposed };
}

/** Score one Kuro page against ANN candidates via annMatch (indexes the small candidate set). */
function scoreAnnPage(kuroRows: Record<string, unknown>[], cands: Candidate[]): Map<string, Scored[]> {
  const report: AnnReportRow[] = cands.map((c) => ({ id: Number(c.key), type: c.type, name: c.title, vintage: c.year ? String(c.year) : null }));
  const kuro: AnnKuroTitle[] = kuroRows.map((r) => ({
    id: Number(r.id),
    titles: titlesOf(r),
    year: typeof r.start_date_year === "number" ? r.start_date_year : null,
    format: typeof r.format === "string" ? r.format : null,
  }));
  const matched = annMatch(kuro, report);
  const out = new Map<string, Scored[]>();
  for (const m of [...matched.accepted, ...matched.proposed]) {
    const list = out.get(m.sourceKey) ?? [];
    list.push({ kuroId: m.kuroId, score: Number(m.confidence) || 0 });
    out.set(m.sourceKey, list);
  }
  return out;
}

/** Score one Kuro page against MangaUpdates candidates (local token index for the page only). */
function scoreMuPage(kuroRows: Record<string, unknown>[], cands: Candidate[]): Map<string, Scored[]> {
  const MAX_DF = 300;
  const byToken = new Map<string, number[]>();
  const byNorm = new Map<string, number[]>();
  const kuro: MuKuro[] = kuroRows.map((r) => ({
    id: Number(r.id),
    titles: titlesOf(r),
    year: typeof r.start_date_year === "number" ? r.start_date_year : null,
    format: typeof r.format === "string" ? r.format : null,
    country: typeof r.country_of_origin === "string" ? r.country_of_origin : null,
  }));
  kuro.forEach((k, i) => {
    for (const norm of new Set(k.titles.map(normaliseTitle).filter(Boolean))) {
      const norms = byNorm.get(norm);
      if (norms) norms.push(i);
      else byNorm.set(norm, [i]);
      for (const t of titleTokens(norm)) {
        const hits = byToken.get(t);
        if (hits) hits.push(i);
        else byToken.set(t, [i]);
      }
    }
  });
  const out = new Map<string, Scored[]>();
  for (const c of cands) {
    const hit: MuHit = { seriesId: Number(c.key), titles: c.titles, year: c.year, type: c.type };
    const shared = new Map<number, number>();
    for (const norm of new Set(c.titles.map(normaliseTitle).filter(Boolean))) {
      for (const i of byNorm.get(norm) ?? []) shared.set(i, Number.MAX_SAFE_INTEGER);
      for (const t of titleTokens(norm)) {
        const hits = byToken.get(t);
        if (!hits || hits.length > MAX_DF) continue;
        for (const i of hits) if ((shared.get(i) ?? 0) !== Number.MAX_SAFE_INTEGER) shared.set(i, (shared.get(i) ?? 0) + 1);
      }
    }
    const scored = [...shared.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, TOP_SCORES)
      .map(([i]) => ({ kuroId: kuro[i].id, score: muScore(kuro[i], hit) }));
    out.set(c.key, scored);
  }
  return out;
}

/** Manga: never scan the full 42k-row table on Edge. Pull only rows whose titles equal a candidate title. */
async function loadMangaByExactTitles(
  supabase: SupabaseLike,
  cands: Candidate[],
): Promise<(Record<string, unknown> & { id: number })[]> {
  const titles = [...new Set(cands.flatMap((c) => c.titles.map((t) => t.trim()).filter(Boolean)))];
  const byId = new Map<number, Record<string, unknown> & { id: number }>();
  for (const col of ["title_english", "title_romaji", "title_native"] as const) {
    for (const part of chunk(titles, 80)) {
      const { data, error } = await supabase.from("manga").select(KURO_COLUMNS.manga).in(col, part);
      if (error) throw new Error(`manga title lookup failed: ${error.message ?? error}`);
      for (const r of (data ?? []) as (Record<string, unknown> & { id: number })[]) byId.set(Number(r.id), r);
    }
  }
  return [...byId.values()];
}

async function matchAgainstCatalogue(
  supabase: SupabaseLike,
  medium: Medium,
  cands: Candidate[],
): Promise<Matched> {
  if (cands.length === 0) return { accepted: [], proposed: [] };
  const tops = new Map<string, Scored[]>();
  if (medium === "manga") {
    const pool = await loadMangaByExactTitles(supabase, cands);
    for (const [key, scored] of scoreMuPage(pool, cands)) mergeTop(tops, key, scored);
    return decideFromScores(cands, tops, "mangaupdates");
  }
  // Anime: page the catalogue (ANN match indexes the small candidate set, so pages stay cheap).
  let after = 0;
  for (;;) {
    const page = await readKuroRows<Record<string, unknown> & { id: number }>(
      supabase,
      medium,
      KURO_COLUMNS[medium],
      after,
      KURO_MATCH_PAGE,
    );
    if (page.length === 0) break;
    for (const [key, scored] of scoreAnnPage(page, cands)) mergeTop(tops, key, scored);
    after = page[page.length - 1].id;
    if (page.length < KURO_MATCH_PAGE) break;
  }
  return decideFromScores(cands, tops, "ann");
}

// ---- create ------------------------------------------------------------------------------------

export async function create(deps: CreateDeps, medium: Medium, opts: CreateOptions): Promise<CreateResult> {
  const result = emptyResult(opts.mode, medium);
  if (opts.mode === "insert" && !(Number.isInteger(opts.minYear) && Number(opts.minYear) > 1800)) {
    throw new Error("create: insert mode needs minYear (the ANN encyclopedia holds many entries AniList never had)");
  }
  const supabase = deps.supabase;
  const nowIso = new Date((deps.now ?? Date.now)()).toISOString();
  const limitCap = medium === "manga" ? MANGA_CREATE_LIMIT_MAX : 1000;
  const limit = clampInt(opts.limit, medium === "manga" ? 25 : 300, 1, limitCap);
  const sampleMax = clampInt(opts.sample, 25, 0, 200);
  const source = SOURCE_FOR[medium];

  // 1. candidate list (scan window)
  let cands: Candidate[] = [];
  let unusable = 0;
  if (medium === "anime") {
    const win = await annCandidates(supabase, Number(opts.after ?? 0) || 0, limit);
    result.scanned = win.scanned;
    result.next = win.scanned < limit ? null : String(win.last);
    for (const r of win.rows) {
      const c = annCandidate(r);
      if (c) cands.push(c);
      else unusable++;
    }
  } else {
    const after = opts.after ?? "";
    const { data, error } = await supabase.from("catalogue_source_records").select("source_key, payload").eq("source", "mangaupdates").eq("medium", "manga").gt("source_key", after).order("source_key", { ascending: true }).limit(limit);
    if (error) throw new Error(`mangaupdates records read failed: ${error.message ?? error}`);
    const rows = ((data ?? []) as { source_key: string; payload: MuRecord }[]).filter((r) => !String(r.source_key).startsWith("report"));
    result.scanned = rows.length;
    result.next = rows.length < limit ? null : rows[rows.length - 1].source_key;
    for (const r of rows) {
      const c = muCandidate(String(r.source_key), r.payload);
      if (c) cands.push(c);
      else unusable++;
    }
  }
  result.skippedUnusable = unusable;

  // 2. year bound, then accepted-link skip
  if (opts.minYear !== undefined) {
    const before = cands.length;
    cands = cands.filter((c) => c.year !== null && c.year >= Number(opts.minYear));
    result.skippedYear = before - cands.length;
  }
  const linked = await acceptedKeys(supabase, medium, source, cands.map((c) => c.key));
  const fresh = cands.filter((c) => !linked.has(c.key));
  result.skippedLinked = cands.length - fresh.length;
  if (fresh.length === 0) return result;

  // 3. match against existing Kuro rows (paged — never load the whole catalogue into Edge memory)
  const matched = await matchAgainstCatalogue(supabase, medium, fresh);
  // One source key that two or more Kuro titles accept is ambiguous (the same rule applyLinks enforces): review, no row.
  const kuroPerKey = new Map<string, Set<number>>();
  for (const m of matched.accepted) kuroPerKey.set(m.sourceKey, (kuroPerKey.get(m.sourceKey) ?? new Set<number>()).add(m.kuroId));
  const ambiguous = new Set([...kuroPerKey].filter(([, ids]) => ids.size > 1).map(([k]) => k));
  matched.proposed.push(...matched.accepted.filter((m) => ambiguous.has(m.sourceKey)).map((m) => ({ ...m, status: "proposed" as const })));
  matched.accepted = matched.accepted.filter((m) => !ambiguous.has(m.sourceKey));
  const acceptedKeysSet = new Set(matched.accepted.map((m) => m.sourceKey));
  const proposedKeysSet = new Set(matched.proposed.map((m) => m.sourceKey));
  const toCreate = fresh.filter((c) => !acceptedKeysSet.has(c.key) && !proposedKeysSet.has(c.key));
  result.linked = fresh.filter((c) => acceptedKeysSet.has(c.key)).length;
  result.review = fresh.filter((c) => !acceptedKeysSet.has(c.key) && proposedKeysSet.has(c.key)).length;
  result.wouldCreate = toCreate.length;
  result.sample = toCreate.slice(0, sampleMax).map((c) => ({ source: c.source, key: c.key, title: c.title, year: c.year, format: c.format }));

  if (opts.mode === "report") return result;

  // 4. insert mode: links for matches, proposed links for review, rows for the rest
  if (matched.accepted.length > 0 || matched.proposed.length > 0) {
    await applyLinks(supabase, medium, [...matched.accepted, ...matched.proposed], nowIso);
  }
  for (const c of toCreate) {
    const { data, error } = await supabase.rpc("catalogue_create_title_v1", {
      p_medium: medium,
      p_row: c.row,
      p_source: c.source,
      p_source_key: c.key,
      p_confidence: 1,
      p_shadow: c.shadow,
    });
    if (error) throw new Error(`catalogue_create_title_v1(${c.source}:${c.key}) failed: ${error.message ?? error}`);
    if ((data as { created?: boolean } | null)?.created) result.created++;
    else result.alreadyExisted++;
  }
  return result;
}

// ---- handler run (cursor: import_track_state `catalogue-intake:create:<medium>`) ---------------------

export async function runCreate(ctx: RunContext, opts: { mode: CreateMode; minYear?: number }): Promise<HandlerOutcome> {
  const key = cursorKey("create", ctx.medium);
  const cursor = (await readCursor<{ after?: string | null; mode?: string }>(ctx.supabase, key)) ?? {};
  // A cursor written by another mode starts again: report and insert passes are independent.
  const after = cursor.mode === opts.mode ? cursor.after ?? null : null;
  const r = await create({ supabase: ctx.supabase, now: ctx.now }, ctx.medium, { ...opts, limit: ctx.limit, after });
  await writeCursor(ctx.supabase, key, ctx.medium, { after: r.next, mode: opts.mode }, { ...r, sample: r.sample.length }, null, new Date(ctx.now()).toISOString());
  return { results: r as unknown as Record<string, unknown> };
}
