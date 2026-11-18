"use strict";
// W10 "Up next in your series": the up-next read (Browse class) and the section's own writes with
// their Undos (Progress class): Plan (insert a Planning row) / Plan Undo (fenced remove), and
// Not interested (deck skip) / its Undo (deck retract). Profiles must not require backend_workload.js;
// helpers arrive through `core`.
//
// Each ACTOR walks its own 10-slot cycle (state.n), so a write's Undo always follows it on the same
// actor and the account returns to its starting state after every pair:
//   0-5 read, 6 plan, 7 plan-undo, 8 dismiss, 9 dismiss-undo.
// A write slot whose precondition is missing (no read yet; no planned row to undo) sends a read instead,
// so state can never drift. Writes use the anime list (up-next cards of either medium cost the same).
const { randomUUID } = require("node:crypto");
const NAME = "collection-up-next";
const MEDIA = ["anime", "manga"];
const stateOf = (actor) => actor.profileState?.[NAME];
const ownedSet = (s, medium) => new Set(s.owned?.[medium] ?? []);
const completedSet = (s, medium) => new Set(s.completed?.[medium] ?? []);
// Seed sizes per library size: completed titles whose sequel the actor does not own.
const WANT = Object.freeze({
  2000: Object.freeze({ anime: 100, manga: 30 }),
  100: Object.freeze({ anime: 40, manga: 12 }),
});
// `requires`: unowned sequel targets the seed must have found per subgroup.
const MIN_TARGETS = Object.freeze({
  2000: Object.freeze({ anime: 40, manga: 10 }),
  100: Object.freeze({ anime: 15, manga: 5 }),
});
const BAD_FORMATS = new Set(["SPECIAL", "MUSIC", "TV_SHORT"]);
const eligible = (row, medium) =>
  row && row.is_adult !== true && row.status !== "CANCELLED" &&
  !(row.genres ?? []).some((g) => g === "Hentai" || g === "Ecchi") &&
  !(medium === "anime" && BAD_FORMATS.has(String(row.format ?? "").toUpperCase()));
const sizeKey = (size) => (size >= 2000 ? 2000 : 100);

async function readOwned(call, actor, medium) {
  const table = medium + "_user_lists";
  const col = medium + "_id";
  const owned = [];
  const completed = [];
  for (let offset = 0; offset < 4000; offset += 1000) {
    const rows = await call(
      `/rest/v1/${table}?select=${col},list_type&order=${col}&limit=1000&offset=${offset}`,
      undefined,
      { method: "GET", token: actor.token },
    );
    for (const r of rows) {
      owned.push(r[col]);
      if (r.list_type === "COMPLETED") completed.push(r[col]);
    }
    if (rows.length < 1000) break;
  }
  return { owned, completed };
}

