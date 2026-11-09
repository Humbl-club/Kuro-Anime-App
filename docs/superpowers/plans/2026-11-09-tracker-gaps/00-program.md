# Tracker gaps: program plan (entry point)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement each linked plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the ten tracker gaps found in the 2026-11-09 competitor research, each proven by BDD scenarios and test-first tasks, without breaking Kuro's capacity, architecture, navigation or business rules.

**Architecture:** One spec with success parameters and one Gherkin feature file per workstream; a traceability gate ties every scenario to exactly one test. Unblocked workstreams have full task-level TDD plans; workstreams that wait on an owner decision have an outline here and get a full plan when the decision lands (a detailed plan for a blocked item goes stale before it is unblocked).

**Tech Stack:** SwiftUI (iOS 26 SDK, Swift Testing, XCUITest offline fixture host), local Swift package `KuroModules`, Supabase PostgreSQL (prepared migrations + disposable local DB tests), Deno Edge Functions, Node load harness `scripts/load/`.

**Spec:** `docs/superpowers/specs/2026-11-09-tracker-gaps-design.md` + `docs/superpowers/specs/2026-11-09-tracker-gaps/features/`

## Global Constraints
All of spec §3 applies to every plan. The numbers that most often decide a task:
- Capacity target: 100 simultaneous active users; 20 rps steady, 40 rps peak. Status: NOT QUALIFIED.
- p95: Browse/Search/Clubs/Progress ≤ 750 ms, Home/Detail ≤ 1200 ms, Discover/Moods ≤ 1500 ms, Edge Parse/Recommend ≤ 2500 ms.
- No release of a feature that adds backend traffic while NOT QUALIFIED; new endpoints join the load mix (F3).
- Migrations are prepared only; applying needs explicit owner approval per migration.
- Free core: no charge for import/export, reminders, search/filter/sort or history.
- D14 notification rules unchanged unless D-B amends them.

## Review Focus (program-wide)
1. **Account switch mid-operation** (export running, offer showing, guest intent pending, custom-list drag in flight, date fill in flight): every new owner captures `AccountContext` and checks `isCurrent` before writing, and every new private request runs inside `accountSession.withCredentialLease(for:)`; each plan with a private request pins a pre-dispatch-switch test (F2 `DateFillCredentialLeaseTests`, W2, W5 replay, W6, W9 `OrganiseCredentialLeaseTests`, W10) and a `<Suite>/flagOffSendsNoRequest` test (F2, W2, W4, W5, W6, W9 ×2, W10).
2. **2,000-title libraries:** every list-wide computation (export, grouping, tag filter, up-next) has a test at that size.
3. **Offline:** export, grouping, tags and lists read from local state; network-only sections show branded offline states, never blank.
4. **Deleted account:** every new per-user table is covered by `delete-account` and a DB/Deno test.
5. **German copy length:** every new string has DE copy and a render test at the largest Dynamic Type size the design caps allow.

---

## Phase 0: owner prerequisites (no code)
- [ ] **D-A first: AniList terms (spec §2).** The current terms (changed 2026-08-18) prohibit API use, including media data, in any competing list/tracker service and prohibit mass collection, with no exception. This concerns how Kuro's live catalogue is sourced, not only new work. Options: legal advice, alternative catalogue sources (each with its own terms check), or knowingly accepting the risk. The outcome may change W7 and parts of the product, so decide before building.
- [ ] D-F: commit/merge the current branch `codex/review-remediation-20261108` (uncommitted: docs, iOS Discover durability, the sources and receipts of the **five** live migrations `20261108120159`, `20261108120211`, `20261109001251`, `20261109003243`, `20261109100800`, and `scripts/load/`). All plans branch from that commit: `git switch -c kuro/tracker-gaps` after it lands.
- [ ] D-B, D-C, D-D, D-E: decide when ready. Each unblocks one outline below.
- [ ] D-G (from W6 planning): reviewed series membership (`series`, `series_sections`, `series_entry_spans`) is live but was empty at the 2026-11-01 audit and nothing writes it. W6 ships correct but changes nothing visible until membership is filled: choose an owner-reviewed list or an explicitly approved rule (06-grouping Task 7). Never merge on mere relations.

