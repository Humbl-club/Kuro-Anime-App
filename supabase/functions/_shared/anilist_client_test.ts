// Offline tests for the shared AniList transport. Fake fetch, fake clock; no network.
// Run: deno test --no-prompt supabase/functions/_shared/anilist_client_test.ts
import { strict as assert } from "node:assert";
import { AniListError, AniListLimiter, createAniListClient, isCleanStop, parseRetryAfter } from "./anilist_client.ts";

type Reply = { status?: number; body?: unknown; headers?: Record<string, string>; throws?: Error };

function harness(replies: Reply[], opts: { perMinute?: number; jitter?: number } = {}) {
  let clock = 1_000_000;
  const sleeps: number[] = [];
  const requests: { url: string; body: string; headers: Headers }[] = [];
  const limiter = AniListLimiter.perMinute(opts.perMinute ?? 25);
  const client = createAniListClient({
    limiter,
    now: () => clock,
    sleep: (ms) => {
      sleeps.push(ms);
      clock += ms;
      return Promise.resolve();
    },
    random: () => 0,
    jitterMs: opts.jitter ?? 0,
    fetch: (input, init) => {
      requests.push({ url: String(input), body: String(init?.body ?? ""), headers: new Headers(init?.headers) });
      const reply = replies.shift();
      if (!reply) throw new Error("unexpected request");
      if (reply.throws) return Promise.reject(reply.throws);
      return Promise.resolve(
        new Response(JSON.stringify(reply.body ?? {}), {
          status: reply.status ?? 200,
          headers: { "Content-Type": "application/json", ...(reply.headers ?? {}) },
        }),
      );
    },
  });
  return { client, sleeps, requests, limiter, advance: (ms: number) => (clock += ms), now: () => clock };
}

const PAGE_OK = { data: { Page: { media: [{ id: 1 }] } } };

Deno.test("a 200 response with GraphQL errors is an error, never an empty page", async () => {
  const h = harness([{ body: { data: null, errors: [{ message: "Internal Server Error" }] } }]);
  await assert.rejects(
    () => h.client.query("q", {}, { require: ["Page"] }),
    (e: unknown) => e instanceof AniListError && e.kind === "graphql",
  );
});

Deno.test("a 200 response without data.Page is a missing_data error", async () => {
  const h = harness([{ body: { data: { Page: null } } }]);
  await assert.rejects(
    () => h.client.query("q", {}, { require: ["Page"] }),
    (e: unknown) => e instanceof AniListError && e.kind === "missing_data",
  );
  const h2 = harness([{ body: { data: null } }]);
  await assert.rejects(() => h2.client.query("q", {}), (e: unknown) => e instanceof AniListError && e.kind === "missing_data");
});

Deno.test("requests are spaced at 25/min and send a User-Agent", async () => {
  const h = harness([{ body: PAGE_OK }, { body: PAGE_OK }, { body: PAGE_OK }]);
  for (let i = 0; i < 3; i++) await h.client.query("q", { page: i }, { require: ["Page"] });
  // First call is immediate; each following call waits the 2400 ms interval.
  assert.deepEqual(h.sleeps, [2400, 2400]);
  assert.match(h.requests[0].headers.get("user-agent") ?? "", /^Kuro-Intake\//);
});

Deno.test("a 429 honours Retry-After and pauses the whole limiter", async () => {
  const h = harness([{ status: 429, headers: { "Retry-After": "7" } }, { body: PAGE_OK }]);
  const data = await h.client.query("q", {}, { require: ["Page"] });
  assert.equal(data.Page.media[0].id, 1);
  assert.equal(h.sleeps[0], 7000);
  assert.equal(h.requests.length, 2);
});

Deno.test("a 429 pause that outlasts the deadline stops cleanly as rate_limited without a second request", async () => {
  const h = harness([{ status: 429, headers: { "Retry-After": "60" } }]);
  const deadline = h.now() + 20_000;
  let caught: unknown = null;
  try {
    await h.client.query("q", {}, { deadlineMs: deadline });
  } catch (e) {
    caught = e;
  }
  assert.ok(caught instanceof AniListError);
  assert.equal((caught as AniListError).kind, "rate_limited");
  assert.equal(isCleanStop(caught), true);
  assert.equal(h.requests.length, 1);
});

Deno.test("X-RateLimit-Remaining at 3 pauses until X-RateLimit-Reset", async () => {
  const resetSec = Math.floor((1_000_000 + 30_000) / 1000); // harness clock starts at 1_000_000 ms
  const h2 = harness([
    { body: PAGE_OK, headers: { "X-RateLimit-Remaining": "3", "X-RateLimit-Reset": String(resetSec) } },
    { body: PAGE_OK },
  ]);
  await h2.client.query("q", {});
  await h2.client.query("q", {});
  assert.ok(h2.sleeps[0] >= 29_000, `expected a reset wait, got ${h2.sleeps[0]}`);
});

Deno.test("5xx is retried with backoff; exhausted retries throw http", async () => {
  const h = harness([{ status: 503 }, { body: PAGE_OK }]);
  await h.client.query("q", {});
  assert.equal(h.requests.length, 2);
  const h2 = harness([{ status: 503 }, { status: 502 }]);
  await assert.rejects(
    () => h2.client.query("q", {}, { retries: 1 }),
    (e: unknown) => e instanceof AniListError && e.kind === "http" && e.status === 502,
  );
});

Deno.test("a network failure is retried, then reported as network", async () => {
  const h = harness([{ throws: new TypeError("connection reset") }, { throws: new TypeError("connection reset") }]);
  await assert.rejects(
    () => h.client.query("q", {}, { retries: 1 }),
    (e: unknown) => e instanceof AniListError && e.kind === "network",
  );
});

Deno.test("a wait that would pass the deadline throws budget before sending", async () => {
  const h = harness([{ body: PAGE_OK }]);
  await h.client.query("q", {});
  await assert.rejects(
    () => h.client.query("q", {}, { deadlineMs: h.now() + 1000 }),
    (e: unknown) => isCleanStop(e) && (e as AniListError).kind === "budget",
  );
  assert.equal(h.requests.length, 1);
});

Deno.test("a 4xx GraphQL validation error is not retried", async () => {
  const h = harness([{ status: 400, body: { errors: [{ message: "Cannot query field" }], data: null } }]);
  await assert.rejects(() => h.client.query("q", {}), (e: unknown) => e instanceof AniListError && e.kind === "graphql");
  assert.equal(h.requests.length, 1);
});

Deno.test("Retry-After accepts seconds and HTTP dates", () => {
  assert.equal(parseRetryAfter("5", 0), 5000);
  assert.equal(parseRetryAfter(null, 0), null);
  const now = Date.parse("2026-11-01T10:00:00Z");
  assert.equal(parseRetryAfter("Sun, 01 Nov 2026 10:00:30 GMT", now), 30_000);
  assert.equal(parseRetryAfter("soon", now), null);
});
