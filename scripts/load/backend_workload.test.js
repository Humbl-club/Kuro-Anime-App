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
      validate: { $fn: "() => true" },
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
test("config bounds cover both lanes", (t) => {
  const P = W.loadProfiles(profileDir(t, { "x-test": { budgetClass: "browse", ratePerSecond: 6 } }));
  const sel = W.selectProfiles({ names: ["x-test"] }, P);
  assert.throws(() => W.validateConfig({ ...config, rps: 45 }, fixture, sel), /Invalid bounded rps/);
  assert.doesNotThrow(() => W.validateConfig({ ...config, rps: 20 }, fixture, sel));
  assert.throws(() => W.validateConfig({ ...config, only: "x-test" }, fixture, sel));
});
