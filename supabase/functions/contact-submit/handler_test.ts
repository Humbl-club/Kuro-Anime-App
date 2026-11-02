// Offline tests for contact-submit (handler.ts) with in-memory fakes: no network, no database.
// The SQL side (table posture, constraints, purge) is tested in supabase/tests/rls/93_contact_messages.sql.
// Run: deno test --no-prompt supabase/functions/contact-submit/
import { strict as assert } from "node:assert";
import {
  type ContactNotification,
  type ContactPlatform,
  classifyAuthorization,
  handleContactSubmit,
  hashIp,
  ipBucketKey,
  isAllowedOrigin,
  LIMITS,
  validateContact,
} from "./handler.ts";

const ANON_KEY = "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.sig"; // {"role":"anon"}
const USER_TOKEN = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyLTEiLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.sig";
const USER_ID = "11111111-1111-4111-8111-111111111111";

const VALID = {
  topic: "support",
  email: "fan@example.com",
  name: "Aiko",
  message: "Hello,\nthe reminder did not fire.",
  locale: "de-DE",
  app_version: "1.4 (220)",
  website: "",
  consent: true,
};

interface RpcCall {
  fn: string;
  args: Record<string, unknown>;
  authHeader: string | null;
}

class Fakes {
  inserts: Record<string, unknown>[] = [];
  rpcCalls: RpcCall[] = [];
  getUserTokens: string[] = [];
  notifications: ContactNotification[] = [];
  /** Default limiter reply; `limiterByKind` overrides it per p_kind. */
  limiterReply: { data: unknown; error: unknown } = { data: { allowed: true }, error: null };
  limiterByKind = new Map<string, { data: unknown; error: unknown }>();
  limiterThrows = false;
  insertError: unknown = null;
  notifyBehaviour: "ok" | "throw" | "off" = "ok";
  validUserTokens = new Map<string, string>([[USER_TOKEN, USER_ID]]);
  ipHashSecret: string | null = "test-secret";

  platform(): ContactPlatform {
    return {
      anonKey: ANON_KEY,
      callerClient: (authHeader) => ({
        auth: {
          getUser: (token: string) => {
            this.getUserTokens.push(token);
            const id = this.validUserTokens.get(token);
            return Promise.resolve(id
              ? { data: { user: { id } }, error: null }
              : { data: { user: null }, error: { message: "invalid JWT" } });
          },
        },
        rpc: (fn: string, args: Record<string, unknown>) => {
          this.rpcCalls.push({ fn, args, authHeader });
          if (this.limiterThrows) return Promise.reject(new Error("network"));
          return Promise.resolve(this.limiterByKind.get(String(args.p_kind)) ?? this.limiterReply);
        },
      }),
      serviceClient: () => ({
        from: (table: string) => ({
          insert: (row: Record<string, unknown>) => {
            assert.equal(table, "contact_messages");
            if (!this.insertError) this.inserts.push(row);
            return Promise.resolve({ error: this.insertError });
          },
        }),
      }),
      ipHashSecret: this.ipHashSecret,
      notify: this.notifyBehaviour === "off" ? null : (n) => {
        this.notifications.push(n);
        return this.notifyBehaviour === "throw" ? Promise.reject(new Error("resend down")) : Promise.resolve();
      },
      newId: () => "00000000-0000-4000-8000-0000000000aa",
    };
  }
}

