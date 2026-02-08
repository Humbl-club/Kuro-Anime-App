# Backend & Curated Lists Analysis Report

**Date:** 2026-02-08
**Analyst:** Backend & Curated Lists Agent

---

## 1. Database Schema & Relationships

### 1.1 Core Curated Tables

#### `curated_rails` (editorial rail definitions)
| Column | Type | Description |
|--------|------|-------------|
| `id` | text (PK) | Slug-style ID, e.g. `classics_anime`, `romcom_manga` |
| `title` | text | Display title, e.g. "Classics", "Romcom" |
| `media_type` | text | CHECK: `ANIME`, `MANGA`, or `BOTH` |
| `description` | text | Internal editorial note |
| `created_at` | timestamptz | Auto-set |
| `updated_at` | timestamptz | Auto-updated via trigger |

- RLS enabled; public read policy (`curated_rails_select_all`) for `anon` and `authenticated`.
- No `sort_order` column -- rails are ordered by context (vibe mode config chooses which rail to show).

#### `curated_rail_items` (pinned titles per rail)
| Column | Type | Description |
|--------|------|-------------|
| `rail_id` | text (FK -> curated_rails.id) | Which rail this item belongs to |
| `media_type` | text | CHECK: `ANIME` or `MANGA` |
| `anilist_id` | integer | AniList ID linking to `anime.anilist_id` or `manga.anilist_id` |
| `rank` | integer | Deterministic sort order within the rail |
| `note` | text | Optional editorial note (currently unused/null) |
| `created_at` / `updated_at` | timestamptz | Auto-managed |

- PK: `(rail_id, media_type, anilist_id)` -- one entry per title per rail.
- Index: `idx_curated_rail_items_rail_rank` on `(rail_id, media_type, rank)`.
- RLS: public read for `anon` and `authenticated`.

### 1.2 Concierge Config (Vibe Modes)

Modes are stored in `concierge_config` (single-row table, `id = true`), inside the JSONB `config` column at path `{modes}`. Each mode is a JSON object with:

```json
{
  "id": "premium_action",
  "title": "Premium Action",
  "synonyms": ["action", "hype action", ...],
  "rail_id": {"anime": "premium_action_anime", "manga": "premium_action_manga"},
  "required_genres": ["Action"],
  "min_score": 75,
  "min_popularity": 3500,
  "exclude_genres": [],
  "exclude_formats": ["TV_SHORT", "SPECIAL", "MUSIC"]
}
```

**Key field: `rail_id`** links a mode to its curated rail(s). When present, the edge function serves from `curated_rail_cards()` first, falling back to algorithmic if the curated pool is empty or too small.

### 1.3 Related Tables

| Table | Role |
|-------|------|
| `anime` | Full catalog (9,450 non-adult titles). Joined via `anilist_id`. Has `genres text[]`, `average_score`, `popularity`, `format`, `is_adult`, etc. |
| `manga` | Full catalog (11,964 non-adult titles). Same structure. |
| `title_search` | Full-text search index used for seed-similarity queries. |
| `user_lists` | Per-user tracked titles; used by `curated_rail_cards()` to exclude already-seen items (`p_exclude_seen`). |

### 1.4 Materialized Views (7 total)

| MV | Used In |
|----|---------|
| `mv_anime_trending` | discover_bundle: "Trending" rail |
| `mv_anime_top_rated` | discover_bundle: "Top Rated" rail |
| `mv_anime_newly_added` | discover_bundle: "Newly Added" rail |
| `mv_anime_current_season` | discover_bundle: "Current Season" rail |
| `mv_manga_trending` | discover_bundle: "Trending" rail |
| `mv_manga_top_rated` | discover_bundle: "Top Rated" rail |
| `mv_manga_newly_added` | discover_bundle: "Newly Added" rail |

These are refreshed by cron jobs and feed the Discover page. They are **not** used by the curated rail system directly.

---

## 2. RPC Functions

### `curated_rail_cards(p_rail_id, p_limit, p_exclude_seen)`
- Joins `curated_rail_items` -> `anime`/`manga` via `anilist_id`.
- Hard-filters: `is_adult = false`, excludes Hentai and Ecchi genres.
- Optionally excludes titles the current user already has in `user_lists`.
- Returns up to 120 items ordered by `rank ASC`.
- Adds `signals` array: `'CLASSIC'` for classics rails, `'GATEWAY'` for gateway rails.
- Granted to `anon` and `authenticated`.

