// concierge-recommend: deterministic mood/seed recommendations with optional Groq narration
// (thin entrypoint). Request flow and run: handler.ts (module map in its header). Deployed slug,
// request and response shapes, rail/mode ids and flag behavior are unchanged; see handler.ts and
// narration.ts for the F32 fail-closed changes.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { handleRecommend } from "./handler.ts";

serve((req) =>
  handleRecommend(req, {
    // Env is read per request, exactly as before the split.
    client(authHeader: string) {
      const supabaseUrl = Deno.env.get("SUPABASE_URL");
      const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY");
      const supabaseService = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
      const supabaseKey = supabaseAnon ?? supabaseService;
      if (!supabaseUrl || !supabaseKey) return null;
      return createClient(supabaseUrl, supabaseKey, {
        global: { headers: authHeader ? { Authorization: authHeader } : {} },
      });
    },
    env: (name) => Deno.env.get(name),
    fetch: (url, init) => fetch(url, init),
    now: () => Date.now(),
  })
);
