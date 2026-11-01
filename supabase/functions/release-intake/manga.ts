// mode 'manga': MangaUpdates (permissive AUP, credit required) release history for tracked and
// popular RELEASING manga.
//
// Mapping chain (no fuzzy matching): manga_source_links (provider 'mangadex', active) ->
// MangaDex GET /manga/{id} attributes.links.mu (base36 MangaUpdates slug) -> MU series_id
// (int(slug, 36)). The series page must echo the slug in its url before anything is trusted.
// manga_source_links only allows provider 'mangadex', so the MU id is re-derived every run.
//
// Per title (MU spacing >= 1 request/s through one limiter, Kuro User-Agent):
//   GET  /v1/series/{id}          -> latest_chapter, status ("115 Volumes (Ongoing)"), url
//   POST /v1/releases/search      {search:"<id>", search_type:"series", orderby:"date", asc:"desc"}
// Releases repeat per scanlation group: deduped by chapter number keeping the earliest date.
// Chapter strings that are not a plain number (ranges, "v.2", oneshots) are skipped, not guessed.
// Emitted rows (all with source + source_url for credit):
//   - the newest <= confirmedPastLimit dated chapters: basis confirmed, precision day
//     (source_local_date), status released once the day is over;
//   - one cadence estimate (cadence.ts) only when confidence >= 0.7 (the writer keeps one
//     estimate per title: kuro_estimate:manga:<id>:chapter:next).
// manga.volumes / manga.chapters only ever move upward (never nulled, never lowered).
// Nothing is fabricated: no MU mapping, no dates or an irregular cadence means no row.
import { isPoliteCleanStop, type PoliteClient } from "../_shared/polite_fetch.ts";
import { estimateNextChapter, isEstimate, type DatedChapter } from "./cadence.ts";
import { dayIsPast, formatUnitNumber, type ReleaseEventRow, writeReleaseEvents } from "./contract.ts";

export const MU_API = "https://api.mangaupdates.com/v1";

export type MangaDexLinkReader = (mangaDexId: string) => Promise<Record<string, string> | null>;

export type MangaOptions = {
  limit: number;
  offset: number;
  mangaIds: number[] | null;
  confirmedPastLimit: number;
  dryRun: boolean;
  deadlineMs: number;
  nowMs: number;
};

export type MangaResult = {
  candidates: number;
  processed: number;
  unmapped: number;
  noMuLink: number;
  muMismatch: number;
  events: number;
  estimates: number;
  mangaPatched: number;
  errors: number;
  stoppedEarly: string | null;
  sampleRows: ReleaseEventRow[];
};

type Candidate = { id: number; chapters: number | null; volumes: number | null };

/** MangaDex links.mu is a base36 slug (e.g. "pb8uwds" -> 55099564912). Null when not decodable. */
export function decodeMuSlug(slug: unknown): number | null {
  if (typeof slug !== "string") return null;
  const s = slug.trim().toLowerCase();
  if (!/^[0-9a-z]{1,12}$/.test(s)) return null;
  let value = 0n;
  for (const ch of s) value = value * 36n + BigInt(parseInt(ch, 36));
  if (value <= 0n || value > BigInt(Number.MAX_SAFE_INTEGER)) return null;
  return Number(value);
}

/** "115 Volumes (Ongoing)" -> 115. */
export function parseVolumeCount(status: unknown): number | null {
  if (typeof status !== "string") return null;
  const m = status.match(/(\d+)\s+Volumes?\b/i);
  if (!m) return null;
  const n = Number(m[1]);
  return Number.isInteger(n) && n > 0 && n < 10_000 ? n : null;
}

/** Plain chapter numbers only ("1196", "10.5"); ranges, prefixes and words are skipped. */
export function parseChapterNumber(raw: unknown): number | null {
  if (typeof raw !== "string" && typeof raw !== "number") return null;
  const s = String(raw).trim();
  if (!/^\d{1,5}(\.\d{1,2})?$/.test(s)) return null;
  const n = Number(s);
  return Number.isFinite(n) && n > 0 ? n : null;
}

