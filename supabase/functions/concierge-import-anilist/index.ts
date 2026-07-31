import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Import a user's AniList list into Kuro by fetching public AniList list entries and
// returning a deterministic text payload that the existing concierge-parse pipeline
// can reconcile (no clipboard required).

type AniListMediaType = "ANIME" | "MANGA";
type AniListStatus =
  | "CURRENT"
  | "COMPLETED"
  | "PLANNING"
  | "DROPPED"
  | "PAUSED"
  | "REPEATING";

type RequestBody = {
  mode?: "preview" | "import";
  username: string;
  types?: AniListMediaType[];
  statuses?: AniListStatus[];
  maxItems?: number;
  perPage?: number;
  text?: string;
  cachedText?: string;
  publicListOnly?: boolean;
};

type AniListTitle = {
  english?: string | null;
  romaji?: string | null;
  native?: string | null;
};

type AniListEntry = {
  status: AniListStatus;
  progress: number | null;
  score: number | null;
  updatedAt: number | null;
  media: {
    id: number;
    seasonYear?: number | null;
    startDate?: { year?: number | null } | null;
    format?: string | null;
    title: AniListTitle;
  };
};

type PreviewItem = {
  mediaId: number;
  type: AniListMediaType;
  status: AniListStatus;
  line: string;
  title: string;
  year: number | null;
  progress: number | null;
  score: number | null;
  updatedAt: number | null;
};

function json(res: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(res), {
    ...init,
    headers: { "Content-Type": "application/json", ...(init.headers ?? {}) },
  });
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

function pickTitle(t: AniListTitle): string {
  return String(t.english || t.romaji || t.native || "").trim();
}

function yearFor(entry: AniListEntry): number | null {
  return entry.media.seasonYear ?? entry.media.startDate?.year ?? null;
}

function lineForEntry(type: AniListMediaType, e: AniListEntry): string {
  const title = pickTitle(e.media.title) || `AniList ${type} ${e.media.id}`;
  const year = yearFor(e);
  const base = year ? `${title} (${year})` : title;

  // Keep output simple and parse-friendly; existing concierge-parse recognizes these cues.
  switch (e.status) {
    case "COMPLETED":
      return `${base} (completed)`;
    case "CURRENT": {
      const p = Number(e.progress ?? 0);
      if (p > 0) {
        return type === "ANIME" ? `${base} up to ep ${p}` : `${base} up to ch ${p}`;
      }
      return `${base} (watching)`;
    }
    case "PLANNING":
      return `${base} (planning)`;
    case "PAUSED":
      return `${base} (on hold)`;
    case "DROPPED":
      return `${base} (dropped)`;
    case "REPEATING":
      return `${base} (rewatching)`;
    default:
      return `${base}`;
  }
}

async function fetchAniListPage(
  username: string,
  type: AniListMediaType,
  statuses: AniListStatus[],
  page: number,
  perPage: number,
): Promise<{ entries: AniListEntry[]; hasNextPage: boolean }> {
  const query = `
    query($username: String, $type: MediaType, $page: Int, $perPage: Int, $statuses: [MediaListStatus]) {
      Page(page: $page, perPage: $perPage) {
        pageInfo { hasNextPage }
        mediaList(userName: $username, type: $type, status_in: $statuses, sort: UPDATED_TIME_DESC) {
          status
          progress
          score(format: POINT_10)
          updatedAt
          media {
            id
            seasonYear
            startDate { year }
            format
            title { english romaji native }
          }
        }
      }
    }
  `;

  const body = JSON.stringify({
    query,
    variables: { username, type, page, perPage, statuses },
  });

  const res = await fetch("https://graphql.anilist.co", {
    method: "POST",
    headers: { "Content-Type": "application/json", "Accept": "application/json" },
    body,
  });

  if (!res.ok) {
    const snippet = await res.text().catch(() => "");
    throw new Error(`AniList error ${res.status}: ${snippet.slice(0, 280)}`);
  }

  const jsonRes = await res.json();
  if (jsonRes?.errors?.length) {
    const msg = String(jsonRes.errors?.[0]?.message ?? "Unknown AniList error");
    throw new Error(`AniList GraphQL: ${msg}`);
  }

  const pageObj = jsonRes?.data?.Page;
  const entries = (pageObj?.mediaList ?? []) as AniListEntry[];
  const hasNextPage = Boolean(pageObj?.pageInfo?.hasNextPage);
  return { entries, hasNextPage };
}

function dedupeAndJoinLines(lines: string[]): { text: string; itemCount: number } {
  const seen = new Set<string>();
  const deduped: string[] = [];
  for (const line of lines) {
    const normalized = line.trim();
    if (!normalized) continue;
    const key = normalized.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    deduped.push(normalized);
  }
  return { text: deduped.join("\n"), itemCount: deduped.length };
}

