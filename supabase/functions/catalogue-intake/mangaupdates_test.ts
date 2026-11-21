// Offline tests for the MangaUpdates matcher, parser and handler run (Task 5). Fetch is a fake; JSON
// fixtures are real MangaUpdates replies captured 2026-11-18 (fixtures/README.md).
// Run: cd supabase/functions/catalogue-intake && deno test --no-prompt
import { strict as assert } from "node:assert";
import { PoliteLimiter } from "../_shared/polite_fetch.ts";
import { createSourceClient } from "../_shared/catalogue/source_http.ts";
import { fakeSupabase, queuedFetch } from "./fake_supabase.ts";
import { muFetch, muMatch, parseMuSearch, parseMuSeries, runMangaUpdates } from "./mangaupdates.ts";
import { parseMuAnimeSpan, toSourceValues } from "./map_mangaupdates.ts";
import searchBerserk from "./fixtures/mu_search_berserk.json" with { type: "json" };
import searchSolo from "./fixtures/mu_search_sololeveling.json" with { type: "json" };
import seriesBerserk from "./fixtures/mu_series_berserk.json" with { type: "json" };

const BERSERK_ID = 51239621230;
const json = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...headers } });

const berserk = { id: 1, titles: ["Berserk"], year: 1989, format: "MANGA", country: "JP" };

Deno.test("uniqueMatchAccepted", () => {
  const res = muMatch(berserk, parseMuSearch(searchBerserk));
  assert.equal(res.proposed.length, 0);
  assert.equal(res.accepted.length, 1);
  const l = res.accepted[0];
  assert.deepEqual(
    { kuroId: l.kuroId, source: l.source, sourceKey: l.sourceKey, method: l.method, status: l.status },
    { kuroId: 1, source: "mangaupdates", sourceKey: String(BERSERK_ID), method: "title_match", status: "accepted" },
  );
});

Deno.test("manhwaMapsWithCountry", () => {
  const hits = parseMuSearch(searchSolo);
  const kr = muMatch({ id: 2, titles: ["Solo Leveling"], year: 2018, format: "MANGA", country: "KR" }, hits);
  assert.deepEqual(kr.accepted.map((l) => l.sourceKey), ["15180124327"]);
  const jp = muMatch({ id: 2, titles: ["Solo Leveling"], year: 2018, format: "MANGA", country: "JP" }, hits);
  assert.equal(jp.accepted.length, 0, "a Manhwa record does not match a Japanese manga");
  const novel = muMatch({ id: 3, titles: ["Solo Leveling"], year: 2016, format: "NOVEL", country: "KR" }, hits);
  assert.equal(novel.accepted.length, 0, "the exact-title Manhwa is not a novel; the (Novel) record's title differs");
});

Deno.test("ambiguousAndYearRules", () => {
  const hit = (id: number, year: number | null, type = "Manga") => ({ seriesId: id, titles: ["Twin"], year, type });
  const k = { id: 9, titles: ["Twin"], year: 2010, format: "MANGA", country: "JP" };
  assert.equal(muMatch(k, [hit(1, 2010), hit(2, 2011)]).accepted.length, 0);
  assert.equal(muMatch(k, [hit(1, 2010), hit(2, 2011)]).proposed.length, 2);
  assert.equal(muMatch(k, [hit(1, 2012)]).accepted.length, 0, "two years off scores 0.5");
  assert.equal(muMatch(k, [hit(1, 2011)]).accepted.length, 1);
  assert.equal(muMatch(k, [hit(1, null)]).accepted.length, 0, "unknown year is proposed, never auto accepted");
  assert.equal(muMatch(k, [hit(1, null)]).proposed.length, 1);
  assert.equal(muMatch(k, [hit(1, 2010, "Doujinshi")]).accepted.length, 0);
});

Deno.test("parsesFixtureSeries", () => {
  const r = parseMuSeries(seriesBerserk);
  assert.ok(r);
  assert.equal(r.seriesId, BERSERK_ID);
  assert.equal(r.title, "Berserk");
  assert.equal(r.type, "Manga");
  assert.equal(r.year, 1989);
  assert.equal(r.completed, false);
  assert.match(r.status, /Ongoing/);
  assert.equal(r.bayesianRating, 8.98);
  assert.equal(r.ratingVotes, 3731);
  assert.ok(r.genres.includes("Action"));
  assert.ok(r.associated.length > 3);
  assert.deepEqual(r.categories[0], { category: "Abuse of Power", votes: 33, votesPlus: 34, votesMinus: 1 });
  assert.ok(r.authors.some((a) => a.name === "MIURA Kentaro" && a.type === "Author"));
  assert.equal(new Set(r.authors.map((a) => `${a.authorId}|${a.type}`)).size, r.authors.length, "authors are deduplicated");
  assert.ok(r.publishers.some((p) => p.name === "Dark Horse"));
  assert.ok(r.related.some((x) => x.relationType === "Spin-Off"));
  // Credit link is Kuro-built from the series id (base 36), never the response's own url.
  assert.equal(r.url, "https://www.mangaupdates.com/series/njeqwry");
  const text = JSON.stringify(r);
  assert.ok(!text.includes("From Dark Horse"), "MangaUpdates description text is not stored");
});

