"use strict";
// W9 "Collection with tags and lists": the tag index and list reads (Browse class) and the organisation
// writes (Progress class): the atomic organise delta, a guarded one-row move, a rebalance, list create, a
// seed with 50 titles and list delete. Profiles must not require backend_workload.js; helpers arrive
// through `core`.
//
// Each ACTOR walks its own 25-slot cycle (state.n), 4 % of the arrivals per slot:
//   0-6 tag-index, 7-12 lists, 13-16 delta, 17-19 move, 20 rebalance, 21 create, 22 seed, 23-24 delete.
// A write slot whose precondition is missing (nothing created yet, every candidate list busy, an unknown
// list id) sends a list read instead, so state can never drift. A list with a write in flight is skipped
// (`busy`), so two writes of one actor never race on one list's revision.
//
// The seed RPC returns names, not ids: the id of a seeded "-s" list is learned from the next list read, so
// slot 24 deletes the PREVIOUS cycle's "-s" list (the actor keeps at most three transient lists).
const { randomUUID } = require("node:crypto");
const NAME = "collection-with-tags-and-lists";
const SPACING = 1024;
const BUSY_MS = 15000;
const MAX_ITEMS = 2000;
const SEED_TITLES = 50;
const rep = (name, n) => Array.from({ length: n }, () => name);
const SLOTS = Object.freeze([
  ...rep("tag-index", 7), ...rep("lists", 6), ...rep("delta", 4), ...rep("move", 3),
  "rebalance", "create", "seed", "delete", "delete",
]);
const stateOf = (actor) => actor.profileState?.[NAME];
const big = (actor) => actor.librarySize >= 2000;
const sizePayload = (actor) => (big(actor) ? "maximum" : "typical");
const nowMs = (core) => (core?.now?.() ?? new Date()).getTime();
const keyOf = (k) => `${k.medium}:${k.id}`;
const isInt = Number.isInteger;
const isStr = (x) => typeof x === "string";
const fixtureName = (i) => `load-fx-${String(i + 1).padStart(2, "0")}`;
const TAG_ROWS = Object.freeze({ 2000: 1000, 100: 50 });

const shapeIndex = (d) => Array.isArray(d) && d.every((r) =>
  r && (r.medium === "anime" || r.medium === "manga") && isInt(r.media_id) &&
  Array.isArray(r.tags) && r.tags.every(isStr));
const shapeLists = (d) => Array.isArray(d) && d.every((l) =>
  l && isStr(l.id) && isStr(l.name) && isStr(l.created_at) && isInt(l.revision) && Array.isArray(l.items) &&
  l.items.every((i) => i && isInt(i.media_id) && typeof i.position === "number"));

const free = (s, listId, now) => s.busy[listId] === undefined || now - s.busy[listId] > BUSY_MS;
const pickList = (s, candidates, now) => candidates.find((id) => id && free(s, id, now) && (s.items[id]?.length ?? 0) >= 4);
const ordered = (items) => [...items].sort((a, b) => a.position - b.position || (a.id < b.id ? -1 : 1));
const readOp = (actor) => ({
  operation: "lists",
  path: "/rest/v1/rpc/custom_lists_v1",
  body: {},
  payload: sizePayload(actor),
});

async function readKeys(call, actor) {
  const keys = [];
  for (const medium of ["anime", "manga"]) {
    const col = medium + "_id";
    for (let offset = 0; offset < 4000; offset += 1000) {
      const rows = await call(
        `/rest/v1/${medium}_user_lists?select=${col}&order=${col}&limit=1000&offset=${offset}`,
        undefined,
        { method: "GET", token: actor.token },
      );
      for (const r of rows) keys.push({ medium, id: r[col] });
      if (rows.length < 1000) break;
    }
  }
  return keys;
}

const rpc = (call, actor, name, body) => call(`/rest/v1/rpc/${name}`, body, { token: actor.token });

