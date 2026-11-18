// LINK TRUST RULES (Wikidata is openly editable; lead ruling 2026-11-18):
//  1. The Q-id found by the reverse lookup on OUR AniList id (P8729/P8731) is `accepted`
//     (method wikidata, confidence 1). A duplicate claim (two items for one title, or one item for
//     two titles) links nothing: the candidates are stored `proposed` and reported as a conflict.
//  2. ANN / MangaUpdates ids that only a Wikidata item carries (P1985, P11149) are stored as
//     `proposed` (method wikidata). They become `accepted` only when the ANN / MangaUpdates
//     matcher (title, year, format against the source's own record) agrees with the same key;
//     a disagreement keeps them `proposed` and is listed as a conflict (ann.ts, mangaupdates.ts).
//  3. Stability: a later run that finds a different Q-id or derived key for a title that already
//     has an accepted link never replaces it. The existing link stays, the new candidate is written
//     `proposed` and reported as a conflict (store.ts applyLinks).
//
// Wikidata crosswalk and facts (CC0). Finds the item for each Kuro title through the AniList id
// Wikidata holds (P8729 anime, P8731 manga), keeps the raw item as a source record, and links the
// title to the item and to the ANN / MangaUpdates ids the item carries.
//
// Limits (plan Global Constraints): one query in flight, at least 1 s between queries (the caller's
// PoliteLimiter), at most 500 ids per VALUES clause, POST as application/sparql-query so the URL
// stays short. AniList ids are string literals in Wikidata.
//
// The query returns entity-attribute-value rows (?aid ?item ?p ?v): one UNION branch per property,
// so multi-valued properties (aliases, genres, relations) never multiply each other.
import { isPoliteCleanStop, type PoliteClient } from "../_shared/polite_fetch.ts";
import type { SupabaseLike } from "../_shared/catalogue/intake_persistence.ts";
import type { HandlerOutcome, RunContext } from "./context.ts";
import { readKuroRows } from "./context.ts";
import { crosswalkKey, type CrosswalkPayload } from "./entities.ts";
import {
  applyLinks,
  chunk,
  clampInt,
  type Conflict,
  cursorKey,
  readCursor,
  writeCursor,
  type LinkCandidate,
  type Medium,
  readExistingRecords,
  selectAll,
  upsertRecords,
} from "./store.ts";

export const WDQS_ENDPOINT = "https://query.wikidata.org/sparql";
export const WIKIDATA_BATCH = 500;
export const WIKIDATA_LICENCE = "CC0-1.0";

const ANILIST_PROPERTY: Record<Medium, string> = { anime: "P8729", manga: "P8731" };

/** Identifier properties kept per medium (raw, in the record payload). */
const ID_PROPERTIES: Record<Medium, readonly string[]> = {
  anime: ["P4086", "P1985", "P5646", "P4835", "P4983", "P4947"],
  manga: ["P4087", "P1984", "P11149", "P648"],
};

/** Properties kept for both media. */
const COMMON_PROPERTIES = ["P577", "P580", "P582", "P136", "P144", "P155", "P156", "P4969", "P856"] as const;
const ANIME_ONLY_PROPERTIES = ["P1113"] as const;

export function wikidataProperties(medium: Medium): string[] {
  return [...ID_PROPERTIES[medium], ...COMMON_PROPERTIES, ...(medium === "anime" ? ANIME_ONLY_PROPERTIES : [])];
}

