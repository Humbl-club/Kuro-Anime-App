// Shadow composer (catalogue Task 7). For each Kuro title with accepted links it maps the stored
// source records to column values, applies the precedence policy and upserts
// catalogue_shadow_values. It never writes a published table: the comparator (Task 8) reads
// shadow values next to today's published ones, and `publish` (Task 15) is the only later writer.
//
// Shadow fields written per title (field, value):
//   <column>         value picked by precedence (source column = winning source)
//   is_adult         composeAdult result (never clears without review)
//   review:adult     { reason } when the title needs the owner's eyes (adult today but no source says
//                    so, or newly adult)
//   relations        ComposedRelation[] (targets resolved through accepted links only)
//   data_sources     distinct sources used, most fields first
// Only accepted links feed a title (a Wikidata-only `proposed` ANN id is not used, link-trust rule 2).
// An unchanged value or source writes nothing, so a second run makes no writes.
import type { SupabaseLike } from "../_shared/catalogue/intake_persistence.ts";
import { composeAdult, DATE_TRIPLES, mapRelations, pick, PRECEDENCE, type RawRelation, type Source, type SourceValue } from "../_shared/catalogue/precedence.ts";
import type { HandlerOutcome, RunContext } from "./context.ts";
import { chunk, clampInt, cursorKey, readCursor, stableStringify, WRITE_BATCH, writeCursor, type Medium } from "./store.ts";
import { toRelations as annRelations, toSourceValues as annValues } from "./map_ann.ts";
import { toRelations as muRelations, toSourceValues as muValues } from "./map_mangaupdates.ts";
import { toRelations as wdRelations, toSourceValues as wdValues, type WikidataPayload } from "./map_wikidata.ts";
import type { AnnRecord } from "./ann.ts";
import type { MuRecord } from "./mangaupdates.ts";

export type ComposeDeps = { supabase: SupabaseLike; now?: () => number };
export type ComposeResult = { titles: number; written: number; unchanged: number; reviews: number };

type ShadowRow = { medium: Medium; media_id: number; field: string; value: unknown; source: string | null; computed_at: string };
type Link = { kuro_id: number; source: string; source_key: string; kind: string };

const SOURCES_FOR: Record<Medium, Source[]> = { anime: ["wikidata", "ann"], manga: ["wikidata", "mangaupdates"] };

async function readIn<T>(supabase: SupabaseLike, table: string, columns: string, col: string, values: (string | number)[], eq: Record<string, string>): Promise<T[]> {
  const out: T[] = [];
  for (const part of chunk(values, WRITE_BATCH)) {
    let q = supabase.from(table).select(columns);
    for (const [k, v] of Object.entries(eq)) q = q.eq(k, v);
    const { data, error } = await q.in(col, part);
    if (error) throw new Error(`${table} read failed: ${error.message ?? error}`);
    out.push(...((data ?? []) as T[]));
  }
  return out;
}

export type TitleInputs = {
  mediaId: number;
  today: boolean | null;
  /** Per-source column values from the mappers. */
  bySource: Partial<Record<Source, Record<string, unknown>>>;
  relations: RawRelation[];
};

/** Pure composition of one title's shadow fields. Exported for tests of the policy wiring. */
export function composeTitle(
  medium: Medium,
  t: TitleInputs,
  resolve: (source: Source, key: string) => { kind: Medium; id: number } | null,
): { fields: { field: string; value: unknown; source: string | null }[]; review: { reason: string } | null } {
  const fields: { field: string; value: unknown; source: string | null }[] = [];
  const valuesFor = (column: string): SourceValue[] =>
    (Object.entries(t.bySource) as [Source, Record<string, unknown>][]).filter(([, v]) => column in v).map(([source, v]) => ({ source, value: v[column] }));

  const done = new Set<string>();
  // A date triple is taken from one source as a unit: year decides, month and day follow it.
  for (const triple of DATE_TRIPLES) {
    const winner = pick(triple[0], medium, valuesFor(triple[0]));
    if (!winner) continue;
    for (const column of triple) {
      const v = t.bySource[winner.source]?.[column];
      if (v !== null && v !== undefined) fields.push({ field: column, value: v, source: winner.source });
      done.add(column);
    }
  }
  for (const column of Object.keys(PRECEDENCE[medium])) {
    if (done.has(column) || column === "is_adult") continue;
    const winner = pick(column, medium, valuesFor(column));
    if (winner) fields.push({ field: column, value: winner.value, source: winner.source });
  }

  // Adult: one boolean per source that carries adult data.
  const adultByOrder = (PRECEDENCE[medium].is_adult ?? []).map((s) => [s, t.bySource[s]?.is_adult] as const).filter(([, v]) => typeof v === "boolean") as [Source, boolean][];
  const adult = composeAdult(t.today, adultByOrder.map(([, v]) => v));
  let review: { reason: string } | null = null;
  if (adultByOrder.length > 0 || t.today === true) {
    const source = adult.value ? (adultByOrder.find(([, v]) => v)?.[0] ?? "today") : adultByOrder[0]?.[0] ?? null;
    fields.push({ field: "is_adult", value: adult.value, source });
    if (adult.review) review = { reason: "adult_today_no_source_says_adult" };
    else if (adult.newlyAdult) review = { reason: "newly_adult" };
  }

  const rel = mapRelations(t.relations, resolve, medium);
  if (rel.relations.length > 0) fields.push({ field: "relations", value: rel.relations, source: [...new Set(rel.relations.flatMap((r) => r.sources))].sort().join(",") });

  return { fields, review };
}

