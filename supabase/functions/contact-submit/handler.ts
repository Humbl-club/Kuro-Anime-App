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
 *   - CORS: Origin must be https://kuro.app, https://www.kuro.app or a kuro-legal preview of the Vercel
 *     team lazy-53aeee76 (`isAllowedOrigin`); no Origin (the app, server-to-server) is allowed. Any other
 *     Origin is 403 without CORS headers. CORS is browser friction only, not an authorization boundary:
 *     the endpoint is public by design.
 *   - Identity: a Bearer token that is a USER JWT (not the anon key, not an anon-role JWT) is verified
 *     with the anon client `auth.getUser(token)`; user_id comes ONLY from that verified user (any
 *     user_id in the body is ignored) and source is 'app'. An invalid user token is 401. Otherwise
 *     source is 'web' and user_id is null.
 *   - `website` is a honeypot: non-empty -> 200 { ok: true } and nothing is stored or sent.
 *   - Validation (`validateContact`): 400 { error: 'invalid', fields: [...] }.
 *   - Rate limit: `check_concierge_rate_limit` kind 'contact', 5 per hour per keyed-hash IP and (app)
 *     per user, through the caller's client so auth.uid() counts the user bucket. Denied -> 429
 *     { error: 'rate_limited', retry_after_s } + Retry-After. Limiter error/unknown -> 500 (fail closed,
 *     nothing stored).
 *   - Store with the service role into public.contact_messages; failure -> 500 { error: 'internal' }.
 *   - Optional notification (RESEND_API_KEY + CONTACT_NOTIFY_TO + CONTACT_NOTIFY_FROM): plain text via
 *     Resend, reply-to = sender. Its failure never fails the request. No secret is ever included.
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

/** 5 submissions per hour per hashed IP and (app) per user. */
export const RATE_LIMIT = { kind: "contact", windowSeconds: 3600, maxUser: 5, maxIp: 5 } as const;

const ALLOWED_ORIGINS = new Set(["https://kuro.app", "https://www.kuro.app"]);
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
  /** Client bound to the caller's Authorization header (anon key when none), or null when env is missing. */
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
    const client = platform.callerClient(caller.kind === "user" ? authHeader : null);
    const service = platform.serviceClient();
    if (!client || !service || !platform.ipHashSecret) {
      console.error("contact-submit: missing SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY / IP hash secret");
      return json({ error: "internal" }, 500);
    }

    let userId: string | null = null;
    if (caller.kind === "user") {
      const { data, error } = await client.auth.getUser(caller.token);
      const id = data?.user?.id;
      if (error || typeof id !== "string" || id.length === 0) return json({ error: "unauthorized" }, 401);
      userId = id;
    }
    const source: "web" | "app" = userId ? "app" : "web";

    // Always an IP bucket (a fixed one when no IP header exists), so the limiter never answers
    // "no uid/ip -> allowed".
    const ipBucket = await hashIp(clientIp(req) ?? "unknown", platform.ipHashSecret);
    const limiter = await Promise.resolve(
      client.rpc("check_concierge_rate_limit", {
        p_kind: RATE_LIMIT.kind,
        p_ip: `contact:${ipBucket}`,
        p_window_seconds: RATE_LIMIT.windowSeconds,
        p_max_user: RATE_LIMIT.maxUser,
        p_max_ip: RATE_LIMIT.maxIp,
      }),
    ).then((r: unknown) => r as { data?: unknown; error?: unknown }, (error: unknown) => ({ data: null, error }));
    const decision = interpretRateLimit(limiter);
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

    if (platform.notify) {
      try {
        await platform.notify(buildNotification(id, submission, source, userId));
      } catch (error) {
        console.warn(`contact-submit: notification failed for ${id}: ${error instanceof Error ? error.name : "error"}`);
      }
    }

    return json({ ok: true });
  } catch {
    return json({ error: "internal" }, 500);
  }
}
