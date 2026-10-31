# Kuro social, clubs, availability, import and taste client-call audit

2026-09-26. Read-only local source inspection. Scope: `Kuro/Services/SupabaseService+Clubs.swift`, `+ClubRealtime.swift`, `+Social.swift`, `+Streaming.swift`, `+Concierge.swift`, `+Taste.swift`, plus callers needed to understand lifecycle. No hosted query, app execution, deployment or code edit. Source risks below are not measured production costs, traffic, latency or privacy incidents. Paths are relative to `/Users/max/Kuro-Anime-App`.

## Complete register

`evidence/social-call-register.csv` enumerates **55 sites**: **47 request sites** (33 RPC, 13 PostgREST SELECT, one Edge Function POST) and eight realtime configuration/lifecycle sites (channel, five stream declarations, subscribe, unsubscribe). A realtime stream declaration is not an independent database query. Each row records file/line, enclosing function, method, endpoint, read/write classification, projection, bounds, pagination, repeat/cache behavior and assessment. Every literal `.from`, `.rpc`, `.functions.invoke`, channel/change/subscribe/unsubscribe occurrence in the six assigned files is included. There are no direct auth or storage calls in these files. Caller locations are retained in `/tmp/kuro-social-callers.txt` (includes some irrelevant encode matches; register is manually classified).

RPC results have no client-side column projection. Client limit parameters describe requested bounds, not proof of server-enforced bounds. RLS and deployed RPC definitions require the separate backend audit. Most writes are explicit user actions; two enrichment enqueue paths also write while browsing.

## Highest-value findings

### 1. Club realtime can refresh a whole bundle for unrelated delivered changes

`+ClubRealtime.swift:21–47` configures five AnyAction streams. Only `club_polls` and `club_messages` have `club_id` filters. `club_rail_items`, `club_votes`, `club_rail_item_reactions` have no client table filter. All five schedule a forced full `refreshClubBundle` after 500ms (`:107–114`). RLS/publication rules can limit events; source alone does not prove whole-table traffic reaches this client.

One relevant reaction can therefore cause a nested club bundle read rather than an isolated reaction update. Multiple events inside500ms coalesce; events spaced farther apart can each cause a refresh. Own vote already explicitly refreshes (`ClubDetailView.swift:433–434`), and own realtime event can schedule another. Club chat request methods have no current external Swift callers, but its message stream still causes refreshes.

Positive: feature guard, same-club guard, one service-owned channel, listener cancellation, debounce cancellation and unsubscribe exist (`+ClubRealtime.swift:12–17`, `:92–103`). Detail subscribes after load and unsubscribes on disappearance (`ClubDetailView.swift:145–164`). No explicit scene-background suspension appears in that view. A failed subscribe leaves `clubRealtimeSubscribedId` set because catch only logs (`+ClubRealtime.swift:16`, `:83–89`); a same-club retry can be skipped until cleanup.

**Planning decision:** retain club-only social, scope invalidation to the active club and changed resource, and make a single owned observation/lifecycle controller. Do not remove the top swipe interaction to solve request ownership. Measure delivered-event count, refresh ratio, payload bytes and concurrent channels before sizing savings.

### 2. Realtime refresh may not update the displayed club state

`ClubDetailView.swift:36` owns a local `@State bundle`, populated by its own `loadBundle` (`:365–401`). Realtime refresh updates `SupabaseService.clubBundleCache` (`+Clubs.swift:297–298`) and discards the returned bundle (`+ClubRealtime.swift:113`). No ClubDetail `.onChange`/subscription consuming that cache change was found. This is a source integration risk: paid-for refresh work can fail to affect the visible view. Runtime verification must establish actual observation behavior. Use one published/readable club state source or explicitly deliver refreshed data to the view.

### 3. Club opening deliberately makes a lightweight and a full request

Initial `loadBundle` starts an unstructured loading-snapshot task (`ClubDetailView.swift:368–373`) and awaits full `fetchClubBundle` (`:376`). Even a full-bundle cache hit does not suppress the loading-snapshot RPC. The snapshot has no service cache/dedup. Full bundle has a good300s TTL and per-club inflight map (`+Clubs.swift:276–299`); force refresh bypasses TTL but still joins an inflight request.

