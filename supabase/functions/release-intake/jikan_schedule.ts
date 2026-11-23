// mode 'jikan': Polite Jikan v4 seasonal broadcast schedule fallback
// (https://api.jikan.moe/v4/seasons/now?sfw=true&page=<p>).
//
// Fills missing or stale `next_airing_at` pointers for RELEASING anime matched strictly on exact
// `anime.mal_id` WITHOUT overwriting titles that already have a fresh future `next_airing_at > now`
// (preserving exact broadcaster times from Syoboi/AniList).
import { readBounded } from "../_shared/polite_fetch.ts";
import { type ReleaseEventRow, writeReleaseEvents } from "./contract.ts";

const JIKAN_SEASONS_NOW = "https://api.jikan.moe/v4/seasons/now";
const JST_OFFSET_MS = 9 * 3600 * 1000;
const WEEK_MS = 7 * 86_400 * 1000;
const WRITER_BATCH_SIZE = 500;

export type JikanBroadcast = {
  weekday: number; // 0 = Sunday ... 6 = Saturday in JST
  hour: number;
  minute: number;
};

export type JikanOptions = {
  maxPages?: number;
  dryRun: boolean;
  deadlineMs: number;
  nowMs: number;
  writeNextAiring?: boolean;
  fetchFn?: typeof fetch;
  nowFn?: () => number;
};

export type JikanResult = {
  candidates: number;
  skippedExistingFuture: number;
  pagesFetched: number;
  matched: number;
  events: number;
  animePatched: number;
  stoppedEarly: string | null;
  sampleRows: ReleaseEventRow[];
};

const WEEKDAY_MAP: Record<string, number> = {
  sunday: 0,
  sundays: 0,
  monday: 1,
  mondays: 1,
  tuesday: 2,
  tuesdays: 2,
  wednesday: 3,
  wednesdays: 3,
  thursday: 4,
  thursdays: 4,
  friday: 5,
  fridays: 5,
  saturday: 6,
  saturdays: 6,
};

/** Parses Jikan `broadcast` (`{ day: "Sundays", time: "23:00", timezone: "Asia/Tokyo" }`). */
export function parseJikanBroadcast(raw: unknown): JikanBroadcast | null {
  if (!raw || typeof raw !== "object") return null;
  const b = raw as Record<string, unknown>;
  const dayRaw = typeof b.day === "string" ? b.day.trim().toLowerCase() : "";
  const timeRaw = typeof b.time === "string" ? b.time.trim() : "";
  const tzRaw = typeof b.timezone === "string" ? b.timezone.trim() : "Asia/Tokyo";
  if (!dayRaw || !timeRaw) return null;
  if (tzRaw && tzRaw !== "Asia/Tokyo" && tzRaw !== "JST") return null;

  const weekday = WEEKDAY_MAP[dayRaw];
  if (weekday === undefined) return null;

  const m = timeRaw.match(/^([01]?\d|2[0-3]):([0-5]\d)$/);
  if (!m) return null;
  const hour = Number(m[1]);
  const minute = Number(m[2]);
  if (!Number.isInteger(hour) || !Number.isInteger(minute)) return null;
  return { weekday, hour, minute };
}

/**
 * Returns the next strictly-future UTC epoch ms for `(weekday, hour, minute)` in Asia/Tokyo (UTC+9)
 * within `(nowMs, nowMs + 7 days]`.
 */
export function computeNextJstBroadcastMs(broadcast: JikanBroadcast, nowMs: number): number {
  const jstNow = new Date(nowMs + JST_OFFSET_MS);
  const currentWeekday = jstNow.getUTCDay();
  const deltaDays = (broadcast.weekday - currentWeekday + 7) % 7;

  const candidateUtcMs = Date.UTC(
    jstNow.getUTCFullYear(),
    jstNow.getUTCMonth(),
    jstNow.getUTCDate() + deltaDays,
    broadcast.hour,
    broadcast.minute,
    0,
    0,
  ) - JST_OFFSET_MS;

  return candidateUtcMs > nowMs ? candidateUtcMs : candidateUtcMs + WEEK_MS;
}

/**
 * Computes the positive integer episode airing at `nextInstantMs` given series premiere timestamp
 * `airedFromISO` assuming weekly cadence. Returns null when premiere is missing or episode exceeds total.
 */
export function estimateEpisodeNumber(
  airedFromISO: unknown,
  nextInstantMs: number,
  totalEpisodes: number | null,
): number | null {
  if (typeof airedFromISO !== "string" || !airedFromISO.trim()) return null;
  const airedMs = Date.parse(airedFromISO);
  if (!Number.isFinite(airedMs)) return null;
  if (nextInstantMs + 12 * 3600 * 1000 < airedMs) return null;

  const weeksElapsed = Math.max(0, Math.floor((nextInstantMs - airedMs + 12 * 3600 * 1000) / WEEK_MS));
  const ep = weeksElapsed + 1;
  if (!Number.isInteger(ep) || ep <= 0 || ep > 9999) return null;
  if (totalEpisodes != null && Number.isInteger(totalEpisodes) && totalEpisodes > 0 && ep > totalEpisodes) {
    return null;
  }
  return ep;
}

type LocalAnimeRow = {
  id: number;
  mal_id: number | null;
  episodes: number | null;
  next_episode_number: number | null;
  next_airing_at: string | null;
};

