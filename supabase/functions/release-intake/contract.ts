// Row contract for the internal writer public.upsert_release_events_v1(p_rows jsonb)
// (service role only; SQL: supabase/prepared-migrations/20261101000000_release_schedule_and_themes_v2.sql,
// section 8). One JSON array element per release unit, <= 500 per call, all-or-nothing.
// Columns follow spec 3.1 (unit_kind, unit_number, unit_label, release_at, basis, confidence,
// source, source_url, observed_at) plus what the writer validates:
//
//   medium             'anime' | 'manga'
//   media_id           local catalog id (anime.id / manga.id), never an AniList id
//   unit_kind          anime: 'episode' | 'season'; manga: 'chapter' | 'volume'
//   unit_number        required, 0..99999 with <= 3 decimals
//   unit_label         'Ep. 7' / 'Ch. 1197' / 'Vol. 115'
//   precision 'instant' -> release_at (ISO instant), source_local_date absent (AniList airing)
//   precision 'day'     -> source_local_date 'YYYY-MM-DD', release_at absent (MangaUpdates
//                          dates, cadence estimates)
//   status             'released' for a past unit, 'scheduled' otherwise (estimates always
//                      'scheduled')
//   basis              'confirmed' | 'announced' | 'estimated' (estimated <=> source kuro_estimate)
//   confidence         1 for confirmed; the cadence confidence (>= 0.7) for estimated
//   source             'anilist' | 'mangaupdates' | 'kuro_estimate'
//   source_url         https attribution link (AniList title page / MangaUpdates series page)
//   observed_at        ISO timestamp of this intake run
//   external_id        source-side evidence id (AniList airing schedule id, MU series id)
// The writer derives the natural key itself:
//   <source>:<medium>:<media_id>:<unit_kind>:<unit_number>   confirmed (a delay updates the row)
//   kuro_estimate:<medium>:<media_id>:<unit_kind>:next       estimated (one per title, replaced)
//
// Licensing D11: rows always carry source + source_url (credit). Nothing here is scheduled.

export type ReleaseBasis = "confirmed" | "announced" | "estimated";
export type ReleaseSource = "anilist" | "mangaupdates" | "kuro_estimate";

export type ReleaseEventRow = {
  medium: "anime" | "manga";
  media_id: number;
  unit_kind: "episode" | "chapter" | "volume";
  unit_number: number;
  unit_label: string;
  precision: "instant" | "day";
  /** ISO instant; only with precision 'instant'. */
  release_at?: string;
  /** YYYY-MM-DD; only with precision 'day'. */
  source_local_date?: string;
  status: "released" | "scheduled";
  basis: ReleaseBasis;
  confidence: number;
  source: ReleaseSource;
  source_url: string | null;
  observed_at: string;
  external_id: string;
};

export const RELEASE_WRITER_RPC = "upsert_release_events_v1";

/** Start of the UTC day after `date` (YYYY-MM-DD): a day-precision unit is past once its day is over. */
export function dayIsPast(date: string, nowMs: number): boolean {
  return Date.parse(`${date}T00:00:00Z`) + 86_400_000 <= nowMs;
}

export function formatUnitNumber(n: number): string {
  return Number.isInteger(n) ? String(n) : String(Math.round(n * 10) / 10);
}

// deno-lint-ignore no-explicit-any
export async function writeReleaseEvents(supabase: any, rows: ReleaseEventRow[]): Promise<number> {
  if (rows.length === 0) return 0;
  const { error } = await supabase.rpc(RELEASE_WRITER_RPC, { p_rows: rows });
  if (error) {
    const message = typeof error?.message === "string" ? error.message : String(error);
    throw new Error(`${RELEASE_WRITER_RPC} failed: ${message}`);
  }
  return rows.length;
}
