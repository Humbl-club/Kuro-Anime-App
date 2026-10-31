"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const auth = require("./probe_auth_api");
const storage = require("./probe_account_storage");
const { makeProbe, APPROVED_ORIGIN } = require("./probe_support");
const config = { url: APPROVED_ORIGIN, anonKey: "fake-anon" };

function backend(options = {}) {
  const users = [], objects = new Map(), calls = [], profiles = new Map();
  const fetch = async (raw, init) => {
    const url = new URL(raw), path = url.pathname;
    const token = init.headers.Authorization.slice(7), admin = token === "fake-admin";
    const user = users.find((row) => row.token === token || row.refreshToken === token);
    calls.push({ method: init.method, path });
    const reply = (body, status = 200) => new Response(JSON.stringify(body), { status });
    if (path === "/auth/v1/admin/users") return admin && !options.badAdmin ? reply({ users: [{ email: "existing-customer@example.invalid" }] }) : reply({}, 403);
    if (path.startsWith("/auth/v1/admin/users/")) {
      const account = users.find((row) => path.endsWith(row.id));
      if (!admin || options.badAdmin) return reply({}, 403);
      if (!account) return reply({ code: "user_not_found" }, 404);
      if (init.method === "DELETE") account.deleted = true;
      return account?.deleted ? reply({}, 404) : reply({ id: account.id });
    }
    if (path === "/storage/v1/object/list/media") {
      if (!admin) return reply({}, 403);
      const body = JSON.parse(init.body);
      return reply([...objects.keys()].filter((name) => name.startsWith(body.prefix)).map((name) => ({ name })));
    }
    if (path === "/storage/v1/object/media" && init.method === "DELETE") {
      if (!admin) return reply({}, 403);
      JSON.parse(init.body).prefixes.forEach((name) => objects.delete(name)); return reply([]);
    }
    if (path.startsWith("/storage/v1/object/public/media/")) {
      const name = path.split("/public/media/")[1];
      return objects.has(name) ? new Response(objects.get(name)) : new Response(JSON.stringify({ statusCode: "404", code: "NoSuchKey" }), { status: 400, headers: { "CF-Cache-Status": "BYPASS" } });
    }
    if (path.startsWith("/storage/v1/object/media/")) {
      const bytes = init.body?.getReader ? Buffer.from(await new Response(init.body).arrayBuffer()) : init.body;
      const name = path.split("/object/media/")[1];
      if (user?.deleted && !options.allowDeletedUpload) return reply({ statusCode: "403", error: "Unauthorized" }, 400);
      objects.set(name, bytes);
      if (options.lostSeedResponse && name.endsWith("seed.png")) throw new Error("Simulated lost upload response");
      return reply({ Key: "media/" + name });
    }
    const body = init.body ? JSON.parse(init.body) : null;
    if (path === "/auth/v1/signup") {
      const id = `00000000-0000-4000-8000-${String(users.length + 1).padStart(12, "0")}`;
      const row = { id, email: body.email, password: body.password, token: "fake-token-" + id, refreshToken: "fake-refresh-" + id, deleted: false };
      users.push(row); return reply({ user: { id }, access_token: row.token, refresh_token: row.refreshToken });
    }
    if (path === "/auth/v1/token") {
      const row = users.find((u) => body.email === u.email || body.refresh_token === u.refreshToken);
      return reply({ user: { id: row.id }, access_token: row.refreshToken, refresh_token: row.refreshToken });
    }
    if (path === "/auth/v1/user") return user?.deleted ? reply({}, 401) : reply({ id: user.id });
    if (path === "/functions/v1/delete-account") {
      user.deleted = true;
      if (!options.allowDeletedUpload) for (const name of objects.keys()) if (name.startsWith(user.id + "/")) objects.delete(name);
      return reply({ success: true });
    }
    if (path === "/rest/v1/profiles") {
      if (url.searchParams.get("select") === "kuro_probe_missing_column") return reply({ code: "42703", details: null }, 400);
      const id = (url.searchParams.get("id") || "").replace("eq.", "");
      if (init.method === "POST") { profiles.set(body.id, body); return reply([body], 201); }
      if (init.method === "PATCH") return reply([]);
      if (!user) return options.malformedAnonymous ? reply({ rows: [] }) : reply({ code: "42501", details: null }, 401);
      const row = profiles.get(id);
      if (id !== user.id || !row) return reply([]);
      return reply([url.searchParams.get("select") === "id" ? { id } : row]);
    }
    throw new Error("Unexpected offline route " + path);
  };
  return { fetch, users, objects, calls };
}

