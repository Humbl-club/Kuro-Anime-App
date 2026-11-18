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
import { chunk, clampInt, cursorKey, readCursor, selectAll, stableStringify, WRITE_BATCH, writeCursor, type Medium } from "./store.ts";
import { toRelations as annRelations, toSourceValues as annValues } from "./map_ann.ts";
import { toRelations as muRelations, toSourceValues as muValues } from "./map_mangaupdates.ts";
import { toRelations as wdRelations, toSourceValues as wdValues, type WikidataPayload } from "./map_wikidata.ts";
import type { AnnRecord } from "./ann.ts";
import type { MuRecord } from "./mangaupdates.ts";
import { composeCredits, CreditsBudgetError, flushPendingLinks, preloadCreditMaps, type CrosswalkPayload, type EntityDeps } from "./entities.ts";

export type ComposeDeps = {
  supabase: SupabaseLike;
  now?: () => number;
  /** Insert new people/companies/characters (credits group switched, Task 15). Default false: shadow proposes only. */
  allowCreate?: boolean;
  /** Absolute ms deadline (per `now`): checked before every title and before every credit. */
  deadlineMs?: number;
};
export type ComposeResult = {
  titles: number;
  written: number;
  unchanged: number;
  reviews: number;
  /** Shadow rows deleted because the title no longer produces that field. */
  removed: number;
  /** Input ids fully composed, in input order. A budget stop leaves the rest out; the cursor may move past exactly these. */
  composedIds: number[];
  stoppedEarly?: "budget";
};

type ShadowRow = { medium: Medium; media_id: number; field: string; value: unknown; source: string | null; computed_at: string };
type Link = { kuro_id: number; source: string; source_key: string; kind: string };

const SOURCES_FOR: Record<Medium, Source[]> = { anime: ["wikidata", "ann"], manga: ["wikidata", "mangaupdates"] };

async function readIn<T>(supabase: SupabaseLike, table: string, columns: string, col: string, values: (string | number)[], eq: Record<string, string>, orderBy: string[]): Promise<T[]> {
  const out: T[] = [];
  for (const part of chunk(values, WRITE_BATCH)) {
    out.push(
      ...(await selectAll<T>(
        () => {
          let q = supabase.from(table).select(columns);
          for (const [k, v] of Object.entries(eq)) q = q.eq(k, v);
          return q.in(col, part);
        },
        orderBy,
        table,
      )),
    );
  }
  return out;
}

