# ADR 2026-07-31 — Design direction for new UI

## Status
Locked as law for all new/touched surfaces from this date.

## Decision
1. **One Hero Grammar (H1):** full-bleed image + grain overlay (`kuroWhite04` in `.overlay` blend, the club-hero recipe) + dual gradient (legibility bottom, vignette top) + bottom-pinned serif masthead + tracked-caps eyebrow. Every new hero uses it; the Deck is its flagship.
2. **Motion tokens only (H3):** new UI animates exclusively through `KuroAnimation` (`editorial` spring 0.6/0.82 for commits and settles, `fast` 0.25 for micro-feedback) with `KuroMotion.resolve` honoring Reduce Motion. No new ad-hoc `.animation(.ease…)`. Deck purposeful motions (exactly three): card settle (scale 0.96→1 + crossfade on deal), commit exit (directional slide + 8° tilt, editorial spring, light→medium haptic ladder), summary reveal (staggered serif lines).
3. **One placeholder spec (H4):** `kuroSecondaryBackground` + `kuroShimmer` + 0.2s fade-in for every image in new/touched surfaces; failure glyph `photo` in `kuroTextTertiary`.
4. **Typography stance:** serif leads (masthead `kuroFeature`/`kuroHeadline`, italic serif for reflective lines), sans serves (tracked-caps eyebrows/labels via `kuroMicro`/`kuroCaption`). The Deck's session summary is the app's first true `kuroDisplay` moment.
5. **Discover hero drift fix:** raw `.system(size: 20, …, design: .serif)` → existing `kuroTitle`-class token at the same rendered size (drift reduction, not redesign; size bump deferred to a daylight visual pass).
6. **Deferred:** warm paper/ink global tokens (H2), designed-absence monograms (E3) — both need a dedicated pass with visual QA.

## Why
The brand is 70% true; new work must not become a third visual dialect. Constraints chosen so every new surface is recognizably Kuro on first render.

## Consequences
- Design review checklist for new UI: hero grammar present, motion tokens only, placeholder spec, serif-led hierarchy, monochrome (red only destructive).
- Drift backlog documented (spacing adoption ~27%, `Cards.swift`/`KuroRefinedCard.swift` pre-token) for a future consolidation pass.
