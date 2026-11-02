# Kuro client request, latency and lifecycle audit

26 September 2026. Read-only current working-tree source audit. No app edits, build, device changes, hosted calls or database writes. Existing AuthView edits preserved. This memo supplies the execution plan, not proof of observed latency or production defects.

## Scope and coverage

- Inventoried all **93 Swift files** under `Kuro/`. Audited owned transport boundaries and complete surrounding service methods, plus the relevant view lifecycle, state, pagination, mutation and cancellation paths. Pure rendering/model files were scanned for direct calls and traced where they create image or service consumers; this does not claim a line-by-line aesthetic review of every styling declaration.
- Six service files are delegated to the companion audit: `SupabaseService+Clubs.swift`, `+ClubRealtime.swift`, `+Social.swift`, `+Streaming.swift`, `+Concierge.swift`, `+Taste.swift`. Their **view callers are registered here**; their endpoint internals and database work are the companion lane's responsibility. Core Concierge methods remain in `SupabaseService.swift`, so those seven core Edge Function sites are covered here.
- `evidence/client-call-register.csv`: **381 source records**, comprising 76 ordinary request boundaries, 7 Edge Function invocation boundaries, 7 SDK session accessors, 1 SDK auth event listener, 3 realtime control sites, 228 view service-call sites, 35 image surfaces and 24 supplementary telemetry/image/flag/stream wrappers. **These are not 381 HTTP requests.** A view wrapper may call several endpoints or hit cache; one transport site may run repeatedly, loop over chunks, retry or be dormant. Auth session accessors can resolve from SDK cache or trigger refresh. Realtime registration is not a database query per declaration. Image surfaces generally share one URLSession boundary.
- `evidence/client-source-coverage.json`: file inventory, line counts and SHA256 at extraction, with delegated files explicitly marked. `evidence/client-register-summary.json`: machine-readable counts. Line references below are relative to `/Users/max/Kuro-Anime-App` and describe the inspected dirty working tree.
- Direct transport inventory includes PostgREST tables/views/RPCs, auth calls, function invokes, realtime and URLSession images. No app-side Supabase Storage upload/download SDK call was found. Downloaded cover URLs may be Supabase Storage/CDN URLs, but share the image pipeline. `openURL` hands off to an external destination; it is not silently counted as an app database fetch. Apple authentication is a system authorization UI followed by the registered Supabase ID-token exchange.

## Priorities for the execution plan

### C01 — One small list change triggers several broad refreshes

**Source:** `SupabaseService+UserLists.swift:104–116` writes one row, then calls `fetchUserLists`, `fetchCollectionItems` and `fetchCollectionFeed`; anime adds a notification metadata read and throttled upcoming read. `fetchUserLists` performs two sequential table reads at 229/235; collection items calls two page RPCs at `SupabaseService+Collection.swift:92–101`; feed calls a third. `SupabaseService.swift:2550–2564` debounces realtime by 350 ms, then refreshes the same sets after an echoed list change.

**Source-derived request model:** one upsert + five base read boundaries = six possible app requests before anime extras, realtime echoes, image loads and retries. Anime adds one reminder lookup and possibly one upcoming query. This is a conditional call graph, not measured per-action traffic. In-flight list coalescing can reduce overlap; collection refresh instead cancels/restarts. Under sufficiently separated responses, own-write echoes cause another broad sweep.

**Additional amplification:** `EditorialCollectionView.swift:750–770` status changes call this full path for every selected item, ignore each Bool result, then refresh feed again. `QuickVerdictActionCard.swift:648–671` can add a new completed title, set progress, then set verdict—three writes with repeated full refreshes. `AddToListSheet.swift:142–144` fetches both whole lists just to edit one title. Profile/import paths also refresh state independently.

