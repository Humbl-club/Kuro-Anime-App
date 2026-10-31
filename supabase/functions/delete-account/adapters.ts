/**
 * Production adapters for `delete-account`: map the Supabase clients onto the
 * narrow `DeletionDeps` / `HandlerPlatform` interfaces.
 *
 * No remote imports. The supabase-js client is passed in as `createClient` and
 * described structurally (only the methods used), which keeps this file
 * type-checkable and unit-testable offline. `index.ts` wires the real package.
 */
import type { AuthUser, HandlerPlatform, RequestScope } from "./handler.ts";
import { type DeletionDeps, type RequiredTextUserTable, STORAGE_BUCKET } from "./deletion.ts";

type DbError = { message: string; code?: string; status?: number } | null;

interface FilterLike extends PromiseLike<{ data?: unknown; count?: number | null; error: DbError }> {
  eq(column: string, value: string): FilterLike;
  in(column: string, values: string[]): FilterLike;
}

interface TableLike {
  delete(): FilterLike;
}

/** The part of a service-role client used for cleanup. */
export interface AdminClientLike {
  from(table: string): TableLike;
  rpc(fn: string, args: Record<string, unknown>): PromiseLike<{ data: unknown; error: DbError }>;
  storage: {
    from(bucket: string): {
      list(
        path: string,
        options: { limit: number; offset: number },
      ): PromiseLike<{ data: { name: string; id?: string | null }[] | null; error: DbError }>;
      remove(paths: string[]): PromiseLike<{ error: DbError }>;
    };
  };
  auth: { admin: { deleteUser(id: string): PromiseLike<{ error: DbError }> } };
}

/** The part of a user-JWT client used for authentication and the RPC. */
export interface UserClientLike {
  auth: { getUser(): PromiseLike<{ data: { user: AuthUser | null } | null; error: unknown }> };
  rpc(fn: string, args: Record<string, unknown>): PromiseLike<{ data: unknown; error: DbError }>;
}

export type CreateClientFn = (
  url: string,
  key: string,
  options?: { global?: { headers?: Record<string, string> } },
) => unknown;

export interface FunctionEnv {
  supabaseUrl: string | undefined;
  supabaseAnonKey: string | undefined;
  serviceRoleKey: string | undefined;
  appleClientId?: string | undefined;
  appleClientSecret?: string | undefined;
}

/**
 * A service-role RPC that must answer `{ success: true }`. A transport error or
 * any other answer is a failure (never read as "done").
 */
async function requireSuccessRpc(admin: AdminClientLike, fn: string, userId: string): Promise<{ error: string | null }> {
  const { data, error } = await admin.rpc(fn, { p_user_id: userId });
  if (error) return { error: error.message };
  if ((data as { success?: unknown } | null)?.success !== true) return { error: `${fn} did not report success` };
  return { error: null };
}

/** Deletion dependencies backed by real clients. */
export function createDeletionDeps(admin: AdminClientLike, user: UserClientLike): DeletionDeps {
  return {
    beginAccountDeletion(userId) {
      // Service role: the id is the JWT-verified caller (handler), never request input.
      return requireSuccessRpc(admin, "begin_account_deletion", userId);
    },

    async deleteUserConciergeData(userId) {
      // Called via the user's JWT so auth.uid() resolves inside the SECURITY DEFINER RPC.
      const { data, error } = await user.rpc("delete_user_concierge_data", { p_user_id: userId });
      if (error) return { kind: "error", message: error.message };
      const refused = (data as { error?: unknown } | null)?.error;
      if (refused) return { kind: "refused", reason: String(refused) };
      if ((data as { success?: unknown } | null)?.success !== true) {
        return { kind: "error", message: "delete_user_concierge_data did not report success" };
      }
      return { kind: "ok" };
    },

    deleteClubMemberships(userId) {
      return requireSuccessRpc(admin, "delete_account_club_memberships", userId);
    },

    async deleteRowsByUserIds(table: RequiredTextUserTable, userIds) {
      const { error } = await admin.from(table).delete().in("user_id", userIds);
      return { error: error?.message ?? null };
    },

    async listStorageObjects(prefix, limit) {
      const { data, error } = await admin.storage.from(STORAGE_BUCKET).list(prefix, { limit, offset: 0 });
      if (error) return { entries: [], error: error.message };
      return { entries: data ?? [], error: null };
    },

    async removeStorageObjects(paths) {
      const { error } = await admin.storage.from(STORAGE_BUCKET).remove(paths);
      return { error: error?.message ?? null };
    },

    async deleteProfile(userId) {
      const { error } = await admin.from("profiles").delete().eq("id", userId);
      return { error: error?.message ?? null };
    },

    async deleteAuthUser(userId) {
      const { error } = await admin.auth.admin.deleteUser(userId);
      // Idempotent: a user that is already gone (concurrent or repeated request) is success.
      if (error && (error.code === "user_not_found" || error.status === 404)) return { error: null };
      return { error: error?.message ?? null };
    },
  };
}

/**
 * Exchange the Apple authorization code for a refresh token and revoke it
 * (App Review Guideline 5.1.1(v)). Best-effort: never throws. One five-second
 * deadline covers both requests and token-body consumption before deletion continues.
 */
export async function revokeAppleToken(
  authorizationCode: string,
  env: Pick<FunctionEnv, "appleClientId" | "appleClientSecret">,
  fetchFn: typeof fetch = fetch,
  timeoutMs = 5_000,
): Promise<void> {
  const clientId = env.appleClientId;
  const clientSecret = env.appleClientSecret;
  if (!clientId || !clientSecret) return;
  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      controller.abort();
      reject(new Error("Apple token revocation timed out"));
    }, timeoutMs);
  });
  try {
    await Promise.race([
      deadline,
      (async () => {
        const tokenRes = await fetchFn("https://appleid.apple.com/auth/token", {
          signal: controller.signal,
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({
            client_id: clientId,
            client_secret: clientSecret,
            code: authorizationCode,
            grant_type: "authorization_code",
          }),
        });
        controller.signal.throwIfAborted();
        if (!tokenRes.ok) return;
        const tokenData = await tokenRes.json();
        controller.signal.throwIfAborted();
        const refreshToken = tokenData?.refresh_token;
        if (!refreshToken) return;
        const revokeRes = await fetchFn("https://appleid.apple.com/auth/revoke", {
          signal: controller.signal,
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({
            client_id: clientId,
            client_secret: clientSecret,
            token: refreshToken,
            token_type_hint: "refresh_token",
          }),
        });
        await revokeRes.body?.cancel();
      })(),
    ]);
  } catch {
    // Token revocation is best-effort; don't block account deletion.
  } finally {
    clearTimeout(timer);
  }
}

/** Wire real clients into the handler's platform interface. */
export function createPlatform(env: FunctionEnv, createClient: CreateClientFn, fetchFn: typeof fetch = fetch): HandlerPlatform {
  return {
    scope(authHeader: string): RequestScope | null {
      const { supabaseUrl, supabaseAnonKey, serviceRoleKey } = env;
      if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey) return null;
      const userClient = createClient(supabaseUrl, supabaseAnonKey, {
        global: { headers: { Authorization: authHeader } },
      }) as UserClientLike;
      const adminClient = createClient(supabaseUrl, serviceRoleKey) as AdminClientLike;
      return {
        async authenticate() {
          const { data, error } = await userClient.auth.getUser();
          if (error || !data?.user) return null;
          return data.user;
        },
        deps: createDeletionDeps(adminClient, userClient),
      };
    },
    revokeAppleToken: (code) => revokeAppleToken(code, env, fetchFn),
  };
}
