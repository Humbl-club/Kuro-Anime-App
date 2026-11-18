"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const W = require("../backend_workload");
const P = require("./collection-with-tags-and-lists");
const NAME = "collection-with-tags-and-lists";
const OPS = ["tag-index", "lists", "delta", "move", "rebalance", "create", "seed", "delete"];
const core = { now: () => new Date("2026-03-01T12:00:00Z") };
const fixture = { media: { anime: [1, 2, 3], manga: [] } };
const qualify = { mode: "qualify" };
const wiring = { mode: "wiring" };

const ids = (prefix, n) => Array.from({ length: n }, (_, i) => `${prefix}${i}`);
const itemsOf = (listId, n) => Array.from({ length: n }, (_, i) => ({ id: `${listId}-i${i}`, position: 1024 * (i + 1) }));
const seeded = (size = 2000, over = {}) => {
  const listIds = ids("L", 20);
  const maxListId = size >= 2000 ? "L19" : null;
  const items = {};
  listIds.forEach((id, i) => { items[id] = itemsOf(id, id === maxListId ? 2000 : size >= 2000 ? 100 : 10); });
  return {
    n: 0, run: "r1", cycle: 0, listIds, maxListId, items,
    revisions: Object.fromEntries(listIds.map((id) => [id, 3])),
    nineTagKeys: Array.from({ length: 10 }, (_, i) => ({ medium: "anime", id: 100 + i })),
    tracked: Array.from({ length: size >= 2000 ? 2000 : 100 }, (_, i) => ({ medium: "anime", id: i + 1 })),
    tagOn: false, deltaN: 0, moveN: 0, rebN: 0, member: { in: false }, busy: {},
    created: null, sLists: [], tagRows: size >= 2000 ? 1000 : 50,
    ...over,
  };
};
const actorWith = (s = seeded(), librarySize = 2000) => ({ id: "u1", token: "tok", librarySize, profileState: { [NAME]: s } });

test("registry: 5 rps in its own lane, eight operations with Browse reads and Progress writes, one combined line", () => {
  const before = JSON.stringify(W.WEIGHTS);
  const p = W.loadProfiles()[NAME];
  assert.equal(p.ratePerSecond, 5);
  assert.ok(!("weight" in p));
  const limits = W.selectProfiles({ names: [NAME] }).limits;
  assert.deepEqual(Object.keys(limits).filter((k) => k.startsWith(NAME + ":")).sort(), OPS.map((o) => `${NAME}:${o}`).sort());
  for (const op of OPS) assert.equal(limits[`${NAME}:${op}`], 750, op);
  assert.equal(W.loadWorkload("tracker-gaps-combined").profiles[NAME], 5);
  assert.equal(JSON.stringify(W.WEIGHTS), before);
  assert.ok(!(NAME in W.WEIGHTS));
});

test("one 25-slot cycle yields every operation in its declared share, never a forbidden path, every write complete", () => {
  const a = actorWith(seeded(2000, { sLists: ["Lold"] }));
  const counts = {};
  const sent = [];
  for (let i = 0; i < 25; i++) {
    const r = P.request(a, fixture, i, Math.random, core);
    sent.push(r);
    counts[r.operation] = (counts[r.operation] ?? 0) + 1;
    assert.ok(["typical", "maximum"].includes(r.payload), r.operation);
    assert.doesNotMatch(r.path, /bulk-import|release-intake|apply_remove/);
    assert.match(r.path, /^\/rest\/v1\/rpc\/(library_tag_index_v1|custom_lists_v1|apply_title_organisation_delta_v1|move_custom_list_item_v1|rebalance_custom_list_v1|create_custom_list_v1|seed_custom_lists_v1|delete_custom_list_v1)$/);
    // answer like a healthy server so the cycle keeps its preconditions
    healthy(a, r);
  }
  assert.deepEqual(counts, { "tag-index": 7, lists: 6, delta: 4, move: 3, rebalance: 1, create: 1, seed: 1, delete: 2 });
  const move = sent.find((r) => r.operation === "move");
  assert.ok("p_expected_list_revision" in move.body && "p_after_position" in move.body && "p_before_position" in move.body);
  const seed = sent.find((r) => r.operation === "seed");
  assert.equal(seed.body.p_lists[0].items.length, 50);
  assert.match(seed.body.p_lists[0].name, /^load-r1-1-s$/);
});

