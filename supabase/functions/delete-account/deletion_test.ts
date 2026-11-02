// Tests for the REAL production `runAccountDeletion` (deletion.ts) with a stateful
// fake backend. The fake models external outcomes (rows, storage objects, auth
// users, injected faults); the policy under test (ordering, required vs
// best-effort, auth-user-last, retry) is the production code.
//
//   deno test --no-check supabase/functions/delete-account/   (or without --no-check)
import { strict as assert } from "node:assert";
import { REQUIRED_TEXT_USER_TABLES, runAccountDeletion, userIdSpellings } from "./deletion.ts";
import { FakeBackend, OTHER, USER } from "./fake_backend.ts";

Deno.test("all required steps succeed: success, barrier FIRST, auth user deleted LAST, other users untouched", async () => {
  const b = new FakeBackend();
  const outcome = await runAccountDeletion(b, USER);
  assert.equal(outcome.ok, true);
  assert.equal(b.rowsLeftFor(USER), 0);
  assert.deepEqual(b.storageFor(USER), []);
  assert.equal(b.profiles.has(USER), false);
  assert.equal(b.authUsers.has(USER), false);
  assert.equal(b.clubMemberships.get(USER), 0, "club lifecycle ran for the user");
  assert.equal(b.calls[0], "beginAccountDeletion", "the write barrier is taken before anything is deleted");
  assert.equal(b.calls[1], "rpc", "RPC (authorization + concierge data) runs right after the barrier");
  assert.equal(b.calls[b.calls.length - 1], "deleteAuthUser", "auth user is deleted last");
  assert.equal(b.calls.filter((c) => c === "deleteAuthUser").length, 1);
  assert.ok(b.otherUserIntact(), "no collateral deletion of another user's data");
});

Deno.test("a failing list delete reports failure and NEVER deletes the auth user", async () => {
  const b = new FakeBackend();
  b.faults.set("delete:anime_user_lists", "permission denied for table anime_user_lists");
  const outcome = await runAccountDeletion(b, USER);
  assert.equal(outcome.ok, false);
  if (outcome.ok) return;
  assert.equal(outcome.status, 500);
  assert.equal(outcome.error, "Account cleanup incomplete");
  assert.deepEqual(outcome.failedSteps, ["anime_user_lists"]);
  assert.match(outcome.detail, /anime_user_lists: permission denied/);
  assert.equal(b.authDeleteCalled(), false);
  assert.equal(b.authUsers.has(USER), true, "auth user must survive so the client can retry");
  // the other required steps still ran in the same attempt
  assert.equal(b.tables.manga_user_lists.has(USER), false);
  assert.deepEqual(b.storageFor(USER), []);
  assert.equal(b.profiles.has(USER), false);
  assert.ok(b.otherUserIntact());
});

Deno.test("each user-keyed table is individually required (parameterized)", async () => {
  for (const table of REQUIRED_TEXT_USER_TABLES) {
    const b = new FakeBackend();
    b.faults.set(`delete:${table}`, "boom");
    const outcome = await runAccountDeletion(b, USER);
    assert.equal(outcome.ok, false, table);
    assert.equal(b.authDeleteCalled(), false, table);
    if (!outcome.ok) assert.deepEqual(outcome.failedSteps, [table]);
  }
});

Deno.test("a failing storage remove reports failure and does not delete the auth user", async () => {
  const b = new FakeBackend();
  b.faults.set("removeStorage", "storage 503");
  const outcome = await runAccountDeletion(b, USER);
  assert.equal(outcome.ok, false);
  if (!outcome.ok) {
    assert.deepEqual(outcome.failedSteps, ["storage:media"]);
    assert.match(outcome.detail, /storage 503/);
  }
  assert.equal(b.authDeleteCalled(), false);
  assert.equal(b.rowsLeftFor(USER), 0, "independent steps still ran");
});

Deno.test("a failing storage LIST is also a failure (a swallowed list error used to look like 'no files')", async () => {
  const b = new FakeBackend();
  b.faults.set("listStorage", "storage list 500");
  const outcome = await runAccountDeletion(b, USER);
  assert.equal(outcome.ok, false);
  assert.equal(b.authDeleteCalled(), false);
});

