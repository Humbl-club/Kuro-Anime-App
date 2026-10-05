/**
 * Account-deletion orchestration for the `delete-account` edge function.
 *
 * PURE MODULE: no network, no Deno APIs and no remote imports, so
 * `deno check` / `deno test` run offline and the tests execute exactly this
 * production code with controlled fake dependencies.
 *
 * Contract (what the function guarantees):
 *   - `userId` is the JWT-derived id supplied by the caller; this module never
 *     reads a request body.
 *   - Order (prepared SQL 20261005140000 + 20261005150000):
 *       1. begin_account_deletion (service role): the database WRITE BARRIER. It
 *          waits for every in-flight write of this user and from then on refuses
 *          new user-keyed writes (own JWT and service-role writers alike), so no
 *          row can appear behind the cleanup (F38). Fail fast.
 *       2. delete_user_concierge_data under the user's JWT (authorization check +
 *          concierge data). Fail fast; refusal => 403.
 *       3. REQUIRED cleanup, all attempted, failures reported together:
 *          delete_account_club_memberships (service role: the SAME club lifecycle
 *          leave_club uses: ownership transfer, empty-club deletion under the club
 *          lock; only this user's clubs, never a global sweep: F37/F39), the
 *          user-keyed TEXT tables without a cascade (both the canonical lower-case
 *          and the legacy upper-case spelling of the id: F16), storage, profile.
 *       4. The auth user LAST and only after every required step succeeded. Rows
 *          that reference auth.users with ON DELETE CASCADE / SET NULL (verified by
 *          supabase/tests/rls/50_account_deletion_fk_and_rpc.sql) are covered by it.
 *     Any failure => `ok: false` and the auth user is NOT deleted, so the function
 *     never reports success after a partial deletion.
 *   - Retry/idempotency: the barrier and the club step are idempotent RPCs, every
 *     delete is a no-op when its data is already gone, and the auth user exists
 *     until the very last step, so the client's JWT stays valid and a second
 *     invocation after a partial failure finishes the job. The barrier persists
 *     across retries (the account accepts no new data while its deletion is
 *     pending) and outlives the auth user for the token lifetime.
 */

/** Result of an operation that either works or reports a message. */
export interface OpResult {
  error: string | null;
}

/** Outcome of the `delete_user_concierge_data` RPC (called with the user's JWT). */
export type RpcOutcome =
  | { kind: "ok" }
  | { kind: "error"; message: string }
  | { kind: "refused"; reason: string };

/** One entry of a storage listing; `id` is null/absent for virtual folders. */
export interface StorageEntry {
  name: string;
  id?: string | null;
}

/**
 * Legacy tables keyed by a TEXT user_id with NO foreign key to auth.users, so
 * the final auth deletion does not cascade into them.
 *   anime_user_lists / manga_user_lists: always deleted here.
 *   anime_comments / manga_comments: not removed by delete_user_concierge_data
 *   (any version in the repo) nor by the previous function. Included as required
 *   deletes so the auth user is not removed while personal comment rows remain.
 *   The lead may drop the two comment tables from this list to revert that
 *   scope addition.
 */
export const REQUIRED_TEXT_USER_TABLES = [
  "anime_user_lists",
  "manga_user_lists",
  "anime_comments",
  "manga_comments",
] as const;
export type RequiredTextUserTable = typeof REQUIRED_TEXT_USER_TABLES[number];

/**
 * Every spelling of the user id a legacy TEXT row may carry: the canonical
 * lower-case uuid text (what auth.uid()::text and the server write) and the
 * upper-case `uuidString` older native builds sent (F16). A deletion that matched
 * only one spelling would leave the other behind.
 */
export function userIdSpellings(userId: string): string[] {
  const canonical = userId.trim().toLowerCase();
  const upper = canonical.toUpperCase();
  return upper === canonical ? [canonical] : [canonical, upper];
}

