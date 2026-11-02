# Kuro — current decisions and architecture audit

26 September 2026 · Prepared for Max · Research and planning only

## Read this first

The direction is a quiet personal space for anime and manga, with fast tracking, relevant updates and discovery through deliberately joined clubs. The approved animation belongs to welcome/authentication only. The earlier Home, first-login, agenda, Collection and email mockups were rejected; neither those layouts nor the later moving-mountains Home are an implementation reference.

This update combines the user's latest decisions with seven independent audit lanes: client requests, clubs/social/provider requests, Edge Functions, SQL/schema, operational workers, metadata/music, and the design contract. The complete companion review retains the earlier 2025–2026 market and monetization research, including its source register and access limitations. This is qualitative research, not a representative survey of what “most people” want.

No app code, hosted data, feature flags, schedules, credentials or release state were changed. Existing local AuthView edits remain untouched. Static call-site coverage is not proof of every request a running app makes; device traces and representative query plans remain implementation prerequisites.

## A. Product decisions that now govern the plan

| Decision | Required behavior | Status |
|---|---|---|
| Welcome/authentication | Preserve the owner-selected GitHub welcome, commit `b943e457fd2b611bafa6a52dcbbada417d5b727a`, including the no-TV composition. Carry its animation into authentication only. | Accepted direction; exact form layout still to design |
| Navigation | Retain the top selector and swipe interaction. Launch into Home. Search belongs to Discover. | Accepted; exact destination order and Browse/Concierge transition remain to settle |
| Anime / Manga | Remember one persistent choice and use it in requests, cache keys, labels, progress and discovery. Do not download both media solely to hide one. | Accepted |
| Home | Show current watching/reading, relevant new releases/seasons, club activity, personal recommendations and small useful snippets. | Accepted content; order and first-screen balance still need visual agreement |
| Discover | Find something new through search, browsing, filters and editorial routes. | Accepted; reuse existing useful Browse/Search functionality |
| Collection | Visual shelf, quick progress, clear Watching/Reading, Planned and Completed states; secondary Paused/Dropped; optional personal named shelves. | Accepted direction; shelf mechanics below are proposals |
| Shelf membership | Several shelves may contain one title; deleting a shelf preserves tracking history. Search covers unloaded records too. | Recommended implementation of accepted optional shelves |
| Clubs and profiles | Relationships arise only from shared clubs. Profiles show identity by default; activity appears only when enabled and authorized. | Accepted; identity fields and consent migration need design |
| Taste | Optional and secondary until its usefulness is demonstrated. | No approval to foreground or remove it |
| Detail music | Research season/episode-associated music, metadata and efficient ingestion. | Requested investigation; OP/ED vs soundtrack vs playback unresolved |
| Feedback and color | Satisfying, restrained motion and haptics; investigate cover-derived accents. | Ideas to test; no approval of colored statuses or constant animation |
| Monetization | Keep tracking, discovery, history, import/export and correction free. Useful optional commerce or disclosed partner benefits may be tested. | Accepted constraint; no partner or revenue model approved |

Recommended navigation for review is Home → Discover → Collection → Clubs within the existing top swipe pattern. Taste and Concierge can be secondary Discover tools, but that placement is not yet a final owner decision. Club identity can remain independent of media choice; club title activity should respect the choice or explicitly identify cross-media content.

The Home first-screen proposal is a compact “what changed for you” area beside an immediately available continue/update action. It must not become either a giant discovery poster or a long activity dashboard. Test returning users, an empty account, an imported large library and a person using only manga. The evidence does not establish one universal rail order.

## B. What is built, enabled and still missing

The source stack is SwiftUI with `@Observable` and Supabase PostgreSQL, Edge Functions, Storage and Realtime. No MongoDB implementation was found in the inspected app/backend/scripts. “Manga” is a media domain in the same PostgreSQL system; a separate database is not justified by the request.