Deno.test("muFetchRequestsOneSeriesAndSkipsMissing", async () => {
  const net = queuedFetch([json(seriesBerserk), json({ reason: "Not found" }, 404)]);
  const client = createSourceClient("mangaupdates", new PoliteLimiter(0), { sleep: () => Promise.resolve(), now: () => 0, random: () => 0, fetch: net.fetch });
  const out = await muFetch({ client }, [BERSERK_ID, 5]);
  assert.equal(net.calls[0].url, `https://api.mangaupdates.com/v1/series/${BERSERK_ID}`);
  assert.deepEqual(out.records.map((r) => r.seriesId), [BERSERK_ID]);
  assert.deepEqual(out.missing, ["5"]);
});

// ---- run-level -------------------------------------------------------------------------------

const NOW = Date.parse("2026-11-18T12:00:00Z");
const mangaRow = (id: number, title: string, year = 1989) => ({
  id, title_english: title, title_romaji: null, title_native: null, title_synonyms: [], start_date_year: year, format: "MANGA", country_of_origin: "JP",
});

function ctxFor(db: ReturnType<typeof fakeSupabase>, responses: Response[], over: { deadlineMs?: number; spacing?: number; limit?: number; clockLog?: number[]; tick?: number } = {}) {
  let t = 0;
  const log = over.clockLog ?? [];
  const net = queuedFetch(responses);
  const fetch = ((input: string | URL | Request, init?: RequestInit) => {
    log.push(t);
    return net.fetch(input, init);
  }) as typeof globalThis.fetch;
  const tick = over.tick ?? 0;
  const clock = () => NOW + t;
  const client = createSourceClient("mangaupdates", new PoliteLimiter(over.spacing ?? 1_100), { fetch, sleep: (ms) => { t += ms; return Promise.resolve(); }, now: clock, random: () => 0 });
  const other = createSourceClient("wikidata", new PoliteLimiter(0), { fetch: net.fetch });
  return {
    net,
    ctx: {
      supabase: db.client,
      clients: { wikidata: other, ann: other, mangaupdates: client, pageviews: other },
      medium: "manga" as const,
      limit: over.limit,
      deadlineMs: NOW + (over.deadlineMs ?? 50_000),
      now: () => {
        t += tick; // a test clock that advances on every read (per-title deadline test)
        return clock();
      },
    },
  };
}

Deno.test("runSearchesUnlinkedMangaAndLinksTheMatch", async () => {
  const db = fakeSupabase({ tables: { manga: [mangaRow(1, "Berserk")] } });
  const { ctx, net } = ctxFor(db, [json(searchBerserk), json(seriesBerserk)]);
  const out = await runMangaUpdates(ctx);
  assert.equal(net.calls[0].url, "https://api.mangaupdates.com/v1/series/search");
  assert.deepEqual(JSON.parse(net.calls[0].body), { search: "Berserk", perpage: 10 });
  assert.equal(net.calls[0].init?.method, "POST");
  assert.deepEqual(db.tables.catalogue_id_links.map((l) => [l.kuro_id, l.source, l.source_key, l.method, l.status]), [[1, "mangaupdates", String(BERSERK_ID), "title_match", "accepted"]]);
  // The accepted link's record is fetched in the same run.
  assert.equal(net.calls[1].url, `https://api.mangaupdates.com/v1/series/${BERSERK_ID}`);
  assert.equal(db.tables.catalogue_source_records.find((r) => r.source === "mangaupdates")?.licence, "MU-API");
  assert.equal(out.results.matched, 1);
});

const wdProposed = (kuro: number, key: string) => ({ id: 1, kind: "manga", kuro_id: kuro, source: "mangaupdates", source_key: key, method: "wikidata", confidence: 1, status: "proposed" });