### `discover_bundle(p_limit, p_hours)`
- The main Discover page aggregator.
- Uses curated rails for "Essentials" (gateway) and "Classics" sections, with heuristic fallback if curated rails are empty.
- Also produces trending, top_rated, newly_added, airing_today, current_season, and new_to_you rails from MVs and live queries.

---

## 3. Edge Function: `concierge-recommend`

### How Curated Rails Feed Into Recommendations

1. **Mode Router** (deterministic): User prompt is scored against all 14 modes via `scoreMode()`. Top-scoring mode becomes `primaryId`, secondary is typically `classics_expanded` unless primary is already classics.

2. **Rail Resolution**: For each mode, `railIdFor()` looks up the `rail_id` config to get the appropriate curated rail slug for the requested media type.

3. **Fetch Priority**: `buildRailItems()` tries `fetchCurated()` first (calls `curated_rail_cards` RPC). If curated returns fewer items than requested, it fills the remainder algorithmically via `buildAlgorithmicRail()`.

4. **Output**: Always 2 rails -- primary + anchor (classics or premium_picks).

5. **LLM Narration**: Optional Groq-based narration adds one-sentence blurbs per item (if `router_llm.enabled = true`, currently enabled).

6. **Quality Compilation**: Each mode's `min_score`, `min_popularity`, `exclude_genres`, `exclude_formats` are compiled into SQL filter parameters for the algorithmic fallback path.

### Router LLM Config (Live)
```json
{
  "enabled": true,
  "max_tokens": 80,
  "min_top_score": 2,
  "cache_ttl_days": 30,
  "min_confidence": 0.45
}
```

---

## 4. Current Curated Rails Inventory

### 4.1 All 27 Rails (Live Data)

| Rail ID | Title | Media Type | Item Count |
|---------|-------|------------|------------|
| `classics_anime` | Classics | ANIME | 210 |
| `classics_manga` | Classics | MANGA | 177 |
| `cozy_comfort_anime` | Cozy / Comfort | ANIME | 160 |
| `cozy_comfort_manga` | Cozy / Comfort | MANGA | 120 |
| `dark_serious_anime` | Dark / Serious | ANIME | 137 |
| `dark_serious_manga` | Dark / Serious | MANGA | 120 |
| `fantasy_non_isekai_anime` | Fantasy (no isekai) | ANIME | 120 |
| `fantasy_non_isekai_manga` | Fantasy (no isekai) | MANGA | 120 |
| `gateway_anime` | Start Here | ANIME | 135 |
| `gateway_manga` | Start Here | MANGA | 152 |
| `hidden_gems_anime` | Hidden Gems | ANIME | 160 |
| `hidden_gems_manga` | Hidden Gems | MANGA | 120 |
| `isekai_anime` | Isekai | ANIME | 114 |
| `isekai_manga` | Isekai | MANGA | 120 |
| `movie_night_anime` | Movie Night | ANIME | 120 |
| `premium_action_anime` | Premium Action | ANIME | 160 |
| `premium_action_manga` | Premium Action | MANGA | 120 |
| `premium_comedy_grownup_anime` | Premium Comedy (grown-up) | ANIME | 160 |
| `premium_comedy_grownup_manga` | Premium Comedy (grown-up) | MANGA | 120 |
| `premium_picks_anime` | Premium Picks | ANIME | 120 |
| `premium_picks_manga` | Premium Picks | MANGA | 120 |
| `romance_serious_anime` | Romance (serious) | ANIME | 120 |
| `romance_serious_manga` | Romance (serious) | MANGA | 120 |
| `romcom_anime` | Romcom | ANIME | 120 |
| `romcom_manga` | Romcom | MANGA | 120 |
| `short_one_season_anime` | Short & Complete | ANIME | 120 |
| `short_one_season_manga` | Short & Complete | MANGA | 120 |

**Total curated items: 3,605**

### 4.2 All 14 Vibe Modes (Live Data)

