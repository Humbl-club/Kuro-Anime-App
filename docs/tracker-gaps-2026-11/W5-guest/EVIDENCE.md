# W5 guest browsing: evidence (built dark, not released)

Status: implemented and locally verified. Not applied, not deployed, not device-accepted. `guest_browsing_v1`
is 0 % (the migration inserts it disabled); while it is off a signed-out launch shows today's auth wall and the
only extra request is the one signed-out `feature_flags` read that decides the switch.

Source: `docs/superpowers/plans/2026-11-09-tracker-gaps/05-guest.md`, feature `W5-guest.feature`.
Rulings applied (2026-11-18): AniList is stopped (D-A resolved: guests see Kuro-held data only); the per-IP
anonymous rate limit is infrastructure in front of the Data API and is NOT built; there is no anonymous write
path in the app.

## What changed

- Prepared migration `supabase/prepared-migrations/20261118110000_guest_anon_allowlist_v1.sql`, registered in
  `supabase/tests/pending_migrations.txt`. DB test `supabase/tests/rls/114_guest_anon_allowlist.sql`.
- App: `GuestSession` (`Kuro/Identity/`), `PendingGuestIntent`/`RootPresentation`/`GuestPager`/`GuestReadAllowlist`,
  `GuestCopy`, `GuestGate`, `GuestSignUpSheet`, `GuestInvitationPage`; root switch in `KuroApp.swift`; guest pager,
  header "Sign in", deep-link gates and re-open after sign-up in `ContentView.swift`; signed-out guards in the
  Discovery, Taste, Social, Clubs, Catalog, outbound-link and interaction-telemetry owners; gated Plan / heart /
  Not interested / Seen it call sites; `AppRoute.signUp` and `RoutePolicy.toolDestination(for:isGuest:)`.
- Load profile `guest-browse` (5 rps, anonymous, own lane) and its line in `tracker-gaps-combined.js`.

## The allowlist (23 signatures)

19 guest page reads and 4 signed-out infrastructure functions. The sweep removes EXECUTE from PUBLIC and `anon` on
every other non-extension `public` function, re-grants other roles what they had (snapshot and restore), drops
Supabase's per-schema anon default, and asserts both at the end (the migration aborts rather than stay open).

| # | Signature | Why anon needs it |
|---|---|---|
| 1 | `discover_bundle(integer,integer)` | Discover |
| 2 | `discover_section_page_v1(text,text,text,text,text,text,integer,integer)` | Discover See all |
| 3 | `discover_mood_v1(text,text,integer,integer)` | Mood pages |
| 4 | `media_franchise_ids_v1(integer[],integer[])` | Discover dedupe |
| 5 | `recommend_ids_similar_to_seeds(text,integer[],integer,boolean)` | More like this (called by 6 as invoker) |
| 6 | `media_similar_v1(text,integer,integer)` | More like this |
| 7-8 | `browse_anime_page(...12)`, `browse_manga_page(...12)` | Browse |
| 9-10 | `search_anime_page(...12)`, `search_manga_page(...9)` | Search |
| 11 | `get_media_ladder(text,integer)` | Seasons, season pages |
| 12 | `get_manga_chapter_status(integer)` | Manga title |
| 13 | `media_release_schedule_v1(text,integer,integer)` | Title next release |
| 14 | `media_themes_v1(integer)` | Songs |
| 15 | `anime_cast_v1(integer,text,integer)` | Cast rail |
| 16 | `character_voice_actors_v1(integer,text)` | Character page |
| 17 | `staff_voice_roles_v1(integer,integer)` | Staff page |
| 18-19 | `search_anime_page_v2(...12)`, `search_manga_page_v2(...9)` (W4, prepared 20261118100000) | Search page 1 with the adult notice |
| 20 | `check_concierge_rate_limit(text,text,integer,integer,integer)` | contact-submit runs its limiter on the ANON client; Edge anonymous parse. Writes a rate-limit counter row |
| 21 | `get_concierge_config()` | concierge-parse anonymous public parse |
| 22 | `search_titles(text,text,integer)` | concierge-parse anonymous public parse (SECURITY INVOKER) |
| 23 | `normalize_title(text)` | pure helper that `search_titles` calls as the invoker |

Rows 20-23 are a deviation from the plan's 19: they are the signed-out functions the live Edge Functions use with
the anon key (checked against `supabase/functions/**`), which the plan's sweep would have closed. Row 23 was
found by the test, not by reading: `search_titles` is SECURITY INVOKER and calls `normalize_title`, so anon got
`42501` once the sweep ran. 114 section A2 now checks every INVOKER allowlisted function for callees outside
the list.