Deno.test("muMatchCorroboratesWikidataIdAndAccepts", async () => {
  const db = fakeSupabase({ tables: { manga: [mangaRow(1, "Berserk")], catalogue_id_links: [wdProposed(1, String(BERSERK_ID))] } });
  const { ctx, net } = ctxFor(db, [json(searchBerserk), json(seriesBerserk)]);
  const out = await runMangaUpdates(ctx);
  assert.equal(net.calls[0].url, "https://api.mangaupdates.com/v1/series/search", "Task 5's own search matching decides");
  assert.equal(db.tables.catalogue_id_links.length, 1);
  assert.equal(db.tables.catalogue_id_links[0].status, "accepted");
  assert.equal(out.results.corroborated, 1);
  assert.equal(out.results.conflicts, 0);
  // The accepted link's record is then fetched by the records phase.
  assert.equal(net.calls[1].url, `https://api.mangaupdates.com/v1/series/${BERSERK_ID}`);
});

Deno.test("muMatchDisagreesKeepsProposedAndListsConflict", async () => {
  const db = fakeSupabase({ tables: { manga: [mangaRow(1, "Totally Different Title", 2001)], catalogue_id_links: [wdProposed(1, String(BERSERK_ID))] } });
  const { ctx } = ctxFor(db, [json(searchBerserk)]);
  const out = await runMangaUpdates(ctx);
  assert.equal(db.tables.catalogue_id_links.length, 1);
  assert.equal(db.tables.catalogue_id_links[0].status, "proposed");
  assert.equal(out.results.conflicts, 1);
  assert.equal((out.results.conflict_sample as { reason: string }[])[0].reason, "wikidata_id_disagrees_with_title_match");
});

Deno.test("wikidataIdIsNeverAcceptedBySingleRecordScore", async () => {
  // Wikidata names series 999 for Berserk. The record at 999 would score perfectly on its own, but the search
  // matching picks the real Berserk id: both stay proposed, nothing is accepted, and a conflict is listed.
  const other = { ...seriesBerserk, series_id: 999 };
  const db = fakeSupabase({ tables: { manga: [mangaRow(1, "Berserk")], catalogue_id_links: [wdProposed(1, "999")] } });
  const { ctx, net } = ctxFor(db, [json(searchBerserk), json(other)]);
  const out = await runMangaUpdates(ctx);
  const links = db.tables.catalogue_id_links;
  assert.equal(links.filter((l) => l.status === "accepted").length, 0, "no accepted link");
  assert.deepEqual(links.map((l) => [l.source_key, l.status]).sort(), [[String(BERSERK_ID), "proposed"], ["999", "proposed"]]);
  assert.equal(out.results.conflicts, 1);
  assert.equal(net.calls.length, 1, "no record is fetched for a link that is not accepted");
});

Deno.test("wikidataIdStaysProposedWhenTheSearchIsAmbiguous", async () => {
  const hit = (id: number) => ({ record: { series_id: id, title: "Twin", year: "2010", type: "Manga" }, hit_title: "Twin" });
  const db = fakeSupabase({ tables: { manga: [mangaRow(1, "Twin", 2010)], catalogue_id_links: [wdProposed(1, "5")] } });
  const { ctx } = ctxFor(db, [json({ results: [hit(5), hit(6)] })]);
  const out = await runMangaUpdates(ctx);
  assert.equal(db.tables.catalogue_id_links.filter((l) => l.status === "accepted").length, 0);
  assert.equal(out.results.conflicts, 1);
});

Deno.test("budgetStopKeepsCursor", async () => {
  const db = fakeSupabase({ tables: { manga: [mangaRow(1, "Berserk"), mangaRow(2, "Another One"), mangaRow(3, "Third")] } });
  // Spacing 1.1 s, budget 1 s: the first search can go out, the second cannot be started.
  const { ctx, net } = ctxFor(db, [json({ results: [] }), json({ results: [] })], { deadlineMs: 1_000 });
  const out = await runMangaUpdates(ctx);
  assert.equal(out.stoppedEarly, "budget");
  assert.equal(net.calls.length, 1);
  const cursor = (db.tables.import_track_state[0].last_results as { cursor: { after_id: number } }).cursor;
  assert.equal(cursor.after_id, 1, "the cursor stops after the last fully processed title");
  assert.equal((db.tables.catalogue_id_links ?? []).length, 0);
});

Deno.test("retryAfterPausesTheRunCleanly", async () => {
  const db = fakeSupabase({ tables: { manga: [mangaRow(1, "Berserk")] } });
  const { ctx } = ctxFor(db, [json({}, 429, { "retry-after": "30" })], { deadlineMs: 10_000 });
  const out = await runMangaUpdates(ctx);
  assert.equal(out.stoppedEarly, "rate_limited");
  assert.equal((db.tables.import_track_state[0].last_results as { cursor: { after_id: number } }).cursor.after_id, 0);
});

