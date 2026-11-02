// Pure request validation and outcome mapping for concierge-undo (no I/O, no remote imports).
//
// The revert itself is the database transaction `undo_import_session` (prepared migration
// supabase/prepared-migrations/20261005130000_import_apply_undo_transactions.sql, P2-R2): under the
// row lock it compares each journaled item's CURRENT row with the after image field by field, deletes
// an unchanged add, reverts only the fields still equal to what the import wrote, keeps later edits
// and later deletions (reported in `skipped` as edited_since_import | deleted_since_import), and
// cancels the session only after every item resolved. Any error rolls the whole Undo back (the
// session stays `applied`, retryable). This replaces the former read-then-upsert plan (F08, F09, F13).

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** `{ sessionId }` as the transaction takes it: a uuid string. */
export function validateUndoRequest(
  // deno-lint-ignore no-explicit-any
  body: any,
): { ok: true; sessionId: string } | { ok: false; body: Record<string, unknown> } {
  const sessionId = body?.sessionId;
  if (typeof sessionId !== "string" || !sessionId) return { ok: false, body: { error: "Missing sessionId" } };
  if (!UUID.test(sessionId)) return { ok: false, body: { error: "Invalid sessionId", code: "INVALID_SESSION_ID" } };
  return { ok: true, sessionId };
}

export type UndoResult = {
  result: "undone" | "already_undone" | "not_found" | "not_latest";
  reverted: unknown[];
  skipped: unknown[];
  warnings: unknown[];
};

const RESULTS = new Set(["undone", "already_undone", "not_found", "not_latest"]);

/** The RPC data as a result, or null when it is not the contract shape (handled as a failed call). */
export function parseUndoResult(data: unknown): UndoResult | null {
  if (!data || typeof data !== "object" || Array.isArray(data)) return null;
  const d = data as Record<string, unknown>;
  if (typeof d.result !== "string" || !RESULTS.has(d.result)) return null;
  const list = (v: unknown) => (Array.isArray(v) ? v : []);
  if ((d.result === "undone") && ![d.reverted, d.skipped, d.warnings].every(Array.isArray)) return null;
  return {
    result: d.result as UndoResult["result"],
    reverted: list(d.reverted),
    skipped: list(d.skipped),
    warnings: list(d.warnings),
  };
}

/** HTTP status + body for a transaction result. */
export function undoResponse(result: UndoResult, sessionId: string): { status: number; body: Record<string, unknown> } {
  switch (result.result) {
    case "not_found":
      // Missing, another user's, or nothing journaled to undo: indistinguishable on purpose.
      return { status: 404, body: { error: "No applied session to undo" } };
    case "not_latest":
      return { status: 409, body: { error: "Can only undo the most recent import session" } };
    case "already_undone":
    case "undone":
      return {
        status: 200,
        body: {
          success: true,
          sessionId,
          reverted: result.reverted,
          skipped: result.skipped,
          warnings: result.warnings,
          errors: [],
          status: "undone",
        },
      };
  }
}

/** HTTP 500 body: the Undo transaction rolled back (or its result is unknown); the session stays undoable. */
export const UNDO_FAILED_BODY = { error: "Undo could not be completed", status: "failed", retryable: true } as const;
