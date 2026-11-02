/**
 * Request handling for `contact-submit` (thin index.ts injects the platform), so the real flow runs
 * against injected fakes in Deno tests. No remote imports here.
 *
 * The second fast contact channel of the Impressum (§ 5 Abs. 1 Nr. 2 DDG): the legal website's
 * contact form (web/legal/kontakt.html) and the app's Contact sheet (Kuro/Support/SupportStore.swift)
 * both POST here. Deployed with verify_jwt=false (the website calls it with the public anon key only);
 * every check below is therefore done in this handler.
 *
 * Contract:
 *   POST JSON { topic, email, name?, message, locale?, app_version?, website, consent: true }
 *   - CORS: Origin must be one of ALLOWED_ORIGINS (https://kuro-legal.vercel.app, the site's only live
 *     hostname on 2026-11-02; the team alias; https://kuro.app / https://www.kuro.app once that domain is
 *     attached) or a kuro-legal preview of the Vercel team lazy-53aeee76 (`isAllowedOrigin`); no Origin
 *     (the app, server-to-server) is allowed. Any other Origin is 403 without CORS headers. CORS is
 *     browser friction only, not an authorization boundary: the endpoint is public by design. Keep the
 *     list in sync whenever the production domain changes.
 *   - Identity: a Bearer token that is a USER JWT (not the anon key, not an anon-role JWT) is verified
 *     with the anon client `auth.getUser(token)`; user_id comes ONLY from that verified user (any
 *     user_id in the body is ignored) and source is 'app'. An invalid user token is 401. Otherwise
 *     source is 'web' and user_id is null.
 *   - `website` is a honeypot: non-empty -> 200 { ok: true } and nothing is stored or sent.
 *   - Validation (`validateContact`): 400 { error: 'invalid', fields: [...] }.
 *   - Rate limits (`check_concierge_rate_limit`, always through the ANON client with an explicit
 *     bucket key in p_ip, so auth.uid() never adds a second, implicit bucket). IP keys are a keyed hash
 *     of the client address, IPv6 grouped by its /64 (`ipBucketKey`), never the raw address:
 *       1. IP bucket BEFORE any token verification (so forged-token floods are throttled too):
 *          anonymous web 5/h (kind 'contact'); a caller presenting a user token 30/h (kind
 *          'contact_app_ip', so carrier-grade NAT neighbours do not lock each other out).
 *       2. Verified app user: 5/h per account (kind 'contact_user', key = the verified user id).
 *       3. Web only: global store ceiling (kind 'contact_global', 200/h) -> 429 beyond it. App users
 *          are never stopped by a global bucket (a flood must not switch the channel off for them).
 *     Denied -> 429 { error: 'rate_limited', retry_after_s } + Retry-After. Limiter error/unknown -> 500
 *     (fail closed, nothing stored).
 *   - Store with the service role into public.contact_messages; failure -> 500 { error: 'internal' }.
 *   - Notification (RESEND_API_KEY + CONTACT_NOTIFY_TO + CONTACT_NOTIFY_FROM; REQUIRED for go-live,
 *     see index.ts): plain text via Resend, reply-to = sender, at most 50 per hour in total (kind
 *     'contact_notify'); beyond that, or when the limiter is unavailable, the message is stored without
 *     an e-mail. Its failure never fails the request. No secret is ever included.
 *   - 200 { ok: true }. Bodies never echo internal error text; logs never contain the message or email.
 */
import { interpretRateLimit } from "../_shared/rate_limit_gate.ts";

export const TOPICS = ["general", "support", "privacy", "legal_notice", "report_content", "other"] as const;
export type Topic = typeof TOPICS[number];

export const LIMITS = {
  email: 254,
  name: 120,
  message: 4000,
  appVersion: 40,
  locale: 10,
  /** Raw body cap (bytes) before JSON parsing. */
  body: 16_384,
} as const;

/** The limiter buckets (all per hour). See the contract above. */
export const RATE_LIMIT = {
  windowSeconds: 3600,
  /** Anonymous (website) submissions per IP (IPv6: per /64). */
  web: { kind: "contact", max: 5 },
  /** Requests presenting a user token, per IP, checked before the token is verified. */
  appIp: { kind: "contact_app_ip", max: 30 },
  /** Verified app submissions per account. */
  user: { kind: "contact_user", max: 5 },
  /** All website submissions together; beyond it the website gets 429. */
  webGlobal: { kind: "contact_global", label: "global", max: 200 },
  /** Notification e-mails in total; beyond it messages are stored without an e-mail. */
  notifyGlobal: { kind: "contact_notify", label: "global:notify", max: 50 },
} as const;

