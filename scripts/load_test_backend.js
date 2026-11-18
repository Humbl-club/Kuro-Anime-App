"use strict";
// Fixed-rate, bounded, authenticated production workload. Credentials stay in a private fixture.
const fs = require("node:fs");
const { performance, monitorEventLoopDelay } = require("node:perf_hooks");
const { setTimeout: sleep } = require("node:timers/promises");
const W = require("./load/backend_workload");
// One deterministic LCG per lane, so a profile lane never shifts the base draw sequence.
function makeRandom(initial) {
  let seed = initial;
  return () => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return seed / 4294967296;
  };
}
async function run(config, fixture, { profiles = W.TRACKER_GAP_PROFILES } = {}) {
  const selection = W.selectProfiles({ names: config.trackerGaps ?? [] }, profiles);
  W.validateConfig(config, fixture, selection);
  const actors = fixture.accounts.slice(0, config.vus);
  const mode = "wiring";
  // Base lane state (identical to the pre-profile runner) and profile lane state.
  const newLane = (name, random) => ({
    name,
    random,
    busy: new Set(),
    samples: [],
    inflight: new Set(),
    offered: 0,
    droppedBusy: 0,
    maxInFlight: 0,
  });
  const base = newLane("base", makeRandom(config.seed || 20261109));
  const lane2 = newLane(
    "profiles",
    makeRandom(((config.seed || 20261109) ^ 0x9e3779b9) >>> 0),
  );
  const seen = new Set();
  const loop = monitorEventLoopDelay({ resolution: 20 });
  loop.enable();
  const cpu = process.cpuUsage(), wall = performance.now();
  let stopReason = null;
  const startedAt = new Date().toISOString();
  const windows = [];
  const core = {
    requestFor: W.requestFor,
    validateResponse: W.validateResponse,
    ORIGIN: W.ORIGIN,
    now: () => new Date(),
  };
  // Sends one request for `lane`; `kind` names the sample; `validate` judges a 2xx body.
  async function send(lane, actor, kind, req, seq, planned, validate) {
    lane.busy.add(actor);
    const t = performance.now();
    let status = 0, ok = false, error = null, bytes = 0;
    let upstreamMs = null, responseStartMs = null, protocol = null;
    try {
      const res = await fetch(W.ORIGIN + req.path, {
        method: "POST",
        headers: {
          apikey: fixture.anonKey,
          Authorization: "Bearer " + actor.token,
          "Content-Type": "application/json",
          "X-Kuro-Load-Run": fixture.runId,
        },
        body: JSON.stringify(req.body),
        signal: AbortSignal.timeout(8000),
      });
      responseStartMs = +(performance.now() - t).toFixed(2);
      const upstream = res.headers?.get?.("x-envoy-upstream-service-time");
      if (/^\d+(?:\.\d+)?$/.test(upstream || "")) upstreamMs = Number(upstream);
      const version = res.headers?.get?.("x-kuro-load-http-version");
      if (["1.0", "1.1", "2", "3"].includes(version)) protocol = version;
      status = res.status;
      const raw = await res.text();
      bytes = Buffer.byteLength(raw);
      const data = JSON.parse(raw);
      ok = res.ok && validate(data);
      if (!ok) {
        error = res.ok
          ? "semantic_contract"
          : String(data.code || data.error || data.error_code || "http_error")
            .slice(0, 80);
      }
    } catch (e) {
      error = e.name === "TimeoutError" ? "timeout" : "transport_or_json";
    } finally {
      lane.busy.delete(actor);
    }
    const sample = {
      kind,
      sequence: seq,
      medium: req.body?.p_medium || req.body?.p_media_type || null,
      variant: req.body?.p_sort || req.body?.p_mood || req.body?.p_query || null,
      ms: +(performance.now() - t).toFixed(2),
      status,
      ok,
      error,
      bytes,
      upstreamMs,
      responseStartMs,
      protocol,
      startLagMs: +(t - planned).toFixed(2),
      librarySize: actor.librarySize,
    };
    lane.samples.push(sample);
    // Each lane keeps its own rolling window; either lane's stop halts both.
    const recent = lane.samples.slice(-50);
    if (
      recent.length >= 20 &&
      (recent.filter((x) => !x.ok).length >= 3 ||
        recent.filter((x) => x.ms > 5000).length >= 5)
    ) stopReason ??= lane.name + ": rolling error/latency safety stop";
  }
  const baseCall = (actor, kind, seq, planned) => {
    seen.add(actor.id);
    if (kind === "progress" && !actor.writeEntry) kind = "home";
    const req = W.requestFor(kind, actor, fixture, seq, base.random);
    return send(
      base,
      actor,
      kind,
      req,
      seq,
      planned,
      (data) => W.validateResponse(kind, data, actor, req),
    );
  };
  const profileCall = (actor, entry, seq, planned) => {
    const req = entry.profile.request(actor, fixture, seq, lane2.random, core);
    return send(
      lane2,
      actor,
      entry.name,
      req,
      seq,
      planned,
      (data) => entry.profile.validate(data, actor, req, { mode }),
    );
  };
  const count = Math.min(
    Math.ceil(config.duration * config.rps),
    config.maxRequests,
  );
  const checkStop = () => {
    if (config.stopFile && fs.existsSync(config.stopFile)) {
      stopReason ??= "external database safety stop";
    }
    return stopReason;
  };
  const launch = (lane, p) => {
    lane.inflight.add(p);
    lane.maxInFlight = Math.max(lane.maxInFlight, lane.inflight.size);
    p.finally(() => lane.inflight.delete(p));
  };
  async function baseLane() {
    for (let i = 0; i < count; i++) {
      const planned = wall + i * 1000 / config.rps;
      if (performance.now() < planned) await sleep(planned - performance.now());
      if (checkStop()) break;
      base.offered++;
      const actor = actors[i % actors.length];
      if (base.busy.has(actor) || base.inflight.size >= Math.min(100, config.vus)) {
        base.droppedBusy++;
        continue;
      }
      const kind = config.only || W.chooseKind(base.random);
      launch(base, baseCall(actor, kind, i, planned));
      if (i && i % Math.max(1, Math.floor(config.rps * 10)) === 0) {
        const x = W.summarize(
          base.samples,
          base.offered,
          (performance.now() - wall) / 1000,
        );
        windows.push({
          atSeconds: Math.round((performance.now() - wall) / 1000),
          completed: x.completed,
          errors: x.errors,
          p95: x.p95,
          inflight: base.inflight.size,
        });
        console.log(JSON.stringify(windows.at(-1)));
      }
    }
  }
  // Actors for a profile: cycle its covered library-size subgroups, then round-robin inside.
  function actorFor(entry, n) {
    const wanted = entry.profile.librarySizes;
    const pool = actors.filter((a) => !wanted || wanted.includes(a.librarySize));
    const sizes = [...new Set(pool.map((a) => a.librarySize))].sort((a, b) => a - b);
    if (!sizes.length) return null;
    const group = pool.filter((a) => a.librarySize === sizes[n % sizes.length]);
    return group[Math.floor(n / sizes.length) % group.length];
  }
  async function profileLane() {
    const counters = {};
    for (const arrival of W.profileSchedule(selection, config.duration)) {
      const planned = wall + arrival.atMs;
      if (performance.now() < planned) await sleep(planned - performance.now());
      if (checkStop()) break;
      lane2.offered++;
      const entry = selection.profiles.find((p) => p.name === arrival.name);
      const n = counters[entry.name] = (counters[entry.name] ?? -1) + 1;
      const actor = actorFor(entry, n);
      if (
        !actor || lane2.busy.has(actor) ||
        lane2.inflight.size >= Math.min(100, config.vus)
      ) {
        lane2.droppedBusy++;
        continue;
      }
      launch(lane2, profileCall(actor, entry, arrival.seq, planned));
    }
  }
  await Promise.all([baseLane(), profileLane()]);
  await Promise.all([...base.inflight, ...lane2.inflight]);
  const { samples, offered, droppedBusy, maxInFlight } = base;
  loop.disable();
  const elapsed = (performance.now() - wall) / 1000,
    cpuUsed = process.cpuUsage(cpu);
  const byLibrarySize = Object.fromEntries(
    [...new Set(samples.map((x) => x.librarySize))].map((size) => {
      const rows = samples.filter((x) => x.librarySize === size);
      return [size, W.summarize(rows, rows.length, elapsed)];
    }),
  );
  const byMedium = Object.fromEntries(
    [...new Set(samples.map((x) => x.medium).filter(Boolean))].map((medium) => {
      const rows = samples.filter((x) => x.medium === medium);
      return [medium, W.summarize(rows, rows.length, elapsed)];
    }),
  );
  const profileBySize = Object.fromEntries(
    [...new Set(lane2.samples.map((x) => x.librarySize))].map((size) => {
      const rows = lane2.samples.filter((x) => x.librarySize === size);
      return [size, W.summarize(rows, rows.length, elapsed, selection.limits)];
    }),
  );
  const report = {
    schemaVersion: 2,
    mode,
    runKey: fixture.runId + "@" + startedAt,
    byLibrarySize,
    byMedium,
    runId: fixture.runId,
    startedAt,
    finishedAt: new Date().toISOString(),
    target: W.ORIGIN,
    config,
    elapsedSeconds: elapsed,
    distinctAccounts: seen.size,
    accountPool: actors.length,
    weights: W.WEIGHTS,
    summary: W.summarize(samples, offered, elapsed),
    stopReason,
    maxInFlight,
    droppedBusy,
    generator: {
      eventLoopP99Ms: loop.percentile(99) / 1e6,
      cpuUserMs: cpuUsed.user / 1000,
      cpuSystemMs: cpuUsed.system / 1000,
      maxStartLagMs: Math.max(0, ...samples.map((x) => x.startLagMs)),
      rssBytes: process.memoryUsage().rss,
    },
    windows,
    samples,
    ...(selection.profiles.length
      ? {
        lanes: {
          profiles: {
            selection: selection.profiles.map((p) => ({
              name: p.name,
              ratePerSecond: p.ratePerSecond,
            })),
            offered: lane2.offered,
            droppedBusy: lane2.droppedBusy,
            maxInFlight: lane2.maxInFlight,
            skippedSteps: {},
            summary: W.summarize(lane2.samples, lane2.offered, elapsed, selection.limits),
            byLibrarySize: profileBySize,
            samples: lane2.samples,
            verdict: "wiring",
          },
        },
      }
      : {}),
  };
  if (
    stopReason || seen.size < Math.min(count, config.vus) ||
    Object.values(byLibrarySize).some((x) => !x.pass) ||
    Object.values(byMedium).some((x) => !x.pass)
  ) report.summary.pass = false;
  return report;
}
if (require.main === module) {
  const args = Object.fromEntries(
    process.argv.slice(2).map((a) => {
      const [k, ...v] = a.replace(/^--/, "").split("=");
      return [k, v.length ? v.join("=") : true];
    }),
  );
  const config = {
    production: args.production === true,
    transport: args.transport || "node",
    rps: Number(args.rps || 2),
    duration: Number(args.duration || 60),
    vus: Number(args.vus || 100),
    maxRequests: Number(args["max-requests"] || 20000),
    seed: Number(args.seed || 20261109),
    ...(args["stop-file"] ? { stopFile: args["stop-file"] } : {}),
    ...(args.only ? { only: args.only } : {}),
    ...(typeof args["tracker-gaps"] === "string"
      ? { trackerGaps: args["tracker-gaps"].split(",").filter(Boolean) }
      : {}),
  };
  if (!args.fixture || !args.output) {
    throw new Error(
      "--fixture=<private path> and --output=<report path> required",
    );
  }
  const stat = fs.statSync(args.fixture);
  if ((stat.mode & 0o077) !== 0) {
    throw new Error("Private fixture must be mode0600");
  }
  const fixture = JSON.parse(fs.readFileSync(args.fixture, "utf8"));
  if (config.transport === "curl") {
    global.fetch = require("./load/backend_curl_fetch").makeCurlFetch();
  }
  run(config, fixture).then((r) => {
    fs.writeFileSync(args.fixture, JSON.stringify(fixture, null, 2) + "\n", {
      mode: 0o600,
    });
    fs.mkdirSync(require("node:path").dirname(args.output), {
      recursive: true,
    });
    fs.writeFileSync(args.output, JSON.stringify(r, null, 2) + "\n");
    console.log(
      JSON.stringify({
        output: args.output,
        summary: r.summary,
        stopReason: r.stopReason,
        distinctAccounts: r.distinctAccounts,
        generator: r.generator,
      }),
    );
    process.exitCode = W.exitCodeFor(r);
  }).catch((e) => {
    console.error(e.message);
    process.exitCode = 1;
  });
}
module.exports = { run };
