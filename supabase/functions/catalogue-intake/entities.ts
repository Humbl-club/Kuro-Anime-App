// Credits: people, companies and characters (catalogue Task 7b; spec section 3 "People, companies,
// characters"). Resolves the people/companies a source credits on a title to Kuro rows:
//   1. an accepted catalogue_id_links link;
//   2. a Wikidata crosswalk (ANN person P1982 -> AniList staff P11227) to an existing staff row. Wikidata is
//      openly editable, so the link is accepted only when the staff row's name agrees with the credit's
//      name; a disagreeing crosswalk is stored `proposed` and resolution goes on;
//   3. a normalised-name match among the rows already credited on the SAME Kuro title (accepted only
//      when unique; two matches go to review);
//   4. otherwise a new row with anilist_id null. New rows are inserted only when `allowCreate` is set
//      (once the credits group is switched, Task 15). In shadow mode (the default) the entity is
//      returned as `proposedNew` and nothing is written, because until then the AniList importer is the
//      writer of these tables.
// Characters match only inside one title's existing characters; ANN carries no character ids or images.
// A credit taken from ANN keeps the ANN entry link available through the stored record's `url`.
import type { SupabaseLike } from "../_shared/catalogue/intake_persistence.ts";
import type { AnnRecord } from "./ann.ts";
import type { MuRecord } from "./mangaupdates.ts";
import { applyLinks, chunk, selectAll, WRITE_BATCH, type LinkKind, type Medium, type SourceCode } from "./store.ts";

export type EntityKind = "staff" | "studio" | "author";

export type EntityDeps = {
  supabase: SupabaseLike;
  medium: Medium;
  /** Insert new rows (credits group switched). Default false: shadow mode proposes instead. */
  allowCreate?: boolean;
  /** Preloaded by composeCredits so a title with hundreds of credits does not query per person. */
  linkMap?: Map<string, number | null>;
  crosswalkMap?: Map<string, CrosswalkPayload | null>;
  creditedCache?: Map<string, Promise<Record<string, unknown>[]>>;
  /** Staff rows by AniList id, preloaded for the Wikidata crosswalk's staff ids (one query per chunk, not per person). */
  staffByAnilist?: Map<number, Record<string, unknown>[]>;
  /** Link writes are queued here and flushed with one applyLinks per kind (flushPendingLinks), not one per credit. */
  pendingLinks?: Map<string, PendingLink>;
  /** Checked before every credit; true makes composeCredits throw CreditsBudgetError so the run can stop cleanly. */
  shouldStop?: () => boolean;
  nowIso?: string;
};

export type PendingLink = { kind: EntityKind; kuroId: number; source: SourceCode; sourceKey: string; method: "wikidata" | "name_match" | "id_match"; status: "accepted" | "proposed" };

/** Thrown by composeCredits when `shouldStop()` turns true; nothing of the interrupted title is kept. */
export class CreditsBudgetError extends Error {
  constructor() {
    super("compose time budget reached inside a title's credits");
    this.name = "CreditsBudgetError";
  }
}

export type ProposedNew = { kind: EntityKind | "character"; source: string; sourceKey: string; name: string };
export type Resolved = { kuroId: number; created: boolean } | { review: true; reason: string } | { proposedNew: ProposedNew };

export type CrosswalkPayload = { qid: string | null; anilistStaffId?: number | null; label?: string | null; conflict?: boolean };

export function crosswalkKey(kind: "person" | "company", annKey: string): string {
  return `${kind}:ann:${annKey}`;
}

/** Order-, case- and Latin-diacritic-insensitive name key ("SAWANO Hiroyuki" == "Hiroyuki Sawano"). */
export function normaliseName(raw: string): string {
  const folded = raw.normalize("NFKC").normalize("NFD").replace(/[̀-ͯ]/g, "").normalize("NFC").toLowerCase();
  return folded.split(/[^\p{L}\p{N}]+/u).filter(Boolean).sort().join(" ");
}

type Spec = {
  kind: EntityKind;
  table: string;
  nameColumns: string[];
  creditTable: string;
  titleColumn: string;
  entityColumn: string;
  newRow: (name: string) => Record<string, unknown>;
};