// Healthy answers per operation (the shapes the migration documents).
function healthy(a, r) {
  const s = a.profileState[NAME];
  const b = r.body;
  switch (r.operation) {
    case "tag-index": return P.validate([{ medium: "anime", media_id: 1, tags: ["a", "b", "c", "d", "e", "f", "g", "h", "i"] }, ...Array.from({ length: s.tagRows }, (_, i) => ({ medium: "anime", media_id: 5000 + i, tags: ["x"] }))], a, r, qualify);
    case "lists": return P.validate(listsAnswer(s, a.librarySize), a, r, qualify);
    case "delta": {
      if (r.meta.kind === "tag") {
        const tags = r.meta.add ? ["a", "load-t"] : ["a"];
        return P.validate({ tags, items: [], lists: [] }, a, r, qualify);
      }
      const rev = s.revisions[r.meta.listId];
      const items = r.meta.add ? [{ list_id: r.meta.listId, item_id: "new-item", position: 999999 }] : [];
      return P.validate({ tags: [], items, lists: [{ list_id: r.meta.listId, revision_before: rev, revision: rev + 1 }] }, a, r, qualify);
    }
    case "move": {
      const m = r.meta;
      const position = m.after === null ? m.before - 1024 : m.before === null ? m.after + 1024 : (m.after + m.before) / 2;
      return P.validate({ item_id: m.itemId, position, revision: m.expected + 1 }, a, r, qualify);
    }
    case "rebalance":
      return P.validate({ revision: r.meta.expected + 1, items: b.p_item_ids.map((id, i) => ({ item_id: id, position: 1024 * (i + 1) })) }, a, r, qualify);
    case "create": return P.validate({ id: "new-" + b.p_name, name: b.p_name, created_at: "2026-03-01T12:00:00+00:00", revision: 0 }, a, r, qualify);
    case "seed": return P.validate({ created: [b.p_lists[0].name], reused: [], skipped: [], added: 50 }, a, r, qualify);
    case "delete": return P.validate(null, a, r, qualify);
    default: throw new Error(r.operation);
  }
}

function listsAnswer(s, size, extra = []) {
  return [
    ...s.listIds.map((id, i) => ({ id, name: `load-fx-${i}`, created_at: "2026-03-01T12:00:00+00:00", revision: s.revisions[id],
      items: s.items[id].map((it) => ({ item_id: it.id, medium: "anime", media_id: 1, position: it.position })) })),
    ...s.sLists.map((id) => ({ id, name: "load-r1-0-s", created_at: "2026-03-01T12:00:00+00:00", revision: 0, items: [] })),
    ...extra,
  ];
}

test("a write slot without its precondition sends a read; per-list writes never overlap", () => {
  const a = actorWith(seeded(2000, { n: 23, created: null }));
  assert.equal(P.request(a, fixture, 0, Math.random, core).operation, "lists", "delete of the -c list with none created reads instead");
  const b = actorWith(seeded(2000, { n: 24, sLists: [] }));
  assert.equal(P.request(b, fixture, 0, Math.random, core).operation, "lists", "delete of the -s list before any read learned its id");

  // the move slot: its first list has a write in flight, so the other one is used; with both busy it reads
  const c = actorWith(seeded(2000, { n: 17 }));
  const s = c.profileState[NAME];
  s.busy[s.listIds[1]] = core.now().getTime();
  const first = P.request(c, fixture, 0, Math.random, core);
  assert.equal(first.operation, "move");
  assert.equal(first.body.p_list_id, s.maxListId, "the typical list is busy: the max list takes the move");
  const second = P.request(c, fixture, 1, Math.random, core);
  assert.equal(second.operation, "lists", "both candidates are now busy: the slot reads");
  // with every candidate busy the slot reads
  const d = actorWith(seeded(2000, { n: 17 }));
  const t = d.profileState[NAME];
  t.busy[t.listIds[1]] = core.now().getTime();
  t.busy[t.maxListId] = core.now().getTime();
  assert.equal(P.request(d, fixture, 0, Math.random, core).operation, "lists");
});

