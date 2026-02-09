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

    const ip = clientIp(req);
    const { data: rl } = await client.rpc("check_concierge_rate_limit", {
      p_kind: "undo",
      p_ip: ip,
      p_window_seconds: null,
      p_max_user: null,
      p_max_ip: null,
    });
    if (rl && rl.allowed === false) {
      return json(
        { error: "Rate limited", retry_after_s: rl.retry_after_s ?? 30 },
        { status: 429, headers: { "Retry-After": String(rl.retry_after_s ?? 30) } },
      );
    }

    const body = await req.json().catch(() => ({}));
    const sessionId = typeof body?.sessionId === "string" ? body.sessionId : null;
    if (!sessionId) return json({ error: "Missing sessionId" }, { status: 400 });

  // H4: Only allow undo of the most recent session for this user
  const latestSession = await client
    .from("import_sessions")
    .select("id")
    .eq("user_id", userId)
    .eq("status", "applied")
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (latestSession.error) return json({ error: latestSession.error.message }, { status: 500 });
  if (!latestSession.data) return json({ error: "No applied session to undo" }, { status: 404 });
  if (latestSession.data.id !== sessionId) {
    return json({ error: "Can only undo the most recent import session" }, { status: 409 });
  }

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
    .select("id,chosen,action,state,import_action,previous_values")
    .eq("session_id", sessionId);
  if (itemsRes.error) return json({ error: itemsRes.error.message }, { status: 500 });

  const reverted: any[] = [];
  const warnings: any[] = [];
  const errors: any[] = [];

  for (const row of itemsRes.data ?? []) {
    try {
      const chosen = row?.chosen ?? {};
      const mediaType: MediaType | null = chosen?.mediaType === "ANIME" || chosen?.mediaType === "MANGA" ? chosen.mediaType : null;
      const mediaId: number | null = clampInt(chosen?.mediaId, 1, 2_000_000_000);
      if (!mediaType || !mediaId) continue;

      const itemAction = row?.import_action ?? "add";
      const actionData = row?.action ?? {};
      const afterData = actionData?.after ?? null;
      const previousValues = row?.previous_values ?? null;

      // Skip items that were skipped during import — nothing to undo
      if (itemAction === "skip") continue;

      if (mediaType === "ANIME") {
        // Verify current state matches what we set (detect manual edits / overlapping imports)
        const current = await client
          .from("anime_user_lists")
          .select("list_type,progress,rating,notes")
          .eq("user_id", userId)
          .eq("anime_id", mediaId)
          .maybeSingle();

        if (current.error) throw current.error;

        // If the entry no longer exists or was modified since our import, warn instead of blindly reverting
        if (afterData && current.data) {
          const cur = current.data;
          if (cur.list_type !== afterData.list_type || cur.progress !== afterData.progress) {
            warnings.push({ mediaType, mediaId, reason: "Entry was modified since import — skipping undo to avoid data loss" });
            continue;
          }
        }

        if (itemAction === "update" && previousValues) {
          // Restore previous values for updates
          const payload = {
            user_id: userId,
            anime_id: mediaId,
            list_type: (previousValues.list_type as ListStatus) ?? "PLANNING",
            progress: previousValues.progress ?? null,
            rating: previousValues.rating ?? null,
            notes: previousValues.notes ?? null,
          };
          const up = await client
            .from("anime_user_lists")
            .upsert(payload as any, { onConflict: "user_id,anime_id" });
          if (up.error) throw up.error;
          reverted.push({ mediaType, mediaId, undoType: "restored" });
        } else {
          // For adds (or legacy items without import_action): delete the entry
          const before = actionData?.before ?? null;
          if (!before) {
            const del = await client
              .from("anime_user_lists")
              .delete()
              .eq("user_id", userId)
              .eq("anime_id", mediaId);
            if (del.error) throw del.error;
            reverted.push({ mediaType, mediaId, undoType: "deleted" });
          } else {
            const payload = {
              user_id: userId,
              anime_id: mediaId,
              list_type: (before.list_type as ListStatus) ?? "PLANNING",
              progress: before.progress ?? null,
              rating: before.rating ?? null,
              notes: before.notes ?? null,
            };
            const up = await client
              .from("anime_user_lists")
              .upsert(payload as any, { onConflict: "user_id,anime_id" });
            if (up.error) throw up.error;
            reverted.push({ mediaType, mediaId, undoType: "restored" });
          }
        }
      } else {
        // MANGA
        const current = await client
          .from("manga_user_lists")
          .select("list_type,progress,rating,notes")
          .eq("user_id", userId)
          .eq("manga_id", mediaId)
          .maybeSingle();

        if (current.error) throw current.error;

        if (afterData && current.data) {
          const cur = current.data;
          if (cur.list_type !== afterData.list_type || cur.progress !== afterData.progress) {
            warnings.push({ mediaType, mediaId, reason: "Entry was modified since import — skipping undo to avoid data loss" });
            continue;
          }
        }

        if (itemAction === "update" && previousValues) {
          const payload = {
            user_id: userId,
            manga_id: mediaId,
            list_type: (previousValues.list_type as ListStatus) ?? "PLANNING",
            progress: previousValues.progress ?? null,
            rating: previousValues.rating ?? null,
            notes: previousValues.notes ?? null,
          };
          const up = await client
            .from("manga_user_lists")
            .upsert(payload as any, { onConflict: "user_id,manga_id" });
          if (up.error) throw up.error;
          reverted.push({ mediaType, mediaId, undoType: "restored" });
        } else {
          const before = actionData?.before ?? null;
          if (!before) {
            const del = await client
              .from("manga_user_lists")
              .delete()
              .eq("user_id", userId)
              .eq("manga_id", mediaId);
            if (del.error) throw del.error;
            reverted.push({ mediaType, mediaId, undoType: "deleted" });
          } else {
            const payload = {
              user_id: userId,
              manga_id: mediaId,
              list_type: (before.list_type as ListStatus) ?? "PLANNING",
              progress: before.progress ?? null,
              rating: before.rating ?? null,
              notes: before.notes ?? null,
            };
            const up = await client
              .from("manga_user_lists")
              .upsert(payload as any, { onConflict: "user_id,manga_id" });
            if (up.error) throw up.error;
            reverted.push({ mediaType, mediaId, undoType: "restored" });
          }
        }
      }
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

    return json({ success: errors.length === 0, sessionId, reverted, warnings, errors });
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
