# Concierge "Modes Router" Plan (Variation 1)

This file documents the idea of routing free-text "vibe" prompts into curated recommendation rails (modes), with the LLM used only as an optional presentation layer.

## Current status (as of 2026-02-08)

The core plan is fully implemented, expanded, and quality-hardened.

Implemented:
- Config-driven "modes" (curated rails) stored in DB config JSON.
- Deterministic router that picks up to 2 modes per prompt (fast, predictable, cheap).
- Backend returns grouped rails (`sets`) plus backward-compatible flattened items.
- iOS renders rails from backend `sets`.
- Classics rail expanded (do not remove existing classic boosts; return more classics by heuristic + config filters).
- **17 modes** (v6, deployed): Premium Picks, Start Here, Premium Action, Premium Comedy (grown-up), Cozy/Comfort, Dark/Serious, Hidden Gems, Classics (expanded), Short & Complete, Movie Night, Romance (serious), Romcom, Fantasy (no isekai), Isekai, **Sports**, **Sci-Fi**, **Horror & Supernatural**.
- **38 curated rails** (27 original + 11 new: sports, sci-fi, horror/supernatural anime+manga, seinen anime+manga, shoujo anime+manga, josei manga).
- Intent detectors in `scoreMode()` for movie, short, isekai/non-isekai, romcom/serious-romance, sports, sci-fi, horror disambiguation.
- Enriched synonyms with German translations across all modes.
- **Negative genre filtering**: "action but no romance", "fantasy without harem" — parsed and applied to both curated/algorithmic rails AND mode selection (excluded genres suppress conflicting mode matches in `mapStrongGenreToModeId` and penalize conflicting modes in `scoreMode`).
- **30 abbreviations** in parser (up from 10): OP, DB/DBZ/DBS, SAO, NGE/Eva, LOTGH, MP100, BC, ToG, MiA, ReZero, KonoSuba, TPN, BNHA, DM, COTE, etc.
- **Phase 0 quality overhaul** (2026-02-08): cross-rail overlap reduced from 94% to ~36%, sequels/misclassified items removed, all rails slimmed to 30-80, classics cleaned (0 post-2014 titles), isekai rebuilt (114 bogus → 14 genuine).
- **Mode analytics table** (`concierge_mode_analytics`) for tracking mode selection patterns.
- **Enhanced audit script** with 5 quality checks: overlap, franchise duplication, classics year, rail size, score floors.
- Foundation migration consolidating all core catalog tables + import tracking + materialized views + lock RPCs (schema drift resolved).
- Migration to fix legacy production drift (`tags.kitsu_id`, `comments.user_id` type): `/Applications/Kuro/supabase/migrations/20260206143000_fix_legacy_tags_and_comments.sql`.

Not implemented yet:
- On-device Core ML classifier.
- Active learning loop ("not my vibe", "too childish", etc.) feeding training data.
- Admin UI to edit modes (today: DB JSON only).

## What happened to this plan file

`/Applications/Kuro/IMPLEMENTATION_PLAN_Variation1.md` existed but was 0 bytes. The implementation moved forward in code, but this doc did not get written.

## Why this architecture is strong

It makes Concierge feel premium without paying LLM costs for every request:
- Deterministic routing + DB queries are fast and consistent.
- LLM is optional narration (and guarded by per-user + global budgets).
- The "taste" is controlled by mode constraints and editorial boosts, not prompt randomness.

## Current implementation (where it lives)

### 1) Modes config
- Migrations write `config.modes` into the single-row JSON config:
  - v1: `/Applications/Kuro/supabase/migrations/20260205190000_concierge_modes_config.sql` (6 modes)
  - v2: `/Applications/Kuro/supabase/migrations/20260205233000_concierge_modes_v2_config.sql` (8 modes + rail_id + router_llm knobs)
  - v3: `/Applications/Kuro/supabase/migrations/20260206100000_concierge_modes_v3_expanded.sql` (14 modes + enriched synonyms)