test("the delta reaches the supported maximum of 10 tags and toggles a list membership", () => {
  const a = actorWith(seeded(2000, { n: 13 }));
  const tag = P.request(a, fixture, 0, Math.random, core);
  assert.equal(tag.operation, "delta");
  assert.deepEqual(tag.body.p_add_tags, ["load-t"]);
  assert.equal(tag.payload, "maximum");
  assert.equal(tag.body.p_medium, "anime");
  const s = a.profileState[NAME];
  assert.equal(tag.body.p_media_id, s.nineTagKeys[0].id, "a 9-tag title: adding the tenth reaches 10");
  assert.equal(P.validate({ tags: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "load-t"], items: [], lists: [] }, a, tag, qualify), true);
  assert.equal(P.validate({ tags: ["1"], items: [], lists: [] }, a, tag, qualify), false, "the added tag must be present");
  assert.equal(P.validate({ tags: Array.from({ length: 11 }, (_, i) => "t" + i).concat("load-t"), items: [], lists: [] }, a, tag, qualify), false, "more than 10 tags is a failure");
  const member = P.request(a, fixture, 1, Math.random, core);
  assert.equal(member.operation, "delta");
  assert.ok(member.body.p_add_list_ids.length === 1 || member.body.p_remove_list_ids.length === 1);
  const remove = P.request(a, fixture, 2, Math.random, core);
  assert.deepEqual(remove.body.p_remove_tags, ["load-t"]);
});

test("moves compute positions from the actor's state; a STALE_LIST-style revision mismatch fails", () => {
  const a = actorWith(seeded(2000, { n: 17 }));
  const m = P.request(a, fixture, 0, () => 0.5, core);
  assert.equal(m.operation, "move");
  assert.equal(typeof m.body.p_expected_list_revision, "number");
  assert.equal(m.body.p_expected_list_revision, 3);
  const mid = (m.meta.after + m.meta.before) / 2;
  assert.equal(P.validate({ item_id: m.meta.itemId, position: mid, revision: 4 }, a, m, qualify), true);
  const b = actorWith(seeded(2000, { n: 17 }));
  const m2 = P.request(b, fixture, 0, () => 0.5, core);
  assert.equal(P.validate({ item_id: m2.meta.itemId, position: mid, revision: 9 }, b, m2, qualify), false, "revision must be expected + 1");
  assert.equal(P.validate({ item_id: m2.meta.itemId, position: m2.meta.before + 5, revision: 4 }, b, m2, qualify), false, "position must lie between its neighbours");
});

test("a rebalance of the max list sends all 2,000 ids; its answer must be 1024 * i", () => {
  const a = actorWith(seeded(2000, { n: 20, rebN: 1 }));
  const r = P.request(a, fixture, 0, Math.random, core);
  assert.equal(r.operation, "rebalance");
  assert.equal(r.body.p_list_id, "L19");
  assert.equal(r.body.p_item_ids.length, 2000);
  assert.equal(r.payload, "maximum");
  const wrong = { revision: 4, items: r.body.p_item_ids.map((id, i) => ({ item_id: id, position: 2048 * (i + 1) })) };
  assert.equal(P.validate(wrong, a, r, qualify), false);
  assert.equal(healthy(a, r), true);
});

