# Kuro iOS API surface audit (lane: api-surface)

Date: 2026-11-01. Branch `kuro/overnight-2026-11-01`. **Read-only.** No source, git, simulator or remote state was changed. The only write is this file.

Scope: every network call the iOS app makes from `Kuro/` and `Packages/KuroModules/Sources`:
- PostgREST table and view reads/writes, and RPCs
- Edge Function invokes
- Realtime channels
- Auth SDK calls
- direct `URLSession` (images, MyAnimeList)

No Supabase Storage SDK call exists in the app (`grep '\.storage'` finds only `ProgressOutboxError.storage` in SQLite code). Cover URLs are fetched through the image pipeline like any other URL.

Method: grep of every `.rpc(`, `.from(`, `functions.invoke`, `client.channel(`, `client.auth.` and `URLSession`, then a trace of each call to its owner, its view trigger and its lifecycle. The earlier inventory `docs/research/2026-09-26-kuro-plan/evidence/client-call-register.csv` was written before the modular refactor (it references the deleted `SupabaseService`). It was used only as a cross-check; every line reference below is to the current tree.

Evidence key:
- **[code]**: read directly in source at the cited line.
- **[live]**: read in `docs/overnight-2026-11-01/live/*.txt`, a read-only snapshot. Row estimates there are stale (for example, `manga` shows 0 rows), and index scan counters may have been reset.
- **[inferred]**: reasoned from code paths, not observed at runtime.
- **[unverified-live]**: depends on live deployment or flag state that this lane could not read.

---

## 0. Headline findings

1. **P0 [code]: every list write is amplified by its own realtime echo.**
   - `LibraryRealtime.scheduleRefresh` (`Kuro/Library/LibraryRealtime.swift:280-290`) fires for any `postgres_changes` event on `anime_user_lists`/`manga_user_lists` (`:84-95`). It does not filter by kind or origin, so the app's own writes come back as events.
   - After a 350 ms debounce, `refreshAfterEvent` (`:293-301`) runs four reads:
     1. `libraryChangedServerSide`: a full `fetchAll` of both list tables in 1000-row pages (`LibraryActions.swift:141-149`, `SupabaseLibraryBackend.swift:62-68,299-318`)
     2. `home.load()` → `home_bundle_v1`
     3. `collection_feed_page` (90 rows)
     4. `user_airing_next`, which is skipped if it ran in the last 20 s
   - This also happens for **progress-only** "+1 episode" taps. The Library change sinks deliberately skip progress-only changes (`HomeStore.swift:581-586`, `CollectionStore.swift:358-360`, `ReleasesStore.swift:227-229`), and the echo undoes that intent.
   - A non-progress edit also triggers the sinks directly:
     - Home reload after 150 ms
     - a Collection page refresh
     - a Releases `anime` single-row read (`ReminderScheduler.swift:180-187`)
     - one `fetch_club_bundle` per club rail that contains the title (`ClubsStore.swift:678-701`)
   - **One status change therefore costs about 1 write + 8-10 reads [inferred]. One "+1" costs 1 write + 4-5 reads.**
2. **P0 [likely, unverified-live]: a table the app reads probably does not exist live, and the failure flips a feature flag.**
   - `FeatureFlags.refresh` reads `feature_flag_overrides` (`FeatureFlags.swift:126-129`). That table is created only by `supabase/prepared-migrations/20261007120000_feature_flag_overrides.sql`.
   - That migration is **not** one of the four declared-live prepared files, and the table is absent from `live/table-stats.txt`, which does list empty 8 kB tables.
   - The PostgREST error is not a `URLError`, so the generic `catch` at `:144-148` runs. It clears the overrides and calls `removeHomeCohort`, which sets `foundationHydrated = false` (`:233-238`).
   - `seriesHomeNativeV1Enabled` requires `foundationHydrated` (`:57-59`), so the native Home flag turns **off** for the rest of `bootstrapAfterAuth`. It turns back on only after another full Library refresh (`SessionController.swift:813-819`).
   - `ContentView.onChange(of: flags.seriesHomeNativeV1Enabled)` (`ContentView.swift:499-507`) then switches the selected tab to Discover and back to Home, and resets `mountedSections` each time.
   - Cost: one wasted 404 per sign-in, a visible tab flip, and an unnecessary Discover mount (which force-loads `discover_bundle`).
   - **Fix:** deploy the table, or treat `PGRST205` / HTTP 404 as "no overrides" without clearing the cohort.
3. **P1 [code]: Discover loads `discover_bundle` twice, and that RPC writes.**
   - `ContentView.task` warms the bundle (`ContentView.swift:424-429`). `EditorialDiscoverView.refreshSections` then always calls it with `force: true` (`EditorialDiscoverView.swift:452`). The second call joins the first only if the first is still in flight.
   - `discover_bundle` is `VOLATILE` and upserts `discover_rail_impressions` (`supabase/migrations/20260326234000_exclude_ancillary_anime_from_default_surfaces.sql`, function body lines ~637-647). So every call, including the warm-up, records impressions and rotates NEW TO YOU, even when Home is the default tab and the user never opens Discover.
   - It is also wrapped in `withRetry` (`DiscoveryStore.swift:112`), so a timeout re-runs a write.
4. **P1 [code]: each anime detail page sends the same RPC two or three times and has no cache.**
   - `resolveDetailLinks` calls `mediaAvailabilityStatus` (`ProviderAvailabilityStore+DetailLinks.swift:101`). `enqueueAvailabilityRefreshIfStale` then calls `get_media_availability_status` again (`ProviderAvailabilityStore.swift:396`). If that call enqueued a refresh, a third status read follows (`DetailLinks.swift:113-115`).
   - The whole chain reruns whenever the viewer's progress changes (`AnimeDetailView.swift:1421` `.task(id: userEntry?.progress)`). Each run includes an uncached `external_links` select of every column (`CatalogStore.swift:800-818`) and an `episodes` select of every column for a single row (`CatalogStore.swift:916-936`).
5. **P1 [code]: catalog reads select every column.**
   - Affected reads: `anime`/`manga` by id (`CatalogStore.swift:95-101,140-146`); batch hydration of up to 100 ids (`:192-197,248-253`), used for the 14 "similar" titles; the genre fallback (`RecommendationsReader.swift:95-107,117-129`); `mv_anime_trending` (`DiscoveryStore.swift:140`); `episodes`, `chapters`, `external_links`, `feature_flags`, `streaming_services`, `realm_meta` and `user_airing_next`.
   - The `anime` baseline has about 65 columns (`20260807000000_baseline_capture_v1.sql`). `Anime` decodes 52 fields (`Kuro/Catalog/CatalogModels.swift:7`). The extra columns include `description_normalized`, eleven `synopsis_enhanced_*` pipeline fields (including `_last_error`) and fifteen `safety_*` fields (including `safety_model_rationale` and `safety_last_error`).
   - The last two groups are internal moderation and pipeline state. Shipping them to every client is both waste and **information exposure** (cross-lane: security).
