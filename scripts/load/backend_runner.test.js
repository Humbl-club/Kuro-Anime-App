"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { setTimeout: sleep } = require("node:timers/promises");
const { run } = require("../load_test_backend");
const { ORIGIN } = require("./backend_workload");
const fixture = {
  origin: ORIGIN,
  runId: "kuro-load-unit",
  anonKey: "public",
  accounts: [0, 1].map((i) => ({
    id: String(i),
    token: "fixture",
    email: "kuro-load-unit-" + i + "@example.invalid",
    librarySize: 0,
  })),
  media: { anime: [1], manga: [2] },
};
test("fixed arrival scheduling counts saturated starts instead of slowing offered traffic", async (t) => {
  t.mock.method(global, "fetch", async () => {
    await sleep(300);
    return new Response(
      JSON.stringify({ active: [], home_revision: 0, club: { state: "none" } }),
      {
        status: 200,
        headers: {
          "x-envoy-upstream-service-time": "7.5",
          "set-cookie": "test-credential",
        },
      },
    );
  });
  const r = await run({
    production: true,
    rps: 10,
    duration: .6,
    vus: 2,
    maxRequests: 20,
    only: "home",
  }, fixture);
  assert.equal(r.summary.offered, 6);
  assert.ok(r.summary.dropped > 0);
  assert.equal(r.summary.errors, 0);
  assert.equal(r.summary.pass, false);
  assert.ok(r.generator.maxStartLagMs < 150);
  assert.equal(r.distinctAccounts, 2);
  assert.ok(
    r.samples.every((x) => x.upstreamMs === 7.5 && x.responseStartMs >= 0),
  );
  assert.ok(!JSON.stringify(r.samples).includes("test-credential"));
});
test("a configured safety stop prevents sending the first request", async (t) => {
  const fs = require("node:fs"),
    os = require("node:os"),
    path = require("node:path");
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "kuro-stop-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const stopFile = path.join(dir, "STOP");
  fs.writeFileSync(stopFile, "test");
  let calls = 0;
  t.mock.method(global, "fetch", () => {
    calls++;
    throw new Error("unexpected network");
  });
  const r = await run({
    production: true,
    rps: 2,
    duration: .1,
    vus: 2,
    maxRequests: 20,
    only: "home",
    stopFile,
  }, fixture);
  assert.equal(calls, 0);
  assert.equal(r.summary.pass, false);
  assert.match(r.stopReason, /safety stop/);
});
// ---- F3.1: the profile lane never disturbs the base lane ----
const W = require("./backend_workload");
const laneFixture = {
  ...fixture,
  accounts: [0, 1].map((i) => ({
    id: String(i),
    token: "tok" + i,
    email: "kuro-load-unit-" + i + "@example.invalid",
    librarySize: 0,
  })),
};
// Answers immediately with a valid body for every base kind and for x-test.
function validAnswer(url, init) {
  const p = new URL(url).pathname;
  const body = init.body ? JSON.parse(init.body) : {};
  const json = (x) => new Response(JSON.stringify(x), { status: 200 });
  if (p.endsWith("/x_test")) return json([{ id: 1 }]);
  if (p.endsWith("/home_bundle_v1")) {
    return json({ active: [], home_revision: 0, club: { state: "none" } });
  }
  if (/\/(browse|search)_/.test(p) || p.endsWith("/discover_mood_v1")) return json([{ id: 1 }]);
  if (p.endsWith("/series_detail_bundle_v1")) {
    return json({ header: { title: "t" }, media_id: 1, units: [] });
  }
  if (p.endsWith("/discover_bundle")) return json({ anime: {}, manga: {} });
  if (p.includes("club")) return json({});
  if (p.endsWith("/concierge-parse")) {
    return json({ success: true, userId: init.headers.Authorization.slice(-1), items: [{}] });
  }
  if (p.endsWith("/concierge-recommend")) return json({ success: true, narrated: false, items: [{}] });
  return json(body);
}
const xProfile = (validate = (d) => Array.isArray(d)) =>
  Object.freeze({
    name: "x-test",
    budgetClass: "browse",
    ratePerSecond: 5,
    request: () => ({ path: "/rest/v1/rpc/x_test", body: {} }),
    validate,
  });
