"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { approvedOrigin, APPROVED_ORIGIN, requirePermissionDenied, makeProbe, execute } = require("./probe_support");
const journal = require("./probe_import_sessions_select_only");
const realtime = require("./probe_club_activity_signals");
const config = { url: APPROVED_ORIGIN, anonKey: "fake-public-key" };

// Controlled external boundary only: the actual production probe functions execute.
function backend(options = {}) {
  const users = [], requests = [];
  let session = null, item = null, removed = false, revision = 1, memberRemoved = false;
  const fetch = async (raw, init) => {
    const url = new URL(raw), path = url.pathname;
    const body = init.body ? JSON.parse(init.body) : null;
    const token = init.headers.Authorization.slice(7);
    const user = users.find((u) => u.token === token);
    requests.push({ path, method: init.method, body });
    const reply = (data, status = 200) => new Response(JSON.stringify(data), { status });
    if (path === "/auth/v1/signup") {
      const id = `00000000-0000-4000-8000-${String(users.length + 1).padStart(12, "0")}`;
      const account = { id, token: `token-${users.length + 1}`, deleted: false };
      users.push(account);
      return reply({ user: { id }, ...(options.noSession ? {} : { access_token: account.token }) });
    }
    if (path === "/functions/v1/delete-account") { user.deleted = true; return reply({ success: true }); }
    if (path === "/auth/v1/user") return user?.deleted ? reply({}, 401) : reply({ id: user.id });
    if (path.startsWith("/auth/v1/admin/users/")) {
      const found = users.find((u) => path.endsWith(u.id));
      if (init.method === "DELETE") { found.deleted = true; return reply({}); }
      return reply({}, found.deleted ? 404 : 200);
    }
    if (path === "/rest/v1/anime") return reply([{ id: 7 }]);
    if (path === "/functions/v1/concierge-apply") {
      session = { id: "11111111-1111-4111-8111-111111111111", user_id: user.id, status: "applied", source: "chat" };
      item = { id: "22222222-2222-4222-8222-222222222222", session_id: session.id, raw: "Anime", parsed: {}, candidates: [], state: "applied" };
      return reply({ success: true, sessionId: session.id, applied: [{ mediaId: 7 }], undoable: true });
    }
    if (path === "/functions/v1/concierge-undo") { removed = true; return reply({ success: true, status: "undone", reverted: [{}] }); }
    if (["/rest/v1/import_sessions", "/rest/v1/import_session_items"].includes(path)) {
      if (init.method !== "GET") return options.zeroMutation ? reply([]) : reply({ code: options.denialCode || "42501" }, 403);
      return reply(user?.id === session?.user_id ? [path.endsWith("import_sessions") ? session : item] : []);
    }
    if (path === "/rest/v1/anime_user_lists") return reply(removed ? [] : [{ anime_id: 7 }]);
    if (path === "/rest/v1/rpc/create_club") return reply({ club_id: "33333333-3333-4333-8333-333333333333", invite_code: "PROBE" });
    if (path === "/rest/v1/rpc/create_club_rail") { revision++; options.onRail?.(revision, memberRemoved); return reply({}); }
    if (path === "/rest/v1/rpc/remove_club_member") { memberRemoved = true; options.onRemoval?.(body.p_user_id); return reply({ success: true }); }
    if (path.startsWith("/rest/v1/rpc/")) return reply({ success: true });
    if (path === "/rest/v1/club_activity_signals") return reply(user?.token === "token-3" || (memberRemoved && user?.token === "token-2") ? [] : [{ revision }]);
    if (path === "/rest/v1/clubs") return reply([]);
    throw new Error(`Unexpected fixture request ${path}`);
  };
  return { fetch, users, requests };
}

test("exact target rejects lookalikes, path/query/userinfo and the old override", () => {
  assert.equal(approvedOrigin(`${APPROVED_ORIGIN}/`, {}), APPROVED_ORIGIN);
  for (const url of ["http://bkdifromsqxkndnllmdj.supabase.co", `${APPROVED_ORIGIN}.attacker.test`, `${APPROVED_ORIGIN}/other`, `${APPROVED_ORIGIN}?target=1`, "https://user@bkdifromsqxkndnllmdj.supabase.co", "https://other.supabase.co/bkdifromsqxkndnllmdj"]) {
    assert.throws(() => approvedOrigin(url, {}));
  }
  assert.throws(() => approvedOrigin(APPROVED_ORIGIN, { KURO_LIVE_PROBE_ALLOW_OTHER: "1" }));
});

test("permission assertion requires 42501, never FK or zero-row success", () => {
  assert.doesNotThrow(() => requirePermissionDenied({ ok: false, status: 403, body: { code: "42501" } }, "write"));
  for (const result of [{ ok: false, status: 400, body: { code: "23503" } }, { ok: true, status: 200, body: [] }]) {
    assert.throws(() => requirePermissionDenied(result, "write"));
  }
});

test("actual journal probe uses Apply, both tables' real rows, outsider SELECT, and Undo", async () => {
  const b = backend();
  const report = await journal.run({ config, fetch: b.fetch, runId: "offline", timeout: 50, env: {} });
  assert.equal(report.status, "PASS");
  assert.equal(b.requests.filter((r) => r.path === "/functions/v1/concierge-apply").length, 1);
  assert.equal(b.requests.filter((r) => r.path === "/functions/v1/concierge-undo").length, 1);
  assert.equal(b.requests.filter((r) => r.path.includes("import_session") && r.method !== "GET").length, 6);
  assert.ok(b.users.every((u) => u.deleted));
});