/** Storage bucket holding user uploads; objects live under `<userId>/...`. */
export const STORAGE_BUCKET = "media";

const STORAGE_PAGE_SIZE = 100;
const STORAGE_MAX_PAGES_PER_PREFIX = 50;
const STORAGE_MAX_DEPTH = 4;

/** Everything the deletion needs from the outside world. */
export interface DeletionDeps {
  /** RPC `begin_account_deletion` (service role): per-user write barrier. Idempotent. */
  beginAccountDeletion(userId: string): Promise<OpResult>;
  /** RPC `delete_user_concierge_data`, executed with the USER's JWT so auth.uid() resolves. */
  deleteUserConciergeData(userId: string): Promise<RpcOutcome>;
  /** RPC `delete_account_club_memberships` (service role): the shared club lifecycle. Idempotent. */
  deleteClubMemberships(userId: string): Promise<OpResult>;
  /** DELETE FROM <table> WHERE user_id IN (<userIds>) (TEXT column). */
  deleteRowsByUserIds(table: RequiredTextUserTable, userIds: string[]): Promise<OpResult>;
  /** List up to `limit` entries directly under `prefix` (offset 0 each call). */
  listStorageObjects(prefix: string, limit: number): Promise<{ entries: StorageEntry[]; error: string | null }>;
  removeStorageObjects(paths: string[]): Promise<OpResult>;
  deleteProfile(userId: string): Promise<OpResult>;
  /** Irreversible. Must treat "user already gone" as success. */
  deleteAuthUser(userId: string): Promise<OpResult>;
}

export type DeletionOutcome =
  | { ok: true; warnings: string[] }
  | {
    ok: false;
    status: 403 | 500;
    error: string;
    detail: string;
    failedSteps: string[];
    warnings: string[];
  };

/** Convert a thrown dependency error (e.g. a network failure) into a message. */
function messageOf(e: unknown): string {
  if (e instanceof Error && e.message) return e.message;
  return typeof e === "string" && e ? e : "unknown error";
}

async function attempt(fn: () => Promise<OpResult>): Promise<OpResult> {
  try {
    return await fn();
  } catch (e) {
    return { error: messageOf(e) };
  }
}

/**
 * Remove every object under `prefix` (recursing into folders), paging until the
 * listing is empty. Bounded so a backend that "succeeds" without removing cannot
 * loop forever; in that case it fails closed with a message.
 */
async function purgeStoragePrefix(deps: DeletionDeps, prefix: string, depth: number): Promise<string | null> {
  for (let page = 0; page < STORAGE_MAX_PAGES_PER_PREFIX; page++) {
    let listing: { entries: StorageEntry[]; error: string | null };
    try {
      listing = await deps.listStorageObjects(prefix, STORAGE_PAGE_SIZE);
    } catch (e) {
      return `list ${STORAGE_BUCKET}/${prefix}: ${messageOf(e)}`;
    }
    if (listing.error) return `list ${STORAGE_BUCKET}/${prefix}: ${listing.error}`;
    if (listing.entries.length === 0) return null;

    const files = listing.entries.filter((entry) => entry.id != null);
    const folders = listing.entries.filter((entry) => entry.id == null);

    if (files.length > 0) {
      const removed = await attempt(() => deps.removeStorageObjects(files.map((f) => `${prefix}/${f.name}`)));
      if (removed.error) return `remove ${STORAGE_BUCKET}/${prefix}: ${removed.error}`;
    }
    for (const folder of folders) {
      if (depth >= STORAGE_MAX_DEPTH) return `storage folders nested deeper than ${STORAGE_MAX_DEPTH} under ${prefix}`;
      const nested = await purgeStoragePrefix(deps, `${prefix}/${folder.name}`, depth + 1);
      if (nested) return nested;
    }
  }
  return `storage purge incomplete for ${STORAGE_BUCKET}/${prefix} after ${STORAGE_MAX_PAGES_PER_PREFIX} pages`;
}

