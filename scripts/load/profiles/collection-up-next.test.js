"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const W = require("../backend_workload");
const P = require("./collection-up-next");
const NAME = "collection-up-next";
const core = { now: () => new Date("2026-03-01T12:00:00Z") };
const fixture = { media: { anime: [1, 2, 3], manga: [] } };
const seeded = (over = {}) => ({
  n: 0,
  owned: { anime: [10, 11, 12, 99], manga: [] },
  completed: { anime: [10, 11, 12], manga: [20] },
  seeded: { anime: Array.from({ length: 40 }, (_, i) => 1000 + i), manga: Array.from({ length: 12 }, (_, i) => 2000 + i) },
  reads: { anime: [], manga: [] },
  planned: null, planTarget: null, dismissed: null,
  ...over,
});
const actorWith = (s = seeded(), librarySize = 100) => ({ id: "u1", token: "tok", librarySize, profileState: { [NAME]: s } });
const rows = (ids, after = 10, medium = "anime") => ids.map((id) => ({
  media_type: medium, media_id: id, title: "T" + id, after_media_id: after, after_title: "P", link: "sequel",
}));
const qualify = { mode: "qualify" };

test("collection-up-next reads library_up_next_v1 (browse) and writes Plan/Dismiss with their Undos (progress) at 2 rps", () => {
  const before = JSON.stringify(W.WEIGHTS);
  const p = W.loadProfiles()[NAME];
  assert.equal(p.ratePerSecond, 2);
  assert.ok(!("weight" in p));
  const limits = W.selectProfiles({ names: [NAME] }).limits;
  for (const op of ["read", "plan", "plan-undo", "dismiss", "dismiss-undo"]) {
    assert.equal(limits[`${NAME}:${op}`], 750, op);
  }
  assert.equal(W.loadWorkload("tracker-gaps-combined").profiles[NAME], 2);
  assert.equal(JSON.stringify(W.WEIGHTS), before);
  assert.ok(!(NAME in W.WEIGHTS));
});

test("one actor cycle: six reads (manga at seq 3 of the cycle), a Plan and its Undo, a dismissal and its retract", () => {
  const a = actorWith();
  const cycle = [];
  for (let i = 0; i < 10; i++) {
    const r = P.request(a, fixture, i, Math.random, core);
    cycle.push(r);
    const s = a.profileState[NAME];
    // the answers a healthy server gives, so state advances like a real run
    if (r.operation === "read") {
      assert.equal(r.path, "/rest/v1/rpc/library_up_next_v1");
      assert.equal(r.body.p_limit, 30);
      assert.ok(["anime", "manga"].includes(r.body.p_medium));
      assert.equal(r.anonymous, undefined);
      if (r.body.p_medium === "anime") P.validate(rows([1000, 1001, 1002]), a, r, qualify);
    } else if (r.operation === "plan") {
      P.validate([{ id: 5, anime_id: r.body.anime_id, list_type: "PLANNING", lifecycle_id: "life-1", server_revision: 1 }], a, r, qualify);
    } else if (r.operation === "plan-undo") {
      P.validate({ items: [{ mutation_id: r.body.p_mutations[0].mutation_id, outcome: "applied" }] }, a, r, qualify);
    } else if (r.operation === "dismiss") {
      P.validate({ ok: true, action: "skip", media_id: r.body.p_media_id }, a, r, qualify);
    } else if (r.operation === "dismiss-undo") {
      P.validate({ ok: true, action: "retract", deleted: 1 }, a, r, qualify);
    }
    assert.equal(s.n, i + 1);
  }
  assert.deepEqual(cycle.map((c) => c.operation), [
    "read", "read", "read", "read", "read", "read", "plan", "plan-undo", "dismiss", "dismiss-undo",
  ]);
  const plan = cycle[6];
  assert.match(plan.path, /^\/rest\/v1\/anime_user_lists\?on_conflict=user_id,anime_id&select=/);
  assert.equal(plan.body.list_type, "PLANNING");
  assert.equal(plan.body.user_id, "u1");
  assert.equal(plan.prefer, "resolution=ignore-duplicates,return=representation");
  const undo = cycle[7];
  assert.equal(undo.path, "/rest/v1/rpc/apply_remove_mutations_v1");
  const m = undo.body.p_mutations[0];
  assert.equal(m.lifecycle_id, "life-1");
  assert.equal(m.base_revision, 1);
  assert.equal(m.media_id, plan.body.anime_id);
  assert.match(m.mutation_id, /^[0-9a-f-]{36}$/);
  assert.equal(cycle[8].path, "/rest/v1/rpc/record_taste_deck_signal");
  assert.equal(cycle[8].body.p_action, "skip");
  assert.equal(cycle[9].body.p_action, "retract");
  assert.equal(cycle[9].body.p_media_id, cycle[8].body.p_media_id);
  assert.notEqual(cycle[6].body.anime_id, cycle[8].body.p_media_id, "Plan and Dismiss take different titles");
  assert.equal(a.profileState[NAME].planned, null);
  assert.equal(a.profileState[NAME].dismissed, null);
});