Deno.test("a failing profile delete reports failure and does not delete the auth user", async () => {
  const b = new FakeBackend();
  b.faults.set("deleteProfile", "profiles locked");
  const outcome = await runAccountDeletion(b, USER);
  assert.equal(outcome.ok, false);
  if (!outcome.ok) assert.deepEqual(outcome.failedSteps, ["profiles"]);
  assert.equal(b.authDeleteCalled(), false);
});

Deno.test("a THROWN dependency error (network failure) is a failure, not a crash and not a success", async () => {
  for (const key of ["delete:manga_user_lists", "listStorage", "deleteProfile"]) {
    const b = new FakeBackend();
    b.throws.add(key);
    const outcome = await runAccountDeletion(b, USER);
    assert.equal(outcome.ok, false, key);
    assert.equal(b.authDeleteCalled(), false, key);
  }
});

Deno.test("retry after a partial failure finishes the job (idempotent)", async () => {
  const b = new FakeBackend();
  b.faults.set("delete:anime_user_lists", "transient");
  b.faults.set("deleteProfile", "transient");
  const first = await runAccountDeletion(b, USER);
  assert.equal(first.ok, false);
  assert.equal(b.authUsers.has(USER), true);
  assert.ok(b.rowsLeftFor(USER) > 0, "partial: some rows remain after the first attempt");

  b.faults.clear();
  const callsBeforeRetry = b.calls.length;
  const second = await runAccountDeletion(b, USER);
  assert.equal(second.ok, true);
  assert.equal(b.rowsLeftFor(USER), 0);
  assert.equal(b.profiles.has(USER), false);
  assert.equal(b.authUsers.has(USER), false);
  assert.equal(b.calls.slice(callsBeforeRetry).filter((c) => c === "deleteAuthUser").length, 1);
  assert.ok(b.otherUserIntact());

  // running it yet again (everything already gone) is still a clean no-op success path
  const b2 = new FakeBackend();
  assert.equal((await runAccountDeletion(b2, USER)).ok, true);
  b2.authUsers.add(USER); // pretend the auth delete was lost: re-run must succeed on empty data
  assert.equal((await runAccountDeletion(b2, USER)).ok, true);
});

Deno.test("auth-user deletion failure is reported and is retryable", async () => {
  const b = new FakeBackend();
  b.faults.set("deleteAuthUser", "auth admin 500");
  const first = await runAccountDeletion(b, USER);
  assert.equal(first.ok, false);
  if (!first.ok) {
    assert.equal(first.error, "Failed to delete auth user");
    assert.deepEqual(first.failedSteps, ["auth.users"]);
  }
  b.faults.clear();
  assert.equal((await runAccountDeletion(b, USER)).ok, true);
  assert.equal(b.authUsers.has(USER), false);
});

Deno.test("RPC failure stops everything: 500, no further deletes, no auth deletion", async () => {
  const b = new FakeBackend();
  b.rpcMode = "error";
  const outcome = await runAccountDeletion(b, USER);
  assert.equal(outcome.ok, false);
  if (!outcome.ok) {
    assert.equal(outcome.status, 500);
    assert.equal(outcome.error, "RPC delete_user_concierge_data failed");
  }
  assert.deepEqual(b.calls, ["beginAccountDeletion", "rpc"]);
});

Deno.test("RPC refusal is 403 and nothing else runs", async () => {
  const b = new FakeBackend();
  b.rpcMode = "refused";
  const outcome = await runAccountDeletion(b, USER);
  assert.equal(outcome.ok, false);
  if (!outcome.ok) {
    assert.equal(outcome.status, 403);
    assert.equal(outcome.error, "RPC refused");
    assert.equal(outcome.detail, "forbidden");
  }
  assert.deepEqual(b.calls, ["beginAccountDeletion", "rpc"]);
  assert.ok(b.otherUserIntact());
});

Deno.test("barrier failure stops everything before any delete: 500, no RPC, no cleanup, no auth deletion", async () => {
  for (const mode of ["fault", "throw"] as const) {
    const b = new FakeBackend();
    if (mode === "fault") b.faults.set("beginAccountDeletion", "permission denied for function begin_account_deletion");
    else b.throws.add("beginAccountDeletion");
    const outcome = await runAccountDeletion(b, USER);
    assert.equal(outcome.ok, false, mode);
    if (!outcome.ok) {
      assert.equal(outcome.status, 500, mode);
      assert.equal(outcome.error, "Account deletion could not start", mode);
      assert.deepEqual(outcome.failedSteps, ["begin_account_deletion"], mode);
    }
    assert.deepEqual(b.calls, ["beginAccountDeletion"], `${mode}: nothing else ran`);
    assert.ok(b.rowsLeftFor(USER) > 0, `${mode}: no data was deleted without the barrier`);
    assert.equal(b.authUsers.has(USER), true, mode);
  }
});

