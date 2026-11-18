"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs"),
  os = require("node:os"),
  path = require("node:path");
const { manage } = require("./backend_fixture");
const { ORIGIN } = require("./backend_workload");
const opts = { anonKey: "test-public", serviceKey: "test-private" };
function setup(t, overrides = {}) {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), "kuro-load-test-"));
  t.after(() => fs.rmSync(d, { recursive: true, force: true }));
  const file = path.join(d, "fixture.json");
  const f = {
    origin: ORIGIN,
    runId: "kuro-load-test",
    accounts: [{
      id: "id1",
      email: "kuro-load-test-a@example.invalid",
      token: "own-token",
    }],
    clubs: [],
    media: {},
    ...overrides,
  };
  fs.writeFileSync(file, JSON.stringify(f), { mode: 0o600 });
  return file;
}
test("cleanup refuses a mismatched provenance before any deletion", async (t) => {
  const file = setup(t);
  const methods = [];
  await assert.rejects(() =>
    manage("cleanup", file, {
      ...opts,
      fetcher: async (url, init) => {
        methods.push(init.method);
        return new Response(
          JSON.stringify({
            id: "id1",
            email: "customer@example.invalid",
            app_metadata: {},
          }),
          { status: 200 },
        );
      },
    }), /provenance mismatch/);
  assert.deepEqual(methods, ["GET"]);
});
test("cleanup refuses a token for a different account", async (t) => {
  const file = setup(t);
  let calls = 0;
  await assert.rejects(() =>
    manage("cleanup", file, {
      ...opts,
      fetcher: async () =>
        new Response(
          JSON.stringify(
            ++calls === 1
              ? {
                id: "id1",
                email: "kuro-load-test-a@example.invalid",
                app_metadata: { kuro_load_fixture: "kuro-load-test" },
              }
              : { id: "other" },
          ),
          { status: 200 },
        ),
    }), /token identity mismatch/);
  assert.equal(calls, 2);
});
test("already absent identities are acknowledged without a deletion request", async (t) => {
  const file = setup(t);
  let calls = 0;
  const r = await manage("cleanup", file, {
    ...opts,
    fetcher: async () => {
      calls++;
      return new Response("{}", { status: 404 });
    },
  });
  assert.equal(calls, 1);
  assert.equal(r.accountsRemoved, 1);
  assert.equal(JSON.parse(fs.readFileSync(file)).accounts[0].token, undefined);
});
test("lookalike origins and customer inventories fail before network access", async (t) => {
  const file = setup(t, { origin: ORIGIN + ".evil.invalid" });
  let called = false;
  await assert.rejects(() =>
    manage("cleanup", file, {
      ...opts,
      fetcher: () => {
        called = true;
      },
    }), /Invalid disposable inventory/);
  assert.equal(called, false);
});
test("catalogue seeds page through the PostgREST1000-row cap", async (t) => {
  const file = setup(t, {
    accounts: [{
      id: "id1",
      email: "kuro-load-test-a@example.invalid",
      token: "own-token",
      seeded: true,
      librarySize: 25,
    }],
    media: { anime: [1], manga: [1] },
  });
  const offsets = [];
  const result = await manage("setup", file, {
    ...opts,
    accounts: 1,
    fetcher: async (raw) => {
      const u = new URL(raw);
      assert.equal(u.searchParams.get("limit"), "1000");
      const offset = Number(u.searchParams.get("offset"));
      offsets.push(offset);
      return new Response(
        JSON.stringify(
          Array.from({ length: 1000 }, (_, i) => ({ id: offset + i + 1 })),
        ),
        { status: 200 },
      );
    },
  });
  assert.deepEqual(offsets, [0, 1000, 0, 1000]);
  assert.equal(JSON.parse(fs.readFileSync(file)).media.anime.length, 2000);
  assert.equal(result.seeded, 1);
});
test("resume refresh reads current revisions with the owner's token and makes no backend writes", async (t) => {
  const file = setup(t, {
    accounts: [{
      id: "id1",
      email: "kuro-load-test-a@example.invalid",
      token: "own-token",
      librarySize: 25,
      writeEntry: { revision: 1 },
    }],
  });
  const r = await manage("refresh", file, {
    ...opts,
    fetcher: async (url, init) => {
      assert.equal(init.method, "GET");
      assert.equal(init.headers.Authorization, "Bearer own-token");
      return new Response(
        JSON.stringify([{
          user_id: "id1",
          anime_id: 7,
          lifecycle_id: "life",
          server_revision: 9,
          progress: 3,
        }]),
        { status: 200 },
      );
    },
  });
  assert.equal(r.changedRevisions, 1);
  assert.equal(
    JSON.parse(fs.readFileSync(file)).accounts[0].writeEntry.revision,
    9,
  );
});
const xProfile = (over = {}) => ({
  name: "x-test",
  librarySizes: [25],
  writes: true,
  seed: async ({ actor, call }) => {
    await call("/rest/v1/x_rows", [{ a: 1 }], { token: actor.token });
    return { rowId: 5, mediaId: 77 };
  },
  cleanupCheck: async () => true,
  ...over,
});
const sizedAccount = (over = {}) => ({
  id: "id1",
  email: "kuro-load-test-a@example.invalid",
  token: "own-token",
  librarySize: 25,
  seeded: true,
  ...over,
});
test("seed-profiles seeds once per covered actor and refresh keeps profile state", async (t) => {
  const file = setup(t, {
    accounts: [sizedAccount(), sizedAccount({ id: "id2", token: "tok2", email: "kuro-load-test-b@example.invalid", librarySize: 0 })],
  });
  const seen = [];
  const fetcher = async (url, init) => {
    seen.push({ url, method: init.method, auth: init.headers.Authorization });
    if (new URL(url).pathname === "/rest/v1/anime_user_lists") {
      if (init.headers.Authorization === "Bearer tok2") return new Response("[]", { status: 200 });
      assert.equal(new URL(url).searchParams.get("anime_id"), "not.in.(77)");
      return new Response(JSON.stringify([{ user_id: "id1", anime_id: 7, lifecycle_id: "l", server_revision: 3, progress: 1 }]), { status: 200 });
    }
    return new Response("{}", { status: 200 });
  };
  const profiles = { "x-test": xProfile() };
  const first = await manage("seed-profiles", file, { ...opts, profiles, fetcher });
  assert.deepEqual(first.seeded, { "x-test": 1 });
  assert.equal(seen.length, 1);
  assert.equal(seen[0].auth, "Bearer own-token");
  const stored = JSON.parse(fs.readFileSync(file)).accounts;
  assert.deepEqual(stored[0].profileState, { "x-test": { rowId: 5, mediaId: 77 } });
  assert.equal(stored[1].profileState, undefined);
  const second = await manage("seed-profiles", file, { ...opts, profiles, fetcher });
  assert.deepEqual(second.seeded, { "x-test": 0 });
  assert.equal(seen.length, 1);
  await manage("refresh", file, { ...opts, accounts: 1, fetcher });
  const after = JSON.parse(fs.readFileSync(file)).accounts[0];
  assert.deepEqual(after.profileState, { "x-test": { rowId: 5, mediaId: 77 } });
  assert.equal(after.writeEntry.mediaId, 7);
});
test("seed-profiles requires a completed setup", async (t) => {
  const file = setup(t, { accounts: [sizedAccount({ seeded: false })] });
  await assert.rejects(() => manage("seed-profiles", file, { ...opts, profiles: { "x-test": xProfile() }, fetcher: () => { throw new Error("no network"); } }), /setup/);
});
test("cleanup verifies profile data is absent", async (t) => {
  const absent = () => new Response("{}", { status: 404 });
  const withState = () => setup(t, { accounts: [sizedAccount({ profileState: { "x-test": { rowId: 5, mediaId: 77 } } })] });
  const file = withState();
  const r = await manage("cleanup", file, { ...opts, profiles: { "x-test": xProfile() }, fetcher: async () => absent() });
  assert.deepEqual(r.cleanup[0].profileData, { "x-test": "absent" });
  const file2 = withState();
  await assert.rejects(() => manage("cleanup", file2, {
    ...opts, profiles: { "x-test": xProfile({ cleanupCheck: async () => false }) }, fetcher: async () => absent(),
  }), /Profile data cleanup not confirmed \(x-test, account 0\)/);
  // An unregistered profile name stops cleanup before any request is made.
  const file3 = withState();
  let calls = 0;
  await assert.rejects(() => manage("cleanup", file3, { ...opts, profiles: {}, fetcher: async () => { calls++; return absent(); } }), /cleanup cannot verify unregistered profile x-test/);
  assert.equal(calls, 0);
});
test("refresh refuses a missing user token before making an administrative fallback read", async (t) => {
  const file = setup(t, {
    accounts: [{
      id: "id1",
      email: "kuro-load-test-a@example.invalid",
      librarySize: 25,
    }],
  });
  let calls = 0;
  await assert.rejects(() =>
    manage("refresh", file, {
      ...opts,
      fetcher: () => {
        calls++;
      },
    }), /active fixture/);
  assert.equal(calls, 0);
});