function spec(kind: EntityKind, medium: Medium): Spec | null {
  if (kind === "staff") {
    const m = medium === "anime" ? "anime" : "manga";
    return { kind, table: "staff", nameColumns: ["name_full", "name_romaji", "name_native"], creditTable: `${m}_staff`, titleColumn: `${m}_id`, entityColumn: "staff_id", newRow: (name) => ({ anilist_id: null, name_full: name }) };
  }
  if (kind === "studio") {
    if (medium !== "anime") return null;
    return { kind, table: "studios", nameColumns: ["name", "name_romaji", "name_native"], creditTable: "anime_studios", titleColumn: "anime_id", entityColumn: "studio_id", newRow: (name) => ({ anilist_id: null, name }) };
  }
  if (medium !== "manga") return null;
  return { kind, table: "authors", nameColumns: ["name_full", "name_romaji", "name_native"], creditTable: "manga_authors", titleColumn: "manga_id", entityColumn: "author_id", newRow: (name) => ({ anilist_id: null, name_full: name }) };
}

function names(row: Record<string, unknown>, columns: string[]): string[] {
  const out: string[] = [];
  for (const c of columns) {
    const v = row[c];
    if (typeof v === "string" && v.trim()) out.push(v);
    else if (Array.isArray(v)) for (const x of v) if (typeof x === "string" && x.trim()) out.push(x);
  }
  return out;
}

function rowMatches(row: Record<string, unknown>, columns: string[], wanted: Set<string>): boolean {
  return names(row, columns).some((n) => wanted.has(normaliseName(n)));
}

async function must<T>(p: PromiseLike<{ data: T; error: { message?: string } | null }>, what: string): Promise<T> {
  const { data, error } = await p;
  if (error) throw new Error(`${what} failed: ${error.message ?? error}`);
  return data;
}

/** Rows already credited on one Kuro title (one query for credit rows, one for the entity rows), cached per title. */
async function creditedRows(deps: EntityDeps, s: { table: string; creditTable: string; titleColumn: string; entityColumn: string }, titleKuroId: number): Promise<Record<string, unknown>[]> {
  const cache = (deps.creditedCache ??= new Map());
  const key = `${s.creditTable}:${titleKuroId}`;
  let hit = cache.get(key);
  if (!hit) {
    hit = (async () => {
      const credits = await selectAll<Record<string, number>>(() => deps.supabase.from(s.creditTable).select(s.entityColumn).eq(s.titleColumn, titleKuroId), [s.entityColumn], s.creditTable);
      const ids = [...new Set(credits.map((c) => c[s.entityColumn]))];
      const out: Record<string, unknown>[] = [];
      for (const part of chunk(ids, WRITE_BATCH)) out.push(...(await selectAll<Record<string, unknown>>(() => deps.supabase.from(s.table).select("*").in("id", part), ["id"], s.table)));
      return out;
    })();
    cache.set(key, hit);
  }
  return hit;
}

async function acceptedLink(deps: EntityDeps, kind: string, source: string, sourceKey: string): Promise<number | null> {
  const k = `${kind}|${source}|${sourceKey}`;
  if (deps.linkMap?.has(k)) return deps.linkMap.get(k) ?? null;
  const row = await must(
    deps.supabase.from("catalogue_id_links").select("kuro_id").eq("kind", kind).eq("source", source).eq("source_key", sourceKey).eq("status", "accepted").maybeSingle(),
    "catalogue_id_links",
  );
  return (row as { kuro_id: number } | null)?.kuro_id ?? null;
}

async function crosswalkFor(deps: EntityDeps, kind: "person" | "company", annKey: string): Promise<CrosswalkPayload | null> {
  const k = crosswalkKey(kind, annKey);
  if (deps.crosswalkMap?.has(k)) return deps.crosswalkMap.get(k) ?? null;
  const row = await must(
    deps.supabase.from("catalogue_source_records").select("payload").eq("source", "wikidata").eq("medium", "anime").eq("source_key", k).maybeSingle(),
    "catalogue_source_records",
  );
  return ((row as { payload: CrosswalkPayload } | null)?.payload) ?? null;
}

