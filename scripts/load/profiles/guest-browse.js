"use strict";
// W5: guest browsing. Anonymous Discover, Search, Browse and title-page reads at an absolute 5 rps on top
// of the unchanged 20 rps base (its own lane; the predeclared mix is never edited). Every request is
// anonymous (anon key only, no account token) and goes to an RPC or table on the anon allowlist of
// 20261118110000_guest_anon_allowlist_v1.sql. No actor data is used, so there is no seed and no cleanup.
// Profiles must not require backend_workload.js; the base bodies come from `core.requestFor`.
const KINDS = Object.freeze([["discover", 5], ["search", 15], ["browse", 20], ["detail", 20]]);
const TOTAL = KINDS.reduce((n, [, w]) => n + w, 0);
const CLASSES = KINDS.map(([k]) => k);

function pickKind(random) {
  let n = random() * TOTAL;
  for (const [kind, weight] of KINDS) {
    n -= weight;
    if (n < 0) return kind;
  }
  return "detail";
}

module.exports = {
  name: "guest-browse",
  budgetClasses: ["discover", "search", "browse", "detail"], // summarised as "guest-browse:<class>" at LIMITS[class]
  ratePerSecond: 5, // absolute: 5 anonymous rps on top of the unchanged 20 rps base (about 20 % of 25 rps)
  writes: false, // anonymous: no actor data, so no seed and no cleanupCheck
  anonymous: true,
  emptyExamples: [[], {}, null],
  request(actor, fixture, seq, random, core) {
    const kind = pickKind(random);
    if (kind !== "detail") {
      return { ...core.requestFor(kind, actor, fixture, seq, random), anonymous: true, budgetClass: kind };
    }
    const medium = seq % 3 === 0 ? "manga" : "anime";
    const ids = fixture.media[medium];
    const id = ids[Math.min(ids.length - 1, Math.floor(random() ** 2 * ids.length))];
    if (seq % 2 === 0) {
      return {
        method: "GET",
        path: "/rest/v1/" + medium + "?id=eq." + id +
          "&select=id,title_romaji,title_english,cover_image_large,description",
        anonymous: true,
        budgetClass: "detail",
      };
    }
    return {
      path: "/rest/v1/rpc/get_media_ladder",
      body: { p_media_type: medium.toUpperCase(), p_media_id: id },
      anonymous: true,
      budgetClass: "detail",
    };
  },
  validate(data, actor, request, ctx) {
    const qualify = ctx?.mode === "qualify";
    const cls = request?.budgetClass;
    if (!CLASSES.includes(cls)) return false; // an unknown or missing class never validates
    const rows = (x) => Array.isArray(x) && x.every((r) => r && Number.isInteger(r.id));
    switch (cls) {
      case "search":
        return rows(data) && (!qualify || data.length >= 1);
      case "browse":
        return rows(data) && data.length >= 1;
      case "discover": {
        const ok = data && typeof data === "object" && !Array.isArray(data) &&
          data.anime && typeof data.anime === "object" && data.manga && typeof data.manga === "object";
        if (!ok) return false;
        return !qualify || (Object.keys(data.anime).length >= 1 && Object.keys(data.manga).length >= 1);
      }
      case "detail": {
        if (request.method === "GET") {
          return rows(data) && data.length <= 1 && (!qualify || data.length === 1);
        }
        // get_media_ladder: an object or an array; qualify mode needs something in it
        if (data === null || typeof data !== "object") return false;
        return !qualify || (Array.isArray(data) ? data.length >= 1 : Object.keys(data).length >= 1);
      }
      default:
        return false;
    }
  },
};