test("both producers require admin verification before any disposable creation", async () => {
  for (const producer of [auth, storage]) {
    const b = backend({ badAdmin: true });
    const report = await producer.run({ config, fetch: b.fetch, adminKey: "fake-admin", runId: "offline", env: {} });
    assert.equal(report.status, "BLOCKED");
    assert.equal(b.users.length, 0);
    assert.equal(b.objects.size, 0);
  }
});

test("Auth captures nullable details, real identity/denial rows and sanitizes credentials/customer listings", async () => {
  const b = backend();
  const report = await auth.run({ config, fetch: b.fetch, adminKey: "fake-admin", runId: "offline", env: {} });
  assert.equal(report.status, "PASS", report.error);
  assert.equal(report.apiResponses.anonymousProfile.status, 401);
  assert.equal(report.apiResponses.structuredError.body.details, null);
  assert.ok(report.protocol.some((row) => row.path.includes("grant_type=password") && row.status === 200));
  const serialized = JSON.stringify(report);
  assert.doesNotMatch(serialized, /existing-customer|fake-token-|fake-refresh-|"password"|"access_token"|"refresh_token"/);
  assert.ok(b.users.every((row) => row.deleted));
  assert.ok(!b.calls.some((row) => row.path === "/auth/v1/admin/users"));
});

test("malformed successful anonymous response fails and still cleans both users", async () => {
  const b = backend({ malformedAnonymous: true });
  const report = await auth.run({ config, fetch: b.fetch, adminKey: "fake-admin", runId: "offline", env: {} });
  assert.equal(report.status, "FAIL");
  assert.ok(b.users.every((row) => row.deleted));
});

test("Storage creates a readable seed, real held overlap, same-token RLS denial and exact physical absence", async () => {
  const b = backend();
  const report = await storage.run({ config, fetch: b.fetch, adminKey: "fake-admin", runId: "offline", env: {} });
  assert.equal(report.status, "PASS", report.error);
  const rows = report.storageResponses;
  assert.equal(rows.initialUpload.status, 200);
  assert.equal(rows.originBefore.status, 200);
  assert.ok(BigInt(rows.overlappingUpload.startedNs) < BigInt(rows.deleteAccount.startedNs));
  assert.ok(BigInt(rows.deleteAccount.startedNs) < BigInt(rows.overlappingUpload.endedNs));
  assert.equal(rows.oldTokenUpload.status, 400);
  assert.equal(rows.oldTokenUpload.body.statusCode, "403");
  assert.equal(rows.oldTokenUpload.tokenSha256, rows.deleteAccount.tokenSha256);
  assert.deepEqual(rows.adminObjects.rows, []);
  assert.equal(b.objects.size, 0);
});

test("accepted old-token writes are failures even after exact emergency object cleanup succeeds", async () => {
  const b = backend({ allowDeletedUpload: true });
  const report = await storage.run({ config, fetch: b.fetch, adminKey: "fake-admin", runId: "offline", env: {} });
  assert.equal(report.status, "FAIL");
  assert.match(report.error, /Old-token upload was accepted/);
  assert.equal(report.emergencyStorageCleanup.paths.length, 3);
  assert.equal(b.objects.size, 0);
});

test("lost seed response stops subsequent business writes and retains exact cleanup inventory", async () => {
  const b = backend({ lostSeedResponse: true });
  const report = await storage.run({ config, fetch: b.fetch, adminKey: "fake-admin", runId: "offline", env: {} });
  assert.equal(report.status, "FAIL");
  assert.equal(b.calls.filter((row) => row.method === "POST" && row.path.includes("/object/media/")).length, 1);
  assert.equal(report.resources.objects.length, 3);
  assert.ok(b.users.every((row) => row.deleted));
  assert.equal(b.objects.size, 0);
});

test("account creation cap prevents the sixth dispatch", async () => {
  const b = backend();
  const p = makeProbe(config, { fetch: b.fetch, adminKey: "fake-admin", runId: "offline", env: {} });
  for (let i = 0; i < 5; i++) await p.provision("bound-" + i);
  await assert.rejects(() => p.provision("sixth"), /account limit/);
  assert.equal(b.users.length, 5);
  await p.cleanup();
});