6. **P1 [code]: N+1 fallback.** `fetchAnimeByIdsPreservingOrder` and `fetchMangaByIdsPreservingOrder` (`CatalogStore.swift:209-222, 265-278`) send one `fetchAnimeById` request per id the batch query did not return. Ids that are missing or adult-filtered therefore cost one round trip each, on every "similar" load.
7. **Data, not API, limits the owner's intake goals [live + code].**
   - The client already decodes `themes` (songs), release-event-backed `upcoming`/`pending`, catalogue `units`, `editions`, `coverage` and `copy` (`Kuro/Home/HomeContracts.swift:249-401`).
   - The live tables behind them are **empty**: `theme_links`, `release_events`, `catalogue_units`, `detail_copy`, `adaptation_coverage`, `series` and `artwork_materials` are all 8 kB with no data (`live/table-stats.txt`).
   - Anime "next episode" works only through the `anime.next_airing_at` fallback inside `home_events_page_v1` (`20261007040000_series_home_foundation_v1.sql:3389-3395`). Manga and volume "next release" depend on `release_events` and are therefore always empty.
   - `volumes` (8.8 MB: `release_date`, `release_at`, `isbn`, cover) and `chapters.release_at` are **never read by the client**.

---

## 1. Flag gating (frequency depends on it)

Many paths fork on `series_home_native_v1`, defined as `foundationHydrated && series_foundation_v1 && series_home_native_v1` (`FeatureFlags.swift:56-59`). CLAUDE.md does not list either series flag's rollout. **The live value is unknown [unverified-live].** `live/table-stats.txt` estimates `feature_flags` at 2 rows; that estimate is stale and cannot be relied on.

| Surface | Flag ON (native series) | Flag OFF (legacy) |
|---|---|---|
| Default tab | Home (`ContentView.swift:499-502`) | Discover (`mountedSections` default `[.discover]`, `ContentView.swift:158`) |
| Anime/Manga detail | `SeriesAnimeDetailView` / `SeriesMangaDetailView` → 1 × `series_detail_bundle_v1` (+ paged units/editions) | Legacy fan-out of about 10 requests (§3.6) |
| Collection | `collection_series_page_v1` / `collection_series_children_v1` | `collection_feed_page` + friend counts + provider prefetch |
| Library writes | `apply_progress_mutations_v1` / `apply_remove_mutations_v1` fence (when `series_foundation_v1`) | PATCH / DELETE on the list tables |

Other relevant flags and their documented rollout (CLAUDE.md):
- `social_activity_v1`: 100% (friend counts)
- `streaming_availability_v1`: 0% (provider v2, status, enqueue)
- `credits_cast_v1`: 100% (legacy credits)
- `clubs_notifications_v1`: 100%
- `clubs_realtime_v1`: 100%
- `personalized_new_to_you_v1`: 0%
- `discover_realm_rails_v1`: 0%
- `taste_deck_v1`: 100%

---

## 2. Existence check: client references vs migrations

### 2.1 RPCs (70 distinct names)

Every name was grepped for `function public.<name>(` in `supabase/migrations/*.sql` and `supabase/prepared-migrations/**`. **All 70 resolve.** Thirty-two are defined only in the four prepared files declared live (`20261007040000`, `20261007130000`, `20261008100000`, `20261008110000`):
- **`20261007040000`:** `home_*`, `series_*`, `collection_series_*`, `apply_progress_mutations_v1`, `apply_remove_mutations_v1`, `friend_activity_page_v1`, `upsert_title_comment_scoped_v1` and the `*_v1` import functions
- **`20261008110000`:** the `*_v2` import workflow functions (`start_library_import_v2`, `prepare_import_chunk_v2`, `apply_import_chunk_v2`, `finish_library_import_v2`, `cancel_library_import_v2`, `undo_library_import_chunk_v2`, `import_job_status_v2`, `import_jobs_page_v2`, `import_items_page_v2`)

`fetch_club_bundle_loading`, `join_club`, `leave_club`, `toggle_comment_reaction` and `fetch_club_bundle` were last redefined in `20261005*` files under `supabase/migrations/`. Older definitions also exist, so the calls work whether or not those files are live. `club_activity_signals` and `club_membership_signals` appear in `live/table-stats.txt`, which suggests the `20261005*` set is live [live].

### 2.2 Tables and views

| Target | Client site | Live status |
|---|---|---|
| `anime`, `manga`, `episodes`, `chapters`, `external_links`, `anime_characters`, `anime_staff`, `anime_studios`, `manga_characters`, `manga_authors` | CatalogStore | present [live] |
| `anime_user_lists`, `manga_user_lists` | `PostgrestLibraryTransport.swift:24-67` via `SupabaseLibraryBackend` | present |
| `profiles` | `AuthService.swift:107` | present |
| `user_airing_next` | `ReleasesStore.swift:137` | **view** (`20260206164200_security_hardening_rls_and_views.sql`), which is why it is absent from table-stats |
| `mv_anime_trending` | `DiscoveryStore.swift:140` | **materialized view** (`REFRESH MATERIALIZED VIEW public.mv_anime_trending` in `live/outliers.txt`) |
| `streaming_services`, `user_streaming_services`, `realm_meta`, `concierge_events`, `feature_flags` | various | present |
| **`feature_flag_overrides`** | `FeatureFlags.swift:126` | **probably missing live** (see headline 2) |
| `anime` / `manga` (variable `table`) | `ImportsService.swift:674` (`resolveLibraryTitles`), `CollectionStore+ImportedTitles.swift:87` | present |

### 2.3 Edge Functions

Invoked: `concierge-parse` (warm-up plus parse), `concierge-recommend`, `concierge-retrieve-feedback`, `concierge-apply`, `concierge-undo`, `concierge-import-anilist` and `delete-account` (sites in §3.10).

**Not invoked by the client:** `concierge-resolve`, `concierge-retrieve-assist`, `bulk-import-*`, `mirror-images`, `manga-*` and `auth-callback`. These are server-side or cron functions, or browser fallbacks. CLAUDE.md lists `concierge-resolve` and `concierge-retrieve-assist` as client features, but no Swift code calls them [code: grep of every `"concierge-` literal].

---

## 3. Full call inventory