| # | Mode ID | Title | Rail IDs | Key Filters |
|---|---------|-------|----------|-------------|
| 1 | `premium_picks` | Premium Picks | anime + manga | min_score=75, min_pop=2500, excl Kids |
| 2 | `gateway_start_here` | Start Here | anime + manga | No filters (curated-only) |
| 3 | `premium_action` | Premium Action | anime + manga | req: Action, min_score=75, min_pop=3500 |
| 4 | `premium_comedy_grownup` | Premium Comedy (grown-up) | anime + manga | req: Comedy, excl Kids, min_score=75, min_pop=3500 |
| 5 | `cozy_comfort` | Cozy / Comfort | anime + manga | req: Slice of Life, min_score=70, min_pop=1200 |
| 6 | `dark_serious` | Dark / Serious | anime + manga | req: Drama/Thriller/Psych/Mystery, excl Kids, min_score=78, min_pop=2500 |
| 7 | `hidden_gems` | Hidden Gems | anime + manga | max_pop=45000, min_score=78, excl Kids |
| 8 | `classics_expanded` | Classics (expanded) | anime + manga | classic_year_max=2012, min_score=80, min_pop=1500 |
| 9 | `short_one_season` | Short & Complete | anime + manga | min_score=74, min_pop=2000, excl Movie/ONA |
| 10 | `movie_night` | Movie Night | anime only | min_score=76, min_pop=2000, excl TV/ONA/OVA |
| 11 | `romance_serious` | Romance (serious) | anime + manga | req: Romance+Drama, excl Comedy+Kids |
| 12 | `romcom` | Romcom | anime + manga | req: Romance+Comedy, excl Kids |
| 13 | `fantasy_non_isekai` | Fantasy (no isekai) | anime + manga | req: Fantasy, excl Kids |
| 14 | `isekai` | Isekai | anime + manga | req: Fantasy+Adventure, excl Kids |

---

## 5. Genre Distribution in Catalog

### Anime (9,450 non-adult titles)
| Genre | Count | Has Dedicated Mode? |
|-------|-------|---------------------|
| Comedy | 4,150 | Yes (premium_comedy_grownup) |
| Action | 3,499 | Yes (premium_action) |
| Fantasy | 2,583 | Yes (fantasy_non_isekai, isekai) |
| Drama | 2,436 | Partial (dark_serious, romance_serious) |
| Adventure | 2,229 | Indirect (isekai req Fantasy+Adventure) |
| Sci-Fi | 2,017 | **NO** |
| Romance | 2,015 | Yes (romcom, romance_serious) |
| Slice of Life | 1,742 | Yes (cozy_comfort) |
| Supernatural | 1,398 | **NO** |
| Mecha | 771 | **NO** |
| Mystery | 760 | Partial (dark_serious) |
| Sports | 558 | **NO** (maps to premium_picks as fallback) |
| Music | 510 | **NO** |
| Psychological | 503 | Partial (dark_serious) |
| Horror | 372 | **NO** |
| Mahou Shoujo | 325 | **NO** |
| Thriller | 194 | Partial (dark_serious) |

### Manga (11,964 non-adult titles)
| Genre | Count | Has Dedicated Mode? |
|-------|-------|---------------------|
| Romance | 6,029 | Yes |
| Comedy | 4,892 | Yes |
| Drama | 4,234 | Partial |
| Fantasy | 4,212 | Yes |
| Action | 3,568 | Yes |
| Slice of Life | 2,519 | Yes |
| Adventure | 2,081 | Indirect |
| Supernatural | 1,872 | **NO** |
| Psychological | 1,018 | Partial |
| Mystery | 961 | Partial |
| Sci-Fi | 858 | **NO** |
| Horror | 706 | **NO** |
| Sports | 298 | **NO** |
| Thriller | 252 | Partial |

### Anime Format Distribution
| Format | Count |
|--------|-------|
| TV | 3,876 |
| OVA | 1,440 |
| MOVIE | 1,429 |
| SPECIAL | 976 |
| ONA | 964 |
| TV_SHORT | 464 |
| MUSIC | 260 |

---

## 6. Audit Script Analysis

`scripts/audit_curated_rails_quality.js` is a Node.js script that:
- Extracts Supabase URL + anon key from `SupabaseService.swift`
- Iterates all curated rails and calls `curated_rail_cards` RPC for each
- Reports per-rail: item count, average score, Ecchi/Hentai/Kids/adult counts, low-score (<70) items
- Lists up to 5 "suspicious" items per rail (Ecchi, Hentai, Kids genres, or score < 70)

