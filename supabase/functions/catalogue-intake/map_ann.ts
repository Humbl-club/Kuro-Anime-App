// Maps one stored ANN record (ann.ts AnnRecord) to Kuro column values (Task 7). Pure.
// Credits taken from ANN need the entry link (docs/catalogue-sources-2026-11/sources/ann.md);
// the record carries `url`, which Task 16 shows. Nothing here drops it.
import type { RawRelation } from "../_shared/catalogue/precedence.ts";
import type { AnnRecord } from "./ann.ts";

const FORMAT: Record<string, string> = { tv: "TV", movie: "MOVIE", oav: "OVA", ona: "ONA", special: "SPECIAL", "tv special": "SPECIAL" };

/** ANN type to AniList-style format. Unknown ANN types (omnibus, web, ...) give no format. */
export function annFormat(type: string | null): string | null {
  return type ? FORMAT[type.trim().toLowerCase()] ?? null : null;
}

/** "24 minutes", "1 hour", "1 hour 30 minutes" to minutes. */
export function annDuration(text: string | null): number | null {
  if (!text) return null;
  const h = /(\d+)\s*hours?/i.exec(text);
  const m = /(\d+)\s*min/i.exec(text);
  const total = (h ? Number(h[1]) * 60 : 0) + (m ? Number(m[1]) : 0);
  return total > 0 ? total : null;
}

type Ymd = { year: number; month: number | null; day: number | null };

/** ANN vintage ("2017-01-18 to 2017-04-05", "2004") to start and end dates. */
export function annDates(vintage: string | null): { start: Ymd | null; end: Ymd | null } {
  if (!vintage) return { start: null, end: null };
  const found: Ymd[] = [];
  for (const m of vintage.matchAll(/(\d{4})(?:-(\d{2}))?(?:-(\d{2}))?/g)) {
    const year = Number(m[1]);
    if (year < 1800) continue;
    found.push({ year, month: m[2] ? Number(m[2]) : null, day: m[3] ? Number(m[3]) : null });
  }
  const hasTo = /\bto\b/i.test(vintage);
  return { start: found[0] ?? null, end: hasTo ? found[1] ?? null : null };
}

const KANA_OR_CJK = /[぀-ヿ㐀-鿿]/;

export function isAnnAdult(r: AnnRecord): boolean {
  const lower = (xs: string[]) => xs.map((x) => x.trim().toLowerCase());
  if (lower(r.genres).includes("erotica") || lower(r.themes).includes("hentai")) return true;
  return !!r.objectionable && /\bAO\b|18\+/i.test(r.objectionable);
}

export function toSourceValues(r: AnnRecord): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  const set = (k: string, v: unknown) => {
    if (v !== null && v !== undefined && v !== "") out[k] = v;
  };
  const alt = r.titles.alternatives;
  const english = alt.find((a) => a.lang === "EN")?.title;
  const native = alt.find((a) => a.lang === "JA" && KANA_OR_CJK.test(a.title))?.title;
  set("title_english", english);
  set("title_native", native);
  set("title_romaji", r.titles.main);
  const synonyms = [...new Set(alt.map((a) => a.title).filter((t) => t && t !== english && t !== native && t !== r.titles.main))];
  if (synonyms.length) out.title_synonyms = synonyms;
  set("format", annFormat(r.type));
  set("episodes", r.episodes);
  set("duration", annDuration(r.runningTime));
  const { start, end } = annDates(r.vintage);
  if (start) {
    set("start_date_year", start.year);
    set("start_date_month", start.month);
    set("start_date_day", start.day);
  }
  if (end) {
    set("end_date_year", end.year);
    set("end_date_month", end.month);
    set("end_date_day", end.day);
  }
  if (r.genres.length > 0 || r.themes.length > 0 || r.objectionable) out.is_adult = isAnnAdult(r);
  return out;
}

/** ANN's `rel` text is read as "this title <rel> the target". */
const REL: Record<string, string> = {
  "sequel of": "PREQUEL",
  "prequel of": "SEQUEL",
  "adapted from": "SOURCE",
  "adapted into": "ADAPTATION",
  "side story of": "SIDE_STORY",
  "spinoff of": "SPIN_OFF",
  "spin-off of": "SPIN_OFF",
};

export function toRelations(r: AnnRecord): RawRelation[] {
  const out: RawRelation[] = [];
  for (const rel of r.related) {
    const type = REL[rel.rel.trim().toLowerCase()];
    out.push({ source: "ann", type: type ?? `UNMAPPED:${rel.rel}`, targetKey: String(rel.id) });
  }
  return out;
}
