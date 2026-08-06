# Independent Review — Wave 2 (deep pass), 2026-08-06

**Reviewer:** Kimi K3. **Method:** 6 more adversarial agents (security/privacy, data integrity, performance/ops, iOS forensics, product integrity, regression archaeology), all live-verified. This document supersedes nothing in wave 1 (`2026-08-06-independent-review.md`); it extends it. **Fixes already shipped this wave are marked [FIXED + migration/commit].**

---

## CRITICAL findings (and their disposition)

### 1. Rec-edges poisoning was live and exploitable by any signed-up user [FIXED]
`upsert_rec_edges` kept its probationary `authenticated` grant after the import ended. Proven end-to-end: fresh account → inject rating-100000 edges → world-readable, **flow into edges-first serving** (rating is min-max normalized into candidate scores), stealth-merge inflates real edges with `source='anilist'` intact, no delete path, per-user fixed-window limits trivially farmable with scripted accounts. One injected edge (16→15 at 100000) was pinning a false #1 on A Silent Voice's rail in prod.
**Shipped fix (`20260806000000`):** grant revoked (import is done; service_role unaffected), poison rows deleted, 16→15 restored to 6003, seed-16 store rows re-staled for rebuild, `audit-*` buckets purged. Verified live: 403 on call, rating reads 6003.