async function link(deps: EntityDeps, kind: EntityKind, kuroId: number, source: SourceCode, sourceKey: string, method: "wikidata" | "name_match" | "id_match", status: "accepted" | "proposed") {
  if (deps.pendingLinks) {
    // Queued: composeCredits flushes once per title. A queued candidate is NOT cached as accepted: only what
    // applyLinks persisted is (flushPendingLinks), so link-trust conflicts cannot be bypassed inside a chunk.
    deps.pendingLinks.set(`${kind}|${source}|${sourceKey}|${kuroId}|${status}`, { kind, kuroId, source, sourceKey, method, status });
    return;
  }
  const res = await applyLinks(deps.supabase, kind, [{ kuroId, source, sourceKey, method, confidence: method === "name_match" ? 0.9 : 1, status }], deps.nowIso);
  if (status === "accepted" && res.accepted > 0) deps.linkMap?.set(`${kind}|${source}|${sourceKey}`, kuroId);
}

async function resolveEntity(deps: EntityDeps, kind: EntityKind, source: SourceCode, sourceKey: string, name: string, titleKuroId: number): Promise<Resolved> {
  const s = spec(kind, deps.medium);
  if (!s) return { review: true, reason: `${kind}_not_credited_on_${deps.medium}` };

  const existing = await acceptedLink(deps, kind, source, sourceKey);
  if (existing !== null) return { kuroId: existing, created: false };

  const wanted = new Set<string>([normaliseName(name)]);
  // Wikidata crosswalk (ANN only). A person's AniList staff id; a company's English label (no AniList studio property exists).
  if (source === "ann" && (kind === "staff" || kind === "studio")) {
    const cw = await crosswalkFor(deps, kind === "staff" ? "person" : "company", sourceKey);
    if (cw && !cw.conflict) {
      if (kind === "studio" && cw.label) wanted.add(normaliseName(cw.label));
      if (kind === "staff" && typeof cw.anilistStaffId === "number") {
        const rows = deps.staffByAnilist?.has(cw.anilistStaffId)
          ? deps.staffByAnilist.get(cw.anilistStaffId)!
          : await selectAll<Record<string, unknown>>(() => deps.supabase.from("staff").select("*").eq("anilist_id", cw.anilistStaffId), ["id"], "staff");
        if (rows.length === 1) {
          const target = rows[0];
          const agrees = rowMatches(target, s.nameColumns, wanted);
          await link(deps, kind, Number(target.id), source, sourceKey, "wikidata", agrees ? "accepted" : "proposed");
          if (agrees) return { kuroId: Number(target.id), created: false };
        }
      }
    }
  }

  const credited = await creditedRows(deps, s, titleKuroId);
  const matches = credited.filter((r) => rowMatches(r, s.nameColumns, wanted));
  if (matches.length === 1) {
    const id = Number(matches[0].id);
    await link(deps, kind, id, source, sourceKey, "name_match", "accepted");
    return { kuroId: id, created: false };
  }
  if (matches.length > 1) return { review: true, reason: "ambiguous_name_on_title" };

  if (!deps.allowCreate) return { proposedNew: { kind, source, sourceKey, name } };
  const created = await must(deps.supabase.from(s.table).insert(s.newRow(name)).select("id").single(), s.table);
  const id = Number((created as { id: number }).id);
  await link(deps, kind, id, source, sourceKey, "id_match", "accepted");
  return { kuroId: id, created: true };
}

export function resolvePerson(deps: EntityDeps, source: SourceCode, sourceKey: string, name: string, titleKuroId: number): Promise<Resolved> {
  return resolveEntity(deps, "staff", source, sourceKey, name, titleKuroId);
}

export function resolveStudio(deps: EntityDeps, source: SourceCode, sourceKey: string, name: string, titleKuroId: number): Promise<Resolved> {
  return resolveEntity(deps, "studio", source, sourceKey, name, titleKuroId);
}

export function resolveAuthor(deps: EntityDeps, source: SourceCode, sourceKey: string, name: string, titleKuroId: number): Promise<Resolved> {
  return resolveEntity(deps, "author", source, sourceKey, name, titleKuroId);
}

