"use strict";
// W6 Collection grouping: the reviewed-membership read the app makes (CatalogStore+SeriesMembership):
// one GET per medium and batch of at most 300 ids against series_entry_spans with the three approval
// filters, sent with the actor's bearer (the app leases this read because its id set is account data).
// Browse class. Only anime is driven (a manga batch costs the same). Profiles must not require
// backend_workload.js; helpers arrive through `core`.
const NAME = "collection-series-membership";
const BATCH = 300;
const SELECT =
  "anime_id,manga_id,medium," +
  "series!series_entry_spans_series_id_fkey!inner(id,medium,continuity,grouping_state)," +
  "series_sections!series_entry_spans_section_id_fkey!inner(kind,ordinal,name,sort_order,state)";

module.exports = {
  name: NAME,
  budgetClass: "browse", // 750 ms
  ratePerSecond: 1, // one membership read per Collection open: 600 completions in 600 s, 200 per library size
  librarySizes: [25, 100, 2000], // a size-0 account has no Collection rows to group
  writes: false,
  emptyExamples: [[], {}, [{ anime_id: 1 }]],
  // Refuses a qualify run until reviewed membership is published and the fixture names its member ids
  // (production membership is empty until the owner decision D-G / the pilot).
  requires(fixture) {
    const ids = fixture?.media?.seriesMemberIds;
    return Array.isArray(ids) && ids.length > 0 ? null : "no published series member ids";
  },
  request(actor, fixture, seq) {
    const pool = fixture.media?.anime ?? [];
    const members = fixture.media?.seriesMemberIds ?? [];
    const take = Math.min(BATCH, pool.length);
    const start = pool.length === 0 ? 0 : (seq * BATCH) % pool.length;
    const ids = [];
    for (let i = 0; i < take; i++) ids.push(pool[(start + i) % pool.length]);
    if (members.length > 0 && !ids.some((id) => members.includes(id))) {
      const member = members[seq % members.length];
      if (ids.length >= BATCH) ids[ids.length - 1] = member;
      else ids.push(member);
    }
    return {
      method: "GET",
      path:
        "/rest/v1/series_entry_spans?select=" + SELECT + "&medium=eq.anime&anime_id=in.(" + ids.join(",") + ")" +
        "&series.continuity=eq.verified&series.grouping_state=eq.approved&series_sections.state=eq.approved",
    };
  },
  // "wiring" (default, never release evidence) accepts an empty array; "qualify" requires a non-empty
  // answer whose rows each carry series.id, series_sections.kind and an integer anime_id.
  validate(data, actor, request, ctx) {
    if (!Array.isArray(data)) return false;
    if (ctx?.mode !== "qualify") return true;
    return data.length >= 1 && data.every((r) =>
      Number.isInteger(r?.anime_id) && typeof r?.series?.id === "string" && typeof r?.series_sections?.kind === "string");
  },
};