const ALLOWED_ORIGINS = new Set([
  // The legal site's production hostname today (Vercel project kuro-legal, team lazy-53aeee76).
  "https://kuro-legal.vercel.app",
  // The project's team alias.
  "https://kuro-legal-lazy-53aeee76.vercel.app",
  // The final domain, once it is attached and resolves.
  "https://kuro.app",
  "https://www.kuro.app",
]);
/** Vercel preview deployments of the kuro-legal project in team lazy-53aeee76 (kuro-legal-<hash>-lazy-53aeee76.vercel.app). */
const PREVIEW_ORIGIN = /^https:\/\/kuro-legal-[a-z0-9]{6,12}-lazy-53aeee76\.vercel\.app$/;

// Same shape as the table CHECK (no whitespace, one @, a dot in the domain), plus no control chars.
const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const LOCALE_RE = /^[A-Za-z]{2,3}([-_][A-Za-z0-9]{2,8})?$/;
const APP_VERSION_RE = /^[0-9A-Za-z .()+_-]{1,40}$/;
// deno-lint-ignore no-control-regex
const CONTROL_EXCEPT_NEWLINE_TAB = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/;
// deno-lint-ignore no-control-regex
const ANY_CONTROL = /[\u0000-\u001F\u007F]/;

export interface ContactSubmission {
  topic: Topic;
  email: string;
  name: string | null;
  message: string;
  locale: string | null;
  appVersion: string | null;
}

export type ValidationResult =
  | { ok: true; value: ContactSubmission }
  | { ok: false; fields: string[] };

function optionalString(value: unknown): string | null | undefined {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") return undefined; // wrong type -> invalid
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}

/** Pure, strict validation. `fields` lists every invalid field in a stable order. */
export function validateContact(body: unknown): ValidationResult {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { ok: false, fields: ["body"] };
  }
  const b = body as Record<string, unknown>;
  const fields: string[] = [];

  const topic = typeof b.topic === "string" && (TOPICS as readonly string[]).includes(b.topic)
    ? b.topic as Topic
    : null;
  if (!topic) fields.push("topic");

  const email = typeof b.email === "string" ? b.email.trim() : "";
  if (!email || email.length > LIMITS.email || !EMAIL_RE.test(email) || ANY_CONTROL.test(email)) {
    fields.push("email");
  }

  const name = optionalString(b.name);
  if (name === undefined || (name !== null && (name.length > LIMITS.name || ANY_CONTROL.test(name)))) {
    fields.push("name");
  }

  const message = typeof b.message === "string" ? b.message.trim() : "";
  if (!message || message.length > LIMITS.message || CONTROL_EXCEPT_NEWLINE_TAB.test(message)) {
    fields.push("message");
  }

  const locale = optionalString(b.locale);
  if (locale === undefined || (locale !== null && (locale.length > LIMITS.locale || !LOCALE_RE.test(locale)))) {
    fields.push("locale");
  }

  const appVersion = optionalString(b.app_version);
  if (appVersion === undefined || (appVersion !== null && !APP_VERSION_RE.test(appVersion))) {
    fields.push("app_version");
  }

  if (b.consent !== true) fields.push("consent");

  if (fields.length > 0 || !topic) return { ok: false, fields };
  return {
    ok: true,
    value: {
      topic,
      email,
      name: name ?? null,
      message,
      locale: locale ?? null,
      appVersion: appVersion ?? null,
    },
  };
}

/** True when the browser Origin may call this function (exact hosts + the team's preview pattern). */
export function isAllowedOrigin(origin: string): boolean {
  return ALLOWED_ORIGINS.has(origin) || PREVIEW_ORIGIN.test(origin);
}

/** The honeypot is filled (a bot): anything but a missing / empty string. */
export function isHoneypotFilled(body: unknown): boolean {
  if (!body || typeof body !== "object") return false;
  const value = (body as Record<string, unknown>).website;
  if (value === undefined || value === null) return false;
  return typeof value !== "string" || value.trim().length > 0;
}

/** Decodes a JWT payload WITHOUT verifying it (only used to recognise anon-role tokens). */
function unverifiedJwtRole(token: string): string | null {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    const b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
    const payload = JSON.parse(atob(padded));
    return typeof payload?.role === "string" ? payload.role : null;
  } catch {
    return null;
  }
}

