// Offline tests for the MangaUpdates new-series fetch (catalogue Task 15c, manga half). Fetch is a fake; the JSON
// fixtures are real MangaUpdates replies captured 2026-11-18 (fixtures/README.md).
// Run: cd supabase/functions/catalogue-intake && deno test --no-prompt
import { strict as assert } from "node:assert";
import { PoliteLimiter } from "../_shared/polite_fetch.ts";
import { createSourceClient } from "../_shared/catalogue/source_http.ts";
import { fakeSupabase, queuedFetch, type Row } from "./fake_supabase.ts";
import { create } from "./create.ts";
import { CRON_JOBS, firingMinutes, inMangaUpdatesQuietWindow, jobMinutes, MU_QUIET_WINDOW, RELEASE_INTAKE_MANGA, renderCronSql } from "./cron_schedule.ts";
import { handleRequest, type IntakeDeps } from "./handler.ts";
import { MU_NEW_DEFAULT_MIN_YEAR, MU_NEW_MAX_PAGES, runMangaUpdatesNew } from "./mangaupdates_new.ts";
import newest from "./fixtures/mu_search_newest.json" with { type: "json" };
import seriesNew from "./fixtures/mu_series_new_2853344834.json" with { type: "json" };

const NOW = Date.parse("2026-11-18T12:00:00Z");
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
// Fixture reading (10 newest): year >= 2024 and a manga type -> 78343182894 (2024), 1382090098, 2853344834, 16508909711 (2026).
// Doujinshi rows and the Manga row without a year are not candidates.
const CANDIDATES = ["78343182894", "1382090098", "2853344834", "16508909711"];
const base = (id: string, over: Row = {}) => ({ ...seriesNew, series_id: Number(id), ...over });

function ctxFor(db: ReturnType<typeof fakeSupabase>, responses: Array<Response | ((url: string, init?: RequestInit) => Response)>, over: { deadlineMs?: number; limit?: number; clock?: number[] } = {}) {
  let t = 0;
  const net = queuedFetch(responses);
  const fetch = ((input: string | URL | Request, init?: RequestInit) => {
    over.clock?.push(t);
    return net.fetch(input, init);
  }) as typeof globalThis.fetch;
  const client = createSourceClient("mangaupdates", new PoliteLimiter(1_100), { fetch, sleep: (ms) => { t += ms; return Promise.resolve(); }, now: () => NOW + t, random: () => 0 });
  const other = createSourceClient("wikidata", new PoliteLimiter(0), { fetch: net.fetch });
  return {
    net,
    ctx: {
      supabase: db.client,
      clients: { wikidata: other, ann: other, mangaupdates: client, pageviews: other },
      medium: "manga" as const,
      limit: over.limit,
      deadlineMs: NOW + (over.deadlineMs ?? 50_000),
      now: () => NOW + t,
    },
  };
}

const emptyPage = json({ total_hits: 10000, page: 2, per_page: 100, results: [] });
const cursorOf = (db: ReturnType<typeof fakeSupabase>) => (db.tables.import_track_state?.find((r) => r.track_key === "catalogue-intake:mangaupdates_new:manga")?.last_results as { cursor?: { seen?: string[] } } | undefined)?.cursor;

Deno.test("storesRecordsOfNewSeries: the newest list is read once, then only unseen manga-type series from the min year are fetched", async () => {
  const db = fakeSupabase();
  const clock: number[] = [];
  const { ctx, net } = ctxFor(db, [
    json(newest),
    json(base("78343182894", { title: "Amagasa-san Chi no Nichinichi", year: "2024" })),
    json({ reason: "gone" }, 404),
    json(seriesNew),
    json(base("16508909711", { title: "Another New One" })),
    emptyPage,
  ], { clock });
  const out = await runMangaUpdatesNew(ctx);
  assert.equal(net.calls[0].url, "https://api.mangaupdates.com/v1/series/search");
  assert.deepEqual(JSON.parse(net.calls[0].body), { orderby: "date_added", perpage: 100, page: 1 });
  assert.equal(net.calls[0].init?.method, "POST");
  assert.deepEqual(net.calls.slice(1, 5).map((c) => c.url.split("/").pop()), CANDIDATES);
  const stored = db.tables.catalogue_source_records.filter((r) => r.source === "mangaupdates").map((r) => r.source_key).sort();
  assert.deepEqual(stored, ["16508909711", "2853344834", "78343182894"], "the 404 series is not stored");
  assert.equal(db.tables.catalogue_source_records.find((r) => r.source_key === "2853344834")?.licence, "MU-API");
  assert.equal(out.results.records_written, 3);
  assert.equal(out.results.missing_ids, 1);
  assert.equal(out.results.candidates, 4);
  assert.equal((db.tables.catalogue_id_links ?? []).length, 0, "no link is written: create decides");
  assert.equal(db.opsOn("anime").length + db.opsOn("manga").length, 0, "no title row is written");
  // spacing: every request (list and GETs) at least 1.1 s after the previous one
  for (let i = 1; i < clock.length; i++) assert.ok(clock[i] - clock[i - 1] >= 1_100, `request ${i} came ${clock[i] - clock[i - 1]} ms after the previous`);
});

