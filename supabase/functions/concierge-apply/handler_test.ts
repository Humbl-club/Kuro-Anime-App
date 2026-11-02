// Handler tests for concierge-apply. They run the REAL handler (handler.ts) and the REAL policy
// (apply_plan.ts) against the in-memory Supabase fake (../_shared/test_fake_supabase.ts). The fake
// models PostgREST/PostgreSQL constraints and the CONTRACT of the `apply_import_session` /
// `undo_import_session` transactions (atomic per call); the SQL itself is tested against PostgreSQL
// in supabase/tests/rls/70_import_apply_undo_transactions.sql. NOT a test against Supabase.
// Run: deno test --no-prompt supabase/functions/concierge-apply/
import { strict as assert } from "node:assert";
import { handleApply } from "./handler.ts";
import { normalizeRating } from "./apply_plan.ts";
import { handleUndo } from "../concierge-undo/handler.ts";
import { conciergeSchema, FakeSupabase, type Row } from "../_shared/test_fake_supabase.ts";

const USER = "11111111-1111-4111-8111-111111111111";
const OTHER = "22222222-2222-4222-8222-222222222222";

function newDb(user: string | null = USER): FakeSupabase {
  return new FakeSupabase(conciergeSchema(), user);
}

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

async function apply(db: FakeSupabase, body: unknown) {
  const res = await handleApply(post("concierge-apply", body), platform(db));
  return { status: res.status, headers: res.headers, body: await res.json() };
}

async function undo(db: FakeSupabase, sessionId: string) {
  const res = await handleUndo(post("concierge-undo", { sessionId }), platform(db));
  return { status: res.status, body: await res.json() };
}

function listRow(db: FakeSupabase, table: "anime_user_lists" | "manga_user_lists", user: string, id: number): Row | undefined {
  const col = table === "anime_user_lists" ? "anime_id" : "manga_id";
  return db.rows(table).find((r) => r.user_id === user && r[col] === id);
}

/** Writes the handler issued itself through the table API (only the optional title alias is allowed). */
function directWrites(db: FakeSupabase) {
  return db.ops.filter((o) => o.via === "table");
}

function plannedItems(db: FakeSupabase): Row[] {
  const [call] = db.calls("apply_import_session");
  return ((call?.args as Row)?.p_items ?? []) as Row[];
}

Deno.test("valid add: one transaction call, a new row with only the provided fields (progress 0, never null), journaled, undoable", async () => {
  const db = newDb();
  const { status, body } = await apply(db, { items: [{ mediaType: "ANIME", mediaId: 7, status: "PLANNING", action: "add", raw: "Frieren" }] });
  assert.equal(status, 200);
  assert.deepEqual(body, {
    success: true,
    sessionId: body.sessionId,
    applied: [{ mediaType: "ANIME", mediaId: 7, status: "PLANNING", action: "add" }],
    skipped: [],
    conflicts: [],
    errors: [],
    status: "applied",
    undoable: true,
    replayed: false,
  });
  assert.equal(db.calls("apply_import_session").length, 1);
  assert.equal((db.calls("apply_import_session")[0].args as Row).p_user_id, USER);
  assert.deepEqual(
    { ...listRow(db, "anime_user_lists", USER, 7) },
    { user_id: USER, anime_id: 7, list_type: "PLANNING", progress: 0, rating: null, notes: null, verdict: null },
  );
  const item = db.rows("import_session_items")[0];
  assert.deepEqual(item.after_values, { list_type: "PLANNING", progress: 0, rating: null, notes: null, verdict: null });
  assert.equal(db.rows("import_sessions")[0].status, "applied");
  assert.deepEqual(directWrites(db).map((o) => o.table), ["title_aliases"], "list/journal/session writes only inside the transaction");
});

