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

function normalizeAliasKey(raw: string): string {
  let s = String(raw ?? "").toLowerCase();
  s = s.replace(/\u00a0/g, " ");
  // strip filler + verbs/status
  s = s.replace(/\b(um+|uh+|erm+|eh+|like|also|äh+|ae+h+|so|halt)\b/giu, " ");
  s = s.replace(/\b(i\s+have|i'?m|im|i\s+am|i)\b/giu, " ");
  s = s.replace(/\b(ich\s+habe|ich\s+hab|ich|bin)\b/giu, " ");
  s = s.replace(
    /\b(watched|watching|finished|completed|dropped|paused|planning|read|reading|caught up|up to date|seen|saw)\b/giu,
    " ",
  );
  s = s.replace(
    /\b(geschaut|gesehen|gelesen|fertig|abgeschlossen|beendet|abgebrochen|pausiert|geplant|aktuell|komplett|vollständig|vollstaendig)\b/giu,
    " ",
  );
  // strip progress markers
  s = s.replace(/\b(?:season|staffel|episode|ep|folge|chapter|ch|kapitel|volume|vol|band)\b/giu, " ");
  s = s.replace(/\b\d{1,2}\s*x\s*\d{1,4}\b/giu, " ");
  s = s.replace(/\bs\d{1,2}\s*e\d{1,4}\b/giu, " ");
  // keep only letters/numbers/spaces (unicode)
  s = s.replace(/[^\p{L}\p{N}\s]+/gu, " ");
  s = s.replace(/\s+/g, " ").trim();
  return s.slice(0, 160);
}

async function bumpTitleAlias(client: any, args: {
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

async function fetchLatestEpisodeNumber(client: any, animeId: number): Promise<number | null> {
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

    const ip = clientIp(req);

    // Parallelize auth, rate-limit check, and body parsing — they are independent.
    const [authResult, rlResult, body] = await Promise.all([
      client.auth.getUser(),
      client.rpc("check_concierge_rate_limit", {
        p_kind: "apply",
        p_ip: ip,
        p_window_seconds: null,
        p_max_user: null,
        p_max_ip: null,
      }),
      req.json().catch(() => ({})),
    ]);

    const { data: userData, error: userErr } = authResult;
    if (userErr || !userData?.user) return json({ error: "Unauthorized" }, { status: 401 });
    const userId = userData.user.id;

    const rl = rlResult.data;
    if (rl && rl.allowed === false) {
      return json(
        { error: "Rate limited", retry_after_s: rl.retry_after_s ?? 30 },
        { status: 429, headers: { "Retry-After": String(rl.retry_after_s ?? 30) } },
      );
    }
    const items: any[] = Array.isArray(body?.items) ? body.items : [];
    if (!Array.isArray(body?.items) || items.length > 100) {
      return json({ error: "Too many items (max 100)" }, { status: 400 });
    }
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
    const skipped: any[] = [];
    const conflicts: any[] = [];
    const errors: any[] = [];

    // Process all items in parallel — each targets a different media_id so they're independent.
    const results = await Promise.all(items.map(async (it) => {
      const mediaType: MediaType | null = it?.mediaType === "ANIME" || it?.mediaType === "MANGA" ? it.mediaType : null;
      const mediaId: number | null = clampInt(it?.mediaId, 1, 2_000_000_000);
      let status: ListStatus | null =
        typeof it?.status === "string" ? (it.status.toUpperCase() as ListStatus) : null;

      if (!mediaType || !mediaId || !status) {
        return { ok: false as const, kind: "error" as const, item: it, error: "Invalid mediaType/mediaId/status" };
      }

      // Reconciliation action: 'add' (default for backwards compat), 'update', or 'skip'
      const importAction: "add" | "update" | "skip" =
        it?.action === "update" ? "update" : it?.action === "skip" ? "skip" : "add";

      try {
        // --- Handle skip action ---
        if (importAction === "skip") {
          await client.from("import_session_items").insert({
            session_id: sessionId,
            raw: typeof it?.raw === "string" ? it.raw.slice(0, 500) : `${mediaType}:${mediaId}`,
            parsed: it?.parsed ?? {},
            candidates: Array.isArray(it?.candidates) ? it.candidates.slice(0, 12) : [],
            chosen: { mediaType, mediaId },
            action: null,
            confidence: typeof it?.confidence === "number" ? it.confidence : 0,
            state: "skipped",
            import_action: "skip",
          });
          return { ok: true as const, kind: "skip" as const, mediaType, mediaId, status };
        }

        if (mediaType === "ANIME") {
          const explicitComplete = it?.lastEpisode === true || it?.completed === true;
          const caughtUp = it?.caughtUp === true;
          if (explicitComplete && status !== "COMPLETED") status = "COMPLETED";

          let progress = clampInt(it?.progressEpisodes, 0, 100_000) ?? clampInt(it?.progress, 0, 100_000);

          // If the user says "caught up" or "last episode" without a number, compute best-effort progress.
          if (progress == null && (caughtUp || status === "COMPLETED")) {
            const { data: animeRow } = await client
              .from("anime")
              .select("episodes,next_episode_number,status")
              .eq("id", mediaId)
              .maybeSingle();

            const nextEp = clampInt(animeRow?.next_episode_number, 0, 100_000);
            const totalKnown = clampInt(animeRow?.episodes, 0, 100_000);

            if (status === "COMPLETED") {
              progress = totalKnown ?? await fetchLatestEpisodeNumber(client, mediaId);
            } else if (caughtUp) {
              progress = nextEp != null && nextEp > 0 ? Math.max(0, nextEp - 1) : (await fetchLatestEpisodeNumber(client, mediaId));
            }
          }

          // Re-check current state (TOCTOU protection for updates)
          const before = await client
            .from("anime_user_lists")
            .select("list_type,progress,rating,notes")
            .eq("user_id", userId)
            .eq("anime_id", mediaId)
            .maybeSingle();
          if (before.error) throw before.error;

          // TOCTOU check for updates: verify current state matches what client expected
          if (importAction === "update" && it?.expectedExisting) {
            const exp = it.expectedExisting;
            const cur = before.data;
            if (!cur) {
              // Entry was deleted between parse and apply — conflict
              return { ok: false as const, kind: "conflict" as const, mediaType, mediaId, error: "Entry no longer exists (deleted since parse)" };
            }
            if (
              (exp.status && cur.list_type !== exp.status) ||
              (exp.progress_episodes != null && cur.progress !== exp.progress_episodes)
            ) {
              await client.from("import_session_items").insert({
                session_id: sessionId,
                raw: typeof it?.raw === "string" ? it.raw.slice(0, 500) : `${mediaType}:${mediaId}`,
                parsed: it?.parsed ?? {},
                candidates: Array.isArray(it?.candidates) ? it.candidates.slice(0, 12) : [],
                chosen: { mediaType, mediaId },
                action: { table: "anime_user_lists", key: { user_id: userId, anime_id: mediaId }, before: cur, after: null },
                confidence: typeof it?.confidence === "number" ? it.confidence : 0,
                state: "error",
                import_action: "update",
                error: "TOCTOU conflict: current state changed since parse",
              });
              return { ok: false as const, kind: "conflict" as const, mediaType, mediaId, error: "State changed since parse — review and retry" };
            }
          }

          const seasonNumber = clampInt(it?.seasonNumber, 1, 100);
          const episodeInSeason = clampInt(it?.episodeInSeason, 0, 100_000);
          const seasonNote = seasonNumber && episodeInSeason ? `S${seasonNumber}E${episodeInSeason}` : null;
          const rawNotes = typeof it?.notes === "string" ? it.notes.slice(0, 2000) : null;
          const notes = seasonNote && !rawNotes ? seasonNote : rawNotes;

          const payload = {
            user_id: userId,
            anime_id: mediaId,
            list_type: status,
            progress: progress ?? null,
            rating: clampInt(it?.rating, 0, 10),
            notes,
          };
          const { error } = await client.from("anime_user_lists").upsert(payload as any, {
            onConflict: "user_id,anime_id",
          });
          if (error) throw error;

          try {
            const aliasNorm = normalizeAliasKey(it?.raw ?? it?.normalized ?? "");
            await bumpTitleAlias(client, {
              userId,
              aliasNorm,
              mediaType: "ANIME",
              mediaId,
              titleRaw: typeof it?.titleRaw === "string" ? it.titleRaw : null,
            });
          } catch {
            // best-effort
          }

          // Store previous_values for undo support on updates
          const previousValues = importAction === "update" && before.data ? before.data : null;

          await client.from("import_session_items").insert({
            session_id: sessionId,
            raw: typeof it?.raw === "string" ? it.raw.slice(0, 500) : `${mediaType}:${mediaId}`,
            parsed: {
              status,
              progressEpisodes: progress ?? null,
              seasonNumber: seasonNumber ?? null,
              episodeInSeason: episodeInSeason ?? null,
              caughtUp: caughtUp || null,
              lastEpisode: explicitComplete || null,
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
            import_action: importAction,
            previous_values: previousValues,
          });
        } else {
          const explicitComplete = it?.completed === true;
          const caughtUp = it?.caughtUp === true;
          if (explicitComplete && status !== "COMPLETED") status = "COMPLETED";

          let progress = clampInt(it?.progressChapters, 0, 500_000) ?? clampInt(it?.progress, 0, 500_000);
          if (progress == null && (caughtUp || status === "COMPLETED")) {
            const { data: mangaRow } = await client
              .from("manga")
              .select("chapters,status")
              .eq("id", mediaId)
              .maybeSingle();
            const totalKnown = clampInt(mangaRow?.chapters, 0, 500_000);
            if (totalKnown != null) progress = totalKnown;
          }

          // Re-check current state (TOCTOU protection for updates)
          const before = await client
            .from("manga_user_lists")
            .select("list_type,progress,rating,notes")
            .eq("user_id", userId)
            .eq("manga_id", mediaId)
            .maybeSingle();
          if (before.error) throw before.error;

          // TOCTOU check for updates: verify current state matches what client expected
          if (importAction === "update" && it?.expectedExisting) {
            const exp = it.expectedExisting;
            const cur = before.data;
            if (!cur) {
              return { ok: false as const, kind: "conflict" as const, mediaType, mediaId, error: "Entry no longer exists (deleted since parse)" };
            }
            if (
              (exp.status && cur.list_type !== exp.status) ||
              (exp.progress_chapters != null && cur.progress !== exp.progress_chapters)
            ) {
              await client.from("import_session_items").insert({
                session_id: sessionId,
                raw: typeof it?.raw === "string" ? it.raw.slice(0, 500) : `${mediaType}:${mediaId}`,
                parsed: it?.parsed ?? {},
                candidates: Array.isArray(it?.candidates) ? it.candidates.slice(0, 12) : [],
                chosen: { mediaType, mediaId },
                action: { table: "manga_user_lists", key: { user_id: userId, manga_id: mediaId }, before: cur, after: null },
                confidence: typeof it?.confidence === "number" ? it.confidence : 0,
                state: "error",
                import_action: "update",
                error: "TOCTOU conflict: current state changed since parse",
              });
              return { ok: false as const, kind: "conflict" as const, mediaType, mediaId, error: "State changed since parse — review and retry" };
            }
          }

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

          try {
            const aliasNorm = normalizeAliasKey(it?.raw ?? it?.normalized ?? "");
            await bumpTitleAlias(client, {
              userId,
              aliasNorm,
              mediaType: "MANGA",
              mediaId,
              titleRaw: typeof it?.titleRaw === "string" ? it.titleRaw : null,
            });
          } catch {
            // best-effort
          }

          const previousValues = importAction === "update" && before.data ? before.data : null;

          await client.from("import_session_items").insert({
            session_id: sessionId,
            raw: typeof it?.raw === "string" ? it.raw.slice(0, 500) : `${mediaType}:${mediaId}`,
            parsed: {
              status,
              progressChapters: progress ?? null,
              caughtUp: caughtUp || null,
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
            import_action: importAction,
            previous_values: previousValues,
          });
        }

        return { ok: true as const, kind: importAction as "add" | "update", mediaType, mediaId, status };
      } catch (e) {
        await client.from("import_session_items").insert({
          session_id: sessionId,
          raw: typeof it?.raw === "string" ? it.raw.slice(0, 500) : `${mediaType ?? "UNKNOWN"}:${mediaId ?? "?"}`,
          parsed: it?.parsed ?? {},
          candidates: Array.isArray(it?.candidates) ? it.candidates.slice(0, 12) : [],
          chosen: mediaType && mediaId ? { mediaType, mediaId } : null,
          action: null,
          confidence: typeof it?.confidence === "number" ? it.confidence : 0,
          state: "error",
          import_action: importAction,
          error: ((e as Error).message ?? String(e)).slice(0, 500),
        });
        return { ok: false as const, kind: "error" as const, mediaType, mediaId, error: (e as Error).message ?? String(e) };
      }
    }));

    // Collect results preserving original order.
    for (const r of results) {
      if (r.ok && r.kind === "skip") {
        skipped.push({ mediaType: r.mediaType, mediaId: r.mediaId });
      } else if (r.ok) {
        applied.push({ mediaType: r.mediaType, mediaId: r.mediaId, status: r.status, action: r.kind });
      } else if (r.kind === "conflict") {
        conflicts.push({ mediaType: r.mediaType, mediaId: r.mediaId, error: r.error });
      } else if ("item" in r) {
        errors.push({ item: r.item, error: r.error });
      } else {
        errors.push({ mediaType: r.mediaType, mediaId: r.mediaId, error: r.error });
      }
    }

    await client.from("import_sessions").update({
      status: errors.length || conflicts.length ? "failed" : "applied",
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

    return json({ success: errors.length === 0 && conflicts.length === 0, sessionId, applied, skipped, conflicts, errors });
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
