// Offline run tests for release-intake: fake AniList / MangaUpdates fetch, fake MangaDex link
// reader, and the shared query fake for supabase-js. No network, no database.
// Response shapes follow the live samples recorded in
// docs/overnight-2026-11-01/understand/sources.md (AniList airingSchedules, MangaUpdates
// series + releases/search) and the MangaUpdates OpenAPI (ReleaseSearchResponseV1).
// Run: deno test --no-prompt supabase/functions/release-intake/
import { strict as assert } from "node:assert";
import { AniListLimiter, createAniListClient } from "../_shared/anilist_client.ts";
import { createPoliteClient, PoliteLimiter } from "../_shared/polite_fetch.ts";
import { queryFake } from "../_shared/test_query_fake.ts";
import { run } from "./handler.ts";
import { decodeMuSlug, dedupeReleases, parseChapterNumber, parseVolumeCount } from "./manga.ts";
import type { ReleaseEventRow } from "./contract.ts";

const NOW = Date.parse("2026-11-01T10:00:00Z");
const NOW_S = Math.floor(NOW / 1000);

type Reply = { status?: number; body?: unknown; headers?: Record<string, string> };

function fakeFetch(replies: Reply[], seen: { url: string; body: unknown; headers: Headers }[]) {
  return (input: string | URL | Request, init?: RequestInit) => {
    seen.push({ url: String(input), body: init?.body ? JSON.parse(String(init.body)) : null, headers: new Headers(init?.headers) });
    const reply = replies.shift();
    if (!reply) return Promise.reject(new Error(`unexpected request ${String(input)}`));
    return Promise.resolve(new Response(JSON.stringify(reply.body ?? {}), {
      status: reply.status ?? 200,
      headers: { "Content-Type": "application/json", ...(reply.headers ?? {}) },
    }));
  };
}

function clients(anilistReplies: Reply[], muReplies: Reply[] = []) {
  const anilistSeen: { url: string; body: unknown; headers: Headers }[] = [];
  const muSeen: { url: string; body: unknown; headers: Headers }[] = [];
  let clock = NOW;
  const sleep = (ms: number) => {
    clock += ms;
    return Promise.resolve();
  };
  return {
    anilistSeen,
    muSeen,
    anilist: createAniListClient({ limiter: new AniListLimiter(0), sleep, now: () => clock, random: () => 0, fetch: fakeFetch(anilistReplies, anilistSeen) }),
    mangaUpdates: createPoliteClient({ limiter: new PoliteLimiter(1_000), sleep, now: () => clock, random: () => 0, fetch: fakeFetch(muReplies, muSeen) }),
    now: () => NOW,
  };
}

function lockRpc(state: { held: Set<string> }) {
  return {
    acquire_import_lock: (args: Record<string, unknown>) => {
      const key = String(args.p_key);
      if (state.held.has(key)) return { data: false, error: null };
      state.held.add(key);
      return { data: true, error: null };
    },
    release_import_lock: (args: Record<string, unknown>) => {
      state.held.delete(String(args.p_key));
      return { data: null, error: null };
    },
  };
}

function writtenRows(fake: ReturnType<typeof queryFake>): ReleaseEventRow[] {
  return fake.rpcCalls("upsert_release_events_v1").flatMap((a) => a.p_rows as ReleaseEventRow[]);
}

// ---------------------------------------------------------------------------
// airing
// ---------------------------------------------------------------------------

function airingPage(rows: unknown[], hasNextPage: boolean) {
  return { body: { data: { Page: { pageInfo: { hasNextPage }, airingSchedules: rows } } } };
}

