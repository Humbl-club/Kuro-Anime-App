// concierge-parse: parses free-text import lines into title candidates + slots (thin entrypoint).
// Request flow and per-line run: handler.ts; data boundary: parse_repository.ts; search ranking:
// search_plan.ts; pure parser: rules.ts. Deployed slug, request and response shapes are unchanged;
// see handler.ts for the F31/F32 changes.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { handleParse } from "./handler.ts";

serve((req) =>
  handleParse(req, {
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
  })
);
