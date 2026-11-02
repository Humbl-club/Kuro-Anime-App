#!/usr/bin/env node
"use strict";
const { createHash, randomUUID } = require("node:crypto");
const { runAdminProbe } = require("./admin_probe");
const { bounded, isAuthorizationDenied } = require("./probe_support");
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jD1EAAAAASUVORK5CYII=", "base64");
const instant = () => new Date().toISOString();
const monotonic = () => process.hrtime.bigint().toString();

async function storageChecks(p) {
  const owner = await p.provision("storage-owner");
  const tokenSha256 = createHash("sha256").update(owner.token).digest("hex");
  const paths = ["seed", "race", "after"].map((name) => `${owner.userId}/kuro-${p.runId}-${name}.png`);
  p.objects.push(...paths); // Record all attempted object identities before dispatch.
  const response = {}; p.evidence.storageResponses = response;
  const upload = (path, extra = {}) => p.request(`/storage/v1/object/media/${path}`, {
    token: owner.token, method: "POST", headers: { "Content-Type": "image/png", "x-upsert": "false" }, rawBody: PNG, ...extra });
  const seed = await upload(paths[0]);
  response.initialUpload = { status: seed.status, body: seed.body, path: paths[0], bucket: "media", userId: owner.userId };
  if (!seed.ok) throw new Error("Seed image upload failed");
  const origin = await p.request(`/storage/v1/object/public/media/${paths[0]}`, { jsonResponse: false });
  response.originBefore = { status: origin.status, cacheHeaders: origin.cacheHeaders, path: paths[0], bucket: "media" };
  if (origin.status !== 200) throw new Error("Seed image was not publicly readable before deletion");
  let openBody, bodyPulled;
  const gate = new Promise((resolve) => { openBody = resolve; });
  const pulled = new Promise((resolve) => { bodyPulled = resolve; });
  let sent = false;
  const stream = new ReadableStream({ async pull(controller) {
    if (sent) return;
    sent = true; controller.enqueue(PNG.subarray(0, 16)); bodyPulled();
    await gate; controller.enqueue(PNG.subarray(16)); controller.close();
  } });
  const race = { tokenSha256, path: paths[1], bucket: "media", userId: owner.userId };
  response.overlappingUpload = race;
  const pending = upload(paths[1], { rawBody: stream, onDispatch: () => { race.startedAt = instant(); race.startedNs = monotonic(); } })
    .then((result) => { Object.assign(race, { endedAt: instant(), endedNs: monotonic(), status: result.status, body: result.body }); return result; });
  // Attach rejection handling immediately; cleanup releases/settles the upload even on failure.
  const settled = pending.then((result) => ({ result }), (error) => ({ error }));
  try {
    await bounded(() => pulled, "upload first body chunk", p.timeout);
    if (race.endedAt) throw new Error("Upload ended before deletion; no overlap proved");
    const deletion = { tokenSha256, userId: owner.userId }; response.deleteAccount = deletion;
    const deleted = await p.request("/functions/v1/delete-account", { token: owner.token, method: "POST", body: { confirm: "true" },
      onDispatch: () => { if (race.endedAt) throw new Error("Upload already ended before deletion dispatch"); deletion.startedAt = instant(); deletion.startedNs = monotonic(); openBody(); } });
    Object.assign(deletion, { endedAt: instant(), endedNs: monotonic(), status: deleted.status, body: deleted.body });
    if (!deleted.ok || deleted.body?.success !== true) throw new Error("App deletion did not succeed");
    owner.deletionConfirmed = true;
    const completed = await settled;
    if (completed.error) throw completed.error;
    if (!completed.result.ok && !isAuthorizationDenied(completed.result)) throw new Error("Overlapping upload returned an unexpected failure");
    if (!(BigInt(race.startedNs) < BigInt(deletion.startedNs) && BigInt(deletion.startedNs) < BigInt(race.endedNs))) throw new Error("Upload/deletion did not overlap");
    const denied = await p.request("/auth/v1/user", { token: owner.token });
    response.deletedUserRead = { status: denied.status, endedAt: instant() };
    if (![401, 403].includes(denied.status)) throw new Error("GoTrue still accepts the deleted account");
    const after = { startedAt: instant(), startedNs: monotonic(), tokenSha256, path: paths[2], bucket: "media", userId: owner.userId };
    response.oldTokenUpload = after;
    const old = await upload(paths[2]);
    Object.assign(after, { status: old.status, body: old.body, endedAt: instant() });
    if (!isAuthorizationDenied(old)) throw new Error("Old-token upload was accepted after deletion");
  } finally {
    openBody();
    await settled;
  }
  return {};
}

const CDN_PROPAGATION_MS = 60000;
const missingObject = (read) => [400, 404].includes(read.status) &&
  String(read.body?.statusCode) === "404" && read.body?.code === "NoSuchKey";