export async function compose(deps: ComposeDeps, medium: Medium, mediaIds: number[]): Promise<ComposeResult> {
  const result: ComposeResult = { titles: 0, written: 0, unchanged: 0, reviews: 0 };
  const ids = [...new Set(mediaIds)];
  if (ids.length === 0) return result;
  const nowIso = new Date((deps.now ?? Date.now)()).toISOString();
  const supabase = deps.supabase;
  const sources = SOURCES_FOR[medium];

  const links = (await readIn<Link>(supabase, "catalogue_id_links", "kuro_id, source, source_key, kind", "kuro_id", ids, { kind: medium, status: "accepted" })).filter((l) => (sources as string[]).includes(l.source));
  const todayRows = await readIn<{ id: number; is_adult: boolean | null }>(supabase, medium, "id, is_adult", "id", ids, {});
  const today = new Map(todayRows.map((r) => [r.id, r.is_adult]));

  const keysBySource = new Map<Source, string[]>();
  for (const l of links) keysBySource.set(l.source as Source, [...(keysBySource.get(l.source as Source) ?? []), l.source_key]);
  const records = new Map<string, unknown>();
  for (const [source, keys] of keysBySource) {
    const rows = await readIn<{ source_key: string; payload: unknown }>(supabase, "catalogue_source_records", "source_key, payload", "source_key", [...new Set(keys)], { source, medium });
    for (const r of rows) records.set(`${source}:${r.source_key}`, r.payload);
  }

  // Per title: mapped values and raw relations from every linked source.
  const inputs = new Map<number, TitleInputs>();
  const targetKeys = new Map<Source, Set<string>>();
  for (const l of links) {
    const payload = records.get(`${l.source}:${l.source_key}`);
    if (!payload) continue;
    const t = inputs.get(l.kuro_id) ?? { mediaId: l.kuro_id, today: today.get(l.kuro_id) ?? null, bySource: {}, relations: [] };
    inputs.set(l.kuro_id, t);
    let rels: RawRelation[] = [];
    if (l.source === "wikidata") {
      t.bySource.wikidata = wdValues(payload as WikidataPayload);
      rels = wdRelations(payload as WikidataPayload);
    } else if (l.source === "ann") {
      t.bySource.ann = annValues(payload as AnnRecord);
      rels = annRelations(payload as AnnRecord);
    } else if (l.source === "mangaupdates") {
      t.bySource.mangaupdates = muValues(payload as MuRecord);
      rels = muRelations(payload as MuRecord);
    }
    t.relations.push(...rels);
    for (const r of rels) targetKeys.set(r.source, (targetKeys.get(r.source) ?? new Set()).add(r.targetKey));
  }

  // Relation targets resolve only through accepted links.
  const resolved = new Map<string, { kind: Medium; id: number }>();
  for (const [source, keys] of targetKeys) {
    const rows = await readIn<Link>(supabase, "catalogue_id_links", "kuro_id, source, source_key, kind", "source_key", [...keys], { source, status: "accepted" });
    for (const r of rows) {
      const kind = r.kind as Medium;
      if (r.kind !== "anime" && r.kind !== "manga") continue;
      if (source === "ann" && kind !== "anime") continue;
      if (source === "mangaupdates" && kind !== "manga") continue;
      resolved.set(`${source}:${r.source_key}`, { kind, id: r.kuro_id });
    }
  }
  const resolve = (source: Source, key: string) => resolved.get(`${source}:${key}`) ?? null;

  const existing = new Map<string, { value: unknown; source: string | null }>();
  for (const r of await readIn<{ media_id: number; field: string; value: unknown; source: string | null }>(supabase, "catalogue_shadow_values", "media_id, field, value, source", "media_id", ids, { medium })) {
    existing.set(`${r.media_id}|${r.field}`, { value: r.value, source: r.source });
  }

  const rows: ShadowRow[] = [];
  const consider = (mediaId: number, field: string, value: unknown, source: string | null) => {
    const prev = existing.get(`${mediaId}|${field}`);
    if (prev && stableStringify(prev.value) === stableStringify(value) && prev.source === source) {
      result.unchanged++;
      return;
    }
    rows.push({ medium, media_id: mediaId, field, value, source, computed_at: nowIso });
  };

  for (const t of inputs.values()) {
    const composed = composeTitle(medium, t, resolve);
    result.titles++;
    const counts = new Map<string, number>();
    for (const f of composed.fields) {
      consider(t.mediaId, f.field, f.value, f.source);
      if (f.source && f.source !== "today") for (const s of f.source.split(",")) counts.set(s, (counts.get(s) ?? 0) + 1);
    }
    if (composed.review) {
      result.reviews++;
      consider(t.mediaId, "review:adult", composed.review, "composer");
    }
    const used = [...counts.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).map(([s]) => s);
    if (used.length > 0) consider(t.mediaId, "data_sources", used, "composer");
  }

  for (const part of chunk(rows, WRITE_BATCH)) {
    const { error } = await supabase.from("catalogue_shadow_values").upsert(part, { onConflict: "medium,media_id,field" });
    if (error) throw new Error(`catalogue_shadow_values upsert failed: ${error.message ?? error}`);
    result.written += part.length;
  }
  return result;
}