**Plan:** one typed mutation result should update the normalized in-memory record and invalidate only affected query keys. Coalesce server reconciliation across optimistic mutation, realtime echo and batch work. Add atomic/batched status mutations that preserve rating/notes and return per-item outcomes. Preserve the existing batch-remove improvement: skipRefresh at `UserLists:318–349` and one final refresh at `EditorialCollectionView:784–794` already avoid per-item refresh.

**Acceptance:** instrument one save, ten rapid increments, twenty-item batch and import; record outgoing requests/rows/bytes and duplicate invalidations. Use a single canonical mutation contract, not per-screen parallel implementations. Fix rating correctness before measuring perceived speed.

### C02 — Whole-list reads are not actually a scalable full-library contract

**Source:** `UserLists:229–238` uses `.select()` with user equality, no order, limit or pagination. In-flight coalescing at 183–194 is useful but has no TTL and does not guarantee completeness above a server response cap. App-derived membership/progress caches depend on these rows. Do not claim a particular hosted cap without root's configuration check.

Collection UI separately loads 90 card rows (`Collection:144`, `:408`), then searches/sorts/counts only loaded cards (`EditorialCollectionView:96–178`, `:666–707`) and disables its pagination sentinel while searchResults exists (`:633`). These are distinct gaps: raw list completeness and card-query global scope.

**Plan:** explicitly paginated lightweight tracking records, global server-filtered collection search/sort/counts, stable media-type-aware identity and complete import/export. Cache a single normalized library state and keep a selected view/page separate. Do not solve global search by eagerly downloading every full catalogue detail.

### C03 — Account transitions need cache and task isolation

**Source:** `SupabaseService.swift:861–885` clears visible lists/collections but not `collectionAnimeIds`, `collectionMangaIds`, `userListByTypeAndId`, `userIdsByTypeAndStatus`, outstanding list/collection/upcoming tasks, upcoming throttle/backoff, or several user-derived caches. Derived lookup state is defined at 293–296 and normally rebuilt by list fetch. `fetchUserLists` may let a new caller await an older user's in-flight task (`UserLists:183–195`); the implementation captures a user ID, then later commits results without an account generation check (`:198–292`).

Discover bundle cache key contains only limit/hours (`SupabaseService:1450`) while the bundle has user-sensitive New to You semantics. It is not cleared by resetUserState. Similar user-scoped cache ownership concerns in delegated services need reconciliation with that lane.

**Risk:** stale badges/state from a previous account and late results repopulating reset state; no cross-account runtime incident was reproduced. RLS can protect server data access while stale local state remains incorrect.

**Plan:** account/session generation token, account-keyed caches, cancellation/invalidation at logout and account change, rebuilding all derived indexes on reset, and post-await generation checks before mutation of shared state. Keep public image/catalogue caches reusable where appropriate.

### C04 — Collection cancellation guards do not cover rollback or loading state

**Source:** refresh calls cancel the old task and immediately start another (`Collection:10–43`). Page success checks generation/cancellation (`:411–415`, `:445–449`, `:478–482`), which is good. But an old task's catch unconditionally calls `restoreCollectionSnapshot` (`:102–109`, `:147–152`). That snapshot restores both type arrays and feed/cursors (`:156–172`), so stale cancellation/failure can overwrite newer results or the other concurrent collection path. Both implementations also share `isCollectionLoading` and unconditionally clear it in defer (`:67–69`, `:115–117`).

**Plan:** generation-check success, failure, rollback and loading cleanup; scope snapshots to their query state. Coalesce identical active refreshes; cancel only genuinely superseded query keys. Verify rapid status changes with deliberately delayed A/B responses and cancellation during bootstrap.

### C05 — Search debounce exists; response identity protection does not

**Source:** `EditorialSearchView:179–215` cancels a 300 ms task before starting a reset. The service stores query/filter/cursor/results globally. Page methods guard shared `isSearching`, await results, then append without query generation validation (`SupabaseService:1133–1267`). Reset can change the query while an old page is active; the new fetch may return early because isSearching remains true, and old results/cursors can append to reset state. There is no onDisappear cancellation of searchTask in that view. Combined anime+manga requests are sequential (`:1217–1248`). `refreshSearch` resets cursors before requests and restores old arrays/hasMore on error but not old cursors (`:1270–1380`).

