import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function json(res: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(res), {
    ...init,
    headers: { "Content-Type": "application/json", ...(init.headers ?? {}) },
  });
}

serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, { status: 405 });

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !supabaseAnon || !serviceRoleKey) {
      return json({ error: "Missing env vars" }, { status: 500 });
    }

    // Parse optional body for Apple token revocation.
    let appleAuthorizationCode: string | null = null;
    try {
      const body = await req.json();
      appleAuthorizationCode = body?.apple_authorization_code ?? null;
    } catch { /* no body or invalid JSON is fine */ }

    // Authenticate the caller using their JWT.
    const authHeader = req.headers.get("Authorization") ?? "";
    const userClient = createClient(supabaseUrl, supabaseAnon, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData?.user) {
      return json({ error: "Unauthorized" }, { status: 401 });
    }
    const userId = userData.user.id;
    const user = userData.user;

    // Use service-role client for cascade deletion + auth user removal.
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    // -------------------------------------------------------
    // 0. Apple token revocation (App Review Guidelines 4.0)
    // -------------------------------------------------------
    const isAppleUser = user.app_metadata?.providers?.includes("apple") ||
      user.identities?.some((i: { provider: string }) => i.provider === "apple");

    if (isAppleUser && appleAuthorizationCode) {
      const appleClientId = Deno.env.get("APPLE_CLIENT_ID");
      const appleClientSecret = Deno.env.get("APPLE_CLIENT_SECRET");

      if (appleClientId && appleClientSecret) {
        // Exchange authorization code for a refresh token, then revoke it.
        try {
          const tokenRes = await fetch("https://appleid.apple.com/auth/token", {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body: new URLSearchParams({
              client_id: appleClientId,
              client_secret: appleClientSecret,
              code: appleAuthorizationCode,
              grant_type: "authorization_code",
            }),
          });

          if (tokenRes.ok) {
            const tokenData = await tokenRes.json();
            const refreshToken = tokenData.refresh_token;

            if (refreshToken) {
              await fetch("https://appleid.apple.com/auth/revoke", {
                method: "POST",
                headers: { "Content-Type": "application/x-www-form-urlencoded" },
                body: new URLSearchParams({
                  client_id: appleClientId,
                  client_secret: appleClientSecret,
                  token: refreshToken,
                  token_type_hint: "refresh_token",
                }),
              });
            }
          }
        } catch {
          // Token revocation is best-effort; don't block account deletion.
        }
      }
    }

    // -------------------------------------------------------
    // 1. Concierge, analytics & club data via DB RPC
    //    delete_user_concierge_data() handles: concierge_events,
    //    rag_retrieval_feedback, concierge_parse_feedback, concierge_runs,
    //    concierge_mode_cache, title_aliases, import_sessions/items,
    //    llm_daily_usage, user_taste_profiles, club_analytics,
    //    club_rail_item_reactions, club_votes, club_members,
    //    + SET NULL on clubs/club_rails/club_rail_items/club_polls.
    // -------------------------------------------------------
    // Call via user's JWT so auth.uid() resolves inside the RPC.
    // The function is SECURITY DEFINER so it bypasses RLS regardless.
    const { data: rpcResult, error: rpcErr } = await userClient.rpc(
      "delete_user_concierge_data",
      { p_user_id: userId }
    );
    if (rpcErr) {
      return json({ error: "RPC delete_user_concierge_data failed", detail: rpcErr.message }, { status: 500 });
    }
    if (rpcResult?.error) {
      return json({ error: "RPC refused", detail: rpcResult.error }, { status: 403 });
    }

    // -------------------------------------------------------
    // 2. Club ownership: delete orphaned clubs
    //    RPC already removed memberships and SET NULL on created_by.
    //    Now clean up clubs with no creator and no remaining members.
    // -------------------------------------------------------
    const { data: orphanedClubs } = await adminClient
      .from("clubs")
      .select("id")
      .is("created_by", null);
    if (orphanedClubs && orphanedClubs.length > 0) {
      for (const club of orphanedClubs) {
        const { count } = await adminClient
          .from("club_members")
          .select("id", { count: "exact", head: true })
          .eq("club_id", club.id);
        if (count === 0) {
          await adminClient.from("clubs").delete().eq("id", club.id);
        }
      }
    }

    // -------------------------------------------------------
    // 3. User lists (legacy TEXT user_id — not in RPC)
    // -------------------------------------------------------
    await adminClient.from("anime_user_lists").delete().eq("user_id", userId);
    await adminClient.from("manga_user_lists").delete().eq("user_id", userId);

    // -------------------------------------------------------
    // 4. Storage objects (user-uploaded media)
    // -------------------------------------------------------
    const { data: objects } = await adminClient.storage.from("media").list(userId);
    if (objects && objects.length > 0) {
      const paths = objects.map((o: { name: string }) => `${userId}/${o.name}`);
      await adminClient.storage.from("media").remove(paths);
    }

    // -------------------------------------------------------
    // 5. Profiles (FK CASCADE from auth.users, but explicit for safety)
    // -------------------------------------------------------
    await adminClient.from("profiles").delete().eq("id", userId);

    // -------------------------------------------------------
    // 6. Delete auth user last (irreversible)
    // -------------------------------------------------------
    const { error: deleteErr } = await adminClient.auth.admin.deleteUser(userId);
    if (deleteErr) {
      return json({ error: "Failed to delete auth user", detail: deleteErr.message }, { status: 500 });
    }

    return json({ success: true });
  } catch (err) {
    return json({ error: err?.message ?? "Internal error" }, { status: 500 });
  }
});