test("wiring validation is shape only; qualify validation is semantic and rejects every empty answer", () => {
  const a = actorWith();
  const index = { operation: "tag-index", body: {} };
  const lists = { operation: "lists", body: {} };
  assert.equal(P.validate({}, a, index, wiring), false);
  assert.equal(P.validate([], a, index, wiring), true);
  assert.equal(P.validate([{ medium: "film", media_id: 1, tags: [] }], a, index, wiring), false);
  assert.equal(P.validate([{ medium: "anime", media_id: 1, tags: ["a"] }], a, index, wiring), true);
  assert.equal(P.validate([{ id: "x", name: "n", items: [{ media_id: "1" }] }], a, lists, wiring), false);
  assert.equal(P.validate([], a, lists, wiring), true);
  assert.equal(P.validate(listsAnswer(a.profileState[NAME], 2000), a, lists, wiring), true);
  for (const empty of P.emptyExamples) {
    assert.equal(P.validate(empty, a, index, qualify), false);
    assert.equal(P.validate(empty, a, lists, qualify), false);
    assert.equal(P.validate(empty, { id: "stub", librarySize: 0, profileState: {} }, { path: "/stub", body: {} }, qualify), false);
  }
  assert.equal(P.validate([], a, index, qualify), false, "an empty tag index from a seeded actor fails");
  assert.equal(P.validate([], a, lists, qualify), false, "an empty list read from a seeded actor fails");
  assert.equal(P.validate([{ medium: "anime", media_id: 1, tags: ["a"] }], a, index, qualify), false, "too few rows");
  const s = a.profileState[NAME];
  assert.equal(P.validate(listsAnswer(s, 2000), a, lists, qualify), true);
  const broken = listsAnswer(s, 2000);
  broken[19].items.reverse();
  assert.equal(P.validate(broken, a, lists, qualify), false, "the 2,000-item list must ascend");
  assert.equal(P.validate(listsAnswer(s, 2000).slice(1), a, lists, qualify), false, "a fixture list is missing");
  const create = { operation: "create", body: { p_name: "n" } };
  assert.equal(P.validate({ id: "i", name: "other", created_at: "x", revision: 0 }, a, create, qualify), false);
  const seed = { operation: "seed", body: { p_lists: [{ name: "n" }] } };
  assert.equal(P.validate({ created: ["n"], reused: [], skipped: [], added: 49 }, a, seed, qualify), false);
  assert.ok(W.loadProfiles(path.dirname(__filename))[NAME]);
});

test("requires names its reason before seed and is null after", () => {
  assert.match(P.requires(fixture, { id: "u", librarySize: 2000, profileState: {} }), /no seeded organisation fixture/);
  assert.equal(P.requires(fixture, actorWith()), null);
  assert.equal(P.requires(fixture, actorWith(seeded(100), 100)), null);
  assert.match(P.requires(fixture, actorWith(seeded(2000, { maxListId: null }))), /2,000-item list/);
  assert.match(P.requires(fixture, actorWith(seeded(2000, { nineTagKeys: [] }))), /9 tags/);
});

