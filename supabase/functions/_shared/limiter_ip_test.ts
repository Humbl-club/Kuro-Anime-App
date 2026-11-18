import { assert, assertEquals, assertNotEquals, assertRejects } from "jsr:@std/assert@1";
import { limiterIpBucket, limiterSecretFromEnv } from "./limiter_ip.ts";

Deno.test("bucket is keyed: never contains the address, differs by secret, stable per secret", async () => {
  const a = await limiterIpBucket("203.0.113.7", "secret-one");
  const again = await limiterIpBucket("203.0.113.7", "secret-one");
  const other = await limiterIpBucket("203.0.113.7", "secret-two");
  assert(a !== null && other !== null);
  assertEquals(a, again);
  assertNotEquals(a, other);
  assert(!a.includes("203.0.113.7"));
  assert(/^c1:[0-9a-f]{32}$/.test(a));
  assert(a.length <= 128);
});

Deno.test("different addresses get different buckets; case and whitespace are normalised", async () => {
  assertNotEquals(await limiterIpBucket("203.0.113.7", "s"), await limiterIpBucket("203.0.113.8", "s"));
  assertEquals(await limiterIpBucket(" 2001:DB8::1 ", "s"), await limiterIpBucket("2001:db8::1", "s"));
});

Deno.test("no address -> null (user-only limiting), even without a secret", async () => {
  assertEquals(await limiterIpBucket(null, undefined), null);
  assertEquals(await limiterIpBucket("", "s"), null);
});

Deno.test("an address without a secret fails closed instead of falling back to the raw value", async () => {
  await assertRejects(() => limiterIpBucket("203.0.113.7", undefined));
  await assertRejects(() => limiterIpBucket("203.0.113.7", ""));
});

Deno.test("secret source: CONTACT_IP_HASH_SECRET first, then service key, else undefined", () => {
  const env = (m: Record<string, string>) => (n: string) => m[n];
  assertEquals(limiterSecretFromEnv(env({ CONTACT_IP_HASH_SECRET: "c", SUPABASE_SERVICE_ROLE_KEY: "s" })), "c");
  assertEquals(limiterSecretFromEnv(env({ SUPABASE_SERVICE_ROLE_KEY: "s" })), "s");
  assertEquals(limiterSecretFromEnv(env({})), undefined);
});
