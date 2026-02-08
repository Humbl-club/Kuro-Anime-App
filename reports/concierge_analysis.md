# Concierge System: Full Technical Analysis

**Date:** 2026-02-08
**Scope:** End-to-end pipeline from user text input to recommendation display

---

## 1. Pipeline Overview

```
User Input (ConciergeView.swift)
       |
       v
  looksLikeImport()  ---- true ----> IMPORT PATH
       |                                  |
     false                                v
       |                          concierge-parse (Edge Function)
       v                             |  splitItems()
  concierge-recommend                |  parseStatus()
  (Edge Function)                    |  parseProgress()
       |                             |  mediaTypeHint()
       v                             |  extractYearMention()
  Mode Router                        |  stripMeta()
  (deterministic +                   |  search_titles RPC
   optional LLM)                     |  candidate scoring
       |                             v
       v                       concierge-resolve (Edge Function)
  Build 2 Rails                   |  Groq LLM disambiguation
  (primary + secondary)          |  (only for ambiguous items)
       |                          v
       v                     concierge-apply (Edge Function)
  Optional Narration              |  upsert user_lists
  (Groq blurbs)                   |  session tracking
       |                          v
       v                     Display: bubbles + undo bar
  Display: horizontal
  card rails + sets
```

### Two Distinct Paths

The iOS client (`ConciergeView.swift:422-455`) decides the path using `looksLikeImport()`:

- **Import path**: Multi-line text, progress markers (ep/chapter/season), status verbs (watched/reading/completed), comma-separated title lists
- **Recommendation path**: Short prompts, vibe words, genre names, "something like X"

The threshold is strict to avoid false positives: vibe prompts like "funny, not childish" must not be routed to import parsing.

---

## 2. Parser: `concierge-parse/index.ts` (892 lines)

### 2.1 Input Splitting (`splitItems`, lines 116-209)

Handles multi-item input by splitting on:
- Newlines
- Sentence-ending punctuation (`.!?;`)
- Clause boundaries with pronoun restarts ("... and I watched ...")
- Comma-separated title lists (when preceded by a verb clause)

Supports both English and German verb patterns:
- EN: `I watched X, Y, and Z`
- DE: `Ich habe X, Y und Z geschaut` (perfect tense with past participle at end)
- DE present: `Ich schaue X und Y`

### 2.2 Status Detection (`parseStatus`, lines 211-257)

Recognizes list statuses from natural language:

| Status | English triggers | German triggers |
|--------|-----------------|-----------------|
| COMPLETED | watched, finished, completed, done, last episode | fertig, abgeschlossen, beendet, komplett |
| WATCHING | caught up, up to date, I'm watching | aktuell, ich schaue, am schauen |
| READING | I'm reading, read | ich lese, am lesen, gelesen |
| DROPPED | dropped | abgebrochen, gedroppt |
| PAUSED | paused, on hold, hiatus | pausiert, auf eis |
| PLANNING | planning, plan to watch, ptw | plane, geplant, will schauen |

Smart partial-progress logic: "I watched Naruto until ep 50" maps to WATCHING (not COMPLETED) because `hasPartialProgress` is true.

### 2.3 Progress Extraction (`parseProgress`, lines 276-389)

Extracts structured progress from free text:

- **S2E5 / s02e05 / 2x05** format: sets seasonNumber + episodeInSeason
- **"Season 2 Episode 5"** / **"Staffel 2 Folge 5"**: named pattern
- **Roman numerals**: "Season II Episode 5" (via `romanToInt`, up to XL)
- **Number words**: "season three episode five" / "Staffel zwei Folge drei"
- **Episode-only**: "ep 12", "Folge 5"
- **Chapter/Volume**: "ch 45", "vol 3", "Kapitel 100", "Band 5"

### 2.4 Media Type Inference (`mediaTypeHint`, lines 391-405)

| Signal | Inferred Type |
|--------|--------------|
| manga/manhwa/manhua | MANGA |
| anime | ANIME |
| read/reading/lese/gelesen | MANGA |
| watched/watching/schaue/geschaut | ANIME |
| volume/chapter/kapitel/band | MANGA |
| episode/staffel/folge | ANIME |

