# Kuro — Production Implementation Handout

## START HERE — paste-ready executor prompt for Claude Code Sonnet 5.5

```text
Implement Kuro's selected Home and Anime/Manga detail redesign as a production-quality native/backend change. Work in /Users/max/Kuro-Anime-App, or the explicitly selected clone of that repository. This handout is the execution specification exported from the singular master plan v1.1. Read all active sections before editing. The historical v0.x appendix in the master plan is non-executable.

First read AGENTS.md, CLAUDE.md, CURRENT_APP_STATE.md, CURRENT_APP_STATE_PLAIN.md, IMPLEMENTATION_PLAN_Variation1.md and the real dirty diff. Record the current branch/SHA, environment and unrelated edits. Do not reset or overwrite existing work. Inspect the selected prototype files and dependency hashes; render Anime Home, Manga Library, both details, busy calendars and failure/empty states. Missing uncommitted reference files must be obtained before claiming visual fidelity. Do not replace the chosen design with a new exploration. Use SwiftUI/@Observable and the existing Supabase/PostgreSQL architecture.

BEFORE IMPLEMENTING, run the mandatory database audit in section12.1. Trace EVERY relevant Swift/RPC/Edge/import/legacy/realtime/background call to its SQL, predicates, bounds, authorization and indexes. Check actual table relationships, foreign keys, uniqueness, ownership and effective RLS/grants/functions. Examine whole-table scans, N+1 requests, full-library refetches after edits, growing exact counts, cast-disabled indexes, unbounded relation traversals, global hot locks and broad subscription fan-out. Pin deployed definitions through authorized read-only inspection where available. Produce the call inventory, schema/permissions map, query-plan evidence, prioritized findings and capacity baseline. Fix integrated-path defects within Wave1; do not skip this audit because older documentation says the database is healthy.

Execute exactly TWO integrated delivery waves, with SIX internal work packages:
Wave1: F1 audit+identity+contracts+additive schema; F2 typed catalogue/enrichment and faithful AniList/MAL imports; F3 bounded bundles, revision/idempotency/lifecycle mutations, current-membership privacy and real-DB qualification.
Wave2: X1 durable native state/outbox+Home/navigation/import; X2 Anime/Manga details and all dependent list/search/deep-link/social wiring; X3 visual/device/accessibility/mixed-load/failure qualification and reviewable release preparation.
Maintain dependency order and one execution ledger. Work continuously through authorized implementation, verification, remediation and focused re-review. Do not stop after a plan, a mockup, a passing happy path or isolated screen. Choose reversible implementation details from this contract and keep going. Performance, latency, concurrency and privacy are gates throughout; do not defer them to a later rewrite. Stop dependent work only for a concrete missing external dependency/authority/gate; continue unaffected work and report the exact blocker. No new cron/heartbeat/public tunnel or paid service.

Preserve existing source anime/manga IDs and each season entry's scores/notes/progress/history. Add stable verified continuity grouping, genuine logical seasons/units/editions, provider-ID crosswalks and unresolved evidence. Never match by titles alone or turn calendar seasons into ordinal seasons. Keep mappings additive and atomically revised; failed enrichment cannot delete the last good relation. Preserve old URLs, list exports, comments, statistics and usable auth/onboarding. Reuse and harden existing workers/services rather than maintaining competing data stores.

Implement the accepted screens ONE-TO-ONE: shallow landscape Anime scenes with white SeasonN artwork tabs and S2 compact stamps, compact persistent Poster medium switch, equal-cover Manga Library with each book's separate44pt chapter action, first-viewport Coming Up summary and complete scalable calendar, artwork-led Sunday Club and Between us. Anime details retain the wide shallow art opening and season selector with selected-season story/units/cast/credits/music underneath. Manga has real spoiler-light story copy, precise bookmark/chapters/editions and a reciprocal source guide, without invented Parts. No Home season-number rows, tall replacement hero, selected-book remote-control bar, offset-sized Manga covers, public comments, excessive copy or generic Journey feature. Suggestions/classics belong on Taste to the left, not personalized Home. Every control has typed state, real route/action, pending/empty/error behavior, accessibility and evidence.

Use one bounded Home/detail/Collection contract family. No per-card provider/social hydration, no full-account reload per progress tap and no franchise-wide eager detail request. Database cost must stay bounded behind those bundles, not merely hidden in one large RPC. Shared artwork/material revisions follow the actual image into details. Missing schedules/Spotify links/copy/coverage remain honest fallbacks. Verify source permission and field capabilities before enabling adapters; AniList does not have a dedicated OP/ED collection in the previously inspected schema. Never invent dates, chapter boundaries or music matches.

Support Anime AND Manga imports from AniList and MyAnimeList. Preserve source IDs, statuses, exact child positions/volumes, raw rating scale, private notes, repeats, dates and custom organization when supplied. Implement typed resumable jobs, safe device-export parsing, checkpoints/receipts, merge rather than silent replacement, conflict protection for current edits and progressive personalized Home readiness. MAL account API access must be qualified; an unavailable API connector cannot be advertised as working because XML import passes. Deliver the functioning export alternative and complete local connector contracts while documenting unmet external access. No provider password collection or implicit two-way write-back.

Persist every accepted offline progress intent transactionally in account-scoped local durable storage before success feedback. Drain bounded batches with stable mutation IDs, absolute values, revision/lifecycle checks, server receipts and field-specific writes. Handle very rapid taps, reordered responses, Undo, backwards edits, status/rating/note races, add/delete/add, two devices, imports and account switches. Old queued writes cannot recreate removed entries. Serialize conflicting entries, not the whole app/all users; allow bounded independent concurrency. Lost responses never double-apply an effect. Audit every legacy writer for the same database revision fence.

Private club authorization must use current database membership/effective sharing rules across reads, counts, comments, reactions, notifications and channels. Prove removal with an established stale-token subscription and warm caches. Clear private projections and reject late callbacks; no persistent offline club bodies. Shared title comments are a union of still-eligible clubs, not exclusive rooms: removal from the only shared club revokes access; another valid shared club can preserve its independently authorized title audience. Cached realtime authorization is not enough; use revocation-safe account invalidation hints and fresh protected fetches, with no sensitive broadcast payloads. Test membership-removal/write races with actual PostgreSQL barriers.

Qualify the stated1000/5000-session workload, mixed writes/imports/realtime, large growth datasets, rapid-edit contention, burst and soak. Record offered/completed RPS, real authenticated roles/accounts, p50/p95/p99, errors/conflicts/429s, SQL rows/buffers/locks/pool wait, queue growth, generator saturation and hardware. User sessions, request rate and database connections are different quantities. Never load-test production implicitly, hide failed throughput behind rate limits, substitute fake-DB tests for concurrency/RLS, or claim measured capacity from source inspection. Mandatory absent tests remain NOT RUN and block the relevant release gate.

At each wave exit, finish required checks, resolve critical findings and re-review changed paths; independent review is required before release when available and missing review remains explicit. Keep exact evidence for source/local/staging/live/released separately. Update the three canonical documents and memory using the approved environment workflow after initiatives. Do not declare either wave done while mocks, missing handlers or mandatory proof gaps remain.

Prepare the exact build/migration/function/flag order and rollback preserving receipts, newer user activity and pending offline intent. Obtain applicable explicit authority before deployment, production backfills, credential changes or public exposure. This handout-writing request itself did not deploy or authorize production writes. Finish reversible work and the concrete release package before asking for release approval. After an authorized release, prove exact deployed artifacts and real live happy/failure journeys before saying it is live.

Final handoff: files/contracts changed; wave status; accepted design screenshots/overlays; every mandatory test PASS/FAIL/NOT RUN; query/capacity/import/privacy/concurrency evidence; exact candidate and deployed identity separately; rollback/remaining blockers. No unsupported promise that the app works perfectly.
```

## Executor entry sequence and authority

This is a self-contained executor edition of the **single master plan v1.1**, dated5October2026. Canonical plan: `docs/plans/2026-10-02-series-and-home-rebuild-DRAFT.md`. This handout adds no separate waves or competing decisions. If the canonical plan changes after this snapshot, reconcile the active versions before execution and regenerate the handout. Intended executor name is user-specified; model availability is not asserted.

**Current proof:** accepted browser design and source review only. Both native/backend waves NOT STARTED; staging/capacity/live/released NOT VERIFIED. No production, credential, public-hosting or purchase operation was performed to create this document.

Start with these read-only local steps, run as separate commands:

```sh
pwd
git rev-parse HEAD
git branch --show-current
git status --short
git diff --stat
git diff -- Kuro/ContentView.swift Kuro/KuroApp.swift Kuro/Services/SupabaseService.swift
```

Read the rules/docs and untracked reference files too; git diff does not include untracked assets. Establish isolated DB/test access and release authority without printing secrets. Run the pre-implementation audit, record contracts and then execute F1→F2/F3→Wave1 gate→X1/X2→X3→Wave2 gate. Performance fixes and reviews stay inside those waves. Use the exact supported build/test commands from the current project instructions, not commands inferred from this old snapshot. No native build or hosted test has been run by this documentation initiative.

Navigation through this handout: accepted design/scope in1–2; identity and calls in3–4; ingestion/offline in5–6; all control wiring in7; two waves in8; metrics/tests/release ledger in9–10; sources in11; mandatory DB audit, concurrency, revocation, fidelity and capacity gates in12; reproducible visual dependency manifest at the end. The ledger is canonical; execution updates go there first, then regenerate this edition.


## Status, scope and authority

**Planning status: COMPLETE FOR HOME + ANIME/MANGA DETAIL EXECUTION. Version 1.1, 5 October 2026 (Europe/Berlin). Owner: Max.**

**Implementation status: NOT STARTED for both native/backend delivery waves. Deployment/release status: NOT VERIFIED.** The planning label does not mean the app is implemented, wired or tested. The existing filename is retained to preserve links; the active specification below supersedes the earlier incomplete draft. Historical material at the end is an audit record, not a second executable specification.

Scope includes everything needed to make Home and both detail pages real: grouping, import-to-Home readiness, source enrichment, artwork continuity, progress/Undo/offline, private-club activity, deep links and compatibility changes in Collection/Discover/Taste. It does not commission another visual exploration or a full redesign of authentication, profile, clubs administration, monetization or the concierge. Preserve those features; adjust interfaces only where required for this integration. Optional personal shelves must survive existing data flows; introducing a new shelf product is outside this delivery.

Two waves are retained deliberately. One enormous wave would mix identity/backfill risks with visual and offline failures; more small waves would leave half-wired screens. Wave 1 produces a qualified shared foundation with flags off; Wave 2 consumes it and proves the full user journey. Contract fixtures can unblock UI development, but mocked screens cannot pass Wave 2.

## 1. Product and design decisions — executable defaults

| Area | Decision and purpose |
| --- | --- |
| Navigation | Target swipe order: **Taste ← Home → Discover → Collection → Clubs**. Home is the default after successful auth. Discover owns deliberate search/browse; preserve current global search access as a shortcut into that same search implementation. No additional Home submenu. Legacy routes remain valid. |
| Medium | Persistent Anime/Manga choice, scoped to the signed-in account. Use the selected compact **Poster** switch. Both media keep their own layout and scroll position. An empty Anime list does not conceal a populated Manga list. Never flip medium automatically after each request. |
| Home eligibility | Watching/reading, explicit planned/saved/followed titles, their verified releases/continuations and allowed private-club activity. Unrelated suggestions/classics/new-to-you belong on Taste to the left. No generic discovery rail disguised as personalized Home. |
| Anime identity | One visible card per verified story continuity. Logical seasons sit beneath it. Keep source release entries intact; a split cour can span several entries. Broad franchise graphs are not authoritative continuity groups. |
| Anime visual | Preserve the accepted shallow landscape scenes, restrained artwork material, white **Season N** tab on main artwork and **S2**-style stamp on compact artwork. No Home season-number rows. A season marker opens the season overview; title opens details; progress is independent. |
| Manga visual | Preserve **Library**: equal cover geometry, readable titles, each book's own chapter position and separate ≥44pt advance key. Cover/title is one detail target. No selected-book workbench, offset/masonry books, repeated Open rows, giant color splashes or decorative numbered parts. |
| Coming Up | A compact full-width artwork summary immediately below the medium switch, wholly visible on short phones. One tap scrolls to the complete calendar and moves accessibility focus. Summary and calendar use the same projection, not separate requests. Keep all simultaneous events reachable. |
| Private club | Preserve distinctive Sunday Club/artwork treatment, member names when allowed, and **Between us.** on details. A shared-club audience is not an individual-club room; label it honestly. No public friend network or public comments. |
| Detail artwork | Anime: wider **horizontal**, shallow opening, not a taller vertical hero. Manga: full portrait cover with restrained paper edges, compact title and bookmark. Artwork is the first visual signal. |
| Detail story | Hook is not a substitute for story. Manga shows one real spoiler-light premise (~20–35 words), then optional longer synopsis. Anime shows a short selected-season hook, optional premise/synopsis; label a series fallback rather than passing it off as a season description. |
| Sections | Anime seasons browse in the liked panels; selection updates the information directly underneath. Manga leads with chapters/bookmark and genuine volumes/editions, without an anime-like parts selector. Authentic named manga runs are metadata only unless a verified publication model needs navigation. |
| Depth and motion | Deliberate shallow edges, restrained highlights and clear press states; no toy-like bevels/domes. Scrolling stays free. Optional motion communicates an accepted action or changing context, never hides information. Reduce Motion preserves the same meaning. |
| Color | Artwork-derived material is allowed by Max's newer design direction; status indicators remain monochrome. Store material identity with the actual displayed image and use it on Home/details. Preserve liked blue/teal overrides explicitly; no arbitrary title-to-color map. |
| New content | Short premises appear for unfamiliar content on Taste/details, not repeated beneath every already-watched Home card. Followed-title announcements may have a concise verified explanation. |
| Journey | Remove prominent generic Journey/Adaptation Path UI. Keep source relations for a useful source handoff, reciprocal anime guide and continuation evidence. |

