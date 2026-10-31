"use strict";
const { makeProbe, execute } = require("./probe_support");
const { getPublicProjectConfig } = require("../lib/project_config");
const { randomUUID } = require("node:crypto");

async function runAdminProbe(options, work, afterCleanup) {
  const config = options.config || getPublicProjectConfig();
  const adminKey = options.adminKey || process.env.SUPABASE_SERVICE_ROLE_KEY;
  const p = makeProbe(config, { ...options, adminKey, limits: true });
  // Validate both administrative services before creating the first resource.
  try {
    // GoTrue's admin get-user endpoint returns user_not_found/404 for an absent
    // UUID, but refuses a non-administrative credential. Never list real users.
    const absent = await p.request(`/auth/v1/admin/users/${randomUUID()}`, { admin: true });
    if (absent.status !== 404 || !(absent.body?.code === "user_not_found" || absent.body?.msg === "User not found")) throw new Error("Administrative Auth access not proven");
    const media = await p.must("/storage/v1/object/list/media", { admin: true, method: "POST",
      body: { prefix: `kuro-preflight-${p.runId}/`, limit: 1 } });
    if (!Array.isArray(media) || media.length) throw new Error("Administrative media access not proven");
  } catch {
    return { target: p.url, runId: p.runId, status: "BLOCKED", ok: false, exitCode: 4,
      error: "Administrative Auth and media cleanup access is required before resource creation",
      resources: { accounts: [], clubs: [], objects: [] }, cleanup: [] };
  }
  const report = await execute(p, work);
  if (afterCleanup) {
    try { await afterCleanup(p, report); }
    catch {
      report.status = "FAIL"; report.ok = false; report.exitCode = 1;
      report.cleanup.push({ type: "service", status: "FAIL", reason: "Additional cleanup verification failed; exact resource inventory retained" });
    }
  }
  report.requestCount = p.requestCount;
  return report;
}
module.exports = { runAdminProbe };
