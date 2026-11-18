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
      { status: 200 },
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