**Plan:** immutable search key including persistent Anime/Manga mode and all filters; generation-checked results/cursors; cancellation through the request path; independent per-query loading; typed error versus empty. Parallelize independent combined queries only if combined mode remains intentional—approved product direction now prefers persistent Anime/Manga selection.

**Acceptance:** typing A→B, changing type/filter while A is delayed, closing/reopening search, refresh failure after several pages; only current-query rows append, pagination neither duplicates nor stalls.

### C06 — Initial page mounting and forced refresh cause avoidable work

**Source:** bootstrap starts two list reads, two collection-type reads, one feed read and one upcoming read (`SupabaseService:927–934`) independently of the first screen. ContentView warms Discover (`:364–368`), Discover's own first task forces the bundle (`EditorialDiscoverView:382–387`, `:439–441`), and discovers daily feature plus list refresh. In-flight bundle sharing limits simultaneous duplicates, but a completed parent warmup is bypassed by force=true. Default Discover also mounts immediate neighbors—Taste/Concierge and Browse—because `ContentView:578–596` mounts distance<=1. `mountedSections` retains every visited page; despite its comment, previously visited distant pages remain mounted. Browse starts its initial network request on mount (`BrowseView:307–311`), and Taste/Concierge have their own startup calls.

`AuthView:97`, `:592` loads twelve trending full-model anime even when the normal welcome uses only the bundled mountain asset; those covers serve the retained debug Genie scene. Removing this unnecessary data fetch need not alter the approved welcome artwork/composition.

**Plan:** critical-path Home data only; activation-aware side-page loading; reuse fresh bundle on first render and reserve force for intentional refresh; defer background prefetch by measured value and connectivity. Keep top swipe navigation; activation is independent of layout mounting. Retain the exact approved mountain welcome, not a new welcome design.

**Acceptance:** cold/warm/restored login request waterfall, first useful paint and main-thread work measured separately. SDK session lookups are conditional requests, not automatically additional HTTP. Restore currently waits for profile upsert before releasing the auth bootstrapping gate (`SupabaseService:572–582`); assess this dependency.

### C07 — Reconnect can spend a request without updating the visible Discover model

**Source:** `ContentView:401–411` reconnect calls `fetchDiscoverBundle(force:true)` and discards its return. Discover renders view-model arrays populated only inside `refreshSections` (`EditorialDiscoverView:451–490`). The service caches that result but does not publish it into those arrays. On Collection reconnect, root fetches status:nil rather than the selected view filter.

**Plan:** reconnect invalidates/refreshes the owning active query controller, with that screen's full query key. Do not duplicate a low-level fetch in the navigation shell. Test visible recovery after offline initial load and after a filtered Collection reconnect.

### C08 — Detail pages are bounded, but repeated subqueries and failure fanout remain

**Positive:** full detail fetch is ID+limit1; memory/disk fallback exists (`SupabaseService:1492–1562`). Tags use one projected nested query rather than one request per tag. Similar IDs are fetched with a max 50 RPC, normally 14, and batch-hydrated rather than normally fetched N+1 (`Recommendations:40–94`).

**Risks:** detail memory cache has no TTL or per-key in-flight sharing. Recommendation batch writes bypass the nominal 200 cache cap (`Recommendations:89–92`, `:144–147`). A missing/failed batch falls back to unrestricted parallel per-ID tasks (`:99–111`, `:154–166`): normally 14 or max 50 extra requests precisely when the service may be failing. Genre fallback can add another query.

Anime detail requests tags/similar/ladder concurrently (`AnimeDetailView:207–220`), plus flag-gated credits, preview episodes and dock links. Episode preview fetches 10 rows while rendering just the next row (`:967–979`, `:1005`). Dock re-fetches an episode link and title links on every progress change (`:1528`, `:1621–1626`). Manga's chapter preview task sequentially loads chapters, status and legal links (`MangaDetailView:693–696`), while its dock separately fetches the same title's legal links (`:1389`). `fetchExternalLinks` has no cache or in-flight coalescing (`UserLists:526–542`).

