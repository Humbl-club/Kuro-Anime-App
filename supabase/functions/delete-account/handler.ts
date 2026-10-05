/**
 * Request handling for `delete-account`, separated from `index.ts` so the real
 * production flow (method check, env check, JWT auth, Apple revocation, deletion
 * result mapping) can be exercised with injected platform dependencies.
 *
 * The user id comes ONLY from the authenticated JWT (`scope.authenticate()`);
 * the request body is read solely for the optional `apple_authorization_code`.
 * No remote imports here.
 */
import { type DeletionDeps, runAccountDeletion } from "./deletion.ts";

/** The slice of the authenticated Supabase user this function needs. */
export interface AuthUser {
  id: string;
  app_metadata?: { providers?: string[] } | null;
  identities?: { provider: string }[] | null;
}

/** Clients bound to one request's Authorization header. */
export interface RequestScope {
  /** Resolve the caller from the JWT; null when the token is missing/invalid. */
  authenticate(): Promise<AuthUser | null>;
  deps: DeletionDeps;
}

export interface HandlerPlatform {
  /** Build the request scope, or return null when required env vars are missing. */
  scope(authHeader: string): RequestScope | null;
  /** Best-effort Apple Sign-In token revocation (App Review Guideline 5.1.1(v)). */
  revokeAppleToken(authorizationCode: string): Promise<void>;
}

function json(res: unknown, status = 200): Response {
  return new Response(JSON.stringify(res), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export function isAppleUser(user: AuthUser): boolean {
  return Boolean(
    user.app_metadata?.providers?.includes("apple") ||
      user.identities?.some((identity) => identity.provider === "apple"),
  );
}

export async function handleDeleteAccount(req: Request, platform: HandlerPlatform): Promise<Response> {
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

    const authHeader = req.headers.get("Authorization") ?? "";
    const scope = platform.scope(authHeader);
    if (!scope) return json({ error: "Missing env vars" }, 500);

    // Optional body: only the Apple authorization code is read. Any user id in
    // the body is ignored by construction.
    let appleAuthorizationCode: string | null = null;
    try {
      const body = await req.json();
      const code = body?.apple_authorization_code;
      appleAuthorizationCode = typeof code === "string" && code.length > 0 ? code : null;
    } catch { /* no body or invalid JSON is fine */ }

    const user = await scope.authenticate();
    if (!user || !user.id) return json({ error: "Unauthorized" }, 401);

    // Apple token revocation is best-effort and must never block deletion.
    if (appleAuthorizationCode && isAppleUser(user)) {
      try {
        await platform.revokeAppleToken(appleAuthorizationCode);
      } catch { /* best-effort */ }
    }

    const outcome = await runAccountDeletion(scope.deps, user.id);

    for (const warning of outcome.warnings) {
      console.warn(`delete-account warning: ${warning}`);
    }

    if (outcome.ok) return json({ success: true });

    console.error(`delete-account failed: ${outcome.error}; steps=${outcome.failedSteps.join(",")}`);
    return json(
      {
        error: outcome.error,
        detail: outcome.detail,
        failed_steps: outcome.failedSteps,
      },
      outcome.status,
    );
  } catch (err) {
    return json({ error: err instanceof Error && err.message ? err.message : "Internal error" }, 500);
  }
}
