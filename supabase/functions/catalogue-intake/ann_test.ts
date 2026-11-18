// Offline tests for the ANN matcher, parser and handler run (Task 4). Fetch is a fake; XML fixtures
// are real ANN replies captured 2026-11-18 (fixtures/README.md) or hand-built rows.
// Run: cd supabase/functions/catalogue-intake && deno test --no-prompt
import { strict as assert } from "node:assert";
import { PoliteLimiter } from "../_shared/polite_fetch.ts";
import { createSourceClient } from "../_shared/catalogue/source_http.ts";
import { fakeSupabase, queuedFetch } from "./fake_supabase.ts";
import { ANN_REPORT_URL, annFetch, annMatch, parseAnnApi, parseAnnReport, runAnn } from "./ann.ts";

const fast = { sleep: () => Promise.resolve(), now: () => 0, random: () => 0 };
import { ANN_API_BATCH, ANN_API_ONE, ANN_REPORT_SAMPLE } from "./fixtures/ann_fixtures.ts";
// The XML files in fixtures/ are the raw captures; ann_fixtures.ts embeds them as strings.
const files: Record<string, string> = { "ann_report_sample.xml": ANN_REPORT_SAMPLE, "ann_api_one.xml": ANN_API_ONE, "ann_api_batch.xml": ANN_API_BATCH };
const read = (name: string) => files[name];

const xml = (body: string, status = 200, headers: Record<string, string> = {}) => new Response(body, { status, headers: { "content-type": "text/xml", ...headers } });
const idsIn = (url: string) => (new URL(url).searchParams.get("anime") ?? "").split("/").filter(Boolean);

Deno.test("parsesReportFixture", () => {
  const rows = parseAnnReport(read("ann_report_sample.xml"));
  assert.equal(rows.length, 40);
  assert.deepEqual(rows[0], { id: 41087, type: "TV", name: "Golden Kamuy Final Season: Runaway Train Arc", vintage: "2027-01-05" });
  assert.equal(rows[1].vintage, null);
  assert.ok(rows.some((r) => r.type === "omnibus"));
});

const row = (id: number, name: string, type = "TV", vintage: string | null = "2009-04-01") => ({ id, type, name, vintage });

Deno.test("uniqueMatchAccepted", () => {
  const report = [row(100, "Kaiju Gakuen"), row(101, "Something Else Entirely"), row(102, "Kaiju Gakuen Movie", "movie")];
  const res = annMatch([{ id: 202, titles: ["Kaiju Gakuen", "Kaijuu Gakuen"], year: 2009, format: "TV" }], report);
  assert.equal(res.proposed.length, 0);
  assert.equal(res.accepted.length, 1);
  const link = res.accepted[0];
  assert.deepEqual(
    { kuroId: link.kuroId, source: link.source, sourceKey: link.sourceKey, method: link.method, status: link.status },
    { kuroId: 202, source: "ann", sourceKey: "100", method: "title_match", status: "accepted" },
  );
  assert.ok((link.confidence ?? 0) >= 0.92);
});

Deno.test("ambiguousMatchIsProposed", () => {
  const report = [row(300, "Same Name"), row(301, "Same Name")];
  const res = annMatch([{ id: 203, titles: ["Same Name"], year: 2009, format: "TV" }], report);
  assert.equal(res.accepted.length, 0);
  assert.deepEqual(res.proposed.map((l) => [l.kuroId, l.sourceKey, l.status]).sort(), [[203, "300", "proposed"], [203, "301", "proposed"]]);
});

Deno.test("runnerUpAtOrAbove0.80BlocksAcceptance", () => {
  // Same normalised title in a second ANN entry whose year is one off scores 1.0 too (within +-1).
  const res = annMatch([{ id: 1, titles: ["Twin"], year: 2009, format: "TV" }], [row(1, "Twin", "TV", "2009-01-01"), row(2, "Twin", "TV", "2010-01-01")]);
  assert.equal(res.accepted.length, 0);
  assert.equal(res.proposed.length, 2);
});

