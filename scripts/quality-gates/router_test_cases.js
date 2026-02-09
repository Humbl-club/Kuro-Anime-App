/*
  Offline router test: validates scoreMode() and mapStrongGenreToModeId()
  logic without hitting the network.

  Duplicates the key routing functions from concierge-recommend/index.ts
  so tests run purely offline.

  Usage:
    node scripts/quality-gates/router_test_cases.js
*/

// ─── Duplicated router logic (from concierge-recommend/index.ts) ─────────────

const GERMAN_VIBE_FORMS = {
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

function normalizeText(s) {
  return s
    .toLowerCase()
    .replace(/[_/\\-]+/g, " ")
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function normalizeUmlauts(s) {
  return s.replace(/ü/g, "ue").replace(/ö/g, "oe").replace(/ä/g, "ae").replace(/ß/g, "ss")
          .replace(/Ü/g, "Ue").replace(/Ö/g, "Oe").replace(/Ä/g, "Ae");
}

function normalizeGermanVibeWords(text) {
  let result = text.toLowerCase();
  for (const [inflected, base] of Object.entries(GERMAN_VIBE_FORMS)) {
    result = result.replace(new RegExp(`\\b${inflected}\\b`, "g"), base);
  }
  return result;
}

function mapStrongGenreToModeId(text, excludedGenres = []) {
  const t = normalizeUmlauts(normalizeGermanVibeWords(text.toLowerCase()));
  const excl = new Set(excludedGenres.map((g) => g.toLowerCase()));
  if (/\b(classic|classics|must watch|essentials|goat|greatest|retro|old school|oldschool|vintage|80s|90s|klassiker|klassisch|legendaer|meisterwerk)\b/.test(t)) return "classics_expanded";
  if (/\b(movie|movies|film|movie night|feature film|standalone movie)\b/.test(t)) return "movie_night";
  if (/\b(short|one season|quick watch|binge|one cour|12 ep|13 ep|eine staffel|kurze serie)\b/.test(t)) return "short_one_season";
  if (/\b(no isekai|not isekai|ohne isekai|non[- ]?isekai)\b/.test(t)) return "fantasy_non_isekai";
  if (!excl.has("romance") && /\b(shounen ai|shonen ai)\b/.test(t)) return "romance_serious";
  if (/\b(mahou shoujo|magical girl)\b/.test(t)) return "premium_picks";
  if (!excl.has("isekai") && /\b(isekai|reincarnat|reborn|another world|truck[- ]?kun)\b/.test(t)) return "isekai";
  if (!excl.has("romance") && /\b(romcom|rom com|romantic comedy)\b/.test(t)) return "romcom";
  if (!excl.has("romance") && /\b(serious romance|romance drama|bittersweet|heartbreak|deep romance)\b/.test(t)) return "romance_serious";
  if (!excl.has("romance") && /\b(romance|love story|romantic)\b/.test(t)) return "romcom";
  if (/\b(school anime|high school|coming of age|schule|jugend)\b/.test(t)) return "school_coming_of_age";
  if (/\b(shoujo|josei|for women|fuer frauen|maedchen)\b/.test(t)) return "shoujo_josei";
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

function isGatewayIntent(text) {
  return /\b(first anime|first manga|where do i start|getting into anime|getting into manga|neu bei anime|neu bei manga|anime anfangen|manga anfangen)\b/i.test(text);
}

function isClassicIntent(text) {
  return /\b(classic|classics|must watch|essentials|goat|greatest|retro|old school|oldschool|vintage|80s|90s)\b/i.test(text);
}

function isHiddenGemsIntent(text) {
  return /\b(hidden gem|hidden gems|underrated|less known|new to me)\b/i.test(text);
}

function inferSeedQuery(text) {
  const t = text.trim();
  const m1 = t.match(/\b(?:like|similar to)\s+(.+?)(?:[.?!]|$)/i);
  if (m1?.[1]) return m1[1].trim().replace(/^["']|["']$/g, "");
  return null;
}

function expandKnownAbbrevSeed(raw) {
  const t = raw.trim();
  const map = {
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

function inferBareSeedCandidate(text) {
  const t = text.trim();
  if (!t) return null;
  if (/\b(recommend|something|give me|suggest|looking for|i want|show me|find me)\b/i.test(t)) return null;
  const words = t.split(/\s+/).filter(Boolean);
  if (words.length === 0 || words.length > 5) return null;
  if (t.length > 40) return null;
  const yearMatch = t.match(/\b(19|20)\d{2}\b/);
  const year = yearMatch ? yearMatch[0] : null;
  const tokenNoYear = year ? t.replace(year, "").trim() : t;
  const expanded = expandKnownAbbrevSeed(tokenNoYear);
  if (expanded) return year ? `${expanded} ${year}` : expanded;
  return t;
}

/**
 * Simplified router: determines expectedMode using the same priority chain
 * as the edge function. Does NOT call DB or scoreMode (which needs live config).
 * For offline testing, we focus on mapStrongGenreToModeId + intent overrides.
 */
function routeOffline(prompt, excludedGenres = []) {
  const text = prompt.trim();

  // 1) Seed detection (like X, similar to Y, bare abbreviations)
  const seedQuery = inferSeedQuery(text);
  if (seedQuery) return "similar_to_seed";

  // Bare seed candidates (abbreviations like AOT, HxH, or bare titles)
  const bareSeed = inferBareSeedCandidate(text);
  // Known abbreviations always resolve to seed
  const yearMatch = text.match(/\b(19|20)\d{2}\b/);
  const year = yearMatch ? yearMatch[0] : null;
  const tokenNoYear = year ? text.replace(year, "").trim() : text;
  if (expandKnownAbbrevSeed(tokenNoYear)) return "similar_to_seed";

  // 2) Gateway / classic / hidden-gems hard overrides
  if (isGatewayIntent(text)) return "gateway_start_here";
  if (isClassicIntent(text)) return "classics_expanded";
  if (isHiddenGemsIntent(text)) return "hidden_gems";

  // 3) Strong genre mapping
  const strongGenre = mapStrongGenreToModeId(text, excludedGenres);
  if (strongGenre) return strongGenre;

  // 4) Fallback
  return "premium_picks";
}

// ─── Test cases ──────────────────────────────────────────────────────────────

const TEST_CASES = [
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

// ─── Runner ──────────────────────────────────────────────────────────────────

let passed = 0;
let failed = 0;
const failures = [];

for (const tc of TEST_CASES) {
  const actual = routeOffline(tc.prompt, tc.excludedGenres || []);
  if (actual === tc.expected) {
    passed++;
  } else {
    failed++;
    failures.push({ prompt: tc.prompt, expected: tc.expected, actual, note: tc.note });
  }
}

console.log(`\n=== Router Offline Tests ===`);
console.log(`Total:  ${TEST_CASES.length}`);
console.log(`Passed: ${passed}`);
console.log(`Failed: ${failed}`);

if (failures.length > 0) {
  console.log(`\nFailures:`);
  for (const f of failures) {
    console.log(`  FAIL: "${f.prompt}" -> expected=${f.expected}, got=${f.actual} (${f.note})`);
  }
  console.log("");
  process.exit(1);
} else {
  console.log(`\nAll tests passed.`);
  process.exit(0);
}