`fetchMyClubs` has no TTL/inflight and catches any error from `fetch_my_clubs_loading` by calling `fetch_my_clubs_enriched` (`+Clubs.swift:188–207`). Callers: Clubs initial/foreground/pull (`ClubsView.swift:46–78`), Profile task (`ProfileView.swift:74–76`), title detail when empty (`ClubActivitySection.swift:71–75`), add-to-club sheet and create/join/leave. Empty membership is not distinguished from never loaded in the title-detail guard, so zero-club users can requery on each title opening. The fallback may be compatibility support; do not remove it blindly, but narrow fallback triggers to known capability mismatch and cache successful empty results.

### 4. Availability detail refresh repeats the same status read

Anime `refreshLinks` (`AnimeDetailView.swift:1628–1648`) calls status, V2 batch for one title, and `enqueueAvailabilityRefreshIfStale`. That helper calls status again (`+Streaming.swift:236`), then queues if absent or >=30days stale, then the view calls status a third time if queued. Manga mirrors this at `MangaDetailView.swift:1395–1415`.

When flag enabled and not within successful-enqueue cooldown, this branch alone requests **3 reads for a fresh title** (status twice + V2) or **4 reads +1 enqueue write for a queued title** (status three times +V2). The legal-watch/episode-link reads preceding these are outside this partition. These are source-path counts, not observed requests. Anime ties refresh to progress (`AnimeDetailView.swift:1528–1529`), so +1 progress can repeat the path; manga uses title ID (`MangaDetailView.swift:1298`).

Good: ten-minute enqueue cooldown after successful write (`+Streaming.swift:230–233`, `:257`), stale threshold, and flag checks in callers. Gap: fresh/no-op status is not cached, status is not passed into the enqueue helper, and no inflight sharing. Prefer one availability state query with freshness metadata, and reuse its result when deciding whether to enqueue.

### 5. “Cache” often stores results without avoiding future requests

- Provider V2 (`+Streaming.swift:147–179`) always calls backend for supplied items, then fills caches; no TTL, cache-hit filtering or request dedup. Its key is media type/id even though results depend on audio/subtitle/includeUnknown parameters; proposed persistent Anime/Manga scope and language preferences need explicit cache keys.
- `prefetchProviders` similarly reissues the entire batch (`:200–223`). Collection starts V2 and legacy provider prefetch for the same feed items under the streaming flag (`EditorialCollectionView.swift:739–745`), up to80 passed by callers. Both write `providerCache`, so parallel completion order also deserves validation.
- Friend-count cache stores only returned rows (`+Social.swift:104–110`) without TTL or cache-hit filtering. Missing rows are not explicitly set to zero, so a formerly nonzero count may remain stale unless cleared elsewhere.
- Club shared-provider fetch always runs; it writes a cache but does not consult it (`+Streaming.swift:374–399`).

Each prefetch family has one global task slot. New calls cancel prior tasks for the whole family, not a title/scope key (`+Social.swift:95`; `+Streaming.swift:188`, `:201`). This helps suppress obsolete work but different mounted surfaces can cancel each other. Cancellation may not reverse server work already issued. V2 lacks the post-response cancellation guard present in the legacy/friend implementations.

### 6. Invisible work is relevant with the retained swipe navigation

`ContentView.swift:575–600` mounts current page and immediate neighbors, and also any previously mounted page (`distance<=1 || mountedSections.contains`). Consequently mount/`.task` does not mean selected/visible. At default Discover, adjacent Taste and Browse may load. Later, mounted Clubs can receive foreground notifications while not the selected page; its handler fetches clubs then checks notifications (`ClubsView.swift:75–79`). This is a source risk, not measured SwiftUI lifecycle execution.

Taste fetches12 on appearance, refills when queue<=3 (`TasteDeckView.swift:68`, `:133–152`, `:244–257`), with inflight and exhausted guards. These bounds are good. A new Home separate from Discover should explicitly pass active surface + persistent media scope to data loaders, preserving swipe/neighbor views while avoiding unnecessary requests. Do not assume unmounting or tab-bar replacement is required.