// ---------------------------------------------------------------------------------------------
// Handler run (cursor: import_track_state `catalogue-intake:compose:<medium>`, { last_id })

export const COMPOSE_DEFAULT_LIMIT = 500;
const COMPOSE_CHUNK = 100;

async function readLinkedIds(supabase: SupabaseLike, medium: Medium, afterId: number, limit: number): Promise<number[]> {
  const ids: number[] = [];
  let last = afterId;
  while (ids.length < limit) {
    const { data, error } = await supabase
      .from("catalogue_id_links")
      .select("kuro_id")
      .eq("kind", medium)
      .eq("status", "accepted")
      .gt("kuro_id", last)
      .order("kuro_id", { ascending: true })
      .limit(1000);
    if (error) throw new Error(`catalogue_id_links read failed: ${error.message ?? error}`);
    const page = (data ?? []) as { kuro_id: number }[];
    for (const r of page) if (ids[ids.length - 1] !== r.kuro_id) ids.push(r.kuro_id);
    if (page.length < 1000) break;
    last = page[page.length - 1].kuro_id;
  }
  return ids.slice(0, limit);
}

export async function runCompose(ctx: RunContext): Promise<HandlerOutcome> {
  const key = cursorKey("compose", ctx.medium);
  const cursor = await readCursor<{ last_id?: number }>(ctx.supabase, key);
  const lastId = typeof cursor?.last_id === "number" ? cursor.last_id : 0;
  const limit = clampInt(ctx.limit, COMPOSE_DEFAULT_LIMIT, 1, 5000);
  const ids = await readLinkedIds(ctx.supabase, ctx.medium, lastId, limit);
  const total: ComposeResult = { titles: 0, written: 0, unchanged: 0, reviews: 0 };
  let done = 0;
  let stoppedEarly: string | undefined;
  for (const part of chunk(ids, COMPOSE_CHUNK)) {
    if (ctx.now() >= ctx.deadlineMs) {
      stoppedEarly = "budget";
      break;
    }
    const r = await compose({ supabase: ctx.supabase, now: ctx.now }, ctx.medium, part);
    total.titles += r.titles;
    total.written += r.written;
    total.unchanged += r.unchanged;
    total.reviews += r.reviews;
    done += part.length;
  }
  const finished = done === ids.length;
  const nextLast = finished ? (ids.length < limit ? 0 : ids[ids.length - 1]) : done > 0 ? ids[done - 1] : lastId;
  const results = { ...total, pass_completed: finished && ids.length < limit };
  await writeCursor(ctx.supabase, key, ctx.medium, { last_id: nextLast }, results, stoppedEarly ? `stopped_early:${stoppedEarly}` : null);
  return { results, stoppedEarly };
}
