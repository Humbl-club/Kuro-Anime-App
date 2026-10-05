// Handler + adapter tests for delete-account. They run the REAL handler
// (handler.ts), the REAL adapters (adapters.ts) and the REAL deletion policy
// (deletion.ts) against a fake supabase-js-shaped client; only the Supabase
// service boundary is faked. This is NOT a test against Supabase itself.
import { strict as assert } from "node:assert";
import { createDeletionDeps, createPlatform, type AdminClientLike, type UserClientLike } from "./adapters.ts";
import { type AuthUser, type HandlerPlatform, handleDeleteAccount } from "./handler.ts";
import { FakeBackend, OTHER, USER } from "./fake_backend.ts";

function post(body: unknown, headers: Record<string, string> = { Authorization: "Bearer jwt" }): Request {
  return new Request("https://example.test/functions/v1/delete-account", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

/** Platform whose deps are the FakeBackend; records which user ids authenticate() hands out. */
function fakePlatform(backend: FakeBackend, user: AuthUser | null, revoke?: (code: string) => Promise<void>): HandlerPlatform {
  return {
    scope: () => ({ authenticate: () => Promise.resolve(user), deps: backend }),
    revokeAppleToken: revoke ?? (() => Promise.resolve()),
  };
}

Deno.test("handler: non-POST is 405 and touches nothing", async () => {
  const b = new FakeBackend();
  const res = await handleDeleteAccount(new Request("https://x.test", { method: "GET" }), fakePlatform(b, { id: USER }));
  assert.equal(res.status, 405);
  assert.deepEqual(b.calls, []);
});

Deno.test("handler: missing env is 500 'Missing env vars'", async () => {
  const platform: HandlerPlatform = { scope: () => null, revokeAppleToken: () => Promise.resolve() };
  const res = await handleDeleteAccount(post({}), platform);
  assert.equal(res.status, 500);
  assert.deepEqual(await res.json(), { error: "Missing env vars" });
});

Deno.test("handler: invalid/missing JWT is 401 and nothing is deleted", async () => {
  const b = new FakeBackend();
  const res = await handleDeleteAccount(post({ confirm: "true" }), fakePlatform(b, null));
  assert.equal(res.status, 401);
  assert.deepEqual(await res.json(), { error: "Unauthorized" });
  assert.deepEqual(b.calls, []);
});

Deno.test("handler: success body is exactly { success: true } with status 200 (client contract)", async () => {
  const b = new FakeBackend();
  const res = await handleDeleteAccount(post({ confirm: "true" }), fakePlatform(b, { id: USER }));
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { success: true });
  assert.equal(b.authUsers.has(USER), false);
});

Deno.test("handler: a user_id in the request body is ignored; only the JWT-derived id is deleted", async () => {
  const b = new FakeBackend();
  const res = await handleDeleteAccount(
    post({ user_id: OTHER, userId: OTHER, id: OTHER, confirm: "true" }),
    fakePlatform(b, { id: USER }),
  );
  assert.equal(res.status, 200);
  assert.equal(b.authUsers.has(USER), false);
  assert.ok(b.otherUserIntact(), "the id supplied in the body must never be acted on");
});

Deno.test("handler: required cleanup failure is a non-2xx response with an error string and NO success flag", async () => {
  const b = new FakeBackend();
  b.faults.set("deleteProfile", "profiles locked");
  const res = await handleDeleteAccount(post({}), fakePlatform(b, { id: USER }));
  assert.equal(res.status, 500);
  const body = await res.json();
  assert.equal(body.success, undefined);
  assert.equal(body.error, "Account cleanup incomplete");
  assert.equal(typeof body.error, "string", "Swift client decodes `error` as String");
  assert.deepEqual(body.failed_steps, ["profiles"]);
  assert.equal(b.authUsers.has(USER), true);
});

Deno.test("handler: RPC refusal maps to 403, RPC error to 500, with the previous error strings", async () => {
  const refused = new FakeBackend();
  refused.rpcMode = "refused";
  const r1 = await handleDeleteAccount(post({}), fakePlatform(refused, { id: USER }));
  assert.equal(r1.status, 403);
  assert.equal((await r1.json()).error, "RPC refused");

  const failing = new FakeBackend();
  failing.rpcMode = "error";
  const r2 = await handleDeleteAccount(post({}), fakePlatform(failing, { id: USER }));
  assert.equal(r2.status, 500);
  assert.equal((await r2.json()).error, "RPC delete_user_concierge_data failed");
});

Deno.test("handler: retry through the handler after a partial failure succeeds", async () => {
  const b = new FakeBackend();
  b.faults.set("removeStorage", "storage 503");
  const first = await handleDeleteAccount(post({}), fakePlatform(b, { id: USER }));
  assert.equal(first.status, 500);
  b.faults.clear();
  const second = await handleDeleteAccount(post({}), fakePlatform(b, { id: USER }));
  assert.equal(second.status, 200);
  assert.equal(b.authUsers.has(USER), false);
});

Deno.test("handler: Apple revocation runs only for Apple users WITH a code, before deletion, and never blocks deletion", async () => {
  const appleUser: AuthUser = { id: USER, identities: [{ provider: "apple" }] };

  const calls: string[] = [];
  const b1 = new FakeBackend();
  const res1 = await handleDeleteAccount(
    post({ apple_authorization_code: "code-1" }),
    fakePlatform(b1, appleUser, (code) => {
      calls.push(`revoke:${code}:authUserStillExists=${b1.authUsers.has(USER)}`);
      return Promise.resolve();
    }),
  );
  assert.equal(res1.status, 200);
  assert.deepEqual(calls, ["revoke:code-1:authUserStillExists=true"]);

  const b2 = new FakeBackend();
  let called2 = 0;
  await handleDeleteAccount(post({}), fakePlatform(b2, appleUser, () => (called2++, Promise.resolve())));
  assert.equal(called2, 0, "no code => no revocation attempt");

  const b3 = new FakeBackend();
  let called3 = 0;
  await handleDeleteAccount(
    post({ apple_authorization_code: "x" }),
    fakePlatform(b3, { id: USER, identities: [{ provider: "email" }] }, () => (called3++, Promise.resolve())),
  );
  assert.equal(called3, 0, "non-Apple user => no revocation attempt");

  const b4 = new FakeBackend();
  const res4 = await handleDeleteAccount(
    post({ apple_authorization_code: "x" }),
    fakePlatform(b4, { id: USER, app_metadata: { providers: ["apple"] } }, () => Promise.reject(new Error("apple down"))),
  );
  assert.equal(res4.status, 200, "a failing revocation must not block account deletion");
  assert.equal(b4.authUsers.has(USER), false);
});

// ---------------------------------------------------------------------------
// Adapter behavior against a fake supabase-js-shaped client
// ---------------------------------------------------------------------------

type Err = { message: string; code?: string; status?: number } | null;

type RpcAnswer = { data: unknown; error: Err };

function fakeAdmin(over: Partial<{
  deleteErr: Err;
  authErr: Err;
  listErr: Err;
  removeErr: Err;
  removeNoop: boolean;
  /** answers per service-role RPC name (default: { success: true }) */
  rpc: Record<string, RpcAnswer>;
}> = {}) {
  const log: string[] = [];
  let files = [{ name: "a.png", id: "1" }];
  const admin: AdminClientLike = {
    from(table) {
      const f = {
        then: (resolve: (v: { error: Err }) => unknown) => {
          log.push(`delete:${table}`);
          return Promise.resolve({ error: over.deleteErr ?? null }).then(resolve);
        },
        eq: (c: string, v: string) => (log.push(`eq:${c}=${v}`), f),
        in: (c: string, v: string[]) => (log.push(`in:${c}=${v.join("|")}`), f),
      };
      return { delete: () => f as unknown as ReturnType<ReturnType<AdminClientLike["from"]>["delete"]> };
    },
    rpc(fn, args) {
      log.push(`rpc:${fn}:${JSON.stringify(args)}`);
      return Promise.resolve(over.rpc?.[fn] ?? { data: { success: true }, error: null });
    },
    storage: {
      from: (bucket: string) => ({
        list: (path: string, o: { limit: number; offset: number }) => {
          log.push(`list:${bucket}/${path}:${o.limit}:${o.offset}`);
          return Promise.resolve({ data: over.listErr ? null : [...files], error: over.listErr ?? null });
        },
        remove: (paths: string[]) => {
          log.push(`remove:${bucket}:${paths.join(",")}`);
          if (!over.removeErr && !over.removeNoop) files = files.filter((f) => !paths.includes(`${USER}/${f.name}`));
          return Promise.resolve({ error: over.removeErr ?? null });
        },
      }),
    },
    auth: { admin: { deleteUser: (id: string) => (log.push(`deleteUser:${id}`), Promise.resolve({ error: over.authErr ?? null })) } },
  };
  return { admin, log };
}

function fakeUser(rpc: { data: unknown; error: Err }, getUser: { user: AuthUser | null; error: unknown } = { user: { id: USER }, error: null }) {
  const calls: string[] = [];
  const client: UserClientLike = {
    auth: { getUser: () => Promise.resolve({ data: { user: getUser.user }, error: getUser.error }) },
    rpc: (fn, args) => (calls.push(`${fn}:${JSON.stringify(args)}`), Promise.resolve(rpc)),
  };
  return { client, calls };
}

Deno.test("adapters: errors from every client call are surfaced, not dropped", async () => {
  const { admin } = fakeAdmin({ deleteErr: { message: "rls denied" } });
  const { client } = fakeUser({ data: { success: true }, error: null });
  const deps = createDeletionDeps(admin, client);
  assert.deepEqual(await deps.deleteRowsByUserIds("anime_user_lists", [USER]), { error: "rls denied" });
  assert.deepEqual(await deps.deleteProfile(USER), { error: "rls denied" });

  const st = fakeAdmin({ listErr: { message: "list failed" }, removeErr: { message: "remove failed" } });
  const sdeps = createDeletionDeps(st.admin, client);
  assert.deepEqual(await sdeps.listStorageObjects(USER, 100), { entries: [], error: "list failed" });
  assert.deepEqual(await sdeps.removeStorageObjects([`${USER}/a.png`]), { error: "remove failed" });
});

Deno.test("adapters: storage is addressed as media/<userId> with offset 0", async () => {
  const { admin, log } = fakeAdmin();
  const { client } = fakeUser({ data: null, error: null });
  const deps = createDeletionDeps(admin, client);
  await deps.listStorageObjects(USER, 100);
  await deps.removeStorageObjects([`${USER}/a.png`]);
  assert.deepEqual(log, [`list:media/${USER}:100:0`, `remove:media:${USER}/a.png`]);
});

Deno.test("adapters: RPC mapping (ok / error / refused) and the JWT-bound client is used", async () => {
  const { admin } = fakeAdmin();
  const ok = fakeUser({ data: { success: true, deleted: {} }, error: null });
  assert.deepEqual(await createDeletionDeps(admin, ok.client).deleteUserConciergeData(USER), { kind: "ok" });
  assert.deepEqual(ok.calls, [`delete_user_concierge_data:${JSON.stringify({ p_user_id: USER })}`]);

  const refused = fakeUser({ data: { error: "forbidden" }, error: null });
  assert.deepEqual(await createDeletionDeps(admin, refused.client).deleteUserConciergeData(USER), { kind: "refused", reason: "forbidden" });

  const failing = fakeUser({ data: null, error: { message: "boom" } });
  assert.deepEqual(await createDeletionDeps(admin, failing.client).deleteUserConciergeData(USER), { kind: "error", message: "boom" });
});

Deno.test("adapters: auth deletion treats 'user already gone' as success but surfaces other errors", async () => {
  const { client } = fakeUser({ data: null, error: null });
  const gone = createDeletionDeps(fakeAdmin({ authErr: { message: "User not found", code: "user_not_found", status: 404 } }).admin, client);
  assert.deepEqual(await gone.deleteAuthUser(USER), { error: null });
  const gone404 = createDeletionDeps(fakeAdmin({ authErr: { message: "nope", status: 404 } }).admin, client);
  assert.deepEqual(await gone404.deleteAuthUser(USER), { error: null });
  const broken = createDeletionDeps(fakeAdmin({ authErr: { message: "db error deleting user", status: 500 } }).admin, client);
  assert.deepEqual(await broken.deleteAuthUser(USER), { error: "db error deleting user" });
});

Deno.test("adapters: the barrier and club RPCs run as the service role with the JWT id and fail unless they answer success: true", async () => {
  const { client } = fakeUser({ data: null, error: null });
  const ok = fakeAdmin();
  const deps = createDeletionDeps(ok.admin, client);
  assert.deepEqual(await deps.beginAccountDeletion(USER), { error: null });
  assert.deepEqual(await deps.deleteClubMemberships(USER), { error: null });
  assert.deepEqual(ok.log, [
    `rpc:begin_account_deletion:${JSON.stringify({ p_user_id: USER })}`,
    `rpc:delete_account_club_memberships:${JSON.stringify({ p_user_id: USER })}`,
  ]);

  const transport = createDeletionDeps(fakeAdmin({ rpc: { begin_account_deletion: { data: null, error: { message: "permission denied" } } } }).admin, client);
  assert.deepEqual(await transport.beginAccountDeletion(USER), { error: "permission denied" });
  const noSuccess = createDeletionDeps(fakeAdmin({ rpc: { delete_account_club_memberships: { data: { success: false }, error: null } } }).admin, client);
  assert.deepEqual(await noSuccess.deleteClubMemberships(USER), { error: "delete_account_club_memberships did not report success" });
  const empty = createDeletionDeps(fakeAdmin({ rpc: { begin_account_deletion: { data: null, error: null } } }).admin, client);
  assert.ok((await empty.beginAccountDeletion(USER)).error, "a missing answer is never read as done");
});

Deno.test("adapters: TEXT-table deletes filter user_id IN the given spellings", async () => {
  const { admin, log } = fakeAdmin();
  const { client } = fakeUser({ data: null, error: null });
  await createDeletionDeps(admin, client).deleteRowsByUserIds("manga_comments", ["abc", "ABC"]);
  assert.deepEqual(log, ["in:user_id=abc|ABC", "delete:manga_comments"]);
});

Deno.test("createPlatform: missing env => no scope; with env, the user client carries the caller's Authorization header and the admin client the service key", async () => {
  const created: { url: string; key: string; headers?: Record<string, string> }[] = [];
  const { admin } = fakeAdmin();
  const { client } = fakeUser({ data: { success: true }, error: null });
  const createClient = (url: string, key: string, options?: { global?: { headers?: Record<string, string> } }) => {
    created.push({ url, key, headers: options?.global?.headers });
    return key === "service-key" ? admin : client;
  };

  const missing = createPlatform({ supabaseUrl: "u", supabaseAnonKey: "anon", serviceRoleKey: undefined }, createClient);
  assert.equal(missing.scope("Bearer jwt"), null);

  const platform = createPlatform({ supabaseUrl: "http://local.test", supabaseAnonKey: "anon-key", serviceRoleKey: "service-key" }, createClient);
  const scope = platform.scope("Bearer caller-jwt");
  assert.ok(scope);
  assert.deepEqual(created, [
    { url: "http://local.test", key: "anon-key", headers: { Authorization: "Bearer caller-jwt" } },
    { url: "http://local.test", key: "service-key", headers: undefined },
  ]);
  assert.deepEqual(await scope!.authenticate(), { id: USER });
});

Deno.test("createPlatform: authenticate() returns null for an auth error or missing user", async () => {
  const { admin } = fakeAdmin();
  for (const getUser of [{ user: null, error: null }, { user: { id: USER }, error: new Error("jwt expired") }]) {
    const { client } = fakeUser({ data: null, error: null }, getUser);
    const platform = createPlatform(
      { supabaseUrl: "u", supabaseAnonKey: "a", serviceRoleKey: "s" },
      (_u, k) => (k === "s" ? admin : client),
    );
    assert.equal(await platform.scope("Bearer x")!.authenticate(), null);
  }
});

Deno.test("end to end through handler + real adapters + real policy: client errors can no longer produce success", async () => {
  // The previous implementation discarded these results and returned { success: true }.
  const cases: { name: string; over: Parameters<typeof fakeAdmin>[0] }[] = [
    { name: "table delete error", over: { deleteErr: { message: "rls denied" } } },
    { name: "storage list error", over: { listErr: { message: "list failed" } } },
    { name: "storage remove error", over: { removeErr: { message: "remove failed" } } },
  ];
  for (const c of cases) {
    const { admin, log } = fakeAdmin(c.over);
    const { client } = fakeUser({ data: { success: true }, error: null });
    const platform = createPlatform({ supabaseUrl: "u", supabaseAnonKey: "a", serviceRoleKey: "s" }, (_u, k) => (k === "s" ? admin : client));
    const res = await handleDeleteAccount(post({}), platform);
    assert.equal(res.status, 500, c.name);
    const body = await res.json();
    assert.equal(body.success, undefined, c.name);
    assert.equal(log.some((l) => l.startsWith("deleteUser:")), false, `${c.name}: auth user must not be deleted`);
  }

  // all calls succeed: real adapters + real policy => 200 { success: true }, auth user deleted last
  const okRun = fakeAdmin();
  const okUser = fakeUser({ data: { success: true }, error: null });
  const okPlatform = createPlatform({ supabaseUrl: "u", supabaseAnonKey: "a", serviceRoleKey: "s" }, (_u, k) => (k === "s" ? okRun.admin : okUser.client));
  const okRes = await handleDeleteAccount(post({}), okPlatform);
  assert.equal(okRes.status, 200);
  assert.deepEqual(await okRes.json(), { success: true });
  assert.equal(okRun.log[okRun.log.length - 1], `deleteUser:${USER}`, "auth user is the last admin call");
  assert.equal(okRun.log[0], `rpc:begin_account_deletion:${JSON.stringify({ p_user_id: USER })}`, "the barrier is the first admin call");
  assert.ok(okRun.log.some((l) => l.startsWith(`remove:media:${USER}/a.png`)));

  // storage "succeeds" but the object never goes away: fail closed, not success
  const stuck = fakeAdmin({ removeNoop: true });
  const { client } = fakeUser({ data: { success: true }, error: null });
  const platform = createPlatform({ supabaseUrl: "u", supabaseAnonKey: "a", serviceRoleKey: "s" }, (_u, k) => (k === "s" ? stuck.admin : client));
  const res = await handleDeleteAccount(post({}), platform);
  assert.equal(res.status, 500);
  assert.equal(stuck.log.some((l) => l.startsWith("deleteUser:")), false);
});

// ---------------------------------------------------------------------------
// Handler-level failures through the REAL handler + adapters + policy
// ---------------------------------------------------------------------------

function realPlatform(admin: AdminClientLike, client: UserClientLike): HandlerPlatform {
  return createPlatform({ supabaseUrl: "u", supabaseAnonKey: "a", serviceRoleKey: "s" }, (_u, k) => (k === "s" ? admin : client));
}

Deno.test("handler: barrier RPC failure is a 500 before anything is deleted (no table, storage, profile or auth call)", async () => {
  const { admin, log } = fakeAdmin({ rpc: { begin_account_deletion: { data: null, error: { message: "function begin_account_deletion does not exist" } } } });
  const { client, calls } = fakeUser({ data: { success: true }, error: null });
  const res = await handleDeleteAccount(post({}), realPlatform(admin, client));
  assert.equal(res.status, 500);
  const body = await res.json();
  assert.equal(body.error, "Account deletion could not start");
  assert.deepEqual(body.failed_steps, ["begin_account_deletion"]);
  assert.deepEqual(log, [`rpc:begin_account_deletion:${JSON.stringify({ p_user_id: USER })}`], "only the barrier was attempted");
  assert.deepEqual(calls, [], "the user-JWT RPC did not run either");
});

Deno.test("handler: partial cleanup (club step fails) is a 500 that keeps the auth user; the retry through the handler finishes", async () => {
  const failing = fakeAdmin({ rpc: { delete_account_club_memberships: { data: null, error: { message: "deadlock detected" } } } });
  const { client } = fakeUser({ data: { success: true }, error: null });
  const first = await handleDeleteAccount(post({}), realPlatform(failing.admin, client));
  assert.equal(first.status, 500);
  const body = await first.json();
  assert.equal(body.error, "Account cleanup incomplete");
  assert.deepEqual(body.failed_steps, ["club_memberships"]);
  assert.equal(failing.log.some((l) => l.startsWith("deleteUser:")), false, "auth user must not be deleted");
  assert.ok(failing.log.includes("delete:anime_user_lists"), "the other required steps still ran");

  const fixed = fakeAdmin();
  const second = await handleDeleteAccount(post({}), realPlatform(fixed.admin, client));
  assert.equal(second.status, 200);
  assert.deepEqual(await second.json(), { success: true });
  assert.equal(fixed.log[fixed.log.length - 1], `deleteUser:${USER}`);
});
