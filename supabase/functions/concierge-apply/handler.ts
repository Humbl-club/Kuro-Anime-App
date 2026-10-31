/**
 * Request handling for `concierge-apply` (thin index.ts injects the platform), so the real flow runs
 * against an injected Supabase-shaped client in Deno tests.
 *
 * Contract (wire v2, docs/plans/2026-10-05-modularity-completion-contracts.md section 3):
 *   POST `{ items, idempotencyKey? }`. Caller identity ONLY from the JWT (`client.auth.getUser()`,
 *   never from the body). Limiter `check_concierge_rate_limit` kind `apply` through the shared gate
 *   (denial 429, limiter error/unknown result 503, no write). Max 100 items; every item is validated
 *   BEFORE anything is written (HTTP 400 `{ error, code: "INVALID_ITEM", index }`).
 *   The write is ONE database transaction, `apply_import_session` (service role): accepted list
 *   writes + journal + session transition commit together or not at all; conflicts and rejected item
 *   data are a partial outcome, not a failure; an `idempotencyKey` replay returns the stored outcome
 *   (`replayed: true`) and writes nothing. The exact account-deletion barrier is HTTP 403,
 *   code ACCOUNT_DELETION_IN_PROGRESS, retryable false. Other RPC errors or unreadable results are HTTP 500
 *   `{ error, status: "failed", retryable: true }`.
 *   Response `{ success, sessionId, applied[], skipped[], conflicts[], errors[], status, undoable, replayed }`.
 * Side effects:
 *   REQUIRED (inside the transaction): list writes, journal, session status, import-origin taste
 *     marking (taste_import_context is set and cleared by the RPC itself).
 *   OPTIONAL (after commit, best-effort, never change the response, skipped on a replay): the
 *     per-user title alias (`title_aliases`, parse learning) and `log_concierge_run` analytics.
 * Reads before the transaction: catalog episode/chapter counts for an implied "completed"/"caught up"
 * progress (public data; a failed read means "unknown progress", as before).
 * No remote imports here (index.ts owns supabase-js and env).
 */
import { normalizeAliasKey } from "../_shared/alias_normalization.ts";
import { interpretRateLimit, rateLimitBlockedResponse } from "../_shared/rate_limit_gate.ts";
import {
  APPLY_FAILED_BODY,
  type ApplyOutcome,
  applyResponseBody,
  clampInt,
  emptyApplyBody,
  type ListStatus,
  type MediaType,
  parseApplyOutcome,
  planApplyItem,
  type PlannedItem,
  statedProgress,
  statusToWrite,
  type ValidatedItem,
  validateApplyRequest,
} from "./apply_plan.ts";

/** Supabase-js client (structurally untyped, as before). */
// deno-lint-ignore no-explicit-any
export type SupabaseLike = any;

export interface ApplyPlatform {
  /** Client bound to the caller's Authorization header, or null when SUPABASE_URL / an API key is missing. */
  client(authHeader: string): SupabaseLike | null;
  /** Service-role client for the import transaction RPC, or null when SUPABASE_SERVICE_ROLE_KEY is missing. */
  serviceClient(): SupabaseLike | null;
}

function json(res: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(res), {
    ...init,
    headers: { "Content-Type": "application/json", ...(init.headers ?? {}) },
  });
}

function clientIp(req: Request): string | null {
  const xf = req.headers.get("x-forwarded-for");
  if (xf) {
    const first = xf.split(",")[0]?.trim();
    if (first) return first;
  }
  const real = req.headers.get("x-real-ip")?.trim();
  if (real) return real;
  const cf = req.headers.get("cf-connecting-ip")?.trim();
  if (cf) return cf;
  return null;
}

async function bumpTitleAlias(client: SupabaseLike, args: {
  userId: string;
  aliasNorm: string;
  mediaType: MediaType;
  mediaId: number;
  titleRaw?: string | null;
}) {
  const aliasNorm = args.aliasNorm;
  if (!aliasNorm) return;

  const existing = await client
    .from("title_aliases")
    .select("hits")
    .eq("user_id", args.userId)
    .eq("alias_norm", aliasNorm)
    .eq("media_type", args.mediaType)
    .maybeSingle();

  const nextHits = clampInt((existing.data?.hits ?? 0) + 1, 1, 1_000_000) ?? 1;

  await client
    .from("title_aliases")
    .upsert({
      user_id: args.userId,
      alias_norm: aliasNorm,
      media_type: args.mediaType,
      media_id: args.mediaId,
      title_raw: args.titleRaw ?? null,
      hits: nextHits,
    }, { onConflict: "user_id,alias_norm,media_type" });
}