- Modes are stored at:
  - `public.concierge_config.config.modes`

Each mode supports (subset may be omitted):
- `id`, `title`
- `synonyms` (phrase matches, including German translations)
- `required_genres`
- `exclude_genres`
- `min_score`, `min_popularity`, `max_popularity`
- `exclude_formats`
- `classic_year_max` (for classics mode)
- `rail_id` (maps media type to a pinned curated rail)

### 2) Mode router + rails output
- Implemented in:
  - `/Applications/Kuro/supabase/functions/concierge-recommend/index.ts`

Key behaviors:
- Picks up to 2 rails ("modes") for each prompt.
- Biases toward including a Classics rail as a stable second rail.
- If prompt includes a seed ("like Vagabond"), replaces the primary rail with `Similar to "X"` (deterministic similarity RPC), while keeping Classics as the other rail.
- Returns:
  - `modes`: selected rails with `confidence` + `reason`
  - `sets`: array of rails, each with `title` + `items`
  - `items`: flattened (backwards compatibility and for narration)

Perf note:
- The Edge function reuses shared candidate pools and media context across rails to avoid extra DB roundtrips.

### 3) iOS rendering
- Decoding:
  - `/Applications/Kuro/Kuro/Services/SupabaseService.swift`
- UI:
  - `/Applications/Kuro/Kuro/Views/ConciergeView.swift`

Behavior:
- If backend returns `sets`, Concierge renders each set as a titled horizontal rail.
- If `sets` is missing (older backend), it falls back to the previous single list rendering.

## Reanalysis: should we do more, and what's the "better way"

### What we should keep (recommended)

Keep the current design as the default:
- Backend deterministic router + config-driven modes is the best cost/perf/iteration point.
- It already gets you 90 percent of the "premium" feel without ML complexity.

### What to improve next (highest leverage)

1. ~~Expand and tune modes in config~~ **(DONE as of v6)**
- All originally planned modes have been added, plus 3 new genre modes:
  - `Gateway / First Anime` (v2)
  - `Short One-Season` (v3: `short_one_season`)
  - `Movie Night` (v3: `movie_night`)
  - `Romance (serious)` vs `Romcom` (v3: `romance_serious`, `romcom`)
  - `Fantasy (non-isekai)` vs `Isekai` (v3: `fantasy_non_isekai`, `isekai`)
  - `Sports` (v6: `sports`) — Haikyuu, Blue Lock, Slam Dunk, Hajime no Ippo
  - `Sci-Fi` (v6: `scifi`) — Cowboy Bebop, Ghost in the Shell, Steins;Gate, Psycho-Pass
  - `Horror & Supernatural` (v6: `horror_supernatural`) — Shiki, Higurashi, Parasyte, Junji Ito
- Demographic rails added (not full modes): seinen, shoujo, josei
- Current count: **17 modes** (within the recommended 20-50 ceiling). Room for more.

2. Add a feedback loop (active learning)
- Add UI actions like:
  - "Not my vibe" (for the whole rail)
  - "More like this" / "Less like this" (for a title)
  - "Too childish" / "Too dark" quick toggles
- Log this as labeled data (user prompt -> selected mode(s) -> feedback).
- Use it to improve synonyms and scoring (and later train ML).

3. Add a lightweight evaluation harness
- Reuse the existing scripts/corpus infrastructure to measure routing stability and result quality:
  - `/Applications/Kuro/scripts/concierge_eval_parse.js` (pattern to follow)
  - Add a similar `concierge_eval_modes.js` if needed (prompt -> expected modes).

### Core ML vs server-side embedding router

Core ML (on-device):
- Pros: instant, free per request, private, works offline.
- Cons: requires a training + versioning pipeline and shipping app updates to improve routing.
- When to do it: only after we have enough real labeled data (from feedback) and we see misrouting is a real problem.

