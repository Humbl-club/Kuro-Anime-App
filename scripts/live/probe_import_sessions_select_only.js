#!/usr/bin/env node
"use strict";
const { randomUUID } = require("node:crypto");
const { getPublicProjectConfig } = require("../lib/project_config");
const { makeProbe, execute, requirePermissionDenied } = require("./probe_support");

async function journalChecks(p) {
  const owner = await p.provision("journal-owner");
  const outsider = await p.provision("journal-out");
  // Existing catalog is read-only; Apply changes only this new disposable user's list.
  const catalog = await p.must("/rest/v1/anime?select=id&order=id.asc&limit=1", { token: owner.token });
  const mediaId = catalog?.[0]?.id;
  if (!Number.isSafeInteger(mediaId) || mediaId < 1) throw new Error("No readable anime fixture for genuine Apply");
  const applied = await p.must("/functions/v1/concierge-apply", { method: "POST", token: owner.token, body: {
    idempotencyKey: `journal-${p.runId}`, items: [{ mediaType: "ANIME", mediaId, status: "PLANNING", action: "add", progressEpisodes: 0 }],
  } });
  if (applied.success !== true || !applied.sessionId || applied.applied?.length !== 1 || applied.undoable !== true) {
    throw new Error("Apply did not create an undoable journal item");
  }
  const sessionId = applied.sessionId;
  p.journals.push({ sessionId, userId: owner.userId, itemIds: [] });
  const targets = [
    { table: "import_sessions", query: `id=eq.${sessionId}`, change: { source: "probe-denied" } },
    { table: "import_session_items", query: `session_id=eq.${sessionId}`, change: { raw: "probe-denied" } },
  ];
  const result = { sessionId, mediaId, apply: "PASS", tables: {} };
  for (const target of targets) {
    const path = `/rest/v1/${target.table}`;
    const rows = await p.must(`${path}?${target.query}&select=*`, { token: owner.token });
    if (!Array.isArray(rows) || rows.length !== 1) throw new Error(`${target.table}: genuine owner row missing`);
    const row = rows[0];
    if (target.table === "import_session_items") p.journals[0].itemIds.push(row.id);
    const hidden = await p.must(`${path}?${target.query}&select=id`, { token: outsider.token });
    if (!Array.isArray(hidden) || hidden.length) throw new Error(`${target.table}: outsider read exposed journal`);
    const insert = { ...row, id: randomUUID() };
    if (target.table === "import_sessions" && insert.idempotency_key) insert.idempotency_key = `denied-${randomUUID()}`;
    // The copied row has valid required fields and the item's real session FK.
    for (const [name, method, body, query] of [
      ["insert", "POST", insert, ""],
      ["update", "PATCH", target.change, `?id=eq.${row.id}`],
      ["delete", "DELETE", undefined, `?id=eq.${row.id}`],
    ]) {
      const response = await p.request(`${path}${query}`, { method, body, token: owner.token, headers: { Prefer: "return=representation" } });
      requirePermissionDenied(response, `${target.table} ${name}`);
    }
    const after = await p.must(`${path}?${target.query}&select=*`, { token: owner.token });
    if (JSON.stringify(after) !== JSON.stringify(rows)) throw new Error(`${target.table}: journal changed after denied writes`);
    result.tables[target.table] = { ownerSelect: "PASS", outsiderSelect: "PASS", insert: "42501", update: "42501", delete: "42501", unchanged: true };
  }
  const undone = await p.must("/functions/v1/concierge-undo", { method: "POST", token: owner.token, body: { sessionId } });
  if (undone.success !== true || undone.status !== "undone" || undone.reverted?.length !== 1) throw new Error("Supported Undo failed for genuine Apply session");
  const remaining = await p.must(`/rest/v1/anime_user_lists?user_id=eq.${owner.userId}&anime_id=eq.${mediaId}&select=anime_id`, { token: owner.token });
  if (!Array.isArray(remaining) || remaining.length) throw new Error("Undo left the probe's added list row");
  result.undo = "PASS";
  return result;
}
async function run(options = {}) {
  const config = options.config || getPublicProjectConfig();
  const probe = makeProbe(config, { ...options, adminKey: options.adminKey || process.env.SUPABASE_SERVICE_ROLE_KEY, limits: true });
  return execute(probe, journalChecks);
}
if (require.main === module) {
  run().then((report) => { console.log(JSON.stringify(report, null, 2)); process.exitCode = report.exitCode; })
    .catch((error) => { console.error(error.message); process.exitCode = 1; });
}
module.exports = { run, journalChecks };
