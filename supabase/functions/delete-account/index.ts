// delete-account: GDPR account deletion (thin entrypoint).
// All logic lives in handler.ts (request flow), deletion.ts (ordered, retry-safe
// cleanup) and adapters.ts (Supabase client wiring); see their headers.
// Deployed slug and success response shape ({ success: true }) are unchanged.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createPlatform } from "./adapters.ts";
import { handleDeleteAccount } from "./handler.ts";

const platform = createPlatform(
  {
    supabaseUrl: Deno.env.get("SUPABASE_URL"),
    supabaseAnonKey: Deno.env.get("SUPABASE_ANON_KEY"),
    serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
    appleClientId: Deno.env.get("APPLE_CLIENT_ID"),
    appleClientSecret: Deno.env.get("APPLE_CLIENT_SECRET"),
  },
  createClient as unknown as Parameters<typeof createPlatform>[1],
);

Deno.serve((req) => handleDeleteAccount(req, platform));
