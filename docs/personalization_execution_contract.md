# Personalization Execution Contract

**Status:** Active planning contract  
**Last updated:** 2026-07-30  
**Scope:** Kuro personalization, recommendation reranking, explanation policy, club taste, and continuation intelligence  
**Primary rule:** Editorial curation stays dominant. Personalization may rerank inside curated bounds but may not replace them.

### Sprint 01 design lock (2026-07-30)

Locked for implementation (backend capture only; no Discover/Search/Browse ranking):

1. **Rating scale:** live DB `anime_user_lists.rating` / `manga_user_lists.rating` are `integer` with `CHECK (rating >= 1 AND rating <= 10)`. Thresholds: `rating_high >= 8`, `rating_low <= 4`. (Stale 10–100 docs are wrong; trust live DB.)
2. **UUID cast:** list `user_id` stays TEXT; triggers use safe `_taste_parse_user_id` and **never** fail the list write on bad cast.
3. **Import origin:** no new list column. `concierge-apply` calls `begin_taste_import_context` / `clear_taste_import_context` (short-lived `taste_import_context` row). PostgREST cannot span `SET LOCAL` across separate upsert requests, so the context table is the production substitute for session-local GUC marking.
4. **Out of scope for Sprint 01:** Discover UI, Search/Browse ranking, profile computation, streaming flag, CDN mirror.

---

## 0) Why this file exists

This file is not a brainstorm.

It is the execution contract for personalization work in Kuro. It exists to prevent rushed implementation, vague ranking logic, silent scope expansion, and sloppy LLM execution.

This file defines:
- what personalization is allowed to do
- what personalization is not allowed to do
- how each sprint is considered complete
- which files and backend surfaces are allowed to change
- which tests, artifacts, and review gates are mandatory
- what triggers a rollback

If code and this file disagree, code wins temporarily, then this file must be corrected immediately.

---

## 1) Program thesis

Kuro should not try to win by being the biggest anime or manga database.

Kuro should win by helping users decide correctly, quickly, and with trust.

Personalization exists to improve four decisions:
- what should I start
- what should I continue
- what should we watch or read together
- where do I go next after I finish this

Personalization does **not** exist to:
- make Search fuzzy or chaotic
- surface ancillary junk by default
- override curation with noisy user behavior
- become an unreviewable black box

---

## 2) Non-negotiable operating rules

1. **Editorial prior stays dominant.**
   - Personalization may rerank only inside curated candidate pools.
   - Personalization may not promote low-quality or ancillary items into default surfaces.

2. **V1 uses durable signals only.**
   - Allowed: status changes, meaningful progress, completion, drop, score, verdict, rewatch/reread, anime-to-manga continuation.
   - Forbidden in v1: detail opens, search opens, scroll depth, hover, dwell time, random taps, provider-sheet opens.

3. **Search is not personalized in v1.**
   - `search_anime_page` and `search_manga_page` remain title-first and deterministic.

4. **Browse is not personalized in v1.**
   - `browse_anime_page` and `browse_manga_page` remain filter-first and editorially clean.

5. **`New to You` is the first personalized surface.**
   - No other home rail gets personalized before `New to You` is proven.

6. **Server-side truth wins.**
   - Taste capture must come from server-side list mutations, not app-only telemetry.

7. **No fuzzy words in implementation.**
   - Terms like `high`, `low`, `meaningful`, `strong`, `mature`, and `fresh` must be numerically defined in this file before any ranking code ships.

8. **No UI rollout before replay evidence exists.**
   - Ranking changes must have replay fixtures and a before/after diff.

9. **No undocumented migration or RPC change.**
   - If backend behavior changes, this file and current-state docs must be updated in the same initiative.

10. **No silent scope expansion.**
    - A sprint may not add new personalized surfaces, new event classes, or new recommendation objectives unless the sprint contract explicitly allows them.

---

## 3) Decision matrix

### Personalize now (v1)
- `discover_bundle -> new_to_you`

### Personalize later
- future `watch_tonight`
- future `continue_tonight`
- `concierge-recommend` reranking within curated candidates
- club decision rails
- continuation prompts

### Do not personalize in v1
- `search_anime_page`
- `search_manga_page`
- `browse_anime_page`
- `browse_manga_page`
- default adaptation-path ordering
- default provider ordering

### Never personalize by weak noisy signals in v1
- detail open
- search open
- scroll depth
- dwell time
- card impression only
- provider tap only

---

## 4) Codebase grounding

These are the current concrete touchpoints.

### Existing profile placeholder
- `/Applications/Kuro/supabase/migrations/20260203171100_concierge_core.sql`
  - `public.user_taste_profiles`
  - currently: `user_id`, `vector jsonb`, `updated_at`
  - status: existing schema, not an active production ranking backbone

