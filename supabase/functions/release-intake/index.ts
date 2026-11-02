// release-intake: confirmed release dates (AniList airing window) and MangaUpdates series data
// (volume counts; official-group chapter dates + cadence estimates only when
// MU_OFFICIAL_GROUP_IDS is set, open D11 decision) into release_events via
// upsert_release_events_v1.
// PREPARED, NOT DEPLOYED, NOT SCHEDULED (owner decision D11). Auth is the shared IMPORT_SECRET
// header, like bulk-import (pg_cron cannot send JWTs). No user input, no user ids.
// Run orchestration: handler.ts. Airing: airing.ts. Manga: manga.ts. Row contract: contract.ts.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createAniListClient } from "../_shared/anilist_client.ts";
import { createPoliteClient, PoliteLimiter } from "../_shared/polite_fetch.ts";
import { createMangaDexClient } from "../manga-chapter-enrich/mangadex.ts";
import { run } from "./handler.ts";

// MangaUpdates asks for "reasonable spacing": one request per 1.1 s per isolate.
const mangaUpdatesLimiter = new PoliteLimiter(1_100);

serve(async (req) => {
  const importSecret = Deno.env.get("IMPORT_SECRET");
  if (!importSecret) return json({ error: "Server misconfigured" }, 500);
  if (req.headers.get("x-import-secret") !== importSecret) return json({ error: "Unauthorized" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) return json({ error: "Server misconfigured" }, 500);
  const supabase = createClient(supabaseUrl, serviceRoleKey);
  const payload = await req.json().catch(() => ({}));

  const startedMs = Date.now();
  const budgetMs = Number(payload?.timeBudgetMs) > 0 ? Number(payload.timeBudgetMs) : 50_000;
  const dex = createMangaDexClient({
    fetch: globalThis.fetch.bind(globalThis),
    sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    withinBudget: (started, budget) => Date.now() - started < budget,
  });
  const metrics = { api_429_count: 0, rate_limiter_wait_ms: 0, "429_cooldown_count": 0 };

  return run(payload, {
    supabase,
    anilist: createAniListClient(),
    mangaUpdates: createPoliteClient({ limiter: mangaUpdatesLimiter }),
    muOfficialGroupIds: parseGroupIds(Deno.env.get("MU_OFFICIAL_GROUP_IDS")),
    readMangaDexLinks: async (mangaDexId) => {
      const { manga } = await dex.fetchMappedMangaDexTitle(mangaDexId, metrics, startedMs, budgetMs);
      return manga?.attributes?.links ?? null;
    },
  });
});

/** "123,456" -> [123, 456]; anything else is ignored (unset = no official groups). */
function parseGroupIds(raw: string | undefined): number[] {
  return (raw ?? "").split(",").map((v) => Number(v.trim())).filter((n) => Number.isInteger(n) && n > 0);
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