Deno.test("sharedSpacingAtLeast1100ms", async () => {
  const rows = [1, 2, 3].map((i) => mangaRow(i, `Title ${i}`));
  const db = fakeSupabase({ tables: { manga: rows } });
  const times: number[] = [];
  const { ctx } = ctxFor(db, [json({ results: [] }), json({ results: [] }), json({ results: [] })], { clockLog: times });
  await runMangaUpdates(ctx);
  assert.equal(times.length, 3);
  for (let i = 1; i < times.length; i++) assert.ok(times[i] - times[i - 1] >= 1_100, `gap ${times[i] - times[i - 1]} ms`);
});

// ---- deadline per title and one bad item (review 2026-11-18) ------------------------------------------

const searchEmpty = () => json({ results: [] });
const cursorOf = (db: ReturnType<typeof fakeSupabase>) => (db.tables.import_track_state[0].last_results as { cursor: { after_id: number; fetch_after_link: number; fails?: Record<string, number> } }).cursor;

Deno.test("deadlineIsCheckedPerTitleEvenWithoutARequest", async () => {
  // Six titles that already have an accepted link need no request; the clock moves 1 ms per read and the
  // budget runs out after three titles, so the walk must stop there instead of scanning the whole page.
  const rows = [1, 2, 3, 4, 5, 6].map((i) => mangaRow(i, `Title ${i}`));
  const accepted = rows.map((r, i) => ({ id: i + 1, kind: "manga", kuro_id: r.id, source: "mangaupdates", source_key: String(100 + i), method: "title_match", confidence: 1, status: "accepted" }));
  const db = fakeSupabase({ tables: { manga: rows, catalogue_id_links: accepted } });
  const { ctx } = ctxFor(db, [], { deadlineMs: 3.5, tick: 1 });
  const out = await runMangaUpdates(ctx);
  assert.equal(out.stoppedEarly, "budget");
  assert.equal(cursorOf(db).after_id, 2, "stopped after the last title walked inside the budget (the clock read for title 3 crossed it)");
});

Deno.test("aSearchRejectedWith4xxIsRecordedAndTheWalkAdvances", async () => {
  const db = fakeSupabase({ tables: { manga: [mangaRow(1, "Bad One"), mangaRow(2, "Good Two")] } });
  const { ctx, net } = ctxFor(db, [json({}, 400), searchEmpty()]);
  const out = await runMangaUpdates(ctx);
  assert.equal(out.stoppedEarly, undefined);
  assert.equal(net.calls.length, 2, "title 2 was searched after title 1 failed");
  assert.equal(out.results.items_failed, 1);
  assert.deepEqual(out.results.failed_items, [{ key: "m:1", reason: "http 400" }]);
  assert.equal(cursorOf(db).after_id, 0, "the pass finished");
});

Deno.test("anUnreadableSearchBodyIsRecordedAndSkipped", async () => {
  const db = fakeSupabase({ tables: { manga: [mangaRow(1, "Bad One"), mangaRow(2, "Good Two")] } });
  const { ctx } = ctxFor(db, [new Response("<html>oops", { status: 200 }), searchEmpty()]);
  const out = await runMangaUpdates(ctx);
  assert.equal(out.results.items_failed, 1);
  assert.equal(out.stoppedEarly, undefined);
});

Deno.test("aServerErrorStopsTheRunAndIsCountedAgainstTheTitle", async () => {
  const db = fakeSupabase({ tables: { manga: [mangaRow(1, "Bad One"), mangaRow(2, "Good Two")] } });
  const { ctx } = ctxFor(db, [json({}, 502), json({}, 502), json({}, 502)]);
  const out = await runMangaUpdates(ctx);
  assert.equal(out.stoppedEarly, "source_error");
  const c = cursorOf(db);
  assert.equal(c.after_id, 0, "the cursor stays before the failing title");
  assert.deepEqual(c.fails, { "m:1": 1 });
});

Deno.test("aTitleThatFailedThreeRunsInARowIsSkippedAndRecorded", async () => {
  const db = fakeSupabase({
    tables: {
      manga: [mangaRow(1, "Bad One"), mangaRow(2, "Good Two")],
      import_track_state: [{ track_key: "catalogue-intake:mangaupdates:manga", last_results: { cursor: { after_id: 0, fetch_after_link: 0, fails: { "m:1": 3 } } } }],
    },
  });
  const { ctx, net } = ctxFor(db, [searchEmpty()]);
  const out = await runMangaUpdates(ctx);
  assert.equal(net.calls.length, 1, "title 1 is not searched again");
  assert.deepEqual(out.results.failed_items, [{ key: "m:1", reason: "skipped_after_repeated_failures" }]);
  assert.equal(out.stoppedEarly, undefined);
});

