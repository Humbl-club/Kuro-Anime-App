# ADR 2026-07-31 — Image / CDN convergence strategy

## Status
Locked.

## Decision
Fix the two root causes found in Phase 0, then add an attention-driven loop:

1. **Stop un-mirroring (DB trigger, not TS checks):** BEFORE UPDATE triggers on `anime`, `manga`, `characters`, `staff` preserve any image column already pointing at Supabase Storage (`%/storage/v1/%`) when an import tries to overwrite it with a remote URL. One place, covers all current and future writers.
2. **Converging selection:** mirror-images selects remote-only rows (`cover_image_large NOT LIKE '%/storage/v1/%'`), popularity-desc for anime/manga; character/staff ordered by catalog join count (visibility), not id asc. A persisted cursor (`mirror_cursor` row in ops state) walks the tail so nightly windows always advance.
3. **Mirror-on-view:** opening a detail page with remote art calls `enqueue_image_mirror` (SECURITY DEFINER, media-type allowlist, dedupe), which sets `priority_at` on `image_mirror_state`; the worker drains priority rows first, then the cursor.
4. **Measurement:** `image_mirror_coverage` metrics view (per media type: total / mirrored / % ) + nightly snapshot into the ops dashboard path. Before/after numbers go into the morning brief.

## Why
Coverage was structurally capped (~top-600 head, import erosion nightly). Premium feel requires owning our imagery; the fix is selection logic + one trigger + an attention loop — no product-surface risk.

## Consequences
- Convergence is provable (coverage view numbers nightly).
- Deck deals mirrored-first, so the strategy is user-visible immediately.
- Cron schedule unchanged (5 nightly jobs); only selection semantics change.