Column guide:
- **Scope**: A = account-scoped. It captures `AccountContext`, uses `withCredentialLease`, and checks `isCurrent` before publishing. P = public.
- **Cache**: "none" means every trigger hits the network.
- **Freq**: what fires it.

### 3.1 Auth and identity

| # | Call | Owner file:line | Trigger | Payload | Cache / retry | Scope | Freq |
|---|---|---|---|---|---|---|---|
| A1 | `auth.session` | `SessionController.swift:270` | launch restore | — | SDK keychain | — | once per launch |
| A2 | `auth.authStateChanges` stream | `SessionController.swift:314` | launch | — | — | — | long-lived |
| A3 | `auth.session` (refresh) | `SessionController.swift:422` | `refreshSessionIfNeeded`, every foreground (`KuroApp.swift:113`) | — | SDK refreshes only if expiring | — | per foreground |
| A4 | `auth.signIn(email,password)` + `auth.session` | `AuthService.swift:63-64` | AuthView sign-in | — | none | — | per tap |
| A5 | `auth.signUp` + `auth.session` | `AuthService.swift:71-73` | AuthView sign-up | — | none | — | per tap |
| A6 | `auth.signInWithIdToken` (Apple) | `AuthService.swift:80` | Apple button | — | none | — | per tap |
| A7 | `auth.update(user: full_name)` | `AuthService.swift:93` | first Apple sign-in | — | best effort | — | once |
| A8 | `profiles` upsert (ignore duplicates) | `AuthService.swift:105-109` | every `bootstrapAfterAuth` / restore (`SessionController.swift:222,280,371,529`) | `{id, adult_opt_in:false}` | none | A | per sign-in or launch |
| A9 | `auth.setSession` + `auth.session` | `SessionController.swift:497-498` | `kuro://auth/callback` | tokens | guard first | — | per link |
| A10 | `auth.resetPasswordForEmail` | `AuthService.swift:182` | reset password | email | — | — | per tap |
| A11 | `auth.signOut()` / `signOut(scope:.local)` | `SessionController.swift:410,520,577,609` | sign-out, deletion, rejected callback | — | — | — | per action |
| A12 | `auth.user()` | `AuthService.swift:124` (`isAppleUser`) | Delete Account flow (`ProfileView.swift:569`) | — | none | — | per delete |
| A13 | RPC `check_email_exists` | `AuthService.swift:165` | AuthView sign-up email field, 500 ms debounce (`AuthView.swift:549-554`) | `p_email` | none | anon | per edited email |
| A14 | fn `delete-account` | `AuthService.swift:146` | Delete Account | `{confirm, apple_authorization_code?}` | none | A | per delete |

Notes:
- **A13 [code + migration]:** granted to `anon` with no rate limit visible in `20260225100000_check_email_exists_rpc.sql:19`. This allows email enumeration. Cross-lane: security.
- **A8** is an extra write on every launch. It is cheap and idempotent.

### 3.2 Session bootstrap: what one sign-in or launch fires

From `SessionController.applySession` and `bootstrapAfterAuth` (`SessionController.swift:633-660, 789-829`):

1. Library refresh: `startLibraryRefresh(for:)` at `:656`. This is a full `fetchAll`: anime pages, then manga pages, sequentially.
2. Home snapshot restore from disk (no network).
3. In parallel: `collection_feed_page` (90 rows) and `user_airing_next` (500-row cap).
4. Realtime: user list channel, club disclosure channel.
5. `feature_flags` select of every column, plus `feature_flag_overrides` (`:813`). The latter probably returns 404 (headline 2).
6. If `series_foundation_v1`: **a second fresh full Library refresh** (`:816`, `fresh: true`, which never joins step 1).
7. If `streaming_availability_v1`: `streaming_services` and `user_streaming_services`.
8. ContentView `.task`: `discover_bundle` warm-up (writes impressions) and `check_club_activity_since` (`ContentView.swift:422-428`).
9. The first visible page's `.task`: `home_bundle_v1` (HomeView) or a forced `discover_bundle` (Discover).

On cold launch with no session, `restoreSession` also calls `flags.refresh(userId:nil)` (`:254`). That is a separate `feature_flags` read.

**Net [inferred]:** about 10-13 requests before the user does anything. Two of them are duplicate full Library reads and one is a duplicate `discover_bundle` write.

### 3.3 Library (tracking)

| # | Call | Owner | Trigger | Projection | Pagination | Scope | Freq |
|---|---|---|---|---|---|---|---|
| L1 | `GET anime_user_lists` / `manga_user_lists` | `SupabaseLibraryBackend.swift:299-318` → `PostgrestLibraryTransport.swift:24` | bootstrap ×2, realtime echo, Discover pull-to-refresh (`EditorialDiscoverView.swift:382`), Collection refresh (`EditorialCollectionView.swift:725,855`), Profile "Sync" (`ProfileView.swift:460`), reconnect on Collection (`ContentView.swift:482`), import publish | explicit columns (`SupabaseLibraryBackend.swift:474-481`), plus fence columns when the fence is on | offset, 1000 per page, max 100 pages, anime then manga **sequential** | A | about 5+ per session [inferred] |
| L2 | `PATCH` list row (notes, rating, verdict; status/progress when fence off) | `PostgrestLibraryTransport.swift:40` | AddToListSheet, QuickVerdict, Collection batch | edited columns only | — | A | per edit |
| L3 | `POST` insert, ignore duplicates | `PostgrestLibraryTransport.swift:52` | save | — | — | A | per save |
| L4 | `DELETE` row | `PostgrestLibraryTransport.swift:67` | remove (fence off) | — | — | A | per remove |
| L5 | RPC `apply_progress_mutations_v1` | `PostgrestLibraryTransport.swift:78`; `HomeStore.swift:661` (outbox drain) | +1 / set position / status (fence on); outbox drain on foreground, reconnect, Home appear | mutation batch | outbox batches | A | per drain |
| L6 | RPC `apply_remove_mutations_v1` | `PostgrestLibraryTransport.swift:87` | remove (fence on) | — | — | A | per remove |
| L7 | Realtime `kuro.user.<id>` on 2 tables | `LibraryRealtime.swift:82-103` | bootstrap | filter `user_id=eq.<id>` | — | A | long-lived; every event → full refresh fan-out (headline 1) |

Drain triggers overlap:
- `home.drain()` runs on foreground from **both** `KuroApp.swift:113` and `ContentView.swift:470`.
- It runs on reconnect from both `KuroApp.swift:105` and `ContentView.swift:477`.
- It runs on Home appear (`HomeView.swift:111`).

The outbox probably serializes these, but two calls race on every foreground [inferred].