Deno.test("valid update: only status/progress the item carries change; rating, notes and verdict stay; journal keeps before and after", async () => {
  const db = newDb();
  db.seed("anime_user_lists", [{ user_id: USER, anime_id: 7, list_type: "WATCHING", progress: 3, rating: 8, notes: "rewatch with friends", verdict: "MASTERPIECE" }]);
  const { body } = await apply(db, {
    items: [{ mediaType: "ANIME", mediaId: 7, status: "WATCHING", action: "update", progressEpisodes: 5, expectedExisting: { status: "WATCHING", progress_episodes: 3 } }],
  });
  assert.equal(body.success, true);
  assert.equal(body.status, "applied");
  assert.deepEqual(
    { ...listRow(db, "anime_user_lists", USER, 7) },
    { user_id: USER, anime_id: 7, list_type: "WATCHING", progress: 5, rating: 8, notes: "rewatch with friends", verdict: "MASTERPIECE" },
  );
  const item = db.rows("import_session_items")[0];
  assert.deepEqual(item.previous_values, { list_type: "WATCHING", progress: 3, rating: 8, notes: "rewatch with friends", verdict: "MASTERPIECE" });
  assert.deepEqual(item.after_values, { list_type: "WATCHING", progress: 5 });
});

Deno.test("planned item wire shape (the p_items contract the SQL test 70_import_apply_undo_transactions.sql uses)", async () => {
  const db = newDb();
  db.seed("anime_user_lists", [{ user_id: USER, anime_id: 21, list_type: "WATCHING", progress: 3, rating: null, notes: null, verdict: null }]);
  await apply(db, {
    idempotencyKey: "0b9f2c1e-5a43-4e57-9d0c-7f1d2e3a4b5c",
    items: [
      { mediaType: "ANIME", mediaId: 11, status: "watching", action: "add", raw: "Mob S2E5", seasonNumber: 2, episodeInSeason: 5, progressEpisodes: 17, rating: 8.5, confidence: 0.92, candidates: [{ media_id: 11 }] },
      { mediaType: "ANIME", mediaId: 21, status: "COMPLETED", action: "update", notes: "loved it", expectedExisting: { status: "WATCHING", progress_episodes: 3 }, progressEpisodes: 12 },
      { mediaType: "MANGA", mediaId: 9, status: "READING", action: "skip", raw: "skip me", parsed: { status: "READING" } },
    ],
  });
  const [call] = db.calls("apply_import_session");
  assert.equal((call.args as Row).p_idempotency_key, "0b9f2c1e-5a43-4e57-9d0c-7f1d2e3a4b5c");
  assert.match(String((call.args as Row).p_session_id), /^[0-9a-f-]{36}$/);
  assert.deepEqual(plannedItems(db), [
    {
      media_type: "ANIME",
      media_id: 11,
      import_action: "add",
      expected: null,
      insert_values: { list_type: "WATCHING", progress: 17, rating: 8, notes: "S2E5" },
      update_values: { list_type: "WATCHING", progress: 17, rating: 8 },
      journal: {
        raw: "Mob S2E5",
        candidates: [{ media_id: 11 }],
        confidence: 0.92,
        parsed: { status: "WATCHING", progressEpisodes: 17, seasonNumber: 2, episodeInSeason: 5, caughtUp: null, lastEpisode: null },
      },
    },
    {
      media_type: "ANIME",
      media_id: 21,
      import_action: "update",
      expected: { list_type: "WATCHING", progress: 3 },
      insert_values: { list_type: "COMPLETED", progress: 12, notes: "loved it" },
      update_values: { list_type: "COMPLETED", progress: 12, notes: "loved it" },
      journal: {
        raw: "ANIME:21",
        candidates: [],
        confidence: 0,
        parsed: { status: "COMPLETED", progressEpisodes: 12, seasonNumber: null, episodeInSeason: null, caughtUp: null, lastEpisode: null },
      },
    },
    {
      media_type: "MANGA",
      media_id: 9,
      import_action: "skip",
      expected: null,
      journal: { raw: "skip me", candidates: [], confidence: 0, parsed: { status: "READING" } },
    },
  ]);
});