This is a quality-gate script to ensure curated content remains safe and high-quality.

---

## 7. Gap Analysis

### 7.1 Genres Without Dedicated Modes/Rails

| Genre | Anime Count | Manga Count | Priority | Rationale |
|-------|-------------|-------------|----------|-----------|
| **Sci-Fi** | 2,017 | 858 | **HIGH** | 3rd largest anime genre with no mode. Popular demand for cyberpunk, space opera, mecha-adjacent. |
| **Sports** | 558 | 298 | **HIGH** | Distinct audience segment. Currently maps to `premium_picks` fallback with a code comment noting "sports is a genre but not a dedicated mode yet." |
| **Supernatural** | 1,398 | 1,872 | **MEDIUM** | Large catalog presence but overlaps with fantasy/dark modes. Could be a distinct "Supernatural / Occult" mode. |
| **Horror** | 372 | 706 | **MEDIUM** | Distinct vibe, partially covered by `dark_serious` but horror fans want different things than psychological thriller fans. |
| **Mecha** | 771 | 108 | **LOW** | Niche but passionate audience. Anime-heavy (771 titles), minimal manga. |
| **Music** | 510 | 129 | **LOW** | Very niche. Could be part of a broader "Creative / Art" mode. |
| **Mahou Shoujo** | 325 | 82 | **LOW** | Niche. Could be combined with supernatural/fantasy. |

### 7.2 Thematic/Format Gaps

| Gap | Description | Priority |
|-----|-------------|----------|
| **Currently Airing / This Season** | No curated rail for current-season picks. Discover has `current_season` and `airing_today` but these are MV-driven, not curated. A curated "Best of This Season" rail could be valuable. | MEDIUM |
| **Award Winners / Critically Acclaimed** | No explicit rail for titles that won major awards or have exceptional critical recognition beyond score threshold. | LOW |
| **Movie Night manga equivalent** | `movie_night` is anime-only. One-shot manga or short complete series could fill a similar "quick read" niche for manga. | LOW (already covered by `short_one_season_manga`) |

### 7.3 Mode Router Gaps

- **Sports intent**: Currently falls through to `premium_picks` with a comment acknowledging the gap.
- **Sci-Fi intent**: Currently maps to the closest genre match which usually ends up in `dark_serious` or `premium_picks`, neither ideal.
- **Horror intent**: Maps to `dark_serious` but horror and psychological thriller are different audiences.

---

## 8. Proposals for New Curated Rails

### 8.1 Sci-Fi Rail (HIGH PRIORITY)

**Proposed rails:**
- `scifi_anime` -- "Sci-Fi Essentials" (ANIME)
- `scifi_manga` -- "Sci-Fi Essentials" (MANGA)

**Rationale:** 2,017 anime + 858 manga titles with Sci-Fi genre. No current mode covers this. Cyberpunk, space opera, dystopian, and hard sci-fi are distinct vibes from fantasy/dark.

**Mode config:**
```json
{
  "id": "scifi",
  "title": "Sci-Fi",
  "synonyms": ["sci-fi", "science fiction", "scifi", "cyberpunk", "space", "futuristic", "dystopian", "mecha", "robots", "space opera", "zukunft", "weltraum"],
  "required_genres": ["Sci-Fi"],
  "min_score": 74,
  "min_popularity": 2000,
  "exclude_genres": ["Kids"],
  "exclude_formats": ["TV_SHORT", "SPECIAL", "MUSIC"],
  "rail_id": {"anime": "scifi_anime", "manga": "scifi_manga"}
}
```

**Estimated items:** 120 anime + 80-100 manga (filter: Sci-Fi genre, score >= 74, non-adult, no Ecchi/Hentai).

### 8.2 Sports Rail (HIGH PRIORITY)

**Proposed rails:**
- `sports_anime` -- "Sports" (ANIME)
- `sports_manga` -- "Sports" (MANGA)

**Rationale:** The edge function code explicitly notes `"sports is a genre but not a dedicated mode yet"`. 558 anime + 298 manga titles. Sports anime has a dedicated, passionate audience.

