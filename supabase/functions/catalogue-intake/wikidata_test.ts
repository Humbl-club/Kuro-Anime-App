// Offline tests for the Wikidata crosswalk (Task 3). No network: fetch is a fake.
// Run: cd supabase/functions/catalogue-intake && deno test --no-prompt
import { strict as assert } from "node:assert";
import { PoliteLimiter } from "../_shared/polite_fetch.ts";
import { createSourceClient } from "../_shared/catalogue/source_http.ts";
import { fakeSupabase, queuedFetch } from "./fake_supabase.ts";
import { runWikidata, wikidataCrosswalk } from "./wikidata.ts";

const fast = { sleep: () => Promise.resolve(), now: () => 0, random: () => 0 };
import q123 from "./fixtures/wikidata_q123.json" with { type: "json" };
// Real Wikidata Query Service replies captured 2026-11-18 (see fixtures/README.md).
import liveAnime from "./fixtures/wikidata_anime_live.json" with { type: "json" };
import liveManga from "./fixtures/wikidata_manga_live.json" with { type: "json" };

const sparql = (bindings: unknown[]) =>
  new Response(JSON.stringify({ head: { vars: [] }, results: { bindings } }), { status: 200, headers: { "content-type": "application/sparql-results+json" } });

const lit = (value: string) => ({ type: "literal", value });
const uri = (q: string) => ({ type: "uri", value: `http://www.wikidata.org/entity/${q}` });
const row = (aid: string, q: string, p: string, v: string) => ({ aid: lit(aid), item: uri(q), p: lit(p), v: lit(v) });

function setup(responses: Response[], tables: Record<string, Record<string, unknown>[]> = {}) {
  const db = fakeSupabase({ tables });
  const net = queuedFetch(responses);
  const client = createSourceClient("wikidata", new PoliteLimiter(0), { ...fast, fetch: net.fetch });
  return { db, net, deps: { supabase: db.client, client } };
}

Deno.test("linksThroughHeldAniListId", async () => {
  const { db, deps, net } = setup([sparql(q123.results.bindings)]);
  const res = await wikidataCrosswalk(deps, "anime", [{ id: 7, anilist_id: 16498 }, { id: 8, anilist_id: 99999 }]);
  assert.equal(res.conflicts.length, 0);
  assert.equal(res.linked, 1); // only the Wikidata item itself; the ANN id it carries is proposed
  assert.equal(net.calls.length, 1);

  const record = db.tables.catalogue_source_records.find((r) => r.source === "wikidata");
  assert.ok(record);
  assert.equal(record.source_key, "Q123");
  assert.equal(record.medium, "anime");
  assert.equal(record.licence, "CC0-1.0");
  const payload = record.payload as { props: Record<string, string[]> };
  assert.deepEqual(payload.props["sitelink:enwiki"], ["Attack on Titan (TV series)"]);

  const links = db.tables.catalogue_id_links;
  const wd = links.find((l) => l.source === "wikidata");
  assert.deepEqual(
    { kind: wd?.kind, kuro_id: wd?.kuro_id, source_key: wd?.source_key, method: wd?.method, confidence: wd?.confidence, status: wd?.status },
    { kind: "anime", kuro_id: 7, source_key: "Q123", method: "wikidata", confidence: 1, status: "accepted" },
  );
  const ann = links.find((l) => l.source === "ann");
  assert.deepEqual({ kuro_id: ann?.kuro_id, source_key: ann?.source_key, status: ann?.status, method: ann?.method }, { kuro_id: 7, source_key: "13592", status: "proposed", method: "wikidata" });
  // Kuro row 8 has no Wikidata item: nothing is written for it.
  assert.ok(!links.some((l) => l.kuro_id === 8));
});

