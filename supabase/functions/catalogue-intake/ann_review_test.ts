// Review-fix tests for the ANN handler (2026-11-18): the cached report is not downloaded just to check
// freshness, and one bad item never stalls the run. Fetch is a fake. Run: deno test --no-prompt
import { strict as assert } from "node:assert";
import { PoliteLimiter } from "../_shared/polite_fetch.ts";
import { createSourceClient } from "../_shared/catalogue/source_http.ts";
import { fakeSupabase, queuedFetch } from "./fake_supabase.ts";
import { ANN_REPORT_URL, annFetch, runAnn } from "./ann.ts";
import { ANN_API_BATCH, ANN_REPORT_SAMPLE } from "./fixtures/ann_fixtures.ts";

const NOW = Date.parse("2026-11-18T12:00:00Z");
const xml = (body: string, status = 200) => new Response(body, { status, headers: { "content-type": "text/xml" } });
const idsIn = (url: string) => (new URL(url).searchParams.get("anime") ?? "").split("/").filter(Boolean);
const mkClient = (responses: Response[]) => {
  const net = queuedFetch(responses);
  return { net, client: createSourceClient("ann", new PoliteLimiter(0), { fetch: net.fetch, sleep: () => Promise.resolve(), now: () => 0, random: () => 0 }) };
};

const reportRecord = (fetchedAt = new Date(NOW - 3600_000).toISOString(), hash = "h1") => ({
  source: "ann",
  source_key: "report:anime",
  medium: "anime",
  payload: { items: [{ id: 100, type: "TV", name: "Kaiju Gakuen", vintage: "2009-04-01" }] },
  payload_hash: hash,
  licence: "ANN-credit-link",
  fetched_at: fetchedAt,
});
const accepted = (id: number, key: string) => ({ id, kind: "anime", kuro_id: id, source: "ann", source_key: key, method: "title_match", confidence: 1, status: "accepted" });
const kuro = { id: 202, title_english: "Kaiju Gakuen", title_romaji: null, title_native: null, title_synonyms: [], start_date_year: 2009, format: "TV" };

function ctxFor(db: ReturnType<typeof fakeSupabase>, responses: Response[]) {
  const { net, client } = mkClient(responses);
  const other = createSourceClient("wikidata", new PoliteLimiter(0), { fetch: net.fetch, sleep: () => Promise.resolve(), now: () => 0, random: () => 0 });
  return { net, ctx: { supabase: db.client, clients: { wikidata: other, ann: client, mangaupdates: other, pageviews: other }, medium: "anime" as const, limit: undefined, deadlineMs: 50_000, now: () => NOW } };
}

/** Records the column list of every select on catalogue_source_records. */
function spyOnSelects(db: ReturnType<typeof fakeSupabase>) {
  const selects: string[] = [];
  const from = db.client.from;
  db.client.from = (table: string) => {
    const q = from(table);
    if (table === "catalogue_source_records") {
      const select = q.select.bind(q);
      q.select = (cols?: string) => {
        selects.push(String(cols));
        return select(cols);
      };
    }
    return q;
  };
  return selects;
}

const cursorOf = (db: ReturnType<typeof fakeSupabase>) => (db.tables.import_track_state.find((r) => r.track_key === "catalogue-intake:ann:anime")?.last_results as { cursor: Record<string, unknown> }).cursor;

Deno.test("freshCachedReportPayloadIsNotDownloadedWhenMatchingIsDone", async () => {
  const db = fakeSupabase({
    tables: {
      catalogue_source_records: [reportRecord()],
      import_track_state: [{ track_key: "catalogue-intake:ann:anime", last_results: { cursor: { match_after_id: 0, fetch_after_link: 0, match_done_for_report: "h1" } } }],
    },
  });
  const selects = spyOnSelects(db);
  const { ctx } = ctxFor(db, []);
  await runAnn(ctx);
  assert.ok(selects.includes("payload_hash, fetched_at"), "freshness and version are read first");
  assert.ok(!selects.some((c) => c === "payload" || c === "payload, fetched_at"), `the multi-MB payload was read: ${selects.join(" | ")}`);
});

Deno.test("cachedReportPayloadIsReadOnceWhenMatchingIsPending", async () => {
  const db = fakeSupabase({ tables: { catalogue_source_records: [reportRecord()], anime: [kuro] } });
  const selects = spyOnSelects(db);
  const { ctx, net } = ctxFor(db, []);
  await runAnn(ctx);
  assert.equal(net.calls.length, 0, "a fresh cached report needs no request");
  assert.equal(selects.filter((c) => c === "payload").length, 1, "the payload is read exactly once, for matching");
  assert.equal(db.tables.catalogue_id_links.filter((l) => l.status === "accepted").length, 1, "matching still works from the lazily read report");
  assert.equal(cursorOf(db).match_done_for_report, "h1", "the report version is its hash");
});