// deno-lint-ignore no-explicit-any
export function dedupeReleases(results: any[], seriesId: number): DatedChapter[] {
  const byNumber = new Map<number, string>();
  for (const r of results) {
    const metaSeries = r?.metadata?.series?.series_id;
    if (metaSeries != null && Number(metaSeries) !== seriesId) continue;
    const record = r?.record ?? r;
    const number = parseChapterNumber(record?.chapter);
    const date = typeof record?.release_date === "string" ? record.release_date.trim() : "";
    if (number === null || !/^\d{4}-\d{2}-\d{2}$/.test(date)) continue;
    const prior = byNumber.get(number);
    if (!prior || date < prior) byNumber.set(number, date);
  }
  return [...byNumber.entries()].map(([number, date]) => ({ number, date })).sort((a, b) => b.number - a.number);
}

// deno-lint-ignore no-explicit-any
async function loadCandidates(supabase: any, opts: MangaOptions): Promise<Candidate[]> {
  if (opts.mangaIds && opts.mangaIds.length > 0) {
    const { data, error } = await supabase.from("manga").select("id, chapters, volumes").in("id", opts.mangaIds);
    if (error) throw new Error(`manga lookup failed: ${error.message ?? error}`);
    return (data ?? []) as Candidate[];
  }
  // Tracked first (titles people read now or plan to), then popular RELEASING titles.
  const { data: tracked, error: trackedError } = await supabase
    .from("manga_user_lists")
    .select("manga_id")
    .in("list_type", ["READING", "WATCHING", "PLANNING", "PAUSED"])
    .limit(2000);
  if (trackedError) throw new Error(`tracked manga lookup failed: ${trackedError.message ?? trackedError}`);
  const counts = new Map<number, number>();
  for (const r of (tracked ?? []) as { manga_id: number }[]) counts.set(Number(r.manga_id), (counts.get(Number(r.manga_id)) ?? 0) + 1);
  const trackedIds = [...counts.entries()].sort((a, b) => b[1] - a[1]).map(([id]) => id).slice(0, 500);

  const rows: Candidate[] = [];
  if (trackedIds.length > 0) {
    const { data, error } = await supabase.from("manga").select("id, chapters, volumes, status").in("id", trackedIds).eq("status", "RELEASING");
    if (error) throw new Error(`manga lookup failed: ${error.message ?? error}`);
    const byId = new Map<number, Candidate>(((data ?? []) as Candidate[]).map((r) => [Number(r.id), r]));
    for (const id of trackedIds) {
      const row = byId.get(id);
      if (row) rows.push(row);
    }
  }
  const { data: popular, error: popularError } = await supabase
    .from("manga")
    .select("id, chapters, volumes")
    .eq("status", "RELEASING")
    .order("popularity", { ascending: false })
    .limit(200);
  if (popularError) throw new Error(`popular manga lookup failed: ${popularError.message ?? popularError}`);
  const seen = new Set(rows.map((r) => r.id));
  for (const r of (popular ?? []) as Candidate[]) {
    if (!seen.has(Number(r.id))) {
      seen.add(Number(r.id));
      rows.push(r);
    }
  }
  return rows;
}

// deno-lint-ignore no-explicit-any
async function mangaDexIds(supabase: any, mangaIds: number[]): Promise<Map<number, string>> {
  const map = new Map<number, string>();
  if (mangaIds.length === 0) return map;
  const { data, error } = await supabase
    .from("manga_source_links")
    .select("manga_id, provider_media_id")
    .eq("provider", "mangadex")
    .eq("status", "active")
    .in("manga_id", mangaIds);
  if (error) throw new Error(`manga_source_links lookup failed: ${error.message ?? error}`);
  for (const r of (data ?? []) as { manga_id: number; provider_media_id: string }[]) map.set(Number(r.manga_id), String(r.provider_media_id));
  return map;
}

