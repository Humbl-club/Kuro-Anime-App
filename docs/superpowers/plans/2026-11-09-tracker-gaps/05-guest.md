# W5 Guest Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** People who are not signed in can open Discover, Search, Browse, title, entity and season pages. Every save, track, club or taste action opens a sign-up tool sheet and finishes the action once, after sign-up. The anonymous database role can call only an explicit allowlist of read RPCs.

**Architecture:**
- A new owner, `GuestSession` (`Kuro/Identity/`), derives the guest state from `IdentityStore` plus the `guest_browsing_v1` release switch, holds the one in-memory `PendingGuestIntent`, and replays it once, inside a credential lease of the new account, at the end of `SessionController.bootstrapAfterAuth`.
- The root shows the normal pager for guests. Taste, Home, Collection and Clubs render a sign-up invitation. Sign-up is a tool route (`AppRoute.signUp`) shown over the current page, and the tracking editor and add-to-club tools turn into that sheet while the user is a guest.
- Prepared migration `20261118110000_guest_anon_allowlist_v1.sql` removes EXECUTE from `PUBLIC`/`anon` on every non-extension function in `public`, re-grants exactly the allowlist to `anon`, keeps every other role's privileges unchanged, and removes Supabase's per-schema default that grants anon EXECUTE on every new function.

**Tech Stack:** Swift 6 / SwiftUI / `@Observable`, supabase-swift 2.54.1, KuroTests (Swift Testing + `StubPostgREST`), XCUITest (offline fixture host), PostgreSQL 17 disposable fixture (`scripts/db/run_local_db_tests.sh`), Node `node:test` (`scripts/load/`).

**Spec:** docs/superpowers/specs/2026-11-09-tracker-gaps-design.md + features/W5-guest.feature

## Global Constraints

- Release gate (spec §1): "W5 | Browse before signing up (guest mode) | L | Build yes | D-A AniList terms, capacity PASS, grant audit". The build ships dark: `guest_browsing_v1` is inserted disabled at 0 %, and the migration stays in `supabase/prepared-migrations/` until the owner approves it. Applying the migration, qualifying the anonymous load and showing guest mode are three separately controllable steps (brief item 1).
- **Order and blocker:** W5 is **last** in the merge order (`00-program.md`: F1 → F2 → F3 → W2 → W4 → W3 → W10 → W6 → W9 → W5) and its release is **blocked on D-A**. It may be built and merged dark; `guest_browsing_v1` is not raised above 0 % while D-A is open, whatever the capacity result.
- **Release switch (brief item 1):** `guest_browsing_v1` (server `feature_flags`, read through the injected `FeatureFlags`, default 0 %). While it is off, a signed-out launch shows today's auth wall and the app sends no guest request: nothing beyond the one signed-out `feature_flags` read that decides the switch (Task 3). That read is itself new: one anonymous GET plus up to `GuestLaunchPolicy.flagWait` (1.5 s) of launch-screen wait on every signed-out launch, even with the switch off, because the switch cannot be known without it. This is an accepted exception to "flag off sends nothing" for the lead to confirm. Pinned by `GuestModeTests/flagOffSendsNoRequest`.
- **AniList-terms risk (D-A, owner; spec §2):** AniList's current terms (`AniList/docs` `docs/guide/terms-of-use.md`, changed 2026-08-18) say: "Use of the AniList API within competing, non-complementary services of the same nature is prohibited. This includes, but is not limited to, anime and manga list or tracker services. The restriction applies to all data provided through the API, including both user data and media data." and "Hoarding or mass collection of data from the AniList API is strictly prohibited." There is **no** "authorized on request" exception (an older mirror had one; it is gone), and the commercial-use contact line does not lift the competing-service ban. The terms cover media data, so the catalogue Kuro serves is in scope today, guest mode or not. Guest mode widens Kuro's own presentation of that AniList-derived data (titles, synopses, cast, artwork URLs) to people without an account. Guest mode is not enabled for users until D-A is resolved by one of the spec's options: (1) legal advice on the current exposure; (2) move catalogue sourcing to sources whose terms allow this use; (3) accept the risk knowingly and in writing. Asking AniList for permission is not a planned route.
- Capacity (§3): "Target: **100 simultaneous active users**; steady **20 requests/second**, peak **40 requests/second**."
- Latency (§3): "p95 end-to-end thresholds: **Browse/Search/Clubs/Progress ≤ 750 ms, Home/Detail ≤ 1200 ms, Discover/Moods ≤ 1500 ms, Edge Parse/Recommend ≤ 2500 ms**; zero unexpected errors/timeouts, zero dropped offered starts."
- Capacity rule (§3): "A workstream that adds backend traffic is not released to users while the qualification is NOT QUALIFIED, and its change must not worsen the measured steady-state result. Budgets are never relaxed for a retry."
- Architecture (§3): "one `@MainActor @Observable final class` owner per capability… account-scoped owners conform to `AccountScopedState`, capture `AccountContext`… tracking reads/writes only through `LibraryStore` / `LibraryActions`; no second Supabase client; no Combine; `print` only inside `#if DEBUG`; no force unwraps."
- Navigation (§3): "Rule 5 (navigation contract) and Rule 6 (Discover R1–R8) apply to every new screen, sheet and tap target. New sheets register `.kuroNavigationLayer`; tool sheets use `.kuroLeavesJourney()`; unsaved input uses `.kuroDiscardGuard`."
- Database (§3): "SECURITY DEFINER functions grant EXECUTE only to the roles that need it and revoke PUBLIC (see `20261108120159_review_security_v1.sql`); new SQL bodies in plpgsql (fixture rule)… Migrations are written to `supabase/prepared-migrations/` and applied only after explicit owner approval; never `supabase db push --include-all`."
- Data rule (§3): "Explain local-only guest saving." Spec §6 copy, used verbatim: "Kuro keeps nothing on this phone until you have an account; the title you picked is added as soon as you sign up".
- Copy and design (§3): every string goes through `KuroLocale` (EN + DE), the UI is monochrome, only branded states are used, and the app stays light-only.
- Business rule (§3): "Kuro will not charge for tracking, ordinary discovery, search/filter/sort…"
- **Rule 6 guest exception (recorded, spec §6 W5):** for a guest, the Plan key and Not interested / Seen it open the sign-up tool sheet instead of stamping (R4) or removing the title (R5). R5's "teach Taste" needs an account, and spec §6 requires "any save/track/club/taste action opens sign-up". The answer is replayed after sign-up. Every other R1–R8 rule is unchanged for guests.
- "Season overview" in the feature file means the title page's seasons section and the season title pages it pushes (`DetailNavigation.seasonPage(id:)`, fed by `get_media_ladder`). Home's `HomeSeasonOverview` (`series_detail_bundle_v1`, authenticated) is Home-only, and Home is an invitation for guests.
- **Anonymous catalogue reads already exist today (verified live 2026-11-09, read-only):** `has_table_privilege('anon','public.anime','select')` and `has_table_privilege('anon','public.manga','select')` are both `true`, through the RLS "Public read access" policies. The anon key ships inside every installed build, so anyone holding the app binary can read the catalogue tables (and today every anon-executable RPC) without an account, independent of W5. A client flag cannot revoke that: `guest_browsing_v1` only decides whether the app's UI offers guest browsing. W5 changes what the app does for signed-out people and shrinks the anon EXECUTE surface (Task 1); it does not create anonymous catalogue access and cannot close it.
- Privacy: a guest leaves nothing on the device or the server. There are no `UserDefaults` writes keyed to a guest and no telemetry inserts from guests (owner decision D-W5-T below). The intent lives in memory only.

### Owner decisions this plan raises (not built until decided)

- **D-W5-RL: per-IP rate limit on anonymous reads — a current production exposure, not a W5-only issue.** Because anon SELECT on the catalogue tables and anon EXECUTE on many RPCs exist today for every install (Global Constraints), unthrottled anonymous reads are possible against production now, with or without guest mode. W5 surfaced it; the decision stays with the owner and is tracked here until the lead moves it to the program. What is verified:
  - Supabase limits only Auth endpoints.
  - Its documented Data API limiter (`pgrst.db_pre_request`) "can only rate-limit `POST`, `PUT`, `PATCH` and `DELETE` requests. This is because `GET` and `HEAD` requests run in read-only mode" (Supabase docs, Securing your API).
  - supabase-swift 2.54.1 sends `.rpc` as POST (`PostgrestClient.rpc(get: false)`), but `.from(...).select()` (title, episodes, credits, links) as GET.

  So a pre-request limiter could at best cover the anonymous RPCs, never the catalogue table reads, and it writes one row per request while capacity is NOT QUALIFIED. *To verify before relying on it:* whether PostgREST runs POSTed STABLE functions read-only, which would also defeat the RPC half. As far as verified, nothing in the current stack gives a per-IP limit on all anonymous reads. Options:
  - (a) Accept, as today: the anon key is already public and the allowlist shrinks the anon EXECUTE surface. Rely on the spend cap and monitoring. The `guest_browsing_v1` switch stops the app from generating guest traffic, but it does **not** stop anyone calling `/rest/v1/*` directly with the shipped anon key, so it is no protection against abuse.
  - (b) A Supabase custom domain behind a CDN/WAF with a per-IP rule on `/rest/v1/*`. *To verify:* that Supabase supports proxying its custom domain through a third-party WAF. It would be configuration only, but paid.
  - (c) An Edge Function proxy for guest reads with per-IP buckets (client IP = XFF[0] / `cf-connecting-ip`, per the 2026-11-02 probe). This adds a hop against the 750 ms Browse/Search budget.
  - (d) A pre-request limiter for anonymous POST RPCs only, if the STABLE question resolves favourably.

  No recommendation until (b) and the STABLE behaviour are verified, which is a small spike, owner-approved. Kept out of `20261118110000`. The limit value is set after the baseline (spec §5.2). Supabase cannot rate-limit GET/HEAD with database counters, so whatever the owner chooses, it is infrastructure in front of the Data API (b/c), not SQL.
- **D-W5-T: conversion measurement.** Default built here: guests send no telemetry. If the owner wants "Guest → account conversion measured", the smallest option is two anonymous counter events (`guest_session_started`, `guest_signup_completed`) with no identifier, through the existing `concierge_events` anonymous insert. That needs a privacy-text update first.
- **D-W5-DP: default privileges.** The migration revokes only Supabase's per-schema default, `alter default privileges for role postgres in schema public revoke execute on functions from anon`. That is low risk: `authenticated` and `service_role` keep theirs.

  It does **not** revoke PostgreSQL's global PUBLIC default (`alter default privileges for role postgres revoke execute on functions from public`). That revoke would also strip PUBLIC EXECUTE from every function `postgres` creates later in any schema, including the disposable test helpers (`supabase/tests/lib/00_test_helpers.sql` loads after the replay and is called after role switches), and it would surprise later migrations.

  Consequence: a new `public` function is still anon-callable through PUBLIC unless its migration revokes PUBLIC, which spec §3 already requires. Test 106's exact-set assertion is the tripwire: W9, W10 and any later migration that forgets `revoke … from public` fails 106 in the fixture. The owner may still choose the global revoke later, together with a `grant execute on all functions in schema tests to public` in the helper library.

## Review Focus

