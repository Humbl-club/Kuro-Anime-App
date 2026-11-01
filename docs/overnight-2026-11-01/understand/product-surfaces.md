# Product surfaces audit: overnight 2026-11-01

Lane: product-surfaces (read-only). Branch `kuro/overnight-2026-11-01`, HEAD `d8aeae7`.
Scope: Discover, Clubs, Collection, Profile, Taste, Search, detail pages (legacy + series), with Home covered only as the end of the pathway and as a home for new data.
Method: source reads with `grep -n` anchors. The live snapshot is read from `docs/overnight-2026-11-01/live/`. I issued no live queries and wrote nothing except this file.

Confidence labels: **[V]** verified in source at the cited line. **[I]** inferred from source, with runtime behaviour not exercised. **[U]** uncertain or weak evidence.

---

## 0. Read this first: two different apps depending on one flag

Every surface below branches on `FeatureFlags.seriesHomeNativeV1Enabled` (`Kuro/Services/FeatureFlags.swift:57-58`). It is true only when `series_foundation_v1`, `series_home_native_v1` and post-sign-in hydration all hold. The last recorded live values of both series flags are 0%. Sources: `CURRENT_APP_STATE.md:914` and `docs/handoffs/2026-10-08-fresh-session/HANDOFF.md` ("Last recorded live Home flags are both false/0%"). I did not re-query live flags, so treat the live state as **[U]**, last recorded 2026-10-08.

| Surface | Flag OFF (what real installs get) | Flag ON (Debug `--ff-on` only today) | Branch point |
|---|---|---|---|
| Pager | Taste, Discover, Browse, Collection, Clubs (`taste_deck_v1` order; Concierge order if that flag is also off) | Taste, Home, Discover, Collection, Clubs | `Kuro/ContentView.swift:143-149` |
| Taste page | `TastePicksView` | `TastePicksView` (the same view) | `Kuro/ContentView.swift:659-660` |
| Anime detail | legacy `AnimeDetailView` body | `SeriesAnimeDetailView` | `Kuro/Views/DetailPages/AnimeDetailView.swift:51-56` |
| Manga detail | legacy `MangaDetailView` body | `SeriesMangaDetailView` | `Kuro/Views/DetailPages/MangaDetailView.swift:52-53` |
| Collection | `collection_feed_page` grid/list with sort, type and verdict filters plus batch edit | `collection_series_page_v1` plain text series list | `Kuro/Views/EditorialCollectionView.swift:237-241, 594` |
| Home | not mounted | mounted, first page after bootstrap | `Kuro/ContentView.swift:338-341` |

Implication for the overnight build: the owner wants Home, so the flag-on world is the target. But the flag-on world is less complete than the flag-off world on detail and Collection (sections 4 and 6). It also depends on backend tables that are empty in production (section 1).

---

## 1. Data reality behind the surfaces

### 1.1 Series foundation tables are empty in production

From `docs/overnight-2026-11-01/live/table-stats.txt`. The estimated row counts are unreliable, so I corroborated with table size. A single 8 kB heap page means "empty or near-empty".

| Table | Table size | Est. rows | Read |
|---|---|---|---|
| `series`, `series_sections`, `series_entry_spans` | 8 kB each | 0 | empty **[V-weak]** |
| `catalogue_units` (episode/chapter rows for the series detail) | 8 kB | 0 | empty |
| `theme_links` (OP/ED songs) | 8 kB | 0 | empty |
| `release_events` (manga chapters/volumes, announced seasons) | 8 kB | 0 | empty |
| `detail_copy` (hook/premise/synopsis) | 8 kB | 0 | empty |
| `adaptation_coverage` (anime↔source chapter map) | 8 kB | 0 | empty |
| `artwork_materials` (Home colour material) | 8 kB | 0 | empty |
| `episodes` | 17 MB | 0 | **NOT empty**: the estimate is stale **[U]** |
| `volumes` | 3.9 MB | 0 | probably populated, estimate stale **[U]** |
| `chapters` | 51 MB | 745 | populated, estimate stale **[U]** |
| `club_members`, `club_rails`, `title_comments` | 8–16 kB | 0 | effectively empty |

Schemas for the empty tables are in `supabase/prepared-migrations/20261007040000_series_home_foundation_v1.sql:268-391`. For example, `theme_links` at `:330-341` already models `role op/ed/insert`, `song_title`, `artist`, `external_url` and `match_state verified/search/unmatched`. `release_events` at `:363-386` models `precision instant/day/month/quarter/year`, `status scheduled/announced/...` and `kind`.

**Consequence [I]:** in the flag-on world, the series detail page shows its empty-state copy for almost every section. The strings are "This entry is not in an approved season group." (`Kuro/Views/Home/SeriesDetailViews.swift:157`), "Story overview isn't available yet." (`:143`), "Chapter boundaries unverified." (`:260`) and "No verified episode rows yet." (`:841`). The music block is hidden entirely (`:269`). The page looks unfinished even though the code is complete. The schema is ready, so populating these tables is the highest-leverage data task. The intake lane owns the "how".

### 1.2 Next-release data is fragmented across five places, and manga has none

