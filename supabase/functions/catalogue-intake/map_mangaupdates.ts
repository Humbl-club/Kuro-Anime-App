// Maps one stored MangaUpdates record (mangaupdates.ts MuRecord) to Kuro column values (Task 7). Pure.
import type { RawRelation } from "../_shared/catalogue/precedence.ts";
import type { MuRecord } from "./mangaupdates.ts";

const FORMAT: Record<string, string> = { manga: "MANGA", manhwa: "MANGA", manhua: "MANGA", novel: "NOVEL", "one-shot": "ONE_SHOT" };
const COUNTRY: Record<string, string> = { manga: "JP", manhwa: "KR", manhua: "CN" };

export function muFormat(type: string | null): string | null {
  return type ? FORMAT[type.trim().toLowerCase()] ?? null : null;
}

/** MangaUpdates status text ("43 Volumes (Ongoing)") and completed flag to an AniList-style status. */
export function muStatus(statusText: string, completed: boolean): string | null {
  if (completed) return "FINISHED";
  if (/hiatus/i.test(statusText)) return "HIATUS";
  if (/cancel|discontinu/i.test(statusText)) return "CANCELLED";
  if (/ongoing/i.test(statusText)) return "RELEASING";
  if (/complete/i.test(statusText)) return "FINISHED";
  return null;
}

export function muVolumes(statusText: string): number | null {
  const m = /(\d+)\s+volumes?/i.exec(statusText);
  const n = m ? Number(m[1]) : NaN;
  return Number.isInteger(n) && n > 0 ? n : null;
}

export function isMuAdult(r: MuRecord): boolean {
  return r.genres.some((g) => /^(adult|hentai)$/i.test(g.trim()));
}

export type MuAnimeSpan = {
  startVolume: number | null;
  startChapter: number | null;
  endVolume: number | null;
  endChapter: number | null;
  nextChapter: number | null;
  rawStart: string | null;
  rawEnd: string | null;
};

function extractUnitNumber(raw: string | null | undefined, pattern: RegExp): number | null {
  if (!raw) return null;
  const match = pattern.exec(raw);
  if (!match) return null;
  const n = Number(match[1]);
  return Number.isInteger(n) && n >= 0 ? n : null;
}

/** Parses MangaUpdates strings like `"Vol 1, Chap 1"` / `"Ends at Vol 8, Chap 63"` into numeric bounds. */
export function parseMuAnimeSpan(start: string | null | undefined, end: string | null | undefined): MuAnimeSpan | null {
  const rawStart = start?.trim() || null;
  const rawEnd = end?.trim() || null;
  if (!rawStart && !rawEnd) return null;
  const startVolume = extractUnitNumber(rawStart, /\bVol(?:ume)?\.?\s*(\d+)/i);
  const startChapter = extractUnitNumber(rawStart, /\bChap(?:ter)?\.?\s*(\d+)/i);
  const endVolume = extractUnitNumber(rawEnd, /\bVol(?:ume)?\.?\s*(\d+)/i);
  const endChapter = extractUnitNumber(rawEnd, /\bChap(?:ter)?\.?\s*(\d+)/i);
  if (startVolume === null && startChapter === null && endVolume === null && endChapter === null) {
    return null;
  }
  return {
    startVolume,
    startChapter,
    endVolume,
    endChapter,
    nextChapter: endChapter !== null ? endChapter + 1 : null,
    rawStart,
    rawEnd,
  };
}

export function toSourceValues(r: MuRecord): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  const set = (k: string, v: unknown) => {
    if (v !== null && v !== undefined && v !== "") out[k] = v;
  };
  // MangaUpdates' main title is the English or romanised title; Wikidata's English label outranks it.
  set("title_english", r.title);
  if (r.associated.length) out.title_synonyms = r.associated;
  set("format", muFormat(r.type));
  set("status", muStatus(r.status, r.completed));
  set("volumes", muVolumes(r.status));
  set("start_date_year", r.year);
  set("country_of_origin", r.type ? COUNTRY[r.type.trim().toLowerCase()] : null);
  if (r.genres.length > 0) out.is_adult = isMuAdult(r);
  const span = parseMuAnimeSpan(r.animeStart, r.animeEnd);
  if (span) out.anime_adaptation_span = span;
  return out;
}

const REL: Record<string, string> = {
  prequel: "PREQUEL",
  sequel: "SEQUEL",
  "side story": "SIDE_STORY",
  "spin-off": "SPIN_OFF",
  "adapted from": "SOURCE",
  "adapted to": "ADAPTATION",
};

export function toRelations(r: MuRecord): RawRelation[] {
  return r.related.map((rel) => ({
    source: "mangaupdates" as const,
    type: REL[rel.relationType.trim().toLowerCase()] ?? `UNMAPPED:${rel.relationType}`,
    targetKey: String(rel.seriesId),
  }));
}
