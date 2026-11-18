"use strict";
const { randomUUID } = require("node:crypto");
const ORIGIN = "https://bkdifromsqxkndnllmdj.supabase.co";
const WEIGHTS = {
  home: 20,
  browse: 20,
  search: 15,
  detail: 20,
  mood: 8,
  clubs: 5,
  discover: 5,
  progress: 5,
  parse: 1,
  recommend: 1,
};
const LIMITS = {
  home: 1200,
  browse: 750,
  search: 750,
  detail: 1200,
  mood: 1500,
  clubs: 750,
  discover: 1500,
  progress: 750,
  parse: 2500,
  recommend: 2500,
};
function validateConfig(c, fixture) {
  if (
    c.production !== true || fixture.origin !== ORIGIN ||
    !fixture.runId?.startsWith("kuro-load-")
  ) {
    throw new Error(
      "Explicit production mode and exact disposable Kuro fixture required",
    );
  }
  for (
    const [key, max] of [["rps", 50], ["duration", 600], ["vus", 100], [
      "maxRequests",
      20000,
    ]]
  ) {
    if (
      !Number.isFinite(c[key]) || c[key] <= 0 || c[key] > max
    ) throw new Error(`Invalid bounded ${key}`);
  }
  if (
    !Array.isArray(fixture.accounts) || fixture.accounts.length < c.vus ||
    new Set(fixture.accounts.map((a) => a.id)).size !==
      fixture.accounts.length ||
    fixture.accounts.some((a) =>
      !a.token || !a.email?.startsWith(fixture.runId + "-")
    )
  ) throw new Error("Distinct disposable account identities required");
  if (
    !Number.isInteger(c.vus) || !Number.isInteger(c.maxRequests) ||
    (c.only && !Object.hasOwn(WEIGHTS, c.only))
  ) throw new Error("Invalid VU, budget or operation");
  if (c.transport && !["node", "curl"].includes(c.transport)) {
    throw new Error("Unsupported workload transport");
  }
  if (fixture.accounts.length > 100) {
    throw new Error("At most100 disposable accounts");
  }
}
function percentile(xs, p) {
  if (!xs.length) return null;
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.max(0, Math.ceil(p * s.length) - 1)];
}
function summarize(samples, offered, seconds) {
  const endpoints = {};
  for (const kind of Object.keys(WEIGHTS)) {
    const rows = samples.filter((x) => x.kind === kind);
    if (!rows.length) continue;
    const success = rows.filter((x) => x.ok);
    const lat = rows.map((x) => x.ms);
    endpoints[kind] = {
      requests: rows.length,
      success: success.length,
      errors: rows.length - success.length,
      p50: percentile(lat, .5),
      p95: percentile(lat, .95),
      p99: percentile(lat, .99),
      p95Target: LIMITS[kind],
      statuses: Object.fromEntries(
        [...new Set(rows.map((x) => x.status))].map(
          (s) => [s, rows.filter((x) => x.status === s).length],
        ),
      ),
      pass: rows.length === success.length &&
        percentile(lat, .95) <= LIMITS[kind],
    };
  }
  const ok = samples.filter((x) => x.ok).length;
  return {
    offered,
    completed: samples.length,
    dropped: offered - samples.length,
    errors: samples.length - ok,
    errorRate: samples.length ? (samples.length - ok) / samples.length : 1,
    achievedRps: samples.length / seconds,
    successRps: ok / seconds,
    p95: percentile(samples.map((x) => x.ms), .95),
    endpoints,
    pass: samples.length === offered && ok === samples.length &&
      Object.values(endpoints).every((x) => x.pass),
  };
}
function chooseKind(random) {
  let n = random() * 100;
  for (const [k, w] of Object.entries(WEIGHTS)) {
    n -= w;
    if (n < 0) return k;
  }
  return "home";
}
function requestFor(kind, actor, fixture, seq, random = Math.random) {
  const medium = seq % 3 === 0 ? "manga" : "anime",
    isAnime = medium === "anime";
  const ids = fixture.media[medium];
  const id =
    ids[Math.min(ids.length - 1, Math.floor(random() ** 2 * ids.length))];
  const rpc = (name, body) => ({ path: "/rest/v1/rpc/" + name, body });
  switch (kind) {
    case "home":
      return rpc("home_bundle_v1", {
        p_medium: medium,
        p_window_days: 7,
        p_active_limit: 12,
        p_event_limit: 20,
      });
    case "browse":
      return rpc("browse_" + medium + "_page", {
        p_limit: 30,
        p_sort: ["popular", "trending", "topRated", "newlyAdded"][seq % 4],
        ...(seq % 5 === 0
          ? { p_genre: ["Action", "Drama", "Comedy"][seq % 3] }
          : {}),
      });
    case "search":
      return rpc("search_" + medium + "_page", {
        p_query: [
          "Naruto",
          "One",
          "Frieren",
          "Berserk",
          "Attack",
          "Dragon",
          "Haikyuu",
          "Fate",
          "Love",
          "Solo",
        ][seq % 10],
        p_limit: 30,
      });
    case "detail":
      return rpc("series_detail_bundle_v1", {
        p_medium: medium,
        p_media_id: id,
      });
    case "mood":
      return rpc("discover_mood_v1", {
        p_mood: ["short", "cozy", "intense"][Math.floor(seq / 3) % 3],
        p_media_type: medium.toUpperCase(),
        p_limit: 24,
        p_offset: seq % 5 === 0 ? 24 : 0,
      });
    case "clubs":
      return actor.clubId && Math.floor(seq / fixture.accounts.length) % 2 === 0
        ? rpc("fetch_club_bundle_loading", { p_club_id: actor.clubId })
        : rpc("fetch_my_clubs_loading", {});
    case "discover":
      return rpc("discover_bundle", { p_limit: 30, p_hours: 24 });
    case "progress": {
      if (!actor.writeEntry) {
        return requestFor("home", actor, fixture, seq, random);
      }
      const e = actor.writeEntry;
      const mutationId = randomUUID();
      return {
        ...rpc("apply_progress_mutations_v1", {
          p_mutations: [{
            mutation_id: mutationId,
            medium: "anime",
            media_id: e.mediaId,
            lifecycle_id: e.lifecycleId,
            base_revision: e.revision,
            position: (e.position + 1) % 5,
          }],
        }),
        mutationId,
      };
    }
    case "parse":
      return {
        path: "/functions/v1/concierge-parse",
        body: {
          text: [
            "Frieren completed",
            "Naruto episode 5",
            "Berserk chapter 20",
          ][seq % 3],
          scope: "both",
        },
      };
    case "recommend":
      return {
        path: "/functions/v1/concierge-recommend",
        body: {
          text: [
            "something cozy",
            "premium action anime",
            "sad but hopeful",
          ][seq % 3],
          scope: "anime",
          limit: 8,
          narrate: false,
        },
      };
    default:
      throw new Error("Unknown workload");
  }
}
function validateResponse(kind, data, actor, request) {
  if (!data || typeof data !== "object") return false;
  if (request.path?.endsWith("/home_bundle_v1")) {
    return Array.isArray(data.active) &&
      (!actor.librarySize || data.active.length > 0) &&
      typeof data.home_revision === "number" && data.club?.state !== "error";
  }
  if (["browse", "search", "mood"].includes(kind)) {
    return Array.isArray(data) && data.every((x) => Number.isInteger(x.id)) &&
      (kind !== "browse" || data.length > 0);
  }
  if (kind === "detail") {
    return !!data.header?.title && data.media_id > 0 &&
      Array.isArray(data.units);
  }
  if (kind === "discover") {
    return typeof data.anime === "object" && typeof data.manga === "object";
  }
  if (kind === "clubs") return !data.error;
  if (kind === "progress") {
    const row = data.items?.[0];
    if (
      row?.mutation_id !== request.mutationId || row.outcome !== "applied" ||
      !Number.isInteger(row.server_revision)
    ) return false;
    actor.writeEntry.revision = row.server_revision;
    actor.writeEntry.position = request.body.p_mutations[0].position;
    return true;
  }
  if (kind === "parse") {
    return data.success === true && data.userId === actor.id &&
      Array.isArray(data.items) && data.items.length > 0;
  }
  if (kind === "recommend") {
    return data.success === true && data.narrated === false &&
      data.items?.length > 0;
  }
  return false;
}
module.exports = {
  ORIGIN,
  WEIGHTS,
  LIMITS,
  validateConfig,
  percentile,
  summarize,
  chooseKind,
  requestFor,
  validateResponse,
};