/** Matches only among the characters already on this title, by normalised name (name_full, native, alternatives). */
export async function resolveCharacter(deps: EntityDeps, titleKuroId: number, name: string): Promise<Resolved> {
  const m = deps.medium;
  const credited = await creditedRows(deps, { table: "characters", creditTable: `${m}_characters`, titleColumn: `${m}_id`, entityColumn: "character_id" }, titleKuroId);
  const wanted = new Set([normaliseName(name)]);
  const matches = credited.filter((r) => rowMatches(r, ["name_full", "name_native", "name_alternative"], wanted));
  if (matches.length === 1) return { kuroId: Number(matches[0].id), created: false };
  if (matches.length > 1) return { review: true, reason: "ambiguous_name_on_title" };
  if (!deps.allowCreate) return { proposedNew: { kind: "character", source: "ann", sourceKey: normaliseName(name), name } };
  const created = await must(deps.supabase.from("characters").insert({ anilist_id: null, name_full: name }).select("id").single(), "characters");
  return { kuroId: Number((created as { id: number }).id), created: true };
}

// ---------------------------------------------------------------------------------------------
// Compose: shadow credit fields for one title

export type CreditField = { field: string; value: unknown; source: string };
type Credit = { kuro_id: number; role: string | null };

const PRODUCTION_TASK = /animation|production/i;

/**
 * Shadow fields `credits:staff|studios|characters` (anime, from ANN) and `credits:authors` (manga,
 * from MangaUpdates) as `{kuro_id, role}` lists, plus `credits:proposed_entities` (people, companies and
 * characters that would be created) and `credits:review` (ambiguous names). Nothing is inserted unless
 * `deps.allowCreate`.
 */
