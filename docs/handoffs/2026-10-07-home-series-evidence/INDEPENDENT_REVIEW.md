# Independent review — Home / series / Anime and Manga details

**7 October 2026 · Verdict: REQUEST CHANGES. Local foundation exists; full-plan closure, design fidelity and release readiness are not established.**

This is a review of the dirty working tree at HEAD `a7f39b66237bc5a9558b5ab2a6758cd1b085e466`, branch `kuro/taste-overhaul`, in `/Users/max/Kuro-Anime-App`. The pin recorded 352 changed/untracked paths. It is not a review of an isolated PR diff or a newly deployed release. Relevant implementation files and original evidence documents are fingerprinted in [source-pin.json](independent-review/source-pin.json). No app, SQL, function, flag, account or hosted resource was changed by this review.

The reference contract is the [singular master v1.1](../../plans/2026-10-02-series-and-home-rebuild-DRAFT.md), with its [production executor handout](../2026-10-05-claude-code-production-handoff.md). All 46 supplied visual dependency hashes were independently rechecked and match. The previous ledger remains implementation history; its “approval only” and “no first-plan rule break” conclusions are contradicted by the findings below.

## What Max needs to know

- **The design has not been transferred faithfully.** The chosen Poster switch, artwork-led Coming Up, season panels and private discussion UI were replaced or omitted. The native screenshots are largely empty artwork fixtures; the detail comparisons use different anime.
- **Fast progress changes lose taps.** Running the actual HomeStore algorithm with 20 concurrent advances from 3 yields 4, rather than 23.
- **Offline recovery is incomplete.** A failed send leaves SQLite rows in flight, invisible to another drain until the database is reopened. A write error also leaves the connection inside a broken transaction.
- **The next successful tap can conflict with the previous one.** Cards/details retain their old revision while acknowledgements only update LibraryStore.
- **AniList can import the wrong title.** Provider IDs are compared with Kuro's independent internal IDs and internal matches take priority.
- **One anime per series is not implemented on Home.** The query still returns one card per underlying list entry. Selecting another season still queries the original entry.
- **Import retries and final Home readiness are not safe yet.** Chunks lack durable replay accounting, local deletion/status edits can be overwritten, and Home does not subscribe to committed import revisions.
- **Club revocation is not integrated into the new Home cache.** Clearing Clubs/Social does not remove Home's already loaded comment bodies. New private RPCs bypass the established credential-lease path.
- **Capacity has not been demonstrated.** One important EXPLAIN uses a stronger index than the prepared schema actually has. Another builds every group before limiting. The old mandatory capacity contract conflicts with the demoted ledger.

These are blockers for enabling this surface and claiming the requested production implementation complete. They are not claims that today's flag-off production app has already suffered these incidents.

## Verification performed in this review