/** SPARQL for one batch of AniList ids. Exported so tests can inspect the batch. */
export function buildQuery(medium: Medium, anilistIds: readonly (number | string)[]): string {
  const aidProp = ANILIST_PROPERTY[medium];
  const values = anilistIds.map((id) => `"${String(id).replace(/[^0-9]/g, "")}"`).join(" ");
  // Every branch starts from the named subquery %items (evaluated first), so a branch never scans
  // all of Wikidata for its property.
  const branch = (p: string, pattern: string) => `    { INCLUDE %items . ${pattern} BIND("${p}" AS ?p) }`;
  const branches = [
    branch(aidProp, `?item wdt:${aidProp} ?v .`),
    ...wikidataProperties(medium).map((p) => branch(p, `?item wdt:${p} ?v .`)),
    branch("label:en", `?item rdfs:label ?v . FILTER(LANG(?v) = "en")`),
    branch("label:ja", `?item rdfs:label ?v . FILTER(LANG(?v) = "ja")`),
    branch("alias:en", `?item skos:altLabel ?v . FILTER(LANG(?v) = "en")`),
    branch("alias:ja", `?item skos:altLabel ?v . FILTER(LANG(?v) = "ja")`),
    branch("sitelink:enwiki", `?sle schema:about ?item ; schema:isPartOf <https://en.wikipedia.org/> ; schema:name ?v .`),
    branch("sitelink:jawiki", `?slj schema:about ?item ; schema:isPartOf <https://ja.wikipedia.org/> ; schema:name ?v .`),
  ];
  return [
    "SELECT ?aid ?item ?p ?v",
    `WITH { SELECT ?aid ?item WHERE { VALUES ?aid { ${values} } ?item wdt:${aidProp} ?aid . } } AS %items`,
    "WHERE {",
    "  {",
    branches.join("\n    UNION\n"),
    "  }",
    "}",
  ].join("\n");
}

// ---------------------------------------------------------------------------------------------
// Parsing

type Binding = { aid?: { value: string }; item?: { value: string }; p?: { value: string }; v?: { value: string; type?: string } };

export type WikidataItem = {
  qid: string;
  /** AniList ids (of this batch) that point at the item. */
  matchedAids: Set<string>;
  props: Record<string, string[]>;
};

function entityId(value: string): string {
  const tail = value.slice(value.lastIndexOf("/") + 1);
  return tail;
}

export function parseBindings(json: unknown): Map<string, WikidataItem> {
  const bindings = ((json as { results?: { bindings?: Binding[] } } | null)?.results?.bindings ?? []) as Binding[];
  const items = new Map<string, WikidataItem>();
  for (const b of bindings) {
    if (!b.item?.value || !b.aid?.value || !b.p?.value || b.v?.value === undefined) continue;
    const qid = entityId(b.item.value);
    const item = items.get(qid) ?? { qid, matchedAids: new Set<string>(), props: {} };
    items.set(qid, item);
    item.matchedAids.add(b.aid.value);
    // Entity values (genres, relations) come as IRIs; keep the Q-id only.
    const value = b.v.type === "uri" && b.v.value.includes("/entity/") ? entityId(b.v.value) : b.v.value;
    const list = (item.props[b.p.value] ??= []);
    if (!list.includes(value)) list.push(value);
  }
  for (const item of items.values()) for (const k of Object.keys(item.props)) item.props[k].sort();
  return items;
}

/** MangaUpdates ids on Wikidata are the base-36 slug; the API and our links use the numeric series id. */
export function muSeriesIdFromWikidata(value: string): string | null {
  const v = value.trim().toLowerCase();
  if (!/^[0-9a-z]+$/.test(v)) return null;
  const n = parseInt(v, 36);
  return Number.isSafeInteger(n) && n > 0 ? String(n) : null;
}

// ---------------------------------------------------------------------------------------------
// Crosswalk

export type WikidataDeps = {
  supabase: SupabaseLike;
  client: PoliteClient;
  /** Absolute ms deadline; a query that cannot start before it ends the run cleanly. */
  deadlineMs?: number;
  now?: () => number;
};

export type CrosswalkResult = {
  linked: number;
  conflicts: Conflict[];
  queries: number;
  /** Rows of the input (in order) whose batch finished; the cursor may advance past exactly these. */
  completedRows: number;
  recordsWritten: number;
  proposed: number;
  stoppedEarly?: "budget" | "rate_limited";
};

