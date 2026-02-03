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
    const items: any[] = Array.isArray(body?.items) ? body.items : [];
    if (items.length === 0) return json({ success: true, applied: 0, sessionId: null, errors: [] });

    // Create an import session so we can support undo.
    const { data: sessionRow, error: sessionErr } = await client
      .from("import_sessions")
      .insert({ user_id: userId, status: "draft", source: "chat" })
      .select("id")
      .single();
    if (sessionErr || !sessionRow?.id) {
      return json({ error: `Failed to create import session: ${sessionErr?.message ?? "unknown"}` }, { status: 500 });
    }
    const sessionId: string = sessionRow.id;

    const applied: any[] = [];
    const errors: any[] = [];

    for (const it of items) {
      const mediaType: MediaType | null = it?.mediaType === "ANIME" || it?.mediaType === "MANGA" ? it.mediaType : null;
      const mediaId: number | null = clampInt(it?.mediaId, 1, 2_000_000_000);
      const status: ListStatus | null =
        typeof it?.status === "string" ? (it.status.toUpperCase() as ListStatus) : null;

      if (!mediaType || !mediaId || !status) {
        errors.push({ item: it, error: "Invalid mediaType/mediaId/status" });
        continue;
      }

      try {
        if (mediaType === "ANIME") {
          const progress = clampInt(it?.progressEpisodes, 0, 100_000) ?? clampInt(it?.progress, 0, 100_000);
          const before = await client
            .from("anime_user_lists")
            .select("list_type,progress,rating,notes")
            .eq("user_id", userId)
            .eq("anime_id", mediaId)
            .maybeSingle();
          if (before.error) throw before.error;
          const payload = {
            user_id: userId,
            anime_id: mediaId,
            list_type: status,
            progress: progress ?? null,
            rating: clampInt(it?.rating, 0, 10),
            notes: typeof it?.notes === "string" ? it.notes.slice(0, 2000) : null,
          };
          const { error } = await client.from("anime_user_lists").upsert(payload as any, {
            onConflict: "user_id,anime_id",
          });
          if (error) throw error;

          await client.from("import_session_items").insert({
            session_id: sessionId,
            raw: typeof it?.raw === "string" ? it.raw.slice(0, 500) : `${mediaType}:${mediaId}`,
            parsed: {
              status,
              progressEpisodes: progress ?? null,
            },
            candidates: Array.isArray(it?.candidates) ? it.candidates.slice(0, 12) : [],
            chosen: { mediaType, mediaId },
            action: {
              table: "anime_user_lists",
              key: { user_id: userId, anime_id: mediaId },
              before: before.data ?? null,
              after: payload,
            },
            confidence: typeof it?.confidence === "number" ? it.confidence : 0,
            state: "applied",
          });
        } else {
          const progress = clampInt(it?.progressChapters, 0, 500_000) ?? clampInt(it?.progress, 0, 500_000);
          const before = await client
            .from("manga_user_lists")
            .select("list_type,progress,rating,notes")
            .eq("user_id", userId)
            .eq("manga_id", mediaId)
            .maybeSingle();
          if (before.error) throw before.error;
          const payload = {
            user_id: userId,
            manga_id: mediaId,
            list_type: status,
            progress: progress ?? null,
            rating: clampInt(it?.rating, 0, 10),
            notes: typeof it?.notes === "string" ? it.notes.slice(0, 2000) : null,
          };
          const { error } = await client.from("manga_user_lists").upsert(payload as any, {
            onConflict: "user_id,manga_id",
          });
          if (error) throw error;

          await client.from("import_session_items").insert({
            session_id: sessionId,
            raw: typeof it?.raw === "string" ? it.raw.slice(0, 500) : `${mediaType}:${mediaId}`,
            parsed: {
              status,
              progressChapters: progress ?? null,
            },
            candidates: Array.isArray(it?.candidates) ? it.candidates.slice(0, 12) : [],
            chosen: { mediaType, mediaId },
            action: {
              table: "manga_user_lists",
              key: { user_id: userId, manga_id: mediaId },
              before: before.data ?? null,
              after: payload,
            },
            confidence: typeof it?.confidence === "number" ? it.confidence : 0,
            state: "applied",
          });
        }

        applied.push({ mediaType, mediaId, status });
      } catch (e) {
        errors.push({ mediaType, mediaId, error: (e as Error).message ?? String(e) });
        await client.from("import_session_items").insert({
          session_id: sessionId,
          raw: typeof it?.raw === "string" ? it.raw.slice(0, 500) : `${mediaType ?? "UNKNOWN"}:${mediaId ?? "?"}`,
          parsed: it?.parsed ?? {},
          candidates: Array.isArray(it?.candidates) ? it.candidates.slice(0, 12) : [],
          chosen: mediaType && mediaId ? { mediaType, mediaId } : null,
          action: null,
          confidence: typeof it?.confidence === "number" ? it.confidence : 0,
          state: "error",
          error: ((e as Error).message ?? String(e)).slice(0, 500),
        });
      }
    }

    await client.from("import_sessions").update({
      status: errors.length ? "failed" : "applied",
    }).eq("id", sessionId);

    try {
      await client.rpc("log_concierge_run", {
        p_kind: "apply",
        p_status: errors.length ? "error" : "success",
        p_items_count: items.length,
        p_error: errors.length ? JSON.stringify(errors).slice(0, 1000) : null,
      });
    } catch {
      // Best-effort metrics only.
    }

    return json({ success: errors.length === 0, sessionId, applied, errors });
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