| Check | Result and boundary |
| --- | --- |
| Source / dirty-tree pin | HEAD and branch verified; 15 key file SHA-256 values saved. Code inspection covers the integrated Home/detail/Collection/import/outbox paths and their relevant ownership, permission, query and lifecycle dependencies. Not an audit of every unrelated modularity edit. |
| Accepted design files | **46/46 hashes match** the handout manifest. This proves the browser references are preserved, not that native implements them. |
| Five existing package tests | **PASS**, freshly rerun: `twentyTapsCollapseToTheLatestPositionAndSurviveReopen`, `outboxDrainStaysInsideTheAccount`, `importBatchCollapsesDuplicatesAndDropsPrivateNotesAndZeroScores`, `groupingRequiresReviewedContinuityAndIgnoresCalendarSeasons`, `malExportKeepsRawScoreNotesAndRejectsEntities`. |
| SQLite failure/coalescing reproductions | **Three defects reproduced** against the unchanged production `ProgressOutbox.swift`: rows undrainable in the same process after marking in flight; no rollback after an injected INSERT failure; unit ID on disk differs from the latest enqueue return. See [recorded output](independent-review/repro-results.txt) and [source](independent-review/Repro.swift). |
| HomeStore rapid-tap reproduction | **Lost advances reproduced** using actual HomeStore, HomeContracts, AccountSessionCoordinator, LibraryStore and ProgressOutbox: 20 concurrent tasks, initial 3, actual 4. Compiled as a macOS harness with the Supabase conditional branch absent and a no-network Library backend. This exercises calculation/enqueue/publication; it does not prove iOS gestures or a hosted receipt. [Source](independent-review/HomeRepro.swift). |
| Fresh PostgreSQL receipt test | **BLOCKED before any SQL test executed**. `run_local_db_tests.sh --only 81_import_session_receipt` exhausted 40 cluster-start attempts because macOS System V shared-memory IDs were exhausted (`shmget`, “No space left on device”). Exit 3; teardown ran. This is host resource exhaustion, not a new SQL-test failure or a PASS. No unrelated cluster was stopped or kernel setting changed. |
| Earlier database proofs | Ledger claims receipt20, races22, import-count9 and earlier foundation proofs. Those numbers are not independently reconfirmed here. The handoff contains earlier foundation/race92 logs; corresponding receipt81/import-count81/race93 raw logs were not present in its listed `db/` files at inspection. Do not equate assertions recorded in prose with freshly repeated proof. |
| Existing screenshots | 24 PNGs inventoried; all four Poster/native 390px surface pairs inspected directly (8 images), alongside generator and composition checklist. No new export overwrote them. This is enough to identify clear composition deviations, not a full device, accessibility or pixel-diff pass. |
| Native simulator build / snapshot suite | Prior ledger claims PASS. Not rerun here; snapshot tests assert file creation, not fidelity. |
| Documentation check | Initially FAIL on stale inventory labels (129/14/235). Corrected only current inventory labels in state docs and CLAUDE to verified local 133/20/245; rerun **PASS** (`check_docs_current_state.py`). Local file counts are not deployment parity. |
| Hosted / staging / release / device / load | **NOT RUN by this review**. Prepared file location and disabled flag inserts are source evidence. No fresh hosted migration/flag identity, native device VoiceOver/haptics, staged capacity or released-user journey was qualified. |

Swift first failed on sandbox cache access and then nested `sandbox-exec`; the focused package test and HomeStore harness succeeded through the tool's approved local escalation. The standalone SQLite reproduction compiled without escalation. No Postman cloud push or production traffic occurred. The Postman API-engineer contract-first review guidance was applied.

## Findings, ordered by impact

### R01 · P1 · Lost-response/offline sends remain in flight until restart

**Sources:** `Kuro/Home/HomeStore.swift:321–390`; `Packages/KuroModules/Sources/KuroLibrary/ProgressOutbox.swift:107,205–221`.

`drain()` marks a batch `in_flight` before awaiting the RPC. Its catch only displays “Saved on this device.” `pending()` selects only `pending` rows. The sole automatic in-flight recovery is in the outbox constructor. A transport failure, timeout or cancellation therefore leaves the running app unable to retry that batch; foreground and reconnection call the same drain and see no rows. Returning to the app is not reopening the database. Turning the native flag off also removes the foreground drain trigger, so rollback is not a complete sync policy.

**Reproduction:** enqueue → markInFlight → pending gives0 while stored count is1; constructing another outbox restores pending count1. This uses the actual SQLite implementation; the network-failure transition was traced in HomeStore.

**Fix / gate:** use a single account-scoped drain owner with a durable attempt/lease state and bounded retry/backoff. After an uncertain response, replay the **same immutable mutation ID and payload**; do not coalesce an attempted request into a different body. Recover abandoned claims in-process, not just on launch. Exercise timeout before dispatch, timeout after server commit, reconnect without restart, cancellation, flag rollback, account switch and drain exhaustion beyond50 intents. Prove one server effect, retained newest UI intent and eventual empty pending queue.

### R02 · P1 · Rapid taps lose progress, acknowledgements can clear newer intents, later taps use stale revisions

**Sources:** `HomeStore.swift:204–258,349–357`; `LibraryStore.swift:168–176`; `SeriesDetailViews.swift:159–170,380–398`.

`advance()` reads the displayed value, computes `next`, then suspends on enqueue before publishing it. Multiple main-actor tasks can all read3, enqueue4 and coalesce to one4. The existing package “20 taps” test provides explicit increasing positions in a sequential loop; it never runs this HomeStore path. The isolated actual-source harness reproduced20→4.