### Fixed defaults that close earlier open decisions

- Main story seasons and verified canonical continuation films may share a continuity; films retain a Film label, never a made-up season number. Recaps/extras are secondary. Remakes, alternate continuity, independent spin-offs and adaptations remain distinct by default; only reviewed evidence changes this.
- Season order/labels require provider relations plus corroborating release/official metadata or a reviewed override. AniList's calendar `MediaSeason` is not an ordinal season. Unknown mapping falls back to the existing entry/progress, without blocking tracking.
- Preserve each entry's rating/notes/status/history. No automatic series average, inferred prior-season completion or automatic follow of all related works. A new season does not undo an old completion. **Caught up** means reaching confirmed available units; **Completed** requires explicit intent against the correct entry/lifecycle.
- Resume preference wins; otherwise use the most recently deliberately interacted current entry with a stable ID tie-break. Do not manufacture activity from imported old history. Browsing a season is not a resume mutation. Rewatching can deliberately resume an earlier entry.
- Both AniList and MAL Anime/Manga imports are mandatory: typed account/list adapters and validated device exports where available, preserving supported source structure and private fields. MAL OAuth/API is an explicit connector qualification gate; a functioning XML fallback does not prove account connection. Complete reversible connector work and export support while awaiting external access, and never advertise the missing path as ready. See section12.5 for fidelity/merge/credential requirements. Unsupported formats show Unsupported, rather than routing IDs through prose. Export compatibility remains intact.
- Existing title comments remain one per user/entry, ≤500 server-defined characters with edit/delete/reactions. Several legacy season comments remain distinct entry-scoped comments in a series feed. Do not merge/overwrite them. Replies and exclusive single-club rooms are outside first delivery. Persist spoiler scope, but never expose a spoiler just because the user browsed that season.
- First continuation delivery is **season-level coverage**. Exact per-episode matching is optional, separately evidenced enrichment; it never blocks the correct season-level/unknown fallback. A reading-guide choice never marks anime watched or changes a manga bookmark.
- Fractional/special chapter labels and separate reading editions are first-class unit identities. Do not round to an integer or convert edition progress by guesswork. Ordinary integer entries continue working without migration-induced loss.

## 2. Verified local baseline and integration gaps

Source inspection on 4 October: checkout HEAD `471c609943d2374c6dda940aebdfde2fcb077d50` plus substantial dirty/untracked work. Re-pin at execution start. Preserve native changes in `ContentView.swift`, `KuroApp.swift`, `SupabaseService.swift`, `TastePicksView.swift`, CLAUDE/docs and all unrelated work. HEAD alone does not describe the prototype.

| Actual surface | Current source observation | Required integration |
| --- | --- | --- |
| `Kuro/ContentView.swift` | Flagged order is Taste/Discover/Browse/Collection/Clubs; local TastePicksView exists. | Add Home to the existing pager/routing; retain exactly five target pages and fallback behavior. Do not create a second root navigation system. |
| `Kuro/Views/DetailPages/AnimeDetailView.swift`, `MangaDetailView.swift` | Existing next-unit, cast/credits, ladder, recommendations, episodes/chapters and club components. Separate tasks fetch tags/similar/ladder and credits; child lists fetch again. | Compose the accepted hierarchy from typed selected-section state; remove eager irrelevant fetches and generic Journey prominence. |
| `SupabaseService+UserLists.swift` | Direct progress update then fetchUserLists. Wider upsert also refreshes Collection/items/feed/upcoming. setUserProgress delegates to wider entry upsert. | Introduce progress-only revision/idempotency writes and one durable coordinator. Patch affected projections, rather than doing a full account refresh per tap. |
| `NetworkMonitor.swift` | NWPathMonitor + reconnection generation. | Retry hint only; one drain on auth/foreground/reconnect. Connectivity does not prove endpoint write success. |
| `KuroDiskDetailCache.swift` | Best-effort catalogue cache in Caches, ignoring disk-write errors. | Reuse for public catalogue snapshots only. Never store the only copy of unsynced actions or private club payloads here. |
| `ConciergeAniListImportCoordinator.swift`, `concierge-import-anilist` | Preview/import/text reconciliation, capped retrieval; no durable job/Home-ready revision in inspected flow. | Typed import job, resumable checkpoints, correct totals and progressive Home invalidation; natural-language concierge remains separate. |
| `bulk-import-anime`, `bulk-import-manga` | AniList IDs + MAL references; source edges rebuilt with separate delete/upsert and absent targets skipped. | Batch identity resolution, persist unresolved references, atomic evidence revision publication and preserved overrides. |
| `scripts/media_relations_worker.js`, ladder RPCs | Existing queue/worker and get_media_ladder; worker also deletes then rebuilds and skips unresolved targets. | Harden/reuse this operational family, not another competing relation worker. Keep a stored adaptation graph separate from verified continuity membership. |
| `SupabaseService+Collection.swift` | Entry-level pagination/state. | Server-side grouping before pagination, aliases searchable, preserve child tracking. No grouping-only-after-page-fetch. |
| `SupabaseService+Social.swift`, `FriendsActivitySection.swift` | Shared-club title comments/reactions/count prefetch. Inspected comment model has no season/episode spoiler fields or reply parent. | Persist spoiler metadata, use latest effective privacy rules for all aggregates/reads, retain drafts on failure, coalesce counts. |
| Catalogue upcoming | Anime next-airing fields exist; Manga enrichment aggregate/index rows are not verified publication schedules. | Evidenced release ledger, localized precision/freshness and honest pending dates. |

No new Home/series bundle, structured durable import, mutation receipt/outbox or native material pipeline is proven implemented by the browser. No fresh hosted parity/data/privacy test was performed in this planning initiative. AGENTS notes describe prior live deployments; executors must verify exact current migrations/functions before any rollout claim.

### Visual reference manifest

- `tools/design-directions/instrument.html` with `?switch=poster&medium=anime` and `?switch=poster&medium=manga`; `manga-library.html` is the focused wrapper. Pin these files/assets at execution start, not a temporary localhost/tunnel URL.
- `instrument.js` v61, `instrument.css` v54, `instrument-detail-data.js` v54, `instrument-art-materials.js`, `manga-philosophies.js/css` and actual referenced assets. Read the rendered composition and its behavior; historical query options are not selected designs.
- Accepted anchors: Artwork season marker, Poster switch, current Anime scenes, equal-cover per-book Manga Library, visible Coming Up summary, artwork-led private club, season-scoped Anime detail and Manga bookmark/story overview.
- Known local proof: phone-size layout and browser fixture checks, six Manga premises, progress/Undo/failure simulation and season selection independence. No real releases, import personalization, native haptics, backend writes, persisted comments or durable offline proof follows from those tests.
- Public share links in history are expired lifecycle evidence. Do not reuse, renew or create another tunnel automatically.

## 3. Foundation contract — shared identity, data and authority

Physical names below are proposed. Reuse an equivalent existing entity if its semantics pass these requirements; record the mapping in the ledger. Do not invent a parallel database or introduce MongoDB: this app is SwiftUI/Supabase/PostgreSQL. Additive migrations keep existing catalogue IDs and foreign keys valid.

| Record | Required semantics and constraints |
| --- | --- |
| Series | Stable UUID, medium/format/continuity, title, grouping state, mapping revision and artwork policy. Never use a graph's minimum member ID as permanent identity. |
| Section | Stable ID, parent, season/film/extra kind, nullable ordinal, name/order, provenance and state. Split cours/source records can span one section; one source record can contain multiple logical ranges. |
| Entry membership/spans | Typed existing anime/manga FK with exactly one target and consistent medium. Source/display ranges and units remain recoverable. Unknown ranges are nullable, not fabricated. |
| Provider references/aliases | Unique provider namespace + external ID, compatible type/format and existing entry reference; titles/synonyms are search aliases. Keep a reviewed cross-provider crosswalk and unresolved relation evidence. |
| Mapping revision/audit | Proposed/approved/superseded state, source/rule revision, reviewer and reversible corrections. Overrides survive refresh. Publish new relation sets atomically after successful validation; a failed/partial fetch cannot erase the last valid set. |
| User series intent | Account-scoped explicit save/follow and optional resume choice. Per-entry list rows remain authoritative for progress, rating, notes and completion. Text/UUID legacy user ID joins need deliberate casts, not unsafe migration shortcuts. |
| Units/editions | Stable unit identity, original label, precise order key, source entry/edition and optional logical section; available/released evidence separate from a placeholder index. Preserve 0.5/special/restarted numbering. |
| Artwork material | Displayed image ID/content revision, crop/override, extraction version, base/deep/wash/edge/ink and contrast results. Home/detail consume the same resolved record. |
| Detail copy | Raw provider synopsis + locale/provenance; distinct short premise, hook, expectation, review status/revision. Missing story copy is explicit, never repeated mood copy as a plot summary. |
| Theme appearance/link | Child entry/section, OP/ED/insert role, order and episode applicability, song/artist IDs, source evidence, verified Spotify/external link + match state. TV cut/remix/cover are not interchangeable. |
| Adaptation coverage | Anime section/entry, source work/edition, exact/partial/reordered/original-ending/unknown mapping, possibly discontinuous unit spans, first/last adapted labels and separately reviewed recommended reading start, rationale/source dates/revision. |
| Release event/evidence | Stable canonical unit/edition/event identity, series/entry/section, kind, source-local date/zone, nullable UTC instant, precision, locale/territory, status, evidence/freshness/revision. Preserve retractions/disagreement. |
| Import job/items | Auth owner, provider/source reference, selected media/merge policy, idempotency key, nullable totals, structured items and per-stream checkpoints, dispositions/errors/retry-after, committed Home revision. |
| Mutation receipt | Auth owner + unique mutation ID, canonical request hash, resulting revision/position and outcome. Transactionally committed with the progress change; replay is not another update. |

Source-ID relationships connect Anime and Manga; they do not merge those media or prove chapter coverage. Similar titles are candidates only. Comics and novels with equal names remain distinct; multiple adaptations can link to the same source. Unresolved target IDs are retained and resolved after later catalogue import, regardless of arrival order.

**Precise progress and legacy writers:** add a nullable stable unit reference, lifecycle and server revision to the existing tracking record (or an equivalent constrained extension keyed to that exact record). The unit reference is the precise position when present; the legacy integer is a compatibility projection for representable source numbering, not a rounded substitute for a fractional chapter. Define old-client rendering/writes explicitly and test them before enablement. Every progress-changing writer—including concierge apply/Undo, structured imports, direct list mutations and older-client writes—must advance the server revision through one database-owned rule. New mutation RPCs use the revision returned by that rule, rather than incrementing twice. A queued base revision must detect a concurrent legacy write. Do not enable durable sync while a writer bypasses this fence. Audit older full-row upserts for unintended notes/status overwrites; preserve reads and either harden the write compatibility path or require a documented compatible app version before rollout. No claim of backward-compatible writes without those tests.

All new tables require RLS, explicit grants/constraints and project SQL search paths. Public catalogue caches exclude accounts/import references/club content. Maintenance is service-only. Read/write authorization derives from auth.uid/JWT, never from trusting a client user ID. Check latest migrations rather than copying outdated first-generation social predicates.

### Grouping, follow and correction invariants

A singleton series is a valid fallback for an unresolved entry. Importing Season3 as current must not mark1/2 completed. Multiple active entries retain distinct progress in detail. Grouping changes never rewrite source IDs or reset reading position. Merge/split corrections preserve comments, list records, exports and deep links through bounded, cycle-checked aliases. Group only approved continuity membership; an ADAPTATION/SIDE_STORY graph edge alone is not permission to join seasons. Historical backfills do not trigger new-release notifications.

## 4. Serving and mutation contracts — contract first