### Current discover surface
- `/Applications/Kuro/Kuro/Services/SupabaseService.swift`
  - `fetchDiscoverBundle(...)`
- `/Applications/Kuro/Kuro/Views/EditorialDiscoverView.swift`
- `/Applications/Kuro/supabase/migrations/20260326221000_discover_new_to_you_rotation.sql`
- `/Applications/Kuro/supabase/migrations/20260326234000_exclude_ancillary_anime_from_default_surfaces.sql`

### Current list mutation paths
- `/Applications/Kuro/Kuro/Services/SupabaseService+UserLists.swift`
- `/Applications/Kuro/Kuro/Views/QuickVerdictActionCard.swift`
- `/Applications/Kuro/Kuro/Views/AddToListSheet.swift`
- `/Applications/Kuro/supabase/functions/concierge-apply/index.ts`

### Current continuation path
- `/Applications/Kuro/supabase/migrations/20260307150000_adaptation_ladder_v2_editorial_context.sql`
- `/Applications/Kuro/supabase/migrations/20260307163000_fix_adaptation_ladder_entry_point.sql`
- `/Applications/Kuro/supabase/functions/bulk-import-anime/index.ts`
- `/Applications/Kuro/supabase/functions/bulk-import-manga/index.ts`
- `/Applications/Kuro/Kuro/Services/SupabaseService+Clubs.swift`
  - `get_media_ladder` fetch path

### Important current limitations
- Episode-to-chapter mapping does **not** exist today.
- `DiscoverViewModel.swift` exists but is not the main discover logic surface.
- `anime_user_lists.user_id` and `manga_user_lists.user_id` are text-backed current write surfaces; trigger work must handle this carefully when writing UUID-backed taste tables.

---

## 5) Glossary and fixed numeric definitions

### Rating thresholds
- `rating_high = >= 8`
- `rating_low = <= 4`
- ratings are stored in DB on a **1–10** scale (`CHECK (rating >= 1 AND rating <= 10)` on list tables)
- UI may still use stars/display helpers, but taste capture thresholds apply to the **DB integer 1–10** value directly
- historical docs that claimed a 10–100 DB scale are superseded by live schema

### Meaningful progress
- `meaningful_progress_anime = max(3 episodes, 25% of known total episodes)`
- `meaningful_progress_manga = max(5 chapters, 20% of known total chapters)`
- if total is unknown:
  - anime fallback: `>= 3 episodes`
  - manga fallback: `>= 5 chapters`

### Signal classes
- `weak_signal`
  - contributes little or nothing to taste profile
  - may contribute to confidence only if explicitly allowed later
- `strong_signal`
  - contributes materially to taste profile
- `very_strong_signal`
  - top-tier preference or avoidance signal

### Allowed v1 signal weights
- `planned_add = +0.10`
- `planned_add_removed_quickly = -0.20`
- `status_current = +0.30`
- `meaningful_progress = +0.45`
- `completed = +0.70`
- `rewatch_reread = +0.90`
- `verdict_masterpiece = +1.00`
- `verdict_okay = +0.55`
- `verdict_bad = -0.85`
- `rating_high = +0.70`
- `rating_low = -0.70`
- `dropped = -0.80`
- `anime_to_manga_continue = +0.85`

### Import discount
Imported history is weaker than live behavior.
- `import_signal_multiplier_default = 0.25`
- `import_signal_multiplier_planned = 0.10`
- imported signals may contribute to initial shape but may not instantly create a mature profile

### Confidence progression
- `0-4 strong signals -> confidence multiplier 0.05`
- `5-14 strong signals -> confidence multiplier 0.10`
- `15-30 strong signals -> confidence multiplier 0.15`
- `30+ strong signals -> confidence multiplier 0.20`

### User influence cap
- `max_user_influence = 0.20`
- editorial prior remains the dominant ranking term

### Context fit (v1 definition)
`context_fit` in v1 is limited to:
- legal availability if already trustworthy on the relevant surface
- completion/commitment fit
- in-progress momentum for `continue_tonight`
- current release relevance only where a surface already supports it

`context_fit` in v1 does **not** include:
- time of day
- session length
- app-open timing heuristics
- ephemeral browsing behavior

### Novelty and repetition
- novelty may improve ordering, but may not outrank editorial quality
- repetition penalty must be active for any personalized rail

### Hard editorial exclusions
- ancillary anime remain excluded on default surfaces unless the user deliberately filters into them
- low-quality material below the editorial threshold may not be promoted by personalization

---

## 6) Ranking contract

### Core formula

```text
final_score
= editorial_prior
+ personalized_fit * confidence_scaled_user_weight
+ context_fit
+ novelty_bonus
- repetition_penalty
- friction_penalty
```