function post(body: unknown, headers: Record<string, string> = {}): Request {
  return new Request("https://example.test/functions/v1/contact-submit", {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-forwarded-for": "203.0.113.7, 10.0.0.1", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

async function call(f: Fakes, req: Request) {
  const res = await handleContactSubmit(req, f.platform());
  const text = await res.text();
  return { status: res.status, headers: res.headers, body: text ? JSON.parse(text) : null };
}

// ---------------------------------------------------------------- validation

Deno.test("validation: a complete submission is accepted and trimmed", () => {
  const r = validateContact({ ...VALID, email: "  fan@example.com ", name: "   " });
  assert.ok(r.ok);
  assert.equal(r.value.email, "fan@example.com");
  assert.equal(r.value.name, null, "blank name becomes null");
  assert.equal(r.value.topic, "support");
});

Deno.test("validation: every invalid field is listed in a stable order", () => {
  const r = validateContact({
    topic: "spam",
    email: "not-an-email",
    name: "x".repeat(LIMITS.name + 1),
    message: "   ",
    locale: "deutsch-und-mehr",
    app_version: "1.0\n2",
    consent: "yes",
  });
  assert.deepEqual(r, { ok: false, fields: ["topic", "email", "name", "message", "locale", "app_version", "consent"] });
});

Deno.test("validation: length boundaries for message and email", () => {
  assert.ok(validateContact({ ...VALID, message: "m".repeat(LIMITS.message) }).ok);
  assert.deepEqual(validateContact({ ...VALID, message: "m".repeat(LIMITS.message + 1) }), { ok: false, fields: ["message"] });
  const local = "a".repeat(LIMITS.email - "@example.com".length);
  assert.ok(validateContact({ ...VALID, email: `${local}@example.com` }).ok);
  assert.deepEqual(validateContact({ ...VALID, email: `a${local}@example.com` }), { ok: false, fields: ["email"] });
});

Deno.test("validation: header-injection characters in email or name are rejected", () => {
  assert.deepEqual(validateContact({ ...VALID, email: "a@example.com\r\nBcc: x@evil.test" }), { ok: false, fields: ["email"] });
  assert.deepEqual(validateContact({ ...VALID, name: "Aiko\r\nX" }), { ok: false, fields: ["name"] });
});

Deno.test("validation: consent must be literally true; non-object bodies are invalid", () => {
  assert.deepEqual(validateContact({ ...VALID, consent: false }), { ok: false, fields: ["consent"] });
  assert.deepEqual(validateContact({ ...VALID, consent: undefined }), { ok: false, fields: ["consent"] });
  assert.deepEqual(validateContact([VALID]), { ok: false, fields: ["body"] });
  assert.deepEqual(validateContact(null), { ok: false, fields: ["body"] });
});

Deno.test("handler: invalid body is 400 with fields; nothing stored, no limiter hit", async () => {
  const f = new Fakes();
  const res = await call(f, post({ ...VALID, topic: "nope", consent: false }));
  assert.equal(res.status, 400);
  assert.deepEqual(res.body, { error: "invalid", fields: ["topic", "consent"] });
  assert.equal(f.inserts.length, 0);
  assert.equal(f.rpcCalls.length, 0);
});

Deno.test("handler: malformed JSON and oversized bodies are 400 body", async () => {
  const f = new Fakes();
  assert.deepEqual((await call(f, post("{not json"))).body, { error: "invalid", fields: ["body"] });
  const huge = await call(f, post({ ...VALID, message: "x".repeat(LIMITS.body) }));
  assert.equal(huge.status, 400);
  assert.deepEqual(huge.body, { error: "invalid", fields: ["body"] });
  assert.equal(f.inserts.length, 0);
});

Deno.test("body cap: a declared or streamed body over the cap is 400 without being buffered whole", async () => {
  const f = new Fakes();
  const declared = await call(f, post(VALID, { "Content-Length": String(LIMITS.body + 1) }));
  assert.equal(declared.status, 400);
  assert.deepEqual(declared.body, { error: "invalid", fields: ["body"] });

  let pulled = 0;
  const endless = new ReadableStream<Uint8Array>({
    pull(controller) {
      pulled += 1;
      controller.enqueue(new Uint8Array(4096).fill(0x61));
      if (pulled > 1000) controller.close();
    },
  });
  const streamed = await call(f, new Request("https://example.test/functions/v1/contact-submit", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: endless,
  }));
  assert.equal(streamed.status, 400);
  assert.ok(pulled <= Math.ceil(LIMITS.body / 4096) + 2, `stopped reading early (pulled ${pulled} chunks)`);
  assert.equal(f.inserts.length, 0);
});

// ---------------------------------------------------------------- honeypot

Deno.test("honeypot: a filled website field is answered 200 ok and nothing is stored or sent", async () => {
  const f = new Fakes();
  const res = await call(f, post({ ...VALID, website: "https://spam.test" }));
  assert.equal(res.status, 200);
  assert.deepEqual(res.body, { ok: true });
  assert.equal(f.inserts.length, 0);
  assert.equal(f.rpcCalls.length, 0);
  assert.equal(f.notifications.length, 0);
});

Deno.test("honeypot: even an otherwise invalid bot submission gets the silent 200", async () => {
  const f = new Fakes();
  const res = await call(f, post({ website: "x" }));
  assert.equal(res.status, 200);
  assert.equal(f.inserts.length, 0);
});

// ---------------------------------------------------------------- identity

Deno.test("web: anon-key bearer stores source web with no user and never calls getUser", async () => {
  const f = new Fakes();
  const res = await call(f, post(VALID, { Authorization: `Bearer ${ANON_KEY}`, apikey: ANON_KEY, Origin: "https://kuro.app" }));
  assert.equal(res.status, 200);
  assert.deepEqual(res.body, { ok: true });
  assert.equal(f.getUserTokens.length, 0);
  assert.equal(f.inserts.length, 1);
  assert.deepEqual(f.inserts[0], {
    id: "00000000-0000-4000-8000-0000000000aa",
    source: "web",
    topic: "support",
    email: "fan@example.com",
    name: "Aiko",
    message: "Hello,\nthe reminder did not fire.",
    user_id: null,
    app_version: "1.4 (220)",
    locale: "de-DE",
  });
  assert.equal(res.headers.get("Access-Control-Allow-Origin"), "https://kuro.app");
});

Deno.test("app: user_id comes from the verified JWT only; a body user_id is ignored", async () => {
  const f = new Fakes();
  const res = await call(f, post({ ...VALID, user_id: "99999999-9999-4999-8999-999999999999", source: "web" }, {
    Authorization: `Bearer ${USER_TOKEN}`,
  }));
  assert.equal(res.status, 200);
  assert.deepEqual(f.getUserTokens, [USER_TOKEN]);
  assert.equal(f.inserts[0].user_id, USER_ID);
  assert.equal(f.inserts[0].source, "app");
  // Every limiter call runs on the anon client with an explicit key (no implicit auth.uid() bucket).
  assert.ok(f.rpcCalls.every((c) => c.authHeader === null));
  assert.deepEqual(f.rpcCalls.map((c) => c.args.p_kind), ["contact_app_ip", "contact_user", "contact_notify"]);
  // Bucket names are secret-keyed: the limiter RPC is anon-callable, so a guessable key could be filled by anyone.
  assert.equal(f.rpcCalls[1].args.p_ip, `contact:${await hashIp(`user:${USER_ID}`, "test-secret")}`);
  assert.ok(!String(f.rpcCalls[1].args.p_ip).includes(USER_ID));
  assert.equal(f.rpcCalls[1].args.p_max_user, 5);
  assert.equal(f.rpcCalls[1].args.p_max_ip, 5);
});

Deno.test("app: an invalid user token is 401 and nothing is stored (its IP bucket was counted first)", async () => {
  const f = new Fakes();
  const res = await call(f, post(VALID, { Authorization: "Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.forged" }));
  assert.equal(res.status, 401);
  assert.deepEqual(res.body, { error: "unauthorized" });
  assert.equal(f.inserts.length, 0);
  assert.deepEqual(f.rpcCalls.map((c) => c.args.p_kind), ["contact_app_ip"]);
});

Deno.test("app: forged-token floods are throttled by the IP bucket before getUser runs", async () => {
  const f = new Fakes();
  f.limiterByKind.set("contact_app_ip", { data: { allowed: false, retry_after_s: 900 }, error: null });
  const res = await call(f, post(VALID, { Authorization: "Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.forged" }));
  assert.equal(res.status, 429);
  assert.equal(f.getUserTokens.length, 0, "no GoTrue call once the IP bucket is spent");
  assert.equal(f.inserts.length, 0);
});

Deno.test("app: a verified user's IP bucket allows 30/hour (carrier-grade NAT), web stays at 5", async () => {
  const app = new Fakes();
  await call(app, post(VALID, { Authorization: `Bearer ${USER_TOKEN}` }));
  assert.equal(app.rpcCalls[0].args.p_kind, "contact_app_ip");
  assert.equal(app.rpcCalls[0].args.p_max_ip, 30);
  assert.equal(app.inserts.length, 1);

  const web = new Fakes();
  await call(web, post(VALID));
  assert.equal(web.rpcCalls[0].args.p_kind, "contact");
  assert.equal(web.rpcCalls[0].args.p_max_ip, 5);
  // The two IP buckets share the hashed address but not the kind, so their counters are separate.
  assert.equal(web.rpcCalls[0].args.p_ip, app.rpcCalls[0].args.p_ip);
});

Deno.test("app: the per-account bucket denies with 429 and nothing is stored", async () => {
  const f = new Fakes();
  f.limiterByKind.set("contact_user", { data: { allowed: false, retry_after_s: 60 }, error: null });
  const res = await call(f, post(VALID, { Authorization: `Bearer ${USER_TOKEN}` }));
  assert.equal(res.status, 429);
  assert.equal(f.inserts.length, 0);
});

Deno.test("app: the web-only global ceiling never blocks a verified user", async () => {
  const f = new Fakes();
  f.limiterByKind.set("contact_global", { data: { allowed: false, retry_after_s: 60 }, error: null });
  const res = await call(f, post(VALID, { Authorization: `Bearer ${USER_TOKEN}` }));
  assert.equal(res.status, 200);
  assert.ok(!f.rpcCalls.some((c) => c.args.p_kind === "contact_global"));
  assert.equal(f.inserts.length, 1);
});

Deno.test("classifyAuthorization: missing, anon key, publishable key and anon-role JWT are anonymous", () => {
  assert.deepEqual(classifyAuthorization(null, ANON_KEY), { kind: "anonymous" });
  assert.deepEqual(classifyAuthorization(`Bearer ${ANON_KEY}`, ANON_KEY), { kind: "anonymous" });
  assert.deepEqual(classifyAuthorization("Bearer sb_publishable_abc", ANON_KEY), { kind: "anonymous" });
  assert.deepEqual(classifyAuthorization(`Bearer ${ANON_KEY}`, null), { kind: "anonymous" }, "role anon even without env");
  assert.deepEqual(classifyAuthorization(`Bearer ${USER_TOKEN}`, ANON_KEY), { kind: "user", token: USER_TOKEN });
  assert.deepEqual(classifyAuthorization("Bearer opaque", ANON_KEY), { kind: "user", token: "opaque" });
});

// ---------------------------------------------------------------- rate limit

Deno.test("rate limit: web is kind contact, 5/hour, keyed-hash IP (never the raw IP), then the global ceiling", async () => {
  const f = new Fakes();
  await call(f, post(VALID));
  assert.deepEqual(f.rpcCalls.map((c) => c.args.p_kind), ["contact", "contact_global", "contact_notify"]);
  const { fn, args } = f.rpcCalls[0];
  assert.equal(fn, "check_concierge_rate_limit");
  assert.equal(args.p_window_seconds, 3600);
  assert.equal(args.p_max_ip, 5);
  assert.equal(args.p_ip, `contact:${await hashIp("203.0.113.7", "test-secret")}`);
  assert.ok(!String(args.p_ip).includes("203.0.113.7"));
  assert.equal(f.rpcCalls[1].args.p_ip, `contact:${await hashIp("global", "test-secret")}`);
  assert.notEqual(f.rpcCalls[1].args.p_ip, "contact:global");
  assert.equal(f.rpcCalls[1].args.p_max_ip, 200);
  assert.ok(f.rpcCalls.every((c) => c.authHeader === null), "limiter always on the anon client");
});

Deno.test("rate limit: no IP header still uses a (fixed) IP bucket so the limiter cannot skip", async () => {
  const f = new Fakes();
  const req = new Request("https://example.test/functions/v1/contact-submit", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(VALID),
  });
  await call(f, req);
  assert.equal(f.rpcCalls[0].args.p_ip, `contact:${await hashIp("unknown", "test-secret")}`);
});

Deno.test("rate limit: IPv6 addresses of one /64 share a bucket; another /64 does not", async () => {
  const bucketFor = async (ip: string) => {
    const f = new Fakes();
    await call(f, post(VALID, { "x-forwarded-for": ip }));
    return f.rpcCalls[0].args.p_ip;
  };
  const a = await bucketFor("2001:db8:abcd:12::1");
  assert.equal(await bucketFor("2001:db8:abcd:12:ffff:ffff:ffff:fffe"), a);
  assert.equal(await bucketFor("2001:0DB8:ABCD:0012:0:0:0:99"), a, "expanded and upper-case forms are the same /64");
  assert.notEqual(await bucketFor("2001:db8:abcd:13::1"), a);
  assert.equal(a, `contact:${await hashIp("2001:db8:abcd:12::/64", "test-secret")}`);
});

Deno.test("ipBucketKey: IPv4 whole, IPv6 /64, IPv4-mapped as IPv4, brackets/zones/ports dropped", () => {
  assert.equal(ipBucketKey("203.0.113.7"), "203.0.113.7");
  assert.equal(ipBucketKey("203.0.113.7:51234"), "203.0.113.7");
  assert.equal(ipBucketKey("2001:db8::1"), "2001:db8:0:0::/64");
  assert.equal(ipBucketKey("[2001:db8:1:2:3:4:5:6]:443"), "2001:db8:1:2::/64");
  assert.equal(ipBucketKey("fe80::1%en0"), "fe80:0:0:0::/64");
  assert.equal(ipBucketKey("::ffff:203.0.113.7"), "203.0.113.7");
  assert.equal(ipBucketKey("::ffff:cb00:7107"), "203.0.113.7");
  assert.equal(ipBucketKey("::1"), "0:0:0:0::/64");
  assert.equal(ipBucketKey("2001:db8::"), "2001:db8:0:0::/64");
  assert.equal(ipBucketKey("64:ff9b::203.0.113.7"), "64:ff9b:0:0::/64");
  assert.equal(ipBucketKey("unknown"), "unknown");
  assert.equal(ipBucketKey("1:2:3:4:5:6:7:8:9"), "1:2:3:4:5:6:7:8:9", "unparsable stays one bucket");
  assert.equal(ipBucketKey("1::2::3"), "1::2::3");
});

Deno.test("rate limit: the web global ceiling answers 429 and stores nothing", async () => {
  const f = new Fakes();
  f.limiterByKind.set("contact_global", { data: { allowed: false, retry_after_s: 1800 }, error: null });
  const res = await call(f, post(VALID));
  assert.equal(res.status, 429);
  assert.deepEqual(res.body, { error: "rate_limited", retry_after_s: 1800 });
  assert.equal(f.inserts.length, 0);
  assert.equal(f.notifications.length, 0);
});

Deno.test("rate limit: a request denied by its IP bucket never spends the global budget", async () => {
  const f = new Fakes();
  f.limiterByKind.set("contact", { data: { allowed: false, retry_after_s: 10 }, error: null });
  await call(f, post(VALID));
  assert.deepEqual(f.rpcCalls.map((c) => c.args.p_kind), ["contact"]);
});

Deno.test("rate limit: denied is 429 rate_limited with Retry-After; nothing stored or sent", async () => {
  const f = new Fakes();
  f.limiterReply = { data: { allowed: false, retry_after_s: 1200 }, error: null };
  const res = await call(f, post(VALID));
  assert.equal(res.status, 429);
  assert.deepEqual(res.body, { error: "rate_limited", retry_after_s: 1200 });
  assert.equal(res.headers.get("Retry-After"), "1200");
  assert.equal(f.inserts.length, 0);
  assert.equal(f.notifications.length, 0);
});

Deno.test("rate limit: limiter error, thrown call or unknown shape fails closed with 500", async () => {
  for (const setup of [
    (f: Fakes) => f.limiterReply = { data: null, error: { message: "boom" } },
    (f: Fakes) => f.limiterThrows = true,
    (f: Fakes) => f.limiterReply = { data: { allowed: "maybe" }, error: null },
  ]) {
    const f = new Fakes();
    setup(f);
    const res = await call(f, post(VALID));
    assert.equal(res.status, 500);
    assert.deepEqual(res.body, { error: "internal" });
    assert.equal(f.inserts.length, 0);
  }
});

// ---------------------------------------------------------------- e-mail

Deno.test("email: notification carries topic, source, reply-to and message, no secret", async () => {
  const f = new Fakes();
  const res = await call(f, post(VALID, { Authorization: `Bearer ${USER_TOKEN}` }));
  assert.equal(res.status, 200);
  assert.equal(f.notifications.length, 1);
  const n = f.notifications[0];
  assert.equal(n.subject, "[Kuro contact] support (app)");
  assert.equal(n.replyTo, "fan@example.com");
  assert.ok(n.text.includes("Hello,\nthe reminder did not fire."));
  assert.ok(n.text.includes("Topic:       support"));
  assert.ok(n.text.includes(`yes (user ${USER_ID})`));
  for (const secret of ["test-secret", ANON_KEY, USER_TOKEN]) assert.ok(!n.text.includes(secret));
});

Deno.test("email: beyond the hourly notification ceiling the message is stored without an e-mail", async () => {
  const f = new Fakes();
  f.limiterByKind.set("contact_notify", { data: { allowed: false, retry_after_s: 60 }, error: null });
  const res = await call(f, post(VALID));
  assert.equal(res.status, 200);
  assert.equal(f.inserts.length, 1);
  assert.equal(f.notifications.length, 0);
  const notifyCall = f.rpcCalls.find((c) => c.args.p_kind === "contact_notify");
  assert.equal(notifyCall?.args.p_ip, `contact:${await hashIp("global:notify", "test-secret")}`);
  assert.equal(notifyCall?.args.p_max_ip, 50);
});

Deno.test("email: an unavailable notification limiter stores the message and skips the e-mail", async () => {
  const f = new Fakes();
  f.limiterByKind.set("contact_notify", { data: null, error: { message: "boom" } });
  const res = await call(f, post(VALID));
  assert.equal(res.status, 200);
  assert.equal(f.inserts.length, 1);
  assert.equal(f.notifications.length, 0);
});

Deno.test("email: not configured still stores and answers 200 (no notification limiter call)", async () => {
  const f = new Fakes();
  f.notifyBehaviour = "off";
  const res = await call(f, post(VALID));
  assert.equal(res.status, 200);
  assert.equal(f.inserts.length, 1);
  assert.ok(!f.rpcCalls.some((c) => c.args.p_kind === "contact_notify"));
});

Deno.test("email: a failing provider never fails the request (stored, 200)", async () => {
  const f = new Fakes();
  f.notifyBehaviour = "throw";
  const res = await call(f, post(VALID));
  assert.equal(res.status, 200);
  assert.deepEqual(res.body, { ok: true });
  assert.equal(f.inserts.length, 1);
  assert.equal(f.notifications.length, 1);
});

Deno.test("store: insert failure is a generic 500 and no e-mail is sent", async () => {
  const f = new Fakes();
  f.insertError = { code: "23514", message: "violates check constraint secret_detail" };
  const res = await call(f, post(VALID));
  assert.equal(res.status, 500);
  assert.deepEqual(res.body, { error: "internal" });
  assert.equal(f.notifications.length, 0);
});

Deno.test("config: missing IP hash secret fails closed (500) before the limiter", async () => {
  const f = new Fakes();
  f.ipHashSecret = null;
  const res = await call(f, post(VALID));
  assert.equal(res.status, 500);
  assert.equal(f.rpcCalls.length, 0);
  assert.equal(f.inserts.length, 0);
});

// ---------------------------------------------------------------- CORS / method

Deno.test("CORS: exact allowed origins and the team preview pattern only", () => {
  for (const ok of [
    "https://kuro-legal.vercel.app",
    "https://kuro-legal-lazy-53aeee76.vercel.app",
    "https://kuro.app",
    "https://www.kuro.app",
    "https://kuro-legal-8fjyazx2o-lazy-53aeee76.vercel.app",
  ]) assert.ok(isAllowedOrigin(ok), ok);
  for (const bad of [
    "http://kuro.app",
    "https://kuro.app.evil.test",
    "https://evil.kuro.app",
    "https://kuro-legal-8fjyazx2o-other-team.vercel.app",
    "https://kuro-legal-8fjyazx2o-lazy-53aeee76.vercel.app.evil.test",
    "https://kuro-legal-a-b-c-lazy-53aeee76.vercel.app",
    "http://kuro-legal.vercel.app",
    "https://kuro-legal.vercel.app.evil.test",
    "https://evil-kuro-legal.vercel.app",
    "https://x.kuro-legal-8fjyazx2o-lazy-53aeee76.vercel.app",
    "null",
  ]) assert.ok(!isAllowedOrigin(bad), bad);
});

Deno.test("CORS: preflight from an allowed origin is 204 with the allowed headers", async () => {
  const f = new Fakes();
  const res = await handleContactSubmit(new Request("https://example.test/functions/v1/contact-submit", {
    method: "OPTIONS",
    headers: { Origin: "https://www.kuro.app", "Access-Control-Request-Method": "POST" },
  }), f.platform());
  assert.equal(res.status, 204);
  assert.equal(res.headers.get("Access-Control-Allow-Origin"), "https://www.kuro.app");
  assert.equal(res.headers.get("Access-Control-Allow-Headers"), "authorization, apikey, content-type, x-client-info");
});

Deno.test("CORS: the live site kuro-legal.vercel.app can submit (200 with its CORS header)", async () => {
  const f = new Fakes();
  const res = await call(f, post(VALID, { Authorization: `Bearer ${ANON_KEY}`, Origin: "https://kuro-legal.vercel.app" }));
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("Access-Control-Allow-Origin"), "https://kuro-legal.vercel.app");
  assert.equal(f.inserts.length, 1);
});

Deno.test("CORS: a foreign origin is 403 without CORS headers and nothing is stored", async () => {
  const f = new Fakes();
  const res = await call(f, post(VALID, { Origin: "https://evil.test" }));
  assert.equal(res.status, 403);
  assert.equal(res.headers.get("Access-Control-Allow-Origin"), null);
  assert.equal(f.inserts.length, 0);
});

Deno.test("CORS: error responses to an allowed origin carry the CORS headers too", async () => {
  const f = new Fakes();
  f.limiterReply = { data: { allowed: false, retry_after_s: 5 }, error: null };
  const res = await call(f, post(VALID, { Origin: "https://kuro.app" }));
  assert.equal(res.status, 429);
  assert.equal(res.headers.get("Access-Control-Allow-Origin"), "https://kuro.app");
});

Deno.test("method: GET is 405", async () => {
  const f = new Fakes();
  const res = await handleContactSubmit(new Request("https://example.test/functions/v1/contact-submit"), f.platform());
  assert.equal(res.status, 405);
});