**Mode config:**
```json
{
  "id": "sports",
  "title": "Sports",
  "synonyms": ["sports", "sport", "basketball", "soccer", "football", "volleyball", "boxing", "tennis", "baseball", "cycling", "running", "swimming", "sportanime", "sportmanga"],
  "required_genres": ["Sports"],
  "min_score": 72,
  "min_popularity": 1500,
  "exclude_genres": ["Kids"],
  "exclude_formats": ["TV_SHORT", "SPECIAL", "MUSIC"],
  "rail_id": {"anime": "sports_anime", "manga": "sports_manga"}
}
```

**Estimated items:** 80-100 anime + 50-70 manga.

### 8.3 Horror / Supernatural Rail (MEDIUM PRIORITY)

**Proposed rails:**
- `horror_supernatural_anime` -- "Horror & Supernatural" (ANIME)
- `horror_supernatural_manga` -- "Horror & Supernatural" (MANGA)

**Rationale:** Horror (372 anime + 706 manga) and Supernatural (1,398 anime + 1,872 manga) overlap significantly. Combined mode captures ghost stories, occult, horror, and creepy supernatural. Distinct from `dark_serious` which focuses on psychological thriller/mystery.

**Mode config:**
```json
{
  "id": "horror_supernatural",
  "title": "Horror & Supernatural",
  "synonyms": ["horror", "scary", "creepy", "supernatural", "ghost", "demon", "occult", "undead", "zombie", "vampire", "curse", "haunted", "gruselig", "geister", "dämonen", "übernatürlich"],
  "required_genres": ["Horror", "Supernatural"],
  "min_score": 70,
  "min_popularity": 1500,
  "exclude_genres": ["Kids"],
  "exclude_formats": ["TV_SHORT", "SPECIAL", "MUSIC"],
  "rail_id": {"anime": "horror_supernatural_anime", "manga": "horror_supernatural_manga"}
}
```

**Estimated items:** 120 anime + 120 manga (combining both genres with OR logic).

---

## 9. Proposals for New Vibe Modes (Without Rails)

These modes could work with algorithmic fallback only (no curated rail needed initially):

### 9.1 "Binge-Worthy Long-Runners"
For users who want epic, long-running series (100+ episodes or 100+ chapters).
- Opposite of `short_one_season`
- Would filter for TV format with high episode count or manga with high chapter count

### 9.2 "Staff Picks / Editor's Choice"
A rotating editorial rail that gets manually refreshed (e.g., monthly). Could highlight seasonal standouts or thematic picks. Would need a cron or manual update workflow.

---

## 10. Architecture Notes & Patterns

### How to Add a New Mode + Rail

1. **Create migration for rail seed**: Insert into `curated_rails` + `curated_rail_items` with ON CONFLICT handling.
2. **Create migration for mode config update**: Update `concierge_config` to add the new mode to the `{modes}` array and attach `rail_id`.
3. **Update edge function fallback**: Add the mode to `defaultModes()` in `index.ts` (belt-and-suspenders fallback).
4. **Update mode router**: Add intent-detection regex patterns in `mapStrongGenreToModeId()` and `scoreMode()`.
5. **Run audit**: Execute `scripts/audit_curated_rails_quality.js` to verify no adult/ecchi/kids content leaked in.

### Safety Invariants
- All curated rail queries hard-filter `is_adult = false` and exclude Hentai + Ecchi genres.
- The `curated_rail_cards` RPC is `SECURITY DEFINER` with `search_path = public`.
- Max 120 items returned per RPC call.
- User-seen items can be excluded via `p_exclude_seen = true`.

### Content Pipeline
- Curated rails are **fully pinned** (manual AniList IDs in migration files). There is no automated population from cron jobs.
- The algorithmic fallback (`recommend_ids_premium` RPC) uses tag-category matching and score/popularity thresholds.
- Seed-similarity (`recommend_ids_similar_to_seeds` RPC) provides "Similar to X" rails when the user mentions a specific title.

---

## 11. Summary Statistics

| Metric | Value |
|--------|-------|
| Total curated rails | 27 |
| Total curated items | 3,605 |
| Total vibe modes | 14 |
| Modes with curated rail_id | 14/14 (100%) |
| Non-adult anime in catalog | 9,450 |
| Non-adult manga in catalog | 11,964 |
| Materialized views | 7 |
| Anime genres tracked | 18 |
| Manga genres tracked | 18 |
| Genres with no dedicated mode | 7 (Sci-Fi, Sports, Supernatural, Horror, Mecha, Music, Mahou Shoujo) |