Deno.test("aRecordFetchRejectedWith4xxDoesNotBlockTheOtherRecords", async () => {
  const accepted = [{ id: 1, kind: "manga", kuro_id: 1, source: "mangaupdates", source_key: "111", method: "title_match", confidence: 1, status: "accepted" }, { id: 2, kind: "manga", kuro_id: 2, source: "mangaupdates", source_key: String(BERSERK_ID), method: "title_match", confidence: 1, status: "accepted" }];
  const db = fakeSupabase({ tables: { manga: [mangaRow(1, "A"), mangaRow(2, "Berserk")], catalogue_id_links: accepted } });
  const { ctx } = ctxFor(db, [json({}, 400), json(seriesBerserk)]);
  const out = await runMangaUpdates(ctx);
  assert.equal(out.stoppedEarly, undefined);
  assert.equal(out.results.records_fetched, 1);
  assert.deepEqual(out.results.failed_items, [{ key: "f:111", reason: "http 400" }]);
});

Deno.test("aRecordFetchServerErrorStopsAndCountsThenIsSkippedAfterThreeRuns", async () => {
  const accepted = [{ id: 1, kind: "manga", kuro_id: 1, source: "mangaupdates", source_key: "111", method: "title_match", confidence: 1, status: "accepted" }, { id: 2, kind: "manga", kuro_id: 2, source: "mangaupdates", source_key: String(BERSERK_ID), method: "title_match", confidence: 1, status: "accepted" }];
  const tables = { manga: [mangaRow(1, "A"), mangaRow(2, "Berserk")], catalogue_id_links: accepted };
  const db = fakeSupabase({ tables });
  const first = await runMangaUpdates(ctxFor(db, [json({}, 500), json({}, 500), json({}, 500)]).ctx);
  assert.equal(first.stoppedEarly, "source_error");
  assert.deepEqual(cursorOf(db).fails, { "f:111": 1 });
  // Two more failing runs, then the series is skipped and the next record is fetched.
  await runMangaUpdates(ctxFor(db, [json({}, 500), json({}, 500), json({}, 500)]).ctx);
  await runMangaUpdates(ctxFor(db, [json({}, 500), json({}, 500), json({}, 500)]).ctx);
  assert.deepEqual(cursorOf(db).fails, { "f:111": 3 });
  const fourth = await runMangaUpdates(ctxFor(db, [json(seriesBerserk)]).ctx);
  assert.equal(fourth.stoppedEarly, undefined);
  assert.equal(fourth.results.records_fetched, 1);
  assert.deepEqual(fourth.results.failed_items, [{ key: "f:111", reason: "skipped_after_repeated_failures" }]);
});

Deno.test("parsesAnimeAdaptationSpanFromMangaUpdatesRecord", () => {
  const parsed = parseMuSeries({
    series_id: 99123,
    title: "Chainsaw Man",
    type: "Manga",
    year: "2018",
    status: "18 Volumes (Ongoing)",
    completed: false,
    genres: [{ genre: "Action" }],
    anime: { start: "Vol 1, Chap 1", end: "Vol 5, Chap 38" },
  });
  assert.ok(parsed);
  assert.equal(parsed.animeStart, "Vol 1, Chap 1");
  assert.equal(parsed.animeEnd, "Vol 5, Chap 38");

  const span = parseMuAnimeSpan(parsed.animeStart, parsed.animeEnd);
  assert.deepEqual(span, {
    startVolume: 1,
    startChapter: 1,
    endVolume: 5,
    endChapter: 38,
    nextChapter: 39,
    rawStart: "Vol 1, Chap 1",
    rawEnd: "Vol 5, Chap 38",
  });
  const values = toSourceValues(parsed);
  assert.deepEqual(values.anime_adaptation_span, span);
  assert.equal(parseMuAnimeSpan(null, "Ends before finale"), null);
});

Deno.test("parsesLatestChapterFromDirectFieldOrStatus", () => {
  const withDirect = parseMuSeries({
    series_id: 55099564912,
    title: "One Piece",
    status: "115 Volumes (Ongoing)",
    latest_chapter: 1198,
    completed: false,
  });
  assert.equal(withDirect?.latestChapter, 1198);

  const fromStatus = parseMuSeries({
    series_id: 10001137810,
    title: "Ongoing Example",
    status: "3 Volumes // 16 Chapters + 2 Extras (Ongoing)",
    completed: false,
  });
  assert.equal(fromStatus?.latestChapter, 16);
});
