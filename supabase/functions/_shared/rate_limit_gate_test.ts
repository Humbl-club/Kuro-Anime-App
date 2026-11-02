import { assertEquals } from "jsr:@std/assert@1";
import { gateRateLimit, interpretRateLimit, rateLimitBlockedResponse } from "./rate_limit_gate.ts";

const json = (body: unknown, init: ResponseInit = {}) =>
  new Response(JSON.stringify(body), { ...init, headers: { "Content-Type": "application/json", ...(init.headers ?? {}) } });

Deno.test("allowed result proceeds", () => {
  const decision = interpretRateLimit({ data: { allowed: true }, error: null });
  assertEquals(decision, { kind: "allowed" });
  assertEquals(rateLimitBlockedResponse(decision, json), null);
});

Deno.test("explicit denial is a 429 with Retry-After", async () => {
  const decision = interpretRateLimit({ data: { allowed: false, retry_after_s: 12.2 }, error: null });
  assertEquals(decision, { kind: "denied", retryAfterSeconds: 13 });
  const res = rateLimitBlockedResponse(decision, json)!;
  assertEquals(res.status, 429);
  assertEquals(res.headers.get("Retry-After"), "13");
  assertEquals(await res.json(), { error: "Rate limited", retry_after_s: 13 });
});

Deno.test("denial without a retry hint uses the default", () => {
  assertEquals(interpretRateLimit({ data: { allowed: false } }), { kind: "denied", retryAfterSeconds: 30 });
});

Deno.test("limiter error with null data fails closed as a retryable 503, never as allowed", async () => {
  const decision = interpretRateLimit({ data: null, error: { message: "limit database unavailable" } });
  assertEquals(decision.kind, "unavailable");
  const res = rateLimitBlockedResponse(decision, json)!;
  assertEquals(res.status, 503);
  assertEquals(res.headers.get("Retry-After"), "30");
});

Deno.test("an error alongside data is still unavailable", () => {
  assertEquals(interpretRateLimit({ data: { allowed: true }, error: { message: "x" } }).kind, "unavailable");
});

Deno.test("a thrown limiter call fails closed as a retryable 503", async () => {
  const res = await gateRateLimit(Promise.reject(new Error("rpc down")), json);
  assertEquals(res?.status, 503);
  assertEquals(res?.headers.get("Retry-After"), "30");
});

Deno.test("missing result, empty data and a shape without a boolean allowed fail closed", () => {
  assertEquals(interpretRateLimit(null).kind, "unavailable");
  assertEquals(interpretRateLimit(undefined).kind, "unavailable");
  assertEquals(interpretRateLimit({ data: null, error: null }).kind, "unavailable");
  assertEquals(interpretRateLimit({ data: {}, error: null }).kind, "unavailable");
  assertEquals(interpretRateLimit({ data: { allowed: "yes" }, error: null }).kind, "unavailable");
});
