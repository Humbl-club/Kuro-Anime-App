"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const W = require("./backend_workload");
const actor = {
  id: "a",
  email: "kuro-load-test-a@example.invalid",
  token: "fixture",
  librarySize: 25,
  writeEntry: { mediaId: 1, lifecycleId: "life", revision: 7, position: 2 },
};
const fixture = {
  origin: W.ORIGIN,
  runId: "kuro-load-test",
  accounts: [actor],
  media: { anime: [1], manga: [2] },
};
const config = {
  production: true,
  rps: 2,
  duration: 60,
  vus: 1,
  maxRequests: 120,
};
test("exact origin, explicit mode and bounded limits reject unsafe runs", () => {
  assert.doesNotThrow(() => W.validateConfig(config, fixture));
  for (
    const c of [
      { production: false },
      { rps: 51 },
      { duration: 601 },
      { vus: 101 },
      { maxRequests: 20001 },
      { rps: NaN },
      { transport: "unreviewed" },
    ]
  ) assert.throws(() => W.validateConfig({ ...config, ...c }, fixture));
  assert.throws(() =>
    W.validateConfig(config, { ...fixture, origin: W.ORIGIN + ".evil.invalid" })
  );
  assert.throws(() =>
    W.validateConfig(config, { ...fixture, accounts: [actor, actor] })
  );
  assert.throws(() =>
    W.validateConfig(config, {
      ...fixture,
      accounts: [{ ...actor, email: "customer@example.invalid" }],
    })
  );
});
test("nearest rank percentiles preserve tail values", () => {
  assert.equal(W.percentile([1, 2, 3, 100], .95), 100);
  assert.equal(W.percentile([], .95), null);
});
test("errors, lost arrivals and slow successful replies cannot pass", () => {
  const s = [{ kind: "browse", ms: 100, status: 200, ok: true }];
  assert.equal(W.summarize(s, 1, 1).pass, true);
  assert.equal(W.summarize(s, 2, 1).pass, false);
  assert.equal(
    W.summarize([{ kind: "browse", ms: 1, status: 503, ok: false }], 1, 1).pass,
    false,
  );
  assert.equal(
    W.summarize([{ kind: "browse", ms: 751, status: 200, ok: true }], 1, 1)
      .pass,
    false,
  );
});
test("workload represents bounded real RPCs; paid narration stays off", () => {
  for (const kind of Object.keys(W.WEIGHTS)) {
    const r = W.requestFor(kind, actor, fixture, 1, () => .1);
    assert.match(r.path, /^\/(rest|functions)\/v1\//);
    assert.doesNotMatch(r.path, /bulk-import|release-intake|apply_remove/);
  }
  assert.equal(
    W.requestFor("recommend", actor, fixture, 1).body.narrate,
    false,
  );
  assert.equal(Object.values(W.WEIGHTS).reduce((a, b) => a + b), 100);
});
test("every medium can reach every mood and odd-index large members can load their club", () => {
  const moods = new Set();
  for (let sequence = 0; sequence < 900; sequence++) {
    const r = W.requestFor("mood", actor, fixture, sequence, () => .1);
    moods.add(r.body.p_media_type + ":" + r.body.p_mood);
  }
  assert.deepEqual([...moods].sort(), ["ANIME:cozy", "ANIME:intense", "ANIME:short",
    "MANGA:cozy", "MANGA:intense", "MANGA:short"]);
  const hundred = { ...fixture, accounts: Array.from({ length: 100 }, (_, i) => ({
    ...actor, id: String(i), clubId: "fixture-club", librarySize: i === 19 ? 2000 : 25,
  })) };
  const member = hundred.accounts[19];
  const paths = new Set(Array.from({ length: 10 }, (_, round) =>
    W.requestFor("clubs", member, hundred, 19 + 100 * round, () => .1).path));
  assert.deepEqual([...paths].sort(), ["/rest/v1/rpc/fetch_club_bundle_loading",
    "/rest/v1/rpc/fetch_my_clubs_loading"]);
});
test("HTTP200 empty failures do not masquerade as working personalized pages", () => {
  const home = W.requestFor("home", actor, fixture, 1);
  assert.equal(
    W.validateResponse("home", { active: [], home_revision: 1 }, actor, home),
    false,
  );
  assert.equal(
    W.validateResponse(
      "home",
      { active: [{}], home_revision: 1, club: { state: "error" } },
      actor,
      home,
    ),
    false,
  );
  assert.equal(
    W.validateResponse(
      "home",
      { active: [{}], home_revision: 1, club: { state: "none" } },
      actor,
      home,
    ),
    true,
  );
  assert.equal(W.validateResponse("browse", [], actor, {}), false);
  assert.equal(
    W.validateResponse("detail", { header: null }, actor, {}),
    false,
  );
});
test("tracking must be applied with matching receipt; conflicts do not count as success", () => {
  const a = structuredClone(actor), r = W.requestFor("progress", a, fixture, 1);
  assert.equal(
    W.validateResponse(
      "progress",
      {
        items: [{
          mutation_id: r.mutationId,
          outcome: "conflict",
          server_revision: 8,
        }],
      },
      a,
      r,
    ),
    false,
  );
  assert.equal(
    W.validateResponse(
      "progress",
      {
        items: [{
          mutation_id: r.mutationId,
          outcome: "applied",
          server_revision: 8,
        }],
      },
      a,
      r,
    ),
    true,
  );
  assert.equal(a.writeEntry.revision, 8);
  assert.equal(a.writeEntry.position, 3);
});
test("parser response belongs to the caller; deterministic recommendations contain content", () => {
  assert.equal(
    W.validateResponse(
      "parse",
      { success: true, userId: "outsider", items: [{}] },
      actor,
      {},
    ),
    false,
  );
  assert.equal(
    W.validateResponse(
      "recommend",
      { success: true, narrated: true, items: [{}] },
      actor,
      {},
    ),
    false,
  );
  assert.equal(
    W.validateResponse(
      "recommend",
      { success: true, narrated: false, items: [{}] },
      actor,
      {},
    ),
    true,
  );
});
// ---- F3.1: profile registry and the separate absolute-rate lane ----
const fs = require("node:fs"), os = require("node:os"), path = require("node:path");
const crypto = require("node:crypto");
// Digest of the first 1,000 chooseKind draws (LCG seed 20261109), computed on the
// unmodified module before F3 touched it.
const FROZEN_MIX_DIGEST =
  "21495cda42ce640e9055984d9ba072128756ec210004b71a51cc98af440e209b";
// Writes one temp profile file per entry. A field value of { $fn: "<source>" }
// is emitted as code; everything else as JSON.
function profileDir(t, profiles) {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), "kuro-profiles-"));
  t.after(() => fs.rmSync(d, { recursive: true, force: true }));
  for (const [name, raw] of Object.entries(profiles)) {
    const fields = {
      name,
      // Accepts any non-empty array; in qualify mode an empty answer is rejected (F3.1c).
      validate: { $fn: "(d, a, r, ctx) => ctx?.mode !== 'qualify' || (Array.isArray(d) && d.length > 0)" },
      emptyExamples: [[]],
      request: { $fn: "() => ({ path: '/rest/v1/rpc/x' })" },
      ...raw,
    };
    const file = fields.$file ?? name;
    delete fields.$file;
    const src = Object.entries(fields).map(([k, v]) =>
      `${JSON.stringify(k)}: ${v && typeof v === "object" && "$fn" in v ? v.$fn : JSON.stringify(v)}`
    ).join(",\n");
    fs.writeFileSync(path.join(d, file + ".js"), `module.exports = {\n${src}\n};\n`);
  }
  return d;
}
test("predeclared mix is unchanged", () => {
  let seed = 20261109;
  const random = () => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return seed / 4294967296;
  };
  const kinds = Array.from({ length: 1000 }, () => W.chooseKind(random));
  assert.equal(
    crypto.createHash("sha256").update(kinds.join(",")).digest("hex"),
    FROZEN_MIX_DIGEST,
  );
  assert.deepEqual(W.WEIGHTS, { home: 20, browse: 20, search: 15, detail: 20,
    mood: 8, clubs: 5, discover: 5, progress: 5, parse: 1, recommend: 1 });
  assert.deepEqual(W.LIMITS, { home: 1200, browse: 750, search: 750, detail: 1200,
    mood: 1500, clubs: 750, discover: 1500, progress: 750, parse: 2500, recommend: 2500 });
  const s = W.summarize([{ kind: "browse", ms: 1, status: 200, ok: true }], 1, 1);
  assert.deepEqual(Object.keys(s.endpoints), ["browse"]);
});
test("selection is empty without opt-in", () => {
  assert.deepEqual(W.selectProfiles({}), { profiles: [], totalRate: 0, limits: {} });
});
test("profiles keep their absolute rate", (t) => {
  const P = W.loadProfiles(profileDir(t, {
    "x-test": { budgetClass: "browse", ratePerSecond: 0.5 },
    "z-test": { budgetClass: "detail", ratePerSecond: 2 },
  }));
  const sel = W.selectProfiles({ names: ["x-test", "z-test"] }, P);
  const sched = W.profileSchedule(sel, 10);
  const x = sched.filter((a) => a.name === "x-test"), z = sched.filter((a) => a.name === "z-test");
  assert.deepEqual(x.map((a) => a.atMs), [0, 2000, 4000, 6000, 8000]);
  assert.equal(z.length, 20);
  assert.ok(z.every((a, i) => a.atMs === i * 500));
  assert.equal(sel.totalRate, 2.5);
  assert.equal(sel.limits["x-test"], 750);
  assert.equal(sel.limits["z-test"], 1200);
  assert.deepEqual(sched.slice(0, 2).map((a) => a.name), ["x-test", "z-test"]);
  const more = W.selectProfiles({ names: ["x-test"], rates: { "x-test": 1 } }, P);
  assert.equal(W.profileSchedule(more, 10).length, 10);
  assert.equal(W.selectProfiles({ names: ["all"] }, P).profiles.length, 2);
  assert.throws(() => W.selectProfiles({ names: ["nope"] }, P));
  assert.throws(() => W.selectProfiles({ names: ["x-test"], rates: { "x-test": 11 } }, P));
  assert.equal(Object.keys(W.WEIGHTS).length, 10);
});
test("invalid profiles are refused", (t) => {
  const ok = { budgetClass: "browse", ratePerSecond: 1 };
  const bad = [
    { ...ok, name: "other" },
    { ...ok, budgetClass: "fast" },
    { ...ok, ratePerSecond: 0 },
    { ...ok, ratePerSecond: -1 },
    { ...ok, ratePerSecond: 10.5 },
    { ...ok, ratePerSecond: null },
    { ...ok, ratePerSecond: "1" },
    { ...ok, validate: 5 },
    { ...ok, weight: 4 },
  ];
  for (const fields of bad) {
    assert.throws(
      () => W.loadProfiles(profileDir(t, { "bad-test": fields })),
      fields.weight ? /ratePerSecond/ : /./,
      JSON.stringify(fields),
    );
  }
  // JSON cannot carry NaN, so emit it as code.
  assert.throws(() => W.loadProfiles(profileDir(t, {
    "nan-test": { ...ok, ratePerSecond: { $fn: "NaN" } },
  })));
  const ten = W.loadProfiles(profileDir(t, { "ten-test": { ...ok, ratePerSecond: 10 } }));
  assert.equal(ten["ten-test"].ratePerSecond, 10);
  assert.ok(Object.isFrozen(ten));
});
test("missing profiles directory yields no profiles", () => {
  assert.deepEqual(W.loadProfiles("/nonexistent"), {});
});
// ---- F3.1b: request options ----
test("profile request options", (t) => {
  const P = W.loadProfiles(profileDir(t, {
    "y-test": {
      budgetClasses: ["browse", "detail"],
      ratePerSecond: 1,
      request: { $fn: "(a, f, seq, r, core) => ({ method: 'GET', anonymous: true, budgetClass: seq % 2 ? 'detail' : 'browse', path: '/rest/v1/anime?id=eq.1', coreOk: core.requestFor })" },
    },
    "w-test": {
      operations: { a: { budgetClass: "progress" }, b: { budgetClass: "progress" } },
      ratePerSecond: 1,
    },
  }));
  const y = W.selectProfiles({ names: ["y-test"] }, P).limits;
  assert.equal(y["y-test:browse"], 750);
  assert.equal(y["y-test:detail"], 1200);
  assert.equal(Object.hasOwn(y, "y-test"), false);
  const core = { requestFor: W.requestFor };
  assert.equal(P["y-test"].request(actor, fixture, 0, Math.random, core).coreOk, W.requestFor);
  const w = W.selectProfiles({ names: ["w-test"] }, P).limits;
  assert.deepEqual(w, { "w-test:a": 750, "w-test:b": 750 });
  const ok = { ratePerSecond: 1 };
  const bad = [
    { ...ok, budgetClasses: ["fast"] },
    { ...ok, budgetClasses: ["browse"], operations: { a: { budgetClass: "browse" } } },
    { ...ok, operations: { a: { budgetClass: "browse", share: 0.5 }, b: { budgetClass: "browse", share: 0.4 } } },
    { ...ok, operations: { a: { budgetClass: "fast" } } },
    { ...ok },
  ];
  for (const fields of bad) {
    assert.throws(() => W.loadProfiles(profileDir(t, { "bad-test": fields })), /./, JSON.stringify(fields));
  }
});
test("summarize reports payload groups when samples carry one", () => {
  const s = W.summarize([
    { kind: "browse", ms: 10, status: 200, ok: true, payload: "typical" },
    { kind: "browse", ms: 20, status: 200, ok: true, payload: "maximum" },
  ], 2, 1);
  assert.deepEqual(Object.keys(s.endpoints.browse.byPayload).sort(), ["maximum", "typical"]);
  assert.equal(s.endpoints.browse.byPayload.maximum.requests, 1);
  assert.equal(W.summarize([{ kind: "browse", ms: 1, status: 200, ok: true }], 1, 1).endpoints.browse.byPayload, undefined);
});
// ---- F3.1c: qualification ----
function qSamples(parts, { ms = 50, payload } = {}) {
  // parts: [[librarySize, count, ok?]]
  return parts.flatMap(([librarySize, n, ok = true]) =>
    Array.from({ length: n }, () => ({
      kind: "q-test", ms, status: ok ? 200 : 500, ok, librarySize,
      ...(payload ? { payload } : {}),
    }))
  );
}
function qSelection(t, extra = {}) {
  const P = W.loadProfiles(profileDir(t, {
    "q-test": { budgetClass: "browse", ratePerSecond: 0.5, librarySizes: [25, 2000], ...extra },
  }));
  return W.selectProfiles({ names: ["q-test"] }, P);
}
test("qualification verdicts", (t) => {
  const sel = qSelection(t);
  const verdict = (samples) => W.qualifyVerdicts(samples, sel);
  assert.equal(verdict(qSamples([[25, 70], [2000, 29]])).profiles["q-test"].endpoints["q-test"].verdict, "insufficient");
  assert.equal(verdict(qSamples([[25, 71], [2000, 29]])).profiles["q-test"].endpoints["q-test"].verdict, "insufficient");
  const pass = verdict(qSamples([[25, 70], [2000, 30]]));
  assert.equal(pass.profiles["q-test"].endpoints["q-test"].verdict, "pass");
  assert.equal(pass.verdict, "pass");
  assert.equal(pass.profiles["q-test"].endpoints["q-test"].bySubgroup[2000].completions, 30);
  const failed = verdict(qSamples([[25, 100], [2000, 99], [2000, 1, false]]));
  assert.equal(failed.verdict, "fail");
  assert.equal(verdict(qSamples([[25, 100], [2000, 100]], { ms: 751 })).verdict, "fail");
  // A slow 2000 subgroup fails even though the overall p95 passes.
  const slowSub = [...qSamples([[25, 600]]), ...qSamples([[2000, 30]], { ms: 900 })];
  assert.equal(verdict(slowSub).verdict, "fail");
  // Zero samples for a declared endpoint is insufficient, never pass.
  assert.equal(verdict([]).verdict, "insufficient");
  const withMax = qSelection(t, { payloads: ["typical", "maximum"] });
  const payloadSamples = [
    ...qSamples([[25, 100], [2000, 90]], { payload: "typical" }),
    ...qSamples([[2000, 10]], { payload: "maximum" }),
  ];
  const pv = W.qualifyVerdicts(payloadSamples, withMax);
  assert.equal(pv.profiles["q-test"].endpoints["q-test"].verdict, "insufficient");
  assert.equal(pv.profiles["q-test"].endpoints["q-test"].byPayload.maximum.verdict, "insufficient");
  assert.notEqual(pv.verdict, "pass");
  assert.equal(W.exitCodeFor({ mode: "qualify", summary: { pass: true }, preflight: { passed: true }, lanes: { profiles: { verdict: "pass", samples: [] } } }), 0);
  assert.equal(W.exitCodeFor({ mode: "qualify", summary: { pass: true }, preflight: { passed: true }, lanes: { profiles: { verdict: "fail", samples: [] } } }), 1);
  assert.equal(W.exitCodeFor({ mode: "qualify", summary: { pass: true }, preflight: { passed: true }, lanes: { profiles: { verdict: "insufficient", samples: [] } } }), 3);
  assert.equal(W.exitCodeFor({ mode: "qualify", summary: { pass: true }, preflight: { passed: false }, lanes: { profiles: { verdict: "pass", samples: [] } } }), 1);
  assert.equal(W.exitCodeFor({ mode: "qualify", summary: { pass: true }, lanes: { profiles: { verdict: "pass", samples: [] } } }), 1);
  // insufficient never masks a failure
  assert.equal(W.exitCodeFor({ mode: "qualify", summary: { pass: false }, preflight: { passed: true }, lanes: { profiles: { verdict: "insufficient", samples: [] } } }), 1);
});
test("qualify preflight refuses thin or empty setups", (t) => {
  const accounts = (sizes) => sizes.map((librarySize, i) => ({ id: String(i), librarySize }));
  const cfg = { duration: 600, vus: 2, rps: 20 };
  const fx = (sizes) => ({ accounts: accounts(sizes) });
  const thin = W.loadProfiles(profileDir(t, { "q-test": { budgetClass: "browse", ratePerSecond: 0.1, librarySizes: [25] } }));
  assert.throws(() => W.qualifyPreflight(cfg, fx([25, 2000]), W.selectProfiles({ names: ["q-test"] }, thin)), /q-test: expected 60 completions < 100/);
  const big = W.loadProfiles(profileDir(t, { "q-test": { budgetClass: "browse", ratePerSecond: 0.5, librarySizes: [2000] } }));
  assert.throws(() => W.qualifyPreflight(cfg, fx([25, 25]), W.selectProfiles({ names: ["q-test"] }, big)), /2000/);
  const req = W.loadProfiles(profileDir(t, { "q-test": {
    budgetClass: "browse", ratePerSecond: 0.5, librarySizes: [25, 2000],
    requires: { $fn: "() => 'no seeded lists'" },
  } }));
  assert.throws(() => W.qualifyPreflight(cfg, fx([25, 2000]), W.selectProfiles({ names: ["q-test"] }, req)), /Fixture not populated for q-test: no seeded lists/);
  const good = W.loadProfiles(profileDir(t, { "q-test": { budgetClass: "browse", ratePerSecond: 0.5, librarySizes: [25, 2000] } }));
  const r = W.qualifyPreflight(cfg, fx([25, 2000]), W.selectProfiles({ names: ["q-test"] }, good));
  assert.equal(r.passed, true);
  assert.equal(r.expected["q-test"].completions, 300);
  assert.deepEqual(r.expected["q-test"].bySubgroup, { 25: 150, 2000: 150 });
  // Operations split the arrivals by share; a thin operation is named.
  const ops = W.loadProfiles(profileDir(t, { "q-test": {
    operations: { a: { budgetClass: "browse", share: 0.9 }, b: { budgetClass: "browse", share: 0.1 } },
    ratePerSecond: 0.5, librarySizes: [25],
  } }));
  assert.throws(() => W.qualifyPreflight(cfg, fx([25]), W.selectProfiles({ names: ["q-test"] }, ops)), /q-test:b: expected 30 completions < 100/);
});
test("qualify mode rejects empty answers", (t) => {
  const ok = { budgetClass: "browse", ratePerSecond: 1 };
  assert.throws(() => W.loadProfiles(profileDir(t, { "bad-test": { ...ok, validate: { $fn: "() => true" } } })), /accepts an empty answer in qualify mode/);
  assert.throws(() => W.loadProfiles(profileDir(t, { "bad-test": { ...ok, emptyExamples: [] } })), /emptyExamples/);
  assert.throws(() => W.loadProfiles(profileDir(t, { "bad-test": { ...ok, writes: true } })), /seed and cleanupCheck/);
  assert.throws(() => W.loadProfiles(profileDir(t, { "bad-test": { ...ok, seed: { $fn: "async () => ({})" } } })), /cleanupCheck/);
  const good = W.loadProfiles(profileDir(t, { "good-test": {
    ...ok,
    validate: { $fn: "(d, a, r, ctx) => Array.isArray(d) && (ctx.mode === 'wiring' || d.length > 0)" },
  } }));
  assert.equal(good["good-test"].validate([], actor, {}, { mode: "wiring" }), true);
  assert.equal(good["good-test"].validate([], actor, {}, { mode: "qualify" }), false);
  // a throwing validate counts as rejection
  assert.doesNotThrow(() => W.loadProfiles(profileDir(t, { "thrower-test": { ...ok, validate: { $fn: "() => { throw new Error('x'); }" } } })));
});
test("combined workload names every profile with an explicit rate", () => {
  const w = W.loadWorkload("tracker-gaps-combined");
  assert.equal(w.baseRps, 20);
  assert.deepEqual(Object.keys(w.profiles).sort(), Object.keys(W.TRACKER_GAP_PROFILES).sort());
  for (const r of Object.values(w.profiles)) assert.ok(Number.isFinite(r) && r > 0 && r <= 10);
  assert.ok(20 + Object.values(w.profiles).reduce((a, b) => a + b, 0) <= 50);
  assert.throws(() => W.loadWorkload("nope-workload"));
  assert.throws(() => W.loadWorkload("../backend_workload"));
});
test("config bounds cover both lanes", (t) => {
  const P = W.loadProfiles(profileDir(t, { "x-test": { budgetClass: "browse", ratePerSecond: 6 } }));
  const sel = W.selectProfiles({ names: ["x-test"] }, P);
  assert.throws(() => W.validateConfig({ ...config, rps: 45 }, fixture, sel), /Invalid bounded rps/);
  assert.doesNotThrow(() => W.validateConfig({ ...config, rps: 20 }, fixture, sel));
  assert.throws(() => W.validateConfig({ ...config, only: "x-test" }, fixture, sel));
});