Deno.test("F15: the S{n}E{m} annotation is only a NEW row's notes; existing authored notes survive the import and its Undo", async () => {
  const db = newDb();
  db.seed("anime_user_lists", [{ user_id: USER, anime_id: 21, list_type: "WATCHING", progress: 3, rating: 8, notes: "my own note", verdict: null }]);
  const { body } = await apply(db, {
    items: [
      { mediaType: "ANIME", mediaId: 21, status: "WATCHING", action: "update", seasonNumber: 2, episodeInSeason: 5, progressEpisodes: 5, expectedExisting: { status: "WATCHING", progress_episodes: 3 } },
      { mediaType: "ANIME", mediaId: 22, status: "WATCHING", action: "add", seasonNumber: 2, episodeInSeason: 5, progressEpisodes: 5 },
    ],
  });
  assert.equal(body.status, "applied");
  assert.deepEqual([listRow(db, "anime_user_lists", USER, 21)?.notes, listRow(db, "anime_user_lists", USER, 21)?.progress], ["my own note", 5]);
  assert.equal(listRow(db, "anime_user_lists", USER, 22)?.notes, "S2E5", "a new row still gets the structural annotation");
  const undone = await undo(db, body.sessionId);
  assert.equal(undone.status, 200);
  assert.deepEqual(
    { ...listRow(db, "anime_user_lists", USER, 21) },
    { user_id: USER, anime_id: 21, list_type: "WATCHING", progress: 3, rating: 8, notes: "my own note", verdict: null },
  );
  assert.equal(listRow(db, "anime_user_lists", USER, 22), undefined);
});

Deno.test("F15: explicit notes still apply, and Undo restores the previous notes", async () => {
  const db = newDb();
  db.seed("anime_user_lists", [{ user_id: USER, anime_id: 23, list_type: "WATCHING", progress: 3, rating: null, notes: "before", verdict: null }]);
  const { body } = await apply(db, {
    items: [{ mediaType: "ANIME", mediaId: 23, status: "WATCHING", action: "update", notes: "explicit edit", seasonNumber: 1, episodeInSeason: 4, progressEpisodes: 4 }],
  });
  assert.equal(listRow(db, "anime_user_lists", USER, 23)?.notes, "explicit edit");
  await undo(db, body.sessionId);
  assert.deepEqual([listRow(db, "anime_user_lists", USER, 23)?.notes, listRow(db, "anime_user_lists", USER, 23)?.progress], ["before", 3]);
});

Deno.test("F10: a journal failure inside the transaction is HTTP 500 retryable, nothing is committed and the handler wrote nothing itself", async () => {
  const db = newDb();
  db.faults.set("import_session_items:insert", "injected journal failure");
  const { status, body } = await apply(db, {
    idempotencyKey: "retry-key-1",
    items: [{ mediaType: "ANIME", mediaId: 7, status: "PLANNING", action: "add", raw: "Frieren" }],
  });
  assert.equal(status, 500);
  assert.deepEqual(body, { error: "Import could not be saved", status: "failed", retryable: true });
  assert.deepEqual([db.rows("anime_user_lists"), db.rows("import_sessions"), db.rows("import_session_items")], [[], [], []]);
  assert.deepEqual(directWrites(db), [], "no optional effect runs for an uncommitted Apply");
  // The same request after the fault clears is a fresh, complete Apply (nothing to replay).
  db.faults.clear();
  const retry = await apply(db, { idempotencyKey: "retry-key-1", items: [{ mediaType: "ANIME", mediaId: 7, status: "PLANNING", action: "add", raw: "Frieren" }] });
  assert.deepEqual([retry.status, retry.body.status, retry.body.replayed, db.rows("import_session_items").length], [200, "applied", false, 1]);
});