**Plan:** shared detail query state; TTL/in-flight coalescing by media type/ID/locale; slim card hydration for recommendations; bounded retry/fallback concurrency and distinguish missing rows from failed batch. Load lower sections when useful. Keep detail full-row reads where actually justified. A detail bundle is optional after measurement, not a mandate to create another giant endpoint.

### C09 — Errors becoming empty pages produce false exhaustion

**Source:** Browse service catches and returns [] (`Browse:42–47`, `:83–88`); view sets hasMore from count and only calls initial failure an error if the network monitor says offline (`BrowseView:393–410`, `:454–480`). Connected server/decode failures can look like valid empty data. Episode/chapter page methods likewise return[] on error (`UserLists:565–616`); sheets set hasMore=false (`AnimeDetailView:1334–1338`, `MangaDetailView:1028–1032`).

**Positive:** keyset Browse uses capped at 120 (view 60), 120 ms debounce, generation guards and cancel-on-disappear. Collection keyset pages are capped at 120 (feed 90/type 80). Shared sentinel triggers at most once per count (`KuroLoadMoreSentinel:39–49`), so it avoids repeated onAppear flooding.

**Plan:** typed page result separating success-empty, cancellation and failure; retry affordance retaining cursor/items. Sentinel should be able to retry a failed page even if item count has not changed. Keyset-by-number is preferable for mutable long chapter/episode sequences. No autonomous endless database pagination loop was established; errors more often falsely end or stall it.

### C10 — Genre detail pays six broad queries per refresh

**Source:** `GenreHubView:164–210` concurrently requests five rails plus tag facets whenever mounted or media kind changes (`:83–87`). Four rails each fetch 30 full rows, New to You fetches 300 anime/350 manga candidates to return 30, and tags fetch 200 parents with nested edges. No cache, generation token or cancellation for rapid mode changes; shared facets may be overwritten by older work. Full-model `.select()` rail helpers are at `SupabaseService:1570–1878`; nested tag sample projections at 2005/2051.

**Plan:** bounded projected genre cards + server exclusion/qualified facets, reuse fresh per-genre/type results, and generation protection. Do not confuse concurrent queries with zero cost; parallelism improves elapsed time while retaining transfer/DB cost. Legacy helpers with no current view consumers should be marked dormant, not attributed to every app launch.

### C11 — Image pipeline has good bounds but cancellation and sizing holes

**Positive:** `ImagePipeline:20–28` defines 80 MB memory, 40 in-flight and 12 prefetch fanout; URL-key dedupe; 20 s timeout; URLCache configured with 64 MB memory/256 MB disk by `KuroApp:20–22`; decoded detail disk cache caps 300 files separately. Most image surfaces share this path. Legacy `PosterView:16` uses AsyncImage, but only Preview callers were found, so don't claim it is a live screen bottleneck.

**Risks:** `ImagePipeline:84–88` waits while all slots are used, swallows sleep cancellation and never checks Task.isCancelled. A canceled waiter can keep yielding/spinning until a slot frees and still start a request. Shared load tasks have no consumer-aware cancellation. Cache/in-flight key is URL only, omitting desired decode size (`:19–20`, `:53–76`); a low-resolution first consumer can supply a later hero. `clampPixelSize(nil)` returns nil (`:135–144`), and Discover/Browse/Collection prefetch omit maxPixelSize, so those prefetches decode the original image instead of applying the 1200 px cap. This means downsampling controls exist but do not cover every path. No response byte budget is enforced before full download. `KuroCachedAsyncImage:54–79` writes phase after awaiting without cancellation or URL-generation validation.