Already service-role only before this file (`20261108120159_review_security_v1.sql`): `check_email_exists`,
`rate_limit_hit`. Not on the list and now closed to anon: `catalogue_search_blob_v1`, `catalogue_anime_visible`,
`catalogue_manga_visible`, `_is_blessed_canon`, `curated_rail_cards`, `is_flag_enabled`, `collection_*`, every
club, list, import, taste, telemetry and queue writer.

## Red / green (this lane)

DB (disposable fixture, `LC_ALL=en_US.UTF-8 KURO_DB_PORT=54370`):

- Red 1, test without the migration: `FAIL 114_guest_anon_allowlist.sql after 1 assertions ... W5: anon can
  execute nothing outside the allowlist: _taste_*, account_deletion_storage_guard(), acquire_import_lock(...),
  add_club_rail_item(...), apply_import_chunk_v1(...), apply_progress_mutations_v1(jsonb), ... fetch_daily_feature(),
  ... save_user_streaming_services(...), series_detail_bundle_v1(...), ... upsert_title_comment(...)`
  (about 110 functions; also `catalogue_search_blob_v1`, `count_friends_tracking`, `create_club`, `delete_user_concierge_data`,
  `enqueue_media_relation_refresh`, `purge_outbound_link_events`, `record_outbound_link`, `record_taste_deck_signal`).
- Red 2, `--exclude-migration 20261118110000_guest_anon_allowlist_v1.sql`: same failure, exit 1.
- First green attempt found `search_titles` denied for anon (missing `normalize_title`): fixed, then green.
- Green: `--only 114_guest,113_search_hidden,107_library_tags,109_library_up_next` -> 5 files (107, 109 x2, 113,
  114), 206 assertions passed, 0 failed, exit 0. 114 alone: 95 assertions.
- Full harness: exit 4, 66 files, 1,966 assertions passed, 0 failed, the two pre-existing BLOCKED scopes (40 and 50).
- The first full run after the migration failed 6 existing files whose anon assertions expected the function
  body's own `UNAUTHENTICATED` (20, 40, 50, 62, 80) or an anon grant on an internal helper (125): the sweep makes
  anon fail earlier, at the grant (42501). They now accept either denial (125 asserts `authenticated`, not anon).

Swift (`GuestModeTests`, serial, own simulator): see the report for exact counts. Pinned behaviours: flag off sends
only `feature_flags`; replay once (second bootstrap and a direct second replay both write once); cancelled sheet
discards; tracked title says "already in your list" and never downgrades; replay after a pre-dispatch account switch
sends nothing as B (real list transport, bearer checked); signed-out flag read returns within its wait and applies
a late answer; guests request only allowlisted resources with the anon bearer and no personal RPC; no account keys
written. Known limit: the lease mutation (replay without `withCredentialLease`) is not caught by the account-switch
test, because `LibraryStore` itself refuses a write once another account is bound; the lease remains the binding
for the SDK credential and is covered by the positive bearer test and `CredentialLeaseTests`.

UI: `GuestBrowsingUITests/testSignedOutLaunchShowsDiscoverNotAuthWall` passes (offline fixture host, no
`--kuro-skip-auth`). `NavigationContractUITests` (11 tests) pass after one identifier fix (below).

## Owner decisions that remain

- D-W5-RL: per-IP limit on anonymous reads is infrastructure (custom domain behind a CDN/WAF, or an Edge Function
  proxy). It is a current production exposure independent of W5 (anon SELECT on `anime`/`manga` is live today) and
  is not built here. The release switch cannot stop anyone calling `/rest/v1/*` with the shipped anon key.
- Keep `check_concierge_rate_limit` anonymous? It is the one anonymous write left (a counter row); the contact form
  and the Edge anonymous parse need it. Removing it needs those flows to move to a service-role limiter first.
- D-W5-T: guests send no telemetry (default built). Conversion measurement needs a privacy-text update first.
- D-W5-DP: the global PUBLIC default (`alter default privileges ... revoke execute ... from public`) is not
  changed; a later migration that forgets `revoke ... from public` is caught by 114's exact-set assertion.
- Release: `guest_browsing_v1` stays at 0 % until the full backend qualification passes (including an owner-approved
  `guest-browse` `--qualify` run), the owner approves applying the migration, and the live audit
  (`live-anon-grants.sql`) returns exactly the allowlist.

## Rollback

`update public.feature_flags set enabled = false, rollout_percentage = 0 where flag_name = 'guest_browsing_v1'`.
Clients return to the auth wall on their next flag read. The grant sweep is not rolled back (it removes only access
nobody needs); re-open one function with `grant execute on function <signature> to anon`.