Deno.test("F11: a session-finalisation failure is HTTP 500 retryable and nothing is committed", async () => {
  const db = newDb();
  db.faults.set("import_sessions:update", "injected finalisation failure");
  const { status, body } = await apply(db, { items: [{ mediaType: "MANGA", mediaId: 9, status: "READING", action: "add" }] });
  assert.equal(status, 500);
  assert.deepEqual(body, { error: "Import could not be saved", status: "failed", retryable: true });
  assert.deepEqual([db.rows("manga_user_lists"), db.rows("import_sessions"), db.rows("import_session_items")], [[], [], []]);
  assert.deepEqual(directWrites(db), []);
});

Deno.test("F78: only the exact deletion barrier is a non-retryable 403; other RPC errors stay retryable", async () => {
  for (const [error, expectedStatus] of [
    [{ code: "42501", message: "ACCOUNT_DELETION_IN_PROGRESS" }, 403],
    [{ code: "42501", message: "permission denied for table anime_user_lists" }, 500],
    [{ code: "XX000", message: "ACCOUNT_DELETION_IN_PROGRESS" }, 500],
  ] as const) {
    const db = newDb();
    const transactionCalls: string[] = [];
    const res = await handleApply(post("concierge-apply", {
      items: [{ mediaType: "ANIME", mediaId: 7, status: "PLANNING", action: "add" }],
    }), { client: () => db, serviceClient: () => ({ rpc: (name: string) => {
      transactionCalls.push(name);
      return Promise.resolve({ data: null, error });
    } }) });
    const body = await res.json();
    assert.equal(res.status, expectedStatus);
    if (expectedStatus === 403) {
      assert.deepEqual(body, {
        error: "This account is being deleted. Imports are no longer accepted.",
        code: "ACCOUNT_DELETION_IN_PROGRESS", status: "failed", retryable: false,
      });
    } else {
      assert.deepEqual(body, { error: "Import could not be saved", status: "failed", retryable: true });
    }
    assert.deepEqual(transactionCalls, ["apply_import_session"]);
    assert.deepEqual(directWrites(db), []);
    assert.equal(db.calls("log_concierge_run").length, 0);
  }
});

Deno.test("F12: a mixed outcome (accepted + conflict) is reported as partial and is undoable", async () => {
  const db = newDb();
  db.seed("anime_user_lists", [{ user_id: USER, anime_id: 7, list_type: "WATCHING", progress: 3, rating: 8, notes: "original", verdict: null }]);
  const { status, body } = await apply(db, {
    items: [
      { mediaType: "ANIME", mediaId: 7, status: "WATCHING", action: "update", progressEpisodes: 5, expectedExisting: { status: "WATCHING", progress_episodes: 1 } },
      { mediaType: "MANGA", mediaId: 9, status: "READING", action: "add" },
    ],
  });
  assert.equal(status, 200);
  assert.deepEqual(
    { success: body.success, status: body.status, undoable: body.undoable, applied: body.applied, conflicts: body.conflicts, errors: body.errors },
    {
      success: false,
      status: "partial",
      undoable: true,
      applied: [{ mediaType: "MANGA", mediaId: 9, status: "READING", action: "add" }],
      conflicts: [{ mediaType: "ANIME", mediaId: 7, error: "State changed since parse — review and retry" }],
      errors: [],
    },
  );
  assert.equal(listRow(db, "anime_user_lists", USER, 7)?.progress, 3, "the conflicted row is untouched");
  const undone = await undo(db, body.sessionId);
  assert.equal(undone.status, 200);
  assert.deepEqual(undone.body.reverted, [{ mediaType: "MANGA", mediaId: 9, undoType: "deleted" }]);
  assert.deepEqual(db.rows("manga_user_lists"), []);
  assert.equal(listRow(db, "anime_user_lists", USER, 7)?.progress, 3);
});