Deno.test("airing: window rows become confirmed events and next_* is patched only when it changed", async () => {
  const locks = { held: new Set<string>() };
  const fake = queryFake({
    tables: {
      anime: [
        { id: 10, anilist_id: 966, status: "RELEASING", next_episode_number: 1308, next_airing_at: new Date((NOW_S - 3600) * 1000).toISOString() },
        { id: 11, anilist_id: 21, status: "RELEASING", next_episode_number: 1181, next_airing_at: new Date((NOW_S + 86400) * 1000).toISOString() },
      ],
    },
    rpc: lockRpc(locks),
  });
  const c = clients([
    airingPage([
      { id: 409393, airingAt: NOW_S - 3600, episode: 1308, mediaId: 966, media: { id: 966, status: "RELEASING", nextAiringEpisode: { episode: 1309, airingAt: NOW_S + 7 * 86400 - 3600 } } },
      { id: 405411, airingAt: NOW_S - 1800, episode: 18, mediaId: 188653, media: { id: 188653, status: "FINISHED", nextAiringEpisode: null } },
    ], true),
    airingPage([
      { id: 500001, airingAt: NOW_S + 86400, episode: 1181, mediaId: 21, media: { id: 21, status: "RELEASING", nextAiringEpisode: { episode: 1181, airingAt: NOW_S + 86400 } } },
    ], false),
  ]);
  const res = await run({ mode: "airing", staleSweep: false }, { supabase: fake.client, ...c, readMangaDexLinks: () => Promise.resolve(null) });
  const out = await res.json();
  assert.equal(res.status, 200, JSON.stringify(out));
  assert.equal(out.results.pages, 2);
  assert.equal(out.results.unknownMedia, 1);
  assert.deepEqual(out.results.unknownSample, [188653]);

  const rows = writtenRows(fake);
  assert.equal(rows.length, 2);
  const past = rows.find((r) => r.source_identity === "anilist:airing:409393");
  assert.ok(past);
  assert.deepEqual(
    { medium: past.medium, media_id: past.media_id, unit_kind: past.unit_kind, unit_number: past.unit_number, unit_label: past.unit_label, basis: past.basis, precision: past.precision, is_past: past.is_past, source: past.source, source_url: past.source_url, confidence: past.confidence },
    { medium: "anime", media_id: 10, unit_kind: "episode", unit_number: 1308, unit_label: "Ep. 1308", basis: "confirmed", precision: "instant", is_past: true, source: "anilist", source_url: "https://anilist.co/anime/966", confidence: 1 },
  );
  assert.equal(rows.find((r) => r.source_identity === "anilist:airing:500001")?.is_past, false);

  // Title 966 moved to episode 1309; title 21 was already current, so it gets no write.
  const updates = fake.calls.filter((call) => call.kind === "update" && call.table === "anime");
  assert.equal(updates.length, 1);
  assert.equal(fake.tables.anime[0].next_episode_number, 1309);
  assert.equal(out.results.animePatched, 1);

  // The window query: [now-6h, now+8d], perPage 50, sort TIME, Kuro User-Agent.
  const vars = (c.anilistSeen[0].body as { variables: Record<string, number> }).variables;
  assert.equal(vars.from, NOW_S - 6 * 3600);
  assert.equal(vars.to, NOW_S + 8 * 86400);
  assert.equal(vars.perPage, 50);
  assert.match(c.anilistSeen[0].headers.get("user-agent") ?? "", /^Kuro-Intake\//);
  assert.equal(locks.held.size, 0);
  assert.equal(fake.tables.import_runs?.[0]?.status, "success");
});

Deno.test("airing: a GraphQL error fails the run, writes nothing and releases the lock", async () => {
  const locks = { held: new Set<string>() };
  const fake = queryFake({ tables: { anime: [] }, rpc: lockRpc(locks) });
  const c = clients([{ body: { data: null, errors: [{ message: "boom" }] } }]);
  const res = await run({ mode: "airing" }, { supabase: fake.client, ...c, readMangaDexLinks: () => Promise.resolve(null) });
  assert.equal(res.status, 500);
  assert.equal(writtenRows(fake).length, 0);
  assert.equal(locks.held.size, 0);
  assert.equal(fake.tables.import_runs?.[0]?.status, "error");
});

Deno.test("airing: the stale sweep re-reads past next_airing_at titles and nulls a finished one", async () => {
  const locks = { held: new Set<string>() };
  const stalePast = new Date((NOW_S - 3 * 86400) * 1000).toISOString();
  const fake = queryFake({
    tables: {
      anime: [
        { id: 20, anilist_id: 3001, status: "RELEASING", popularity: 9, next_episode_number: 4, next_airing_at: stalePast },
        { id: 21, anilist_id: 3002, status: "RELEASING", popularity: 8, next_episode_number: 12, next_airing_at: stalePast },
      ],
    },
    rpc: lockRpc(locks),
  });
  const c = clients([
    airingPage([], false),
    { body: { data: { Page: { media: [
      { id: 3001, status: "RELEASING", nextAiringEpisode: { id: 777, episode: 5, airingAt: NOW_S + 10 * 86400 } },
      { id: 3002, status: "FINISHED", nextAiringEpisode: null },
    ] } } } },
  ]);
  const res = await run({ mode: "airing" }, { supabase: fake.client, ...c, readMangaDexLinks: () => Promise.resolve(null) });
  const out = await res.json();
  assert.equal(res.status, 200, JSON.stringify(out));
  assert.equal(out.results.stalePatched, 2);
  assert.equal(fake.tables.anime[0].next_episode_number, 5);
  assert.equal(fake.tables.anime[1].next_episode_number, null);
  assert.equal(fake.tables.anime[1].next_airing_at, null);
  const rows = writtenRows(fake);
  assert.deepEqual(rows.map((r) => r.source_identity), ["anilist:airing:777"]);
  assert.deepEqual((c.anilistSeen[1].body as { variables: { ids: number[] } }).variables.ids, [3001, 3002]);
});

Deno.test("airing: dryRun reads and samples rows but writes nothing", async () => {
  const locks = { held: new Set<string>() };
  const fake = queryFake({ tables: { anime: [{ id: 10, anilist_id: 966, next_episode_number: null, next_airing_at: null }] }, rpc: lockRpc(locks) });
  const c = clients([airingPage([{ id: 1, airingAt: NOW_S + 60, episode: 3, mediaId: 966, media: { id: 966, nextAiringEpisode: { episode: 3, airingAt: NOW_S + 60 } } }], false)]);
  const res = await run({ mode: "airing", dryRun: true, staleSweep: false }, { supabase: fake.client, ...c, readMangaDexLinks: () => Promise.resolve(null) });
  const out = await res.json();
  assert.equal(out.sampleRows.length, 1);
  assert.equal(writtenRows(fake).length, 0);
  assert.equal(fake.calls.filter((call) => call.kind === "update").length, 0);
  assert.equal(fake.tables.import_runs, undefined);
});

Deno.test("airing: a busy lock skips without reading the provider", async () => {
  const locks = { held: new Set<string>(["release-intake:airing"]) };
  const fake = queryFake({ rpc: lockRpc(locks) });
  const c = clients([]);
  const res = await run({ mode: "airing" }, { supabase: fake.client, ...c, readMangaDexLinks: () => Promise.resolve(null) });
  const out = await res.json();
  assert.equal(out.reason, "locked");
  assert.equal(c.anilistSeen.length, 0);
  assert.ok(locks.held.has("release-intake:airing"), "a skipped run must not release someone else's lock");
});

Deno.test("an unknown mode is rejected before any work", async () => {
  const fake = queryFake({});
  const res = await run({ mode: "everything" }, { supabase: fake.client, ...clients([]), readMangaDexLinks: () => Promise.resolve(null) });
  assert.equal(res.status, 400);
  assert.equal(fake.calls.length, 0);
});

// ---------------------------------------------------------------------------
// manga (MangaUpdates)
// ---------------------------------------------------------------------------

const ONE_PIECE_SERIES = {
  series_id: 55099564912,
  title: "One Piece",
  url: "https://www.mangaupdates.com/series/pb8uwds/one-piece",
  latest_chapter: 1196,
  status: "115 Volumes (Ongoing)",
  completed: false,
};

function weeklyReleases(lastDate: string, count: number, lastChapter: number) {
  const results = [];
  let t = Date.parse(`${lastDate}T00:00:00Z`);
  for (let i = 0; i < count; i++) {
    const date = new Date(t).toISOString().slice(0, 10);
    const chapter = String(lastChapter - i);
    // Two groups release the same chapter; the later duplicate must not win.
    results.push({ record: { id: i * 2, chapter, volume: null, release_date: date, groups: [{ name: "MANGA Plus" }] }, metadata: { series: { series_id: 55099564912 } } });
    results.push({ record: { id: i * 2 + 1, chapter, volume: null, release_date: new Date(t + 86_400_000).toISOString().slice(0, 10), groups: [{ name: "Viz" }] }, metadata: { series: { series_id: 55099564912 } } });
    t -= 7 * 86_400_000;
  }
  return { total_hits: count * 2, page: 1, per_page: 40, results };
}

function mangaFake(extra: Record<string, unknown[]> = {}) {
  const locks = { held: new Set<string>() };
  const fake = queryFake({
    tables: {
      manga: [{ id: 5, status: "RELEASING", popularity: 100, chapters: 1190, volumes: null }],
      manga_user_lists: [{ manga_id: 5, list_type: "READING" }],
      manga_source_links: [{ manga_id: 5, provider: "mangadex", status: "active", provider_media_id: "a1c7c817-4e59-43b7-9365-09675a149a6f" }],
      ...extra,
    },
    rpc: lockRpc(locks),
  });
  return { fake, locks };
}

Deno.test("manga: MangaUpdates history becomes confirmed chapter rows plus one credited estimate", async () => {
  const { fake, locks } = mangaFake();
  const c = clients([], [{ body: ONE_PIECE_SERIES }, { body: weeklyReleases("2026-10-25", 10, 1196) }]);
  const dexIds: string[] = [];
  const res = await run({ mode: "manga" }, {
    supabase: fake.client,
    ...c,
    readMangaDexLinks: (id) => {
      dexIds.push(id);
      return Promise.resolve({ al: "30013", mu: "pb8uwds" });
    },
  });
  const out = await res.json();
  assert.equal(res.status, 200, JSON.stringify(out));
  assert.deepEqual(dexIds, ["a1c7c817-4e59-43b7-9365-09675a149a6f"]);
  assert.equal(out.results.processed, 1);
  assert.equal(out.results.estimates, 1);

  // Request shapes (sources.md, MU OpenAPI): GET series/{id}; POST releases/search by series id.
  assert.equal(c.muSeen[0].url, "https://api.mangaupdates.com/v1/series/55099564912");
  assert.equal(c.muSeen[1].url, "https://api.mangaupdates.com/v1/releases/search");
  assert.deepEqual(c.muSeen[1].body, { search: "55099564912", search_type: "series", orderby: "date", asc: "desc", perpage: 40 });
  assert.match(c.muSeen[0].headers.get("user-agent") ?? "", /^Kuro-Intake\//);

  const rows = writtenRows(fake);
  const confirmed = rows.filter((r) => r.basis === "confirmed");
  assert.equal(confirmed.length, 10);
  assert.deepEqual(confirmed[0], {
    medium: "manga",
    media_id: 5,
    unit_kind: "chapter",
    unit_number: 1196,
    unit_label: "Ch. 1196",
    release_at: "2026-10-25T12:00:00.000Z",
    precision: "day",
    basis: "confirmed",
    confidence: 1,
    is_past: true,
    source: "mangaupdates",
    source_url: "https://www.mangaupdates.com/series/pb8uwds/one-piece",
    observed_at: new Date(NOW).toISOString(),
    source_identity: "mangaupdates:55099564912:ch:1196",
  });
  const estimate = rows.find((r) => r.basis === "estimated");
  assert.ok(estimate);
  assert.equal(estimate.unit_number, 1197);
  assert.equal(estimate.release_at, "2026-11-01T12:00:00.000Z");
  assert.equal(estimate.source, "kuro_estimate");
  assert.equal(estimate.source_url, ONE_PIECE_SERIES.url);
  assert.ok(estimate.confidence >= 0.7);
  assert.equal(estimate.source_identity, "kuro_estimate:manga:5:next");

  // Counts move upward only: volumes from MU status, chapters 1190 -> 1196.
  assert.equal(fake.tables.manga[0].volumes, 115);
  assert.equal(fake.tables.manga[0].chapters, 1196);
  assert.equal(locks.held.size, 0);
});

Deno.test("manga: an irregular history emits confirmed rows but no estimate", async () => {
  const { fake } = mangaFake();
  const irregular = {
    results: ["2026-10-28", "2026-10-21", "2026-10-02", "2026-09-29", "2026-09-05", "2026-08-30", "2026-08-02"].map((date, i) => ({
      record: { chapter: String(60 - i), release_date: date },
      metadata: { series: { series_id: 55099564912 } },
    })),
  };
  const c = clients([], [{ body: ONE_PIECE_SERIES }, { body: irregular }]);
  const res = await run({ mode: "manga" }, { supabase: fake.client, ...c, readMangaDexLinks: () => Promise.resolve({ mu: "pb8uwds" }) });
  assert.equal(res.status, 200);
  const rows = writtenRows(fake);
  assert.equal(rows.filter((r) => r.basis === "estimated").length, 0);
  assert.equal(rows.length, 7);
});

Deno.test("manga: a series page that does not echo the slug is not trusted", async () => {
  const { fake } = mangaFake();
  const c = clients([], [{ body: { ...ONE_PIECE_SERIES, url: "https://www.mangaupdates.com/series/zzzzzz/other" } }]);
  const res = await run({ mode: "manga" }, { supabase: fake.client, ...c, readMangaDexLinks: () => Promise.resolve({ mu: "pb8uwds" }) });
  const out = await res.json();
  assert.equal(out.results.muMismatch, 1);
  assert.equal(writtenRows(fake).length, 0);
  assert.equal(c.muSeen.length, 1, "no release search for an untrusted mapping");
});

Deno.test("manga: titles without a MangaDex mapping or MU link make no requests", async () => {
  const { fake } = mangaFake({ manga_source_links: [] });
  const c = clients([], []);
  const res = await run({ mode: "manga" }, { supabase: fake.client, ...c, readMangaDexLinks: () => Promise.resolve(null) });
  const out = await res.json();
  assert.equal(out.results.unmapped, 1);
  assert.equal(c.muSeen.length, 0);

  const second = mangaFake();
  const c2 = clients([], []);
  const res2 = await run({ mode: "manga" }, { supabase: second.fake.client, ...c2, readMangaDexLinks: () => Promise.resolve({ al: "1" }) });
  assert.equal((await res2.json()).results.noMuLink, 1);
  assert.equal(c2.muSeen.length, 0);
});

Deno.test("manga: MangaUpdates requests are spaced at least 1 s apart", async () => {
  const { fake } = mangaFake();
  let clock = NOW;
  const stamps: number[] = [];
  const muReplies: Reply[] = [{ body: ONE_PIECE_SERIES }, { body: weeklyReleases("2026-10-25", 6, 1196) }];
  const mangaUpdates = createPoliteClient({
    limiter: new PoliteLimiter(1_000),
    now: () => clock,
    sleep: (ms) => {
      clock += ms;
      return Promise.resolve();
    },
    random: () => 0,
    fetch: (input, init) => {
      stamps.push(clock);
      return fakeFetch(muReplies, [])(input as string, init);
    },
  });
  await run({ mode: "manga" }, { supabase: fake.client, ...clients([]), mangaUpdates, readMangaDexLinks: () => Promise.resolve({ mu: "pb8uwds" }) });
  assert.equal(stamps.length, 2);
  assert.ok(stamps[1] - stamps[0] >= 1_000);
});

Deno.test("manga: a writer RPC failure fails the run (systemic), the lock is released", async () => {
  const locks = { held: new Set<string>() };
  const fake = queryFake({
    tables: {
      manga: [{ id: 5, status: "RELEASING", popularity: 1, chapters: 1, volumes: 1 }],
      manga_user_lists: [],
      manga_source_links: [{ manga_id: 5, provider: "mangadex", status: "active", provider_media_id: "x" }],
    },
    rpc: { ...lockRpc(locks), upsert_release_events_v1: { data: null, error: { message: "Could not find the function", code: "PGRST202" } } },
  });
  const c = clients([], [{ body: ONE_PIECE_SERIES }, { body: weeklyReleases("2026-10-25", 6, 1196) }]);
  const res = await run({ mode: "manga" }, { supabase: fake.client, ...c, readMangaDexLinks: () => Promise.resolve({ mu: "pb8uwds" }) });
  assert.equal(res.status, 500);
  assert.equal(locks.held.size, 0);
});

// ---------------------------------------------------------------------------
// pure helpers
// ---------------------------------------------------------------------------

Deno.test("MangaUpdates helpers: base36 slug, volume count, plain chapter numbers, per-group dedupe", () => {
  assert.equal(decodeMuSlug("pb8uwds"), 55099564912);
  assert.equal(decodeMuSlug("PB8UWDS"), 55099564912);
  assert.equal(decodeMuSlug("not a slug"), null);
  assert.equal(decodeMuSlug(undefined), null);
  assert.equal(parseVolumeCount("115 Volumes (Ongoing)"), 115);
  assert.equal(parseVolumeCount("1 Volume (Complete)"), 1);
  assert.equal(parseVolumeCount("Ongoing"), null);
  assert.equal(parseChapterNumber("1196"), 1196);
  assert.equal(parseChapterNumber("10.5"), 10.5);
  assert.equal(parseChapterNumber("1195-1196"), null);
  assert.equal(parseChapterNumber("v.2 c.10"), null);
  assert.equal(parseChapterNumber("Oneshot"), null);
  const deduped = dedupeReleases([
    { record: { chapter: "7", release_date: "2026-10-12" } },
    { record: { chapter: "7", release_date: "2026-10-10" } },
    { record: { chapter: "8", release_date: "2026-10-17" }, metadata: { series: { series_id: 999 } } },
  ], 1);
  assert.deepEqual(deduped, [{ number: 7, date: "2026-10-10" }]);
});
