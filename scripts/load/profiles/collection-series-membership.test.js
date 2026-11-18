"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const W = require("../backend_workload");
const NAME = "collection-series-membership";
const P = require("./collection-series-membership");
const anime = Array.from({ length: 2000 }, (_, i) => 100 + i);
const fixture = (extra = {}) => ({ media: { anime, ...extra } });

test("collection-series-membership is a browse-class profile at 1 rps", () => {
  const before = JSON.stringify(W.WEIGHTS);
  const p = W.loadProfiles()[NAME];
  assert.ok(p, "profile registered");
  assert.equal(p.budgetClass, "browse");
  assert.equal(W.selectProfiles({ names: [NAME] }).limits[NAME], 750);
  assert.equal(p.ratePerSecond, 1);
  assert.ok(!("weight" in p));
  assert.equal(W.loadWorkload("tracker-gaps-combined").profiles[NAME], 1);
  assert.equal(JSON.stringify(W.WEIGHTS), before);
  assert.ok(!(NAME in W.WEIGHTS));
});

test("the request is a bounded GET with the three approval filters", () => {
  const r = P.request({}, fixture(), 3);
  assert.equal(r.method, "GET");
  assert.equal(r.body, undefined);
  assert.ok(r.path.startsWith("/rest/v1/series_entry_spans?"));
  const ids = r.path.match(/anime_id=in\.\(([^)]*)\)/)[1].split(",");
  assert.ok(ids.length <= 300);
  for (const f of ["series.continuity=eq.verified", "series.grouping_state=eq.approved", "series_sections.state=eq.approved"]) {
    assert.ok(r.path.includes(f), f);
  }
  const withMember = P.request({}, fixture({ seriesMemberIds: [77] }), 0);
  assert.ok(withMember.path.match(/anime_id=in\.\(([^)]*)\)/)[1].split(",").includes("77"));
});

test("requires refuses a run without published member ids", () => {
  assert.match(P.requires(fixture(), {}), /no published series member ids/);
  assert.equal(P.requires(fixture({ seriesMemberIds: [77] }), {}), null);
});

test("validate accepts an empty array only in wiring mode", () => {
  const r = P.request({}, fixture(), 0);
  assert.equal(P.validate([], {}, r, { mode: "wiring" }), true);
  assert.equal(P.validate({}, {}, r, { mode: "wiring" }), false);
  for (const e of P.emptyExamples) assert.equal(P.validate(e, {}, r, { mode: "qualify" }), false);
  assert.equal(
    P.validate([{ anime_id: 1, series: { id: "s" }, series_sections: { kind: "season" } }], {}, r, { mode: "qualify" }),
    true,
  );
});
