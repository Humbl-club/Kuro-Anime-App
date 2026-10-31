// Pure AniList list lines and the item cap. No fetch and no clock: the same
// title, year, status, and progress cues the concierge parser already accepts.
// Season year wins over start year. Score stays off the line (preview only).

export type AniListMediaType = "ANIME" | "MANGA";
export type AniListStatus =
  | "CURRENT"
  | "COMPLETED"
  | "PLANNING"
  | "DROPPED"
  | "PAUSED"
  | "REPEATING";

export type AniListTitle = {
  english?: string | null;
  romaji?: string | null;
  native?: string | null;
};

export type AniListEntry = {
  status: AniListStatus;
  progress: number | null;
  score: number | null;
  scoreRaw?: number | null;
  original3?: number | null; original5?: number | null; original10?: number | null; originalDecimal?: number | null;
  scoreFormat?: string;
  customListOrder?: string[];
  sourceListOptions?: string;
  progressVolumes?: number | null;
  repeat?: number | null;
  notes?: string | null;
  private?: boolean | null;
  hiddenFromStatusLists?: boolean | null;
  customLists?: Record<string, boolean> | null;
  startedAt?: { year?: number | null; month?: number | null; day?: number | null } | null;
  completedAt?: { year?: number | null; month?: number | null; day?: number | null } | null;
  updatedAt: number | null;
  media: {
    id: number;
    seasonYear?: number | null;
    startDate?: { year?: number | null } | null;
    format?: string | null;
    title: AniListTitle;
  };
};

export type PreviewItem = {
  mediaId: number;
  type: AniListMediaType;
  status: AniListStatus;
  line: string;
  title: string;
  year: number | null;
  progress: number | null;
  score: number | null;
  updatedAt: number | null;
};

export function pickTitle(t: AniListTitle): string {
  return String(t.english || t.romaji || t.native || "").trim();
}

export function yearFor(entry: AniListEntry): number | null {
  return entry.media.seasonYear ?? entry.media.startDate?.year ?? null;
}

export function lineForEntry(type: AniListMediaType, e: AniListEntry): string {
  const title = pickTitle(e.media.title) || `AniList ${type} ${e.media.id}`;
  const year = yearFor(e);
  const base = year ? `${title} (${year})` : title;

  switch (e.status) {
    case "COMPLETED":
      return `${base} (completed)`;
    case "CURRENT": {
      const p = Number(e.progress ?? 0);
      if (p > 0) {
        return type === "ANIME" ? `${base} up to ep ${p}` : `${base} up to ch ${p}`;
      }
      return `${base} (watching)`;
    }
    case "PLANNING":
      return `${base} (planning)`;
    case "PAUSED":
      return `${base} (on hold)`;
    case "DROPPED":
      return `${base} (dropped)`;
    case "REPEATING":
      return `${base} (rewatching)`;
    default:
      return `${base}`;
  }
}

export function dedupeAndJoinLines(lines: string[]): { text: string; itemCount: number } {
  const seen = new Set<string>();
  const deduped: string[] = [];
  for (const line of lines) {
    const normalized = line.trim();
    if (!normalized) continue;
    const key = normalized.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    deduped.push(normalized);
  }
  return { text: deduped.join("\n"), itemCount: deduped.length };
}

export function buildPreviewItems(
  lines: string[],
  entries: Array<{ type: AniListMediaType; entry: AniListEntry }>,
): PreviewItem[] {
  return entries.slice(0, 8).map(({ type, entry }, index) => ({
    mediaId: entry.media.id,
    type,
    status: entry.status,
    line: lines[index] ?? lineForEntry(type, entry),
    title: pickTitle(entry.media.title) || `AniList ${type} ${entry.media.id}`,
    year: yearFor(entry),
    progress: entry.progress,
    score: entry.score,
    updatedAt: entry.updatedAt,
  }));
}

/**
 * Entries from one provider page that still fit under maxItems.
 * Truncation is set only when the cap stops the list while the provider
 * still has more (another entry on this page, or another page). Filling the
 * cap on the last page is not truncation.
 */
export function takePage(
  entries: readonly AniListEntry[],
  alreadyTaken: number,
  maxItems: number,
  hasNextPage: boolean,
): { entries: AniListEntry[]; truncated: boolean; fetchNextPage: boolean } {
  const taken: AniListEntry[] = [];
  for (const entry of entries) {
    if (alreadyTaken + taken.length >= maxItems) {
      return { entries: taken, truncated: true, fetchNextPage: false };
    }
    taken.push(entry);
  }
  if (!hasNextPage) {
    return { entries: taken, truncated: false, fetchNextPage: false };
  }
  if (alreadyTaken + taken.length >= maxItems) {
    return { entries: taken, truncated: true, fetchNextPage: false };
  }
  return { entries: taken, truncated: false, fetchNextPage: true };
}