| Capability | Evidence | Consequence |
|---|---|---|
| Existing top swipe pager, Discover/Browse/Search, list grid/rows, progress, clubs, title social activity | Current source; 93 app Swift files | Improve ownership and information hierarchy rather than replacing the stack |
| Taste, social and club feature flags | Live snapshot enabled at 100% | Availability is not proof of useful recommendations, correct privacy behavior or installed-client parity |
| Personalized New To You, realm discovery rails, provider availability | Live rollout 0%; provider availability dataset empty in preceding exact-count check | Built/staged; do not promise these to users or enable them blindly |
| Home as a separate personal destination | Proposed, not the current default screen | Requires its own scoped data contract and design |
| Personal named shelves and identity-first member profiles | Additional product work | Status filters and club rails do not already satisfy these requirements |
| Release support | Anime next-airing fields, upcoming query and reminders exist | Existing schedule data is too sparse/stale to promise a complete release calendar |
| Manga next-chapter schedule | No future timestamps in preceding live check; bulk mapping explicitly sets these fields to null | Chapter counts/catalogue rows are not a reliable official release schedule |
| Music song/version/episode model | Not established in current ingestion | Separate source and data model needed, subject to scope and permissions |
| GitHub welcome upload | Exact branch/commit verified in earlier review | Not proof that TestFlight, public App Store or the installed phone contains it |

At 21:14 UTC on 25 September, exact aggregate checks found five future anime next-airing timestamps, none within seven days, no future episode rows, and no manga next-chapter timestamps. These are missing-coverage/freshness signals, not proof nothing is releasing. Later PostgreSQL catalogue estimates differ from those exact counts; they are approximate and have not been substituted for them.

## C. Audit coverage and evidence strength

The evidence folder contains separate CSV registers for the core client, social extensions, Edge Functions, operational scripts and latest definitions of 49 literal iOS RPC names. Registers include request sites, callers, wrappers, external HTTP and subscription setup where relevant. Their totals must not be added together as unique requests or requests per session. Dynamic endpoints and runtime execution are explicitly bounded by each lane's coverage statement.

Read-only hosted inspection collected database metadata, indexes, selected function definitions, performance-advisor results, normalized statement statistics and sanitized cron summaries. Sixteen selected deployed function bodies match the latest local definitions after comments/whitespace normalization. That sample does not establish complete schema, migration checksum, Edge Function or runtime parity.

Evidence labels in the findings below:

- **Observed live:** a current metadata/statistics result, with a timestamp and interpretation limit.
- **Confirmed source:** a call graph or implementation visible in the inspected checkout; activation/runtime effect may be unverified.
- **Risk to reproduce:** a plausible failure requiring a targeted device/integration test.
- **Proposal:** a change and acceptance criterion, not implemented behavior.

## D. Highest-priority findings and decisions

### A01 — A simple list update triggers much more work than its visible change

**Confirmed source.** `SupabaseService+UserLists.swift:109–115` awaits full user-list refresh, separate anime/manga Collection pages and the combined Collection feed after a successful upsert; anime additionally schedules reminders and fetches upcoming titles. The full-list path at lines 232–243 reads both user tables without pagination or an explicit projection. A server maximum-row setting could also make the apparent full snapshot incomplete. Existing in-flight deduplication helps, but does not eliminate the separate downstream work.

**Decision:** use one canonical mutation result to reconcile shared progress/status locally, invalidate only affected pages/sections, and refresh bounded data when needed. Do not refresh both media just because they share a service. Preserve Undo and error recovery. First reproduce the prior audit's rating-scale mismatch: some source paths send 100-scale values while the live list constraints accept 1–10.

**Acceptance:** instrument +1, Undo, rapid repeated edits and rejected writes. A successful basic progress action must not reload complete anime and manga lists or the mixed feed. Ratings/notes must survive unrelated progress changes; stale responses must not overwrite newer edits.

### A02 — Mounted pages and weak cache ownership can create invisible work

