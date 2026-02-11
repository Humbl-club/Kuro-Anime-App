import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function json(res: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(res), {
    ...init,
    headers: { "Content-Type": "application/json", ...(init.headers ?? {}) },
  });
}

function clientIp(req: Request): string | null {
  const xf = req.headers.get("x-forwarded-for");
  if (xf) {
    const first = xf.split(",")[0]?.trim();
    if (first) return first;
  }
  const real = req.headers.get("x-real-ip")?.trim();
  if (real) return real;
  const cf = req.headers.get("cf-connecting-ip")?.trim();
  if (cf) return cf;
  return null;
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------

serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, { status: 405 });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !supabaseAnon) {
    return json({ error: "Missing SUPABASE_URL or SUPABASE_ANON_KEY" }, { status: 500 });
  }

  // Auth-aware client: feedback requires authenticated user (RLS enforces user_id = auth.uid())
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader) {
    return json({ error: "Authorization required" }, { status: 401 });
  }

  const client = createClient(supabaseUrl, supabaseAnon, {
    global: { headers: { Authorization: authHeader } },
  });

  // Verify user is authenticated
  const { data: { user }, error: authError } = await client.auth.getUser();
  if (authError || !user) {
    return json({ error: "Authentication required" }, { status: 401 });
  }

  const ip = clientIp(req);
  const { data: rl } = await client.rpc("check_concierge_rate_limit", {
    p_kind: "rag_feedback",
    p_ip: ip,
    p_window_seconds: null,
    p_max_user: null,
    p_max_ip: null,
  });
  if (rl && rl.allowed === false) {
    return json(
      { error: "Rate limited", retry_after_s: rl.retry_after_s ?? 30 },
      { status: 429, headers: { "Retry-After": String(rl.retry_after_s ?? 30) } },
    );
  }

  // Parse request body
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, { status: 400 });
  }

  // Validate required fields
  const query = typeof body.query === "string" ? body.query.trim() : "";
  const locale = typeof body.locale === "string" ? body.locale.trim() : "";
  const accepted = typeof body.accepted === "boolean" ? body.accepted : null;

  if (!query) {
    return json({ error: "query is required" }, { status: 400 });
  }
  if (!locale) {
    return json({ error: "locale is required" }, { status: 400 });
  }
  if (accepted === null) {
    return json({ error: "accepted (boolean) is required" }, { status: 400 });
  }

  // Optional fields
  const selectedEntityId = typeof body.selected_entity_id === "string"
    ? body.selected_entity_id.trim()
    : null;
  if (selectedEntityId && !isUuid(selectedEntityId)) {
    return json({ error: "selected_entity_id must be a UUID" }, { status: 400 });
  }
  const rejectedReason =
    typeof body.rejected_reason === "string"
      ? body.rejected_reason.slice(0, 500)
      : null;

  // Insert feedback (RLS policy enforces user_id = auth.uid()::text)
  const { error: insertError } = await client.from("rag_retrieval_feedback").insert({
    user_id: user.id,
    query: query.slice(0, 500),
    locale,
    selected_entity_id: selectedEntityId,
    accepted,
    rejected_reason: rejectedReason,
  });

  if (insertError) {
    return json({ error: "Failed to save feedback" }, { status: 500 });
  }

  return json({ ok: true });
});