| # | Source | Consumer | Anchor |
|---|---|---|---|
| 1 | `anime.next_airing_at` filtered to the Berlin day | Discover "AIRING TODAY" rail. The RPC **drops `next_airing_at` / `next_episode_number` from the row**, so cards cannot show time or episode | `supabase/migrations/20260326234000_exclude_ancillary_anime_from_default_surfaces.sql:1008-1037` (select list `:1009-1021`, `ORDER BY popularity` `:1032`). Client model has no airing fields: `Kuro/Catalog/MediaDisplayModels.swift:168-188` |
| 2 | `home_events_page_v1`: union of `release_events` and an `anime.next_airing_at` fallback | Home "Coming up" and calendar (flag-on only) | `supabase/prepared-migrations/20261007040000_series_home_foundation_v1.sql:3355-3411`. The anime fallback is at `:3389-3395`. The manga branch can only come from `release_events` (empty), so **manga Coming up is always empty [I]** |
| 3 | `user_airing_next` view via `ReleasesStore` | legacy Collection card countdown only (`NextEpisodeCountdown`) | `Kuro/Releases/ReleasesStore.swift:111-160`, `Kuro/Views/EditorialCollectionComponents.swift:317, 323, 614`, `Kuro/Views/CountdownTimer.swift:7` |
| 4 | `Anime.nextAiringAt` / `nextEpisodeNumber` on the detail model | legacy detail `NextUpSection` | `Kuro/Views/DetailPages/AnimeDetailView.swift:90, 391-405, 448-482`. The series detail has **no** equivalent: `SeriesDetailBundle` has no airing field (`Kuro/Home/HomeContracts.swift:371-389`) |
| 5 | `chapters` (with `release_date`) via `fetchChaptersNext` | legacy manga detail chapter preview | `Kuro/Views/DetailPages/MangaDetailView.swift:749`, `Kuro/Catalog/CatalogDetailModels.swift:59` |

There is **no next-volume source anywhere** in client or RPCs. `volumes` feeds only the legacy `VolumesSection` (`MangaDetailView.swift:134, 1158`). Device reminders (`Kuro/Releases/ReminderScheduler.swift:182`) read `anime` directly, so they cover anime only.

Recommendation: one canonical "next event" projection per title (anime episode, manga chapter, manga volume, announced season) that all five consumers read. `release_events` is already the right shape. Feed it from `anime.next_airing_at`, from MangaDex chapter cadence (the `chapters` table) and from a volume source. The intake lane decides the source.

### 1.3 Songs/themes

These are modelled end to end but have no data. The contract is `SeriesDetailBundle.Theme` (`Kuro/Home/HomeContracts.swift:295-309`). The UI is "The sound of it." (`Kuro/Views/Home/SeriesDetailViews.swift:268-293`). It opens a Spotify URL when `match_state == verified` and the host is `open.spotify.com` (`:276`), otherwise it falls back to a Spotify **search** URL (`:282-283`). It exists only in the flag-on anime detail. The legacy detail, the manga side, Discover and Clubs have no themes surface.

### 1.4 Inventory drift

`docs/modules/sql-function-index.md` has no entries for `home_bundle_v1`, `home_events_page_v1`, `series_detail_bundle_v1`, `collection_series_page_v1`, `fetch_daily_feature`, `get_manga_chapter_status` or the `user_airing_next` view (grep count 0). `discover_bundle`, `fetch_because_you_rail`, `record_taste_deck_signal`, `fetch_club_bundle` and `collection_feed_page` are present. `edge-call-register.csv` covers edge functions, not these RPCs (0 hits for each).

---

## 2. Cross-surface pathway: Discover → detail → track → Home

| Step | Flag OFF | Flag ON | Problem |
|---|---|---|---|
| Find a title | Discover rails, Browse (full catalog and filters), Search sheet | Discover rails and Search sheet only. **Browse is unreachable.** Its only call site is `Kuro/ContentView.swift:670`, and `.browse` is dropped from the flag-on order at `:145` **[V]** | The full filtered catalog disappears with the flag. Home's "find a title" CTA just jumps to Discover (`ContentView.swift:285-288`) |
| Open detail | legacy detail: next-up, genres, cast, ladder, similar, share, watch links (`AnimeDetailView.swift:86-185, 208`) | series detail: art, seasons, story, units, coverage, music, cast, "Between us" (`SeriesDetailViews.swift:30-48`) | The series detail **loses**: next-episode countdown, score/meta line, genres/tags, similar/"more like this", the adaptation ladder (replaced by `coverage`, which is empty), watch/read provider links, share link and the sticky action bar. With empty tables it is mostly placeholders (section 1.1) |
| Track | Quick Add (Planned) from a card context menu (`KuroRefinedCard.swift:181-184`, `EditorialSearchView.swift:560-563`, `ClubDetailTabComponents.swift:602-605`). The sticky `ActionButtons` on detail | "Add to list" / "List settings" text buttons below the units list (`SeriesDetailViews.swift:233-239`), via `routes.presentTrackingEditor` | On the series page, "Add to list" is buried mid-page under the units, and the lead action is not obvious |
| Appear on Home | n/a | Home `active` includes PLANNING rows (`20261007040000…sql:1389, 1447`). A newly planned title, with nothing else in progress, puts Home in the `.saved` scene (`Kuro/Views/Home/HomeShelfPolicy.swift:18-26`). The scene renders that title as the hero over the copy **"Nothing in progress. Completed and saved titles stay in Collection."** (`Kuro/Views/Home/HomeView.swift:300-321`) | Contradictory message **[I]**. With other shows in progress, `active` is ordered `updated_at desc` (`…sql:1390-1395`). A just-planned title can then take one of the two big anime scene slots (`HomeView.swift:436`) and get a +1 key at 0/12 **[I]** |
| Undo / propagation | Library change sinks fan out to Releases, Collection, Concierge, Clubs and Home (`Kuro/Composition/LibraryChangeSinks.swift`) | same. The Home sink only runs once a bundle is loaded | OK |