Every advance also passes the card/detail bundle's original `serverRevision`. The acknowledgement adopts the new revision in LibraryStore but neither updates that card/user snapshot nor consults LibraryStore's revision on the next send. Thus base1 → first applied at revision2 → next request still base1 creates a self-inflicted conflict. A response unconditionally removes `positions[key]`, even if another newer intent for that key appeared while the RPC awaited. `adoptServerProgress` can silently do nothing when the entry is missing or another Library mutation is in flight, yet the overlay is still cleared.

**Fix / gate:** serialize issue order per account/lifecycle/key; atomically commit the local projection and intent; resolve the confirmed revision from the authoritative coordinator. Clear pending only for the acknowledged local sequence, preserving newer edits. Coordinate Home receipts with existing Library mutations rather than creating two competing queues. Test20/100 overlapping taps, normal tap→ack→tap, tap during ack, Library mutation overlap, not-yet-loaded Library and cap crossing. All views and server must agree on the final value without own-write conflicts or dropped taps.

### R03 · P1 · SQLite errors poison subsequent writes; coalescing persists the wrong unit

**Source:** `ProgressOutbox.swift:154–203`.

`enqueueSync` begins a transaction but has no error-path rollback. An injected aborting INSERT trigger produced `storage("injected write failure")`, followed by `storage("cannot start a transaction within a transaction")` on the next enqueue. The source needs the same safety for genuine disk/write errors.

The coalescing UPDATE changes position/label/status but not `unit_id`. Its returned `ProgressIntent` is built from the newest input and reports the newest unit, while `pending()` reads the old unit from disk. The reproduction reports latest position3, latest-unit=false on disk, but latest-unit=true in the return. This matters for real chapter/edition identity, even though current Home taps do not send a unit.

**Fix / gate:** guaranteed rollback for every failed transaction, resource cleanup on initializer failure, and a single persisted canonical return value. Persist every field whose coalescing is allowed; isolate edition/unit changes appropriately. Inject failure during INSERT, UPDATE and COMMIT; then remove the failure condition and successfully reuse the same connection. Reopen after coalescing fractional/edition units and assert the drained body exactly equals the latest durable intent. Add an explicit bounded retention policy for acknowledged rows and a device file-protection policy.

### R04 · P1 · New Home/detail private requests bypass account credential leases and revocation

**Sources:** `HomeStore.swift:115–176,224–258,315–390`; `SeriesDetailViews.swift:269–290,502–519`; `Kuro/Clubs/ClubsStore.swift:232–247`; `Packages/KuroModules/Sources/KuroCore/AccountSession.swift:8–21`.

The modular architecture deliberately established `withCredentialLease` so a request cannot dispatch with another account's SDK token. New Home load/load-more/drain and both detail loaders call the SDK directly. Home guards some results by generation; a result guard is not a credential lease. Anime details guard only their season token; Manga details have no account-result guard. The bundle includes private list state, notes and ratings. `advance()` also lacks an account check after the durable enqueue await, so a late old-account completion can repopulate the new account's in-memory position map.

Club invalidation clears Clubs, Social and Provider caches, but not Home's retained `bundle.club.items`. Foreground only drains; it does not reauthorize/purge those bodies. Server RLS stopping a fresh read does not erase an already visible Home comment after removal. The new helper `shares_club_at_least` uses `coalesce(me.sharing_level, cl.sharing_level)` instead of the existing trust contract's lower member/club rank; an explicit member status setting can exceed a private club's cap. This needs the existing effective privacy policy, not a new interpretation.

**Fix / gate:** route private requests through capability-owned credential leases and account/permission generations; discard stale detail state before credential replacement; invalidate Home when any membership/privacy signal changes. Reuse the effective minimum sharing-rank policy, including peer visibility rules where applicable. Test delayed dispatch across logout/login, A→B with different notes/progress, removal while Home is visible/backgrounded, rejoin and privacy downgrade. New fetches must reject revoked access and already loaded private content must disappear under the documented revocation contract. Hosted RLS/Realtime remains a separate proof gate.

### R05 · P1 · AniList namespace collision imports the wrong title

**Sources:** prepared SQL `20261007040000_series_home_foundation_v1.sql:2003–2012`; `supabase/functions/bulk-import-anime/mapping.ts:56–100`; baseline migration `20260807000000_baseline_capture_v1.sql:59–61`.