function sameInstant(a: string | null | undefined, b: string | null): boolean {
  if (a == null || b == null) return a == null && b == null;
  return Date.parse(a) === Date.parse(b);
}

export async function runJikanSchedule(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  opts: JikanOptions,
): Promise<JikanResult> {
  const fetchFn = opts.fetchFn ?? fetch;
  const nowFn = opts.nowFn ?? Date.now;
  const maxPages = Math.max(1, Math.min(12, opts.maxPages ?? 8));
  const observedAt = new Date(opts.nowMs).toISOString();

  const result: JikanResult = {
    candidates: 0,
    skippedExistingFuture: 0,
    pagesFetched: 0,
    matched: 0,
    events: 0,
    animePatched: 0,
    stoppedEarly: null,
    sampleRows: [],
  };

  const { data: localAnime, error: animeErr } = await supabase
    .from("anime")
    .select("id, mal_id, episodes, next_episode_number, next_airing_at")
    .eq("status", "RELEASING")
    .not("mal_id", "is", null)
    .limit(2000);
  if (animeErr) throw new Error(`jikan anime lookup failed: ${animeErr.message ?? animeErr}`);

  const candidateByMal = new Map<number, LocalAnimeRow>();
  for (const row of (localAnime ?? []) as LocalAnimeRow[]) {
    const malId = Number(row.mal_id);
    if (!Number.isInteger(malId) || malId <= 0) continue;
    const futureMs = row.next_airing_at ? Date.parse(row.next_airing_at) : NaN;
    if (Number.isFinite(futureMs) && futureMs > opts.nowMs) {
      result.skippedExistingFuture++;
      continue;
    }
    candidateByMal.set(malId, row);
  }
  result.candidates = candidateByMal.size;
  if (candidateByMal.size === 0) return result;

  const eventRows: ReleaseEventRow[] = [];
  const matchedMal = new Set<number>();

  for (let page = 1; page <= maxPages; page++) {
    if (nowFn() >= opts.deadlineMs) {
      result.stoppedEarly = "deadline";
      break;
    }
    const url = `${JIKAN_SEASONS_NOW}?sfw=true&page=${page}`;
    const res = await fetchFn(url, { headers: { Accept: "application/json" } });
    if (res.status === 429) {
      result.stoppedEarly = "rate_limited";
      break;
    }
    if (!res.ok) {
      throw new Error(`jikan seasons/now page ${page} failed with HTTP ${res.status}`);
    }
    result.pagesFetched++;
    const raw = await readBounded(res, 2 * 1024 * 1024);
    // deno-lint-ignore no-explicit-any
    const parsed = raw ? (JSON.parse(raw) as any) : {};
    // deno-lint-ignore no-explicit-any
    const items = Array.isArray(parsed?.data) ? (parsed.data as any[]) : [];

    for (const item of items) {
      const malId = Number(item?.mal_id);
      if (!Number.isInteger(malId) || matchedMal.has(malId)) continue;
      const local = candidateByMal.get(malId);
      if (!local) continue;

      const broadcast = parseJikanBroadcast(item?.broadcast);
      if (!broadcast) continue;

      const nextMs = computeNextJstBroadcastMs(broadcast, opts.nowMs);
      const jikanEpisodes = Number.isInteger(Number(item?.episodes)) ? Number(item.episodes) : null;
      const totalEpisodes = local.episodes ?? jikanEpisodes;
      const ep = estimateEpisodeNumber(item?.aired?.from, nextMs, totalEpisodes);
      if (ep === null) continue;

      matchedMal.add(malId);
      result.matched++;

      const nextIso = new Date(nextMs).toISOString();
      eventRows.push({
        medium: "anime",
        media_id: local.id,
        unit_kind: "episode",
        unit_number: ep,
        unit_label: `Ep. ${ep}`,
        precision: "instant",
        release_at: nextIso,
        status: "scheduled",
        basis: "announced",
        confidence: 1,
        source: "publisher",
        source_url: null,
        observed_at: observedAt,
        external_id: `jikan:${malId}:${ep}`,
      });

      if (opts.writeNextAiring !== false) {
        if ((local.next_episode_number ?? null) !== ep || !sameInstant(local.next_airing_at, nextIso)) {
          if (!opts.dryRun) {
            const { error: updateErr } = await supabase
              .from("anime")
              .update({ next_episode_number: ep, next_airing_at: nextIso })
              .eq("id", local.id);
            if (updateErr) throw new Error(`jikan anime next airing update failed: ${updateErr.message ?? updateErr}`);
          }
          local.next_episode_number = ep;
          local.next_airing_at = nextIso;
          result.animePatched++;
        }
      }
    }

    const hasNext = Boolean(parsed?.pagination?.has_next_page);
    if (!hasNext) break;
  }

  for (let i = 0; i < eventRows.length; i += WRITER_BATCH_SIZE) {
    const chunk = eventRows.slice(i, i + WRITER_BATCH_SIZE);
    if (!opts.dryRun) await writeReleaseEvents(supabase, chunk);
    result.events += chunk.length;
    if (result.sampleRows.length < 5) {
      result.sampleRows.push(...chunk.slice(0, 5 - result.sampleRows.length));
    }
  }

  return result;
}