Deno.test("idempotency: a retry with the same key returns the same outcome without a second write; a new key is a new Apply", async () => {
  const db = newDb();
  const request = { idempotencyKey: "action-1", items: [{ mediaType: "ANIME", mediaId: 7, status: "WATCHING", action: "add", progressEpisodes: 2, raw: "Frieren ep 2" }] };
  const first = await apply(db, request);
  const writesAfterFirst = db.ops.length;
  const second = await apply(db, { ...request, items: [{ ...request.items[0], progressEpisodes: 9 }] });
  assert.equal(second.status, 200);
  assert.deepEqual(second.body, { ...first.body, replayed: true });
  assert.equal(db.ops.length, writesAfterFirst, "the replay wrote nothing (no list, journal, session or alias write)");
  assert.equal(listRow(db, "anime_user_lists", USER, 7)?.progress, 2);
  assert.equal(db.rows("import_sessions").length, 1);
  const third = await apply(db, { ...request, idempotencyKey: "action-2" });
  assert.deepEqual([third.body.replayed, third.body.sessionId !== first.body.sessionId, db.rows("import_sessions").length], [false, true, 2]);
});

Deno.test("F14: invalid identities (0, -4, null, 1.5, a string, out of int4 range) are HTTP 400 INVALID_ITEM and nothing is written", async () => {
  for (const mediaId of [0, -4, null, 1.5, "7", 2_147_483_648]) {
    const db = newDb();
    const { status, body } = await apply(db, {
      items: [
        { mediaType: "ANIME", mediaId: 5, status: "PLANNING", action: "add" },
        { mediaType: "ANIME", mediaId, status: "PLANNING", action: "add" },
      ],
    });
    assert.equal(status, 400, `mediaId ${JSON.stringify(mediaId)}`);
    assert.equal(body.code, "INVALID_ITEM");
    assert.equal(body.index, 1);
    assert.deepEqual(db.calls("apply_import_session"), [], "no transaction call, not even for the valid item");
    assert.deepEqual(db.ops, []);
  }
});

Deno.test("F14: an unknown mediaType or a status outside the medium's vocabulary is HTTP 400; anime and manga ids stay distinct", async () => {
  for (const item of [
    { mediaType: "ANIME", mediaId: 5, status: "READING" },
    { mediaType: "MOVIE", mediaId: 5, status: "PLANNING" },
    { mediaType: "MANGA", mediaId: 5, status: "SOMETIMES" },
    { mediaType: "MANGA", mediaId: 5 },
    "not an object",
  ]) {
    const db = newDb();
    const { status, body } = await apply(db, { items: [item] });
    assert.deepEqual([status, body.code, body.index], [400, "INVALID_ITEM", 0], JSON.stringify(item));
    assert.deepEqual(db.ops, []);
  }
  const db = newDb();
  const { body } = await apply(db, {
    items: [
      { mediaType: "ANIME", mediaId: 42, status: "WATCHING", action: "add", progressEpisodes: 4 },
      { mediaType: "MANGA", mediaId: 42, status: "reading", action: "add", progressChapters: 30 },
    ],
  });
  assert.equal(body.success, true);
  assert.deepEqual(db.rows("anime_user_lists").map((r) => [r.anime_id, r.progress, "manga_id" in r]), [[42, 4, false]]);
  assert.deepEqual(db.rows("manga_user_lists").map((r) => [r.manga_id, r.list_type, r.progress, "anime_id" in r]), [[42, "READING", 30, false]]);
});

Deno.test("R1: 10-digit media ids (1500000000, 2147483647) round-trip as numbers in the 200 body, never null", async () => {
  const db = newDb();
  const { status, body } = await apply(db, {
    items: [
      { mediaType: "ANIME", mediaId: 1_500_000_000, status: "PLANNING", action: "add" },
      { mediaType: "ANIME", mediaId: 2_147_483_647, status: "PLANNING", action: "skip" },
    ],
  });
  assert.equal(status, 200);
  assert.deepEqual([body.applied, body.skipped], [
    [{ mediaType: "ANIME", mediaId: 1_500_000_000, status: "PLANNING", action: "add" }],
    [{ mediaType: "ANIME", mediaId: 2_147_483_647 }],
  ]);
});