The structured importer resolves an AniList ID with `a.id = external_id OR a.anilist_id = external_id`, preferring the internal-ID match. Kuro's internal IDs come from their own sequence; the catalogue importer writes `anilist_id` and receives a distinct internal `id`. For catalogue A `(id=123, anilist_id=999)` and B `(id=7, anilist_id=123)`, importing AniList123 selects A, not B. Manga has the same branch. This is a real namespace error, not a title-spelling concern.

**Fix / gate:** resolve exclusively by `(provider, medium, external_id)` through unique source identifiers/provider refs. Never use the internal PK as an external fallback. Add a collision fixture with distinct internal/AniList/MAL IDs for both media, plus unmatched/ambiguous targets. Assert the intended internal entry and no unintended list write. Do not run this destructive example on a real user's account.

### R06 · P1 · Structured imports cannot reliably resume, replay, or protect concurrent deletions/status edits

**Sources:** `Kuro/Imports/ImportsService.swift:205–253`; prepared SQL `1900–1956,1985–2166`; `LibraryImportBatch.swift:93–104`.

Import items have a unique key, but the apply loop does not consult an already processed item before writing again and adding job counters. Replaying a committed chunk can inflate dispositions/counters or classify its own previous write as a conflict. A restarted client reapplies every chunk from the start. If the job is already ready, start returns it and the next chunk fails `JOB_NOT_RUNNING`; the client does not short-circuit completed jobs. The hash-derived key is reused for separate user actions and omits volumes, dates, score scale, privacy and provider/source identity.

The local-edit check compares progress and optionally notes, not status or all imported fields. A user dropping a title at the same position during import can be reset to Watching. A deleted row has no `updated_at`, so the upsert can resurrect it with a new lifecycle despite its tombstone. Row locks serialize writes but do not establish semantic conflict protection for those cases. The start active-job check is also check-then-insert, without a uniqueness constraint on the active provider/medium slot; separate keys can race through it.

**Fix / gate:** durable chunk/item receipts, canonical full-payload hashes, one identity per import action, resume/checkpoints and ready-job replay behavior. Compare field versions/lifecycle/tombstone at import baseline, not wall-clock plus progress/notes alone. Define safe merge/explicit restore and one active-job policy transactionally. Test response loss before/after each chunk commit, process death after chunk1, repeated ready job, concurrent starts, removal/re-add, status-only edit, repeat/score/date changes and fresh reimport of identical source after a user intentionally changed their list. Counts must correspond to terminal unique items, not RPC attempts.

### R07 · P1 · Home still lists individual season entries, and selected seasons do not select their data

**Sources:** prepared SQL `1216–1267,1555–1608,1683–1719`; `SeriesDetailViews.swift:108–137,269–282`; `HomeContracts.swift:17–19`.

The anime Home query joins each `anime_user_lists` row to a span and returns its entry ID. It never groups/deduplicates approved series or selects one resume entry per continuity. Importing Season1 and Season2 as active/planned produces two visible cards for the same approved anime, contrary to the primary product requirement.

Selecting Season2 sends the original `anime.id` and another `section_id`. Header, progress/user, cast and source mapping remain filtered by the original entry. Units/themes require that same original ID and thus cannot load another season's actual child entry. Coverage is not section-filtered at all. A selected section is not validated as belonging to this series. The season marker on a Home card just opens the normal detail route, without routing to a season overview.

**Fix / gate:** read approved continuity → one account-specific resume card → resolve selected section into its entry spans/units. Keep child tracking independent, and update copy/artwork/music/cast/coverage under the selected section without changing progress on browse. Test two imported seasons, split cour, canonical film, noncanonical extra, remake separation, stale/foreign section ID and selection races. Season1→2 must show genuinely different entry data and the correct continuation boundary, not merely a changed label.

### R08 · P1 · The import-to-personalized-Home journey is not connected

**Sources:** `ImportsService.swift:231–253`; `Kuro/Composition/LibraryChangeSinks.swift:42–55`; `Kuro/Library/LibraryActions.swift:129–136`; prepared SQL `2149–2157`; `HomeView.swift:111–120`.

The importer applies all chunks, discards the finish response, then starts an unawaited Library refresh. It does not notify Home after committed batches, fetch/adopt the final Home publication, or compare returned versus rendered revisions. The registered Library sinks omit Home. The Home empty state offers descriptive text rather than the requested import-first CTA. A mounted empty Home can remain empty after import. A mixed-media import increments only the Anime publication counter.

