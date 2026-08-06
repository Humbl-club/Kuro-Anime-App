# Phase 0 — Full-System Check (2026-07-31)

**Method:** 8-agent recon swarm over live code, migrations, edge functions, and docs. Live CLI access confirmed: `supabase migration list --linked` works (all 170 local migrations applied remotely), `supabase db lint --linked` returns one warning (`_club_sharing_rank` unused in `fetch_club_bundle_loading`). Evidence cited per area. Prior audits treated as hints; everything below re-verified against HEAD.

Verdict scale: **healthy / needs patch / needs revamp / backlog**.

---

## 1. Database — needs patch

- **82 tables, 8 views, ~158 function defs across 170 migrations.** Core catalog schema (`anime`, `manga`, `episodes`, join tables, list tables) predates migration tracking and lives in `legacy_sql/`; four 2025 placeholder migrations stand in for the baseline.
- **Untracked remote schema:** 7 materialized views (home feeds read 6 of them directly), the `kuro-refresh-matviews` cron, `import_runs`/`import_locks` + lock RPCs exist only in production — never captured in a migration. Highest structural risk.
- **Hollowed migrations:** 4 files contain literally `;` (`20260215124919`, `20260215124946`, `20260215125056`, `20260215125312`). `create_club_rail`, `create_club_poll`, `club_rail_item_reactions`, and the invite-code crypto fix are missing from the reproducible chain; `generate_invite_code` uses `random()` again in prod (`20260305162000:64-77`).
- **Duplication:** `20260219xxx` migration family applied twice; two `curated_rails_expansion` files; heavy function re-definition churn.
- **RLS:** all 82 tables have RLS **except `discover_rail_impressions`** (revoke-only; safe via privileges but inconsistent). 7 SECURITY INVOKER functions lack `SET search_path` (low risk). TEXT-vs-UUID `user_id` debt (`anime/manga_user_lists` TEXT) is now load-bearing — taste triggers and GDPR deletes parse defensively around it.
- **Dead weight:** `anime_comments`/`manga_comments` (0 refs), `user_lists` view, `club_messages` + chat RPCs (deprecated, no retention), `rag_*` tables (flag never flipped), `user_taste_profiles` (written by nothing since February).

## 2. Crons & ops — needs patch

| Job | Schedule | Issue |
|---|---|---|
| mirror-images ×5 | 02:00–03:00 UTC | Fixed offsets 0/200/400 — windows never advance; no remote-only filter; char/staff stuck at id-asc offset 0 |
| manga-chapter-enrich | */15 + nightly | Healthy (queue-driven, 900s lock) |
| concierge housekeeping | 04:00 | Healthy |
| matview refresh | remote-only | Not in repo (risk above) |
| bulk-import anime/manga | **no cron anywhere** | Runs manually/via local scripts despite docs claiming hourly |

- Auth fragility: cron bodies hardcode an anon JWT and read `x-import-secret` from the `app.settings.import_secret` GUC — no fallback; already broke once (`20260219234000`). Lock acquisition in mirror-images **fails open**.
- Local-Mac dependency: synopsis enrichment, catalog safety, media relations, and the Watchmode provider-availability worker all run via launchd on a dev machine. `club_messages` and `mirror_runs` have no retention; `taste_signal_events` is unbounded append-only.

## 3. Edge functions — healthy (13/15)

JWT-derived user_id everywhere required; rate limits on all concierge-*; `delete-account` solid. Exceptions:
- **mirror-images — needs patch:** selection logic (above) is why CDN coverage cannot converge.
- **concierge-import-anilist — needs patch (minor):** never calls `getUser()`; only IP-rate-limited.
- **concierge-resolve — dead:** zero callers in iOS or server code.
- No `config.toml` in repo; `verify_jwt` settings unverifiable from source.

## 4. iOS architecture — healthy, with known debt

