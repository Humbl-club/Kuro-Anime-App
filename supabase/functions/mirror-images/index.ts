// Mirror remote AniList images into Supabase Storage (slug: mirror-images).
// Cron payload still sends bucket "media", limit/offset and mediaTypes.
// Lock key: mirror-images:<sorted types>:<offset>. Report: mirror_runs.results.
// Any other bucket is rejected. Object paths are derived, never read from the payload.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createMirrorRepository } from "./mirror_repository.ts";
import { createMirrorStorage } from "./mirror_storage.ts";
import { runMirrorImages } from "./mirror_run.ts";

serve(async (req) => {
  const importSecret = Deno.env.get("IMPORT_SECRET");
  const reqSecret = req.headers.get("x-import-secret");
  if (!importSecret || reqSecret !== importSecret) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !supabaseKey) {
    return new Response(JSON.stringify({ error: "Server misconfigured" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(supabaseUrl, supabaseKey);
  const payload = await req.json().catch(() => ({}));
  return runMirrorImages({
    repository: createMirrorRepository(supabase),
    storage: createMirrorStorage(supabase),
    fetch: (input, init) => fetch(input, init),
    now: () => Date.now(),
    supabaseUrl,
    payload,
  });
});
