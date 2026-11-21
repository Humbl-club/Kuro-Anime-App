// release-intake: confirmed release dates (AniList airing window) and MangaUpdates series data
// (volume counts; official-group chapter dates + cadence estimates only when
// MU_OFFICIAL_GROUP_IDS is set, open D11 decision) into release_events via
// upsert_release_events_v1.
// PREPARED, NOT DEPLOYED, NOT SCHEDULED (owner decision D11). Auth is the shared IMPORT_SECRET
// header, like bulk-import (pg_cron cannot send JWTs). No user input, no user ids.
// Run orchestration: handler.ts. Airing: airing.ts. Manga: manga.ts. Row contract: contract.ts.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createAniListClient, INTAKE_USER_AGENT, parseRetryAfter } from "../_shared/anilist_client.ts";
import { createPoliteClient, PoliteLimiter } from "../_shared/polite_fetch.ts";
import { createMangaDexClient } from "../manga-chapter-enrich/mangadex.ts";
import { run } from "./handler.ts";

// MangaUpdates and Syoboi ask for reasonable spacing between requests (~1.1 s per isolate).
const mangaUpdatesLimiter = new PoliteLimiter(1_100);
const syoboiLimiter = new PoliteLimiter(1_100);

function createPoliteFetch(limiter: PoliteLimiter, deadlineMs: number): typeof fetch {
  return async (input: RequestInfo | URL, init?: RequestInit) => {
    const nowMs = Date.now();
    const waitMs = Math.max(0, Math.max(limiter.nextAllowedAt, limiter.pausedUntil) - nowMs);
    if (nowMs + waitMs >= deadlineMs) {
      return new Response(null, { status: 429 });
    }
    if (waitMs > 0) {
      await new Promise((resolve) => setTimeout(resolve, waitMs));
    }
    limiter.nextAllowedAt = Date.now() + limiter.minIntervalMs;

    const headers = new Headers(init?.headers ?? {});
    if (!headers.has("User-Agent")) {
      headers.set("User-Agent", INTAKE_USER_AGENT);
    }
    const signal = init?.signal ?? AbortSignal.timeout(15_000);
    const response = await globalThis.fetch(input, { ...init, headers, signal });
    if (response.status === 429) {
      const retryAfter = parseRetryAfter(response.headers.get("retry-after"), Date.now()) ?? 60_000;
      limiter.pausedUntil = Math.max(limiter.pausedUntil, Date.now() + Math.min(retryAfter, 65_000));
    }
    return response;
  };
}

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
    syoboiFetch: createPoliteFetch(syoboiLimiter, startedMs + budgetMs),
    readMangaDexLinks: async (mangaDexId) => {
      const { manga } = await dex.fetchMappedMangaDexTitle(mangaDexId, metrics, startedMs, budgetMs);
      return manga?.attributes?.links ?? null;
    },
  });
});

/** Verified official English publisher group IDs on MangaUpdates (VIZ, MANGA Plus, K MANGA, Kodansha USA, Yen Press, Tapas, J-Novel Club). */
export const DEFAULT_MU_OFFICIAL_GROUP_IDS = [
  45251742061,
  49204242348,
  20977306229,
  67085909306,
  56980946982,
  4290065293,
  31439080110,
] as const;

/** "123,456" -> [123, 456]; "none" -> []; unset/empty falls back to the verified 7 official publishers. */
function parseGroupIds(raw: string | undefined): number[] {
  const trimmed = (raw ?? "").trim();
  if (trimmed.toLowerCase() === "none") return [];
  if (!trimmed) return [...DEFAULT_MU_OFFICIAL_GROUP_IDS];
  const parsed = trimmed.split(",").map((v) => Number(v.trim())).filter((n) => Number.isInteger(n) && n > 0);
  return parsed.length > 0 ? parsed : [...DEFAULT_MU_OFFICIAL_GROUP_IDS];
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