1. **Revoke from `public` alone leaves anon's direct grant; a new function without `revoke … from public` reopens anon.** `fetch_daily_feature`, `fetch_because_you_rail`, `fetch_tonight_shelf`, `fetch_realm_hidden_gem`, `fetch_personalized_new_to_you` and the 12-argument `browse_*_page` overloads are anon-callable today, through Supabase's per-schema default grant. (Live read-only check 2026-11-09 via `has_function_privilege('anon', …)`: all of these true; `purge_outbound_link_events()` is **false** live, so the migration-reading claim that it is open was wrong. The open ones are catalogue reads or return nothing without `auth.uid()`; no write is exposed.) Pinned by the 106 set-equality assertion (Task 1), which also fails any later migration that forgets the PUBLIC revoke.
2. **SECURITY INVOKER readers break when their callee loses anon.** `media_similar_v1` → `recommend_ids_similar_to_seeds`; `anime_cast_v1` reads tables. Pinned by 106 section C, which calls every allowlisted function as anon and fails on SQLSTATE `42501` (Task 1).
3. **A guest request that fails is wasted capacity and a load-test error.** Examples: friend-count prefetch, `checkClubNotifications`, `fetch_daily_feature`, `record_outbound_link`, `enqueue_media_relation_refresh`. Pinned by `GuestModeTests/guestDiscoverBrowseAndSearchReadOnlyTheAllowlist` and `guestCanOpenTitleEntityAndSeasonPages` (Task 4).
4. **The sheet's teardown on success must not discard the intent.** The account switch rebuilds `ContentView`, so `onDisappear` runs after sign-up. A second bootstrap (an SDK `.signedIn` event) must not replay again. Pinned by `GuestModeTests/intentSurvivesSheetTeardownAfterSignUp` and the double-bootstrap assertion inside `pendingIntentReplaysOnceAfterSignUp` (Tasks 2–3).
5. **Signing in to an existing account that already tracks the title.** `save` never downgrades, and the banner must not claim "added". Pinned by `GuestModeTests/replayOnTrackedTitleSaysAlreadyInList` (Task 3).
6. **The replayed intent sent with the wrong account's credentials.** The replay is a new private request path: `.plan` goes through `LibraryActions.save` → `LibraryStore` → `PostgrestLibraryTransport`, which take **no** credential lease today (grep: no `withCredentialLease` in `KuroLibrary` / `PostgrestLibraryTransport.swift`). The replay therefore runs inside `accountSession.withCredentialLease(for: context)` (brief item 2). Pinned by `GuestModeTests/replayAfterAccountSwitchSendsNothingAsB` (Task 3).
7. **Guest mode switched off still sending requests.** Pinned by `GuestModeTests/flagOffSendsNoRequest` (Task 3).

Also pinned:
- sign-out lands on guest Discover: `GuestModeTests/rootResolvesGuestAfterSignOut` (Task 6);
- newest intent wins: inside `saveAsGuestOpensSignUpWithPendingIntent` (Task 5);
- a guest writes no account-scoped device keys: `GuestModeTests/guestBrowsingWritesNoAccountKeys` (Task 4).

## Success parameters

