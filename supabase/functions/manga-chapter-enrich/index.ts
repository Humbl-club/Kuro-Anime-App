// manga-chapter-enrich (slug unchanged). The import-secret gate and the one
// service-role client live here. Lock/finally, the time budget and the candidate
// run are runChapterEnrich.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { runChapterEnrich } from "./run.ts";

serve(async (req) => {
  const importSecret = Deno.env.get("IMPORT_SECRET");
  const requestSecret = req.headers.get("x-import-secret");
  if (!importSecret || requestSecret !== importSecret) {
    return json({ error: "Unauthorized" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "Server misconfigured" }, 500);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);
  const payload = await req.json().catch(() => ({}));
  return runChapterEnrich({ supabase, payload });
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