Use typed request/response examples and repository-local OpenAPI/contract fixtures before changing callers. Postman collections are an optional execution instrument after proper bootstrap; no cloud push required. One response schema must drive mocks, Swift models and tests. Names are proposed versioned RPCs; document reuse/rename explicitly.

| Contract | Inputs / limits | Response / ownership |
| --- | --- | --- |
| `home_bundle_v1` | Auth; medium, locale/territory, opaque cursors, requested revision. Initial12 active series,20 events,6 club items; hard maximum50 per section. Date window defaults7days, expand through bounded≤90day windows and a paged Later group for farther known announcements; counts always name their window. | Account/Home/mapping revisions, as_of; active summaries and exact resume targets, upcoming/pending groups/counts, allowed club slice, independent freshness/error states and cursors. One canonical Home contract, replacing earlier competing home_series_bundle proposals. |
| `series_detail_bundle_v1` | Series or original entry, selected section, locale and expected mapping revision. Initial3 unit rows,12 cast,20 activity; hard cap50 per page. | Public header/material/copy, selected-section data, user projection, allowed club context, field availability/source state and separate cursors. Split public/private storage even if assembled in one response. |
| Child/detail page reads | Unit/cast/activity kind, stable parent/section and opaque cursor. | Bounded next page, unchanged context revision. Stale mapping cursor returns REFRESH_REQUIRED rather than silently changing targets. |
| `collection_series_page_v1` | Auth, medium/status/query, sort and cursor; initial30, max50. | Server-grouped series before keyset pagination; matched aliases/child entry, exact child state inspectable. No gaps/duplicate parent cards across pages. |
| `start_library_import_v1` | Provider/source handle or validated upload reference, media/status filters, merge policy and key; validated file/row caps. | Durable job ID/state/revision. Same key+payload resumes same job; reused key with changed payload rejects. Auth/abuse limits enforced. |
| `import_job_status_v1` | Own job ID, after_revision. | Counters, nullable discovered total, per-medium checkpoint, terminal dispositions, retry-after, sanitized error and latest committed home_revision. Cross-account access denied. |
| `apply_progress_mutations_v1` | Bounded ≤50 mutations, exact entry/unit/edition, lifecycle, base revision, absolute position, mutation UUID. | Per item applied/already_applied/conflict/invalid_target/removed_entry/not_authorized; canonical state+revision+receipt. Update progress only; status/completion changes require explicit owned intent. |
| Save/follow/resume/list intent | Explicit add/remove/follow/set_resume and child/series target, revision/key. | New affected summary and revision; no guessed completion/season changes. Retain existing list workflows and distinguish destructive scope. |
| Club feed/comment writes | Auth, exact entry and optional spoiler scope; comments ≤500 server-defined characters; existing rate limits. | Privacy-filtered paged roster/comments and safe counts; comment writes preserve original entry identity and scope. No public fallback. |

Every contract example covers success, empty, partial metadata, loading/pending, offline-cache, unauthorized, conflict, invalid cursor/target and retryable failure. Use machine-readable error codes/detail consistent with current project patterns, HTTP status where applicable, retry_after for429, and bounded timeouts. Do not return an empty array as a success disguise for a transport failure. Concurrent selection requests have generation IDs; a late response cannot overwrite the currently inspected section or signed-in account.

### Request and cache policy

- Home mount: at most one bundle request for the selected medium, plus one bounded optional neighbor warmup. No per-card counts/provider/season fan-out. Offscreen/distant pager pages do not keep fetching.
- Detail open: one bounded initial bundle; only selected-section/explicitly expanded pages fetch. A rapid season change cancels/ignores old work. Section failures are isolated: missing music cannot break chapters/progress.
- Progress tap: durable local transaction, coalesced bounded mutation drain, returned affected projection. Zero unconditional whole-library/Collection refetches from each tap. Periodic authoritative reconciliation is lifecycle-based, bounded and overlays pending local state.
- Upcoming summary/full calendar share the same event page/revision. More reads/events remain cursor-accessible; preview thumbnails are not a count cap. Server counts are indexed aggregate queries, never client loading thousands of rows to count.
- Public detail cache key includes series/section/locale/artwork/mapping revision. Private snapshots include account and permission epoch; clear/suspend on account switch/revocation. No private stale-while-revalidate after authorization is revoked. First delivery stores no persistent offline private club bodies and hides private activity when current authorization cannot be established. Reauthorize on foreground/reconnect; section12.4 governs membership generation, revocation and sensitive realtime payloads.
- Single-flight dedup, finite TTL, bounded LRU/disk size, request cancellation and incremental invalidation. No per-render image analysis or recursive global relation traversal in serving SQL. Workers coalesce shared catalogue work across users.

## 5. Import, release and enrichment execution

### Durable import → genuinely personalized Home

1. Validate provider/format/access. Capture source IDs/status/progress/score scale/repeat state/available dates and supported shelves/notes as structured fields. Missing fields remain absent. Preview and merge policy use the same typed payload; never ID→text→LLM→ID.
2. Persist job/checkpoints before external work. Prioritize current/planned data, interleave selected Anime/Manga streams and exhaust pagination. No “complete library” at the current200/400 cap. Apply bounded known items while unresolved entries enter shared hydration/review; never block all known titles on one missing title.
3. Transactionally apply each chunk, dispositions/counters and affected-user Home invalidation. Protect local updates since preview/prior sync using revision checks. Replay cannot duplicate progress/notifications. Cancellation honestly reports already-applied items; Undo only reverts this job's unchanged writes, never subsequent user edits.
4. Coalesce Home revision publication and fetches (target ≤1 UI refresh/second). Real current titles fill Home as committed batches arrive. Stable ordering while scrolling; no shifting/auto-switching medium. Image/optional enrichment is not a readiness prerequisite.
5. Job subscription is account-authorized and debounced; fallback conditional foreground polling begins around2s, backs off10–30s and honors Retry-After. Stop at terminal state/background/account change. Persist job ID for reopen. No endless polling/crash-reset job.
6. Terminal ready/ready_with_issues requires provider pagination exhausted and every discovered item terminally applied/conflicted/unresolved/skipped. Fetch at least the terminal home_revision before saying **Your Home is ready**. Record unresolved counts with an action, not concealed omissions.
7. Animation shows honest phases/counters, no fake percentage or artificial wait. A150–300ms finishing transition is optional once ready, omitted for Reduce Motion. If enrichment lags, the user can enter usable Home and return to progress; never trap them on a spinner.
8. Import is one-time copy; later refresh uses deliberate reconciliation. No two-way remote writes implied. Private lists, invalid handles/files, provider429/403, truncation, cancellation, crash and logout have explicit resumable/error states.

### Sources and release truth

| Information | First-delivery policy |
| --- | --- |
| Anime catalogue/cast/credits/relations/next airing | AniList IDs/data plus existing stored metadata; validate observed field coverage. Next-airing timestamp is scheduling evidence, not proof of local streaming availability. |
| OP/ED metadata | AniList's Media schema has no dedicated song collection. Qualify AnimeThemes metadata/official music evidence, source-ID joins and permitted retention before enabling an adapter. Metadata/verified external links only; no audio/video rehosting or autoplay. |
| Spotify | Prefer verified provided track links. If no exact recording match, offer explicitly labelled **Find on Spotify** search or omit the link. Do not pretend a title search identifies the correct TV cut/remix. A separate Spotify API adapter is unnecessary for basic external linking. |
| Anime→Manga continuation | Use stored source relations plus reviewed season-level coverage evidence. MangaUpdates start/end strings are candidates, not universally reliable season boundaries. Supplementary datasets require accuracy/permission review. Exact chapter CTA only for approved edition-specific evidence. |
| Manga chapter releases | Use permitted authoritative publisher/feed evidence for supported titles/languages; existing MangaDex aggregate/placeholder rows are insufficient for “new today” or future dates. No unofficial scrape as default ingestion. |
| Manga volumes/editions | Publisher schedules distinguish chapter versus volume, edition/language/territory. A US English volume date is not a global new chapter date. |
| Missing future dates | Show **Dates to come**/pending announcement with real evidence, not a invented cadence or midnight timestamp. Unknown manga coverage is an intentional honest state, not a hidden fabricated schedule. |

All adapters have permission/retention/rate-limit checks, finite retries with jitter, leases/checkpoints, idempotent upserts and dead-letter review. Reuse operational reporting families, separate locks as project rules require. Source unavailable/expired/payload-invalid states preserve previous verified data while marking freshness. Catalogue descriptions/links are untrusted: sanitize markup, allowlist supported URL schemes/hosts, constrain redirects/fetch destinations, and disable external entities in file parsers. Import upload bytes, decompression and row counts have explicit caps; no arbitrary URL-fetch proxy. Remote provider jobs never execute synchronously inside page reads.

Release events retain instant/day/month/quarter/year/unknown precision and source-local timezone. Date-only is date-only. Scheduled/released/delayed/cancelled/withdrawn are distinct. Passing a schedule time is not proof of publication/accessibility. Stale unconfirmed past events lose countdowns. Confirmed counts exclude estimates/undated announcements; archival backfill does not become a new notification. Track source seen state separately from reading progress.

Audit at least100 stratified followed titles: airing/completed anime+sequels, Japanese/localized manga, manhwa/webtoons, hiatus/finished/niche. Report identity/date precision/locale/freshness/permission separately. Do not declare universal Manga scheduling or invented coverage percentages. Optional enrichment adapters may remain disabled with explicit absence UX; the implemented core must still be complete and tested.

### Artwork and copy ingestion

Resolve current/selected section art first, else explicit series banner/cover fallback. Preserve image association and crop provenance; never pass a cover crop off as sourced seasonal art. Generate deterministic material on ingest/content revision, store extraction version and contrast results, allow explicit editorial crop/color overrides. Material lookup is by exact displayed image digest/revision, not title. Selecting another season can change detail art/material without changing Home's current resume artwork. Transition from Home to its current detail uses the same record.

Manga preserves full-cover composition and common cover proportions; use only restrained material accents. Missing/decode-failed art has stable geometry, readable neutral colors and live controls. Raw synopsis is preserved; short edited premise/hook/expectation has source locale/provenance/review state. Do not infer a plot or quality judgment from tags or repeat mood copy as a story. Use the existing synopsis pipeline where compatible; no LLM classification/routing beyond project policy.

## 6. Durable tracking and non-happy paths

Use one `@Observable` progress coordinator/store shared across Home/details/Collection. Baseline choice: versioned SQLite in Application Support with transactional projection+outbox, appropriate file protection and finite storage rules. If an existing equivalent is discovered, reuse it and prove these invariants. Best-effort Caches/UserDefaults/in-memory arrays are not an outbox. Do not add Combine.

Each mutation records auth owner/device/lifecycle, UUID/key/hash, exact entry/unit/edition, absolute desired position, local sequence, base server revision, prior value for Undo, operation type, creation time, attempts/next retry and state. Device wall clock is for display, not write precedence.

- Local accepted success occurs only after projection and outbox commit atomically; disk full/corruption/migration failure keeps the old count with retryable feedback. One haptic then, not another on remote ack. Pending says saved on device rather than synced.
- Online/offline actions use the same path. Refreshes overlay pending local state. Twenty rapid taps survive app kill/restart. Compact only unsent consecutive ordinary position intents for the same entry/lifecycle; never across in-flight operations/removal/edition/rewatch boundaries.
- Drain preserves per-entry FIFO with bounded cross-entry concurrency and one active drain. Foreground/session restoration/reconnect trigger it; finite exponential backoff+jitter for network/timeout/429/retryable5xx honors Retry-After. No offline timer storm.
- Server verifies revision and field ownership, atomically writes progress+receipt. Identical replay returns receipt; different payload with the same key rejects. Default receipt retention180days, audited/configurable: older clients first reconcile and reissue explicit intent with a new base revision/key; never blindly replay beyond retention.
- Concurrent device/import edits use revision conflicts. First delivery does **not** auto-max all positions; compatible forward-only merges may be introduced only with lifecycle-specific tests. Explicit rewind/rewatch/Undo is preserved as intent. Conflict UI offers use server or deliberately reapply this position, never silently overwrite newer notes/rating/status.
- Undo unsent: cancel/replace atomically and restore prior projection. In-flight/acked: compensating absolute intent in order, not receipt deletion. Newer remote change may conflict. Show the same result across all screens.
- Deleted/removed entry, changed edition/mapping or invalid unit retains an actionable error; do not recreate a removed list row or guess a chapter conversion. Completion/status is explicit, not inferred from provisional counts.
-401 refreshes session once, then suspends the queue if reauth required. Logout cancels draining and isolates data; another account cannot read/send it. Re-login resumes only the owner queue. Account deletion handles private local cleanup with the existing approved lifecycle.
- Background drain is opportunistic, checkpointed on expiration. Foreground/reopen is the guaranteed application-controlled retry point; iOS scheduling does not guarantee immediate suspended-app reconnect. Do not require an always-running background loop.