### Hard invariants
- `editorial_prior` is always the largest term
- `personalized_fit` cannot bypass curated candidate eligibility
- `confidence_scaled_user_weight <= max_user_influence`
- personalization cannot override hard exclusions
- repetition penalty is always active on personalized rails
- ranking inputs must remain explainable

### Forbidden ranking behavior
- no direct personalization on the full catalog
- no weak-signal-only profile boosts
- no title/franchise runaway dominance
- no ancillary promotion into default surfaces
- no Search rank mutation in v1

### Required caps
- no single title may contribute more than `8%` of total profile mass
- no single franchise may contribute more than `15%` of total profile mass
- no single genre cluster may dominate without cross-signal support

If implementation needs different numeric caps, this file must be updated before code is merged.

---

## 7) Fixture users (must exist before personalization rollout)

These are not personas. They are explicit test fixtures.

### `empty_user`
- no list entries
- no ratings
- no verdicts
- expected behavior:
  - near-pure editorial outputs
  - almost no personalization effect

### `import_heavy_old_history_user`
- large imported completed history
- sparse live behavior
- mixed ratings
- expected behavior:
  - broad initial taste shape
  - low-to-moderate confidence only
  - imports do not instantly dominate home rails

### `prestige_completion_user`
- many completed high-rated dramatic or critically strong works
- few drops
- strong completion behavior
- expected behavior:
  - stronger fit toward prestige and complete narratives
  - still bounded by curated pool

### `long_shounen_dropper`
- starts long-running titles
- drops them repeatedly
- prefers shorter, finished works
- expected behavior:
  - lower ranking for very long commitment candidates

### `cozy_manga_user`
- manga-heavy
- high verdicts on calm or character-driven works
- expected behavior:
  - manga recommendation fit rises where personalized surfaces allow it

### `chaotic_sampler`
- many planned adds
- many starts
- low completion
- mixed scores
- expected behavior:
  - low confidence
  - personalization stays weak

### `club_member_outlier`
- strong niche preferences unlike the rest of a synthetic club
- expected behavior:
  - later club aggregation cannot fully hijack shared picks

For each fixture, implementation must provide:
- exact list rows
- exact ratings
- exact verdicts
- exact progress values
- exact expected top outputs or directional expectations

---

## 8) Review rubric

Every sprint review must answer these questions explicitly.

1. Can this pollute curation?
2. Can this overfit one title or franchise?
3. Can this leak ancillary content into default surfaces?
4. Can this degrade Search or Browse?
5. Can this be explained simply?
6. Is every threshold numeric?
7. Is rollback possible?
8. Is the feature-flag boundary clear?
9. Are the tests real, not ceremonial?
10. Are the replay fixtures sufficient for the changed surface?

If any answer is weak, incomplete, or hand-wavy, the sprint is not approved.

---

## 9) Rollback policy

Every ranking-affecting sprint must have:
- a feature flag
- a rollback path
- a replay artifact
- a metrics diff

### Mandatory rollback triggers
Rollback or disable the flag immediately if any of these occur:
- ancillary or filtered-only content leaks into default surfaces
- recommendation repetition rises materially
- curator review fails
- recommendation quality regresses even if CTR improves
- Search or Browse behavior changes unintentionally
- ranking output can no longer be explained cleanly

### Minimum rollback assets
- name of affected feature flag
- migration/RPC list touched
- scripts or commands used to evaluate before/after outputs
- last known good state

---

## 10) Global LLM execution checklist

No sprint may start unless this checklist is completed.

- [ ] Read the sprint section in this file in full
- [ ] Read all files listed under `Files allowed to change`
- [ ] Read all listed migrations/RPCs before editing them
- [ ] Confirm all fuzzy terms are numerically defined
- [ ] Confirm the feature flag strategy exists
- [ ] Confirm rollback path exists
- [ ] Confirm replay fixtures exist or are part of the sprint scope

No sprint may finish unless this checklist is completed.

- [ ] Build passes
- [ ] Targeted tests pass
- [ ] Replay diff generated
- [ ] Curator review completed
- [ ] Docs updated
- [ ] No forbidden file touched
- [ ] No undefined terms remain
- [ ] All thresholds are numeric
- [ ] Rollback path is documented
- [ ] Feature flag exists if ranking behavior changed

If any item is unchecked, the sprint is not done.

---

## 11) Sprint contract template

Every sprint below uses the same structure.

Required sections:
- Goal
- User promise
- Non-goals
- Allowed surfaces
- Forbidden surfaces
- Data contracts
- Files allowed to change
- Migrations / RPCs allowed to change
- Feature flags
- Acceptance criteria
- Failure conditions
- Validation commands
- Required artifacts
- Docs to update
- Rollback plan
- Done only if

