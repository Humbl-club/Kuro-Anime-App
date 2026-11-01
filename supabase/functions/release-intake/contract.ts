// Row contract for the internal writer public.upsert_release_events_v1(p_rows jsonb)
// (service role only; SQL lives in supabase/prepared-migrations/20261101000000_*). One JSON
// array element per release unit. Columns follow spec 3.1 (unit_kind, unit_number, unit_label,
// release_at, basis, confidence, source, source_url, observed_at) plus the identity the writer
// needs to upsert idempotently.
//
//   medium           'anime' | 'manga'
//   media_id         local catalog id (anime.id / manga.id), never an AniList id
//   unit_kind        'episode' | 'chapter' | 'volume'
//   unit_number      numeric or null
//   unit_label       'Ep. 7' / 'Ch. 1197' / 'Vol. 115'
//   release_at       ISO timestamptz or null. Day-precision dates are stored at 12:00 UTC so the
//                    calendar day survives display in any time zone between UTC-11 and UTC+11.
//   precision        'instant' (AniList airing) | 'day' (MangaUpdates date, cadence estimate)
//   basis            'confirmed' | 'announced' | 'estimated'
//   confidence       1 for confirmed/announced; the cadence confidence (>= 0.7) for estimated
//   is_past          release_at <= observed_at
//   source           'anilist' | 'mangaupdates' | 'kuro_estimate'
//   source_url       attribution link (AniList title page / MangaUpdates series page)
//   observed_at      ISO timestamp of this intake run
//   source_identity  stable dedupe key; the writer upserts on it:
//                      anilist:airing:<airingScheduleId>         (a delay rewrites release_at)
//                      mangaupdates:<seriesId>:ch:<number>
//                      kuro_estimate:manga:<mangaId>:next        (one estimate per title, replaced)
//
// Licensing D11: rows always carry source + source_url (credit). Nothing here is scheduled.

export type ReleaseBasis = "confirmed" | "announced" | "estimated";
export type ReleaseSource = "anilist" | "mangaupdates" | "kuro_estimate";

export type ReleaseEventRow = {
  medium: "anime" | "manga";
  media_id: number;
  unit_kind: "episode" | "chapter" | "volume";
  unit_number: number | null;
  unit_label: string | null;
  release_at: string | null;
  precision: "instant" | "day";
  basis: ReleaseBasis;
  confidence: number;
  is_past: boolean;
  source: ReleaseSource;
  source_url: string | null;
  observed_at: string;
  source_identity: string;
};

export const RELEASE_WRITER_RPC = "upsert_release_events_v1";

/** YYYY-MM-DD -> the 12:00 UTC instant used for day-precision rows. */
export function dayPrecisionInstant(date: string): string {
  return `${date}T12:00:00.000Z`;
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