module.exports = {
  name: NAME,
  operations: {
    "tag-index": { budgetClass: "browse", share: 0.28 },
    lists: { budgetClass: "browse", share: 0.24 },
    delta: { budgetClass: "progress", share: 0.16 },
    move: { budgetClass: "progress", share: 0.12 },
    rebalance: { budgetClass: "progress", share: 0.04 },
    create: { budgetClass: "progress", share: 0.04 },
    seed: { budgetClass: "progress", share: 0.04 },
    delete: { budgetClass: "progress", share: 0.08 },
  },
  ratePerSecond: 5, // 3,000 arrivals in 600 s: the rarest operations expect 120 completions, 60 per subgroup/payload
  librarySizes: [100, 2000],
  writes: true,
  payloads: ["typical", "maximum"],
  emptyExamples: [[], {}, null, { tags: [] }],
  requires(fixture, actor) {
    const s = stateOf(actor);
    if (!s || !Array.isArray(s.listIds)) return "no seeded organisation fixture";
    if (s.listIds.length !== 20) return "fewer than the 20 fixture lists";
    if (big(actor) && !s.maxListId) return "no 2,000-item list";
    if (!Array.isArray(s.nineTagKeys) || s.nineTagKeys.length < 10) return "fewer than 10 titles with 9 tags";
    return null;
  },
  // Populated fixture through the actor's OWN rpc calls (no service role), before the measured window:
  // 20 lists (19 x 100 items plus one list of 2,000 for a 2,000-title actor; 20 x 10 for a 100-title actor),
  // tags on every 2nd title, ten titles with 9 tags.
  async seed({ actor, fixture, call }) {
    const keys = await readKeys(call, actor);
    const n = keys.length;
    const wantBig = big(actor);
    const per = wantBig ? 100 : 10;
    const window = (i) => Array.from({ length: Math.min(per, n) }, (_, j) => keys[(i * per + j) % n]);
    const lists = Array.from({ length: 20 }, (_, i) => ({
      name: fixtureName(i),
      items: (wantBig && i === 19 ? keys.slice(0, MAX_ITEMS) : window(i)).map((k) => ({ medium: k.medium, media_id: k.id })),
    }));
    await rpc(call, actor, "seed_custom_lists_v1", { p_lists: lists });
    const listKeys = {};
    lists.forEach((l, i) => { listKeys[i] = new Set(l.items.map((it) => `${it.medium}:${it.media_id}`)); });

    const tagWork = [];
    const nineTagKeys = [];
    for (let i = 0; i < n; i += 2) {
      const nine = nineTagKeys.length < 10;
      const tags = nine
        ? Array.from({ length: 9 }, (_, t) => "t" + (t + 1))
        : ["comfy", "rewatch", "slow burn"].slice(0, 1 + ((i / 2) % 3));
      if (nine) nineTagKeys.push(keys[i]);
      tagWork.push({ key: keys[i], tags });
    }
    for (let i = 0; i < tagWork.length; i += 8) {
      await Promise.all(tagWork.slice(i, i + 8).map(({ key, tags }) =>
        rpc(call, actor, "apply_title_organisation_delta_v1", {
          p_medium: key.medium, p_media_id: key.id, p_add_tags: tags, p_remove_tags: [],
          p_add_list_ids: [], p_remove_list_ids: [],
        })));
    }

    const read = await rpc(call, actor, "custom_lists_v1", {});
    const byName = new Map(read.map((l) => [l.name, l]));
    const listIds = [], items = {}, revisions = {};
    for (let i = 0; i < 20; i++) {
      const row = byName.get(fixtureName(i));
      if (!row) throw new Error(NAME + ": seed list missing " + fixtureName(i));
      listIds.push(row.id);
      revisions[row.id] = row.revision;
      items[row.id] = row.items.map((it) => ({ id: it.item_id, position: it.position }));
    }
    const list0 = listKeys[0];
    return {
      n: 0, run: randomUUID().slice(0, 6), cycle: 0,
      listIds, maxListId: wantBig ? listIds[19] : null, items, revisions,
      nineTagKeys, tracked: keys, tagRows: tagWork.length,
      freeKey: keys.find((k) => !list0.has(keyOf(k))) ?? keys[keys.length - 1],
      tagOn: false, deltaN: 0, moveN: 0, rebN: 0, member: { in: false, itemId: null },
      busy: {}, created: null, sLists: [],
    };
  },
  request(actor, fixture, seq, random, core) {
    const s = stateOf(actor);
    const slot = s.n % SLOTS.length;
    s.n += 1;
    const now = nowMs(core);
    const payload = sizePayload(actor);
    let op = SLOTS[slot];

    if (op === "delta") {
      const member = s.deltaN % 2 === 1 && free(s, s.listIds[0], now);
      s.deltaN += 1;
      if (!member) {
        const add = !s.tagOn;
        s.tagOn = add;
        const key = s.nineTagKeys[0];
        return {
          operation: "delta", payload: add ? "maximum" : "typical",
          path: "/rest/v1/rpc/apply_title_organisation_delta_v1",
          body: {
            p_medium: key.medium, p_media_id: key.id,
            p_add_tags: add ? ["load-t"] : [], p_remove_tags: add ? [] : ["load-t"],
            p_add_list_ids: [], p_remove_list_ids: [],
          },
          meta: { kind: "tag", add },
        };
      }
      const listId = s.listIds[0];
      const add = !s.member.in;
      s.member.in = add;
      s.busy[listId] = now;
      const key = s.freeKey ?? s.tracked[s.tracked.length - 1];
      return {
        operation: "delta", payload: "typical",
        path: "/rest/v1/rpc/apply_title_organisation_delta_v1",
        body: {
          p_medium: key.medium, p_media_id: key.id, p_add_tags: [], p_remove_tags: [],
          p_add_list_ids: add ? [listId] : [], p_remove_list_ids: add ? [] : [listId],
        },
        meta: { kind: "member", add, listId },
      };
    }
    if (op === "move") {
      const even = s.moveN % 2 === 0;
      const typical = big(actor) ? s.listIds[1] : s.listIds[even ? 1 : 3];
      const candidates = big(actor) ? (even ? [typical, s.maxListId] : [s.maxListId, typical]) : [s.listIds[1], s.listIds[3]];
      const listId = pickList(s, candidates, now);
      s.moveN += 1;
      if (!listId) return readOp(actor);
      const list = ordered(s.items[listId]);
      const moved = list[list.length - 1];
      const others = list.slice(0, -1);
      // A random gap between two other items (a mid-list move writes one row; head/tail never apply here).
      const g = Math.min(others.length - 2, Math.floor(random() * (others.length - 1)));
      const after = others[g].position, before = others[g + 1].position;
      s.busy[listId] = now;
      return {
        operation: "move", payload: listId === s.maxListId ? "maximum" : "typical",
        path: "/rest/v1/rpc/move_custom_list_item_v1",
        body: {
          p_list_id: listId, p_item_id: moved.id, p_after_position: after, p_before_position: before,
          p_expected_list_revision: s.revisions[listId],
        },
        meta: { listId, itemId: moved.id, after, before, expected: s.revisions[listId] },
      };
    }
    if (op === "rebalance") {
      const even = s.rebN % 2 === 0;
      const candidates = big(actor) ? (even ? [s.listIds[2], s.maxListId] : [s.maxListId, s.listIds[2]]) : [s.listIds[2], s.listIds[4]];
      const listId = pickList(s, candidates, now);
      s.rebN += 1;
      if (!listId) return readOp(actor);
      s.busy[listId] = now;
      return {
        operation: "rebalance", payload: listId === s.maxListId ? "maximum" : "typical",
        path: "/rest/v1/rpc/rebalance_custom_list_v1",
        body: {
          p_list_id: listId, p_item_ids: ordered(s.items[listId]).map((i) => i.id),
          p_expected_list_revision: s.revisions[listId],
        },
        meta: { listId, expected: s.revisions[listId] },
      };
    }
    if (op === "create") {
      s.cycle += 1;
      const name = `load-${s.run}-${s.cycle}-c`;
      return { operation: "create", payload, path: "/rest/v1/rpc/create_custom_list_v1", body: { p_name: name }, meta: { name } };
    }
    if (op === "seed") {
      const name = `load-${s.run}-${s.cycle}-s`;
      const items = s.tracked.slice(0, SEED_TITLES).map((k) => ({ medium: k.medium, media_id: k.id }));
      return { operation: "seed", payload, path: "/rest/v1/rpc/seed_custom_lists_v1", body: { p_lists: [{ name, items }] }, meta: { name } };
    }
    if (op === "delete") {
      // Slot 23 deletes this cycle's "-c" list, slot 24 the oldest known "-s" list.
      const target = slot === 23 ? s.created?.id : s.sLists[0];
      if (!target) return readOp(actor);
      if (slot === 23) s.created = null; else s.sLists.shift();
      return { operation: "delete", payload, path: "/rest/v1/rpc/delete_custom_list_v1", body: { p_list_id: target }, meta: { listId: target } };
    }
    if (op === "tag-index") {
      return { operation: "tag-index", payload, path: "/rest/v1/rpc/library_tag_index_v1", body: {} };
    }
    return readOp(actor);
  },
  validate(data, actor, step, ctx) {
    if (!step?.operation) return false;
    const s = stateOf(actor);
    const qualify = ctx?.mode === "qualify";
    const op = step.operation;
    const meta = step.meta ?? {};
    if (meta.listId && s?.busy) delete s.busy[meta.listId];

    if (op === "tag-index") {
      if (!shapeIndex(data)) return false;
      if (!qualify) return true;
      const need = TAG_ROWS[big(actor) ? 2000 : 100];
      return !!s && data.length >= need && data.some((r) => r.tags.length >= 9);
    }
    if (op === "lists") {
      if (!shapeLists(data)) return false;
      if (!qualify) return true;
      if (!s || !Array.isArray(s.listIds)) return false;
      const byId = new Map(data.map((l) => [l.id, l]));
      if (!s.listIds.every((id) => byId.has(id))) return false;
      const transient = data.filter((l) => !s.listIds.includes(l.id));
      if (transient.length > 3) return false;
      if (s.maxListId) {
        const max = byId.get(s.maxListId);
        if (max.items.length !== MAX_ITEMS) return false;
        for (let i = 1; i < max.items.length; i++) if (!(max.items[i].position > max.items[i - 1].position)) return false;
      }
      for (const l of data) {
        if (!s.listIds.includes(l.id) || !free(s, l.id, Date.now())) continue;
        s.revisions[l.id] = l.revision;
        s.items[l.id] = l.items.map((i) => ({ id: i.item_id, position: i.position }));
      }
      s.sLists = transient.filter((l) => /^load-.*-s$/.test(l.name)).map((l) => l.id);
      return true;
    }
    if (op === "delta") {
      if (!data || !Array.isArray(data.tags) || !Array.isArray(data.items) || !Array.isArray(data.lists)) return false;
      if (!qualify) return true;
      if (data.tags.length > 10 || data.items.length > 10) return false;
      if (meta.kind === "tag") return data.tags.includes("load-t") === meta.add;
      const change = data.lists.find((l) => l.list_id === meta.listId);
      const row = data.items.find((i) => i.list_id === meta.listId);
      if (!change || change.revision !== change.revision_before + 1 || !!row !== meta.add) return false;
      if (s) {
        s.revisions[meta.listId] = change.revision;
        if (meta.add) {
          s.items[meta.listId].push({ id: row.item_id, position: row.position });
          s.member.itemId = row.item_id;
        } else {
          s.items[meta.listId] = s.items[meta.listId].filter((i) => i.id !== s.member.itemId);
          s.member.itemId = null;
        }
      }
      return true;
    }
    if (op === "move") {
      if (!data || !isStr(data.item_id) || typeof data.position !== "number" || !isInt(data.revision)) return false;
      if (!qualify) return true;
      if (data.item_id !== meta.itemId || !Number.isFinite(data.position)) return false;
      if (!(data.position > meta.after && data.position < meta.before)) return false;
      if (data.revision !== meta.expected + 1) return false;
      if (s) {
        const moved = s.items[meta.listId].find((i) => i.id === meta.itemId);
        if (moved) moved.position = data.position;
        s.revisions[meta.listId] = data.revision;
      }
      return true;
    }
    if (op === "rebalance") {
      if (!data || !isInt(data.revision) || !Array.isArray(data.items) ||
        !data.items.every((i) => i && isStr(i.item_id) && typeof i.position === "number")) return false;
      if (!qualify) return true;
      const sent = step.body?.p_item_ids ?? [];
      if (data.revision !== meta.expected + 1 || data.items.length !== sent.length || sent.length < 1) return false;
      const byPosition = [...data.items].sort((a, b) => a.position - b.position);
      if (!byPosition.every((i, k) => i.item_id === sent[k] && i.position === SPACING * (k + 1))) return false;
      if (s) {
        s.items[meta.listId] = byPosition.map((i) => ({ id: i.item_id, position: i.position }));
        s.revisions[meta.listId] = data.revision;
      }
      return true;
    }
    if (op === "create") {
      if (!data || !isStr(data.id) || !isStr(data.name) || !isStr(data.created_at) || !isInt(data.revision)) return false;
      if (!qualify) return true;
      if (data.name !== step.body?.p_name || data.revision !== 0) return false;
      if (s) s.created = { id: data.id, name: data.name };
      return true;
    }
    if (op === "seed") {
      if (!data || !Array.isArray(data.created) || !isInt(data.added)) return false;
      if (!qualify) return true;
      return data.added === SEED_TITLES && data.created.includes(step.body?.p_lists?.[0]?.name);
    }
    if (op === "delete") return data === null || data === undefined || data === "";
    return false;
  },
  // After the disposable account's auth record is gone (delete-account): its tags, lists and list items
  // cascade with it, so nothing may remain.
  async cleanupCheck({ actor, call }) {
    const userId = actor?.id;
    if (!userId) return false;
    for (const [table, column] of [["library_tags", "user_id"], ["custom_lists", "id"], ["custom_list_items", "id"]]) {
      const rows = await call(
        `/rest/v1/${table}?user_id=eq.${userId}&select=${column}&limit=1`,
        undefined,
        { method: "GET" },
      );
      if (!Array.isArray(rows) || rows.length !== 0) return false;
    }
    return true;
  },
};