Deno.test("duplicateAniListClaimLinksNothing", async () => {
  const { db, deps } = setup([
    sparql([
      row("555", "Q1", "P8729", "555"),
      row("555", "Q1", "P1985", "111"),
      row("555", "Q2", "P8729", "555"),
      row("555", "Q2", "P1985", "222"),
    ]),
  ]);
  const res = await wikidataCrosswalk(deps, "anime", [{ id: 3, anilist_id: 555 }]);
  assert.equal(res.conflicts.length, 1);
  assert.equal(res.conflicts[0].kuroIds[0], 3);
  assert.equal(res.linked, 0);
  const links = db.tables.catalogue_id_links ?? [];
  assert.equal(links.filter((l) => l.status === "accepted").length, 0);
  // The conflict is kept for review as proposed links; no ANN id is accepted from either item.
  assert.ok(links.length >= 2 && links.every((l) => l.status === "proposed" && l.source === "wikidata"));
  // Raw records are still retained.
  assert.equal(db.tables.catalogue_source_records.length, 2);
});

Deno.test("sameItemForTwoKuroRowsIsAConflict", async () => {
  const { db, deps } = setup([sparql([row("10", "Q9", "P8729", "10"), row("11", "Q9", "P8729", "11")])]);
  const res = await wikidataCrosswalk(deps, "anime", [{ id: 1, anilist_id: 10 }, { id: 2, anilist_id: 11 }]);
  assert.equal(res.conflicts.length, 1);
  assert.equal((db.tables.catalogue_id_links ?? []).filter((l) => l.status === "accepted").length, 0);
});

Deno.test("unchangedPayloadWritesNothing", async () => {
  const bindings = q123.results.bindings;
  const first = setup([sparql(bindings)]);
  await wikidataCrosswalk(first.deps, "anime", [{ id: 7, anilist_id: 16498 }]);
  const afterFirst = { records: first.db.tables.catalogue_source_records, links: first.db.tables.catalogue_id_links };

  const second = setup([sparql(bindings)], { catalogue_source_records: afterFirst.records, catalogue_id_links: afterFirst.links });
  const res = await wikidataCrosswalk(second.deps, "anime", [{ id: 7, anilist_id: 16498 }]);
  assert.equal(second.db.ops.length, 0, JSON.stringify(second.db.ops));
  assert.equal(res.linked, 0);
});

Deno.test("changedPayloadUpdatesTheRecordOnly", async () => {
  const first = setup([sparql(q123.results.bindings)]);
  await wikidataCrosswalk(first.deps, "anime", [{ id: 7, anilist_id: 16498 }]);
  const changed = [...q123.results.bindings, row("16498", "Q123", "label:ja", "進撃の巨人")];
  const second = setup([sparql(changed)], { catalogue_source_records: first.db.tables.catalogue_source_records, catalogue_id_links: first.db.tables.catalogue_id_links });
  await wikidataCrosswalk(second.deps, "anime", [{ id: 7, anilist_id: 16498 }]);
  assert.equal(second.db.opsOn("catalogue_source_records", "upsert").length, 1);
  assert.equal(second.db.opsOn("catalogue_id_links").length, 0);
});

Deno.test("batchesAtMost500Ids", async () => {
  const rows = Array.from({ length: 1201 }, (_, i) => ({ id: i + 1, anilist_id: 1000 + i }));
  const { deps, net } = setup([sparql([]), sparql([]), sparql([])]);
  const res = await wikidataCrosswalk(deps, "anime", rows);
  assert.equal(net.calls.length, 3);
  assert.equal(res.queries, 3);
  const counts = net.calls.map((c) => (c.body.match(/"\d+"/g) ?? []).length);
  assert.deepEqual(counts, [500, 500, 201]);
  assert.ok(net.calls.every((c) => c.init?.method === "POST"));
  assert.equal((net.calls[0].init?.headers as Record<string, string>)["Content-Type"], "application/sparql-query");
  assert.match(net.calls[0].body, /wdt:P8729/);
  assert.equal(res.completedRows, 1201);
});

Deno.test("mangaUsesTheMangaProperty", async () => {
  const { deps, net } = setup([sparql([])]);
  await wikidataCrosswalk(deps, "manga", [{ id: 1, anilist_id: 30002 }]);
  assert.match(net.calls[0].body, /wdt:P8731/);
  assert.doesNotMatch(net.calls[0].body, /wdt:P8729/);
  assert.match(net.calls[0].body, /wdt:P11149/);
});

