# Kuro: Curated Content Expansion Plan

**Date:** 2026-02-08
**Sources:** Backend Analysis, Quality Review (Devil's Advocate), Concierge System Analysis

---

## Phase 0 — Fix Critical Overlap (MUST DO FIRST)

The devil's advocate review revealed that 56-58% of all curated item placements are duplicates across rails. Gateway manga and Premium Picks manga share **94.2%** of their items. This must be fixed before adding any new content.

### 0.1 Deduplicate Existing Rails

**Problem:** 27 rails with 3,605 placements but only ~1,568 unique items. Users see the same titles across different vibe modes.

**Implementation:**
1. **SQL audit query** — identify all cross-rail overlaps exceeding 15%:
   ```sql
   SELECT a.rail_id AS rail_a, b.rail_id AS rail_b,
          COUNT(*) AS shared,
          ROUND(COUNT(*)::numeric / LEAST(ac.cnt, bc.cnt) * 100, 1) AS overlap_pct
   FROM curated_rail_items a
   JOIN curated_rail_items b ON a.anilist_id = b.anilist_id AND a.media_type = b.media_type AND a.rail_id < b.rail_id
   JOIN (SELECT rail_id, COUNT(*) cnt FROM curated_rail_items GROUP BY rail_id) ac ON ac.rail_id = a.rail_id
   JOIN (SELECT rail_id, COUNT(*) cnt FROM curated_rail_items GROUP BY rail_id) bc ON bc.rail_id = b.rail_id
   GROUP BY a.rail_id, b.rail_id, ac.cnt, bc.cnt
   HAVING COUNT(*)::numeric / LEAST(ac.cnt, bc.cnt) > 0.15
   ORDER BY overlap_pct DESC;
   ```
2. **Migration: Remove duplicates** — for each pair above 15%, remove overlapping items from the less-specific rail (e.g., remove shared items from `premium_picks` that already exist in `gateway`)
3. **Backfill** — replace removed items with new unique titles that fit the rail's theme
4. **Target:** No rail pair exceeds 15% overlap post-migration

**Priority:** CRITICAL — blocks all other work
**Migration:** `20260209000000_deduplicate_curated_rails.sql`

### 0.2 Enforce One-Entry-Per-Franchise Rule

**Problem:** Attack on Titan has 5 entries in Gateway (S1, S2, S3, S3P2, Final). Uma Musume has 3 entries in Hidden Gems. This inflates rail sizes without editorial value.

**Implementation:**
1. For each franchise with multiple entries, keep only the best entry point (typically S1 or the highest-rated installment)
2. Delete sequel/recap/movie entries that aren't standalone
3. Affected rails: gateway_anime (AoT, Code Geass), hidden_gems_anime (Uma Musume, JJK)

**Priority:** CRITICAL
**Migration:** `20260209000001_one_entry_per_franchise.sql`

### 0.3 Reduce Rail Sizes to 30-80 Items

**Problem:** Rails have 120-210 items. "Curated" loses meaning at that scale — it becomes "filtered algorithm."

**Implementation:**
1. Rank all items within each rail by editorial value (score × uniqueness-to-this-rail)
2. Keep top 50 for genre-specific rails, top 80 for broad rails (gateway, classics)
3. Delete lower-ranked items via migration
4. Update `curated_rail_cards` RPC `p_limit` default from 120 to 80

**Priority:** HIGH
**Migration:** `20260209000002_slim_curated_rails.sql`

### 0.4 Fix Classics Definition

**Problem:** 31 titles from 2015+ in the Classics rail. Missing cornerstone classics (Akira, Ghost in the Shell, Trigun, Utena, Yu Yu Hakusho).

**Implementation:**
1. Remove titles newer than 2014 from `classics_anime` and `classics_manga`
2. Add missing cornerstone classics with high ranks (shown first)
3. Move removed "modern" titles to more appropriate rails (gateway, premium_picks, or genre-specific)

**Priority:** HIGH
**Migration:** `20260209000003_fix_classics_definition.sql`

### 0.5 Add Overlap Detection to Audit Script

**Implementation:**
1. Extend `scripts/audit_curated_rails_quality.js` with cross-rail overlap check
2. Flag any pair exceeding 15% overlap
3. Add one-entry-per-franchise check (detect duplicate `anilist_id` base series)

**Priority:** HIGH
**Files:** `scripts/audit_curated_rails_quality.js`

---

## Phase 1 — New Vibe Modes & Curated Rails

### 1.1 Sports Mode (HIGH PRIORITY)

**Rationale:** 558 anime + 298 manga titles. The edge function code explicitly notes sports lacks a dedicated mode. Haikyuu, Blue Lock, Kuroko, Hajime no Ippo, Slam Dunk have passionate audiences.

**Implementation:**
1. Create rails: `sports_anime`, `sports_manga`
2. Seed with 50 anime + 40 manga (hand-picked, score ≥ 72, no Kids)
3. Add mode to `concierge_config.config.modes`:
   ```json
   {
     "id": "sports",
     "title": "Sports",
     "synonyms": ["sports", "sport", "basketball", "soccer", "football", "volleyball", "boxing", "tennis", "baseball", "cycling", "running", "swimming", "haikyuu", "blue lock", "kuroko"],
     "required_genres": ["Sports"],
     "min_score": 72,
     "min_popularity": 1500,
     "exclude_genres": ["Kids"],
     "exclude_formats": ["TV_SHORT", "SPECIAL", "MUSIC"],
     "rail_id": {"anime": "sports_anime", "manga": "sports_manga"}
   }
   ```
4. Update `mapStrongGenreToModeId()` in recommend edge function (optional: only if DB-only approach isn't sufficient)
5. Run audit script

**Migration:** `20260210000000_add_sports_mode.sql`
**Edge Function:** No redeploy needed (mode config is DB-driven)

### 1.2 Sci-Fi Mode (HIGH PRIORITY)

**Rationale:** 3rd largest anime genre (2,017 titles). No current mode covers cyberpunk, space opera, dystopian, or hard sci-fi.

**Implementation:**
1. Create rails: `scifi_anime`, `scifi_manga`
2. Seed with 60 anime + 40 manga (Cowboy Bebop, Ghost in the Shell, Psycho-Pass, Steins;Gate, Planetes, Legend of the Galactic Heroes, Akira, etc.)
3. Add mode:
   ```json
   {
     "id": "scifi",
     "title": "Sci-Fi",
     "synonyms": ["sci-fi", "science fiction", "scifi", "cyberpunk", "space", "futuristic", "dystopian", "robots", "space opera", "mecha"],
     "required_genres": ["Sci-Fi"],
     "min_score": 74,
     "min_popularity": 2000,
     "exclude_genres": ["Kids"],
     "exclude_formats": ["TV_SHORT", "SPECIAL", "MUSIC"],
     "rail_id": {"anime": "scifi_anime", "manga": "scifi_manga"}
   }
   ```
4. Run audit script

**Migration:** `20260210000001_add_scifi_mode.sql`

### 1.3 Horror & Supernatural Mode (MEDIUM PRIORITY)

**Rationale:** Horror (372+706) and Supernatural (1,398+1,872) are large genres. Currently absorbed into `dark_serious`, but horror fans want different things than psychological thriller fans.

**Implementation:**
1. Create rails: `horror_supernatural_anime`, `horror_supernatural_manga`
2. Seed with 50 anime + 50 manga (Another, Shiki, Higurashi, Junji Ito Collection, Mieruko-chan, Parasyte, Hell's Paradise, etc.)
3. Add mode with OR-logic for required genres:
   ```json
   {
     "id": "horror_supernatural",
     "title": "Horror & Supernatural",
     "synonyms": ["horror", "scary", "creepy", "supernatural", "ghost", "demon", "occult", "vampire", "zombie", "curse", "haunted", "junji ito"],
     "required_genres": ["Horror", "Supernatural"],
     "min_score": 70,
     "min_popularity": 1500,
     "exclude_genres": ["Kids"],
     "exclude_formats": ["TV_SHORT", "SPECIAL", "MUSIC"],
     "rail_id": {"anime": "horror_supernatural_anime", "manga": "horror_supernatural_manga"}
   }
   ```
4. Run audit script

**Note:** `required_genres` uses OR logic in the algorithmic fallback (any of the listed genres matches). Verify this behavior in `recommend_ids_premium`.

**Migration:** `20260210000002_add_horror_supernatural_mode.sql`

### 1.4 Demographic Rails (MEDIUM PRIORITY)

**Rationale:** Demographics (Shoujo, Josei, Seinen) are a primary axis of taste for manga readers. No current rails address this. A knowledgeable manga reader expects this segmentation.

**Implementation:**
1. Create rails: `seinen_anime`, `seinen_manga`, `shoujo_anime`, `shoujo_manga`, `josei_manga`
2. These are NOT full vibe modes — they're curated rails accessible via the Discover page and recommendation fallback
3. Seed using AniList demographic tags (not genres — demographics are in the `tags` array):
   - Seinen (50 anime, 60 manga): Berserk, Monster, Vinland Saga, Ghost in the Shell, Mushishi, Vagabond
   - Shoujo (30 anime, 50 manga): Fruits Basket, Ouran, Nana, Skip Beat, Cardcaptor Sakura, Sailor Moon
   - Josei (40 manga): Chihayafuru, Nana, Honey and Clover, Paradise Kiss, Princess Jellyfish, Nodame Cantabile
4. Optionally add a `seinen` vibe mode with synonyms: "seinen", "mature", "adult manga", "grown-up", "for adults"
5. Run audit script

**Migration:** `20260211000000_add_demographic_rails.sql`

---

## Phase 2 — Concierge Parser & Recommender Improvements

### 2.1 Expand Abbreviation Map (HIGH PRIORITY)

**Current state:** Only 10 abbreviations (AoT, JJK, MHA, HxH, FMAB, OPM, CSM, JJBA, KNY, FMA).

**Add 15+ more:**
| Abbreviation | Expansion |
|-------------|-----------|
| OP | One Piece |
| DB / DBZ / DBS | Dragon Ball / Dragon Ball Z / Dragon Ball Super |
| SAO | Sword Art Online |
| BC | Black Clover |
| ToG | Tower of God |
| MiA | Made in Abyss |
| ReZero | Re:ZERO |
| KonoSuba | Kono Subarashii Sekai ni Shukufuku wo! |
| MP100 | Mob Psycho 100 |
| DS | Demon Slayer (careful: already mapped via KNY) |
| AOT | Attack on Titan (alias for AoT) |
| SOL | Slice of Life (meta, for searches) |
| NGE / Eva | Neon Genesis Evangelion |
| LOTGH / LoGH | Legend of the Galactic Heroes |
| TPN | The Promised Neverland |

**Implementation:**
1. Add to `expandCommonAbbreviations()` map in `concierge-parse/index.ts`
2. Deploy edge function

**Files:** `supabase/functions/concierge-parse/index.ts`
**Deploy:** Yes (edge function redeploy required)

### 2.2 Move Abbreviations to Database (MEDIUM PRIORITY)

**Rationale:** Hardcoded abbreviations require edge function redeploy. A DB table allows updates without deploy.

**Implementation:**
1. Create `common_abbreviations` table: `(abbreviation text PK, expansion text, added_at timestamptz)`
2. Migrate existing 10 + new 15 abbreviations into the table
3. Modify parser to fetch abbreviations from DB on cold start (cache in-memory for the request)
4. Keep hardcoded map as fallback

**Migration:** `20260212000000_abbreviation_table.sql`
**Files:** `supabase/functions/concierge-parse/index.ts`

### 2.3 Add Negative Genre Filtering (MEDIUM PRIORITY)

**Rationale:** Users say "action but no romance" or "fantasy without harem" — currently the system ignores the negative part.

**Implementation:**
1. Add `inferExcludedGenres()` function in `concierge-recommend/index.ts`:
   - Parse patterns: "no X", "without X", "not X", "minus X", "keine X" (DE)
   - Map to genre names
2. Pass excluded genres to `buildAlgorithmicRail()` as additional `exclude_genres`
3. For curated rails, post-filter items that match excluded genres

**Files:** `supabase/functions/concierge-recommend/index.ts`
**Deploy:** Yes

### 2.4 Multi-Seed Similarity (LOW PRIORITY)

**Rationale:** "Something like Cowboy Bebop and Samurai Champloo" currently only uses the first seed.

**Implementation:**
1. Modify `inferSeedQuery()` to extract multiple seeds (split on "and"/"und"/"&")
2. Call `search_titles` for each seed
3. Combine tag overlap scores from all seeds in `recommend_ids_similar_to_seeds`

**Files:** `supabase/functions/concierge-recommend/index.ts`
**Deploy:** Yes

---

## Phase 3 — Quality Infrastructure

### 3.1 Enhanced Audit Script

**Add to `scripts/audit_curated_rails_quality.js`:**
1. Cross-rail overlap detection (flag pairs > 15%)
2. Franchise duplication check (multiple entries from same series)
3. Classics year validation (flag items newer than 10 years)
4. Rail size check (flag rails over 80 items)
5. Genre coherence check (flag items whose genres don't match the rail's theme)

### 3.2 Mode Analytics Table

**Implementation:**
1. Create `concierge_mode_analytics` table:
   ```sql
   CREATE TABLE concierge_mode_analytics (
     id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     mode_id text NOT NULL,
     prompt_hash text,
     matched_synonyms text[],
     confidence real,
     was_llm_routed boolean DEFAULT false,
     created_at timestamptz DEFAULT now()
   );
   ```
2. Log mode selections in `concierge-recommend` edge function
3. Use data to identify which modes are popular, which synonyms match most, and where the router fails

**Migration:** `20260213000000_mode_analytics.sql`
**Files:** `supabase/functions/concierge-recommend/index.ts`

### 3.3 Editorial Notes

**The `curated_rail_items.note` column exists but is unused.** For new rails, populate with 1-sentence editorial justifications. This:
- Forces curators to articulate why each item belongs
- Could be surfaced in the UI as editorial blurbs
- Improves quality by requiring intentionality

---

## Implementation Priority & Order

| # | Task | Phase | Priority | Depends On | Effort |
|---|------|-------|----------|------------|--------|
| 1 | Deduplicate existing rails | 0 | CRITICAL | — | Large (manual curation) |
| 2 | One-entry-per-franchise | 0 | CRITICAL | — | Medium |
| 3 | Slim rail sizes to 30-80 | 0 | HIGH | #1 | Medium |
| 4 | Fix classics definition | 0 | HIGH | — | Small |
| 5 | Add overlap detection to audit | 0 | HIGH | — | Small |
| 6 | Sports mode + rails | 1 | HIGH | #1-3 done | Medium |
| 7 | Sci-Fi mode + rails | 1 | HIGH | #1-3 done | Medium |
| 8 | Horror/Supernatural mode + rails | 1 | MEDIUM | #1-3 done | Medium |
| 9 | Demographic rails | 1 | MEDIUM | #1-3 done | Medium |
| 10 | Expand abbreviation map | 2 | HIGH | — | Small |
| 11 | Move abbreviations to DB | 2 | MEDIUM | #10 | Small |
| 12 | Negative genre filtering | 2 | MEDIUM | — | Medium |
| 13 | Multi-seed similarity | 2 | LOW | — | Medium |
| 14 | Enhanced audit script | 3 | HIGH | — | Small |
| 15 | Mode analytics table | 3 | MEDIUM | — | Small |

---

## Key Principle

> **Fix the foundation before expanding.** The quality reviewer rated individual items B+ but curation architecture D. Adding more rails on top of 94% overlap would compound the problem. Phase 0 must complete before Phase 1 begins.