---

# Sprint contracts

## Sprint 00 — Scope lock and glossary freeze

### Goal
Lock the rules before implementation starts.

### User promise
Kuro will personalize carefully, not chaotically.

### Non-goals
- no code
- no migrations
- no UI changes

### Allowed surfaces
- docs only

### Forbidden surfaces
- app code
- backend code
- SQL behavior changes

### Data contracts
- glossary
- decision matrix
- ranking contract
- rollout contract

### Files allowed to change
- this file
- `/Applications/Kuro/CURRENT_APP_STATE.md`
- `/Applications/Kuro/CURRENT_APP_STATE_PLAIN.md`
- `/Applications/Kuro/IMPLEMENTATION_PLAN_Variation1.md`
- `/Applications/Kuro/docs/documentation-surface-map.md`

### Migrations / RPCs allowed to change
- none

### Feature flags
- define names only
- do not implement yet

### Acceptance criteria
- all fuzzy terms are numerically defined
- all allowed and forbidden personalized surfaces are listed
- feature-flag names are agreed

### Failure conditions
- any fuzzy term remains undefined
- Search/Browse policy is ambiguous
- import discount remains unspecified

### Validation commands
- `git diff --check`
- `python3 scripts/quality-gates/check_docs_current_state.py`

### Required artifacts
- finalized glossary
- finalized decision matrix
- finalized feature-flag names

### Docs to update
- same as allowed files

### Rollback plan
- revert doc-only change

### Done only if
- [ ] Every threshold is numeric
- [ ] Every v1 surface is explicit
- [ ] Every forbidden surface is explicit
- [ ] Docs are updated
- [ ] No code changed

---

## Sprint 01 — Durable taste signal capture

### Goal
Capture durable taste signals from list-state mutations and verdict changes.

### User promise
Kuro starts learning from what the user actually commits to, not from noisy browsing behavior.

### Non-goals
- no personalized ranking yet
- no discover UI changes yet
- no Search/Browse changes

### Allowed surfaces
- backend mutation capture only

### Forbidden surfaces
- Search ranking
- Browse ranking
- Discover UI presentation

### Data contracts
Create:
- `public.taste_signal_events`
Optional create:
- `public.taste_profile_recompute_queue`

Minimum columns for `taste_signal_events`:
- `id`
- `user_id`
- `media_id`
- `media_type`
- `event_type`
- `event_strength`
- `signal_value jsonb`
- `source_transition jsonb`
- `created_at`

### Files allowed to change
- new migration(s) under `/Applications/Kuro/supabase/migrations/`
- `/Applications/Kuro/supabase/functions/concierge-apply/index.ts` only if needed for compatibility, not for primary signal creation

### Migrations / RPCs allowed to change
- `anime_user_lists` trigger additions
- `manga_user_lists` trigger additions
- optional recompute queue support

### Feature flags
- none required for signal capture itself

### Acceptance criteria
- insert/update/delete transitions emit correct semantic taste events
- `concierge-apply` mutations are captured via trigger path
- no-op updates do not create spam events
- import-origin events are marked so import discount can be applied later
- rating thresholds use live DB 1–10 scale (`>=8` / `<=4`)

### Failure conditions
- app-only logging becomes the source of truth
- repeated no-op updates emit noise
- invalid `user_id` casting can break mutations

### Validation commands
- targeted SQL tests for row transitions
- event count sanity checks on fixture users
- `supabase db lint --linked`

### Required artifacts
- event schema examples
- transition matrix: `OLD -> NEW -> emitted event`
- duplicate suppression rules

### Docs to update
- `/Applications/Kuro/CURRENT_APP_STATE.md`
- `/Applications/Kuro/CURRENT_APP_STATE_PLAIN.md`
- `/Applications/Kuro/IMPLEMENTATION_PLAN_Variation1.md`
- memory

### Rollback plan
- disable trigger path by reverting migration or rolling forward with safe no-op trigger

### Done only if
- [x] Server-side trigger path is the source of truth
- [x] Import-origin events are marked
- [x] No noisy event spam remains
- [x] Transition tests pass
- [x] UUID/text user-id handling is safe

### Shipped surfaces (2026-07-30)
- Migration: `supabase/migrations/20260730160000_taste_signal_events_v1.sql`
- Tables: `taste_signal_events`, `taste_profile_recompute_queue`, `taste_import_context`
- Triggers: `taste_capture_anime_user_lists`, `taste_capture_manga_user_lists`
- Edge: `concierge-apply` begin/clear import context around list upserts

---

## Sprint 02 — Profile computation v1

### Goal
Compute a stable, capped user taste profile from durable signals.