test("a write slot without its precondition sends a read, so state never drifts", () => {
  const a = actorWith(seeded({ n: 6 }));
  assert.equal(P.request(a, fixture, 0, Math.random, core).operation, "read"); // plan with no read yet
  const b = actorWith(seeded({ n: 7 }));
  assert.equal(P.request(b, fixture, 0, Math.random, core).operation, "read"); // undo with nothing planned
  const c = actorWith(seeded({ n: 9 }));
  assert.equal(P.request(c, fixture, 0, Math.random, core).operation, "read"); // retract with nothing dismissed
});

test("wiring validation is shape only; qualify validation is semantic and rejects every empty answer", () => {
  const a = actorWith();
  const read = { operation: "read", body: { p_medium: "anime", p_limit: 30 } };
  assert.equal(P.validate({}, a, read, { mode: "wiring" }), false);
  assert.equal(P.validate([], a, read, { mode: "wiring" }), true);
  for (const empty of P.emptyExamples) {
    assert.equal(P.validate(empty, a, read, qualify), false);
    assert.equal(P.validate(empty, {}, { path: "/stub", body: {} }, qualify), false);
  }
  assert.equal(P.validate([], a, read, qualify), false, "an empty answer from a populated actor fails");
  assert.equal(P.validate(rows([1000]), a, read, qualify), true);
  assert.equal(P.validate(rows([1000], 555), a, read, qualify), false, "after must be one of the actor's COMPLETED ids");
  assert.equal(P.validate(rows([99]), a, read, qualify), false, "an owned title must never be listed");
  assert.equal(P.validate([{ ...rows([1000])[0], link: "other" }], a, read, qualify), false);
  const big = actorWith(seeded(), 2000);
  assert.equal(P.validate(rows([1000, 1001]), big, read, qualify), false, "a 2,000-title actor's anime answer must be at the cap");
  assert.equal(P.validate(rows(Array.from({ length: 30 }, (_, i) => 1000 + i)), big, read, qualify), true);
  const plan = { operation: "plan", body: { anime_id: 1000 } };
  a.profileState[NAME].planTarget = 1000;
  const good = { id: 5, anime_id: 1000, list_type: "PLANNING", lifecycle_id: "l", server_revision: 1 };
  assert.equal(P.validate([{ ...good, anime_id: 7 }], a, plan, qualify), false);
  assert.equal(P.validate([good, good], a, plan, qualify), false);
  assert.equal(P.validate([{ ...good, list_type: "WATCHING" }], a, plan, qualify), false);
  assert.equal(P.validate([good], a, plan, qualify), true);
  const undo = { operation: "plan-undo", body: { p_mutations: [{ mutation_id: "m1" }] } };
  assert.equal(P.validate({ items: [{ mutation_id: "m1", outcome: "conflict" }] }, a, undo, qualify), false);
  assert.equal(P.validate({ items: [{ mutation_id: "other", outcome: "applied" }] }, a, undo, qualify), false);
  assert.equal(P.validate({ items: [{ mutation_id: "m1", outcome: "applied" }] }, a, undo, qualify), true);
  const retract = { operation: "dismiss-undo", body: {} };
  assert.equal(P.validate({ ok: true, action: "retract", deleted: 0 }, a, retract, qualify), false);
  assert.equal(P.validate({ ok: true, action: "retract", deleted: 1 }, a, retract, qualify), true);
  // the registry accepts it (this runs the F3.1c qualify checks)
  assert.ok(W.loadProfiles(path.dirname(__filename))[NAME]);
});

test("requires names its reason before seed and is null after", () => {
  assert.match(P.requires(fixture, { id: "u", librarySize: 100, profileState: {} }), /no seeded up-next fixture/);
  assert.equal(P.requires(fixture, actorWith()), null);
  const thin = actorWith(seeded({ seeded: { anime: [1], manga: [] } }));
  assert.match(P.requires(fixture, thin), /fewer than/);
});