### 3.4 Home (native series)

| # | Call | Owner | Trigger | Params / bounds | Cache | Freq |
|---|---|---|---|---|---|---|
| H1 | RPC `home_bundle_v1` | `HomeStore.swift:310` | HomeView `.task` (`HomeView.swift:110`); **every** foreground (`ContentView.swift:466-472`, regardless of the selected tab); reconnect while on Home (`:486`); Library sink (150 ms debounce, `:593-602`); realtime echo (`LibraryActions.swift:146-148`); medium switch with no bundle (`:279`); retry button | `p_window_days 7, p_active_limit 12, p_event_limit 20` | disk snapshot (`HomePersonalSnapshot`) used only as offline fallback; no TTL, so every trigger hits the network | 3-6 per foreground cycle [inferred] |
| H2 | RPC `home_bundle_v1` (cursor) | `HomeStore.swift:456` | "More" button | 12 per page | — | per tap |
| H3 | RPC `home_bundle_v1` × up to 3 per medium | `HomeStore.swift:362-380` | import publication | revision floor, 250/500 ms backoff | — | per import |
| H4 | RPC `home_events_page_v1` | `HomeStore.swift:400` | "More dates" | cursor | — | per tap |
| H5 | RPC `home_pending_page_v1` | `HomeStore.swift:425` | "More announcements" | cursor | — | per tap |
| H6 | RPC `series_detail_bundle_v1` | `HomeStore.swift:97`; callers `SeriesDetailViews.swift:322,543`, `HomeView.swift:1256` | open series detail or seasons sheet; **re-runs on every `privacyEpoch` bump** (`SeriesDetailViews.swift:57-61,383-389`, `HomeView.swift:1252,1265`) | — | **none** (no memory cache) | per open, plus per foreground while a sheet is open |
| H7 | RPC `series_units_page_v1` | `HomeStore.swift:109`; caller `SeriesDetailViews.swift:908` | unit list paging | keyset | — | per page |
| H8 | RPC `series_editions_page_v1` | `HomeStore.swift:119`; caller `SeriesDetailViews.swift:923` | editions | cursor | — | per page |

`privacyEpoch` is `permissionGeneration`, which `invalidateClubContent()` increments on **every** `scenePhase == .active` (`ContentView.swift:466-468`). The intent is to drop club bodies, but it also discards and reloads any open series detail bundle (H6) and seasons sheet on every return from background. **P1.**

### 3.5 Discover and Browse

| # | Call | Owner | Trigger | Bounds | Cache | Freq |
|---|---|---|---|---|---|---|
| D1 | RPC `discover_bundle` (**writes impressions**) | `DiscoveryStore.swift:111-116` | ContentView warm-up (`ContentView.swift:425`, unforced); Discover `.task` / pull-to-refresh with `force:true` (`EditorialDiscoverView.swift:452`); reconnect on Discover with `force:true` (`ContentView.swift:480`) | `p_limit 30` × 14 rails | TimedCache 120 s per user, but the force bypasses it; in-flight join | 2 at launch [inferred] |
| D2 | RPC `fetch_daily_feature` | `DiscoveryStore.swift:251` | `refreshSections` (`EditorialDiscoverView.swift:451`) | 1 row | none | per refresh |
| D3 | RPC `fetch_because_you_rail` | `DiscoveryStore.swift:271` | refresh, if `personalized_new_to_you_v1` (0%) | 12 | none | — |
| D4 | RPC `fetch_personalized_new_to_you` | `TasteStore.swift:175` | refresh fallback (same flag) | 20 | none | — |
| D5 | RPC `fetch_tonight_shelf`, `fetch_realm_hidden_gem` | `DiscoveryStore.swift:291,311` | refresh, if `discover_realm_rails_v1` (0%) | 12 / 1 | none | — |
| D6 | RPC `count_friends_tracking` | `SocialActivityStore.swift:243-268` | Discover refresh (up to 100 items, `EditorialDiscoverView.swift:572-583`); Browse page 0 and each page (`BrowseView.swift:418,447,472,487`); Collection (`EditorialCollectionView.swift:878`) | batches of 100 | dictionary with **no TTL**; a new call cancels the previous call's prefetch task | per refresh or page |
| D7 | RPC `enqueue_media_relation_refresh` ×≤12, **sequential** | `CatalogStore.swift:774-796` | Discover refresh (`EditorialDiscoverView.swift:585-599`); Concierge recommend (`ConciergeView.swift:1073`) | 12 | 12 h cooldown **in memory only**, reset every launch | up to 12 writes per launch |
| D8 | `mv_anime_trending` select of every column | `DiscoveryStore.swift:140` | `fetchTrendingAnime` | range | none | **no caller found in Views** (`grep fetchTrendingAnime` shows only the definition) → dead code [code] |
| D9 | RPC `browse_anime_page` / `browse_manga_page` | `DiscoveryStore.swift:190,232`; callers `BrowseView.swift:495,514` | Browse `.task`, every filter/sort/medium change, sentinel paging | 60 per page (`BrowseView.swift:39`), keyset | none: toggling Anime↔Manga or reverting a filter re-fetches | per filter/page |
| D10 | Images ×≤70 prefetch | `EditorialDiscoverView.swift:603-613` → `ImagePipeline.prefetch` | each refresh | fan-out cap | NSCache + URLCache | per refresh |

### 3.6 Detail pages (legacy path: `series_home_native_v1` OFF)

Per anime detail open (`AnimeDetailView.swift:244-307,851,1165,1421`):

