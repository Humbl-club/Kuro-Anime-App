// Pure precedence policy for the catalogue composer (docs/superpowers/plans/2026-11-09-catalogue-sources.md
// Task 7; spec section 3 "Precedence policy"). No I/O: given the values each source offers for a
// column, it decides which one wins, and it holds the adult-safety and relation-mapping rules.
//
// Column names are the published columns of FIELD_GROUP_COLUMNS (field_groups.ts).

export type Source = "wikidata" | "ann" | "mangaupdates";
export type Medium = "anime" | "manga";

export type SourceValue = { source: Source; value: unknown };

const DATES = ["start_date_year", "start_date_month", "start_date_day", "end_date_year", "end_date_month", "end_date_day"] as const;
const START_DATES = ["start_date_year", "start_date_month", "start_date_day"] as const;

function entries(columns: readonly string[], order: readonly Source[]): [string, readonly Source[]][] {
  return columns.map((c) => [c, order]);
}

/**
 * Ordered sources per column; a source that is not listed is never used for that column.
 * Anime: titles from Wikidata labels then ANN (romaji the other way round); format, episode count
 * and duration from ANN then Wikidata; dates from Wikidata (full dates) then ANN (vintage).
 * Manga: every facts column from MangaUpdates then Wikidata; native title only exists on Wikidata.
 * The start and end date triples are chosen as a unit by the composer (one source for all parts).
 */
export const PRECEDENCE: Record<Medium, Record<string, readonly Source[]>> = {
  anime: Object.fromEntries([
    ["title_english", ["wikidata", "ann"]],
    ["title_native", ["wikidata", "ann"]],
    ["title_romaji", ["ann", "wikidata"]],
    ["title_synonyms", ["wikidata", "ann"]],
    ["format", ["ann", "wikidata"]],
    ["episodes", ["ann", "wikidata"]],
    ["duration", ["ann", "wikidata"]],
    ...entries(DATES, ["wikidata", "ann"]),
    ["is_adult", ["ann", "wikidata"]],
  ]),
  manga: Object.fromEntries([
    ["title_english", ["wikidata", "mangaupdates"]],
    ["title_native", ["wikidata"]],
    ["title_synonyms", ["mangaupdates", "wikidata"]],
    ...entries(["format", "status", "chapters", "volumes", "country_of_origin", ...DATES], ["mangaupdates", "wikidata"]),
    ["is_adult", ["mangaupdates", "wikidata"]],
  ]),
};

export const DATE_TRIPLES: readonly (readonly string[])[] = [
  START_DATES,
  ["end_date_year", "end_date_month", "end_date_day"],
];

function hasValue(v: unknown): boolean {
  if (v === null || v === undefined) return false;
  if (typeof v === "string") return v.trim() !== "";
  if (Array.isArray(v)) return v.length > 0;
  return true;
}

/** First source in the column's order that offers a real value (null, undefined, blank and [] are skipped). */
export function pick(column: string, medium: Medium, values: SourceValue[]): SourceValue | null {
  const order = PRECEDENCE[medium][column];
  if (!order) return null;
  for (const source of order) {
    const hit = values.find((v) => v.source === source && hasValue(v.value));
    if (hit) return hit;
  }
  return null;
}

/**
 * Adult flag (spec section 3, safety). `sourcesSayAdult` holds one boolean per source that carries
 * adult data for the title (true = adult). Any true wins. A title that is adult today never
 * becomes non-adult here: it stays adult and `review` is set for the owner. `newlyAdult` marks
 * titles that become adult (gate "every newly adult title listed").
 */
export function composeAdult(today: boolean | null, sourcesSayAdult: boolean[]): { value: boolean; review: boolean; newlyAdult: boolean } {
  const anyAdult = sourcesSayAdult.some((s) => s === true);
  if (anyAdult) return { value: true, review: false, newlyAdult: today !== true };
  if (today === true) return { value: true, review: true, newlyAdult: false };
  return { value: false, review: false, newlyAdult: false };
}

// ---------------------------------------------------------------------------------------------
// Relations

export const KURO_RELATION_TYPES = ["SOURCE", "ADAPTATION", "PREQUEL", "SEQUEL", "SIDE_STORY", "SPIN_OFF"] as const;
export type RelationType = (typeof KURO_RELATION_TYPES)[number];

/** A relation as one source states it: a Kuro type, or DERIVATIVE (resolved against the target's medium), or anything else (dropped). */
export type RawRelation = { source: Source; type: string; targetKey: string };

export type ComposedRelation = {
  type: RelationType;
  kind: Medium;
  target_id: number;
  /** Sources that state this exact relation, sorted. */
  sources: Source[];
  /** accepted: no source states a different type for the same target; proposed: sources disagree. */
  status: "accepted" | "proposed";
};

/**
 * Maps raw relations to Kuro's set and drops (a) any type outside it and (b) any target that has no
 * accepted link (`resolve` returns null). Same target + same type from several sources merges.
 * Different types for one target keep every variant as `proposed` for review.
 */
export function mapRelations(
  raw: RawRelation[],
  resolve: (source: Source, targetKey: string) => { kind: Medium; id: number } | null,
  ownMedium?: Medium,
): { relations: ComposedRelation[]; dropped: number } {
  let dropped = 0;
  const byTarget = new Map<string, Map<RelationType, Set<Source>>>();
  const targets = new Map<string, { kind: Medium; id: number }>();
  for (const rel of raw) {
    const target = resolve(rel.source, rel.targetKey);
    // DERIVATIVE (Wikidata P4969 "derivative work") is an ADAPTATION only across media; between two
    // titles of one medium it does not say sequel/spin-off, so it is dropped rather than guessed.
    const type = rel.type === "DERIVATIVE" ? (target && ownMedium && target.kind !== ownMedium ? "ADAPTATION" : "") : rel.type;
    const r = { ...rel, type };
    if (!(KURO_RELATION_TYPES as readonly string[]).includes(r.type) || !target) {
      dropped++;
      continue;
    }
    const key = `${target.kind}:${target.id}`;
    targets.set(key, target);
    const types = byTarget.get(key) ?? new Map<RelationType, Set<Source>>();
    byTarget.set(key, types);
    const sources = types.get(r.type as RelationType) ?? new Set<Source>();
    sources.add(r.source);
    types.set(r.type as RelationType, sources);
  }
  const relations: ComposedRelation[] = [];
  for (const [key, types] of byTarget) {
    const target = targets.get(key)!;
    for (const [type, sources] of types) {
      relations.push({ type, kind: target.kind, target_id: target.id, sources: [...sources].sort(), status: types.size > 1 ? "proposed" : "accepted" });
    }
  }
  relations.sort((a, b) => a.target_id - b.target_id || a.type.localeCompare(b.type));
  return { relations, dropped };
}