AniList still has a global200 default /400 maximum across media, fetching Anime before Manga, and returns a truncation flag without resumable next-page checkpoints. A large Anime list can consume the cap before Manga begins. The structured path is a capped import, not the complete5000-title account import requested in the master. MAL account connection is intentionally unavailable; XML success is useful but does not satisfy that connector gate.

**Fix / gate:** incremental durable provider checkpoints, honest source-exhaustion state, coalesced Home revision publications for each affected medium, and an awaited final readiness handoff. Wire an import action into empty Home. Keep provider fetch duration separate from internal apply/readiness. Test0/1/50/400/5000, Anime-only/Manga-only/both, cancellation/provider429, partially committed chunks and switching to Home during/after import. A ready message requires that the committed final revision is actually rendered; never insert artificial delay to hide missing wiring.

### R09 · P1 · Native detail functionality is a shell, not the accepted product

**Sources:** `SeriesDetailViews.swift:140–185,235–266,446–499`; prepared SQL `1566–1577,1630–1640,1722–1737`.

Both “Between us.” sections are explanatory Text, not roster/comments/reactions or Leave a thought. They do not fetch a title-specific private discussion. Characters are a list of names without artwork or entity routes; principals/studio/author credits are omitted. Episode/chapter rows are capped at the first3 and have no paging action/cursor. Untracked details lack an Add/Status list action. Manga's “Choose a season you've finished” merely toggles the literal string `Unverified`, without choosing an anime/season or opening a verified guide. Manga's bookmark only increments an integer; there is no real unit/edition/precise chapter selection.

**Fix / gate:** reuse the established club/comment capabilities and typed routes, with the accepted image-led composition; provide real controls, drafts, spoiler state, editing/reactions and permission-aware empty/error states. Page unit data and retain accurate labels/editions; bind progress to the actual unit. Include principal credits and usable source/official continuation links. Every visible control must have a genuine handler and happy/failure test. Missing metadata should show a restrained honest state, not a permanently nonfunctional product control.

### R10 · P1 · The EXPLAIN fixture uses an artwork index absent from the prepared schema

**Sources:** prepared SQL `263–274,1228,1343`; `scripts/db/explain_series_inner_plans.sh:123–131`; [recorded EXPLAIN](db/explain-largest-fixture.txt).

Real `artwork_materials` is keyed by `image_digest`. Home joins on `image_url`, which has neither an index nor a one-current-material uniqueness constraint in this migration. The plan fixture instead makes **image_url the primary key**, so its efficient `artwork_materials_pkey` lookup is not a plan available in the submitted schema. Several digests/revisions for one URL also duplicate Home rows before LIMIT. `detail_copy`, `theme_links` and `adaptation_coverage` similarly lack entry/locale/section indexes corresponding to their new lookup predicates.

**Fix / gate:** define image/version identity and a unique selected material relationship, add the justified matching indexes, and populate the exact prepared DDL plus effective RLS in the performance fixture. Measure queries with realistic art/copy/theme/coverage cardinalities. Assert material joins cannot multiply Home cards. Do not “pass” a planner test by creating stronger indexes than the implementation.

### R11 · P1 · Some bundle work is unbounded; release schedules are incomplete

**Sources:** prepared SQL `1414–1439,1790–1833`; `HomeView.swift:58–95,311–355`; `HomeContracts.swift:75–85`.

The pending release query applies `LIMIT20` outside a `jsonb_agg`. That limits the one aggregate output row, not its input events; every matching announcement is included. Collection aggregates children across the user's full matching library before the30-group page limit, repeating that work on every page. Grouping before pagination is correct semantically; building every child payload first is unnecessary work and does not provide the claimed bounded cost. The prior1M plan itself estimates all1M rows passing through GroupAggregate.

Upcoming events stop at20 without an event cursor; active-card load-more cannot retrieve the omitted releases. Counts use that truncated array as the whole window. Manga `precision='day'` still requires a UTC instant, excluding legitimate date-only publications that the plan explicitly preserves. Save/follow intent is created but not consumed; tracked completed titles cannot surface a followed sequel through that relation. Event identity also omits the stable release-event ID, allowing two events for one title/date to share a SwiftUI ID.

