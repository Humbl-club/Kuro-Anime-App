# Concierge Editorial Visual Delta (v1)

## Purpose
Replace the current mixed Concierge look with a cohesive editorial surface that matches the rest of Kuro.

This pass is presentation-focused:
- Keep existing Concierge behavior (parse/recommend/clarify/auto-apply).
- Replace layout/composition/card language so the visual delta is obvious.
- Keep performance constraints as first-class acceptance criteria.

## Direction
- Mode: **Light-only** for Concierge surface.
- Tone: Calm, editorial, typographic, monochrome.
- UX principle: Choices should be beautiful and easy to scan; no "chore" flows.

## Core Layout
1. Header block
   - `CONCIERGE` micro-label
   - One-line subtitle that explains value
2. Composer dock
   - Stable, premium container for input + send
3. Intent deck (empty state)
   - Three clear routes:
     - Import list
     - Find recommendations
     - Quick paste
4. Response stage
   - Message stream with stable spacing rhythm
5. Action footer
   - Quiet helper text
   - Contextual undo when import session exists

## Tokens and Rhythm
- Horizontal padding: `16` (compact), `20` (major sections)
- Vertical rhythm: `8 / 12 / 16 / 24`
- Radius:
  - cards: `KuroRadius.md`
  - pills/buttons: `KuroRadius.sm`
- Color:
  - primary text: `black.opacity(0.84)`
  - secondary text: `black.opacity(0.52)`
  - separators: `black.opacity(0.06)`
  - surfaces: `Color.kuroBackground`, soft white overlays only

## Typography
- Title label: `kuroMicro(weight: .medium)` + tracking
- Headline/subtitle: `kuroBody(weight: .light)`
- Card title: `kuroBody(weight: .regular)`
- Meta/help text: `kuroCaption(weight: .light)`

## Motion
- No ornamental loops.
- Allowed transitions:
  - content entry (fast fade+slide)
  - selection confirmation (micro scale)
  - state swap (crossfade)
- Durations: ~140–220ms for micro interactions.

## Performance Constraints
- Network call starts immediately when send is tapped.
- Optimistic append remains immediate.
- Keep prefetch fanout capped.
- Avoid expensive off-center transforms in recommendation rails.

## Acceptance
1. Visual delta is obvious within 5 seconds on Concierge page.
2. Empty state provides clear, premium choices (not plain text fallback).
3. No regression to clarify/auto-apply/import/recommend flows.
4. Build + existing quality gates pass.
5. Screenshot pack captured for:
   - empty state
   - active input
   - clarify
   - import review
   - recommendation stage