Deno.test("budgetStopKeepsCompletedBatchesOnly", async () => {
  const rows = Array.from({ length: 600 }, (_, i) => ({ id: i + 1, anilist_id: 1000 + i }));
  const db = fakeSupabase();
  const net = queuedFetch([sparql([row("1000", "Q5", "P8729", "1000")]), sparql([])]);
  let t = 0;
  const client = createSourceClient("wikidata", new PoliteLimiter(1000), { fetch: net.fetch, sleep: () => Promise.resolve(), now: () => t, random: () => 0 });
  // Second query would have to wait for the 1 s spacing, past the deadline.
  const res = await wikidataCrosswalk({ supabase: db.client, client, deadlineMs: 500 }, "anime", rows);
  t = 0;
  assert.equal(res.queries, 1);
  assert.equal(res.completedRows, 500);
  assert.equal(res.stoppedEarly, "budget");
});

Deno.test("aRejectedRowIsRecordedFailedAndWritesNothing", async () => {
  const { db, deps } = setup([new Response("{}", { status: 400 })]);
  const res = await wikidataCrosswalk(deps, "anime", [{ id: 1, anilist_id: 1 }]);
  assert.deepEqual(res.failed, [{ key: "row:1", reason: "http 400" }]);
  assert.equal(res.completedRows, 1, "the cursor may advance past a row the source rejects");
  assert.equal(db.ops.length, 0);
});

Deno.test("parsesLiveAnimeCapture", async () => {
  const { db, deps } = setup([new Response(JSON.stringify(liveAnime), { status: 200 })]);
  const res = await wikidataCrosswalk(deps, "anime", [{ id: 1, anilist_id: 16498 }, { id: 2, anilist_id: 21355 }, { id: 3, anilist_id: 1 }]);
  assert.equal(res.conflicts.length, 0);
  assert.equal(db.tables.catalogue_source_records.length, 3);
  const links = db.tables.catalogue_id_links;
  assert.equal(links.filter((l) => l.source === "wikidata").length, 3);
  const ann = links.filter((l) => l.source === "ann");
  assert.deepEqual(ann.map((l) => [l.kuro_id, l.source_key]).sort(), [[1, "14950"], [2, "17360"], [3, "13"]]);
  assert.ok(ann.every((l) => l.status === "proposed"));
  const bebop = db.tables.catalogue_source_records.find((r) => r.source_key === "Q101244908")!.payload as { props: Record<string, string[]> };
  assert.deepEqual(bebop.props["sitelink:jawiki"], ["カウボーイビバップ"]);
});

Deno.test("parsesLiveMangaCaptureAndConvertsMangaUpdatesSlug", async () => {
  const { db, deps } = setup([new Response(JSON.stringify(liveManga), { status: 200 })]);
  const res = await wikidataCrosswalk(deps, "manga", [{ id: 1, anilist_id: 30002 }, { id: 2, anilist_id: 30013 }]);
  assert.equal(res.conflicts.length, 0);
  const mu = db.tables.catalogue_id_links.filter((l) => l.source === "mangaupdates");
  // "njeqwry" is Berserk's MangaUpdates slug; base 36 gives the API's numeric series id.
  assert.deepEqual(mu.map((l) => [l.kuro_id, l.source_key]).sort(), [[1, "51239621230"], [2, String(parseInt("pb8uwds", 36))]]);
  assert.ok(mu.every((l) => l.status === "proposed" && l.method === "wikidata"));
  assert.ok(!db.tables.catalogue_id_links.some((l) => l.source === "ann"), "manga does not link ANN (anime handler only)");
});

Deno.test("wikidataDerivedAnnIdIsProposed", async () => {
  const { db, deps } = setup([sparql(q123.results.bindings)]);
  await wikidataCrosswalk(deps, "anime", [{ id: 7, anilist_id: 16498 }]);
  const ann = db.tables.catalogue_id_links.filter((l) => l.source === "ann");
  assert.equal(ann.length, 1);
  assert.deepEqual({ status: ann[0].status, method: ann[0].method, decided: ann[0].decided_at }, { status: "proposed", method: "wikidata", decided: undefined });
  // The Q-id found through our own AniList id stays accepted.
  assert.equal(db.tables.catalogue_id_links.find((l) => l.source === "wikidata")?.status, "accepted");
});