for (const options of [{ denialCode: "23503" }, { zeroMutation: true }]) {
  test(`actual journal rejects false denial ${JSON.stringify(options)} and cleans both accounts`, async () => {
    const b = backend(options);
    const report = await journal.run({ config, fetch: b.fetch, runId: "offline", timeout: 50, env: {} });
    assert.equal(report.status, "FAIL");
    assert.match(report.error, /expected permission denial/);
    assert.ok(b.users.every((u) => u.deleted));
  });
}

test("missing session is recorded immediately; admin cleanup or explicit leftover, never pass", async () => {
  for (const adminKey of [null, "fake-admin-key"]) {
    const b = backend({ noSession: true });
    const p = makeProbe(config, { fetch: b.fetch, adminKey, runId: "missing", timeout: 50, env: {} });
    const report = await execute(p, () => p.provision("missing"));
    assert.equal(report.status, "FAIL");
    assert.ok(report.resources.accounts[0].userId);
    assert.equal(report.cleanup[0].status, adminKey ? "PASS" : "BLOCKED");
    assert.equal(b.users[0].deleted, Boolean(adminKey));
    assert.doesNotMatch(JSON.stringify(report), /fake-admin-key|access_token|token-/);
  }
});

function noDeliveryClient(options, state) {
  return () => ({
    realtime: { setAuth: async () => {} },
    channel() {
      const channel = { on() { return channel; }, subscribe(cb) { if (!options.noAck) cb("SUBSCRIBED"); }, unsubscribe() { state.cancelled++; } };
      return channel;
    },
    async removeChannel() { state.removed++; return "ok"; },
  });
}
for (const noAck of [false, true]) {
  test(`actual Realtime cannot pass without ${noAck ? "subscription acknowledgment" : "delivery despite a revision bump"}; channels clean up`, async () => {
    const b = backend(), state = { removed: 0, cancelled: 0 };
    const report = await realtime.run({ config, fetch: b.fetch, adminKey: "fake-admin", runId: "offline", timeout: 15,
      createClient: noDeliveryClient({ noAck }, state), observationMs: 0, env: {} });
    assert.equal(report.status, "FAIL");
    assert.match(report.error, noAck ? /subscribe.*timeout/ : /no matching event/);
    assert.equal(state.removed, noAck ? 1 : 4);
    assert.ok(b.users.every((u) => u.deleted));
    assert.equal(report.cleanup.find((r) => r.type === "club").status, "PASS");
  });
}

test("failure after first provision still cleans its recorded account", async () => {
  const b = backend();
  const p = makeProbe(config, { fetch: b.fetch, runId: "failed", timeout: 50, env: {} });
  const report = await execute(p, async () => { await p.provision("first"); throw new Error("fixture failure"); });
  assert.equal(report.status, "FAIL");
  assert.equal(report.cleanup[0].status, "PASS");
  assert.equal(b.users[0].deleted, true);
});


test("request deadline covers body read and cancels timed-out work", async () => {
  let signal;
  const p = makeProbe(config, { env: {}, timeout: 10, fetch: async (_url, init) => {
    signal = init.signal;
    return { ok: true, status: 200, text: () => new Promise(() => {}) };
  } });
  await assert.rejects(p.request("/auth/v1/user"), /timeout/);
  assert.equal(signal.aborted, true);
});

test("timed-out sign-up retains exact unknown identity for cleanup follow-up", async () => {
  const p = makeProbe(config, { env: {}, timeout: 10, runId: "uncertain", fetch: () => new Promise(() => {}) });
  const report = await execute(p, () => p.provision("unknown"));
  assert.equal(report.status, "FAIL");
  assert.equal(report.cleanup[0].status, "BLOCKED");
  assert.equal(report.resources.accounts[0].email, "kuro-probe-unknown-uncertain@mailbox.invalid");
});


test("actual Realtime verifies delivery, own removal and revocation before cleanup", async () => {
  const subscriptions = [];
  const clubId = "33333333-3333-4333-8333-333333333333";
  const b = backend({
    onRail(revision, removed) {
      for (const s of subscriptions) if (s.table === "club_activity_signals" && s.role !== "outsider" && !(removed && s.role === "member")) {
        s.callback({ new: { club_id: clubId, revision } });
      }
    },
    onRemoval(userId) {
      for (const s of subscriptions) if (s.table === "club_membership_signals") s.callback({ new: { club_id: clubId, user_id: userId, state: "removed" } });
    },
  });
  let clientCount = 0, removedChannels = 0;
  const createClient = () => {
    const role = ["owner", "member", "outsider"][clientCount++];
    return { realtime: { setAuth: async () => {} },
      channel() {
        const channel = { on(_event, spec, callback) { subscriptions.push({ role, table: spec.table, callback }); return channel; },
          subscribe(cb) { cb("SUBSCRIBED"); }, unsubscribe() {} };
        return channel;
      },
      async removeChannel() { removedChannels++; return "ok"; },
    };
  };
  const report = await realtime.run({ config, fetch: b.fetch, adminKey: "fake-admin", runId: "offline", timeout: 50, createClient, observationMs: 0, env: {} });
  assert.equal(report.status, "PASS");
  assert.equal(report.delivery, "PASS");
  assert.equal(report.membershipDelivery, "PASS");
  assert.equal(report.revocation, "PASS");
  assert.equal(report.nativeSubscriptionLifecycle, "NOT_RUN");
  assert.equal(removedChannels, 4);
  assert.ok(b.users.every((u) => u.deleted));
});
