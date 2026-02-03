import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type MediaType = "ANIME" | "MANGA";
type ListStatus = "WATCHING" | "READING" | "PLANNING" | "COMPLETED" | "DROPPED" | "PAUSED";

function json(res: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(res), {
    ...init,
    headers: { "Content-Type": "application/json", ...(init.headers ?? {}) },
  });
}

function clampInt(v: unknown, min: number, max: number) {
  const n = Math.floor(Number(v));
  if (!Number.isFinite(n)) return null;
  return Math.max(min, Math.min(max, n));
}

serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, { status: 405 });

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY");
    const supabaseService = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const supabaseKey = supabaseAnon ?? supabaseService;
    if (!supabaseUrl || !supabaseKey) {
      return json({ error: "Missing SUPABASE_URL or a Supabase API key env (SUPABASE_ANON_KEY or SUPABASE_SERVICE_ROLE_KEY)" }, { status: 500 });
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const client = createClient(supabaseUrl, supabaseKey, {
      global: { headers: authHeader ? { Authorization: authHeader } : {} },
    });

    const { data: userData, error: userErr } = await client.auth.getUser();
    if (userErr || !userData?.user) return json({ error: "Unauthorized" }, { status: 401 });
    const userId = userData.user.id;

    const body = await req.json().catch(() => ({}));
    const sessionId = typeof body?.sessionId === "string" ? body.sessionId : null;
    if (!sessionId) return json({ error: "Missing sessionId" }, { status: 400 });

  const session = await client
    .from("import_sessions")
    .select("id,user_id,status")
    .eq("id", sessionId)
    .maybeSingle();

  if (session.error) return json({ error: session.error.message }, { status: 500 });
  if (!session.data) return json({ error: "Not found" }, { status: 404 });
  if (session.data.user_id !== userId) return json({ error: "Forbidden" }, { status: 403 });

  const itemsRes = await client
    .from("import_session_items")
    .select("id,chosen,action,state")
    .eq("session_id", sessionId);
  if (itemsRes.error) return json({ error: itemsRes.error.message }, { status: 500 });

  const reverted: any[] = [];
  const errors: any[] = [];

  for (const row of itemsRes.data ?? []) {
    try {
      const chosen = row?.chosen ?? {};
      const mediaType: MediaType | null = chosen?.mediaType === "ANIME" || chosen?.mediaType === "MANGA" ? chosen.mediaType : null;
      const mediaId: number | null = clampInt(chosen?.mediaId, 1, 2_000_000_000);
      if (!mediaType || !mediaId) continue;

      const action = row?.action ?? {};
      const before = action?.before ?? null;

      if (mediaType === "ANIME") {
        if (!before) {
          const del = await client
            .from("anime_user_lists")
            .delete()
            .eq("user_id", userId)
            .eq("anime_id", mediaId);
          if (del.error) throw del.error;
        } else {
          const payload = {
            user_id: userId,
            anime_id: mediaId,
            list_type: (before?.list_type as ListStatus) ?? "PLANNING",
            progress: before?.progress ?? null,
            rating: before?.rating ?? null,
            notes: before?.notes ?? null,
          };
          const up = await client
            .from("anime_user_lists")
            .upsert(payload as any, { onConflict: "user_id,anime_id" });
          if (up.error) throw up.error;
        }
      } else {
        if (!before) {
          const del = await client
            .from("manga_user_lists")
            .delete()
            .eq("user_id", userId)
            .eq("manga_id", mediaId);
          if (del.error) throw del.error;
        } else {
          const payload = {
            user_id: userId,
            manga_id: mediaId,
            list_type: (before?.list_type as ListStatus) ?? "PLANNING",
            progress: before?.progress ?? null,
            rating: before?.rating ?? null,
            notes: before?.notes ?? null,
          };
          const up = await client
            .from("manga_user_lists")
            .upsert(payload as any, { onConflict: "user_id,manga_id" });
          if (up.error) throw up.error;
        }
      }

      reverted.push({ mediaType, mediaId });
    } catch (e) {
      errors.push({ id: row?.id, error: (e as Error).message ?? String(e) });
    }
  }

  await client.from("import_sessions").update({ status: "cancelled" }).eq("id", sessionId);

  try {
    await client.rpc("log_concierge_run", {
      p_kind: "undo",
      p_status: errors.length ? "error" : "success",
      p_items_count: (itemsRes.data ?? []).length,
      p_error: errors.length ? JSON.stringify(errors).slice(0, 1000) : null,
    });
  } catch {
    // Best-effort metrics only.
  }

    return json({ success: errors.length === 0, sessionId, reverted, errors });
  } catch (e) {
    const err = e as Error;
    return json(
      {
        error: "Internal error",
        message: err?.message ?? String(e),
      },
      { status: 500 },
    );
  }
});
