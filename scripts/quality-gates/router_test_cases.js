/*
  Offline router cases (DATA ONLY) for the concierge-recommend router.

  Until 2026-10-05 this file also contained a hand-maintained COPY of the routing
  functions (and a hand-written routeOffline chain) that had drifted from production
  (22 German alternatives missing, gateway/classic order swapped, scoreMode never run).
  The copy was removed. The cases below are now executed against the REAL production
  rules by supabase/functions/concierge-recommend/router_test.ts, which imports
  supabase/functions/concierge-recommend/router.ts (the module index.ts deploys).

  Run: bash scripts/quality-gates/test_router_offline.sh

  `excludedGenres`: production never receives exclusions from the client; it derives
  them from the prompt (extractConstraints). The test asserts that the production
  derivation yields at least these genres, then routes the prompt text alone.

  File name is kept stable: .githooks/pre-commit and check_secrets.sh whitelist it.
*/

export const ROUTER_OFFLINE_CASES = [
  // --- English vibes ---
  { prompt: "recommend something", expected: "premium_picks", note: "vague -> fallback" },
  { prompt: "surprise me with anything good", expected: "premium_picks", note: "vague quality request" },
  { prompt: "what should i watch", expected: "premium_picks", note: "vague intent" },
  { prompt: "best action anime", expected: "premium_action", note: "strong genre: action" },
  { prompt: "hype action with epic fights", expected: "premium_action", note: "action keyword" },
  { prompt: "funny anime comedy", expected: "premium_comedy_grownup", note: "strong genre: comedy" },
  { prompt: "cozy anime for a rainy day", expected: "cozy_comfort", note: "cozy keyword" },
  { prompt: "something chill and relaxing", expected: "cozy_comfort", note: "chill + relax" },
  { prompt: "dark psychological thriller", expected: "dark_serious", note: "dark/thriller" },
  { prompt: "hidden gems I haven't seen", expected: "hidden_gems", note: "hidden gems intent" },
  { prompt: "underrated anime that people miss", expected: "hidden_gems", note: "underrated -> hidden gems" },
  { prompt: "classic must watch anime", expected: "classics_expanded", note: "classic intent" },
  { prompt: "greatest of all time essentials", expected: "classics_expanded", note: "goat/essentials" },
  { prompt: "90s anime retro vibes", expected: "classics_expanded", note: "90s + retro" },
  { prompt: "short anime I can binge in one night", expected: "short_one_season", note: "short/binge" },
  { prompt: "one season quick watch", expected: "short_one_season", note: "one season" },
  { prompt: "anime movie recommendations", expected: "movie_night", note: "movie intent" },
  { prompt: "good film for movie night", expected: "movie_night", note: "film + movie night" },
  { prompt: "serious romance anime with heartbreak", expected: "romance_serious", note: "heartbreak -> serious" },
  { prompt: "deep romance drama not comedy", expected: "romance_serious", note: "deep romance" },
  { prompt: "romcom recommendations", expected: "romcom", note: "romcom keyword" },
  { prompt: "cute funny romance anime", expected: "romcom", note: "romance -> romcom" },
  { prompt: "high fantasy no isekai", expected: "fantasy_non_isekai", note: "no isekai intent" },
  { prompt: "isekai anime where they get reincarnated", expected: "isekai", note: "isekai keyword" },
  { prompt: "transported to another world adventure", expected: "isekai", note: "another world" },
  { prompt: "truck-kun anime", expected: "isekai", note: "truck-kun" },

  // --- German vibes (mapStrongGenreToModeId handles these via umlaut normalization) ---
  { prompt: "gemütlich anime zum entspannen", expected: "cozy_comfort", note: "DE: gemuetlich in regex" },
  { prompt: "düsteres dunkles dark anime", expected: "dark_serious", note: "DE: 'dark' keyword triggers dark_serious" },
  { prompt: "lustiges comedy anime", expected: "premium_comedy_grownup", note: "DE: 'comedy' keyword in text" },
  { prompt: "gruselig horror anime empfehlung", expected: "horror_supernatural", note: "DE: gruselig in regex" },
  { prompt: "historisches samurai anime", expected: "historical", note: "DE: samurai -> historical" },
  { prompt: "romantisches romance anime", expected: "romcom", note: "DE: 'romance' keyword in text" },
  { prompt: "unheimlich geister anime", expected: "horror_supernatural", note: "DE: unheimlich in regex" },
  { prompt: "anime anfangen erste empfehlung", expected: "gateway_start_here", note: "DE: anime anfangen -> gateway" },
  { prompt: "klassiker anime meisterwerk", expected: "classics_expanded", note: "DE: klassiker + meisterwerk" },
  { prompt: "entspannende wohlfühl anime", expected: "cozy_comfort", note: "DE: wohlfuehl in regex" },
  { prompt: "ein romantischer anime für heute", expected: "romcom", note: "DE: romantischer -> romantisch -> romcom (F28)" },
  { prompt: "schaurigen anime für halloween", expected: "horror_supernatural", note: "DE: schaurigen -> schaurig -> horror (F28)" },

  // --- Negative genres (exclusions) ---
  // Note: "action but no romance" contains "romance" which matches romcom before action
  // in mapStrongGenreToModeId priority. The live router uses excludedGenres parsed by
  // concierge-parse. Here we test with explicit excludedGenres param.
  { prompt: "action but no romance", excludedGenres: ["Romance"], expected: "premium_action", note: "action with excl romance" },
  { prompt: "fantasy non-isekai pure magic anime", expected: "fantasy_non_isekai", note: "non-isekai intent" },
  { prompt: "comedy but no action", excludedGenres: ["Action"], expected: "premium_comedy_grownup", note: "comedy with excl action" },

  // --- New modes: mecha, mystery, music, historical, school, shoujo ---
  { prompt: "mecha giant robot anime", expected: "mecha", note: "mecha keyword" },
  { prompt: "gundam style anime", expected: "mecha", note: "gundam -> mecha" },
  { prompt: "mystery detective whodunit", expected: "mystery_detective", note: "mystery keyword" },
  { prompt: "krimi detektiv anime", expected: "mystery_detective", note: "DE: krimi -> mystery" },
  { prompt: "music anime band", expected: "music_performance", note: "music anime" },
  { prompt: "idol anime concert", expected: "music_performance", note: "idol anime" },
  { prompt: "historical samurai period drama", expected: "historical", note: "historical keyword" },
  { prompt: "medieval anime mittelalter", expected: "historical", note: "medieval + DE mittelalter" },
  { prompt: "school anime coming of age", expected: "school_coming_of_age", note: "school intent" },
  { prompt: "high school campus anime", expected: "school_coming_of_age", note: "high school" },
  { prompt: "shoujo anime for women", expected: "shoujo_josei", note: "shoujo keyword" },
  { prompt: "josei manga fuer frauen", expected: "shoujo_josei", note: "DE: josei + fuer frauen" },

  // --- Sports / Sci-fi / Horror (added Feb 2026) ---
  { prompt: "best sports anime", expected: "sports", note: "sports keyword" },
  { prompt: "volleyball anime haikyuu style", expected: "sports", note: "volleyball -> sports" },
  { prompt: "sci-fi anime recommendations", expected: "scifi", note: "sci-fi keyword" },
  { prompt: "cyberpunk dystopian future anime", expected: "scifi", note: "cyberpunk -> scifi" },
  { prompt: "something scary and creepy", expected: "horror_supernatural", note: "scary + creepy -> horror" },
  { prompt: "anime with ghost and demon themes", expected: "horror_supernatural", note: "ghost + demon -> horror" },

  // --- Seed-based routing ---
  { prompt: "something like FMAB", expected: "similar_to_seed", note: "like X -> seed" },
  { prompt: "similar to Attack on Titan", expected: "similar_to_seed", note: "similar to X -> seed" },
  { prompt: "AOT", expected: "similar_to_seed", note: "abbreviation -> seed" },
  { prompt: "HxH 2011", expected: "similar_to_seed", note: "abbreviation + year -> seed" },

  // --- Edge cases ---
  { prompt: "ISEKAI ANIME WITH OP MC", expected: "isekai", note: "all-caps: isekai" },
  { prompt: "RomCom with school setting", expected: "romcom", note: "mixed-case: romcom" },
  { prompt: "asdfghjkl", expected: "premium_picks", note: "gibberish -> fallback" },
  { prompt: "", expected: "premium_picks", note: "empty -> fallback" },
  { prompt: "shounen ai romance", expected: "romance_serious", note: "shounen ai sub-genre" },
  { prompt: "mahou shoujo magical girl anime", expected: "premium_picks", note: "mahou shoujo -> premium" },
  { prompt: "bittersweet love story that will make me cry", expected: "romance_serious", note: "bittersweet -> serious romance" },
  { prompt: "first anime recommendations", expected: "gateway_start_here", note: "gateway intent" },
  { prompt: "getting into anime, where do i start", expected: "gateway_start_here", note: "gateway intent phrase" },
  { prompt: "getting into anime where do i start", expected: "gateway_start_here", note: "gateway intent (no comma)" },
  { prompt: "fussball anime", expected: "sports", note: "DE: fussball -> sports" },
  { prompt: "weltraum zukunft anime", expected: "scifi", note: "DE: weltraum -> scifi" },
];
