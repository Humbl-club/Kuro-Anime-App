// mode 'syoboi': Zero-key Japanese broadcast airing schedule from Syoboi Calendar
// (https://cal.syoboi.jp/json.php?Req=ProgLookup&...) for anime linked in
// catalogue_id_links (kind = 'anime', source = 'syoboi', status = 'accepted').
//
// Emits confirmed instant episode rows with source = 'publisher' and omitted source_url
// so every row satisfies upsert_release_events_v1 (prepared 20261101000000).
import { readBounded } from "../_shared/polite_fetch.ts";
import { type ReleaseEventRow, writeReleaseEvents } from "./contract.ts";
import { WINDOW_FUTURE_SECONDS, WINDOW_PAST_SECONDS } from "./airing.ts";

const SYOBOI_ENDPOINT = "https://cal.syoboi.jp/json.php";
const SYOBOI_TID_BATCH = 50;
const WRITER_BATCH_SIZE = 500;
const JST_OFFSET_MS = 9 * 3600 * 1000;

export type SyoboiProgItem = {
  tid: string;
  pid: string;
  episode: number;
  stTimeSeconds: number;
};

export type SyoboiOptions = {
  limit: number;
  dryRun: boolean;
  deadlineMs: number;
  nowMs: number;
  writeNextAiring?: boolean;
  fetchFn?: typeof fetch;
  nowFn?: () => number;
};

export type SyoboiResult = {
  tids: number;
  programs: number;
  events: number;
  animePatched: number;
  stoppedEarly: string | null;
  sampleRows: ReleaseEventRow[];
};

function formatSyoboiJstStamp(ms: number): string {
  const jst = new Date(ms + JST_OFFSET_MS);
  const y = jst.getUTCFullYear();
  const m = String(jst.getUTCMonth() + 1).padStart(2, "0");
  const d = String(jst.getUTCDate()).padStart(2, "0");
  const hh = String(jst.getUTCHours()).padStart(2, "0");
  const mm = String(jst.getUTCMinutes()).padStart(2, "0");
  return `${y}${m}${d}_${hh}${mm}`;
}

export function buildSyoboiLookupUrl(tids: string[], fromMs: number, toMs: number): string {
  const params = new URLSearchParams({
    Req: "ProgLookup",
    TID: tids.join(","),
    Range: `${formatSyoboiJstStamp(fromMs)}-${formatSyoboiJstStamp(toMs)}`,
    JOIN: "SubTitles",
  });
  return `${SYOBOI_ENDPOINT}?${params.toString()}`;
}

function parseEntry(raw: unknown, fallbackPid?: string): SyoboiProgItem | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  if (r.Deleted === true || String(r.Deleted ?? "0") === "1") return null;
  const tid = String(r.TID ?? r.tid ?? "").trim();
  const pid = String(r.PID ?? r.pid ?? fallbackPid ?? "").trim();
  const episode = Number(r.Count ?? r.count);
  const stTimeSeconds = Number(r.StTime ?? r.st_time);
  if (!tid || !pid) return null;
  if (!Number.isFinite(episode) || episode <= 0 || episode > 99_999) return null;
  if (!Number.isFinite(stTimeSeconds) || stTimeSeconds <= 0) return null;
  return { tid, pid, episode, stTimeSeconds };
}

/**
 * Parses Syoboi ProgLookup JSON payloads (both canonical `{ Programs: { pid: {...} } }`
 * and `{ ProgItems: ... }` object/array variants) and returns normalized program entries.
 */
export function parseSyoboiProgItems(body: unknown): SyoboiProgItem[] {
  if (!body || typeof body !== "object") return [];
  const root = body as Record<string, unknown>;
  const container = root.ProgItems ?? root.Programs;
  const items: SyoboiProgItem[] = [];

  if (Array.isArray(container)) {
    for (const raw of container) {
      const parsed = parseEntry(raw);
      if (parsed) items.push(parsed);
    }
  } else if (container && typeof container === "object") {
    for (const [key, raw] of Object.entries(container as Record<string, unknown>)) {
      const parsed = parseEntry(raw, key);
      if (parsed) items.push(parsed);
    }
  }

  return items;
}

function sameInstant(a: string | null | undefined, b: string | null): boolean {
  if (a == null || b == null) return a == null && b == null;
  return Date.parse(a) === Date.parse(b);
}