test("transport starts at most five requests per second and holds at most five slots", async () => {
  let active = 0, peak = 0;
  const starts = [];
  const p = makeProbe(config, { limits: true, env: {}, fetch: async () => {
    starts.push(Date.now()); peak = Math.max(peak, ++active);
    await new Promise((resolve) => setTimeout(resolve, 1100)); active--;
    return new Response("[]");
  } });
  await Promise.all(Array.from({ length: 6 }, () => p.request("/bounded-offline")));
  assert.ok(peak <= 5);
  assert.equal(p.requestCount, 6);
  for (let i = 1; i < starts.length; i++) assert.ok(starts[i] - starts[i - 1] >= 200);
});


test("Storage separates uncached origin from cached delivery and never forgives expiry or uncertain absence", async () => {
  for (const scenario of ["invalidates", "stays-cached", "cached-origin", "malformed-origin", "uncached-200", "late-absence"]) {
    let time = 100000, ordinaryReads = 0;
    const p = { runId: "offline-cache", async request(url, options) {
      if (url.includes("?")) return { status: 400, body: { statusCode: "404", ...(scenario === "malformed-origin" ? {} : { code: "NoSuchKey" }) },
        cacheHeaders: { "cf-cache-status": scenario === "cached-origin" ? "HIT" : "BYPASS" } };
      assert.ok(options.timeoutMs > 0 && options.timeoutMs <= 60000);
      ordinaryReads++;
      if (scenario === "late-absence") time = 160001;
      if ((scenario === "invalidates" && ordinaryReads === 2) || scenario === "late-absence") return {
        status: 400, body: { statusCode: "404", code: "NoSuchKey" }, cacheHeaders: { "cf-cache-status": "BYPASS" } };
      return { status: 200, body: null, cacheHeaders: { "cf-cache-status": scenario === "uncached-200" ? "BYPASS" : "HIT", age: "49" } };
    } };
    const result = await storage.qualifyPublicAbsence(p, "disposable/seed.png", new Date(100000).toISOString(), {
      now: () => time, sleep: async (ms) => { time += ms; } });
    assert.equal(result.status, scenario === "invalidates" ? "PASS" : "FAIL", scenario);
    assert.ok(time <= 160001);
    if (scenario === "invalidates") {
      assert.equal(result.cachedObservations[0].status, 200);
      assert.equal(result.cachedObservations[0].cacheHeaders["cf-cache-status"], "HIT");
      assert.equal(result.cachedObservations[1].body.code, "NoSuchKey");
      assert.equal(result.cachedObservations[1].elapsedMs, 5000);
    }
    if (scenario.endsWith("origin")) assert.equal(ordinaryReads, 0);
  }
});


test("Realtime producer retains each account token through actual SDK join refresh without network", async () => {
  const realtime = require("./probe_club_activity_signals");
  const { createClient } = require("@supabase/supabase-js");
  const accounts = ["owner", "member", "outsider"].map((role, index) => ({
    userId: `00000000-0000-4000-8000-${String(index + 1).padStart(12, "0")}`,
    token: `placeholder-${role}-token`,
  }));
  let provisioned = 0, requests = 0;
  const clients = [];
  const stopBeforeSubscriptions = new Error("No WebSocket subscription in this offline regression");
  const p = { url: "https://example.supabase.co", anonKey: "public-placeholder", timeout: 100,
    runId: "sdk-auth-only", clubs: [],
    provision: async () => accounts[provisioned++],
    rpc: async (_account, name) => name === "create_club" ? { club_id: "33333333-3333-4333-8333-333333333333", invite_code: "placeholder" } : {},
  };
  await assert.rejects(() => realtime.realtimeChecks(p, (url, key, options) => {
    const client = createClient(url, key, { ...options, global: { fetch: async () => {
      requests++; throw new Error("Unexpected network request");
    } } });
    clients.push(client);
    if (clients.length === accounts.length) throw stopBeforeSubscriptions;
    return client;
  }), (error) => error === stopBeforeSubscriptions);
  for (let index = 0; index < clients.length; index++) {
    // RealtimeChannel.subscribe invokes the installed SDK's parameterless
    // setAuth after a successful join; it must not fall back to the anon key.
    await clients[index].realtime.setAuth();
    assert.equal(clients[index].realtime.accessTokenValue, accounts[index].token);
    assert.notEqual(clients[index].realtime.accessTokenValue, p.anonKey);
  }
  assert.equal(requests, 0);
});