### 2.5 Year Extraction (`extractYearMention`, lines 407-421)

Extracts year from:
- Parenthesized: `Hunter x Hunter (2011)` -> 2011
- Standalone 4-digit: any `1950-2099` range not part of a larger number

Used downstream for disambiguation (e.g., HxH 1999 vs 2011).

### 2.6 Title Normalization (`stripMeta`, lines 423-467)

Strips from the raw input to produce a clean search query:
- Parenthetical notes `(...)`
- Speech fillers: um, uh, erm, like, also, halt (EN+DE)
- Status/completion phrases
- Progress markers (season/episode/chapter references)
- Leading pronouns: "I'm", "ich habe"
- Trailing progress phrases: "until the last episode"

### 2.7 Abbreviation Expansion (`expandCommonAbbreviations`, lines 43-75)

Hardcoded map of 10 common abbreviations:
- AoT/SNK -> Attack on Titan
- JJK -> Jujutsu Kaisen
- MHA -> My Hero Academia
- HxH -> Hunter x Hunter
- FMAB/FMA -> Fullmetal Alchemist (Brotherhood)
- OPM -> One Punch Man
- CSM -> Chainsaw Man
- JJBA -> JoJo's Bizarre Adventure
- KNY -> Demon Slayer

Also handles abbreviation as first token: "JJK season 2" -> "Jujutsu Kaisen season 2"

### 2.8 Candidate Scoring (lines 469-558)

After `search_titles` RPC returns fuzzy matches, scores are adjusted:

1. **Token overlap boost** (`tokenOverlapBoost`): +0.14 for 1 shared word, +0.34 for 2, +0.42 for 3+
2. **Variant penalty** (`variantPenalty`): -0.12 for OVA/special/movie/recap, -0.18 for collab titles, -0.10 for subtitled variants
3. **Season match boost** (`seasonMatchBoost`): +0.18 when title includes the mentioned season number
4. **Alias boost**: +0.80 when matching a user's previously-confirmed `title_aliases` entry
5. **Year boost**: +0.25 when candidate year matches user's yearMention
6. **Season queries** (`buildSeasonQueries`): generates 6 alternate queries like "Naruto season 2", "Naruto s2", "Naruto staffel 2"

Final score capped at 1.25 (allows season variants to beat base titles).

### 2.9 Low-Confidence Recovery (lines 806-827)

If best candidate score < 0.55 and query >= 8 chars, runs `buildDenoisedQueries`:
- Extracts longest tokens (>=6 chars) as anchor words
- Tries last 1-3 tokens, first 2 tokens
- Up to 5 additional keyword queries

### 2.10 Feedback Logging (lines 833-852)

Logs low-confidence parses (score < 0.55) to `concierge_parse_feedback` table for later analysis. Configurable via `concierge_config.parse_feedback`.

---

## 3. LLM Resolver: `concierge-resolve/index.ts` (284 lines)

### 3.1 When It Triggers

Called from the iOS client **only during import flow** when:
1. User is authenticated
2. There are remaining unresolved items after auto-resolve
3. `llm_enabled` feature flag is true

### 3.2 Groq Integration

- **Model**: configurable via `GROQ_MODEL_RESOLVE` env, default `openai/gpt-oss-20b`
- **Temperature**: 0.0 (deterministic)
- **Max tokens**: 220
- **System prompt**: `Return JSON only: {"choices":[{"i":0,"pick":0,"confidence":0.0,"reason":""}]}`

### 3.3 User Prompt Construction

Sends items with their candidate options in a structured format:
```
#0 raw="hunter x hunter" parsed={"yearMention":2011}
options:
  [0] ANIME|11061 Hunter x Hunter (2011) [2011] TV score=0.950
  [1] ANIME|136 Hunter x Hunter [1999] TV score=0.880
```

