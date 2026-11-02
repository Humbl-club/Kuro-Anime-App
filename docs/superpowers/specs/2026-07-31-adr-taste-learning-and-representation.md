# ADR 2026-07-31 — Taste learning + representation

## Status
Locked.

## Decision
**Learning:** "The Deck" — a full-bleed, one-title-at-a-time tap-to-decide ritual (PASS / I KNOW THIS / CALLS TO ME), sessions of 12, never repeats, living at pager index 0 behind flag `taste_deck_v1`. No drag gestures in v1 (root pager uses `simultaneousGesture`; taps eliminate the conflict class entirely). Onboarding's last card gains a "Teach Kuro your taste" CTA that lands on the Deck.

**Signals:** new `taste_signal_events` event types written only via SECURITY DEFINER RPC `record_taste_deck_signal` (JWT-derived user, dedupe per user/media, `retract` action supported):
- `deck_love` **+0.55** — explicit pull toward a title
- `deck_known` **+0.25** — familiarity without sentiment (deliberately weak)
- `deck_skip` **−0.45** — explicit push away

**Representation (Sprint 02, contract-native):** `recompute_user_taste_profile(uuid)` aggregates events × `anime_tags.rank`/`manga_tags.rank` + genres into `user_taste_profiles` (jsonb: `genres`, `tags`, `avoided_tags`, `confidence`, `event_count`, `computed_at`). Contract numbers honored: import discount ×0.25, confidence tiers 0.05/0.10/0.15/0.20 (0–4/5–14/15–30/30+ strong events), title mass cap 8%, franchise cap 15%. **Avoidance floors (B4):** a tag enters `avoided_tags` only with ≥2 negative signals OR cumulative negative weight ≤ −0.8; per-tag negative mass capped at −1.0 so one skip never exiles a genre.

**Drain:** pure-SQL pg_cron every 15 min (`select public.drain_taste_recompute_queue()`), 50 users/run, stamps `processed_at`, captures per-user errors. No HTTP/GUC cron pattern.

**Consumer (one, isolated):** new `fetch_personalized_new_to_you` RPC — same candidate pool rules as Discover NEW TO YOU (score ≥ 80, ancillary formats excluded, not in user lists, impression-memory rotation) plus `personalized_fit × confidence ≤ 0.20` ordering influence and avoided-tag penalty. Discover uses it only when `personalized_new_to_you_v1` (seeded 0%) is on. `discover_bundle` and matviews untouched.

## Why
Capture already worked; consumption was dark. This makes taste a readable asset with one honest consumer, fully flag-reversible, and gives cold start a beautiful front door instead of a marketing carousel.

## Consequences
- Profile inspectable via "Your leanings" sheet on the Deck (top genres/tags + avoided).
- Mis-taps reversible via `retract`.
- Personalized ranking has numeric rules and a 0% flag; editorial prior remains dominant.
- Roadmap: drag gestures + `deck_v1` sheet iteration, B2 compass, D2 Today page, retention policy for events (append-only tonight by design).