export async function wikidataCrosswalk(
  deps: WikidataDeps,
  medium: Medium,
  kuroRows: { id: number; anilist_id: number | string | null }[],
): Promise<CrosswalkResult> {
  const result: CrosswalkResult = { linked: 0, conflicts: [], queries: 0, completedRows: 0, recordsWritten: 0, proposed: 0 };
  const rows = kuroRows.filter((r) => r.anilist_id !== null && r.anilist_id !== undefined);
  for (const batch of chunk(rows, WIKIDATA_BATCH)) {
    let json: unknown;
    try {
      const res = await deps.client.request(
        WDQS_ENDPOINT,
        { method: "POST", body: buildQuery(medium, batch.map((r) => r.anilist_id as number)), contentType: "application/sparql-query" },
        deps.deadlineMs,
      );
      if (res.status !== 200) throw new Error(`wikidata http ${res.status}`);
      json = res.json;
    } catch (e) {
      if (isPoliteCleanStop(e)) {
        result.stoppedEarly = (e as { kind: "budget" | "rate_limited" }).kind;
        break;
      }
      throw e;
    }
    result.queries++;
    const stats = await persistBatch(deps, medium, batch, parseBindings(json));
    result.linked += stats.accepted;
    result.proposed += stats.proposed;
    result.recordsWritten += stats.recordsWritten;
    result.conflicts.push(...stats.conflicts);
    result.completedRows += batch.length;
  }
  // Rows without an AniList id never block the cursor: the caller filters them in its query.
  return result;
}

async function persistBatch(
  deps: WikidataDeps,
  medium: Medium,
  batch: { id: number; anilist_id: number | string | null }[],
  items: Map<string, WikidataItem>,
) {
  const kuroByAid = new Map<string, number[]>();
  for (const r of batch) {
    const k = String(r.anilist_id);
    kuroByAid.set(k, [...(kuroByAid.get(k) ?? []), r.id]);
  }
  const aidProp = ANILIST_PROPERTY[medium];

  // Which Kuro titles does each item answer for, and which items answer for each title?
  const kuroByItem = new Map<string, Set<number>>();
  const itemsByKuro = new Map<number, Set<string>>();
  for (const item of items.values()) {
    for (const aid of item.matchedAids) {
      for (const kid of kuroByAid.get(aid) ?? []) {
        (kuroByItem.get(item.qid) ?? kuroByItem.set(item.qid, new Set()).get(item.qid)!).add(kid);
        (itemsByKuro.get(kid) ?? itemsByKuro.set(kid, new Set()).get(kid)!).add(item.qid);
      }
    }
  }
  // An implicated item (shared by several titles, or competing for one title) yields no derived links.
  const implicated = new Set<string>();
  for (const [qid, kids] of kuroByItem) if (kids.size > 1) implicated.add(qid);
  for (const qids of itemsByKuro.values()) if (qids.size > 1) qids.forEach((q) => implicated.add(q));

  // Duplicate claims are judged on the item's FULL fetched AniList id list (the P8729/P8731 branch returns every
  // value), not on this batch: an item claiming two AniList ids that both map to Kuro rows links nothing, even when
  // the two titles fall in different batches. Ids outside this batch are resolved with one paged Kuro read.
  const claimedAids = (item: WikidataItem): string[] => [...new Set([...(item.props[aidProp] ?? []), ...item.matchedAids])];
  const outside = new Set<string>();
  for (const item of items.values()) {
    const claimed = claimedAids(item);
    if (claimed.length > 1) for (const a of claimed) if (!kuroByAid.has(a) && /^[0-9]+$/.test(a)) outside.add(a);
  }
  const kuroOutside = new Map<string, number[]>();
  for (const part of chunk([...outside].map(Number), 500)) {
    const found = await selectAll<{ id: number; anilist_id: number }>(() => deps.supabase.from(medium).select("id, anilist_id").in("anilist_id", part), ["id"], medium);
    for (const f of found) kuroOutside.set(String(f.anilist_id), [...(kuroOutside.get(String(f.anilist_id)) ?? []), f.id]);
  }
  const claimConflict = new Map<string, string>(); // qid -> reason
  for (const item of items.values()) {
    const titles = new Set<number>();
    for (const a of claimedAids(item)) for (const kid of kuroByAid.get(a) ?? kuroOutside.get(a) ?? []) titles.add(kid);
    // Several titles inside this batch are already handled by applyLinks (one_key_for_several_titles).
    if (titles.size > 1 && !implicated.has(item.qid)) claimConflict.set(item.qid, "item_claims_several_titles");
  }
  // An item that another title already holds in a stored accepted link is not this title's either.
  for (const part of chunk([...items.keys()], 500)) {
    const held = await selectAll<{ kuro_id: number; source_key: string }>(
      () => deps.supabase.from("catalogue_id_links").select("kuro_id, source_key").eq("kind", medium).eq("source", "wikidata").eq("status", "accepted").in("source_key", part),
      ["id"],
      "catalogue_id_links",
    );
    for (const h of held) {
      const kids = kuroByItem.get(h.source_key);
      if (kids && [...kids].some((k) => k !== h.kuro_id)) claimConflict.set(h.source_key, "item_held_by_another_title");
    }
  }

  const records = [...items.values()].map((item) => ({
    source: "wikidata" as const,
    sourceKey: item.qid,
    medium,
    licence: WIKIDATA_LICENCE,
    payload: { qid: item.qid, medium, anilist_ids: item.props[aidProp] ?? [...item.matchedAids].sort(), props: item.props },
  }));

  const candidates: LinkCandidate[] = [];
  const claimConflicts: Conflict[] = [];
  for (const [qid, kids] of kuroByItem) {
    const item = items.get(qid)!;
    for (const kid of kids) {
      const reason = claimConflict.get(qid);
      if (reason) {
        // Contested item: stored for review as proposed, never accepted, and no ANN / MangaUpdates id is derived from it.
        candidates.push({ kuroId: kid, source: "wikidata", sourceKey: qid, method: "wikidata", confidence: 1, status: "proposed" });
        claimConflicts.push({ kind: medium, source: "wikidata", sourceKey: qid, kuroIds: [kid], reason });
        continue;
      }
      candidates.push({ kuroId: kid, source: "wikidata", sourceKey: qid, method: "wikidata", confidence: 1, status: "accepted" });
      if (implicated.has(qid)) continue;
      // A single value only: several ANN / MangaUpdates ids on one item are ambiguous and stay in the raw record.
      if (medium === "anime") {
        const ann = item.props["P1985"] ?? [];
        if (ann.length === 1 && /^[0-9]+$/.test(ann[0])) candidates.push({ kuroId: kid, source: "ann", sourceKey: ann[0], method: "wikidata", confidence: 1, status: "proposed" });
      } else {
        const mu = (item.props["P11149"] ?? []).map(muSeriesIdFromWikidata).filter((x): x is string => x !== null);
        if (mu.length === 1) candidates.push({ kuroId: kid, source: "mangaupdates", sourceKey: mu[0], method: "wikidata", confidence: 1, status: "proposed" });
      }
    }
  }

  const rec = await upsertRecords(deps.supabase, records);
  const links = await applyLinks(deps.supabase, medium, candidates);
  return { accepted: links.accepted, proposed: links.proposed, conflicts: [...claimConflicts, ...links.conflicts], recordsWritten: rec.written };
}

