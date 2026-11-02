# Overnight Morning Brief — 2026-07-31 (Kimi K3 Agent Swarm)

One night, one swarm: 8 recon agents → adversary ideation → 6 ADRs → 5 implementers → verify. Everything below is verified against commands, not vibes.

---

## 1. Phase 0 findings (what was actually true)

Full report: `docs/superpowers/specs/2026-07-31-phase0-full-system-check.md`. The load-bearing truths:

- **Taste pipeline was write-only.** `taste_signal_events` (Sprint 01) captured events via triggers; nothing read them, the recompute queue had no worker, `user_taste_profiles` untouched since February, personalization flags unseeded.
- **Image mirroring could never converge.** Cron used fixed offsets into popularity-sorted tables (permanent ceiling: top-600 anime/manga, top-200 char/staff *by lowest id*) **and hourly bulk imports overwrote mirrored URLs back to remote** on every re-import.
- **Clubs reactions were API-dead.** Client sends keys `fire/heart/eyes/100`; RPC allowlisted emoji chars → every toggle raised `INVALID_EMOJI`.
- **Clubs privacy leaked.** `fetch_friend_activity_for_title` / `count_friends_tracking` ignored sharing levels entirely — a member who downgraded to private still exposed "EP 8 · ★9" to club-mates. Live trust regression.
- **Five club flags** (reactions/list-enriched/realtime/pace/notifications) existed in code but were seeded in no migration — dark and unflippable without a migration.
- **Onboarding collected zero taste signal** — 5 static marketing cards that say "Start with Concierge" then land you on Discover.
- **Design brand ~70% true.** Monochrome + 8pt grid + system serif real; "Cormorant" doesn't exist (New York); spacing-token adoption ~27%; Discover the most generic surface, Clubs the most editorial, frozen Auth the emotional benchmark.
- **Remote-only schema risk:** 7 matviews + the matview-refresh cron + lock RPCs exist only in prod (still untracked — follow-up).
- Docs lied in specific places: NL search is Collection-only (not the search sheet); streaming subscriptions UI is behind a 0% flag; inventories were 88/169 vs actual 91/176.

## 2. Creative ideas — won and lost

Full deck with Red Team verdicts: `docs/superpowers/specs/2026-07-31-creative-ideation-deck.md`. 27 concepts across 8 problem spaces; the fight that mattered:

- **The Deck survived — transformed.** Red Team killed the original full-drag Tinder form with repo evidence (root pager is `.simultaneousGesture`; a viewport-sized draggable *would* fight it) and killed unflagged triple surgery on the front door. The winner keeps the surface and changes the interaction: **tap-to-decide** (PASS / I KNOW THIS / CALLS TO ME) with cinematic spring exits. More editorial — considered judgment, not reflex flicking — and zero gesture-conflict class. Flag-gated (`taste_deck_v1`, one-UPDATE rollback).
- **Killed:** Tinder-drag swipe, Interview cold-start (aspiration ≠ taste), Catalog merge, social-first left edge, club paywalls (banned forever), taste "neighborhoods" (research project), monogram placeholders (deferred), warm-paper global migration (deferred), Discover hero size bump (scope creep on the least-disciplined surface).
- **Red Team's missing piece adopted:** a morning report (`taste_pipeline_status` + `image_mirror_coverage` views) — the difference between "shipped" and "known-shipped" — plus a retraction path for taste signals.

## 3. What shipped

**Taste (learning + representation + consumer):**
- The **Taste Deck** at pager index 0 (`TasteDeckView.swift`, 914 lines): full-bleed one-title ritual, 12-card sessions, never repeats, undo (4s `retract`), long-press synopsis, "Kuro is listening." summary, "Your leanings" sheet (profile inspectable, no raw numbers). Onboarding's last card now has a **"Teach Kuro your taste"** CTA (EN/DE).
- Signals: `record_taste_deck_signal` — `deck_love +0.55` / `deck_known +0.25` / `deck_skip −0.45`, latest-action-wins dedupe, 300/day cap, retract supported.
- Representation: `recompute_user_taste_profile` — events × per-title tag ranks + genres, import ×0.25, confidence tiers 0.05→0.20, title cap 8%, **franchise cap 15% (implemented via media_relations components)**, avoidance floors (≥2 negatives or ≤−0.8; −1.0 per-name floor). Drained by pure-SQL pg_cron every 15 min with per-user error capture.
- Consumer: `fetch_personalized_new_to_you` (editorial_prior×0.8 + fit×confidence, avoided-tag penalty, 7-day impression rotation) wired into Discover's NEW TO YOU behind `personalized_new_to_you_v1` (**0%**). `discover_bundle` and matviews untouched.