Rules provided to the LLM:
- Must pick from options only (no hallucination)
- Prefer ANIME for watched/saw, MANGA for read
- Prefer season-matching option when seasonNumber present
- Prefer year-matching option when yearMention present

### 3.4 Budget System

- **Per-user budget**: `llm_budget_reserve` / `llm_budget_finalize` RPCs
- **Global budget**: `llm_global_budget_reserve` / `llm_global_budget_finalize` RPCs
- Reserve-then-finalize pattern prevents budget leakage
- Default limits: 50,000 tokens/day per user, 1,000,000 global, 600 calls/day global

### 3.5 Rate Limiting

Per-kind rate limits from `concierge_config.rate_limits`:
- resolve: 10 user / 40 IP per 60s

---

## 4. Recommendation Engine: `concierge-recommend/index.ts` (1606 lines)

### 4.1 Architecture: Deterministic-First Mode Router

The engine follows a strict priority chain to select a "vibe mode":

```
1. Cache hit (concierge_mode_cache) ---------> use cached decision
2. Seed query ("like X") -------------------> similar_to_seed
3. Classic intent keywords ------------------> classics_expanded
4. Gateway intent (first anime/manga) ------> gateway_start_here
5. Hidden gems intent -----------------------> hidden_gems
6. Strong genre signal (regex) --------------> mapped mode
7. Deterministic scoring (all modes) --------> top scorer
   7a. If low confidence + LLM enabled -----> Groq router fallback
8. Fallback ---------------------------------> premium_picks (+1 tiebreaker)
```

### 4.2 The 14 Vibe Modes

All modes are stored in `concierge_config.config.modes` (JSONB). The DB config overrides the hardcoded `defaultModes()` fallback.

| Mode ID | Title | Rail IDs | Key Filters |
|---------|-------|----------|-------------|
| `premium_picks` | Premium Picks | premium_picks_anime/manga | score>=75, pop>=2500, no Kids |
| `gateway_start_here` | Start Here | gateway_anime/manga | Curated only |
| `premium_action` | Premium Action | premium_action_anime/manga | genre:Action, score>=75 |
| `premium_comedy_grownup` | Premium Comedy (grown-up) | premium_comedy_grownup_anime/manga | genre:Comedy, no Kids |
| `cozy_comfort` | Cozy / Comfort | cozy_comfort_anime/manga | genre:Slice of Life, score>=70 |
| `dark_serious` | Dark / Serious | dark_serious_anime/manga | genre:Drama/Thriller/Psych/Mystery, score>=78 |
| `hidden_gems` | Hidden Gems | hidden_gems_anime/manga | score>=78, pop<=45000 |
| `classics_expanded` | Classics (expanded) | classics_anime/manga | score>=80, year<=2012 |
| `short_one_season` | Short & Complete | short_one_season_anime/manga | score>=74, no MOVIE/ONA |
| `movie_night` | Movie Night | movie_night_anime | MOVIE format only |
| `romance_serious` | Romance (serious) | romance_serious_anime/manga | genre:Romance+Drama, no Comedy |
| `romcom` | Romcom | romcom_anime/manga | genre:Romance+Comedy |
| `fantasy_non_isekai` | Fantasy (no isekai) | fantasy_non_isekai_anime/manga | genre:Fantasy |
| `isekai` | Isekai | isekai_anime/manga | genre:Fantasy+Adventure |

### 4.3 Curated Rails (Database)

27 curated rails total, stored in `curated_rails` + `curated_rail_items`:

| Rail | Media Type | Items |
|------|-----------|-------|
| classics_anime | ANIME | 210 |
| classics_manga | MANGA | 177 |
| cozy_comfort_anime | ANIME | 160 |
| cozy_comfort_manga | MANGA | 120 |
| dark_serious_anime | ANIME | 137 |
| dark_serious_manga | MANGA | 120 |
| fantasy_non_isekai_anime | ANIME | 120 |
| fantasy_non_isekai_manga | MANGA | 120 |
| gateway_anime | ANIME | 135 |
| gateway_manga | MANGA | 152 |
| hidden_gems_anime | ANIME | 160 |
| hidden_gems_manga | MANGA | 120 |
| isekai_anime | ANIME | 114 |
| isekai_manga | MANGA | 120 |
| movie_night_anime | ANIME | 120 |
| premium_action_anime | ANIME | 160 |
| premium_action_manga | MANGA | 120 |
| premium_comedy_grownup_anime | ANIME | 160 |
| premium_comedy_grownup_manga | MANGA | 120 |
| premium_picks_anime | ANIME | 120 |
| premium_picks_manga | MANGA | 120 |
| romance_serious_anime | ANIME | 120 |
| romance_serious_manga | MANGA | 120 |
| romcom_anime | ANIME | 120 |
| romcom_manga | MANGA | 120 |
| short_one_season_anime | ANIME | 120 |
| short_one_season_manga | MANGA | 120 |

**Total curated items: ~3,671** across all rails.

### 4.4 Curated vs Algorithmic: The Hybrid Strategy

For each mode, `buildRailItems()` (line 1381):

1. If the mode has a `rail_id` configured, fetch curated items via `curated_rail_cards` RPC
2. If curated returns enough items (`>= total`), use curated only
3. If curated returns fewer than requested, **fill remainder algorithmically** using `recommend_ids_premium` RPC
4. If no curated rail or curated fetch fails, fall back entirely to algorithmic

The `curated_rail_cards` function:
- Joins `curated_rail_items` -> `anime`/`manga` by `anilist_id`
- Filters out adult/hentai/ecchi
- **Excludes titles already in user's `user_lists`** (seen-filtering)
- Orders by `rank` (editorial sort order)
- Caps at 120 items

### 4.5 Algorithmic Ranking: `recommend_ids_premium` RPC

Composite scoring formula:
```
score = tag_match_count * 8
      + ln(1 + favourites) * 2.0
      + ln(1 + popularity) * 1.0
      + average_score / 10.0
      + classic_bonus (7 if <=2005, 4 if <=2015)
      + editorial_boost_weight
      + penalty_tags (negative, unless allow_gimmicks)
```

Key features:
- Tag categories matched against `tags.category` (AniList taxonomy)
- Editorial boosts from `editorial_boosts` table (per media_id)
- Penalty tags from `editorial_penalty_tags` (e.g., harem, ecchi-adjacent)
- Always excludes titles already in user's lists
- Always excludes adult/hentai/ecchi

### 4.6 "Similar To" Path

When user says "something like Cowboy Bebop":
1. `inferSeedQuery()` extracts the seed title from "like X" / "similar to X"
2. `search_titles` RPC finds the closest match
3. `recommend_ids_similar_to_seeds` RPC finds tag-similar titles
4. Results built using same quality filtering pipeline

### 4.7 Mode Router: Deterministic Scoring (`scoreMode`, lines 241-336)

Each mode scores against user text via:
- **Synonym matching**: +2 to +5 points per matched synonym
- **Genre overlap**: +2 + min(3, overlap_count)
- **Intent heuristics**: classic/hidden/mature/movie/short/isekai/romcom patterns, +2 to +4 each
- **Disambiguation**: romance vs romcom, isekai vs fantasy-no-isekai (cross-penalty of -2 to -4)
- **Tiebreaker**: `premium_picks` gets +1 so vague prompts land on the default

Confidence = sigmoid(score_delta - 1) between top and runner-up.

### 4.8 LLM Router Fallback (`groqRouteMode`, lines 617-682)

When deterministic confidence < 0.45 or top score <= 2:
1. Check `llm_enabled` and `llm_router_enabled` feature flags
2. Reserve budget (small: ~120-600 tokens)
3. Send all mode IDs + synonyms to Groq with: "Pick exactly one primary_mode_id"
4. If LLM returns a valid mode ID, use it with confidence=0.65

### 4.9 Two-Rail Output

Every recommendation response returns exactly 2 rails:
1. **Primary rail**: matched vibe mode
2. **Secondary rail**: anchor rail (classics by default, or premium_picks if primary is classics)

