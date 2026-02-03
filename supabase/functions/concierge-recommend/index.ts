import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type MediaType = "ANIME" | "MANGA";

function json(res: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(res), {
    ...init,
    headers: { "Content-Type": "application/json", ...(init.headers ?? {}) },
  });
}

function uniq<T>(arr: T[]) {
  return Array.from(new Set(arr));
}

function inferMediaType(text: string, scope: string): MediaType | "BOTH" {
  const s = (scope || "").toLowerCase();
  if (s === "anime") return "ANIME";
  if (s === "manga") return "MANGA";
  const t = text.toLowerCase();
  if (/\b(manga|manhwa|manhua)\b/.test(t)) return "MANGA";
  if (/\b(anime)\b/.test(t)) return "ANIME";
  return "BOTH";
}

function inferSeedQuery(text: string): string | null {
  const t = text.trim();
  const m1 = t.match(/\b(?:like|similar to)\s+(.+?)(?:[.?!]|$)/i);
  if (m1?.[1]) return m1[1].trim().replace(/^["']|["']$/g, "");
  return null;
}

function inferCategories(text: string): string[] {
  const t = text.toLowerCase();
  const out: string[] = [];

  if (/\b(fun|funny|comedy|laugh)\b/.test(t)) out.push("Theme-Comedy");
  if (/\b(sad|cry|tears?|heartbreak)\b/.test(t)) out.push("Theme-Drama");
  if (/\b(cozy|comfort|chill|relax)\b/.test(t)) out.push("Theme-Slice of Life");
  if (/\b(romance|love)\b/.test(t)) out.push("Theme-Romance");
  if (/\b(action)\b/.test(t)) out.push("Theme-Action");
  if (/\b(fantasy)\b/.test(t)) out.push("Theme-Fantasy");
  if (/\b(sci[- ]?fi|scifi)\b/.test(t)) out.push("Theme-Sci-Fi");
  if (/\b(sports?)\b/.test(t)) out.push("Theme-Game-Sport");
  if (/\b(music)\b/.test(t)) out.push("Theme-Arts-Music");
  // Explicit modes that should be discoverable.
  if (/\b(isekai)\b/.test(t)) out.push("Theme-Fantasy");
  if (/\b(reincarnat)/.test(t)) out.push("Theme-Other");

  return uniq(out);
}

function inferFocusTagIds(text: string): number[] {
  const t = text.toLowerCase();
  const ids: number[] = [];
  if (/\b(isekai)\b/.test(t)) ids.push(350);
  if (/\b(reincarnat|reborn|tensei)\b/.test(t)) ids.push(1023);
  if (/\b(another world|in another world|isekai)\b/.test(t)) ids.push(350);
  if (/\b(slime)\b/.test(t)) ids.push(350, 1023);
  if (/\b(harem)\b/.test(t)) ids.push(358, 9154, 18064);
  return uniq(ids);
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

    const body = await req.json().catch(() => ({}));
    const text: string = String(body?.text ?? "");
    const scope: string = String(body?.scope ?? "both");
    const limit = Math.max(3, Math.min(20, Number(body?.limit ?? 8)));

    const categories = inferCategories(text);
    const focusTagIds = inferFocusTagIds(text);
    const allowGimmicks =
      focusTagIds.length > 0 || /\b(slime)\b/.test(text.toLowerCase());

    const mediaType = inferMediaType(text, scope);
    const results: any[] = [];

    const seedQuery = inferSeedQuery(text);

    const run = async (mt: MediaType) => {
      let rows: any[] = [];

      // If the user gives an explicit seed ("like Vagabond"), prefer similarity over generic premium.
      if (seedQuery) {
        const seedType = mt;
        const { data: seeds, error: seedErr } = await client.rpc("search_titles", {
          p_query: seedQuery,
          p_media_type: seedType,
          p_limit: 6,
        });
        if (!seedErr && Array.isArray(seeds) && seeds.length > 0) {
          const top = seeds[0];
          if ((top?.score ?? 0) >= 0.35) {
            const seedIds = [Number(top.media_id)];
            const { data: sim, error: simErr } = await client.rpc("recommend_ids_similar_to_seeds", {
              p_media_type: mt,
              p_seed_ids: seedIds,
              p_limit: limit,
              p_allow_gimmicks: allowGimmicks,
            });
            if (!simErr && Array.isArray(sim)) {
              rows = sim.map((r: any) => ({
                media_id: r.media_id,
                match_count: r.overlap_count ?? r.match_count ?? 0,
                score: r.score ?? null,
              }));
            }
          }
        }
      }

      if (rows.length === 0) {
        const { data: ids, error } = await client.rpc("recommend_ids_premium", {
          p_media_type: mt,
          p_categories: categories.length ? categories : null,
          p_limit: limit,
          p_allow_gimmicks: allowGimmicks,
          p_focus_tag_ids: focusTagIds.length ? focusTagIds : null,
        });
        if (error) throw error;
        rows = Array.isArray(ids) ? ids : [];
      }

      const idList = rows.map((r) => r.media_id);
      if (idList.length === 0) return;

      const table = mt === "ANIME" ? "anime" : "manga";
      const { data: mediaRows, error: mediaErr } = await client
        .from(table)
        .select("id,title_english,title_romaji,title_native,cover_image_medium,average_score,start_date_year,format,status,site_url,is_adult,genres")
        .in("id", idList);
      if (mediaErr) throw mediaErr;
      const byId = new Map<number, any>((mediaRows ?? []).map((r: any) => [r.id, r]));

      for (const r of rows) {
        const m = byId.get(r.media_id);
        if (!m) continue;
        results.push({
          mediaType: mt,
          mediaId: r.media_id,
          matchCount: r.match_count ?? 0,
          score: r.score ?? null,
          title: m.title_english ?? m.title_romaji ?? m.title_native ?? "Unknown",
          coverImageMedium: m.cover_image_medium ?? null,
          averageScore: m.average_score ?? null,
          year: m.start_date_year ?? null,
          format: m.format ?? null,
          status: m.status ?? null,
          siteUrl: m.site_url ?? null,
        });
      }
    };

    if (mediaType === "BOTH") {
      await run("ANIME");
      await run("MANGA");
    } else {
      await run(mediaType);
    }

    try {
      await client.rpc("log_concierge_run", {
        p_kind: "recommend",
        p_status: "success",
        p_input_chars: text.length,
        p_items_count: results.length,
      });
    } catch {
      // best-effort
    }

    const message =
      categories.length === 0
        ? "Premium picks (new to you). Tell me a vibe like “funny”, “sad”, “cozy”, or a genre to sharpen it."
        : null;
    return json({ success: true, categories, items: results, message });
  } catch (e) {
    const err = e as Error;
    return json({ error: "Internal error", message: err?.message ?? String(e) }, { status: 500 });
  }
});