### 7. Some batched social work has no visible consumer

Collection prefetches friend counts (`EditorialCollectionView.swift:734–735`) but its custom grid/list components do not read friend counts. Shared catalog cards do, under the social flag. Discover prefetch includes up to100 concatenated titles before deduplication (`EditorialDiscoverView.swift:561–571`) and omits explicit daily-feature/AiringToday/BecauseYou/Shelf/HiddenGem IDs unless they overlap other rails. Batch reads are preferable to per-card calls; the next step is visible-ID dedup and matching consumers, not additional per-card RPCs.

Under club-only friends and activity opt-in direction, keep identity/profile available without fetching activity implicitly. Gate social counts/activity at consent and visibility boundaries as well as global rollout. Existing service methods themselves generally rely on caller gates.

### 8. Detail credits overfetch relative to initial display; entity works are unpaged

Five forward-join requests (`+Clubs.swift:488`, `:511`, `:534`, `:557`, `:580`) filter one media ID and use explicit projections, but fetch all matching entities including descriptions; no limit/order. Detail executes them only under credits flag (`AnimeDetailView.swift:234–238`, `MangaDetailView.swift:232–235`). Cast initially previews8 and limits displayed selection10 (`CastSection.swift:11–30`); credits curate first2 (`CreditsSection.swift:43`). Full descriptions would be better fetched on entity detail when needed if payload measurement justifies it.

Reverse entity-work queries (`+Clubs.swift:617`, `:645`, `:678`, `:711`, `:718`) have narrow card projections and adult filters, but no stable sort, limit or pagination. Prolific staff/studios can grow. A character sheet issues anime+manga reads in parallel even if future app-wide scope is one type. Good:120s TTL, approximate50-key trim, and source-card mapping; forward joins also cache successful empty results and approximately100 keys. No inflight dedup for these entity requests.

### 9. Enrichment writes happen during discovery

`prefetchMediaRelationRefreshRequests` dedups, caps12 and sends serial enqueue RPCs in an unowned Task (`+Clubs.swift:810–831`). Discover supplies hero +4 current-season +4 trending +4 manga candidates (`EditorialDiscoverView.swift:575–588`), Concierge supplies8 recommendation candidates (`ConciergeView.swift:1086–1093`). Per-key12h cooldown begins after successful enqueue (`+Clubs.swift:775–792`) and is session-local. This prefetch path does not test current ladder strength; detail's `enqueue...IfNeeded` does (`:800–807`). Good cap and cooldown, but cold sessions can issue up to12 queue writes merely from Discover load. Backend idempotency/dedup and downstream execution cost belong in the live audit; do not call these12 upstream provider refreshes without evidence.

### 10. Taste retry count is not a hard retry limit

Local model retains failed pending signals after failure count3 and merely shows a warning (`TasteDeckView.swift:195–222`); future commits/appearances can retry them again. The queue is memory-only and not user/scope-keyed. Good: batch fetch inflight guard,12-item result request, error distinct from exhaustion, explicit retry UI and undo. Recommendation: bounded delivery policy and identity/scope reset in a Taste data controller; do not change optional taste into mandatory setup. Local source improvements differ from approved welcome reference, as earlier comparison documented.

### 11. Profile and auth boundary responsibilities need clearer ownership

Profile currently warms clubs on appearance and, under availability flag, sequentially reads service registry, user subscriptions and operational queue aggregate (`ProfileView.swift:74–79`, `:337–343`). Bootstrap also loads registry/preferences (`SupabaseService.swift:944–949`). Registry/realm metadata are small-catalog cache candidates, not proven large costs. In proposed identity-first Profile, place operational diagnostics behind diagnostics and fetch social activity only on opt-in/action.

