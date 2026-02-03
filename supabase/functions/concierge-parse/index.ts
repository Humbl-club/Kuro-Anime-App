import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type MediaType = "ANIME" | "MANGA";
type ListStatus = "WATCHING" | "READING" | "PLANNING" | "COMPLETED" | "DROPPED" | "PAUSED";

type ParsedItem = {
  raw: string;
  normalized: string;
  mediaTypeHint?: MediaType;
  status?: ListStatus;
  progressEpisodes?: number;
  progressChapters?: number;
  progressVolumes?: number;
  completed?: boolean;
};

function json(res: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(res), {
    ...init,
    headers: { "Content-Type": "application/json", ...(init.headers ?? {}) },
  });
}

function normalizeLine(s: string) {
  return s
    .trim()
    .replace(/\u00A0/g, " ")
    .replace(/\s+/g, " ");
}

function splitItems(text: string): string[] {
  const normalized = text.replace(/\r\n/g, "\n").trim();
  if (!normalized) return [];

  const lines = normalized
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean)
    .flatMap((l) => {
      // allow comma-separated within a line if it's not obviously a sentence
      if (l.includes(",") && l.length < 160) return l.split(",").map((x) => x.trim()).filter(Boolean);
      return [l];
    });

  return lines
    .map((l) => l.replace(/^[\-\*\u2022]+\s*/, "").trim())
    .filter(Boolean);
}

function parseStatus(raw: string): { status?: ListStatus; completed?: boolean } {
  const s = raw.toLowerCase();
  if (/\b(completed|finished|done)\b/.test(s)) return { status: "COMPLETED", completed: true };
  if (/\b(dropped)\b/.test(s)) return { status: "DROPPED" };
  if (/\b(paused|on hold|on-hold|hiatus)\b/.test(s)) return { status: "PAUSED" };
  if (/\b(planning|plan to watch|plan to read|ptw|ptr)\b/.test(s)) return { status: "PLANNING" };
  if (/\b(reading)\b/.test(s)) return { status: "READING" };
  if (/\b(watching)\b/.test(s)) return { status: "WATCHING" };
  return {};
}

function parseProgress(raw: string): Pick<ParsedItem, "progressEpisodes" | "progressChapters" | "progressVolumes"> {
  const s = raw.toLowerCase();
  const out: any = {};

  const ep = s.match(/\b(?:ep|episode)\s*(\d{1,4})\b/);
  if (ep) out.progressEpisodes = parseInt(ep[1], 10);

  const ch = s.match(/\b(?:ch|chapter)\s*(\d{1,5})\b/);
  if (ch) out.progressChapters = parseInt(ch[1], 10);

  const vol = s.match(/\b(?:vol|volume)\s*(\d{1,4})\b/);
  if (vol) out.progressVolumes = parseInt(vol[1], 10);

  return out;
}

function mediaTypeHint(raw: string): MediaType | undefined {
  const s = raw.toLowerCase();
  if (/\b(manga|manhwa|manhua|volume|vol\.|chapter|ch\.)\b/.test(s)) return "MANGA";
  if (/\b(anime|episode|ep\.)\b/.test(s)) return "ANIME";
  return undefined;
}

function stripMeta(raw: string): string {
  // remove parenthetical notes and common suffixes without nuking the title
  let s = raw;
  s = s.replace(/\((?:[^()]+)\)/g, " ");
  s = s.replace(/\b(completed|finished|done|dropped|paused|planning|watching|reading)\b/gi, " ");
  s = s.replace(/\b(?:ep|episode|ch|chapter|vol|volume)\s*\d{1,5}\b/gi, " ");
  s = s.replace(/\s+/g, " ").trim();
  return s;
}

serve(async (req) => {
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

  const body = await req.json().catch(() => ({}));
  const text: string = String(body?.text ?? "");
  const scope: "anime" | "manga" | "both" = body?.scope ?? "both";
  const limitPerItem = Math.max(3, Math.min(15, Number(body?.limitPerItem ?? 10)));

  const itemsRaw = splitItems(text);
  if (itemsRaw.length === 0) {
    return json({ success: true, items: [] });
  }

  // Verify user (required for launch). If missing, we still return candidates but mark unauthenticated.
  const { data: userData } = await client.auth.getUser();
  const userId = userData?.user?.id ?? null;

  const parsed: ParsedItem[] = itemsRaw.map((raw) => {
    const cleaned = normalizeLine(raw);
    const status = parseStatus(cleaned);
    const progress = parseProgress(cleaned);
    const hint = mediaTypeHint(cleaned);
    return {
      raw: cleaned,
      normalized: stripMeta(cleaned),
      mediaTypeHint: hint,
      status: status.status,
      completed: status.completed,
      ...progress,
    };
  });

  const outItems: any[] = [];

  for (const item of parsed) {
    const mediaType =
      scope === "anime" ? "ANIME" : scope === "manga" ? "MANGA" : item.mediaTypeHint ?? null;

    // Search against title_search via RPC (fast, indexed).
    const { data: candidates, error } = await client.rpc("search_titles", {
      p_query: item.normalized,
      p_media_type: mediaType,
      p_limit: limitPerItem,
    });

    outItems.push({
      raw: item.raw,
      normalized: item.normalized,
      parsed: {
        mediaTypeHint: item.mediaTypeHint ?? null,
        status: item.status ?? null,
        progressEpisodes: item.progressEpisodes ?? null,
        progressChapters: item.progressChapters ?? null,
        progressVolumes: item.progressVolumes ?? null,
        completed: item.completed ?? null,
      },
      candidates: error ? [] : (candidates ?? []),
      candidateError: error?.message ?? null,
    });
  }

  // Lightweight run logging (best-effort; table is RLS-deny by default for users).
  if (userId) {
    try {
      await client.rpc("log_concierge_run", {
        p_kind: "parse",
        p_status: "success",
        p_input_chars: text.length,
        p_items_count: outItems.length,
      });
    } catch {
      // Best-effort metrics only.
    }
  }

  return json({ success: true, userId, items: outItems });
});