export type CallerToken = { kind: "anonymous" } | { kind: "user"; token: string };

/**
 * Classifies the Authorization header. Missing, the anon key itself, a publishable key or an
 * anon-role JWT is anonymous (the website). Anything else must be a user JWT and is verified.
 * Treating a token as anonymous grants nothing (no user_id, source 'web'), so the unverified
 * role read cannot elevate anything.
 */
export function classifyAuthorization(header: string | null, anonKey: string | null): CallerToken {
  const match = /^Bearer\s+(\S+)$/i.exec((header ?? "").trim());
  if (!match) return { kind: "anonymous" };
  const token = match[1];
  if (anonKey && token === anonKey) return { kind: "anonymous" };
  if (token.startsWith("sb_publishable_")) return { kind: "anonymous" };
  if (unverifiedJwtRole(token) === "anon") return { kind: "anonymous" };
  return { kind: "user", token };
}

/**
 * The caller IP. On Supabase hosting the edge proxy rebuilds x-forwarded-for, so its LEFTMOST entry is
 * the real client (= cf-connecting-ip); a client-sent value never survives (probe 2026-11-02,
 * docs/go-live/2026-11-02/STAGE4_DATA_ON.md). The rightmost entry is a proxy hop: never use it.
 */
export function clientIp(req: Request): string | null {
  const xf = req.headers.get("x-forwarded-for");
  if (xf) {
    const first = xf.split(",")[0]?.trim();
    if (first) return first;
  }
  return req.headers.get("x-real-ip")?.trim() || req.headers.get("cf-connecting-ip")?.trim() || null;
}

/**
 * The address the IP bucket is keyed on: IPv4 whole; IPv6 reduced to its /64 network (one household,
 * VPS or phone usually owns a whole /64, so per-address buckets would be free to multiply);
 * IPv4-mapped IPv6 (::ffff:a.b.c.d) as the IPv4 address. Brackets, a zone id and an IPv4 port are
 * dropped. Anything unparsable is returned trimmed and lower-cased (still a single bucket).
 */
export function ipBucketKey(raw: string): string {
  let ip = raw.trim().toLowerCase();
  const bracketed = /^\[([^\]]+)\](?::\d+)?$/.exec(ip);
  if (bracketed) ip = bracketed[1];
  const zone = ip.indexOf("%");
  if (zone >= 0) ip = ip.slice(0, zone);
  const v4WithPort = /^(\d{1,3}(?:\.\d{1,3}){3}):\d+$/.exec(ip);
  if (v4WithPort) ip = v4WithPort[1];
  if (!ip.includes(":")) return ip;

  const groups = expandIpv6(ip);
  if (!groups) return ip;
  // IPv4-mapped (::ffff:0:0/96): the last 32 bits are the IPv4 address.
  if (groups.slice(0, 5).every((g) => g === 0) && groups[5] === 0xffff) {
    return `${groups[6] >> 8}.${groups[6] & 0xff}.${groups[7] >> 8}.${groups[7] & 0xff}`;
  }
  return `${groups.slice(0, 4).map((g) => g.toString(16)).join(":")}::/64`;
}

/** The eight 16-bit groups of an IPv6 address (with `::` and a dotted IPv4 tail), or null. */
function expandIpv6(ip: string): number[] | null {
  let text = ip;
  const tail: number[] = [];
  const dotted = /(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(text);
  if (dotted) {
    const octets = dotted.slice(1).map(Number);
    if (octets.some((o) => o > 255)) return null;
    tail.push((octets[0] << 8) | octets[1], (octets[2] << 8) | octets[3]);
    text = text.slice(0, dotted.index) + "0";
  }
  const halves = text.split("::");
  if (halves.length > 2) return null;
  const parse = (part: string): number[] | null => {
    if (part === "") return [];
    const out: number[] = [];
    for (const g of part.split(":")) {
      if (!/^[0-9a-f]{1,4}$/.test(g)) return null;
      out.push(parseInt(g, 16));
    }
    return out;
  };
  const head = parse(halves[0]);
  const rest = halves.length === 2 ? parse(halves[1]) : [];
  if (!head || !rest) return null;
  if (dotted) {
    // The placeholder "0" stands for the two IPv4 groups.
    const owner = halves.length === 2 ? rest : head;
    owner.pop();
    owner.push(...tail);
  }
  let groups: number[];
  if (halves.length === 2) {
    const missing = 8 - head.length - rest.length;
    if (missing < 1) return null;
    groups = [...head, ...new Array(missing).fill(0), ...rest];
  } else {
    groups = head;
  }
  return groups.length === 8 ? groups : null;
}

/** Keyed hash (HMAC-SHA-256, hex, 32 chars) of the caller IP: the limiter never stores the raw IP. */
export async function hashIp(ip: string, secret: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(`contact:${ip}`)));
  return Array.from(sig.slice(0, 16), (b) => b.toString(16).padStart(2, "0")).join("");
}