export async function composeCredits(
  baseDeps: EntityDeps,
  titleKuroId: number,
  records: { ann?: AnnRecord; mangaupdates?: MuRecord },
): Promise<{ fields: CreditField[] }> {
  const deps: EntityDeps = {
    ...baseDeps,
    linkMap: baseDeps.linkMap ?? new Map(),
    crosswalkMap: baseDeps.crosswalkMap ?? new Map(),
    creditedCache: baseDeps.creditedCache ?? new Map(),
    staffByAnilist: baseDeps.staffByAnilist ?? new Map(),
    pendingLinks: baseDeps.pendingLinks ?? new Map(),
  };
  const fields: CreditField[] = [];
  const proposed: ProposedNew[] = [];
  const review: { kind: string; source: string; sourceKey: string; name: string; reason: string }[] = [];
  // Every resolved credit, so it can be checked against what applyLinks actually persisted.
  const tracked: { list: Credit[]; kuroId: number; role: string | null; p: ProposedNew }[] = [];
  const absorb = (list: Credit[], r: Resolved, role: string | null, p: ProposedNew) => {
    if ("kuroId" in r) {
      tracked.push({ list, kuroId: r.kuroId, role, p });
      if (!list.some((c) => c.kuro_id === r.kuroId && c.role === role)) list.push({ kuro_id: r.kuroId, role });
    } else if ("proposedNew" in r) {
      if (!proposed.some((x) => x.kind === p.kind && x.source === p.source && x.sourceKey === p.sourceKey)) proposed.push(r.proposedNew);
    } else review.push({ kind: p.kind, source: p.source, sourceKey: p.sourceKey, name: p.name, reason: r.reason });
  };
  // The deadline is checked before every credit, so a title with hundreds of credits cannot overrun it.
  const checkBudget = () => {
    if (deps.shouldStop?.()) throw new CreditsBudgetError();
  };

  try {
    const ann = records.ann;
    const sources = new Set<string>();
    const staff: Credit[] = [];
    const studios: Credit[] = [];
    const characters: Credit[] = [];
    const authors: Credit[] = [];
    if (ann) {
      await preloadCreditMaps(deps, { staff: ann.staff.map((x) => String(x.personId)), studio: ann.companies.filter((c) => PRODUCTION_TASK.test(c.task)).map((x) => String(x.companyId)), author: [] });
      for (const p of ann.staff) {
        checkBudget();
        absorb(staff, await resolvePerson(deps, "ann", String(p.personId), p.name, titleKuroId), p.task || null, { kind: "staff", source: "ann", sourceKey: String(p.personId), name: p.name });
      }
      for (const c of ann.companies.filter((x) => PRODUCTION_TASK.test(x.task))) {
        checkBudget();
        absorb(studios, await resolveStudio(deps, "ann", String(c.companyId), c.name, titleKuroId), c.task || null, { kind: "studio", source: "ann", sourceKey: String(c.companyId), name: c.name });
      }
      const seen = new Set<string>();
      for (const c of ann.cast) {
        const n = normaliseName(c.role);
        if (!n || seen.has(n)) continue;
        seen.add(n);
        checkBudget();
        absorb(characters, await resolveCharacter(deps, titleKuroId, c.role), null, { kind: "character", source: "ann", sourceKey: n, name: c.role });
      }
      sources.add("ann");
    }
    const mu = records.mangaupdates;
    if (mu) {
      await preloadCreditMaps(deps, { staff: [], studio: [], author: mu.authors.map((a) => String(a.authorId)) });
      for (const a of mu.authors) {
        checkBudget();
        absorb(authors, await resolveAuthor(deps, "mangaupdates", String(a.authorId), a.name, titleKuroId), a.type || null, { kind: "author", source: "mangaupdates", sourceKey: String(a.authorId), name: a.name });
      }
      sources.add("mangaupdates");
    }
    // Persist the queued links now (applyLinks runs its conflict and trust checks), then keep only the credits whose
    // link is really accepted for the person they resolved to; the rest go to review.
    const persisted = await flushPendingLinks(deps);
    for (const t of tracked) {
      const key = `${t.p.kind}|${t.p.source}|${t.p.sourceKey}`;
      const accepted = persisted.get(key);
      if (accepted === undefined || accepted === t.kuroId) continue;
      const at = t.list.findIndex((c) => c.kuro_id === t.kuroId && c.role === t.role);
      if (at >= 0) t.list.splice(at, 1);
      if (!review.some((r) => r.kind === t.p.kind && r.sourceKey === t.p.sourceKey && r.name === t.p.name)) review.push({ kind: t.p.kind, source: t.p.source, sourceKey: t.p.sourceKey, name: t.p.name, reason: "link_not_accepted" });
    }
    if (staff.length) fields.push({ field: "credits:staff", value: staff, source: "ann" });
    if (studios.length) fields.push({ field: "credits:studios", value: studios, source: "ann" });
    if (characters.length) fields.push({ field: "credits:characters", value: characters, source: "ann" });
    if (authors.length) fields.push({ field: "credits:authors", value: authors, source: "mangaupdates" });
    const src = [...sources].join(",");
    if (proposed.length) fields.push({ field: "credits:proposed_entities", value: proposed, source: src });
    if (review.length) fields.push({ field: "credits:review", value: review, source: src });
  } finally {
    // Links found so far are real whether or not the title finished.
    await flushPendingLinks(deps);
  }
  return { fields };
}

/**
 * Applies the queued credit links, one applyLinks call (itself batched) per kind, then reads back what is actually
 * accepted for the queued keys and caches exactly that in `linkMap`. Returns `kind|source|key` -> accepted Kuro id
 * (or null) for every key a queued accepted candidate named; queued candidates are never cached unchecked.
 */