### User promise
Kuro becomes slightly more personal only when the user has given enough real evidence.

### Non-goals
- no live home-surface changes yet
- no Concierge changes yet
- no Clubs changes yet

### Allowed surfaces
- backend profile computation only

### Forbidden surfaces
- Search
- Browse
- Discover UI
- user-facing taste settings

### Data contracts
Extend `public.user_taste_profiles` with:
- `profile_version`
- `confidence_score`
- `strong_signal_count`
- `weak_signal_count`
- `last_signal_at`
- `debug_summary jsonb`

Keep `vector jsonb` for:
- genre weights
- theme weights
- tone weights
- format weights
- length preferences
- completion bias
- avoidance weights
- source/continuation bias

Create:
- `public.recompute_user_taste_profile(p_user_id uuid)`

### Files allowed to change
- new migration(s) under `/Applications/Kuro/supabase/migrations/`
- replay/fixture scripts under `/Applications/Kuro/scripts/` if needed for profile verification

### Migrations / RPCs allowed to change
- `public.user_taste_profiles`
- new profile recompute function(s)

### Feature flags
- `taste_profile_v1` may gate downstream consumers, not profile computation itself

### Acceptance criteria
- profile output is normalized and bounded
- strong-signal counts and confidence are populated
- imports are discounted correctly
- one title/franchise cannot dominate the profile

### Failure conditions
- imported history instantly creates a mature profile
- weak signals influence profile in v1
- profile fields are too vague to debug

### Validation commands
- fixture-user recompute runs
- profile snapshot diff outputs
- `supabase db lint --linked`

### Required artifacts
- exact weight table
- exact decay rules
- exact cap rules
- fixture-user outputs

### Docs to update
- current-state docs
- implementation plan
- memory

### Rollback plan
- downstream consumers stay disabled behind flag if profile quality is not acceptable

### Done only if
- [ ] Confidence is explicit and numeric
- [ ] Weight table is explicit and numeric
- [ ] Import discount is implemented
- [ ] Fixture outputs are sane
- [ ] No single title/franchise runaway remains

---

## Sprint 03 — Discover personalization v1 (`New to You` only)

### Goal
Use the profile to rerank `new_to_you` only.

### User promise
`New to You` becomes more relevant without becoming weird, repetitive, or lower quality.

### Non-goals
- no Search personalization
- no Browse personalization
- no other discover rails personalized yet

### Allowed surfaces
- `public.discover_bundle`
- `New to You` consumption path in iOS

### Forbidden surfaces
- `search_anime_page`
- `search_manga_page`
- `browse_anime_page`
- `browse_manga_page`
- other discover rails

### Data contracts
Rerank `new_to_you` using:
- `editorial_prior`
- `personalized_fit`
- `confidence_scaled_user_weight`
- `novelty_bonus`
- `repetition_penalty`
- `friction_penalty`

### Files allowed to change
- new migration updating `discover_bundle`
- `/Applications/Kuro/Kuro/Services/SupabaseService.swift`
- `/Applications/Kuro/Kuro/Views/EditorialDiscoverView.swift`

### Migrations / RPCs allowed to change
- `public.discover_bundle`
- supporting SQL helpers only if documented

### Feature flags
- `discover_personalization_v1`

### Acceptance criteria
- only `new_to_you` is personalized
- outputs stay inside curated candidate bounds
- repetition does not increase materially
- curator review passes

### Failure conditions
- other rails become personalized accidentally
- ancillary material leaks into defaults
- output quality drops even if engagement rises

### Validation commands
- replay top-8 before/after for fixture users
- rail diversity/repetition diff
- `supabase db lint --linked`

### Required artifacts
- ranking formula
- replay diff
- curator signoff checklist for top outputs

### Docs to update
- current-state docs
- implementation plan
- memory

### Rollback plan
- disable `discover_personalization_v1`

### Done only if
- [ ] Only `new_to_you` changed
- [ ] Replay diff exists
- [ ] Curator review passed
- [ ] Repetition did not spike
- [ ] Search/Browse are untouched

---

## Sprint 04 — Explanation layer

### Goal
Explain personalized picks in one short editorial line.

### User promise
Users can understand why a recommendation is there without reading a paragraph.

### Non-goals
- no long-form AI explanations
- no new personalized surfaces

### Allowed surfaces
- discover recommendation payload
- discover cards/UI only

### Forbidden surfaces
- Search
- Browse
- freeform essay generation

### Data contracts
Add explanation payload fields such as:
- `primary_reason`
- `commitment_label`
- `availability_label`

### Files allowed to change
- discover-related migration/RPC output
- `/Applications/Kuro/Kuro/Views/EditorialDiscoverView.swift`
- relevant discover card components

