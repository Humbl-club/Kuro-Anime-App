# Kuro — product contract and implementation-plan input

Planning synthesis · 26 September 2026 · No app, database, flags, or canonical documents changed.

This document translates the latest user decisions into implementation contracts. It supersedes the earlier four-destination bottom navigation proposal and the subsequent proposal to carry moving mountains through Home and the rest of the app. Existing research remains the evidence base for usability, scope, reliable progress, release uncertainty, privacy and free-core monetization. Neither earlier mockups nor an old GitHub branch are an implementation baseline.

## 1. Decisions to preserve

| Accepted direction | Consequence for implementation |
|---|---|
| Keep the approved animation on welcome/auth only. | Reuse the exact approved mountain scene and motion as the reference. Do not add living scenery to Home, Collection, Discover, agenda or Clubs. Authentication should feel coherent with welcome without requiring moving art behind every form. |
| Keep quiet top navigation and swipe navigation. | Make destinations understandable and reachable within this pattern. Do not introduce the previously proposed bottom tab bar. Final page count/order remains an explicit design decision. |
| Persist Anime/Manga choice. | One shared selection governs media surfaces and their requests. Changing pages must not reset it. A hidden second medium must not be fetched merely because a view model supports both. |
| Separate Home from Discover. | Home helps resume and notice relevant changes; Discover combines intentional search and browsing. Do not make two copies of editorial discovery. |
| Home contains current watching/reading, relevant updates and recommendations, and club activity. | Resume/progress is the primary action. Recommendations need an honest reason and must respect actual feature availability. Social content comes only through shared Clubs. |
| Collection is a visual shelf, with status and personal named shelves. | Watching/Reading, Planned and Completed are primary. Paused/Dropped can be secondary. Named-shelf membership is independent of tracking status. Preserve whole-library search. |
| Profiles begin with identity; activity is opt-in. | Do not load or expose another person's history by default. Opt-in is constrained by the shared-Club audience, not permission for a public feed. |
| Social relationships flow through shared Clubs only. | No unsolicited followers, public social graph or broad activity feed. Check viewer membership and subject sharing permission on the server. |
| Taste is optional and currently unproven. | Do not require a taste questionnaire or mount its network work at startup to justify the feature. Keep entry discoverable but secondary until measured benefit exists. |
| Audit every database call, costs, modularity and metadata/music. | Account for client, server and background work, not just visible Swift RPC calls. Produce a cost model from observed workloads and current billing inputs; do not invent savings. |
| Core utility stays free. | Tracking, discovery, history, import/export and correction must not acquire paywalls or monetization friction. Partner commerce and any sponsored content remain optional, useful and disclosed under the existing research constraints. |

## 2. Questions that remain design or implementation choices

These are decisions to resolve in the detailed plan, not reasons to stop the audit.

- **Navigation:** Home is a distinct destination, while search/browse belong to Discover. Decide the exact top-navigation order, initial page, treatment of an existing Browse deep link, and whether Taste is an auxiliary entry. Do not silently treat a new four-page map as approved.
- **Scope persistence:** propose a per-account preference on this device, with an explicit default for a new account. Cross-device syncing is a separate choice; logging out must not expose another account's personal cached state.
- **Library search:** propose search across all statuses, shelves and loaded/unloaded records of the selected medium. Provide a clearly labelled, deliberate way to search both media if desired. Confirm whether the user's phrase “whole library” instead requires both media by default; either way scope must be visible and the query intentional.
- **Named shelves:** establish private-by-default ownership, ordering, limits and mixed-media behavior. Shelf membership should be possible in several shelves at once unless the user chooses otherwise. Renaming or deleting a shelf must not delete tracking history.
- **Profile identity:** agree which identity fields exist and which club members may see them. Identity-only does not mean public discovery of every profile. Define progress/comment/activity visibility separately, with conservative defaults.
- **Updates:** define whether this includes a new episode/chapter, official announcement, metadata correction, or club event. These require different provenance and unread semantics. “No known release” cannot mean “no release exists.”
- **Music:** determine whether the goal is opening/ending metadata, performers/composers, soundtrack links, playable previews, or in-app playback. Start with a source/coverage audit; audio playback and external services are separate capabilities and dependencies.
- **Styling and feedback:** cover-derived color, new transitions and haptics are optional proposals to validate, not requirements inferred from the user's liking the welcome animation. Preserve existing monochrome interface rules unless the user explicitly approves a change. Actual cover artwork can retain its original colors.