Deno.test("yearOffByTwoNotAccepted", () => {
  const res = annMatch([{ id: 1, titles: ["Kaiju Gakuen"], year: 2011, format: "TV" }], [row(100, "Kaiju Gakuen", "TV", "2009-04-01")]);
  assert.equal(res.accepted.length, 0);
  assert.equal(res.proposed.length, 0, "an exact title two years off scores 0.5, below the proposal floor");
});

Deno.test("yearOffByOneIsAccepted", () => {
  const res = annMatch([{ id: 1, titles: ["Kaiju Gakuen"], year: 2010, format: "TV" }], [row(100, "Kaiju Gakuen", "TV", "2009-12-30")]);
  assert.equal(res.accepted.length, 1);
});

Deno.test("unknownYearOrFormatIsNeverAutoAccepted", () => {
  const noYearKuro = annMatch([{ id: 1, titles: ["Kaiju Gakuen"], year: null, format: "TV" }], [row(100, "Kaiju Gakuen")]);
  assert.equal(noYearKuro.accepted.length, 0);
  assert.equal(noYearKuro.proposed.length, 1);
  const noYearAnn = annMatch([{ id: 1, titles: ["Kaiju Gakuen"], year: 2009, format: "TV" }], [row(100, "Kaiju Gakuen", "TV", null)]);
  assert.equal(noYearAnn.accepted.length, 0);
  const wrongType = annMatch([{ id: 1, titles: ["Kaiju Gakuen"], year: 2009, format: "MOVIE" }], [row(100, "Kaiju Gakuen", "TV")]);
  assert.equal(wrongType.accepted.length, 0);
});

Deno.test("typeMapCoversAniListFormats", () => {
  const cases: [string, string][] = [["TV", "TV"], ["TV_SHORT", "TV"], ["MOVIE", "movie"], ["OVA", "OAV"], ["ONA", "ONA"], ["SPECIAL", "special"]];
  for (const [format, annType] of cases) {
    const res = annMatch([{ id: 1, titles: ["Mapped"], year: 2009, format }], [row(5, "Mapped", annType)]);
    assert.equal(res.accepted.length, 1, `${format} <-> ${annType}`);
  }
});

Deno.test("seasonMarkersMatchAcrossTitleForms", () => {
  const res = annMatch([{ id: 1, titles: ["Shingeki no Kyojin Season 2"], year: 2017, format: "TV" }], [row(9, "Shingeki no Kyojin 2nd Season", "TV", "2017-04-01")]);
  assert.equal(res.accepted.length, 1);
});

Deno.test("parsesFixtureRecord", () => {
  const { records, missing } = parseAnnApi(read("ann_api_one.xml"));
  assert.deepEqual(missing, []);
  assert.equal(records.length, 1);
  const r = records[0];
  assert.equal(r.id, 4658);
  assert.equal(r.type, "TV");
  assert.equal(r.name, "Jinki:Extend");
  assert.equal(r.titles.main, "Jinki:Extend");
  assert.ok(r.titles.alternatives.some((t) => t.lang === "JA" && t.title === "ジンキ・エクステンド"));
  assert.deepEqual(r.genres, ["drama", "science fiction"]);
  assert.ok(r.themes.includes("mecha"));
  assert.equal(r.episodes, 12);
  assert.equal(r.vintage, "2005-01-05 to 2005-03-23");
  assert.equal(r.vintageYear, 2005);
  assert.equal(r.objectionable, "TA");
  assert.deepEqual(r.ratings, { votes: 436, weighted: 6.0315, bayesian: 6.07 });
  assert.deepEqual(r.related, [{ rel: "adapted from", id: 4199, direction: "prev" }]);
  assert.ok(r.companies.some((c) => c.task === "Animation Production" && c.companyId === 8883 && c.name === "feel."));
  assert.ok(r.cast.length > 0 && r.cast.every((c) => c.lang === "JA" || c.lang === "EN"), "only JA/EN cast is kept");
  assert.equal(r.url, "https://www.animenewsnetwork.com/encyclopedia/anime.php?id=4658");
  assert.ok(!JSON.stringify(r).includes("Aoba is a young girl"), "ANN plot text is not stored");
});