`+Clubs.swift:246` defaults new clubs to sharing `status`; this differs from a future identity-only/activity-opt-in policy and requires an explicit product/migration plan, not a label change. Base `resetUserState` (`SupabaseService.swift:861–880`) clears lists/entity caches but does not visibly clear `myClubs`, club bundle/inflight maps, friend counts or streaming preferences. Assigned extensions do not add identity reset. Sign-out calls `stopRealtimeSubscriptions`, whose body at `SupabaseService.swift:2567–2577` stops only the separate `realtimeChannel`/`realtimeListenTasks`, not `clubRealtimeChannel`; club cleanup is delegated to detail disappearance. Parent/client owner should verify service lifetime and central cleanup before concluding anything cross-account; this audit does not demonstrate a leak. Global notification/per-club seen timestamps are not keyed by user in `+Clubs.swift:212`, `:406`.

### 12. Import is bounded and reuses preview work

One shared Edge POST at `+Concierge.swift:123`, used by preview and import modes. `maxItems` is clamped25..400 (`:106`), default200. Coordinator passes preview text to confirmation (`ConciergeAniListImportCoordinator.swift:81–82`, `:103–108`) so backend can reuse parsed input. This endpoint returns import text; actual list application is another flow, so CSV labels this read/orchestration, not a direct list-write claim. Service spawns an unstructured Task and awaits it (`+Concierge.swift:119–125`); cancellation propagation on dismissal is not explicitly wired. Avoid duplicating import logic for Anime/Manga/Home; pass persistent scope while allowing an explicit “both” import choice if desired.

## Request bundles worth measuring

| Interaction | Source-derived request shape in this partition | Good boundary / unresolved part |
|---|---|---|
| Open club first time | Loading snapshot + full bundle; optional shared-provider RPC + provider batch; realtime subscription | Full bundle cache may eliminate its read; snapshot still launches; server bounds unknown |
| Vote | One mutation + explicit full refresh + possible realtime-triggered refresh | Per-poll inflight/optimistic UI good; measure duplication |
| Open anime credits cold | Characters + staff + studios | Flagged; cache avoids repeats; unbounded entity count |
| Open manga credits cold | Characters + authors | Same |
| Open entity works cold | One SELECT; character two SELECTs |120s TTL; no paging |
| Submit/delete title comment | One mutation + full title activity read | Explicit action; delete reload also occurs after failure |
| React to title comment | One toggle + full title activity read | No per-comment inflight suppression in current caller |
| Collection metadata warmup | Count batch; if availability on V2 batch + legacy provider batch | Up to80 passed; visibility/consumer overlap unresolved |
| Show Leanings | Profile RPC + realm table SELECT in parallel | Per-sheet didLoad guard; service has no TTL |
| Preview + confirm AniList | Same function endpoint once per step | Cached text and cap; downstream apply excluded |

## Modularity for the future plan

Keep the current observable pattern and top swipe. These are responsibility boundaries for incremental extraction, not a proposal to replace the backend stack or create parallel systems:

1. **App scope/session owner:** persistent Anime/Manga, selected Home/Discover/etc., identity epoch, opt-in privacy; cancels/clears user-scoped work on identity change. Visual neighbor mounting must not imply request eligibility.
2. **Club data owner:** membership list, detail snapshot/full data, mutations, targeted invalidation, one realtime lifecycle. Shared state must drive both detail and previews. Friends remain derived from club permissions.
3. **Title social owner:** permission-aware friend activity/comments/count batches with visible-ID dedup and scoped TTL. Treat “tracking,” “completed,” and progress as different data, respecting opt-in.
4. **Availability owner:** one consistent cache key including media type/region/language semantics, status+providers contract, stale enqueue decision and bounded background maintenance. Do not expose operations aggregates as default profile content.
5. **Catalog people/relations owner:** move entity/ladder methods out of the already large Clubs extension; retain shared cache implementation, add paging only where needed. This is separation by responsibility, not redundant services.
6. **Taste owner:** bounded batches/signals/retries/profile metadata, active-surface and media-scope aware; shared by Home/Discover without independent duplicate warmups.
7. **Import coordinator:** keep preview/reconcile/apply/undo ownership centralized and explicitly user-triggered. Auth animation remains confined to auth UI, not a reason to refetch data in Home/Profile.

Before implementing: assign request/payload budgets per interaction, verify server result bounds/RLS/idempotency, record actual call counts and bytes for cold/warm/reconnect/rapid-swipe scenarios, and test active-surface/flag-off/identity-change cases. No monetary estimate is justified from this source inventory alone.