## 3. Shared data and interaction rules

A screen requests data for its purpose, current account and selected medium. The shared scope must reach the query boundary; filtering a combined response after download does not satisfy the scope requirement. Cache keys include user where applicable, medium, effective filters/status/shelf, sort and cursor. Use separate public metadata and private user-state caches so one person's status cannot leak into another account.

Keep existing data-service patterns and `@Observable`. Establish typed request/response contracts before splitting files. A new Home endpoint is not automatically necessary: first see which existing calls can compose a bounded snapshot, and whether a narrow aggregate operation measurably reduces duplicated work. One HTTP RPC can still perform costly SQL scans, joins, function calls and trigger work.

Cancel obsolete searches and scope requests; also reject stale completions using request identity/generation. Cancellation alone does not guarantee the server stopped work. Coalesce identical in-flight requests, preserve useful cached content through refresh failure, and invalidate the smallest affected section after a mutation. No automatically mounted offscreen page should trigger a full second load just because swiping may reach it later.

The payload shapes below describe information contracts, not approved SQL or endpoint names. Counts, timestamps and freshness fields must have clear semantics. Small display summaries should not hydrate full catalog entities and relations merely to render a card.

## 4. Per-screen contracts

### Welcome and authentication

**User outcome:** understand that Kuro covers anime and manga; create an account or sign in clearly; retain the approved introduction's visual identity.

**Data:** session/auth state, operation status and precise recoverable errors. Terms and Privacy are independently accessible. The actual Apple/email flows remain explicit. No catalog, recommendations, Taste, club activity or user-library fetch is needed before successful authentication. Audit bootstrap after auth separately; it must load only necessary session/profile/flag state and the chosen destination.

**Acceptance:** both account paths work; existing-account switching is obvious; keyboards and errors do not obscure the primary action; reduced-motion behavior keeps a still approved image; no perpetual motion remains active while auth is not visible; no mock Terms text ships as legal content.

### Home

**User outcome:** immediately resume something, see a relevant change and notice shared-club activity without browsing a general catalog.

**Data:** bounded current items `{id, medium, title, cover, progress, knownTotal?, userUpdatedAt}`; relevant updates `{type, titleId?, eventTime?, source, checkedAt, certainty}`; a small recommendation section `{candidate, reason, basis, generatedAt}` when supported; club summaries `{clubId, allowedActivity, unreadState}`. Status/progress and named-shelf membership are separate fields. Unknown total remains unknown.

**Calls:** request only the selected medium's current items and title-related updates. Club identity or general club announcements can be intentionally scope-independent; media activities and rails must obey the selected scope unless labelled otherwise. Reuse cached profile/flags, avoid fetching full user lists for badge decoration, and load later sections only when appropriate. A missing personal recommendation capability yields an honest editorial fallback, not a fabricated “because you liked” claim.

**Acceptance:** cold launch exposes the continuation action before secondary content finishes; an account with no library gets import/find-first-title options; Taste is optional; a progress update immediately reconciles Home and Collection; recommendation failure does not block tracking; no club access means no friend activity; a stale release source produces an uncertainty message, not an empty-day assertion.

### Discover: search and browse

**User outcome:** search directly or browse a coherent selected-medium catalog using useful filters and editorial routes.

**Data:** bounded card summaries plus sort/filter metadata and stable cursors; explicit scoped search results; editorial section identity and short reason. Metadata and availability filters must appear only when their data and enabled capability support the promise.

**Calls:** one effective search/browse request per debounced settled query and filter state; server-side selected-medium filtering; cursor paging; batch decoration for visible result IDs only. Editorial loading must not force both anime and manga rails. Switching medium should cancel/discard old results and use the new scope's cache rather than merge the two.

