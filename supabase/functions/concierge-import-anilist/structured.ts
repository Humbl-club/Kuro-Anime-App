// Structured AniList list rows for the durable import job.
// The concierge text line stays a separate preview. Missing fields stay absent.
import type { AniListEntry, AniListMediaType } from "./lines.ts";

export type LibraryImportItem = {
  medium: "anime" | "manga";
  external_id: string;
  status: string;
  progress: number | null;
  volumes_progress: number | null;
  score_raw: string | null;
  score_scale: string;
  notes: string | null;
  repeat_count: number | null;
  started_raw: string | null;
  finished_raw: string | null;
  private: boolean | null;
  custom_lists: string[];
  hidden_from_status_lists: boolean;
  source_list_options: string | null;
  normalized_rating: number | null;
};

function fuzzyDate(value: AniListEntry["startedAt"]): string | null {
  if (!value?.year) return null;
  const month = value.month ?? 0;
  const day = value.day ?? 0;
  if (!month) return String(value.year);
  if (!day) return `${value.year}-${String(month).padStart(2, "0")}`;
  return `${value.year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

export function libraryItem(type: AniListMediaType, entry: AniListEntry): LibraryImportItem {
  const raw = entry.scoreFormat ? entry.scoreRaw : (entry.scoreRaw ?? entry.score);
  return {
    medium: type === "ANIME" ? "anime" : "manga",
    external_id: String(entry.media.id),
    status: entry.status.toLowerCase(),
    progress: entry.progress,
    volumes_progress: entry.progressVolumes ?? null,
    score_raw: raw == null ? null : String(raw),
    score_scale: entry.scoreFormat ?? (entry.scoreRaw == null ? "POINT_10" : "POINT_100"),
    notes: entry.notes ?? null,
    repeat_count: entry.repeat ?? null,
    started_raw: fuzzyDate(entry.startedAt),
    finished_raw: fuzzyDate(entry.completedAt),
    private: entry.private ?? null,
    custom_lists: [...new Set([...(entry.customListOrder ?? []), ...Object.keys(entry.customLists ?? {})])]
      .filter((name) => entry.customLists?.[name] === true),
    source_list_options: entry.sourceListOptions ?? null,
    normalized_rating: entry.score != null && entry.score > 0 ? Math.max(1, Math.min(10, Math.round(entry.score))) : null,
    hidden_from_status_lists: entry.hiddenFromStatusLists ?? false,
  };
}
