#!/usr/bin/env node
"use strict";
const { randomUUID } = require("node:crypto");
const { runAdminProbe } = require("./admin_probe");

// Real v2 wire proof using synthetic source entries over existing public catalog IDs.
// This does not prove provider OAuth/paging, native orchestration or projection publication.
const columns = "list_type,progress,progress_label,unit_id,notes,rating,score_raw,score_scale,repeat_count,started_raw,finished_raw,entry_private,source_custom_lists,source_hidden,source_list_options,server_revision,lifecycle_id";
const semanticColumns = columns.split(",").filter((key) => key !== "server_revision");
function requireTrue(value, message) { if (!value) throw new Error(message); }
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === "object") return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])]));
  return value;
}
function same(actual, expected, message) {
  requireTrue(JSON.stringify(canonical(actual)) === JSON.stringify(canonical(expected)), message);
}
function decision(item, action, fields = []) {
  return { medium: item.medium, external_id: item.external_id, action, fields,
    expected_revision: item.expected_revision, expected_lifecycle: item.expected_lifecycle,
    resolved_media_id: item.media_id };
}
function reject(response, message) {
  requireTrue(!response.ok && response.body?.code === "P0001" && response.body?.message === message,
    `Expected ${message}, received HTTP ${response.status}/${response.body?.code || "no code"}`);
}
function source(title, provider, values) {
  const external = provider === "anilist" ? title.anilist_id : title.mal_id;
  requireTrue(Number.isSafeInteger(external) && external > 0, "Catalog provider identity is unavailable");
  return { medium: title.medium, external_id: String(external), title: title.title_romaji, values };
}
function fields(row, medium) {
  return Object.fromEntries([...semanticColumns, ...(medium === "manga" ? ["volumes_progress"] : [])].map((key) => [key, row[key]]));
}
async function readLists(p, owner) {
  const result = {};
  for (const medium of ["anime", "manga"]) {
    result[medium] = await p.must(`/rest/v1/${medium}_user_lists?user_id=eq.${owner.userId}&select=${medium}_id,${columns}${medium === "manga" ? ",volumes_progress" : ""}&order=${medium}_id.asc`, { token: owner.token });
    requireTrue(Array.isArray(result[medium]) && result[medium].length <= 2, "Unexpected disposable Library size");
  }
  return result;
}
function row(lists, title) { return lists[title.medium].find((item) => item[`${title.medium}_id`] === title.id); }
async function review(p, owner, jobId, limit = 1) {
  const items = [], seen = new Set();
  let cursor = null;
  for (let page = 0; page < 8; page++) {
    const result = await p.rpc(owner, "import_items_page_v2", { p_job_id: jobId, p_cursor: cursor, p_limit: limit });
    requireTrue(Array.isArray(result.items) && result.items.length <= limit, "Review pagination is not bounded");
    for (const item of result.items) {
      const identity = `${item.medium}|${item.external_id}`;
      requireTrue(!seen.has(identity), "Review pagination repeated an identity");
      seen.add(identity); items.push(item);
    }
    if (!result.next_cursor) return items;
    requireTrue(result.next_cursor !== cursor, "Review cursor did not advance");
    cursor = result.next_cursor;
  }
  throw new Error("Review exceeded this probe's eight-page limit");
}
async function start(p, owner, provider, label) {
  const selection = { provider, source_kind: "export", source_identity: `probe-${p.runId}-${label}`, media: ["anime", "manga"], statuses: [] };
  const actionId = `probe-${randomUUID()}`;
  // Record admission intent before dispatch so an uncertain start remains attributable.
  const entry = { userId: owner.userId, actionId, provider, label, jobId: null, items: [] };
  p.journals.push(entry);
  const result = await p.rpc(owner, "start_library_import_v2", { p_selection: selection, p_action_id: actionId });
  requireTrue(typeof result.job_id === "string" && /^[0-9a-f-]{36}$/i.test(result.job_id), "Start did not return a job identity");
  entry.jobId = result.job_id;
  same(await p.rpc(owner, "start_library_import_v2", { p_selection: selection, p_action_id: actionId }), result, "Start replay changed the job");
  requireTrue(result.phase === "preparing", "A new job did not begin preparation");
  return entry;
}
async function stage(p, owner, job, items) {
  job.items = items.map(({ medium, external_id }) => ({ medium, external_id }));
  const before = await readLists(p, owner);
  const first = await p.rpc(owner, "prepare_import_chunk_v2", { p_job_id: job.jobId, p_items: items.filter((item) => item.medium === "anime"), p_exhausted_media: { anime: true } });
  requireTrue(first.phase === "preparing", "One completed stream hid incomplete Manga");
  const prepared = await p.rpc(owner, "prepare_import_chunk_v2", { p_job_id: job.jobId, p_items: items.filter((item) => item.medium === "manga"), p_exhausted_media: { manga: true } });
  requireTrue(prepared.phase === "reviewing" && prepared.exhausted_media.anime === true && prepared.exhausted_media.manga === true, "Both-medium source was not ready for review");
  same(await readLists(p, owner), before, "Preparation wrote Library data");
  const actual = await review(p, owner, job.jobId);
  requireTrue(actual.length === items.length, "Staging lost a source identity");
  return actual;
}
async function apply(p, owner, job, decisions, replay = false) {
  const body = { p_job_id: job.jobId, p_action_id: job.actionId, p_decisions: decisions };
  const result = await p.rpc(owner, "apply_import_chunk_v2", body);
  if (replay) same(await p.rpc(owner, "apply_import_chunk_v2", body), result, "Apply replay changed the original receipt");
  return result;
}
async function finish(p, owner, job) {
  const result = await p.rpc(owner, "finish_library_import_v2", { p_job_id: job.jobId });
  requireTrue(result.phase === "ready" && result.projection_ready === false && result.history_available === true, "Finalization did not expose an honest durable result");
  same(await p.rpc(owner, "import_job_status_v2", { p_job_id: job.jobId }), result, "Persistent status differs from completion");
  return result;
}
async function undo(p, owner, job) {
  const actionId = `undo-${randomUUID()}`;
  let cursor = null, firstReceipt;
  for (let page = 0; page < 4; page++) {
    const body = { p_job_id: job.jobId, p_action_id: actionId, p_cursor: cursor, p_limit: 1 };
    const result = await p.rpc(owner, "undo_library_import_chunk_v2", body);
    same(await p.rpc(owner, "undo_library_import_chunk_v2", body), result, "Undo replay changed its receipt");
    if (!firstReceipt) firstReceipt = { body, result };
    if (!result.next_cursor) {
      requireTrue(result.job.phase === "undone", "Undo did not terminate");
      if (firstReceipt.result.next_cursor) {
        same(await p.rpc(owner, "undo_library_import_chunk_v2", firstReceipt.body), firstReceipt.result, "Earlier Undo receipt changed after later compensation");
        same(await p.rpc(owner, "import_job_status_v2", { p_job_id: job.jobId }), result.job, "Earlier Undo replay changed terminal status or Home revisions");
      }
      return result;
    }
    requireTrue(result.next_cursor !== cursor, "Undo cursor did not advance");
    cursor = result.next_cursor;
  }
  throw new Error("Undo exceeded this probe's four-page limit");
}
async function importChecks(p) {
  // Administrative read permission on every cleanup surface is established before signup.
  const absent = randomUUID();
  for (const [table, column] of [["library_import_jobs", "user_id"], ["library_import_items", "job_id"], ["library_import_baselines", "job_id"], ["anime_user_lists", "user_id"], ["manga_user_lists", "user_id"]]) {
    const rows = await p.must(`/rest/v1/${table}?${column}=eq.${absent}&select=*&limit=1`, { admin: true });
    requireTrue(Array.isArray(rows) && rows.length === 0, "Administrative cleanup preflight failed");
  }
  p.evidence.cleanupDatabasePreflight = "PASS";
  const owner = await p.provision("import-v2-owner"), outsider = await p.provision("import-v2-outsider");
  const titles = [];
  for (const medium of ["anime", "manga"]) {
    const candidates = await p.must(`/rest/v1/${medium}?select=id,anilist_id,mal_id,title_romaji&anilist_id=not.is.null&mal_id=not.is.null&order=id.asc&limit=8`, { token: owner.token });
    requireTrue(Array.isArray(candidates), "Catalog read failed");
    const selected = candidates.filter((item) => Number.isSafeInteger(item.id) && item.id > 0 && Number.isSafeInteger(item.anilist_id) && item.anilist_id > 0 && Number.isSafeInteger(item.mal_id) && item.mal_id > 0).slice(0, 2);
    requireTrue(selected.length === 2, `Two existing ${medium} provider identities are required`);
    titles.push(...selected.map((item, index) => ({ ...item, medium, index })));
  }
  p.evidence.catalog = titles;
  const existing = titles.filter((item) => item.index === 0), fresh = titles.filter((item) => item.index === 1);
  const baseline = (medium) => ({ status: medium === "anime" ? "watching" : "reading", progress: 2, notes: "Kuro disposable baseline", score_raw: "8", score_scale: "MAL_10", repeat_count: 1, private: true, custom_lists: ["Kuro test"], started_raw: "2025-01", ...(medium === "manga" ? { volumes_progress: 1 } : {}) });
  const incoming = (medium) => ({ ...baseline(medium), status: "on_hold", progress: 7, notes: "Disposable provider note", score_raw: "6", private: false, custom_lists: ["Provider test"], ...(medium === "manga" ? { volumes_progress: 3 } : {}) });
  const seed = await start(p, owner, "anilist", "seed");
  const initial = await stage(p, owner, seed, existing.map((title) => source(title, "anilist", baseline(title.medium))));
  for (const title of existing) requireTrue(initial.find((item) => item.medium === title.medium)?.media_id === title.id, "Provider namespace resolved the wrong catalog identity");
  requireTrue(initial.every((item) => item.disposition === "new" && item.current === null), "New owner unexpectedly has tracked entries");
  requireTrue((await apply(p, owner, seed, initial.map((item) => decision(item, "add")), true)).counts.added === 2, "Both-media seed did not add two entries");
  await finish(p, owner, seed);
  const original = await readLists(p, owner);
  for (const title of existing) {
    const actual = row(original, title);
    requireTrue(actual && Number.isSafeInteger(actual.server_revision) && actual.server_revision > 0 &&
      typeof actual.lifecycle_id === "string" && /^[0-9a-f-]{36}$/i.test(actual.lifecycle_id), "Seed did not establish real revision/lifecycle identity");
    const supplied = { list_type: title.medium === "anime" ? "WATCHING" : "READING", progress: 2,
      notes: "Kuro disposable baseline", rating: 8, score_raw: 8, score_scale: "MAL_10", repeat_count: 1,
      entry_private: true, source_custom_lists: ["Kuro test"], started_raw: "2025-01",
      ...(title.medium === "manga" ? { volumes_progress: 1 } : {}) };
    same(Object.fromEntries(Object.keys(supplied).map((key) => [key, actual[key]])), supplied,
      "Initial import dropped supplied tracking/score/private/source metadata");
  }

  const statusBefore = await p.rpc(owner, "import_job_status_v2", { p_job_id: seed.jobId });
  for (const [rpc, body] of [["import_job_status_v2", { p_job_id: seed.jobId }], ["import_items_page_v2", { p_job_id: seed.jobId, p_limit: 50 }], ["cancel_library_import_v2", { p_job_id: seed.jobId }], ["apply_import_chunk_v2", { p_job_id: seed.jobId, p_action_id: seed.actionId, p_decisions: initial.map((item) => decision(item, "add")) }], ["undo_library_import_chunk_v2", { p_job_id: seed.jobId, p_action_id: `outsider-${randomUUID()}`, p_limit: 1 }]]) {
    reject(await p.request(`/rest/v1/rpc/${rpc}`, { token: outsider.token, method: "POST", body }), "NOT_AUTHORIZED");
  }
  requireTrue((await p.rpc(outsider, "import_jobs_page_v2", { p_limit: 50 })).jobs.length === 0, "Outsider job discovery exposed owner results");
  same(await p.rpc(owner, "import_job_status_v2", { p_job_id: seed.jobId }), statusBefore, "Denied outsider calls changed the owner job");
  same(await readLists(p, owner), original, "Denied outsider calls changed tracking");

  const keep = await start(p, owner, "myanimelist", "keep");
  const keepReview = await stage(p, owner, keep, existing.map((title) => source(title, "myanimelist", incoming(title.medium))));
  requireTrue(keepReview.every((item) => item.current && item.disposition === "changes"), "Existing changes were not reviewable");
  requireTrue((await apply(p, owner, keep, keepReview.map((item) => decision(item, "keep")), true)).counts.unchanged === 2, "Default Keep did not count unchanged entries");
  same(await readLists(p, owner), original, "Default Keep replaced Kuro values");
  await finish(p, owner, keep);

  const update = await start(p, owner, "myanimelist", "updates");
  const updateReview = await stage(p, owner, update, existing.map((title) => source(title, "myanimelist", incoming(title.medium))));
  requireTrue(updateReview.every((item) => item.changed_fields.includes("status") && item.changed_fields.includes("progress")), "The chosen explicit fields were not changes");
  const approved = updateReview.map((item) => decision(item, "update", ["status", "progress"]));
  requireTrue((await apply(p, owner, update, approved, true)).counts.updated === 2, "Explicit updates did not commit both media");
  const rewritten = approved.map((item) => ({ ...item, fields: ["notes"] }));
  reject(await p.request("/rest/v1/rpc/apply_import_chunk_v2", { token: owner.token, method: "POST", body: { p_job_id: update.jobId, p_action_id: update.actionId, p_decisions: rewritten } }), "DECISION_ALREADY_FINAL");
  const changed = await readLists(p, owner);
  for (const title of existing) {
    const actual = row(changed, title), before = row(original, title);
    requireTrue(actual?.list_type === "PAUSED" && actual.progress === 7, "Approved status/progress did not persist");
    same(fields(actual, title.medium), { ...fields(before, title.medium), list_type: "PAUSED", progress: 7 }, "Explicit updates replaced unapproved metadata");
  }
  await finish(p, owner, update);

  const conflict = await start(p, owner, "myanimelist", "conflict");
  const conflictReview = await stage(p, owner, conflict, existing.map((title) => source(title, "myanimelist", { ...incoming(title.medium), progress: 9 })));
  const anime = existing.find((title) => title.medium === "anime");
  // Same authenticated PATCH used by the app's notes writer, scoped to this new owner's exact row.
  const edited = await p.must(`/rest/v1/anime_user_lists?user_id=eq.${owner.userId}&anime_id=eq.${anime.id}&select=${columns}`, { token: owner.token, method: "PATCH", headers: { Prefer: "return=representation" }, body: { notes: "Later deliberate Kuro edit" } });
  requireTrue(Array.isArray(edited) && edited.length === 1 && edited[0].server_revision > row(changed, anime).server_revision, "Later edit did not advance the actual revision");
  const afterEdit = await readLists(p, owner);
  const conflicted = await apply(p, owner, conflict, conflictReview.map((item) => decision(item, item.medium === "anime" ? "update" : "keep", item.medium === "anime" ? ["progress"] : [])), true);
  requireTrue(conflicted.counts.conflict === 1 && conflicted.counts.unchanged === 1, "A post-review edit was not a guarded conflict");
  same(await readLists(p, owner), afterEdit, "Conflict changed later Kuro edits");
  await finish(p, owner, conflict);
  const compensated = await undo(p, owner, update);
  requireTrue(compensated.reverted === 1 && compensated.skipped === 1, "Undo did not skip the edited lifetime and restore the untouched one");
  const afterUndo = await readLists(p, owner);
  same(row(afterUndo, anime), row(afterEdit, anime), "Undo overwrote the later edit");
  const manga = existing.find((title) => title.medium === "manga");
  same(fields(row(afterUndo, manga), "manga"), fields(row(original, manga), "manga"), "Undo did not restore the actual before-image");

  const partial = await start(p, owner, "anilist", "partial-stop");
  const partialReview = await stage(p, owner, partial, fresh.map((title) => source(title, "anilist", baseline(title.medium))));
  requireTrue(partialReview.every((item) => item.disposition === "new"), "Fresh sample is already tracked or unresolved");
  const first = partialReview.find((item) => item.medium === "anime");
  const partialDecision = [decision(first, "add")];
  const partialApply = await apply(p, owner, partial, partialDecision, true);
  requireTrue(partialApply.counts.added === 1 && partialApply.counts.pending === 1, "Partial Apply did not retain the second stream item");
  const stopped = await p.rpc(owner, "cancel_library_import_v2", { p_job_id: partial.jobId });
  requireTrue(stopped.phase === "cancelled" && stopped.counts.added === 1 && stopped.undo_available, "Stop discarded committed effects");
  same(await p.rpc(owner, "import_job_status_v2", { p_job_id: partial.jobId }), stopped, "Stopped result was not durable");
  same(await apply(p, owner, partial, partialDecision), partialApply, "Original Apply receipt changed after Stop");
  same(await p.rpc(owner, "import_job_status_v2", { p_job_id: partial.jobId }), stopped, "Apply receipt replay reopened stopped work");
  const stoppedLists = await readLists(p, owner);
  requireTrue(row(stoppedLists, fresh.find((title) => title.medium === "anime")) && !row(stoppedLists, fresh.find((title) => title.medium === "manga")), "Stop applied unapproved remaining work");
  requireTrue((await undo(p, owner, partial)).reverted === 1, "Stopped partial import could not be compensated");
  requireTrue(!row(await readLists(p, owner), fresh.find((title) => title.medium === "anime")), "Partial Undo retained its added title");
  const jobs = await p.rpc(owner, "import_jobs_page_v2", { p_limit: 50 });
  requireTrue(jobs.jobs.length === p.journals.length && p.journals.every((job) => jobs.jobs.some((item) => item.job_id === job.jobId)), "Persistent result discovery lost a recorded job");
  return { importWorkflowV2: "PASS", proofs: ["provider namespaces/both media", "stage without Library writes", "paged review/current baselines", "default Keep", "explicit fields", "immutable Apply/Undo receipts", "revision conflict", "persistent results", "partial Stop/Undo", "outsider denial"], nativeOrchestration: "NOT_RUN", providerAccountIngestion: "NOT_RUN", nativeProjectionPublication: "NOT_RUN" };
}
async function verifyCleanup(p, report) {
  const proof = []; report.importCleanup = proof;
  for (const account of p.accounts) {
    if (!account.userId) { proof.push({ userId: null, status: "BLOCKED" }); continue; }
    for (const [table, select] of [["library_import_jobs", "id"], ["anime_user_lists", "anime_id"], ["manga_user_lists", "manga_id"]]) {
      const rows = await p.must(`/rest/v1/${table}?user_id=eq.${account.userId}&select=${select}`, { admin: true });
      proof.push({ userId: account.userId, table, remaining: Array.isArray(rows) ? rows.length : null });
      requireTrue(Array.isArray(rows) && rows.length === 0, "App deletion left an exact disposable account resource");
    }
  }
  for (const job of p.journals.filter((entry) => entry.jobId)) {
    for (const table of ["library_import_items", "library_import_baselines"]) {
      const rows = await p.must(`/rest/v1/${table}?job_id=eq.${job.jobId}&select=job_id&limit=1`, { admin: true });
      proof.push({ jobId: job.jobId, table, remaining: Array.isArray(rows) ? rows.length : null });
      requireTrue(Array.isArray(rows) && rows.length === 0, "App deletion left an exact job child resource");
    }
  }
  report.cleanup.push({ type: "import-resources", status: "PASS", reason: "Administrative exact-owner/job absence after app deletion" });
}
async function run(options = {}) {
  const report = await runAdminProbe(options, importChecks, verifyCleanup);
  // No credential material or its fingerprint is part of this producer's output.
  for (const entry of report.protocol || []) delete entry.credentialSha256;
  return report;
}
if (require.main === module) run().then((report) => { console.log(JSON.stringify(report, null, 2)); process.exitCode = report.exitCode; })
  .catch(() => { console.error("Import v2 probe failed before a sanitized report could be emitted"); process.exitCode = 1; });
module.exports = { run, importChecks, verifyCleanup };