// ---------------------------------------------------------------------------------------------
// People and company crosswalk (Task 7b): ANN person id (P1982) / company id (P1983) to the Wikidata
// item, and for people the AniList staff id (P11227). One query per <= 500 ANN keys, stored as one
// record per key (`person:ann:<key>` / `company:ann:<key>`, medium anime), a negative record
// ({qid: null}) when Wikidata has no item so a key is asked once. Duplicate items for one key are stored
// as a conflict and never used for linking.

export type EntityCrosswalkKind = "person" | "company";
const ENTITY_PROPERTY: Record<EntityCrosswalkKind, string> = { person: "P1982", company: "P1983" };

export function buildEntityQuery(kind: EntityCrosswalkKind, annKeys: readonly string[]): string {
  const values = annKeys.map((k) => `"${String(k).replace(/[^0-9]/g, "")}"`).join(" ");
  const optional = kind === "person" ? "OPTIONAL { ?item wdt:P11227 ?al }" : `OPTIONAL { ?item rdfs:label ?label . FILTER(LANG(?label) = "en") }`;
  return `SELECT ?key ?item ${kind === "person" ? "?al" : "?label"} WHERE { VALUES ?key { ${values} } ?item wdt:${ENTITY_PROPERTY[kind]} ?key . ${optional} }`;
}