| # | Call | Owner | Projection | Cache |
|---|---|---|---|---|
| X1 | `anime` by id (only when opened from an id route, `MediaDetailSheet.swift:73`) | `CatalogStore.swift:95` | every column | memory, 200 entries + disk fallback |
| X2 | `anime?select=id,anime_tags(rank,tags(...))` | `CatalogStore.swift:341-347` | embed | **none** |
| X3 | RPC `recommend_ids_similar_to_seeds` | `RecommendationsReader.swift:79-82` | ids | **none** |
| X4 | `anime?id=in.(14 ids)` | `CatalogStore.swift:192-197` | **every column**, ×14 rows | detail cache (fills it) |
| X4b | per-id N+1 for unresolved ids | `CatalogStore.swift:209-222` | every column | — |
| X4c | genre fallback when the RPC is empty | `RecommendationsReader.swift:95-107` | **every column**, ordered by favourites | none |
| X5 | RPC `get_media_ladder` | `CatalogStore.swift:719-722` | — | TimedCache 120 s, 80 entries |
| X6 | RPC `enqueue_media_relation_refresh` (if coverage is not strong) | `CatalogStore.swift:752-755` | — | 12 h in-memory cooldown |
| X7 | `anime_studios` + `studios` embed | `CatalogStore.swift:476-481` | 6 columns | memory, 100 entries |
| X8 | `anime_staff` + `staff` embed, **unbounded** | `CatalogStore.swift:445-450` | includes `description` text for every staff member | memory, 100 entries |
| X9 | `anime_characters` + `characters` embed, **unbounded** | `CatalogStore.swift:414-419` | includes `description` text for every character | memory, 100 entries |
| X10 | `episodes` next 10 | `CatalogStore.swift:822-840` (`.task(id: nextEpisodeNumber)`, `AnimeDetailView.swift:851`) | **every column** (includes `description`) | none |
| X11 | `episodes` single row | `CatalogStore.swift:916-936` | **every column**, for `stream_url,stream_site` only | none |
| X12 | `external_links` | `CatalogStore.swift:800-818` | every column | **none** |
| X13 | RPC `get_media_availability_status` ×2-3 (flag 0%) | `ProviderAvailabilityStore.swift:484` via `DetailLinks.swift:101,114` and `ProviderAvailabilityStore.swift:396` | — | none |
| X14 | RPC `batch_provider_availability_for_media_v2` (flag 0%) | `ProviderAvailabilityStore.swift:324` | — | dictionary, no TTL |
| X15 | RPC `enqueue_media_availability_refresh` (flag 0%) | `ProviderAvailabilityStore.swift:415` | — | 10 min in-memory cooldown |
| X16 | RPC `fetch_friend_activity_for_title` / `friend_activity_page_v1` | `SocialActivityStore.swift:160-163`; `FriendsActivitySection.swift:127,455,478` | — | none |
| X17 | `fetch_my_clubs_*` via `ClubActivitySection.swift:71-74` | ClubsStore | — | none |

**Per open: about 11-13 requests [inferred]** (X2-X12 + X16-X17, with flag-gated rows excluded). X10-X12 rerun when progress changes on the page. The manga version is similar, adding `chapters` next 10 (`MangaDetailView.swift:749`) and RPC `get_manga_chapter_status` (`:755`).

Entity sheets have no in-flight join and no row bound. All four use TimedCache 120 s, 50 entries:
- `fetchAnimeByStudio` (`CatalogStore.swift:560-587`)
- `fetchAnimeByStaff` (`:589-621`)
- `fetchMangaByAuthor` (`:623-655`)
- `fetchMediaByCharacter` (`:657-697`, 2 parallel requests)

Live index check [live]: the client's filter columns are all indexed:
- `idx_episodes_anime_id_number_unique`
- `idx_chapters_manga_id_number_unique`
- `idx_external_links_media`
- `idx_anime_characters_anime_id`
- `idx_anime_staff_anime_id`
- `idx_anime_studios_studio_id`
- `idx_manga_authors_*`

There is no missing-index finding for the client. The large scan counters on `anime_staff`, `manga_authors` and `anime_studios` (hundreds of thousands to over a million) come from server rebuild workers (`rebuild_media_similar_titles` and others in `outliers.txt`), not from the app.

### 3.7 Collection

| # | Call | Owner | Trigger | Bounds | Freq |
|---|---|---|---|---|---|
| C1 | RPC `collection_feed_page` | `CollectionStore.swift:331-334` | Collection `.task` and filter change (`EditorialCollectionView.swift:233-258`); Library sink; realtime echo; bootstrap; Profile Sync; reconnect | 90 per page (max 120), keyset | about 3-5 per session plus per edit |
| C2 | RPC `collection_series_page_v1` | `CollectionStore.swift:510-517` | native: `.task`, filter, medium, search (300 ms debounce, `EditorialCollectionView.swift:541-554`), Library sink | 30 groups | per keystroke burst |
| C3 | RPC `collection_series_children_v1` | `CollectionStore.swift:540-541` | "More seasons" | cursor | per tap |
| C4 | `anime`/`manga?select=id,titles,cover,banner&id=in.(≤30)` | `CollectionStore+ImportedTitles.swift:85-90` | imported-titles view | 30 | per page |
| C5 | `count_friends_tracking` (≤80) + `batch_provider_availability_for_media_v2` (flag 0%) | `EditorialCollectionView.swift:858-885` | legacy load and refresh | — | per refresh |

`refreshCollectionPages` (`CollectionStore.swift:445-457`) re-reads page 1 from scratch after any applied change. A user scrolled to page 3 loses their position, and the refresh pulls 90 rows again.

### 3.8 Releases and reminders

| # | Call | Owner | Trigger | Projection | Cache | Freq |
|---|---|---|---|---|---|---|
| R1 | `user_airing_next` (view) | `ReleasesStore.swift:134-145` | bootstrap; realtime echo; Library sink on add; Profile Sync; import publish | **every column**, 7-day window, limit 500 | 20 s throttle + backoff + in-flight join (`:104-122`) | throttled |
| R2 | `anime?select=id,titles,next_episode_number,next_airing_at&id=eq` `.single()` | `ReminderScheduler.swift:180-187` | Library sink: every **non-progress** anime change that is not completed/dropped (`ReleasesStore.swift:227-249`) | 5 columns | none | per status edit |

R1 overlaps with Home's `home_events_page_v1`, which computes the same "next airing" from `anime.next_airing_at`. Both are fetched at bootstrap. The 60 s countdown timer (`ReleasesStore.swift:196-208`) is local only and makes no network calls (good).

### 3.9 Clubs

| # | Call | Owner | Trigger | Cache | Freq |
|---|---|---|---|---|---|
| K1 | RPC `fetch_my_clubs_loading`, **fallback** `fetch_my_clubs_enriched` on *any* error | `ClubsStore.swift:392-413` | ClubsView `.task` (`didInitialLoad` is reset on disappear, `ClubsView.swift:68-86`, so it refetches on **every** tab revisit); pull-to-refresh; `willEnterForeground` while mounted (`:89-95`); ProfileView `.task` (`ProfileView.swift:102`); ClubActivitySection; AddToClubRailSheet (`:180`) | none | high |
| K2 | RPC `check_club_activity_since` | `ClubsStore.swift:735-765` | ContentView `.task` (launch), reconnect on Clubs, ClubsView foreground | — | per launch/foreground |
| K3 | RPC `fetch_club_bundle` | `ClubsStore.swift:505-547` | ClubDetailView load (`ClubDetailView.swift:442`); realtime signal; Library sink (`:678-701`); AddToClubRailSheet with `forceRefresh:true` (`:230`) | TimedCache `bundleTTL` per account + in-flight join | per open/event |
| K4 | RPC `fetch_club_bundle_loading` | `ClubsStore.swift:553-567` | first open, in parallel with K3 (`ClubDetailView.swift:430-437`) | none | per first open |
| K5 | Writes: `create_club`, `join_club`, `leave_club`, `add_club_rail_item`, `cast_club_vote`, `create_club_rail`, `create_club_poll`, `toggle_club_reaction` | `ClubsStore.swift:461,475,490,612,625,637,650,665` | user actions | — | per action |
| K6 | Realtime `kuro.club.<id>` (`club_activity_signals`) + `.membership` | `ClubRealtimeCoordinator.swift:99-140` | ClubDetail open (`clubs_realtime_v1`) | debounced re-read | — |
| K7 | Realtime `kuro.permissions.<uid>.<uuid>` (`club_membership_signals`) | `ClubRealtimeCoordinator.swift:193-196` | bootstrap | — | long-lived |
| K8 | RPC `club_shared_providers` | `ProviderAvailabilityStore.swift:573` | club detail | dictionary | per open |

