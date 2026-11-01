# Kuro overnight production pass — morning report (2026-11-01)

Branch `kuro/overnight-2026-11-01` (local only, **not pushed**). Base: `3962ad1` (the 31 Oct cleanup). Live production was **not touched**: no migration applied, no function deployed, no cron/flag/secret changed, no live data written. Everything backend-side is *prepared* and tested locally.

## What you asked for → what exists now

| Ask | Result |
|---|---|
| Check every API call, intake path and table | 8 audit reports in `docs/overnight-2026-11-01/understand/` (API surface, intake, schema of all 140 live tables, external sources, screens, design rulebook, auth/onboarding, product surfaces) + completeness critic. Live read-only snapshot in `live/`. |
| Take in more: songs, next episode / chapter / volume | **Data model + RPCs prepared** (`20261101000000_release_schedule_and_themes_v2.sql`): `user_release_schedule_v1`, `media_release_schedule_v1`, `media_themes_v1` with a certainty model (confirmed / announced / estimated ≥ 0.7, `release_precision`, source + credit link). **Intake prepared, unscheduled**: new `release-intake` function (AniList airing window → confirmed next episodes; MangaUpdates official-group releases → chapter cadence estimates), themes worker moved to AnimeThemes GraphQL, MangaDex volume grouping kept. **App shows them**: next-release lines on Home, Collection lists and detail pages; a songs section ("Listen" opens Apple Music / Spotify search) on anime detail. Until you deploy, the app silently falls back to today's data (next episodes only). |
| Optimize tables / intake / delivery | Prepared perf migrations: change-gated similar-titles rebuild (was **97% of all DB time**), audit-table retention, 22 duplicate indexes dropped, concurrent matview refresh, cheaper `updated_at` trigger, bridge identity fix. Intake: shared AniList limiter (25/min, Retry-After), GraphQL errors no longer reset cursors, no clobbering of mirrored images/synopses, real per-track queries. Client: explicit columns (no internal moderation fields shipped), cached watch-link chain (status RPC 3→1 per detail), size-aware image cache, Discover bundle once per launch, own-write realtime echo suppressed (each +1 used to trigger ~4 extra reads), single Library read at sign-in, no Clubs refetch on every tab visit. |
| Hyper-polish Home, Discover, Clubs, Profile + lists | Neutral palette frozen (white/#181818 ink, no cream/green casts), Dynamic-Type-reactive type, shared components (medium switch, 44 pt advance key, release line, honest state views, ink buttons). **Lists = "Folio"**: status word strip with counts, Shelf (equal covers / shallow scenes) ↔ Index (rows with +1, Undo, next release), sort words, search across statuses, batch bar incl. Dropped — in Collection in both flag worlds, previewed on Profile ("Your lists"). Discover: issue-style frames on white, airing-today by time, manga See All, Browse entry. Clubs: real-artwork cards, honest failed/offline states, neutral room. Profile: identity, library counts + lists preview, imports & connections, account & privacy, Advanced, **Data sources & credits**. Detail: next release, songs, EN/DE throughout, no internal wording. |
| Onboarding / sign-in / sign-up perfect, branded | Welcome kept exactly as approved (b943e457). Form rebranded (ink focus, Dynamic Type, Return-key chaining, VoiceOver, tappable Terms/Privacy, EN/DE errors mapped by error code). Onboarding rebuilt as 3 frames in the welcome's language (medium choice, bring your list, clubs are private), per-account completion. **Security**: sign-in links now only accepted when this device asked for them (fixes the login-CSRF issue), PKCE code exchange, a real **set-new-password** screen (reset used to just sign you in), no live "email taken" probing. 5 email templates re-skinned (not uploaded). |
| Every screen adaptive, on-brand | iPhone portrait lock, iPad 680 pt readable column, accessibility text sizes reflow, 44 pt targets, Reduce Motion crossfades, header usable with VoiceOver. Simulator screenshots: `screenshots/app/` (+ `VISUAL_QA.md`), fixture renders: `screenshots/snapshot-*`. |
| Generate assets | App-icon candidates (brush / serif / mountain) in `assets/app-icon-candidates/` — **icon not replaced**, your pick. No other scenery generated: the rulebook allows only the approved mountain artwork. |
| Plan with both agents, review, second-guess | Claude: 8 audit lanes → spec → foundation → 7 build lanes → 5-lens review with 2 skeptics per finding (15 confirmed, all fixed) → simulator visual QA → fix round with its own reviewers. **Codex could not run**: your Codex config has an `mcp_servers.higgsfield` entry without `command`, so Codex refuses to start. |

## Verification (final tree)

- iOS: Debug build-for-testing and **Release** build succeed. Full `KuroTests` on the owned simulator: see `FINAL_TESTS` below.
- Package tests (`Packages/KuroModules`): pass. Architecture, secrets, migrations, docs gates: PASS.
- Edge functions: offline deno tests for 15 function folders pass (see below).
- Local disposable PostgreSQL harness: see below (it always exits 4 because two fixture scopes can't be built locally; that is the known honest state).

**Final numbers (tree at the end of the night):**
- `KuroTests` on the owned simulator: **609 tests**. Full run: 608 passed; the one failure was a new test counting HTTP attempts instead of logical reads (a forced "Try again" goes through `withRetry` like every load). Assertion fixed, then its suites re-run: 14/14 passed.
- `Packages/KuroModules`: 96 tests pass.
- Edge functions (offline deno): **255 passed, 0 failed** across 15 function folders (new `release-intake`: 27).
- Local PostgreSQL harness: **33 test files, 1,168 assertions passed, 0 findings**; every prepared migration applied to the fixture; 2 fixture scopes BLOCKED as before (exit 4, honest state).
- Release build (generic iOS): BUILD SUCCEEDED. Gates: architecture, secrets, migrations, docs: PASS.

## Decisions I made for you (all reversible — please review)

Spec `docs/superpowers/specs/2026-11-01-overnight-production-pass-design.md` §2, D1–D16. The ones you will notice:
- **D3** iPhone portrait only; iPad gets a centred 680 pt column.
- **D5** medium switch stays the native serif; manga Home stays 2 columns; club room is neutral #222222.
- **D7** onboarding = 3 welcome-style frames (you never approved an onboarding design).
- **D8** Discover drops the glass panel for issue-style frames on white.
- **D9** Folio lists (above).
- **D10** release certainty model; nothing is shown that a source didn't state.
- **D11** licensing: nothing new is *scheduled* from restricted sources (see below).
- **D13** no live "email already taken" check.
- "Get started" on the welcome now opens **Create account** first (audit evidence; one-line revert).

## What only you can do / decide

1. **Licensing (blocking for production intake):** AniList's terms restrict mass storage and use in tracker apps; AnimeThemes, MangaDex, MAL/Jikan restrict commercial use; MangaUpdates is permissive with credit. Details: `understand/sources.md`. Decide which sources Kuro may use commercially before scheduling `release-intake` / the themes worker.
2. **Manga release dates:** set `MU_OFFICIAL_GROUP_IDS` (official publisher groups on MangaUpdates, e.g. MANGA Plus / VIZ / K MANGA) — until then manga schedules stay empty by design.
3. **Deploy (when you're ready):** apply `supabase/prepared-migrations/20261101*.sql` in order (the 010100 duplicate-index file must run outside a transaction; pause `realm-similar-drive-5m` + bulk-import crons during 010000; confirm PostgreSQL ≥ 14), deploy `release-intake` + changed edge functions, upload the 5 email templates, apply `20261101030000_auth_hardening` only after the new iOS build ships. Step-by-step: **`docs/overnight-2026-11-01/DEPLOY_CHECKLIST.md`** (includes the weekly-instead-of-nightly similar-titles freshness change that needs your sign-off).
4. **Supabase dashboard:** password minimum 8 + leaked-password check, `kuro://auth/callback` in redirect allow-list, SMTP (Resend), email-confirmation setting.
5. **Legal URLs (App Store risk):** `kuro.app` **does not resolve** right now, so the Privacy link in the app is dead. Publish a privacy page (and Terms) and confirm the URLs; Terms stays unlinked everywhere until `KuroLegalLinks.terms` is set (the welcome no longer hard-codes an invented Terms URL).
6. **App icon:** pick a candidate (or keep the current one).
7. **Visual acceptance:** nothing here is owner-approved; screenshots are for your review.
8. **Codex:** fix `~/.codex/config.toml` (`mcp_servers.higgsfield` needs `command`) if you want Codex reviews.
9. **Push:** say the word and I push `kuro/overnight-2026-11-01`.

## Not covered tonight (so "every screen" is not over-claimed)

- **Concierge** (9 view files) was not redesigned (it is a sheet; out of the lanes' ownership).
- Launch sequence: launch text now says anime & manga; `UILaunchScreen` is still an empty (white) dictionary — no launch mark yet.
- Production-readiness items never audited tonight: `PrivacyInfo.xcprivacy` vs the new on-device storage (recent searches, pending auth flow, onboarding keys) and telemetry, App Store privacy labels, `docs/production-blockers.md`.
- Series grouping has **no producer** (`series`, `series_sections`, `series_entry_spans`): the flag-on Home/series detail would still lack series data after deploying tonight's SQL.
- Localhost prototype map: classification of every page on `http://127.0.0.1:8803` (selected vs rejected) is in `understand/DESIGN_RULEBOOK.md` §2; native screen map in `screenshots/final/SCREEN_MAP.md`.

## Process disclosures

- One foundation fix agent ran `xcodebuild test` against a simulator chosen **by name** ("iPhone 17 Pro") early in the night, which may be the device the handoff reserves for other work. I did not touch that device afterwards; please check it is as you left it. All later runs used the owned UUID only.
- The live Supabase connector had no permission; live facts were read with read-only CLI inspection and public REST reads (feature flags, row counts).

## Known remaining issues (honest list)

- Flags-off live world vs flags-on target world are both supported; the series foundation tables are still empty live, so the series detail falls back to legacy sections.
- Some Imports-owner toast strings are still English-only (`ProfileImportCoordinator`); provider caption copy in `Kuro/Providers` partly English.
- Legacy Collection features dropped when Folio replaced the grid: on-device FM collection search and streaming-service/language filters (product call).
- Folio search covers up to ~1,500 titles per medium before it says so; a server-side search would remove that cap.
- AniList 25/min limiter is per function instance; scheduling must stagger jobs.
- VoiceOver reading order and keyboard focus timing need a device check; no German-locale screenshots were taken.
- Invite codes: deep links accept 6–12 characters, the join sheet expects exactly 8 (pre-existing).
- Two older security notes remain as noted on 31 Oct: `concierge-parse` per-IP limit trusts `x-forwarded-for` (needs deploy).