Deno.test("club lifecycle failure is a required failure: other cleanup still runs, auth user kept; the retry finishes", async () => {
  const b = new FakeBackend();
  b.faults.set("deleteClubMemberships", "deadlock detected");
  const first = await runAccountDeletion(b, USER);
  assert.equal(first.ok, false);
  if (!first.ok) {
    assert.deepEqual(first.failedSteps, ["club_memberships"]);
    assert.match(first.detail, /club_memberships: deadlock detected/);
  }
  assert.equal(b.authDeleteCalled(), false, "auth user must survive a failed club step");
  assert.equal(b.rowsLeftFor(USER), 0, "independent required steps still ran");
  assert.equal(b.clubMemberships.get(USER), 2);

  b.faults.clear();
  const second = await runAccountDeletion(b, USER);
  assert.equal(second.ok, true);
  assert.equal(b.clubMemberships.get(USER), 0);
  assert.equal(b.authUsers.has(USER), false);
  assert.equal(b.calls.filter((c) => c === "beginAccountDeletion").length, 2, "the barrier is re-taken (idempotent) on retry");
  assert.ok(b.otherUserIntact());
});

Deno.test("legacy TEXT rows are deleted in BOTH id spellings (canonical lower-case and upper-case uuidString)", async () => {
  const b = new FakeBackend();
  assert.equal(b.tables.anime_user_lists.get(USER.toUpperCase()), 1, "precondition: an upper-case spelling row exists");
  const outcome = await runAccountDeletion(b, USER);
  assert.equal(outcome.ok, true);
  assert.equal(b.tables.anime_user_lists.has(USER.toUpperCase()), false);
  assert.equal(b.rowsLeftFor(USER), 0);
  assert.ok(b.otherUserIntact(), "the other user's rows in either spelling are untouched");
  assert.deepEqual(userIdSpellings("ABCDEF00-0000-4000-8000-000000000001"),
    ["abcdef00-0000-4000-8000-000000000001", "ABCDEF00-0000-4000-8000-000000000001"], "canonical first, then the uuidString spelling");
  assert.deepEqual(userIdSpellings("00000000-0000-4000-8000-000000000001"), ["00000000-0000-4000-8000-000000000001"], "no duplicate when case is meaningless");
});

Deno.test("storage purge pages through >100 objects and nested folders", async () => {
  const b = new FakeBackend();
  b.storage.clear();
  for (let i = 0; i < 250; i++) b.storage.add(`${USER}/f${String(i).padStart(3, "0")}.png`);
  for (let i = 0; i < 130; i++) b.storage.add(`${USER}/albums/2024/p${i}.png`);
  b.storage.add(`${OTHER}/keep.png`);
  const outcome = await runAccountDeletion(b, USER);
  assert.equal(outcome.ok, true);
  assert.deepEqual(b.storageFor(USER), []);
  assert.deepEqual([...b.storage], [`${OTHER}/keep.png`]);
});

Deno.test("a storage backend that reports success but removes nothing fails closed (bounded, no infinite loop)", async () => {
  const b = new FakeBackend();
  b.storageRemoveIsNoop = true;
  const outcome = await runAccountDeletion(b, USER);
  assert.equal(outcome.ok, false);
  if (!outcome.ok) {
    assert.deepEqual(outcome.failedSteps, ["storage:media"]);
    assert.match(outcome.detail, /incomplete/);
  }
  assert.equal(b.authDeleteCalled(), false);
  assert.ok(b.calls.filter((c) => c === "listStorage").length <= 60, "bounded number of list calls");
});

Deno.test("an empty user id is rejected before any dependency is called", async () => {
  const b = new FakeBackend();
  const outcome = await runAccountDeletion(b, "");
  assert.equal(outcome.ok, false);
  assert.deepEqual(b.calls, []);
});
