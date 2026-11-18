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
