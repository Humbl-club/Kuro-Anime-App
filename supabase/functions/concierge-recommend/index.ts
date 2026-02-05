import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type MediaType = "ANIME" | "MANGA";

type ConciergeMode = {
  id: string;
  title: string;
  synonyms?: string[];
  required_genres?: string[];
  exclude_genres?: string[];
  min_score?: number;
  min_popularity?: number;
  max_popularity?: number;
  exclude_formats?: string[];
  classic_year_max?: number;
};

type ModePick = { id: string; title: string; confidence: number; reason: string };

type CandidateRow = { media_id: number; match_count?: number | null; score?: number | null };

function json(res: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(res), {
    ...init,
    headers: { "Content-Type": "application/json", ...(init.headers ?? {}) },
  });
}

function uniq<T>(arr: T[]) {
  return Array.from(new Set(arr));
}

function safeStringArray(v: unknown): string[] {
  if (!Array.isArray(v)) return [];
  return uniq(
    v
      .map((x) => (typeof x === "string" ? x.trim() : ""))
      .filter((x) => x.length > 0),
  );
}

function safeNumber(v: unknown): number | null {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : null;
}

function normalizeText(s: string): string {
  return s
    .toLowerCase()
    .replace(/[_/\\-]+/g, " ")
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function parseModesFromConfig(cfg: any): ConciergeMode[] {
  const raw = cfg?.modes;
  if (!Array.isArray(raw)) return [];
  const out: ConciergeMode[] = [];
  for (const r of raw) {
    if (!r || typeof r !== "object") continue;
    const id = typeof r.id === "string" ? r.id.trim() : "";
    const title = typeof r.title === "string" ? r.title.trim() : "";
    if (!id || !title) continue;
    out.push({
      id,
      title,
      synonyms: safeStringArray((r as any).synonyms),
      required_genres: safeStringArray((r as any).required_genres),
      exclude_genres: safeStringArray((r as any).exclude_genres),
      min_score: safeNumber((r as any).min_score) ?? undefined,
      min_popularity: safeNumber((r as any).min_popularity) ?? undefined,
      max_popularity: safeNumber((r as any).max_popularity) ?? undefined,
      exclude_formats: safeStringArray((r as any).exclude_formats),
      classic_year_max: safeNumber((r as any).classic_year_max) ?? undefined,
    });
  }
  return out;
}

function defaultModes(): ConciergeMode[] {
  // Safe fallback if config/migration hasn't been applied yet.
  return [
    {
      id: "premium_action",
      title: "Premium Action",
      synonyms: ["premium action", "best action", "action premium", "hype action", "fight scenes"],
      required_genres: ["Action"],
      min_score: 75,
      min_popularity: 3500,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    {
      id: "cozy_comfort",
      title: "Cozy / Comfort",
      synonyms: ["cozy", "comfort", "chill", "relax", "healing", "iyashikei", "gemütlich"],
      required_genres: ["Slice of Life"],
      min_score: 70,
      min_popularity: 1200,
      exclude_formats: ["MUSIC"],
    },
    {
      id: "premium_comedy_grownup",
      title: "Premium Comedy (grown-up)",
      synonyms: ["funny but not childish", "grown up comedy", "smart comedy", "adult humor", "witzig aber nicht kindisch"],
      required_genres: ["Comedy"],
      min_score: 75,
      min_popularity: 3500,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    {
      id: "dark_serious",
      title: "Dark / Serious",
      synonyms: ["dark", "serious", "mature", "grown up", "not childish", "psychological", "thriller", "mind game"],
      required_genres: ["Drama", "Thriller", "Psychological", "Mystery"],
      min_score: 78,
      min_popularity: 2500,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    {
      id: "hidden_gems",
      title: "Hidden Gems",
      synonyms: ["hidden gems", "underrated", "less known", "something new", "new to me", "surprise me"],
      min_score: 78,
      max_popularity: 45000,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    {
      id: "classics_expanded",
      title: "Classics (expanded)",
      synonyms: ["classic", "classics", "must watch", "essentials", "goat", "greatest of all time"],
      classic_year_max: 2012,
      min_score: 80,
      min_popularity: 1500,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
  ];
}

function scoreMode(text: string, mode: ConciergeMode, inferredGenres: string[]): { score: number; reason: string } {
  const t = normalizeText(text);
  let score = 0;
  let reason = "";

  const synonyms = mode.synonyms ?? [];
  for (const syn of synonyms) {
    const s = normalizeText(syn);
    if (!s) continue;
    if (t.includes(s)) {
      score += Math.max(2, Math.min(5, Math.ceil(s.split(" ").length / 2) + 2));
      if (!reason) reason = `matches "${syn}"`;
    }
  }

  // Genre overlap is a strong signal (even if the user doesn't use the mode's exact synonyms).
  const req = mode.required_genres ?? [];
  const overlap = req.filter((g) => inferredGenres.includes(g));
  if (overlap.length > 0) {
    score += 2 + Math.min(3, overlap.length);
    if (!reason) reason = `genre: ${overlap.slice(0, 2).join(", ")}`;
  }

  // Classic intent boosts the classics mode and slightly downweights gimmick modes.
  const wantsClassic = /\b(classic|classics|must watch|essentials|goat|greatest)\b/i.test(text);
  if (wantsClassic && mode.id.includes("classic")) {
    score += 3;
    if (!reason) reason = "classic intent";
  }
  const wantsHidden = /\b(hidden gem|underrated|less known|new to me|surprise)\b/i.test(text);
  if (wantsHidden && mode.id.includes("hidden")) {
    score += 3;
    if (!reason) reason = "hidden gems intent";
  }

  // Cheap maturity heuristic.
  const mature = /\b(not childish|grown[- ]?up|mature|serious|dark)\b/i.test(text);
  if (mature && (mode.id.includes("grown") || mode.id.includes("dark"))) {
    score += 2;
    if (!reason) reason = "mature tone";
  }

  return { score, reason: reason || "default" };
}

function pickTwoModes(text: string, modes: ConciergeMode[], inferredGenres: string[]): ModePick[] {
  const scored = modes.map((m) => {
    const { score, reason } = scoreMode(text, m, inferredGenres);
    return { mode: m, score, reason };
  });

  // Always keep a classics rail as a stable anchor, unless we don't have such a mode.
  const classics = scored.find((x) => x.mode.id.includes("classic"))?.mode ?? null;

  scored.sort((a, b) => b.score - a.score);

  const primary = scored.find((x) => !x.mode.id.includes("classic"))?.mode ?? scored[0]?.mode ?? null;
  const primaryReason = scored.find((x) => x.mode.id === primary?.id)?.reason ?? "default";
  const primaryScore = scored.find((x) => x.mode.id === primary?.id)?.score ?? 0;

  let secondary: ConciergeMode | null = null;
  let secondaryReason = "default";
  let secondaryScore = 0;

  if (classics && classics.id !== primary?.id) {
    secondary = classics;
    const hit = scored.find((x) => x.mode.id === classics.id);
    secondaryReason = hit?.reason ?? "classic rail";
    secondaryScore = hit?.score ?? 0;
  } else {
    const next = scored.find((x) => x.mode.id !== primary?.id);
    secondary = next?.mode ?? null;
    secondaryReason = next?.reason ?? "default";
    secondaryScore = next?.score ?? 0;
  }

  const mk = (m: ConciergeMode | null, score: number, reason: string): ModePick | null => {
    if (!m) return null;
    // Convert a small integer-ish score to a [0..1] confidence for UI/debugging.
    const confidence = Math.max(0, Math.min(1, score / 10));
    return { id: m.id, title: m.title, confidence, reason };
  };

  const out: ModePick[] = [];
  const p = mk(primary, primaryScore, primaryReason);
  if (p) out.push(p);
  const s = mk(secondary, secondaryScore, secondaryReason);
  if (s) out.push(s);
  return out.slice(0, 2);
}

function inferLanguage(text: string): "de" | "en" {
  const t = text.toLowerCase();
  // Minimal heuristic: just enough for DE narration.
  if (/\b(ich|habe|hab|schaue|gucke|sehe|lese|staffel|folge|kapitel|band|bitte|empfehl)\b/.test(t)) return "de";
  if (/[äöüß]/i.test(t)) return "de";
  return "en";
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

  // NOTE:
  // `recommend_ids_premium` uses `tags.category` (as imported from AniList tag.category) to compute matches.
  // AniList category strings are usually "Comedy", "Drama", "Slice of Life", etc. (not "Theme-...").
  //
  // We also do a genre gate later using `anime.genres` / `manga.genres` for higher precision.

  // EN
  if (/\b(fun|funny|comedy|laugh)\b/.test(t)) out.push("Comedy");
  if (/\b(sad|cry|tears?|heartbreak)\b/.test(t)) out.push("Drama");
  if (/\b(cozy|comfort|chill|relax)\b/.test(t)) out.push("Slice of Life");
  if (/\b(romance|love|romcom)\b/.test(t)) out.push("Romance");
  if (/\b(action)\b/.test(t)) out.push("Action");
  if (/\b(adventure)\b/.test(t)) out.push("Adventure");
  if (/\b(fantasy)\b/.test(t)) out.push("Fantasy");
  if (/\b(sci[- ]?fi|scifi|science fiction)\b/.test(t)) out.push("Sci-Fi");
  if (/\b(mystery|detective)\b/.test(t)) out.push("Mystery");
  if (/\b(thriller)\b/.test(t)) out.push("Thriller");
  if (/\b(horror|scary)\b/.test(t)) out.push("Horror");
  if (/\b(psychological|mind[- ]?game)\b/.test(t)) out.push("Psychological");
  if (/\b(supernatural)\b/.test(t)) out.push("Supernatural");
  if (/\b(sports?)\b/.test(t)) out.push("Sports");
  if (/\b(music)\b/.test(t)) out.push("Music");

  // DE (keep lightweight; only high-signal words)
  if (/\b(lustig|witzig|kom(ö|oe)die|zum lachen)\b/.test(t)) out.push("Comedy");
  if (/\b(traurig|heul|weinen|herzschmerz)\b/.test(t)) out.push("Drama");
  if (/\b(gem(ü|ue)tlich|comfort|chillen|entspann)\b/.test(t)) out.push("Slice of Life");
  if (/\b(liebe|romantik|romance|romcom)\b/.test(t)) out.push("Romance");
  if (/\b(action)\b/.test(t)) out.push("Action");
  if (/\b(abenteuer)\b/.test(t)) out.push("Adventure");
  if (/\b(fantasy|fantasie)\b/.test(t)) out.push("Fantasy");
  if (/\b(sci[- ]?fi|science fiction)\b/.test(t)) out.push("Sci-Fi");
  if (/\b(krimi|mystery|detektiv)\b/.test(t)) out.push("Mystery");
  if (/\b(thriller)\b/.test(t)) out.push("Thriller");
  if (/\b(horror|gruselig)\b/.test(t)) out.push("Horror");
  if (/\b(psychologisch)\b/.test(t)) out.push("Psychological");
  if (/\b(übernatürlich)\b/.test(t)) out.push("Supernatural");
  if (/\b(sport)\b/.test(t)) out.push("Sports");
  if (/\b(musik)\b/.test(t)) out.push("Music");

  // “First anime/manga” intent nudges toward accessible, broadly-liked picks.
  // This is not hardcoded curation; it just biases toward general-audience categories.
  if (/\b(first anime|first manga|getting into anime|getting into manga)\b/.test(t)) {
    out.push("Slice of Life", "Drama", "Adventure");
  }
  if (/\b(erstes anime|erstes manga|anime anfangen|manga anfangen|neu bei anime|neu bei manga)\b/.test(t)) {
    out.push("Slice of Life", "Drama", "Adventure");
  }
  // Explicit modes that should be discoverable.
  if (/\b(isekai)\b/.test(t)) out.push("Fantasy");

  return uniq(out);
}

function inferGimmickTagIds(text: string): number[] {
  const t = text.toLowerCase();
  const ids: number[] = [];
  if (/\b(isekai)\b/.test(t)) ids.push(350);
  if (/\b(reincarnat|reborn|tensei|wiedergeboren|reinkarnat)\b/.test(t)) ids.push(1023);
  if (/\b(another world|in another world|isekai)\b/.test(t)) ids.push(350);
  if (/\b(slime)\b/.test(t)) ids.push(350, 1023);
  if (/\b(harem)\b/.test(t)) ids.push(358, 9154, 18064);
  return uniq(ids);
}

function inferRequiredGenres(text: string): string[] {
  const t = text.toLowerCase();
  const out: string[] = [];
  if (/\b(fun|funny|comedy|laugh|lustig|witzig|kom(ö|oe)die)\b/.test(t)) out.push("Comedy");
  if (/\b(romance|love|romcom|liebe|romantik)\b/.test(t)) out.push("Romance");
  if (/\b(action)\b/.test(t)) out.push("Action");
  if (/\b(adventure|abenteuer)\b/.test(t)) out.push("Adventure");
  if (/\b(fantasy|fantasie|isekai)\b/.test(t)) out.push("Fantasy");
  if (/\b(sci[- ]?fi|scifi|science fiction)\b/.test(t)) out.push("Sci-Fi");
  if (/\b(slice of life|sol|comfort|cozy|gem(ü|ue)tlich)\b/.test(t)) out.push("Slice of Life");
  if (/\b(drama|sad|cry|traurig|herzschmerz)\b/.test(t)) out.push("Drama");
  if (/\b(mystery|detective|krimi|detektiv)\b/.test(t)) out.push("Mystery");
  if (/\b(thriller)\b/.test(t)) out.push("Thriller");
  if (/\b(horror|scary|gruselig)\b/.test(t)) out.push("Horror");
  if (/\b(psychological|psychologisch)\b/.test(t)) out.push("Psychological");
  if (/\b(supernatural|übernatürlich)\b/.test(t)) out.push("Supernatural");
  if (/\b(sports?|sport)\b/.test(t)) out.push("Sports");
  return uniq(out);
}

function inferQualityFloor(text: string): { minScore: number; minPopularity: number; excludeFormats: Set<string> } {
  const t = text.toLowerCase();
  const wantsPremium = /\b(premium|masterpiece|must[- ]?watch|classic|classics|top tier|best)\b/.test(t);
  const noChildish = /\b(not childish|grown[- ]?up|mature|serious|not for kids)\b/.test(t);

  // Defaults: avoid over-filtering; the DB may be small in early imports.
  let minScore = 0;
  let minPopularity = 0;

  if (wantsPremium) {
    minScore = 75;
    minPopularity = 5000;
  }
  if (noChildish) {
    minScore = Math.max(minScore, 75);
    minPopularity = Math.max(minPopularity, 3500);
  }

  // Exclude shortform/noise formats unless explicitly requested.
  const excludeFormats = new Set<string>(["TV_SHORT", "SPECIAL", "MUSIC"]);
  if (/\b(short|mini|shortform)\b/.test(t)) {
    excludeFormats.delete("TV_SHORT");
  }
  return { minScore, minPopularity, excludeFormats };
}

async function mapTagAnilistIdsToInternal(client: any, anilistIds: number[]): Promise<number[]> {
  const ids = uniq(anilistIds).filter((x) => Number.isFinite(x) && x > 0);
  if (!ids.length) return [];
  const { data, error } = await client.from("tags").select("id,anilist_id").in("anilist_id", ids);
  if (error || !Array.isArray(data)) return [];
  return uniq(data.map((r: any) => Number(r.id)).filter((x: any) => Number.isFinite(x) && x > 0));
}

async function groqNarrate(opts: {
  apiKey: string;
  model: string;
  lang: "de" | "en";
  userText: string;
  debug?: boolean;
  items: Array<{ id: string; title: string; year?: number | null; format?: string | null; signals: string[] }>;
}): Promise<{ blurbs: Record<string, string>; usageTotal: number | null }> {
  const url = "https://api.groq.com/openai/v1/chat/completions";
  // NOTE: Groq's GPT-OSS models sometimes return empty `content` if the system prompt is too "policy-like".
  // Keep the system prompt extremely short and drive style via a single user instruction.
  const system =
    opts.lang === "de"
      ? `Gib nur JSON zurück: {"blurbs":{"ANIME|123":"...", "MANGA|456":"..."}}`
      : `Return JSON only: {"blurbs":{"ANIME|123":"...", "MANGA|456":"..."}}`;

  const user =
    opts.lang === "de"
      ? `User prompt: ${opts.userText}\n\nItems:\n${opts.items
          .map((it) => `- ${it.id}: ${it.title} (${it.year ?? "?"}) ${it.format ?? ""} [${it.signals.join(", ")}]`)
          .join("\n")}\n\nSchreibe pro Item genau einen kurzen, spoilerfreien Satz. Gib nur JSON zurück: {"blurbs":{"ANIME|123":"...", "MANGA|456":"..."}}`
      : `User prompt: ${opts.userText}\n\nItems:\n${opts.items
          .map((it) => `- ${it.id}: ${it.title} (${it.year ?? "?"}) ${it.format ?? ""} [${it.signals.join(", ")}]`)
          .join("\n")}\n\nWrite one short, spoiler-free sentence per item. Return JSON only: {"blurbs":{"ANIME|123":"...", "MANGA|456":"..."}}`;

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${opts.apiKey}`,
    },
    body: JSON.stringify({
      model: opts.model,
      // Keep this deterministic and tiny. We're only writing 5–10 single-sentence blurbs.
      temperature: 0.2,
      // We only need short JSON blurbs; keeping this low improves latency/cost.
      max_tokens: 260,
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
    }),
  });

  const jsonRes = await res.json().catch(() => null);
  if (!res.ok) {
    throw new Error(`Groq error: ${res.status} ${JSON.stringify(jsonRes)?.slice(0, 300)}`);
  }

  const usageTotal = Number(
    jsonRes?.usage?.total_tokens ??
      ((Number(jsonRes?.usage?.prompt_tokens ?? 0) || 0) + (Number(jsonRes?.usage?.completion_tokens ?? 0) || 0)),
  );
  const usage = Number.isFinite(usageTotal) && usageTotal > 0 ? usageTotal : null;

  const content = jsonRes?.choices?.[0]?.message?.content;
  if (typeof content !== "string" || !content.trim()) {
    if (opts.debug) {
      throw new Error(
        `Groq narration missing content. status=${res.status} body_snippet=${JSON.stringify(jsonRes)?.slice(0, 600)}`,
      );
    }
    return { blurbs: {}, usageTotal: usage };
  }
  try {
    // Be forgiving: some models wrap JSON in text/code fences.
    const start = content.indexOf("{");
    const end = content.lastIndexOf("}");
    const candidate = start >= 0 && end > start ? content.slice(start, end + 1) : content;
    const parsed = JSON.parse(candidate);
    const blurbs = parsed?.blurbs;
    if (blurbs && typeof blurbs === "object") return { blurbs, usageTotal: usage };
  } catch {
    // ignore
  }
  if (opts.debug) {
    throw new Error(`Groq narration JSON parse failed. content_snippet=${content.slice(0, 400)}`);
  }
  return { blurbs: {}, usageTotal: usage };
}

function clampBlurb(s: string, maxWords: number, maxChars: number) {
  const trimmed = s.replace(/\s+/g, " ").trim();
  if (!trimmed) return "";
  const words = trimmed.split(" ");
  const clippedWords = words.slice(0, maxWords).join(" ");
  const clippedChars = clippedWords.slice(0, maxChars).trim();
  return clippedChars.replace(/[,\s]+$/g, "").trim();
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

    // Server-side rate limiting (per-user + per-IP).
    const ip = clientIp(req);
    const { data: rl } = await client.rpc("check_concierge_rate_limit", {
      p_kind: "recommend",
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
    const text: string = String(body?.text ?? "");
    const scope: string = String(body?.scope ?? "both");
    const limit = Math.max(3, Math.min(20, Number(body?.limit ?? 8)));
    let narrate: boolean = Boolean(body?.narrate ?? false);
    const debugNarration: boolean = Boolean(body?.debugNarration ?? false);

    const categories = inferCategories(text);
    const gimmickTagIds = inferGimmickTagIds(text);
    const requiredGenres = inferRequiredGenres(text);
    const quality = inferQualityFloor(text);

    // Concierge config (tunable without redeploy): used for modes + global LLM budgets.
    const { data: conciergeCfg } = await client.rpc("get_concierge_config");
    const configuredModes = parseModesFromConfig(conciergeCfg);
    const modes = configuredModes.length ? configuredModes : defaultModes();

    // Focus tags are only used for explicit "gimmicks" (isekai, reincarnation, etc.)
    // because `recommend_ids_premium` *requires* focus tags to match when provided.
    const focusTagIds = await mapTagAnilistIdsToInternal(client, gimmickTagIds);
    const allowGimmicks =
      gimmickTagIds.length > 0 || /\b(slime)\b/.test(text.toLowerCase());
    const lang = inferLanguage(text);

    const mediaType = inferMediaType(text, scope);
    const seedQuery = inferSeedQuery(text);

    // Load editorial tag boosts once; used to add deterministic "premium" signals.
    const { data: tagBoosts } = await client
      .from("editorial_tag_boosts")
      .select("tag_id,boost,reason");
    const tagBoostByTag = new Map<number, any>((tagBoosts ?? []).map((t: any) => [t.tag_id, t]));
    const boostTagIds = Array.from(tagBoostByTag.keys());

    const mergeAlternating = <T>(a: T[], b: T[], max: number): T[] => {
      const out: T[] = [];
      let i = 0;
      while (out.length < max && (i < a.length || i < b.length)) {
        if (i < a.length) out.push(a[i]);
        if (out.length >= max) break;
        if (i < b.length) out.push(b[i]);
        i++;
      }
      return out;
    };

    const compileQuality = (mode: ConciergeMode | null) => {
      const minScore = Math.max(quality.minScore, Number(mode?.min_score ?? 0) || 0);
      const minPopularity = Math.max(quality.minPopularity, Number(mode?.min_popularity ?? 0) || 0);
      const maxPopularityRaw = mode?.max_popularity;
      const maxPopularity = Number.isFinite(Number(maxPopularityRaw)) ? Number(maxPopularityRaw) : null;
      const excludeFormats = new Set<string>(Array.from(quality.excludeFormats));
      for (const f of safeStringArray(mode?.exclude_formats)) {
        excludeFormats.add(String(f).toUpperCase());
      }
      return { minScore, minPopularity, maxPopularity, excludeFormats };
    };

    const getPremiumCandidates = async (mt: MediaType, pCategories: string[] | null): Promise<CandidateRow[]> => {
      const { data: ids, error } = await client.rpc("recommend_ids_premium", {
        p_media_type: mt,
        p_categories: pCategories && pCategories.length ? pCategories : null,
        p_limit: 50,
        p_allow_gimmicks: allowGimmicks,
        p_focus_tag_ids: focusTagIds.length ? focusTagIds : null,
      });
      if (error) throw error;
      const rows = Array.isArray(ids) ? ids : [];
      return rows.map((r: any) => ({
        media_id: Number(r.media_id),
        match_count: r.match_count ?? r.overlap_count ?? 0,
        score: r.score ?? null,
      }));
    };

    const assembleItems = async (mt: MediaType, rows: CandidateRow[], opts: {
      limit: number;
      requiredGenres: string[];
      excludeGenres: string[];
      classicYearMax?: number;
      quality: { minScore: number; minPopularity: number; maxPopularity: number | null; excludeFormats: Set<string> };
      prioritizeClassicBoost?: boolean;
    }) => {
      const idList = uniq(rows.map((r) => r.media_id)).filter((x) => Number.isFinite(x) && x > 0);
      if (idList.length === 0) return [] as any[];

      const table = mt === "ANIME" ? "anime" : "manga";
      const { data: mediaRows, error: mediaErr } = await client
        .from(table)
        .select("id,title_english,title_romaji,title_native,cover_image_medium,average_score,popularity,start_date_year,format,status,site_url,is_adult,genres")
        .in("id", idList);
      if (mediaErr) throw mediaErr;
      const byId = new Map<number, any>((mediaRows ?? []).map((r: any) => [r.id, r]));

      // Signals for premium feel (deterministic; no hallucinations).
      const { data: boosts } = await client
        .from("editorial_boosts")
        .select("media_id,label,weight")
        .eq("media_type", mt)
        .in("media_id", idList);
      const boostById = new Map<number, any>((boosts ?? []).map((b: any) => [b.media_id, b]));

      // Get which boosted tags apply to each media id.
      let tagLinks: any[] = [];
      if (boostTagIds.length > 0) {
        const linkTable = mt === "ANIME" ? "anime_tags" : "manga_tags";
        const idCol = mt === "ANIME" ? "anime_id" : "manga_id";
        const resLinks = await client
          .from(linkTable)
          .select(`${idCol},tag_id`)
          .in(idCol, idList)
          .in("tag_id", boostTagIds);
        if (!resLinks.error) tagLinks = resLinks.data ?? [];
      }

      const boostedReasonsById = new Map<number, string[]>();
      for (const row of tagLinks) {
        const mediaId = Number(row[mt === "ANIME" ? "anime_id" : "manga_id"]);
        const tagId = Number(row.tag_id);
        const tb = tagBoostByTag.get(tagId);
        const reason = String(tb?.reason ?? "").trim();
        if (!reason) continue;
        const arr = boostedReasonsById.get(mediaId) ?? [];
        if (!arr.includes(reason)) arr.push(reason);
        boostedReasonsById.set(mediaId, arr);
      }

      const hasGenres = (m: any, required: string[]) => {
        if (!required.length) return true;
        const gs = Array.isArray(m?.genres) ? m.genres.map((x: any) => String(x)) : [];
        if (!gs.length) return false;
        // Require at least one requested genre to match.
        return required.some((g) => gs.includes(g));
      };

      const hasExcludedGenres = (m: any, excluded: string[]) => {
        if (!excluded.length) return false;
        const gs = Array.isArray(m?.genres) ? m.genres.map((x: any) => String(x)) : [];
        if (!gs.length) return false;
        return excluded.some((g) => gs.includes(g));
      };

      const passes = (m: any) => {
        if (!m) return false;
        if (m.is_adult === true) return false;
        if (opts.quality.excludeFormats.has(String(m.format ?? "").toUpperCase())) return false;
        if (hasExcludedGenres(m, opts.excludeGenres)) return false;

        const year = Number(m.start_date_year ?? 0);
        if (opts.classicYearMax && year > 0 && year > opts.classicYearMax) return false;

        const score = Number(m.average_score ?? 0);
        const pop = Number(m.popularity ?? 0);
        if (opts.quality.minScore > 0 && score > 0 && score < opts.quality.minScore) return false;
        if (opts.quality.minPopularity > 0 && pop > 0 && pop < opts.quality.minPopularity) return false;
        if (opts.quality.maxPopularity != null && pop > 0 && pop > opts.quality.maxPopularity) return false;
        return true;
      };

      // Prefer: genre match + quality; then quality; then anything (no hard failures).
      const primary: CandidateRow[] = [];
      const secondary: CandidateRow[] = [];
      const tertiary: CandidateRow[] = [];

      for (const r of rows) {
        const m = byId.get(r.media_id);
        if (!m) continue;
        if (passes(m) && hasGenres(m, opts.requiredGenres)) primary.push(r);
        else if (passes(m)) secondary.push(r);
        else tertiary.push(r);
      }

      let ordered = [...primary, ...secondary, ...tertiary];
      if (opts.prioritizeClassicBoost) {
        const boosted: CandidateRow[] = [];
        const rest: CandidateRow[] = [];
        for (const r of ordered) {
          const b = boostById.get(r.media_id);
          if (b?.label === "classic") boosted.push(r);
          else rest.push(r);
        }
        ordered = [...boosted, ...rest];
      }
      ordered = ordered.slice(0, opts.limit);

      const out: any[] = [];
      for (const r of ordered) {
        const m = byId.get(r.media_id);
        if (!m) continue;
        const signals: string[] = [];
        const b = boostById.get(r.media_id);
        if (b?.label === "classic") signals.push("CLASSIC");
        const reasons = boostedReasonsById.get(r.media_id) ?? [];
        for (const x of reasons.slice(0, 3)) signals.push(String(x).toUpperCase());
        if ((r.match_count ?? 0) >= 2) signals.push("MATCH");

        out.push({
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
          signals,
          genres: Array.isArray(m.genres) ? m.genres : null,
        });
      }
      return out;
    };

    const modePicks = pickTwoModes(text, modes, requiredGenres);
    const modeById = new Map<string, ConciergeMode>(modes.map((m) => [m.id, m]));

    // Build up to 2 rails (modes). Always keep a classics rail as the second choice where possible.
    const sets: any[] = [];

    for (const mp of modePicks) {
      const mode = modeById.get(mp.id) ?? null;
      const isClassicMode = (mode?.id ?? mp.id).includes("classic");
      const perSetTotal = isClassicMode ? Math.min(20, Math.max(limit, 14)) : limit;
      const perType = mediaType === "BOTH" ? Math.max(3, Math.ceil(perSetTotal / 2)) : perSetTotal;

      const modeRequired = uniq([...(mode?.required_genres ?? []), ...requiredGenres]);
      const modeExcluded = mode?.exclude_genres ?? [];

      // Feed the DB scorer with a small, mode-aware category set, but don't overconstrain.
      const modeCats = uniq([...(categories ?? []), ...(mode?.required_genres ?? [])]);
      const pCats = modeCats.length ? modeCats : (categories.length ? categories : null);
      const q = compileQuality(mode);

      const animeRows = (mediaType === "ANIME" || mediaType === "BOTH") ? await getPremiumCandidates("ANIME", pCats) : [];
      const mangaRows = (mediaType === "MANGA" || mediaType === "BOTH") ? await getPremiumCandidates("MANGA", pCats) : [];

      const animeItems = (mediaType === "ANIME" || mediaType === "BOTH")
        ? await assembleItems("ANIME", animeRows, {
          limit: perType,
          requiredGenres: modeRequired,
          excludeGenres: modeExcluded,
          classicYearMax: mode?.classic_year_max,
          quality: q,
          prioritizeClassicBoost: isClassicMode,
        })
        : [];
      const mangaItems = (mediaType === "MANGA" || mediaType === "BOTH")
        ? await assembleItems("MANGA", mangaRows, {
          limit: perType,
          requiredGenres: modeRequired,
          excludeGenres: modeExcluded,
          classicYearMax: mode?.classic_year_max,
          quality: q,
          prioritizeClassicBoost: isClassicMode,
        })
        : [];

      const merged = mediaType === "BOTH" ? mergeAlternating(animeItems, mangaItems, perSetTotal) : [...animeItems, ...mangaItems].slice(0, perSetTotal);

      sets.push({
        id: mp.id,
        title: mp.title,
        modeId: mp.id,
        confidence: mp.confidence,
        reason: mp.reason,
        items: merged,
      });
    }

    // If the user is explicit ("like Vagabond"), offer a similarity rail as the first mode.
    // This keeps the UX feeling "smart" without spending LLM tokens.
    if (seedQuery) {
      // Only override when we can find a decent seed title.
      const pickSeed = async (mt: MediaType) => {
        const { data: seeds, error: seedErr } = await client.rpc("search_titles", {
          p_query: seedQuery,
          p_media_type: mt,
          p_limit: 6,
        });
        if (seedErr || !Array.isArray(seeds) || seeds.length === 0) return null;
        const top = seeds[0];
        if ((top?.score ?? 0) < 0.35) return null;
        return { mt, mediaId: Number(top.media_id), title: String(top.title ?? "").trim() };
      };

      const seed = mediaType === "MANGA" ? await pickSeed("MANGA")
        : mediaType === "ANIME" ? await pickSeed("ANIME")
        : (await pickSeed("ANIME")) ?? (await pickSeed("MANGA"));

      if (seed && Number.isFinite(seed.mediaId) && seed.mediaId > 0) {
        const perSetTotal = limit;
        const perType = mediaType === "BOTH" ? Math.max(3, Math.ceil(perSetTotal / 2)) : perSetTotal;
        const q = compileQuality(null);

        const getSim = async (mt: MediaType) => {
          const { data: sim, error: simErr } = await client.rpc("recommend_ids_similar_to_seeds", {
            p_media_type: mt,
            p_seed_ids: [seed.mediaId],
            p_limit: 50,
            p_allow_gimmicks: allowGimmicks,
          });
          if (simErr || !Array.isArray(sim)) return [] as CandidateRow[];
          return sim.map((r: any) => ({
            media_id: Number(r.media_id),
            match_count: r.overlap_count ?? r.match_count ?? 0,
            score: r.score ?? null,
          }));
        };

        const animeRows = (mediaType === "ANIME" || mediaType === "BOTH") ? await getSim("ANIME") : [];
        const mangaRows = (mediaType === "MANGA" || mediaType === "BOTH") ? await getSim("MANGA") : [];
        const animeItems = (mediaType === "ANIME" || mediaType === "BOTH")
          ? await assembleItems("ANIME", animeRows, { limit: perType, requiredGenres, excludeGenres: [], quality: q })
          : [];
        const mangaItems = (mediaType === "MANGA" || mediaType === "BOTH")
          ? await assembleItems("MANGA", mangaRows, { limit: perType, requiredGenres, excludeGenres: [], quality: q })
          : [];

        const merged = mediaType === "BOTH" ? mergeAlternating(animeItems, mangaItems, perSetTotal) : [...animeItems, ...mangaItems].slice(0, perSetTotal);
        const title = seed.title || seedQuery;

        // Keep the classics rail as the secondary mode, but replace the primary.
        if (sets.length >= 1) {
          sets[0] = {
            id: "similar_to_seed",
            title: `Similar to “${title}”`,
            modeId: "similar_to_seed",
            confidence: 1,
            reason: "seed similarity",
            items: merged,
          };
        } else {
          sets.unshift({
            id: "similar_to_seed",
            title: `Similar to “${title}”`,
            modeId: "similar_to_seed",
            confidence: 1,
            reason: "seed similarity",
            items: merged,
          });
        }
      }
    }

    // Flatten for backwards compatibility + LLM narration.
    const allItems: any[] = [];
    const seen = new Set<string>();
    for (const s of sets) {
      for (const it of (s?.items ?? [])) {
        const key = `${it.mediaType}|${it.mediaId}`;
        if (seen.has(key)) continue;
        seen.add(key);
        allItems.push(it);
      }
    }

    try {
      await client.rpc("log_concierge_run", {
        p_kind: "recommend",
        p_status: "success",
        p_input_chars: text.length,
        p_items_count: allItems.length,
      });
    } catch {
      // best-effort
    }

    const message = (() => {
      if (sets.length === 0) {
        return categories.length === 0
          ? "Premium picks (new to you). Tell me a vibe like “funny”, “sad”, “cozy”, or a genre to sharpen it."
          : null;
      }
      const titles = sets.slice(0, 2).map((s: any) => String(s.title ?? "")).filter(Boolean);
      if (titles.length >= 2) return `Two rails for you: ${titles[0]} + ${titles[1]}.`;
      if (titles.length === 1) return `Here’s a rail for you: ${titles[0]}.`;
      return null;
    })();

    // Optional narration (pure presentation layer).
    let narrationError: string | null = null;
    if (narrate) {
      // Global kill-switch: keep core recommendations deterministic if disabled.
      const { data: llmEnabled } = await client.rpc("is_flag_enabled", { p_key: "llm_enabled" });
      if (llmEnabled === false) narrate = false;
    }

    if (narrate) {
      const groqKey = Deno.env.get("GROQ_API_KEY");
      const groqModel = Deno.env.get("GROQ_MODEL") ?? "openai/gpt-oss-20b";
      if (groqKey) {
        const maxCompletion = 260;
        const packed = allItems.slice(0, 8).map((it) => ({
          id: `${it.mediaType}|${it.mediaId}`,
          title: it.title,
          year: it.year,
          format: it.format,
          signals: Array.isArray(it.signals) ? it.signals : [],
        }));

        const promptChars = 1200 + text.length + JSON.stringify(packed).length;
        const reserveTokens = Math.min(9000, Math.max(160, Math.ceil(promptChars / 4) + maxCompletion));

        // Reserve budget. If exceeded, just return without blurbs.
        const { data: budget } = await client.rpc("llm_budget_reserve", {
          p_reserved_tokens: reserveTokens,
          p_max_daily_tokens: null,
          p_max_daily_calls: null,
          p_model: groqModel,
        });
        if (budget && budget.allowed === false) {
          narrate = false;
        }

        // Global budget (prevents "many users" abuse).
        let gReserveOk = true;
        if (narrate) {
          try {
            const globalBudget = conciergeCfg?.global_llm_budget ?? null;
            const globalDailyTokens = Number(globalBudget?.daily_tokens ?? 250000);
            const globalDailyCalls = Number(globalBudget?.daily_calls ?? 600);
            const { data: gBudget } = await client.rpc("llm_global_budget_reserve", {
              p_reserved_tokens: reserveTokens,
              p_max_daily_tokens: Number.isFinite(globalDailyTokens) ? globalDailyTokens : 250000,
              p_max_daily_calls: Number.isFinite(globalDailyCalls) ? globalDailyCalls : 600,
            });
            if (gBudget && gBudget.allowed === false) gReserveOk = false;
          } catch {
            // If config/global budget fails for some reason, fail closed (no narration).
            gReserveOk = false;
          }
          if (!gReserveOk) {
            narrate = false;
            try {
              await client.rpc("llm_budget_finalize", { p_reserved_tokens: reserveTokens, p_actual_tokens: 0, p_model: groqModel });
            } catch {
              // ignore
            }
          }
        }

        try {
          if (!narrate) throw new Error("LLM budget exceeded");

          const { blurbs, usageTotal } = await groqNarrate({
            apiKey: groqKey,
            model: groqModel,
            lang,
            userText: text,
            debug: debugNarration,
            items: packed,
          });
          for (const it of allItems) {
            const key = `${it.mediaType}|${it.mediaId}`;
            const b = blurbs[key];
            if (typeof b === "string" && b.trim()) it.blurb = clampBlurb(b, 18, 180);
          }

          // Finalize with actual usage if available; else treat reserve as actual.
          try {
            const actual = usageTotal ?? reserveTokens;
            await client.rpc("llm_budget_finalize", {
              p_reserved_tokens: reserveTokens,
              p_actual_tokens: actual,
              p_model: groqModel,
            });
            await client.rpc("llm_global_budget_finalize", {
              p_reserved_tokens: reserveTokens,
              p_actual_tokens: actual,
            });
          } catch {
            // best-effort
          }
        } catch (e) {
          // Release reservation on failure (best-effort).
          try {
            await client.rpc("llm_budget_finalize", {
              p_reserved_tokens: reserveTokens,
              p_actual_tokens: 0,
              p_model: groqModel,
            });
            await client.rpc("llm_global_budget_finalize", {
              p_reserved_tokens: reserveTokens,
              p_actual_tokens: 0,
            });
          } catch {
            // best-effort
          }
          narrationError = (e as Error)?.message ?? String(e);
        }
      } else {
        narrate = false;
      }
    }

    return json({
      success: true,
      categories,
      modes: modePicks,
      sets,
      // Backwards compat: clients that only understand `items` still get a useful response.
      items: allItems,
      message,
      narrated: narrate,
      ...(debugNarration ? { narrationError } : {}),
    });
  } catch (e) {
    const err = e as Error;
    return json({ error: "Internal error", message: err?.message ?? String(e) }, { status: 500 });
  }
});