module.exports = {
  name: NAME,
  operations: {
    read: { budgetClass: "browse", share: 0.6 },
    plan: { budgetClass: "progress", share: 0.1 },
    "plan-undo": { budgetClass: "progress", share: 0.1 },
    dismiss: { budgetClass: "progress", share: 0.1 },
    "dismiss-undo": { budgetClass: "progress", share: 0.1 },
  },
  ratePerSecond: 2, // arrivals/s: 1,200 in 600 s = 720 reads, 120 of each write, 60 per subgroup
  librarySizes: [100, 2000], // size-0 and tiny libraries have no completed titles to continue
  writes: true,
  emptyExamples: [[], {}, null],
  requires(fixture, actor) {
    const s = stateOf(actor);
    if (!s || !Array.isArray(s.completed?.anime)) return "no seeded up-next fixture";
    const need = MIN_TARGETS[sizeKey(actor.librarySize)];
    for (const medium of MEDIA) {
      if ((s.seeded?.[medium]?.length ?? 0) < need[medium]) {
        return `fewer than ${need[medium]} completed ${medium} titles with an unowned sequel`;
      }
    }
    return null;
  },
  // Completed rows for titles whose SEQUEL the actor does not own, inserted exactly as
  // SupabaseLibraryBackend.insertIfMissing does (POST on_conflict=user_id,<medium>_id,
  // Prefer resolution=ignore-duplicates,return=representation) with the actor's own token.
  async seed({ actor, fixture, call }) {
    const want = WANT[sizeKey(actor.librarySize)];
    const s = {
      n: 0,
      owned: {}, completed: {}, seeded: {}, reads: { anime: [], manga: [] },
      planned: null, planTarget: null, dismissed: null,
    };
    for (const medium of MEDIA) {
      const T = medium.toUpperCase();
      const table = medium + "_user_lists";
      const col = medium + "_id";
      const { owned, completed } = await readOwned(call, actor, medium);
      const ownedIds = new Set(owned);
      const from = new Set();
      const to = new Set();
      for (let page = 0; page < 8 && from.size < want[medium]; page++) {
        const edges = await call(
          `/rest/v1/media_relations?select=from_media_id,to_media_id&from_media_type=eq.${T}&to_media_type=eq.${T}` +
            `&relation_type=eq.SEQUEL&order=from_media_id,to_media_id&limit=1000&offset=${page * 1000}`,
          undefined,
          { method: "GET", token: actor.token },
        );
        const candidates = edges.filter((e) =>
          e.from_media_id !== e.to_media_id && !ownedIds.has(e.from_media_id) && !ownedIds.has(e.to_media_id));
        const targetIds = [...new Set(candidates.map((e) => e.to_media_id))];
        const ok = new Set();
        for (let i = 0; i < targetIds.length; i += 100) {
          const chunk = targetIds.slice(i, i + 100);
          const rows = await call(
            `/rest/v1/${medium}?select=id,format,status,genres,is_adult&id=in.(${chunk.join(",")})`,
            undefined,
            { method: "GET", token: actor.token },
          );
          for (const r of rows) if (eligible(r, medium)) ok.add(r.id);
        }
        for (const e of candidates) {
          if (from.size >= want[medium]) break;
          if (!ok.has(e.to_media_id) || from.has(e.from_media_id) || to.has(e.to_media_id)) continue;
          if (to.has(e.from_media_id) || from.has(e.to_media_id)) continue;
          from.add(e.from_media_id);
          to.add(e.to_media_id);
        }
        if (edges.length < 1000) break;
      }
      const ids = [...from];
      // The seeded targets must not carry a dismissal already.
      if (to.size) {
        const hits = await call(
          `/rest/v1/taste_signal_events?user_id=eq.${actor.id}&media_type=eq.${T}` +
            `&media_id=in.(${[...to].join(",")})&event_type=in.(deck_skip,deck_known)&select=media_id`,
          undefined,
          { method: "GET", token: actor.token },
        );
        if (hits.length) throw new Error(NAME + ": seeded targets already carry deck signals");
      }
      const inserted = [];
      for (let i = 0; i < ids.length; i += 100) {
        const rows = await call(
          `/rest/v1/${table}?on_conflict=user_id,${col}&select=${col}`,
          ids.slice(i, i + 100).map((id) => ({ user_id: actor.id, [col]: id, list_type: "COMPLETED", progress: 0 })),
          { token: actor.token, prefer: "resolution=ignore-duplicates,return=representation" },
        );
        for (const r of rows) inserted.push(r[col]);
      }
      s.owned[medium] = [...owned, ...inserted];
      s.completed[medium] = [...completed, ...inserted];
      s.seeded[medium] = inserted;
    }
    s.targetCount = { anime: s.seeded.anime.length, manga: s.seeded.manga.length };
    return s;
  },
  request(actor, fixture, seq, random, core) {
    const s = stateOf(actor);
    const slot = s.n % 10;
    s.n += 1;
    const anime = s.reads.anime ?? [];
    let op = ["read", "read", "read", "read", "read", "read", "plan", "plan-undo", "dismiss", "dismiss-undo"][slot];
    if (op === "plan" && anime.length < 1) op = "read";
    if (op === "plan-undo" && !s.planned) op = "read";
    if (op === "dismiss" && anime.length < 1) op = "read";
    if (op === "dismiss-undo" && !s.dismissed) op = "read";
    if (op === "read") {
      return {
        operation: "read",
        path: "/rest/v1/rpc/library_up_next_v1",
        body: { p_medium: s.n % 3 === 0 ? "manga" : "anime", p_limit: 30 },
      };
    }
    if (op === "plan") {
      s.planTarget = anime[0];
      return {
        operation: "plan",
        path: "/rest/v1/anime_user_lists?on_conflict=user_id,anime_id&select=id,anime_id,lifecycle_id,server_revision,list_type",
        body: { user_id: actor.id, anime_id: s.planTarget, list_type: "PLANNING", progress: 0 },
        prefer: "resolution=ignore-duplicates,return=representation",
      };
    }
    if (op === "plan-undo") {
      return {
        operation: "plan-undo",
        path: "/rest/v1/rpc/apply_remove_mutations_v1",
        body: {
          p_mutations: [{
            mutation_id: randomUUID(),
            medium: "anime",
            media_id: s.planned.mediaId,
            lifecycle_id: s.planned.lifecycleId,
            base_revision: s.planned.revision,
          }],
        },
      };
    }
    if (op === "dismiss") {
      s.dismissed = null;
      s.dismissTarget = anime[anime.length > 1 ? 1 : 0];
      return {
        operation: "dismiss",
        path: "/rest/v1/rpc/record_taste_deck_signal",
        body: { p_media_type: "ANIME", p_media_id: s.dismissTarget, p_action: "skip" },
      };
    }
    return {
      operation: "dismiss-undo",
      path: "/rest/v1/rpc/record_taste_deck_signal",
      body: { p_media_type: "ANIME", p_media_id: s.dismissed, p_action: "retract" },
    };
  },
  validate(data, actor, step, ctx) {
    const s = stateOf(actor);
    if (!step) return false;
    const qualify = ctx?.mode === "qualify";
    const op = step.operation;
    if (op === "read") {
      if (!Array.isArray(data) || data.length > 30) return false;
      if (!qualify) return true;
      if (!s || data.length < 1) return false;
      const medium = step.body?.p_medium;
      if (!MEDIA.includes(medium)) return false;
      const done = completedSet(s, medium);
      const owned = ownedSet(s, medium);
      const clean = data.every((r) =>
        Number.isInteger(r?.media_id) && r.media_type === medium && done.has(r.after_media_id) &&
        !owned.has(r.media_id) && (r.link === "sequel" || r.link === "reviewed"));
      if (!clean) return false;
      // A 2,000-title actor holds >= 100 unowned sequel targets: a short answer means a leaked Plan or Dismiss.
      if (medium === "anime" && actor.librarySize >= 2000 && data.length !== 30) return false;
      s.reads[medium] = data.map((r) => r.media_id);
      return true;
    }
    if (op === "plan") {
      if (!Array.isArray(data) || data.length !== 1) return false;
      const row = data[0];
      if (!qualify) return row?.list_type === "PLANNING";
      if (
        !s || row?.anime_id !== s.planTarget || row.list_type !== "PLANNING" ||
        typeof row.lifecycle_id !== "string" || !Number.isInteger(row.server_revision)
      ) return false;
      s.planned = { mediaId: row.anime_id, lifecycleId: row.lifecycle_id, revision: row.server_revision };
      return true;
    }
    if (op === "plan-undo") {
      const sent = step.body?.p_mutations?.[0];
      const item = data?.items?.[0];
      if (!sent || item?.mutation_id !== sent.mutation_id || item.outcome !== "applied") return false;
      if (s) s.planned = null;
      return true;
    }
    if (op === "dismiss") {
      const ok = data?.ok === true && data.action === "skip" && data.media_id === step.body?.p_media_id;
      if (ok && s) s.dismissed = step.body.p_media_id;
      return ok;
    }
    if (op === "dismiss-undo") {
      const ok = data?.ok === true && data.action === "retract" && (!qualify || data.deleted === 1);
      if (ok && s) s.dismissed = null;
      return ok;
    }
    return false;
  },
  // After the disposable account's auth record is gone (delete-account), its list rows and every
  // taste signal (taste_signal_events.user_id cascades) are gone too.
  async cleanupCheck({ actor, call }) {
    const userId = actor?.id;
    if (!userId) return false;
    for (const table of ["anime_user_lists", "manga_user_lists", "taste_signal_events"]) {
      const rows = await call(
        `/rest/v1/${table}?user_id=eq.${userId}&select=id&limit=1`,
        undefined,
        { method: "GET" },
      );
      if (!Array.isArray(rows) || rows.length !== 0) return false;
    }
    return true;
  },
};