## 7. Native composition and every-control wiring

### Home information order and scaling

Header/page identity → Poster medium switch → Coming Up glance → Current reads/watches → full Coming Up → private-club slice. Keep visual explanations outside the product. Current-title capacity is never one item per date or an assumed six-item library: initial bounded cards plus explicit load-more/cursors, while the liked density remains. Anime main cards and compact continuation use the same summary model. Manga has equal covers and no focus-selection detour. Small/large phones and iPad layouts retain coherent hierarchy, safe areas and text scaling.

Calendar supports ≥100 simultaneous events, many events from one series and many same-day rows. Group by user's local date; allow long date windows as labels. Expand/load-more preserves scroll/focus; preview count includes all eligible events, not only thumbnails. No sticky overlay hides current reads. The glance has one generous target, with Reduce Motion instant scrolling. No second submenu to find the calendar.

### Anime detail order

Shallow wide artwork → compact title/status → selected-season hook / optional story → liked season panels → selected-season unit/progress workspace → source/continuation → OP/ED links → cast and principal creators → artwork-led **Between us.**. Metadata can show concise chips rather than paragraphs. Move unrelated new suggestions to Taste. Keep verification/source explanation inside optional disclosures.

Selected information belongs to the inspected season: episodes, premise/synopsis, principal credits, songs, source coverage and optional availability. Keep current tracking distinct from inspected context. A season selector never completes/starts a season. If no history exists, show untracked, with a separate start/resume action. No whole-franchise fetch to switch panels. Existing entry deep links preserve exact original context.

### Manga detail order

Book artwork/title → true series premise + collapsed story → **Your bookmark** with exact chapter/edition → next chapter and paged chapter list → genuine volumes/edition context if available → **On screen / I've watched the anime** reciprocal guide → compact characters/author/artist → **Between us.**. No decorative seasons/parts/default music for manga. Chapter update directly affects the exact reading record through the durable coordinator.

Guide displays known anime progress as context, never as a finished-season assumption. User chooses the actual adaptation and finished season; it is read-only guidance. Show Starts at / Ends at / Read next only with approved evidence; read-next is not arithmetic. Novel source is labelled novel. Unverified boundaries show source detail/official link without a precise chapter CTA. If internal artwork is missing, do not label manga art as anime art.

### Wiring contract

| Visible element | Real destination/state | Failure/accessibility requirement |
| --- | --- | --- |
| Poster Anime/Manga target | Persistent account medium state → corresponding Home bundle/projection. Art uses current prioritized title, else eligible saved/followed title, else neutral; selection remains stable during scrolling/import. | ≥44pt both choices; keyboard/VoiceOver selected state; no vertical-drag switching, stale data cross-medium or fabricated art count. |
| Taste/page navigation | Existing pager/router; left from Home enters recommendation page. | Horizontal page swipe loses to vertical scroll/child rails; back retains medium/scroll. |
| Anime title/art | Correct series detail with exact resume entry. Season marker opens full season overview. | No tracking mutation; dismissal returns origin/focus; unavailable mapping falls back entry detail. |
| Manga cover/title | Correct Manga detail, one meaning throughout target. | No image-select/text-navigate split, workbench or forced select-to-track. |
| Advance / set position | Shared durable coordinator, exact entry/unit, explicit status intent when needed. | ≥44pt separate from detail; pending/confirmed/conflict/error states; no duplicate on double tap, scroll/pointer cancel or lost response. |
| Save/follow/start/resume | Explicit list/series-intent command and returned projection. | Empty/untracked states work; clear affected scope; failed write keeps prior state and action usable. |
| Coming Up glance/date/more | Scroll/focus into same calendar; event opens exact source entry/section. | Counts/order survive grouping, unknowns separate; one shared projection and bounded paging. |
| Season panel/return-current | Inspect section ID; return-current restores view selection only. | Selected versus tracked distinction, generation/cancellation, no inferred watched state. |
| Unit row/disclosure/more | Unit detail/spoiler info; expansion/pagination with exact parent. | Track button separate; next-unit unavailable at end, fractional labels preserved; retain focus/expansion during patching. |
| Synopsis/character | Optional disclosure/inline bio or existing entity sheet. | Non-spoiler default; empty/missing info honest; no dead tappable portrait. |
| Song link | Verified external track URL or explicitly labelled search. | External failures do not block progress; no autoplay, fake play or embedded copyrighted audio. |
| Source/On screen/guide | Stored typed adaptation; internal detail or official source; verified season coverage. | Missing/disputed mapping no exact CTA; guide does not mutate either medium. |
| Club members/activity | Allowed deduplicated roster, original entry scope and club origin. | Membership/rank enforced server-side; no forbidden names/counts; no fake club-room privacy. |
| Leave a thought/edit/delete/reaction | Existing social model plus persisted spoiler scope. | Draft survives failed send; empty/length/rate limits, revoked membership and auth handled; own scope retained. |
| Undo/retry/conflict | Shared mutation intent/receipt and affected projection. | Focus/scroll stable; no false success or infinite retry; no repainting unrelated cards. |
| Import CTA/progress/exit | Existing import entry point with durable typed job; readiness revision. | No fake totals, frozen spinner, concealed truncation, or background polling after leaving. |

### Motion, depth and accessibility specifications

Press target response is immediate and reversible: shallow inset/highlight with ~0.985 scale only where artwork remains crisp; ≥9pt movement cancellation in prototype is a reference, not a native touch constant. Use existing iOS gesture policy and verify scroll-versus-tap physically. No contact after cancellation/background/dismissal. Settling springs are bounded; optional selection/content crossfades ~180–260ms; no repeated stagger on refresh. Reduced Motion uses direct state/short opacity, with no parallax/page flip needed to understand progress.

Native haptic once for durable accepted progress/selection where appropriate, quiet error feedback on actual rejection and no repeated remote-sync vibration. Respect device/accessibility availability. Controls carry descriptive labels, selected/current/pending traits, header semantics and explicit focus return. Color is not the sole status/season indicator. Test largest accessibility text, long localized titles, high contrast, screen reader ordering and iPad touch/keyboard; reflow controls rather than compressing targets. Use existing typography/spacing/radius tokens, plus named artwork-material tokens; no hardcoded device width or UIScreen.main.

## 8. Exactly two waves — six integrated work packages

A wave is a releasable integration boundary, not every small task/commit. Work packages below consolidate the original16 task IDs for traceability. Each has owner, dependencies, output and acceptance; one lead integrates the result. Parallel executors may work only after shared contracts are agreed and with explicit file ownership; do not have two agents edit the same core file blindly.

### Wave 1 — Complete data, ingestion, serving and sync foundation

**Status: NOT STARTED. Lead: backend/integration executor.** Native contract fixtures may be prepared, but production callers stay on the old path with new feature flags off.

| Work package | Original tasks / owner | Execution and output | Success gate |
| --- | --- | --- | --- |
| F1 Baseline + identity + contracts | W1.1–W1.4 / data-contract owner | Pin source/dirty diff; execute section12.1 database/call/schema/RLS audit before implementation, inventory every writer/reader/subscription and latest effective migrations. Resolve proposed entity reuse; make fixture expectations explicit. Add replayable RLS/grants/constraints/indexes, stored identity/membership/units/evidence and atomic correction resolver. Capture typed contracts and error fixtures. | Correct arrival-order/renamed/same-title/novel/remake/split-season cases; no replaced catalogue IDs; missing references retained; failed refresh preserves valid mappings; unauthorized maintenance rejected. |
| F2 Ingestion + enrichment + import readiness | W1.5–W1.6 / ingestion owner; depends F1 identity/contracts | Harden current import/relation worker family, both-provider typed adapters/field fidelity and durable job/checkpoints (section12.5). Add material/copy/theme/coverage/release evidence pipelines with source gates. Test backfill in isolated environment, corrections/Undo and progressive Home revision. | Pagination exhausted or explicit partial; replay/crash/cancel/rate-limit safe; no newer local state overwritten; publisher schedules not guessed; all user/social references accounted for before/after; optional adapters unavailable honestly. |
| F3 Bundles + mutation server + foundation qualification | W1.3/W1.7/W1.8 / serving-sync owner; depends F1, consumes F2 | Implement bounded Home/detail/Collection aggregates, cursors/cache invalidation/privacy. Progress receipts/revisions and explicit intent contracts. Review indexes/query plans under large-table growth and1000/5000 sessions; contract, replay, real-DB rapid-edit/lifecycle races, membership revocation/realtime, RLS, integrity and rollback tests (section12). | One versioned contract family; no provider fan-out/N+1/global graph scans; exact idempotency/conflicts; partial metadata isolation; zero reference loss/privacy defects; budgets measured and all foundation checks pass. |

**Within-wave order:** F1 contract/baseline → F1 additive test schema → F2 resolver/import/enrichment and F3 serving against the same fixtures → lead integrates → review → F3 gate. Do not delay the server mutation contract to the UI wave. Dry-run/backfill and source qualification are Wave1 work, not ad hoc production experiments.

**Wave1 exit:** section12 database audit and integrated critical fixes, both-provider fidelity/connector gate classification, growth/query plans, real mutation races and membership-revocation tests are complete, with1000/5000-session backend capacity qualified or an explicit blocking evidence gap. Then isolated/local or explicitly authorized staging migrations replay from a clean baseline; typed contract examples and executable behavior agree; two-user RLS tests, duplicate/concurrent import, relation correction, receipts and failure injection pass; backfill reconciles all touched references; cost/coverage limitations are documented. Old app remains usable. Foundation gate result is an explicit signed ledger entry. A passed local gate does not authorize live migration/backfill or enablement.

### Wave 2 — Complete native Home/detail experience, wiring and qualification

**Status: NOT STARTED. Lead: native/integration executor. Depends on Wave1 foundation gate.**

| Work package | Original tasks / owner | Execution and output | Success gate |
| --- | --- | --- | --- |
| X1 Shared native state + Home/navigation/import | W2.1/W2.2 / Home-state owner | Typed services/models, shared account projection and durable SQLite coordinator, lifecycle drain, persistent medium/scroll, existing five-page pager wiring. Build accepted Anime/Manga Home/calendar/private-club summaries and durable import progress/readiness UX. | All current titles/events cursor-accessible, initial glance visible, correct personalized batches, no per-tap full refresh, offline rapid changes survive restart, no gestures/actions collide; no fake fixtures in real service path. |
| X2 Both details + privacy + dependent surfaces | W2.3–W2.6 / detail owner; depends shared X1 state/contracts | Build accepted Anime/Manga hierarchies, selected-section data and material continuity; songs/source guide/cast/creators/Between us. Update deep links, Collection/search/Taste recommendation entry points and existing club/statistics consumers for series identity. | Every wiring row works with real data/errors. Season browse != resume/write; Manga true synopsis/bookmark and reciprocal guide; latest club privacy/spoilers/pagination persist; old URLs/comments/history/exports remain valid. |
| X3 Integrated device/performance/release preparation | W2.7/W2.8 / QA lead + independent reviewer | Full acceptance matrix and section12 closure gates, exact visual overlays, physical device/accessibility/scroll+haptics, clean build/unit/UI/integration tests and measured mixed-load/burst/soak request traces. Re-review fixes, opt-in flags, backward compatibility and rehearsal rollback. Prepare reviewable release package. | All mandatory tests pass or block release explicitly; no unsupported environment claim. Exact artifact/SHA/flags/DB revision/screenshots available; owner approves final native design and authorized target release. |

**Within-wave order:** X1 state/outbox lifecycle first → Home and X2 selected-section composition → all navigation/social/import/list entry points wired → X3 integrated failure/accessibility/performance review → fixes and focused re-review → release candidate. Contract-backed native mocks may aid development, but remove every stub from the qualified real-service route before exit.

**Wave2 exit:** a real imported account can use Home → exact season/edition detail → progress/Undo/offline → Collection and back, receive verified upcoming/club changes, and recover from failures without corruption/leakage. Screenshots alone do not pass this gate. Release preparation is complete only with the evidence below; production release remains separately authorized and verified.

## 9. Measurement and acceptance matrix

Budgets are **targets to validate**, never claims of current results. Measure on a specified representative supported iPhone, cold/warm app, representative network and isolated/staging PostgreSQL under recorded concurrency. Record sample count/distribution/dataset, median/p95 and query plans. A miss requires fixing or owner-approved budget revision before release, not quiet relabelling.

