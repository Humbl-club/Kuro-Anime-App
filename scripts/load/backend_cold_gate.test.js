"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const W = require("./backend_workload");
const C = require("./backend_cold_gate");
function healthy() {
  const actors = Array.from({ length: 100 }, (_, i) => ({
    librarySize: i < 20 ? 0 : i < 70 ? 25 : i < 95 ? 100 : 2000,
    clubId: i < 50 ? "fixture" : null,
  }));
  let seed = 20261109;
  const random = () => ((seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0) / 4294967296);
  const samples = Array.from({ length: 12000 }, (_, sequence) => {
    let kind = W.chooseKind(random);
    random(); // The frozen request builder consumes its catalogue-selection random value.
    const actor = actors[sequence % 100];
    if (kind === "progress" && !actor.librarySize) kind = "home";
    return { kind, sequence, librarySize: actor.librarySize, medium: null, ms: 40, ok: true };
  });
  return { actors, report: { config: { rps: 20, duration: 600, vus: 100 }, samples,
    summary: W.summarize(samples, 12000, 600) } };
}
test("complete onset, routes and library coverage pass without changing the limits", () => {
  const { actors, report } = healthy();
  const r = C.evaluateColdStage(report, actors);
  assert.equal(r.pass, true);
  assert.equal(r.missing.length, 0);
  assert.equal(r.fullLibrary.length, 39);
  assert.equal(r.first60Seconds.routes.length, 16);
  assert.equal(r.firstRouteCalls.find((x) => x.key === "search:manga").limit, 750);
});
test("one slow first call fails even when warm requests make overall p95 pass", () => {
  const { actors, report } = healthy();
  report.samples.find((s) => s.kind === "search").ms = 751;
  report.summary = W.summarize(report.samples, 12000, 600);
  assert.equal(report.summary.pass, true);
  assert.equal(C.evaluateColdStage(report, actors).pass, false);
});
test("missing rare large-library coverage fails instead of disappearing from percentiles", () => {
  const { actors, report } = healthy();
  report.samples = report.samples.map((s) => s.kind === "recommend" && s.librarySize === 2000
    ? { ...s, kind: "home" } : s);
  const r = C.evaluateColdStage(report, actors);
  assert.equal(r.pass, false);
  assert.ok(r.missing.includes("recommend/2000"));
});
test("a missing first-minute route fails even when it occurs in the later warm period", () => {
  const { actors, report } = healthy();
  report.samples = report.samples.map((s) => s.sequence < 1200 && s.kind === "parse"
    ? { ...s, kind: "home" } : s);
  const r = C.evaluateColdStage(report, actors);
  assert.ok(r.fullRoutes.find((x) => x.key === "parse").pass);
  assert.equal(r.first60Seconds.routes.find((x) => x.key === "parse").pass, false);
  assert.equal(r.pass, false);
});
test("conflicting media and missing user starts cannot qualify", () => {
  const { actors, report } = healthy();
  const s = report.samples.find((x) => x.kind === "search");
  s.medium = s.sequence % 3 === 0 ? "ANIME" : "MANGA";
  assert.throws(() => C.evaluateColdStage(report, actors), /medium/);
  s.medium = null;
  report.samples = report.samples.filter((x) => x.sequence !== 0);
  assert.equal(C.evaluateColdStage(report, actors).pass, false);
});