async function fetchLatestEpisodeNumber(client: SupabaseLike, animeId: number): Promise<number | null> {
  const res = await client
    .from("episodes")
    .select("number")
    .eq("anime_id", animeId)
    .not("number", "is", null)
    .order("number", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (res.error) return null;
  const n = clampInt(res.data?.number, 0, 100_000);
  return n ?? null;
}

/** Progress to write: the item's own value, else the catalog count for "completed" / "caught up". */
async function resolveProgress(
  client: SupabaseLike,
  item: ValidatedItem,
  // deno-lint-ignore no-explicit-any
  it: any,
  status: ListStatus,
): Promise<number | null> {
  const stated = statedProgress(item, it);
  const caughtUp = it?.caughtUp === true;
  if (stated != null || !(caughtUp || status === "COMPLETED")) return stated;
  if (item.mediaType === "ANIME") {
    const { data: animeRow } = await client
      .from("anime")
      .select("episodes,next_episode_number,status")
      .eq("id", item.mediaId)
      .maybeSingle();
    const nextEp = clampInt(animeRow?.next_episode_number, 0, 100_000);
    const totalKnown = clampInt(animeRow?.episodes, 0, 100_000);
    if (status === "COMPLETED") return totalKnown ?? await fetchLatestEpisodeNumber(client, item.mediaId);
    return nextEp != null && nextEp > 0 ? Math.max(0, nextEp - 1) : await fetchLatestEpisodeNumber(client, item.mediaId);
  }
  const { data: mangaRow } = await client
    .from("manga")
    .select("chapters,status")
    .eq("id", item.mediaId)
    .maybeSingle();
  return clampInt(mangaRow?.chapters, 0, 500_000);
}

/** Optional effects after commit: best-effort, never change the response. */
async function recordOptionalEffects(
  client: SupabaseLike,
  userId: string,
  // deno-lint-ignore no-explicit-any
  items: Array<{ raw: any; item: ValidatedItem }>,
  outcome: ApplyOutcome,
) {
  const applied = new Set(outcome.applied.map((a) => `${a.mediaType}:${a.mediaId}`));
  await Promise.all(items.map(async ({ raw: it, item }) => {
    if (!applied.has(`${item.mediaType}:${item.mediaId}`)) return;
    try {
      await bumpTitleAlias(client, {
        userId,
        aliasNorm: normalizeAliasKey(it?.raw ?? it?.normalized ?? ""),
        mediaType: item.mediaType,
        mediaId: item.mediaId,
        titleRaw: typeof it?.titleRaw === "string" ? it.titleRaw : null,
      });
    } catch {
      // optional: alias learning only
    }
  }));
  try {
    await client.rpc("log_concierge_run", {
      p_kind: "apply",
      p_status: outcome.errors.length ? "error" : "success",
      p_items_count: items.length,
      p_error: outcome.errors.length ? JSON.stringify(outcome.errors).slice(0, 1000) : null,
    });
  } catch {
    // optional: metrics only
  }
}

export async function handleApply(req: Request, platform: ApplyPlatform): Promise<Response> {
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, { status: 405 });

    const authHeader = req.headers.get("Authorization") ?? "";
    const client = platform.client(authHeader);
    const service = platform.serviceClient();
    if (!client || !service) {
      return json({ error: "Missing SUPABASE_URL, a Supabase API key env (SUPABASE_ANON_KEY) or SUPABASE_SERVICE_ROLE_KEY" }, { status: 500 });
    }

    const ip = clientIp(req);

    // Auth, rate-limit check and body parsing are independent.
    const [authResult, rlResult, body] = await Promise.all([
      client.auth.getUser(),
      client.rpc("check_concierge_rate_limit", {
        p_kind: "apply",
        p_ip: ip,
        p_window_seconds: null,
        p_max_user: null,
        p_max_ip: null,
      }).then((r: unknown) => r, (error: unknown) => ({ data: null, error })),
      req.json().catch(() => ({})),
    ]);

    const { data: userData, error: userErr } = authResult;
    if (userErr || !userData?.user) return json({ error: "Unauthorized" }, { status: 401 });
    const userId: string = userData.user.id;

    const blocked = rateLimitBlockedResponse(interpretRateLimit(rlResult), json);
    if (blocked) return blocked;

    const validation = validateApplyRequest(body);
    if (!validation.ok) return json(validation.body, { status: 400 });
    const { items, idempotencyKey } = validation.request;
    if (items.length === 0) return json(emptyApplyBody());

    const planned: PlannedItem[] = await Promise.all(items.map(async ({ raw, item }) => {
      const status = statusToWrite(item, raw);
      const progress = item.importAction === "skip" ? null : await resolveProgress(client, item, raw, status);
      return planApplyItem({ item, raw, status, progress });
    }));

    // ONE transaction: list writes + journal + session transition (+ import-origin taste marking).
    const { data, error } = await service.rpc("apply_import_session", {
      p_user_id: userId,
      p_session_id: crypto.randomUUID(),
      p_idempotency_key: idempotencyKey,
      p_items: planned,
    });
    if (error?.code === "42501" && error?.message === "ACCOUNT_DELETION_IN_PROGRESS") {
      return json({
        error: "This account is being deleted. Imports are no longer accepted.",
        code: "ACCOUNT_DELETION_IN_PROGRESS",
        status: "failed",
        retryable: false,
      }, { status: 403 });
    }
    const outcome = error ? null : parseApplyOutcome(data);
    if (!outcome) return json(APPLY_FAILED_BODY, { status: 500 });

    if (!outcome.replayed) await recordOptionalEffects(client, userId, items, outcome);

    return json(applyResponseBody(outcome));
  } catch {
    // Nothing is written by the handler itself; the transaction either committed (a retry with the
    // same idempotencyKey replays it) or did not.
    return json(APPLY_FAILED_BODY, { status: 500 });
  }
}