| Metric | Initial acceptance target |
| --- | --- |
| Home API | Warm p95≤300ms; cold p95≤1s; compressed page-one JSON≤100KB excluding artwork. |
| Detail initial API | Warm p95≤500ms; cold p95≤1.5s; initial compressed payload≤150KB excluding images; no franchise-wide hydration. |
| Local progress commit | Durable transaction p95≤50ms; immediate UI response after commit, no frame-blocking I/O on main actor. |
| Import→Home | First committed batch visible≤2s; terminal warm Home revision handoff≤1s or explicit usable partial state. No fixed promise for entire external5000-title import. |
| Requests | Home1 bundle; detail1 initial bundle and1 per selected-section/page action; mutation1 per bounded drain batch. Optional warmup documented separately, never per-card. |
| Database cost | Fixed, instrumented indexed read shape independent of visible card/franchise count; rows scanned/examined and plan regressions reported for50/500/5000 tracked entries. All loops/paging/batches bounded. |
| Scrolling | No persistent layout shifts or action-triggering drags; measure hitch/frame stability on target60/120Hz devices rather than claiming FPS from browser CSS. |

Development qualification profile:50/500/5000 tracked entries, fresh versus warm caches, concurrency1/10/50 clients in a disposable or authorized staging environment. These small profiles do not prove production capacity; mandatory1000/5000-session sustained/burst/soak and large-table gates are in section12.6. Record at least100 warm requests and30 cold requests per representative profile, workload/seed and cancellation/error counts; isolate provider fetch, SQL execution, network and image decode. Never load-test production implicitly. If a profile cannot be run, its measurement gate remains pending.

### Required tests with observable outcomes

| Group / cases | Success parameters |
| --- | --- |
| Legacy writers / precise position | A pending offline mutation detects a direct legacy/import write through a new revision; fractional unit identity survives new reads/export/restart. Old clients never silently round/misroute the position. Unsupported write compatibility blocks enablement. |
| Catalogue identity | Same title/different source, changed language/title, comic versus novel, remake/spin-off, canonical film/recap, split cours, single-entry long anime: expected approved or singleton grouping, stable IDs and source-local positions preserved. |
| Concurrent ingestion/corrections | Two new-season jobs, missing target arriving later, source omission, partial refresh, worker death after delete/stage, merge/split reversal: no duplicate approved membership or reference loss; prior published data survives failure. |
| Imports | AniList account/list + MAL account connector qualification and validated MAL export, both media and supported field fidelity; duplicate/reimport;0/1/50/400/5000 mixed titles; private/invalid list, pagination rate-limit/truncation, malformed/oversized/XML entity/file attack, provider403/429, cancellation/logout/crash: explicit dispositions, safe bounds, resume checkpoint and honest totals. |
| Home readiness | Real current/planned data appears progressively; Home loaded revision≥terminal import revision before ready message. Empty selected medium remains separate; no generic suggestions masquerade as imported content; no hidden terminal unresolved items. |
| Home/calendar density | Six and many current titles,1/20/100 events including same series/day; short320×568 reference, standard/large phones and iPad: glance visible, all events accessible, exact counts, no overflows, ≥44pt targets. Dynamic Type may reflow, never clip or hide calendar access. |
| Release truth | Date-only/window/unknown/delayed/cancelled/stale/past unconfirmed, chapter versus volume, locales/timezones/DST, historical backfill: no guessed instant, false released badge, duplicate translation event or new notification from old data. |
| Detail state | JJK1↔2, deep link directly to later season, rewind/rewatch/untracked new user, fast out-of-order response, invalid section/revision, >1000 units: correct selected data, progress independent, paged units and honest fallback. |
| Manga/source guide | Unknown/fractional/restarted chapters/edition change; multiple anime adaptations, novel source, skipped/original ending/disputed map: exact source identity, no parts invention or end+1 claim, guide choice never mutates tracking. |
| Music/art/copy | Missing Spotify/provider metadata, TV-cut/cover mismatch, image404/decode/material revision failure, missing seasonal synopsis: readable neutral/fallback with correct context, no fake play/plot, identical current Home/detail material identity, no core-action failure. |
| Online progress | Correct exact entry/unit, receipts/revision, untouched notes/rating/status; single haptic after durable commit. Home/detail/Collection agree without full list reload. |
| Offline and response loss | Airplane mode/captive portal/DNS/connection lost before or after server commit;20 taps then force quit: local state survives, bounded retry acknowledges once, no false server-saved message. |
| Undo/concurrency | Unsent/in-flight/acked Undo, late read/ack, offline rewind, second device/import conflict, removal elsewhere: correct cancellation/compensation/conflict, latest local intent retained, no accidental recreation/max merge. |
| Account/lifecycle |401/session expiry/relogin/account switch/logout, app suspension/background expiry, disk full/corruption/schema migration failure: isolated retained intent, no cross-account delivery, no fabricated local success, safe checkpoint and recovery. |
| Club privacy | Two users without shared club, multiple shared clubs, rankprivate/status/progress, left/archived/revoked club, other account cache: no unauthorized name/progress/count/comment/text leakage; one person deduped correctly; real server authorization tests. |
| Comments/spoilers | Own legacy multi-entry comments,500+ chars/whitespace/rate-limit, failed send/edit/delete/reaction, spoiler across viewed seasons: original entry preserved, draft retained, scope persisted, hidden text only revealed explicitly. |
| Navigation/compatibility | Old anime/manga/club/collection/discover/concierge/auth URLs and notification route, entry aliases, search for season synonym, saved/list batch actions, exports/stats: correct destination, no duplicates/double counts/lost history, no auth/onboarding regression. |
| Accessibility/interactions | VoiceOver headers/labels/focus/selected-current-pending, largest text/long EN-DE titles, keyboard, high contrast, Reduce Motion, physical scroll-vs-tap/rails/medium gestures: every control reachable and deliberate; focus/scroll return retained; no accidental tracking/navigation. |
| Cost/regression | Instrument every new page-open/mutation/import invalidation path; query plans/rows/payload/call count under accounts/concurrency, lifecycle cancellation and memory growth: bounded indexed cost, no N+1/endless fetch/global scan, budgets met. |

Do not claim the full table tested from fake-DB unit mocks. Use disposable PostgreSQL for transaction/RLS/concurrency proof; authorized staging for integration when needed. If unavailable, document the missing test and leave its gate open. Browser geometry is a visual reference only. Build on the exact supported simulator listed in AGENTS; no simulator boot or physical-device access without applicable authorization. Physical-device haptics/touch/VoiceOver must be recorded, not inferred from simulator/browser.

## 10. Review, rollout and executor ledger

### Review checkpoints

1. **Contract review inside Wave1:** identity/migration constraints, privacy and mutation receipts/import merge policy; approve fixtures before callers depend on them.
2. **Wave1 foundation review:** isolated replay/backfill, correctness/concurrency/RLS, coverage and query/payload evidence. Lead integrates and resolves findings; re-review changed paths. No native rollout on failed foundation.
3. **Wave2 design/wiring review:** compare native current/empty/dense/error screens to pinned accepted references. Check every wiring row and exact child/account state; owner reviews actual native screen quality.
4. **Wave2 end-to-end/release review:** complete matrix, source/local/staging evidence, backward compatibility and rollback. Critical correctness/privacy/data-loss findings block release. No silent waiver of missing physical/device or hosted proof.

### Release and rollback

Prepare two named flags (or reuse equivalent documented flags): series foundation serving and native Home/details, off by default. Old clients/old entry routes remain compatible; deploy additive DB contracts before a consuming app only after authorization. Source adapters have separate readiness switches. Rehearse disabling new serving/UI, rollback to old entry-based reads, and mapping revision reversal **without deleting new user activity**. Preserve durable pending mutations; turning the UI flag off cannot strand or replay them through legacy full-row upserts. Do not use production migration rollback as an excuse to drop receipts/queues.

Before release: exact app artifact/SHA, migration checksums/order, deployed function versions, feature flag/config values, tested rollback, source permissions, screenshots/video and performance/privacy evidence. After authorized release: verify installed/released build against live project using a real happy/failure journey and record live observations separately. Prepare metrics for import dispositions, revision lag, outbox age/receipt conflicts, unknown mapping/release coverage, endpoint p95/query count and privacy failures; logs exclude credentials/comment text/private import contents. No new cron/heartbeat/public tunnel from this plan.

### One execution ledger — fill in place

| Item | Status | Evidence / owner / next condition |
| --- | --- | --- |
| Planning specification v1.1 | COMPLETE FOR REQUESTED SCOPE | Consolidated on4October; production audit/concurrency/revocation/import/capacity extension and Claude Code handout added5October2026. Implementation not started. |
| Source/prototype baseline | INSPECTED LOCALLY | HEAD471c609 + dirty work; prototype proof does not establish native/hosted state. Re-pin before execution. |
| F1 / F2 / F3 | NOT STARTED | Contracts/schema, ingestion/enrichment and serving qualification pending. |
| Wave1 exit | NOT PASSED | Needs isolated real DB, import/concurrency/privacy/cost and review evidence. |
| X1 / X2 / X3 | NOT STARTED | Native state/Home, details/compatibility and full qualification pending. |
| Wave2 exit | NOT PASSED | Needs every wiring row, real journey and device/accessibility/performance review. |
| Staging proof | NOT VERIFIED | Environment-specific check after authorized implementation. |
| Production/release | NOT AUTHORIZED BY THIS PLANNING TURN; NOT VERIFIED | Separate applicable release authority and exact live proof required. |

For each work package append: pinned SHA+dirty diff, owned files/contracts, implementation result, exact checks/data/environment, acceptance rows passed/failed/not run, measured latency/payload/query counts, screenshots, reviewer findings/fixes/re-review, rollback proof and next condition. Keep progress granular without adding delivery waves. A complete handoff must explicitly report absent optional metadata as an intentional fallback and mandatory missing proof as unfinished work.

### Definition of fully wired

Every accepted visual element has a typed state source, server or durable-local action, valid route, ownership/auth rules, finite lifecycle/cancellation, error/empty/partial state, pending/confirmed behavior, and demonstrated acceptance result. All entry points use the same coordinators/contracts; there is no fixture-only bypass, disabled fake CTA or divergent progress copy. Home reflects a real imported account; details reflect the chosen entry/section; updates reconcile across Home/detail/Collection; all allowed club information is private and all unknown source claims remain unknown. This is the implementation exit condition, not the current state.

## 11. Research and historical evidence references

Capabilities are not live coverage, licensed reuse or permission to activate an adapter. These references support the requirements; qualification remains explicit in Wave1.