### 4.10 Optional Narration (Groq blurbs)

When `narrate=true` (default from iOS):
- Takes up to 8 items
- Groq generates one-sentence spoiler-free blurbs per item
- Language auto-detected (EN/DE)
- Budget-gated: skipped if daily limit exceeded
- Blurbs clamped to 18 words / 180 chars

### 4.11 Caching

- **Mode cache**: `concierge_mode_cache` table, keyed by (user_id, prompt_norm), TTL 30 days
- **iOS-side**: `conciergeRecommendCache` with 1-hour TTL, max 60 entries
- **iOS parse cache**: `conciergeParseCache` with 10-minute TTL, max 50 entries

---

## 5. iOS Integration

### 5.1 ConciergeView.swift (1772 lines)

**UI Flow:**
1. Empty state shows intro card + 3 starter actions (paste, example import, example vibe)
2. User types in text field (1-4 lines, auto-expanding)
3. `send()` routes to import or recommend path
4. Messages displayed as bubbles (user = dark, assistant = glass)
5. Import results show candidate picker with radio dots per item
6. Recommendations show horizontal card rails with cover art

**Auto-resolve logic** (lines 491-545):
- Deterministic auto-apply when: score >= 1.10 with margin >= 0.10, or score >= 1.00 with margin >= 0.22
- Additional gates: `isTitleAutoApplySafe()` (token overlap >= 75%), `hasAmbiguousAdaptations()` (same base title, different years)
- LLM auto-apply gate: confidence >= 0.88, score >= 0.70, title safe, not ambiguous

**Ambiguous adaptation detection** (lines 596-628):
- Detects when top 2 candidates have same base title but different media_ids (e.g., HxH 1999 vs 2011, FMA vs FMA:B)
- If user mentioned a year and top candidate matches, override ambiguity

### 5.2 SupabaseService API Methods

5 concierge methods, all calling Edge Functions:
- `conciergeParse()`: text -> parsed items with candidates
- `conciergeResolve()`: items -> LLM-disambiguated choices
- `conciergeApply()`: items -> upsert into user_lists
- `conciergeUndo()`: sessionId -> revert batch
- `conciergeRecommend()`: text -> mode picks + rail sets + items

All use `Task.detached(priority: .userInitiated)` to avoid main-actor blocking.

---

## 6. Supported Natural Language Patterns (Complete)

### 6.1 Import Patterns

```
# English
I watched Attack on Titan
I finished Jujutsu Kaisen season 2
I'm watching One Piece ep 1089
I read Chainsaw Man chapter 150
I have seen Hunter x Hunter (2011)
Completed Steins;Gate, Dropped Bleach
Attack on Titan (completed), JJK up to ep 12

# German
Ich habe Attack on Titan geschaut
Ich schaue One Piece Folge 1089
Ich habe Naruto und Bleach gesehen
Ich lese Chainsaw Man Kapitel 150
Staffel 2 Folge 5

# Progress formats
S2E5, s02e05, 2x05
Season 2 Episode 5
Season III Episode 7 (roman numerals)
Season two Episode five (number words)
ep 12, chapter 45, vol 3
```

### 6.2 Recommendation Patterns

```
# Vibe words
funny, sad, cozy, dark, serious, chill, relax
action, romance, comedy, thriller, horror, mystery
premium, best, top tier, quality, masterpiece

# Specific modes
hidden gems, underrated, something new
classic, must watch, essentials, goat
first anime, getting into anime, beginner
movie, movie night, film
short, one season, quick watch, binge
romcom, romantic comedy, funny romance
serious romance, heartbreak, bittersweet
isekai, another world, reincarnated, truck-kun
fantasy, high fantasy, magic (without isekai)
funny but not childish, grown up comedy, adult humor

# Similarity
something like Cowboy Bebop
similar to Death Note

# German vibes
gemutlich, witzig, duster, ernst, erwachsen
geheimtipp, klassiker, filmabend
```

---

## 7. Gaps and Weaknesses

### 7.1 Parser Gaps

