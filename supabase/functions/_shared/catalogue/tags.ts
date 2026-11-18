// Kuro tag assignment (catalogue Task 11). Pure. Maps source labels (ANN genres/themes,
// MangaUpdates genres/categories, Wikidata genre ids) to Kuro tag ids through the reviewed map.
//
// AniDB is not a source here: its terms could not be read (docs/catalogue-sources-2026-11/sources/anidb.md),
// so the plan's exclusion applies. Nothing is published from the map until the owner has reviewed it:
// parseTagMapCsv keeps only rows marked reviewed=yes that carry a tag id.

export type TagSource = "ann" | "mangaupdates" | "wikidata";
export type TagMapRow = { source: TagSource; source_label: string; tag_id: number; weight: number };
export type SourceLabel = { source: TagSource; label: string; votes?: number };

export const MAX_TAGS_PER_TITLE = 20;
/** A MangaUpdates category counts only with at least this many positive votes. */
export const MIN_CATEGORY_VOTES = 2;

const TAG_SOURCES: readonly string[] = ["ann", "mangaupdates", "wikidata"];
const norm = (s: string) => s.trim().toLowerCase();

/**
 * Tags for one title: each distinct mapped label adds its weight to its tag; the rank is the tag's
 * share of the strongest tag, 0-100 (rounded). Strongest first, ties by tag id, at most 20.
 * `votes` is set only for categories (a genre has none and always counts).
 */
export function assignTags(labels: SourceLabel[], map: readonly TagMapRow[]): { tag_id: number; rank: number }[] {
  const byLabel = new Map<string, TagMapRow>();
  for (const m of map) byLabel.set(`${m.source}|${norm(m.source_label)}`, m);
  const seen = new Set<string>();
  const score = new Map<number, number>();
  for (const l of labels) {
    if (l.votes !== undefined && l.votes < MIN_CATEGORY_VOTES) continue;
    const key = `${l.source}|${norm(l.label)}`;
    if (seen.has(key)) continue;
    seen.add(key);
    const m = byLabel.get(key);
    if (!m) continue;
    score.set(m.tag_id, (score.get(m.tag_id) ?? 0) + m.weight);
  }
  const max = Math.max(0, ...score.values());
  if (max <= 0) return [];
  return [...score.entries()]
    .map(([tag_id, s]) => ({ tag_id, rank: Math.round((100 * s) / max) }))
    .sort((a, b) => b.rank - a.rank || a.tag_id - b.tag_id)
    .slice(0, MAX_TAGS_PER_TITLE);
}

function csvRecords(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = "";
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') {
        cell += '"';
        i++;
      } else if (c === '"') quoted = false;
      else cell += c;
    } else if (c === '"') quoted = true;
    else if (c === ",") {
      row.push(cell);
      cell = "";
    } else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(cell);
      cell = "";
      if (row.some((x) => x !== "")) rows.push(row);
      row = [];
    } else cell += c;
  }
  row.push(cell);
  if (row.some((x) => x !== "")) rows.push(row);
  return rows;
}

/**
 * Rows of tag-map.csv that may be used: `reviewed` is yes (case-insensitive), the source is allowed,
 * the tag id is a positive integer and the weight (blank = 1) is positive. Everything else is dropped.
 */
export function parseTagMapCsv(text: string): TagMapRow[] {
  const [header, ...rows] = csvRecords(text);
  if (!header) return [];
  const col = (name: string) => header.map((h) => h.trim().toLowerCase()).indexOf(name);
  const [iSource, iLabel, iTag, iWeight, iReviewed] = ["source", "source_label", "tag_id", "weight", "reviewed"].map(col);
  if ([iSource, iLabel, iTag, iReviewed].some((i) => i < 0)) return [];
  const out: TagMapRow[] = [];
  for (const r of rows) {
    if ((r[iReviewed] ?? "").trim().toLowerCase() !== "yes") continue;
    const source = (r[iSource] ?? "").trim();
    const label = (r[iLabel] ?? "").trim();
    const tagId = Number((r[iTag] ?? "").trim());
    const rawWeight = iWeight >= 0 ? (r[iWeight] ?? "").trim() : "";
    const weight = rawWeight === "" ? 1 : Number(rawWeight);
    if (!TAG_SOURCES.includes(source) || label === "" || !Number.isInteger(tagId) || tagId <= 0 || !(weight > 0)) continue;
    out.push({ source: source as TagSource, source_label: label, tag_id: tagId, weight });
  }
  return out;
}