async function qualifyPublicAbsence(p, path, deletedAt, { now = Date.now, sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)) } = {}) {
  const url = `/storage/v1/object/public/media/${path}`;
  const result = { origin: null, cachedObservations: [], propagationLimitMs: CDN_PROPAGATION_MS, status: "FAIL" };
  try {
    const origin = await p.request(`${url}?cacheNonce=${encodeURIComponent(p.runId)}-${randomUUID()}`, {
      jsonResponse: false, headers: { "Cache-Control": "no-cache" } });
    result.origin = { status: origin.status, body: origin.body, cacheHeaders: origin.cacheHeaders };
    // A fresh query alone does not prove origin: a cache HIT is still cached.
    if (!missingObject(origin) || !["BYPASS", "MISS"].includes(origin.cacheHeaders?.["cf-cache-status"]?.toUpperCase())) return result;
    const deletionTime = Date.parse(deletedAt);
    if (!Number.isFinite(deletionTime)) return result;
    const deadline = deletionTime + CDN_PROPAGATION_MS;
    while (now() < deadline) {
      const read = await p.request(url, { jsonResponse: false, timeoutMs: deadline - now() });
      const elapsedMs = now() - deletionTime;
      result.cachedObservations.push({ at: new Date(now()).toISOString(), elapsedMs,
        status: read.status, body: read.body, cacheHeaders: read.cacheHeaders });
      if (missingObject(read) && elapsedMs >= 0 && elapsedMs <= CDN_PROPAGATION_MS) { result.status = "PASS"; return result; }
      if (read.status !== 200 || !["HIT", "STALE", "UPDATING"].includes(read.cacheHeaders?.["cf-cache-status"]?.toUpperCase()) || elapsedMs >= CDN_PROPAGATION_MS) return result;
      await sleep(Math.min(5000, Math.max(0, deadline - now())));
    }
    return result;
  } catch (error) { result.error = error.message; return result; }
}

async function finishStorage(p, report) {
  const response = report.storageResponses || {}; report.storageResponses = response;
  let failed = false;
  for (const account of p.accounts.filter((row) => row.userId)) {
    try {
      const auth = await p.request(`/auth/v1/admin/users/${account.userId}`, { admin: true });
      response.adminAuthRead = { status: auth.status, userId: account.userId };
      const listed = await p.request("/storage/v1/object/list/media", { admin: true, method: "POST", body: { prefix: account.userId + "/", limit: 100 } });
      response.adminObjects = { status: listed.status, rows: listed.body, prefix: account.userId + "/", bucket: "media" };
      if (auth.status !== 404 || !listed.ok || !Array.isArray(listed.body) || listed.body.length) failed = true;
      if (Array.isArray(listed.body) && listed.body.length) {
        // Emergency cleanup may remove only this run's exact recorded object paths.
        const removed = await p.request("/storage/v1/object/media", { admin: true, method: "DELETE", body: { prefixes: p.objects.filter((path) => path.startsWith(account.userId + "/")) } });
        report.emergencyStorageCleanup = { status: removed.status, paths: [...p.objects] };
      }
      if (auth.status === 200) {
        const remaining = await p.request("/storage/v1/object/list/media", { admin: true, method: "POST", body: { prefix: account.userId + "/", limit: 100 } });
        if (remaining.ok && Array.isArray(remaining.body) && !remaining.body.length) {
          const removed = await p.request(`/auth/v1/admin/users/${account.userId}`, { admin: true, method: "DELETE" });
          const absent = await p.request(`/auth/v1/admin/users/${account.userId}`, { admin: true });
          report.emergencyAuthCleanup = { userId: account.userId, status: removed.status, absentStatus: absent.status };
        }
      }
    } catch { failed = true; }
  }
  response.originReads = {};
  for (const path of p.objects) {
    try {
      const qualification = await qualifyPublicAbsence(p, path, response.deleteAccount?.endedAt);
      response.originReads[path] = qualification;
      if (qualification.status !== "PASS") failed = true;
    } catch { failed = true; }
  }
  report.cleanup.push({ type: "storage", paths: [...p.objects], status: failed ? "FAIL" : "PASS" });
  if (failed) { report.status = "FAIL"; report.ok = false; report.exitCode = 1; report.error ||= "Physical Auth/media cleanup, uncached origin absence, or bounded CDN invalidation failed; inspect recorded observations and emergency cleanup"; }
}
async function run(options = {}) { return runAdminProbe(options, storageChecks, finishStorage); }
if (require.main === module) run().then((report) => { console.log(JSON.stringify(report, null, 2)); process.exitCode = report.exitCode; })
  .catch(() => { console.error("Storage probe failed before a report could be emitted"); process.exitCode = 1; });
module.exports = { run, storageChecks, finishStorage, qualifyPublicAbsence };