Pathway verdict: flag-off is complete but visually legacy. Flag-on is visually new but loses discovery breadth (Browse), detail breadth and planned-title handling.

---

## 3. Discover (`Kuro/Views/EditorialDiscoverView.swift`, `Kuro/Discovery/DiscoveryStore.swift`)

**What the user sees [V]:** a TYPE menu (ALL/ANIME/MANGA) top-right (`:121-143`), then a daily "One Thing" hero (`:146-161`). The rails follow: AIRING TODAY (`:163-172`), BECAUSE YOU LOVED or NEW TO YOU (`:176-193`), the flag-gated Shelf (`:196-207`), ESSENTIAL ANIME (`:209-218`), the flag-gated Hidden Gem (`:221-232`), NEW TO YOU (MANGA) (`:234-242`), TRENDING (`:245-255`) and ESSENTIAL MANGA (`:257-266`). A "N MORE SECTIONS" expander (`:270-292`) reveals CLASSICS, CURRENT SEASON, TOP RATED, JUST ADDED, MANGA CLASSICS, TRENDING MANGA and TOP RATED MANGA.

**Data:** one `discover_bundle` RPC (`DiscoveryStore.swift:92-133`, 120 s per-account cache with in-flight dedupe). Plus `fetch_daily_feature`, the flag-gated `fetch_because_you_rail` / `fetch_personalized_new_to_you`, and the flag-gated `fetch_tonight_shelf` / `fetch_realm_hidden_gem` (`:430-560`). After load it calls `count_friends_tracking` (`:573-586`), a ladder-refresh enqueue (`:588-602`) and an image prefetch.

