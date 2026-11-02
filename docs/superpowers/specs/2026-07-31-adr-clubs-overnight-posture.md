# ADR 2026-07-31 — Clubs overnight posture

## Status
Locked.

## Decision
**Patch trust, don't revamp.** Ship the F1 pack:

1. **Reactions contract fix:** `toggle_club_reaction` accepts the client's canonical keys `fire`/`heart`/`eyes`/`100` (server aligns to client; keys are what bundle aggregation and UI lookups use). Unflagged repair.
2. **Privacy hole closure:** `fetch_friend_activity_for_title` and `count_friends_tracking` ported to the bundle's sharing-level semantics: exclude members whose effective sharing rank is 0 (private club or member downgrade); progress/rating detail only at effective rank ≥ 2; status-only at rank 1. No new rules invented.
3. **Invite chain:** new `kuro://join/<code>` deep link (stashes through auth via the existing pending-deep-link path, opens Clubs page with the join sheet prefilled); share text now includes the URL; non-member `kuro://club/<uuid>` copy fixed ("You're not a member yet — ask for an invite" instead of "You were removed").
4. **Flag seeding:** `clubs_reactions_v1` + `clubs_list_enriched_v1` → enabled 100% (repaired features); `clubs_realtime_v1`, `clubs_pace_sync_v1`, `clubs_notifications_v1` → seeded enabled at **0%** (remotely flippable without a migration; never-run-in-prod code paths stay dark until deliberately ramped).

## Why
Clubs' bones are good; the surface is degraded by a dead API contract, a live trust regression, and an invite chain with too much friction. Revamps (duo mode, club night ritual) are roadmap once trust is repaired.

## Consequences
- Duo-club ACTIVE tab stays k≥3 tonight; honest copy added where empty.
- Roadmap: F2 duo semantics (consent model), F3 club night, settings-sheet spec items (rename/archive/regenerate), chat backend teardown, hollowed-migration restoration.