/** The notification e-mail (plain text). Subject is built from enums only (no header injection). */
export interface ContactNotification {
  subject: string;
  text: string;
  replyTo: string;
}

export function buildNotification(
  id: string,
  submission: ContactSubmission,
  source: "web" | "app",
  userId: string | null,
): ContactNotification {
  const lines = [
    `New Kuro contact message`,
    ``,
    `Id:          ${id}`,
    `Topic:       ${submission.topic}`,
    `Source:      ${source}`,
    `Signed in:   ${userId ? `yes (user ${userId})` : "no"}`,
    `Name:        ${submission.name ?? "-"}`,
    `Email:       ${submission.email}`,
    `Locale:      ${submission.locale ?? "-"}`,
    `App version: ${submission.appVersion ?? "-"}`,
    ``,
    `Message:`,
    submission.message,
    ``,
    `Reply to this email to answer the sender. Stored in public.contact_messages (purged after 12 months).`,
  ];
  return {
    subject: `[Kuro contact] ${submission.topic} (${source})`,
    text: lines.join("\n"),
    replyTo: submission.email,
  };
}

// deno-lint-ignore no-explicit-any
export type SupabaseLike = any;

export interface ContactPlatform {
  /** The public anon key (to recognise the website's bearer); null when unset. */
  anonKey: string | null;
  /** Client bound to the caller's Authorization header (anon key when null: the limiter), or null when env is missing. */
  callerClient(authHeader: string | null): SupabaseLike | null;
  /** Service-role client for the insert, or null when SUPABASE_SERVICE_ROLE_KEY is missing. */
  serviceClient(): SupabaseLike | null;
  /** Secret for the IP hash; null when no secret is configured (then the request fails closed). */
  ipHashSecret: string | null;
  /** Sends the notification, or null when e-mail is not configured. May throw; the handler swallows it. */
  notify: ((notification: ContactNotification) => Promise<void>) | null;
  /** Message id (injectable for tests). */
  newId(): string;
}

/**
 * Reads at most `limit` bytes of the body: null when it is larger (declared Content-Length or the
 * actual stream), so an oversized body is never buffered whole.
 */
export async function readCappedBody(req: Request, limit: number): Promise<string | null> {
  const declared = Number(req.headers.get("Content-Length") ?? "");
  if (Number.isFinite(declared) && declared > limit) return null;
  if (!req.body) return "";
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > limit) {
      await reader.cancel().catch(() => {});
      return null;
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

function corsHeaders(origin: string | null): Record<string, string> {
  if (!origin) return {};
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Max-Age": "600",
    "Vary": "Origin",
  };
}