**Plan:** cancellation-aware bounded scheduler, default decode target for all callers, resolution-aware cache strategy (or safely upgrade cached images), explicit viewport prefetch budget, off-main bounded decode, and HTTP/cache freshness policy appropriate for immutable image URLs. Measure decoded pixels/bytes and canceled work, not just request count.

### C12 — Taste retries are not bounded by the stated retry count

**Source:** `TasteDeckView:183–220` launches a Task for each signal; failed rows remain pending even after failures>=3, which merely sets a banner. Every later commit/appear retries the whole pending batch; no queue length cap or time-based retry backoff is present. `isFlushingSignals` prevents overlapping queue flushes, but a concurrent new signal skips waiting for the current flush and then sends its own write. Undo records another asynchronous signal. This risks increasing work during outages and out-of-order state; server idempotency/order contract belongs to the companion lane.

**Positive:** batch fetch itself has isFetchingBatch/batchExhausted guards, 12-row requests and local dealt-key dedupe (`:254–275`). There is no evidence of a fetch-every-frame loop. Endless means user-driven replenishment, not automatically exhausting the catalogue.

**Plan:** per-title ordered, bounded signal delivery; retract/supersession semantics; bounded retry policy and outage backoff. Preserve an optional Taste tool; do not add obligatory training to login. Companion audit should reconcile endpoint cost and retry semantics.

### C13 — Telemetry flush can launch 200 individual inserts

**Source:** `ConciergeAnalytics:19–20` caps offline queue at 200; `:73–81` drains it by calling one detached-style fire-and-forget Task per row; each inserts at 93–95. Reconnect triggers flush in `KuroApp:116–119`. No concurrency cap, bulk insert or persistent retry; failed sends are discarded. Queued rows capture user_id before account changes, and setUserId does not clear/isolate the queue (`:36–39`). Outbound-link logging is one non-blocking RPC per tap (`SupabaseService+Monetization:12–31`), with no affiliate flag guard in that method; this ledger is not proof of monetized links or partner approval.

**Plan:** small bounded batches, backpressure, account-scoped queue, explicit retention/drop policy and privacy preference alignment. Approved product direction keeps social club-only and profile activity opt-in; telemetry must not silently create a social activity feed. Do not make core navigation wait for logging.

### C14 — Retry/cancellation and feature flag freshness policy needs consolidation

**Source:** `SupabaseService:218–245` retries only URLError, at most 3 total attempts, with 500/1000 ms waits—finite, useful bounds. It does not explicitly exclude canceled requests from eligible URLError categories; however, a canceled parent task will normally terminate at the throwing retry sleep, so this is a policy gap rather than proof that cancellation always retries. Shared unstructured parse/recommend/bundle tasks do not automatically cancel when an individual awaiting view disappears. Mutating apply/undo do not get that automatic retry, a useful safety property.

`FeatureFlags:56–100` has 4 attempts separated by 10/30/60 s; sleep uses try? and no cancellation check. Multiple refreshes have no coalescing/TTL despite lastFetchDate being recorded. Cached flags survive network failure, appropriate for resilience but without age visibility. Bootstrap launches flag refresh without awaiting it, then immediately tests the cached provider flag (`SupabaseService:939–950`), so a fresh flag change may not trigger provider bootstrap until another path runs.

**Plan:** one explicit policy for cancellation, finite transient retries, request sharing and stale-cache age. Coalesced flags refresh with observable generation; feature data activation reacts to resolved flags. Do not blindly retry writes or add a universal blocking refresh on foreground.

### C15 — Auth validation and profile work are bounded but tied to unrelated work

**Source:** signup email check is 500 ms debounced and cancellation-checked (`AuthView:535–553`); service returns false for failed check (`SupabaseService:709–718`), which can appear “available” rather than “check unavailable.” Profile upsert writes adult_opt_in=false each restore/login (`:909–918`), not merely insert-if-missing; root should assess intended preference semantics. Auth session property reads may be local; isAppleUser uses an actual user fetch (`:795`) only on explicit delete flow. No unbounded auth polling found.

