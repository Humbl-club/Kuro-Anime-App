"use strict";
// F2 date leg: with the revision fence on and library_date_autofill_v1 enabled, a status change
// that fills a date is two requests: the durable status mutation, then a PATCH of the date.
// Each action toggles one dedicated PLANNING row between "fill" (-> WATCHING + today as the
// start date) and "undo" (-> PLANNING + no start date). Never touches actor.writeEntry: the
// PATCH advances server_revision and would stale the base `progress` kind.
// Profiles must not require backend_workload.js; helpers arrive through `core`.
const { randomUUID } = require("node:crypto");
const NAME = "status-with-date-fill";
const TABLE_SELECT = "id,list_type,started_raw,server_revision";
const stateOf = (actor) => actor.profileState?.[NAME];
function todayIn(timeZone, date) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone, year: "numeric", month: "2-digit", day: "2-digit",
  }).format(date);
}
module.exports = {
  name: NAME,
  operations: {
    mutation: { budgetClass: "progress" },
    "date-patch": { budgetClass: "progress" },
  },
  ratePerSecond: 0.4, // actions/s: 240 per leg in 600 s, 80 per covered subgroup
  librarySizes: [25, 100, 2000], // size-0 accounts have nothing to change
  writes: true,
  payloads: ["typical"],
  emptyExamples: [[], {}, { items: [] }],
  todayIn,
  requires(fixture, actor) {
    return Number.isInteger(stateOf(actor)?.rowId)
      ? null
      : "no seeded date-fill entry";
  },
  // One dedicated PLANNING row per covered actor, inserted exactly as
  // SupabaseLibraryBackend.insertIfMissing does (POST on_conflict=user_id,anime_id,
  // Prefer resolution=ignore-duplicates,return=representation).
  async seed({ actor, fixture, call }) {
    const owned = new Set();
    for (let offset = 0; offset < 3000; offset += 1000) {
      const rows = await call(
        "/rest/v1/anime_user_lists?select=anime_id&order=anime_id&limit=1000&offset=" + offset,
        undefined,
        { method: "GET", token: actor.token },
      );
      for (const r of rows) owned.add(r.anime_id);
      if (rows.length < 1000) break;
    }
    const mediaId = fixture.media.anime.find((id) => !owned.has(id));
    if (!Number.isInteger(mediaId)) {
      throw new Error(NAME + ": no catalogue title outside the actor's library");
    }
    const rows = await call(
      "/rest/v1/anime_user_lists?on_conflict=user_id,anime_id&select=id,anime_id,lifecycle_id,server_revision,list_type",
      { user_id: actor.id, anime_id: mediaId, list_type: "PLANNING", progress: 0 },
      { token: actor.token, prefer: "resolution=ignore-duplicates,return=representation" },
    );
    const row = rows?.[0];
    if (!row) throw new Error(NAME + ": seed row not inserted");
    return {
      rowId: row.id,
      mediaId,
      lifecycleId: row.lifecycle_id,
      revision: row.server_revision,
      phase: "fill",
    };
  },
  request(actor, fixture, seq, random, core) {
    const s = stateOf(actor);
    const fill = s.phase === "fill";
    return {
      steps: [
        {
          operation: "mutation",
          path: "/rest/v1/rpc/apply_progress_mutations_v1",
          body: {
            p_mutations: [{
              mutation_id: randomUUID(),
              medium: "anime",
              media_id: s.mediaId,
              lifecycle_id: s.lifecycleId,
              base_revision: s.revision,
              status: fill ? "WATCHING" : "PLANNING",
            }],
          },
          payload: "typical",
        },
        {
          operation: "date-patch",
          method: "PATCH",
          path: `/rest/v1/anime_user_lists?id=eq.${s.rowId}&select=${TABLE_SELECT}`,
          body: { started_raw: fill ? todayIn("Europe/Berlin", core.now()) : null },
          payload: "typical",
        },
      ],
    };
  },
  validate(data, actor, step, ctx) {
    const s = stateOf(actor);
    if (!s || !step) return false;
    if (step.operation === "mutation") {
      const sent = step.body?.p_mutations?.[0];
      const item = data?.items?.[0];
      if (
        !sent || item?.mutation_id !== sent.mutation_id ||
        item.outcome !== "applied" || !Number.isInteger(item.server_revision)
      ) return false;
      s.revision = item.server_revision;
      return true;
    }
    if (step.operation === "date-patch") {
      if (!Array.isArray(data) || data.length !== 1) return false;
      const row = data[0];
      const fill = s.phase === "fill";
      if (
        row?.id !== s.rowId || row.started_raw !== step.body.started_raw ||
        row.list_type !== (fill ? "WATCHING" : "PLANNING") ||
        !Number.isInteger(row.server_revision)
      ) return false;
      s.revision = row.server_revision;
      s.phase = fill ? "undo" : "fill"; // flips only after both legs succeeded
      return true;
    }
    return false;
  },
  async cleanupCheck({ state, call }) {
    const rows = await call(
      `/rest/v1/anime_user_lists?id=eq.${state.rowId}&select=id`,
      undefined,
      { method: "GET" },
    );
    return Array.isArray(rows) && rows.length === 0;
  },
};