**Fix / gate:** limit ordered input before aggregation, bounded child paging after a series-summary page, independent release/pending cursors and honest totals/window labels. Respect source-local date/zone/precision without inventing UTC midnight. Use stable release IDs and explicit save/follow eligibility. Test1/20/100 simultaneous events, long undated announcement lists, date-only chapter releases, delayed/cancelled updates, multiple editions on the same date and later pages. Use actual query count/rows/buffers plus payload size to qualify growth; an index-only outer label is insufficient.

### R12 · P1 · Progress replay hash and unit validation do not fully honor the mutation contract

**Source:** prepared SQL `596–704`.

Status-only requests fill their missing position from the current stored row **before** computing the receipt hash. A successfully committed status request retried after a separate progress edit can therefore get `rejected_payload` for an unchanged request body. The canonical hash also omits base revision. `unit_id` is accepted without validation that it belongs to the requested medium/entry/section/edition, and the list columns have no unit FK. The fractional-label branch updates label/unit but drops a supplied status while still returning an applied receipt.

**Fix / gate:** hash the immutable canonical request, preserving absent fields; replay lookup must not depend on current row state. Include all defined semantic request fields. Validate unit ownership and intentionally model fractional progress/status together. Test a lost status-only response followed by another progress update, changed-body same-ID rejection, a foreign/missing unit, special/fractional units and fractional completion. These are source findings; fresh PostgreSQL execution is blocked in this review and must be obtained before claiming the fix.

### R13 · P1 · Approved remapping silently destroys section-specific metadata links

**Source:** prepared SQL `1063–1095`.

`publish_mapping_revision` nulls `section_id` on units, copy, themes, coverage and releases, deletes all sections, then creates new section UUIDs. It does not rebind those existing rows to replacement sections. A valid administrative revision can succeed while turning carefully curated season-specific descriptions/song/chapter/release evidence into unscoped fallback data. Validation failure rolling back is useful, but it does not make a successful remap safe.

**Fix / gate:** stable logical section identity or an explicit reviewed old→new mapping; update dependent associations transactionally and audit ambiguous moves. Test adding a new season and changing a section label with existing metadata, plus split/merge and invalid targets. Existing bindings either retain equivalent meaning or are explicitly unresolved and unavailable; they must not silently become universal data for every season.

### R14 · P1 · Required ingestion/enrichment and import fidelity are not delivered by creating tables

**Sources:** prepared SQL new metadata tables; `LibraryImportBatch.swift:4–19,65–78`; `concierge-import-anilist/paging.ts:19–42`; `concierge-import-anilist/structured.ts:20–44`.

There is scaffolding for copy/music/release/coverage/materials/units, but no newly wired worker in this Home delivery populating those contracts from existing source metadata and keeping revisions/freshness current. The new UI consequently depends on empty tables unless operators manually seed them. Existing workers write older catalogue/chapter relationships; a table being available is not a consuming bridge.

Structured draft/payload fields omit custom-list membership/order, and `hiddenFromStatusLists` is fetched but not retained. AniList private notes are deliberately deleted rather than preserved in owner-only storage; the test blesses the deletion, contrary to the master requirement to preserve supported private fields without publishing them as club comments. Entry-private visibility is not carried through. Raw AniList score is marked `ANILIST_RAW` without the actual user's source scale. Partial dates lose month information when the day is absent. These are silent fidelity loss, not simply unknown catalogue metadata.

**Fix / gate:** bridge/reuse existing ingestion ownership into these tables with provenance, exact provider IDs, freshness/backoff/retention and additive updates. Retain private fields in appropriately scoped storage, custom memberships/order and original score/date representations; explicitly report unsupported/lost fields. Keep exact adaptation boundaries unknown until evidence exists. Fixture and authorized live-provider tests must prove source→stored contract→native rendering, and re-enrichment must retain the last good data. Qualify MAL XML separately from unavailable MAL account API.

### R15 · P1 for fidelity / P2 for polish · The native redesign diverges materially from the approved design

**Sources:** `HomeView.swift:38–95,181–206,277–308,361–399`; `SeriesDetailViews.swift:59–137,252–266,489–499`; [prior composition checklist](composition-differences.md).

This is not a taste judgement about a new proposal. The master explicitly fixes the **Poster** switch, artwork glance, Library manga treatment, liked season panels, artwork/material continuity and private club imagery. The prior comparison document calls their replacements “intentional flourishes versus the accepted native shell,” but records no owner approval for a different shell. Native uses a plain text medium control, text-arrow Coming Up, unlabelled progress integers, a chapter key overlapping the cover rather than the accepted below-cover key, basic season text blocks, and discussion-placeholder paragraphs.