export function parseEntityBindings(json: unknown): Map<string, CrosswalkPayload> {
  type B = { key?: { value: string }; item?: { value: string }; al?: { value: string }; label?: { value: string } };
  const bindings = ((json as { results?: { bindings?: B[] } } | null)?.results?.bindings ?? []) as B[];
  const byKey = new Map<string, { items: Set<string>; al: Set<number>; label: string | null }>();
  for (const b of bindings) {
    if (!b.key?.value || !b.item?.value) continue;
    const e = byKey.get(b.key.value) ?? { items: new Set<string>(), al: new Set<number>(), label: null };
    byKey.set(b.key.value, e);
    e.items.add(entityId(b.item.value));
    const al = Number(b.al?.value);
    if (b.al?.value && Number.isSafeInteger(al) && al > 0) e.al.add(al);
    if (b.label?.value && e.label === null) e.label = b.label.value;
  }
  const out = new Map<string, CrosswalkPayload>();
  for (const [key, e] of byKey) {
    if (e.items.size > 1) out.set(key, { qid: null, conflict: true });
    else out.set(key, { qid: [...e.items][0], anilistStaffId: e.al.size === 1 ? [...e.al][0] : null, label: e.label });
  }
  return out;
}

export async function wikidataEntityCrosswalk(
  deps: WikidataDeps,
  kind: EntityCrosswalkKind,
  annKeys: string[],
): Promise<{ queries: number; recordsWritten: number; completedKeys: number; stoppedEarly?: "budget" | "rate_limited" }> {
  const out: { queries: number; recordsWritten: number; completedKeys: number; stoppedEarly?: "budget" | "rate_limited" } = { queries: 0, recordsWritten: 0, completedKeys: 0 };
  for (const batch of chunk([...new Set(annKeys)], WIKIDATA_BATCH)) {
    let json: unknown;
    try {
      const res = await deps.client.request(WDQS_ENDPOINT, { method: "POST", body: buildEntityQuery(kind, batch), contentType: "application/sparql-query" }, deps.deadlineMs);
      if (res.status !== 200) throw new Error(`wikidata http ${res.status}`);
      json = res.json;
    } catch (e) {
      if (isPoliteCleanStop(e)) {
        out.stoppedEarly = (e as { kind: "budget" | "rate_limited" }).kind;
        break;
      }
      throw e;
    }
    out.queries++;
    const found = parseEntityBindings(json);
    const records = batch.map((key) => ({
      source: "wikidata" as const,
      sourceKey: crosswalkKey(kind, key),
      medium: "anime" as const,
      licence: WIKIDATA_LICENCE,
      payload: { annKey: key, ...(found.get(key) ?? { qid: null }) },
    }));
    out.recordsWritten += (await upsertRecords(deps.supabase, records)).written;
    out.completedKeys += batch.length;
  }
  return out;
}

const ENTITY_RECORD_LIMIT = 100;
const PRODUCTION_TASK = /animation|production/i;