### 2. Mirror image convergence was dead since Jul 31 — 0 rows in 5 days [FIXED]
The era-1 convergence machinery was perfect except auth: the 5 mirror crons (and both manga-chapter-enrich crons) read `app.settings.import_secret` / `supabase_url` / `supabase_anon_key` GUCs — **all empty in this project**. Every nightly run 401'd. Coverage flat at 602/600/200/201.
**Shipped fix (remote-only, via Management API — literals stay out of git):** all 7 jobs re-armed with literals transplanted from `kuro-import-anime-hourly`. Verified: 0 GUC references remain in those commands. First real convergence numbers arrive tonight 02:00–03:00 UTC. **Revealed truth:** the era-1 "convergence unblocked" claim was untrue until now; also the manga-chapter enrichment pipeline was silently dead the whole time.
**Owner follow-up:** IMPORT_SECRET rotation still pending (it's a literal in 4 import-cron commands; rotation = one `supabase secrets set` + reschedule those 4 jobs — 15 minutes, do it with the owner present).

### 3. Deck gesture trap: swiping to leave the deck records NOT FOR ME [FIXED — code review level]
Full-page card + exclusion-zone drag marking + wrong guard order in the pager's onEnded = no way to page out of the deck except the 54pt header, and leave-swipes became negative taste signals. **Shipped fix (commit `49f3227`):** edge-origin drags (24pt) never rail-mark; fast-fling check moved before rail guards; deck flicks ignore edge-origin drags. Residual risk (documented by the implementer): a fast MID-card fling both judges and pages — design-intended but worth one on-device feel test.

### 4. ~63% of the score≥70 pool silently misses the precomputed store
Probe: only 28/75 sampled quality-pool seeds serve from `media_similar_titles`; the rest fall back to the 1.5–3.1s live scorer with no entry-point mapping and no own-franchise exclusion (this is the direct cause of the wave-1 canonicalization failures). **Contradictory evidence exists** (`media_similar_seed_state` showed 7,537 seeds / 0 stale) — the table is service-role-only so the discrepancy couldn't be fully resolved from outside. *Owner action:* check store coverage vs the pool with service SQL (`select count(*) from media_similar_seed_state where built_at is not null` vs pool count) and look at driver batch failures. Until the store covers the pool, the "p95 ≤105ms" and canonicalization claims hold only for the covered slice.

## HIGH findings

5. **The 0.20 personalization cap survives only in a 0%-flagged RPC.** Because-You (uncapped similarity order), the deck's exploit slots (100% rollout), and tonight's-shelf realm selection all personalize without editorial-prior dominance, and the contract was never amended (its own rule: code disagrees → correct the file immediately). Either amend the contract to bless these paths with numbers, or gate them. This is the philosophy document lying about the product.
6. **Tonight's shelf had no franchise cap** (6/12 AoT slots for the demo profile) [FIXED `20260806010000`: ≤2 per cluster, verified live] and **the hidden gem's argument was raw scraper text** [FIXED same migration: sentence-trim + capitalization; residual wart: HTML tags survive into the argument — iOS must sanitize like the deck does].
7. **Craft lift over-promotion**: a 63-score Vending Machine sits at "acclaimed" via director lineage. [FIXED `20260806010000`: lift requires own score ≥ 70; takes effect at tonight's 04:50 tier rebuild.]
8. **rate_limit_hit was anon-callable** → anyone could DoS shared buckets. [FIXED `20260806000000`: revoked from anon+authenticated; all callers are definer functions. Verified: PGRST202.]
9. **Migration chain unreproducible — and worse than wave-1 knew**: the chain dies at migration #16 because the entire baseline catalog schema lives only in `legacy_sql/`, and `CURRENT_APP_STATE.md:2834` **falsely claims** the placeholder consolidates matviews/cron/locks. 4 hollowed Feb migrations remain hollow; 4 of the "7 non-idempotent" claims verified (3 were overstated). No gate replays the chain. *Fix direction:* capture the baseline via a management-API schema dump into a real migration; until then, treat "rebuild from migrations" as impossible.
10. **Deck signal integrity**: silent loss on record failure + retry-less shimmer. [FIXED `49f3227`: pending-retry queue with transient banner after repeated failure; 8s watchdog + retry state; offline-vs-empty copy fixed.]
11. **Penalty sign was custom, not structure.** [FIXED: CHECK(penalty <= 0) — a positive row can no longer become a silent boost.]

## MEDIUM findings (fixed or queued)

12. `discover_rail_impressions` (TEXT user_id, no FK) survives account deletion — GDPR orphan. Queued: add to delete-account flow.
13. **Deck memory**: mounted-forever pages + per-view decoded images; deck prefetch skipped downsampling [FIXED `49f3227`: prefetch now passes maxPixelSize 1200]. Pager unmount surgery deliberately deferred.
14. **Accessibility**: "I KNOW THIS" contrast (kuroWhite60 on glass ≈3.7:1) [FIXED → kuroWhite80]; undo chip 4s timing [FIXED: 8s under VoiceOver]; synopsis gesture-only [FIXED: accessibility action added]. Dynamic Type truncation of deck actions at XXXL remains (queued).
15. **One Thing hero unclamped on iPad/landscape** (984×1230pt card). Queued: cap width.
16. **Hidden gem selection** is "least famous of the most famous" (a Black Butler sequel) — the mechanic needs "no franchise the user knows" logic (partially addressed in `20260806010000`) and probably an editorial floor rethink.
17. **One dubious realm override**: WIND BREAKER promoted to horror-dread (delinquent brawler; battle-shounen fits). One-row fix during the owner veto pass.
18. Edge-floor asymmetry (2.6 floor > 2.5 cosine cap): penalized edges can't fall below clean cosine candidates. Deliberate per the fork header, but "demotion" is weaker than the word implies — owner should confirm intent.

## The measurement layer (wave-1 verdict stands, sharpened)

- **Gold seed bias quantified**: 76/80 anime seeds are top-3.1% popularity; 82 canon / 18 acclaimed / zero solid / zero tail; 13 same-franchise pairs. The 0.823 measures the fame head only.
- The committed harness's own auto-decision on heuristic labels reads **NO** (raw 0.851 / gated 0.791, Δ below the +0.05 bar). The fork shipped on an owner decision recorded in a migration header, not on the gate.
- Owner veto: still zero verdicts. Remains the single highest-value hour available.

## Ops governance notes

- Mirror/enrich re-arm this wave; the **membership/affinity refreshes run bare under the postgres role's 2-min statement_timeout** — the exact pattern that killed the tier cron 4 nights. Add SET-first guards before data doubles (one-line cron command change each).
- Tier-swap TRUNCATE can queue behind a 600s builder batch; watch 04:50–05:10.
- Suggested partial indexes for the deck/discover eligibility scans are specified in the ops agent's report (10× headroom).
- `.bak` files ship inside the app bundle; ContentView comment cites the wrong bundle id (`com.kuro.app`); docs gate red on 222→229 count drift.

## What is genuinely healthy (verified this wave)

RLS/grant matrix on all new tables; SECURITY DEFINER hygiene (search_path, no user_id params, revokes live-tested); GDPR cascades on all new user tables; overlay math (10/10 hand-computed matches); canon_seed quality (no fabrications, citations real); media_relations TV chains complete for all 10 sampled franchises; deck RPC warm latency ~300ms; Because-You/daily-feature ~95ms; club/social layer untouched by regressions.

## Files shipped this wave

- Migration `20260806000000_security_and_mirror_repair.sql` (revokes, poison cleanup, re-stale, penalty CHECK) + remote cron re-arm (API)
- Migration `20260806010000_serving_fixes_v1.sql` (shelf franchise cap, gem argument, craft-lift guard)
- Commit `49f3227` (iOS: gesture trap, signal retry, shimmer retry, a11y, prefetch downsample)