Deno.test("A4: an explicit JSON null progress is 'not provided' (stored progress kept), never progress 0", async () => {
  const db = newDb();
  db.seed("anime_user_lists", [{ user_id: USER, anime_id: 12, list_type: "WATCHING", progress: 7, rating: null, notes: null, verdict: null }]);
  const { body } = await apply(db, {
    items: [{ mediaType: "ANIME", mediaId: 12, status: "PAUSED", action: "update", progressEpisodes: null, progress: null }],
  });
  assert.equal(body.status, "applied");
  assert.deepEqual(plannedItems(db)[0].update_values, { list_type: "PAUSED" });
  assert.deepEqual([listRow(db, "anime_user_lists", USER, 12)?.list_type, listRow(db, "anime_user_lists", USER, 12)?.progress], ["PAUSED", 7]);
});

Deno.test("F14 review: a season number of 0 or below is no season (no S1E5 fabricated), not clamped to 1", async () => {
  const db = newDb();
  await apply(db, { items: [{ mediaType: "ANIME", mediaId: 31, status: "WATCHING", action: "add", seasonNumber: 0, episodeInSeason: 5, progressEpisodes: 5 }] });
  assert.equal(listRow(db, "anime_user_lists", USER, 31)?.notes, null);
});

Deno.test("F32: a limiter error is HTTP 503 with Retry-After and nothing is written; an explicit denial stays 429", async () => {
  const db = newDb();
  db.rateLimitError = { message: "rate-limit database unavailable" };
  const failed = await apply(db, { items: [{ mediaType: "ANIME", mediaId: 7, status: "PLANNING", action: "add" }] });
  assert.equal(failed.status, 503);
  assert.equal(failed.headers.get("Retry-After"), "30");
  assert.equal(failed.body.error, "Rate limiter unavailable");
  assert.deepEqual(db.calls("apply_import_session"), []);
  assert.deepEqual(db.ops, []);

  const denied = newDb();
  denied.rateLimit = { allowed: false, retry_after_s: 12 };
  const res = await apply(denied, { items: [{ mediaType: "ANIME", mediaId: 7, status: "PLANNING", action: "add" }] });
  assert.deepEqual([res.status, res.headers.get("Retry-After"), res.body], [429, "12", { error: "Rate limited", retry_after_s: 12 }]);
  assert.deepEqual(denied.ops, []);
});

Deno.test("rating: 0 and sub-1 values are absent, values clamp to 10 and floor (DB CHECK 1..10 never violated)", async () => {
  const db = newDb();
  db.seed("anime_user_lists", [{ user_id: USER, anime_id: 1, list_type: "COMPLETED", progress: 12, rating: 7, notes: null, verdict: null }]);
  const { body } = await apply(db, {
    items: [
      { mediaType: "ANIME", mediaId: 1, status: "COMPLETED", action: "update", progressEpisodes: 12, rating: 0 },
      { mediaType: "ANIME", mediaId: 2, status: "COMPLETED", action: "add", progressEpisodes: 12, rating: 15 },
      { mediaType: "ANIME", mediaId: 3, status: "COMPLETED", action: "add", progressEpisodes: 12, rating: 8.5 },
      { mediaType: "ANIME", mediaId: 4, status: "PLANNING", action: "add", rating: 0.5 },
    ],
  });
  assert.equal(body.success, true, JSON.stringify(body.errors));
  assert.equal(listRow(db, "anime_user_lists", USER, 1)?.rating, 7, "rating 0 must not wipe or violate");
  assert.equal(listRow(db, "anime_user_lists", USER, 2)?.rating, 10);
  assert.equal(listRow(db, "anime_user_lists", USER, 3)?.rating, 8);
  assert.equal(listRow(db, "anime_user_lists", USER, 4)?.rating, null);
  assert.equal(normalizeRating("9"), 9);
  assert.equal(normalizeRating(-4), null);
});

