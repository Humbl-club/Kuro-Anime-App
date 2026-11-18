// Offline tests for Wikimedia pageviews (Task 6). Fetch is a fake; the Berserk reply is a real
// capture (2026-11-18, window 20251118..20261117), see fixtures/README.md.
// Run: cd supabase/functions/catalogue-intake && deno test --no-prompt
import { strict as assert } from "node:assert";
import { PoliteLimiter } from "../_shared/polite_fetch.ts";
import { createSourceClient } from "../_shared/catalogue/source_http.ts";
import { fakeSupabase, queuedFetch } from "./fake_supabase.ts";
import { pageviewsFetch, pageviewsUrl, runPageviews } from "./pageviews.ts";
import berserk from "./fixtures/pageviews_berserk_en.json" with { type: "json" };
import missing from "./fixtures/pageviews_missing_404.json" with { type: "json" };

const NOW = Date.parse("2026-11-18T12:00:00Z");
const json = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...headers } });

function client(responses: Response[], spacing = 0, clock?: { t: number }) {
  const net = queuedFetch(responses);
  const c = createSourceClient("pageviews", new PoliteLimiter(spacing), {
    fetch: net.fetch,
    sleep: (ms) => { if (clock) clock.t += ms; return Promise.resolve(); },
    now: () => clock?.t ?? 0,
    random: () => 0,
  });
  return { net, client: c };
}

Deno.test("encodesTitlesWithSlashesAndSpaces", () => {
  const url = (title: string) => pageviewsUrl("en.wikipedia", title, "20251118", "20261117");
  const base = "https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/en.wikipedia/all-access/user/";
  assert.equal(url("Fate/stay night"), `${base}Fate%2Fstay_night/daily/20251118/20261117`);
  assert.equal(url("Berserk (manga)"), `${base}Berserk_(manga)/daily/20251118/20261117`);
  assert.equal(url("100% Pascal-sensei?"), `${base}100%25_Pascal-sensei%3F/daily/20251118/20261117`);
  assert.equal(url("Re:Zero"), `${base}Re%3AZero/daily/20251118/20261117`);
});

Deno.test("windowIsThe365DaysEndingYesterdayUtc", async () => {
  const { net, client: c } = client([json({ items: [] })]);
  await pageviewsFetch({ client: c, nowMs: NOW }, [{ mediaKey: "1", project: "en.wikipedia", title: "X" }]);
  assert.ok(net.calls[0].url.endsWith("/daily/20251118/20261117"), net.calls[0].url);
});

Deno.test("sumsFixtureIntoTotalAndTwoThirtyDayWindows", async () => {
  const { client: c } = client([json(berserk)]);
  const out = await pageviewsFetch({ client: c, nowMs: NOW }, [{ mediaKey: "7", project: "en.wikipedia", title: "Berserk (manga)" }]);
  const items = (berserk as { items: { timestamp: string; views: number }[] }).items;
  const sum = (pred: (ts: string) => boolean) => items.filter((i) => pred(i.timestamp)).reduce((a, i) => a + i.views, 0);
  assert.equal(out.results.length, 1);
  assert.deepEqual(out.results[0], {
    mediaKey: "7",
    total365: sum(() => true),
    last30: sum((ts) => ts >= "2026101900"),
    prev30: sum((ts) => ts >= "2026091900" && ts < "2026101900"),
  });
  assert.ok(out.results[0].total365 > 100_000 && out.results[0].last30 > 0 && out.results[0].prev30 > 0);
});

Deno.test("missingArticleStoresZeros", async () => {
  const { client: c } = client([json(missing, 404)]);
  const out = await pageviewsFetch({ client: c, nowMs: NOW }, [{ mediaKey: "9", project: "ja.wikipedia", title: "KuroNoSuchArticleZzz" }]);
  assert.deepEqual(out.results, [{ mediaKey: "9", total365: 0, last30: 0, prev30: 0 }]);
});

Deno.test("sumsBothProjects", async () => {
  const day = (ts: string, views: number) => ({ timestamp: ts, views });
  const en = { items: [day("2026111700", 10), day("2026101900", 5), day("2026091900", 2)] };
  const ja = { items: [day("2026111700", 1), day("2025111800", 4)] };
  const { net, client: c } = client([json(en), json(ja)]);
  const out = await pageviewsFetch({ client: c, nowMs: NOW }, [
    { mediaKey: "3", project: "en.wikipedia", title: "A" },
    { mediaKey: "3", project: "ja.wikipedia", title: "あ" },
  ]);
  assert.equal(net.calls.length, 2);
  assert.ok(net.calls[1].url.includes("/ja.wikipedia/") && net.calls[1].url.includes(encodeURIComponent("あ")));
  assert.deepEqual(out.results, [{ mediaKey: "3", total365: 22, last30: 16, prev30: 2 }]);
});

