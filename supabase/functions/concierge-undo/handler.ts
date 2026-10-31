/**
 * Request handling for `concierge-undo` (thin index.ts injects the platform), so the real flow runs
 * against an injected Supabase-shaped client in Deno tests.
 *
 * Contract (wire v2, docs/plans/2026-10-05-modularity-completion-contracts.md section 3):
 *   POST `{ sessionId }`. Identity ONLY from the JWT. Limiter kind `undo` through the shared gate
 *   (denial 429, limiter error/unknown result 503, nothing reverted). The revert is ONE database
 *   transaction, `undo_import_session` (service role, JWT user passed as p_user_id): only the
 *   caller's most recent applied session (409 otherwise; 404 when missing, not the caller's or with
 *   nothing journaled); compare-and-revert per field; later edits/deletions kept and reported in
 *   `skipped[]`; an already-undone session is 200 `status: "undone"` with empty `reverted`.
 *   The exact account-deletion barrier is HTTP 403, code ACCOUNT_DELETION_IN_PROGRESS, retryable false.
 *   Other transaction errors or unreadable results are HTTP 500 `{ error, status: "failed", retryable: true }`
 *   and the session stays undoable. Response `{ success, sessionId, reverted[], skipped[], warnings[], errors[], status }`.
 * Side effects: REQUIRED (inside the transaction): list reverts, journal `reverted_at`, session
 *   `cancelled`, import-origin taste marking of the revert writes (as concierge-apply).
 *   OPTIONAL (after commit, best-effort): `log_concierge_run` analytics.
 * No remote imports here (index.ts owns supabase-js and env).
 */
import { interpretRateLimit, rateLimitBlockedResponse } from "../_shared/rate_limit_gate.ts";
import { parseUndoResult, UNDO_FAILED_BODY, undoResponse, validateUndoRequest } from "./undo_plan.ts";

/** Supabase-js client (structurally untyped, as before). */
// deno-lint-ignore no-explicit-any
export type SupabaseLike = any;

export interface UndoPlatform {
  /** Client bound to the caller's Authorization header, or null when SUPABASE_URL / an API key is missing. */
  client(authHeader: string): SupabaseLike | null;
  /** Service-role client for the Undo transaction RPC, or null when SUPABASE_SERVICE_ROLE_KEY is missing. */
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

export async function handleUndo(req: Request, platform: UndoPlatform): Promise<Response> {
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, { status: 405 });

    const authHeader = req.headers.get("Authorization") ?? "";
    const client = platform.client(authHeader);
    const service = platform.serviceClient();
    if (!client || !service) {
      return json({ error: "Missing SUPABASE_URL, a Supabase API key env (SUPABASE_ANON_KEY) or SUPABASE_SERVICE_ROLE_KEY" }, { status: 500 });
    }

    const { data: userData, error: userErr } = await client.auth.getUser();
    if (userErr || !userData?.user) return json({ error: "Unauthorized" }, { status: 401 });
    const userId: string = userData.user.id;

    const rl = await client.rpc("check_concierge_rate_limit", {
      p_kind: "undo",
      p_ip: clientIp(req),
      p_window_seconds: null,
      p_max_user: null,
      p_max_ip: null,
    }).then((r: unknown) => r, (error: unknown) => ({ data: null, error }));
    const blocked = rateLimitBlockedResponse(interpretRateLimit(rl), json);
    if (blocked) return blocked;

    const validation = validateUndoRequest(await req.json().catch(() => ({})));
    if (!validation.ok) return json(validation.body, { status: 400 });
    const { sessionId } = validation;

    // ONE transaction: compare-and-revert every journaled item, then cancel the session.
    const { data, error } = await service.rpc("undo_import_session", { p_user_id: userId, p_session_id: sessionId });
    if (error?.code === "42501" && error?.message === "ACCOUNT_DELETION_IN_PROGRESS") {
      return json({
        error: "This account is being deleted. Imports can no longer be undone.",
        code: "ACCOUNT_DELETION_IN_PROGRESS",
        status: "failed",
        retryable: false,
      }, { status: 403 });
    }
    const result = error ? null : parseUndoResult(data);
    if (!result) return json(UNDO_FAILED_BODY, { status: 500 });

    if (result.result === "undone") {
      try {
        await client.rpc("log_concierge_run", {
          p_kind: "undo",
          p_status: "success",
          p_items_count: result.reverted.length + result.skipped.length,
          p_error: null,
        });
      } catch {
        // optional: metrics only
      }
    }

    const response = undoResponse(result, sessionId);
    return json(response.body, { status: response.status });
  } catch {
    // The handler writes nothing itself; the transaction either committed or rolled back.
    return json(UNDO_FAILED_BODY, { status: 500 });
  }
}