Deno.test("identity: only the JWT user is passed to the transaction; user ids in the body are ignored", async () => {
  const db = newDb(USER);
  db.seed("anime_user_lists", [{ user_id: OTHER, anime_id: 5, list_type: "COMPLETED", progress: 24, rating: 9, notes: "theirs", verdict: null }]);
  const { body } = await apply(db, {
    user_id: OTHER,
    userId: OTHER,
    items: [{ mediaType: "ANIME", mediaId: 5, status: "DROPPED", action: "add", user_id: OTHER, userId: OTHER }],
  });
  assert.equal(body.success, true);
  assert.equal((db.calls("apply_import_session")[0].args as Row).p_user_id, USER);
  assert.ok(!JSON.stringify(plannedItems(db)).includes(OTHER), "no body user id reaches the planned items");
  assert.deepEqual(listRow(db, "anime_user_lists", OTHER, 5), { user_id: OTHER, anime_id: 5, list_type: "COMPLETED", progress: 24, rating: 9, notes: "theirs", verdict: null });
  assert.equal(listRow(db, "anime_user_lists", USER, 5)?.list_type, "DROPPED");
  assert.equal(db.rows("import_sessions")[0].user_id, USER);
});

Deno.test("invalid JWT: 401, no transaction call and nothing is written", async () => {
  const db = newDb(null);
  const { status, body } = await apply(db, { items: [{ mediaType: "ANIME", mediaId: 1, status: "PLANNING" }] });
  assert.equal(status, 401);
  assert.deepEqual(body, { error: "Unauthorized" });
  assert.deepEqual(db.calls("apply_import_session"), []);
  assert.deepEqual(db.ops, []);
});

Deno.test("optional alias record (after commit) uses the shared Parse/Apply key; a conflicted item records none", async () => {
  const db = newDb();
  db.seed("anime_user_lists", [{ user_id: USER, anime_id: 3, list_type: "WATCHING", progress: 1, rating: null, notes: null, verdict: null }]);
  await apply(db, {
    items: [
      { mediaType: "ANIME", mediaId: 16498, status: "COMPLETED", action: "add", raw: "Ich habe Shingeki no Kyojin geschaut, eine 9", progressEpisodes: 25 },
      { mediaType: "ANIME", mediaId: 3, status: "WATCHING", action: "update", raw: "Monster 9/10", expectedExisting: { status: "PAUSED" } },
    ],
  });
  assert.deepEqual(
    db.rows("title_aliases").map((r) => [r.alias_norm, r.media_type, r.media_id, r.hits]),
    [["shingeki no kyojin", "ANIME", 16498, 1]],
  );
});

Deno.test("taste semantics: list writes carry the import context of their session, which does not outlive the transaction", async () => {
  const db = newDb();
  const { body } = await apply(db, { items: [{ mediaType: "ANIME", mediaId: 8, status: "PLANNING", action: "add" }] });
  const [write] = db.writes("anime_user_lists");
  assert.equal(write.importContext, body.sessionId);
  assert.equal(db.importContext, null);
});

Deno.test("request shape: an invalid idempotencyKey is 400; an empty item list writes nothing", async () => {
  const db = newDb();
  const bad = await apply(db, { idempotencyKey: "has spaces", items: [{ mediaType: "ANIME", mediaId: 1, status: "PLANNING" }] });
  assert.deepEqual([bad.status, bad.body.code], [400, "INVALID_IDEMPOTENCY_KEY"]);
  const empty = await apply(db, { items: [] });
  assert.deepEqual([empty.status, empty.body.status, empty.body.sessionId, empty.body.applied], [200, "none", null, []]);
  assert.deepEqual(db.calls("apply_import_session"), []);
  assert.deepEqual(db.ops, []);
});
