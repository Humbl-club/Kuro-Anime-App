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

function matchAnn(kuroRows: Record<string, unknown>[], cands: Candidate[]): Matched {
  const report: AnnReportRow[] = cands.map((c) => ({ id: Number(c.key), type: c.type, name: c.title, vintage: c.year ? String(c.year) : null }));
  const kuro: AnnKuroTitle[] = kuroRows.map((r) => ({ id: Number(r.id), titles: titlesOf(r), year: typeof r.start_date_year === "number" ? r.start_date_year : null, format: typeof r.format === "string" ? r.format : null }));
  return annMatch(kuro, report);
}

/** Matching of manga candidates: candidate Kuro rows by exact or shared uncommon title tokens, scored with muScore. */
function matchMu(kuroRows: Record<string, unknown>[], cands: Candidate[]): Matched {
  const MAX_DF = 300;
  const byToken = new Map<string, number[]>();
  const byNorm = new Map<string, number[]>();
  const kuro: MuKuro[] = kuroRows.map((r) => ({ id: Number(r.id), titles: titlesOf(r), year: typeof r.start_date_year === "number" ? r.start_date_year : null, format: typeof r.format === "string" ? r.format : null, country: typeof r.country_of_origin === "string" ? r.country_of_origin : null }));
  kuro.forEach((k, i) => {
    for (const norm of new Set(k.titles.map(normaliseTitle).filter(Boolean))) {
      byNorm.set(norm, [...(byNorm.get(norm) ?? []), i]);
      for (const t of titleTokens(norm)) byToken.set(t, [...(byToken.get(t) ?? []), i]);
    }
  });
  const accepted: LinkCandidate[] = [];
  const proposed: LinkCandidate[] = [];
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
    const scored = [...shared.entries()].sort((a, b) => b[1] - a[1]).slice(0, 40)
      .map(([i]) => ({ k: kuro[i], score: muScore(kuro[i], hit) }))
      .sort((a, b) => b.score - a.score || a.k.id - b.k.id);
    const link = (s: { k: MuKuro; score: number }, status: "accepted" | "proposed"): LinkCandidate => ({ kuroId: s.k.id, source: "mangaupdates", sourceKey: c.key, method: "title_match", confidence: Math.round(s.score * 1000) / 1000, status });
    if (scored.length > 0 && scored[0].score >= ACCEPT_SCORE && (scored[1]?.score ?? 0) < RUNNER_UP_MAX) accepted.push(link(scored[0], "accepted"));
    else for (const s of scored.filter((x) => x.score >= PROPOSE_FLOOR).slice(0, 3)) proposed.push(link(s, "proposed"));
  }
  return { accepted, proposed };
}

// ---- create ------------------------------------------------------------------------------------

export async function create(deps: CreateDeps, medium: Medium, opts: CreateOptions): Promise<CreateResult> {
  const result = emptyResult(opts.mode, medium);
  if (opts.mode === "insert" && !(Number.isInteger(opts.minYear) && Number(opts.minYear) > 1800)) {
    throw new Error("create: insert mode needs minYear (the ANN encyclopedia holds many entries AniList never had)");
  }
  const supabase = deps.supabase;
  const nowIso = new Date((deps.now ?? Date.now)()).toISOString();
  const limit = clampInt(opts.limit, 300, 1, 1000);
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

  // 3. match against existing Kuro rows
  const kuroRows = await readKuroRows<Record<string, unknown> & { id: number }>(supabase, medium, KURO_COLUMNS[medium], 0, 200_000);
  const matched = medium === "anime" ? matchAnn(kuroRows, fresh) : matchMu(kuroRows, fresh);
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