**Acceptance:** a title beyond the initial page can be found; changing scope or filters resets the cursor; no duplicate/omitted records across page boundaries in a stable dataset; unsupported filters cannot masquerade as reliable; back navigation preserves query, sort and scroll; whole-page search is not confused with filtering one rail.

### Collection

**User outcome:** recognize their own shelf, find any tracked title, update progress quickly, and create an intuitively named shelf without a setup wizard.

**Data:** compact selected-medium list records with cover/title, status, progress, knownTotal?, rating if relevant, updatedAt, membership IDs; personal shelf definitions; a paged result cursor. Label the current status Watching for anime and Reading for manga while keeping one clear underlying state mapping.

**Calls:** selected-medium page/search with explicit status/shelf predicates; lightweight shelf definitions once per relevant invalidation; one mutation for a simple progress change; batched membership/status operations for multiselect. Search must cover unloaded records on the server. Do not fetch the entire collection or providers for every first paint. Remember visual shelf/list preference if the compact alternative remains useful.

**Acceptance:** name-only shelf creation succeeds with clear validation and local optimistic/error handling; adding to a named shelf does not change status; removing from a shelf does not remove from Collection; deleting a shelf preserves records; progress +1 has Undo and respects known bounds without inventing unknown totals; stale or rejected writes reconcile honestly; multiselect does not lose selection on incidental metadata refresh; shelf and status filters are visible, clearable and distinct.

### Updates / agenda (placement to resolve)

**User outcome:** know what is confirmed next for followed titles and what Kuro cannot currently verify.

**Data:** selected-medium, user-relevant events with timestamp/time-zone interpretation, event kind, source and freshness; a separate unscheduled/unknown state. A release date, local availability date and translated chapter publication are different facts.

**Calls:** bounded time-range request over followed title IDs, with server authorization and practical batching; no full global schedule download. Reuse Home's event summaries where semantics match. Refresh on a measured freshness policy, not a countdown-triggered request every second.

**Acceptance:** zero matching events is distinguished from missing or stale source coverage; unknown manga release timing never becomes a guessed recurring date; region/provider claims remain unavailable when the supporting capability is off; an event crossing midnight is shown consistently in the user's time zone. Current schedule scarcity is a product/data prerequisite, not something animation can fix.

### Clubs and profiles

**User outcome:** connect through a deliberately joined group, with identity visible and activity under control.

**Data:** authorized club identity/membership/summary; selected-medium rail entries; activity appropriate to both viewer relationship and subject consent; identity-only profile by default. Expose the permitted information, not a broad payload hidden by UI conditions.

**Calls:** membership bootstrap once as needed; club detail on entry; bounded activity paging and one scoped real-time lifecycle. Do not query activity when disabled or when the viewer has no shared club. A profile visit must not trigger a hidden complete-library fetch. Invalidation must cover leaving a club, member removal and privacy changes, including cached content and active subscriptions.

**Acceptance:** strangers cannot obtain activity by calling endpoints directly; shared-club membership alone does not override activity opt-out; leaving the last shared club revokes access; identity and activity permissions remain separate; private progress stays out of analytics and notifications; multiple shared clubs do not duplicate events; no public social graph appears as incidental implementation scope.

### Title details and optional Taste

**Details data:** a minimal identity/cover/synopsis/status/progress payload first, followed by visible and requested relations, cast/staff, author/studio, credits and external links. Optional music metadata needs stable title/season/episode association and source attribution, not a guessed title match. Avoid eagerly hydrating every nested entity, social section and provider relation on sheet presentation.

**Taste data:** only requested when the user enters the feature or explicitly participates. Explain what an input changes. Treat the current flag state as availability evidence, not proof of recommendation quality.

**Acceptance:** absent credits/music are distinguished from loading errors; alternate titles and duplicate names do not associate the wrong performer or soundtrack; credits and trailers do not autoplay audio; opting out of Taste does not degrade core access; recommendation benefit is evaluated against an editorial/control baseline before promoting it.

## 5. Every-call cost audit: required deliverable

Create an exhaustive request ledger that follows each user or scheduled trigger to its full workload:

`screen / lifecycle / job → service call → HTTP/RPC/function → SQL dependencies / triggers / RLS → optional provider or storage operation`.

Each row needs the owner and source location; trigger and repeat conditions; selected-medium support; authorization boundary; parameters and projection; cache key/TTL/invalidation; cancellation/deduplication; retries and failure behavior; rows returned and (where observable) read; payload/egress; measured duration; call frequency; and whether the work is necessary for visible UI. Flag unmeasured values as unknown.

Include authentication/bootstrap, all catalog/list/detail/search/recommendation calls, import and mutation fan-out, comment and reaction mutations, real-time subscription lifecycle, storage/images, background workers, scheduled imports/enrichment, materialized-view refreshes, analytics writes, feature flags and any third-party AI/provider calls. Separate database cost from storage/egress, Edge Function, real-time, AI, provider and local-compute costs. A local worker can still drive paid hosted work.

Trace representative cold and warm launch, scope switch, page swipe, search typing, scrolling/pagination, refresh, foreground/resume, offline/reconnect, progress update/Undo, bulk status change, named-shelf edit, import and club privacy change. Include repeated actions, retries and cancellation races, not only a happy path.

For each scenario report observed request count, duplicate work, payload size and latency distribution where samples permit. Then model low/expected/high usage using explicit assumptions and actual current billing/rate inputs, distinguishing marginal usage from fixed provisioned resources and included allowances. Do not price a database RPC as if every call had a fixed tariff. Select budgets after baseline measurement; do not fabricate existing p95, user volume or monthly savings.

### Concrete source leads already inspected

- `Kuro/Views/EditorialDiscoverView.swift`: local `selectedMediaType` defaults to `.all`; `refreshSections()` calls `fetchUserLists`, `fetchDailyFeature` and a forced `fetchDiscoverBundle(limit: 30, hours: 24, force: true)`. The response hydrates both anime and manga rails. Follow its conditional recommendations and decoration prefetches through service and SQL layers.
- `Kuro/Views/EditorialCollectionView.swift`: local medium defaults to `.all`; initial/status/refresh/mutation paths can fetch user lists, a mixed feed and metadata. Audit all paths before declaring any duplicates wasteful.
- `Kuro/Services/SupabaseService+Collection.swift`: separate anime/manga paging RPCs already exist; `_fetchCollectionItemsImpl` currently invokes both. The mixed feed is explicitly interleaved. These are useful foundations for a scoped contract, not a reason to create a parallel collection stack.
- `Kuro/Views/BrowseView.swift`: separate anime/manga branches already exist; inspect whether requests, cursor and decoration lifecycle can become the common scope pattern.
- `Kuro/ContentView.swift`: existing quiet pager and lazy mounting are the navigation baseline. Inspect actual mount/lifecycle behavior before attributing background calls to the pager.
- Social and recommendation service extensions are separate source surfaces. Recommendation ID retrieval can be followed by entity hydration or genre fallback; a single apparent feature load is not necessarily one network or SQL operation.

These are source findings and audit leads. They are not a runtime cost benchmark, deployed parity check or proof that all listed paths execute in one session.

## 6. Modularity and metadata work

Refactor around accountable behaviors: shared selected-medium state, feature-owned loading/state, typed query contracts, reusable card summaries, mutation reconciliation and authorized social access. Keep `SupabaseService` compatibility while extracting only boundaries that demonstrably simplify ownership or prevent repeated work. Avoid introducing a second networking stack, competing caches or a generic framework for hypothetical screens.

The metadata audit should inventory fields and relationships actually stored, fetched and displayed for anime and manga separately. For each record type measure population, validity, source, freshness, identity match confidence, null meaning and locale coverage. Include episodes/chapters/volumes, dates, alternative titles, formats, descriptions, covers, external links, relations, people/studios/authors, and music-specific data if present. A populated field is not automatically reliable.

Music should begin with a precise content contract and source feasibility. Opening/ending names and credited artists, soundtrack links and audio playback have different matching, region and rights dependencies. Do not add ingestion, playback or a new provider until this distinction is resolved. Audit whether existing music-related code merely represents a genre or taste label rather than a music catalog capability.