**Plan:** retain approved auth mountain design, eliminate unused welcome network dependency, make validation failure distinct, and avoid requiring unrelated catalogue/collection completion to establish a usable authenticated screen. Functional auth state fixes from the approved-reference review remain separate from visual redesign.

## Modularity and approved screen direction

The existing extensions, `@Observable` and SwiftUI are the right foundation. Do not introduce parallel data stores or replace the stack. `SupabaseService.swift` is 2972 lines combining authentication, caching, legacy browse/search, Concierge transport, realtime and state; extraction into files alone has not separated lifecycle ownership.

Execution should introduce small, testable query/mutation ownership boundaries on that stack:

1. Session/account scope: auth identity, generation and teardown.
2. Catalogue queries: explicit card/detail projections, media-aware keys, per-key cache/in-flight state, cancellation.
3. Collection state: normalized tracking records, named shelf membership separate from status, mutation reconciliation and one invalidation coordinator.
4. Screen query controllers: Home distinct from Discover; Discover owns search/Browse; persistent Anime/Manga mode is in every relevant key; top swipe navigation only activates useful work.
5. Delivery policies: image scheduling, bounded analytics and Taste queues; independent of navigation rendering.

Club-only social and opt-in profile activity require server/privacy policy work in the companion lane. Removing unconsumed social count prefetch from general pages may save requests, but do not remove useful club context without the agreed scope. Auth animation is confined to the approved welcome; none of these performance proposals requires moving its headline or replacing artwork.

## Safe or bounded cases to retain

- ID-specific full detail fetches, deliberate explicit mutation requests, user-filtered realtime registration, finite retry counts.
- Search card RPC max 50, Browse/Collection max 120 and proper keyset cursor components; do not replace these with global catalogue downloads.
- Existing per-key Discover/Concierge in-flight coalescing and TTLs, while fixing account/query identity and invalidation.
- Upcoming 20 s cooldown, exponential failure backoff and 500-row bound; countdown Timer updates local strings every 60 s and does **not** query the server.
- Batch recommendation hydration and 200-ID export title chunks on the normal path; not universally N+1. Fix only the failure fallback and media-type identity issues.
- Batch remove already refreshes once; structured profile import preview caching avoids re-downloading the same snapshot on confirmation. Fidelity/caps are a separate data contract problem.
- Apple Foundation Models work is on-device, not an HTTP endpoint. It still affects task latency; do not put it into database-request totals.
- Dormant methods: legacy searchContent, offset Browse helpers, several older rail helpers and Preview-only PosterView should be documented/removed only after reachability checks, not charged against live use by assumption.

## Validation gates, not invented performance results

No request trace, byte count, latency percentile, memory profile, SQL execution plan or end-to-end save was captured in this audit. Root's hosted SQL/cron/worker review is complementary; a capped client query may still execute an expensive plan, and an RPC's returned row count does not reveal its internal cost.

Before changes, instrument request name, safe query-key hash, trigger/screen, cold/cache/coalesced status, duration, bytes, returned rows, retry index and cancellation. Avoid credentials, emails, notes and raw import text. Capture cold/warm startup; ten page swipes; repeated detail visits; typing/scope races; a collection larger than server row caps; twenty-item batch; offline/reconnect; rapid account switch; five minutes of fast Taste judgments; image-heavy scrolling.

For each work package set a measured baseline and explicit budget: request count per action, first useful content, p50/p95 latency, transferred bytes, peak decode memory and canceled work. Proposed correctness gates: no late prior-account writes to UI state; no stale-query append/rollback; no silent page exhaustion on failure; bounded retry and queue lengths; ratings/notes preserved; one coherent collection update per confirmed action. No statement here says these gates currently pass.

Inventory verification: all 381 IDs are unique, all file/line references are in range, and all 93 source hashes still matched at final verification. Forty-eight files contain registered boundaries or consumers; remaining files are accounted for in the coverage inventory. No repository files changed in this audit.
