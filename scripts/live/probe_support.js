"use strict";
const { randomUUID, createHash } = require("node:crypto");
const APPROVED_ORIGIN = "https://bkdifromsqxkndnllmdj.supabase.co";
function sanitize(value) {
  if (Array.isArray(value)) return value.map(sanitize);
  if (value && typeof value === "object") return Object.fromEntries(Object.entries(value)
    .filter(([key]) => !/password|token|authorization|service.?role|apikey/i.test(key)).map(([key, item]) => [key, sanitize(item)]));
  return value;
}

function approvedOrigin(raw, env = process.env) {
  const url = new URL(raw);
  if (env.KURO_LIVE_PROBE_ALLOW_OTHER || url.origin !== APPROVED_ORIGIN ||
      url.username || url.password || (url.pathname !== "/" && url.pathname !== "") || url.search || url.hash) {
    throw new Error("Live probe requires the exact approved Kuro HTTPS origin; overrides are refused");
  }
  return APPROVED_ORIGIN;
}
function requirePermissionDenied(response, label) {
  if (response.ok || response.body?.code !== "42501") {
    throw new Error(`${label}: expected permission denial 42501, got HTTP ${response.status} / ${response.body?.code || "no code"}`);
  }
}
function isAuthorizationDenied(response) {
  return !response.ok && ([401, 403].includes(response.status) || (response.status === 400 &&
    (["401", "403"].includes(String(response.body?.statusCode)) || response.body?.code === "42501")));
}
function requireDelivery(results) {
  if (results.memberEvents < 1 || results.outsiderEvents !== 0) {
    throw new Error(`Realtime delivery failed: member=${results.memberEvents}, outsider=${results.outsiderEvents}`);
  }
}
// Race also bounds SDK operations. The caller supplies cancellation for channels.
async function bounded(operation, label, milliseconds, cancel = () => {}) {
  let timer;
  try {
    return await Promise.race([Promise.resolve().then(operation), new Promise((_, reject) => {
      timer = setTimeout(() => {
        try { Promise.resolve(cancel()).catch(() => {}); } catch {}
        reject(new Error(`${label}: timeout`));
      }, milliseconds);
    })]);
  } finally { clearTimeout(timer); }
}
function makeProbe(config, options = {}) {
  const url = approvedOrigin(config.url, options.env || process.env);
  const fetcher = options.fetch || fetch;
  const timeout = options.timeout || 15000;
  const runId = options.runId || `${new Date().toISOString().replace(/[^0-9TZ]/g, "")}-${randomUUID().slice(0, 8)}`;
  const accounts = [], clubs = [], journals = [], channels = [];
  const objects = [];
  const protocol = [];
  const adminKey = options.adminKey || null;
  let nextStart = 0, activeRequests = 0, requestCount = 0, dispatchQueue = Promise.resolve();
  const waiting = [];
  const limits = options.limits;
  const acquire = async () => {
    const acquireSlot = async () => {
      if (limits && requestCount >= 1000) throw new Error("Disposable probe request budget exceeded");
      while (limits && activeRequests >= 5) await new Promise((resolve) => waiting.push(resolve));
      if (limits) {
        while (Date.now() < nextStart) await new Promise((resolve) => setTimeout(resolve, nextStart - Date.now()));
        nextStart = Date.now() + 200;
      }
      activeRequests++; requestCount++;
    };
    const slot = dispatchQueue.then(acquireSlot);
    dispatchQueue = slot.catch(() => {});
    await slot;
    return () => { activeRequests--; waiting.splice(0).forEach((resolve) => resolve()); };
  };
  const request = async (path, { token, admin = false, method = "GET", body, rawBody, headers = {}, jsonResponse = true, onDispatch, timeoutMs = timeout } = {}) => {
    if (admin && !adminKey) throw new Error("Administrative cleanup verification requires SUPABASE_SERVICE_ROLE_KEY");
    const release = await acquire();
    const key = admin ? adminKey : config.anonKey;
    const controller = new AbortController();
    const trace = { method, path, actorUserId: accounts.find((row) => row.token === token)?.userId || null,
      administrative: admin, startedAt: new Date().toISOString(), requestBody: sanitize(body) };
    if (token) trace.credentialSha256 = createHash("sha256").update(token).digest("hex");
    protocol.push(trace);
    try { return await bounded(async () => {
      onDispatch?.();
      const response = await fetcher(`${url}${path}`, { method, signal: controller.signal,
        headers: { apikey: key, Authorization: `Bearer ${token || key}`, "Content-Type": "application/json", ...headers },
        ...(rawBody === undefined ? (body === undefined ? {} : { body: JSON.stringify(body) }) : { body: rawBody,
          ...(rawBody?.getReader ? { duplex: "half" } : {}) }) });
      const text = await response.text();
      let data;
      try { data = text ? JSON.parse(text) : null; } catch { if (jsonResponse) throw new Error(`${path.split("?")[0]}: invalid JSON response`); data = null; }
      const cacheHeaders = Object.fromEntries(["cf-cache-status", "cache-control", "age"].map((name) => [name, response.headers.get(name)]).filter(([, value]) => value !== null));
      Object.assign(trace, { status: response.status, cacheHeaders, responseBody: path.startsWith("/auth/v1/admin/users?") ? { redacted: true } : sanitize(data) });
      return { ok: response.ok, status: response.status, body: data, cacheHeaders };
    }, path.split("?")[0], Math.min(timeout, timeoutMs), () => controller.abort()); }
    finally { trace.endedAt = new Date().toISOString(); release(); }
  };
  const must = async (path, params) => {
    const result = await request(path, params);
    if (!result.ok) throw new Error(`${path.split("?")[0]}: HTTP ${result.status} / ${result.body?.code || "request failed"}`);
    return result.body;
  };
  const provision = async (role) => {
    if (accounts.length >= 5) throw new Error("Disposable probe account limit exceeded");
    const email = `kuro-probe-${role}-${runId}@mailbox.invalid`;
    // Record intent before dispatch: a timed-out sign-up may have committed remotely.
    const account = { email, userId: null, token: null, provisioned: false, password: `Probe-${randomUUID()}-Aa1!` };
    accounts.push(account);
    const response = await request("/auth/v1/signup", { method: "POST", body: { email, password: account.password } });
    const auth = response.body || {};
    account.signupStatus = response.status;
    const returnedId = auth.user?.id || auth.id;
    account.userId = typeof returnedId === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(returnedId) ? returnedId.toLowerCase() : null;
    account.token = auth.access_token || auth.session?.access_token || null;
    account.provisioned = Boolean(account.userId);
    if (!response.ok || !account.userId || !account.token) throw new Error("Disposable sign-up did not return an identity and session; cleanup record retained");
    return account;
  };
  const rpc = (account, name, body) => must(`/rest/v1/rpc/${name}`, { method: "POST", token: account.token, body });
  const cleanup = async () => {
    const outcomes = [];
    for (const { client, channel } of channels) {
      try {
        const status = await bounded(() => client.removeChannel(channel), "channel cleanup", timeout, () => channel.unsubscribe());
        if (status !== "ok") throw new Error("Channel disposal not acknowledged");
      }
      catch { outcomes.push({ type: "channel", status: "FAIL" }); }
    }
    for (const account of [...accounts].reverse()) {
      try {
        if (account.token) {
          if (!account.deletionConfirmed) {
            const result = await must("/functions/v1/delete-account", { method: "POST", token: account.token, body: { confirm: "true" } });
            if (result?.success !== true) throw new Error("delete-account did not confirm success");
          }
          const who = await request("/auth/v1/user", { token: account.token });
          if (who.ok || ![401, 403].includes(who.status)) throw new Error("Auth deletion not confirmed");
          if (adminKey) {
            const absent = await request(`/auth/v1/admin/users/${account.userId}`, { admin: true });
            if (absent.status !== 404) throw new Error("Physical Auth cleanup not confirmed");
          }
        } else if (account.userId && adminKey) {
          await must(`/auth/v1/admin/users/${account.userId}`, { method: "DELETE", admin: true });
          const who = await request(`/auth/v1/admin/users/${account.userId}`, { admin: true });
          if (who.ok || who.status !== 404) throw new Error("Admin account cleanup not confirmed");
        } else {
          outcomes.push({ type: "account", email: account.email, userId: account.userId, status: "BLOCKED", reason: "No session or verified administrative cleanup; inspect this exact sign-up identity" });
          continue;
        }
        outcomes.push({ type: "account", email: account.email, userId: account.userId, status: "PASS" });
      } catch {
        const outcome = { type: "account", email: account.email, userId: account.userId, status: "FAIL", reason: "Account cleanup or its verification failed" };
        if (account.userId && adminKey && objects.length === 0) {
          try {
            const present = await request(`/auth/v1/admin/users/${account.userId}`, { admin: true });
            if (present.status === 200) await must(`/auth/v1/admin/users/${account.userId}`, { method: "DELETE", admin: true });
            const absent = await request(`/auth/v1/admin/users/${account.userId}`, { admin: true });
            outcome.emergencyAuthCleanup = absent.status === 404 ? "PASS" : "FAIL";
          } catch { outcome.emergencyAuthCleanup = "FAIL"; }
        }
        outcomes.push(outcome);
      }
    }
    // RLS invisibility is not physical deletion. Admin access is read-only here.
    for (const clubId of clubs) {
      if (!adminKey) { outcomes.push({ type: "club", clubId, status: "BLOCKED", reason: "Physical absence requires administrative verification" }); continue; }
      try {
        const rows = await must(`/rest/v1/clubs?id=eq.${clubId}&select=id`, { admin: true });
        if (!Array.isArray(rows) || rows.length) throw new Error("Club remains");
        outcomes.push({ type: "club", clubId, status: "PASS" });
      } catch { outcomes.push({ type: "club", clubId, status: "FAIL", reason: "Created club absence not confirmed" }); }
    }
    return outcomes;
  };
  return { url, runId, accounts, clubs, journals, channels, objects, protocol, evidence: {}, request, must, provision, rpc, cleanup, timeout,
    get requestCount() { return requestCount; } };
}
async function execute(probe, work) {
  let error = null, results = {};
  try { results = await work(probe); } catch (e) { error = e.message; }
  const cleanup = await probe.cleanup();
  const failed = error || cleanup.some((r) => r.status === "FAIL");
  const blocked = cleanup.some((r) => r.status === "BLOCKED");
  const status = failed ? "FAIL" : blocked ? "BLOCKED" : "PASS";
  return { ok: status === "PASS", status, exitCode: failed ? 1 : blocked ? 4 : 0, runId: probe.runId, target: probe.url,
    ...probe.evidence, ...results, ...(error ? { error } : {}), requestCount: probe.requestCount, protocol: probe.protocol,
    resources: { accounts: probe.accounts.map(({ email, userId }) => ({ email, userId })), clubs: probe.clubs, journals: probe.journals, objects: probe.objects }, cleanup };
}
module.exports = { APPROVED_ORIGIN, approvedOrigin, bounded, requirePermissionDenied, requireDelivery, isAuthorizationDenied, makeProbe, execute };
