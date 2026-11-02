// concierge-apply: applies reconciled import items to the caller's anime/manga lists
// (thin entrypoint). Request flow: handler.ts; pure validation/planning/outcome rules: apply_plan.ts;
// the write itself is the database transaction `apply_import_session` (service role only; prepared
// migration 20261005130000_import_apply_undo_transactions.sql must be deployed first).
// Deployed slug, JWT-only identity and rate-limit kind are unchanged; wire v2 adds fields.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { handleApply } from "./handler.ts";

serve((req) =>
  handleApply(req, {
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
    serviceClient() {
      const supabaseUrl = Deno.env.get("SUPABASE_URL");
      const supabaseService = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
      if (!supabaseUrl || !supabaseService) return null;
      return createClient(supabaseUrl, supabaseService, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
    },
  })
);