K1's catch-all fallback doubles traffic offline and on cancellation, and can hide a real error in `fetch_my_clubs_loading`. Legacy content-table realtime streams are off (`ClubRealtimeCoordinator.swift:91`), which is good.

### 3.10 Search, Concierge, Imports, Taste, Telemetry, Providers

| # | Call | Owner | Trigger | Notes |
|---|---|---|---|---|
| S1 | RPC `search_anime_page` / `search_manga_page` | `SearchStore.swift:413,447` | search sheet, 300 ms debounce (`EditorialSearchView.swift:188-196`) | 20 per page; **combined "All" scope runs anime then manga sequentially** (`SearchStore.swift:211-252`, and refresh at ~:290-350); no query cache |
| Q1 | fn `concierge-parse` (warm-up, `?warmup=true`) | `ConciergeStore.swift:61-80` | Concierge open | background priority |
| Q2 | fn `concierge-recommend` | `ConciergeStore.swift:86-133` | Concierge prompt | TimedCache 1 h per user and prompt; `withRetry` on `URLError`, so a timeout can bill Groq narration twice |
| Q3 | fn `concierge-retrieve-feedback` | `ConciergeStore.swift:137-172` | RAG accept/reject | best effort |
| Q4 | fn `concierge-parse` | `ImportsService.swift:246-247` | import text | `withRetry` |
| Q5 | fn `concierge-apply` / `concierge-undo` | `ImportsService.swift:288,449` | import apply/undo | — |
| Q6 | fn `concierge-import-anilist` | `ImportsService.swift:409,479,498`; `ImportsService+WorkflowSources.swift:209` | AniList import | — |
| Q7 | RPC `*_v1` import (`start_library_import_v1`, `import_job_status_v1`, `apply_import_chunk_v1`, `finish_library_import_v1`) | `ImportsService.swift:331-356` | legacy structured import | chunked |
| Q8 | RPC `*_v2` import workflow (9 names) | `ImportsService+WorkflowRPC.swift:59` via `ImportsService+Workflow.swift` | Profile import workflow | `import_jobs_page_v2` loop ≤200×50, `import_items_page_v2` loop ≤2000×50 (bounded) |
| Q9 | `anime`/`manga?select=id,titles&id=in.(≤200)` | `ImportsService.swift:666-678` | import title resolution | chunked 200 |
| Q10 | MyAnimeList OAuth + `GET api.myanimelist.net/v2/users/@me` and `/animelist` / `/mangalist` | `MALNativeAccountConnector.swift:19-20,68-80,196`; `Packages/KuroModules/Sources/KuroLibrary/MALAccountList.swift:22` | MAL account import; `refreshMALIdentity` on **every Profile open** (`ProfileView.swift:100`, `ProfileImportCoordinator.swift:63-68`, gated by `series_foundation_v1`) | ephemeral session, redirect refusal |
| T1 | RPC `fetch_taste_deck_batch` | `TasteStore.swift:132` | TasteDeckView `.task` (`TasteDeckView.swift:583`) | — |
| T2 | RPC `fetch_my_taste_profile` + `realm_meta` select of every column | `TasteStore.swift:152,195`; caller `TasteDeckView.swift:1075-1080` | taste profile sheet | `realm_meta` is static reference data with **no cache**; live seq-scan count 8231 [live; attribution uncertain] |
| T3 | RPC `record_taste_deck_signal` | `TasteStore.swift:227` | deck swipe (bounded outbox) | a "love" swipe triggers a full Library refresh |
| E1 | `concierge_events` insert, one row per event | `ConciergeAnalytics.swift:107-120` | analytics | **offline flush fans out N concurrent single-row inserts** (`:89-98`); no batching |
| E2 | RPC `record_outbound_link` | `OutboundLinkTelemetry.swift:33-60` | WATCH/READ tap | fire-and-forget |
| P1 | RPC `batch_providers_for_media` | `ProviderAvailabilityStore.swift:370` | `prefetchProviders` | no TTL |
| P2 | RPC `get_provider_availability_refresh_queue_summary` | `ProviderAvailabilityStore.swift:449` | Profile freshness card (flag 0%) | — |
| P3 | `streaming_services` (every column), `user_streaming_services`, RPC `save_user_streaming_services` | `ProviderAvailabilityStore.swift:493,516,540` | bootstrap (flag 0%), Profile open (`ProfileView.swift:103-105,628-632`) | registry refetched on every Profile open |

### 3.11 Direct URLSession

| # | Call | Owner | Notes |
|---|---|---|---|
| I1 | Image GET | `ImagePipeline.swift:108` (`URLSession.shared`, `.returnCacheDataElseLoad`, 20 s timeout) | Memory cache is `NSCache` keyed **by URL only**, ignoring `maxPixelSize` (`:44,54,104,126`). Prefetches use `maxPixelSize: nil` (`EditorialDiscoverView.swift:612`, `EditorialCollectionView.swift:868`, `BrowseView.swift:415`), so full-resolution decodes go into the 80 MB cache, and a thumbnail decode can later be served to a 1400 px hero (or the reverse). `URLCache` is 64 MB memory / 256 MB disk (`KuroApp.swift:48-50`). |
| I2 | MAL API | Q10 | — |

---

## 4. Waste catalogue (by type)

### 4.1 Over-fetching