### Migrations / RPCs allowed to change
- `public.discover_bundle`
- supporting SQL helpers if documented

### Feature flags
- piggyback on `discover_personalization_v1` or add `discover_reason_labels_v1`

### Acceptance criteria
- every personalized recommendation has one short valid reason
- explanation matches real ranking inputs
- explanation is editorial, not robotic

### Failure conditions
- explanations become verbose
- explanations overclaim unavailable signals
- reasons become generic filler

### Validation commands
- screenshot review
- localization review
- explanation-to-ranking consistency checks

### Required artifacts
- explanation template bank
- forbidden-copy examples
- screenshot set

### Docs to update
- current-state docs
- implementation plan
- memory

### Rollback plan
- disable explanation labels while keeping ranking if needed

### Done only if
- [ ] One-line max is enforced
- [ ] Reasons are grounded in real inputs
- [ ] Copy review passed
- [ ] No generic filler text remains

---

## Sprint 05 — `Watch Tonight` and `Continue Tonight`

### Goal
Convert personalization into compact decision modules.

### User promise
Kuro helps the user decide what to do tonight instead of forcing them to browse aimlessly.

### Non-goals
- no giant new shelves
- no Clubs changes yet

### Allowed surfaces
- discover bundle additions only
- discover UI additions only

### Forbidden surfaces
- Search
- Browse
- Concierge

### Data contracts
Add discover outputs:
- `watch_tonight`
- `continue_tonight`

### Files allowed to change
- discover migration/RPCs
- `/Applications/Kuro/Kuro/Views/EditorialDiscoverView.swift`
- supporting discover card components if necessary

### Migrations / RPCs allowed to change
- `public.discover_bundle`

### Feature flags
- `discover_tonight_modules_v1`

### Acceptance criteria
- modules are compact: 1-4 items max
- `watch_tonight` uses curated + availability/commitment-aware logic
- `continue_tonight` prefers genuine in-progress momentum

### Failure conditions
- modules become giant rails
- modules duplicate existing rails without clearer value
- weak browsing signals are used as momentum proxies

### Validation commands
- replay outputs
- screenshot review
- conversion comparison vs old home behavior

### Required artifacts
- module contract
- candidate eligibility rules
- screenshot set

### Docs to update
- current-state docs
- implementation plan
- memory

### Rollback plan
- disable `discover_tonight_modules_v1`

### Done only if
- [ ] Modules are compact
- [ ] User promise is clearer than old rails
- [ ] Momentum uses durable signals only
- [ ] Curator review passed

---

## Sprint 06 — Concierge reranking

### Goal
Use the taste profile to improve recommendation ordering in Concierge without touching intent routing.

### User promise
Concierge recommendations become more personally relevant while staying mode-correct and curated.

### Non-goals
- no FM/router changes
- no global recommendation redesign

### Allowed surfaces
- `/Applications/Kuro/supabase/functions/concierge-recommend/index.ts`
- recommendation ordering and explanation only

### Forbidden surfaces
- intent classification
- Search
- Browse

### Data contracts
Taste profile may rerank within curated candidate sets only.

### Files allowed to change
- `/Applications/Kuro/supabase/functions/concierge-recommend/index.ts`
- related helper files only if documented
- minimal iOS rendering changes if payload shape changes

### Migrations / RPCs allowed to change
- backend function contracts only as documented

### Feature flags
- `concierge_personalization_v1`

### Acceptance criteria
- Concierge mode integrity remains intact
- reranked outputs show better fit without collapsing diversity
- reasons remain explainable

### Failure conditions
- personalization overrides mode constraints
- one genre floods all rails
- outputs become less editorial

### Validation commands
- replay prompt set for fixture users
- diversity checks
- curator review

### Required artifacts
- before/after prompt-output diffs
- diversity report
- curator review notes

### Docs to update
- current-state docs
- implementation plan
- memory

### Rollback plan
- disable `concierge_personalization_v1`

### Done only if
- [ ] Intent routing is untouched
- [ ] Mode constraints are preserved
- [ ] Replay output quality improved
- [ ] Diversity remains healthy

---

## Sprint 07 — Club taste and group coordination

### Goal
Create fair, actionable group recommendations.

### User promise
Kuro helps a small group decide what to watch or read together without one member dominating the result.

### Non-goals
- no public social expansion
- no generic feed work

### Allowed surfaces
- club recommendation logic
- club recommendation surfaces only

### Forbidden surfaces
- public/global recommendation behavior
- Search/Browse changes

### Data contracts
Group ranking must use:
- overlap-aware aggregation
- shared availability constraints where trustworthy
- minority-dislike penalty
- commitment-size fit

