"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const W = require("../backend_workload");

test("export-mal-id-lookup is a Browse-class GET of at most 500 ids at 0.2 rps", () => {
  const before = JSON.stringify(W.WEIGHTS);
  const p = W.loadProfiles()["export-mal-id-lookup"];
  assert.equal(p.budgetClass, "browse"); assert.equal(p.ratePerSecond, 0.2); assert.ok(!("weight" in p));
  assert.equal(W.selectProfiles({ names: ["export-mal-id-lookup"] }).limits["export-mal-id-lookup"], 750);
  assert.equal(W.loadWorkload("tracker-gaps-combined").profiles["export-mal-id-lookup"], 0.2);
  const fixture = { media: { anime: Array.from({ length: 2000 }, (_, i) => i + 1), manga: [1, 2] } };
  const core = { requestFor: W.requestFor, validateResponse: W.validateResponse, ORIGIN: W.ORIGIN, now: () => new Date(0) };
  for (let seq = 0; seq < 8; seq++) {
    const r = p.request({ librarySize: 2000 }, fixture, seq, Math.random, core);
    assert.equal(r.method, "GET"); assert.equal(r.body, undefined); assert.notEqual(r.anonymous, true);
    const ids = decodeURIComponent(r.path).match(/id=in\.\(([^)]*)\)/)[1].split(",");
    assert.ok(ids.length >= 1 && ids.length <= 500);
  }
  const req = p.request({ librarySize: 2000 }, fixture, 0, Math.random, core);
  const firstId = Number(decodeURIComponent(req.path).match(/id=in\.\(([^)]*)\)/)[1].split(",")[0]);
  const wiring = { mode: "wiring" }, qualify = { mode: "qualify" };
  assert.ok(p.validate([{ id: firstId }], {}, req, qualify));
  assert.ok(!p.validate({}, {}, req, wiring)); assert.ok(p.validate([], {}, req, wiring)); // wiring mode: empty is accepted
  for (const e of p.emptyExamples) assert.ok(!p.validate(e, {}, req, qualify));
  assert.ok(!p.validate([{ id: -1 }], {}, req, qualify));
  assert.equal(JSON.stringify(W.WEIGHTS), before); assert.ok(!("export-mal-id-lookup" in W.WEIGHTS)); // base mix untouched
});
