// contact-submit: contact form of the legal website and the app's Contact sheet (thin entrypoint).
// Request flow and contract: handler.ts. Storage: public.contact_messages (prepared migration
// 20261102100000_contact_messages.sql must be deployed first).
//
// PREPARED, NOT DEPLOYED (2026-11-02). Deploy with verify_jwt=false, because the website calls it
// with the public anon key only and the handler does all checks itself:
//   supabase functions deploy contact-submit --no-verify-jwt --project-ref bkdifromsqxkndnllmdj
// (the repo has no supabase/config.toml; auth-callback uses the same flag.)
//
// Env: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY (platform-provided);
//      CONTACT_IP_HASH_SECRET (recommended; falls back to SUPABASE_SERVICE_ROLE_KEY as the HMAC key);
//      optional e-mail notification: RESEND_API_KEY + CONTACT_NOTIFY_TO + CONTACT_NOTIFY_FROM
//      (all three, else no e-mail is sent; the message is stored either way).
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
    notify: resendKey && notifyTo.length > 0 && notifyFrom
      ? (n) => sendViaResend(resendKey, notifyFrom, notifyTo, n)
      : null,
    newId: () => crypto.randomUUID(),
  });
});
