"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const W = require("../backend_workload");
const P = require("./status-with-date-fill");
const NAME = "status-with-date-fill";
const fixed = { now: () => new Date("2026-03-01T23:30:00Z") }; // 2026-03-02 in Europe/Berlin
const state = (over = {}) => ({
  rowId: 41, mediaId: 77, lifecycleId: "life-1", revision: 7, phase: "fill", ...over,
});
const actorWith = (s = state()) => ({
  id: "u1", librarySize: 25, token: "tok", profileState: { [NAME]: s },
});
const fixture = { media: { anime: [1, 2, 3, 4, 5], manga: [] } };
const plan = (actor) => P.request(actor, fixture, 0, Math.random, fixed);

test("fill and undo legs", () => {
  const fill = plan(actorWith());
  assert.deepEqual(fill.steps.map((s) => s.operation), ["mutation", "date-patch"]);
  const m = fill.steps[0];
  assert.equal(m.path, "/rest/v1/rpc/apply_progress_mutations_v1");
  const item = m.body.p_mutations[0];
  assert.equal(item.status, "WATCHING");
  assert.equal(item.lifecycle_id, "life-1");
  assert.equal(item.base_revision, 7);
  assert.equal(item.media_id, 77);
  assert.match(item.mutation_id, /^[0-9a-f-]{36}$/);
  const patch = fill.steps[1];
  assert.equal(patch.method, "PATCH");
  assert.equal(patch.path, "/rest/v1/anime_user_lists?id=eq.41&select=id,list_type,started_raw,server_revision");
  assert.deepEqual(patch.body, { started_raw: "2026-03-02" });
  const undo = plan(actorWith(state({ phase: "undo" })));
  assert.equal(undo.steps[0].body.p_mutations[0].status, "PLANNING");
  assert.deepEqual(undo.steps[1].body, { started_raw: null });
  assert.equal(P.todayIn("Europe/Berlin", new Date("2026-03-01T23:30:00Z")), "2026-03-02");
  assert.equal(P.todayIn("UTC", new Date("2026-03-01T23:30:00Z")), "2026-03-01");
});
test("revision threads through both legs", () => {
  const a = actorWith();
  const [m, patch] = plan(a).steps;
  const mutationId = m.body.p_mutations[0].mutation_id;
  assert.equal(P.validate({ items: [{ mutation_id: mutationId, outcome: "applied", server_revision: 8 }] }, a, m, { mode: "qualify" }), true);
  assert.equal(a.profileState[NAME].revision, 8);
  assert.equal(a.profileState[NAME].phase, "fill"); // not flipped yet
  const row = { id: 41, list_type: "WATCHING", started_raw: "2026-03-02", server_revision: 9 };
  assert.equal(P.validate([row], a, patch, { mode: "qualify" }), true);
  assert.equal(a.profileState[NAME].revision, 9);
  assert.equal(a.profileState[NAME].phase, "undo");
  const next = plan(a);
  assert.equal(next.steps[0].body.p_mutations[0].base_revision, 9);
  assert.equal(next.steps[0].body.p_mutations[0].status, "PLANNING");
});
test("qualify validation is strict", (t) => {
  for (const empty of P.emptyExamples) {
    assert.equal(P.validate(empty, actorWith(), { path: "/stub", body: {} }, { mode: "qualify" }), false);
    const a = actorWith();
    for (const step of plan(a).steps) assert.equal(P.validate(empty, a, step, { mode: "qualify" }), false);
  }
  const a = actorWith();
  const patch = plan(a).steps[1];
  const wrong = { id: 41, list_type: "WATCHING", started_raw: "2020-01-01", server_revision: 9 };
  assert.equal(P.validate([wrong], a, patch, { mode: "qualify" }), false);
  const good = { id: 41, list_type: "WATCHING", started_raw: "2026-03-02", server_revision: 9 };
  assert.equal(P.validate([good, good], a, patch, { mode: "qualify" }), false);
  assert.equal(P.validate([{ ...good, list_type: "PLANNING" }], a, patch, { mode: "qualify" }), false);
  assert.equal(P.validate([{ ...good, server_revision: "9" }], a, patch, { mode: "qualify" }), false);
  assert.equal(a.profileState[NAME].phase, "fill");
  // a conflict outcome is never success
  const m = plan(a).steps[0];
  assert.equal(P.validate({ items: [{ mutation_id: m.body.p_mutations[0].mutation_id, outcome: "conflict", server_revision: 8 }] }, a, m, { mode: "qualify" }), false);
  assert.equal(P.validate({ items: [{ mutation_id: "other", outcome: "applied", server_revision: 8 }] }, a, m, { mode: "qualify" }), false);
  // the registry accepts it, which runs the F3.1c qualify checks
  const loaded = W.loadProfiles(path.dirname(__filename));
  assert.ok(loaded[NAME]);
  assert.equal(loaded[NAME].ratePerSecond, 0.4);
});
test("seed uses a dedicated row and cleanup checks it", async () => {
  const calls = [];
  const call = async (p, body, opts = {}) => {
    calls.push({ p, body, opts });
    if (opts.method === "GET") {
      const offset = Number(new URL("https://x" + p).searchParams.get("offset") ?? 0);
      return offset === 0 ? [{ anime_id: 1 }, { anime_id: 2 }] : [];
    }
    return [{ id: 99, anime_id: body.anime_id, lifecycle_id: "life-x", server_revision: 1, list_type: "PLANNING" }];
  };
  const actor = { id: "u1", token: "tok", librarySize: 25, writeEntry: { mediaId: 1, revision: 1 } };
  assert.match(P.requires({}, actor), /no seeded date-fill entry/);
  const s = await P.seed({ actor, fixture, call });
  assert.deepEqual(s, { rowId: 99, mediaId: 3, lifecycleId: "life-x", revision: 1, phase: "fill" });
  const insert = calls.find((c) => c.opts.method !== "GET");
  assert.equal(insert.opts.token, "tok");
  assert.equal(insert.opts.prefer, "resolution=ignore-duplicates,return=representation");
  assert.match(insert.p, /^\/rest\/v1\/anime_user_lists\?on_conflict=user_id,anime_id&select=/);
  assert.deepEqual(insert.body, { user_id: "u1", anime_id: 3, list_type: "PLANNING", progress: 0 });
  assert.deepEqual(actor.writeEntry, { mediaId: 1, revision: 1 });
  assert.equal(P.requires({}, { ...actor, profileState: { [NAME]: s } }), null);
  // a duplicate-ignored insert is an error, never a silent pass
  await assert.rejects(() => P.seed({ actor, fixture, call: async (p, b, o = {}) => (o.method === "GET" ? [] : []) }), /not inserted/);
  const check = (rows) => P.cleanupCheck({ actor, state: s, call: async () => rows });
  assert.equal(await check([]), true);
  assert.equal(await check([{ id: 99 }]), false);
});
