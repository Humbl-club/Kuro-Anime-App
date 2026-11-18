"use strict";
// W4: Search page 1 through search_<medium>_page_v2 (items + the bounded hidden-adult count in
// one response). Public catalogue read: no account data, no credential lease. Profiles must not
// require backend_workload.js; this file has no dependency on it.
const WORDS = [
  "Naruto", "One", "Frieren", "Berserk", "Attack",
  "Dragon", "Haikyuu", "Fate", "Love", "Solo",
]; // the predeclared `search` word list (backend_workload.js requestFor)
module.exports = {
  name: "search-with-hidden-adult-count",
  budgetClass: "search", // 750 ms
  ratePerSecond: 1, // old weight 5 x 0.2 (F3.1 conversion): page-1 v2 calls only
  writes: false, // librarySizes omitted: every fixture size (0, 25, 100, 2000) supplies actors
  emptyExamples: [[], {}, { items: [], hidden_adult: 0 }, { items: [{ id: 1 }] }],
  request(actor, fixture, seq) {
    const medium = seq % 3 === 0 ? "manga" : "anime";
    return {
      path: "/rest/v1/rpc/search_" + medium + "_page_v2",
      body: { p_query: WORDS[seq % 10], p_limit: 30 },
    };
  },
  validate(data, actor, request, ctx) {
    const shape = Array.isArray(data?.items) && data.items.every((x) => Number.isInteger(x.id)) &&
      (data.hidden_adult === null || Number.isInteger(data.hidden_adult));
    if (ctx?.mode !== "qualify") return shape; // wiring: shape only, never release evidence
    // qualify: the fixture words match real catalogue titles, so page 1 is non-empty, and a page-1
    // query of >= 2 characters always carries an integer count (0-100), never null
    return shape && data.items.length >= 1 && Number.isInteger(data.hidden_adult) &&
      data.hidden_adult >= 0 && data.hidden_adult <= 100;
  },
};