export async function runMangaReleases(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  mu: PoliteClient,
  readMangaDexLinks: MangaDexLinkReader,
  opts: MangaOptions,
): Promise<MangaResult> {
  const result: MangaResult = {
    candidates: 0,
    processed: 0,
    unmapped: 0,
    noMuLink: 0,
    muMismatch: 0,
    events: 0,
    estimates: 0,
    mangaPatched: 0,
    errors: 0,
    stoppedEarly: null,
    sampleRows: [],
  };
  const observedAt = new Date(opts.nowMs).toISOString();
  const all = await loadCandidates(supabase, opts);
  result.candidates = all.length;
  if (all.length === 0) return result;
  // Stateless rotation: each run takes the next `limit` titles (offset wraps).
  const start = opts.mangaIds ? 0 : ((opts.offset % all.length) + all.length) % all.length;
  const batch: Candidate[] = [];
  for (let i = 0; i < Math.min(opts.limit, all.length); i++) batch.push(all[(start + i) % all.length]);
  const dexIds = await mangaDexIds(supabase, batch.map((c) => c.id));

  for (const candidate of batch) {
    const dexId = dexIds.get(candidate.id);
    if (!dexId) {
      result.unmapped++;
      continue;
    }
    try {
      const links = await readMangaDexLinks(dexId);
      const slug = links?.mu;
      const seriesId = decodeMuSlug(slug);
      if (seriesId === null) {
        result.noMuLink++;
        continue;
      }
      const series = await mu.request(`${MU_API}/series/${seriesId}`, { method: "GET" }, opts.deadlineMs);
      // deno-lint-ignore no-explicit-any
      const s = series.json as any;
      const url = typeof s?.url === "string" ? s.url : "";
      if (series.status !== 200 || Number(s?.series_id) !== seriesId || !url.toLowerCase().includes(`/series/${String(slug).toLowerCase()}`)) {
        result.muMismatch++;
        continue;
      }
      const releases = await mu.request(`${MU_API}/releases/search`, {
        method: "POST",
        body: { search: String(seriesId), search_type: "series", orderby: "date", asc: "desc", perpage: 40 },
      }, opts.deadlineMs);
      if (releases.status !== 200) throw new Error(`MangaUpdates releases ${releases.status}`);
      // deno-lint-ignore no-explicit-any
      const dated = dedupeReleases(Array.isArray((releases.json as any)?.results) ? (releases.json as any).results : [], seriesId);

      const rows: ReleaseEventRow[] = [];
      for (const c of dated.slice(0, Math.max(0, opts.confirmedPastLimit))) {
        rows.push({
          medium: "manga",
          media_id: candidate.id,
          unit_kind: "chapter",
          unit_number: c.number,
          unit_label: `Ch. ${formatUnitNumber(c.number)}`,
          precision: "day",
          source_local_date: c.date,
          status: dayIsPast(c.date, opts.nowMs) ? "released" : "scheduled",
          basis: "confirmed",
          confidence: 1,
          source: "mangaupdates",
          source_url: url,
          observed_at: observedAt,
          external_id: `series:${seriesId}`,
        });
      }
      const estimate = estimateNextChapter(dated, opts.nowMs);
      if (isEstimate(estimate)) {
        rows.push({
          medium: "manga",
          media_id: candidate.id,
          unit_kind: "chapter",
          unit_number: estimate.nextNumber,
          unit_label: `Ch. ${estimate.nextNumber}`,
          precision: "day",
          source_local_date: estimate.nextDate,
          status: "scheduled",
          basis: "estimated",
          confidence: estimate.confidence,
          source: "kuro_estimate",
          source_url: url,
          observed_at: observedAt,
          external_id: `series:${seriesId}`,
        });
        result.estimates++;
      }
      if (!opts.dryRun) await writeReleaseEvents(supabase, rows);
      result.events += rows.length;
      if (result.sampleRows.length < 5) result.sampleRows.push(...rows.slice(0, 5 - result.sampleRows.length));

      // Counts only move upward.
      const patch: Record<string, number> = {};
      const volumes = parseVolumeCount(s?.status);
      if (volumes !== null && (candidate.volumes == null || volumes > Number(candidate.volumes))) patch.volumes = volumes;
      const latest = parseChapterNumber(s?.latest_chapter);
      if (latest !== null && Number.isInteger(latest) && (candidate.chapters == null || latest > Number(candidate.chapters))) patch.chapters = latest;
      if (Object.keys(patch).length > 0) {
        if (!opts.dryRun) {
          const { error } = await supabase.from("manga").update(patch).eq("id", candidate.id);
          if (error) throw new Error(`manga count update failed: ${error.message ?? error}`);
        }
        result.mangaPatched++;
      }
      result.processed++;
    } catch (e) {
      if (isPoliteCleanStop(e) || (e instanceof Error && e.message === "Time budget reached")) {
        result.stoppedEarly = isPoliteCleanStop(e) ? (e as { kind: string }).kind : "budget";
        break;
      }
      // The writer RPC failing is systemic (missing function, bad contract): fail the run.
      if (e instanceof Error && e.message.startsWith("upsert_release_events_v1 failed")) throw e;
      console.error("release-intake manga item failed:", candidate.id, e instanceof Error ? e.message : e);
      result.errors++;
    }
  }
  return result;
}
