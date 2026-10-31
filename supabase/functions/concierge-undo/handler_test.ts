// Handler tests for concierge-undo. Sessions are produced by the REAL concierge-apply handler and
// undone by the REAL undo handler (handler.ts + undo_plan.ts), both against the in-memory Supabase
// fake (../_shared/test_fake_supabase.ts), which models the CONTRACT of the `apply_import_session` /
// `undo_import_session` transactions (atomic per call, compare-and-revert). The SQL is tested against
// PostgreSQL in supabase/tests/rls/70_import_apply_undo_transactions.sql (including the two-session
// race). NOT a test against Supabase.
// Run: deno test --no-prompt supabase/functions/concierge-undo/
import { strict as assert } from "node:assert";
import { handleUndo } from "./handler.ts";
import { handleApply } from "../concierge-apply/handler.ts";
import { conciergeSchema, FakeSupabase, type Row } from "../_shared/test_fake_supabase.ts";

const USER = "11111111-1111-4111-8111-111111111111";
const OTHER = "22222222-2222-4222-8222-222222222222";

function platform(db: FakeSupabase) {
  return { client: () => db, serviceClient: () => db };
}

function post(path: string, body: unknown): Request {
  return new Request(`https://example.test/functions/v1/${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer jwt" },
    body: JSON.stringify(body),
  });
}

async function apply(db: FakeSupabase, items: unknown[]) {
  const res = await handleApply(post("concierge-apply", { items }), platform(db));
  const body = await res.json();
  assert.equal(res.status, 200, JSON.stringify(body));
  assert.equal(body.undoable, true, JSON.stringify(body));
  return body.sessionId as string;
}

async function undo(db: FakeSupabase, body: unknown) {
  const res = await handleUndo(post("concierge-undo", body), platform(db));
  return { status: res.status, headers: res.headers, body: await res.json() };
}

function animeRow(db: FakeSupabase, user: string, id: number): Row | undefined {
  return db.rows("anime_user_lists").find((r) => r.user_id === user && r.anime_id === id);
}

/** The user edits their own row after the import (outside any import context). */
function edit(db: FakeSupabase, id: number, patch: Row) {
  const row = db.tables.get("anime_user_lists")?.find((r) => r.user_id === USER && r.anime_id === id);
  assert.ok(row, `row ${id} exists`);
  Object.assign(row, patch);
}

Deno.test("undo of an add deletes the row inside the taste import context of the undone session", async () => {
  const db = new FakeSupabase(conciergeSchema(), USER);
  const sessionId = await apply(db, [
    { mediaType: "ANIME", mediaId: 42, status: "PLANNING", action: "add" },
    { mediaType: "MANGA", mediaId: 42, status: "READING", action: "add", progressChapters: 10 },
  ]);
  const { status, body } = await undo(db, { sessionId });
  assert.equal(status, 200);
  assert.deepEqual(body, {
    success: true,
    sessionId,
    reverted: [
      { mediaType: "ANIME", mediaId: 42, undoType: "deleted" },
      { mediaType: "MANGA", mediaId: 42, undoType: "deleted" },
    ],
    skipped: [],
    warnings: [],
    errors: [],
    status: "undone",
  });
  assert.deepEqual([db.rows("anime_user_lists"), db.rows("manga_user_lists")], [[], []]);
  const deletes = db.ops.filter((o) => o.op === "delete");
  // executed last item first (review A1); `reverted` above stays in request order
  assert.deepEqual(deletes.map((d) => d.table), ["manga_user_lists", "anime_user_lists"]);
  // The DELETE of a fresh PLANNING row is what taste_capture turns into
  // 'planned_add_removed_quickly'; it must be marked as import-origin like the add was.
  for (const d of deletes) assert.equal(d.importContext, sessionId);
  assert.equal(db.importContext, null, "context does not outlive the transaction");
  assert.equal(db.rows("import_sessions")[0].status, "cancelled");
});

Deno.test("undo of an update restores the before-values and keeps later edits of fields the import never wrote", async () => {
  const db = new FakeSupabase(conciergeSchema(), USER);
  db.seed("anime_user_lists", [{ user_id: USER, anime_id: 7, list_type: "WATCHING", progress: 3, rating: 8, notes: "mine", verdict: "OKAY" }]);
  const sessionId = await apply(db, [{
    mediaType: "ANIME", mediaId: 7, status: "WATCHING", action: "update", progressEpisodes: 5, expectedExisting: { status: "WATCHING", progress_episodes: 3 },
  }]);
  edit(db, 7, { notes: "edited after import" });
  const { body } = await undo(db, { sessionId });
  assert.deepEqual(body.reverted, [{ mediaType: "ANIME", mediaId: 7, undoType: "restored", fields: ["list_type", "progress"] }]);
  assert.deepEqual(body.skipped, []);
  assert.deepEqual(animeRow(db, USER, 7), { user_id: USER, anime_id: 7, list_type: "WATCHING", progress: 3, rating: 8, notes: "edited after import", verdict: "OKAY" });
});

Deno.test("F08: later edits of written fields (rating, notes, progress) survive Undo and are reported; untouched written fields revert", async () => {
  const db = new FakeSupabase(conciergeSchema(), USER);
  db.seed("anime_user_lists", [
    { user_id: USER, anime_id: 1, list_type: "WATCHING", progress: 3, rating: 8, notes: "original", verdict: null },
    { user_id: USER, anime_id: 2, list_type: "WATCHING", progress: 3, rating: 8, notes: "original", verdict: null },
    { user_id: USER, anime_id: 3, list_type: "WATCHING", progress: 3, rating: 8, notes: "original", verdict: null },
  ]);
  const update = (id: number) => ({
    mediaType: "ANIME", mediaId: id, status: "WATCHING", action: "update", progressEpisodes: 5, rating: 9, notes: "imported",
    expectedExisting: { status: "WATCHING", progress_episodes: 3 },
  });
  const sessionId = await apply(db, [update(1), update(2), update(3)]);
  edit(db, 1, { rating: 10 });
  edit(db, 2, { notes: "my later note" });
  edit(db, 3, { progress: 6 });
  const { status, body } = await undo(db, { sessionId });
  assert.equal(status, 200);
  assert.deepEqual(
    [1, 2, 3].map((id) => {
      const r = animeRow(db, USER, id);
      return [r?.list_type, r?.progress, r?.rating, r?.notes];
    }),
    [
      ["WATCHING", 3, 10, "original"],
      ["WATCHING", 3, 8, "my later note"],
      ["WATCHING", 6, 8, "original"],
    ],
  );
  assert.deepEqual(body.skipped, [
    { mediaType: "ANIME", mediaId: 1, reason: "edited_since_import", fields: ["rating"] },
    { mediaType: "ANIME", mediaId: 2, reason: "edited_since_import", fields: ["notes"] },
    { mediaType: "ANIME", mediaId: 3, reason: "edited_since_import", fields: ["progress"] },
  ]);
  assert.equal(db.rows("import_sessions")[0].status, "cancelled");
});

Deno.test("F09: a row deleted after an update import stays deleted and the skip is explained", async () => {
  const db = new FakeSupabase(conciergeSchema(), USER);
  db.seed("anime_user_lists", [{ user_id: USER, anime_id: 7, list_type: "WATCHING", progress: 3, rating: 8, notes: "original", verdict: null }]);
  const sessionId = await apply(db, [{
    mediaType: "ANIME", mediaId: 7, status: "WATCHING", action: "update", progressEpisodes: 5, rating: 9, expectedExisting: { status: "WATCHING", progress_episodes: 3 },
  }]);
  db.tables.set("anime_user_lists", []);
  const { status, body } = await undo(db, { sessionId });
  assert.equal(status, 200);
  assert.deepEqual([body.reverted, body.skipped], [[], [{ mediaType: "ANIME", mediaId: 7, reason: "deleted_since_import" }]]);
  assert.deepEqual(db.rows("anime_user_lists"), []);
});

Deno.test("A1: [add 3, update 5] on one title in one batch: Undo unwinds the last write first and removes the row", async () => {
  const db = new FakeSupabase(conciergeSchema(), USER);
  const sessionId = await apply(db, [
    { mediaType: "ANIME", mediaId: 70, status: "WATCHING", action: "add", progressEpisodes: 3 },
    { mediaType: "ANIME", mediaId: 70, status: "WATCHING", action: "update", progressEpisodes: 5 },
  ]);
  const { status, body } = await undo(db, { sessionId });
  assert.equal(status, 200);
  assert.deepEqual([body.reverted, body.skipped], [[
    { mediaType: "ANIME", mediaId: 70, undoType: "deleted" },
    { mediaType: "ANIME", mediaId: 70, undoType: "restored", fields: ["list_type", "progress"] },
  ], []]);
  assert.equal(animeRow(db, USER, 70), undefined);
});

Deno.test("F13: a failed Undo is HTTP 500 retryable, rolls back and stays undoable; the retry completes; a further retry is idempotent", async () => {
  const db = new FakeSupabase(conciergeSchema(), USER);
  const sessionId = await apply(db, [
    { mediaType: "ANIME", mediaId: 7, status: "PLANNING", action: "add" },
    { mediaType: "ANIME", mediaId: 8, status: "PLANNING", action: "add" },
  ]);
  db.faults.set("anime_user_lists:delete", "transient delete failure");
  const failed = await undo(db, { sessionId });
  assert.equal(failed.status, 500);
  assert.deepEqual(failed.body, { error: "Undo could not be completed", status: "failed", retryable: true });
  assert.equal(db.rows("anime_user_lists").length, 2, "nothing reverted");
  assert.equal(db.rows("import_sessions")[0].status, "applied", "still undoable");

  db.faults.clear();
  const retry = await undo(db, { sessionId });
  assert.equal(retry.status, 200);
  assert.equal(retry.body.reverted.length, 2);
  assert.deepEqual([db.rows("anime_user_lists"), db.rows("import_sessions")[0].status], [[], "cancelled"]);

  const again = await undo(db, { sessionId });
  assert.deepEqual([again.status, again.body.status, again.body.reverted], [200, "undone", []]);
});

Deno.test("F78: only the exact deletion barrier is a non-retryable 403; other RPC errors stay retryable", async () => {
  for (const [error, expectedStatus] of [
    [{ code: "42501", message: "ACCOUNT_DELETION_IN_PROGRESS" }, 403],
    [{ code: "42501", message: "permission denied for table anime_user_lists" }, 500],
    [{ code: "XX000", message: "ACCOUNT_DELETION_IN_PROGRESS" }, 500],
  ] as const) {
    const db = new FakeSupabase(conciergeSchema(), USER);
    const sessionId = await apply(db, [{ mediaType: "ANIME", mediaId: 7, status: "PLANNING", action: "add" }]);
    const before = db.rows("anime_user_lists");
    const logsBefore = db.calls("log_concierge_run").length;
    const transactionCalls: string[] = [];
    const res = await handleUndo(post("concierge-undo", { sessionId }), {
      client: () => db, serviceClient: () => ({ rpc: (name: string) => {
        transactionCalls.push(name);
        return Promise.resolve({ data: null, error });
      } }),
    });
    const body = await res.json();
    assert.equal(res.status, expectedStatus);
    if (expectedStatus === 403) {
      assert.deepEqual(body, {
        error: "This account is being deleted. Imports can no longer be undone.",
        code: "ACCOUNT_DELETION_IN_PROGRESS", status: "failed", retryable: false,
      });
    } else {
      assert.deepEqual(body, { error: "Undo could not be completed", status: "failed", retryable: true });
    }
    assert.deepEqual(transactionCalls, ["undo_import_session"]);
    assert.deepEqual(db.rows("anime_user_lists"), before);
    assert.equal(db.rows("import_sessions")[0].status, "applied");
    assert.equal(db.calls("log_concierge_run").length, logsBefore);
  }
});

Deno.test("F32: a limiter error is HTTP 503 and nothing is reverted; an explicit denial stays 429", async () => {
  const db = new FakeSupabase(conciergeSchema(), USER);
  const sessionId = await apply(db, [{ mediaType: "ANIME", mediaId: 7, status: "PLANNING", action: "add" }]);
  const writes = db.ops.length;
  db.rateLimitError = { message: "rate-limit database unavailable" };
  const failed = await undo(db, { sessionId });
  assert.deepEqual([failed.status, failed.headers.get("Retry-After"), failed.body.error], [503, "30", "Rate limiter unavailable"]);
  db.rateLimitError = null;
  db.rateLimit = { allowed: false, retry_after_s: 5 };
  const denied = await undo(db, { sessionId });
  assert.deepEqual([denied.status, denied.headers.get("Retry-After")], [429, "5"]);
  assert.deepEqual(db.calls("undo_import_session"), []);
  assert.equal(db.ops.length, writes);
  assert.equal(animeRow(db, USER, 7)?.list_type, "PLANNING");
});

Deno.test("identity: another user's session id is reported as not found and their rows stay", async () => {
  const otherDb = new FakeSupabase(conciergeSchema(), OTHER);
  const otherSession = await apply(otherDb, [{ mediaType: "ANIME", mediaId: 5, status: "PLANNING", action: "add" }]);
  // Same storage, now called with USER's JWT and OTHER's session id in the body.
  const asUser = new FakeSupabase(conciergeSchema(), USER);
  asUser.tables = otherDb.tables;
  const { status, body } = await undo(asUser, { sessionId: otherSession, userId: OTHER });
  assert.equal(status, 404);
  assert.deepEqual(body, { error: "No applied session to undo" });
  assert.equal((asUser.calls("undo_import_session")[0].args as Row).p_user_id, USER);
  assert.equal(animeRow(asUser, OTHER, 5)?.list_type, "PLANNING");
  assert.equal(asUser.ops.length, 0);
});

Deno.test("only the most recent applied session can be undone (409); a malformed sessionId is 400 without a transaction call", async () => {
  const db = new FakeSupabase(conciergeSchema(), USER);
  const older = await apply(db, [{ mediaType: "ANIME", mediaId: 1, status: "PLANNING", action: "add" }]);
  await apply(db, [{ mediaType: "ANIME", mediaId: 2, status: "PLANNING", action: "add" }]);
  const refused = await undo(db, { sessionId: older });
  assert.deepEqual([refused.status, refused.body], [409, { error: "Can only undo the most recent import session" }]);
  assert.equal(animeRow(db, USER, 1)?.list_type, "PLANNING");

  const calls = db.calls("undo_import_session").length;
  for (const sessionId of [undefined, 42, "not-a-uuid"]) {
    const res = await undo(db, { sessionId });
    assert.equal(res.status, 400, JSON.stringify(sessionId));
  }
  assert.equal(db.calls("undo_import_session").length, calls);
});
