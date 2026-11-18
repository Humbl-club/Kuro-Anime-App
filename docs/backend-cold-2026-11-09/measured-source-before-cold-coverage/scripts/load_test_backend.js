"use strict";
// Fixed-rate, bounded, authenticated production workload. Credentials stay in a private fixture.
const fs = require("node:fs");
const { performance, monitorEventLoopDelay } = require("node:perf_hooks");
const { setTimeout: sleep } = require("node:timers/promises");
const W = require("./load/backend_workload");
async function run(config, fixture) {
  W.validateConfig(config, fixture);
  const actors = fixture.accounts.slice(0, config.vus);
  const busy = new Set(), samples = [], inflight = new Set(), seen = new Set();
  let seed = config.seed || 20261109;
  const random = () => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return seed / 4294967296;
  };
  const loop = monitorEventLoopDelay({ resolution: 20 });
  loop.enable();
  const cpu = process.cpuUsage(), wall = performance.now();
  let offered = 0, droppedBusy = 0, stopReason = null, maxInFlight = 0;
  const startedAt = new Date().toISOString();
  const windows = [];
  async function call(actor, kind, seq, planned) {
    busy.add(actor);
    seen.add(actor.id);
    if (kind === "progress" && !actor.writeEntry) kind = "home";
    const req = W.requestFor(kind, actor, fixture, seq, random);
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
      ok = res.ok && W.validateResponse(kind, data, actor, req);
      if (!ok) {
        error = res.ok
          ? "semantic_contract"
          : String(data.code || data.error || data.error_code || "http_error")
            .slice(0, 80);
      }
    } catch (e) {
      error = e.name === "TimeoutError" ? "timeout" : "transport_or_json";
    } finally {
      busy.delete(actor);
    }
    const sample = {
      kind,
      sequence: seq,
      medium: req.body.p_medium || req.body.p_media_type || null,
      variant: req.body.p_sort || req.body.p_mood || req.body.p_query || null,
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
    samples.push(sample);
    const recent = samples.slice(-50);
    if (
      recent.length >= 20 &&
      (recent.filter((x) => !x.ok).length >= 3 ||
        recent.filter((x) => x.ms > 5000).length >= 5)
    ) stopReason = "rolling error/latency safety stop";
  }
  const count = Math.min(
    Math.ceil(config.duration * config.rps),
    config.maxRequests,
  );
  for (let i = 0; i < count; i++) {
    const planned = wall + i * 1000 / config.rps;
    if (performance.now() < planned) await sleep(planned - performance.now());
    if (config.stopFile && fs.existsSync(config.stopFile)) {
      stopReason = "external database safety stop";
    }
    if (stopReason) break;
    offered++;
    const actor = actors[i % actors.length];
    if (busy.has(actor) || inflight.size >= Math.min(100, config.vus)) {
      droppedBusy++;
      continue;
    }
    const kind = config.only || W.chooseKind(random);
    const p = call(actor, kind, i, planned);
    inflight.add(p);
    maxInFlight = Math.max(maxInFlight, inflight.size);
    p.finally(() => inflight.delete(p));
    if (i && i % Math.max(1, Math.floor(config.rps * 10)) === 0) {
      const x = W.summarize(
        samples,
        offered,
        (performance.now() - wall) / 1000,
      );
      windows.push({
        atSeconds: Math.round((performance.now() - wall) / 1000),
        completed: x.completed,
        errors: x.errors,
        p95: x.p95,
        inflight: inflight.size,
      });
      console.log(JSON.stringify(windows.at(-1)));
    }
  }
  await Promise.all(inflight);
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
  const report = {
    schemaVersion: 1,
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
    process.exitCode = r.summary.pass ? 0 : 1;
  }).catch((e) => {
    console.error(e.message);
    process.exitCode = 1;
  });
}
module.exports = { run };