Deno.test("aBatchTheSourceRejectsIsBisectedDownToTheBadId", async () => {
  const { net, client } = mkClient([xml("", 400), xml(ANN_API_BATCH), xml("", 400), xml(ANN_API_BATCH), xml("", 400)]);
  const out = await annFetch({ client }, [1, 2, 3, 4]);
  assert.deepEqual(net.calls.map((c) => idsIn(c.url).join("/")), ["1/2/3/4", "1/2", "3/4", "3", "4"]);
  assert.deepEqual(out.failed, [{ key: "ann:4", reason: "http 400" }]);
  assert.equal(out.stoppedEarly, undefined);
  assert.ok(out.records.length > 0, "the good ids were still read");
});

Deno.test("anAnnRecordRunDoesNotStallOnOneBadBatch", async () => {
  const db = fakeSupabase({ tables: { catalogue_source_records: [reportRecord()], catalogue_id_links: [accepted(1, "11"), accepted(2, "12")], import_track_state: [{ track_key: "catalogue-intake:ann:anime", last_results: { cursor: { match_done_for_report: "h1" } } }] } });
  const { ctx } = ctxFor(db, [xml("", 400), xml(ANN_API_BATCH), xml("", 400)]);
  const out = await runAnn(ctx);
  assert.equal(out.stoppedEarly, undefined);
  assert.equal(out.results.items_failed, 1);
  assert.deepEqual(out.results.failed_items, [{ key: "ann:12", reason: "http 400" }]);
  assert.equal(cursorOf(db).fetch_after_link, 0, "the pass finished");
});

Deno.test("aServerErrorStopsTheRunCountsThePageAndThreeRunsSkipIt", async () => {
  const tables = { catalogue_source_records: [reportRecord()], catalogue_id_links: [accepted(1, "11")], import_track_state: [{ track_key: "catalogue-intake:ann:anime", last_results: { cursor: { match_done_for_report: "h1" } } }] };
  const db = fakeSupabase({ tables });
  const fail = () => [xml("", 503), xml("", 503), xml("", 503)];
  const first = await runAnn(ctxFor(db, fail()).ctx);
  assert.equal(first.stoppedEarly, "source_error");
  assert.deepEqual(cursorOf(db).fails, { "page:0": 1 });
  assert.equal(cursorOf(db).fetch_after_link, 0, "the cursor stays before the page");
  await runAnn(ctxFor(db, fail()).ctx);
  await runAnn(ctxFor(db, fail()).ctx);
  assert.deepEqual(cursorOf(db).fails, { "page:0": 3 });
  const fourth = await runAnn(ctxFor(db, []).ctx);
  assert.equal(fourth.stoppedEarly, undefined);
  assert.deepEqual(fourth.results.failed_items, [{ key: "page:0", reason: "skipped_after_repeated_failures" }]);
  assert.deepEqual(cursorOf(db).fails, {}, "the skip clears the count");
});

Deno.test("aRejectedReportIsRecordedAndTheRecordsPhaseStillRuns", async () => {
  const stale = reportRecord(new Date(NOW - 8 * 86_400_000).toISOString());
  const db = fakeSupabase({ tables: { catalogue_source_records: [stale], catalogue_id_links: [accepted(1, "41045")] } });
  const { ctx, net } = ctxFor(db, [xml("", 400), xml(ANN_API_BATCH)]);
  const out = await runAnn(ctx);
  assert.equal(net.calls[0].url, ANN_REPORT_URL);
  assert.equal(out.results.items_failed, 1);
  assert.deepEqual(out.results.failed_items, [{ key: "report", reason: "http 400" }]);
  assert.equal(out.results.records_fetched, 1, "a bad report no longer blocks the records");
});

Deno.test("aReportServerErrorStopsTheRunAndCounts", async () => {
  const stale = reportRecord(new Date(NOW - 8 * 86_400_000).toISOString());
  const db = fakeSupabase({ tables: { catalogue_source_records: [stale] } });
  const { ctx } = ctxFor(db, [xml("", 500), xml("", 500), xml("", 500)]);
  const out = await runAnn(ctx);
  assert.equal(out.stoppedEarly, "source_error");
  assert.deepEqual(cursorOf(db).fails, { report: 1 });
});

Deno.test("aReportThatFailedThreeRunsIsSkippedAndTheCachedCopyUsed", async () => {
  const stale = reportRecord(new Date(NOW - 8 * 86_400_000).toISOString());
  const db = fakeSupabase({
    tables: { catalogue_source_records: [stale], anime: [kuro], import_track_state: [{ track_key: "catalogue-intake:ann:anime", last_results: { cursor: { fails: { report: 3 } } } }] },
  });
  const { ctx, net } = ctxFor(db, []);
  const out = await runAnn(ctx);
  assert.equal(net.calls.length, 0, "the report is not requested again");
  assert.deepEqual(out.results.failed_items, [{ key: "report", reason: "skipped_after_repeated_failures" }]);
  assert.equal(db.tables.catalogue_id_links.filter((l) => l.status === "accepted").length, 1, "matching used the cached (stale) report");
});

Deno.test("aFreshReportDownloadStoresItsHashAsTheVersion", async () => {
  const db = fakeSupabase({});
  const { ctx } = ctxFor(db, [xml(ANN_REPORT_SAMPLE)]);
  await runAnn(ctx);
  const stored = db.tables.catalogue_source_records.find((r) => r.source_key === "report:anime");
  assert.equal(cursorOf(db).match_done_for_report, stored?.payload_hash);
});