- **Every-column selects:**
  - `anime`/`manga` detail and batch (`CatalogStore.swift:95,140,192,248`)
  - genre fallback (`RecommendationsReader.swift:95,117`)
  - `episodes` (`CatalogStore.swift:825,847,920`) and `chapters` (`:864,886`)
  - `external_links` (`:804`), `feature_flags` (`FeatureFlags.swift:110`), `streaming_services` (`ProviderAvailabilityStore.swift:493`), `realm_meta` (`TasteStore.swift:195`), `user_airing_next` (`ReleasesStore.swift:137`), `mv_anime_trending` (dead code)
- Credits embeds pull a long `description` for every character and staff member, with no row limit (`CatalogStore.swift:416,447,509,540`). Long-running shows (Naruto, One Piece) return hundreds of rows. The UI shows a strip; descriptions are needed only in the entity sheet.
- `getStreamLinkForEpisode` needs 2 columns and fetches about 20.

### 4.2 N+1 and serial chains

- Per-id fallback in batch hydration (`CatalogStore.swift:209-222,265-278`).
- `prefetchMediaRelationRefreshRequests` sends up to 12 sequential write RPCs (`CatalogStore.swift:787-795`). This should be one batch RPC, or should not come from the client at all.
- The Library `fetchAll` runs anime then manga sequentially (`SupabaseLibraryBackend.swift:65-67`).
- Combined search runs sequentially (`SearchStore.swift:215-249`).
- `ConciergeAnalytics` flush sends N concurrent single-row inserts.

### 4.3 Duplicate calls on one screen or flow

- `discover_bundle`: warm-up plus forced load (headline 3).
- `get_media_availability_status` two or three times per detail open (flag-gated).
- Full Library read twice at bootstrap (`SessionController.swift:656` and `:816`).
- `feature_flags` twice on a cold launch that signs in (`:254` and `:813`).
- `home_bundle_v1`: from the Library sink (150 ms) **and** the realtime echo (350 ms) for the same edit, plus every foreground regardless of tab.
- `home.drain()`: twice per foreground and per reconnect.
- `fetch_club_bundle_loading` and `fetch_club_bundle` in parallel on first open. The loading snapshot is cheap but is a second round trip.
- `user_airing_next` and `home_events_page_v1` both compute the next anime airing.

### 4.4 Calls on every appear or foreground

- ClubsView refetches `fetch_my_clubs_*` on every tab revisit because it resets `didInitialLoad` (`ClubsView.swift:86`).
- The ProfileView `.task` runs `fetchMyClubs`, MAL identity, the streaming registry and user services on every sheet open (`ProfileView.swift:91-106`).
- Series detail and seasons sheets reload on every foreground through `privacyEpoch` (§3.4).
- `home_bundle_v1` runs on every foreground even when Home is not visible (`ContentView.swift:471`).
- `check_club_activity_since` runs on launch and on foreground while ClubsView is mounted.

### 4.5 Missing caching

| Call | What is missing |
|---|---|
| `series_detail_bundle_v1` | no cache at all |
| `fetchTopTags*` | none |
| `recommend_ids_similar_to_seeds` | none |
| `external_links` | none |
| `episodes` / `chapters` previews | none |
| `fetch_daily_feature` | none (changes daily) |
| `realm_meta`, `streaming_services` | static data refetched; could be cached for a session or longer |
| Browse pages | not cached across filter toggles |
| Search | no last-N query cache |
| `count_friends_tracking`, provider caches | no TTL and no skip-if-cached; every refresh resends all ids |
| Enqueue cooldowns (ladder 12 h, availability 10 min) | in memory only, so they reset each launch, and every launch re-enqueues up to 12 Discover titles |

### 4.6 Unbounded reads

- Credits embeds and reverse entity joins (studio/staff/author/character works) have no `.limit` (`CatalogStore.swift:414-697`).
- `external_links` per title has no limit (small in practice).
- The Library `fetchAll` is bounded at 100 × 1000 rows (`SupabaseLibraryBackend.swift:318`). It depends on PostgREST `max_rows` ≥ 1000, as the comment at `:26-28` notes.

### 4.7 Missing batch prefetch, or prefetch without dedup

- Friend counts and provider availability are batched at 100 (good), but they are re-sent on every refresh and cancel each other across screens (one shared `friendCountPrefetchTask`, `SocialActivityStore.swift:244`).
- Friend counts could be skipped when `myClubs` is empty (a user with no clubs has no friends to count). That check is absent [code].

### 4.8 Correctness and risk adjacent to transport

- `fetchMyClubs` swallows the primary error and silently switches RPC (`ClubsStore.swift:398-403`).
- `withRetry` wraps two writes: `discover_bundle` (impressions) and `concierge-recommend` (Groq cost).
- Image cache key collision across pixel sizes (I1).
- `check_email_exists` allows enumeration (A13).
- Internal `safety_*` and `synopsis_enhanced_*` columns are exposed through every-column selects (headline 5).

---

## 5. Prioritized optimization list

Effort: S = under 1 day, M = 1-3 days, L = more than 3 days. "Deploy" means a backend change is needed (migration or function). Per the lane rules, nothing here was deployed.

