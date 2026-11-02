// Pure routing / classification rules of concierge-recommend.
//
// Extracted MECHANICALLY from index.ts (2026-10-05, E7): every function, constant and
// type below is the production code moved verbatim with an `export` keyword added, plus
// `anchorModes` / `routePrimaryMode`, which are the former `decideModes` primary chain
// (seed -> DB-verified bare title -> classic -> gateway -> hidden gems -> strong genre ->
// scored fallback) with the `search_titles` RPC injected as a port.
//
// No imports and no I/O: handler.ts (behind the deployed index.ts) and the Deno tests import the
// SAME code, so the offline router gate executes production rules instead of a copy.
// Groq is never used here: routing is deterministic (narration lives in narration.ts).
// F28 (2026-10-05): GERMAN_VIBE_FORMS gained the schaurig forms and two romantisch forms, and the
// romance strong-genre rule accepts the German base form `romantisch`.

export type MediaType = "ANIME" | "MANGA";

export type ConciergeMode = {
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

export type UserConstraints = {
  excluded_genres: string[];
  format: string | null;       // "MOVIE" | "SHORT_FORM" | "ONA" | "OVA" | null
  max_episodes: number | null;
  min_episodes: number | null;
  year_min: number | null;
  year_max: number | null;
  why: string[];
};

// Penalties for known weak/sparse mode inventories.
// Keeps routing deterministic while reducing accidental selection of weaker rails
// unless user intent is explicit.
export const MODE_HEALTH_PENALTIES: Record<string, number> = {
  historical: 2.8,
  mecha: 2.6,
  school_coming_of_age: 2.4,
  shoujo_josei: 2.2,
  mystery_detective: 1.4,
  music_performance: 1.2,
};

export function uniq<T>(arr: T[]) {
  return Array.from(new Set(arr));
}

export function safeStringArray(v: unknown): string[] {
  if (!Array.isArray(v)) return [];
  return uniq(
    v
      .map((x) => (typeof x === "string" ? x.trim() : ""))
      .filter((x) => x.length > 0),
  );
}

export function safeNumber(v: unknown): number | null {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : null;
}

export function normalizeText(s: string): string {
  return s
    .toLowerCase()
    .replace(/[_/\\-]+/g, " ")
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

export function parseModesFromConfig(cfg: any): ConciergeMode[] {
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

export function defaultModes(): ConciergeMode[] {
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

export const GERMAN_VIBE_FORMS: Record<string, string> = {
  "düsteres": "düster", "düstere": "düster", "düsterem": "düster", "düsterer": "düster", "düsteren": "düster",
  "lustiges": "lustig", "lustige": "lustig", "lustigem": "lustig", "lustiger": "lustig", "lustigen": "lustig",
  "gemütliches": "gemütlich", "gemütliche": "gemütlich", "gemütlichem": "gemütlich",
  "ernstes": "ernst", "ernste": "ernst", "ernstem": "ernst", "ernster": "ernst",
  "gruseliges": "gruselig", "gruselige": "gruselig", "gruseligem": "gruselig",
  "romantisches": "romantisch", "romantische": "romantisch", "romantischem": "romantisch", "romantischer": "romantisch", "romantischen": "romantisch",
  "historisches": "historisch", "historische": "historisch", "historischem": "historisch",
  "witziges": "witzig", "witzige": "witzig", "witzigem": "witzig",
  "entspannendes": "entspannend", "entspannende": "entspannend",
  "unheimliches": "unheimlich", "unheimliche": "unheimlich",
  "legendäres": "legendär", "legendäre": "legendär",
  "übernatürliches": "übernatürlich", "übernatürliche": "übernatürlich",
  // F28 (router_de_029): 'schaurig' was in the horror rules but none of its inflections were folded.
  "schauriges": "schaurig", "schaurige": "schaurig", "schaurigem": "schaurig", "schauriger": "schaurig", "schaurigen": "schaurig",
};

export function normalizeUmlauts(s: string): string {
  return s.replace(/ü/g, "ue").replace(/ö/g, "oe").replace(/ä/g, "ae").replace(/ß/g, "ss")
          .replace(/Ü/g, "Ue").replace(/Ö/g, "Oe").replace(/Ä/g, "Ae");
}

export function normalizeGermanVibeWords(text: string): string {
  let result = text.toLowerCase();
  for (const [inflected, base] of Object.entries(GERMAN_VIBE_FORMS)) {
    result = result.replace(new RegExp(`\\b${inflected}\\b`, "g"), base);
  }
  return result;
}

export function scoreMode(text: string, mode: ConciergeMode, inferredGenres: string[], excludedGenres: string[] = [], userConstraints?: UserConstraints): { score: number; reason: string } {
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

  // Quality guardrail: down-weight known weak/sparse mode inventories when
  // the prompt signal is weak. Explicit intent still wins.
  const healthPenalty = MODE_HEALTH_PENALTIES[mode.id] ?? 0;
  if (healthPenalty > 0) {
    if (score < 3) {
      score -= healthPenalty;
      if (!reason) reason = "quality safeguard";
    } else if (score < 5) {
      score -= Math.min(1.5, healthPenalty * 0.35);
    }
  }

  return { score, reason: reason || "default" };
}

export function sigmoid(x: number) {
  const v = 1 / (1 + Math.exp(-x));
  return Math.max(0, Math.min(1, v));
}

export function isClassicIntent(text: string) {
  const t = normalizeUmlauts(text.toLowerCase());
  return /\b(classic|classics|must watch|essentials|goat|greatest|retro|old school|oldschool|vintage|80s|90s|klassiker|klassisch|meisterwerk|muss man gesehen haben|legendaer|legendaere)\b/i.test(t);
}

export function isGatewayIntent(text: string) {
  const t = normalizeUmlauts(text.toLowerCase());
  return /\b(first anime|first manga|where do i start|getting into anime|getting into manga|neu bei anime|neu bei manga|anime anfangen|manga anfangen|erstes anime|erstes manga|womit anfangen|wo fange ich an)\b/i.test(t);
}

export function isHiddenGemsIntent(text: string) {
  const t = normalizeUmlauts(text.toLowerCase());
  return /\b(hidden gem|hidden gems|underrated|less known|new to me|geheimtipp|unterschaetzt|unbekannt|wenig bekannt|insider)\b/i.test(t);
}

export function mapStrongGenreToModeId(text: string, excludedGenres: string[] = []): string | null {
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
  // F28 (router_de_005): German 'romantisch' (inflections folded above) routes like English 'romantic'.
  if (!excl.has("romance") && /\b(romance|love story|romantic|romantisch)\b/.test(t)) return "romcom";
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

export function normalizePromptForCache(text: string) {
  return normalizeText(text).slice(0, 220);
}

export function inferLanguage(text: string): "de" | "en" {
  const t = text.toLowerCase();
  // Minimal heuristic: just enough for DE narration.
  if (/\b(ich|habe|hab|schaue|gucke|sehe|lese|staffel|folge|kapitel|band|bitte|empfehl|vorschlagen|suchen|finden|zeig|such|importieren|eintragen|hinzuf(ü|ue)gen|aktualisieren)\b/.test(t)) return "de";
  if (/[äöüß]/i.test(t)) return "de";
  return "en";
}

export function inferMediaType(text: string, scope: string): MediaType | "BOTH" {
  const s = (scope || "").toLowerCase();
  if (s === "anime") return "ANIME";
  if (s === "manga") return "MANGA";
  const t = text.toLowerCase();
  if (/\b(manga|manhwa|manhua)\b/.test(t)) return "MANGA";
  if (/\b(anime)\b/.test(t)) return "ANIME";
  return "BOTH";
}

export function inferSeedQuery(text: string): string | null {
  const t = text.trim();
  const m1 = t.match(/\b(?:like|similar to)\s+(.+?)(?:[.?!]|$)/i);
  if (m1?.[1]) return m1[1].trim().replace(/^["']|["']$/g, "");
  return null;
}

export type SeedOverride = { mt: MediaType; mediaId: number; title: string };

export function expandKnownAbbrevSeed(raw: string): string | null {
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

export function inferBareSeedCandidate(text: string): string | null {
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

export function inferCategories(text: string): string[] {
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

export function inferGimmickTagIds(text: string): number[] {
  const t = text.toLowerCase();
  const ids: number[] = [];
  if (/\b(isekai)\b/.test(t)) ids.push(350);
  if (/\b(reincarnat|reborn|tensei|wiedergeboren|reinkarnat)\b/.test(t)) ids.push(1023);
  if (/\b(another world|in another world|isekai)\b/.test(t)) ids.push(350);
  if (/\b(slime)\b/.test(t)) ids.push(350, 1023);
  if (/\b(harem)\b/.test(t)) ids.push(358, 9154, 18064);
  return uniq(ids);
}

export function inferRequiredGenres(text: string): string[] {
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

export function inferExcludedGenres(text: string): string[] {
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
export function extractConstraints(text: string): UserConstraints {
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

export function inferQualityFloor(text: string): { minScore: number; minPopularity: number; excludeFormats: Set<string> } {
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

/** `search_titles` RPC port: handler.ts passes `repo.searchTitles(query, mt, 6)` (the `search_titles` RPC, `p_limit: 6`). */
// deno-lint-ignore no-explicit-any
export type SearchTitlesPort = (query: string, mt: MediaType) => PromiseLike<{ data: any; error: any }>;

/** Classics / premium anchor modes, resolved exactly as the handler always did. */
export function anchorModes(modeById: Map<string, ConciergeMode>): { classicsMode: ConciergeMode | null; premiumMode: ConciergeMode | null } {
  const classicsMode = modeById.get("classics_expanded") ?? Array.from(modeById.values()).find((m) => m.id.includes("classic")) ?? null;
  const premiumMode = modeById.get("premium_picks") ?? Array.from(modeById.values()).find((m) => m.id.includes("premium")) ?? null;
  return { classicsMode, premiumMode };
}

export type PrimaryRoute = {
  primaryId: string;
  primaryConfidence: number;
  primaryReason: string;
  topScore: number;
  /** Set only when the DB-verified bare-title path fired; the handler adopts it as its seed. */
  bareSeed: { query: string; override: SeedOverride } | null;
};

export type PrimaryRouteInput = {
  text: string;
  /** inferSeedQuery(text) as computed by the handler. */
  seedQuery: string | null;
  mediaType: MediaType | "BOTH";
  modeById: Map<string, ConciergeMode>;
  /** classicsMode?.id ?? "classics_expanded" */
  classicsId: string;
  /** premiumMode?.id (undefined when no premium mode is configured). */
  premiumId: string | undefined;
  requiredGenres: string[];
  /** constraints.excluded_genres (derived from the prompt text, never from the request body). */
  userExcludedGenres: string[];
  constraints: UserConstraints;
};

/**
 * Primary-mode decision chain (former body of `decideModes` after the cache lookup).
 * Deterministic; the only external input is the injected `search_titles` port used to
 * verify bare-title seeds (score >= 0.45; ANIME then MANGA when the scope is BOTH).
 */
export async function routePrimaryMode(input: PrimaryRouteInput, searchTitles: SearchTitlesPort): Promise<PrimaryRoute> {
  const { text, seedQuery, mediaType, modeById, classicsId, premiumId, requiredGenres, userExcludedGenres, constraints } = input;
  const route = (primaryId: string, primaryConfidence: number, primaryReason: string, topScore: number): PrimaryRoute => ({
    primaryId,
    primaryConfidence,
    primaryReason,
    topScore,
    bareSeed: null,
  });

  // Hard overrides (one-shot magic).
  if (seedQuery) {
    return route("similar_to_seed", 1, "seed similarity", 999);
  }

  // Bare-title seed: verify against DB first (prevents gibberish => empty Similar rail).
  const bareCandidate = inferBareSeedCandidate(text);
  if (bareCandidate) {
    const pickSeedVerified = async (mt: MediaType) => {
      const { data: seeds, error: seedErr } = await searchTitles(bareCandidate, mt);
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
      return { ...route("similar_to_seed", 1, "bare title seed similarity", 999), bareSeed: { query: bareCandidate, override: verified } };
    }
  }

  if (isClassicIntent(text)) {
    return route(classicsId, 1, "classic intent", 999);
  }
  if (isGatewayIntent(text)) {
    const primaryId = modeById.has("gateway_start_here") ? "gateway_start_here" : (premiumId ?? "premium_picks");
    return route(primaryId, 1, "start here intent", 999);
  }
  if (isHiddenGemsIntent(text)) {
    const primaryId = modeById.has("hidden_gems") ? "hidden_gems" : (premiumId ?? "premium_picks");
    return route(primaryId, 1, "hidden gems intent", 999);
  }
  const genreMapped = mapStrongGenreToModeId(text, userExcludedGenres);
  if (genreMapped && modeById.has(genreMapped)) {
    return route(genreMapped, 0.9, "strong genre signal", 999);
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
  const topId = top?.mode?.id ?? (premiumId ?? "premium_picks");
  const topScore = Number(top?.score ?? 0);
  const delta = Number(top?.score ?? 0) - Number(runner?.score ?? 0);
  const primaryConfidence = sigmoid(delta - 1);
  const primaryReason = top?.reason ?? "scored";

  return route(topId, primaryConfidence, primaryReason, topScore);
}
