"use strict";
// W2 export: the public catalogue identity lookup the app makes while preparing a MAL file
// (CatalogStore+ExportIdentities): one GET of at most 500 ids per batch, sent with the actor's
// bearer (the app leases this read because its id set is account data).
// Profiles must not require backend_workload.js; helpers arrive through `core`.
const NAME = "export-mal-id-lookup";
const BATCH = 500;
const SELECT = "id,mal_id,title_english,title_romaji,title_native";

module.exports = {
  name: NAME,
  budgetClass: "browse", // 750 ms
  ratePerSecond: 0.2, // on-demand export is rare: 120 completions in 600 s, 40 per covered subgroup
  librarySizes: [25, 100, 2000], // a size-0 account has nothing to export
  writes: false,
  emptyExamples: [[], {}, null],
  request(actor, fixture, seq, random, core) {
    const medium = seq % 3 === 0 ? "manga" : "anime";
    const pool = fixture.media[medium] ?? [];
    const take = Math.min(BATCH, pool.length);
    const start = pool.length === 0 ? 0 : (seq * BATCH) % pool.length;
    const ids = [];
    for (let i = 0; i < take; i++) ids.push(pool[(start + i) % pool.length]);
    return {
      method: "GET",
      path: "/rest/v1/" + medium + "?select=" + SELECT + "&id=in.(" + ids.join(",") + ")",
    };
  },
  // "wiring" (default, never release evidence) accepts an empty array; "qualify" requires a
  // non-empty answer containing only requested ids (populated fixture: real catalogue ids).
  validate(data, actor, request, ctx) {
    if (!Array.isArray(data) || data.length > BATCH || !data.every((x) => Number.isInteger(x?.id))) return false;
    if (ctx?.mode !== "qualify") return true;
    if (!data.every((x) => x.id > 0)) return false;
    const m = decodeURIComponent(request?.path ?? "").match(/id=in\.\(([^)]*)\)/);
    if (!m) return false;
    const asked = new Set(m[1].split(",").map(Number));
    return data.length >= 1 && data.every((x) => asked.has(x.id));
  },
};
