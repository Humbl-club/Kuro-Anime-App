# ADR 2026-07-31 — Monetization posture (no ads, ever)

## Status
Locked. Ads, rewarded ads, feed ads, paid ranking injection, and fake free streaming are permanently banned. Club paywalls (G4) banned.

## Decision
**Posture:** Kuro earns when it genuinely helps you get to the thing — affiliate commerce on links users already tap (G1), growing into editorial commerce (G3 "Kuro Selects" buying guides), with a voluntary Patron membership (G2) as the long-term trust-aligned tier.

**Tonight's scaffold (bounded, reversible):**
- `outbound_link_events` table (RLS; user_id from JWT only; validated `link_kind`/`provider` enums; media_type/media_id; created_at) + `record_outbound_link` SECURITY DEFINER RPC (rate-limited).
- **Retention in the same migration:** 90-day rollup-and-purge via the housekeeping cron family (no third unbounded table).
- iOS instrumentation on existing WATCH/READ CTAs and ExternalLinksSection taps (fire-and-forget, never blocks navigation).
- `affiliate_links_v1` flag seeded **OFF**; no affiliate registry, no URL decoration, no StoreKit tonight.

**Compliance notes:** affiliate decoration requires per-program disclosure (Amazon Associates, BookWalker, Kobo) and App Store review honesty; links must remain editorially chosen first, monetized second — decoration never changes which providers we show or their order. Legal review precedes any flag flip.

## Why
You can't backfill taps you never recorded. The ledger compounds; everything else can wait for daylight.

## Consequences
- Morning report includes click counts by provider/kind.
- Roadmap: G1 decoration pass (flag-gated), G3 Selects on curated_rails infra, G2 Patron (StoreKit + entitlements, no feature ransom).