/** Crosswalks the ANN people and production companies of the next ANN records that have no crosswalk record yet. */
export async function runEntityCrosswalk(ctx: RunContext): Promise<{ records: number; people: number; companies: number; queries: number; stoppedEarly?: "budget" | "rate_limited" }> {
  const key = cursorKey("wikidata-entities", "anime");
  const cursor = await readCursor<{ after_key?: string }>(ctx.supabase, key);
  const after = typeof cursor?.after_key === "string" ? cursor.after_key : "";
  const { data, error } = await ctx.supabase
    .from("catalogue_source_records")
    .select("source_key, payload")
    .eq("source", "ann")
    .eq("medium", "anime")
    .gt("source_key", after)
    .order("source_key", { ascending: true })
    .limit(ENTITY_RECORD_LIMIT);
  if (error) throw new Error(`catalogue_source_records read failed: ${error.message ?? error}`);
  const rows = ((data ?? []) as { source_key: string; payload: { staff?: { personId: number }[]; companies?: { companyId: number; task: string }[] } }[]).filter((r) => /^\d+$/.test(r.source_key));
  const result: { records: number; people: number; companies: number; queries: number; stoppedEarly?: "budget" | "rate_limited" } = { records: rows.length, people: 0, companies: 0, queries: 0 };
  if (rows.length === 0) return result;

  const people = [...new Set(rows.flatMap((r) => (r.payload.staff ?? []).map((s) => String(s.personId))))];
  const companies = [...new Set(rows.flatMap((r) => (r.payload.companies ?? []).filter((c) => PRODUCTION_TASK.test(c.task)).map((c) => String(c.companyId))))];
  const pending = async (kind: EntityCrosswalkKind, keys: string[]) => {
    const have = await readExistingRecords(ctx.supabase, "wikidata", "anime", keys.map((k) => crosswalkKey(kind, k)));
    return keys.filter((k) => !have.has(crosswalkKey(kind, k)));
  };
  const deps = { supabase: ctx.supabase, client: ctx.clients.wikidata, deadlineMs: ctx.deadlineMs };
  let complete = true;
  for (const [kind, keys] of [["person", people], ["company", companies]] as const) {
    const todo = await pending(kind, keys);
    if (todo.length === 0) continue;
    const r = await wikidataEntityCrosswalk(deps, kind, todo);
    result.queries += r.queries;
    if (kind === "person") result.people += r.completedKeys;
    else result.companies += r.completedKeys;
    if (r.stoppedEarly) {
      result.stoppedEarly = r.stoppedEarly;
      complete = false;
      break;
    }
  }
  // The cursor only moves past records whose people and companies were all asked.
  if (complete) {
    const last = rows[rows.length - 1].source_key;
    await writeCursor(ctx.supabase, key, "anime", { after_key: rows.length < ENTITY_RECORD_LIMIT ? "" : last }, { ...result }, null);
  }
  return result;
}

// ---------------------------------------------------------------------------------------------
// Handler run (cursor: import_track_state `catalogue-intake:wikidata:<medium>`, { last_id })

export const WIKIDATA_DEFAULT_LIMIT = 2000;

export async function runWikidata(ctx: RunContext): Promise<HandlerOutcome> {
  const key = cursorKey("wikidata", ctx.medium);
  const cursor = await readCursor<{ last_id?: number }>(ctx.supabase, key);
  const lastId = typeof cursor?.last_id === "number" ? cursor.last_id : 0;
  const limit = clampInt(ctx.limit, WIKIDATA_DEFAULT_LIMIT, 1, 5000);
  const rows = await readKuroRows<{ id: number; anilist_id: number }>(ctx.supabase, ctx.medium, "id, anilist_id", lastId, limit, "anilist_id");
  const cross = await wikidataCrosswalk({ supabase: ctx.supabase, client: ctx.clients.wikidata, deadlineMs: ctx.deadlineMs }, ctx.medium, rows);

  const finished = cross.completedRows === rows.length && !cross.stoppedEarly;
  let nextLast = lastId;
  if (finished) nextLast = rows.length < limit ? 0 : rows[rows.length - 1].id;
  else if (cross.completedRows > 0) nextLast = rows[cross.completedRows - 1].id;
  const results = {
    rows: rows.length,
    completed_rows: cross.completedRows,
    queries: cross.queries,
    linked: cross.linked,
    proposed: cross.proposed,
    conflicts: cross.conflicts.length,
    records_written: cross.recordsWritten,
    pass_completed: finished && rows.length < limit,
  };
  await writeCursor(ctx.supabase, key, ctx.medium, { last_id: nextLast }, results, cross.stoppedEarly ? `stopped_early:${cross.stoppedEarly}` : null);
  // Task 7b: after the title crosswalk, ask Wikidata about the people and companies ANN credits (anime only).
  let entities: Awaited<ReturnType<typeof runEntityCrosswalk>> | undefined;
  let stoppedEarly = cross.stoppedEarly;
  if (ctx.medium === "anime" && !cross.stoppedEarly && ctx.now() < ctx.deadlineMs) {
    const e = await runEntityCrosswalk(ctx);
    if (e.records > 0) entities = e;
    stoppedEarly = e.stoppedEarly;
  }
  return { results: { ...results, ...(entities ? { entities } : {}), conflict_sample: cross.conflicts.slice(0, 20) }, stoppedEarly };
}