const laneConfig = { production: true, rps: 10, duration: 1, vus: 2, maxRequests: 20 };
// Short profile-only-ish runs: base lane at 1 rps (one request), profile at 2 rps over 1 s.
const optConfig = { production: true, rps: 1, duration: 1, vus: 2, maxRequests: 20, only: "home", trackerGaps: ["o-test"] };
function recordingFetch(t, answer) {
  const calls = [];
  t.mock.method(global, "fetch", async (url, init) => {
    const p = new URL(url).pathname;
    calls.push({ path: p, search: new URL(url).search, method: init.method, headers: init.headers, body: init.body });
    if (p.endsWith("/home_bundle_v1")) {
      return new Response(JSON.stringify({ active: [], home_revision: 0, club: { state: "none" } }), { status: 200 });
    }
    return answer(p, init);
  });
  return calls;
}
test("GET and anonymous requests", async (t) => {
  const calls = recordingFetch(t, () => new Response(JSON.stringify([{ id: 1 }]), { status: 200 }));
  const profile = Object.freeze({
    name: "o-test",
    budgetClasses: ["browse", "detail"],
    ratePerSecond: 2,
    request: (a, f, seq) => seq % 2
      ? { method: "GET", anonymous: true, budgetClass: "detail", path: "/rest/v1/anime?id=eq.1" }
      : { budgetClass: "browse", path: "/rest/v1/rpc/o_test", body: {} },
    validate: (d) => Array.isArray(d),
  });
  const r = await run(optConfig, structuredClone(laneFixture), { profiles: { "o-test": profile } });
  const get = calls.find((c) => c.path === "/rest/v1/anime");
  assert.equal(get.method, "GET");
  assert.equal(get.search, "?id=eq.1");
  assert.equal(get.body, undefined);
  assert.equal(get.headers["Content-Type"], undefined);
  assert.equal(get.headers.Authorization, "Bearer public");
  const post = calls.find((c) => c.path === "/rest/v1/rpc/o_test");
  assert.equal(post.method, "POST");
  assert.match(post.headers.Authorization, /^Bearer tok/);
  assert.deepEqual(Object.keys(r.lanes.profiles.summary.endpoints).sort(), ["o-test:browse", "o-test:detail"]);
});
test("PATCH and multi-step actions", async (t) => {
  let aStatus = 200;
  const calls = recordingFetch(t, (p, init) => {
    if (p.endsWith("/x")) return new Response(JSON.stringify(aStatus === 200 ? { ok: 1 } : { code: "boom" }), { status: aStatus });
    return new Response(JSON.stringify([{ id: 1 }]), { status: 200 });
  });
  const action = {
    steps: [
      { operation: "a", path: "/rest/v1/rpc/x", body: {} },
      { operation: "b", method: "PATCH", path: "/rest/v1/anime_user_lists?id=eq.1", body: { started_raw: "2026-03-02" } },
    ],
  };
  const profile = (request) => Object.freeze({
    name: "o-test",
    operations: { a: { budgetClass: "progress" }, b: { budgetClass: "progress" } },
    ratePerSecond: 1,
    request,
    validate: () => true,
  });
  const r = await run({ ...optConfig }, structuredClone(laneFixture), { profiles: { "o-test": profile(() => action) } });
  const own = calls.filter((c) => c.path !== "/rest/v1/rpc/home_bundle_v1");
  assert.deepEqual(own.map((c) => c.method), ["POST", "PATCH"]);
  assert.ok(own.every((c) => /^Bearer tok/.test(c.headers.Authorization)));
  assert.equal(own[1].headers.Prefer, "return=representation");
  assert.equal(own[1].headers["Content-Type"], "application/json");
  assert.deepEqual(JSON.parse(own[1].body), { started_raw: "2026-03-02" });
  assert.deepEqual(Object.keys(r.lanes.profiles.summary.endpoints).sort(), ["o-test:a", "o-test:b"]);
  assert.equal(r.lanes.profiles.summary.endpoints["o-test:a"].requests, 1);
  assert.equal(r.lanes.profiles.summary.endpoints["o-test:b"].requests, 1);
  // First failing step ends the action; later steps are counted, not sampled.
  aStatus = 500;
  calls.length = 0;
  const r2 = await run({ ...optConfig }, structuredClone(laneFixture), { profiles: { "o-test": profile(() => action) } });
  assert.equal(calls.filter((c) => c.method === "PATCH").length, 0);
  assert.equal(r2.lanes.profiles.skippedSteps["o-test:b"], 1);
  assert.equal(r2.lanes.profiles.summary.endpoints["o-test:b"], undefined);
  // An undeclared operation is a failed sample and sends nothing.
  calls.length = 0;
  const r3 = await run({ ...optConfig }, structuredClone(laneFixture), {
    profiles: { "o-test": profile(() => ({ operation: "zz", path: "/rest/v1/rpc/x", body: {} })) },
  });
  assert.equal(calls.filter((c) => c.path.endsWith("/x")).length, 0);
  assert.ok(r3.lanes.profiles.samples.every((s) => !s.ok && s.error === "undeclared_operation"));
});
test("base lane is identical with a profile lane", async (t) => {
  t.mock.method(global, "fetch", async (url, init) => validAnswer(url, init));
  const A = await run(laneConfig, structuredClone(laneFixture), { profiles: {} });
  const B = await run(
    { ...laneConfig, trackerGaps: ["x-test"] },
    structuredClone(laneFixture),
    { profiles: { "x-test": xProfile() } },
  );
  assert.equal(A.droppedBusy, 0);
  assert.equal(B.droppedBusy, 0);
  const shape = (r) => r.samples.map((s) => [s.sequence, s.kind]).sort((a, b) => a[0] - b[0]);
  assert.deepEqual(shape(B), shape(A));
  assert.equal(B.summary.offered, A.summary.offered);
  assert.deepEqual(Object.keys(B.summary.endpoints), Object.keys(A.summary.endpoints));
  assert.ok(B.samples.every((s) => s.kind !== "x-test"));
  assert.equal(B.lanes.profiles.summary.endpoints["x-test"].requests, 5);
  assert.equal(B.schemaVersion, 2);
  assert.equal(A.schemaVersion, 2);
  assert.equal(A.lanes, undefined);
  assert.equal(B.summary.pass, A.summary.pass);
  assert.equal(W.exitCodeFor(B), 0);
  const C = await run(
    { ...laneConfig, trackerGaps: ["x-test"] },
    structuredClone(laneFixture),
    { profiles: { "x-test": xProfile(() => false) } },
  );
  assert.equal(C.summary.pass, A.summary.pass);
  assert.equal(W.exitCodeFor(C), 1);
});
