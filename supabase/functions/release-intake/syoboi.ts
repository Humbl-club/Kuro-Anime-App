// mode 'syoboi': Zero-key Japanese broadcast airing schedule from Syoboi Calendar
// (https://cal.syoboi.jp/cal_chk.php?days=14 + Req=TitleMedium auto-discovery + Req=ProgLookup).
//
// Emits confirmed instant episode rows with source = 'publisher' and omitted source_url
// so every row satisfies upsert_release_events_v1, updates anime.next_episode_number /
// anime.next_airing_at, and (when discover=true or no accepted syoboi links exist yet)
// auto-links RELEASING / NOT_YET_RELEASED anime via exact normalized title + year matching.
import { normaliseTitle } from "../_shared/catalogue/normalise_title.ts";
import { readBounded } from "../_shared/polite_fetch.ts";
import { type ReleaseEventRow, writeReleaseEvents } from "./contract.ts";
import { WINDOW_FUTURE_SECONDS, WINDOW_PAST_SECONDS } from "./airing.ts";

const SYOBOI_JSON_ENDPOINT = "https://cal.syoboi.jp/json.php";
const SYOBOI_CAL_CHK_ENDPOINT = "https://cal.syoboi.jp/cal_chk.php";
const SYOBOI_TID_BATCH = 50;
const SYOBOI_TITLE_BATCH = 40;
const WRITER_BATCH_SIZE = 500;
const JST_OFFSET_MS = 9 * 3600 * 1000;
const STALE_PAST_GRACE_MS = 14 * 24 * 3600 * 1000;

export type SyoboiProgItem = {
  tid: string;
  pid: string;
  episode: number;
  stTimeSeconds: number;
  title?: string;
};

export type SyoboiTitleMeta = {
  tid: string;
  title: string | null;
  titleEn: string | null;
  titleYomi: string | null;
  firstYear: number | null;
};

export type SyoboiOptions = {
  limit: number;
  discover?: boolean;
  days?: number;
  maxDiscoverTids?: number;
  staleSweep?: boolean;
  dryRun: boolean;
  deadlineMs: number;
  nowMs: number;
  writeNextAiring?: boolean;
  fetchFn?: typeof fetch;
  nowFn?: () => number;
};

export type SyoboiResult = {
  tids: number;
  discoveredTids: number;
  linked: number;
  programs: number;
  events: number;
  animePatched: number;
  staleCleared: number;
  stoppedEarly: string | null;
  sampleRows: ReleaseEventRow[];
};

function decodeXmlEntities(raw: string): string {
  return raw
    .replaceAll("&amp;", "&")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&quot;", '"')
    .replaceAll("&apos;", "'")
    .replaceAll("&#039;", "'")
    .replace(/&#(\d+);/g, (_m, dec) => {
      const code = Number(dec);
      return Number.isInteger(code) && code > 0 ? String.fromCodePoint(code) : "";
    });
}

function parseJstCompactTimestamp(stamp: string): number | null {
  const m = stamp.trim().match(/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$/);
  if (!m) return null;
  const year = Number(m[1]);
  const month = Number(m[2]);
  const day = Number(m[3]);
  const hour = Number(m[4]);
  const minute = Number(m[5]);
  const second = Number(m[6]);
  const utcMs = Date.UTC(year, month - 1, day, hour, minute, second) - JST_OFFSET_MS;
  return Number.isFinite(utcMs) ? Math.floor(utcMs / 1000) : null;
}

/**
 * Parses `cal_chk.php?days=N` XML `<ProgItem ... />` tags into normalized broadcast items.
 * Skips rerun marathons without a positive integer `Count` and deleted items (`Deleted="1"`).
 */
