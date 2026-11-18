"use strict";
const { randomUUID } = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
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
const EMPTY_SELECTION = Object.freeze({
  profiles: Object.freeze([]),
  totalRate: 0,
  limits: Object.freeze({}),
});
function validateConfig(c, fixture, selection = EMPTY_SELECTION) {
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
  if (c.rps + selection.totalRate > 50) throw new Error("Invalid bounded rps");
  if (
    !Number.isInteger(c.vus) || !Number.isInteger(c.maxRequests) ||
    (c.only && !Object.hasOwn(WEIGHTS, c.only))
  ) throw new Error("Invalid VU, budget or operation");
  const profilePlanned = selection.profiles.reduce(
    (n, p) => n + Math.ceil(c.duration * p.ratePerSecond),
    0,
  );
  if (
    Math.min(Math.ceil(c.duration * c.rps), c.maxRequests) + profilePlanned >
      20000
  ) throw new Error("Invalid bounded maxRequests");
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
function summarize(samples, offered, seconds, limits = LIMITS) {
  const endpoints = {};
  for (const kind of Object.keys(limits)) {
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
      p95Target: limits[kind],
      statuses: Object.fromEntries(
        [...new Set(rows.map((x) => x.status))].map(
          (s) => [s, rows.filter((x) => x.status === s).length],
        ),
      ),
      pass: rows.length === success.length &&
        percentile(lat, .95) <= limits[kind],
    };
    if (rows.some((x) => x.payload)) {
      endpoints[kind].byPayload = {};
      for (const payload of [...new Set(rows.map((x) => x.payload).filter(Boolean))]) {
        const own = rows.filter((x) => x.payload === payload);
        endpoints[kind].byPayload[payload] = {
          requests: own.length,
          errors: own.filter((x) => !x.ok).length,
          p95: percentile(own.map((x) => x.ms), .95),
        };
      }
    }
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
const PROFILE_MAX_RATE = 10;
function checkProfile(profile, file) {
  const name = path.basename(file, ".js");
  const fail = (why) => {
    throw new Error(`profile ${name}: ${why}`);
  };
  if (!profile || typeof profile !== "object") fail("must export an object");
  if (profile.name !== name) fail("name must equal the file name");
  if (Object.hasOwn(profile, "weight")) {
    fail(
      "weight is retired: declare ratePerSecond (weight w = 0.2*w rps at the 20 rps base)",
    );
  }
  const declared = ["budgetClass", "budgetClasses", "operations"].filter((k) =>
    Object.hasOwn(profile, k)
  );
  if (declared.length !== 1) {
    fail("declare exactly one of budgetClass, budgetClasses, operations");
  }
  const known = (c) => Object.hasOwn(LIMITS, c);
  if (declared[0] === "budgetClass" && !known(profile.budgetClass)) {
    fail("budgetClass must be one of " + Object.keys(LIMITS).join(", "));
  }
  if (declared[0] === "budgetClasses") {
    const cs = profile.budgetClasses;
    if (!Array.isArray(cs) || !cs.length || !cs.every(known)) {
      fail("budgetClasses must be a non-empty list of " + Object.keys(LIMITS).join(", "));
    }
  }
  if (declared[0] === "operations") {
    const ops = Object.entries(profile.operations ?? {});
    if (!ops.length || !ops.every(([, o]) => o && known(o.budgetClass))) {
      fail("every operation needs a budgetClass from " + Object.keys(LIMITS).join(", "));
    }
    const shares = ops.map(([, o]) => o.share);
    if (shares.some((s) => s !== undefined)) {
      const sum = shares.reduce((n, s) => n + (s ?? NaN), 0);
      if (
        shares.some((s) => typeof s !== "number" || !(s > 0 && s <= 1)) ||
        Math.abs(sum - 1) > 1e-9
      ) fail("operation shares must each be in (0, 1] and sum to 1");
    }
  }
  const r = profile.ratePerSecond;
  if (
    typeof r !== "number" || !Number.isFinite(r) || r <= 0 ||
    r > PROFILE_MAX_RATE
  ) fail("ratePerSecond must be a finite number, 0 < r <= " + PROFILE_MAX_RATE);
  if (typeof profile.validate !== "function") fail("validate must be a function");
  if (typeof profile.request !== "function") fail("request must be a function");
}
// One file per profile under scripts/load/profiles. Never part of WEIGHTS/chooseKind.
function loadProfiles(dir = path.join(__dirname, "profiles")) {
  if (!fs.existsSync(dir)) return Object.freeze({});
  const out = {};
  for (const f of fs.readdirSync(dir).sort()) {
    if (!f.endsWith(".js") || f.endsWith(".test.js")) continue;
    const file = path.join(dir, f);
    const profile = require(file);
    checkProfile(profile, file);
    out[profile.name] = Object.freeze(profile);
  }
  return Object.freeze(out);
}
const TRACKER_GAP_PROFILES = loadProfiles();
function selectProfiles(spec = {}, profiles = TRACKER_GAP_PROFILES) {
  const rates = spec.rates ?? {};
  let names = spec.names ?? Object.keys(rates);
  if (names.includes("all")) names = Object.keys(profiles);
  const chosen = [], limits = {};
  let totalRate = 0;
  for (const name of [...new Set(names)]) {
    const profile = profiles[name];
    if (!profile) throw new Error("Unknown load profile " + name);
    const ratePerSecond = rates[name] ?? profile.ratePerSecond;
    if (
      typeof ratePerSecond !== "number" || !Number.isFinite(ratePerSecond) ||
      ratePerSecond <= 0 || ratePerSecond > PROFILE_MAX_RATE
    ) throw new Error("Invalid rate for profile " + name);
    chosen.push({ name, ratePerSecond, profile });
    if (profile.budgetClasses) {
      for (const c of profile.budgetClasses) limits[`${name}:${c}`] = LIMITS[c];
    } else if (profile.operations) {
      for (const [op, o] of Object.entries(profile.operations)) {
        limits[`${name}:${op}`] = LIMITS[o.budgetClass];
      }
    } else limits[name] = LIMITS[profile.budgetClass];
    totalRate += ratePerSecond;
  }
  if (!chosen.length) return EMPTY_SELECTION;
  return Object.freeze({
    profiles: Object.freeze(chosen),
    totalRate,
    limits: Object.freeze(limits),
  });
}
// Profile p's i-th arrival is at i * 1000 / rate, independent of the base --rps.
function profileSchedule(selection, durationSeconds) {
  const out = [];
  for (const p of selection.profiles) {
    const n = Math.ceil(durationSeconds * p.ratePerSecond);
    for (let seq = 0; seq < n; seq++) {
      out.push({ atMs: seq * 1000 / p.ratePerSecond, name: p.name, seq });
    }
  }
  return out.sort((a, b) => a.atMs - b.atMs || (a.name < b.name ? -1 : 1));
}
// 0 pass; 1 fail. (Qualification adds 3 for insufficient.)
function exitCodeFor(report) {
  const profileSamples = report.lanes?.profiles?.samples ?? [];
  if (!report.summary?.pass || profileSamples.some((x) => !x.ok)) return 1;
  return 0;
}
module.exports = {
  loadProfiles,
  TRACKER_GAP_PROFILES,
  selectProfiles,
  profileSchedule,
  exitCodeFor,
  EMPTY_SELECTION,
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