function buildPreviewItems(lines: string[], entries: Array<{ type: AniListMediaType; entry: AniListEntry }>): PreviewItem[] {
  return entries.slice(0, 8).map(({ type, entry }, index) => ({
    mediaId: entry.media.id,
    type,
    status: entry.status,
    line: lines[index] ?? lineForEntry(type, entry),
    title: pickTitle(entry.media.title) || `AniList ${type} ${entry.media.id}`,
    year: yearFor(entry),
    progress: entry.progress,
    score: entry.score,
    updatedAt: entry.updatedAt,
  }));
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

    const ip = clientIp(req) ?? "";
    const { data: rl } = await client.rpc("check_concierge_rate_limit", { p_kind: "anilist_import", p_ip: ip });
    if (rl && rl.allowed === false) {
      return json({ error: "Rate limited", retry_after_s: rl.retry_after_s ?? null }, { status: 429 });
    }

    const raw = (await req.json().catch(() => ({}))) as Partial<RequestBody>;
    const mode = raw.mode === "preview" ? "preview" : "import";
    const cachedText = String(raw.text ?? raw.cachedText ?? "").trim();
    const hasCachedText = cachedText.length > 0;
    const username = String(raw.username ?? "").trim();
    if (mode === "preview" || !hasCachedText) {
      if (!username) return json({ success: false, error: "Missing username" }, { status: 400 });
      if (username.length > 64) return json({ success: false, error: "Username too long" }, { status: 400 });
    }

    const types = (Array.isArray(raw.types) ? raw.types : ["ANIME", "MANGA"])
      .map((t) => String(t).toUpperCase())
      .filter((t) => t === "ANIME" || t === "MANGA") as AniListMediaType[];
    const uniqueTypes = Array.from(new Set(types));
    if (uniqueTypes.length === 0) return json({ success: false, error: "No types selected" }, { status: 400 });

    const statuses = (Array.isArray(raw.statuses) ? raw.statuses : ["CURRENT", "COMPLETED", "PLANNING"])
      .map((s) => String(s).toUpperCase())
      .filter((s) => ["CURRENT", "COMPLETED", "PLANNING", "DROPPED", "PAUSED", "REPEATING"].includes(s)) as AniListStatus[];
    const uniqueStatuses = Array.from(new Set(statuses));
    if (uniqueStatuses.length === 0) return json({ success: false, error: "No statuses selected" }, { status: 400 });

    const maxItems = Math.max(25, Math.min(400, Number(raw.maxItems ?? 200)));
    const perPage = Math.max(10, Math.min(50, Number(raw.perPage ?? 50)));
    const publicListOnly = raw.publicListOnly ?? true;

    if (mode === "import" && hasCachedText) {
      const { text, itemCount } = dedupeAndJoinLines(cachedText.split(/\r?\n/));
      return json({
        success: true,
        source: "anilist",
        mode,
        username: username || null,
        itemCount,
        truncated: Boolean(raw.truncated ?? false),
        text,
        publicListOnly,
        cachedTextUsed: true,
      });
    }

    const lines: string[] = [];
    const sampledEntries: Array<{ type: AniListMediaType; entry: AniListEntry }> = [];
    const countsByType: Record<AniListMediaType, number> = { ANIME: 0, MANGA: 0 };
    const countsByStatus: Record<AniListStatus, number> = {
      CURRENT: 0,
      COMPLETED: 0,
      PLANNING: 0,
      DROPPED: 0,
      PAUSED: 0,
      REPEATING: 0,
    };
    let total = 0;
    let truncated = false;

    for (const t of uniqueTypes) {
      let page = 1;
      let hasNext = true;
      while (hasNext) {
        const { entries, hasNextPage } = await fetchAniListPage(username, t, uniqueStatuses, page, perPage);
        for (const e of entries) {
          if (total >= maxItems) {
            truncated = true;
            hasNext = false;
            break;
          }
          const line = lineForEntry(t, e);
          lines.push(line);
          countsByType[t] += 1;
          countsByStatus[e.status] += 1;
          if (sampledEntries.length < 8) sampledEntries.push({ type: t, entry: e });
          total += 1;
        }
        if (!hasNextPage) break;
        page += 1;
        hasNext = hasNextPage;
        if (total >= maxItems) {
          truncated = true;
          break;
        }
      }
      if (total >= maxItems) break;
    }

    const { text, itemCount } = dedupeAndJoinLines(lines);
    const sampleItems = buildPreviewItems(lines, sampledEntries);
    return json({
      success: true,
      source: "anilist",
      mode,
      username,
      itemCount,
      truncated,
      text,
      publicListOnly,
      countsByType,
      countsByStatus,
      sampleItems,
    });
  } catch (e) {
    const msg = (e instanceof Error ? e.message : String(e)).slice(0, 400);
    return json({ success: false, error: msg }, { status: 500 });
  }
});