export type TitleInputs = {
  mediaId: number;
  today: boolean | null;
  /** Per-source column values from the mappers. */
  bySource: Partial<Record<Source, Record<string, unknown>>>;
  relations: RawRelation[];
  /** Raw ANN / MangaUpdates records, kept for the credits composer (Task 7b). */
  records?: { ann?: AnnRecord; mangaupdates?: MuRecord };
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
  const result: ComposeResult = { titles: 0, written: 0, unchanged: 0, reviews: 0, removed: 0, composedIds: [] };
  const ids = [...new Set(mediaIds)];
  if (ids.length === 0) return result;
  const clock = deps.now ?? Date.now;
  const nowIso = new Date(clock()).toISOString();
  const supabase = deps.supabase;
  const sources = SOURCES_FOR[medium];
  const overBudget = () => deps.deadlineMs !== undefined && clock() >= deps.deadlineMs;

  const links = (await readIn<Link>(supabase, "catalogue_id_links", "kuro_id, source, source_key, kind", "kuro_id", ids, { kind: medium, status: "accepted" }, ["id"])).filter((l) => (sources as string[]).includes(l.source));
  const todayRows = await readIn<{ id: number; is_adult: boolean | null }>(supabase, medium, "id, is_adult", "id", ids, {}, ["id"]);
  const today = new Map(todayRows.map((r) => [r.id, r.is_adult]));

  const keysBySource = new Map<Source, string[]>();
  for (const l of links) keysBySource.set(l.source as Source, [...(keysBySource.get(l.source as Source) ?? []), l.source_key]);
  const records = new Map<string, unknown>();
  for (const [source, keys] of keysBySource) {
    const rows = await readIn<{ source_key: string; payload: unknown }>(supabase, "catalogue_source_records", "source_key, payload", "source_key", [...new Set(keys)], { source, medium }, ["source_key"]);
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
      t.records = { ...t.records, ann: payload as AnnRecord };
      rels = annRelations(payload as AnnRecord);
    } else if (l.source === "mangaupdates") {
      t.bySource.mangaupdates = muValues(payload as MuRecord);
      t.records = { ...t.records, mangaupdates: payload as MuRecord };
      rels = muRelations(payload as MuRecord);
    }
    t.relations.push(...rels);
    for (const r of rels) targetKeys.set(r.source, (targetKeys.get(r.source) ?? new Set()).add(r.targetKey));
  }

  // Relation targets resolve only through accepted links.
  const resolved = new Map<string, { kind: Medium; id: number }>();
  for (const [source, keys] of targetKeys) {
    const rows = await readIn<Link>(supabase, "catalogue_id_links", "kuro_id, source, source_key, kind", "source_key", [...keys], { source, status: "accepted" }, ["id"]);
    for (const r of rows) {
      const kind = r.kind as Medium;
      if (r.kind !== "anime" && r.kind !== "manga") continue;
      if (source === "ann" && kind !== "anime") continue;
      if (source === "mangaupdates" && kind !== "manga") continue;
      resolved.set(`${source}:${r.source_key}`, { kind, id: r.kuro_id });
    }
  }
  const resolve = (source: Source, key: string) => resolved.get(`${source}:${key}`) ?? null;

  // Every shadow field the chunk's titles hold today (paged: 100 titles hold well over 1,000 rows).
  const existing = new Map<string, { value: unknown; source: string | null }>();
  const existingFields = new Map<number, Set<string>>();
  for (const r of await readIn<{ media_id: number; field: string; value: unknown; source: string | null }>(supabase, "catalogue_shadow_values", "media_id, field, value, source", "media_id", ids, { medium }, ["media_id", "field"])) {
    existing.set(`${r.media_id}|${r.field}`, { value: r.value, source: r.source });
    (existingFields.get(r.media_id) ?? existingFields.set(r.media_id, new Set()).get(r.media_id)!).add(r.field);
  }

  // Credits: preload the accepted links, crosswalk records and crosswalked staff rows of the whole chunk once,
  // so no credit queries per person.
  const creditDeps: EntityDeps = {
    supabase,
    medium,
    allowCreate: deps.allowCreate,
    nowIso,
    linkMap: new Map<string, number | null>(),
    crosswalkMap: new Map<string, CrosswalkPayload | null>(),
    creditedCache: new Map(),
    staffByAnilist: new Map(),
    pendingLinks: new Map(),
    shouldStop: deps.deadlineMs === undefined ? undefined : overBudget,
  };
  const chunkRecords = [...inputs.values()].map((t) => t.records).filter((r): r is NonNullable<TitleInputs["records"]> => !!r);
  await preloadCreditMaps(creditDeps, {
    staff: chunkRecords.flatMap((r) => (r.ann?.staff ?? []).map((x) => String(x.personId))),
    studio: chunkRecords.flatMap((r) => (r.ann?.companies ?? []).filter((c) => /animation|production/i.test(c.task)).map((x) => String(x.companyId))),
    author: chunkRecords.flatMap((r) => (r.mangaupdates?.authors ?? []).map((a) => String(a.authorId))),
  });

  const rows: ShadowRow[] = [];
  const stale: { mediaId: number; fields: string[] }[] = [];
  for (const mediaId of ids) {
    if (overBudget()) {
      result.stoppedEarly = "budget";
      break;
    }
    const t = inputs.get(mediaId);
    if (!t) {
      result.composedIds.push(mediaId);
      continue;
    }
    // Compose the whole title first; a budget stop inside it keeps nothing of this title.
    const produced: { field: string; value: unknown; source: string | null }[] = [];
    let review: { reason: string } | null = null;
    try {
      const composed = composeTitle(medium, t, resolve);
      review = composed.review;
      produced.push(...composed.fields);
      const counts = new Map<string, number>();
      for (const f of composed.fields) if (f.source && f.source !== "today") for (const s of f.source.split(",")) counts.set(s, (counts.get(s) ?? 0) + 1);
      if (t.records) {
        const credits = await composeCredits(creditDeps, t.mediaId, t.records);
        for (const f of credits.fields) {
          produced.push(f);
          for (const s of f.source.split(",")) if (!f.field.startsWith("credits:proposed") && !f.field.startsWith("credits:review")) counts.set(s, (counts.get(s) ?? 0) + 1);
        }
      }
      if (review) produced.push({ field: "review:adult", value: review, source: "composer" });
      const used = [...counts.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).map(([s]) => s);
      if (used.length > 0) produced.push({ field: "data_sources", value: used, source: "composer" });
    } catch (e) {
      if (!(e instanceof CreditsBudgetError)) throw e;
      result.stoppedEarly = "budget";
      break;
    }
    result.titles++;
    if (review) result.reviews++;
    for (const f of produced) {
      const prev = existing.get(`${t.mediaId}|${f.field}`);
      if (prev && stableStringify(prev.value) === stableStringify(f.value) && prev.source === f.source) result.unchanged++;
      else rows.push({ medium, media_id: t.mediaId, field: f.field, value: f.value, source: f.source, computed_at: nowIso });
    }
    // A field the title no longer produces (a fixed review flag, a dropped source field, empty credits) must not linger.
    const keep = new Set(produced.map((f) => f.field));
    const gone = [...(existingFields.get(t.mediaId) ?? [])].filter((f) => !keep.has(f));
    if (gone.length > 0) stale.push({ mediaId: t.mediaId, fields: gone });
    result.composedIds.push(mediaId);
  }
  await flushPendingLinks(creditDeps);

  for (const part of chunk(rows, WRITE_BATCH)) {
    const { error } = await supabase.from("catalogue_shadow_values").upsert(part, { onConflict: "medium,media_id,field" });
    if (error) throw new Error(`catalogue_shadow_values upsert failed: ${error.message ?? error}`);
    result.written += part.length;
  }
  for (const s of stale) {
    const { error } = await supabase.from("catalogue_shadow_values").delete().eq("medium", medium).eq("media_id", s.mediaId).in("field", s.fields);
    if (error) throw new Error(`catalogue_shadow_values delete failed: ${error.message ?? error}`);
    result.removed += s.fields.length;
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
  const total = { titles: 0, written: 0, unchanged: 0, reviews: 0, removed: 0 };
  let done = 0;
  let stoppedEarly: string | undefined;
  for (const part of chunk(ids, COMPOSE_CHUNK)) {
    if (ctx.now() >= ctx.deadlineMs) {
      stoppedEarly = "budget";
      break;
    }
    // The deadline is also checked per title and per credit inside compose.
    const r = await compose({ supabase: ctx.supabase, now: ctx.now, deadlineMs: ctx.deadlineMs }, ctx.medium, part);
    total.titles += r.titles;
    total.written += r.written;
    total.unchanged += r.unchanged;
    total.reviews += r.reviews;
    total.removed += r.removed;
    done += r.composedIds.length;
    if (r.stoppedEarly) {
      stoppedEarly = r.stoppedEarly;
      break;
    }
  }
  const finished = done === ids.length;
  // The cursor sits on the last fully composed title (ids are composed in order, so these are a prefix).
  const nextLast = finished ? (ids.length < limit ? 0 : ids[ids.length - 1]) : done > 0 ? ids[done - 1] : lastId;
  const results = { ...total, pass_completed: finished && ids.length < limit };
  await writeCursor(ctx.supabase, key, ctx.medium, { last_id: nextLast }, results, stoppedEarly ? `stopped_early:${stoppedEarly}` : null);
  return { results, stoppedEarly };
}