Server-side embeddings (router):
- Pros: easy to iterate without app update (update mode vectors or examples).
- Cons: embedding calls cost money and add latency; also introduces a new provider dependency.
- If you want "ML but cheap", do it offline:
  - Precompute mode centroids from synonyms.
  - Only embed user text when deterministic scoring confidence is low.
  - Cache (prompt_norm -> chosen_modes) for a while.

Pragmatic recommendation:
- Keep deterministic router as primary (already done).
- Add feedback logging + mode tuning first.
- Add ML only if metrics show it meaningfully improves routing.

## Two-mode vs one-mode routing

You previously asked for up to 2 modes. That is implemented and is a good default:
- Mode A: best-fit vibe rail
- Mode B: Classics (expanded) rail (stable, always good)

If you ever want to switch to 1-mode:
- Keep Classics as a separate fixed section in Discover (not in Concierge).
- Let Concierge always return one rail for "vibe" only.

## Deployment notes

To get the latest 17-mode router live, you must deploy:
- DB migrations (in order): **63 total migrations** — see `supabase/migrations/` for full list
  - Key mode migrations:
    - `20260205190000_concierge_modes_config.sql` (v1: 6 modes)
    - `20260205233000_concierge_modes_v2_config.sql` (v2: 8 modes + rail_id + router_llm)
    - `20260206100000_concierge_modes_v3_expanded.sql` (v3: 14 modes)
    - `20260208022110_add_sports_mode.sql` (sports rails)
    - `20260208022153_add_scifi_mode.sql` (sci-fi rails)
    - `20260208022239_add_horror_supernatural_mode.sql` (horror/supernatural rails)
    - `20260208022342_add_demographic_rails.sql` (seinen, shoujo, josei)
    - `20260208022356_update_concierge_config_new_modes.sql` (v6: 17 modes in config)
  - Key quality migrations:
    - `20260208022035_phase0_remove_sequels.sql`
    - `20260208022136_phase0_remove_misclassified.sql`
    - `20260208022250_phase0_dedup_rails.sql`
    - `20260208022326_phase0_slim_and_rerank.sql`
    - `20260208022404_phase0_fix_classics.sql`
- Edge functions (deployed):
  - `concierge-parse` (year mention extraction + boost; strips years from trigram search queries)
  - `concierge-resolve` (includes year/format tags in LLM prompt and passes them through in response)
  - `concierge-recommend` (negative-genre suppression in routing + scoring; improved seed/classics intent)
- Note: Avoid pinning Edge Function version numbers in docs. Verify actual deployed versions with:
  - `supabase functions list --project-ref bkdifromsqxkndnllmdj`
- **Adaptation disambiguation** (iOS): auto-apply guard blocks when top candidates share base title but differ in media_id. Year override: if user mentions a year matching the top candidate, auto-apply proceeds.

The iOS UI is already compatible (renders `sets` when present).

## Quality infrastructure

- **Audit script**: `scripts/audit_curated_rails_quality.js` — 5 checks: cross-rail overlap (>15%), franchise duplication, classics year (>2014), rail size (>80), score floor (category-specific). Run with `node scripts/audit_curated_rails_quality.js`.
- **Router eval**: `scripts/eval_router.js` — 63 test cases against live endpoint, 90% pass threshold. Exponential backoff for 429/5xx (up to 3 retries, honours Retry-After). Infra errors excluded from pass rate.
- **Rail generator**: `scripts/generate_rail_migration.js` — deterministic SQL from `scripts/rail_config.json`. Validates: no duplicates, max 100 items/rail, valid media types. Same config always produces same SQL.
- **Mode analytics**: `concierge_mode_analytics` table logs mode selections, synonyms matched, confidence scores, and whether the request was LLM-routed.
- **Overlap target**: No rail pair should exceed 15% overlap (was 94%, now ~36% worst-case).