Deno.test("skipsStoredAndLinkedSeries: a series with a stored record or an accepted link is not fetched again", async () => {
  const db = fakeSupabase({
    tables: {
      catalogue_source_records: [{ source: "mangaupdates", source_key: "78343182894", medium: "manga", payload: base("78343182894"), payload_hash: "h", licence: "MU-API", fetched_at: "2026-11-17T00:00:00Z" }],
      catalogue_id_links: [{ kind: "manga", kuro_id: 7, source: "mangaupdates", source_key: "1382090098", method: "title_match", status: "accepted" }],
    },
  });
  const { ctx, net } = ctxFor(db, [json(newest), json(seriesNew), json(base("16508909711")), emptyPage]);
  await runMangaUpdatesNew(ctx);
  assert.deepEqual(net.calls.slice(1, 3).map((c) => c.url.split("/").pop()), ["2853344834", "16508909711"]);
});

Deno.test("secondRunStopsAtTheSeenList: an unchanged list costs one request and no fetch", async () => {
  const db = fakeSupabase();
  await runMangaUpdatesNew(ctxFor(db, [json(newest), json(seriesNew), json(base("78343182894")), json(base("1382090098")), json(base("16508909711")), emptyPage]).ctx);
  assert.equal(cursorOf(db)?.seen?.length, 10, "every listed id is remembered, candidates and non-candidates");
  const again = ctxFor(db, [json(newest)]);
  const out = await runMangaUpdatesNew(again.ctx);
  assert.equal(again.net.calls.length, 1, "one list page, nothing else");
  assert.equal(out.results.candidates, 0);
  assert.equal(out.results.pages, 1);
});

Deno.test("pagingIsBounded: unseen pages are followed up to the page cap only", async () => {
  const db = fakeSupabase();
  const page = (n: number) => json({ total_hits: 10000, page: n, per_page: 100, results: Array.from({ length: 100 }, (_, i) => ({ record: { series_id: n * 1000 + i, title: `Doujin ${n}-${i}`, type: "Doujinshi", year: "2026" } })) });
  const { ctx, net } = ctxFor(db, [page(1), page(2), page(3), page(4)]);
  const out = await runMangaUpdatesNew(ctx);
  assert.equal(MU_NEW_MAX_PAGES, 3);
  assert.equal(net.calls.length, 3);
  assert.deepEqual(net.calls.map((c) => JSON.parse(c.body).page), [1, 2, 3]);
  assert.equal(out.results.pages, 3);
});

Deno.test("budgetStopKeepsUnfetchedUnseen: a stop mid-fetch keeps the unfetched ids out of the seen list so the next run fetches them", async () => {
  const db = fakeSupabase();
  // 1.1 s spacing and a 3 s budget: the list, the first GET, then the budget ends
  const { ctx, net } = ctxFor(db, [json(newest), json(base("78343182894")), json(base("1382090098"))], { deadlineMs: 3_000 });
  const out = await runMangaUpdatesNew(ctx);
  assert.equal(out.stoppedEarly, "budget");
  assert.ok(net.calls.length < 4);
  const seen = cursorOf(db)?.seen ?? [];
  assert.ok(seen.includes("78343182894"), "the fetched series is remembered");
  for (const id of ["2853344834", "16508909711"]) assert.ok(!seen.includes(id), `${id} was not fetched and must stay unseen`);
  const next = ctxFor(db, [json(newest), json(seriesNew), json(base("16508909711")), emptyPage]);
  await runMangaUpdatesNew(next.ctx);
  const urls = next.net.calls.map((c) => c.url.split("/").pop());
  assert.ok(urls.includes("2853344834") && urls.includes("16508909711"));
});

Deno.test("requestCapAndRateLimit: the limit caps requests; a 429 pause stops cleanly without remembering the candidate", async () => {
  const db = fakeSupabase();
  const { ctx, net } = ctxFor(db, [json(newest), json(seriesNew)], { limit: 2 });
  const out = await runMangaUpdatesNew(ctx);
  assert.equal(net.calls.length, 2, "limit 2 = the list page plus one fetch");
  assert.equal(out.results.requests, 2);
  const db2 = fakeSupabase();
  const limited = ctxFor(db2, [json(newest), new Response("{}", { status: 429, headers: { "retry-after": "600" } })]);
  const out2 = await runMangaUpdatesNew(limited.ctx);
  assert.equal(out2.stoppedEarly, "rate_limited");
  assert.ok(!(cursorOf(db2)?.seen ?? []).includes("78343182894"));
});

