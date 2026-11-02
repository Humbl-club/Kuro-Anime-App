// concierge-import-anilist (slug unchanged). Auth and the anilist_import rate
// limit stay here. The import run is runAnilistImport: cached text versus a
// fresh list, AniList paging behind the injected fetch, and pure line conversion.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { gateRateLimit } from "../_shared/rate_limit_gate.ts";
import { runAnilistImport } from "./run.ts";

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

serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, { status: 405 });

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY");
    const supabaseService = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const supabaseKey = supabaseAnon ?? supabaseService;
    if (!supabaseUrl || !supabaseKey) {
      return json({ error: "Missing SUPABASE_URL or a Supabase API key env (SUPABASE_ANON_KEY or SUPABASE_SERVICE_ROLE_KEY)" }, { status: 500 });
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const client = createClient(supabaseUrl, supabaseKey, {
      global: { headers: authHeader ? { Authorization: authHeader } : {} },
    });

    const { data: userData, error: userErr } = await client.auth.getUser();
    if (userErr || !userData?.user) return json({ error: "Unauthorized" }, { status: 401 });

    const ip = clientIp(req) ?? "";
    const blocked = await gateRateLimit(
      client.rpc("check_concierge_rate_limit", { p_kind: "anilist_import", p_ip: ip }),
      json,
    );
    if (blocked) return blocked;

    const raw = await req.json().catch(() => ({}));
    return await runAnilistImport(raw, { fetch });
  } catch (e) {
    const msg = (e instanceof Error ? e.message : String(e)).slice(0, 400);
    return json({ success: false, error: msg }, { status: 500 });
  }
});
