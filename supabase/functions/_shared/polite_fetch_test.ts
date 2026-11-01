// Offline tests for the polite JSON client used for MangaUpdates. Fake fetch and clock.
// Run: deno test --no-prompt supabase/functions/_shared/polite_fetch_test.ts
import { strict as assert } from "node:assert";
import { createPoliteClient, isPoliteCleanStop, PoliteFetchError, PoliteLimiter, readBounded } from "./polite_fetch.ts";

function harness(replies: { status?: number; body?: unknown; headers?: Record<string, string> }[]) {
  let clock = 0;
  const sleeps: number[] = [];
  let requests = 0;
  const client = createPoliteClient({
    limiter: new PoliteLimiter(1_000),
    now: () => clock,
    sleep: (ms) => {
      sleeps.push(ms);
      clock += ms;
      return Promise.resolve();
    },
    random: () => 0,
    fetch: () => {
      requests++;
      const r = replies.shift();
      if (!r) return Promise.reject(new Error("unexpected request"));
      return Promise.resolve(new Response(r.body === undefined ? "" : JSON.stringify(r.body), { status: r.status ?? 200, headers: r.headers }));
    },
  });
  return { client, sleeps, now: () => clock, requests: () => requests };
}

Deno.test("requests are spaced by the limiter interval", async () => {
  const h = harness([{ body: { a: 1 } }, { body: { a: 2 } }]);
  await h.client.request("https://example.test/1", {});
  const second = await h.client.request("https://example.test/2", {});
  assert.deepEqual(second, { status: 200, json: { a: 2 } });
  assert.deepEqual(h.sleeps, [1000]);
});

Deno.test("a 429 honours Retry-After before retrying", async () => {
  const h = harness([{ status: 429, headers: { "Retry-After": "5" } }, { body: { ok: true } }]);
  const res = await h.client.request("https://example.test/x", {});
  assert.equal(res.status, 200);
  assert.ok(h.sleeps.includes(5000));
});

Deno.test("a pause beyond the deadline is a clean stop without another request", async () => {
  const h = harness([{ status: 429, headers: { "Retry-After": "120" } }]);
  let caught: unknown;
  try {
    await h.client.request("https://example.test/x", {}, h.now() + 10_000);
  } catch (e) {
    caught = e;
  }
  assert.ok(caught instanceof PoliteFetchError);
  assert.equal(isPoliteCleanStop(caught), true);
  assert.equal(h.requests(), 1);
});

Deno.test("a 404 is returned to the caller, not retried", async () => {
  const h = harness([{ status: 404, body: { reason: "not found" } }]);
  const res = await h.client.request("https://example.test/x", {});
  assert.equal(res.status, 404);
  assert.equal(h.requests(), 1);
});

Deno.test("unreadable JSON is a parse error", async () => {
  const client = createPoliteClient({
    limiter: new PoliteLimiter(0),
    sleep: () => Promise.resolve(),
    fetch: () => Promise.resolve(new Response("<html>", { status: 200 })),
  });
  await assert.rejects(() => client.request("https://example.test/x", {}), (e: unknown) => e instanceof PoliteFetchError && e.kind === "parse");
});

Deno.test("readBounded rejects a declared Content-Length over the cap before reading", async () => {
  const response = new Response("x".repeat(10), { headers: { "content-length": "10" } });
  await assert.rejects(() => readBounded(response, 5), (error: unknown) => error instanceof PoliteFetchError && error.kind === "parse");
});

Deno.test("readBounded cancels a stream that passes the cap without a Content-Length", async () => {
  let pulls = 0;
  const stream = new ReadableStream<Uint8Array>({
    pull(controller) {
      pulls++;
      controller.enqueue(new Uint8Array(4));
      if (pulls > 100) controller.close();
    },
  });
  await assert.rejects(() => readBounded(new Response(stream), 10), (error: unknown) => error instanceof PoliteFetchError);
  assert.ok(pulls < 10, `stream was read past the cap (${pulls} pulls)`);
  assert.equal(await readBounded(new Response("{\"ok\":true}"), 100), "{\"ok\":true}");
});