- [AniList Media schema](https://raw.githubusercontent.com/AniList/ApiV2-GraphQL-Docs/master/docs/reference/object/media.md) and [media query/relations guide](https://github.com/AniList/docs/blob/master/docs/guide/graphql/queries/media.md): stable media IDs/relations, aliases and selected detail metadata; no dedicated OP/ED collection in the inspected schema. Rechecked official schema4October; no successful live title API response claimed.
- [AnimeThemes content](https://github.com/AnimeThemes/animethemes-api-docs/blob/main/docs/jsonapi/reference/content/index.md), [theme entries](https://raw.githubusercontent.com/AnimeThemes/animethemes-api-docs/main/docs/jsonapi/reference/content/animethemeentry/index.md), [resources](https://github.com/AnimeThemes/animethemes-api-docs/blob/main/docs/jsonapi/reference/content/resource/index.md): candidate metadata/episode context/external sites. Theme entry docs rechecked4October; title coverage and retention permission not certified.
- [MangaUpdates API](https://api.mangaupdates.com/) and [OtakuPeople data](https://otakupeople.com/data): continuation candidates inspected in the prior review, not integrated/comprehensive sources. Preserve raw strings/confidence/evidence/date/attribution; verify actual season and reuse conditions before enabling.
- [MANGA Plus FAQ](https://mangaplus.shueisha.co.jp/faq/eng/), [VIZ release calendar](https://www.viz.com/calendar/2026/12), [MangaDex API docs](https://api.mangadex.org/docs/), [MAL API reference](https://myanimelist.net/apiconfig/references/api/v2): supported publisher/format/locale scope must be qualified. No verified universal publisher feed or MAL connector follows from these links.
- [Apple background strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app) and [background task setup](https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app): scheduling/expiration shape opportunistic drains; durable foreground recovery remains required. Official strategy reference rechecked4October.
- Publisher sources for new sample story copy: [Solo Leveling comic1](https://yenpress.com/titles/9781975319434-solo-leveling-vol-1-comic), [Berserk catalogue](https://images.darkhorse.com/common/salestools/catalogs/DH_Backlist_2011.pdf), [SPY x FAMILY1](https://www.viz.com/manga-books/manga/spy-x-family-volume-1/product/6302/digital), [Vagabond](https://www.viz.com/vagabond). Hook/lens are editorial; sample copy is not a catalogue-wide ingestion result.

## 12. Production execution contract — 5 October 2026

This section extends the same two-wave plan. It is mandatory alongside sections1–11; it adds no third wave. Performance is part of correctness throughout implementation, not a late optional optimization. Requirements below are decisions and acceptance targets, not measurements or proof of an existing deployment.

### 12.1 Mandatory database audit prompt — run before editing implementation

Paste this instruction into the executor's first work item:

> Before changing the implementation, inspect the actual current schema and every application/database call again. Pin HEAD, dirty work, migration files and the authorized target environment. Trace Swift callers, RPCs, Edge Functions, imports, legacy writers, realtime subscriptions and background workers. Establish the effective deployed function/RLS definitions where read access is available; local migration files alone are not deployed proof. Find whole-table requests, unbounded relationship traversals, N+1 hydration, duplicate refetches, expensive counts, offset pagination, per-row membership functions, cast-disabled indexes, broad realtime fan-out and hot global locks. Review anime/manga identity, seasons, units, provider references, list ownership, comments/reactions, club membership, evidence tables, jobs and receipts for integrity, indexes and growth. Produce a call inventory, schema/authorization map, measured plan evidence and a prioritized problem→fix register. Run expensive execution plans/concurrency/load tests only on a disposable or explicitly authorized staging database. Implement the resulting fixes within Wave1, preserving existing IDs and unrelated work. Do not proceed to a production-ready verdict while mandatory query, permission or capacity proof is absent.

**Required audit artifacts**, under a dated evidence directory selected and recorded by the executor:

1. `baseline.md`: SHA+dirty diff, database/server/client versions, migration/function parity, target identity, available permissions and unknowns. Never log connection passwords, service keys, provider tokens or private comments.
2. `call-inventory.csv`: every call site → trigger → endpoint/RPC → concrete tables/predicates → selected columns → limit/cursor → auth/RLS → indexes → request/query/fan-out count → invalidation/cancellation → current risk → planned fix → evidence path. Include startup/auth, Home/Taste/Discover/Browse/Collection, details, list mutations/batch changes, comments/reactions, clubs, imports/Undo, scheduled workers and cleanup. An existing path outside the redesign still needs an audit row; unrelated defects may be recorded separately, but a privacy/integrity/performance defect on an integrated path blocks its gate.
3. `schema-and-access.md`: ER relationships, typed FKs, delete/cascade behavior, unique/check constraints, user TEXT/UUID casts, grants, policies, SECURITY DEFINER owners/search paths, views/materialized views, private Storage and realtime channels. Distinguish source-entry identity, logical continuity, season, manga edition, publication unit and user position. No giant nested per-user copy of an entire catalogue and no new MongoDB layer.
4. `plans/`: representative exact SQL or traced RPC statements and parameter distributions; planning/execution time, rows returned/examined, loops, buffers, sort spills, lock waits and RLS role. Use anonymized/synthetic data. Capture hot-path query statistics where available without resetting shared production statistics. An unexecuted EXPLAIN is a predicted plan, not measured latency.
5. `findings.md`: confirmed behavior versus source risk, severity, reproducer, affected endpoints, minimal fix, migration compatibility, test and closure proof. A small-table sequential scan or offline maintenance scan can be appropriate; the failure is repeated unbounded work on growing tables in a user hot path. Do not install indexes merely to make every plan display Index Scan.
6. `capacity.md`: workload, dataset/seed, authorization identities, resources/pool limits, request arrivals, latency/error/queue/connection measurements, cost assumptions, saturation boundary and honest qualified capacity. Record unavailable hosted evidence explicitly.

**Schema/query decisions:** use indexed account-first list predicates, provider+external-ID uniqueness, typed entry/section/unit FKs, indexed membership lookups in both directions and keyset-compatible event/comment/order indexes. Verify actual join/filter/order combinations; an index name is not evidence of usefulness. Prefer EXISTS for eligibility and bounded lateral/aggregate reads; pre-limit before expensive hydration while preserving correct series grouping/count semantics. Avoid a cast on the indexed legacy column where a safe parameter-side cast suffices. Inventory FK lookup indexes, JSON predicates, aliases/search plans and secondary-index write cost. Keep hot progress rows small; catalogue metadata, user notes, sources and activity are separate records. Partitioning is a measured growth/retention decision, not a default rewrite.

**Operational safety:** use read-only statistics and EXPLAIN without execution for sensitive live queries unless explicitly qualified. EXPLAIN ANALYZE executes the statement; DML, triggers and external side effects must not be tested against production under a rollback assumption. Use reproducible isolated migrations/seeds for write plans. Set measured per-path statement/lock timeouts and bounded retries; a timeout cannot be turned into a false success. Rehearse index/backfill lock impact and feature compatibility before an authorized release.

### 12.2 Hot-path request shape, cache and connection ownership

| User operation | Required bounded behavior | Verification |
| --- | --- | --- |
| Open Home | One authenticated bundle with active titles, first release projection and allowed club summary. Resolve fixed-size ID batches in SQL; no card-by-card catalogue, progress or social calls. | Trace0/50/500/5000-entry accounts; same bounded page shape, no catalogue-wide walk. |
| Open/switch detail season | One initial/selected-section bundle; fetch only requested units/cast/theme pages. Cancel prior inspection request; ignore stale responses by selection and account generation. | Switch ten times with deliberately reordered responses; inspected data never overwrites current tracking or another selection. |
| Advance/rewind/edit status | Durable local intent, bounded field-specific mutation batch, one response patch to shared state; no fetchUserLists/Collection/upcoming sweep per tap. | Burst50 taps across ten titles; correct positions, bounded drains and zero full-library reloads. |
| Add/delete/save/reorder | Explicit create/remove/field update contract with identity/lifecycle/revision. Optional existing shelf memberships are separate from progress. | Duplicate delivery, add→delete→add, concurrent add/remove and ordered shelf changes preserve explicit intent. |
| Comment/react/private people | Bounded entry-scoped feed and aggregates, current database authorization, canonical spoiler scope, revision/idempotency for writes. | Multiple shared clubs do not duplicate people/reactions; revoked viewers receive neither private text nor stale aggregate disclosures. |
| Import | One durable job; provider pagination and catalogue enrichment off the request path; bounded apply batches and one Home invalidation per committed batch. |5000 items do not mean5000 page-open calls or an unbounded Edge invocation. |
| Realtime | Subscription lifecycle tied to account/screen/membership; bounded coalesced refresh of affected projection. | Measure subscribers×events×authorization checks and resulting fetches; unrelated clubs do not trigger a full reload. |

A bundle is not permission to hide an unbounded scan inside one giant RPC. Record SQL statements and row work behind it. Cache public catalogue/material by identity+revision; user data by account+medium+revision; social data additionally by current permission generation. Do not share authenticated responses through an unkeyed CDN/cache. Single-flight identical reads, jitter optional cache refresh, and collapse invalidations without dropping the newest revision. Define a finite stale-data policy per payload; private club bodies use no persistent offline cache in the first delivery. Core progress must survive failed optional enrichment.

Keep Supabase SDK/Data API as the client boundary. Inspect existing PostgREST/Edge pool configuration before adding direct connections. If a worker/Edge path genuinely needs a driver, use the appropriate existing pooler, transaction-local state and bounded module-level connection ownership; never allocate one PostgreSQL connection per phone/user. Measure pool wait, active/idle connections and timeout rates. Do not set max_connections higher as a substitute for query/backpressure work. Supabase documents serverless transaction pooling and its session/prepared-statement limitations; verify against the installed driver and backend version. [Connection guidance](https://supabase.com/docs/guides/database/connecting-to-postgres).

Separate foreground reads/mutations from import/enrichment/backfill admission. Initial safety caps to qualify: one active job per account+provider+medium, at most four provider fetches per worker, apply batches≤100 rows and mutation batches≤50; honor provider-specific lower limits and measure resource usage before raising them. Preserve transaction boundaries when splitting large jobs. A page open never starts per-title upstream enrichment synchronously. Bounded admission failures surface retryable state; queues have age/size metrics and recoverable checkpoint leases, not indefinite fire-and-forget promises.

### 12.3 Rapid edits, ordering and race-condition contract

Serialize **conflicting operations on the same tracking entry/lifecycle**, and permission-sensitive transactions on their authorization boundary. Allow bounded concurrency across independent entries/accounts. Do not serialize the entire application, all users, all imports or all rows behind one actor/database advisory lock. Swift rendering stays on the main actor; disk/network/decode work does not block it. Cancellation controls presentation, but cannot undo a committed server write.

For each mutation: generate a stable UUID once; persist account, exact entry/unit/edition, lifecycle, field mask, absolute desired value, base server revision and local sequence. In one server transaction, validate ownership/current membership as relevant, validate lifecycle and revision, update only declared fields, apply the database-owned version fence, insert the receipt and return canonical state. Duplicate key+same hash returns the same outcome; same key+different payload is rejected. Never apply an increment twice after response loss. Updating progress cannot overwrite a simultaneous rating, note or shelf edit.

Coalesce only unsent progress intents for the same entry when it preserves the user's final absolute position and Undo semantics; never silently coalesce status/removal/completion or an already in-flight request. Maintain the acknowledged server base separately from pending local intent. Drop stale read/ack projections without dropping receipts. A conflicting newer device/import edit requires defined reconciliation, not `max(progress)` or client-clock last-write-wins. Preserve explicit backwards edits and rewatch/reread transitions. Feed revisions must be monotonic per relevant account/context, without a global catalogue revision row locked on every user tap.

Removal advances a persistent lifecycle/tombstone fence so old offline writes cannot recreate the deleted entry. A deliberate later add receives a new lifecycle; replaying the earlier remove cannot delete it. Absence of a row alone cannot detect a stale write. Cover remove versus save/follow, comment deletion versus late edit, reactions toggled rapidly and season-resume selection versus read-only inspection. Exactly-once effect is achieved within a documented receipt retention horizon; beyond it reconcile rather than blindly replay. Retention/cleanup uses bounded batches and cannot run a full receipt scan per mutation.

Transaction retries for serialization/deadlock failures repeat the whole transaction with the same key and bounded jitter; lock rows in deterministic order. No upstream HTTP calls or long await inside locked transactions. Cross-field independent changes may merge only when their field revision/mask proves they do not conflict; otherwise return a typed conflict. Foreign-key/unique violations are classified, not endlessly retried. Deleting an account cancels/rejects its jobs and drains without resurrecting state.

Worker claims/checkpoints use a bounded lease plus monotonic fencing token. A stalled worker whose lease expired cannot publish counters, overwrite a newer mapping revision or advance a resumed job checkpoint. Claim with an atomic compare-and-set or equivalent transaction; use SKIP LOCKED only where its queue semantics are appropriate, not to silently skip user mutation conflicts. Catalogue-provider enrichment is single-flight by source ID across jobs, while each account keeps its own authorized dispositions. Test lease expiry, two claimers, delayed old-worker completion and process kill after apply commit. Batch snapshot/progress counters commit together; a duplicate receipt does not increment counters twice.

**Concurrency tests use actual PostgreSQL transactions and barriers**, not sequential mocked requests:

| Interleaving | Expected outcome |
| --- | --- |
|50 rapid taps, reordered replies, same receipt replay100 times | Latest accepted local position survives; one effect per receipt; bounded queue/request count. |
| Two devices advance/rewind same base revision | One canonical revision wins; other receives conflict/reconciliation; no lost rewind or manufactured completion. |
| Progress + rating/note/status edits | No unrelated fields overwritten; explicit dependent-status semantics enforced. |
| Add/delete/add with old queued actions and import retries | No duplicate row, accidental resurrection or deletion of the new lifecycle. |
| Import races current edit/remove and another provider import | Typed merge policy and receipt fences preserve newer deliberate local state; jobs report conflicts. |
| Duplicate job start, worker crash after commit before checkpoint | One logical job/item effect; restart resumes with consistent committed counters. |
| Membership removal versus comment/reaction write | Authorized-before-removal transaction may commit in defined lock order; operations authorized after removal fail. No stale check-then-write bypass. |
| Account switch/logout, stale selected-section/read responses | No cross-account projection or action delivery; canceled display cannot reappear. |
| Receipt cleanup, mapping correction or backfill versus user edits | User IDs/history/intents preserved; no global lock or revision bypass; stale mappings reconciled. |

### 12.4 Club removal, comments and realtime revocation

Server authorization uses **current database membership and effective club/member sharing settings** on each protected fetch/write. A cached JWT club list, channel name, UI hiding or client-supplied user ID is not authorization. Apply grants+RLS and correctly guarded RPCs/views/aggregates/reactions/counts; use auth.uid() ownership, safe search_path and qualified tables for SECURITY DEFINER paths. Test using real authenticated identities, not only service_role. Read success tests assert actual returned rows; denied writes assert both denial/zero affected rows and unchanged stored data. JWT claims can lag membership changes. [RLS guidance](https://supabase.com/docs/guides/database/postgres/row-level-security).

**Audience decision:** existing title comments are visible through the union of currently eligible shared clubs, not individually owned club threads. Leaving/kicking/archiving the only eligible shared club removes that audience connection. If another valid shared club remains, title-level visibility may legitimately remain at its effective sharing level; removed-club-specific messages, rail/poll content, membership and identities must still disappear. Preserve the existing trust-pack rank rules; private/status/progress cannot be reduced to a boolean shares_club_with check. Private imported notes are never comments and are never published by importing.

Commit removal and permission-generation change atomically; define consistent row-lock ordering for membership-sensitive writes. Prevent membership authorization based on an earlier SELECT followed by an unguarded insert. Return denial after committed removal for every newly authorized access. A request already authorized before that boundary may have delivered data: do not claim retroactive erasure of previously seen text/screenshots. Redact unavailable authors/progress/counts uniformly without an error side channel exposing private memberships.

On the native client, revocation/logout/account switch invalidates all affected social bundles, names, counts, images tied to private membership, notifications and active detail/club views; cancel requests, reject stale responses by permission generation and close subscriptions. Keep a personal unsent comment draft private, but require fresh authorization before submission. First delivery persists no offline club body cache; whenever authorization freshness cannot be established, hide private sections and show a concise reconnect state. This avoids promising that an offline device can instantly learn a remote removal. Re-authorize on foreground/reconnect and before showing a stale private projection. Ordinary personal progress stays usable offline.

**Realtime decision:** do not transmit comment/message bodies, member progress, private names or private image URLs through a channel whose membership can remain stale. Supabase's documented channel authorization cache may persist until token refresh/expiry; a private flag alone does not prove immediate revocation. Use a narrowly scoped, authenticated **per-account invalidation stream** with generic revision hints, or an equivalent demonstrably revocation-safe design. Determine recipients from current membership at dispatch; invalidate and fetch protected content through fresh database authorization. Already queued hints must contain no private body/identity/count/club identifier. A revocation signal reaches the removed user's own account stream; foreground reauthorization is the recovery path for missed signals. No claim of perfectly instantaneous network delivery. [Realtime authorization](https://supabase.com/docs/guides/realtime/authorization).

Audit and remove the currently inspected unfiltered `club_rail_items`, `club_votes` and `club_rail_item_reactions` subscriptions, or prove a bounded alternative. Filters on insert/update do not prove correct delete behavior. Postgres Changes has documented delete-event caveats and subscriber-scaled authorization costs; benchmark the installed behavior, test established stale-token subscriptions and never send sensitive old-row payloads on removal. Broad table event names are not private rooms. [Postgres Changes](https://supabase.com/docs/guides/realtime/postgres-changes).

**Required revocation test:** users A/B share club C; B has a connected channel, warm Home/detail caches, an open spoiler and pending edit. A removes B while B fetches/reacts. After committed removal, prove RPC/direct-table/count/reaction/write/Storage/notification paths deny or redact as intended, no subsequent sensitive channel payload reaches B, private UI clears on invalidation or reauthorization, late callbacks cannot restore it, and reconnect/logout/relogin remain denied. Repeat with a second valid shared club, rank downgrade, archived club, removing a comment author rather than the viewer, invitation acceptance/removal races and service-role worker broadcasts. Test delete and membership revocation separately.

### 12.5 AniList and MyAnimeList import fidelity — both mandatory

Deliver **both providers**, for Anime and Manga, within F2/X1 qualification. Implement typed AniList account/list ingestion and MAL export ingestion; also build the MAL account API connector where provider access/credentials permit, with explicit OAuth/access qualification before enabling it. Missing MAL API credentials are an unmet connector gate, not permission to call an XML-only path a working account connection. Finish its local contracts/failure tests and the functioning export alternative while awaiting the external dependency. Do not call a release fully qualified for account import while a required advertised connector is unavailable; owner must explicitly narrow scope to export-only if necessary. No password collection, silent provider write-back or production credential creation.

Each provider adapter declares fields actually available via authenticated account, public list or export. Capture response fixtures and provider version/docs before enabling. AniList has list fields for status/progress/volumes/repeat/notes/privacy/custom lists; verify the whole configured query and pagination, not just this schema list. The currently inspected importer requests normalized score/progress and emits reconciliation text: extend the structured path rather than implying it already preserves all fields. [AniList MediaList schema](https://raw.githubusercontent.com/AniList/ApiV2-GraphQL-Docs/master/docs/reference/object/medialist.md). MAL official reference could not be retrieved in this planning review; live field/pagination/export capability must be qualified before an API claim. [MAL API reference](https://myanimelist.net/apiconfig/references/api/v2).

| Source information | Destination and preservation rule |
| --- | --- |
| Provider user/list/item/media IDs, original medium/format | Retained typed source references; IDs drive matching. Same name is never automatic identity. Resolve or mark unmatched with a reviewable candidate; novel/comic remain distinct. |
| Watching/reading/planned/completed/on-hold/dropped/repeating | Explicit mapping plus raw source status. Preserve paused/dropped and repeat intent; series grouping never completes other seasons. |
| Episodes/chapters/volumes and reported totals | Exact child progress and original quantity/known-unknown state. Retain volume-only progress when chapter conversion is unevidenced; no guessed chapter bookmark. |
| Score and source scoring format | Original value+scale retained; normalized display separate, unset distinct from zero. No destructive POINT_10 conversion as sole archived value. |
| Notes, tags, priority, start/finish/update dates | Private per-entry fields or owner-only import provenance. Preserve fuzzy/partial dates and provider-specific semantics; sanitized rendering, no silent public comment conversion. |
| Rewatch/reread count and flags | Preserve separately from current position and explicit completion. Imported past repeats do not create new Home interaction timestamps. |
| Custom lists, hidden-from-status preference, order, private flags | Preserve all source memberships/names and ordering if provided in a constrained account-owned imported organization record or equivalent existing schema. Do not invent an unavailable order or flatten custom categories away. Multiple source groups can reference the same tracking entry. No new public shelf product is commissioned. |
| Unsupported/provider-only fields | Keep declared, bounded private provenance where permitted or expose Not supplied/Unsupported; never fabricate, silently discard supported data or fetch it through unrestricted HTML scraping. |

Import snapshot/provenance has an explicit bounded encrypted/private retention policy and deletion behavior; raw payload retention is permission-dependent and never includes OAuth tokens. If raw payload retention is forbidden, retain only allowed normalized/provenance fields with a field-loss report. Default **merge, never replacement deletion**. Three-way reconcile source snapshot, previous import baseline and current Kuro field revisions. Update untouched fields; preserve deliberate edits since baseline; report conflicts. A later source omission, pagination failure or private-list403 cannot remove local titles. An explicit replace mode requires a reviewable removal preview and separate owner confirmation; do not implement that destructive mode as a hidden default.

Process provider pages with checkpoints, counts/dispositions and an end-of-pagination condition. Validate host/size/type for pagination URLs; detect repeated/cyclic cursors, truncated pages and duplicates. AniList custom-list appearances can repeat an entry: dedupe by provider item/media identity while unioning valid memberships. MAL anime and manga streams have independent progress/checkpoints; one completed stream does not mark the other completed. Support files from the user's device via system picker with hard compressed/uncompressed/item/text/depth bounds, XML external entities disabled and safe temporary deletion. Unknown catalogue IDs become retained pending matches, not title-only guessed list entries.

Apply deterministic bounded transactions. On crash between DB commit and checkpoint, receipts make replay safe. First committed eligible titles populate Home immediately from the job's recorded Home revision; ordering remains stable as batches arrive. Job terminal state waits for its personalized projection revision or exposes usable partial readiness. Optional release/music/cast enrichment cannot hold the entire import screen hostage. Animation reflects genuine work/minimum visual transition only; no fabricated progress or artificial delay covering errors. Export a fidelity report with added/updated/unchanged/conflicting/unmatched/unsupported counts and preserved field counts by source. Imports retain old seasons' independent scores/notes/history while Home groups them.

**Provider tests:** account/public/private permissions, both media0/1/50/400/5000 entries, every status and rating format available, repeat/volumes/fuzzy dates, duplicate custom lists, same-title unrelated works, rename/cross-provider aliases, stale score/notes/progress, conflicting local changes, deleted Kuro lifecycle, source omission, expired OAuth,429/Retry-After,5xx, pagination cycle/partial results, corrupt/oversized export, worker restart/cancel/logout and reimport. Verify field-by-field fidelity and no provider-side writes. No source's list is exposed to club peers by default.

### 12.6 Thousands of concurrent sessions — qualification, not a slogan

The baseline1/10/50-client tests are development checks, not the production capacity gate. Qualify **1000 and5000 concurrent application sessions** with realistic arrivals and separate connection limits. Initial test contract below is provisional workload, not a traffic forecast or capacity claim; document any owner-approved adjustment before release. Load generation is local/disposable or explicitly authorized staging only. Do not create paid capacity or production stress automatically.

| Profile | Workload and duration | Required evidence |
| --- | --- | --- |
| Growth datasets | Synthetic100k then1M catalogue rows,1M then10M tracking rows, representative multi-million comment/receipt/event tables;50/500/5000 items per active account. Preserve production-like selectivity, skew, index width and RLS. If these sizes cannot be provisioned, record the missing large-table gate. | Row distributions/index sizes/seed/hardware, measured plans at both growth scales and no growing global scan per bounded request. |
|1000 sessions |300 API requests/sec for30 minutes after warmup; at least1000 distinct authenticated test accounts; randomized think time and title selection. Mix35% Home,25% detail/season/pages,15% Collection/search,20% progress/list writes,5% comment/reaction/private activity. | Offered/completed throughput, p50/p95/p99, application errors/conflicts, RLS/query work, pool/lock/CPU/memory/IO, queue age and generator headroom. |
|5000 sessions |1500 requests/sec for30 minutes with same mix/distributions and at least5000 accounts; separately model up to5000 connected realtime sessions and the actual maximum active subscriptions. | All endpoint budgets stay met at admitted workload; no resource leak or unbounded pool/fan-out. Distinguish websocket sessions from simultaneous SQL transactions. |
| Burst and contention |2× arrival rate for60 seconds,50 rapid taps/account across ten entries, same-entry two-device collision,100 simultaneous import jobs of5000 entries and hot public-title reads across unrelated private accounts.5% of mutations contend within the same permitted account entry to exercise conflicts. | No corruption/leak/duplicate effects; honest bounded admission/retry, recovery to steady queue level within5 minutes after burst; foreground SLOs tested while import workers run. |
| Soak | At least2 hours at the highest passed sustainable profile, mixed account switches/cancel/reconnect/session expiry and scheduled maintenance overlap. | Stable memory/connections/subscriptions/receipt counts, no endless polling; optional queues drain or retain actionable recoverable state. |

The stated sessions and RPS are **independent chosen inputs**; users do not each perform one request per second or require a database connection. Use a paced/open-arrival-rate HTTP harness so a slow server does not silently reduce offered load. Record dropped iterations and load-generator saturation; never report an under-driven run as a pass. Use seeded randomized operation mixes plus deterministic correctness races. Requests use real test JWTs/roles and per-account data, not one service_role bypass. Do not hit external providers at benchmark scale: contract-backed source fixtures qualify queue behavior, and small approved provider probes qualify integration separately.

Initial acceptance targets extend section9: normal admitted requests meet its Home/detail latency/payload budgets; mutation server warm p95≤300ms/p99≤1s excluding local offline delay; steady-state unexpected5xx/timeouts<0.1%, zero correctness/privacy/data-loss violations. Expected validation/conflict/429 results are classified separately but still counted; rate limiting cannot masquerade as passing the requested steady throughput. Publish end-to-end network and server/SQL timing separately. Burst overload can reject with bounded retry hints; it cannot lose durably accepted actions. Queue capacity/latency and database query counts remain bounded; measure against agreed limits, not only average CPU. A capacity miss is a failed release gate until fixed or explicitly accepted as a lower supported capacity by Max.

Postgres locks should protect individual invariants while independent requests proceed. Review row contention, transaction length, lock order and retry rates with exact PostgreSQL version behavior. [Explicit locking](https://www.postgresql.org/docs/current/explicit-locking.html). Inspect plan estimates and actual measured work rather than assuming table size/one bundle proves speed. [EXPLAIN](https://www.postgresql.org/docs/current/using-explain.html).

### 12.7 Exact design transfer and release evidence

Implement the selected browser geometry/material/hierarchy/controls **one-to-one in native SwiftUI**, adapted only for safe areas, Dynamic Type and real data. No replacement design, generic cards, different Manga sizing or reintroduced season number rows. Pin the selected source and dependency hashes, capture phone-size baselines for both media and details, then compare matching native states with overlays and annotated differences. The first screen, all scrolling sections, season chooser, chapter/bookmark controls, source guide and private discussion must be compared; one hero screenshot is insufficient. Artwork placeholders cannot substitute for loaded-art fidelity approval. Prototype buttons are references for intent, not permission to ship fixture logic.

At320/390/430pt phone content widths and supported iPad layouts, verify equal Manga cover geometry, shallow landscape Anime detail, first-viewport Coming Up, readable titles, no clipped/overlapping/safe-area controls, ≥44pt distinct targets, scroll/tap separation, focus/scroll restoration and current-versus-inspected season state. Dynamic Type/VoiceOver/Reduce Motion and real device haptics remain mandatory. Pixel-identical typography may vary by platform rendering; any visible material/composition deviation must be explained and owner-approved, not called one-to-one after a token approximation.

**Portability:** this checkout contains dirty/untracked prototype files. Another machine pulling HEAD alone may not have the selected design. The handout includes the current dependency manifest: ensure those exact files are present on the implementation branch or transferred through an authorized private artifact before native work. A missing wrapper/asset is a missing reference, not permission to recreate it from memory. Do not automatically commit/push unrelated work. Version references and screenshots as qualification artifacts when executing.

**Two-wave integration additions:** F1 now starts with the full database/call audit and critical remediation contracts; F2 owns both-provider field fidelity, checkpoint/import contention and provider qualification; F3 owns bounded hot paths, durable mutation/lifecycle races, revocation-safe social/realtime and real-DB capacity proof. X1 uses those contracts for all Home/list/import mutations; X2 applies current permission generation and selected-context bundles on every detail/dependent surface; X3 proves native visual fidelity, full mixed-load/device failure journeys, staging parity and rollback. These are the same six work packages and two waves, not separate side projects.

**Release evidence required:** every mandatory requirement has an implementation path and test/evidence row; no untested workaround counted done. Capture cold/warm query and request traces, authenticated privacy tests, membership-removal channel captures,5000-session capacity results, both-provider fidelity reports, rapid-edit/offline/restart tests, design overlays/device videos, migration rehearsal, exact app artifact and rollback preserving newer activity. Specify flags, build/migration order, environment and approval boundary. No automatic recurring jobs/tunnels. Existing scheduled catalogue operations must be inspected for overlap; new scheduled activation needs applicable approval.

Prepare and rehearse the release continuously within the two waves, but obtain the applicable explicit deployment/backfill/credential/public-exposure authority before those actions. Never interpret this handout-writing turn as permission to alter production. At authorized release: additive schema/contracts first, compatible worker/server version, tested native artifact, then a5%→25%→100% deterministic flag rollout with at least30 minutes of representative observation at each intermediate cohort. Low traffic requires enough explicit qualified journeys/samples rather than passing from elapsed time alone. Use section12.6 latency/error thresholds, zero privacy/data-loss tolerance, monotonic revision/queue recovery checks and old-client compatibility as rollback criteria. Record effective cohort/config and exact schema/function/build identity at every step. Rehearse index creation/backfill write-lock limits; concurrent index operations must respect PostgreSQL transaction restrictions and failed-index cleanup. Backfills are bounded/checkpointed and never rewrite catalogue IDs or monopolize foreground capacity. A privacy leak, data loss, sustained SLO failure or compatibility break triggers disable/rollback of the new path while retaining receipts/pending actions. Run real live journeys and record exact deployed SHA/build/functions/migrations separately from staging. No promise that unverified software works perfectly.

### 12.8 Executor closure checklist

- [ ] Database/call audit complete; every caller/writer/subscription mapped, effective permissions and growth plans reviewed, critical findings closed with evidence.
- [ ] One additive series identity model, precise child progress and matching provenance; references/history/ratings/notes preserved.
- [ ] Both Anime/Manga AniList and MAL import pathways declared honestly, full supported-field fidelity and personalized Home readiness proved.
- [ ] Bounded Home/detail/Collection/private aggregates; no per-card/upstream/full-library mutation refetch.
- [ ] Durable local progress, revisions/receipts/lifecycle fences, rapid edits, two-device/import conflicts and Undo qualified.
- [ ] Current-membership authorization and removal revocation proved across reads/writes/realtime/cache/notifications; no offline private body cache.
- [ ] Selected Anime Home, Poster switch, Manga Library and both detail pages transferred with complete wiring and owner visual approval.
- [ ]1000/5000-session sustained/burst/soak and large-table targets measured; admitted steady throughput, latency and privacy/data integrity pass.
- [ ] All acceptance rows classified PASS/FAIL/NOT RUN with exact environment, command, fixture seed and artifact path; no missing gate hidden.
- [ ] Two wave exits, independent review where required, compatible rollback, canonical docs and memory extension notes recorded.
- [ ] Applicable release approval received; deployed artifacts and real live happy/failure journeys independently recorded before claiming released.


## Visual source transfer manifest — pinned5October2026

Checkout HEAD: `471c609943d2374c6dda940aebdfde2fcb077d50` plus dirty/untracked work. These hashes identify local selected references, **not a published GitHub artifact**. There are 46 preview/dependency files below (5236827 bytes). Include the files on the authorized handoff branch/private transfer; validate hashes before implementation. Relative names are under `tools/design-directions/`. Preview fixtures are illustrative; their data is never production truth. Changes after this manifest require deliberate repinning and regeneration, not automatic approval of a new design.

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `assets/anime0-banner.jpg` | 167942 | `f307ee6fea449318b5d53ee2473e83f34e839d9d548d9cbc3459d6aa8fc1cfa2` |
| `assets/anime0.jpg` | 28423 | `e486c00310db934d53b3a744bcbeb1b73647616b8c8ae9cfdab7bb61525af0cc` |
| `assets/anime1-banner.jpg` | 362165 | `fa8551c29236600f85ad486d02e6617d85016eb7c91f4aac2a0fb52cdfb8427b` |
| `assets/anime1.jpg` | 20597 | `17fa998bd33e9156be8358898958271320c210257baf129044fda99c26660c06` |
| `assets/anime2.jpg` | 41477 | `14651682668cb9a1229766b7b1cffe7f3b3f1f799e9dafddcac65d4762e74531` |
| `assets/anime3-banner.jpg` | 143977 | `cab3add52bf03239f61a6022bdbe2c2ba2b87a3b62e3e5617dc0e1a24a0213b1` |
| `assets/anime3.jpg` | 24090 | `fd94378f9035cfcf3196eb497ae1b0b6b30d72bb579f0b85936d71e803241421` |
| `assets/detail-character-180.png` | 157192 | `1a59ef3fb799d98e92134d10fcb0b7e5bb7c025e672d183ebd16f50722fde750` |
| `assets/detail-character-181.png` | 150525 | `24f6d88fdb8dbef3a6e583eba1363309cf6da918a6689273a573e66de812af0f` |
| `assets/detail-character-182.png` | 161213 | `ad6ad84cc5a331638e294eb303e0601e3d63b933e880afc7a825c30193fc9c3b` |
| `assets/detail-character-21.png` | 83107 | `727bd621ff18841e91653022d170652ff272173bf7b683b821096aa710d8e7a8` |
| `assets/detail-character-22.png` | 144480 | `8ee287a1387f798835ec6208b4e6de10bf3982439f5fc468787205d7dd1e4595` |
| `assets/detail-character-23.png` | 147615 | `2d24a3e9b8e6d3dda53b05e5c5dab5dfdd5ee9bbed87da45a07bea9beb5f8ccb` |
| `assets/detail-character-24.png` | 150198 | `e9e8fd18697ff2d494665dee0e5f7ba66e52ce71474f664cd824c2f1910c98ab` |
| `assets/fonts/BodoniModa-Italic-Variable.ttf` | 176300 | `dfff1619f8f6871c6372f8855b67211f9a73b4e93d45aca868cd8f46a48622de` |
| `assets/fonts/BodoniModa-Variable.ttf` | 162104 | `550f5e34ee0a828d7941b1fe9bc58b34e5260d3f33a61532e6d0a0114e79a5cf` |
| `assets/journal-anime-12-cover.jpg` | 26263 | `a34ab5e0d5fb2d99ca77bc0f8fd011470569499bc1f5a15abea59eec09841c76` |
| `assets/journal-anime-15-banner.jpg` | 102196 | `b4ed1e72a428dd2a71498c03f164015fcf4f4268f3a32a92b447bb0cdc8c94fe` |
| `assets/journal-anime-15-cover.png` | 124046 | `5628cd2bd017ac95acbf44bf7e43c45c1dc8e3e9bf34ad892dc95fe11fed8feb` |
| `assets/journal-anime-16-cover.jpg` | 37460 | `1c65fe4b95ffe3119bc1e235d8f75d9d3f14785f2df45def9e91edb09ef9249f` |
| `assets/journal-anime-22-banner.jpg` | 92992 | `1cc02754f96dd457ff4d89fe8854c7617c401c600937467bc451e7fcda4ee0be` |
| `assets/journal-anime-22-cover.jpg` | 57463 | `b3ea36d35af8ae919ffdc01331dac5a429113f7f6e2343cad53fae843910edef` |
| `assets/journal-manga-13-cover.jpg` | 21328 | `4f98cd5951adbf516bad50ee4623c15ef1c84e1eb3551c5e7a9e0cdd67007329` |
| `assets/journal-manga-14-cover.png` | 162426 | `e577ff6adb537fa2623505b07cf33f76bf590ac17fe68dcd9d64e48ab313157a` |
| `assets/journal-manga-16-cover.jpg` | 54599 | `7484567bb387ce063aed2a00cd29f9728e4a888f5944b8eb69fb06c1e5b4ce3a` |
| `assets/journal-manga-23-cover.jpg` | 61197 | `10096ee138f5109b8e5c8aef11a4880c7b3c8867f05255f50ac6806e39c22430` |
| `assets/manga0-banner.jpg` | 212076 | `04d0d17815b56e2701c02b1110f57eab5a280db4b2d1abd9116105fdd7915978` |
| `assets/manga0.jpg` | 171700 | `a9492decfb333ad5a8e4b50a3028ad51f2f2e097195c6f5ed4ed85d47345a9d0` |
| `assets/manga1-banner.jpg` | 269938 | `c1f1071b859f662959a487295ec610c0878823a9886580e11a961a07885a4995` |
| `assets/manga1.jpg` | 31794 | `ce3ab23db07e0d05db9fdfbd2dd8b8b32752b94af75cfa494ad6133366263eef` |
| `assets/manga2.jpg` | 33552 | `ab137af41c2ee8cabb3ab1fdd95881a8daabf88296d8352828c8f7a1c0fb4d21` |
| `assets/manga3-banner.jpg` | 226522 | `5d15b8c100bbf3c6534fbfe55871dbc82af3a899ebad379e3f23225865431220` |
| `assets/manga3.jpg` | 33682 | `87599a212154ba79920d461d7c4003bca69d2baf21bd548097cdc4d5ff525357` |
| `assets/medium-diptych-v43.jpg` | 233911 | `1881d92e33a23c4ba417ba174f162c440434672dec9209b05699f7f981a61c7b` |
| `assets/medium-objects-v47.png` | 856277 | `07406d76ec585eb4b71c54d63c597f77cd7891c92fcd98e325adafebacb55ae0` |
| `instrument-art-materials.js` | 5820 | `5ea5103da880e554c6f9072cf1bd83930bc99bf2083678e8988187dd2470afd4` |
| `instrument-detail-data.js` | 6754 | `9a328ec277428fd4a0c00e0e4c81630c2e9be83f48878dba93d525d9d85da548` |
| `instrument.css` | 165496 | `ed15e7137be08cddb3b8b22e598a91d45df5c9d0be4143e117e53b6339d7d854` |
| `instrument.html` | 3171 | `11fa0ebeda623d7896fd703c6e7ed539a811e09c389881c5282fe3345709523d` |
| `instrument.js` | 77380 | `8f3dd3586bd43e54c0aca0db7ec6f220c514a4aa6317e71365457a3aaeadf906` |
| `journal-data.js` | 6074 | `8916dfc2c62bc743b0d663f88e76c645a3933a4fcd21b6f858aca0b48cc5c49d` |
| `manga-directions.css` | 20328 | `e3cd047dacbe50c3c735c530210aa93e323edac34b0ff5042439197e2cdeefa8` |
| `manga-directions.js` | 2668 | `bae3695790339af8fe6a475fe9aadbb23f7e59920a91fb10dc6aeb71aab9bb59` |
| `manga-library.html` | 3718 | `7867e78f90e31d7211b76719bc36779c14c2798d1452da7fabdd57db754ab254` |
| `manga-philosophies.css` | 10979 | `69cb5e09410cf8bfddb410f1ea44d75914c8cd8f9a66f352f000c875fb328a22` |
| `manga-philosophies.js` | 3612 | `8fc5cc5effa1e00b636cf4191765c84d41987d0a570ca2baa0f9430bd63757ee` |

To render locally, use the existing README command from the repository root and select `instrument.html?switch=poster&medium=anime`, `instrument.html?switch=poster&medium=manga`, `instrument.html?detail=anime-2`, and `instrument.html?detail=manga-0`. For other titles open their cover/title. `manga-library.html` is the focused wrapper; its older proposal captions are historical, and the active specification controls selection. Do not renew expired public share links. Screenshot baselines and real-native comparison are executor deliverables, not supplied proof of a native implementation.
