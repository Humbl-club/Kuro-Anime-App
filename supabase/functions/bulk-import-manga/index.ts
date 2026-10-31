// Deployed from local patch of scripts/legacy/07_manga_edge_function_with_chapters.js
// Thin entrypoint. Slug bulk-import-manga and IMPORT_SECRET / x-import-secret auth are unchanged.
// Run orchestration: handler.ts. AniList transport: anilist.ts. Manga mapping: mapping.ts.
// Lock, cursor and import_runs: ../bulk-import-anime/persistence.ts (identical bookkeeping).
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { fetchAniListMangaData } from "./anilist.ts";
import { run } from "./handler.ts";
import { parseBooleanEnv } from "../bulk-import-anime/persistence.ts";

serve(async (req) => {
  // Secret header auth: pg_cron/pg_net can't send JWTs, so verify a shared secret instead.
  const IMPORT_SECRET = Deno.env.get("IMPORT_SECRET");
  if (!IMPORT_SECRET) {
    return new Response(JSON.stringify({ error: "Server misconfigured" }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
  const authHeader = req.headers.get("x-import-secret");
  if (authHeader !== IMPORT_SECRET) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: { "Content-Type": "application/json" } });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const supabase = createClient(supabaseUrl, supabaseKey);
  const payload = await req.json().catch(() => ({} as any));
  return run(payload, {
    supabase,
    fetchPage: fetchAniListMangaData,
    heavyImportsEnabled: parseBooleanEnv(Deno.env.get("IMPORT_HEAVY_ENABLED"), true),
  });
});