Deno.test("changedWikidataItemDoesNotReplaceAcceptedLink", async () => {
  const first = setup([sparql(q123.results.bindings)]);
  await wikidataCrosswalk(first.deps, "anime", [{ id: 7, anilist_id: 16498 }]);
  // Someone edits Wikidata: AniList id 16498 now sits on a different item Q999, which carries another ANN id.
  const edited = [row("16498", "Q999", "P8729", "16498"), row("16498", "Q999", "P1985", "777")];
  const second = setup([sparql(edited)], { catalogue_source_records: first.db.tables.catalogue_source_records, catalogue_id_links: first.db.tables.catalogue_id_links });
  const res = await wikidataCrosswalk(second.deps, "anime", [{ id: 7, anilist_id: 16498 }]);
  const links = second.db.tables.catalogue_id_links;
  const accepted = links.filter((l) => l.status === "accepted");
  assert.deepEqual(accepted.map((l) => [l.source, l.source_key]), [["wikidata", "Q123"]], "the existing accepted link stays");
  assert.ok(links.some((l) => l.source === "wikidata" && l.source_key === "Q999" && l.status === "proposed"));
  assert.ok(res.conflicts.some((c) => c.source === "wikidata" && c.reason === "title_already_linked_to_other_key"));
  assert.equal(res.linked, 0);
});

// ---- review fixes (2026-11-18) ---------------------------------------------------------------

Deno.test("duplicateClaimAcrossBatchesLinksNothing", async () => {
  // Item Q7 lists AniList ids 1000 and 1500; Kuro has a row for each, 500 rows apart so they fall in different batches.
  const rows = Array.from({ length: 501 }, (_, i) => ({ id: i + 1, anilist_id: 1000 + i }));
  const { db, deps } = setup(
    [
      sparql([row("1000", "Q7", "P8729", "1000"), row("1000", "Q7", "P8729", "1500"), row("1000", "Q7", "P1985", "777")]),
      sparql([row("1500", "Q7", "P8729", "1000"), row("1500", "Q7", "P8729", "1500"), row("1500", "Q7", "P1985", "777")]),
    ],
    { anime: rows },
  );
  const res = await wikidataCrosswalk(deps, "anime", rows);
  const links = db.tables.catalogue_id_links ?? [];
  assert.equal(links.filter((l) => l.status === "accepted").length, 0, "no accepted link from a duplicate claim, whatever the batch");
  assert.deepEqual(
    links.filter((l) => l.source === "wikidata").map((l) => [l.kuro_id, l.source_key, l.status]).sort(),
    [[1, "Q7", "proposed"], [501, "Q7", "proposed"]],
  );
  assert.ok(!links.some((l) => l.source === "ann"), "no ANN id is derived from a contested item");
  assert.equal(res.linked, 0);
  assert.equal(res.conflicts.length, 2, JSON.stringify(res.conflicts));
  assert.ok(res.conflicts.every((c) => c.reason === "item_claims_several_titles" && c.sourceKey === "Q7"));
  // The raw record is still kept once.
  assert.equal(db.tables.catalogue_source_records.filter((r) => r.source_key === "Q7").length, 1);
});

Deno.test("claimingSeveralIdsWhereOnlyOneMapsToKuroStillLinks", async () => {
  // Q8 also lists AniList id 424242, which Kuro does not hold: that is not a duplicate claim between Kuro titles.
  const { db, deps } = setup([sparql([row("10", "Q8", "P8729", "10"), row("10", "Q8", "P8729", "424242")])], { anime: [{ id: 1, anilist_id: 10 }] });
  const res = await wikidataCrosswalk(deps, "anime", [{ id: 1, anilist_id: 10 }]);
  assert.equal(res.conflicts.length, 0);
  assert.equal(db.tables.catalogue_id_links.filter((l) => l.status === "accepted").length, 1);
});

