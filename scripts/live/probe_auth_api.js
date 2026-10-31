#!/usr/bin/env node
"use strict";
const { runAdminProbe } = require("./admin_probe");
const { isAuthorizationDenied } = require("./probe_support");

function identity(response) {
  return { status: response.status, user: { id: response.body?.user?.id || response.body?.id } };
}
function rows(response) { return { status: response.status, rows: Array.isArray(response.body) ? response.body :
  (isAuthorizationDenied(response) ? [] : null), ...(!response.ok ? { body: response.body } : {}) }; }
async function authChecks(p) {
  const owner = await p.provision("auth-owner");
  const outsider = await p.provision("auth-outsider");
  const auth = { signup: { status: owner.signupStatus, user: { id: owner.userId } } };
  p.evidence.authResponses = auth;
  auth.outsiderSession = identity(await p.request("/auth/v1/user", { token: outsider.token }));
  if (auth.outsiderSession.status !== 200 || auth.outsiderSession.user.id !== outsider.userId) throw new Error("Authenticated outsider session is missing");
  const signin = await p.request("/auth/v1/token?grant_type=password", { method: "POST", body: { email: owner.email, password: owner.password } });
  auth.passwordSignin = identity(signin);
  if (!signin.ok || !signin.body?.access_token || !signin.body.refresh_token || auth.passwordSignin.user.id !== owner.userId) throw new Error("Password sign-in identity failed");
  const refresh = await p.request("/auth/v1/token?grant_type=refresh_token", { method: "POST", body: { refresh_token: signin.body.refresh_token } });
  auth.refresh = identity(refresh);
  if (!refresh.ok || !refresh.body?.access_token || auth.refresh.user.id !== owner.userId) throw new Error("Refresh identity failed");
  const restored = await p.request("/auth/v1/user", { token: refresh.body.access_token });
  auth.restoredUser = identity(restored);
  if (!restored.ok || auth.restoredUser.user.id !== owner.userId) throw new Error("Restored token identity failed");
  const seeded = await p.request("/rest/v1/profiles?on_conflict=id", { method: "POST", token: owner.token,
    headers: { Prefer: "resolution=merge-duplicates,return=representation" }, body: { id: owner.userId, display_name: `Probe ${p.runId}` } });
  if (!seeded.ok || !Array.isArray(seeded.body) || seeded.body[0]?.id !== owner.userId) throw new Error("Own disposable profile setup failed");
  const path = `/rest/v1/profiles?id=eq.${owner.userId}`;
  const api = {}; p.evidence.apiResponses = api;
  api.ownerProfile = rows(await p.request(`${path}&select=id`, { token: owner.token }));
  api.ownerBefore = rows(await p.request(`${path}&select=id,display_name`, { token: owner.token }));
  const anonymous = await p.request(`${path}&select=id`);
  api.anonymousProfile = rows(anonymous);
  const update = await p.request(`${path}&select=id,display_name`, { token: outsider.token, method: "PATCH",
    headers: { Prefer: "return=representation" }, body: { display_name: "Probe unauthorized update" } });
  api.outsiderUpdate = { ...rows(update), actorUserId: outsider.userId };
  if (!(update.status === 200 || isAuthorizationDenied(update)) || api.outsiderUpdate.rows === null || api.outsiderUpdate.rows.length) throw new Error("Outsider profile update was not safely refused");
  api.ownerAfter = rows(await p.request(`${path}&select=id,display_name`, { token: owner.token }));
  if (api.ownerProfile.status !== 200 || api.ownerProfile.rows[0]?.id !== owner.userId ||
      !(anonymous.status === 200 || isAuthorizationDenied(anonymous)) || !Array.isArray(api.anonymousProfile.rows) || api.anonymousProfile.rows.length ||
      !Array.isArray(api.ownerBefore.rows) || !api.ownerBefore.rows.length || JSON.stringify(api.ownerBefore) !== JSON.stringify(api.ownerAfter)) throw new Error("Live profile isolation failed");
  const error = await p.request("/rest/v1/profiles?select=kuro_probe_missing_column", { token: owner.token });
  api.structuredError = { status: error.status, body: error.body };
  if (error.ok || !error.body?.code || !Object.hasOwn(error.body, "details")) throw new Error("Structured PostgREST error was not captured");
  return { nativeSessionRestore: "NOT_RUN" };
}
async function run(options = {}) { return runAdminProbe(options, authChecks); }
if (require.main === module) run().then((report) => { console.log(JSON.stringify(report, null, 2)); process.exitCode = report.exitCode; })
  .catch(() => { console.error("Auth/API probe failed before a report could be emitted"); process.exitCode = 1; });
module.exports = { run, authChecks };