| P | Item | Why (evidence) | Effort | Deploy |
|---|---|---|---|---|
| P0 | **Stop the realtime echo from re-reading everything.** Options: (a) drop events within N seconds of a local write whose `mutation_id` / `server_revision` the store already holds; (b) apply the echoed row to `LibraryStore` instead of running `fetchAll`; (c) in `refreshAfterEvent`, skip `home.load` / `collection_feed_page` for progress-only payloads (fetch `AnyAction` with a record diff rather than a bare signal). | Headline 1; `LibraryRealtime.swift:280-301`, `LibraryActions.swift:141-149` | M | No |
| P0 | **Make `feature_flag_overrides` failure non-destructive, or deploy the table.** Treat PostgREST "relation not found" (`PGRST205`/404) like "no overrides" and do not call `removeHomeCohort`. | Headline 2; `FeatureFlags.swift:126-148,233-238`; table absent from `live/table-stats.txt` | S | Optional (deploying `20261007120000` also fixes it) |
| P1 | **Explicit column lists for catalog reads.** Add a `CatalogColumns.animeDetail` constant that mirrors `Anime.CodingKeys`. Use card projections for similar/fallback hydration (14 rows, about 12 fields), and `stream_url,stream_site` for the stream link. Drop `description` from credits embeds. | Headline 5, §4.1 | S | No (column grants to hide `safety_*` would be a deploy) |
| P1 | **One `discover_bundle` per launch, and no impression writes from the warm-up.** Remove `force:true` from the first `.task` load (keep it for pull-to-refresh), or skip the warm-up when Home is the default tab. Server side: split impressions into a separate `record_discover_impressions` call made when rails are actually shown. | Headline 3 | S (client) / M (server) | Server part yes |
| P1 | **One Library read at bootstrap.** Let step 6 join step 1 when no write has happened since (`runFresh` → `run` with a write-epoch check), or order flags before `applySession`'s refresh. | §3.2; `SessionController.swift:656,816` | S | No |
| P1 | **Cache `series_detail_bundle_v1`** (TimedCache about 120 s per account and media). Do not clear the detail bundle on `privacyEpoch`; re-fetch only the club/between-us slice, or bump the epoch only on actual membership change signals rather than on every foreground. | §3.4; `SeriesDetailViews.swift:57-61`, `ContentView.swift:466-472` | M | No |
| P1 | **Fix the detail-page watch-link chain.** Call `get_media_availability_status` once, pass its result into the enqueue decision, cache `external_links` per media (TimedCache 10 min), and key the task on `anime.id` (recompute the primary link locally when progress changes). | Headline 4 | S | No |
| P1 | **Remove the per-id N+1** in batch hydration. If a batch omitted ids, they are missing or adult-filtered, so do not retry them one by one. | Headline 6 | S | No |
| P1 | **Debounce or skip foreground `home.load`.** Load only if Home is mounted and its bundle is older than about 60 s. Merge the two `drain` call sites into one. | §4.3/§4.4 | S | No |
| P2 | **Add a batch release-schedule RPC**, for example `user_release_schedule_v1(p_medium, p_window)`. It should cover anime next episode, manga next chapter (`chapters.release_at`) and next volume (`volumes.release_at`), and should replace `user_airing_next` and the duplicate Home event logic. The tables already exist and `volumes` is unread. | Headline 7; `ReleasesStore.swift:137`, `home_events_page_v1` | M | Yes |
| P2 | **Bound credits and entity reads.** Use `.limit(24)` for the inline strip plus "see all" paging, and add `.limit(200)` with paging to entity sheets. | §4.6 | S | No |
| P2 | **ClubsView should stop refetching on every revisit.** Keep `didInitialLoad` set (or use a 60 s TTL). Remove the catch-all fallback in `fetchMyClubs`, falling back only on `PGRST202` (function missing). | §3.9 | S | No |
| P2 | **Batch the ladder-enqueue writes** (one `enqueue_media_relation_refresh_batch(p_items jsonb)`) and persist cooldowns in `UserDefaults`. Better still, have the server worker pick candidates from impressions. | §3.5 D7 | S/M | Batch RPC: yes |
| P2 | **Give the image pipeline a pixel-size-aware cache key** (`url#maxPx` bucketed), and give prefetches a card-size `maxPixelSize`. | I1 | S | No |
| P2 | **Session-cache static reference data:** `realm_meta`, `streaming_services`, and `feature_flags` (with a TTL rather than every bootstrap). | §4.5 | S | No |
| P2 | **Add TTL and skip-if-cached to friend counts and provider prefetch;** skip friend counts when the user has no clubs. | §4.7 | S | No |
| P3 | Run combined search in parallel (`async let`), and add a small LRU of recent query pages. | §3.10 S1 | S | No |
| P3 | Batch the `ConciergeAnalytics` offline flush into one multi-row insert. | E1 | S | No |
| P3 | Remove `withRetry` from writer RPCs (`discover_bundle`, `concierge-recommend`), or make them idempotent. | §4.8 | S | No |
| P3 | Delete dead `fetchTrendingAnime` / `mv_anime_trending` client code (no callers). | D8 | S | No |
| P3 | Parallelize anime and manga pages in `fetchAll`. | §4.2 | S | No |
| X-lane | Revoke `anon` on `check_email_exists` or rate-limit it (security). Add column-level `REVOKE SELECT` on `anime`/`manga` `safety_*` and `synopsis_enhanced_*` for `anon`/`authenticated` once the client uses explicit columns (security/backend). | A13, headline 5 | S | Yes |

---

## 6. Data-intake cross-reference for the owner's ask (songs, next episode/chapter/volume)

These are API-side observations only; the intake lanes own the pipeline work.

| Owner wants | Client contract today | Live data | API gap |
|---|---|---|---|
| Songs (OP/ED) | `SeriesDetailBundle.themes` → `Theme{role, song_title, artist, external_url, match_state}` (`HomeContracts.swift:295-309`), rendered by the `music` section (`SeriesDetailViews.swift:43`) | `theme_links` **empty** [live] | None in the API. It needs an intake source (AniList does not carry themes; candidates are AnimeThemes.moe or MAL `opening_themes`/`ending_themes`). |
| Next episode | `home_events_page_v1` via `anime.next_airing_at` fallback; `user_airing_next` view; legacy `episodes` preview | `anime.next_airing_at` is populated by AniList bulk import [inferred from schema and CLAUDE.md]; `release_events` empty | Works for anime. Two parallel paths (R1 and H4) should become one. |
| Next chapter | Home `upcoming` (manga) needs `release_events`; legacy `get_manga_chapter_status` | `release_events` empty; `chapters` 94 MB has `release_at` | Manga upcoming is always empty. Needs `release_events` population, or a fallback from `chapters`/MangaDex like the anime one. |
| Next volume/book | `HomeCard.volumes`, `volumesProgress`; editions paging | `volumes` 8.8 MB (`release_date`, `release_at`, `isbn`, `cover_image_*`); **no client read** | Expose through the batch release RPC (P2 above) and through `series_editions_page_v1`. |
| Episode/chapter units and titles | `series_units_page_v1`, `SeriesDetailBundle.units` | `catalogue_units` empty; legacy `episodes`/`chapters` populated | The series path depends on `backfill_legacy_series_units_v1`, which has not run (or produced nothing) live [inferred]. |
| Premise/hook copy | `SeriesDetailBundle.copy` | `detail_copy` empty | Intake or generation needed. |

---

## 7. Uncertainty register

- **Live flag values** (`series_foundation_v1`, `series_home_native_v1`, all rollouts): unknown. The CLAUDE.md percentages are documentation, not a live read.
- **`feature_flag_overrides` existence:** inferred from its absence in table-stats and from the prepared-only migration. Not confirmed with a live query (read-only rules respected).
- **Whether the `20261005*` migrations are live:** suggested by the signal tables in table-stats. The client works either way.
- **Request counts per action** are derived from code paths ([inferred]). They were not measured with a proxy. Coalescing (`AccountScopedLoads.run`) can merge some of them when timing overlaps.
- **Seq-scan and index counters** may have been reset recently. Large counters on catalog and join tables are attributed to server workers (from `outliers.txt`), not to the client.
- **Outbox drain concurrency:** assumed to be serialized inside `LibraryStore`/`ProgressOutbox`. This lane did not verify it line by line.
