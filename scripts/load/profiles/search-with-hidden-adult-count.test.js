"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const W = require("../backend_workload");

test("search-with-hidden-adult-count is a Search-class first page on v2 at 1 rps", () => {
  const before = JSON.stringify(W.WEIGHTS);
  const p = W.loadProfiles()["search-with-hidden-adult-count"];
  assert.equal(p.budgetClass, "search");
  assert.equal(p.ratePerSecond, 1);
  assert.ok(!("weight" in p));
  assert.equal(W.selectProfiles({ names: ["search-with-hidden-adult-count"] }).limits["search-with-hidden-adult-count"], 750);
  assert.equal(W.loadWorkload("tracker-gaps-combined").profiles["search-with-hidden-adult-count"], 1);
  const core = { requestFor: W.requestFor, validateResponse: W.validateResponse, ORIGIN: W.ORIGIN, now: () => new Date(0) };
  const r = p.request({}, { media: { anime: [1], manga: [1] } }, 1, Math.random, core);
  assert.match(r.path, /\/rest\/v1\/rpc\/search_(anime|manga)_page_v2$/);
  assert.equal(r.body.p_cursor_id, undefined);
  assert.ok(p.validate({ items: [{ id: 1 }], hidden_adult: 0 }, {}, r, { mode: "qualify" }));
  assert.ok(p.validate({ items: [], hidden_adult: null }, {}, r, { mode: "wiring" }));
  assert.ok(!p.validate([{ id: 1 }], {}, r, { mode: "wiring" }));
  for (const e of p.emptyExamples) assert.ok(!p.validate(e, {}, r, { mode: "qualify" }));
  assert.equal(JSON.stringify(W.WEIGHTS), before);
  assert.ok(!("search-with-hidden-adult-count" in W.WEIGHTS));
});

test("the profile alternates media like the predeclared search and never sends a cursor", () => {
  const p = W.loadProfiles()["search-with-hidden-adult-count"];
  const paths = [0, 1, 2, 3].map((seq) => p.request({}, {}, seq, Math.random, {}).path);
  assert.match(paths[0], /search_manga_page_v2$/); // seq % 3 === 0
  assert.match(paths[1], /search_anime_page_v2$/);
  const body = p.request({}, {}, 4, Math.random, {}).body;
  assert.equal(body.p_limit, 30);
  assert.ok(typeof body.p_query === "string" && body.p_query.length >= 2);
});