/**
 * Run the deletion for the JWT-authenticated user `userId`.
 * Returns `ok: true` only when the auth user was deleted after all required
 * cleanup succeeded.
 */
export async function runAccountDeletion(deps: DeletionDeps, userId: string): Promise<DeletionOutcome> {
  const warnings: string[] = [];
  if (!userId) {
    return { ok: false, status: 500, error: "Missing user id", detail: "no authenticated user id", failedSteps: ["authenticate"], warnings };
  }

  // 1. Write barrier (required, fail fast): nothing is deleted unless no new row
  //    can appear behind the cleanup any more.
  const barrier = await attempt(() => deps.beginAccountDeletion(userId));
  if (barrier.error) {
    return {
      ok: false,
      status: 500,
      error: "Account deletion could not start",
      detail: barrier.error,
      failedSteps: ["begin_account_deletion"],
      warnings,
    };
  }

  // 2. RPC (required, fail fast: it is also the authorization check, since it
  //    refuses a caller whose auth.uid() differs from p_user_id).
  let rpc: RpcOutcome;
  try {
    rpc = await deps.deleteUserConciergeData(userId);
  } catch (e) {
    rpc = { kind: "error", message: messageOf(e) };
  }
  if (rpc.kind === "error") {
    return {
      ok: false,
      status: 500,
      error: "RPC delete_user_concierge_data failed",
      detail: rpc.message,
      failedSteps: ["delete_user_concierge_data"],
      warnings,
    };
  }
  if (rpc.kind === "refused") {
    return {
      ok: false,
      status: 403,
      error: "RPC refused",
      detail: rpc.reason,
      failedSteps: ["delete_user_concierge_data"],
      warnings,
    };
  }

  // 3. Required cleanup. Independent and idempotent, so all of them run and
  //    every failure is reported together.
  const failed: string[] = [];
  const details: string[] = [];

  const clubs = await attempt(() => deps.deleteClubMemberships(userId));
  if (clubs.error) {
    failed.push("club_memberships");
    details.push(`club_memberships: ${clubs.error}`);
  }

  const spellings = userIdSpellings(userId);
  for (const table of REQUIRED_TEXT_USER_TABLES) {
    const result = await attempt(() => deps.deleteRowsByUserIds(table, spellings));
    if (result.error) {
      failed.push(table);
      details.push(`${table}: ${result.error}`);
    }
  }

  // The barrier transaction has committed, so a storage INSERT either waited on
  // its shared lock and then failed the policy, or starts later and sees the
  // barrier. This purge removes objects that landed before that lock. The second
  // call must observe an empty prefix; success is refused if it does not.
  const storageError = await purgeStoragePrefix(deps, userId, 0);
  const storageConfirm = storageError ? null : await purgeStoragePrefix(deps, userId, 0);
  if (storageError || storageConfirm) {
    failed.push(`storage:${STORAGE_BUCKET}`);
    details.push(storageError ?? storageConfirm ?? "storage confirm failed");
  }

  const profile = await attempt(() => deps.deleteProfile(userId));
  if (profile.error) {
    failed.push("profiles");
    details.push(`profiles: ${profile.error}`);
  }

  if (failed.length > 0) {
    return {
      ok: false,
      status: 500,
      error: "Account cleanup incomplete",
      detail: details.join("; "),
      failedSteps: failed,
      warnings,
    };
  }

  // 4. Auth user last (irreversible). Everything keyed to auth.users with
  //    CASCADE / SET NULL is handled by this deletion.
  const auth = await attempt(() => deps.deleteAuthUser(userId));
  if (auth.error) {
    return {
      ok: false,
      status: 500,
      error: "Failed to delete auth user",
      detail: auth.error,
      failedSteps: ["auth.users"],
      warnings,
    };
  }

  return { ok: true, warnings };
}