Deno.test("serverErrorIsNotZeros", async () => {
  const { client: c } = client([json({}, 400)]);
  await assert.rejects(() => pageviewsFetch({ client: c, nowMs: NOW }, [{ mediaKey: "1", project: "en.wikipedia", title: "X" }]), /pageviews http 400/);
});

Deno.test("stopMidWayReturnsOnlyCompletedTitles", async () => {
  const clock = { t: 0 };
  const { net, client: c } = client([json({ items: [] }), json({ items: [] })], 100, clock);
  // Spacing 100 ms, budget 50 ms: the first call goes out, the second cannot start.
  const out = await pageviewsFetch({ client: c, nowMs: NOW, deadlineMs: 50 }, [
    { mediaKey: "1", project: "en.wikipedia", title: "A" },
    { mediaKey: "2", project: "en.wikipedia", title: "B" },
  ]);
  assert.equal(net.calls.length, 1);
  assert.equal(out.stoppedEarly, "budget");
  assert.deepEqual(out.results.map((r) => r.mediaKey), ["1"]);
});

// ---- run-level -------------------------------------------------------------------------------

const wikidataLink = (id: number, kuro: number, qid: string) => ({ id, kind: "manga", kuro_id: kuro, source: "wikidata", source_key: qid, method: "wikidata", confidence: 1, status: "accepted" });
const wdRecord = (qid: string, props: Record<string, string[]>) => ({ source: "wikidata", source_key: qid, medium: "manga", payload: { qid, props }, payload_hash: "h", licence: "CC0-1.0", fetched_at: "2026-11-01T00:00:00Z" });

function ctxFor(db: ReturnType<typeof fakeSupabase>, responses: Response[], over: { limit?: number } = {}) {
  const { net, client: c } = client(responses);
  const other = createSourceClient("wikidata", new PoliteLimiter(0), { fetch: net.fetch });
  return {
    net,
    ctx: { supabase: db.client, clients: { wikidata: other, ann: other, mangaupdates: other, pageviews: c }, medium: "manga" as const, limit: over.limit, deadlineMs: 50_000, now: () => NOW },
  };
}

Deno.test("runStoresOneRecordPerKuroTitleAndSkipsFreshOnes", async () => {
  const db = fakeSupabase({
    tables: {
      catalogue_id_links: [wikidataLink(1, 11, "Q1"), wikidataLink(2, 12, "Q2"), wikidataLink(3, 13, "Q3")],
      catalogue_source_records: [
        wdRecord("Q1", { "sitelink:enwiki": ["Berserk (manga)"], "sitelink:jawiki": ["ベルセルク"] }),
        wdRecord("Q2", {}), // no Wikipedia article: nothing to fetch, nothing stored
        wdRecord("Q3", { "sitelink:enwiki": ["Fresh"] }),
        { source: "pageviews", source_key: "13", medium: "manga", payload: { total365: 1, last30: 1, prev30: 1 }, payload_hash: "x", licence: "CC0-1.0", fetched_at: "2026-11-15T00:00:00Z" },
      ],
    },
  });
  const { ctx, net } = ctxFor(db, [json(berserk), json({ items: [{ timestamp: "2026111700", views: 3 }] })]);
  const out = await runPageviews(ctx);
  assert.equal(net.calls.length, 2, "two projects for Q1; Q2 has no article and Q3's record is under a week old");
  const rec = db.tables.catalogue_source_records.find((r) => r.source === "pageviews" && r.source_key === "11");
  assert.ok(rec);
  assert.equal(rec.licence, "CC0-1.0");
  assert.equal(rec.medium, "manga");
  const p = rec.payload as { total365: number; last30: number; prev30: number };
  assert.deepEqual(Object.keys(p).sort(), ["last30", "prev30", "total365"]);
  assert.ok(p.total365 > 100_000);
  assert.ok(!db.tables.catalogue_source_records.some((r) => r.source === "pageviews" && r.source_key === "12"));
  assert.equal(out.results.titles_stored, 1);

  // A second run inside the week makes no request.
  const again = ctxFor(db, []);
  const out2 = await runPageviews(again.ctx);
  assert.equal(again.net.calls.length, 0);
  assert.equal(out2.results.titles_stored, 0);
});