export async function handleContactSubmit(req: Request, platform: ContactPlatform): Promise<Response> {
  const origin = req.headers.get("Origin");
  if (origin !== null && !isAllowedOrigin(origin)) {
    return new Response(JSON.stringify({ error: "forbidden_origin" }), {
      status: 403,
      headers: { "Content-Type": "application/json" },
    });
  }
  const cors = corsHeaders(origin);
  const json = (body: unknown, status = 200, extra: Record<string, string> = {}) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...cors, ...extra },
    });

  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405, { Allow: "POST, OPTIONS" });

  try {
    const raw = await readCappedBody(req, LIMITS.body);
    if (raw === null) return json({ error: "invalid", fields: ["body"] }, 400);
    let body: unknown;
    try {
      body = JSON.parse(raw);
    } catch {
      return json({ error: "invalid", fields: ["body"] }, 400);
    }

    // Bots fill every field: answer as if accepted, store and send nothing.
    if (isHoneypotFilled(body)) return json({ ok: true });

    const validation = validateContact(body);
    if (!validation.ok) return json({ error: "invalid", fields: validation.fields }, 400);
    const submission = validation.value;

    const authHeader = req.headers.get("Authorization");
    const caller = classifyAuthorization(authHeader, platform.anonKey);
    // The limiter always runs on the ANON client: every bucket is an explicit key in p_ip, and
    // auth.uid() stays null so the RPC never adds an implicit per-user bucket of its own.
    const limiterClient = platform.callerClient(null);
    const service = platform.serviceClient();
    const hashSecret = platform.ipHashSecret;
    if (!limiterClient || !service || !hashSecret) {
      console.error("contact-submit: missing SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY / IP hash secret");
      return json({ error: "internal" }, 500);
    }
    const check = (kind: string, key: string, max: number) =>
      Promise.resolve(
        limiterClient.rpc("check_concierge_rate_limit", {
          p_kind: kind,
          p_ip: key,
          p_window_seconds: RATE_LIMIT.windowSeconds,
          p_max_user: max,
          p_max_ip: max,
        }),
      ).then(
        (r: unknown) => interpretRateLimit(r as { data?: unknown; error?: unknown }),
        (error: unknown) => interpretRateLimit({ data: null, error }),
      );
    const blocked = (decision: Awaited<ReturnType<typeof check>>): Response | null => {
      if (decision.kind === "denied") {
        return json(
          { error: "rate_limited", retry_after_s: decision.retryAfterSeconds },
          429,
          { "Retry-After": String(decision.retryAfterSeconds) },
        );
      }
      if (decision.kind === "unavailable") {
        console.error("contact-submit: rate limiter unavailable (fail closed)");
        return json({ error: "internal" }, 500);
      }
      return null;
    };

    // 1. IP bucket first, before any token is verified (a fixed bucket when no IP header exists, so
    //    the limiter never answers "no uid/ip -> allowed").
    // Every bucket name is secret-keyed: check_concierge_rate_limit is anon-callable, so a guessable
    // name (the global ceiling, a user id) could be filled by anyone to block the contact channel.
    const bucket = async (label: string) => `contact:${await hashIp(label, hashSecret)}`;
    const ipBucket = await bucket(ipBucketKey(clientIp(req) ?? "unknown"));
    const ipLimit = caller.kind === "user" ? RATE_LIMIT.appIp : RATE_LIMIT.web;
    const ipBlocked = blocked(await check(ipLimit.kind, ipBucket, ipLimit.max));
    if (ipBlocked) return ipBlocked;

    // 2. Identity, then the per-account bucket.
    let userId: string | null = null;
    if (caller.kind === "user") {
      const client = platform.callerClient(authHeader);
      if (!client) return json({ error: "internal" }, 500);
      const { data, error } = await client.auth.getUser(caller.token);
      const id = data?.user?.id;
      if (error || typeof id !== "string" || id.length === 0) return json({ error: "unauthorized" }, 401);
      userId = id;
      const userBlocked = blocked(await check(RATE_LIMIT.user.kind, await bucket(`user:${id}`), RATE_LIMIT.user.max));
      if (userBlocked) return userBlocked;
    } else {
      // 3. Website only: the global ceiling bounds table growth from address pools.
      const globalBlocked = blocked(await check(RATE_LIMIT.webGlobal.kind, await bucket(RATE_LIMIT.webGlobal.label), RATE_LIMIT.webGlobal.max));
      if (globalBlocked) return globalBlocked;
    }
    const source: "web" | "app" = userId ? "app" : "web";

    const id = platform.newId();
    const { error: insertError } = await service.from("contact_messages").insert({
      id,
      source,
      topic: submission.topic,
      email: submission.email,
      name: submission.name,
      message: submission.message,
      user_id: userId,
      app_version: submission.appVersion,
      locale: submission.locale,
    });
    if (insertError) {
      console.error(`contact-submit: insert failed (${insertError.code ?? "unknown"})`);
      return json({ error: "internal" }, 500);
    }

    // The inbox and the mail quota stay bounded: beyond the hourly notification ceiling (or when the
    // limiter cannot answer) the message is stored without an e-mail.
    if (platform.notify) {
      const notifyDecision = await check(RATE_LIMIT.notifyGlobal.kind, await bucket(RATE_LIMIT.notifyGlobal.label), RATE_LIMIT.notifyGlobal.max);
      if (notifyDecision.kind !== "allowed") {
        console.warn(`contact-submit: notification skipped for ${id} (${notifyDecision.kind})`);
      } else {
        try {
          await platform.notify(buildNotification(id, submission, source, userId));
        } catch (error) {
          console.warn(`contact-submit: notification failed for ${id}: ${error instanceof Error ? error.name : "error"}`);
        }
      }
    }

    return json({ ok: true });
  } catch {
    return json({ error: "internal" }, 500);
  }
}
