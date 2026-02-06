# Concierge "Modes Router" Plan (Variation 1)

This file documents the idea of routing free-text "vibe" prompts into curated recommendation rails (modes), with the LLM used only as an optional presentation layer.

## Current status (as of 2026-02-05)

The core of this plan is already implemented in the codebase, but this file was accidentally created as an empty placeholder.

Implemented:
- Config-driven "modes" (curated rails) stored in DB config JSON.
- Deterministic router that picks up to 2 modes per prompt (fast, predictable, cheap).
- Backend returns grouped rails (`sets`) plus backward-compatible flattened items.
- iOS renders rails from backend `sets`.
- Classics rail expanded (do not remove existing classic boosts; return more classics by heuristic + config filters).

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
- Migration writes `config.modes` into the single-row JSON config:
  - `/Applications/Kuro/supabase/migrations/20260205190000_concierge_modes_config.sql`
- Modes are stored at:
  - `public.concierge_config.config.modes`

Each mode supports (subset may be omitted):
- `id`, `title`
- `synonyms` (phrase matches)
- `required_genres`
- `exclude_genres`
- `min_score`, `min_popularity`, `max_popularity`
- `exclude_formats`
- `classic_year_max` (for classics mode)

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

1. Expand and tune modes in config (no app deploy needed)
- Add modes you mentioned but are not yet present:
  - `Gateway / First Anime`
  - `Short One-Season`
  - `Movie Night`
  - `Romance (serious)` vs `Romcom`
  - `Fantasy (non-isekai)` vs `Isekai`
- Keep mode count roughly 20-50 max. Too many rails makes routing worse and UI noisier.

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

To get the new rails live, you must deploy:
- DB migration:
  - `/Applications/Kuro/supabase/migrations/20260205190000_concierge_modes_config.sql`
- Edge function:
  - `/Applications/Kuro/supabase/functions/concierge-recommend/index.ts`

The iOS UI is already compatible (renders `sets` when present).