Deno.test("itemAlreadyHeldByAnotherTitleLinksNothing", async () => {
  const stored = [{ id: 1, kind: "anime", kuro_id: 2, source: "wikidata", source_key: "Q9", method: "wikidata", status: "accepted" }];
  const { db, deps } = setup([sparql([row("10", "Q9", "P8729", "10"), row("10", "Q9", "P1985", "55")])], { anime: [{ id: 1, anilist_id: 10 }, { id: 2, anilist_id: 11 }], catalogue_id_links: stored });
  const res = await wikidataCrosswalk(deps, "anime", [{ id: 1, anilist_id: 10 }]);
  assert.equal(db.tables.catalogue_id_links.filter((l) => l.status === "accepted").length, 1, "only the stored link stays accepted");
  assert.ok(db.tables.catalogue_id_links.some((l) => l.kuro_id === 1 && l.source_key === "Q9" && l.status === "proposed"));
  assert.ok(!db.tables.catalogue_id_links.some((l) => l.source === "ann"), "no derived ANN id from an item another title holds");
  assert.ok(res.conflicts.length >= 1);
});

Deno.test("wikidataReadsOnlyWhenAnItemClaimsSeveralIds", async () => {
  const { db, deps } = setup([sparql(q123.results.bindings)], { anime: [{ id: 7, anilist_id: 16498 }] });
  await wikidataCrosswalk(deps, "anime", [{ id: 7, anilist_id: 16498 }]);
  assert.equal(db.reads.filter((r) => r.table === "anime").length, 0, "single-claim items need no extra Kuro read");
});

// ---- one bad item must not stall the handler (review 2026-11-18) -------------------------------------

const bad = () => new Response("{}", { status: 400 });

Deno.test("aRejectedBatchIsBisectedDownToTheBadRow", async () => {
  const rows = [1, 2, 3, 4].map((i) => ({ id: i, anilist_id: 100 + i }));
  const { net, deps } = setup([bad(), sparql([]), bad(), sparql([]), bad()]);
  const res = await wikidataCrosswalk(deps, "anime", rows);
  assert.equal(net.calls.length, 5);
  assert.deepEqual(res.failed, [{ key: "row:4", reason: "http 400" }]);
  assert.equal(res.completedRows, 4);
  assert.equal(res.stoppedEarly, undefined);
});

Deno.test("anUnreadableAnswerIsTreatedAsTheRowsOwnFault", async () => {
  const { deps } = setup([new Response("<html>", { status: 200 })]);
  const res = await wikidataCrosswalk(deps, "anime", [{ id: 1, anilist_id: 1 }]);
  assert.deepEqual(res.failed.map((f) => f.key), ["row:1"]);
  assert.equal(res.completedRows, 1);
});

Deno.test("aServerErrorStopsTheRunAndCountsAgainstTheBatch", async () => {
  const failures: Record<string, number> = {};
  const { deps } = setup([new Response("x", { status: 503 }), new Response("x", { status: 503 }), new Response("x", { status: 503 })]);
  const res = await wikidataCrosswalk({ ...deps, failures }, "anime", [{ id: 7, anilist_id: 1 }]);
  assert.equal(res.stoppedEarly, "source_error");
  assert.equal(res.completedRows, 0);
  assert.deepEqual(failures, { "b:7": 1 });
});

Deno.test("aBatchThatFailedThreeRunsInARowIsSkippedAndRecorded", async () => {
  const db = fakeSupabase({
    tables: {
      anime: [{ id: 1, anilist_id: 11 }, { id: 2, anilist_id: 12 }],
      import_track_state: [{ track_key: "catalogue-intake:wikidata:anime", last_results: { cursor: { last_id: 0, fails: { "b:1": 3 } } } }],
    },
  });
  const net = queuedFetch([]);
  const client = createSourceClient("wikidata", new PoliteLimiter(0), { ...fast, fetch: net.fetch });
  const other = client;
  const out = await runWikidata({ supabase: db.client, clients: { wikidata: client, ann: other, mangaupdates: other, pageviews: other }, medium: "anime", limit: undefined, deadlineMs: 50_000, now: () => 0 });
  assert.equal(net.calls.length, 0, "the poisoned batch is not requested again");
  assert.equal(out.stoppedEarly, undefined);
  assert.deepEqual(out.results.failed_items, [{ key: "b:1", reason: "skipped_after_repeated_failures" }]);
  const cur = (db.tables.import_track_state[0].last_results as { cursor: { last_id: number; fails: Record<string, number> } }).cursor;
  assert.equal(cur.last_id, 0, "the pass finished (fewer rows than the limit)");
  assert.deepEqual(cur.fails, {});
});