- 88 Swift files / 43.5k lines. `@Observable` discipline: **zero** Combine/`UIScreen.main`/`asyncAfter` violations. Prints DEBUG-wrapped. Feature-flag system real (15 flags, server-driven, deterministic hash).
- Oversized: `SupabaseService.swift` 2,972 (mid-extraction, plus a `!canImport(Supabase)` mock twin at file tail), `AnimeDetailView.swift` 2,422, `ConciergeView.swift` 1,681. Extension pattern exists; extraction unfinished, not absent.
- Bespoke pager in `ContentView.swift` (820 lines): ~200 lines of gesture arbitration; visited pages stay mounted forever (monotonic memory growth).
- Dead code: `ContentView.swift.bak`, `Cards.swift.bak`, `GenreHubView.swift`, `ConciergeIntentDeck/ComposerDock/ActionFooter` (352 lines, shell slots fed `EmptyView()`).

## 5. Tests — needs patch

- `KuroTests` (773 lines, swift-testing): real suites for import intent (17, EN/DE), auth error mapping, credit roles, provider notes, ladder. Two theater tests (`testAppLaunch` asserts `true`). All pure-logic — no service/view-model coverage, nothing for taste, clubs RPC contracts, or deep links.
- UITests: one real regression guard (swipe/tap), one flaky network-dependent E2E, screenshot harness.
- Quality gates: 8 real gates; **migrations gate currently hard-fails** on the untracked `20260730160000_taste_signal_events_v1.sql`. No arch-lint gate for stack-law greps.

## 6. Design system reality — needs patch (brand claim ~70% true)

- Real: monochrome (21 black-opacity stops), 8pt grid, serif+sans scale via system fonts (New York — **no Cormorant anywhere**), light-mode forced, motion tokens with Reduce-Motion plumbing.
- Drift: font-token adoption ~75%, spacing-token adoption **~27%**, 64+ ad-hoc animations bypassing `KuroAnimation`. `EditorialDiscoverView` is the flagship surface with near-zero spacing discipline; `Cards.swift`/`KuroRefinedCard.swift` are 100% pre-token.
- Color-law violations: yellow→orange score badge in `PosterView.swift:47` (dead code, still wrong), colored streaming chips in `AnimeDetailView.swift:1865-1875`.
- Benchmarks: frozen Auth = warm, tactile, cinematic white (warm ink `#161412`, red accent); Clubs empty state + club hero (grain overlay) = most editorial; Discover = most generic ("well-mannered streaming app, not a magazine"); big display tokens (`kuroHero`/`kuroDisplay`) go unused.
- `AccentColor` empty; `UILaunchScreen` empty dict → white flash before code-driven launch view.

## 7. Surfaces — one-line verdicts

- **Discover:** healthy mechanically (server bundle, rotation, impression memory); editorially generic. **Browse:** most token-disciplined; healthy. **Collection:** tool-like, healthy; FM NL search lives here (docs wrongly claim it for the Search sheet). **Search sheet:** server-driven, healthy. **Detail pages:** premium hero + section firehose; needs pacing, not patches. **Profile:** streaming section invisible (flag 0%) though docs claim it live. **Onboarding:** 5 static marketing cards, **collects zero taste signal**, then says "Start with Concierge" but lands on Discover.
- **Auth:** frozen. Read as brand benchmark only.

## 8. Taste readiness — capture live, consumption dark

- `taste_signal_events` (2026-07-30 migration, applied remotely, untracked in git): 12 contract events emitted by SECURITY DEFINER triggers on both list tables, correct weights, import discount marking, no-op suppression, safe TEXT→UUID parsing. Import path wrapped via `begin/clear_taste_import_context` in `concierge-apply`. **Missing:** `anime_to_manga_continue` emitter, retraction events, retention.
- **Nothing reads the events.** `taste_profile_recompute_queue` fills with every event; no worker, cron, or RPC drains it. `user_taste_profiles` untouched except GDPR delete. Personalization flags named in the contract are **not seeded** in `feature_flags`.
- Raw material is excellent: per-title tag weights (`anime_tags.rank` 0–100), genres arrays, studios/staff, editorial boosts/penalties, curated rails, typed `media_relations`, and a working multi-seed similarity RPC (`recommend_ids_similar_to_seeds`).
- Ranking surfaces today use user data only for **exclusion/repetition** (NEW TO YOU) or **demotion** (concierge genre-overlap penalty). No positive fit term anywhere.
- Contract's own cheapest path: Sprint 02 = one SQL function over events × tag ranks with import discount, confidence tiers, 8%/15% caps.

