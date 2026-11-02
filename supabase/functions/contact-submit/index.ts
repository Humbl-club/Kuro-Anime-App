// contact-submit: contact form of the legal website and the app's Contact sheet (thin entrypoint).
// Request flow and contract: handler.ts. Storage: public.contact_messages (prepared migration
// 20261102100000_contact_messages.sql must be deployed first).
//
// PREPARED, NOT DEPLOYED (2026-11-02). HARD RELEASE PREREQUISITE, in this order, before the legal site
// (Impressum names this form) is published or an app build with Profile > Contact us ships:
//   1. migration supabase/prepared-migrations/20261102100000_contact_messages.sql
//   2. supabase functions deploy contact-submit --no-verify-jwt --project-ref bkdifromsqxkndnllmdj
//      (verify_jwt=false: the website calls it with the public anon key only and the handler does
//      all checks itself; the repo has no supabase/config.toml; auth-callback uses the same flag)
//   3. secrets CONTACT_IP_HASH_SECRET + RESEND_API_KEY + CONTACT_NOTIFY_TO + CONTACT_NOTIFY_FROM
//   4. the CORS list in handler.ts matches the live legal-site hostname
//   5. live smoke: one message from the website origin and one from the app is stored AND arrives
//      as an e-mail in CONTACT_NOTIFY_TO.
// Checklist: docs/go-live/2026-11-02/CONTACT_FORM_RELEASE.md.
//
// Env: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY (platform-provided);
//      CONTACT_IP_HASH_SECRET (recommended; falls back to SUPABASE_SERVICE_ROLE_KEY as the HMAC key);
//      e-mail notification RESEND_API_KEY + CONTACT_NOTIFY_TO + CONTACT_NOTIFY_FROM: REQUIRED for
//      go-live. The form only counts as the § 5 Abs. 1 Nr. 2 DDG fast channel if messages reach the
//      owner promptly, and nobody watches the table. Without all three the message is still stored
//      (better than dropping it) and every request logs an error so the gap shows in the function logs.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { type ContactNotification, handleContactSubmit } from "./handler.ts";

const RESEND_TIMEOUT_MS = 5_000;

async function sendViaResend(apiKey: string, from: string, to: string[], n: ContactNotification): Promise<void> {
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from, to, subject: n.subject, text: n.text, reply_to: n.replyTo }),
    signal: AbortSignal.timeout(RESEND_TIMEOUT_MS),
  });
  // Drain the body; never log it (it may echo addresses).
  await res.body?.cancel();
  if (!res.ok) throw new Error(`resend_status_${res.status}`);
}

Deno.serve((req) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? null;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? null;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? null;
  const resendKey = Deno.env.get("RESEND_API_KEY") ?? "";
  const notifyTo = (Deno.env.get("CONTACT_NOTIFY_TO") ?? "").split(",").map((s) => s.trim()).filter(Boolean);
  const notifyFrom = (Deno.env.get("CONTACT_NOTIFY_FROM") ?? "").trim();
  const notifyConfigured = Boolean(resendKey && notifyTo.length > 0 && notifyFrom);
  if (!notifyConfigured && req.method === "POST") {
    console.error("contact-submit: e-mail notification NOT configured (RESEND_API_KEY / CONTACT_NOTIFY_TO / CONTACT_NOTIFY_FROM); messages are stored but nobody is alerted");
  }

  return handleContactSubmit(req, {
    anonKey,
    callerClient(authHeader) {
      if (!supabaseUrl || !anonKey) return null;
      return createClient(supabaseUrl, anonKey, {
        auth: { persistSession: false, autoRefreshToken: false },
        global: { headers: authHeader ? { Authorization: authHeader } : {} },
      });
    },
    serviceClient() {
      if (!supabaseUrl || !serviceKey) return null;
      return createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    },
    ipHashSecret: Deno.env.get("CONTACT_IP_HASH_SECRET") || serviceKey,
    notify: notifyConfigured
      ? (n) => sendViaResend(resendKey, notifyFrom, notifyTo, n)
      : null,
    newId: () => crypto.randomUUID(),
  });
});