**Confirmed source.** The pager retains previously mounted pages and neighbors. Mounting is therefore not proof of visibility. Some caches store results but do not avoid future reads; availability keys omit language parameters; broad prefetch task slots can cancel another surface's request. Club membership with a successful empty result is repeatedly treated as not loaded. Collection prefetches friend counts that its custom cards do not display.

**Decision:** preserve top swiping, but give loaders explicit active-surface, account and media scope. Use one keyed in-flight request per resource, cache empty results, batch visible IDs, and avoid decoration requests without a visible consumer. Keep public catalogue data separate from private list/social state.

**Acceptance:** cold/warm page changes, fast swiping, foreground return and switching Anime/Manga do not duplicate identical active requests. Old results cannot populate the new scope. Optional feature-off paths issue no associated requests.

### A03 — Account reset and optimistic rollback need correctness checks

**Confirmed source / risk to reproduce.** `resetUserState` clears several arrays but not all derived list lookups, club/social/provider caches or in-flight work. Club cleanup is partly tied to view disappearance; the general sign-out realtime cleanup targets a different channel. Collection refresh error handling can restore an older snapshot after a newer request has begun. These findings do not establish a demonstrated cross-account disclosure.

**Decision:** centralize identity-epoch cancellation and private-state cleanup, including scheduled local airing reminders; guard all response and rollback commits by account and request generation. Keep public metadata caches only where no private decoration is embedded.

**Acceptance:** sign out/account switch during a slow request, failed refresh and active club subscription; no previous account's list, membership, activity, seen-state or preferences appears in the next account. Leaving a club or disabling sharing invalidates cached access immediately.

### A04 — Live recommendation maintenance is a material background workload

**Observed live, 22:16 UTC on 25 September.** `realm-similar-drive-5m` completed 287 runs in the preceding 24 hours, mean 25.89 seconds, maximum 442.59 seconds. The daily realm-tier refresh took 133.57 seconds. Since statement-statistics reset on 4 August, the similar rebuild accumulated 15,060 calls averaging 25.54 seconds. These are job/function durations, not Home latency or a monetary bill.

The current live similar builder synchronizes seed state, recursively reconstructs franchise components and refreshes entry points before checking whether its stale-title batch is empty. This was deliberately implemented to keep franchise data fresh. An advisory lock already prevents overlapping execution; removing it or merely moving the early return would be an incomplete fix.

**Decision:** separate change-driven franchise maintenance from bounded similarity work. Preserve freshness/version dependencies, overlap protection and the last valid serving snapshot. Measure quiet/active queue costs and internal query plans before choosing the implementation. Review daily re-staling and realm refreshes as part of the same dependency graph.

**Acceptance:** an unchanged empty queue avoids whole-catalogue franchise recomputation; changed relations/cuts still update franchise entry points within the agreed freshness budget. Reader correctness and serving indexes remain intact.

