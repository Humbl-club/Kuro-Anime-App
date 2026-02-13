import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type MediaType = "ANIME" | "MANGA";

type ConciergeMode = {
  id: string;
  title: string;
  synonyms?: string[];
  // Optional linkage to a pinned curated rail (per media type).
  // Example config:
  //   "rail_id": {"anime":"classics_anime","manga":"classics_manga"}
  rail_id?: string | { anime?: string; manga?: string; both?: string };
  required_genres?: string[];
  exclude_genres?: string[];
  min_score?: number;
  min_popularity?: number;
  max_popularity?: number;
  exclude_formats?: string[];
  classic_year_max?: number;
};

type ModePick = { id: string; title: string; confidence: number; reason: string };

type UserConstraints = {
  excluded_genres: string[];
  format: string | null;       // "MOVIE" | "SHORT_FORM" | "ONA" | "OVA" | null
  max_episodes: number | null;
  min_episodes: number | null;
  year_min: number | null;
  year_max: number | null;
  why: string[];
};

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

function stableBucket(input: string): number {
  // djb2-style deterministic hash, then map into [0, 99].
  let hash = 5381;
  for (let i = 0; i < input.length; i++) {
    hash = ((hash << 5) + hash) + input.charCodeAt(i);
    hash |= 0;
  }
  return Math.abs(hash) % 100;
}

function inferRequestMarket(req: Request): string {
  const cfCountry = req.headers.get("cf-ipcountry")?.trim().toUpperCase();
  if (cfCountry && /^[A-Z]{2}$/.test(cfCountry)) return cfCountry;

  const acceptLanguage = req.headers.get("accept-language") ?? "";
  const first = acceptLanguage.split(",")[0]?.trim() ?? "";
  const region = first.match(/-[A-Za-z]{2}\b/)?.[0]?.slice(1).toUpperCase();
  if (region && /^[A-Z]{2}$/.test(region)) return region;
  return "US";
}

