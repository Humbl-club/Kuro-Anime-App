// mode 'airing': AniList Page.airingSchedules over [now - 6 h, now + 8 d], sort TIME, paged.
//   - Every schedule row of a catalog title becomes a confirmed release event (source anilist,
//     precision instant; the writer keys it by title + episode, so a delay rewrites release_at).
//     Rows in the past part of the window are status 'released'.
//   - anime.next_episode_number / next_airing_at are patched from the nested
//     media.nextAiringEpisode (AniList's own "next"), only when the value differs. A title that is
//     not in the window is never touched by the window pass.
//   - Stale sweep (optional): RELEASING titles whose next_airing_at is more than 6 h past are
//     re-read with Page.media(id_in:[...]) (<= 50 per request) and patched the same way.
//   - mediaIds that are not in the catalog are counted and sampled, never imported here.
// Writes go per page, so a later failure keeps earlier pages. A limiter stop (budget / rate
// limit) before a request ends the pass cleanly; any other provider error fails the run.
import { type AniListClient, isCleanStop } from "../_shared/anilist_client.ts";
import { type ReleaseEventRow, writeReleaseEvents } from "./contract.ts";

export const WINDOW_PAST_SECONDS = 6 * 3600;
export const WINDOW_FUTURE_SECONDS = 8 * 86400;

export const AIRING_WINDOW_QUERY = `
  query ($page: Int, $perPage: Int, $from: Int, $to: Int) {
    Page(page: $page, perPage: $perPage) {
      pageInfo { hasNextPage }
      airingSchedules(airingAt_greater: $from, airingAt_lesser: $to, sort: [TIME]) {
        id airingAt episode mediaId
        media { id status nextAiringEpisode { episode airingAt } }
      }
    }
  }
`;

export const STALE_MEDIA_QUERY = `
  query ($ids: [Int]) {
    Page(page: 1, perPage: 50) {
      media(id_in: $ids, type: ANIME) { id status nextAiringEpisode { id episode airingAt } }
    }
  }
`;

export type AiringOptions = {
  perPage: number;
  maxPages: number;
  staleSweep: boolean;
  staleLimit: number;
  dryRun: boolean;
  deadlineMs: number;
  nowMs: number;
};

export type AiringResult = {
  pages: number;
  schedules: number;
  events: number;
  animePatched: number;
  unknownMedia: number;
  unknownSample: number[];
  stalePatched: number;
  staleChecked: number;
  stoppedEarly: string | null;
  sampleRows: ReleaseEventRow[];
};

type CatalogAnime = { id: number; anilist_id: number; next_episode_number: number | null; next_airing_at: string | null };

function iso(seconds: number): string {
  return new Date(seconds * 1000).toISOString();
}

function sameInstant(a: string | null, b: string | null): boolean {
  if (a == null || b == null) return a == null && b == null;
  return Date.parse(a) === Date.parse(b);
}

// deno-lint-ignore no-explicit-any
async function catalogByAniList(supabase: any, anilistIds: number[]): Promise<Map<number, CatalogAnime>> {
  const map = new Map<number, CatalogAnime>();
  if (anilistIds.length === 0) return map;
  const { data, error } = await supabase
    .from("anime")
    .select("id, anilist_id, next_episode_number, next_airing_at")
    .in("anilist_id", anilistIds);
  if (error) throw new Error(`anime lookup failed: ${error.message ?? error}`);
  for (const row of (data ?? []) as CatalogAnime[]) map.set(Number(row.anilist_id), row);
  return map;
}

/** Patch next_* only when AniList's next differs from the stored value. */
async function patchNextAiring(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  row: CatalogAnime,
  // deno-lint-ignore no-explicit-any
  next: any,
  dryRun: boolean,
): Promise<boolean> {
  const episode = Number.isFinite(Number(next?.episode)) && next?.airingAt ? Number(next.episode) : null;
  const airingAt = episode !== null ? iso(Number(next.airingAt)) : null;
  if ((row.next_episode_number ?? null) === episode && sameInstant(row.next_airing_at, airingAt)) return false;
  if (dryRun) return true;
  const { error } = await supabase.from("anime").update({ next_episode_number: episode, next_airing_at: airingAt }).eq("id", row.id);
  if (error) throw new Error(`anime next airing update failed: ${error.message ?? error}`);
  row.next_episode_number = episode;
  row.next_airing_at = airingAt;
  return true;
}

function eventRow(row: CatalogAnime, scheduleId: number, episode: number, airingAt: number, nowMs: number, observedAt: string): ReleaseEventRow {
  return {
    medium: "anime",
    media_id: row.id,
    unit_kind: "episode",
    unit_number: episode,
    unit_label: `Ep. ${episode}`,
    precision: "instant",
    release_at: iso(airingAt),
    status: airingAt * 1000 <= nowMs ? "released" : "scheduled",
    basis: "confirmed",
    confidence: 1,
    source: "anilist",
    source_url: `https://anilist.co/anime/${row.anilist_id}`,
    observed_at: observedAt,
    external_id: `airing:${scheduleId}`,
  };
}