Deno.test("parsesBatchWithUnknownIds", () => {
  const { records, missing } = parseAnnApi(read("ann_api_batch.xml"));
  assert.deepEqual(records.map((r) => r.id), [41045]);
  assert.deepEqual(missing.sort(), ["16798", "9999999"]);
  assert.deepEqual(records[0].related, [{ rel: "sequel of", id: 35362, direction: "prev" }]);
  assert.equal(records[0].ratings, null);
});

Deno.test("batchesAtMost50Ids", async () => {
  const ids = Array.from({ length: 120 }, (_, i) => i + 1);
  const net = queuedFetch([xml("<ann/>"), xml("<ann/>"), xml("<ann/>")]);
  const client = createSourceClient("ann", new PoliteLimiter(0), { ...fast, fetch: net.fetch });
  const res = await annFetch({ client }, ids);
  assert.equal(net.calls.length, 3);
  assert.equal(res.requests, 3);
  assert.deepEqual(net.calls.map((c) => idsIn(c.url).length), [50, 50, 20]);
  assert.ok(net.calls.every((c) => c.url.startsWith("https://cdn.animenewsnetwork.com/encyclopedia/api.xml?anime=")));
  assert.deepEqual(idsIn(net.calls[0].url).slice(0, 3), ["1", "2", "3"]);
});

// ---- run-level -------------------------------------------------------------------------------

const NOW = Date.parse("2026-11-18T12:00:00Z");
const reportRecord = (rows: ReturnType<typeof row>[], fetchedAt = new Date(NOW - 3600_000).toISOString()) => ({
  source: "ann",
  source_key: "report:anime",
  medium: "anime",
  payload: { items: rows },
  payload_hash: "h",
  licence: "ANN-credit-link",
  fetched_at: fetchedAt,
});

function ctxFor(db: ReturnType<typeof fakeSupabase>, responses: Response[], over: { deadlineMs?: number; limiter?: PoliteLimiter; clock?: () => number; limit?: number } = {}) {
  const net = queuedFetch(responses);
  const clock = over.clock ?? (() => 0);
  const client = createSourceClient("ann", over.limiter ?? new PoliteLimiter(0), { fetch: net.fetch, sleep: () => Promise.resolve(), now: clock, random: () => 0 });
  const other = createSourceClient("wikidata", new PoliteLimiter(0), { ...fast, fetch: net.fetch });
  return {
    net,
    ctx: {
      supabase: db.client,
      clients: { wikidata: other, ann: client, mangaupdates: other, pageviews: other },
      medium: "anime" as const,
      limit: over.limit,
      deadlineMs: over.deadlineMs ?? 50_000,
      now: () => NOW,
    },
  };
}

Deno.test("runMatchesUnlinkedTitlesFromTheCachedReport", async () => {
  const db = fakeSupabase({
    tables: {
      catalogue_source_records: [reportRecord([row(100, "Kaiju Gakuen"), row(300, "Same Name"), row(301, "Same Name")])],
      anime: [
        { id: 202, title_english: "Kaiju Gakuen", title_romaji: null, title_native: null, title_synonyms: [], start_date_year: 2009, format: "TV" },
        { id: 203, title_english: null, title_romaji: "Same Name", title_native: null, title_synonyms: null, start_date_year: 2009, format: "TV" },
        { id: 204, title_english: "Already Linked", title_romaji: null, title_native: null, title_synonyms: [], start_date_year: 2009, format: "TV" },
      ],
      catalogue_id_links: [{ id: 1, kind: "anime", kuro_id: 204, source: "ann", source_key: "999", method: "wikidata", confidence: 1, status: "accepted" }],
    },
  });
  const { ctx, net } = ctxFor(db, [xml("<ann/>")]);
  const out = await runAnn(ctx);
  // The fresh cached report needs no request; the only request fetches records of the accepted links.
  assert.equal(net.calls.length, 1);
  assert.ok(!net.calls[0].url.includes("reports.xml"));
  assert.deepEqual(idsIn(net.calls[0].url), ["999", "100"]);
  const links = db.tables.catalogue_id_links.filter((l) => l.id !== 1);
  assert.deepEqual(links.filter((l) => l.status === "accepted").map((l) => [l.kuro_id, l.source_key, l.method]), [[202, "100", "title_match"]]);
  assert.deepEqual(links.filter((l) => l.status === "proposed").map((l) => [l.kuro_id, l.source_key]).sort(), [[203, "300"], [203, "301"]]);
  assert.ok(!links.some((l) => l.kuro_id === 204), "titles with an accepted ANN link are not matched again");
  assert.equal(out.results.matched, 1);
  assert.equal(out.results.proposed, 2);
});

