"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const W = require("../backend_workload");

// A seeded LCG so the draw is reproducible.
function lcg(seed) {
  let s = seed >>> 0;
  return () => {
    s = (Math.imul(1664525, s) + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

const ALLOWED_PATHS = new Set([
  "/rest/v1/rpc/discover_bundle",
  "/rest/v1/rpc/search_anime_page",
  "/rest/v1/rpc/search_manga_page",
  "/rest/v1/rpc/browse_anime_page",
  "/rest/v1/rpc/browse_manga_page",
  "/rest/v1/rpc/get_media_ladder",
]);

function draw(p, n) {
  const random = lcg(20261118);
  const core = { requestFor: W.requestFor, validateResponse: W.validateResponse, ORIGIN: W.ORIGIN, now: () => new Date(0) };
  const fixture = { media: { anime: [101, 102, 103, 104], manga: [201, 202, 203] }, accounts: [{ id: "a", librarySize: 0 }] };
  const out = [];
  for (let seq = 0; seq < n; seq++) out.push(p.request({ id: "a" }, fixture, seq, random, core));
  return out;
}

test("guest-browse: 5 rps anonymous in its own lane, allowlisted paths only, no user token", () => {
  const before = JSON.stringify(W.WEIGHTS);
  const p = W.loadProfiles()["guest-browse"];
  assert.equal(p.ratePerSecond, 5);
  assert.ok(!("weight" in p));
  assert.equal(W.loadWorkload("tracker-gaps-combined").profiles["guest-browse"], 5);
  assert.ok(!("guest-browse" in W.WEIGHTS), "the profile runs in its own lane");
  assert.equal(JSON.stringify(W.WEIGHTS), before);

  const requests = draw(p, 1000);
  for (const r of requests) {
    assert.equal(r.anonymous, true);
    assert.ok(["discover", "search", "browse", "detail"].includes(r.budgetClass));
    const table = /^\/rest\/v1\/(anime|manga)\?/.test(r.path);
    assert.ok(ALLOWED_PATHS.has(r.path) || table, "path off the allowlist: " + r.path);
    if (table) {
      assert.equal(r.method, "GET");
      assert.equal(r.body, undefined);
    }
  }
  assert.ok(!JSON.stringify(requests).includes("series_detail_bundle_v1"));
  assert.ok(!JSON.stringify(requests).includes("Authorization"));

  const L = W.selectProfiles({ names: ["guest-browse"] }).limits;
  assert.equal(L["guest-browse:detail"], 1200);
  assert.equal(L["guest-browse:discover"], 1500);
  assert.equal(L["guest-browse:search"], 750);
  assert.equal(L["guest-browse:browse"], 750);
  assert.ok(!("guest-browse" in L));

  const share = (cls) => requests.filter((r) => r.budgetClass === cls).length / requests.length;
  assert.ok(Math.abs(share("detail") - 20 / 60) <= 0.05, "detail share " + share("detail"));
  assert.ok(Math.abs(share("discover") - 5 / 60) <= 0.03, "discover share " + share("discover"));
});

test("guest-browse: an empty answer never validates in qualify mode, wiring accepts an empty search", () => {
  const p = W.loadProfiles()["guest-browse"];
  const requestOf = (cls, extra = {}) => ({ path: "/stub", body: {}, budgetClass: cls, ...extra });
  const searchRequest = requestOf("search");
  assert.equal(p.validate([], {}, searchRequest, { mode: "qualify" }), false);
  assert.equal(p.validate([], {}, searchRequest, { mode: "wiring" }), true);
  for (const cls of ["discover", "search", "browse", "detail"]) {
    for (const empty of p.emptyExamples) {
      assert.equal(p.validate(empty, {}, requestOf(cls), { mode: "qualify" }), false, cls + " accepted an empty answer");
      assert.equal(p.validate(empty, {}, requestOf(cls, { method: "GET" }), { mode: "qualify" }), false, cls + " GET accepted an empty answer");
    }
  }
  // a missing or unknown class never validates (the harness's stub request rejects every empty example)
  assert.equal(p.validate([{ id: 1 }], {}, { path: "/stub", body: {} }, { mode: "wiring" }), false);
  assert.equal(p.validate([{ id: 1 }], {}, requestOf("other"), { mode: "wiring" }), false);
  // real shapes pass in qualify mode
  assert.equal(p.validate([{ id: 1 }], {}, requestOf("search"), { mode: "qualify" }), true);
  assert.equal(p.validate([{ id: 1 }], {}, requestOf("browse"), { mode: "qualify" }), true);
  assert.equal(p.validate({ anime: { trending: [] }, manga: { trending: [] } }, {}, requestOf("discover"), { mode: "qualify" }), true);
  assert.equal(p.validate([{ id: 1 }], {}, requestOf("detail", { method: "GET" }), { mode: "qualify" }), true);
  assert.equal(p.validate({ coverageStatus: "strong" }, {}, requestOf("detail"), { mode: "qualify" }), true);
});
