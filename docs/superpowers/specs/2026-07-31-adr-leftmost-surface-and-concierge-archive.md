# ADR 2026-07-31 — Leftmost surface + Concierge archive

## Status
Locked.

## Decision
Pager order becomes **[Taste (Deck), Discover, Browse, Collection, Clubs]**; default remains Discover. Concierge is **archived, not gutted**: all code and edge functions preserved; entry points become a Profile row ("Concierge") and the existing `kuro://concierge` deep link (both wired). `taste_deck_v1` flag (seeded 100%) gates the new page — rollback is one DB UPDATE restoring Concierge at index 0.

Red Team conditions adopted: no pager drag-gesture changes beyond the page swap; the Deck's gestures are taps, so the root `simultaneousGesture` arbitration is untouched; header behavior on page 0 returns to standard (search/profile visible).

## Why
Chat is a tool; taste is an identity. The left edge is the app's soul slot, and a place you visit to be *known* beats a box you must feed. Concierge's real usage (imports) already lives in Profile. Tap-to-decide is the Kuro-native form: considered judgment over reflex flicking — editorial, not Tinder.

## Consequences
- Onboarding copy updated (no more "Start with Concierge"); final card CTA → Deck.
- Concierge remains fully functional via Profile/deep link; header un-hides on page 0.
- V2 roadmap: card drags with proper exclusion zones, Deck as modal sheet variant, D2 Today page evaluation.