1. **Limited abbreviation map**: Only 10 entries. Missing common ones: DB/DBS (Dragon Ball), OP (One Piece), BC (Black Clover), DS (Demon Slayer - intentionally avoided for ambiguity), KonoSuba, SAO, Re:Zero, ToG (Tower of God)

2. **No fuzzy/typo correction**: If user types "Atack on Titan" (one t), relies entirely on `search_titles` fuzzy matching. No client-side levenshtein or phonetic matching.

3. **English/German only**: No Japanese, Spanish, French, or other language support for status/progress markers.

4. **No batch status**: Cannot say "I completed all of these: X, Y, Z" - must repeat status per item or rely on the verb clause pattern.

5. **Rating not parsed**: No support for "I watched X, 9/10" or "X was great" sentiment extraction.

### 7.2 Recommendation Gaps

1. **No Sports mode**: Sports queries map to `premium_picks` (line 369: "keep broad; sports is a genre but not a dedicated mode yet"). Given the popularity of Haikyuu, Kuroko, Blue Lock, this is a notable gap.

2. **No Sci-Fi mode**: Sci-fi queries get no dedicated mode; they'd be caught by genre inference but with no curated rail.

3. **No Mecha mode**: Classic mecha (Gundam, Evangelion, Code Geass) has no dedicated path.

4. **No Horror mode**: Horror queries map to `dark_serious` which is a superset. Users asking specifically for horror get a mix of psychological/thriller/drama.

5. **No "Currently Airing" mode**: No way to ask "what's good this season?" - no airing schedule integration.

6. **No negative filtering in recommendations**: Can't say "action but no romance" or "fantasy but no harem". The `exclude_genres` are mode-level only, not user-controllable.

7. **Limited "similar to" handling**: Only extracts one seed title. "Something like Cowboy Bebop and Samurai Champloo" would only use the first match.

8. **Isekai vs Fantasy overlap**: The isekai tag (AniList tag 350) is used as a gimmick filter, but the Fantasy (no isekai) mode's exclusion relies on genre filtering (`exclude_genres` doesn't include isekai because isekai is a tag, not a genre). This means some isekai titles with Fantasy genre but without the isekai tag may leak into the fantasy rail.

9. **Movie Night is anime-only**: `movie_night` has `rail_id: {anime: "movie_night_anime"}` with no manga equivalent. Manga one-shots/short series could serve a similar function.

### 7.3 Mode Router Gaps

1. **Compound vibes poorly handled**: "funny dark comedy" could match both `premium_comedy_grownup` and `dark_serious`. The deterministic scorer sums points, so the highest-synonym-match mode wins, which may not capture the blend.

2. **No multi-mode output**: System always picks exactly one primary + one secondary. Users asking for "action and romance" get only one, not a blended rail.

3. **Cache key doesn't include scope**: If user switches between anime/manga scope with same prompt, cached mode is reused. (Minor: scope is handled downstream in item fetching, not in mode selection.)

### 7.4 iOS/UX Gaps

1. **No conversation memory**: Each send() is stateless. User can't refine: "More like the third one" or "But less violent."

2. **No recommendation feedback loop**: Skipping/saving a recommendation doesn't influence future recommendations within the session.

3. **No explicit mode picker**: User must know the right words. No UI to browse available modes and pick one.

---

## 8. How Curated List Expansion Flows Through to NL Suggestions

### Current Flow

```
concierge_config.modes[].rail_id  -->  curated_rails.id
                                            |
                                            v
                                   curated_rail_items
                                   (rail_id, media_type, anilist_id, rank)
                                            |
                                            v
                                   curated_rail_cards() RPC
                                   (joins to anime/manga, filters seen, orders by rank)
                                            |
                                            v
                                   concierge-recommend fetchCurated()
                                   (maps to display items)
```

### Adding New Curated Content

To expand curated lists, the pipeline requires:

