"use strict";
// Offline acceptance only. No requests, credentials, warmup or changed workload limits.
const W = require("./backend_workload");
const LIBRARIES = [0, 25, 100, 2000];
const MEDIA_ROUTES = ["home", "browse", "search", "detail", "mood"];
const EXPECTED_ROUTES = [
  ...MEDIA_ROUTES.filter((k) => k !== "mood")
    .flatMap((k) => [k + ":anime", k + ":manga"]),
  ...["anime", "manga"].flatMap((m) => ["short", "cozy", "intense"]
    .map((v) => "mood:" + m + ":" + v)),
  "clubs:list", "clubs:bundle", "discover", "progress:anime", "parse", "recommend",
];
function routeFor(sample, actors) {
  const derived = sample.sequence % 3 === 0 ? "manga" : "anime";
  if (MEDIA_ROUTES.includes(sample.kind)) {
    if (sample.medium && sample.medium.toLowerCase() !== derived) {
      throw new Error("Recorded medium conflicts with frozen request builder");
    }
    if (sample.kind === "mood") {
      if (!["short", "cozy", "intense"].includes(sample.variant)) {
        throw new Error("Unknown measured mood variant");
      }
      return "mood:" + derived + ":" + sample.variant;
    }
    return sample.kind + ":" + derived;
  }
  if (sample.kind === "progress") return "progress:anime";
  if (sample.kind === "clubs") {
    const actor = actors[sample.sequence % 100];
    return actor.clubId && Math.floor(sample.sequence / actors.length) % 2 === 0
      ? "clubs:bundle" : "clubs:list";
  }
  return sample.kind;
}
function cells(samples, expected, keyFor, firstOnly = false) {
  return expected.map((key) => {
    const rows = samples.filter((s) => keyFor(s) === key)
      .sort((a, b) => a.sequence - b.sequence);
    const checked = firstOnly ? rows.slice(0, 1) : rows;
    const kind = key.split(/[:/]/)[0];
    const p95 = W.percentile(checked.map((s) => s.ms), .95);
    return {
      key, count: rows.length, checked: checked.length,
      firstSequence: rows[0]?.sequence ?? null,
      p95, limit: W.LIMITS[kind],
      pass: checked.length > 0 && checked.every((s) => s.ok) &&
        p95 <= W.LIMITS[kind],
    };
  });
}
function evaluateColdStage(report, actors) {
  if (report.config.rps !== 20 || report.config.duration !== 600 ||
    report.config.vus !== 100 || actors.length !== 100) {
    throw new Error("Cold stage requires the unchanged 100-user, 20-rps, 600-second profile");
  }
  if (new Set(actors.filter((a) => a.clubId).map((a) => a.librarySize)).size !== 4) {
    throw new Error("Club membership must cover all four declared library sizes");
  }
  const samples = report.samples;
  for (const s of samples) {
    if (!Number.isInteger(s.sequence) || s.sequence < 0 || s.sequence >= 12000 ||
      actors[s.sequence % 100].librarySize !== s.librarySize ||
      !Object.hasOwn(W.LIMITS, s.kind) || !Number.isFinite(s.startLagMs)) {
      throw new Error("Invalid measured actor/sequence/timing");
    }
  }
  const libraryKeys = Object.keys(W.WEIGHTS).flatMap((k) =>
    LIBRARIES.filter((l) => k !== "progress" || l !== 0).map((l) => k + "/" + l)
  );
  const libraryKey = (s) => s.kind + "/" + s.librarySize;
  const route = (s) => routeFor(s, actors);
  const firstMinute = samples.filter((s) => s.sequence < 1200);
  const crossKeys = EXPECTED_ROUTES.flatMap((route) =>
    LIBRARIES.filter((l) => route !== "progress:anime" || l !== 0)
      .map((l) => route + "/" + l));
  const crossKey = (s) => route(s) + "/" + s.librarySize;
  const fullLibrary = cells(samples, libraryKeys, libraryKey);
  const fullRoutes = cells(samples, EXPECTED_ROUTES, route);
  const onsetRoutes = cells(firstMinute, EXPECTED_ROUTES, route);
  const onsetLibrary = cells(firstMinute,
    [...new Set(firstMinute.map(libraryKey))].sort(), libraryKey);
  const firstLibraryCalls = cells(samples, libraryKeys, libraryKey, true);
  const firstRouteCalls = cells(samples, EXPECTED_ROUTES, route, true);
  const fullCross = cells(samples, crossKeys, crossKey);
  const firstCrossCalls = cells(samples, crossKeys, crossKey, true);
  const groups = [fullLibrary, fullRoutes, onsetRoutes, onsetLibrary,
    firstLibraryCalls, firstRouteCalls, fullCross, firstCrossCalls];
  const allFirstUsers = new Set(samples.filter((s) => s.sequence < 100)
    .map((s) => s.sequence)).size === 100;
  const actualStartMs = (s) => s.sequence * 50 + s.startLagMs;
  const pass = report.summary.pass && report.summary.offered === 12000 &&
    samples.length === 12000 && new Set(samples.map((s) => s.sequence)).size === 12000 &&
    report.summary.errors === 0 && report.summary.dropped === 0 && allFirstUsers &&
    firstMinute.length === 1200 && firstMinute.every((s) => actualStartMs(s) < 60000) &&
    samples.filter((s) => s.sequence < 100).every((s) => actualStartMs(s) < 5000) &&
    groups.every((xs) => xs.every((x) => x.pass));
  return {
    pass, all100UsersRepresentedInFirst100Starts: allFirstUsers,
    first60Seconds: { offered: 1200, completed: firstMinute.length, routes: onsetRoutes,
      observedLibrary: onsetLibrary,
      missingLibrary: libraryKeys.filter((key) => !onsetLibrary.some((x) => x.key === key)),
      boundary: "First1200 planned arrivals; their responses may complete after60seconds. Actual timing includes measured start lag.",
      actualStartsBy60Seconds: firstMinute.filter((s) => actualStartMs(s) <= 60000).length,
      completionsBy60Seconds: firstMinute.filter((s) => actualStartMs(s) + s.ms <= 60000).length,
      latestActualStartMs: Math.max(...firstMinute.map(actualStartMs)),
      latestCompletionMs: Math.max(...firstMinute.map((s) => actualStartMs(s) + s.ms)) },
    fullLibrary, fullRoutes, firstLibraryCalls, firstRouteCalls, fullCross, firstCrossCalls,
    missing: groups.flatMap((xs) => xs.filter((x) => !x.count).map((x) => x.key)),
    scope: "Cold-start sequence acceptance. Later first-use cells share earlier cache activity; they are not independently cold experiments. A separate owning-service receipt must verify restart, readiness-to-t0 gap, cron overlap and Edge boot state.",
  };
}
module.exports = { evaluateColdStage, routeFor, cells, EXPECTED_ROUTES };
