// Maps one stored Wikidata record (wikidata.ts persistBatch payload) to Kuro column values (Task 7).
// Pure. Returns only columns the record actually supports; absent means "no value".
import type { RawRelation } from "../_shared/catalogue/precedence.ts";

export type WikidataPayload = { qid: string; medium: "anime" | "manga"; anilist_ids?: string[]; props: Record<string, string[]> };

/**
 * Wikidata genre items that make a title adult. Looked up 2026-11-18 with a read-only WDQS label
 * query (see fixtures/README.md): `SELECT ?item ?l WHERE { VALUES ?l { "hentai"@en "ecchi"@en
 * "yaoi"@en "adult animation"@en ... } ?item rdfs:label ?l }` returned Q172067 hentai ("Japanese
 * pornographic animation, comics, and video games"), Q219559 ecchi ("playful sexual actions"),
 * Q242488 yaoi, Q3249257 adult animation. Only hentai is adult by itself: AniList's isAdult is not set
 * by ecchi or yaoi, and treating them as adult would flip hundreds of titles. See the report's
 * open question on ecchi.
 */
export const WIKIDATA_ADULT_GENRES: readonly string[] = ["Q172067"];

type Ymd = { year: number; month: number | null; day: number | null };

/** "2013-04-07T00:00:00Z" to parts. Wikidata's precision is not in the record, so a 01-01 date is read as year-only. */
export function parseWikidataDate(raw: string): Ymd | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(raw);
  if (!m) return null;
  const year = Number(m[1]);
  if (year < 1800) return null;
  const month = Number(m[2]);
  const day = Number(m[3]);
  if (month === 1 && day === 1) return { year, month: null, day: null };
  return { year, month, day };
}

function earliest(values: string[] | undefined): Ymd | null {
  const parsed = (values ?? []).map(parseWikidataDate).filter((d): d is Ymd => d !== null);
  parsed.sort((a, b) => a.year - b.year || (a.month ?? 0) - (b.month ?? 0) || (a.day ?? 0) - (b.day ?? 0));
  return parsed[0] ?? null;
}

export function toSourceValues(record: WikidataPayload): Record<string, unknown> {
  const p = record.props ?? {};
  const out: Record<string, unknown> = {};
  const set = (k: string, v: unknown) => {
    if (v !== null && v !== undefined && v !== "") out[k] = v;
  };
  set("title_english", p["label:en"]?.[0]);
  set("title_native", p["label:ja"]?.[0]);
  const synonyms = [...new Set([...(p["alias:en"] ?? []), ...(p["alias:ja"] ?? [])])];
  if (synonyms.length) out.title_synonyms = synonyms;
  if (record.medium === "anime") {
    const n = Number(p["P1113"]?.[0]);
    if (Number.isInteger(n) && n > 0) out.episodes = n;
  }
  const start = earliest(p["P580"]?.length ? p["P580"] : p["P577"]);
  if (start) {
    set("start_date_year", start.year);
    set("start_date_month", start.month);
    set("start_date_day", start.day);
  }
  const end = earliest(p["P582"]);
  if (end) {
    set("end_date_year", end.year);
    set("end_date_month", end.month);
    set("end_date_day", end.day);
  }
  const genres = p["P136"];
  if (genres && genres.length > 0) out.is_adult = genres.some((g) => WIKIDATA_ADULT_GENRES.includes(g));
  return out;
}

const RELATION_PROPERTY: Record<string, string> = { P155: "PREQUEL", P156: "SEQUEL", P144: "SOURCE", P4969: "DERIVATIVE" };

/** P155 follows = the target came first (PREQUEL), P156 followed by (SEQUEL), P144 based on (SOURCE), P4969 derivative work. */
export function toRelations(record: WikidataPayload): RawRelation[] {
  const out: RawRelation[] = [];
  for (const [prop, type] of Object.entries(RELATION_PROPERTY)) {
    for (const q of record.props?.[prop] ?? []) if (/^Q\d+$/.test(q)) out.push({ source: "wikidata", type, targetKey: q });
  }
  return out;
}