1. **Insert into `curated_rail_items`**: new rows with (rail_id, media_type, anilist_id, rank, note)
2. **No code changes needed**: The `curated_rail_cards` RPC and `fetchCurated()` in the Edge Function are generic
3. **Rank determines order**: Lower rank = shown first. Ties broken by media_id
4. **Seen-filtering is automatic**: Already-seen titles excluded via `user_lists` check
5. **Hybrid fill is automatic**: If curated items are exhausted (all seen), algorithmic fill kicks in

### Adding New Modes

To add a new vibe mode:

1. Add mode object to `concierge_config.config.modes` JSON array (DB update only)
2. Create curated rails: `INSERT INTO curated_rails (id, title, media_type, description)`
3. Populate rails: `INSERT INTO curated_rail_items (rail_id, media_type, anilist_id, rank)`
4. Add `rail_id` mapping to mode config: `{"anime":"new_mode_anime","manga":"new_mode_manga"}`
5. **No Edge Function redeploy needed** if the `defaultModes()` fallback isn't relied upon
6. Synonyms in the mode config drive NL matching automatically

### Quality Gates

The `curated_rail_cards` function applies:
- Adult content filter (is_adult, Hentai, Ecchi genre)
- Seen-title exclusion
- Rank ordering (editorial intent preserved)

The Edge Function `buildItemsFromRows` adds:
- Genre gating (required_genres match)
- Quality floor (min_score, min_popularity)
- Format exclusion (TV_SHORT, SPECIAL, etc.)
- Year cap (for classics mode)

---

## 9. Proposals for Improvement

### 9.1 New Vibe Modes (Priority Order)

1. **Sports** (`sports`): Required genre: Sports. Synonyms: sports, soccer, basketball, volleyball, baseball, boxing, climbing. Would immediately serve Haikyuu, Blue Lock, Kuroko, Hajime no Ippo queries.

2. **Sci-Fi** (`scifi`): Required genre: Sci-Fi. Synonyms: sci-fi, science fiction, space, cyberpunk, mecha, futuristic. Covers Cowboy Bebop, Ghost in the Shell, Psycho-Pass, Steins;Gate.

3. **Horror** (`horror`): Required genres: Horror. Synonyms: horror, scary, creepy, supernatural horror, ghost, monster. Distinct from dark_serious by being genre-specific rather than tone-based.

4. **Currently Airing** (`airing_now`): Filter on `status = 'RELEASING'` + `start_date_year = current_year`. Synonyms: airing, this season, currently airing, what's on now. Would need a new algorithmic strategy (no curated rail, or auto-refreshed curated rail).

5. **Long-Running** (`long_runners`): The inverse of short_one_season. For users who want 100+ episode epics. Synonyms: long, marathon, epic, 100 episodes, long running.

### 9.2 Parser Improvements

1. **Expanded abbreviation map**: Add 15-20 more common abbreviations (OP, DB/DBS/DBZ, SAO, Re:Zero, KonoSuba, BC, ToG, MiA, CSM:P2, etc.)

2. **Rating extraction**: Parse "9/10", "8.5", "loved it", "meh" into a rating field. Would allow imported ratings to flow into user_lists.

3. **Batch status shorthand**: "Completed: X, Y, Z" pattern where the status prefix applies to all following titles.

### 9.3 Recommendation Engine Improvements

1. **Negative genre filtering**: Parse "no romance", "without harem", "not isekai" and pass as exclude_genres to the scoring pipeline. The `inferRequiredGenres` pattern could be mirrored with `inferExcludedGenres`.

2. **Multi-seed similarity**: Parse multiple titles from "like X and Y" and combine tag overlap scores.

3. **Session context**: Pass previous recommendations (skipped/saved) as exclusion list in subsequent requests within same chat session.

### 9.4 Infrastructure

1. **Abbreviation table**: Move from hardcoded map to a DB table (`common_abbreviations`) that can be updated without redeploy. Include community-contributed abbreviations.

2. **Mode analytics**: Track which modes are triggered and how often, which synonyms matched, to inform new mode creation and synonym tuning.

3. **A/B testing**: The `concierge_config` JSONB could support multiple mode configurations for testing different scoring weights or synonym sets.