export async function flushPendingLinks(deps: EntityDeps): Promise<Map<string, number | null>> {
  const verified = new Map<string, number | null>();
  const pending = deps.pendingLinks;
  if (!pending || pending.size === 0) return verified;
  const byKind = new Map<EntityKind, PendingLink[]>();
  for (const l of pending.values()) byKind.set(l.kind, [...(byKind.get(l.kind) ?? []), l]);
  pending.clear();
  for (const [kind, list] of byKind) {
    await applyLinks(
      deps.supabase,
      kind,
      list.map((l) => ({ kuroId: l.kuroId, source: l.source, sourceKey: l.sourceKey, method: l.method, confidence: l.method === "name_match" ? 0.9 : 1, status: l.status })),
      deps.nowIso,
    );
    const wanted = new Map<string, Set<string>>(); // source -> keys queued as accepted
    for (const l of list) if (l.status === "accepted") (wanted.get(l.source) ?? wanted.set(l.source, new Set()).get(l.source)!).add(l.sourceKey);
    for (const [source, keySet] of wanted) {
      for (const part of chunk([...keySet], WRITE_BATCH)) {
        const rows = await selectAll<{ kuro_id: number; source_key: string }>(
          () => deps.supabase.from("catalogue_id_links").select("kuro_id, source_key").eq("kind", kind).eq("source", source).eq("status", "accepted").in("source_key", part),
          ["id"],
          "catalogue_id_links",
        );
        const found = new Map(rows.map((r) => [r.source_key, r.kuro_id]));
        for (const k of part) {
          verified.set(`${kind}|${source}|${k}`, found.get(k) ?? null);
          deps.linkMap?.set(`${kind}|${source}|${k}`, found.get(k) ?? null);
        }
      }
    }
  }
  return verified;
}

/**
 * Loads, for many credits at once, the accepted links, the Wikidata crosswalk records and the staff rows
 * the crosswalk names. Keys already loaded are skipped. compose calls it once per chunk of titles, so a
 * credit then resolves from memory instead of querying per person.
 */
export async function preloadCreditMaps(deps: EntityDeps, keys: { staff: string[]; studio: string[]; author: string[] }): Promise<void> {
  await preload(deps, "staff", "ann", keys.staff);
  await preload(deps, "studio", "ann", keys.studio);
  await preload(deps, "author", "mangaupdates", keys.author);
  if (!deps.staffByAnilist) return;
  const wanted = new Set<number>();
  for (const k of keys.staff) {
    const cw = deps.crosswalkMap?.get(crosswalkKey("person", k));
    if (cw && !cw.conflict && typeof cw.anilistStaffId === "number" && !deps.staffByAnilist.has(cw.anilistStaffId)) wanted.add(cw.anilistStaffId);
  }
  for (const part of chunk([...wanted], WRITE_BATCH)) {
    const rows = await selectAll<Record<string, unknown>>(() => deps.supabase.from("staff").select("*").in("anilist_id", part), ["id"], "staff");
    for (const id of part) deps.staffByAnilist.set(id, []);
    for (const r of rows) deps.staffByAnilist.get(Number(r.anilist_id))?.push(r);
  }
}

/** One query each (paged) for the accepted links and the Wikidata crosswalk records of the credits. */
async function preload(deps: EntityDeps, kind: EntityKind, source: SourceCode, keys: string[]): Promise<void> {
  const unique = [...new Set(keys)].filter((k) => !deps.linkMap?.has(`${kind}|${source}|${k}`));
  if (unique.length === 0) return;
  for (const part of chunk(unique, WRITE_BATCH)) {
    const rows = await selectAll<{ kuro_id: number; source_key: string }>(
      () => deps.supabase.from("catalogue_id_links").select("kuro_id, source_key").eq("kind", kind).eq("source", source).eq("status", "accepted").in("source_key", part),
      ["id"],
      "catalogue_id_links",
    );
    const found = new Map(rows.map((r) => [r.source_key, r.kuro_id]));
    for (const k of part) deps.linkMap?.set(`${kind}|${source}|${k}`, found.get(k) ?? null);
    if (source === "ann" && (kind === "staff" || kind === "studio")) {
      const cwKind = kind === "staff" ? "person" : "company";
      const todo = part.filter((k) => !deps.crosswalkMap?.has(crosswalkKey(cwKind, k)));
      const recs = await selectAll<{ source_key: string; payload: CrosswalkPayload }>(
        () => deps.supabase.from("catalogue_source_records").select("source_key, payload").eq("source", "wikidata").eq("medium", "anime").in("source_key", todo.map((k) => crosswalkKey(cwKind, k))),
        ["source_key"],
        "catalogue_source_records",
      );
      const byKey = new Map(recs.map((r) => [r.source_key, r.payload]));
      for (const k of todo) deps.crosswalkMap?.set(crosswalkKey(cwKind, k), byKey.get(crosswalkKey(cwKind, k)) ?? null);
    }
  }
}