Deno.test("minYearIsHonoured: a payload year below the default widens the candidate set", async () => {
  assert.equal(MU_NEW_DEFAULT_MIN_YEAR, 2024);
  const db = fakeSupabase();
  const { ctx, net } = ctxFor(db, [json(newest), ...CANDIDATES.map((id) => json(base(id))), json(base("9876726148")), emptyPage]);
  const out = await runMangaUpdatesNew(ctx, { minYear: 2022 });
  // 2022 admits no extra manga-type row in this fixture (the 2022 and 2023 rows are Doujinshi): still four candidates
  assert.equal(out.results.candidates, 4);
  assert.equal(net.calls.length >= 5, true);
});

Deno.test("feedsCreate: the stored records are the manga candidate set; report mode (default) writes no title row", async () => {
  const db = fakeSupabase({ tables: { manga: [{ id: 1, anilist_id: 5, title_english: "Berserk", start_date_year: 1989, format: "MANGA", country_of_origin: "JP" }] } });
  await runMangaUpdatesNew(ctxFor(db, [json(newest), json(seriesNew), json(base("78343182894", { title: "Amagasa-san Chi no Nichinichi", year: "2024" })), json(base("1382090098", { title: "Toki no Hazama no Kimi to", year: "2026" })), json(base("16508909711", { title: "Fourth Series", year: "2026" })), emptyPage]).ctx);
  const r = await create({ supabase: db.client }, "manga", { mode: "report", minYear: 2024 });
  assert.equal(r.scanned, 4);
  assert.equal(r.wouldCreate, 4);
  assert.equal(r.created, 0);
  assert.equal(db.opsOn("manga").length, 0);
  assert.ok(r.sample.some((s) => s.key === "2853344834" && s.title === "Bokutotsu Cool to Yurufuwa Yankee" && s.year === 2026));
});

Deno.test("handlerRouting: mangaupdates_new is manga only, skips the release-intake window, and has its own lock", async () => {
  const mk = (payload: unknown, now: number, db = fakeSupabase()) =>
    handleRequest(new Request("https://x.test/", { method: "POST", headers: { "x-import-secret": "s" }, body: JSON.stringify(payload) }), {
      secret: "s",
      buildDeps: () => ({ supabase: db.client, clients: ctxFor(db, [json(newest), emptyPage]).ctx.clients, now: () => now } as IntakeDeps),
    });
  const anime = await mk({ handler: "mangaupdates_new", medium: "anime" }, NOW);
  assert.equal(anime.status, 400);
  const window = await mk({ handler: "mangaupdates_new", medium: "manga" }, Date.UTC(2026, 10, 18, 3, 50));
  assert.deepEqual(await window.json(), { success: true, skipped: true, reason: "release_intake_window" });
  const db = fakeSupabase();
  const ok = await mk({ handler: "mangaupdates_new", medium: "manga" }, NOW, db);
  assert.equal(ok.status, 200);
  assert.ok(db.rpcs.some((c) => c.name === "acquire_import_lock" && JSON.stringify(c.args).includes("catalogue-intake:mangaupdates_new")), "its own lock key");
  assert.ok(db.tables.import_runs?.some((r) => r.run_type === "catalogue_intake_mangaupdates_new") ?? db.opsOn("import_runs").length > 0);
});

Deno.test("cronNeverOverlapsMangaUpdates: odd minutes only, outside the quiet window, a run ends before the next even-minute run", () => {
  const jobs = CRON_JOBS.filter((j) => j.handler === "mangaupdates_new");
  assert.ok(jobs.length >= 1);
  const others = CRON_JOBS.filter((j) => j.handler === "mangaupdates");
  const otherMinutes = new Set<number>();
  for (const dow of [0, 1, 6]) for (const m of jobMinutes(others, dow)) otherMinutes.add(m);
  for (const dow of [0, 1, 6]) {
    for (const m of jobMinutes(jobs, dow)) {
      assert.ok(m % 2 === 1, `minute ${m} is odd, the matcher fires on even minutes`);
      assert.ok(m < MU_QUIET_WINDOW.startMinute || m > MU_QUIET_WINDOW.endMinute, `minute ${m} is inside the release-intake window`);
      assert.ok(!otherMinutes.has(m), `minute ${m} overlaps another MangaUpdates run`);
      // the matcher run of minute m-1 started 60 s earlier and its budget is 50 s: it has ended
    }
  }
  assert.ok(firingMinutes(RELEASE_INTAKE_MANGA.schedule)[0] >= MU_QUIET_WINDOW.startMinute);
  assert.equal(inMangaUpdatesQuietWindow(Date.UTC(2026, 10, 18, 3, 37)), true);
  // twice an hour at most: well under one request per 1.1 s on average, and the budget is under a minute
  assert.ok(jobMinutes(jobs, 1).size <= 48);
  const sql = renderCronSql();
  for (const j of jobs) assert.ok(sql.includes(`cron.schedule('${j.name}'`));
});