/** Strip common LLM prompt-injection patterns from user-supplied text before interpolation. */
function sanitizeForLLM(text: string): string {
  return text
    // Strip common injection patterns
    .replace(/\b(ignore|disregard|forget)\s+(all\s+)?(previous|above|prior)\s+(instructions?|prompts?|rules?|context)/gi, '[filtered]')
    .replace(/\b(you\s+are\s+now|new\s+instructions?|system\s*:)/gi, '[filtered]')
    .replace(/\b(act\s+as|pretend\s+(to\s+be|you\s+are)|role\s*play)/gi, '[filtered]')
    // Strip markdown/HTML injection attempts
    .replace(/```[\s\S]*?```/g, '')
    .replace(/<[^>]+>/g, '')
    // Limit length
    .slice(0, 2000)
    // Trim whitespace
    .trim();
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
    let rail_id: ConciergeMode["rail_id"] | undefined = undefined;
    const rid = (r as any).rail_id;
    if (typeof rid === "string" && rid.trim()) {
      rail_id = rid.trim();
    } else if (rid && typeof rid === "object") {
      const anime = typeof (rid as any).anime === "string" ? (rid as any).anime.trim() : "";
      const manga = typeof (rid as any).manga === "string" ? (rid as any).manga.trim() : "";
      const both = typeof (rid as any).both === "string" ? (rid as any).both.trim() : "";
      rail_id = {
        ...(anime ? { anime } : {}),
        ...(manga ? { manga } : {}),
        ...(both ? { both } : {}),
      };
    }
    out.push({
      id,
      title,
      synonyms: safeStringArray((r as any).synonyms),
      rail_id,
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
  // Matches the v3 migration (20260206100000_concierge_modes_v3_expanded).
  return [
    // ── Existing 8 modes (enriched synonyms) ──
    {
      id: "premium_picks",
      title: "Premium Picks",
      synonyms: ["something good", "recommend something", "surprise me", "premium", "best", "top tier", "what should i watch", "anything good", "just pick something", "quality"],
      min_score: 75,
      min_popularity: 2500,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    {
      id: "gateway_start_here",
      title: "Start Here",
      synonyms: ["first anime", "first manga", "where do i start", "getting into anime", "getting into manga", "beginner", "new to anime", "new to manga", "gateway", "never watched anime"],
      rail_id: { anime: "gateway_anime", manga: "gateway_manga" },
    },
    {
      id: "premium_action",
      title: "Premium Action",
      synonyms: ["action", "hype action", "action premium", "best action", "sakuga", "fight scenes", "battle", "tournament", "shounen", "epic fights", "adrenaline"],
      required_genres: ["Action"],
      min_score: 75,
      min_popularity: 3500,
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    {
      id: "premium_comedy_grownup",
      title: "Premium Comedy (grown-up)",
      synonyms: ["funny but not childish", "grown up comedy", "adult humor", "smart comedy", "witzig aber nicht kindisch", "sitcom", "parody", "satire", "clever humor", "comedy for adults"],
      required_genres: ["Comedy"],
      min_score: 75,
      min_popularity: 3500,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    {
      id: "cozy_comfort",
      title: "Cozy / Comfort",
      synonyms: ["cozy", "comfort", "chill", "relax", "healing", "iyashikei", "gemütlich", "wholesome", "feel good", "heartwarming", "warm", "gentle", "peaceful"],
      required_genres: ["Slice of Life"],
      min_score: 70,
      min_popularity: 1200,
      exclude_formats: ["MUSIC"],
    },
    {
      id: "dark_serious",
      title: "Dark / Serious",
      synonyms: ["dark", "serious", "mature", "grown up", "not childish", "psychological", "thriller", "mind game", "seinen", "gore", "violent", "gritty", "brutal", "mind bending"],
      required_genres: ["Drama", "Thriller", "Psychological", "Mystery"],
      min_score: 78,
      min_popularity: 2500,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    {
      id: "hidden_gems",
      title: "Hidden Gems",
      synonyms: ["hidden gems", "underrated", "less known", "something new", "new to me", "overlooked", "sleeper", "cult", "niche", "off the beaten path"],
      min_score: 78,
      max_popularity: 45000,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    {
      id: "classics_expanded",
      title: "Classics (expanded)",
      synonyms: ["classic", "classics", "must watch", "essentials", "goat", "greatest of all time", "old school", "retro", "90s anime", "80s anime", "iconic", "all time best"],
      rail_id: { anime: "classics_anime", manga: "classics_manga" },
      classic_year_max: 2012,
      min_score: 80,
      min_popularity: 1500,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    // ── 6 new modes ──
    {
      id: "short_one_season",
      title: "Short & Complete",
      synonyms: ["short", "one season", "12 episodes", "13 episodes", "quick watch", "binge", "one cour", "single season", "short anime"],
      min_score: 74,
      min_popularity: 2000,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC", "MOVIE", "ONA"],
    },
    {
      id: "movie_night",
      title: "Movie Night",
      synonyms: ["movie", "movies", "film", "anime movie", "movie night", "feature film", "standalone movie"],
      min_score: 76,
      min_popularity: 2000,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV", "TV_SHORT", "SPECIAL", "MUSIC", "ONA", "OVA"],
    },
    {
      id: "romance_serious",
      title: "Romance (serious)",
      synonyms: ["serious romance", "love story", "romantic drama", "romance drama", "emotional romance", "bittersweet", "heartbreak", "romance not comedy", "deep romance"],
      required_genres: ["Romance", "Drama"],
      min_score: 74,
      min_popularity: 2000,
      exclude_genres: ["Kids", "Comedy"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    {
      id: "romcom",
      title: "Romcom",
      synonyms: ["romcom", "romantic comedy", "rom com", "funny romance", "lighthearted romance", "love comedy", "cute romance", "fluffy", "sweet romance"],
      required_genres: ["Romance", "Comedy"],
      min_score: 72,
      min_popularity: 2000,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    {
      id: "fantasy_non_isekai",
      title: "Fantasy (no isekai)",
      synonyms: ["fantasy", "high fantasy", "swords and sorcery", "magic", "epic fantasy", "fantasy no isekai", "traditional fantasy", "pure fantasy"],
      required_genres: ["Fantasy"],
      min_score: 74,
      min_popularity: 2000,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    {
      id: "isekai",
      title: "Isekai",
      synonyms: ["isekai", "transported to another world", "reincarnated", "another world", "reborn", "other world", "parallel world", "summoned to another world", "truck-kun"],
      required_genres: ["Fantasy", "Adventure"],
      min_score: 72,
      min_popularity: 2500,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    // ── 3 additional modes (Phase 1 expansion) ──
    {
      id: "sports",
      title: "Sports",
      synonyms: ["sports", "sport", "basketball", "soccer", "football", "volleyball", "boxing", "tennis", "baseball", "cycling", "running", "swimming", "haikyuu", "blue lock", "kuroko"],
      required_genres: ["Sports"],
      min_score: 72,
      min_popularity: 1500,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
      rail_id: { anime: "sports_anime", manga: "sports_manga" },
    },
    {
      id: "scifi",
      title: "Sci-Fi",
      synonyms: ["sci-fi", "science fiction", "scifi", "cyberpunk", "space", "futuristic", "dystopian", "robots", "space opera", "mecha"],
      required_genres: ["Sci-Fi"],
      min_score: 74,
      min_popularity: 2000,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
      rail_id: { anime: "scifi_anime", manga: "scifi_manga" },
    },
    {
      id: "horror_supernatural",
      title: "Horror & Supernatural",
      synonyms: ["horror", "scary", "creepy", "supernatural", "ghost", "demon", "occult", "vampire", "zombie", "curse", "haunted", "junji ito"],
      required_genres: ["Horror", "Supernatural"],
      min_score: 70,
      min_popularity: 1500,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
      rail_id: { anime: "horror_supernatural_anime", manga: "horror_supernatural_manga" },
    },
  ];
}

const GERMAN_VIBE_FORMS: Record<string, string> = {
  "düsteres": "düster", "düstere": "düster", "düsterem": "düster", "düsterer": "düster", "düsteren": "düster",
  "lustiges": "lustig", "lustige": "lustig", "lustigem": "lustig", "lustiger": "lustig", "lustigen": "lustig",
  "gemütliches": "gemütlich", "gemütliche": "gemütlich", "gemütlichem": "gemütlich",
  "ernstes": "ernst", "ernste": "ernst", "ernstem": "ernst", "ernster": "ernst",
  "gruseliges": "gruselig", "gruselige": "gruselig", "gruseligem": "gruselig",
  "romantisches": "romantisch", "romantische": "romantisch", "romantischem": "romantisch",
  "historisches": "historisch", "historische": "historisch", "historischem": "historisch",
  "witziges": "witzig", "witzige": "witzig", "witzigem": "witzig",
  "entspannendes": "entspannend", "entspannende": "entspannend",
  "unheimliches": "unheimlich", "unheimliche": "unheimlich",
  "legendäres": "legendär", "legendäre": "legendär",
  "übernatürliches": "übernatürlich", "übernatürliche": "übernatürlich",
};

function normalizeUmlauts(s: string): string {
  return s.replace(/ü/g, "ue").replace(/ö/g, "oe").replace(/ä/g, "ae").replace(/ß/g, "ss")
          .replace(/Ü/g, "Ue").replace(/Ö/g, "Oe").replace(/Ä/g, "Ae");
}

function normalizeGermanVibeWords(text: string): string {
  let result = text.toLowerCase();
  for (const [inflected, base] of Object.entries(GERMAN_VIBE_FORMS)) {
    result = result.replace(new RegExp(`\\b${inflected}\\b`, "g"), base);
  }
  return result;
}

function scoreMode(text: string, mode: ConciergeMode, inferredGenres: string[], excludedGenres: string[] = [], userConstraints?: UserConstraints): { score: number; reason: string } {
  const t = normalizeText(text);
  const tNorm = normalizeUmlauts(normalizeGermanVibeWords(text));
  let score = 0;
  let reason = "";

  const synonyms = mode.synonyms ?? [];
  for (const syn of synonyms) {
    const s = normalizeText(syn);
    if (!s) continue;
    if (t.includes(s) || normalizeUmlauts(normalizeGermanVibeWords(t)).includes(normalizeUmlauts(normalizeGermanVibeWords(s)))) {
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

  // Penalize modes whose core genres are excluded by user (e.g. "no romance" suppresses romcom).
  const exclLower = new Set(excludedGenres.map((g) => g.toLowerCase()));
  const exclOverlap = req.filter((g) => exclLower.has(g.toLowerCase()));
  if (exclOverlap.length > 0) {
    score -= 5 * exclOverlap.length;
  }

  // Classic intent boosts the classics mode and slightly downweights gimmick modes.
  const wantsClassic = /\b(classic|classics|must watch|essentials|goat|greatest|retro|old school|oldschool|vintage|80s|90s|klassiker|klassisch|legendaer|meisterwerk|muss man gesehen haben)\b/i.test(tNorm);
  if (wantsClassic && mode.id.includes("classic")) {
    score += 3;
    if (!reason) reason = "classic intent";
  }
  const wantsHidden = /\b(hidden gem|underrated|less known|new to me|surprise|geheimtipp|unterschaetzt|unbekannt|wenig bekannt)\b/i.test(tNorm);
  if (wantsHidden && mode.id.includes("hidden")) {
    score += 3;
    if (!reason) reason = "hidden gems intent";
  }

  // Cheap maturity heuristic.
  const mature = /\b(not childish|grown[- ]?up|mature|serious|dark)\b/i.test(tNorm);
  if (mature && (mode.id.includes("grown") || mode.id.includes("dark"))) {
    score += 2;
    if (!reason) reason = "mature tone";
  }

  // Movie intent.
  const wantsMovie = /\b(movie|film|filme|movie night|filmabend|kinofilm)\b/i.test(tNorm);
  if (wantsMovie && mode.id === "movie_night") {
    score += 3;
    if (!reason) reason = "movie intent";
  }

  // Short/binge intent.
  const wantsShort = /\b(short|one season|quick watch|binge|one cour|12 ep|13 ep|kurz|eine staffel|1 staffel|schnell|durchschauen|kurze serie|kurz und gut)\b/i.test(tNorm);
  if (wantsShort && mode.id === "short_one_season") {
    score += 3;
    if (!reason) reason = "short series intent";
  }

  // Isekai intent (boost isekai, penalize fantasy_non_isekai).
  const wantsIsekai = /\b(isekai|reincarnated|another world|reborn|truck[- ]?kun)\b/i.test(tNorm);
  if (wantsIsekai && mode.id === "isekai") {
    score += 3;
    if (!reason) reason = "isekai intent";
  }
  if (wantsIsekai && mode.id === "fantasy_non_isekai") {
    score -= 4; // suppress non-isekai fantasy when user explicitly wants isekai
  }

  // "No isekai" intent (boost fantasy_non_isekai, penalize isekai).
  const noIsekai = /\b(no isekai|not isekai|ohne isekai|nicht isekai|kein isekai|fantasy no isekai|non[- ]?isekai)\b/i.test(tNorm);
  if (noIsekai && mode.id === "fantasy_non_isekai") {
    score += 4;
    if (!reason) reason = "non-isekai intent";
  }
  if (noIsekai && mode.id === "isekai") {
    score -= 4;
  }

  // Romance sub-type disambiguation.
  const wantsRomcom = /\b(romcom|rom com|romantic comedy|funny romance|cute romance|fluffy|romantische komoedie|lustige romanze)\b/i.test(tNorm);
  if (wantsRomcom && mode.id === "romcom") {
    score += 3;
    if (!reason) reason = "romcom intent";
  }
  if (wantsRomcom && mode.id === "romance_serious") {
    score -= 2;
  }
  const wantsSeriousRomance = /\b(serious romance|romance drama|heartbreak|bittersweet|deep romance|ernste romanze|liebesgeschichte|herzschmerz)\b/i.test(tNorm);
  if (wantsSeriousRomance && mode.id === "romance_serious") {
    score += 3;
    if (!reason) reason = "serious romance intent";
  }
  if (wantsSeriousRomance && mode.id === "romcom") {
    score -= 2;
  }

  // Sports intent.
  const wantsSports = /\b(sports?|soccer|basketball|volleyball|boxing|tennis|baseball|haikyuu|blue lock|kuroko|fussball)\b/i.test(tNorm);
  if (wantsSports && mode.id === "sports") {
    score += 3;
    if (!reason) reason = "sports intent";
  }

  // Sci-fi intent.
  const wantsScifi = /\b(sci[- ]?fi|scifi|science fiction|cyberpunk|space|futuristic|dystopian|space opera|mecha|weltraum|zukunft|roboter)\b/i.test(tNorm);
  if (wantsScifi && mode.id === "scifi") {
    score += 3;
    if (!reason) reason = "sci-fi intent";
  }

  // Horror/supernatural intent (disambiguate from dark_serious).
  const wantsHorror = /\b(horror|scary|creepy|ghost|demon|occult|vampire|zombie|curse|haunted|junji ito|gruselig|geist|daemon|unheimlich|schaurig)\b/i.test(tNorm);
  if (wantsHorror && mode.id === "horror_supernatural") {
    score += 3;
    if (!reason) reason = "horror intent";
  }
  if (wantsHorror && mode.id === "dark_serious") {
    score -= 2; // prefer horror_supernatural over dark_serious for explicit horror queries
  }

  // Cozy/comfort intent.
  const wantsCozy = /\b(cozy|chill|healing|wholesome|comfort|gemuetlich|entspannend|wohlfuehl|beruhigend)\b/i.test(tNorm);
  if (wantsCozy && mode.id === "cozy_comfort") {
    score += 3;
    if (!reason) reason = "cozy intent";
  }

  // Mecha intent.
  const wantsMecha = /\b(mecha|giant robot|gundam|eva(ngelion)?|code geass|roboter|riesenroboter)\b/i.test(tNorm);
  if (wantsMecha && mode.id === "mecha") {
    score += 3;
    if (!reason) reason = "mecha intent";
  }

  // Mystery/detective intent.
  const wantsMystery = /\b(mystery|detective|whodunit|krimi|detektiv|who done it|case solved|raetsel)\b/i.test(tNorm);
  if (wantsMystery && mode.id === "mystery_detective") {
    score += 3;
    if (!reason) reason = "mystery intent";
  }

  // Music/performance intent.
  const wantsMusic = /\b(music anime|band|idol|concert|musik|instrument|k[- ]?on)\b/i.test(tNorm);
  if (wantsMusic && mode.id === "music_performance") {
    score += 3;
    if (!reason) reason = "music intent";
  }

  // Historical intent.
  const wantsHistorical = /\b(historical|samurai|period|war drama|medieval|historisch|mittelalter|vinland)\b/i.test(tNorm);
  if (wantsHistorical && mode.id === "historical") {
    score += 3;
    if (!reason) reason = "historical intent";
  }

  // School/coming-of-age intent.
  const wantsSchool = /\b(school|campus|high school|coming.of.age|youth|schule|jugend|gymnasium)\b/i.test(tNorm);
  if (wantsSchool && mode.id === "school_coming_of_age") {
    score += 3;
    if (!reason) reason = "school intent";
  }

  // Shoujo/Josei intent.
  const wantsShoujoJosei = /\b(shoujo|josei|for women|girls manga|fuer frauen|maedchen|woman protagonist)\b/i.test(tNorm);
  if (wantsShoujoJosei && mode.id === "shoujo_josei") {
    score += 3;
    if (!reason) reason = "shoujo/josei intent";
  }

  // ── Constraint-based mode penalties ──
  if (userConstraints) {
    // Movie constraint: penalize TV-focused modes, boost movie_night.
    if (userConstraints.format === "MOVIE") {
      if (mode.id === "movie_night") {
        score += 4;
        if (!reason) reason = "movie constraint";
      } else if (mode.exclude_formats?.includes("MOVIE")) {
        score -= 6; // mode explicitly excludes movies
      }
    }
    // Short-form constraint: penalize long-series modes.
    if (userConstraints.format === "SHORT_FORM" || userConstraints.format === "OVA" || userConstraints.format === "ONA") {
      if (mode.id === "short_one_season") {
        score += 3;
        if (!reason) reason = "short-form constraint";
      }
    }
    // Max-episodes constraint: boost short_one_season mode when user wants <=26 episodes.
    if (userConstraints.max_episodes != null && userConstraints.max_episodes <= 26) {
      if (mode.id === "short_one_season") {
        score += 2;
        if (!reason) reason = "episode limit constraint";
      }
    }
    // Min-episodes constraint: penalize short modes when user wants long.
    if (userConstraints.min_episodes != null && userConstraints.min_episodes >= 50) {
      if (mode.id === "short_one_season" || mode.id === "movie_night") {
        score -= 5;
      }
    }
    // Year max constraint: boost classics mode if user wants older titles.
    if (userConstraints.year_max != null && userConstraints.year_max <= 2012) {
      if (mode.id.includes("classic")) {
        score += 2;
        if (!reason) reason = "year constraint (classic era)";
      }
    }
  }

  return { score, reason: reason || "default" };
}

function sigmoid(x: number) {
  const v = 1 / (1 + Math.exp(-x));
  return Math.max(0, Math.min(1, v));
}

function isClassicIntent(text: string) {
  const t = normalizeUmlauts(text.toLowerCase());
  return /\b(classic|classics|must watch|essentials|goat|greatest|retro|old school|oldschool|vintage|80s|90s|klassiker|klassisch|meisterwerk|muss man gesehen haben|legendaer|legendaere)\b/i.test(t);
}

function isGatewayIntent(text: string) {
  const t = normalizeUmlauts(text.toLowerCase());
  return /\b(first anime|first manga|where do i start|getting into anime|getting into manga|neu bei anime|neu bei manga|anime anfangen|manga anfangen|erstes anime|erstes manga|womit anfangen|wo fange ich an)\b/i.test(t);
}

function isHiddenGemsIntent(text: string) {
  const t = normalizeUmlauts(text.toLowerCase());
  return /\b(hidden gem|hidden gems|underrated|less known|new to me|geheimtipp|unterschaetzt|unbekannt|wenig bekannt|insider)\b/i.test(t);
}

function mapStrongGenreToModeId(text: string, excludedGenres: string[] = []): string | null {
  const t = normalizeUmlauts(normalizeGermanVibeWords(text.toLowerCase()));
  const excl = new Set(excludedGenres.map((g) => g.toLowerCase()));
  // High-signal intent should win over generic genre words.
  // Structural intents (movie, short, no-isekai) are never blocked by genre exclusions.
  if (/\b(classic|classics|must watch|essentials|goat|greatest|retro|old school|oldschool|vintage|80s|90s|klassiker|klassisch|legendaer|meisterwerk)\b/.test(t)) return "classics_expanded";
  if (/\b(movie|movies|film|filme|movie night|feature film|standalone movie|filmabend|kinofilm)\b/.test(t)) return "movie_night";
  if (/\b(short|one season|quick watch|binge|one cour|12 ep|13 ep|eine staffel|1 staffel|kurze serie|kurz und gut)\b/.test(t)) return "short_one_season";
  if (/\b(no isekai|not isekai|ohne isekai|nicht isekai|non[- ]?isekai|kein isekai)\b/.test(t)) return "fantasy_non_isekai";
  // Special romance sub-genres (no dedicated mode, but we prefer serious romance over romcom).
  if (!excl.has("romance") && /\b(shounen ai|shonen ai)\b/.test(t)) return "romance_serious";
  // "Magical girl" / mahou shoujo shouldn't be treated as generic fantasy.
  if (/\b(mahou shoujo|magical girl)\b/.test(t)) return "premium_picks";
  if (!excl.has("isekai") && /\b(isekai|reincarnat|reborn|another world|truck[- ]?kun)\b/.test(t)) return "isekai";
  if (!excl.has("romance") && /\b(romcom|rom com|romantic comedy)\b/.test(t)) return "romcom";
  if (!excl.has("romance") && /\b(serious romance|romance drama|bittersweet|heartbreak|deep romance)\b/.test(t)) return "romance_serious";
  if (!excl.has("romance") && /\b(romance|love story|romantic)\b/.test(t)) return "romcom";
  // School/coming-of-age and shoujo/josei (after romance to avoid false positives).
  if (/\b(school anime|high school|coming of age|schule|jugend)\b/.test(t)) return "school_coming_of_age";
  if (/\b(shoujo|josei|for women|fuer frauen|maedchen)\b/.test(t)) return "shoujo_josei";
  // Specific genre modes (before generic action/comedy/fantasy).
  if (/\b(mecha|giant robot|gundam|evangelion)\b/.test(t)) return "mecha";
  if (/\b(mystery|detective|whodunit|krimi|detektiv)\b/.test(t)) return "mystery_detective";
  if (/\b(music anime|band anime|idol anime|musik anime)\b/.test(t)) return "music_performance";
  if (/\b(historical|samurai|period drama|medieval|historisch|mittelalter)\b/.test(t)) return "historical";
  if (!excl.has("action") && /\b(action)\b/.test(t)) return "premium_action";
  if (!excl.has("comedy") && /\b(comedy|funny|laugh)\b/.test(t)) return "premium_comedy_grownup";
  if (!excl.has("slice of life") && /\b(slice of life|cozy|comfort|chill|relax|gemuetlich|entspannend|wohlfuehl)\b/.test(t)) return "cozy_comfort";
  if (!excl.has("horror") && !excl.has("supernatural") && /\b(horror|scary|creepy|supernatural|ghost|demon|occult|vampire|zombie|gruselig|unheimlich|schaurig)\b/.test(t)) return "horror_supernatural";
  if (!excl.has("thriller") && !excl.has("psychological") && !excl.has("mystery") && /\b(thriller|psychological|mind[- ]?game|mystery|dark|serious)\b/.test(t)) return "dark_serious";
  if (!excl.has("sci-fi") && /\b(sci[- ]?fi|scifi|science fiction|cyberpunk|space opera|dystopian|futuristic|weltraum|zukunft)\b/.test(t)) return "scifi";
  if (!excl.has("sports") && /\b(sports?|soccer|basketball|volleyball|boxing|tennis|baseball|fussball)\b/.test(t)) return "sports";
  if (!excl.has("fantasy") && /\b(fantasy|magic)\b/.test(t)) return "fantasy_non_isekai";
  return null;
}

function normalizePromptForCache(text: string) {
  return normalizeText(text).slice(0, 220);
}

type RouterDecision = {
  primaryId: string;
  secondaryId: string;
  primaryConfidence: number;
  primaryReason: string;
  usedLLM: boolean;
  topScore: number;
};


function inferLanguage(text: string): "de" | "en" {
  const t = text.toLowerCase();
  // Minimal heuristic: just enough for DE narration.
  if (/\b(ich|habe|hab|schaue|gucke|sehe|lese|staffel|folge|kapitel|band|bitte|empfehl|vorschlagen|suchen|finden|zeig|such|importieren|eintragen|hinzuf(ü|ue)gen|aktualisieren)\b/.test(t)) return "de";
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

type SeedOverride = { mt: MediaType; mediaId: number; title: string };

function expandKnownAbbrevSeed(raw: string): string | null {
  const t = raw.trim();
  // Keep this small and high-signal; it only runs for bare/short prompts.
  const map: Record<string, string> = {
    aot: "Attack on Titan",
    hxh: "Hunter x Hunter",
    fmab: "Fullmetal Alchemist: Brotherhood",
    nge: "Neon Genesis Evangelion",
    eva: "Neon Genesis Evangelion",
    lotgh: "Legend of the Galactic Heroes",
    op: "One Piece",
  };
  const key = t.toLowerCase();
  return map[key] ?? null;
}

function inferBareSeedCandidate(text: string): string | null {
  const t = text.trim();
  if (!t) return null;
  // Avoid treating normal recommendation prompts as seeds.
  if (/\b(recommend|something|give me|suggest|looking for|i want|show me|find me)\b/i.test(t)) return null;
  // Limit to short queries: bare titles or abbreviations.
  const words = t.split(/\s+/).filter(Boolean);
  if (words.length === 0 || words.length > 5) return null;
  if (t.length > 40) return null;

  // Abbrev + optional year (e.g. "HxH 2011").
  const yearMatch = t.match(/\b(19|20)\d{2}\b/);
  const year = yearMatch ? yearMatch[0] : null;
  const tokenNoYear = year ? t.replace(year, "").trim() : t;
  const expanded = expandKnownAbbrevSeed(tokenNoYear);
  if (expanded) return year ? `${expanded} ${year}` : expanded;

  // Single/bare title candidate; verified against DB before use.
  return t;
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

function inferExcludedGenres(text: string): string[] {
  const excluded: string[] = [];
  const lower = text.toLowerCase();

  // Patterns: "no romance", "without harem", "not isekai", "minus comedy"
  // German: "kein romance", "keine comedy", "ohne harem"
  const negPatterns = [
    /\b(?:no|without|not|minus|keine?|ohne)\s+(\w+)/gi,
  ];

  const genreMap: Record<string, string> = {
    romance: "Romance",
    comedy: "Comedy",
    action: "Action",
    horror: "Horror",
    harem: "Harem",
    ecchi: "Ecchi",
    isekai: "Isekai",
    mecha: "Mecha",
    sports: "Sports",
    music: "Music",
    kids: "Kids",
    fantasy: "Fantasy",
    scifi: "Sci-Fi",
    "sci-fi": "Sci-Fi",
    drama: "Drama",
    thriller: "Thriller",
    mystery: "Mystery",
    supernatural: "Supernatural",
  };

  for (const pat of negPatterns) {
    pat.lastIndex = 0;
    let m;
    while ((m = pat.exec(lower)) !== null) {
      const mapped = genreMap[m[1].toLowerCase()];
      if (mapped && !excluded.includes(mapped)) excluded.push(mapped);
    }
  }

  return excluded;
}

/**
 * Unified constraint extraction from user text (EN + DE).
 * Produces structured constraints used by mode selection, rail filtering, and post-filtering.
 * Each detected constraint appends an explainable reason to `why`.
 */
function extractConstraints(text: string): UserConstraints {
  const t = text.toLowerCase();
  const tNorm = normalizeUmlauts(t);
  const why: string[] = [];

  // ── Genre/tag exclusions (extends inferExcludedGenres) ──
  const excluded_genres = inferExcludedGenres(text);
  for (const g of excluded_genres) {
    why.push(`Excluded genre: user excluded '${g}'`);
  }
  // Additional DE patterns: "nicht Isekai", "non-isekai"
  if (/\b(?:nicht|non)\s*[- ]?\s*isekai\b/i.test(tNorm) && !excluded_genres.includes("Isekai")) {
    excluded_genres.push("Isekai");
    why.push("Excluded genre: user excluded 'Isekai' (nicht/non pattern)");
  }

  // ── Format constraints ──
  let format: string | null = null;

  // Movie intent (EN + DE)
  if (/\b(movie|movies|film|filme|filmabend|kinofilm|feature film|standalone movie)\b/i.test(tNorm)) {
    format = "MOVIE";
    why.push("Format: user wants movies");
  }
  // One season / short series intent (EN + DE)
  else if (/\b(one season|eine staffel|1 staffel|single season|one cour|ein cour)\b/i.test(tNorm)) {
    format = "TV_SHORT_SERIES";  // sentinel: handled as max_episodes <= 13 below
    why.push("Format: user wants single-season / short series");
  }
  // Short / OVA / ONA intent (EN + DE)
  else if (/\b(short|kurz|ova|ona|special|kurzfilm)\b/i.test(tNorm) &&
           !/\b(short series|kurze serie)\b/i.test(tNorm)) {
    // Only match standalone "short" / "kurz", not "short series"
    if (/\b(ova)\b/i.test(tNorm)) {
      format = "OVA";
      why.push("Format: user wants OVA");
    } else if (/\b(ona)\b/i.test(tNorm)) {
      format = "ONA";
      why.push("Format: user wants ONA");
    } else {
      format = "SHORT_FORM"; // sentinel for ONA|OVA|SPECIAL
      why.push("Format: user wants short-form content");
    }
  }

  // ── Length constraints ──
  let max_episodes: number | null = null;
  let min_episodes: number | null = null;

  // "under X episodes" / "unter X Folgen" / "weniger als X Folgen" / "less than X episodes"
  const maxEpMatch = tNorm.match(/\b(?:under|unter|weniger als|less than|max|maximal|hoechstens|höchstens|bis zu)\s+(\d{1,4})\s*(?:episodes?|folgen?|eps?)\b/i);
  if (maxEpMatch) {
    max_episodes = parseInt(maxEpMatch[1], 10);
    why.push(`Length: max ${max_episodes} episodes`);
  }
  // "over X episodes" / "über X Folgen" / "mehr als X Folgen" / "more than X episodes"
  const minEpMatch = tNorm.match(/\b(?:over|ueber|über|mehr als|more than|min|mindestens|ab)\s+(\d{1,4})\s*(?:episodes?|folgen?|eps?)\b/i);
  if (minEpMatch) {
    min_episodes = parseInt(minEpMatch[1], 10);
    why.push(`Length: min ${min_episodes} episodes`);
  }
  // "long" / "lang" implies 50+ episodes
  if (!min_episodes && /\b(long anime|long series|langes anime|lange serie|lang|marathon)\b/i.test(tNorm)) {
    min_episodes = 50;
    why.push("Length: user wants long series (50+ episodes)");
  }

  // One-season sentinel: apply max_episodes if not already set
  if (format === "TV_SHORT_SERIES" && !max_episodes) {
    max_episodes = 13;
    format = null; // don't lock to a specific format, just limit episodes
  } else if (format === "TV_SHORT_SERIES") {
    format = null; // max_episodes already captures intent
  }

  // ── Year constraints ──
  let year_min: number | null = null;
  let year_max: number | null = null;
  const currentYear = new Date().getFullYear();

  // "from YYYY" / "ab YYYY" / "seit YYYY" / "after YYYY" / "nach YYYY"
  const yearMinMatch = tNorm.match(/\b(?:from|ab|seit|after|nach|starting|beginning)\s+((?:19|20)\d{2})\b/i);
  if (yearMinMatch) {
    year_min = parseInt(yearMinMatch[1], 10);
    why.push(`Year: from ${year_min} onward`);
  }
  // "before YYYY" / "vor YYYY" / "until YYYY" / "bis YYYY" (year context only)
  const yearMaxMatch = tNorm.match(/\b(?:before|vor|until|bis)\s+((?:19|20)\d{2})\b/i);
  if (yearMaxMatch) {
    year_max = parseInt(yearMaxMatch[1], 10);
    why.push(`Year: before ${year_max}`);
  }
  // "classic" / "Klassiker" → year_max: 2005
  if (!year_max && /\b(classic|klassiker|klassisch|retro|old school|oldschool|vintage)\b/i.test(tNorm)) {
    year_max = 2005;
    why.push("Year: classic era (pre-2005)");
  }
  // "new" / "neu" / "recent" / "aktuell" → year_min: current_year - 2
  if (!year_min && /\b(new|neu|recent|aktuell|neue|neues|neueste|latest|this season|diese saison)\b/i.test(tNorm)) {
    // Avoid false positives: "new to me" / "new to anime" is not a year filter
    if (!/\b(new to me|new to anime|new to manga|neu bei)\b/i.test(tNorm)) {
      year_min = currentYear - 2;
      why.push(`Year: recent (${year_min}+)`);
    }
  }
  // Decade mentions: "90s anime" / "80er" / "2000er"
  const decadeMatch = tNorm.match(/\b((?:19|20)?\d0)s?\s*(?:anime|manga)?\b/i) ??
                       tNorm.match(/\b((?:19|20)?\d0)er\b/i);
  if (decadeMatch && !year_min && !year_max) {
    let decade = parseInt(decadeMatch[1], 10);
    if (decade < 100) decade += decade >= 50 ? 1900 : 2000; // "90s" → 1990, "00s" → 2000
    if (decade >= 1960 && decade <= 2020) {
      year_min = decade;
      year_max = decade + 9;
      why.push(`Year: ${decade}s decade`);
    }
  }

  return { excluded_genres, format, max_episodes, min_episodes, year_min, year_max, why };
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

  const safeUserText = sanitizeForLLM(opts.userText);
  const user =
    opts.lang === "de"
      ? `User prompt: ${safeUserText}\n\nItems:\n${opts.items
          .map((it) => `- ${it.id}: ${it.title} (${it.year ?? "?"}) ${it.format ?? ""} [${it.signals.join(", ")}]`)
          .join("\n")}\n\nSchreibe pro Item genau einen kurzen, spoilerfreien Satz. Gib nur JSON zurück: {"blurbs":{"ANIME|123":"...", "MANGA|456":"..."}}`
      : `User prompt: ${safeUserText}\n\nItems:\n${opts.items
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

async function isFeatureFlagEnabledForUser(
  client: any,
  flagName: string,
  userId: string,
  market: string,
): Promise<boolean> {
  try {
    const { data, error } = await client
      .from("feature_flags")
      .select("enabled,rollout_percentage,target_markets")
      .eq("flag_name", flagName)
      .maybeSingle();
    if (error || !data) return false;

    const enabled = Boolean((data as any).enabled);
    if (!enabled) return false;

    const targetMarkets = Array.isArray((data as any).target_markets)
      ? (data as any).target_markets.map((x: any) => String(x).toUpperCase())
      : [];
    if (targetMarkets.length > 0 && !targetMarkets.includes("*") && !targetMarkets.includes(market.toUpperCase())) {
      return false;
    }

    const rollout = Number((data as any).rollout_percentage ?? 0);
    if (!Number.isFinite(rollout) || rollout <= 0) return false;
    if (rollout >= 100) return true;

    const bucket = stableBucket(`${userId}:${flagName}`);
    return bucket < rollout;
  } catch {
    return false;
  }
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

    // Auth + rate-limit in parallel (both use the same client).
    const ip = clientIp(req);
    const [rlResult, userResult] = await Promise.all([
      client.rpc("check_concierge_rate_limit", {
        p_kind: "recommend",
        p_ip: ip,
        p_window_seconds: null,
        p_max_user: null,
        p_max_ip: null,
      }),
      client.auth.getUser(),
    ]);

    const rl = rlResult.data;
    if (rl && rl.allowed === false) {
      return json(
        { error: "Rate limited", retry_after_s: rl.retry_after_s ?? 30 },
        { status: 429, headers: { "Retry-After": String(rl.retry_after_s ?? 30) } },
      );
    }

    const userData = userResult.data;
    const userErr = userResult.error;
    if (userErr || !userData?.user) return json({ error: "Unauthorized" }, { status: 401 });

    const body = await req.json().catch(() => ({}));
    const text: string = String(body?.text ?? "");
    const scope: string = String(body?.scope ?? "both");
    const limit = Math.max(3, Math.min(20, Number(body?.limit ?? 8)));
    let narrate: boolean = Boolean(body?.narrate ?? false);
    const debugNarration: boolean = Boolean(body?.debugNarration ?? false);

    const categories = inferCategories(text);
    const gimmickTagIds = inferGimmickTagIds(text);
    const requiredGenres = inferRequiredGenres(text);
    const constraints = extractConstraints(text);
    const userExcludedGenres = constraints.excluded_genres;
    const quality = inferQualityFloor(text);

    // Parallel fetch: config, tag mapping, and editorial boosts are independent.
    const allowGimmicks =
      gimmickTagIds.length > 0 || /\b(slime)\b/.test(text.toLowerCase());
    const lang = inferLanguage(text);
    const mediaType = inferMediaType(text, scope);
    let seedQuery = inferSeedQuery(text);
    let seedOverride: SeedOverride | null = null;

    const [
      { data: conciergeCfg },
      focusTagIds,
      { data: tagBoosts },
    ] = await Promise.all([
      client.rpc("get_concierge_config"),
      mapTagAnilistIdsToInternal(client, gimmickTagIds),
      client.from("editorial_tag_boosts").select("tag_id,boost,reason"),
    ]);

    const configuredModes = parseModesFromConfig(conciergeCfg);
    const modes = configuredModes.length ? configuredModes : defaultModes();
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

    type MediaContext = {
      byId: Map<number, any>;
      boostById: Map<number, any>;
      boostedReasonsById: Map<number, string[]>;
    };

    const fetchMediaContext = async (mt: MediaType, idList: number[]): Promise<MediaContext> => {
      const ids = uniq(idList).filter((x) => Number.isFinite(x) && x > 0);
      if (ids.length === 0) return { byId: new Map(), boostById: new Map(), boostedReasonsById: new Map() };

      const table = mt === "ANIME" ? "anime" : "manga";
      const linkTable = mt === "ANIME" ? "anime_tags" : "manga_tags";
      const idCol = mt === "ANIME" ? "anime_id" : "manga_id";
      const mediaSelect =
        mt === "ANIME"
          ? "id,title_english,title_romaji,title_native,cover_image_medium,average_score,popularity,start_date_year,format,status,site_url,is_adult,genres,episodes"
          : "id,title_english,title_romaji,title_native,cover_image_medium,average_score,popularity,start_date_year,format,status,site_url,is_adult,genres,chapters as episodes";

      // All three queries depend only on `ids` — run in parallel.
      const [mediaRes, boostsRes, tagLinksRes] = await Promise.all([
        client
          .from(table)
          .select(mediaSelect)
          .in("id", ids),
        client
          .from("editorial_boosts")
          .select("media_id,label,weight")
          .eq("media_type", mt)
          .in("media_id", ids),
        boostTagIds.length > 0
          ? client
              .from(linkTable)
              .select(`${idCol},tag_id`)
              .in(idCol, ids)
              .in("tag_id", boostTagIds)
          : Promise.resolve({ data: [] as any[], error: null }),
      ]);

      if (mediaRes.error) throw mediaRes.error;
      const byId = new Map<number, any>((mediaRes.data ?? []).map((r: any) => [r.id, r]));
      const boostById = new Map<number, any>((boostsRes.data ?? []).map((b: any) => [b.media_id, b]));
      const tagLinks = !tagLinksRes.error ? (tagLinksRes.data ?? []) : [];

      const boostedReasonsById = new Map<number, string[]>();
      for (const row of tagLinks) {
        const mediaId = Number(row[idCol]);
        const tagId = Number(row.tag_id);
        const tb = tagBoostByTag.get(tagId);
        const reason = String(tb?.reason ?? "").trim();
        if (!reason) continue;
        const arr = boostedReasonsById.get(mediaId) ?? [];
        if (!arr.includes(reason)) arr.push(reason);
        boostedReasonsById.set(mediaId, arr);
      }

      return { byId, boostById, boostedReasonsById };
    };

    const buildItemsFromRows = (mt: MediaType, rows: CandidateRow[], ctx: MediaContext, opts: {
      limit: number;
      requiredGenres: string[];
      excludeGenres: string[];
      classicYearMax?: number;
      quality: { minScore: number; minPopularity: number; maxPopularity: number | null; excludeFormats: Set<string> };
      prioritizeClassicBoost?: boolean;
      constraints?: UserConstraints;
    }) => {
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

      const uc = opts.constraints;

      const passes = (m: any) => {
        if (!m) return false;
        if (m.is_adult === true) return false;
        const fmt = String(m.format ?? "").toUpperCase();

        // Format constraint: if user wants MOVIE, only allow MOVIE format.
        if (uc?.format === "MOVIE" && fmt !== "MOVIE") return false;
        // Short-form: allow ONA, OVA, SPECIAL only.
        if (uc?.format === "SHORT_FORM" && !["ONA", "OVA", "SPECIAL"].includes(fmt)) return false;
        if (uc?.format === "OVA" && fmt !== "OVA") return false;
        if (uc?.format === "ONA" && fmt !== "ONA") return false;

        // Default format exclusions (unless overridden by constraint).
        if (!uc?.format && opts.quality.excludeFormats.has(fmt)) return false;
        if (hasExcludedGenres(m, opts.excludeGenres)) return false;

        const year = Number(m.start_date_year ?? 0);
        if (opts.classicYearMax && year > 0 && year > opts.classicYearMax) return false;
        // Year constraints from user.
        if (uc?.year_min != null && year > 0 && year < uc.year_min) return false;
        if (uc?.year_max != null && year > 0 && year > uc.year_max) return false;

        const score = Number(m.average_score ?? 0);
        const pop = Number(m.popularity ?? 0);
        if (opts.quality.minScore > 0 && score > 0 && score < opts.quality.minScore) return false;
        if (opts.quality.minPopularity > 0 && pop > 0 && pop < opts.quality.minPopularity) return false;
        if (opts.quality.maxPopularity != null && pop > 0 && pop > opts.quality.maxPopularity) return false;

        // Episode count constraints (anime only; manga uses chapters).
        if (mt === "ANIME") {
          const eps = Number(m.episodes ?? 0);
          if (uc?.max_episodes != null && eps > 0 && eps > uc.max_episodes) return false;
          if (uc?.min_episodes != null && eps > 0 && eps < uc.min_episodes) return false;
        }

        return true;
      };

      // Prefer: genre match + quality; then quality; then anything (no hard failures).
      const primary: CandidateRow[] = [];
      const secondary: CandidateRow[] = [];
      const tertiary: CandidateRow[] = [];

      for (const r of rows) {
        const m = ctx.byId.get(r.media_id);
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
          const b = ctx.boostById.get(r.media_id);
          if (b?.label === "classic") boosted.push(r);
          else rest.push(r);
        }
        ordered = [...boosted, ...rest];
      }
      ordered = ordered.slice(0, opts.limit);

      const out: any[] = [];
      for (const r of ordered) {
        const m = ctx.byId.get(r.media_id);
        if (!m) continue;
        const signals: string[] = [];
        const b = ctx.boostById.get(r.media_id);
        if (b?.label === "classic") signals.push("CLASSIC");
        const reasons = ctx.boostedReasonsById.get(r.media_id) ?? [];
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

    const modeById = new Map<string, ConciergeMode>(modes.map((m) => [m.id, m]));
    const classicsMode = modeById.get("classics_expanded") ?? Array.from(modeById.values()).find((m) => m.id.includes("classic")) ?? null;
    const premiumMode = modeById.get("premium_picks") ?? Array.from(modeById.values()).find((m) => m.id.includes("premium")) ?? null;

    const routerCfg = conciergeCfg?.router_llm ?? {};
    const cacheTtlDays = Number(routerCfg?.cache_ttl_days ?? 30);

    const userId = userData.user.id;
    const market = inferRequestMarket(req);
    const ragAssistEnabled = await isFeatureFlagEnabledForUser(client, "rag_assist_v1", userId, market);
    const promptNorm = normalizePromptForCache(text);

    const resolveSecondary = (primaryId: string) => {
      const classicsId = classicsMode?.id ?? "classics_expanded";
      if (primaryId === classicsId) return premiumMode?.id ?? "premium_picks";
      return classicsId;
    };

    const mkPick = (id: string, title: string, confidence: number, reason: string): ModePick => ({
      id,
      title,
      confidence: Math.max(0, Math.min(1, confidence)),
      reason,
    });

    const loadCache = async (): Promise<RouterDecision | null> => {
      if (!cacheTtlDays || cacheTtlDays <= 0) return null;
      const { data, error } = await client
        .from("concierge_mode_cache")
        .select("primary_mode_id,secondary_mode_id,used_llm,updated_at")
        .eq("user_id", userId)
        .eq("prompt_norm", promptNorm)
        .maybeSingle();
      if (error || !data) return null;
      const updatedAt = Date.parse(String((data as any).updated_at ?? ""));
      if (!Number.isFinite(updatedAt)) return null;
      const ageDays = (Date.now() - updatedAt) / (1000 * 60 * 60 * 24);
      if (ageDays > cacheTtlDays) return null;
      const primaryId = String((data as any).primary_mode_id ?? "").trim();
      const secondaryId = String((data as any).secondary_mode_id ?? "").trim();
      if (!primaryId || !secondaryId) return null;
      return {
        primaryId,
        secondaryId,
        primaryConfidence: 0.75,
        primaryReason: "cache",
        usedLLM: Boolean((data as any).used_llm ?? false),
        topScore: 999,
      };
    };

    const saveCache = async (dec: RouterDecision) => {
      if (!cacheTtlDays || cacheTtlDays <= 0) return;
      try {
        await client
          .from("concierge_mode_cache")
          .upsert(
            {
              user_id: userId,
              prompt_norm: promptNorm,
              primary_mode_id: dec.primaryId,
              secondary_mode_id: dec.secondaryId,
              used_llm: dec.usedLLM,
            },
            { onConflict: "user_id,prompt_norm" },
          );
      } catch {
        // best-effort
      }
    };

    const decideModes = async (): Promise<RouterDecision> => {
      const classicsId = classicsMode?.id ?? "classics_expanded";

      // Cache (prevents repeated LLM spend and stabilizes routing).
      const cached = await loadCache();
      if (cached) return cached;

      // Hard overrides (one-shot magic).
      if (seedQuery) {
        const secondaryId = resolveSecondary("similar_to_seed");
        const dec: RouterDecision = {
          primaryId: "similar_to_seed",
          secondaryId,
          primaryConfidence: 1,
          primaryReason: "seed similarity",
          usedLLM: false,
          topScore: 999,
        };
        await saveCache(dec);
        return dec;
      }

      // Bare-title seed: verify against DB first (prevents gibberish => empty Similar rail).
      const bareCandidate = inferBareSeedCandidate(text);
      if (bareCandidate) {
        const pickSeedVerified = async (mt: MediaType) => {
          const { data: seeds, error: seedErr } = await client.rpc("search_titles", {
            p_query: bareCandidate,
            p_media_type: mt,
            p_limit: 6,
          });
          if (seedErr || !Array.isArray(seeds) || seeds.length === 0) return null;
          const top = seeds[0];
          if ((top?.score ?? 0) < 0.45) return null;
          return { mt, mediaId: Number(top.media_id), title: String(top.title_raw ?? top.title ?? "").trim() };
        };

        const verified =
          mediaType === "MANGA" ? await pickSeedVerified("MANGA")
            : mediaType === "ANIME" ? await pickSeedVerified("ANIME")
            : (await pickSeedVerified("ANIME")) ?? (await pickSeedVerified("MANGA"));

        if (verified && Number.isFinite(verified.mediaId) && verified.mediaId > 0) {
          seedQuery = bareCandidate;
          seedOverride = verified;
          const secondaryId = resolveSecondary("similar_to_seed");
          const dec: RouterDecision = {
            primaryId: "similar_to_seed",
            secondaryId,
            primaryConfidence: 1,
            primaryReason: "bare title seed similarity",
            usedLLM: false,
            topScore: 999,
          };
          await saveCache(dec);
          return dec;
        }
      }

      if (isClassicIntent(text)) {
        const secondaryId = resolveSecondary(classicsId);
        const dec: RouterDecision = {
          primaryId: classicsId,
          secondaryId,
          primaryConfidence: 1,
          primaryReason: "classic intent",
          usedLLM: false,
          topScore: 999,
        };
        await saveCache(dec);
        return dec;
      }
      if (isGatewayIntent(text)) {
        const primaryId = modeById.has("gateway_start_here") ? "gateway_start_here" : (premiumMode?.id ?? "premium_picks");
        const secondaryId = resolveSecondary(primaryId);
        const dec: RouterDecision = {
          primaryId,
          secondaryId,
          primaryConfidence: 1,
          primaryReason: "start here intent",
          usedLLM: false,
          topScore: 999,
        };
        await saveCache(dec);
        return dec;
      }
      if (isHiddenGemsIntent(text)) {
        const primaryId = modeById.has("hidden_gems") ? "hidden_gems" : (premiumMode?.id ?? "premium_picks");
        const secondaryId = resolveSecondary(primaryId);
        const dec: RouterDecision = {
          primaryId,
          secondaryId,
          primaryConfidence: 1,
          primaryReason: "hidden gems intent",
          usedLLM: false,
          topScore: 999,
        };
        await saveCache(dec);
        return dec;
      }
      const genreMapped = mapStrongGenreToModeId(text, userExcludedGenres);
      if (genreMapped && modeById.has(genreMapped)) {
        const secondaryId = resolveSecondary(genreMapped);
        const dec: RouterDecision = {
          primaryId: genreMapped,
          secondaryId,
          primaryConfidence: 0.9,
          primaryReason: "strong genre signal",
          usedLLM: false,
          topScore: 999,
        };
        await saveCache(dec);
        return dec;
      }

      // Deterministic scoring (fallback).
      const candidates = Array.from(modeById.values()).filter((m) => m.id !== classicsId);
      const scored = candidates.map((m) => {
        const s = scoreMode(text, m, requiredGenres, userExcludedGenres, constraints);
        let score = s.score;
        // Tie-breaker so vague prompts don't pick random modes.
        if (m.id === "premium_picks") score += 1;
        return { mode: m, score, reason: s.reason };
      }).sort((a, b) => b.score - a.score);

      const top = scored[0] ?? null;
      const runner = scored[1] ?? null;
      const topId = top?.mode?.id ?? (premiumMode?.id ?? "premium_picks");
      const topScore = Number(top?.score ?? 0);
      const delta = Number(top?.score ?? 0) - Number(runner?.score ?? 0);
      const primaryConfidence = sigmoid(delta - 1);
      const primaryReason = top?.reason ?? "scored";

      const secondaryId = resolveSecondary(topId);
      const dec: RouterDecision = {
        primaryId: topId,
        secondaryId,
        primaryConfidence,
        primaryReason,
        usedLLM: false,
        topScore,
      };
      await saveCache(dec);
      return dec;
    };

    const decision = await decideModes();

    const modePicks: ModePick[] = [];
    const primaryModeTitle = decision.primaryId === "similar_to_seed"
      ? "Similar to your seed"
      : (modeById.get(decision.primaryId)?.title ?? decision.primaryId);
    modePicks.push(mkPick(decision.primaryId, primaryModeTitle, decision.primaryConfidence, decision.primaryReason));
    const secondaryTitle = modeById.get(decision.secondaryId)?.title ?? decision.secondaryId;
    modePicks.push(mkPick(decision.secondaryId, secondaryTitle, 1, "anchor rail"));

    const perTypeLimit = (total: number) => mediaType === "BOTH" ? Math.max(3, Math.ceil(total / 2)) : total;

    const mapCuratedRowToItem = (row: any) => {
      const mt = String(row?.media_type ?? row?.mediaType ?? "").toUpperCase();
      const mediaTypeOut = mt === "MANGA" ? "MANGA" : "ANIME";
      const mediaId = Number(row?.media_id ?? row?.mediaId ?? 0);
      const title = row?.title_english ?? row?.title_romaji ?? row?.title_native ?? "Unknown";
      return {
        mediaType: mediaTypeOut,
        mediaId,
        matchCount: null,
        score: null,
        title,
        coverImageMedium: row?.cover_image_medium ?? row?.coverImageMedium ?? null,
        averageScore: row?.average_score ?? row?.averageScore ?? null,
        year: row?.year ?? null,
        format: row?.format ?? null,
        status: row?.status ?? null,
        siteUrl: row?.site_url ?? row?.siteUrl ?? null,
        signals: Array.isArray(row?.signals) ? row.signals : [],
        genres: Array.isArray(row?.genres) ? row.genres : null,
      };
    };

    const railIdFor = (mode: ConciergeMode | null, mt: MediaType): string | null => {
      if (!mode?.rail_id) return null;
      if (typeof mode.rail_id === "string") return mode.rail_id;
      const both = mode.rail_id.both;
      if (both) return both;
      return mt === "ANIME" ? (mode.rail_id.anime ?? null) : (mode.rail_id.manga ?? null);
    };

    const filterByConstraints = (items: any[]) => {
      return items.filter((it) => {
        // Genre exclusion.
        if (userExcludedGenres.length) {
          const gs = Array.isArray(it.genres) ? it.genres.map((g: any) => String(g)) : [];
          if (userExcludedGenres.some((eg) => gs.includes(eg))) return false;
        }
        // Format constraint.
        const fmt = String(it.format ?? "").toUpperCase();
        if (constraints.format === "MOVIE" && fmt !== "MOVIE") return false;
        if (constraints.format === "SHORT_FORM" && !["ONA", "OVA", "SPECIAL"].includes(fmt)) return false;
        if (constraints.format === "OVA" && fmt !== "OVA") return false;
        if (constraints.format === "ONA" && fmt !== "ONA") return false;
        // Year constraints.
        const year = Number(it.year ?? 0);
        if (constraints.year_min != null && year > 0 && year < constraints.year_min) return false;
        if (constraints.year_max != null && year > 0 && year > constraints.year_max) return false;
        return true;
      });
    };

    const fetchCurated = async (mode: ConciergeMode, total: number) => {
      // Fetch extra to compensate for post-filtering by user constraints.
      const hasActiveConstraints = userExcludedGenres.length > 0 || constraints.format != null || constraints.year_min != null || constraints.year_max != null;
      const fetchLimit = hasActiveConstraints ? total + 20 : total;
      const perType = perTypeLimit(fetchLimit);
      const animeRid = railIdFor(mode, "ANIME");
      const mangaRid = railIdFor(mode, "MANGA");
      const [animeRows, mangaRows] = await Promise.all([
        (mediaType === "ANIME" || mediaType === "BOTH") && animeRid
          ? client.rpc("curated_rail_cards", { p_rail_id: animeRid, p_limit: perType, p_exclude_seen: true }).then((r) => r.data)
          : [],
        (mediaType === "MANGA" || mediaType === "BOTH") && mangaRid
          ? client.rpc("curated_rail_cards", { p_rail_id: mangaRid, p_limit: perType, p_exclude_seen: true }).then((r) => r.data)
          : [],
      ]);
      const a = filterByConstraints(Array.isArray(animeRows) ? animeRows.map(mapCuratedRowToItem) : []);
      const m = filterByConstraints(Array.isArray(mangaRows) ? mangaRows.map(mapCuratedRowToItem) : []);
      const merged = mediaType === "BOTH" ? mergeAlternating(a, m, total) : [...a, ...m].slice(0, total);
      return merged;
    };

    let ragAssistUsed = false;
    let ragSeedEntityId: string | null = null;

    const fetchSeedFromRag = async (): Promise<{ mt: MediaType; mediaId: number; title: string; entityId: string | null } | null> => {
      if (!ragAssistEnabled || !seedQuery) return null;

      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 5000);
      const ragFormat =
        constraints.format === "MOVIE" || constraints.format === "ONA" || constraints.format === "OVA"
          ? constraints.format
          : null;

      try {
        const ragUrl = `${supabaseUrl}/functions/v1/concierge-retrieve-assist`;
        const res = await fetch(ragUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            ...(authHeader ? { Authorization: authHeader } : {}),
          },
          body: JSON.stringify({
            query: seedQuery,
            locale: lang,
            media_type: mediaType === "BOTH" ? null : mediaType,
            excluded_genres: userExcludedGenres,
            format: ragFormat,
            year_min: constraints.year_min,
            year_max: constraints.year_max,
          }),
          signal: controller.signal,
        });
        if (!res.ok) return null;
        const payload = await res.json().catch(() => null);
        const candidates = Array.isArray(payload?.entity_candidates) ? payload.entity_candidates : [];
        const top = candidates[0];
        if (!top) return null;

        const mt = String(top.media_type ?? "").toUpperCase();
        const mediaId = Number(top.anilist_id ?? 0);
        const score = Number(top.score ?? 0);
        const title = String(top.title ?? "").trim();
        const entityId = typeof top.entity_id === "string" ? top.entity_id : null;
        if (!Number.isFinite(mediaId) || mediaId <= 0) return null;
        if (score < 0.45) return null;
        if (mt !== "ANIME" && mt !== "MANGA") return null;

        ragAssistUsed = true;
        ragSeedEntityId = entityId;
        return { mt, mediaId, title: title || seedQuery, entityId };
      } catch {
        return null;
      } finally {
        clearTimeout(timeout);
      }
    };

    const buildSimilarToSeedRail = async (total: number) => {
      // Only build when we have a decent seed title.
      const pickSeed = async (mt: MediaType) => {
        const { data: seeds, error: seedErr } = await client.rpc("search_titles", {
          p_query: seedQuery,
          p_media_type: mt,
          p_limit: 6,
        });
        if (seedErr || !Array.isArray(seeds) || seeds.length === 0) return null;
        const top = seeds[0];
        if ((top?.score ?? 0) < 0.35) return null;
        return { mt, mediaId: Number(top.media_id), title: String(top.title_raw ?? top.title ?? "").trim() };
      };

      const seed = seedOverride
        ? seedOverride
        : mediaType === "MANGA" ? await pickSeed("MANGA")
        : mediaType === "ANIME" ? await pickSeed("ANIME")
        : (await pickSeed("ANIME")) ?? (await pickSeed("MANGA"));
      const ragSeed = (!seed || !Number.isFinite(seed.mediaId) || seed.mediaId <= 0)
        ? await fetchSeedFromRag()
        : null;
      if (ragSeed) {
        seedOverride = { mt: ragSeed.mt, mediaId: ragSeed.mediaId, title: ragSeed.title };
      }
      const effectiveSeed = seedOverride ?? seed;
      if (!effectiveSeed || !Number.isFinite(effectiveSeed.mediaId) || effectiveSeed.mediaId <= 0) {
        return { title: "Similar", items: [] as any[] };
      }

      const perType = perTypeLimit(total);
      const q = compileQuality(null);
      const getSim = async (mt: MediaType) => {
        const { data: sim, error: simErr } = await client.rpc("recommend_ids_similar_to_seeds", {
          p_media_type: mt,
          p_seed_ids: [effectiveSeed.mediaId],
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

      const [animeRows, mangaRows] = await Promise.all([
        (mediaType === "ANIME" || mediaType === "BOTH") ? getSim("ANIME") : [],
        (mediaType === "MANGA" || mediaType === "BOTH") ? getSim("MANGA") : [],
      ]);
      const emptyCtx: MediaContext = { byId: new Map(), boostById: new Map(), boostedReasonsById: new Map() };
      const [simCtxAnime, simCtxManga] = await Promise.all([
        (mediaType === "ANIME" || mediaType === "BOTH")
          ? fetchMediaContext("ANIME", animeRows.map((r) => r.media_id))
          : emptyCtx,
        (mediaType === "MANGA" || mediaType === "BOTH")
          ? fetchMediaContext("MANGA", mangaRows.map((r) => r.media_id))
          : emptyCtx,
      ]);

      const a = (mediaType === "ANIME" || mediaType === "BOTH")
        ? buildItemsFromRows("ANIME", animeRows, simCtxAnime, { limit: perType, requiredGenres, excludeGenres: userExcludedGenres, quality: q, constraints })
        : [];
      const m = (mediaType === "MANGA" || mediaType === "BOTH")
        ? buildItemsFromRows("MANGA", mangaRows, simCtxManga, { limit: perType, requiredGenres, excludeGenres: userExcludedGenres, quality: q, constraints })
        : [];

      const merged = mediaType === "BOTH" ? mergeAlternating(a, m, total) : [...a, ...m].slice(0, total);
      const title = effectiveSeed.title || seedQuery || "seed";
      return { title: `Similar to "${title}"`, items: merged };
    };

    const buildAlgorithmicRail = async (mode: ConciergeMode | null, total: number) => {
      const perType = perTypeLimit(total);
      const modeRequired = uniq([...(mode?.required_genres ?? []), ...requiredGenres]);
      const modeExcluded = uniq([...(mode?.exclude_genres ?? []), ...userExcludedGenres]);
      const q = compileQuality(mode);
      const pCats = uniq([...categories, ...(mode?.required_genres ?? [])]);
      const cats = pCats.length ? pCats : (categories.length ? categories : null);

      const [animeRows, mangaRows] = await Promise.all([
        (mediaType === "ANIME" || mediaType === "BOTH") ? getPremiumCandidates("ANIME", cats) : [],
        (mediaType === "MANGA" || mediaType === "BOTH") ? getPremiumCandidates("MANGA", cats) : [],
      ]);
      const emptyCtx: MediaContext = { byId: new Map(), boostById: new Map(), boostedReasonsById: new Map() };
      const [ctxAnime, ctxManga] = await Promise.all([
        (mediaType === "ANIME" || mediaType === "BOTH")
          ? fetchMediaContext("ANIME", animeRows.map((r) => r.media_id))
          : emptyCtx,
        (mediaType === "MANGA" || mediaType === "BOTH")
          ? fetchMediaContext("MANGA", mangaRows.map((r) => r.media_id))
          : emptyCtx,
      ]);

      const a = (mediaType === "ANIME" || mediaType === "BOTH")
        ? buildItemsFromRows("ANIME", animeRows, ctxAnime, {
          limit: perType,
          requiredGenres: modeRequired,
          excludeGenres: modeExcluded,
          classicYearMax: mode?.classic_year_max,
          quality: q,
          prioritizeClassicBoost: (mode?.id ?? "").includes("classic"),
          constraints,
        })
        : [];
      const m = (mediaType === "MANGA" || mediaType === "BOTH")
        ? buildItemsFromRows("MANGA", mangaRows, ctxManga, {
          limit: perType,
          requiredGenres: modeRequired,
          excludeGenres: modeExcluded,
          classicYearMax: mode?.classic_year_max,
          quality: q,
          prioritizeClassicBoost: (mode?.id ?? "").includes("classic"),
          constraints,
        })
        : [];
      return mediaType === "BOTH" ? mergeAlternating(a, m, total) : [...a, ...m].slice(0, total);
    };

    const buildRailItems = async (modeId: string, total: number) => {
      if (modeId === "similar_to_seed") {
        return await buildSimilarToSeedRail(total);
      }
      const mode = modeById.get(modeId) ?? null;
      // Curated rail if configured; fall back to algorithmic if empty/unavailable.
      // If curated returns fewer than requested, fill the remainder algorithmically (still one-shot).
      if (mode?.rail_id) {
        try {
          const curated = await fetchCurated(mode, total);
          if (curated.length > 0) {
            if (curated.length >= total) return { title: mode.title, items: curated.slice(0, total) };

            const algo = await buildAlgorithmicRail(mode, total);
            const seen = new Set(curated.map((it: any) => `${it.mediaType}|${it.mediaId}`));
            const filled = [...curated];
            for (const it of algo) {
              if (filled.length >= total) break;
              const k = `${it.mediaType}|${it.mediaId}`;
              if (seen.has(k)) continue;
              seen.add(k);
              filled.push(it);
            }
            return { title: mode.title, items: filled };
          }
        } catch {
          // ignore
        }
      }
      const items = await buildAlgorithmicRail(mode, total);
      return { title: mode?.title ?? modeId, items };
    };

    // Exactly 2 rails: primary + classics anchor (unless primary is classics, then secondary becomes premium picks).
    const primaryTotal = limit;
    const classicsTotal = Math.min(20, Math.max(limit, 14));
    const [primaryBuilt, secondaryBuilt] = await Promise.all([
      buildRailItems(decision.primaryId, primaryTotal),
      buildRailItems(decision.secondaryId, classicsTotal),
    ]);

    const sets: any[] = [
      {
        id: decision.primaryId,
        title: primaryBuilt.title,
        modeId: decision.primaryId,
        confidence: modePicks[0].confidence,
        reason: modePicks[0].reason,
        items: primaryBuilt.items,
      },
      {
        id: decision.secondaryId,
        title: secondaryBuilt.title,
        modeId: decision.secondaryId,
        confidence: 1,
        reason: "anchor rail",
        items: secondaryBuilt.items,
      },
    ];

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
      // Constraint info for WhyThisSheet and debugging.
      constraints: constraints.why.length > 0 ? {
        excluded_genres: constraints.excluded_genres.length > 0 ? constraints.excluded_genres : undefined,
        format: constraints.format ?? undefined,
        max_episodes: constraints.max_episodes ?? undefined,
        min_episodes: constraints.min_episodes ?? undefined,
        year_min: constraints.year_min ?? undefined,
        year_max: constraints.year_max ?? undefined,
        why: constraints.why,
      } : undefined,
      assist: ragAssistEnabled
        ? {
          ragUsed: ragAssistUsed,
          seedEntityId: ragSeedEntityId ?? undefined,
        }
        : undefined,
      ...(debugNarration ? { narrationError } : {}),
    });
  } catch (e) {
    const err = e as Error;
    return json({ error: "Internal error", message: err?.message ?? String(e) }, { status: 500 });
  }
});