test("seed uses only the actor token, inserts COMPLETED rows exactly as insertIfMissing, and returns the state", async () => {
  const calls = [];
  const call = async (p, body, opts = {}) => {
    calls.push({ p, body, opts });
    const url = new URL("https://x" + p);
    if (url.pathname === "/rest/v1/anime_user_lists" && opts.method === "GET") {
      return url.searchParams.get("offset") === "0" ? [{ anime_id: 10, list_type: "COMPLETED" }, { anime_id: 99, list_type: "PLANNING" }] : [];
    }
    if (url.pathname === "/rest/v1/manga_user_lists" && opts.method === "GET") return [];
    if (url.pathname === "/rest/v1/media_relations") {
      const t = url.searchParams.get("from_media_type");
      if (url.searchParams.get("offset") !== "0") return [];
      return t === "eq.ANIME"
        ? [{ from_media_id: 10, to_media_id: 11 }, { from_media_id: 500, to_media_id: 501 }, { from_media_id: 502, to_media_id: 503 }, { from_media_id: 504, to_media_id: 99 }]
        : [{ from_media_id: 800, to_media_id: 801 }];
    }
    if (url.pathname === "/rest/v1/anime") return [{ id: 501, format: "TV", status: "FINISHED", genres: ["Drama"], is_adult: false }, { id: 503, format: "MUSIC", status: "FINISHED", genres: [] }];
    if (url.pathname === "/rest/v1/manga") return [{ id: 801, format: "MANGA", status: "FINISHED", genres: [], is_adult: false }];
    if (url.pathname === "/rest/v1/taste_signal_events") return [];
    return body.map((r) => ({ anime_id: r.anime_id, manga_id: r.manga_id }));
  };
  const actor = { id: "u1", token: "tok", librarySize: 100, profileState: {} };
  const s = await P.seed({ actor, fixture, call });
  assert.ok(calls.every((c) => c.opts.token === "tok"), "every call carries the actor token only");
  const inserts = calls.filter((c) => c.opts.prefer);
  assert.equal(inserts.length, 2);
  for (const i of inserts) {
    assert.match(i.p, /_user_lists\?on_conflict=user_id,(anime|manga)_id&select=/);
    assert.equal(i.opts.prefer, "resolution=ignore-duplicates,return=representation");
    assert.ok(i.body.every((r) => r.list_type === "COMPLETED" && r.user_id === "u1"));
  }
  assert.deepEqual(s.seeded.anime, [500], "owned titles, the MUSIC target and an owned target are skipped");
  assert.deepEqual(s.seeded.manga, [800]);
  assert.ok(s.completed.anime.includes(10) && s.completed.anime.includes(500), "existing and seeded completed ids");
  assert.ok(s.owned.anime.includes(99) && s.owned.anime.includes(500));
  assert.deepEqual(s.targetCount, { anime: 1, manga: 1 });
});

test("cleanupCheck is true when the service-role reads return [] and false when any returns a row", async () => {
  const none = async () => [];
  assert.equal(await P.cleanupCheck({ actor: { id: "u1" }, state: {}, call: none }), true);
  const seen = [];
  const leaky = async (p) => { seen.push(p); return p.includes("taste_signal_events") ? [{ id: 1 }] : []; };
  assert.equal(await P.cleanupCheck({ actor: { id: "u1" }, state: {}, call: leaky }), false);
  assert.ok(seen.some((p) => p.includes("anime_user_lists?user_id=eq.u1")));
  assert.equal(await P.cleanupCheck({ actor: {}, state: {}, call: none }), false);
});

test("qualify verdicts: 99 plan completions (or 29 in one subgroup) are insufficient, never pass", () => {
  const selection = W.selectProfiles({ names: [NAME] });
  const mk = (kind, n, size, ms = 100) => Array.from({ length: n }, () => ({ kind, ms, ok: true, librarySize: size }));
  const full = (plan100, plan2000) => [
    ...mk(`${NAME}:read`, 400, 100), ...mk(`${NAME}:read`, 400, 2000),
    ...mk(`${NAME}:plan`, plan100, 100), ...mk(`${NAME}:plan`, plan2000, 2000),
    ...["plan-undo", "dismiss", "dismiss-undo"].flatMap((op) => [...mk(`${NAME}:${op}`, 60, 100), ...mk(`${NAME}:${op}`, 60, 2000)]),
  ];
  assert.equal(W.qualifyVerdicts(full(60, 60), selection).verdict, "pass");
  assert.equal(W.qualifyVerdicts(full(49, 50), selection).verdict, "insufficient", "99 plan completions");
  assert.equal(W.qualifyVerdicts(full(29, 70), selection).verdict, "insufficient", "29 in one subgroup");
});