## 9. Image reality — needs revamp (root cause found)

- Mechanism is sound (in-place column rewrite to Storage CDN, immutable cache headers, per-asset state, lock per batch). iOS reads the columns directly; no fallback chain needed.
- **Why coverage can't converge:** (1) cron windows are fixed offsets into popularity-sorted tables — already-mirrored rows occupy the windows; ceiling ≈ top-600 anime/manga, top-200 char/staff *by lowest id*; (2) **hourly imports actively un-mirror** — `bulk-import-*` upserts `cover_image_*` from AniList on every re-import of the same popular slice.
- Estimated steady-state: anime ~10–20%, manga ~5–12%, characters/staff ~1–4% mirrored (code-derived ceilings vs stale 2025-11 catalog counts of ~2.2k anime / ~4k manga; no live measurement yet).
- `PosterView` uses raw `AsyncImage` but is dead code; live path `KuroCachedAsyncImage` + `ImagePipeline` (NSCache+URLCache, dedupe, downsample) is healthy.

## 10. Clubs reality — needs patch (solid bones, degraded surface)

- Core loop genuinely well built: create/join (structured error codes), rails, polls (optimistic votes), privacy-aware bundle, 30+ RLS policies, unread dots real.
- **Broken now:** reactions contract mismatch — client sends keys `fire/heart/eyes/100`, RPC allowlists emoji chars → every toggle raises `INVALID_EMOJI`. Reactions are dead at the API level.
- **Trust regression:** `fetch_friend_activity_for_title` / `count_friends_tracking` return status/progress/rating for all club-mates **ignoring sharing levels** — violates the spec's core "no data leaks upward" promise.
- **Dark features:** `clubs_reactions_v1`, `clubs_pace_sync_v1`, `clubs_realtime_v1`, `clubs_notifications_v1`, `clubs_list_enriched_v1` seeded in **no migration** → realtime, pace, badges never fire. Duo clubs (2 members, spec-legal) get a permanently empty ACTIVE tab (k≥3 rule).
- **Invite chain weakest link:** share = plain text with 8-char code; no `kuro://join/<code>` route; `kuro://club/<uuid>` exists but misleads non-members ("You were removed" toast); invite expiry columns enforced but never set; no regenerate; regular members can't see the code.
- Settings sheet is a stub vs spec (no rename/archive/regenerate/member downgrade; backing RPCs don't exist). Chat backend is dead weight.

## 11. Money readiness — needs patch (surfaces live, instrumentation zero)

- Live, tapped surfaces: `external_links` (populated from AniList every import), episode-level `stream_url`, "WATCH ON / READ ON {PROVIDER}" CTAs + provider sheet with Verified badges. Highest-intent surface: manga READ ON (purchase, not subscription).
- Parked: streaming availability v2 schema is rent/buy-ready (`availability_type`, `deep_link_url`) but tables are empty, refresh worker is a dev-machine launchd job, flag at 0%.
- **No affiliate fields, no click tracking anywhere** — outbound taps are unmeasured. `external_links.url` is plain text: affiliate decoration needs no schema change, but reporting does.

## 12. Cross-cutting top risks (ranked)

1. Untracked remote schema (matviews + cron + lock RPCs) — home feeds depend on it.
2. Taste pipeline write-only — events accumulate unread; Sprint 02 unstarted.
3. Clubs privacy hole in social RPCs — live trust regression.
4. Mirror pipeline cannot converge — selection logic + import erosion.
5. Clubs reactions API-broken; five club flags dark.
6. Cron auth via GUC secret with no fallback (broken once already).
7. Migration chain can't reproduce prod (4 hollowed files + duplicated family).
8. Pager memory growth; `SupabaseService` god-file mid-extraction.

---

*Next: creative ideation deck (`2026-07-31-creative-ideation-deck.md`), Red Team pass, then ADR locks.*