export function parseSyoboiCalChkXml(xmlText: string): SyoboiProgItem[] {
  if (!xmlText || typeof xmlText !== "string") return [];
  const items: SyoboiProgItem[] = [];
  const tagRe = /<ProgItem\b([^>]*?)\/?>/g;
  const attrRe = /([A-Za-z0-9_]+)=(?:"([^"]*)"|'([^']*)')/g;

  for (const tagMatch of xmlText.matchAll(tagRe)) {
    const attrsRaw = tagMatch[1] ?? "";
    const attrs: Record<string, string> = {};
    for (const am of attrsRaw.matchAll(attrRe)) {
      attrs[am[1]] = decodeXmlEntities(am[2] ?? am[3] ?? "");
    }
    if (attrs.Deleted === "1") continue;
    const tid = (attrs.TID ?? "").trim();
    const pid = (attrs.PID ?? "").trim();
    const ep = Number((attrs.Count ?? "").trim());
    const stTimeSeconds = parseJstCompactTimestamp(attrs.StTime ?? "");
    if (!tid || !pid || stTimeSeconds === null) continue;
    if (!Number.isInteger(ep) || ep <= 0 || ep > 99_999) continue;
    items.push({
      tid,
      pid,
      episode: ep,
      stTimeSeconds,
      title: attrs.Title?.trim() || undefined,
    });
  }

  return items;
}

export function parseSyoboiTitleMedium(body: unknown): Map<string, SyoboiTitleMeta> {
  const out = new Map<string, SyoboiTitleMeta>();
  if (!body || typeof body !== "object") return out;
  const titles = (body as { Titles?: unknown }).Titles;
  if (!titles || typeof titles !== "object") return out;

  for (const [tidKey, raw] of Object.entries(titles as Record<string, unknown>)) {
    if (!raw || typeof raw !== "object") continue;
    const r = raw as Record<string, unknown>;
    const tid = String(r.TID ?? tidKey).trim();
    if (!tid) continue;
    const yearRaw = Number(r.FirstYear);
    out.set(tid, {
      tid,
      title: typeof r.Title === "string" && r.Title.trim() ? r.Title.trim() : null,
      titleEn: typeof r.TitleEN === "string" && r.TitleEN.trim() ? r.TitleEN.trim() : null,
      titleYomi: typeof r.TitleYomi === "string" && r.TitleYomi.trim() ? r.TitleYomi.trim() : null,
      firstYear: Number.isInteger(yearRaw) && yearRaw > 1950 ? yearRaw : null,
    });
  }
  return out;
}

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
  return `${SYOBOI_JSON_ENDPOINT}?${params.toString()}`;
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