const wdProposed = (id: number, kuro: number, key: string) => ({ id, kind: "anime", kuro_id: kuro, source: "ann", source_key: key, method: "wikidata", confidence: 1, status: "proposed" });
const kuro202 = { id: 202, title_english: "Kaiju Gakuen", title_romaji: null, title_native: null, title_synonyms: [], start_date_year: 2009, format: "TV" };

Deno.test("annMatchCorroboratesWikidataIdAndAccepts", async () => {
  const db = fakeSupabase({
    tables: { catalogue_source_records: [reportRecord([row(100, "Kaiju Gakuen")])], anime: [kuro202], catalogue_id_links: [wdProposed(1, 202, "100")] },
  });
  const { ctx } = ctxFor(db, [xml(read("ann_api_batch.xml"))]);
  const out = await runAnn(ctx);
  const links = db.tables.catalogue_id_links;
  assert.equal(links.length, 1, "the proposed link is promoted in place, not duplicated");
  assert.deepEqual({ status: links[0].status, method: links[0].method }, { status: "accepted", method: "wikidata" });
  assert.equal(out.results.corroborated, 1);
});

Deno.test("annMatchDisagreesKeepsProposedAndListsConflict", async () => {
  const db = fakeSupabase({
    tables: { catalogue_source_records: [reportRecord([row(100, "Kaiju Gakuen"), row(555, "Unrelated Show")])], anime: [kuro202], catalogue_id_links: [wdProposed(1, 202, "555")] },
  });
  const { ctx } = ctxFor(db, [xml(read("ann_api_batch.xml"))]);
  const out = await runAnn(ctx);
  const links = db.tables.catalogue_id_links;
  assert.equal(links.filter((l) => l.status === "accepted").length, 0, "neither key is accepted");
  assert.deepEqual(links.map((l) => [l.source_key, l.status]).sort(), [["100", "proposed"], ["555", "proposed"]]);
  assert.equal(out.results.conflicts, 1);
  const sample = out.results.conflict_sample as { reason: string }[];
  assert.equal(sample[0].reason, "wikidata_id_disagrees_with_title_match");
});

Deno.test("runFetchesRecordsForAcceptedLinksAndSkipsFreshOnes", async () => {
  const fresh = { source: "ann", source_key: "4658", medium: "anime", payload: { id: 4658 }, payload_hash: "x", licence: "ANN-credit-link", fetched_at: new Date(NOW - 86_400_000).toISOString() };
  const db = fakeSupabase({
    tables: {
      catalogue_source_records: [reportRecord([]), fresh],
      catalogue_id_links: [
        { id: 1, kind: "anime", kuro_id: 1, source: "ann", source_key: "4658", method: "wikidata", confidence: 1, status: "accepted" },
        { id: 2, kind: "anime", kuro_id: 2, source: "ann", source_key: "41045", method: "title_match", confidence: 0.95, status: "accepted" },
        { id: 3, kind: "anime", kuro_id: 3, source: "ann", source_key: "777", method: "title_match", confidence: 0.5, status: "proposed" },
      ],
    },
  });
  const { ctx, net } = ctxFor(db, [xml(read("ann_api_batch.xml"))]);
  const out = await runAnn(ctx);
  assert.equal(net.calls.length, 1);
  assert.deepEqual(idsIn(net.calls[0].url), ["41045"], "the week-old-or-newer record 4658 and the proposed link are not fetched");
  const stored = db.tables.catalogue_source_records.find((r) => r.source_key === "41045");
  assert.ok(stored);
  assert.equal(stored.licence, "ANN-credit-link");
  assert.equal(stored.medium, "anime");
  assert.equal(out.results.records_fetched, 1);
});