### Files allowed to change
- new migrations/RPCs for club recommendation outputs
- club UI surfaces only

### Migrations / RPCs allowed to change
- new club recommendation RPCs/helpers

### Feature flags
- `club_personalization_v1`

### Acceptance criteria
- one member cannot hijack results
- outputs are realistically actionable for the group
- shared availability is respected where applicable

### Failure conditions
- plain averaging dominates
- one outlier member hijacks recommendations
- recommendations are not actually available to most members

### Validation commands
- synthetic club fixture replay
- fairness review
- screenshot review

### Required artifacts
- club aggregation mini-spec
- synthetic club outputs
- fairness review notes

### Docs to update
- current-state docs
- implementation plan
- memory

### Rollback plan
- disable `club_personalization_v1`

### Done only if
- [ ] Group fairness rule is explicit
- [ ] Synthetic fixtures pass
- [ ] One-user dominance is prevented
- [ ] Results are actionable

---

## Sprint 08 — Continuation intelligence (title-level first)

### Goal
Make the post-finish next step clearer without inventing chapter-accurate data.

### User promise
After finishing something, Kuro can usually say what comes next at the title level, and only becomes chapter-specific when data is truly trustworthy.

### Non-goals
- no forced episode-to-chapter mapping in v1
- no franchise encyclopedia UI

### Allowed surfaces
- adaptation/continuation backend
- detail and post-finish continuation surfaces

### Forbidden surfaces
- fake chapter-accurate continuation when no trustworthy mapping exists
- noisy relation spam

### Data contracts
Continuation states must be explicit:
- `known`
- `partial`
- `unknown`
- `do_not_show`

### Files allowed to change
- relevant ladder/continuation migrations
- relevant detail-page continuation surfaces

### Migrations / RPCs allowed to change
- `public.get_media_ladder(...)` and supporting ladder helpers only as documented

### Feature flags
- `continuation_intelligence_v1`

### Acceptance criteria
- title-level continuation is correct and concise
- chapter-accurate continuation is shown only where truly supported
- unknown states are honest

### Failure conditions
- chapter mapping is inferred from weak data
- continuation copy overclaims precision
- noisy relation clutter leaks into detail pages

### Validation commands
- top-title fixture review
- unknown-state review
- adaptation accuracy spot checks

### Required artifacts
- continuation state matrix
- supported-vs-unsupported precision table
- screenshot set

### Docs to update
- current-state docs
- implementation plan
- memory

### Rollback plan
- disable `continuation_intelligence_v1`

### Done only if
- [ ] Title-level continuation is trustworthy
- [ ] Unknown states are honest
- [ ] No fake precision ships
- [ ] Curator review passed

---

## Sprint 09 — Hardening and rollout control

### Goal
Prove the system improves the product before broad rollout.

### User promise
Personalization should make Kuro more useful, not noisier.

### Non-goals
- no new recommendation ideas
- no new personalized surfaces

### Allowed surfaces
- evaluation scripts
- metrics dashboards
- flags and rollout controls

### Forbidden surfaces
- uncontrolled broad rollout
- ranking changes without replay evidence

### Data contracts
Required evaluation artifacts:
- replay harness
- ranking diff report
- fixture library
- curator signoff checklist
- metrics dashboard

### Files allowed to change
- scripts under `/Applications/Kuro/scripts/`
- relevant docs
- minimal rollout plumbing only if documented

### Migrations / RPCs allowed to change
- only if needed for evaluation metrics and documented explicitly

### Feature flags
- all relevant personalization flags must be listed and reversible

### Acceptance criteria
- replay harness exists
- ranking diff exists
- guardrail metrics are tracked
- rollback switches are documented and tested

### Failure conditions
- rollout proceeds without replay evidence
- metrics optimize curiosity instead of usefulness
- no rollback path exists

### Validation commands
- replay suite
- metrics sanity checks
- flag disable/rollback smoke test

### Required artifacts
- replay harness output
- curator review package
- rollback checklist
- rollout checklist

### Docs to update
- current-state docs
- implementation plan
- memory

### Rollback plan
- disable relevant flags
- restore prior ranking path

### Done only if
- [ ] Replay harness exists
- [ ] Metrics dashboard exists
- [ ] Rollback was smoke-tested
- [ ] Curator review approved rollout
- [ ] Guardrail metrics are explicit

---


## 12) Ticket-style execution backlog

These tickets are intentionally narrow. They exist so an implementer cannot claim a sprint is “mostly done” while skipping the hard parts.

### Sprint 00 ticket set

- `PERS-00A` — Freeze glossary and constants
  - Output: all fuzzy terms converted into numeric thresholds in this file
  - Blocker if missing: Sprint 01 may not start