| W5 row (spec §5.2) | Measured by | Expected |
|---|---|---|
| Signed-out people can open Discover, Search, Browse and title/entity pages | `xcodebuild … test -only-testing:KuroUITests/GuestBrowsingUITests` and `-only-testing:KuroTests/GuestModeTests` | `Test Suite 'GuestBrowsingUITests' passed`; `GuestModeTests` all passed |
| any save/track/club/taste action opens sign-up and completes the original action after sign-up | `GuestModeTests/saveAsGuestOpensSignUpWithPendingIntent`, `pendingIntentReplaysOnceAfterSignUp`, `pendingIntentDiscardedWhenSignUpCancelled`, `guestToolRoutesBecomeSignUp` | passed |
| no local guest library exists, and the sign-up sheet says so | `GuestModeTests/guestBrowsingWritesNoAccountKeys` + the copy assertion in `saveAsGuestOpensSignUpWithPendingIntent` | passed |
| anon role can call only the allowlisted read RPCs | `scripts/db/run_local_db_tests.sh --only 114_guest_anon_allowlist`; live: `docs/tracker-gaps-2026-11/W5-guest/live-anon-grants.sql` (owner-approved read-only run) | `TESTS : … 0 failed`; live query returns exactly the 19 allowlist rows (17 while W4 is not applied) |
| Anonymous reads in the F3 workload at the same class budgets | `node --test scripts/load/profiles/guest-browse.test.js` (profile exists, absolute `ratePerSecond: 5` on top of the unchanged 20 rps base, allowlisted paths only); live `guest-browse` `--qualify` run in the next owner-approved qualification | test passes; live: every class p95 ≤ its §3 budget, 0 errors, 0 dropped, ≥ 100 completions per class (fewer → `insufficient`), base results reported separately and not worse than the base-only run |
| Guest mode switched off sends nothing | `GuestModeTests/flagOffSendsNoRequest` | passed |
| Replay never crosses accounts | `GuestModeTests/replayAfterAccountSwitchSendsNothingAsB` | passed |
| per-IP rate limit on anonymous reads (limit set after baseline) | Owner decision D-W5-RL (current production exposure, not W5-only) | recorded in the evidence note; not built |
| Outcome (learning goal, not a release criterion): Guest → account conversion; no "forced sign-in" complaints | Only if D-W5-T says yes: event `guest_signup_completed`, denominator `guest_session_started` (both anonymous counters); support messages tagged "sign-in" | the owner reviews after 4 weeks of data; with D-W5-T = no, nothing is measured and the goal is reviewed from support messages only |

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `supabase/prepared-migrations/20261118110000_guest_anon_allowlist_v1.sql` | create | Sweep: revoke PUBLIC/anon EXECUTE on every non-extension `public` function, restore other roles, grant the anon allowlist (each signature that exists), drop the per-schema anon default, insert `guest_browsing_v1` (off), self-assert "anon ⊆ allowlist, no other role lost anything" |
| `supabase/tests/rls/114_guest_anon_allowlist.sql` | create | Exact allowlist, anon calls not denied, private/write functions denied, other roles unchanged, per-schema anon default gone, catalogue tables readable |
| `supabase/tests/pending_migrations.txt`, `supabase/tests/README.md` | modify | List the pending file and test 106 |
| `Kuro/Identity/PendingGuestIntent.swift` | create | `PendingGuestIntent`, `GuestSignUpRequest`, `RootPresentation` (pure root decision), `GuestPager` (pure guest pager order), `GuestReadAllowlist` (Swift mirror of the SQL allowlist + catalogue tables) |
| `Kuro/Identity/GuestCopy.swift` | create | EN/DE strings: sheet notes per intent, invitation copy, replay banners |
| `Kuro/Identity/GuestSession.swift` | create | Owner: `isGuest`, in-memory intent, `signUpSheetClosed`, `replayPendingIntent(for:)`, `takeReopenTitle(for:)` |
| `Kuro/Identity/SessionController.swift` | modify | `bootstrapAfterAuth` = data bootstrap + guest replay; bounded signed-out flag read in the failed launch restore |
| `Kuro/Services/FeatureFlags.swift` | modify | `guestBrowsingV1Enabled`; `refreshSignedOut(client:accountSession:timeout:)` |
| `Kuro/Composition/AppComposition.swift` | modify | Build `GuestSession`; pass it to `SessionController`; `AppGraph.guest`; `CatalogStore(client:accountSession:)` |
| `Kuro/KuroApp.swift` | modify | `RootView` uses `RootPresentation.resolve`; injects `GuestSession` |
| `Kuro/ContentView.swift` | modify | Guest pager order, invitation pages, header profile → sign-up, no onboarding for guests, join/club/concierge links gated, reopen title after sign-up |
| `Kuro/Views/EditorialDiscoverFrames.swift` | modify | `DiscoverBrowseEntry.isOffered(flags:guest:)` |
| `Kuro/Views/Routing/KuroRoutes.swift` | modify | `AppRoute.signUp`, `KuroRoutes.presentSignUp`, `RoutePolicy.toolDestination(for:isGuest:)`, guest rewrite in `ToolDestinationView` |
| `Kuro/Views/Guest/GuestGate.swift` | create | View-side helper: `GuestGate.allows(_:guest:routes:mode:)` |
| `Kuro/Views/Guest/GuestSignUpSheet.swift` | create | Tool sheet: note line + `AuthView(entry: .guestSheet)`, ✕, discard guard, navigation layer |
| `Kuro/Views/Guest/GuestInvitationPage.swift` | create | Taste/Home/Collection/Clubs invitation page with "Create account" / "Sign in" |
| `Kuro/Views/AuthView.swift` | modify | `init(entry: AuthEntry = .welcome)`; `.guestSheet(mode:)` starts on the email step |
| `Kuro/Views/TastePicksView.swift` | modify | `TastePlanKey` action gated (`.plan`) |
| `Kuro/Views/LibraryViewActions.swift` + its 5 callers (`KuroRefinedCard.swift` ×2, `GridAnimeCard.swift`, `EditorialDiscoverFrames.swift`, `ClubDetailTabComponents.swift`) | modify | `toggleTracked(_:title:actions:guest:routes:)` gated (`.plan`) |
| `Kuro/Views/DetailPages/Prototype/AnimeDetailSections.swift`, `MangaDetailSections.swift`, `Kuro/Views/DetailPages/AnimeDetailView.swift`, `MangaDetailView.swift` | modify | Plan/save buttons gated (`.plan`); bell and "Between us" hidden or gated for guests |
| `Kuro/Views/Discover/Preview/DiscoverFeedbackController.swift`, `DiscoverTitleMenu.swift` | modify | Not interested / Seen it gated (`.discoverAnswer`) |
| `Kuro/Discovery/DiscoveryStore.swift`, `Kuro/Taste/TasteStore.swift`, `Kuro/Social/SocialActivityStore.swift`, `Kuro/Clubs/ClubsStore.swift`, `Kuro/Telemetry/OutboundLinkTelemetry.swift`, `Kuro/Catalog/CatalogStore.swift` | modify | Signed-out guards: no request that needs an account |
| `Kuro/Telemetry/InteractionTelemetry.swift` | modify | `suppressesSending` hook set to `{ guest.isGuest }` by composition (guests only; the auth wall's existing anonymous events unchanged) |
| `KuroTests/GuestModeTests.swift` | create | The five tagged tests + Review Focus pins |
| `KuroUITests/GuestBrowsingUITests.swift` | create | `testSignedOutLaunchShowsDiscoverNotAuthWall` |
| `scripts/load/profiles/guest-browse.js`, `scripts/load/profiles/guest-browse.test.js` | create | Profile `guest-browse` (F3 contract; anonymous, GET and per-request classes via F3.1b; 5 rps) |
| `scripts/load/workloads/tracker-gaps-combined.js` | modify | one line `"guest-browse": 5` |
| `docs/tracker-gaps-2026-11/W5-guest/EVIDENCE.md`, `live-anon-grants.sql` | create | Evidence note; read-only live grant audit query (also records the anon catalogue-table SELECT check) |
| `docs/tracker-gaps-2026-11/acceptance/W5.json` | create | F1 execution record (brief item 6) |
| `docs/superpowers/specs/2026-11-09-tracker-gaps/features/W5-guest.feature` | modify | corrections 2026-11-09: `@load` scenario states the absolute guest rate; new flag-off scenario (8 scenarios) |
| `CURRENT_APP_STATE.md`, `CURRENT_APP_STATE_PLAIN.md`, `IMPLEMENTATION_PLAN_Variation1.md`, `docs/modules/README.md`, `~/.claude/projects/-Users-max-Kuro-Anime-App/memory/MEMORY.md` | modify | Rules 1–2 |

### The anonymous allowlist (decision per RPC)

Allowlisted (anon EXECUTE). Every guest page calls these. All are SECURITY DEFINER over public catalogue rows unless marked INVOKER.

| # | regprocedure (exact) | Guest page | `auth.uid()` use | Decision |
|---|---|---|---|---|
| 1 | `public.discover_bundle(integer,integer)` | Discover | Writes NEW TO YOU impressions only `if v_user_id is not null` | anon-safe as is |
| 2 | `public.discover_section_page_v1(text,text,text,text,text,text,integer,integer)` | Discover See all | Personal exclusions only when signed in (`v_uid is null or …`) | anon-safe as is |
| 3 | `public.discover_mood_v1(text,text,integer,integer)` | Mood pages | `like_last_loved` answers no rows signed out | anon-safe as is |
| 4 | `public.media_franchise_ids_v1(integer[],integer[])` | Discover dedupe | none | anon-safe |
| 5 | `public.recommend_ids_similar_to_seeds(text,integer[],integer,boolean)` | More like this; called by #6 (INVOKER) | Excludes the caller's list only when signed in | anon-safe; required by #6 |
| 6 | `public.media_similar_v1(text,integer,integer)` (INVOKER) | Title page "More like this" | via #5 | anon-safe |
| 7 | `public.browse_anime_page(text,text,integer,integer,text,integer,timestamptz,integer,integer,integer,integer,text)` | Browse | none | anon-safe |
| 8 | `public.browse_manga_page(text,text,integer,integer,text,integer,timestamptz,integer,integer,integer,integer,text)` | Browse | none | anon-safe |
| 9 | `public.search_anime_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer)` | Search (page 2+, flag off, club/import callers) | none | anon-safe (unchanged by W4) |
| 10 | `public.search_manga_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean)` | Search (page 2+, flag off) | none | anon-safe (unchanged by W4) |
| 11 | `public.get_media_ladder(text,integer)` | Title seasons, original story, season pages | none | anon-safe |
| 12 | `public.get_manga_chapter_status(integer)` | Manga title | none | anon-safe |
| 13 | `public.media_release_schedule_v1(text,integer,integer)` | Title next-release row, timeline | none | anon-safe |
| 14 | `public.media_themes_v1(integer)` | Title songs | none | anon-safe |
| 15 | `public.anime_cast_v1(integer,text,integer)` (INVOKER) | Title cast rail | none | anon-safe |
| 16 | `public.character_voice_actors_v1(integer,text)` | Character page | none | anon-safe |
| 17 | `public.staff_voice_roles_v1(integer,integer)` | Staff page | none | anon-safe |
| 18 | `public.search_anime_page_v2(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer)` (W4) | Search page 1 with `search_adult_notice_v1` on | none (wraps #9) | anon-safe; W4 grants it to anon + authenticated |
| 19 | `public.search_manga_page_v2(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean)` (W4) | Search page 1 with `search_adult_notice_v1` on | none (wraps #10) | anon-safe |

Guests also read catalogue tables through RLS "Public read access" policies (unchanged, not EXECUTE): `anime`, `manga`, `episodes`, `chapters`, `anime_characters`, `anime_staff`, `anime_studios`, `manga_characters`, `manga_authors`, `manga_staff`, `external_links`, `characters`, `staff`, `studios`, `authors`, `anime_tags`, `manga_tags`, `tags`, `character_voice_actors`, `theme_links`, `feature_flags`, and the materialized view `mv_anime_trending`.

Not allowlisted. The client skips these for guests, or the section is hidden:

| Function(s) | Why | Guest behaviour |
|---|---|---|
| `fetch_daily_feature()` | Raises `not authenticated` when `auth.uid()` is null | Skipped; Discover uses its existing lead fallback |
| `fetch_because_you_rail`, `fetch_tonight_shelf`, `fetch_realm_hidden_gem`, `fetch_personalized_new_to_you`, `fetch_taste_deck_batch`, `fetch_my_taste_profile` | Personal (and flags at 0 %) | Skipped (owner guards) |
| `series_detail_bundle_v1`, `series_units_page_v1`, `series_editions_page_v1`, `home_*` | Personal; authenticated-only | Not reached (series flags off for guests; Home is an invitation) |
| `enqueue_media_relation_refresh`, `enqueue_media_availability_refresh`, `record_outbound_link`, `purge_outbound_link_events`, every list/club/comment/import writer | Writes | Skipped (owner guards); outbound links still open |
| `count_friends_tracking`, `fetch_friend_activity_for_title`, `friend_activity_page_v1`, club readers, `user_release_schedule_v1` | Private | Skipped; "Between us" hidden |
| `batch_provider*`, `get_media_availability_status`, `get_provider_availability_refresh_queue_summary` | `streaming_availability_v1` at 0 %, authenticated | Not reached |
| `catalogue_search_blob_v1(text,text,text)`, `current_season_name`, `_discover_page_v1`, old `browse_*`/`search_*` overloads, trigger/helper functions | Internal; reached only from SECURITY DEFINER callers | Revoked from anon |
| Everything else in `public` | — | Revoked by the sweep |

Extension member functions in `public` (`pg_trgm`, installed `with schema public` by one migration) are excluded from the sweep and from the assertion. They are pure, read no data, and belong to the extension.

**W4 note (cross-plan, final names):** W4 keeps v1 `search_anime_page`/`search_manga_page` byte-identical (rows 9–10) and adds `search_anime_page_v2`/`search_manga_page_v2` with v1's parameter lists, granted to `anon` and `authenticated` (rows 18–19). **Ordering:** W4's `20261118100000_search_hidden_adult_v1.sql` sorts and replays before this `20261118110000` file. Either merge order works in the fixture: before W4 lands, rows 18–19 do not resolve and are reported `tests.blocked` (section A) / `raise notice` (migration step 1), never a failure; after W4 lands they must be anon-executable or 114 fails. Live: the audit expects 19 rows when both migrations are applied (17 if only W5 is); if W4 is applied after W5, re-run the live audit after W4.

---

### Task 1: Anonymous EXECUTE allowlist (prepared migration + DB test 106)

**Files:** create `supabase/prepared-migrations/20261118110000_guest_anon_allowlist_v1.sql`, `supabase/tests/rls/114_guest_anon_allowlist.sql`; modify `supabase/tests/pending_migrations.txt`, `supabase/tests/README.md`.

**Interfaces:**
- **Consumes:** the fixture stub's `alter default privileges for role postgres in schema public grant all on functions to anon, authenticated, service_role` (`supabase/tests/fixtures/00_platform_stub.sql:71-76`), and the helpers `tests.as_anon()`, `tests.as_user(uuid)`, `tests.make_user(int)`, `tests.ok`, `tests.denied` (`supabase/tests/lib/00_test_helpers.sql`).
- **Produces:** the 19-row allowlist (table above; rows 18–19 resolve once W4's migration exists), the `feature_flags` row `guest_browsing_v1` (`enabled=false, rollout_percentage=0`), and default privileges under which new `public` functions are not executable by anon or PUBLIC.

- [ ] **Step 1: Write the failing test** `supabase/tests/rls/114_guest_anon_allowlist.sql`.
  - Header: `-- @requires table public.anime`, `-- @requires table public.manga`, `-- @requires table public.feature_flags`.
  - Before writing sections A and C, build the fixture and check that all 19 signatures exist (18–19 only after W4 is merged): `scripts/db/run_local_db_tests.sh --no-tests --report-dir <scratch>` + `\df`, or the first red run's section A label. Known risk: `20260806020000_serving_hardening_v1.sql` (latest `recommend_ids_similar_to_seeds`) FAILs in the baseline-first replay, so an older body is what the fixture holds. Each allowlisted function confirmed present is the subject (no `@requires`). Any signature the fixture lacks gets a `-- @requires-for "anon call <name>" function <sig>` scope (BLOCKED, not failed), and the live audit (Task 8) enforces it.
  - Body: `\set ON_ERROR_STOP on`, then `begin;` … `rollback;`, with these sections:
  - **A. Exact set.** `create temp table w5_allow(sig text)` with the 19 signatures, each normalised via `to_regprocedure(sig)::text`. Then compute `w5_anon` as `select p.oid::regprocedure::text` from `pg_proc p join pg_namespace n on n.oid=p.pronamespace` where `n.nspname='public'`, there is no `pg_depend` row with `deptype='e'` for `p.oid`, and `has_function_privilege('anon', p.oid, 'EXECUTE')`. Assertions:
    - `w5_allow_present` = `w5_allow` rows with `to_regprocedure(sig) is not null`. Each missing signature is reported with `tests.blocked('W5: allowlisted function absent from fixture: '||sig, 'live audit enforces it')`.
    - `tests.ok('W5: anon can execute every allowlisted function present', not exists (select * from w5_allow_present except select * from w5_anon))`
    - `tests.ok('W5: anon can execute nothing outside the allowlist: ' || coalesce((select string_agg(x,', ') from (select * from w5_anon except select * from w5_allow) e(x)),'none'), not exists (select * from w5_anon except select * from w5_allow))`. The label names every extra function, so the red run lists them. This is also the tripwire for later migrations that forget `revoke … from public`.
  - **B. No PUBLIC grant** on any non-extension `public` function: no `aclexplode(proacl)` row has `grantee = 0` with `privilege_type='EXECUTE'`. Also the five-function spot check `has_function_privilege('anon', …)` is false for `fetch_daily_feature()`, `fetch_because_you_rail(integer)`, `purge_outbound_link_events()`, `enqueue_media_relation_refresh(text,integer,text)` and `catalogue_search_blob_v1(text,text,text)`.
  - **C. No allowlisted call is denied as anon.** Run `select tests.as_anon();`, then call each one with real arguments inside a plpgsql block. `exception when insufficient_privilege then` records a failure; any other error is a NOTICE and counts as a pass, because fixture relations such as `curated_rail_items` do not replay. This proves the whole grant chain, INVOKER callees included, without depending on fixture data. The calls:
    - `discover_bundle(30,24)`
    - `discover_section_page_v1('trending','ANIME',null,null,null,'popular',24,0)`; use the parameter order of the deployed signature, read from `20261104100000`
    - `discover_mood_v1('cozy','ANIME',24,0)` and `discover_mood_v1('like_last_loved','ANIME',24,0)` (expected count 0)
    - `media_franchise_ids_v1(array[1],array[]::int[])`
    - `recommend_ids_similar_to_seeds('ANIME',array[1],12,false)`
    - `media_similar_v1('ANIME',1,12)`
    - `browse_anime_page()` and `browse_manga_page()` (defaults)
    - `search_anime_page('a')` and `search_manga_page('a')`
    - `search_anime_page_v2('a')` and `search_manga_page_v2('a')` (only when `to_regprocedure` resolves them, i.e. W4 merged)
    - `get_media_ladder('ANIME',1)`
    - `get_manga_chapter_status(1)`
    - `media_release_schedule_v1('ANIME',1,6)`
    - `media_themes_v1(1)`
    - `anime_cast_v1(1,'JAPANESE',50)`
    - `character_voice_actors_v1(1,'JAPANESE')`
    - `staff_voice_roles_v1(1,50)`

    Insert anime/manga/character/staff id 1 rows first, as `postgres` with `session_replication_role=replica`. Each call ends in `tests.ok('W5 anon call not denied: <name>', not v_denied)`. A final assertion checks that `(select count(*) from public.discover_rail_impressions)` is unchanged after the anon `discover_bundle` call.
  - **D. Denied as anon:** `tests.denied` for
    - `select public.fetch_daily_feature()`
    - `select public.enqueue_media_relation_refresh('ANIME',1,'probe')`
    - `select public.record_outbound_link('ANIME',1,'watch','x')`
    - `select public.series_detail_bundle_v1('anime',1,null,null)`
    - `select public.count_friends_tracking('[]')`
    - `select public.purge_outbound_link_events()`
    - `select public.home_bundle_v1('anime',7,12,20)`
    - `select public.apply_progress_mutations_v1('[]'::jsonb)`

    Use the exact signatures from the latest migrations, and confirm each one with `\df` in the fixture before you write it.
  - **E. Other roles unchanged:** `has_function_privilege('authenticated', …)` is true for `fetch_daily_feature()`, `series_detail_bundle_v1(text,integer,uuid,text)`, `home_bundle_v1(…)` and `apply_progress_mutations_v1(jsonb)`; `has_function_privilege('service_role', …)` is true for `purge_outbound_link_events()`; `has_function_privilege('authenticated','public.check_email_exists(text)','EXECUTE')` is still false.
  - **F. Per-schema anon default gone.**
    - `tests.ok('W5: no per-schema default grants anon EXECUTE in public', not exists (select 1 from pg_default_acl d join pg_namespace n on n.oid=d.defaclnamespace, aclexplode(d.defaclacl) a where n.nspname='public' and d.defaclobjtype='f' and a.grantee='anon'::regrole))`.
    - As `postgres`, create `public.w5_probe() returns int language plpgsql set search_path = public, extensions as $$ begin return 1; end $$` and run `revoke all on function public.w5_probe() from public` (the §3 pattern). Then assert `not has_function_privilege('anon','public.w5_probe()','EXECUTE')` and `has_function_privilege('authenticated','public.w5_probe()','EXECUTE')`.
  - **G. Catalogue tables.** As anon, `tests.ok` that `select count(*) from public.<t>` succeeds for each guest table listed above, and that `select count(*) from public.anime_user_lists` returns 0.
  - **H. Flag row.** `tests.ok('W5: guest_browsing_v1 exists and is off', exists(select 1 from public.feature_flags where flag_name='guest_browsing_v1' and enabled=false and rollout_percentage=0))`.
- [ ] **Step 2: Run it.** `scripts/db/run_local_db_tests.sh --only 114_guest_anon_allowlist`. Expected FAIL: `not ok … W5: anon can execute nothing outside the allowlist: …fetch_daily_feature()…` (plus the section B, D, F and H failures). Paste the extra-function list into the evidence note (red).
- [ ] **Step 3: Implement the migration.** `begin; set local lock_timeout='3s'; set local search_path = public, extensions;`, then one plpgsql `do $$ … $$` block, then `commit;`. The header names the owner approval and D-W5-DP, and says "deploy only after the W5 build is approved; client guests depend on the allowlist". Algorithm (the order matters):
  1. `v_allow regprocedure[]` from the 19 strings that `to_regprocedure` resolves. `raise notice 'W5: allowlisted function absent: %'` for any that do not resolve. Production presence is enforced by the Task 8 live audit (exactly 19 rows once W4 is applied, else 17), so the prepared file still applies to the incomplete fixture (PREPARED verdict).
  2. Snapshot. Create a temp table `w5_before(fn oid, role name)` holding every (non-extension `public` function, role) pair where the role is not `anon`, not `rolsuper`, not `pg_%`, and `has_function_privilege(role, fn, 'EXECUTE')` is true.
  3. For each non-extension `public` function: `execute format('revoke execute on function %s from public, anon', fn::regprocedure)`.
  4. For each `w5_before` row whose privilege is now false: `execute format('grant execute on function %s to %I', fn::regprocedure, role)`. This covers roles that had EXECUTE only through PUBLIC.
  5. `grant execute on function <each allowlisted> to anon`.
  6. `alter default privileges for role postgres in schema public revoke execute on functions from anon;` as a top-level statement after the `do` block. No global PUBLIC default revoke (D-W5-DP).
  7. `insert into public.feature_flags (flag_name, enabled, rollout_percentage, target_markets, description) values ('guest_browsing_v1', false, 0, '{}', 'W5: browse before signing up (guest mode)') on conflict (flag_name) do nothing;`
  8. A final `do` block raises `'W5: anon EXECUTE outside allowlist: %'` if anon can execute anything outside the allowlist, and `'W5: role % lost EXECUTE on %'` if any `w5_before` row is no longer true. A live function owned by another role that `postgres` cannot revoke therefore aborts the whole migration instead of silently staying open.
- [ ] **Step 4: Register.** Add `20261118110000_guest_anon_allowlist_v1.sql` under a `# 2026-11-10 W5 guest mode (prepared only; owner approval required; release gated by D-A + capacity PASS).` comment in `pending_migrations.txt`. Add a row to the README "Pending now" table: `` `20261118110000_guest_anon_allowlist_v1.sql` | anon EXECUTE = 19-function allowlist (17 + W4's two v2 search functions); PUBLIC EXECUTE removed in public; per-schema anon default removed; guest_browsing_v1 off | `106` ``.
- [ ] **Step 5: Run.**
  - `scripts/db/run_local_db_tests.sh --only 114_guest_anon_allowlist`: expected `TESTS : 1 test files, … assertions passed, 0 finding markers -> PASS`.
  - The whole suite, `scripts/db/run_local_db_tests.sh`: expected exit `4`, the honest BLOCKED state that is unchanged from before; no test fails. Pay attention to the anon assertions already in 84, 85, 86, 87 and 98 (they assert anon on allowlisted readers only).
  - `scripts/db/run_local_db_tests.sh --exclude-pending --only 114_guest_anon_allowlist`: expected FAIL, the red half for the evidence.
- [ ] **Step 6: Commit.** `git add supabase/prepared-migrations/20261118110000_guest_anon_allowlist_v1.sql supabase/tests/rls/114_guest_anon_allowlist.sql supabase/tests/pending_migrations.txt supabase/tests/README.md`, message `W5: prepared anon EXECUTE allowlist + DB test 106 (not applied)`.

### Task 2: Guest state and the pending intent (owner + pure rules)

**Files:** create `Kuro/Identity/PendingGuestIntent.swift`, `Kuro/Identity/GuestCopy.swift`, `Kuro/Identity/GuestSession.swift`, `KuroTests/GuestModeTests.swift`; modify `Kuro/Services/FeatureFlags.swift`, `Kuro/Composition/AppComposition.swift`, `Kuro/KuroApp.swift`.

**Interfaces:**
- **Consumes:** `IdentityStore` (`configError`, `isAuthBootstrapping`, `isAuthenticated`, `requiresPasswordUpdate`, `currentUserId`), `FeatureFlags.evaluate(_:)`, `LibraryActions` (`accountSession`, `save(_:status:)`), `TasteStore.recordDiscoverFeedback(_:for:)`, `ClubsStore.joinClub(inviteCode:)`, `BannerCenter.show(_:duration:)`, `DiscoverFeedback`.
- **Produces:**

```swift
nonisolated enum PendingGuestIntent: Equatable, Sendable {
    case plan(MediaKey, title: String)
    case discoverAnswer(MediaKey, DiscoverFeedback, title: String)
    case joinClub(code: String)
    case openTitle(MediaKey)          // tracking editor, add to club, bell: re-open the title after sign-up
}
nonisolated struct GuestSignUpRequest: Equatable, Sendable, Identifiable {
    let intent: PendingGuestIntent?
    let mode: AuthFormRules.Mode       // .signUp from actions, .signIn from the header
    var id: String { "signUp" }
}
nonisolated enum RootPresentation: Equatable {
    case configError, bootstrapping, setPassword, signedIn(userId: String), guest, authWall
    static func resolve(configError: Bool, isBootstrapping: Bool, isAuthenticated: Bool,
                        requiresPasswordUpdate: Bool, userId: String?, guestEnabled: Bool) -> RootPresentation
}
nonisolated enum GuestPager {
    /// The guest order mirrors the live signed-in order; Browse is reached from Discover and Search.
    static let order: [KuroMainView.Section] = [.taste, .home, .discover, .collection, .clubs]
    static let invitationSections: Set<KuroMainView.Section> = [.taste, .home, .collection, .clubs]
}
nonisolated enum GuestReadAllowlist {
    static let rpcs: Set<String>      // the 19 function names, as "rpc/<name>" (incl. W4's search_*_page_v2)
    static let tables: Set<String>    // the catalogue tables/view listed above
    static func permits(resource: String) -> Bool   // strips a query string; true for rpcs ∪ tables
}
@MainActor @Observable final class GuestSession {
    init(identity: IdentityStore, flags: FeatureFlags, libraryActions: LibraryActions,
         taste: TasteStore, clubs: ClubsStore, banner: BannerCenter)
    var isGuest: Bool { get }                          // RootPresentation.resolve(...) == .guest
    private(set) var pendingIntent: PendingGuestIntent?
    func begin(_ intent: PendingGuestIntent?)          // newest wins; called by the sign-up sheet on appear
    func signUpSheetClosed()                           // discards only while identity.isAuthenticated == false
    func replayPendingIntent(for context: AccountContext) async   // take-and-clear, once (Task 3)
    private(set) var reopenAfterSignUp: (key: MediaKey, account: AccountContext)?   // observable
    func takeReopenTitle(for current: AccountContext?) -> MediaKey?   // same account only; clears either way
}
```

- `FeatureFlags`: `var guestBrowsingV1Enabled: Bool { evaluate("guest_browsing_v1") }`. With no user id, only a 100 % rollout or `--ff-on=guest_browsing_v1` turns it on; the existing `guard let uid` in `evaluate` gives that.
- `GuestCopy` (EN / DE):
  - `sheetNote(for: .plan, german:)` = "Kuro keeps nothing on this phone until you have an account; the title you picked is added as soon as you sign up." / "Kuro speichert nichts auf diesem Gerät, bis du ein Konto hast; der Titel, den du gewählt hast, wird hinzugefügt, sobald du dich registrierst."
  - `sheetNote(for: nil)` = "Kuro keeps nothing on this phone until you have an account." / "Kuro speichert nichts auf diesem Gerät, bis du ein Konto hast."
  - Each other intent: "Kuro keeps nothing on this phone until you have an account; we finish this as soon as you sign up." / "Kuro speichert nichts auf diesem Gerät, bis du ein Konto hast; wir erledigen das, sobald du dich registrierst."
  - Banners `planned(title)` "Added “%@” to Planning." / "„%@“ steht jetzt auf deiner Planliste."; `alreadyListed(title)` "“%@” is already in your list." / "„%@“ ist schon in deiner Liste."; `replayFailed(title)` "Couldn't add “%@”. Try again from its page." / "„%@“ konnte nicht hinzugefügt werden. Versuch es auf der Titelseite noch einmal."
  - Invitation title per section plus the buttons "Create account" / "Konto erstellen" and "Sign in" / "Anmelden".

- [ ] **Step 1: Write the failing tests** in `KuroTests/GuestModeTests.swift` (`@MainActor @Suite struct GuestModeTests`):
  - `rootResolvesGuestAfterSignOut`: `#expect(RootPresentation.resolve(configError: false, isBootstrapping: false, isAuthenticated: false, requiresPasswordUpdate: false, userId: nil, guestEnabled: true) == .guest)`; the same with `guestEnabled: false` gives `.authWall`; `isAuthenticated: true, userId: "u"` gives `.signedIn(userId: "u")`; `isBootstrapping: true` gives `.bootstrapping`; `configError: true` gives `.configError`. On a `testingGraph` with `--ff-on=guest_browsing_v1` flags, after `await graph.session.endSession()`, `graph.guest.isGuest == true`.
  - `guestPagerHasInvitationPages`: `#expect(GuestPager.order == [.taste, .home, .discover, .collection, .clubs])`; `#expect(GuestPager.invitationSections == [.taste, .home, .collection, .clubs])`; `#expect(!GuestPager.order.contains(.browse))` (Browse comes from the Discover entry).
  - `intentSurvivesSheetTeardownAfterSignUp`: on a graph, call `guest.begin(.plan(frieren, title: "Frieren"))`, set `identity.isAuthenticated = true` (as `applySession` does), call `guest.signUpSheetClosed()`, then `#expect(guest.pendingIntent == .plan(frieren, title: "Frieren"))`. With `isAuthenticated == false` the same call gives `#expect(guest.pendingIntent == nil)`.
  - Shared constant: `let frieren = MediaKey(kind: .anime, id: 154587)`.
- [ ] **Step 2: Run.** `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,id=7FC4B58A-430C-457D-A017-6B0095723F3F' test -only-testing:KuroTests/GuestModeTests`. Expected: build failure `cannot find 'RootPresentation' in scope`.
- [ ] **Step 3: Implement** the types above.
  - Build `GuestSession` in `AppComposition.makeGraph` right after `identity`, from `identity`, `shell.flags`, `libraryActions`, `assistant.taste`, `clubs` and `shell.banner`; add `let guest: GuestSession` to `AppGraph` and `var guest: GuestSession { graph.guest }` to `AppComposition`.
  - It is **not** an `AccountScopedState`: it holds no account data, and its intent exists only while signed out.
  - Inject it in `KuroApp` with `.environment(guest)` (add `@State private var guest = AppComposition.shared.guest`).
  - `RootView` switches on `RootPresentation.resolve(…, guestEnabled: flags.guestBrowsingV1Enabled)`. `.guest` shows `ContentView(pendingDeepLink:).id("guest")`, `.authWall` shows `AuthView()`, and the other cases keep today's views.
- [ ] **Step 4: Run** the same command. Expected: `GuestModeTests` 3 tests passed.
- [ ] **Step 5: Commit.** `git add Kuro/Identity/PendingGuestIntent.swift Kuro/Identity/GuestCopy.swift Kuro/Identity/GuestSession.swift Kuro/Services/FeatureFlags.swift Kuro/Composition/AppComposition.swift Kuro/KuroApp.swift KuroTests/GuestModeTests.swift`, message `W5: guest state, pending intent, root presentation`.

### Task 3: Replay once after sign-up; discard on cancel; signed-out flag read

**Files:** modify `Kuro/Identity/SessionController.swift`, `Kuro/Identity/GuestSession.swift`, `Kuro/Services/FeatureFlags.swift`, `Kuro/Composition/AppComposition.swift`, `KuroTests/GuestModeTests.swift`.

**Interfaces:**
- **Consumes:** `SessionSDKHarness` and `StubAuth` (`KuroTests/IdentityCompositionTests.swift`), `FakeLibraryBackend` (`KuroTests/LibraryTestSupport.swift`), `LibraryChange.Kind` (`.added` / `.updated`), `AccountSessionCoordinator.withCredentialLease(for:_:)` (`Packages/KuroModules/Sources/KuroCore/AccountSession.swift:120`; pattern `Kuro/Home/HomeStore.swift:99`), and the lease test pattern `KuroTests/CredentialLeaseTests.swift` (`signedInAsAKeepingBsSession`, line 37; `preDispatchSwitchSendsNothingAsB`, line 47).
- **Produces:**
  - `SessionController.init(…, guest: GuestSession, accountScopedStates:)`.
  - The private `bootstrapAfterAuth()` becomes `let context = accountSession.current; await bootstrapAccountData(); guard let context, accountSession.isCurrent(context) else { return }; await guest.replayPendingIntent(for: context)`. Today's body moves unchanged into `bootstrapAccountData()`.
  - `FeatureFlags.refreshSignedOut(client: Any, accountSession: AccountSessionCoordinator, timeout: Duration) async`: one attempt, no retries; it applies its result only while `accountSession.current == nil`, and returns after `timeout` even when the read is still in flight.
  - `enum GuestLaunchPolicy { static let flagWait: Duration = .milliseconds(1500) }`.
  - Credential lease (brief item 2): anonymous guest reads need none (there is no account). The replayed intent is the first private request of the new account and runs as one lease: `try await accountSession.withCredentialLease(for: context) { … dispatch the intent … }`. `.joinClub` already leases internally (`ClubsStore.swift:156`, covered by `CredentialLeaseTests/preDispatchSwitchForEveryFamily(clubJoin)`). `.discoverAnswer` (`TasteStore.recordDiscoverFeedback`, synchronous) only enqueues into the Taste signal outbox; the later drain sends through `recordTasteDeckSignal`, which leases the account current at send time (`TasteStore.swift:338`), and `TasteStore.clearPrivateState` empties `pendingSignals` / `outboxAccount` on an account change, so the outer lease does not bind that send and does not need to. `.plan` through `LibraryActions.save` takes no lease of its own, so the outer lease is what binds it. A refused or revoked lease (`CancellationError`) drops the intent silently: it is never replayed into another account.

- [ ] **Step 1: Write the failing tests** (in `GuestModeTests`):
  - `pendingIntentReplaysOnceAfterSignUp`:
    - `let backend = FakeLibraryBackend()`.
    - `let h = try SessionSDKHarness(responder: StubAuth.signInResponder { r in StubAuth.isAuth(r, "signup") ? .json(StubAuth.sessionJSON(StubAuth.userA, email: "a@example.com")) : .emptyArray }, libraryBackend: backend)`.
    - `h.graph.guest.begin(.plan(frieren, title: "Frieren"))`.
    - `try await h.session.signUpWithEmail(email: "a@example.com", password: "long-enough")`.
    - Then `#expect(backend.rows(for: StubAuth.userA)[frieren]?.status == .planning)`, `#expect(backend.writeCalls.filter { if case .insertIfMissing(frieren, _) = $0 { true } else { false } }.count == 1)`, `#expect(h.graph.banner.message == "Added “Frieren” to Planning.")` and `#expect(h.graph.guest.pendingIntent == nil)`.
    - Second bootstrap: `await h.session.handleAuthEvent(...)` with the SDK `.signedIn` event for user A. Use the same entry the `handleAuthEvent` tests use, and read its signature before writing. Afterwards the write count is still `1`.
    - `await h.tearDown()`.
  - `pendingIntentDiscardedWhenSignUpCancelled`: `guest.begin(.plan(frieren, title: "Frieren"))`; `guest.signUpSheetClosed()` while signed out; `#expect(guest.pendingIntent == nil)`. Then `try await h.session.signInWithEmail(email: "a@example.com", password: "long-enough")` and `#expect(backend.writeCalls.isEmpty)`, `#expect(h.graph.banner.message == nil)`.
  - `replayOnTrackedTitleSaysAlreadyInList`: `backend.setRows([FakeLibraryBackend.entry(.anime, 154587, rowId: 1, status: .current)], for: StubAuth.userA)`; begin `.plan`; sign in. Then `#expect(backend.rows(for: StubAuth.userA)[frieren]?.status == .current)` (never downgraded) and `#expect(h.graph.banner.message == "“Frieren” is already in your list.")`.
  - `flagOffSendsNoRequest` (brief item 1): a `SessionSDKHarness` with no stored session (so `restoreSession` takes the failed-restore path and `refreshSignedOut` runs) whose `feature_flags` answer has `guest_browsing_v1` `enabled=false, rollout_percentage=0`. Afterwards `RootPresentation.resolve(…, guestEnabled: flags.guestBrowsingV1Enabled) == .authWall`, `graph.guest.isGuest == false`, and the set of non-Auth request resources is a subset of `["feature_flags"]` (the switch's own read; no catalogue table, no RPC, no `concierge_events`). `guest.replayPendingIntent(for:)` with no intent sends nothing. Red: `refreshSignedOut` does not exist yet (build failure), a genuine missing behaviour.
  - `replayAfterAccountSwitchSendsNothingAsB` (brief item 2): modelled on `CredentialLeaseTests.preDispatchSwitchSendsNothingAsB`. `guest.begin(.plan(frieren, title: "Frieren"))`; sign up as A with the harness holding B's session (`signedInAsAKeepingBsSession` pattern); switch the funnel to B after `bootstrapAccountData()` and before the replay dispatches. Expect no request to `anime_user_lists` (any method) whose `bearerSubject == userB`, `backend.writeCalls.isEmpty` for B, no banner, and `guest.pendingIntent == nil` (dropped, not kept for B). Second case, `.discoverAnswer(frieren, .notInterested, title:)` with the same switch: no `rpc/record_taste_deck_signal` request carries B's bearer for A's answer, and B's `TasteStore` outbox is empty.
  - `signedOutLaunchReadsFlagsWithinTheWait`: a `PublicDataHarness` whose responder holds `feature_flags` until released; `await flags.refreshSignedOut(client:…, accountSession:…, timeout: .milliseconds(200))` returns within 1 s (measured with `ContinuousClock`) and leaves `guestBrowsingV1Enabled == false`. After the held response answers `[{"flag_name":"guest_browsing_v1","enabled":true,"rollout_percentage":100,"target_markets":[]}]` and a second call, `guestBrowsingV1Enabled == true`.
- [ ] **Step 2: Run** `-only-testing:KuroTests/GuestModeTests`. Expected FAIL: first the build (`value of type 'FeatureFlags' has no member 'refreshSignedOut'`, used by `flagOffSendsNoRequest` and `signedOutLaunchReadsFlagsWithinTheWait`). With a temporary empty `refreshSignedOut` stub the build passes and `pendingIntentReplaysOnceAfterSignUp` fails with `Expectation failed: backend.rows(...)[frieren]?.status → nil == .planning` (no replay exists yet). Both are genuine missing behaviour (brief item 7).
- [ ] **Step 3: Implement.**
  - `replayPendingIntent(for:)` rules:
    - Take and clear the intent first (`let intent = pendingIntent; pendingIntent = nil`), on the main actor before any suspension. This is what makes "exactly once" hold across repeated bootstraps.
    - If `library.loadState != .loaded`, await `libraryActions.startLibraryRefresh(for: context).value`.
    - Stop silently unless `accountSession.isCurrent(context)`.
    - Dispatch the intent inside `try await accountSession.withCredentialLease(for: context) { … }`; on `CancellationError` return without banner and without restoring the intent.
    - `.plan`: `libraryActions.save(key, status: .planning)`. Banner `planned` on `change.kind == .added`, `alreadyListed` on `.updated`, `replayFailed` on `.failed`.
    - `.discoverAnswer`: `taste.recordDiscoverFeedback(feedback, for: key)`; no banner, because Discover's own toast is not on screen after the rebuild.
    - `.joinClub`: `try await clubs.joinClub(inviteCode:)`. On success show the banner "Joined the club." / "Du bist dem Club beigetreten."; on failure use the existing join-error copy.
    - `.openTitle`: store `reopenAfterSignUp = (key, context)`. This is an observable property. `takeReopenTitle(for current: AccountContext?) -> MediaKey?` returns the key only when `current == context` and clears it either way, so an unconsumed key never reaches another account.
  - In `restoreSession`'s failure branch (the `endSessionAfterFailedRestore` path), before returning, run `await flags.refreshSignedOut(client: client, accountSession: accountSession, timeout: GuestLaunchPolicy.flagWait)`. `isAuthBootstrapping` stays true for at most that long, and the launch screen covers it.
  - Pass `guest` into `SessionController` in `makeGraph`.
- [ ] **Step 4: Run.** Expected: `GuestModeTests` all passed. Then run `-only-testing:KuroTests/IdentityCompositionTests -only-testing:KuroTests/AuthLaneTests`: still passing.
- [ ] **Step 5: Commit.** `git add Kuro/Identity/SessionController.swift Kuro/Identity/GuestSession.swift Kuro/Services/FeatureFlags.swift Kuro/Composition/AppComposition.swift KuroTests/GuestModeTests.swift`, message `W5: replay the guest intent once after bootstrap; bounded signed-out flag read`.

### Task 4: Guests read only the allowlist (owner guards)

**Files:** modify `Kuro/Discovery/DiscoveryStore.swift`, `Kuro/Taste/TasteStore.swift`, `Kuro/Social/SocialActivityStore.swift`, `Kuro/Clubs/ClubsStore.swift`, `Kuro/Telemetry/OutboundLinkTelemetry.swift`, `Kuro/Telemetry/InteractionTelemetry.swift`, `Kuro/Catalog/CatalogStore.swift`, `Kuro/Composition/AppComposition.swift`, `KuroTests/GuestModeTests.swift`.

**Interfaces:**
- **Consumes:** `PublicDataHarness` (signed out, `StubSupabase.anonKey`) and `GuestReadAllowlist.permits(resource:)`.
- **Produces:**
  - Signed-out guards that return before any request: `guard accountSession.current != nil else { return <empty> }`.
    - `DiscoveryStore.fetchDailyFeature()` returns `nil`.
    - `fetchBecauseYouRail`, `fetchTonightShelf` and `fetchRealmHiddenGem` return `nil`.
    - `TasteStore.fetchPersonalizedNewToYou` returns `nil`.
    - `SocialActivityStore.prefetchFriendCounts` returns.
    - `fetchFriendActivityForTitle` throws `CancellationError()`.
    - `ClubsStore.checkClubNotifications` returns.
    - `OutboundLinkTelemetry.recordOutboundLink` returns a completed task when `context == nil`.
    - `InteractionTelemetry` gains `@ObservationIgnored var suppressesSending: @MainActor () -> Bool = { false }`. `track`/`trackInteractionEvent` return `nil` when it is true. `makeGraph` sets it to `{ [weak guest] in guest?.isGuest == true }` after building `GuestSession`, so it applies to guests only and the auth wall's existing anonymous events are unchanged (D-W5-T default).
  - `CatalogStore.init(client: SupabaseClient?, accountSession: AccountSessionCoordinator)`: `enqueueMediaRelationRefresh` returns when `accountSession.current == nil`. Update `makePublicData` to pass it.

- [ ] **Step 1: Write the failing tests:**
  - `guestCanOpenTitleEntityAndSeasonPages` (tag). Set up a `PublicDataHarness` (signed out) whose responder answers `anime` with one Frieren row and `rpc/get_media_ladder` with one prequel season `{media_id: 52991}`; everything else answers `[]`. Drive exactly the reads the pages make:
    - title, through the `AnimeDetailSections.swift` load table: `catalog.fetchAnimeById(154587)`, `fetchMediaLadder(mediaType: "ANIME", mediaId: 154587)`, `fetchCast(forAnime:)`, `fetchCharactersForAnime`, `fetchStaffForAnime`, `fetchStudiosForAnime`, `fetchEpisodesPage(animeId:offset:0,limit:50)`, `fetchExternalLinks`, `availability.resolveWatchLinks(animeId: 154587, …)` (use the signature in `ProviderAvailabilityStore+DetailLinks.swift:41`; with `streaming_availability_v1` off it reads only `external_links`/`episodes`), `releases.mediaSchedule(kind: .anime, id: 154587)`, `releases.themes(animeId:)`, `recommendations.fetchSimilar(kind: .anime, id: 154587)`, `try? await social.fetchFriendActivityForTitle(mediaType: "ANIME", mediaId: 154587)`, and `enqueueMediaRelationRefreshIfNeeded(... ladder: weak)`;
    - character page: `fetchMediaByCharacter(characterId: 1)`, `fetchVoiceActors(forCharacter: 1)`;
    - season page (`DetailNavigation.seasonPage(id: 52991)`, the title page of that season): `fetchAnimeById(52991)`, `fetchMediaLadder(mediaType: "ANIME", mediaId: 52991)`.

    Assertions:
    - `#expect(h.server.requests.compactMap(\.resource).allSatisfy(GuestReadAllowlist.permits))`
    - `#expect(h.server.requests.allSatisfy { $0.header("Authorization") == "Bearer \(StubSupabase.anonKey)" })`
    - `#expect(h.requests(to: "rpc/enqueue_media_relation_refresh").isEmpty)`
    - `#expect(h.requests(to: "rpc/fetch_friend_activity_for_title").isEmpty)`
    - `#expect(!h.requests(to: "rpc/get_media_ladder").isEmpty)`, and likewise for `rpc/character_voice_actors_v1` and `anime`.
  - `guestDiscoverBrowseAndSearchReadOnlyTheAllowlist`: signed out, call `discovery.ensureDiscoverBundle()`, `discovery.fetchDailyFeature()`, `discovery.fetchBecauseYouRail()`, `taste.fetchPersonalizedNewToYou(limit: 20, mediaType: "ANIME")`, `taste.loadDiscoverHidden()`, `discovery.moodPage(.cozy, …)` (use the existing signature), `discovery.browseAnimePage(…)`, `search` for `"Frieren"`, `social.prefetchFriendCounts(items: [("ANIME", 1)])` (await the task the test seam exposes, or poll `server.requests` for 1 s), `clubs.checkClubNotifications()`, and `graph.outboundLinks.recordOutboundLink(mediaType: "ANIME", mediaId: 1, linkKind: "watch", provider: "x").value`. Then assert the same two `allSatisfy` checks, plus `h.requests(to: "rpc/fetch_daily_feature").isEmpty`, `h.requests(to: "rpc/count_friends_tracking").isEmpty` and `h.requests(to: "concierge_events").isEmpty`.
  - `guestBrowsingWritesNoAccountKeys`: record `Set(h.defaults.dictionaryRepresentation().keys)` before and after the two read sequences above plus `discovery.recordRecentSearch("Frieren")`. `#expect(after.subtracting(before).allSatisfy { $0.hasPrefix("kuro.featureFlags") })`. Read `FeatureFlags`' cache key prefix before writing this, and use the exact prefix.
- [ ] **Step 2: Run** `-only-testing:KuroTests/GuestModeTests`. Expected FAIL: `guestDiscoverBrowseAndSearchReadOnlyTheAllowlist` → `rpc/fetch_daily_feature` was requested (and `rpc/count_friends_tracking`); `guestCanOpenTitleEntityAndSeasonPages` → `rpc/enqueue_media_relation_refresh` was requested.
- [ ] **Step 3: Implement** the guards above. Each is one `guard` at the top of the method. Match the `accountSession.current` style already used by `fetchBecauseYouRail`.
- [ ] **Step 4: Run.** Expected: all `GuestModeTests` pass. Also run `-only-testing:KuroTests/DiscoverLaneTests -only-testing:KuroTests/DetailsSongsDataTests -only-testing:KuroTests/SharedInfrastructureTests`: still passing. The signed-in paths are unchanged.
- [ ] **Step 5: Commit.** `git add Kuro/Discovery/DiscoveryStore.swift Kuro/Taste/TasteStore.swift Kuro/Social/SocialActivityStore.swift Kuro/Clubs/ClubsStore.swift Kuro/Telemetry/OutboundLinkTelemetry.swift Kuro/Telemetry/InteractionTelemetry.swift Kuro/Catalog/CatalogStore.swift Kuro/Composition/AppComposition.swift KuroTests/GuestModeTests.swift`, message `W5: signed-out guards so guests read only the allowlist`. `CatalogStore(client:)` has no other call site (verified by grep: only `AppComposition.makePublicData`).

### Task 5: Sign-up tool sheet and gated actions

**Files:** create `Kuro/Views/Guest/GuestGate.swift`, `Kuro/Views/Guest/GuestSignUpSheet.swift`; modify `Kuro/Views/Routing/KuroRoutes.swift`, `Kuro/Views/AuthView.swift`, `Kuro/Views/TastePicksView.swift`, `Kuro/Views/LibraryViewActions.swift`, `Kuro/Views/KuroRefinedCard.swift`, `Kuro/Views/SharedCards/GridAnimeCard.swift`, `Kuro/Views/EditorialDiscoverFrames.swift`, `Kuro/Views/ClubDetailTabComponents.swift`, `Kuro/Views/DetailPages/Prototype/AnimeDetailSections.swift`, `Kuro/Views/DetailPages/Prototype/MangaDetailSections.swift`, `Kuro/Views/DetailPages/AnimeDetailView.swift`, `Kuro/Views/DetailPages/MangaDetailView.swift`, `Kuro/Views/Discover/Preview/DiscoverFeedbackController.swift`, `Kuro/Views/Discover/Preview/DiscoverTitleMenu.swift`, `KuroTests/GuestModeTests.swift`.

**Interfaces:**
- **Consumes:** `KuroRoutes`, `RoutePolicy`, `ToolDestinationView`, `AuthFormRules.Mode`, `.kuroDiscardGuard(isDirty:isBusy:isConfirming:onDiscard:)`, `.kuroNavigationLayer(_:isPresented:)`, `.kuroLeavesJourney()`.
- **Produces:**
  - `AppRoute.signUp(GuestSignUpRequest)` (id `"signUp"`; `RoutePolicy.journeyPage(for:)` returns `nil`, so it is a tool).
  - `KuroRoutes.presentSignUp: (GuestSignUpRequest) -> Void`, also wrapped by `gated(by:)`.
  - `RouteDestination.signUp(GuestSignUpRequest)`.
  - `RoutePolicy.toolDestination(for route: AppRoute, isGuest: Bool) -> RouteDestination`: maps `.trackingEditor(r)` → `.signUp(.init(intent: .openTitle(r.media.libraryKey), mode: .signUp))` and `.addToClub(k)` → `.signUp(.init(intent: .openTitle(k), mode: .signUp))` when `isGuest`; otherwise `destination(for:)`. `ToolDestinationView` reads `@Environment(GuestSession.self)` and uses it.
  - `@MainActor enum GuestGate { static func allows(_ intent: PendingGuestIntent?, guest: GuestSession, routes: KuroRoutes, mode: AuthFormRules.Mode = .signUp) -> Bool }`. It returns `true` when the user is not a guest. Otherwise it calls `routes.presentSignUp(GuestSignUpRequest(intent: intent, mode: mode))` and returns `false`.
  - `AuthView.init(entry: AuthEntry = .welcome)` with `enum AuthEntry: Equatable { case welcome, guestSheet(mode: AuthFormRules.Mode) }`; `.guestSheet` starts on `.email` with that mode.
  - `struct GuestSignUpSheet: View { let request: GuestSignUpRequest }`:
    - It shows the `GuestCopy.sheetNote(for:)` line above `AuthView(entry: .guestSheet(mode:))`, plus a ✕ labelled "Close" / "Schließen".
    - `.onAppear { guest.begin(request.intent) }`; on ✕ or swipe-down dismissal, `guest.signUpSheetClosed()`.
    - `.kuroDiscardGuard(isDirty: <email or password typed>, …)`, registered as layer `"guestSignUp"`.
    - A deep-link collapse closes it like ✕ (that counts as cancel).
  - `LibraryViewActions.toggleTracked(_ key: MediaKey, title: String, actions: LibraryActions, guest: GuestSession, routes: KuroRoutes) -> Task<Void, Never>?`, gated with `.plan(key, title:)`.
  - Gated call sites:
    - `TastePlanKey`: `GuestGate.allows(.plan(card.key, title: card.media.title), …)` before `controller.tap`.
    - `AnimeDetailSections`:601, `MangaDetailSections`:526, `AnimeDetailView`:954 and `MangaDetailView`:1047 (`.plan`).
    - The `DiscoverFeedbackController` / `DiscoverTitleMenu` answers (`.discoverAnswer`).
    - The detail bell → `GuestGate.allows(.openTitle(key), …)`.
    - The "Between us" / `FriendsActivitySection` is not rendered while `guest.isGuest`.
  - The four `toggleTracked` callers and `ClubDetailTabComponents` (not reachable by guests) pass `guest`/`routes` through.

- [ ] **Step 1: Write the failing tests:**
  - `saveAsGuestOpensSignUpWithPendingIntent` (tag). On a graph with `--ff-on=guest_browsing_v1`, signed out:
    - `var shown: [AppRoute] = []; let routes = KuroRoutes { shown.append($0) }`.
    - `let allowed = GuestGate.allows(.plan(frieren, title: "Frieren"), guest: graph.guest, routes: routes)`.
    - `#expect(allowed == false)`.
    - `#expect(shown.map(\.id) == ["signUp"])`.
    - `guard case .signUp(let request) = shown.first else { Issue.record("no sign-up route"); return }`.
    - `#expect(request.intent == .plan(frieren, title: "Frieren"))`.
    - `#expect(GuestCopy.sheetNote(for: request.intent, german: false) == "Kuro keeps nothing on this phone until you have an account; the title you picked is added as soon as you sign up.")`.
    - Simulate the sheet appearing: `graph.guest.begin(request.intent)`, then `#expect(graph.guest.pendingIntent == .plan(frieren, title: "Frieren"))`.
    - Newest wins: after `graph.guest.begin(.joinClub(code: "ABC"))`, `pendingIntent == .joinClub(code: "ABC")`.
    - Signed in (`identity.isAuthenticated = true`): `GuestGate.allows(...) == true` and `shown.count == 1`.
  - `guestToolRoutesBecomeSignUp`:
    - `#expect(RoutePolicy.toolDestination(for: .addToClub(frieren), isGuest: true) == .signUp(GuestSignUpRequest(intent: .openTitle(frieren), mode: .signUp)))`. Give `RouteDestination` a test-only `Equatable` conformance on the `.signUp` case, or compare with `if case`.
    - With `isGuest: false`, the result is `.addToClub(mediaId: 154587, mediaType: "ANIME")`.
- [ ] **Step 2: Run** `-only-testing:KuroTests/GuestModeTests`. Expected: build failure `type 'GuestGate' has no member 'allows'` / `cannot find 'GuestGate' in scope`.
- [ ] **Step 3: Implement** the interfaces above. Keep `RoutingTests` green: the existing `destination(for:)` stays exactly as it is.
- [ ] **Step 4: Run** `-only-testing:KuroTests/GuestModeTests -only-testing:KuroTests/RoutingTests -only-testing:KuroTests/NavdetailTests -only-testing:KuroTests/DUpreviewTests`. Expected: all passed. Then run `scripts/quality-gates/check_navigation.sh` and `check_branded_states.sh`: expected 0 offenders.
- [ ] **Step 5: Commit.** `git add Kuro/Views/Guest/GuestGate.swift Kuro/Views/Guest/GuestSignUpSheet.swift Kuro/Views/Routing/KuroRoutes.swift Kuro/Views/AuthView.swift Kuro/Views/TastePicksView.swift Kuro/Views/LibraryViewActions.swift Kuro/Views/KuroRefinedCard.swift Kuro/Views/SharedCards/GridAnimeCard.swift Kuro/Views/EditorialDiscoverFrames.swift Kuro/Views/ClubDetailTabComponents.swift Kuro/Views/DetailPages/Prototype/AnimeDetailSections.swift Kuro/Views/DetailPages/Prototype/MangaDetailSections.swift Kuro/Views/DetailPages/AnimeDetailView.swift Kuro/Views/DetailPages/MangaDetailView.swift Kuro/Views/Discover/Preview/DiscoverFeedbackController.swift Kuro/Views/Discover/Preview/DiscoverTitleMenu.swift KuroTests/GuestModeTests.swift`, message `W5: sign-up tool sheet and gated save/track/club/taste actions`.

### Task 6: Guest root, pager, invitation pages, header and the UI test

**Files:** create `Kuro/Views/Guest/GuestInvitationPage.swift`, `KuroUITests/GuestBrowsingUITests.swift`; modify `Kuro/ContentView.swift`, `Kuro/Views/EditorialDiscoverFrames.swift`, the Search idle state's Browse row (`EditorialSearchView.swift`), `KuroTests/GuestModeTests.swift`.

**Interfaces:**
- **Consumes:** `GuestPager`, `GuestSession`, `GuestGate`, `KuroNavigationCoordinator.collapseThenOpen(_:)`, and the launch arguments `--kuro-fixture-host` (`FixtureHost.launchArgument`) and `--ff-on=guest_browsing_v1`.
- **Produces:**
  - `KuroMainView.Section.pagerOrder(tasteDeck: Bool, seriesHome: Bool, guest: Bool) -> [Section]`: `guest` returns `GuestPager.order`. All three call sites pass `guest.isGuest`: `ContentView` `swipeOrder`, the header neighbour order, and `DiscoverBrowseEntry.isOffered(flags:guest:)`.
  - `struct GuestInvitationPage: View { let section: KuroMainView.Section }`: a branded empty state (`KuroEmptyView`) with `GuestCopy` text, and buttons "Create account" (`routes.presentSignUp(.init(intent: nil, mode: .signUp))`) and "Sign in" (`mode: .signIn`). Accessibility identifier `guest.invitation.<section.rawValue>`.
  - In the pager's page `switch`, the `.taste`, `.home`, `.collection` and `.clubs` cases render `GuestInvitationPage` while `guest.isGuest`.
  - Header profile menu while guest: a single "Sign in" / "Anmelden" button → `GuestGate.allows(nil, …, mode: .signIn)`. "Sign out" is hidden.
  - `onAppear`: `showOnboarding = !guest.isGuest && !OnboardingView.hasCompletedOnboarding(for: identity.currentUserId)`. A guest never sees onboarding; it runs in the new signed-in tree.
  - Deep links while guest, in `handleDeepLink` (the `ShellLinkPolicy` actions):
    - `.joinClub(code)`: switch to the Clubs invitation, then `GuestGate.allows(.joinClub(code: code), …)`.
    - `.openJourney(.club(id))` (`kuro://club/<id>`): switch to the Clubs invitation, then `GuestGate.allows(nil, …)`.
    - `.openConciergeSheet` / `.openConciergePage` (`kuro://concierge`): `GuestGate.allows(nil, …)`. Concierge would call the edge functions with the anon JWT.
    - `kuro://anime|manga/<id>` and `kuro://discover` open normally.

    No public page offers `routes.openClub` to a guest: "Between us" and club presence are hidden (Task 5).
  - Signed-in tree: `.onChange(of: guest.reopenAfterSignUp?.key, initial: true) { if let key = guest.takeReopenTitle(for: accountSession.current) { navigation?.collapseThenOpen(.media(MediaRoute(key))) } }`. This is observation, not `onAppear`: the replay sets the key seconds after the tree appears. Read the coordinator from `\.kuroNavigation` and the account through `LibraryActions.accountSession`.
  - Landing after sign-up: the app's normal start page (Discover, then Home once the series flags hydrate). The replay banner confirms the action.
  - Accessibility identifiers:
    - `header.search` on the existing search button (`ContentView.swift`, near line 1205);
    - `search.browseEntry` on Search's idle "Browse the catalogue" row;
    - `discover.page` on the Discover page root, in every load state (loading, offline and failed included);
    - `auth.wall` on `AuthView`'s root.

- [ ] **Step 1: Write the failing UI test** `KuroUITests/GuestBrowsingUITests.swift`:

```swift
final class GuestBrowsingUITests: XCTestCase {
    func testSignedOutLaunchShowsDiscoverNotAuthWall() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--kuro-fixture-host", "--ff-on=guest_browsing_v1",
                                "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]   // no --kuro-skip-auth
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["discover.page"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.descendants(matching: .any)["auth.wall"].exists)
        XCTAssertFalse(app.buttons["Get started"].exists)          // AuthView's welcome control
        app.buttons["header.search"].tap()
        XCTAssertTrue(app.buttons["search.browseEntry"].waitForExistence(timeout: 10))
        app.buttons["journey.close"].firstMatch.tap()
        for (swipes, id) in [(1, "home"), (2, "taste")] { /* swipeRight from Discover */ }
        // then swipeLeft to collection and clubs; each: XCTAssertTrue(app.descendants(matching: .any)["guest.invitation.<id>"].waitForExistence(timeout: 5))
    }
}
```

  Spell out the four page assertions concretely: Home after 1 page back, Taste after 2, then back to Discover, Collection after 1 page forward, and Clubs after 2. Turn pages with an edge drag, so a card's swipe-exclusion zone can never swallow it (`isSwipeExcluded` always allows the edge margin): back is `app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))`, and forward is the mirror from `dx: 0.98` to `0.1`. Assert each page with `app.descendants(matching: .any)["guest.invitation.<rawValue>"].waitForExistence(timeout: 5)`. The offline fixture host denies every request, so the test asserts only identifiers that exist in Discover's offline/failed state.

  Add the unit test `guestPagerOrderReachesBrowseFromDiscover`: `#expect(KuroMainView.Section.pagerOrder(tasteDeck: true, seriesHome: false, guest: true) == GuestPager.order)` and `#expect(DiscoverBrowseEntry.isOffered(flags: flags, guest: true))`.
- [ ] **Step 2: Run** `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,id=7FC4B58A-430C-457D-A017-6B0095723F3F' test -only-testing:KuroUITests/GuestBrowsingUITests`. Expected FAIL: `XCTAssertTrue failed` on `discover.page` (the auth wall shows). Boot the simulator first (`xcrun simctl bootstatus 7FC4B58A-430C-457D-A017-6B0095723F3F -b`).
- [ ] **Step 3: Implement** the interfaces above.
- [ ] **Step 4: Run** the UI test: expected `Test Suite 'GuestBrowsingUITests' passed`. Then run `-only-testing:KuroUITests/NavigationContractUITests`: still passing, because `--kuro-skip-auth` keeps the signed-in tree. Then run `-only-testing:KuroTests/GuestModeTests`: all passed.
- [ ] **Step 5: Commit.** `git add Kuro/Views/Guest/GuestInvitationPage.swift KuroUITests/GuestBrowsingUITests.swift Kuro/ContentView.swift Kuro/Views/EditorialDiscoverFrames.swift Kuro/Views/EditorialSearchView.swift KuroTests/GuestModeTests.swift`, message `W5: guest pager with invitation pages; UI test`.

### Task 7: Load profile `guest-browse` (via F3)

**Files:** create `scripts/load/profiles/guest-browse.js`, `scripts/load/profiles/guest-browse.test.js`; modify `scripts/load/workloads/tracker-gaps-combined.js` (one line).

**Interfaces:**
- **Consumes:** F3's profile contract exactly as `00-foundation.md` defines it: F3.1 (registry, `ratePerSecond`, separate absolute-rate lane: the predeclared mix keeps its 20 rps, the profile adds its own rate and is reported separately; a `weight` field makes `loadProfiles` throw), F3.1b (`anonymous: true` sends the anon key only, `method: "GET"`, per-request `budgetClass` with declared `budgetClasses`, `core.requestFor`), F3.1c (`emptyExamples`, `validate(…, ctx)` with `ctx.mode`, `--qualify`, the `tracker-gaps-combined` workload). `backend_workload.js` is not edited.
- **Produces** (`scripts/load/profiles/guest-browse.js`):
  ```js
  module.exports = {
    name: "guest-browse",
    budgetClass: "browse",
    budgetClasses: ["discover", "search", "browse", "detail"],   // samples summarised as "guest-browse:<class>" at LIMITS[class]
    ratePerSecond: 5,                                            // absolute: 5 anonymous rps on top of the unchanged 20 rps base
                                                                 // (≈ 20 % of 25 rps total, the share the spec intended)
    writes: false,                                               // anonymous: no actor data, so no seed / cleanupCheck
    emptyExamples: [[], {}, null],                               // qualify must reject each (F3.1c)
    request(actor, fixture, seq, random, core) {
      // kind drawn with `random` in proportion to the predeclared WEIGHTS of the four guest kinds (discover 5, search 15, browse 20, detail 20)
      // discover | search | browse → { ...core.requestFor(kind, actor, fixture, seq, random), anonymous: true, budgetClass: kind }
      // detail → even seq: { method: "GET", path: "/rest/v1/" + medium + "?id=eq." + id + "&select=id,title_romaji,title_english,cover_image_large,description" }
      //          odd seq:  { path: "/rest/v1/rpc/get_media_ladder", body: { p_media_type: medium.toUpperCase(), p_media_id: id } }
      //          both with anonymous: true, budgetClass: "detail"
    },
    validate(data, actor, request, ctx) {
      // by request.budgetClass (an unknown or missing class → false, so F3.1c's stub request rejects every empty example):
      // search/browse → array of rows with integer id (browse non-empty); discover → object with `anime` and `manga`
      // objects; detail GET → array of ≤ 1 row with integer id; ladder → non-null object or array.
      // ctx.mode "qualify": search and detail GET must be non-empty too (no empty-array passes; the fixture's ids are real
      // catalogue ids), and discover's `anime` / `manga` objects must each hold ≥ 1 section.
    },
  };
  ```
  Anonymous `discover`, `search` and `browse` reuse today's bodies; all their RPCs are on the allowlist.
- Combined workload line: `"guest-browse": 5` (an absolute rps, not a share).
- Qualification arithmetic (F3.1c preflight; anonymous samples have no library-size subgroup): 5 rps × 600 s = 3,000 arrivals; the rarest class, `discover`, gets 5/60 of the draws = 250 expected completions ≥ 100 (`search` 750, `browse` 1,000, `detail` 1,000).

- [ ] **Step 1: Write the failing test** `scripts/load/profiles/guest-browse.test.js`: `test("guest-browse: 5 rps anonymous in its own lane, allowlisted paths only, no user token", …)`. Load it with `W.loadProfiles()["guest-browse"]`; draw 1,000 requests with a seeded LCG `random`, passing `core = { requestFor: W.requestFor, validateResponse: W.validateResponse, ORIGIN: W.ORIGIN, now: () => new Date(0) }`. Assert:
  - the profile has `ratePerSecond === 5` and no `weight` key; `W.loadWorkload("tracker-gaps-combined").profiles["guest-browse"] === 5`; the base mix is unchanged (`JSON.stringify(W.WEIGHTS)` equals its value before the profile was loaded and `!("guest-browse" in W.WEIGHTS)`: the profile runs in its own lane);
  - every request has `anonymous === true` and `budgetClass` in `["discover", "search", "browse", "detail"]`;
  - every request path is in `["/rest/v1/rpc/discover_bundle", "/rest/v1/rpc/search_anime_page", "/rest/v1/rpc/search_manga_page", "/rest/v1/rpc/browse_anime_page", "/rest/v1/rpc/browse_manga_page", "/rest/v1/rpc/get_media_ladder"]` or starts with `"/rest/v1/anime?"` / `"/rest/v1/manga?"` (GET, no body);
  - `!JSON.stringify(requests).includes("series_detail_bundle_v1")`;
  - with `const L = W.selectProfiles({ names: ["guest-browse"] }).limits`: `L["guest-browse:detail"] === 1200`, `L["guest-browse:discover"] === 1500`, `L["guest-browse:search"] === 750`, `L["guest-browse:browse"] === 750`, and `!("guest-browse" in L)`;
  - the share of `detail` draws is within ±0.05 of 20/60, and of `discover` within ±0.03 of 5/60;
  - `validate([], {}, searchRequest, { mode: "qualify" })` is false and `validate([], {}, searchRequest, { mode: "wiring" })` is true; every `emptyExamples` entry is rejected in qualify mode for each of the four classes.
- [ ] **Step 2: Run** `node --test scripts/load/profiles/guest-browse.test.js`. Expected FAIL: `TypeError: Cannot read properties of undefined (reading 'budgetClass')` (profile absent).
- [ ] **Step 3: Implement** the profile file (no `require` of `backend_workload.js`; use `core`) and add its line to `tracker-gaps-combined.js`.
- [ ] **Step 4: Run** `bash scripts/quality-gates/test_load_profiles.sh`: expected `# pass` for all tests, `# fail 0` (incl. `combined workload names every profile with an explicit rate`). Then run the F1 gate `scripts/quality-gates/check_bdd_traceability.sh`: `@load:guest-browse` resolves.
- [ ] **Step 5: SQL plan note.** Guest mode adds no SQL statement. Every allowlisted reader's anonymous path is its signed-in plan minus the `v_uid`-guarded personal predicates. Search/Browse plans stay covered by `102_load_hotpaths` (2,000+ title fixture, `Bitmap Index Scan` on `_load_title_`), and Discover by `87`/`103`. Record this in the evidence note. Nothing new to EXPLAIN.
- [ ] **Step 6: Commit.** `git add scripts/load/profiles/guest-browse.js scripts/load/profiles/guest-browse.test.js scripts/load/workloads/tracker-gaps-combined.js`, message `W5: guest-browse load profile (5 rps anonymous, own lane)`.

### Task 8: Docs, evidence and full verification

**Files:** create `docs/tracker-gaps-2026-11/W5-guest/EVIDENCE.md`, `docs/tracker-gaps-2026-11/W5-guest/live-anon-grants.sql`, `docs/tracker-gaps-2026-11/acceptance/W5.json`; modify `CURRENT_APP_STATE.md`, `CURRENT_APP_STATE_PLAIN.md`, `IMPLEMENTATION_PLAN_Variation1.md`, `docs/modules/README.md`, `~/.claude/projects/-Users-max-Kuro-Anime-App/memory/MEMORY.md`.

- [ ] **Step 1: Live audit query (read-only; run only with owner approval).** In `live-anon-grants.sql`, `select p.oid::regprocedure::text as fn` from `pg_proc p join pg_namespace n on n.oid=p.pronamespace` where `n.nspname='public'`, `not exists (select 1 from pg_depend d where d.objid=p.oid and d.deptype='e')`, and `has_function_privilege('anon', p.oid, 'EXECUTE')`, ordered by 1. Run it before applying (expected: many rows, saved as `anon-grants-before.tsv`) and after applying (expected: exactly the 19 allowlist rows, or 17 while W4's migration is not applied; re-run after W4 is applied, `anon-grants-after.tsv`). This covers functions that exist only live, since the fixture replay is INCOMPLETE. The same file also selects `has_table_privilege('anon', t, 'select')` for every guest catalogue table listed above plus `anime_user_lists` / `manga_user_lists` (expected: catalogue `true`; for the user lists record the grant as found, and the rows anon can see must be 0 through RLS, as section G asserts in the fixture). This records, before and after, that anonymous catalogue SELECT existed before W5 and is unchanged by it (verified 2026-11-09 for `anime` and `manga`).
- [ ] **Step 2: Evidence note** `EVIDENCE.md` contains:
  - the red/green outputs of Tasks 1–7;
  - the 106 extra-function list from the red run;
  - the allowlist table;
  - owner decisions D-A, D-W5-RL (current production exposure), D-W5-T, D-W5-DP and their status;
  - the release checklist: W5 merged last; D-A resolved (legal advice, sourcing change, or written risk acceptance; no AniList "authorization on request" exists); capacity qualification PASS including `guest-browse` in an owner-approved `--qualify` run; live audit after = 19 rows (with W4 applied); `guest_browsing_v1` raised only after all of these;
  - the rollback: `update feature_flags set enabled=false, rollout_percentage=0 where flag_name='guest_browsing_v1'`. Clients then fall back to the auth wall on their next flag read. This stops the app's guest UI and its traffic only; anonymous catalogue reads with the shipped anon key stay possible (D-W5-RL). The grant sweep is not rolled back: it only removes access nobody needs.
  - the item-7 statement: every red step in Tasks 1–7 showed missing behaviour (missing migration, types, guards, profile); no expectation was written wrong on purpose and no non-vacuity mutation was needed.
- [ ] **Step 3: Rule 1.**
  - `CURRENT_APP_STATE.md`: navigation (guest pager), Identity (`GuestSession`, `RootPresentation`), feature flags (`guest_browsing_v1` 0 %), Supabase (pending `20261118110000`, test 114, anon allowlist), file counts (+6 app Swift: `PendingGuestIntent`, `GuestCopy`, `GuestSession`, `GuestGate`, `GuestSignUpSheet`, `GuestInvitationPage`; +1 KuroTests; +1 KuroUITests; exact inventory sentences from `check_docs_current_state.py`, recomputed at merge time, then the script → `PASS`), and a Change Log line.
  - `CURRENT_APP_STATE_PLAIN.md`: the same in plain English.
  - `IMPLEMENTATION_PLAN_Variation1.md`: W5 status "built, not released (D-A, capacity, migration approval)".
  - `docs/modules/README.md`: the Identity row gains `GuestSession`.
- [ ] **Step 4: Rule 2.** In MEMORY.md, record:
  - the new files;
  - gotchas: `revoke … from public` does not remove Supabase's direct anon grant; the default privileges are now closed, so a future guest RPC needs an explicit `grant … to anon` plus a 106 update; `GuestSession` is not account-scoped, and its intent is take-and-clear in `bootstrapAfterAuth`, dispatched inside a credential lease (LibraryStore writes take none themselves); the release switch is `guest_browsing_v1` and cannot revoke anonymous catalogue reads (anon SELECT on `anime`/`manga` is true live); the UI test must not pass `--kuro-skip-auth`; XCUITest method names need the `test` prefix (feature tag changed accordingly);
  - the updated counts.
- [ ] **Step 5: Full verification.** Each with its expected result:
  - `SKIP_IOS_BUILD=1 SKIP_IOS_TEST=1 scripts/quality-gates/run_all.sh` → green (WARN only for registered non-blocking gates).
  - `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,id=7FC4B58A-430C-457D-A017-6B0095723F3F' test -only-testing:KuroTests` → passed; then `-only-testing:KuroUITests/GuestBrowsingUITests -only-testing:KuroUITests/NavigationContractUITests` → passed.
  - `scripts/quality-gates/check_architecture.sh`, `check_navigation.sh`, `check_branded_states.sh` → 0 offenders.
  - `scripts/quality-gates/check_bdd_traceability.sh` → all 8 W5 scenarios (7 + the 2026-11-09 flag-off scenario) resolve to exactly one test; exit 0.
  - Acceptance record `docs/tracker-gaps-2026-11/acceptance/W5.json` (brief item 6, F1 format): tested commit SHA (`git rev-parse HEAD`); per scenario `pass` / `fail` / `blocked` / `insufficient`; the test command; the context (simulator id for `@swift`/`@ui`; `local DB` for `@sql:rls/114_guest_anon_allowlist.sql`, which counts only if the DB test ran and passed, not file existence; load run id for `@load:guest-browse`); unresolved gates (D-A, migration approval, live audit, capacity). `@load:guest-browse` stays `blocked` until an owner-approved `--qualify` run id passes with ≥ 100 completions per class (fewer → `insufficient`). Then `scripts/quality-gates/check_bdd_traceability.sh --accepted W5` → expected to fail while any scenario is not `pass`; record the output. W5 is "resolved", not "accepted", until it passes. Write it in F1.3's schema: start from `python3 scripts/quality-gates/check_bdd_traceability.py --record-template W5`; workstream `W5` (the feature basename up to its first `-`, spec §4); `runs[]` with the exact command, `context` (`simulator` + UUID for `@swift`/`@ui`, `local-db` for `@sql`, `load-qualification` with report, `runKey` and cleanup report for `@load`) and a log under `docs/tracker-gaps-2026-11/acceptance/logs/W5-<run id>.txt`; one `scenarios[]` entry per non-gated scenario with its current tag. Commit order (F1.3 rule 2): make the docs/evidence commit first, run the gates on that clean commit, then commit only `docs/tracker-gaps-2026-11/acceptance/W5.json` and `acceptance/logs/` (message `W5: acceptance record`); nothing outside that folder may change after the tested commit.
  - `cd Packages/KuroModules && swift test` → passed (no package change expected).
  - `scripts/db/run_local_db_tests.sh` → exit 4 with `TESTS … 0 failed` (the BLOCKED scopes are unchanged).
  - `bash scripts/quality-gates/test_load_profiles.sh` → pass.
  - Append `W5-guest.feature` to `scripts/quality-gates/bdd_landed.txt` (F1 landed scope).
  - The build warning count does not rise above the 2026-10-31 baseline (60 unique Kuro-side warnings): `xcodebuild … build 2>&1 | grep -c "warning:"` compared with the baseline method in `CURRENT_APP_STATE.md`.
- [ ] **Step 6: Commit.** `git add docs/tracker-gaps-2026-11/W5-guest/EVIDENCE.md docs/tracker-gaps-2026-11/W5-guest/live-anon-grants.sql CURRENT_APP_STATE.md CURRENT_APP_STATE_PLAIN.md IMPLEMENTATION_PLAN_Variation1.md docs/modules/README.md scripts/quality-gates/bdd_landed.txt`, message `W5: docs, evidence and verification`. MEMORY.md lives outside the repo and is not staged.