- [ ] D-H: release gate for backend-traffic features. (a) Blanket [current default]: nothing that adds backend traffic goes live while the overall qualification is NOT QUALIFIED, so only W3a can ship now. (b) Per-feature: a feature may go live when its own F3 profile meets its budget class in an owner-approved run and the 20 rps steady result does not worsen; W5 guest browsing still waits for full qualification (a whole new anonymous population). Recommendation: (b).

## Smaller owner decisions raised by the plans (defaults in brackets; the plans implement the default)
| Plan | Decision |
|---|---|
| F2 | Server-side cap on repeat count [no server cap; client limits 0–999] |
| F3 | Apply the minimum-sample rule (≥ 100 per endpoint, ≥ 30 per subgroup) to the base qualification lane too [report sufficiency for the base lane without changing its pass rule; at 20 rps the 2,000-title Parse/Recommend subgroups get only a handful of samples, as R13's 3-sample Recommend fail shows, so a dedicated targeted run is needed for them] |
| W2 | CSV formula cells — **resolved**: neutralise (`'` prefix) in CSV; JSON keeps exact text |
| W3a | Offer on Watching only, not Planning [Watching only: a Planning title never notifies today, so an offer would promise nothing] |
| W4 | Read-only count of adult titles in the live catalogue before starting (decides whether the import label can ever appear); Hentai genre counts as 18+ [yes]; a new unresolved-titles CSV in import review [yes] |
| W5 | Per-IP limit for anonymous reads — a **current production exposure** for every install (anon SELECT on `anime`/`manga` is live today), not something W5 introduces (Supabase's limiter cannot limit GET reads; options in plan); guest telemetry [off until the privacy text says so]; Discover R4/R5 exception for guests (Plan / Not interested open sign-up) [yes] |
| W6 | Pilot of ≈ 10 owner-reviewed series via D-G (any publish also changes Home/detail for every user; 06-grouping Task 8 Step 2 checks this first) |
| W9 | Tags and list items keyed by title and allowed only for titles in the library [yes] |
| W10 | Section on the Completed view [yes]; dismissals reuse Discover's Not interested (also hides on Discover, counts as Taste skip) [yes] |
| F2 / W10 (lead) | Existing `LibraryStore` → `PostgrestLibraryTransport` writes take no credential lease (05-guest Review Focus 6). F2 leases only the new date leg; W5 leases its replay at the caller; W10's Plan/Undo reuse the unleased existing path. Lease every Library write in one separate change [recommended; not in these plans] |

## Phase 1: foundation (sequential, first)
Plan: [`00-foundation.md`](00-foundation.md)
- F1 BDD traceability gate (WARN until W2 lands, then blocking for landed features) + F1.3 `--accepted` execution records. Workstream attribution (spec §4): the feature file's basename up to its first `-` (`W3-alerts.feature` → `W3`), unless a Scenario/Rule/Feature carries `@workstream-<ID>` (the F2 Rule in `W9-lists.feature`). Each final task commits its record `acceptance/<WS>.json` on its own, after the tested commit (F1.3 rule 2).
- F2 Library contract v2: `PartialDate`, editable repeat count and dates through `LibraryEdit`, date auto-fill behind `library_date_autofill_v1`, and F2.5 widening the shared bare-plan check (Taste/Discover Plan-key Undo must not delete a dated plan). W2, W9 and W7 consume it.
- F3 load profiles on the absolute-rate model: the base mix keeps its 20 rps; profiles add their own rates in a separate lane, reported separately; `tracker-gaps-combined` names every rate; `--qualify` demands populated fixtures, semantic assertions, writes, cleanup and ≥ 100 samples per endpoint / ≥ 30 per subgroup (else `insufficient`).

## Phase 2: first workstreams (export and alert offer first, then 18+ notice, then Up next)
| Plan | Workstream | Touches |
|---|---|---|
| [`02-export.md`](02-export.md) | W2 export | `KuroLibrary` exporters, Profile tool sheet |
| [`04-adult-notice.md`](04-adult-notice.md) | W4 18+ notice | search RPC + SearchStore, import review |
| [`03-alerts.md`](03-alerts.md) | W3a alert offer | Releases owner, save confirmation |
| [`10-up-next.md`](10-up-next.md) | W10 up next | new RPC + Collection section |

## Phase 3: bigger items
| Plan | Workstream | Note |
|---|---|---|
| [`06-grouping.md`](06-grouping.md) | W6 one row per series | with the reviewed-membership pilot (D-G) so it is visible |
| [`09-lists.md`](09-lists.md) | W9 tags, custom lists, dates | after F2 and W6 |
| [`05-guest.md`](05-guest.md) | W5 guest browsing | **last**; blocked on D-A, data/access controls and full qualification |

## Release gates (every workstream)
- [ ] All feature scenarios green and resolved by F1; gates in spec §5.1 green.
- [ ] Owner approves each prepared migration by name and checksum; apply in one transaction; record in history; verify with the plan's DB checks live (read-only) afterwards.
- [ ] Three separate switches: migration applied (owner approval), endpoint qualified (qualification-mode F3 run), feature shown (flag raised). Flags: W2 `library_export_v1`, W4 `search_adult_notice_v1`, W5 `guest_browsing_v1`, W6 `collection_series_grouping_v1`, W9 `library_organise_v1`, W10 `collection_up_next_v1`, F2 `library_date_autofill_v1`; all start at 0 % and send no request while off.
- [ ] Backend-traffic workstreams (W2 lookup, W4, W5, W6 membership read, W9, W10, F2 date fill): go live according to D-H.
- [ ] Acceptance: `check_bdd_traceability.sh --accepted <workstream>` (`F2`, `W2`, `W3`, `W4`, `W5`, `W6`, `W9`, `W10`) passes against `docs/tracker-gaps-2026-11/acceptance/<workstream>.json` for the release commit (resolved ≠ accepted).
- [ ] TestFlight build (next number 26) with release notes in plain English; Rule 1/Rule 2 docs updated.


## Shared files and merge order
Lanes run in parallel, but these files are edited by more than one plan. Merge in the order given; the later lane rebases onto the earlier one and re-runs its own tests.

**Merge order:** F1 (incl. F1.3) → F2 (incl. F2.5) → F3 (F3.1, F3.1b, F3.1c, F3.1d, F3.2) → W2 → W3 → W4 → W10 → W6 → W9 → W5. W2 Task 1 (`KuroLibrary/RFC4180.swift`) must precede W4 Task 5. W4 precedes W5 (allowlist rows 18–19 name W4's `search_*_page_v2`).

| Shared file | Plans | Rule |
|---|---|---|
| `scripts/quality-gates/run_all.sh` | F1, F3.1b, W2 | F1 adds `bdd-selftest` (1) and `bdd-traceability` (0); F3.1b adds `load-profiles` (1); W2's final task flips `bdd-traceability` to 1. |
| `scripts/quality-gates/bdd_landed.txt` | W2 (creates), W3, W4, W5, W6, W9, W10 | F1's landed scope. W2 creates it with `W2-export.feature`; every later final task appends its own feature file. Resolution findings block only for listed features. |
| `scripts/load/profiles/` | F3.1d, W2, W4, W5, W6, W9, W10 | One `<name>.js` + `<name>.test.js` per profile, in F3's contract (`ratePerSecond`, `emptyExamples`, `validate(…, ctx)`, write profiles `seed` + `cleanupCheck`; a `weight` field throws). No plan edits `backend_workload.js` after F3. |
| `scripts/load/workloads/tracker-gaps-combined.js` | F3.1c (creates), F3.1d, W2, W4, W5, W6, W9, W10 | Each profile's task appends its one line; final rates: `status-with-date-fill` 0.4, `export-mal-id-lookup` 0.2, `search-with-hidden-adult-count` 1, `guest-browse` 5 (anonymous), `collection_series_membership` 1, `collection-with-tags-and-lists` 5, `collection-up-next` 2 = 14.6 rps on top of the 20 rps base (table and sample arithmetic in `00-foundation.md` F3.1c). |
| `supabase/tests/pending_migrations.txt`, `supabase/tests/README.md` | W4, W5, W9, W10 | Append in timestamp order: `20261110100000` (W4), `20261110110000` (W5), `20261110120000` (W9), `20261110130000` (W10). |
| DB test numbers | F3.2, W4, W5, W9, W10, W2, W6 | 104 F3.2 · 105 W4 · 106 W5 · 107/108 (+ `concurrency/108`) W9 · 109 W10 · 110 W2 · 111 W6. |
| `supabase/tests/rls/50_account_deletion_fk_and_rpc.sql` | W9 | Only W9 adds per-user tables (W10 adds none). |
| `Kuro/Composition/AppComposition.swift`, `KuroTests/IdentityCompositionTests.swift` | F2, W2, W4, W5, W6, W9, W10 | F2 first: `makeLibrary(backend:dateAutofillEnabled:credentialLease:)`, `CompositionGraphTests/dateAutofillFollowsTheServerFlag`, and `SessionSDKHarness.init(…, flags: FeatureFlags? = nil)` (later plans find it present). Then the final `makeAccountScopedStates` / `expectedAccountScopedStates` order: `libraryActions, home, collection, libraryTags, customLists, upNext, discovery, recommendations, releases, social, availability, clubs, imports, concierge, taste, support, libraryExport, widgets, songPreview, interactionTelemetry`. `GuestSession` (W5) is not account-scoped. W5 changes `CatalogStore(client:accountSession:)`; W6 changes `makeCollection(…userDefaults:groupingEnabled:)`. |
| W2 ↔ W9 export wiring | W2, W9 | W2 consumes `LibraryExportService(tagsByKey:customLists:)` with providers `@MainActor () async -> [MediaKey: [String]]?` and `@MainActor () async -> [ExportCustomList]?`. W9 provides `LibraryTagsStore.tagsByKey`, `CustomListsStore.exportLists() -> [ExportCustomList]?` (W2's `KuroLibrary` type `ExportCustomList(id:name:createdAt:items: [MediaKey])`: lists in manual order with plain keys, empty lists and titles no longer in the library included; W2 derives `position`, `in_library` and `title`) and `FeatureFlags.libraryOrganiseV1Enabled` (`library_organise_v1`; off → the providers return empty without a request). Wired in `makeGraph` by whichever of W2/W9 lands second (with the order above: W9 Task W9.6). |
| `Kuro/KuroApp.swift`, `Kuro/Services/FeatureFlags.swift` | F2, W2, W4, W5, W6, W9, W10 | Additive (`.environment(...)` lines, flag accessors: F2 `libraryDateAutofillV1Enabled`, W2 `libraryExportV1Enabled`, W4 `searchAdultNoticeV1Enabled`, W5 `guestBrowsingV1Enabled`, W6 `collectionSeriesGroupingV1Enabled`, W9 `libraryOrganiseV1Enabled`, W10 `collectionUpNextV1Enabled`); keep alphabetical within the new block. |
| `Kuro/Views/EditorialCollectionView.swift` | W3, W6, W9, W10 | W3 (foot-slot stack, batch suppression) → W10 (Completed section, `FolioNotice.undo`) → W6 (grouped items, counts, select mode) → W9 (tag strip, lists link, organise sheet). |
| `Kuro/Views/Lists/FolioHeader.swift`, `FolioItems.swift` | W6, W9, W10 | W10 (`FolioNotice.undo`) → W6 (Group seasons switch, group row) → W9 (`FolioRowActions.organise`). |
| `Kuro/Views/EditorialSearchView.swift` | W3, W4, W5 | W3 (offer stack around the banner) → W4 (footnote, rebased onto W3's stack) → W5 (Browse row identifier). |
| `Kuro/Views/TastePicksView.swift`, `Kuro/Views/Discover/Preview/DiscoverFeedbackController.swift`, `Kuro/Views/Home/HomeShelfPolicy.swift` | F2.5, W3, W5 | F2.5 (`TastePlanAction.isBarePlan` widened; doc comments) → W3 (offer slot) → W5 (guest gate). |
| `Packages/KuroModules/Sources/KuroLibrary/LibraryStore.swift`, `LibraryValues.swift` | F2 | Date fill, `dateAutofillEnabled`, `credentialLease` (the leased date leg); later plans only read. |
| `Kuro/Library/LibraryActions.swift` | W3 | — |
| `Kuro/ContentView.swift`, `Kuro/Views/Routing/KuroNavigationCoordinator.swift`, `Kuro/Views/Routing/JourneyHost.swift` | W3, W5 | W3 (visible-page signal for the offer) → W5 (guest gate in the root). |
| `CURRENT_APP_STATE*.md`, `IMPLEMENTATION_PLAN_Variation1.md`, `CLAUDE.md` file map | all | Inventory counts are recomputed from `check_docs_current_state.py` at each merge, never carried over from a plan's arithmetic. |

---

## Gated outlines (full plans are written when the decision lands)

### W1 Home Screen widget (needs D-E)
The widget code, tests and `KuroWidgetSupport` package exist; builds 24–25 shipped widget-less because API-key signing cannot create App Groups.
1. Owner registers `group.com.Kuro.app` for `com.Kuro.app` and `com.Kuro.app.widgets` (Xcode, Apple ID).
2. Restore the widget embed in the release lane (`fastlane/Fastfile`, `release_candidate.rb` checks `CURRENT_PROJECT_VERSION` parity).
3. Run the existing widget suites named in `W1-widget.feature`; archive; install on a device; owner visual acceptance; TestFlight 26.
Success: spec §5.2 W1.

### W3b Manga chapter alerts (needs D-B)
Options in spec §2. Option 2 (day-precision at 09:00 local) changes `ReleaseNotificationPlanner` eligibility and copy only; option 3 needs `BGAppRefreshTask` registration, a background read of new chapter rows, and a per-title last-seen marker. Both keep: permission only from toggle/bell, default off, cleared on sign-out.

### W7 Two-way AniList sync (needs D-A: authorization + API client)
Shape decided now so the decision is informed:
- **Status after the 2026-11-09 review:** AniList's current terms prohibit this use with no exception, so W7 is not a route to permission and stays parked unless D-A changes the picture (for example a written agreement). Shape kept for reference:
- On-device sync (AniList's limit is per client IP, currently 30 requests/minute): `AniListSyncQueue` outbox in `KuroLibrary` (durable like `ProgressOutbox`), drained at ≤ 1 write per 2.5 s, `SaveMediaListEntry` mutations from `LibraryEdit` (F2 fields map to `repeat`, `startedAt`, `completedAt`).
- Link flow with `ASWebAuthenticationSession`; token in Keychain through an injected credential store (pattern: `MALCredentialStore`).
- Identity preview before the first write (counts of additions, updates, conflicts), visible queue, conflict choice with Undo (research decision: "Optional automation needs an identity preview, queue visibility, conflict policy and undo").
- Pull side: periodic read of the user's AniList list, reconciled through the existing import reconciler.
Feature: `W7-anilist-sync.feature`.

### W8 Dark mode (needs D-D)
Can start before the decision: a gate script `check_color_tokens.sh` that fails on raw `Color(red:…)`, `.black`, `.white` and hex literals outside `Kuro/Design/` (WARN first; count offenders as the baseline). After D-D: dark token values in `KuroDesignSystem.swift`, `ArtworkMaterial` dark rule (white text ≥ 7:1), remove `.preferredColorScheme(.light)` in favour of an Appearance setting (System/Light/Dark, per device), render every gallery screen in both appearances for owner acceptance.

### W10 Dub info and where to watch (needs D-C)
`streaming_availability_v1` stays at 0 % until a data source is chosen; the provider UI exists (`Kuro/Providers/`). Dub data has no source today. Write the plan after D-C.

---

## How to execute (adopted from the 2026-11-09 independent review)
- **One coordinated lead implementer per phase** owns shared composition (`AppComposition`, `KuroApp`), Collection/Folio and lifecycle changes, and lands them sequentially in the merge order above.
- **Parallel help only for isolated pieces** once the foundation is stable: pure exporters, pure policies, SQL tests, load-profile tooling.
- **A fresh independent reviewer at every workstream boundary** (specialist + QA, per the owner's global instructions), with extra scrutiny on identity/credential leases, permissions and grants, Undo/recovery, and wire contracts. Not a reviewer per tiny task, and not one review after everything.

## Plan size
70 tasks after the 2026-11-09 corrections (`grep -c '^### Task'`: foundation 14, W2 8, W3 6, W4 8, W5 8, W6 9, W9 9, W10 8) and 86 scenarios in 10 feature files (74 live, 12 gated: W1 4, W3b 1, W7 3, W8 3, W10 dub/where-to-watch 1). Live scenarios by workstream (spec §4 attribution): F2 6, W2 13, W3 8, W4 5, W5 8, W6 11, W9 14, W10 9. Before the corrections: 65 tasks and 59 scenarios.