- `PERS-00B` — Freeze decision matrix
  - Output: explicit list of personalized-now, personalized-later, and never-personalized surfaces
  - Blocker if missing: no backend ranking work may start
- `PERS-00C` — Freeze feature-flag map
  - Output: approved flag names and rollout order
  - Blocker if missing: no rollout-capable change may merge

### Sprint 01 ticket set

- `PERS-01A` — Create `taste_signal_events`
  - Must include schema, indexes, and RLS decision if needed
- `PERS-01B` — Add semantic triggers on `anime_user_lists`
  - Must map row transitions into durable events
- `PERS-01C` — Add semantic triggers on `manga_user_lists`
  - Must mirror anime behavior exactly where applicable
- `PERS-01D` — Mark import-origin events
  - Must allow later import discounting
- `PERS-01E` — Add transition test coverage
  - Must include insert, update, delete, and no-op cases

### Sprint 02 ticket set

- `PERS-02A` — Extend `user_taste_profiles`
  - Add governance fields and versioning
- `PERS-02B` — Implement `recompute_user_taste_profile(...)`
  - Must be deterministic for the same input event history
- `PERS-02C` — Add cap and decay enforcement
  - Must prevent title/franchise runaway dominance
- `PERS-02D` — Add fixture-user dataset
  - Must be concrete rows, not prose personas
- `PERS-02E` — Produce profile snapshot report
  - Must show before/after or expected outputs per fixture

### Sprint 03 ticket set

- `PERS-03A` — Snapshot current `new_to_you` baseline
  - Must exist before reranking lands
- `PERS-03B` — Add personalized rerank term to `discover_bundle`
  - Must affect `new_to_you` only
- `PERS-03C` — Preserve impression memory and repetition penalty
  - Must not regress freshness behavior
- `PERS-03D` — Generate replay diff for top outputs
  - Must compare baseline vs personalized outputs
- `PERS-03E` — Curator approval pass
  - Must explicitly approve or reject the changed outputs

### Sprint 04 ticket set

- `PERS-04A` — Define explanation templates
  - Must include allowed and forbidden examples
- `PERS-04B` — Add explanation fields to personalized payload
  - Must be short and deterministic
- `PERS-04C` — Render explanations in discover cards
  - Must keep layout compact
- `PERS-04D` — Explanation truthfulness review
  - Must verify explanation reasons actually match ranking factors

### Sprint 05 ticket set

- `PERS-05A` — Define `watch_tonight` candidate policy
  - Must include commitment and availability rules
- `PERS-05B` — Define `continue_tonight` candidate policy
  - Must use durable in-progress signals only
- `PERS-05C` — Add compact modules to discover payload
  - Must stay within 1-4 items each
- `PERS-05D` — Add discover UI modules
  - Must not create giant new shelves

### Sprint 06 ticket set

- `PERS-06A` — Identify all Concierge rerank insertion points
  - Must preserve mode constraints
- `PERS-06B` — Add taste-aware reranking inside curated candidates
  - Must not touch intent routing
- `PERS-06C` — Replay prompt set against fixture users
  - Must compare diversity and mode correctness before/after

### Sprint 07 ticket set

- `PERS-07A` — Write club aggregation mini-spec
  - Must define fairness, tie-breaks, and minority-dislike policy
- `PERS-07B` — Implement club recommendation backend path
  - Must remain isolated from solo-user ranking
- `PERS-07C` — Validate synthetic club fixtures
  - Must prove one-user dominance is prevented

### Sprint 08 ticket set

- `PERS-08A` — Define continuation state matrix
  - Must distinguish known, partial, unknown, do-not-show
- `PERS-08B` — Add title-level continuation outputs only
  - Must not fake chapter-accurate precision
- `PERS-08C` — Review top-title continuation examples
  - Must prove copy is honest and compact

### Sprint 09 ticket set

- `PERS-09A` — Build replay harness
  - Must be runnable against fixture users and current ranking outputs
- `PERS-09B` — Build ranking diff report
  - Must compare editorial-only vs personalized outputs
- `PERS-09C` — Build rollout checklist and rollback smoke test
  - Must prove flags can be disabled cleanly
- `PERS-09D` — Final curator signoff package
  - Must include metrics, replay outputs, and approval status

### Ticket completion rule

A ticket is not complete if any of the following are missing:
- explicit changed files
- explicit validation commands
- explicit output artifact
- explicit reviewer signoff owner
- explicit rollback note if the ticket changes ranking behavior

---

## 13) Final execution rule

No sprint is considered complete because code exists.

A sprint is complete only when:
- the contract is satisfied
- the artifacts exist
- the replay evidence exists
- the review gate passed
- the rollback path exists
- the docs were updated

If any one of those is missing, the sprint is not done.