test("seed uses only the actor's token; lists come from one seed call, tags from deltas", async () => {
  const calls = [];
  const tracked = Array.from({ length: 150 }, (_, i) => ({ anime_id: i + 1 }));
  const call = async (p, body, opts = {}) => {
    calls.push({ p, body, opts });
    const url = new URL("https://x" + p);
    if (url.pathname === "/rest/v1/anime_user_lists") return url.searchParams.get("offset") === "0" ? tracked : [];
    if (url.pathname === "/rest/v1/manga_user_lists") return [];
    if (url.pathname === "/rest/v1/rpc/seed_custom_lists_v1") {
      return { created: body.p_lists.map((l) => l.name), reused: [], skipped: [], added: body.p_lists.reduce((n, l) => n + l.items.length, 0) };
    }
    if (url.pathname === "/rest/v1/rpc/apply_title_organisation_delta_v1") return { tags: body.p_add_tags, items: [], lists: [] };
    if (url.pathname === "/rest/v1/rpc/custom_lists_v1") {
      return Array.from({ length: 20 }, (_, i) => ({ id: "L" + i, name: `load-fx-${String(i + 1).padStart(2, "0")}`, created_at: "x", revision: 1,
        items: Array.from({ length: 10 }, (_, j) => ({ item_id: `L${i}-${j}`, medium: "anime", media_id: j + 1, position: 1024 * (j + 1) })) }));
    }
    throw new Error("unexpected " + p);
  };
  const actor = { id: "u1", token: "tok", librarySize: 100, profileState: {} };
  const s = await P.seed({ actor, fixture, call });
  assert.ok(calls.every((c) => c.opts.token === "tok"), "every call carries the actor token only");
  const seedCalls = calls.filter((c) => c.p.endsWith("/seed_custom_lists_v1"));
  assert.equal(seedCalls.length, 1);
  assert.equal(seedCalls[0].body.p_lists.length, 20);
  assert.ok(calls.filter((c) => c.p.endsWith("/apply_title_organisation_delta_v1")).length >= 50, "tags on every 2nd of 100 titles");
  assert.equal(s.listIds.length, 20);
  assert.equal(s.maxListId, null, "a 100-title actor has no 2,000-item list");
  assert.equal(s.nineTagKeys.length, 10);
  assert.ok(s.revisions.L0 >= 1);
  assert.equal(P.requires(fixture, { id: "u1", librarySize: 100, profileState: { [NAME]: s } }), null);
});

test("cleanupCheck is true when the three service-role reads return [] and false when any returns a row", async () => {
  const none = async () => [];
  assert.equal(await P.cleanupCheck({ actor: { id: "u1" }, state: {}, call: none }), true);
  for (const table of ["library_tags", "custom_lists", "custom_list_items"]) {
    const seen = [];
    const leaky = async (p) => { seen.push(p); return p.includes(`/${table}?`) ? [{ id: 1 }] : []; };
    assert.equal(await P.cleanupCheck({ actor: { id: "u1" }, state: {}, call: leaky }), false, table);
    assert.ok(seen.some((p) => p.includes(`${table}?user_id=eq.u1`)));
  }
  assert.equal(await P.cleanupCheck({ actor: {}, state: {}, call: none }), false);
});

test("qualify verdicts: 99 rebalance completions, or 29 in one subgroup or payload, are insufficient, never pass", () => {
  const selection = W.selectProfiles({ names: [NAME] });
  const mk = (kind, n, size, payload, ms = 100) => Array.from({ length: n }, () => ({ kind, ms, ok: true, librarySize: size, payload }));
  const op = (name, per) => [
    ...mk(`${NAME}:${name}`, per, 100, "typical"), ...mk(`${NAME}:${name}`, per, 2000, "maximum"),
  ];
  const full = (rebalance) => [
    ...["tag-index", "lists", "delta", "move", "create", "seed", "delete"].flatMap((name) => op(name, 100)),
    ...op("rebalance", rebalance),
  ];
  assert.equal(W.qualifyVerdicts(full(60), selection).verdict, "pass");
  assert.equal(W.qualifyVerdicts(full(49), selection).verdict, "insufficient", "98 rebalance completions");
  const subgroup = [...full(60).filter((x) => !(x.kind.endsWith(":rebalance") && x.librarySize === 100)), ...mk(`${NAME}:rebalance`, 29, 100, "typical")];
  assert.equal(W.qualifyVerdicts(subgroup, selection).verdict, "insufficient", "29 in one subgroup");
  const payload = [...full(60).filter((x) => !(x.kind.endsWith(":rebalance") && x.payload === "maximum")), ...mk(`${NAME}:rebalance`, 29, 2000, "maximum")];
  assert.equal(W.qualifyVerdicts(payload, selection).verdict, "insufficient", "29 maximum payloads");
});