## 7. Plan phases and dependencies

| Phase | Work and exit evidence | Dependencies |
|---|---|---|
| 0. Preserve the current baseline | Record current branch/SHA, dirty work, approved auth reference, enabled flags and existing artifacts. Separate source, local runtime and hosted evidence. Keep research decisions; mark rejected visual alternatives superseded. | None. No branch reset, broad checkout replacement or production writes. |
| 1. Inventory and measure | Complete every-call ledger, scenario traces, schema/metadata/music inventory and cost assumptions. Identify duplication, broad projections, RLS risks, scope leakage and unbounded background work. | Phase 0. Read-only inspection first; instrumentation changes are separately reviewable. |
| 2. Lock behavior and contracts | Resolve navigation order, scope semantics, whole-library search, shelf ownership, update semantics, profile permissions and music definition. Draft typed payloads and measured performance budgets. | Phase 1 findings plus accepted decisions above. No need to redesign all screens. |
| 3. Build shared foundations | Shared scope/persistence, cache isolation, request identity/cancellation/deduplication, narrow selected-medium queries and targeted mutation invalidation. Preserve existing service conventions. | Phase 2 contracts. This must precede new Home data composition. |
| 4. Deliver core journeys | Coherent auth; distinct Home; Discover search+browse; visual Collection and named-shelf operations; honest updates. Ship as small independently reviewable slices with appropriate integration tests. | Phase 3; update UI may need a limited honest state until source coverage improves. |
| 5. Enforce social and deepen metadata | Identity-first profiles, shared-Club/consent authorization and revocation; detail loading boundaries; validated metadata/credit improvements; music capability only if supported by the agreed contract. | Phase 2 privacy/content contracts; Phase 3 shared state. Server privacy protections precede new activity exposure. |
| 6. Validate optional additions | Measure Taste benefit; evaluate optional haptics/transitions/color treatments; validate beneficial partner monetization using earlier research and provider permissions. | Stable core journeys and privacy. No subscription or paywall insertion. |
| 7. Release readiness | Repeat baseline scenarios, quantify actual cost/performance changes, check accessibility and failure modes, update required project documentation and obtain explicit deployment authorization if release is requested. | Completed slices and verified dependencies. Local success is not production proof. |

## 8. Cross-cutting release acceptance

1. **Scope:** a captured Anime session performs no Manga catalog/list/detail work unless the user explicitly asks for cross-scope content; the reverse holds. Intentional scope-independent operations are separately listed.
2. **Persistence:** switching pages, reopening the app, opening details and returning preserves the selected medium; a deep link's target can open without silently changing the global preference unless that behavior is explicitly chosen.
3. **Race safety:** rapidly switching medium, query, status and shelves cannot paint results from an obsolete request or write progress to the wrong title.
4. **Reconciliation:** a successful change appears consistently across relevant screens; rejected writes recover clearly; Undo has defined limits and cannot silently overwrite a newer edit.
5. **Privacy:** direct endpoint tests prove private activity cannot be obtained through UI bypass, stale membership, disabled sharing, cache reuse or real-time continuation.
6. **Completeness:** search finds library entries beyond loaded pages; cursors are scoped correctly; counts disclose their scope; named-shelf deletion leaves tracking/history intact.
7. **Truthfulness:** unknown totals, unavailable providers, missing schedule coverage and editorial recommendation fallbacks are labelled accurately. No guessed release facts or personalization claims.
8. **Efficiency:** every required scenario has a before/after request trace; identified duplicate loads and N+1 decoration paths are resolved or explicitly justified; budget assertions use measured evidence.
9. **Accessibility:** usable type scaling and touch targets, meaningful VoiceOver order/labels, accessible contrast, keyboard-safe auth forms and reduced-motion support. Haptics are supplementary and optional.
10. **Scope discipline:** no app-wide animated mountains, bottom navigation, public social feed, mandatory Taste, unapproved playback or paywall slips in as a dependency. No rollback to an old branch replaces the current working app.