Home accepts an artwork material, while Anime details use fixed green fallback styling and the detail contract returns no shared material. The full Home→detail color continuity is therefore not implemented. The main Season tab label uses a28pt frame; an explicit tested44pt hit region is absent despite the interaction contract. Anime Between us explanatory text is dark secondary ink on a dark background in the inspected screenshot. The seasonal hook/episode progress hierarchy and Manga cover/title placement are also visibly different. New placeholder paragraphs increase text density precisely where the owner requested image-led minimalism.

**Fix / gate:** keep the existing approved prototype as the source of truth. Implement the chosen compositions and explicit press/disabled/loading/confirmation/failure/conflict states, artwork-matched materials, touch regions and Reduce Motion, rather than relabelling deviations as intentional. Restore white SeasonN artwork tabs and compact S stamps without number rails. Compare populated matching fixtures at320/390/430 with overlay/difference review, then native device interactions/VoiceOver/haptics. Obtain owner approval for any substantive design substitution.

### R16 · P1 for evidence · Screenshot and release gates were made weaker than the unchanged master

**Sources:** `HomeCompositionSnapshotTests.swift:21–97,99–176`; [ledger](ledger.md); [existing findings](findings.md); master/handout capacity and visual gates.

The test only checks that `drawHierarchy` yields/writes PNG bytes and that files exist. Fixtures omit artwork URLs/materials and meaningful club content, use different anime for the detail comparison, and render height `width*2.2` rather than the same phone viewport. Poster files include study chrome and clipped phone framing. There is no pixel baseline, full scroll/expanded-state comparison or asserted interaction result. Thus “snapshot suite PASS” means capture succeeded, not “native matches Poster.”

The ledger says only deploy approval blocks release and demotes1000/5000/burst/soak and independent review. The canonical master/portable handout still require the stated thousands-user qualification, meaningful visual equality and complete handlers; the existing findings document itself says absent capacity/device/hosted gates block a release claim. No resolved owner approval of this narrower contract was recorded in the evidence reviewed. The audit need not insist on10M specifically before any test cohort, but dropping the requested concurrency workload is a material acceptance change.

**Fix / gate:** reconcile one authoritative contract and ledger with explicit owner scope decisions. Mark each stage separately: schema preparation, migration candidate, native candidate, limited cohort, capacity-qualified candidate, released. Restore truthful FAIL/NOT RUN for missing behavior, fidelity and capacity. A low-user staging rollout may qualify its actual measured envelope, but cannot be advertised as the original thousands-session production qualification. An independent review is now available and requests changes; it cannot remain listed as optional/not run.

## Why the existing passes are still useful

The additive schema keeps old catalogue IDs; list triggers expose revisions/lifecycles; internal receipt helpers are revoked from normal clients; read bundles are authenticated invokers; jobs are owner-scoped; reviewed graph membership is distinguished from title-name guessing; mutation UUIDs and durable outbox storage exist; MAL XML rejects external entities; cap/truncation and unavailable connectors are explicitly represented. Those are good foundations. The flag-off boundary limits current rollout exposure. The selected tests correctly verify their narrow cases.

These strengths do not close the integrated async paths, data-population paths, accepted UI, cache-revocation paths or realistic capacity tests above. The right outcome is to repair this implementation, not discard its useful foundation or silently change the product contract.

## Database / API review completeness and next proof

The previous seven-row caller inventory is a useful introduction, not the mandatory full audit. This review traced Home load/load-more, drain/Undo/reapply, bundle RPCs, Library receipt adapter/adoption, direct revision triggers, import-session receipt helpers, structured chunk/import finishing, source ID mapping, new detail loaders, Collection grouping, Library refresh hooks/sinks, club invalidation/privacy helpers, Realtime/foreground entry points and the planner/snapshot fixtures.

Still needed before the original release claim: complete latest-effective caller/SQL/index/RLS register, provider-population bridges, candidate migration replay/parity, service-role versus authenticated plan measurements, actual staged HTTP/SDK journeys and capacity profile. The current planner artifact is `EXPLAIN` estimates, not `EXPLAIN ANALYZE` runtimes; it loads one user with1M entries, not realistic many-user distributions, and explains only one inner slice per bundle. It cannot establish authenticated RPC latency, total queries, pool/lock wait, HTTP payload or concurrency.