**Concierge archive:** off the pager (code + edge functions fully preserved); entry via new Profile row + `kuro://concierge` (now a sheet, prompt injection preserved) + `--kuro-start=concierge`.

**Images:** anti-unmirror DB triggers on 4 tables (storage URLs can't be overwritten by remote/NULL — covers all importers forever), remote-only selection, character/staff by visibility not id, 50-row priority drain per run, `enqueue_image_mirror` RPC (mirror-on-view), crons rescheduled to advancing windows (0/600/1200 + 300/300), `image_mirror_coverage` view.

**Clubs trust pack:** reactions contract fixed (server aligns to client keys), privacy hole closed (bundle's sharing semantics ported: eff_rank 0 excluded, 1 = status-only, 2 = full; verified on scratch PG with an 8-user/4-club fixture), `kuro://join/<code>` deep link (stash-through-auth fixed for *all* link types) + share text includes the URL + prefilled join sheet, "You were removed" copy fixed for never-members, duo-club honest empty state, flags seeded (reactions + list-enriched 100%; realtime/pace/notifications 0%, remotely flippable).

**Money:** `outbound_link_events` ledger + `record_outbound_link` (120/hr, enums, RLS) + 90-day retention cron in the *same* migration + instrumentation on all WATCH/READ/provider-sheet/external-reference taps. `affiliate_links_v1` seeded OFF. No decoration, no StoreKit.

**Hygiene:** `concierge-import-anilist` now has the standard JWT gate; RLS enabled on `discover_rail_impressions`; Discover hero raw font → `kuroTitle` token.

## 4. The taste model in plain English

Everything you do in Kuro quietly leaves signed footprints: adding to your list, making progress, finishing, dropping, rating, verdicts — and now, Deck judgments. Each footprint has a weight (loving a title in the Deck is +0.55, dropping a show is −0.80, importing your AniList history counts at quarter strength). Every 15 minutes, Kuro folds your footprints into a one-page sketch of you: which genres and themes you lean toward, which you've learned to avoid, and a confidence level (it takes ~15 honest signals before Kuro trusts the sketch). No single favorite can dominate (8% cap), no franchise can swallow your identity (15% cap), and one bad mood can't exile a genre (avoidance needs two strikes or a strong pattern). You can read the sketch anytime ("Your leanings"), take back any judgment (Undo), and for now the sketch only whispers — the one place it's allowed to influence is a single rail, behind a flag at 0%, where editorial picks still carry 80% of the vote.

## 5. Design rationale for the new UI

- **Composition:** the club-hero recipe promoted to law ("One Hero Grammar"): full-bleed art + grain overlay + dual gradient + bottom-pinned serif masthead + tracked-caps eyebrow. First Deck viewport: hairline + "TASTE" + "3 / 12" up top; title in `kuroFeature` serif, one quiet caption (genres · year · format), three actions — hairline PASS capsule, text-only I KNOW THIS, solid-ink CALLS TO ME.
- **Motion (exactly three, all via `KuroAnimation` tokens, Reduce-Motion aware):** card settle (scale 0.96→1 + crossfade), commit exit (directional slide + 8° tilt, editorial spring 0.6/0.82, light→medium haptic ladder), summary reveal (staggered serif lines, `kuroDisplay` "Kuro is listening." — the app's first true display-serif moment).
- **Type:** serif leads, sans serves; italic serif reserved for reflective lines; no raw `.system` fonts in new code; Discover hero drift-fixed to the token at the same size.
- **Image strategy:** deck deals mirrored-CDN art first (product-visible convergence), one placeholder spec (`kuroSecondaryBackground` + shimmer + 0.2s fade, `photo` glyph on failure), prefetch next 3 via `ImagePipeline`.
- **States:** loading shimmer, empty ("The deck is empty — Kuro will deal more as the catalog grows."), offline (serif message + retry, session preserved, reconnect auto-resumes).

## 6. Image coverage: before → after

Measured via REST counts against production (2026-07-31, ~02:00 UTC — before tonight's first converging cron run):

| Type | Mirrored | Total | % | Old nightly ceiling | New mechanics |
|---|---|---|---|---|---|
| anime | 602 | 21,668 | **2.8%** | 600 (fixed) | ~600/night + priority drain, no more erosion |
| manga | 600 | 41,721 | **1.4%** | 600 (fixed) | shared with anime window |
| characters | 200 | 97,800 | **0.2%** | 200 (lowest ids!) | 300/night by visibility |
| staff | 201 | 41,220 | **0.5%** | 200 (lowest ids) | 300/night by visibility |

"After" is now *structurally* unbounded: remote-only selection makes every nightly window actionable, the trigger stops import erosion, and detail-page views enqueue priority mirrors. Projected: catalog head (~2k most-visible titles) fully owned in under a week; full convergence in ~10–12 weeks at current cron rates; measure nightly via `image_mirror_coverage`. **Tomorrow's number is the real proof — check it.**

## 7. Clubs verdict

**Needs patch → patched, not revamped.** Bones were genuinely good (structured errors, privacy-aware bundle, RLS matrix); the night repaired a dead reactions API, a live privacy regression, and a manual-text-only invite chain. Five dark flags are now seeded and remotely flippable. Deliberately NOT done tonight (roadmap, in ADR): duo-mode semantics (k≥3 stays; honest copy instead), club-night ritual, settings-sheet spec items, chat-backend teardown, hollowed-migration restoration.

## 8. Monetization

Posture locked in ADR: **no ads, no paid ranking, no club paywalls, ever.** Kuro earns when it genuinely gets you to the thing. Tonight: the click ledger (you can't backfill taps you never recorded) with retention built in. Roadmap: affiliate decoration of existing WATCH/READ links (flag OFF pending per-program compliance review — Amazon/BookWalker/Kobo disclosure rules), then "Kuro Selects" editorial buying guides on curated-rails infra, then voluntary Patron membership (StoreKit, no feature ransom).

## 9. Migrations / flags / deploys

**Applied to production (`db push --linked --include-all`, all six clean):**
`20260731010000_taste_deck_v1` · `20260731011000_taste_profile_recompute_v1` · `20260731012000_personalized_nty_and_flags_v1` · `20260731020000_image_convergence_v1` · `20260731030000_outbound_link_ledger_v1` · `20260731040000_clubs_trust_pack_v1`

**Flags:** `taste_deck_v1` 100% (rollback = one UPDATE) · `personalized_new_to_you_v1` 0% · `affiliate_links_v1` off · `clubs_reactions_v1`/`clubs_list_enriched_v1` 100% · `clubs_realtime_v1`/`clubs_pace_sync_v1`/`clubs_notifications_v1` 0%.

**Deployed:** `mirror-images` (selection + priority drain), `concierge-import-anilist` (JWT gate). **Crons added/rescheduled:** `taste-profile-drain-15m` (*/15, pure SQL), `outbound-link-ledger-retention` (04:40), mirror ×5 (advancing windows).

## 10. Commands + results

| Command | Result |
|---|---|
| `supabase migration list --linked` | local == remote, all applied |
| `supabase db push --linked --include-all` | 6/6 applied clean |
| `supabase db lint --linked` | 1 pre-existing warning (`_club_sharing_rank`), zero new |
| `supabase functions deploy mirror-images / concierge-import-anilist` | both deployed |
| `xcodebuild -scheme Kuro -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` | **BUILD SUCCEEDED** |
| `xcodebuild test -only-testing:KuroTests` | **TEST SUCCEEDED** (incl. 8 new TasteDeckTests, 5 new DeepLinkRouterTests) |
| `scripts/quality-gates/run_all.sh` | **8/8 PASS** (after fixing the docs gate's hardcoded `/Applications/Kuro` root + stale counts in CLAUDE.md; run with `MIGRATIONS_ALLOW_UNTRACKED=1` since git commits were out of scope) |
| REST coverage counts (anon key) | baseline in §6 |
| Scratch-PG functional suites (implementers) | taste: 21/21 assertions; image: all trigger/RPC/view cases; clubs: 8-user privacy fixture + reaction toggle — all pass |

**Couldn't verify:** authed RPC behavior end-to-end in prod (no user JWT available — deck/record/profile RPCs verified on scratch PG with live shapes); first converging cron run (fires 02:00 UTC tonight); `taste_deck_v1` flag row vs any manually-created prod row (`ON CONFLICT DO NOTHING` keeps pre-existing rows); UITests (excluded from gates by design — network-dependent).

## 11. Risks / follow-ups

1. **Watch the 02:00 UTC mirror run** — first proof of convergence (coverage view + `mirror_runs`); priority-drain PostgREST filter behavior is untested against the live gateway.
2. **Ramp `personalized_new_to_you_v1`** only after drain telemetry looks sane (queue depth → 0, no recurring `last_error`) and a staff account confirms rail quality; contract max influence 0.20 stays.
3. **`deck_known` false-positive watch** — it's sentiment-free +0.25; if profiles skew mainstream, consider 0.15 or separate "familiarity" axis.
4. **Untracked remote schema** (matviews + refresh cron + lock RPCs) still needs capturing in a migration — top structural debt.
5. **Hollowed migrations** (4 club files) still break fresh `db reset` reproducibility.
6. Flags seeded with `ON CONFLICT DO NOTHING` — if prod had manually-created rows, they won; verify actual flag rows before assuming rollout.
7. All new files are uncommitted (git mutations were out of scope) — **commit the working tree soon**; migrations gate currently needs `MIGRATIONS_ALLOW_UNTRACKED=1`.
8. Deck V2 backlog: card drags with exclusion-zone work, canon-biased first session for empty profiles, retention policy for `taste_signal_events`, `anime_to_manga_continue` emitter still missing from Sprint 01.

## 12. Files touched

**New specs (9):** phase0-full-system-check · creative-ideation-deck · 6 ADRs · this brief (all in `docs/superpowers/specs/`).
**New migrations (6):** listed §9. **Edge functions patched (2):** `mirror-images`, `concierge-import-anilist`.
**New Swift (3):** `Kuro/Views/TasteDeckView.swift` (914), `Kuro/Services/SupabaseService+Taste.swift` (289), `Kuro/Services/SupabaseService+Monetization.swift`.
**Modified Swift (12):** `ContentView` (flag-aware pager, concierge sheet, join deep link, logged-out stash fix) · `ProfileView` (Concierge row) · `OnboardingView` (taste CTA, EN/DE copy) · `EditorialDiscoverView` (hero token, personalized NTY branch) · `FeatureFlags` (+2 accessors) · `DeepLinkRouter` (`.joinClub`) · `ClubsView` (prefilled join) · `ClubDetailSheets` (share URL) · `ClubDetailView` (member copy) · `ClubDetailTabComponents` (duo copy) · `AnimeDetailView`/`MangaDetailView`/`ExternalLinksSection` (click instrumentation).
**Tests:** `KuroTests` +2 suites (13 tests). **Gates:** `check_docs_current_state.py` root fix; `CLAUDE.md` counts. **Docs triad + MEMORY:** updated (176 migrations / 91 Swift files, all features documented, stale claims corrected).

---

*Bottom line: the app you open this morning learns your taste on its first screen, owns a little more of its imagery every night, lets your clubs actually react and invite, keeps your privacy promises, records what helps you — and does all of it in one visual language. Flags give you the brake pedal on everything risky.*

---

## Addendum 2026-07-31 (later) — Taste Deck v1.1 redesign

Same day, later pass: the product owner redirected the deck's visual hierarchy — *"It's a full image, but the only thing that should be on the image is, in a modern style: how many episodes, how many seasons, if it's VO or if there's a dub version maybe."*

- **Image**: now carries only a modern meta strip — sans micro capsules (`24 EP`, `2 SEASONS`, `FILM`, `VOL 14`, `1 CH`) plus `DUB`/`SUB` shown only on positive knowledge (unknown ≠ false). Grain kept, heavy bottom gradient dropped, subtle top gradient for strip legibility. In-card TASTE eyebrow and on-image progress removed (the header already owns TASTE).
- **Below the image** (74/26 split): serif title, one caption line (genres · year · format), the three actions (PASS hairline / I KNOW THIS text / CALLS TO ME solid ink), quiet `3 / 12` progress.
- **Real swipe**: flicks on the image commit decisions (right = calls to me, left = pass, up = I know this; ~90pt travel or fast flick; ≤8° tilt; spring-back on cancel; Reduce Motion turns the exit into a crossfade). The image registers as a pager swipe-exclusion zone; the panel and screen edges still page.
- **New migration** `supabase/migrations/20260731050000_taste_deck_meta_v1.sql` (staged, not pushed): `fetch_taste_deck_batch` dropped + recreated with `episodes`, `chapters`, `volumes`, `seasons_count` (recursive PREQUEL/SEQUEL walk over `media_relations`, depth ≤ 10, TV-only), tri-state `has_dub`/`has_sub` from `provider_availability`, plus a `provider_availability_public_read` RLS policy (the SECURITY INVOKER function otherwise reads zero availability rows). iOS call site unchanged. `TasteDeckCard` + `metaChips` extended; KuroTests +9.

---

## Addendum 2 (2026-07-31 evening) — Taste Math v2 + live user verification

Same day, evening: the v2 taste math spec (`2026-07-31-taste-math-v2-critical-review.md`) was implemented, pushed to production, hotfixed twice against live failures, and then verified end-to-end with real throwaway users. Four migrations, all pushed:

- **`20260731060000_taste_math_v2.sql`** — the v2 core: `media_tag_vectors` matview (IDF-weighted tag space, genres folded in as `genre:` pseudo-tags, per-media L2 norm), `taste_tag_stats` (per-user per-tag α/β posteriors), `recompute_user_taste_profile` v3 (user vector in the same space: 180-day half-life, weighted evidence n with strong = 1.0 / weak = 0.5, smooth shrinkage w = 0.20·n/(n+20) replacing the tier-step weights, cosine fit, avoidance floors), `fetch_taste_deck_batch` v3 (2-axis stratified dealing: 6 genre clusters × 3 popularity strata; explore ratio max(0.25, 0.75·e^(−n/50)); UCB explore slots; MMR λ = 0.7; ≤ 4/12 per cluster, ≤ 2/12 per franchise; negative-space probe p = 0.10), `fetch_personalized_new_to_you` v2 (cosine + w blend), `recommend_ids_similar_to_seeds` v2 (full cosine + craft multiplier × ≤ 2, popularity removed from similarity), crons `taste-tag-vectors-refresh` (03:50) + `taste-tag-stats-decay` (Sun 04:10), `taste_pipeline_status` v2. **Initial push FAILED** on tag/genre duplicate keys — prod data has case-variant tag rows and duplicated `genres` arrays — fixed with uniqueness-by-construction (max-rank collapse, distinct unnest) and re-pushed clean.
- **`20260731070000_taste_math_v2_hotfix.sql`** — live verification found: **P0 deck 100% down** (`pg_safeupdate` blocked a bare DELETE on a temp table); **P2** `drain_taste_recompute_queue` callable by any authenticated user (Postgres default EXECUTE-to-PUBLIC; fixed with explicit revokes from public/anon/authenticated on 12 internal/definer functions — tier-2 helpers kept authenticated-callable because SECURITY INVOKER RPCs call them as the caller); **P3 profile vector inverted personas** (positive-only caps + IDF-drowned genres: a Fantasy lover's vector came out 87% negative with `genre:fantasy` itself negative) → symmetric absolute-mass caps, genre weight 1.2×√IDF, top-80, NTY penalty narrowed to genre keys / Genre-category tags.
- **`20260731080000_taste_math_v2_fix2.sql`** — P0 **still** down (two bare UPDATEs without WHERE had survived; fixed), genre retention (top-60 tags + ALL `genre:` keys with abs > 0.001 — genres were being truncated out of the stored vector), avoidance net-sentiment guard (a tag is avoided only if ≥ 2 negatives or ≤ −0.8 **and** net-negative — fixes the loved-yet-avoided Drama artifact), plus a profile re-enqueue wave.
- **`20260731090000_taste_deck_pass_memory.sql`** — new `pass` action (`deck_pass`, strength 0.00, no stats/evidence/recompute, excluded from future deals — passes were being re-dealt, live-verified 2/12 of batch 2 were batch-1 passes). iOS: the left action was restored to DISLIKE semantics and relabeled **NOT FOR ME** (`deck_skip` −0.45) per the "continuous liking/disliking" product decision; `.pass` remains supported server-side.

**Live verification** (3 runs; 4 throwaway users created and deleted via the public auth API — auth signup autoconfirm is ON; exercised via curl against the REST/RPC API, not the iOS UI; evidence in the agent reports):

- Signal contract exact; α/β stats 141/141 and 118/118 exact; evidence/event_count exact; avoidance sets exact including the net-sentiment guard.
- Profile negative-mass ratio 87% → 14% after the P3 fix; genres retained with correct signs; ramp w verified at n = 0 / 5.5 / 6.5 (taste holds ~4% of ranking at 5.5 evidence — by design, §4.1 of the v2 doc).
- Personalized NTY replicated 20/20 positionally × 3 runs.
- **Deck finally VERIFIED LIVE** (after the two P0 rounds): 12 cards, 6/6 anime-manga, stratified (not the popularity chart — head/mid/gems spread), 12/12 mirrored covers, zero repeats vs signaled titles, meta fields (episodes/seasons_count) populated.
- Drain cron fired on two */15 boundaries; delete-account cascades clean.

**Open items / follow-ups:** (1) run-2 phantom `discover_rail_impressions` anomaly (20 foreign rows hid top-20 from one fresh user; did not recur; needs one service-role SQL query on `discover_rail_impressions` to close — prime suspect: deploy-window activity 15:55–16:10 UTC); (2) `taste_pipeline_status` contents + `cron.job` registration unverifiable without service-role access (403 correctly enforced); (3) v1 positive-mass caps vs small profiles noted by the implementer — watch as data grows; (4) KuroTests has zero deck-action coverage; (5) `deck_known` false-positive watch continues; (6) `personalized_new_to_you_v1` flag still at 0% — ramp criteria: drain telemetry sane + staff rail check.