// deno-lint-ignore no-explicit-any
export async function runSyoboiAiring(supabase: any, opts: SyoboiOptions): Promise<SyoboiResult> {
  const fetchFn = opts.fetchFn ?? globalThis.fetch.bind(globalThis);
  const nowFn = opts.nowFn ?? Date.now;
  const observedAt = new Date(opts.nowMs).toISOString();
  const fromMs = opts.nowMs - WINDOW_PAST_SECONDS * 1000;
  const toMs = opts.nowMs + WINDOW_FUTURE_SECONDS * 1000;
  const cap = opts.limit > 0 ? opts.limit : 250;

  const { data: linkRows, error: linkErr } = await supabase
    .from("catalogue_id_links")
    .select("kuro_id, source_key")
    .eq("kind", "anime")
    .eq("source", "syoboi")
    .eq("status", "accepted")
    .order("kuro_id", { ascending: true })
    .limit(cap);
  if (linkErr) throw new Error(`syoboi links lookup failed: ${linkErr.message ?? linkErr}`);

  const tidToAnimeIds = new Map<string, number[]>();
  for (const link of (linkRows ?? []) as { kuro_id: unknown; source_key: unknown }[]) {
    const kuroId = Number(link.kuro_id);
    const tid = String(link.source_key ?? "").trim();
    if (!Number.isInteger(kuroId) || kuroId <= 0 || !tid) continue;
    const list = tidToAnimeIds.get(tid) ?? [];
    if (!list.includes(kuroId)) list.push(kuroId);
    tidToAnimeIds.set(tid, list);
  }

  const allTids = [...tidToAnimeIds.keys()];
  const result: SyoboiResult = {
    tids: allTids.length,
    programs: 0,
    events: 0,
    animePatched: 0,
    stoppedEarly: null,
    sampleRows: [],
  };
  if (allTids.length === 0) return result;

  // Earliest broadcast per (animeId, episode) across channels so multi-station airings do not
  // collide or overwrite an earlier premiere instant.
  const bestByAnimeEpisode = new Map<string, { animeId: number; item: SyoboiProgItem }>();

  for (let i = 0; i < allTids.length; i += SYOBOI_TID_BATCH) {
    if (nowFn() >= opts.deadlineMs) {
      result.stoppedEarly = "deadline";
      break;
    }
    const batch = allTids.slice(i, i + SYOBOI_TID_BATCH);
    const url = buildSyoboiLookupUrl(batch, fromMs, toMs);
    const res = await fetchFn(url, { headers: { Accept: "application/json" } });
    if (res.status === 429) {
      result.stoppedEarly = "rate_limited";
      break;
    }
    if (!res.ok) {
      throw new Error(`syoboi lookup failed with HTTP ${res.status}`);
    }
    const rawBody = await readBounded(res, 2 * 1024 * 1024);
    const payload = rawBody ? JSON.parse(rawBody) : {};
    const parsed = parseSyoboiProgItems(payload);
    result.programs += parsed.length;

    for (const item of parsed) {
      const animeIds = tidToAnimeIds.get(item.tid) ?? [];
      for (const animeId of animeIds) {
        const key = `${animeId}:${item.episode}`;
        const prev = bestByAnimeEpisode.get(key);
        if (
          !prev ||
          item.stTimeSeconds < prev.item.stTimeSeconds ||
          (item.stTimeSeconds === prev.item.stTimeSeconds && item.pid < prev.item.pid)
        ) {
          bestByAnimeEpisode.set(key, { animeId, item });
        }
      }
    }
  }

  const rows: ReleaseEventRow[] = [];
  const nextByAnime = new Map<number, { episode: number; stTimeSeconds: number }>();

  for (const { animeId, item } of bestByAnimeEpisode.values()) {
    const releaseMs = item.stTimeSeconds * 1000;
    const releaseIso = new Date(releaseMs).toISOString();
    rows.push({
      medium: "anime",
      media_id: animeId,
      unit_kind: "episode",
      unit_number: item.episode,
      unit_label: `Ep. ${item.episode}`,
      precision: "instant",
      release_at: releaseIso,
      status: releaseMs <= opts.nowMs ? "released" : "scheduled",
      basis: "confirmed",
      confidence: 1,
      source: "publisher",
      source_url: null,
      observed_at: observedAt,
      external_id: `syoboi:${item.tid}:${item.pid}`.slice(0, 120),
    });

    if (releaseMs > opts.nowMs) {
      const currentNext = nextByAnime.get(animeId);
      if (
        !currentNext ||
        item.stTimeSeconds < currentNext.stTimeSeconds ||
        (item.stTimeSeconds === currentNext.stTimeSeconds && item.episode < currentNext.episode)
      ) {
        nextByAnime.set(animeId, { episode: item.episode, stTimeSeconds: item.stTimeSeconds });
      }
    }
  }

  result.events = rows.length;
  result.sampleRows = rows.slice(0, 5);

  if (!opts.dryRun) {
    for (let i = 0; i < rows.length; i += WRITER_BATCH_SIZE) {
      await writeReleaseEvents(supabase, rows.slice(i, i + WRITER_BATCH_SIZE));
    }

    if (opts.writeNextAiring !== false && nextByAnime.size > 0) {
      const targetIds = [...nextByAnime.keys()];
      const { data: existingAnime, error: animeErr } = await supabase
        .from("anime")
        .select("id, next_episode_number, next_airing_at")
        .in("id", targetIds);
      if (animeErr) throw new Error(`syoboi anime lookup failed: ${animeErr.message ?? animeErr}`);

      for (const row of (existingAnime ?? []) as { id: number; next_episode_number: number | null; next_airing_at: string | null }[]) {
        const next = nextByAnime.get(Number(row.id));
        if (!next) continue;
        const nextIso = new Date(next.stTimeSeconds * 1000).toISOString();
        if ((row.next_episode_number ?? null) === next.episode && sameInstant(row.next_airing_at, nextIso)) {
          continue;
        }
        const { error: updErr } = await supabase
          .from("anime")
          .update({ next_episode_number: next.episode, next_airing_at: nextIso })
          .eq("id", row.id);
        if (updErr) throw new Error(`syoboi anime update failed: ${updErr.message ?? updErr}`);
        result.animePatched++;
      }
    }
  }

  return result;
}
