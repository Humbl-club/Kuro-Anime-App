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
import { applyLinks, type LinkKind, type Medium, type SourceCode } from "./store.ts";

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
  nowIso?: string;
};

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
      const credits = ((await must(deps.supabase.from(s.creditTable).select(s.entityColumn).eq(s.titleColumn, titleKuroId), s.creditTable)) ?? []) as Record<string, number>[];
      const ids = [...new Set(credits.map((c) => c[s.entityColumn]))];
      if (ids.length === 0) return [];
      return ((await must(deps.supabase.from(s.table).select("*").in("id", ids), s.table)) ?? []) as Record<string, unknown>[];
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
        const rows = ((await must(deps.supabase.from("staff").select("*").eq("anilist_id", cw.anilistStaffId), "staff")) ?? []) as Record<string, unknown>[];
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
  const deps: EntityDeps = { ...baseDeps, linkMap: baseDeps.linkMap ?? new Map(), crosswalkMap: baseDeps.crosswalkMap ?? new Map(), creditedCache: baseDeps.creditedCache ?? new Map() };
  const fields: CreditField[] = [];
  const proposed: ProposedNew[] = [];
  const review: { kind: string; source: string; sourceKey: string; name: string; reason: string }[] = [];
  const absorb = (list: Credit[], r: Resolved, role: string | null, p: ProposedNew) => {
    if ("kuroId" in r) {
      if (!list.some((c) => c.kuro_id === r.kuroId && c.role === role)) list.push({ kuro_id: r.kuroId, role });
    } else if ("proposedNew" in r) {
      if (!proposed.some((x) => x.kind === p.kind && x.source === p.source && x.sourceKey === p.sourceKey)) proposed.push(r.proposedNew);
    } else review.push({ kind: p.kind, source: p.source, sourceKey: p.sourceKey, name: p.name, reason: r.reason });
  };

  const ann = records.ann;
  const sources = new Set<string>();
  if (ann) {
    await preload(deps, "staff", "ann", ann.staff.map((x) => String(x.personId)));
    await preload(deps, "studio", "ann", ann.companies.filter((c) => PRODUCTION_TASK.test(c.task)).map((x) => String(x.companyId)));
    const staff: Credit[] = [];
    for (const p of ann.staff) absorb(staff, await resolvePerson(deps, "ann", String(p.personId), p.name, titleKuroId), p.task || null, { kind: "staff", source: "ann", sourceKey: String(p.personId), name: p.name });
    const studios: Credit[] = [];
    for (const c of ann.companies.filter((x) => PRODUCTION_TASK.test(x.task))) absorb(studios, await resolveStudio(deps, "ann", String(c.companyId), c.name, titleKuroId), c.task || null, { kind: "studio", source: "ann", sourceKey: String(c.companyId), name: c.name });
    const characters: Credit[] = [];
    const seen = new Set<string>();
    for (const c of ann.cast) {
      const n = normaliseName(c.role);
      if (!n || seen.has(n)) continue;
      seen.add(n);
      absorb(characters, await resolveCharacter(deps, titleKuroId, c.role), null, { kind: "character", source: "ann", sourceKey: n, name: c.role });
    }
    if (staff.length) fields.push({ field: "credits:staff", value: staff, source: "ann" });
    if (studios.length) fields.push({ field: "credits:studios", value: studios, source: "ann" });
    if (characters.length) fields.push({ field: "credits:characters", value: characters, source: "ann" });
    sources.add("ann");
  }
  const mu = records.mangaupdates;
  if (mu) {
    await preload(deps, "author", "mangaupdates", mu.authors.map((a) => String(a.authorId)));
    const authors: Credit[] = [];
    for (const a of mu.authors) absorb(authors, await resolveAuthor(deps, "mangaupdates", String(a.authorId), a.name, titleKuroId), a.type || null, { kind: "author", source: "mangaupdates", sourceKey: String(a.authorId), name: a.name });
    if (authors.length) fields.push({ field: "credits:authors", value: authors, source: "mangaupdates" });
    sources.add("mangaupdates");
  }
  const src = [...sources].join(",");
  if (proposed.length) fields.push({ field: "credits:proposed_entities", value: proposed, source: src });
  if (review.length) fields.push({ field: "credits:review", value: review, source: src });
  return { fields };
}

/** One query each for the accepted links and the Wikidata crosswalk records of a title's credits. */
async function preload(deps: EntityDeps, kind: EntityKind, source: SourceCode, keys: string[]): Promise<void> {
  const unique = [...new Set(keys)];
  if (unique.length === 0) return;
  const rows = ((await must(deps.supabase.from("catalogue_id_links").select("kuro_id, source_key").eq("kind", kind).eq("source", source).eq("status", "accepted").in("source_key", unique), "catalogue_id_links")) ?? []) as { kuro_id: number; source_key: string }[];
  const found = new Map(rows.map((r) => [r.source_key, r.kuro_id]));
  for (const k of unique) deps.linkMap?.set(`${kind}|${source}|${k}`, found.get(k) ?? null);
  if (source === "ann" && (kind === "staff" || kind === "studio")) {
    const cwKind = kind === "staff" ? "person" : "company";
    const recs = ((await must(deps.supabase.from("catalogue_source_records").select("source_key, payload").eq("source", "wikidata").eq("medium", "anime").in("source_key", unique.map((k) => crosswalkKey(cwKind, k))), "catalogue_source_records")) ?? []) as { source_key: string; payload: CrosswalkPayload }[];
    const byKey = new Map(recs.map((r) => [r.source_key, r.payload]));
    for (const k of unique) deps.crosswalkMap?.set(crosswalkKey(cwKind, k), byKey.get(crosswalkKey(cwKind, k)) ?? null);
  }
}