function expandSyoboiCandidateTitles(values: (string | null | undefined)[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  const push = (s: string | null | undefined) => {
    const trimmed = (s ?? "").trim();
    if (!trimmed || seen.has(trimmed)) return;
    seen.add(trimmed);
    out.push(trimmed);
    const strippedYear = trimmed.replace(/\s*\(\d{4}\)$/, "").trim();
    if (strippedYear && strippedYear !== trimmed && !seen.has(strippedYear)) {
      seen.add(strippedYear);
      out.push(strippedYear);
    }
  };
  for (const v of values) push(v);
  return out;
}

type AnimeCandidate = {
  id: number;
  title_english?: string | null;
  title_romaji?: string | null;
  title_native?: string | null;
  title_synonyms?: string[] | null;
  start_date_year?: number | null;
  status?: string | null;
};

function scoreSyoboiCandidate(titles: string[], firstYear: number | null, cand: AnimeCandidate): number {
  const syoboiNorms = new Set(titles.map(normaliseTitle).filter(Boolean));
  const candTitles = [
    cand.title_native,
    cand.title_english,
    cand.title_romaji,
    ...(Array.isArray(cand.title_synonyms) ? cand.title_synonyms : []),
  ]
    .map((t) => (typeof t === "string" ? normaliseTitle(t) : ""))
    .filter(Boolean);

  const exactHit = candTitles.some((t) => syoboiNorms.has(t));
  if (!exactHit) return 0;

  let score = 0.96;
  if (firstYear !== null && typeof cand.start_date_year === "number") {
    const diff = Math.abs(cand.start_date_year - firstYear);
    if (diff > 1) score *= 0.5;
    else if (diff === 0) score = 1.0;
  }
  return score;
}

// deno-lint-ignore no-explicit-any
async function autoDiscoverSyoboiLinks(
  supabase: any,
  calItems: SyoboiProgItem[],
  tidToAnimeIds: Map<string, number[]>,
  opts: SyoboiOptions,
  fetchFn: typeof fetch,
  nowFn: () => number,
  observedAt: string,
): Promise<{ linked: number; stoppedEarly: string | null }> {
  const titleHintByTid = new Map<string, string>();
  for (const item of calItems) {
    if (!tidToAnimeIds.has(item.tid) && item.title && !titleHintByTid.has(item.tid)) {
      titleHintByTid.set(item.tid, item.title);
    }
  }
  const maxDiscover = Math.max(1, Math.min(200, opts.maxDiscoverTids ?? 120));
  const unknownTids = [...titleHintByTid.keys()].slice(0, maxDiscover);
  if (unknownTids.length === 0) return { linked: 0, stoppedEarly: null };

  const metaByTid = new Map<string, SyoboiTitleMeta>();
  for (let i = 0; i < unknownTids.length; i += SYOBOI_TITLE_BATCH) {
    if (nowFn() >= opts.deadlineMs) return { linked: 0, stoppedEarly: "deadline" };
    const batch = unknownTids.slice(i, i + SYOBOI_TITLE_BATCH);
    const params = new URLSearchParams({ Req: "TitleMedium", TID: batch.join(",") });
    const res = await fetchFn(`${SYOBOI_JSON_ENDPOINT}?${params.toString()}`, {
      headers: { Accept: "application/json" },
    });
    if (res.status === 429) return { linked: 0, stoppedEarly: "rate_limited" };
    if (!res.ok) throw new Error(`syoboi TitleMedium failed with HTTP ${res.status}`);
    const bodyText = await readBounded(res, 2 * 1024 * 1024);
    const parsedMeta = parseSyoboiTitleMedium(bodyText ? JSON.parse(bodyText) : {});
    for (const [k, v] of parsedMeta) metaByTid.set(k, v);
  }

  let linked = 0;
  const acceptedToInsert: Record<string, unknown>[] = [];
  const usedAnimeIds = new Set<number>([...tidToAnimeIds.values()].flat());

  for (const tid of unknownTids) {
    if (nowFn() >= opts.deadlineMs) return { linked, stoppedEarly: "deadline" };
    const meta = metaByTid.get(tid);
    const rawTitles = expandSyoboiCandidateTitles([meta?.title, meta?.titleEn, titleHintByTid.get(tid)]);
    if (rawTitles.length === 0) continue;

    const firstYear = meta?.firstYear ?? null;
    const { data: candidates, error: rpcErr } = await supabase.rpc("catalogue_find_title_candidates_v1", {
      p_medium: "anime",
      p_titles: rawTitles,
      p_year_min: firstYear ? firstYear - 1 : null,
      p_year_max: firstYear ? firstYear + 1 : null,
      p_limit: 20,
    });
    if (rpcErr || !Array.isArray(candidates) || candidates.length === 0) continue;

    const candidateRows = candidates as AnimeCandidate[];
    const candidateIds = candidateRows.map((c) => Number(c.id)).filter((id) => Number.isInteger(id) && id > 0);
    if (candidateIds.length === 0) continue;

    const { data: statusRows } = await supabase
      .from("anime")
      .select("id, status")
      .in("id", candidateIds);
    const activeIds = new Set<number>(
      ((statusRows ?? []) as { id: number; status?: string | null }[])
        .filter((r) => {
          const st = String(r.status ?? "").toUpperCase();
          return st === "RELEASING" || st === "NOT_YET_RELEASED";
        })
        .map((r) => Number(r.id)),
    );

    const activeCandidates = candidateRows.filter((c) => activeIds.has(Number(c.id)));
    if (activeCandidates.length === 0) continue;

    const scored = activeCandidates
      .map((c) => ({ cand: c, score: scoreSyoboiCandidate(rawTitles, firstYear, c) }))
      .filter((x) => x.score >= 0.92 && !usedAnimeIds.has(Number(x.cand.id)))
      .sort((a, b) => b.score - a.score || Number(a.cand.id) - Number(b.cand.id));

    if (scored.length === 0) continue;
    if (scored.length > 1 && scored[1].score >= 0.8) continue;

    const kuroId = Number(scored[0].cand.id);
    usedAnimeIds.add(kuroId);
    tidToAnimeIds.set(tid, [kuroId]);
    acceptedToInsert.push({
      kind: "anime",
      kuro_id: kuroId,
      source: "syoboi",
      source_key: tid,
      method: "title_match",
      confidence: Math.round(scored[0].score * 1000) / 1000,
      status: "accepted",
      decided_at: observedAt,
    });
    linked++;
  }

  if (!opts.dryRun && acceptedToInsert.length > 0) {
    const { error: insErr } = await supabase.from("catalogue_id_links").insert(acceptedToInsert);
    if (insErr && insErr.code !== "23505") {
      for (const row of acceptedToInsert) {
        await supabase.from("catalogue_id_links").insert(row);
      }
    } else if (insErr?.code === "23505") {
      for (const row of acceptedToInsert) {
        await supabase.from("catalogue_id_links").insert(row);
      }
    }
  }

  return { linked, stoppedEarly: null };
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

  const result: SyoboiResult = {
    tids: tidToAnimeIds.size,
    discoveredTids: 0,
    linked: 0,
    programs: 0,
    events: 0,
    animePatched: 0,
    staleCleared: 0,
    stoppedEarly: null,
    sampleRows: [],
  };

  // Earliest broadcast per (animeId, episode) across channels so multi-station airings do not
  // collide or overwrite an earlier premiere instant.
  const bestByAnimeEpisode = new Map<string, { animeId: number; item: SyoboiProgItem }>();
  const calCoveredTids = new Set<string>();

  const shouldDiscover = opts.discover === true || tidToAnimeIds.size === 0;
  if (shouldDiscover) {
    if (nowFn() >= opts.deadlineMs) {
      result.stoppedEarly = "deadline";
      return result;
    }
    const calDays = Math.max(1, Math.min(14, opts.days ?? 14));
    const calRes = await fetchFn(`${SYOBOI_CAL_CHK_ENDPOINT}?days=${calDays}`, {
      headers: { Accept: "application/xml, text/xml" },
    });
    if (calRes.status === 429) {
      result.stoppedEarly = "rate_limited";
      return result;
    }
    if (!calRes.ok) {
      throw new Error(`syoboi cal_chk failed with HTTP ${calRes.status}`);
    }
    const xmlBody = await readBounded(calRes, 4 * 1024 * 1024);
    const calItems = parseSyoboiCalChkXml(xmlBody);
    const distinctCalTids = new Set(calItems.map((c) => c.tid));
    result.discoveredTids = distinctCalTids.size;

    const disc = await autoDiscoverSyoboiLinks(
      supabase,
      calItems,
      tidToAnimeIds,
      opts,
      fetchFn,
      nowFn,
      observedAt,
    );
    result.linked = disc.linked;
    if (disc.stoppedEarly) result.stoppedEarly = disc.stoppedEarly;

    result.tids = tidToAnimeIds.size;
    for (const item of calItems) {
      const animeIds = tidToAnimeIds.get(item.tid);
      if (!animeIds || animeIds.length === 0) continue;
      calCoveredTids.add(item.tid);
      result.programs++;
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

  const remainingTids = [...tidToAnimeIds.keys()].filter((t) => !calCoveredTids.has(t));
  if (remainingTids.length > 0 && !result.stoppedEarly) {
    for (let i = 0; i < remainingTids.length; i += SYOBOI_TID_BATCH) {
      if (nowFn() >= opts.deadlineMs) {
        result.stoppedEarly = "deadline";
        break;
      }
      const batch = remainingTids.slice(i, i + SYOBOI_TID_BATCH);
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

    if (opts.writeNextAiring !== false && opts.staleSweep !== false && shouldDiscover) {
      const staleCutoffIso = new Date(opts.nowMs - STALE_PAST_GRACE_MS).toISOString();
      const { data: staleRows } = await supabase
        .from("anime")
        .select("id")
        .eq("status", "RELEASING")
        .lt("next_airing_at", staleCutoffIso)
        .limit(50);
      for (const sr of (staleRows ?? []) as { id: number }[]) {
        const id = Number(sr.id);
        if (nextByAnime.has(id)) continue;
        const { error: clearErr } = await supabase
          .from("anime")
          .update({ next_episode_number: null, next_airing_at: null })
          .eq("id", id);
        if (!clearErr) result.staleCleared++;
      }
    }
  }

  return result;
}