// deno-lint-ignore no-explicit-any
export async function runAiringWindow(supabase: any, anilist: AniListClient, opts: AiringOptions): Promise<AiringResult> {
  const nowSec = Math.floor(opts.nowMs / 1000);
  const observedAt = new Date(opts.nowMs).toISOString();
  const result: AiringResult = {
    pages: 0,
    schedules: 0,
    events: 0,
    animePatched: 0,
    unknownMedia: 0,
    unknownSample: [],
    stalePatched: 0,
    staleChecked: 0,
    stoppedEarly: null,
    sampleRows: [],
  };
  const unknown = new Set<number>();
  const patched = new Set<number>();

  for (let page = 1; page <= opts.maxPages; page++) {
    let data;
    try {
      data = await anilist.query(AIRING_WINDOW_QUERY, {
        page,
        perPage: opts.perPage,
        from: nowSec - WINDOW_PAST_SECONDS,
        to: nowSec + WINDOW_FUTURE_SECONDS,
      }, { require: ["Page"], deadlineMs: opts.deadlineMs });
    } catch (e) {
      if (isCleanStop(e)) {
        result.stoppedEarly = (e as { kind: string }).kind;
        break;
      }
      throw e;
    }
    const schedules = data.Page.airingSchedules;
    if (!Array.isArray(schedules)) throw new Error("AniList response is missing data.Page.airingSchedules");
    result.pages++;
    result.schedules += schedules.length;

    const ids = [...new Set(schedules.map((s) => Number(s?.mediaId)).filter((n) => Number.isInteger(n) && n > 0))];
    const catalog = await catalogByAniList(supabase, ids);
    const rows: ReleaseEventRow[] = [];
    for (const s of schedules) {
      const mediaId = Number(s?.mediaId);
      const row = catalog.get(mediaId);
      if (!row) {
        if (Number.isInteger(mediaId) && mediaId > 0) unknown.add(mediaId);
        continue;
      }
      const scheduleId = Number(s?.id);
      const episode = Number(s?.episode);
      const airingAt = Number(s?.airingAt);
      if (!Number.isInteger(scheduleId) || !Number.isFinite(episode) || !Number.isFinite(airingAt)) continue;
      rows.push(eventRow(row, scheduleId, episode, airingAt, opts.nowMs, observedAt));
      if (!patched.has(row.id)) {
        patched.add(row.id);
        if (await patchNextAiring(supabase, row, s?.media?.nextAiringEpisode, opts.dryRun)) result.animePatched++;
      }
    }
    if (!opts.dryRun) await writeReleaseEvents(supabase, rows);
    result.events += rows.length;
    if (result.sampleRows.length < 5) result.sampleRows.push(...rows.slice(0, 5 - result.sampleRows.length));
    if (data.Page.pageInfo?.hasNextPage !== true) break;
  }

  if (opts.staleSweep && !result.stoppedEarly && opts.staleLimit > 0) {
    const cutoff = iso(nowSec - WINDOW_PAST_SECONDS);
    const { data: stale, error } = await supabase
      .from("anime")
      .select("id, anilist_id, next_episode_number, next_airing_at")
      .eq("status", "RELEASING")
      .lt("next_airing_at", cutoff)
      .not("anilist_id", "is", null)
      .order("popularity", { ascending: false })
      .limit(Math.min(opts.staleLimit, 50));
    if (error) throw new Error(`stale anime lookup failed: ${error.message ?? error}`);
    const staleRows = ((stale ?? []) as CatalogAnime[]).filter((r) => !patched.has(r.id));
    if (staleRows.length > 0) {
      try {
        const data = await anilist.query(STALE_MEDIA_QUERY, { ids: staleRows.map((r) => Number(r.anilist_id)) }, {
          require: ["Page"],
          deadlineMs: opts.deadlineMs,
        });
        const media = Array.isArray(data.Page.media) ? data.Page.media : [];
        const byId = new Map<number, CatalogAnime>(staleRows.map((r) => [Number(r.anilist_id), r]));
        const rows: ReleaseEventRow[] = [];
        for (const m of media) {
          const row = byId.get(Number(m?.id));
          if (!row) continue;
          result.staleChecked++;
          const next = m?.nextAiringEpisode;
          if (await patchNextAiring(supabase, row, next, opts.dryRun)) result.stalePatched++;
          const scheduleId = Number(next?.id);
          if (Number.isInteger(scheduleId) && Number.isFinite(Number(next?.episode)) && Number.isFinite(Number(next?.airingAt))) {
            rows.push(eventRow(row, scheduleId, Number(next.episode), Number(next.airingAt), opts.nowMs, observedAt));
          }
        }
        if (!opts.dryRun) await writeReleaseEvents(supabase, rows);
        result.events += rows.length;
      } catch (e) {
        if (!isCleanStop(e)) throw e;
        result.stoppedEarly = (e as { kind: string }).kind;
      }
    }
  }

  result.unknownMedia = unknown.size;
  result.unknownSample = [...unknown].slice(0, 20);
  return result;
}