Deno.test("staleRecordIsRefetchedAndUnchangedPayloadOnlyTouchesFetchedAt", async () => {
  const { records } = parseAnnApi(read("ann_api_one.xml"));
  const { payloadHash } = await import("./store.ts");
  const hash = await payloadHash(records[0]);
  const old = { source: "ann", source_key: "4658", medium: "anime", payload: records[0], payload_hash: hash, licence: "ANN-credit-link", fetched_at: new Date(NOW - 8 * 86_400_000).toISOString() };
  const db = fakeSupabase({
    tables: {
      catalogue_source_records: [reportRecord([]), old],
      catalogue_id_links: [{ id: 1, kind: "anime", kuro_id: 1, source: "ann", source_key: "4658", method: "wikidata", confidence: 1, status: "accepted" }],
    },
  });
  const { ctx, net } = ctxFor(db, [xml(read("ann_api_one.xml"))]);
  await runAnn(ctx);
  assert.equal(net.calls.length, 1);
  assert.equal(db.opsOn("catalogue_source_records", "upsert").length, 0, "same hash writes no payload");
  const updated = db.tables.catalogue_source_records.find((r) => r.source_key === "4658");
  assert.equal(updated?.fetched_at, new Date(NOW).toISOString(), "freshness is recorded so the next pass skips it");
});

Deno.test("staleReportIsRefetchedAndStored", async () => {
  const db = fakeSupabase({ tables: { catalogue_source_records: [reportRecord([row(1, "Old")], new Date(NOW - 8 * 86_400_000).toISOString())] } });
  const { ctx, net } = ctxFor(db, [xml(read("ann_report_sample.xml"))]);
  await runAnn(ctx);
  assert.equal(net.calls.length, 1);
  assert.equal(net.calls[0].url, ANN_REPORT_URL);
  const stored = db.tables.catalogue_source_records.find((r) => r.source_key === "report:anime");
  assert.equal((stored?.payload as { items: unknown[] }).items.length, 40);
});

Deno.test("retryAfterPausesAndKeepsCursor", async () => {
  const cursorRow = { track_key: "catalogue-intake:ann:anime", last_results: { cursor: { match_after_id: 0, fetch_after_link: 0 } } };
  const db = fakeSupabase({
    tables: {
      catalogue_source_records: [reportRecord([])],
      catalogue_id_links: [{ id: 1, kind: "anime", kuro_id: 1, source: "ann", source_key: "41045", method: "wikidata", confidence: 1, status: "accepted" }],
      import_track_state: [cursorRow],
    },
  });
  // A 429 with Retry-After: 30 pauses the limiter 30 s; the run budget ends in 10 s, so the retry
  // cannot be sent and the run stops cleanly.
  let t = 0;
  const { ctx, net } = ctxFor(db, [xml("", 429, { "retry-after": "30" })], { deadlineMs: 10_000, limiter: new PoliteLimiter(1_100), clock: () => t });
  const before = JSON.stringify(db.tables.import_track_state[0].last_results);
  const out = await runAnn(ctx);
  t = 0;
  assert.equal(out.stoppedEarly, "rate_limited");
  assert.equal(net.calls.length, 1);
  assert.equal(db.opsOn("catalogue_source_records").length, 0, "nothing is written for the interrupted batch");
  assert.equal(db.opsOn("catalogue_id_links").length, 0);
  const after = db.tables.import_track_state[0].last_results as { cursor: Record<string, number> };
  assert.equal(after.cursor.fetch_after_link, 0, "the fetch cursor did not move");
  assert.equal(JSON.stringify(db.tables.import_track_state[0].last_results).includes("fetch_after_link\":0"), true);
  assert.ok(before.includes("fetch_after_link"));
});