**Weak, confusing or broken:**
1. **AIRING TODAY has no times or episodes.** The rail is ordered by popularity, not air time, and the row omits the airing fields (section 1.2 #1). This is the most obvious "when is the next episode" gap on a live surface. **[V]**
2. **`vm.newlyAddedManga` is loaded but never rendered** (`:487`). It counts toward `hasAnyContent` (`:60`) and friend prefetch (`:577`), but no section shows it. **[V]**
3. **TRENDING MANGA (`:350-357`) and TOP RATED MANGA (`:360-366`) have no See All.** `EditorialDiscoverRoute` has no case for them (`Kuro/Views/EditorialDiscoverRouting.swift:3-16`). The anime equivalents do. **[V]**
4. **BECAUSE YOU LOVED is a mixed anime+manga feed**, but See All routes to `.animeBecauseYou` → `FullSectionView` (`:182, 408-409`), the anime grid. Rendering mixed `Media` probably works, but the route name and layout assume anime. **[U]**
5. Dead code: `currentSeasonQueryParams()` has no caller (`:616`). `DiscoverViewModel.swift` is flagged "Legacy/secondary" in CLAUDE.md. **[V]**
6. **TYPE filter is a 9 pt grey menu** (`:121-143`, `.system(size: 9)`). It is the most important scoping control on the page and also the least visible. Home uses a 40 pt serif medium switch for the same concept (`HomeView.swift:217-262`). **[V]**
7. **Brand drift.** The file has 23 raw `.black.opacity(...)`, 20 `.system(size:)` and 21 `.tracking(` uses with **0** `kuroInk` tokens. Home, Profile and series detail use the new ink family (`kuroInk` 43/29/30 uses; `Kuro/Design/KuroDesignSystem.swift:98-110`). Discover still speaks the old tracked-caps "Swiss" dialect (ALL-CAPS rail titles, "REFINE THIS RAIL"). **[V]**
8. **Duplicate bundle fetches at launch [I].** `ContentView.swift:426` warms `discover_bundle(limit 30)` on every launch, even when Home is the first page. Discover's first refresh then calls `force: true` (`EditorialDiscoverView.swift:452`), which bypasses the warm cache unless the two calls overlap in flight. `TastePicksView` makes a third call with `limit: 12` (`Kuro/Views/TastePicksView.swift:102`). That is a different cache key, so it is another full run of a roughly 330-line CTE RPC just to show 4 picks.
9. A UserDefaults-sticky "show more" (`:25, 275`). Once expanded it stays expanded forever, and there is no collapse control. **[V]**
10. Discover vs Taste duplication: Taste picks are a subset of the same bundle's `newToYou` / `essentials` plus because-you (`TastePicksView.swift:117-136`). Discover shows the same items in "NEW TO YOU" / "BECAUSE YOU LOVED".

**Where new data belongs on Discover:**
- AIRING TODAY cards should show a date-stamp ("Ep 7 · 21:30"), sorted by air time. This needs `next_airing_at` and `next_episode_number` in the bundle row; it is a backend change.
- An "Out this week" rail covering new chapters and volumes from `release_events`, once populated.
- An editorial "Openings worth hearing" rail from verified `theme_links`. This is optional and only makes sense once verified data exists.
- A season premiere / "announced" strip from `release_events` with `status = announced`.

---

## 4. Detail pages

### 4.1 Legacy (`Kuro/Views/DetailPages/AnimeDetailView.swift`, `MangaDetailView.swift`): live today

Parallax hero, title and meta line (score/year/format/eps/status, `:410-445`). `NextUpSection` shows "EP n · in 3 days" or "AIR DATE TBA" (`:448-482`). Then description (with FM condensed synopsis), genres, sub-genre tags, cast and production (`credits_cast_v1`), the adaptation ladder, episodes (preview of 10 plus a sheet paged by 50), the NEXT pick, MORE LIKE THIS, club activity, friend comments, a share link and the sticky `ActionButtons` (`:86-215`). Manga mirrors this with `ChaptersSection` and `VolumesSection` (`MangaDetailView.swift:130, 134`) plus `MangaActionButtons` (`:209`).

Weak points:
- `effectiveUpcomingEpisodeDisplay` shows `rawNextEpisode + 1` as "AIR DATE TBA" once `nextAiringAt` has passed (`:402`). That is a guess with no evidence of airing order. **[I]**
- Two design generations meet inside one page: tracked caps and `.black.opacity` (7 / 9 / 20 uses) against new ink tokens (0). **[V]**
- No themes and no next-chapter date. The chapter rows show `releaseDate` (`MangaDetailView.swift:829, 899`) but there is no "next chapter expected" line.

### 4.2 Series (`Kuro/Views/Home/SeriesDetailViews.swift`): flag-on

Anime (`:7-339`): art with title and status (`:69-124`). Seasons panels with entry chips and "Return to opened entry" (`:149-217`). Story hook/premise/synopsis (`:128-147`). Units via `SeriesUnitsView` (`:230-241`, `:800-955`). Then coverage "The original story" (`:244-265`), music (`:268-293`), cast, principals and "Between us" club discussion (`:300-314`). Manga (`:341-560`): cover, premise, bookmark, editions and a reciprocal anime guide.

Weak points:
- **Empty-state heavy, because the backing tables are empty** (section 1.1). **[I]**
- **Missing relative to legacy:** next airing, score/meta, genres, similar, provider links, share link, sticky action. This is a regression in user value, not just a different style. **[V]** by absence in `body` (`:30-48`).
- The lead action ("Add to list") sits after the units list (`:233-239`) instead of at the top or in a sticky bar.
- Copy strings are typed inline with no German variants, while Home has DE strings (`HomeView.swift:300-321`). **[V]**
- "Chapter boundaries unverified." is shown to every anime without coverage (`:259-262`). That is internal QA language exposed to users.

### 4.3 Where new data belongs on detail

- **Next episode / chapter / volume:** a single "Next" line directly under the title, using a date-stamp (instrument `date-stamp` vocabulary). Precision-aware: "Thu 21:30", "Nov 14", "November", "Announced". Both legacy and series detail should read the same projection.
- **Songs:** keep "The sound of it." Add artist and the OP/ED sequence ("OP 2 · Song — Artist"), and show the section only when at least one row is `verified` or `search`. Manga: none.
- **Volumes:** add a "Next volume" date-stamp to the manga bookmark area.

---

## 5. Taste (`Kuro/Views/TastePicksView.swift`)

**What the user sees [V]:** an ANIME/MANGA caps switch (`:27-31`), one explanatory note, up to **4** picks (`:20`) shown as `CompactAnimeCard`, each followed by a separate "Add to list" text button (`:55-62`).

**Data:** `fetch_because_you_rail(limit 8)` and `discover_bundle(limit 12)` (`:101-102`). The first runs regardless of `personalized_new_to_you_v1`, while Discover gates it (`EditorialDiscoverView.swift:511`).

**Findings:**
1. **The Taste Deck is orphaned in current source [V].** `TasteDeckView` (1,304 lines) has **no instantiation** anywhere in `Kuro/` or `KuroTests/` (grep). The `.taste` page renders `TastePicksView` in every pager order (`ContentView.swift:659-660`). Taste signals are written only by `TasteDeckView` (`TasteDeckView.swift:117, 143, 162` → `TasteStore.submitSignal` / `recordTasteDeckSignal`, `Kuro/Taste/TasteStore.swift:216-227`). That makes `record_taste_deck_signal` client-uncalled. Its consumers (because-you rail, personalized NEW TO YOU, taste profile) would get no new signal from fresh installs. **[I]** The installed TestFlight/App Store binary may predate this and still show the deck. **[U]**
2. **Doc drift:** `CURRENT_APP_STATE.md:915-916` and CLAUDE.md still say "Taste (Taste Deck)" at index 0.
3. **Onboarding mismatch:** onboarding's `.tasteDeck` destination selects `.taste` (`ContentView.swift:533-535`). The user is promised a taste deck and lands on a 4-item list.
4. The page duplicates Discover data (section 3 item 10) and has a weak role: "Close to what you already like" with 4 cards and no reason line. That is a thin left-most page on a 5-page pager.
5. Style: the caps underline switch is a third medium-switch dialect (Home serif, Discover menu, Taste caps). See section 9.

---

## 6. Collection (`Kuro/Views/EditorialCollectionView.swift`, `EditorialCollectionComponents.swift`, `Kuro/Collection/CollectionStore.swift`)

### 6.1 Flag OFF (live)

Status filter bar ALL/WATCHING/COMPLETED/PLANNED/PAUSED/DROPPED (`:40-58`) and a status count line (`:297-314`). Sort row (LAST UPDATED / TITLE A-Z / RATING / MY RATING / PROGRESS, `:95-101`). TYPE menu, the flag-gated service and language filters, a grid/list toggle and EDIT batch mode (`:384-437`). Under COMPLETED there is a verdict filter (Masterpiece/Okay/Bad/Unsorted) with an "N completed titles still need a verdict" nudge (`:351-380`). The cards show a countdown from `ReleasesStore` (`EditorialCollectionComponents.swift:614`). Data comes from `collection_feed_page`, joined with the `LibraryStore` projection.

Weak points:
- **The batch status dialog omits Dropped** (`:216-220`: Watching / Completed / Planned / Paused). **[V]**
- The label "WATCHING" is used for manga too (`:42, 178, 216`). `ListStatus.displayName` is "Watching" (`Packages/KuroModules/Sources/KuroLibrary/LibraryValues.swift:38`). **[V]**
- `.repeating` shows as "REWATCHING" in counts (`:183`) but has no filter tab. **[V]**
- The 9 pt tracked caps controls are hard to read (`:363-366`, `.system(size: 9)`).

### 6.2 Flag ON (`collection_series_page_v1`)

`seriesCollection` (`:605-676`) is a **plain text list**. Each group's heading is `group.children.first?.title` (`:623`), which is the first child's title, not a series name. Each child row is title + a bare number. **Tapping the number advances progress by +1** (`:638-656`) with no confirmation, no unit label and no total. There are no covers, no status, no rating and no next release.

- **The header controls still render but do nothing [V/I].** `collectionHeaderSection` is drawn whenever `importedTitleKeys == nil` (`:203-205`). It includes sort buttons, the TYPE menu, the grid/list toggle, EDIT and the verdict filters (`:317-437`). `reloadSeriesCollection` passes only `home.medium`, status and query (`:274-284`). The sort, type, verdict, listView and edit states feed only the legacy `items` pipeline (`:103-170`).
- **Medium is invisible:** the series Collection follows `home.medium` (`:278, 284`), a choice made on another page, and has no visible medium switch.
- The contract is too thin for a good list. `CollectionSeriesChild` carries only `mediaId`, `listType`, `progress`, `serverRevision`, `lifecycleId` and `title` (`CollectionStore.swift:563-581`). There is no cover, unit total, rating, verdict or next event.

**Where new data belongs:** a date-stamp on every in-progress or planned row ("Ep 8 Thu", "Ch 141 Nov 14", "Vol 12 Dec"). An "out now / behind by N" marker comes from the next-event projection plus progress. See the list concepts in section 10.

---

## 7. Profile (`Kuro/Views/ProfileView.swift`, `ProfileFreshnessCard.swift`, import entry points)

**What the user sees [V]:** a sheet opened from the header avatar menu (`ContentView.swift:896-903`). Order: a scenery identity header with the initial and "Your account" (`:216-253`). Library has three figures (anime/manga/done), "Open Collection" and a "Progress on this device" disclosure (`:271-333`). Imports follow (`:335-415`, AniList / MAL account / MAL XML, history), then pending (flag-gated, `:417-430`). Clubs is a row that opens **ClubsView again in a sheet** (`:151-167, 432-446`). Preferences hold Sync Data, Concierge and the flag-gated streaming services plus `ProfileFreshnessCard` (`:448-509, 617-624`). Account holds Sign Out and Delete, then the footer and an Advanced section with Clear Cache (`:531-615`).

**Findings:**
1. **"Profile where your lists are"**, as the owner asked, does not exist. The lists live on the Collection page, and Profile only links there (`:299-303`).
2. **Duplicated features:**
   - Clubs: a pager page, a Profile sheet and a Home slice.
   - Sign Out: the header menu (`ContentView.swift:900`) and Profile (`:538`).
   - Import: Home invitation, Home `ImportSourceChooser`, Profile and Concierge.
3. **`ProfileFreshnessCard` is an ops/observability panel** ("STREAMING STATUS", queue reasons, `ProfileFreshnessCard.swift:54, 104`) shown inside a consumer profile. It is behind `streaming_availability_v1` (0%). It should not ship in Profile. **[V]**
4. **Sync Data in flag-on mode refreshes the legacy feed** (`collection.fetchCollectionFeed()`, `:462`), not the series page the user sees. **[V/I]**
5. The header avatar is a `Menu` with two items (`ContentView.swift:896-903`). Profile is one tap deeper than needed, and Sign Out sits one tap from the main header.
6. The identity block is nearly content-free ("Your account" plus email). The design plan already calls for identity, Library, imports, pending, preferences and account (`docs/plans/2026-10-08-native-design-polish.md:101-112`).

---

## 8. Clubs (`Kuro/Views/ClubsView.swift`, `ClubDetail*.swift`, `Kuro/Clubs/ClubsStore.swift`)

**What the user sees [V]:**
- **List.** Empty state "Watch together. Private by design." with CREATE/JOIN (`ClubsView.swift:200-270`). Journal club cards show covers, sharing level, member names, activity preview and relative last activity (`:370-590`).
- **Detail.** Hero, status bar, RAILS / ACTIVE / POLLS tabs (`ClubDetailView.swift:28-31`; CLAUDE.md still says "This Week"). Rails carry items, reactions and Quick Add (`ClubDetailTabComponents.swift:185-615`). Activity is a day-grouped member status timeline (`:617-885`). There are pace and milestone banners (`:886, 923`) and polls (`:961-1280`).

**Data:** `fetch_my_clubs_enriched`, `fetch_club_bundle`, `check_club_activity_since`, `toggle_club_reaction`, `cast_club_vote`, `create_club*`, `join_club`, `leave_club` and realtime (`Kuro/Clubs/ClubsStore.swift`, `ClubRealtimeCoordinator.swift`). Live club tables are effectively empty (section 1.1).

**Findings:**
1. **Create/Join sheets are private copies inside `ClubsView.swift`** (`:591, 753`). CLAUDE.md's file map says `ClubCreateSheets.swift` holds create/join, but that file holds rail and poll sheets (`ClubCreateSheets.swift:6, 144`). This is doc drift. **[V]**
2. Brand drift: 26 raw `.black.opacity` in `ClubsView.swift` and 18 in `ClubDetailView.swift`, with 0 ink tokens.
3. **The club has no shared calendar.** Rails list titles, and pace says "3 ep behind". Nothing says "Ep 8 of the club pick airs Thursday" or "Ch 141 drops Sunday". That is the most natural social use of next-release data.
4. Three surfaces show club content: the page, the Profile sheet copy and the Home club slice (`HomeView.swift:1017-1050`). The Series detail adds a "Between us" disclosure.

**Where new data belongs:** a "This week in the club" strip on the club detail (next events for rail items and members' in-progress titles, from the same projection). Next-event date-stamps on rail item cards. Optionally a "club anthem" (a verified OP) on the club hero. That is decorative and low priority.

---

## 9. Search (`Kuro/Views/EditorialSearchView.swift`, `Kuro/Search/SearchStore.swift`)

**What the user sees [V]:** a header-sheet search bar "SEARCH" (`:317`), a scope toggle ALL/ANIME/MANGA (`:28-32, 234-266`), "DISCOVERY REFINEMENTS" chips (TRENDING, NEW, NEW SEASON, CLASSICS, HIDDEN GEMS, AIRING; `:34-41, 269-305`) and result rows with a context-menu Quick Add (Planned) (`:560-563`). The placeholder reads "DISCOVER / Begin your search for the extraordinary" (`:705-735`). The no-results state has suggestions (`:640-700`).

**Data:** `search_anime_page`, `search_manga_page`.

**Findings:**
1. In the flag-on world Search is the **only** open catalog entry (Browse is gone, section 2), yet its idle state is a decorative placeholder. There are no recent searches, genre/format entry points, airing-this-week list or "browse all" link. **[V]**
2. The placeholder headline "DISCOVER" (`:716`) collides with the Discover page name. The copy is generic.
3. Brand drift: 25 raw `.black.opacity`, 12 `.system(size:)`, 0 ink tokens.
4. Result rows show "· N eps" (`:513`) but not airing state. The AIRING refinement exists, but rows don't say when.

**Where new data belongs:** an "Airing · Thu" / "New chapter" badge in rows, a "Releasing this week" idle list, and Browse filters folded into Search refinements (genre, format, decade, length) to restore what flag-on removes.

---

## 10. Duplicated controls and inconsistent grammar (cross-surface)

| Concept | Variants in source |
|---|---|
| Medium switch | Home 40 pt serif with picture-fill letters (`HomeView.swift:217-262`). Taste caps underline (`TastePicksView.swift:80-96`). Discover 9 pt TYPE menu (`EditorialDiscoverView.swift:121-143`). Collection TYPE menu (`EditorialCollectionView.swift:456-472`), ignored under the flag. Search scope toggle (`EditorialSearchView.swift:234-266`) |
| Add to list | Taste text button (`TastePicksView.swift:57`). Series detail text button (`SeriesDetailViews.swift:235`). Context menus with Quick Add (Planned) in 3 files. Legacy sticky ActionButtons (`AnimeDetailView.swift:208`) |
| +1 progress | Home key-cap (`HomeView.swift:642-680`). Series Collection bare number (`EditorialCollectionView.swift:638-656`). Legacy cards "+1 EP/CH" (`LibraryViewActions.swift:47-52`). Episode/chapter rows (`LibraryViewActions.swift:59-62`) |
| Next release | 5 sources, 4 visual treatments (section 1.2) |
| Clubs entry | pager page, Profile sheet, Home slice, detail "Between us" |
| Import entry | Home invitation, Home chooser, Profile, Concierge |
| Status vocabulary | "Watching" for manga (Collection). "Watching/Reading" (Home SQL). "PLANNED" vs "Planning" vs "Saved". "REWATCHING" without a tab |
| Typography dialect | ink/serif (Home, Profile, Series) vs tracked caps + black opacity (Discover, Collection, Clubs, Search, legacy detail). Counts in the token drift table (sections 3–9) |

Other adaptivity notes **[V]**:
- `ContentView.rootWidth` falls back to a hard-coded `393` (`ContentView.swift:216-220`), which DO-NOT #5 forbids in spirit.
- `HomeView.sceneryHeight` uses a 320 fallback and `max(520, w*1.45)`, which may overflow small landscape heights **[U]**.

---

## 11. Three list concepts (Library as a view over `LibraryStore`)

### Shared constraints (apply to all three)

- **Authority.** Rows come from `LibraryStore.allEntries` / `entry(for:)`: key, status, progress, progressLabel, rating, verdict, notes, createdAt, updatedAt, revision, lifecycleId (`Packages/KuroModules/Sources/KuroLibrary/LibraryValues.swift:101-118`). Status set: CURRENT, PLANNING, COMPLETED, DROPPED, PAUSED, **REPEATING** (`:28-34`). Verdict: MASTERPIECE / OKAY / BAD (`:6-9`).
- **Writers. There are two, so say which.**
  - **Progress +1 / set-to-unit** goes through `HomeStore.advance(...)` → `LibraryStore.storeProgress` (SQLite outbox, guarded Undo, conflict tokens; `Kuro/Home/HomeStore.swift:501-545, 547-560`). On the non-foundation path the alternative is `LibraryViewActions.incrementProgress` → `LibraryActions.incrementProgress` (`Kuro/Views/LibraryViewActions.swift:47-52`).
  - **Status, rating, verdict, notes and removal** go through `LibraryActions.apply/save/remove` (`Kuro/Library/LibraryActions.swift:295-311`), via `LibraryViewActions` or the tracking editor route (`routes.presentTrackingEditor`).
  - No list view writes the store directly. That is enforced by `scripts/quality-gates/check_architecture.sh`.
- **Display join (the missing piece).** `LibraryEntry` has no title, cover, unit totals or next event. `CollectionSeriesChild` (`CollectionStore.swift:563-581`) lacks the same fields. Every concept needs, per title: `title`, `cover_image`, `episodes|chapters|volumes` total, `catalogue_status`, `next_event {at, precision, unit_label, kind}` and optionally `series_id/section_name`.
  - Cheapest path: **extend `collection_series_page_v1` children and `collection_feed_page`** with these columns. That is a **backend change** (prepared migration, owner deploy).
  - No-deploy fallback: join the legacy `collection_feed_page` `Media` (which already has title, cover and episodes, `CollectionStore.swift:263-266`) with `ReleasesStore.upcomingAirings` for anime. Manga next-chapter dates stay absent.
- **Monochrome** (CLAUDE.md DO-NOT #3): no coloured status dots or pills. Encode status by **position, ink density, weight and shape**. Red is reserved for destructive actions.
- **Prototype vocabulary to reuse** (grep of `tools/design-directions/instrument.css`, `instrument.js`, `manga-philosophies.css/js`):
  - `key-cap` (separate 44 pt advance key)
  - `progress-track` / `progress-trace` / `progress-total` / `progress-label`
  - `date-stamp`, `bookmark-tick` / `folio-bookmark`
  - `library-covers` (equal covers), `medium-paper` / `ribbon-paper`
  - `season-strip`, `release-calendar`, `clubroom-table`
  - The manga-library rule: "Every book. Its own bookmark… cover and title are one detail target. Chapter advance is a separate sibling control" (`tools/design-directions/manga-library.html`, aside copy).
- **Medium.** All concepts keep Anime and Manga as a visible serif switch that matches Home (`HomeView.swift:217-262`), not a hidden `home.medium` coupling.

### Concept A: "Folio Ledger" (typographic ledger, status as chapters of a book)

- **Layout.** One vertical scroll. Each status is a serif section header with a count, in this order: **Watching/Reading · Rewatching · Planned · Paused · Completed · Dropped**. Watching is expanded. The others show the first 3 rows plus "All 24". A section header pins while scrolling. Each row has:
  - left: an equal-ratio cover at 44×66 (cover + title = **one** detail target)
  - centre: the title (2 lines) above a `progress-track` hairline with ink fill = progress/total, and `progress-label` "7 / 12" in mono digits
  - right: a `key-cap` +1 (44 pt, separate sibling control)
  - under the title, when present: a `date-stamp` ("Ep 8 · Thu 21:30", "Ch 141 · Nov 14", "Vol 12 · December", "Announced")
  - a small serif rating numeral and verdict word in the right margin for Completed rows
- **Monochrome encoding.** Paused rows use 70% ink with an italic title. Dropped rows use 45% ink with a hairline through the progress track. Completed rows replace the key-cap with the verdict word. A new episode out ("behind") gets a solid `bookmark-tick` notch on the cover edge, which is a shape signal, not a colour.
- **Interactions.**
  - Key-cap → `HomeStore.advance` (Undo toast).
  - Leading swipe → +1 (same path).
  - Trailing swipe → status sheet (`LibraryActions.apply(LibraryEdit(status:))`).
  - Long-press → the tracking editor route (rating, verdict, notes, remove).
  - EDIT → multi-select with a batch status bar that **includes Dropped and Rewatching** (fixes `EditorialCollectionView.swift:216-220`).
  - A search field filters in place, and sort is per section (Recent / Title / Rating / Progress).
- **Why it fits.** It is the closest native translation of the Instrument progress rows and `release-calendar`. It is dense, reads at a glance, is VoiceOver-friendly ("Frieren, 7 of 28, next episode Thursday 21:30, advance button") and supports Dynamic Type (the cover drops below the title at accessibility sizes).
- **Data.** Shared join plus `next_event`. It works with the no-deploy fallback for anime. Manga dates arrive once `release_events` is populated.
- **Risk.** It is the least "wow". Its innovation is in the date-stamp and behind-notch, not the layout.

### Concept B: "Contact Sheet" (equal-cover grid with grease-pencil marks)

- **Layout.** An adaptive grid of **equal covers** (`library-covers`, the manga-library rule): 3 columns at 320 pt, 4 at 390–430, 6+ on iPad, recomputed from width and Dynamic Type, never hard-coded. A segmented strip at the top (Now · Planned · Finished · All) changes the set. Under each cover sit the title and a `progress-trace` baseline aligned across the row, with a `key-cap` below for in-progress titles.
- **Marks, darkroom style, all monochrome.**
  - In progress: a progress baseline under the cover.
  - Behind: a corner `bookmark-tick`.
  - Completed: a small stamped verdict ("M" / "OK" / "B") or a rating numeral in a white tab, borrowed from the Home `Season N` white artwork tab (`HomeView.swift:458-475`).
  - Paused: the cover at 60% luminance with a pause notch.
  - Dropped: a grayscale cover with a diagonal hairline.
  - Planned: no baseline, just an empty `progress-track` outline.
- **Interactions.**
  - Tap cover → detail (one target).
  - Key-cap → `HomeStore.advance`.
  - Drag a cover onto a status tab ("Finished") → `LibraryActions.apply(status:)` with Undo, with a long-press menu as the accessible alternative.
  - Pinch to change density (3↔5 columns).
  - Multi-select by long-press and drag across covers → batch bar.
- **Why it fits.** It is the most visual and the closest to how people remember shows (by artwork). It reuses equal-cover discipline and white-tab vocabulary. It is a strong fit for Manga, where the cover is the identity.
- **Data.** Needs a reliable `cover_image` on every row (a backend extension for the series path) and `total` for the baseline. The behind-tick needs `next_event` plus the last released unit.
- **Risk.** It is weak for long titles and VoiceOver unless each cell is a combined element with a custom action (+1, change status). Drag-to-status needs an accessible equivalent, and the long-press menu covers that.

### Concept C: "Almanac" (a time-first list: what happens next)

- **Layout.** The list is organised by **time, not status**, in four bands.
  - **Out now** holds in-progress titles with a released unit you have not watched or read ("Ep 8 out · you're on 7"). Each row has a key-cap.
  - **This week** holds a day-by-day `release-calendar` strip (Mon–Sun columns of small covers with `date-stamp` times), covering in-progress and planned titles.
  - **Waiting** holds in-progress titles with nothing new yet, plus Paused, with the next known date or "No date yet".
  - **Shelf** holds Planned (start next) and Completed by month, with verdicts, as a compact typographic index.
  - Dropped lives behind "Show dropped" at the bottom.
  - A sticky "Today" marker anchors the scroll position.
- **Interactions.**
  - Key-cap on Out now → `HomeStore.advance`. When a title catches up it animates down into Waiting, with Reduce Motion as a crossfade.
  - Tap a calendar cover → detail.
  - "Start" on a Planned row → `LibraryActions.apply(status: .current)`, then advance to unit 1 via `HomeStore.advance`.
  - Status changes elsewhere use the tracking editor route.
- **Why it fits.** It turns the new data (next episode, chapter and volume dates) into the organising principle. It answers the owner's "when is the next one coming out" directly, and it makes the list a daily-return surface without duplicating Home. Home stays "what I'm in". The Almanac is "my whole library over time".
- **Data.** It is the most dependent on `next_event` and on a "latest released unit" per title, which `anime.next_episode_number - 1` gives for anime and `chapters` max number for manga. It degrades to Concept A ordering when dates are absent. Manga is weak until `release_events` / chapter-cadence data exists.
- **Risk.** It overlaps the Home calendar (`HomeView.swift:926`). The two must share one component and one projection. Empty weeks look sparse, so collapse empty days.

### Recommendation (for the design spec lane)

Ship **A (Folio Ledger)** as the default Library view inside Profile/Collection. It works today with the no-deploy join, is accessible and on-brand. Add **B (Contact Sheet)** as a density toggle (grid ↔ ledger, replacing the current grid/list toggle at `EditorialCollectionView.swift:402-413`). Bring **C (Almanac)** in as a "This week" lens once the `next_event` projection exists, sharing its calendar component with Home. A spine bookshelf concept was considered and rejected: vertical text fails Dynamic Type and VoiceOver, and it hides progress.

---

## 12. Prioritised fixes this lane recommends

1. **Decide the flag world, then fix its regressions.** If flag-on is the target: restore Browse (as a Search refinement page or a Discover "All titles" route). Bring next-up, score/genres, similar, provider links and share into the series detail. Hide the series Collection controls that do nothing, or wire them.
2. **Populate the series foundation tables**, or fall back gracefully. Until they have data, the series detail should fall back to legacy sections instead of showing "unverified / not available" copy (`SeriesDetailViews.swift:143, 157, 260, 841`).
3. **One next-event projection.** Add `next_airing_at` / `next_episode_number` to the Discover airing-today rows and sort by time. Feed `release_events` for manga chapters and volumes. Make Home, detail, list rows and clubs read it.
4. **Restore or retire the Taste Deck.** Either mount `TasteDeckView` (signals feed personalization) or delete it, and stop promising a deck from onboarding (`ContentView.swift:533`). Fix the docs at `CURRENT_APP_STATE.md:915-916` and CLAUDE.md.
5. **Library in Profile:** implement Concept A as the Profile "Your Library" section, keep Collection as the full-screen version of the same component, and remove the duplicate Clubs sheet from Profile (`ProfileView.swift:151-167`).
6. **Unify medium switch, status vocabulary ("Reading" for manga, Rewatching/Rereading tab, Dropped in batch) and typography** onto the ink token family.
7. **Small fixes:**
   - render or remove `newlyAddedManga` (`EditorialDiscoverView.swift:487`)
   - add See All routes for trending and top-rated manga
   - delete `currentSeasonQueryParams` (`:616`)
   - drop the `ContentView.swift:426` warm fetch when Home is the first page, and make Taste reuse the limit-30 bundle
   - remove `ProfileFreshnessCard` from the consumer Profile
   - make Profile Sync refresh the series page under the flag (`ProfileView.swift:462`)
   - fix `group.children.first?.title` as the series name (`EditorialCollectionView.swift:623`)
   - add a unit label and Undo to the series Collection +1 (`:638-656`)
8. **Planned titles on Home:** exclude PLANNING from the anime scene slots or give them a "Start" affordance. Fix the "Nothing in progress" copy when the hero is a planned title (`HomeView.swift:300-321`). The server side is at `20261007040000…sql:1389, 1447`.

## 13. Open questions

- Is the flag-on world (Home + series detail + series Collection) the production target for this release, given the empty foundation tables and the owner-approval rule for backend deploys?
- What is the installed live binary? Does it still mount `TasteDeckView`? Source does not.
- Is a backend extension of `collection_series_page_v1` / `collection_feed_page` (cover, totals, next_event) in scope, or must lists use the client-side join?
- Which source for manga next-chapter and next-volume dates? MangaDex chapter cadence is already ingested into `chapters`, and a volume calendar source is unknown. Which source for themes (e.g. AnimeThemes, intake lane)?
- Should Collection remain a pager page if the Library moves into Profile, or should Profile become a full page?