Use exact prepared DDL/effective policies, multiple realistic account sizes, populated metadata and separate real authenticated connections. Capture p50/p95/p99, offered/completed requests, errors/conflicts/429, buffers/rows/sorts, pool wait/locks, payload bytes and outbox/import backlog. Check dense release windows, hot same-entry progress contention and randomized cross-entry edits. Do not demand SQL avoid every sequential scan regardless of selectivity; prove that measured plans remain appropriate and bounded for the actual workload. Do not load-test production implicitly.

## Repair in the same two waves

| Wave | Required work | Binary exit |
| --- | --- | --- |
| **1 · qualified shared foundation** | R01–R08 and R10–R14: one durable progress coordinator integrated with Library, immutable receipts, namespace-safe/replay-safe imports, lifecycle/permission guards, real series/season resolution, metadata-population bridges and exact schema/index/query qualification. Preserve old entry IDs, account data and accepted contracts; keep flags off while repairing. | New regressions pass on real SQLite and disposable PostgreSQL; package/SDK contract checks pass; exact schema/RLS/index plans and capacity envelope recorded; migration candidate independently reviewed. Missing connector/capacity/access proof remains a named gate, not replaced by a prose PASS. |
| **2 · accepted native experience and qualification** | R09/R15/R16: restore approved artwork-driven compositions and real controls; connect incremental/final import Home hydration, chapters/episodes/music/credits/private discussion; finish revision/conflict/Undo/failure UI, routes, accessibility and scroll/motion. | Same populated visual fixtures pass fidelity review; native happy/failure/device journeys pass; staged/authorized hosted proof uses exact candidate identities; explicit owner deployment/flag approval and controlled rollout/rollback are recorded. No source/local test is called production proof. |

A clean reviewable change set is required: identify the Home feature's files and its modularity dependencies without staging/resetting unrelated dirty work. Review the final candidate again after fixes. Do not issue `supabase db push`, move the prepared migration into automatic deploy paths, enable flags, deploy functions or upload a native release from this review.

## Reproducing the new local evidence

Read both harness sources first. They create temporary SQLite files and remove only their own temporary directories/files. The standalone trigger injects an aborting local INSERT; it never contacts Supabase.

```bash
# Existing focused package tests; Swift may require normal compiler cache access.
CLANG_MODULE_CACHE_PATH=/private/tmp/kuro-review-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/kuro-review-swift-cache \
swift test --package-path Packages/KuroModules \
  --filter 'twentyTaps|outboxDrain|malExport|importBatch|groupingRequires'

# SQLite implementation reproduction (from the repository root).
swiftc -parse-as-library -module-cache-path /private/tmp/kuro-review-swift-cache \
  Packages/KuroModules/Sources/KuroLibrary/ProgressOutbox.swift \
  docs/handoffs/2026-10-07-home-series-evidence/independent-review/Repro.swift \
  -o /private/tmp/kuro-review-outbox-repro
/private/tmp/kuro-review-outbox-repro

# HomeStore algorithm reproduction; uses package object files built by swift test.
# macOS26/arm64 toolchain used for this review; adapt target/platform on another host.
swiftc -target arm64-apple-macos26.0 -parse-as-library \
  -module-cache-path /private/tmp/kuro-review-swift-cache \
  -I Packages/KuroModules/.build/arm64-apple-macosx/debug/Modules \
  Kuro/Home/HomeStore.swift Kuro/Home/HomeContracts.swift \
  Kuro/Composition/AccountScopedState.swift \
  docs/handoffs/2026-10-07-home-series-evidence/independent-review/HomeRepro.swift \
  Packages/KuroModules/.build/arm64-apple-macosx/debug/KuroCore.build/*.o \
  Packages/KuroModules/.build/arm64-apple-macosx/debug/KuroLibrary.build/*.o \
  -o /private/tmp/kuro-review-home-repro
/private/tmp/kuro-review-home-repro
```

The reproduced defects are evidence of the reviewed snapshot, not permanent expected behavior. After fixes these outputs should change and meaningful regression assertions should be added to the appropriate existing test targets.
