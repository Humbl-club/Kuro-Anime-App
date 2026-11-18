// concierge-parse: parses free-text import lines into title candidates + slots (thin entrypoint).
// Request flow and per-line run: handler.ts; data boundary: parse_repository.ts; search ranking:
// search_plan.ts; pure parser: rules.ts. Deployed slug, request and response shapes are unchanged;
// see handler.ts for the F31/F32 changes.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { handleParse } from "./handler.ts";
import { limiterSecretFromEnv } from "../_shared/limiter_ip.ts";

// Guarded lookup: the global exists only on the Edge runtime (absent in local deno check/test).
const edgeRuntime = (globalThis as { EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void } }).EdgeRuntime;
const waitUntil = typeof edgeRuntime?.waitUntil === "function" ? edgeRuntime.waitUntil.bind(edgeRuntime) : undefined;

serve((req) =>
  handleParse(req, {
    // Env is read per request, exactly as before the split.
    client(authHeader: string) {
      const supabaseUrl = Deno.env.get("SUPABASE_URL");
      const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY");
      const supabaseKey = supabaseAnon;
      if (!supabaseUrl || !supabaseKey) return null;
      return createClient(supabaseUrl, supabaseKey, {
        global: { headers: authHeader ? { Authorization: authHeader } : {} },
      });
    },
    waitUntil,
    limiterIpSecret: () => limiterSecretFromEnv((name) => Deno.env.get(name)),
  })
);
