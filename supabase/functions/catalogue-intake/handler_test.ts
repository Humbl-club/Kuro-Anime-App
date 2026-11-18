// Offline tests for the catalogue-intake request handler (Task 3): auth, lock, run bookkeeping,
// cursor. Run: cd supabase/functions/catalogue-intake && deno test --no-prompt
import { strict as assert } from "node:assert";
import { PoliteLimiter } from "../_shared/polite_fetch.ts";
import { createSourceClient } from "../_shared/catalogue/source_http.ts";
import { fakeSupabase, queuedFetch } from "./fake_supabase.ts";
import { handleRequest, type IntakeDeps } from "./handler.ts";

const fast = { sleep: () => Promise.resolve(), now: () => 0, random: () => 0 };

function request(body: unknown, secret: string | null = "s3cret") {
  return new Request("https://example.test/catalogue-intake", {
    method: "POST",
    headers: { "content-type": "application/json", ...(secret === null ? {} : { "x-import-secret": secret }) },
    body: JSON.stringify(body),
  });
}

function build(db: ReturnType<typeof fakeSupabase>, fetchResponses: Response[] = []) {
  const net = queuedFetch(fetchResponses);
  const mk = (source: "wikidata" | "ann" | "mangaupdates" | "pageviews") => createSourceClient(source, new PoliteLimiter(0), { ...fast, fetch: net.fetch });
  const deps: IntakeDeps = {
    supabase: db.client,
    clients: { wikidata: mk("wikidata"), ann: mk("ann"), mangaupdates: mk("mangaupdates"), pageviews: mk("pageviews") },
    now: () => 1_000_000,
  };
  return { deps, net };
}

const emptySparql = () => new Response(JSON.stringify({ head: { vars: [] }, results: { bindings: [] } }), { status: 200 });

Deno.test("wrongSecretIs401", async () => {
  const db = fakeSupabase();
  const { deps, net } = build(db);
  const res = await handleRequest(request({ handler: "wikidata", medium: "anime" }, "nope"), { secret: "s3cret", buildDeps: () => deps });
  assert.equal(res.status, 401);
  const none = await handleRequest(request({ handler: "wikidata", medium: "anime" }, null), { secret: "s3cret", buildDeps: () => deps });
  assert.equal(none.status, 401);
  assert.equal(db.rpcs.length, 0);
  assert.equal(net.calls.length, 0);
});

Deno.test("missingServerSecretIs500", async () => {
  const db = fakeSupabase();
  const { deps } = build(db);
  const res = await handleRequest(request({ handler: "wikidata", medium: "anime" }, ""), { secret: undefined, buildDeps: () => deps });
  assert.equal(res.status, 500);
});

Deno.test("lockHeldReturnsSkipped", async () => {
  const db = fakeSupabase({ lock: false, tables: { anime: [{ id: 1, anilist_id: 5 }] } });
  const { deps, net } = build(db);
  const res = await handleRequest(request({ handler: "wikidata", medium: "anime" }), { secret: "s3cret", buildDeps: () => deps });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.deepEqual({ skipped: body.skipped, reason: body.reason }, { skipped: true, reason: "locked" });
  assert.equal(net.calls.length, 0);
  const acquire = db.rpcs.find((r) => r.name === "acquire_import_lock");
  assert.deepEqual(acquire?.args, { p_key: "catalogue-intake:wikidata", p_ttl_seconds: 900 });
  assert.ok(!db.rpcs.some((r) => r.name === "release_import_lock"), "a run that did not acquire must not release");
});

Deno.test("unknownHandlerAndMissingMediumAre400", async () => {
  const db = fakeSupabase();
  const { deps } = build(db);
  const a = await handleRequest(request({ handler: "bogus", medium: "anime" }), { secret: "s3cret", buildDeps: () => deps });
  assert.equal(a.status, 400);
  const b = await handleRequest(request({ handler: "wikidata" }), { secret: "s3cret", buildDeps: () => deps });
  assert.equal(b.status, 400);
  assert.equal(db.rpcs.length, 0);
});

Deno.test("wikidataRunWalksFromTheCursorAndAdvancesIt", async () => {
  const db = fakeSupabase({
    tables: { anime: [{ id: 1, anilist_id: 10 }, { id: 2, anilist_id: 11 }, { id: 3, anilist_id: null }, { id: 4, anilist_id: 13 }] },
  });
  const { deps, net } = build(db, [emptySparql(), emptySparql()]);
  const call = () => handleRequest(request({ handler: "wikidata", medium: "anime", limit: 2 }), { secret: "s3cret", buildDeps: () => deps });
  const first = await (await call()).json();
  assert.equal(first.success, true);
  assert.equal(first.results.rows, 2);
  const cursor = db.tables.import_track_state.find((r) => r.track_key === "catalogue-intake:wikidata:anime");
  assert.equal((cursor?.last_results as { cursor: { last_id: number } }).cursor.last_id, 2);
  const second = await (await call()).json();
  assert.equal(second.results.rows, 1); // id 4 only: id 3 has no AniList id
  const cursor2 = db.tables.import_track_state.find((r) => r.track_key === "catalogue-intake:wikidata:anime");
  assert.equal((cursor2?.last_results as { cursor: { last_id: number } }).cursor.last_id, 0, "a finished pass wraps to the start");
  assert.equal(net.calls.length, 2);
  assert.ok(db.rpcs.filter((r) => r.name === "release_import_lock").length === 2);
  assert.equal(db.opsOn("import_runs", "insert").length, 2);
});

Deno.test("handlersNotBuiltYetAnswer501AndTakeNoLock", async () => {
  const db = fakeSupabase();
  const { deps } = build(db);
  const res = await handleRequest(request({ handler: "publish", medium: "anime" }), { secret: "s3cret", buildDeps: () => deps });
  assert.equal(res.status, 501);
  assert.equal(db.rpcs.length, 0);
});