Statement statistics are normalized aggregates; this server tracks top-level statements, not every nested statement. Cumulative scanned tuples and temporary bytes cannot be presented as per-request or daily totals. [PostgreSQL statistics documentation](https://www.postgresql.org/docs/17/pgstatstatements.html)

### A05 — An idle local worker can still issue 1,000 diagnostic title calls

**Confirmed source; installation/activation unverified.** The relations worker calls its coverage report even with an empty queue. Defaults inspect 500 anime and 500 manga using individual ladder RPCs, plus relation counts and a paginated relation-table read. Its installer specifies a 15-minute cadence. That implies up to 96,000 ladder checks/day only if this exact configuration runs continuously; it is not measured live traffic.

**Decision:** separate work polling from diagnostic reporting; cache or batch the coverage summary, run it on changes or an explicit lower cadence, and document one supported scheduler per pipeline. Local dashboards that read local JSON are not database polling and should not be incorrectly removed.

**Acceptance:** idle worker call traces contain only bounded queue/lease checks; full reports run at their intended cadence. Confirm installed path and environment before changing any running job.

### A06 — Import names and dispatch success overstate freshness

**Confirmed source + observed live schedule.** The anime/manga bulk imports request popularity-sorted catalogue pages even when track names imply airing/recent processing. Four live import jobs run hourly, including jobs whose names contain “weekly.” Cron's successful HTTP dispatch does not prove Edge Function completion, persisted updates or fresh release dates.

Some import checkpoints are saved only at run end; per-title failures may be caught while the page cursor advances. Lock acquisition fails open on some RPC errors. Episodes/relations can be deleted and then rewritten in separate operations; interrupted refreshes can leave partial data. A recommendation-edge importer retries HTTP 5xx indefinitely at a fixed interval. See the Edge and operational appendices for exact sites and qualifications.

**Decision:** define distinct initial backfill, current-title refresh and changed-source reconciliation jobs. Use explicit status/update filters where supported and authorized, durable per-item outcomes, bounded retry/deadline rules and distributed leases that fail safely. Replace a valid snapshot only after the replacement is ready. Keep anime episode freshness separate from manga chapter/edition release evidence.

**Acceptance:** forced provider failure, timeout, 429 and database 5xx leave resumable progress and last-known-good rows; no endless retry or silent skipped failed title. Report last successful source update, age and unresolved coverage—not merely a green cron dispatch.

### A07 — Search and schema reproducibility deserve targeted fixes, not a database rewrite

**Confirmed source / selected live parity.** Search computes normalized title blobs, text vectors and similarities that do not align with some existing expression indexes. Friend-count SQL casts legacy text user IDs to UUID. Collection already has useful keyset pagination and matching indexes; retain those foundations. Performance-advisor output includes nine unindexed foreign keys, eight repeated-auth-evaluation RLS warnings and a primary-key warning on the live realm-tier table. The 105 unused-index notices are not permission to delete indexes, especially for disabled or low-traffic features.

The migration chain has replay gaps: an early dependency on a view whose CREATE exists in legacy SQL, a late baseline, and an object-kind mismatch around realm-tier. Sixteen sampled function bodies match live, but version-list equality cannot prove a fresh database can be recreated.

**Decision:** establish reproducible scratch/staging schema and a dependency map; migrate legacy identifiers carefully; align predicates and indexes using representative plans. Prioritize RLS/foreign-key work by actual hot path and write/delete behavior. Do not add MongoDB, duplicate anime/manga services, or drop indexes based only on advisor labels.

**Acceptance:** supported empty-database setup succeeds in isolation; selected current schemas/functions/indexes match the intended deployment; representative small/large-library search, counts and paging meet measured budgets without changing result semantics. [Supabase query optimization guidance](https://supabase.com/docs/guides/database/query-optimization)

### A08 — Club realtime can pay for a refresh that the view does not consume

**Confirmed source / risk to reproduce.** Three of five club stream declarations lack club filters; RLS may still constrain delivered events. All streams debounce into a forced full bundle read. Own mutations may also explicitly refresh. The detail view stores its own bundle while realtime refresh updates the service cache; a visible consumer of that changed cache was not found. Failed subscription setup may leave the same-club guard set.

**Decision:** one observable club state owner and one subscription lifecycle, scoped to authorized club/resource changes. Deduplicate own mutation echoes, remove obsolete chat-triggered work if no supported consumer remains, and make successful refreshes reach displayed state. Do not equate stream declarations with independent queries.

**Acceptance:** one remote reaction updates the visible counts without a full unrelated reload; own reaction is not applied twice; unsubscribe, reconnect, backgrounding, permission loss and failed subscribe recover predictably.

### A09 — Optional provider, detail and recommendation work needs bounds

**Confirmed source.** Availability can perform repeated status checks plus duplicate legacy/V2 prefetches; it remains rollout 0%. Entity-work pages have no explicit stable pagination. Credits fetch full entity descriptions before showing small previews. Recommendation fallbacks can repeat a secondary rail; parsing parallelizes candidates/variants without a shared concurrency ceiling. Taste failures can remain queued past the comment's stated retry count. Image slot waiting swallows cancellation and may repeatedly yield while all slots remain busy.

**Decision:** keep detail first paint small; page entity work; reuse a single availability result with a full scope/locale cache key; cap and deduplicate recommendation/provider work; stop retries under an explicit policy. Distinguish unavailable, failed and valid-empty states.

**Acceptance:** optional enrichment never blocks tracking or title identity, cannot loop forever, and is not fetched when hidden/disabled. Test cancellation and partial failures at concurrency limits. No provider rollout is part of this audit.

### A10 — Data semantics must be corrected before they power richer screens

**Confirmed source and a targeted live view check.** The RAG cache key omits media type although its retrieval query uses it. Some ingest paths derive an episode total from aired-so-far or a manga total from the maximum indexed chapter; these are not equivalent. Undo can mark an import cancelled despite individual restore failures and does not guard every later-edited field. Account deletion includes a global orphan-club scan and an unpaginated storage listing; completeness requires an isolated test.

At 22:28 UTC on 25 September, the live `user_lists` view was confirmed to project `rating * 10` as score, null volume progress/start/completion dates, and a constant false `private` field for both media. Those projected placeholders are not actual user history or a consent model. The constant does not itself prove public access; RLS and RPC authorization remain separate. The missing CREATE VIEW in the migration chain must reproduce this live contract intentionally rather than adopting a guessed projection.

**Decision:** fix scope keys, version-safe apply/Undo and explicit progress/history/consent semantics before exposing them in Home, profiles, exports or recommendations. Scope account cleanup to affected resources and verify every page is removed in tests. Do not fill unknown history or dates with fabricated values.

**Acceptance:** identical Anime/Manga queries cannot cross-serve cached results; ongoing totals remain unknown where appropriate; Undo preserves subsequent rating/notes edits and reports partial failures; isolated deletion fixtures prove completeness without scanning unrelated clubs.

## E. More value from the data already available

| Information | Current verified position | Product use and next decision |
|---|---|---|
| Cover color | Imported for both media and decoded in models; source search found no actual view use of `coverImageColor` | Optional restrained artwork treatment needs no additional provider request. Contrast/monochrome approval still required. |
| Covers and banners | Already requested/stored; anime query requests extraLarge but mapping uses large | Choose image sizes intentionally; avoid downloading unused sizes or unbounded decoding. Audit before requesting more art. |
| Alternate titles, format, season/year, source/country, dates | Present in current catalogue/import paths | Better search, concise detail labels and filters; do not dump metadata into Home. |
| Relations and source IDs | Existing relation/ladder pipelines | Follow a franchise or sequel deliberately; distinguish adaptation, sequel, remake and compilation. A new season is not the same as next episode. |
| Airing times | Source capability and existing fields, with sparse/stale live data | Refresh selected/followed/current titles efficiently; show source age and confirmed vs unknown. |
| Chapters/volumes | Large existing datasets and progress paths | Preserve unknown totals, decimal/extra chapters and independent volume/edition concepts. Metadata coverage does not establish authorized reading availability. |
| Cast, staff, studios, authors | Existing import/model/detail paths | Fetch summaries first and full entity details on demand. Investigate pagination before promising complete credits. |
| External links | Current query uses site, URL, language and color | Provider schema also offers type, disabled state and notes; ingest only fields needed to avoid stale/mislabelled watch/read links. |
| Tag spoilers / role distinctions | Tag rank/spoiler fields and limited people/roles are already imported; more detailed dub/role distinctions exist upstream | Audit end-to-end presentation and top-ten pagination limits; keep spoiler-sensitive discovery and exact credit roles source-backed. |
| Music | AniList Media schema has no structured OP/ED song/version fields | Add a separate permitted metadata adapter if OP/ED is the intended feature. Never associate a song with every image solely by title. |

Provider capability is not proof that all records contain the field. Every added field should have a user-visible purpose, measured coverage, freshness rule, stable source mapping and permission to use it. The existing source's terms must cover expanded ingestion; prior private permission was not inspected. See the primary-source music/metadata appendix for dated terms and access limits.

## F. Music: useful first version and efficient data flow

Pending the user's scope answer, the narrow proposal is a detail section showing OP/ED, song, credited performer, version/episode coverage when known, and verified official listening links. AnimeThemes is structurally well suited; Jikan exposes less-structured theme strings; MusicBrainz can help identity matching if later needed. Direct sample API access was unsuccessful in this environment, so no working integration or coverage claim is made. Documentation and code licenses do not establish playback or commercial metadata reuse rights.

Treat the anime production, theme sequence, song, performer credit and theme version as separate entities. OP2 does not mean season two. Preserve nullable raw episode coverage and ambiguous matches. Match existing AniList/MAL IDs before title fallback; split cours and compilations may need review. Manga should not acquire arbitrary anime music automatically; an adaptation's soundtrack is a separately labelled association, if ever wanted.

Use one bounded server ingestion queue for authorized sources, batched ID matching, deduplicated song/artist hydration, conditional requests where supported, source timestamps and negative caching. Refresh airing titles more often than finished ones. Serve a compact cached summary; never request a music service separately for every card or image. Preserve last valid data on failure. No autoplay, audio download or background player is assumed. [AnimeThemes documentation](https://api-docs.animethemes.moe/), [AniList Media schema](https://docs.anilist.co/reference/object/media)

## G. Architecture: modular ownership without parallel systems

Keep SwiftUI, `@Observable` and Supabase. Extract responsibilities only when a concrete fix benefits from them; splitting extensions by filename alone is not modularity.

1. Session/scope owner: account epoch, persistent medium, selected surface, private-cache reset and cancellation.
2. Library owner: one status/progress truth, mutation results, Undo, paging, search and optional shelf membership.
3. Home/Discover coordinators: different bounded payloads, shared catalogue summaries and scoped loading.
4. Clubs/social owner: identity, membership, consent, scoped activity, visible state and realtime lifecycle.
5. Catalogue details owner: public metadata, relations, credits, optional music and availability adapters, each with one cache contract.
6. Ingestion/operations owner: jobs, leases, retries, checkpoints, provenance, freshness and run completion.

Define dependencies and cache keys before moving code. Keep compatibility while migrating callers. Avoid one enormous Home RPC that simply hides many scans, and avoid dozens of per-card requests. Choose bounded aggregation from measured request/payload costs.

## H. Delivery order and remaining agreement

The companion execution prompt is comprehensive but remains a draft until the screens are agreed. It specifies phased acceptance checks and deployment boundaries; its presence is not an instruction to execute it now.

First agree a small set of phone states: auth form, returning and empty Home, Anime/Manga Discover, visual/compact Collection with shelf creation, Club/member profile, and detail music only after scope is clear. Show realistic data, large text, keyboard and empty/error states; use minimal copy. Resolve exact navigation order, Home hierarchy and whether subtle cover accents are appropriate. Do not create another elaborate animation-led Home concept.

Then establish request baselines and reproducible schema; fix tracking/account-state correctness and expensive idle/background work; implement scoped Home/Discover/Collection; improve clubs/profiles (new Home activity stays gated until server-enforced opt-in is ready); add qualified release and metadata paths; validate usefulness before optional music/Taste/monetization expansion. Some correctness and schema work can run independently after implementation is authorized, but unresolved visuals should not be silently chosen.

Cost measurement must separate database compute/storage, Edge execution, egress, Realtime, source APIs, AI and local workers. Record low/expected/high usage assumptions with actual billing inputs if forecasts are needed. No defensible monthly saving or maximum-user capacity follows from static site counts alone.

Outstanding proof: actual installed build/commit and phone visuals; cold/warm network traces; query plans on representative fixtures; installed local worker activation; full migration replay; working music API/rights/coverage; precise final design choices. These gaps are recorded, not presented as completed checks.
