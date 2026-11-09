# W6 One List Entry Per Series Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collection shows one row per reviewed series ("S2 · 5/12"), +1 advances the season you are on, a fold shows every season with its own status and +1, and a per-account "Group seasons" switch turns it off; grouping never changes a single library entry.

**Architecture:** A pure `SeriesListGrouping` in `KuroLibrary` turns `[LibraryEntry]` plus a reviewed-membership map into list rows (display only). The membership map comes from a new cached, batched PostgREST read of the already-live, public `series_entry_spans` / `series` / `series_sections` tables (no migration) held by `CatalogStore`. `CollectionStore` builds the rows from the whole Library (not the paged feed), hydrates missing member cards, owns the per-account switch, and the Folio views render a group row with an inline `KuroFoldMemory` fold. The group status follows the member you are on (a Watching/Reading or Rewatching/Rereading member decides; corrections brief 2026-11-09). Every membership/card read runs only while `collection_series_grouping_v1` is on and inside a credential lease of the captured account. **Reviewed membership is empty in production today, so W6 ships visually identical to today until the owner-decided population runs: first the ≈ 10-series reviewed pilot (Task 8, TestFlight evaluation behind the flag), then the broad population (Task 7, D-G).**

**Tech Stack:** Swift 6.2 toolchain in Swift 5 language mode (package), SwiftUI + `@Observable`, Swift Testing, supabase-swift PostgREST, PostgreSQL 17 disposable fixture, Node load harness `scripts/load/`.

**Spec:** docs/superpowers/specs/2026-11-09-tracker-gaps-design.md + docs/superpowers/specs/2026-11-09-tracker-gaps/features/W6-grouping.feature

---

## Investigation findings (read before Task 1)

**Rule code.** `Packages/KuroModules/Sources/KuroLibrary/SeriesGrouping.swift` (`SeriesGrouping.decide(ContinuityEvidence) -> ContinuityDecision`) joins only when `sameReviewedContinuity == true`; MOVIE/FILM → `.join(label: "Film")`, SPECIAL/OVA/ONA/MUSIC/TV_SHORT → `.join(label: "Extra")`, else `.join(label: nil)`; `ordinal(fromCalendarSeason:)` always returns nil. Its only caller is `Tests/KuroLibraryTests/SeriesHomeFoundationTests.swift:78-82`. No app code uses it.

**Where reviewed membership lives.** `supabase/prepared-migrations/20261007040000_series_home_foundation_v1.sql` (despite the folder name, this migration is **applied live**; CLAUDE.md migration caveat):
- `series` (`continuity` default `'singleton'` ∈ singleton/verified/disputed; `grouping_state` default **`'approved'`**; `medium`), `series_sections` (`kind` season/film/extra/edition, `ordinal`, `name`, `sort_order`, `state`), `series_entry_spans` (`series_id`, `section_id`, `medium`, `anime_id`/`manga_id`; partial unique indexes `series_entry_spans_anime_uq (anime_id)` and `series_entry_spans_manga_uq (manga_id)`, so a title belongs to at most one series), `mapping_revisions` / `mapping_revision_spans` (`state` proposed/approved/superseded, `source`, `rule_revision`, `reviewer` nullable).
- RLS on, policies `*_public_read ... for select to anon, authenticated using (true)`, `grant select ... to anon, authenticated` (lines 451-473, 519-523). A client read needs no migration.
- The only writer is `publish_mapping_revision(uuid)` (service role only; lines 1102-1225). It sets `series.continuity = 'verified'`, `grouping_state = 'approved'`, sections `state = 'approved'`.
- **Loophole to avoid:** a `series` row inserted with defaults is `grouping_state = 'approved'` but `continuity = 'singleton'`. The existing server readers (`collection_series_page_v1`, `collection_series_children_v1`, `anime/manga_home_resume_v1`) check only `grouping_state = 'approved'`. W6 defines "reviewed" as **`continuity = 'verified'` AND `grouping_state = 'approved'` AND section `state = 'approved'` AND `series.medium = span.medium`**, which only `publish_mapping_revision` produces.
- `media_franchise_components` (`20260804140000`) and `media_franchise_ids_v1` (`20261104100000`) are automatic connected components over AniList `media_relations` (sequels, side stories, alternatives, characters). **They are not reviewed membership and W6 must never read them.**

**Is any reviewed membership live? No (as far as the repository can show; production was not queried).**
- `docs/overnight-2026-11-01/understand/product-surfaces.md` §1.1 and `schema.md` §4: `series`, `series_sections`, `series_entry_spans`, `mapping_revisions`, `mapping_revision_spans` are 8 kB heaps ("empty or near-empty").
- `docs/overnight-2026-11-01/REPORT.md`: "Series grouping has **no producer**".
- `docs/overnight-2026-11-01/understand/CRITIC.md`: nothing outside SQL calls `publish_mapping_revision` (no hits in `scripts/`, `supabase/functions/`, `tools/`, `Kuro/`).
- `docs/handoffs/2026-10-07-home-series-evidence/INDEPENDENT_REVIEW.md` (line 159): a republish nulls section-scoped data. Population (Task 7) must therefore publish each series once, carefully.
- Consequence: the rule stays strict (no merging on relations). Task 7 prepares the population path as **owner decision D-G** (`00-program.md`; called D-W6 in earlier drafts of this plan). Task 8 is the owner-reviewed pilot at ≈ 10 series. Until either runs, every row stays its own row.

**Other live readers of reviewed membership (publishing is NOT flag-gated for them).** Publishing a series changes more than Collection:
- `home_bundle_v1` (Home is live at 100 %) joins approved spans and returns `series_id`, `section_ordinal`, `section_kind`, `section_name` (`20261007040000` lines ~1378-1386). The client shows "S\(ordinal)" labels from them (`Kuro/Home/HomeContracts.swift:63-66`), and `HomeItem.id` becomes `seriesId ?? "entry:\(mediaId)"` (`HomeContracts.swift:18`): two tracked seasons of one published series can share one id.
- `series_detail_bundle_v1`, `home_pending_page_v1`, `collection_series_page_v1` / `_children_v1` and `home_events_page_v1` (re-created in `20261101000000`, line ~174, which adds a saved/followed series' spans to the tracked set via `user_series_intent`) also read approved spans.
- These readers check only `grouping_state = 'approved'` and are not behind `collection_series_grouping_v1`. Any publish (pilot or broad) therefore changes Home/detail for **every** user who tracks a published title. Task 8 makes the owner approve that all-users effect explicitly.

**Collection today.**
- `Kuro/Views/EditorialCollectionView.swift` builds `FolioItem`s from `collection.displayedFeedItems`, which are paged (90/120) and **status-filtered on the server** (`feedStatus`), joined with `LibraryStore` and `ReleasesStore`. The strip counts come from `FolioPolicy.counts(library.allEntries, medium:)`.
- Density is `@AppStorage("kuro.folio.density.anime|manga")`, which is per device. +1 is `advance(_:)` → `CollectionStore.advanceFromList(key, cap: item.total)` → `undoListAdvance()` (`Kuro/Collection/CollectionStore+Lists.swift`). Rows: `FolioIndex` / `FolioShelf` (`Kuro/Views/Lists/FolioItems.swift`). Controls: `FolioControlsRow` (`Kuro/Views/Lists/FolioHeader.swift`).
- `CollectionStore.fetchSeriesPage` / `fetchMoreSeriesChildren` (server `collection_series_page_v1`) and `CollectionSeriesGroup` exist but no view uses them; only `KuroTests/LibraryFacadeTests.swift` does. **W6 does not revive that path or reuse those names.** It is server-paged by group, carries no section ordinal, and uses the weaker approval filter.
- Per-account device preferences follow `DiscoverVisitLedger.storageKey` (SHA-256 of the lower-cased user id, first 16 hex chars) and are removed in `removeDeletedAccountData(userId:)`. `CollectionStore` has no `UserDefaults` today, and `AppComposition.makeCollection` does not pass one.
- Public batched reads follow `DiscoveryStore.loadFranchiseIds` (300 ids per medium per request, silent fallback) and `CatalogStore.fetchAnimeByIdsPreservingOrder` (card cache, 100 per batch, `toMedia()`).

## Decisions taken in this plan (HOW, inside spec §6)

1. **Group status rule (owner-approved correction, 2026-11-09; replaces spec §6's "most recently updated member").** The member that decides the status is the *anchor*:
   - If any member is Watching/Reading or Rewatching/Rereading (`.current` / `.repeating`), the anchor is the most recently updated such member, and the group shows its status. +1 targets it.
   - Otherwise, if every member is Planning, the anchor is the most recently updated member and the group shows Planning.
   - Otherwise, the anchor is the most recently updated member (whatever its status, Planning included), and the group shows its status.
   - Ties on `updatedAt` break by `ListStatus` raw value, then larger `key.id`.
   Consequence: re-rating a finished S1 after S2 does not move a series you are still watching out of Watching.
2. **Group row placement.** A group appears once, in the status strip of its group status, at the anchor's recency position (`anchor.updatedAt`). Its other members do not appear separately in other strips while grouping is on. The anchor always has the group status, so it is always in that strip's server-filtered feed. Feed paging and order stay as they are.
3. **Strip counts count rows** (groups + singles) while grouping is on, so a count never disagrees with what the strip shows. Profile "Your lists" stays per entry (out of scope).
4. **Display member** = the anchor. Invariant: `advanceTarget == nil || advanceTarget == anchor` (when an active member exists it is both the anchor and the +1 target). Title, cover, sorts (title, score, next release), the row's open tap and its context menu all use the display member. The menu items name it, for example "Edit S2". Search matches the group if any member's loaded title matches.
5. **Selection never acts on a whole group silently.** In select mode, groups render expanded and only member rows are selectable. A group row has no selection id.
6. **+1** calls `advanceFromList(target, cap: targetTotal)` with the **member's own** total, never another member's. Because the +1 target is the anchor, its feed item (and card total) is loaded whenever the row is shown. The key is still hidden while that total is unknown (no card yet). The existing Undo path is unchanged.
7. **Labels.** The "S2" / "St. 2" label comes only from a reviewed `series_sections.ordinal` with `kind = season`. "Film" and "Extra" come from `SeriesGrouping.decide`. No ordinal means no S-number. Labels never come from sort position or calendar season.
8. **Imported-titles view** (`importedTitleKeys != nil`) never groups. It is an explicit subset.
9. **Release switch** `collection_series_grouping_v1` (server `feature_flags`, read through the injected `FeatureFlags`, default 0 %; client default off). It is checked **before** any request: while it is off there is no membership read, no member-card hydration, no `.added` follow-up read, no switch and no grouping. Pinned by `SeriesGroupingCollectionTests/flagOffSendsNoRequest`. This keeps the new read dark while capacity is NOT QUALIFIED (see open question Q1). Migration/publish, endpoint qualification and showing the feature stay three separate steps.
10. **Switch visibility.** "Group seasons" shows only when the flag is on and the current medium has at least one group of two or more reviewed members. A control that cannot do anything is not shown.
11. **Credential lease.** The membership rows and member cards are public catalogue data, but each request's parameters are the signed-in account's library ids. `CollectionStore` (which has `accountSession`; `CatalogStore` gains one only in W5, which merges later) therefore runs every membership read and card hydration, including the `libraryDidChange(.added)` read, inside `accountSession.withCredentialLease(for: account) { … }` of the context captured at the start (`Packages/KuroModules/Sources/KuroCore/AccountSession.swift:120`; pattern `Kuro/Home/HomeStore.swift:99`). An account switch during dispatch never sends A's ids with B's credentials. A lease-cancelled read records no `seriesMembershipCheckedAt` (B must not inherit a 24 h negative cache from A's cancelled read).

## Open questions for the owner / lead (do not resolve in code)
- **Q1, spec conflict.** §1 says W6 has no owner gate beyond TestFlight. But §3 says "A workstream that adds backend traffic is not released to users while the qualification is NOT QUALIFIED", and W6 adds one Browse-class read. This plan ships the feature behind flag `collection_series_grouping_v1` at 0 %. Plan review added "W6 membership read" to the backend-traffic list in `00-program.md` → Release gates; the owner still confirms that §1 is read this way.
- **Q2, group status rule — RESOLVED (owner-approved corrections, 2026-11-09).** The old §6 rule ("most recently updated member") moved a series to Completed when a finished S1 was re-rated after S2. Replaced by Decision 1: an active (Watching/Reading/Rewatching/Rereading) member decides; otherwise Planning when all members are Planning; otherwise the most recently updated member. Pinned by `activeMemberDecidesGroupStatus` and `groupStatusFallsBackWithoutActiveMember` (Task 1). Spec §6 and `00-program.md` (W6 row "Group row status = most recently updated season") still carry the old wording; the lead updates them.
- **Q3, D-G (was D-W6).** How reviewed membership is populated (Task 7): (a) an owner-reviewed list, or (b) an explicitly approved rule whose outputs are still published one series at a time. The ≈ 10-series pilot (Task 8) is option (a) at pilot scale only; the owner's approval of the pilot sheet decides those series and nothing else. Nothing is published live without approval.
- **Q4, feature file (resolved at plan review).** Spec §3 requires an SQL plan check and an F3 load profile for the new read. The two scenarios (`@sql:rls/111_series_membership_read.sql`, `@load:collection_series_membership`) are in `W6-grouping.feature` since plan review; Tasks 3 and 4 only verify them.

## Global Constraints
- "Target: **100 simultaneous active users**; steady **20 requests/second**, peak **40 requests/second**."
- "p95 end-to-end thresholds: **Browse/Search/Clubs/Progress ≤ 750 ms, Home/Detail ≤ 1200 ms, Discover/Moods ≤ 1500 ms, Edge Parse/Recommend ≤ 2500 ms**; zero unexpected errors/timeouts, zero dropped offered starts."
- "Rule for this program: every new or changed backend read/write is assigned to one existing budget class, added to `scripts/load/backend_workload.js` (F3), and covered by an SQL-plan check. A workstream that adds backend traffic is not released to users while the qualification is NOT QUALIFIED, and its change must not worsen the measured steady-state result. Budgets are never relaxed for a retry."
- "On-device budgets in this spec are **proposed, confirm after baseline** (the September full review forbids inventing budgets): measure first on the owned simulator `7FC4B58A-430C-457D-A017-6B0095723F3F`, record the baseline in the plan's evidence folder, then set the gate."
- Architecture: "one `@MainActor @Observable final class` owner per capability in `Kuro/<Capability>/`, built once in `AppComposition`; views read owners with `@Environment(Type.self)` and import no Supabase SDK module; account-scoped owners conform to `AccountScopedState`, capture `AccountContext` at the start of every async operation and check `isCurrent` before every private write, and are registered in `makeAccountScopedStates`; tracking reads/writes only through `LibraryStore` / `LibraryActions`; no second Supabase client; no Combine; `print` only inside `#if DEBUG`; no force unwraps."
- Navigation: "Rule 5 (navigation contract) and Rule 6 (Discover R1–R8) apply to every new screen, sheet and tap target."
- Copy/design: "every user-facing string through `KuroLocale` (EN + DE); monochrome only, no coloured status; branded states only (`check_branded_states.sh`); light only until W8 ships."
- Data rules: "Group franchises without throwing away season-level detail that some users explicitly like." "Preserve imported IDs through grouping and export."
- Continuity: "`SeriesGrouping.decide` — "A provider relation, a shared title or a calendar season is not membership." Only reviewed continuity joins a group."
- Database: "Migrations are written to `supabase/prepared-migrations/` and applied only after explicit owner approval; never `supabase db push --include-all` or history repair without a new approval." (W6 adds **no** migration.)
- Process: "Rule 1 (three state docs) and Rule 2 (memory) after every workstream; quality gates `scripts/quality-gates/run_all.sh` green; build warning count does not rise above the 2026-10-31 baseline (60 unique Kuro-side warnings)."

## Review Focus
1. **Group members on unloaded pages or in other strips.** Rows are built from the whole Library; the anchor decides the strip. Pin: `SeriesGroupingCollectionTests/groupAppearsOnceInItsGroupStatusStrip` (Task 6).
2. **Unreviewed or loophole membership.** Inputs: default-inserted `series` (approved but `singleton`), a superseded section, a manga span in an anime series, an AniList SEQUEL without a span. Pins: `SeriesListGroupingTests/onlyVerifiedApprovedSameMediumMembershipJoins` (Task 1) and `111_series_membership_read.sql` (Task 3).
3. **Group-row actions hitting every season.** Inputs: remove, edit, classify, batch status, batch remove. Pin: `SeriesGroupingCollectionTests/groupRowActionsTargetOneNamedSeason` and `selectedSeasonOfGroupIsWrittenByBatch` (Task 6).
4. **+1 past a total.** The cap is another member's total (for example the longest season's), or the target's total is unknown. Pin: `SeriesGroupingCollectionTests/groupAdvanceUsesTheActiveMembersOwnTotal` (Task 6).
5. **Account switch during membership/card hydration, and switch leakage between accounts.** Pins: `SeriesGroupingCollectionTests/memberHydrationFromPreviousAccountIsDropped`, `membershipReadNeverSendsPreviousAccountsIdsWithNewCredentials` and `groupSeasonsSwitchIsRememberedPerAccount` (Task 5); `SeriesMembershipReaderTests/cancelledReadRecordsNoNegativeCache` (Task 3).
6. **Status rule regressions.** A re-rated finished season or a newly added Planned season moving a series out of Watching. Pins: `SeriesListGroupingTests/activeMemberDecidesGroupStatus`, `groupStatusFallsBackWithoutActiveMember`, `advanceTargetIsAlwaysTheAnchor` (Task 1).
7. **A publish changing Home for everyone.** Pilot publishes are not flag-gated for Home/detail readers. Pin: Task 8 Step 2 Home impact check before any publish.

## Success parameters
Spec §5.2 row W6:

| Parameter | Measured by | Expected |
|---|---|---|
| Collection shows one row per reviewed series with the active season ("S2 · 5/12") | `cd Packages/KuroModules && swift test --filter SeriesListGroupingTests/reviewedContinuityMembersShareOneRow` | `✔ Test reviewedContinuityMembersShareOneRow() passed` |
| +1 advances that season's entry | `swift test --filter SeriesListGroupingTests/advanceTargetsActiveMember` + `xcodebuild … -only-testing:KuroTests/SeriesGroupingCollectionTests/groupAdvanceUsesTheActiveMembersOwnTotal` | both pass |
| Expanding shows every season with its own status | `xcodebuild … -only-testing:KuroTests/SeriesGroupingCollectionTests/expandShowsEverySeasonWithOwnStatus` | `** TEST SUCCEEDED **` |
| Turning grouping off restores per-entry rows | `xcodebuild … -only-testing:KuroTests/SeriesGroupingCollectionTests/groupSeasonsSwitchIsRememberedPerAccount` | `** TEST SUCCEEDED **` |
| No entry, id or status changes because of grouping | `swift test --filter SeriesListGroupingTests/groupingNeverChangesEntries` | pass |
| A series I am still watching stays in Watching when a finished season is re-rated | `swift test --filter SeriesListGroupingTests/activeMemberDecidesGroupStatus` | pass |
| Flag off sends nothing | `xcodebuild … -only-testing:KuroTests/SeriesGroupingCollectionTests/flagOffSendsNoRequest` | `** TEST SUCCEEDED **` |
| Pilot visible for evaluation (≈ 10 owner-reviewed series, flag on for TestFlight accounts only) | Task 8 `PILOT.md` (approved sheet SHA-256, read-only verification, TestFlight screenshots) | owner signs off; not a release criterion |
| Grouping is on-device; proposed budget 2,000 entries ≤ 50 ms (confirm after baseline) | baseline on simulator `7FC4B58A-…` recorded in `docs/tracker-gaps-2026-11/w6-grouping/BASELINE.md`; gate `swift test -c release --filter SeriesListGroupingTests/groupingTwoThousandEntriesWithinBudget` | median ≤ confirmed budget |
| Group membership read in Browse class | `scripts/db/run_local_db_tests.sh --only 111_series_membership_read` (index used) + `node --test scripts/load/profiles/collection_series_membership.test.js` (profile `collection_series_membership`, `budgetClass` `browse`, 750 ms) | `TESTS : … PASS`; node `# fail 0`. Release evidence only from an owner-approved `--qualify` run id (≥ 100 completions, non-empty answers); until then the `@load` scenario is `blocked`/`insufficient` in `acceptance/W6.json` |
| Outcome (learning goal, not a release criterion; revisit after 4 weeks) | "Fewer duplicate-looking rows; add-to-list of a sequel from the group row used." | **Open item:** no event, denominator or reviewer is named yet. This plan adds no telemetry because `InteractionTelemetry` was not read and the feature file does not ask for it. The lead names the event, its denominator and who reviews it after 4 weeks, or drops the goal. |

## File Structure
| File | Responsibility |
|---|---|
| `Packages/KuroModules/Sources/KuroLibrary/SeriesListGrouping.swift` (new) | `SeriesMembership`, `SeriesListRow`, `SeriesListIndex`, `SeriesListGrouping` (pure rows, label, counts, budget constant) |
| `Packages/KuroModules/Tests/KuroLibraryTests/SeriesListGroupingTests.swift` (new) | the five `@pkg` scenarios + pins |
| `Kuro/Catalog/CatalogStore+SeriesMembership.swift` (new) | batched, cached membership read (public catalogue data) |
| `Kuro/Catalog/CatalogStore.swift` (modify) | stored membership cache properties |
| `Kuro/Collection/CollectionStore+SeriesGrouping.swift` (new) | per-account switch, row memo, member card hydration, role lookup |
| `Kuro/Collection/CollectionStore.swift` (modify) | stored properties, `userDefaults`/`catalog`/`groupingEnabled` injection, account clear/cancel, `removeDeletedAccountData`, sink hook |
| `Kuro/Composition/AppComposition.swift` (modify) | pass `userDefaults`, `catalog`, flag closure to `makeCollection` |
| `Kuro/Services/FeatureFlags.swift` (modify) | `collectionSeriesGroupingV1Enabled` |
| `Kuro/Views/Lists/FolioGrouping.swift` (new) | `FolioGroup`, `FolioMember`, pure `FolioGrouping` (feed → items), `FolioShelfChunks`, `FolioGroupCopy` (EN/DE) |
| `Kuro/Views/Lists/FolioModels.swift` (modify) | `FolioItem.group`, `FolioItem.id` for groups |
| `Kuro/Views/Lists/FolioItems.swift` (modify) | group row + fold + member rows in Index; group cell + band in Shelf |
| `Kuro/Views/Lists/FolioHeader.swift` (modify) | "Group seasons" word switch in `FolioControlsRow` |
| `Kuro/Views/EditorialCollectionView.swift` (modify) | uses `FolioGrouping`, row counts, membership prepare, select-mode expansion |
| `KuroTests/SeriesGroupingCollectionTests.swift` (new) | the two `@swift` scenarios + pins |
| `KuroTests/SeriesMembershipReaderTests.swift` (new) | reader batching, filters, cache, silent failure |
| `supabase/tests/rls/111_series_membership_read.sql` (new) | reviewed-only result + index plan on 2,000 titles + grants |
| `scripts/load/profiles/collection_series_membership.js`, `.test.js` (new); `scripts/load/workloads/tracker-gaps-combined.js` (one line) | F3 profile `collection_series_membership` (GET via F3.1b, 1 rps, `requires` published membership) |
| `scripts/series_continuity_proposals.js` + `.test.js` (new, Task 7, owner-gated) | proposals → review sheet + `proposed` revisions SQL; never publishes |
| `docs/superpowers/specs/2026-11-09-tracker-gaps/features/W6-grouping.feature` | two scenarios (`@sql`, `@load`) added at plan review, see Q4; corrections 2026-11-09 added "Re-rating a finished season doesn't move a series I'm still watching" and "Grouping switched off on the server sends nothing" (11 scenarios) |
| `docs/tracker-gaps-2026-11/w6-grouping/` (new) | `BASELINE.md`, `EVIDENCE.md`, `MEMBERSHIP_POPULATION.md`, `PILOT.md` + pilot sheet/SQL (Task 8) |
| `docs/tracker-gaps-2026-11/acceptance/W6.json` (new) | F1 execution record (Task 9) |

---

### Task 1: Pure grouping rule in `KuroLibrary`

**Files:** Create `Packages/KuroModules/Sources/KuroLibrary/SeriesListGrouping.swift`, `Packages/KuroModules/Tests/KuroLibraryTests/SeriesListGroupingTests.swift`.

**Interfaces.** Consumes `LibraryEntry`, `MediaKey`, `ListStatus` and `SeriesGrouping.decide` / `ContinuityEvidence` (unchanged). Produces:
```swift
public struct SeriesMembership: Equatable, Sendable {
    public enum SectionKind: String, Sendable { case season, film, extra, edition }
    public let seriesId: String          // series.id (uuid text)
    public let medium: MediaKind         // the span's medium
    public let sectionKind: SectionKind
    public let ordinal: Int?             // reviewed series_sections.ordinal; never a calendar season
    public let sortOrder: Int
    public let sectionName: String
    public let isReviewed: Bool
    public init(seriesId: String, medium: MediaKind, sectionKind: SectionKind, ordinal: Int?, sortOrder: Int,
                sectionName: String, isReviewed: Bool)
    /// Reviewed = continuity verified AND series approved AND section approved AND same medium.
    public static func isReviewed(continuity: String, groupingState: String, sectionState: String,
                                  seriesMedium: String, spanMedium: String) -> Bool
}
public struct SeriesListRow: Identifiable, Equatable, Sendable {
    public enum ID: Hashable, Sendable { case entry(MediaKey); case series(MediaKind, String) }
    public let id: ID
    public let members: [LibraryEntry]   // byte-identical input entries, sorted by section sortOrder, then key.id
    public let anchor: MediaKey          // the member that decides the status (Decision 1): latest-updated
                                         // .current/.repeating member, else latest-updated member; placement + recency
    public let status: ListStatus        // anchor's status
    public let advanceTarget: MediaKey?  // the anchor when it is .current/.repeating, else nil
    public var displayMember: MediaKey { get }   // anchor (== advanceTarget whenever advanceTarget != nil)
    public var isGroup: Bool { get }             // members.count > 1
}
public struct SeriesListIndex: Sendable {
    public enum Role: Equatable, Sendable { case single; case anchor(SeriesListRow); case member(anchor: MediaKey) }
    public init(rows: [SeriesListRow])
    public func role(of key: MediaKey) -> Role
}
public enum SeriesListGrouping {
    public static func rows(_ entries: [LibraryEntry], membership: [MediaKey: SeriesMembership],
                            enabled: Bool = true) -> [SeriesListRow]
    public static func ungrouped(_ rows: [SeriesListRow]) -> [LibraryEntry]
    public static func sectionLabel(_ membership: SeriesMembership?, german: Bool) -> String?
    public static func rowLabel(_ row: SeriesListRow, membership: [MediaKey: SeriesMembership],
                                progress: Int, total: Int?, german: Bool) -> String?
    public static func counts(_ rows: [SeriesListRow]) -> [ListStatus: Int]
    /// Proposed, confirm after baseline (Task 2).
    public static let proposedBudget: Duration = .milliseconds(50)
}
```
Pinned rules for `rows`:
- Single pass, O(n).
- An entry joins a group only when it has a membership, `membership.medium == entry.key.kind`, and `SeriesGrouping.decide(ContinuityEvidence(link: .other, sameReviewedContinuity: membership.isReviewed, format: format(for: sectionKind)))` is `.join`. Format mapping: season/edition → "TV", film → "MOVIE", extra → "SPECIAL".
- The group key is `.series(kind, seriesId)`. A group that ends up with one member becomes a single row with id `.entry(key)`.
- Anchor and status follow Decision 1: if any member is `.current` or `.repeating`, the anchor is the latest-updated such member; else (all `.planning` or mixed) the anchor is the latest-updated member. `status = anchor.status`; `advanceTarget = anchor` when its status is `.current`/`.repeating`, else nil.
- Row order is the order of each row's anchor in the input. `LibraryStore.allEntries` is newest first.
- Anchor ties on `updatedAt` break by `ListStatus` raw value, then larger `key.id`, so the result is deterministic.
- `enabled == false` returns one `.entry` row per entry in input order.

Label rules:
- `sectionLabel`: season with an ordinal → "S\(n)" / DE "St. \(n)"; film → "Film"; extra → "Extra"; otherwise nil.
- `rowLabel`: `[sectionLabel(displayMember)]` + `"\(progress)/\(total)"` when the total is known, or `"\(progress)"` when progress > 0, joined with " · ". Nil when both parts are nil.

- [ ] **Step 1: Write the failing tests** in `@Suite struct SeriesListGroupingTests` (helpers: `entry(_ id: Int, _ status: ListStatus, _ progress: Int, minutes: Int)` built with `LibraryEntry(key: MediaKey(kind: .anime, id: id), rowId: id, status:, progress:, createdAt: t0, updatedAt: t0 + minutes*60, revision: 1, lifecycleId: fixed UUID, sourceMetadata: LibrarySourceMetadata(scoreRaw: "8", customLists: ["fav"]))`; `member(_ series: String, ordinal: Int?, sort: Int, kind: .season, reviewed: true)`).
```swift
@Test func reviewedContinuityMembersShareOneRow() {
    let s1 = entry(101, .completed, 12, minutes: 0), s2 = entry(102, .current, 5, minutes: 10)
    let m = [s1.key: member("A", ordinal: 1, sort: 1), s2.key: member("A", ordinal: 2, sort: 2)]
    let rows = SeriesListGrouping.rows([s2, s1], membership: m)
    #expect(rows.count == 1)
    #expect(rows[0].id == .series(.anime, "A"))
    #expect(rows[0].members.map(\.key.id) == [101, 102])
    #expect(rows[0].advanceTarget == s2.key)
    #expect(rows[0].displayMember == s2.key)
    #expect(SeriesListGrouping.rowLabel(rows[0], membership: m, progress: 5, total: 12, german: false) == "S2 · 5/12")
    #expect(SeriesListGrouping.rowLabel(rows[0], membership: m, progress: 5, total: 12, german: true) == "St. 2 · 5/12")
}
@Test func unreviewedRelationsStayOwnRows() {
    let a = entry(201, .completed, 12, minutes: 0), b = entry(202, .current, 3, minutes: 5)
    // AniList SEQUEL with no reviewed span: no membership at all.
    #expect(SeriesListGrouping.rows([b, a], membership: [:]).map(\.id) == [.entry(b.key), .entry(a.key)])
    // Same series id but not reviewed (default-inserted series: approved yet 'singleton').
    let unreviewed = [a.key: member("B", ordinal: 1, sort: 1, reviewed: false), b.key: member("B", ordinal: 2, sort: 2, reviewed: false)]
    #expect(SeriesListGrouping.rows([b, a], membership: unreviewed).count == 2)
    #expect(SeriesMembership.isReviewed(continuity: "singleton", groupingState: "approved", sectionState: "approved",
                                        seriesMedium: "anime", spanMedium: "anime") == false)
}
@Test @MainActor func advanceTargetsActiveMember() async throws {
    try await withHarness { h in
        h.signIn(Fixture.userA)
        let s1 = Fixture.entry(MediaKey(kind: .anime, id: 301), rowId: 1, status: .completed, progress: 12, updatedAt: Fixture.earlier)
        let s2 = Fixture.entry(MediaKey(kind: .anime, id: 302), rowId: 2, status: .current, progress: 5, updatedAt: Fixture.now)
        try await h.load([s1, s2])
        let m = [s1.key: member("C", ordinal: 1, sort: 1), s2.key: member("C", ordinal: 2, sort: 2)]
        let row = try #require(SeriesListGrouping.rows(h.store.allEntries, membership: m).first)
        let target = try #require(row.advanceTarget)
        #expect(target == s2.key)
        let pending = Task { await h.store.apply(LibraryEdit(progress: .set(6)), to: target) }
        let call = try await h.nextCall()
        #expect(call.request == .edit(LibraryEdit(progress: .set(6)), createIfMissing: nil, baseRevision: nil))
        call.answer(.write(LibraryWriteResult(entry: Fixture.entry(s2.key, rowId: 2, status: .current, progress: 6, updatedAt: Fixture.now), created: false)))
        _ = await pending.value
        #expect(h.store.entry(for: s2.key)?.progress == 6)
        #expect(h.store.entry(for: s1.key) == s1)
    }
}
@Test func groupingNeverChangesEntries() {
    let entries = (1...60).map { entry($0, ListStatus.allCases[$0 % 6], $0, minutes: $0) }
    let m = Dictionary(uniqueKeysWithValues: entries.filter { $0.key.id % 3 != 0 }.map {
        ($0.key, member("S\($0.key.id % 7)", ordinal: $0.key.id % 5 + 1, sort: $0.key.id)) })
    let before = entries
    let rows = SeriesListGrouping.rows(entries, membership: m)
    #expect(rows.count < entries.count)
    let flat = SeriesListGrouping.ungrouped(rows)
    #expect(Set(flat.map(\.key)) == Set(before.map(\.key)))
    #expect(flat.count == before.count)
    for original in before { #expect(flat.first { $0.key == original.key } == original) } // id, status, progress, rowId, lifecycleId, sourceMetadata
    #expect(SeriesListGrouping.rows(entries, membership: m, enabled: false).flatMap(\.members) == before)
    #expect(entries == before)
}
```
Pins (same suite):
- `onlyVerifiedApprovedSameMediumMembershipJoins`: `isReviewed` is true only for ("verified", "approved", "approved", "anime", "anime"). It is false for "disputed", "proposed", a "superseded" section, or ("anime", "manga"). Also, a manga entry whose membership has `medium: .anime` stays single.
- `sectionLabelComesOnlyFromReviewedOrdinal`: season with nil ordinal → nil; film → "Film"; extra → "Extra"; label with nil total and progress 0 → nil; `SeriesGrouping.ordinal(fromCalendarSeason: "SPRING") == nil` is unchanged.
- `activeMemberDecidesGroupStatus` (Q2 resolved; feature scenario "Re-rating a finished season doesn't move a series I'm still watching"): S2 `.current` at minute 10 and S1 `.completed` re-rated at minute 20 → `status == .current`, `anchor == S2`, `advanceTarget == S2`, `displayMember == S2`; the row's position follows S2 (`rows([s1, s2], …)` with S1 first in input still yields one row anchored at S2). Adding S3 `.planning` at minute 30 keeps `status == .current`, `anchor == S2`. A `.repeating` S1 at minute 5 next to a `.current` S2 at minute 10 → anchor S2 (latest active); with S1 `.repeating` at minute 15 → anchor S1, `status == .repeating`.
- `groupStatusFallsBackWithoutActiveMember`: (a) S1 `.planning` minute 0 + S2 `.planning` minute 10 → `.planning`, anchor S2, `advanceTarget == nil`; (b) S1 `.completed` minute 20 + S2 `.planning` minute 10 → `.completed`, anchor S1; (c) S1 `.completed` minute 0 + S2 `.planning` minute 10 → `.planning`, anchor S2 (the brief's fallback as written: most recent member wins even when Planned); (d) S1 `.paused` minute 10 + S2 `.dropped` minute 10 → tie broken by `ListStatus` raw value, then larger `key.id`, identical on repeated calls.
- `advanceTargetIsAlwaysTheAnchor`: over the 60-entry library of `groupingNeverChangesEntries`, every row satisfies `row.advanceTarget == nil || row.advanceTarget == row.anchor`, and `row.status == row.members.first { $0.key == row.anchor }?.status`.
- `countsCountRows`: for the first test's input, `counts(rows) == [.current: 1]`.

- [ ] **Step 2: Run, expect FAIL.** `cd Packages/KuroModules && swift test --filter SeriesListGroupingTests` → expect `error: cannot find 'SeriesListGrouping' in scope`.
- [ ] **Step 3: Implement** `SeriesListGrouping.swift` with the signatures and pinned rules above. Doc comments must say "display only: members are the caller's entries, never copies with changed fields".
- [ ] **Step 4: Run, expect PASS.** Same command. All tests in the suite pass, and the existing `SeriesHomeFoundationTests` still pass (`swift test`).
- [ ] **Step 5: Commit.** `git add Packages/KuroModules/Sources/KuroLibrary/SeriesListGrouping.swift Packages/KuroModules/Tests/KuroLibraryTests/SeriesListGroupingTests.swift && git commit -m "W6: pure SeriesListGrouping over reviewed continuity (display only)"`

### Task 2: 2,000-entry performance test and baseline

**Files:** Modify `Packages/KuroModules/Tests/KuroLibraryTests/SeriesListGroupingTests.swift`. Create `docs/tracker-gaps-2026-11/w6-grouping/BASELINE.md`.

**Interfaces.** Consumes `SeriesListGrouping.rows`, `SeriesListGrouping.proposedBudget`. Produces the test `groupingTwoThousandEntriesWithinBudget`.

- [ ] **Step 1: Write the test.** It builds 2,000 anime entries with ids 1...2000, mixed statuses and distinct `updatedAt`. 1,200 of them get reviewed membership in 400 series of 3 seasons. One warm-up call, then 7 timed runs with `ContinuousClock`; take the median.
```swift
@Test func groupingTwoThousandEntriesWithinBudget() {
    let (entries, m) = largeLibrary(count: 2_000, grouped: 1_200, seasonsPerSeries: 3)
    _ = SeriesListGrouping.rows(entries, membership: m)
    let clock = ContinuousClock()
    var samples: [Duration] = []
    var rows: [SeriesListRow] = []
    for _ in 0..<7 { samples.append(clock.measure { rows = SeriesListGrouping.rows(entries, membership: m) }) }
    let median = samples.sorted()[3]
    #expect(rows.count == 800 + 400)
    #if DEBUG
    #expect(median <= SeriesListGrouping.proposedBudget * 10, "debug guard; the gate runs -c release")
    #else
    #expect(median <= SeriesListGrouping.proposedBudget, "median \(median)")
    #endif
}
```
- [ ] **Step 2: Non-vacuity check** (brief item 7: this test is added after Task 1's code exists, so there is no honest red; never write a wrong expectation). Run it once and record that it was added green after Task 1. Then, as a labelled **non-vacuity check**, temporarily set `proposedBudget` to `.microseconds(1)` in `SeriesListGrouping.swift`, run `swift test -c release --filter SeriesListGroupingTests/groupingTwoThousandEntriesWithinBudget`, expect `Expectation failed: (median → …) <= …`, and revert the constant in this same step (`git diff --exit-code Packages/KuroModules/Sources/KuroLibrary/SeriesListGrouping.swift` clean before Step 3).
- [ ] **Step 3: Measure the baseline (no gate change yet).**
  - Host: `cd Packages/KuroModules && swift test -c release --filter SeriesListGroupingTests/groupingTwoThousandEntriesWithinBudget`.
  - Simulator: `cd Packages/KuroModules && xcodebuild -list`, to confirm the package scheme name (expected `KuroModules-Package`). Then `xcodebuild -scheme KuroModules-Package -configuration Release -destination 'platform=iOS Simulator,id=7FC4B58A-430C-457D-A017-6B0095723F3F' test -only-testing:KuroLibraryTests/SeriesListGroupingTests/groupingTwoThousandEntriesWithinBudget`. The test writes the 7 samples and the median (ms) to the file named by the environment variable `KURO_W6_BASELINE_OUT` when it is set (no `print`; it writes nothing when unset). On the simulator, pass it as `TEST_RUNNER_KURO_W6_BASELINE_OUT`.
  - Write host + simulator medians (5 runs each) and the machine/OS into `BASELINE.md`.
- [ ] **Step 4: Set the gate.** If the simulator median is ≤ 25 ms, keep `proposedBudget = 50 ms`. Otherwise set it to 2× the measured median and write "confirmed after baseline, YYYY-MM-DD" in its doc comment and in `BASELINE.md`. Re-run the release command and expect PASS.
- [ ] **Step 5: Commit.** `git add Packages/KuroModules/Tests/KuroLibraryTests/SeriesListGroupingTests.swift Packages/KuroModules/Sources/KuroLibrary/SeriesListGrouping.swift docs/tracker-gaps-2026-11/w6-grouping/BASELINE.md && git commit -m "W6: 2,000-entry grouping budget with recorded baseline"`

### Task 3: Membership read (SQL plan check + `CatalogStore` reader)

**Files:**
- Create: `supabase/tests/rls/111_series_membership_read.sql`, `Kuro/Catalog/CatalogStore+SeriesMembership.swift`, `KuroTests/SeriesMembershipReaderTests.swift`.
- Modify: `Kuro/Catalog/CatalogStore.swift` (stored properties).

**Interfaces.** Consumes `SeriesMembership` (Task 1) and the single SDK client in `CatalogStore`. Produces:
```swift
extension CatalogStore {
    nonisolated static let seriesMembershipBatch = 300          // ids per medium per request
    nonisolated static let seriesMembershipTTL: TimeInterval = 86_400
    /// Reads reviewed membership for keys not checked within the TTL. Public data; silent on failure.
    func loadSeriesMembership(for keys: [MediaKey]) async
    func seriesMembership(for key: MediaKey) -> SeriesMembership?
    var seriesMembershipMap: [MediaKey: SeriesMembership] { get }
}
// CatalogStore.swift stored properties:
//   private(set) var seriesMembershipVersion = 0                     (observed; bumps when the map changes)
//   var seriesMembershipStore: [MediaKey: SeriesMembership] = [:]
//   @ObservationIgnored var seriesMembershipCheckedAt: [MediaKey: Date] = [:]   (negative cache too)
```
Request per medium and batch (supabase-swift):
```
from("series_entry_spans")
 .select("anime_id,manga_id,medium,series!series_entry_spans_series_id_fkey!inner(id,medium,continuity,grouping_state),series_sections!series_entry_spans_section_id_fkey!inner(kind,ordinal,name,sort_order,state)")
 .eq("medium", m).in("anime_id"|"manga_id", values: chunk)
 .eq("series.continuity","verified").eq("series.grouping_state","approved").eq("series_sections.state","approved")
```
Every returned row is mapped through `SeriesMembership.isReviewed(...)` again before it enters the map (defence in depth). The FK constraint names are verified in Step 1's SQL (`pg_constraint`). If they differ, use the actual names.

- [ ] **Step 1: Write the failing SQL test** `111_series_membership_read.sql`. Header: `-- @requires table public.series_entry_spans`, plus `public.series` and `public.series_sections`. Run the body in one `begin; … rollback;`:
  - Follow `102_load_hotpaths.sql` so plan assertions stay stable: `set local jit=off`, bulk insert under `set local session_replication_role=replica` then `origin`, then `analyze` the three tables before any `explain`.
  - Insert 20,000 `anime` rows (ids 7_110_001…7_130_000), so 300 ids are about 1.5 % selective and an index plan is the correct plan. The first 2,000 are the "library". Add 6,000 spans in 2,000 published series of 3. Use a direct insert that mirrors `publish_mapping_revision`'s output: `continuity 'verified'`, approved series and sections.
  - Add one default-inserted series (`continuity` default `'singleton'`) with 2 spans, one verified series whose section is `superseded`, and one anime series holding a manga span.
  - Assertions (`tests.eq`):
    - 'server filter': the filter query is written as SQL equal to the PostgREST request (`join series s … join series_sections sec … where sp.medium='anime' and sp.anime_id = any(:ids) and s.continuity='verified' and s.grouping_state='approved' and sec.state='approved'`). It has **no** `s.medium = sp.medium` predicate, because PostgREST cannot compare columns across an embed. Over 300 ids that include all loophole ids, it returns exactly the expected count. The default-inserted and superseded ids are absent. The cross-medium span **is** returned; the client removes it (pinned in `SeriesMembershipReaderTests`).
    - 'index used': `explain (analyze, format json)` of the same query with 300 ids contains `series_entry_spans_anime_uq`.
    - 'fk names': `select conname from pg_constraint where conrelid='public.series_entry_spans'::regclass and contype='f'` contains `series_entry_spans_series_id_fkey` and `series_entry_spans_section_id_fkey`.
    - 'clients read only': `has_table_privilege('anon','public.series_entry_spans','select') = true` and `has_table_privilege('authenticated','public.series_entry_spans','insert') = false`, and the same for `series` / `series_sections`.
- [ ] **Step 2: Run.** `scripts/db/run_local_db_tests.sh --only 111_series_membership_read`. There is no honest red here: the tables, indexes and grants are live and replayed through `20261007040000`, so this is a characterization test of existing schema (brief item 7: never write a deliberately wrong expected count). Write the expected counts from the fixture's construction (published spans in the 300 ids, minus default-inserted and superseded ones, plus the one cross-medium span) and expect `111_series_membership_read … PASS`.
- [ ] **Step 3: Non-vacuity check** (labelled; reverted in this step). Temporarily delete the `and s.continuity='verified'` predicate from the 'server filter' query under test (the predicate that closes the default-insert loophole; the expected count stays unchanged). Run the same command → expect `not ok … server filter` because the default-inserted series' 2 spans now appear. Restore the predicate in this same step and re-run → `PASS`. Record both outputs in `EVIDENCE.md`. (No migration.) The fixture is not PostgREST, so the real request string is unproven locally, including the `!hint!inner` embed form. `EVIDENCE.md` must say so until the first owner-approved load or live run.
- [ ] **Step 4: Write the failing reader tests** in `@MainActor @Suite struct SeriesMembershipReaderTests`. Use `FacadeHarness` (`KuroTests/LibraryFacadeTests.swift`) with `h.server.respond { request in request.resource == "series_entry_spans" ? .json(rows) : .emptyArray }`:
  - `readsInBatchesOfThreeHundredPerMedium`: 650 anime keys + 10 manga keys → 3 anime requests (`anime_id=in.(…)` with 300/300/50 ids) + 1 manga request. Each URL contains `series.continuity=eq.verified`, `series.grouping_state=eq.approved` and `series_sections.state=eq.approved`.
  - `keepsOnlyReviewedRowsAndCachesNegatives`: the server returns one verified row and one `continuity:"disputed"` row. The map holds 1 entry. A second `loadSeriesMembership` for the same keys sends 0 requests. After `seriesMembershipCheckedAt` is moved back 86,401 s, it sends 1 request.
  - `crossMediumSpanIsDroppedOnTheClient`: the server returns a verified row whose `series.medium` is `"anime"` for a `medium: "manga"` span → the map stays empty.
  - `failureIsSilentAndKeepsKnownMembership`: an HTTP 500 on the second load leaves the first map unchanged. `seriesMembershipVersion` is unchanged and nothing throws.
  - `cancelledReadRecordsNoNegativeCache`: `loadSeriesMembership` runs in a `Task` whose `series_entry_spans` response is held (deferred); the task is cancelled (as a revoked credential lease does), then the response is released. Afterwards `seriesMembershipCheckedAt` has no entry for those keys, the map is unchanged, and the next `loadSeriesMembership` for the same keys sends exactly 1 request. Rule: `checkedAt` is written only for a chunk whose request completed with HTTP 200 while `!Task.isCancelled`.
- [ ] **Step 5: Run, expect FAIL.** `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,id=7FC4B58A-430C-457D-A017-6B0095723F3F' test -only-testing:KuroTests/SeriesMembershipReaderTests` → `cannot find 'loadSeriesMembership'`.
- [ ] **Step 6: Implement** the reader. It is modelled on `DiscoveryStore.loadFranchiseIds` (batching, `continue` on empty chunks) and `fetchAnimeByIdsPreservingOrder` (`#if DEBUG` print on error). `seriesMembershipVersion` bumps only when the map actually changes. `trimCachesForMemoryPressure` clears only `seriesMembershipCheckedAt`; the map is small public data. The reader itself takes no lease (`CatalogStore` has no `accountSession` before W5); its account-derived callers in `CollectionStore` wrap it (Decision 11, Task 5). It checks `Task.isCancelled` after each chunk and stops without recording `checkedAt`.
- [ ] **Step 7: Run, expect PASS** (same command).
- [ ] **Step 8: Verify the scenario** is in `W6-grouping.feature` (added at plan review, Q4) exactly as:
```gherkin
  @sql:rls/111_series_membership_read.sql
  Scenario: Only reviewed membership is read, through an index
    Given published, default-inserted, superseded and cross-medium series spans for 2,000 titles
    When the Collection reads membership for 300 of my titles
    Then only published same-medium spans are returned and the read uses the anime_id index
```
- [ ] **Step 9: Commit.** `git add supabase/tests/rls/111_series_membership_read.sql Kuro/Catalog/CatalogStore+SeriesMembership.swift Kuro/Catalog/CatalogStore.swift KuroTests/SeriesMembershipReaderTests.swift && git commit -m "W6: batched reviewed-membership read with SQL plan check"`

### Task 4: F3 load profile `collection_series_membership`

**Files:** Create `scripts/load/profiles/collection_series_membership.js`, `scripts/load/profiles/collection_series_membership.test.js`; modify `scripts/load/workloads/tracker-gaps-combined.js` (one line).

**Interfaces.** Consumes F3's profile contract exactly as `00-foundation.md` defines it: F3.1 (registry, `ratePerSecond`, separate absolute-rate lane; the predeclared mix keeps its 20 rps; a `weight` field throws), F3.1b (GET option, `core`), F3.1c (`emptyExamples`, `requires`, `validate(…, ctx)` with `ctx.mode`, `--qualify`, `tracker-gaps-combined`). `backend_workload.js` is not edited. Produces `scripts/load/profiles/collection_series_membership.js`:
- `name: "collection_series_membership"` (equals the basename), `budgetClass: "browse"` (750 ms), `ratePerSecond: 1` (one membership read per Collection open), `librarySizes: [25, 100, 2000]` (a size-0 account has no Collection rows to group), `writes: false`, `emptyExamples: [[], {}, [{ anime_id: 1 }]]` (qualify must reject each).
- `request(actor, fixture, seq, random, core)` → `{ method: "GET", path: "/rest/v1/series_entry_spans?select=<Task 3 select>&medium=eq.anime&anime_id=in.(<300 ids from fixture.media.anime, offset (seq*300) % size>)&series.continuity=eq.verified&series.grouping_state=eq.approved&series_sections.state=eq.approved" }`. The actor's bearer is sent (the read is account-initiated and leased in the app); F3.1b's GET option. When `fixture.media.seriesMemberIds` is non-empty, each request's 300 ids include at least one of them (the rest drawn as before).
- `requires(fixture, actor)` → `"no published series member ids"` while `fixture.media.seriesMemberIds` is empty or absent, else `null`. The fixture builder reads the published span ids read-only (never writes catalogue rows live). Production membership is empty today, so F3.1c's preflight **refuses** a `--qualify` run (exit 1, nothing sent) until reviewed membership exists; after the Task 8 pilot (≈ 30 spans) a qualifying run is possible, and its run id is recorded in `acceptance/W6.json`.
- `validate(data, actor, request, ctx)`: `ctx.mode === "wiring"` → `Array.isArray(data)` (empty allowed; never release evidence). `ctx.mode === "qualify"` → a non-empty array whose rows each carry `series.id`, `series_sections.kind` and an integer `anime_id` (brief item 5: no empty-array passes).
- Combined workload line: `"collection_series_membership": 1`.
- Qualification arithmetic (F3.1c preflight): 1 rps × 600 s = 600 expected completions ≥ 100; ÷ 3 covered subgroups = 200 ≥ 30.

- [ ] **Step 1: Write the failing offline test** `scripts/load/profiles/collection_series_membership.test.js`, `test("collection_series_membership is a browse-class profile at 1 rps", …)`. Assert that `W.loadProfiles()["collection_series_membership"]` exists, `budgetClass === "browse"` and `W.selectProfiles({ names: ["collection_series_membership"] }).limits["collection_series_membership"] === 750`, `ratePerSecond === 1` and there is no `weight` key, `W.loadWorkload("tracker-gaps-combined").profiles["collection_series_membership"] === 1`, the request's `method` is `"GET"` and it has no `body`, its path starts with `/rest/v1/series_entry_spans?`, it has ≤ 300 ids in `anime_id=in.(`, it contains the three approval filters, with `seriesMemberIds: [77]` the ids include 77, `requires({ media: { anime: [1] } }, {})` names the reason and `requires({ media: { anime: [1], seriesMemberIds: [77] } }, {})` is `null`, `validate([], {}, r, { mode: "wiring" })` is true, every `emptyExamples` entry is rejected with `{ mode: "qualify" }`, `validate([{ anime_id: 1, series: { id: "s" }, series_sections: { kind: "season" } }], {}, r, { mode: "qualify" })` is true, `validate({}, {}, r, { mode: "wiring" })` is false, and the base mix is unchanged by loading the profile (`JSON.stringify(W.WEIGHTS)` equal before and after, no `collection_series_membership` key).
- [ ] **Step 2: Run, expect FAIL.** `node --test scripts/load/profiles/collection_series_membership.test.js` → `# fail 1` (profile not found).
- [ ] **Step 3: Implement** the profile file and add its line to `tracker-gaps-combined.js`.
- [ ] **Step 4: Run, expect PASS** (`bash scripts/quality-gates/test_load_profiles.sh`, `# fail 0`, incl. `combined workload names every profile with an explicit rate`).
- [ ] **Step 5: Verify the scenario** is in the feature file (added at plan review, Q4) exactly as:
```gherkin
  @load:collection_series_membership
  Scenario: The membership read stays inside the Browse budget
    Given reviewed series membership is published and the qualification fixture names its member ids
    When the membership read runs in qualification mode at its declared 1 request per second on top of the unchanged base mix
    Then the read's p95 is at most 750 ms with zero errors
    And it has at least 100 completions and at least 30 per library size, otherwise the result is "insufficient"
```
- [ ] **Step 6: Commit.** `git add scripts/load/profiles/collection_series_membership.js scripts/load/profiles/collection_series_membership.test.js scripts/load/workloads/tracker-gaps-combined.js && git commit -m "W6: register collection_series_membership load profile (browse)"`

### Task 5: `CollectionStore` grouping state, per-account switch, member cards

**Files:**
- Create: `Kuro/Collection/CollectionStore+SeriesGrouping.swift`, `KuroTests/SeriesGroupingCollectionTests.swift`.
- Modify: `Kuro/Collection/CollectionStore.swift`, `Kuro/Composition/AppComposition.swift`, `Kuro/Services/FeatureFlags.swift`.

**Interfaces.** Consumes `LibraryStore.allEntries`, `CatalogStore.loadSeriesMembership` / `seriesMembershipMap` / `fetchAnimeByIdsPreservingOrder` / `fetchMangaByIdsPreservingOrder`, `SeriesListGrouping`, `SeriesListIndex`. Produces:
```swift
// FeatureFlags.swift
var collectionSeriesGroupingV1Enabled: Bool { evaluate("collection_series_grouping_v1") }
// CollectionStore.swift
init(client: SupabaseClient?, accountSession: AccountSessionCoordinator,
     userDefaults: UserDefaults = .standard, groupingEnabled: @escaping @MainActor () -> Bool = { false })
weak var catalog: CatalogStore?                       // wired like `library`
var groupSeasonsByAccount: Bool                       // observed copy for the current account (default true)
var seriesMemberMedia: [MediaKey: Media]              // account-scoped card cache for off-feed members
// CollectionStore+SeriesGrouping.swift
extension CollectionStore {
    nonisolated static func groupSeasonsKey(userId: String) -> String   // "kuro.collection.groupSeasons." + 16 hex of SHA-256(lowercased id)
    var isSeriesGroupingAvailable: Bool { get }       // flag on && !importedView
    var groupsSeasons: Bool { get }                   // isSeriesGroupingAvailable && groupSeasonsByAccount
    func setGroupsSeasons(_ on: Bool)                 // writes the current account's key; no-op signed out
    func seriesRows(medium: MediaKind) -> [SeriesListRow]   // memoized on (medium, groupsSeasons, catalog version, entries ==)
    func seriesIndex(medium: MediaKind) -> SeriesListIndex
    func hasSeriesGroups(medium: MediaKind) -> Bool
    func prepareSeriesGrouping(medium: MediaKind, loadedFeed: Set<MediaKey>) async   // membership read + card hydration of off-feed members
    func memberMedia(_ key: MediaKey) -> Media?       // feed first, then seriesMemberMedia
}
// CollectionStore: removeDeletedAccountData(userId:) removes groupSeasonsKey(userId:).
```
Pinned behaviour:
- `prepareSeriesGrouping` captures `accountSession.current` at the start. It checks the flag **first** and returns without any read when the flag is off, the view is imported, or there is no account. It calls `catalog.loadSeriesMembership(for:)` with every Library key of the medium, then fetches cards only for members of multi-member groups that are not in `loadedFeed`. Both calls run inside `try await accountSession.withCredentialLease(for: account) { … }` (Decision 11); a `CancellationError` from a refused or revoked lease ends the preparation silently. It publishes `seriesMemberMedia` only while the captured context `isCurrent`.
- `cancelAccountWork` cancels the hydration task.
- `clearPrivateState` empties `seriesMemberMedia` and the memo, and reloads `groupSeasonsByAccount` for the next account (default `true`).
- `libraryDidChange` with `change.kind == .added` starts `catalog.loadSeriesMembership(for: [key])` inside a lease of `change.account` when the flag is on; nothing when it is off. A full refresh is not assumed to emit per-entry `.added` changes; the view covers it (Task 6, `onChange(of: library.loadState)`).
- `AppComposition.makeCollection(client:accountSession:userDefaults:groupingEnabled:)` passes the graph's `userDefaults` and `{ shell.flags.collectionSeriesGroupingV1Enabled }`, and sets `collection.catalog = publicData.catalog` next to `collection.library`.

- [ ] **Step 1: Write the failing tests** in `@MainActor @Suite struct SeriesGroupingCollectionTests`. Use `FacadeHarness` built with a fresh `UserDefaults(suiteName:)` and flags `FeatureFlags(userDefaults:, launchArguments: ["--ff-on=collection_series_grouping_v1"])`. The harness gains optional `userDefaults` / `launchArguments` init parameters and a `signIn(_ userId:)` overload if it lacks them; read `KuroTests/LibraryFacadeTests.swift` first and keep the existing call sites unchanged. Reviewed rows are served by `h.server.respond` for `series_entry_spans` and cards for `anime`.
```swift
@Test func groupSeasonsSwitchIsRememberedPerAccount() async throws {
    let suite = "kuro.w6.\(UUID().uuidString)"; let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var h = try FacadeHarness(userDefaults: defaults, launchArguments: ["--ff-on=collection_series_grouping_v1"])
    h.backend.setRows(threeSeasons(ids: [401, 402, 403]), for: FacadeHarness.userA)
    h.server.respond(reviewedSpans(series: "D", ids: [401, 402, 403]))
    await h.signIn()
    await h.service.collection.prepareSeriesGrouping(medium: .anime, loadedFeed: [])
    #expect(h.service.collection.groupsSeasons == true)                 // default on
    #expect(h.service.collection.seriesRows(medium: .anime).count == 1)
    h.service.collection.setGroupsSeasons(false)
    #expect(h.service.collection.seriesRows(medium: .anime).map(\.members.count) == [1, 1, 1])
    await h.tearDown()
    h = try FacadeHarness(userDefaults: defaults, launchArguments: ["--ff-on=collection_series_grouping_v1"])   // relaunch
    h.backend.setRows(threeSeasons(ids: [401, 402, 403]), for: FacadeHarness.userA)
    h.server.respond(reviewedSpans(series: "D", ids: [401, 402, 403]))
    await h.signIn()
    #expect(h.service.collection.groupsSeasons == false)
    #expect(h.service.collection.seriesRows(medium: .anime).count == 3)
    await h.signIn(FacadeHarness.userB)                                  // other account on the phone
    #expect(h.service.collection.groupsSeasons == true)
    #expect(defaults.object(forKey: CollectionStore.groupSeasonsKey(userId: FacadeHarness.userA)) as? Bool == false)
    try await h.service.collection.removeDeletedAccountData(userId: FacadeHarness.userA)
    #expect(defaults.object(forKey: CollectionStore.groupSeasonsKey(userId: FacadeHarness.userA)) == nil)
    await h.tearDown()
}
```
  Pins (same suite). The first three need `FolioGrouping`, so they are written in Task 6 Step 1; the last three are written here:
  - `groupAppearsOnceInItsGroupStatusStrip`: S2 `.current` (minute 10), S1 `.completed` re-rated later (minute 20), so the new status rule is exercised. Through `FolioGrouping.items`, the Watching feed `[S2]` gives one group item and the Completed feed `[S1]` gives zero items. Row counts are `[.watching: 1]`.
  - `groupRowActionsTargetOneNamedSeason`: for a group item, `item.key == S2.key` (display member = anchor). `FolioGroupCopy.menuEdit(section: "S2", german: false) == "Edit S2"` and the DE form is `"S2 bearbeiten"`. In select mode, `FolioGrouping.selectableIds(for:)` contains the member stable keys only, never the group id `"series:anime:D"`.
  - `groupAdvanceUsesTheActiveMembersOwnTotal`: active member S2 (anchor) has a card with 12 episodes; S1 has 24 and S3 has 13. `FolioGrouping.advanceRequest(group:)` returns `(S2.key, cap: 12)`, never 24 or 13. With S2's card total `nil` (unknown): `advanceRequest` returns nil, the key is hidden, and no write is sent: `h.backend.writeCalls.isEmpty`. A group whose members are all Completed/Planning returns nil (no +1 on the row).
  - `memberHydrationFromPreviousAccountIsDropped`: user A's card read is held open (`h.server` deferred response); sign in as B; complete A's response → `seriesMemberMedia.isEmpty`.
  - `membershipReadNeverSendsPreviousAccountsIdsWithNewCredentials` (brief item 2): modelled on `KuroTests/CredentialLeaseTests.swift` `preDispatchSwitchSendsNothingAsB` (line 47, `SessionSDKHarness` + `signedInAsAKeepingBsSession`) and `AccountSessionTests` "A lease runs only while its context is current…" (`Packages/KuroModules/Tests/KuroCoreTests/AccountSessionTests.swift:232`) / "A transition cancels a running lease…" (line 262). Signed in as A with the flag on, start `prepareSeriesGrouping(medium: .anime, loadedFeed: [])`; switch the funnel to B before dispatch. Expect no `series_entry_spans` or `anime` request whose `bearerSubject == userB` carries A's ids, `seriesMemberMedia.isEmpty`, and `catalog.seriesMembershipCheckedAt` holds none of A's keys.
  - `flagOffSendsNoRequest` (brief item 1): without the launch argument (flag off), signed in with a three-season library: `prepareSeriesGrouping` sends 0 requests of any kind (`series_entry_spans`, `anime`, `manga`), a `LibraryChange` of kind `.added` sends 0 requests, `isSeriesGroupingAvailable == false`, and `seriesRows` gives one row per entry.
- [ ] **Step 2: Run, expect FAIL.** `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,id=7FC4B58A-430C-457D-A017-6B0095723F3F' test -only-testing:KuroTests/SeriesGroupingCollectionTests` → `cannot find 'prepareSeriesGrouping'` / `extra argument 'userDefaults'`.
- [ ] **Step 3: Implement** the flag, the injection, the extension and the composition wiring. The memo is an `@ObservationIgnored private var seriesRowsMemo: (medium: MediaKind, on: Bool, version: Int, entries: [LibraryEntry], rows: [SeriesListRow])?`. Reading it still registers observation through `library.allEntries`, `catalog.seriesMembershipVersion` and `groupSeasonsByAccount`.
- [ ] **Step 4: Run, expect PASS** for the switch test and the store pins (the Folio pins follow in Task 6). Run `scripts/quality-gates/check_architecture.sh` → 0 offenders: no SDK import in views; the new owner state lives in `CollectionStore`, which is already registered in `makeAccountScopedStates`.
- [ ] **Step 5: Commit.** `git add Kuro/Collection/CollectionStore+SeriesGrouping.swift Kuro/Collection/CollectionStore.swift Kuro/Composition/AppComposition.swift Kuro/Services/FeatureFlags.swift KuroTests/SeriesGroupingCollectionTests.swift KuroTests/LibraryFacadeTests.swift && git commit -m "W6: Collection grouping state, per-account Group seasons switch, member cards"`

### Task 6: Group row, inline fold and "Group seasons" control

**Files:**
- Create: `Kuro/Views/Lists/FolioGrouping.swift`.
- Modify: `Kuro/Views/Lists/FolioModels.swift`, `Kuro/Views/Lists/FolioItems.swift`, `Kuro/Views/Lists/FolioHeader.swift`, `Kuro/Views/EditorialCollectionView.swift`, `KuroTests/SeriesGroupingCollectionTests.swift`.

**Interfaces.** Consumes Task 5 and `KuroFoldMemory` (`\.kuroFoldMemory`, `KuroFoldButton`, `KuroFold.key`). Produces:
```swift
struct FolioMember: Identifiable { let item: FolioItem; let sectionLabel: String?; var id: String { item.id } }
struct FolioGroup { let row: SeriesListRow; let members: [FolioMember]; let label: String?; var id: String }  // id "series:<kind>:<seriesId>"
// FolioItem gains `var group: FolioGroup? = nil`; `id` = group?.id ?? media.stableKey
enum FolioGrouping {
    static func items(feed: [FolioItem], index: SeriesListIndex, member: (MediaKey) -> FolioItem?,
                      membership: [MediaKey: SeriesMembership], german: Bool) -> [FolioItem]
    static func rowCounts(_ rows: [SeriesListRow]) -> [FolioStatus: Int]
    static func advanceRequest(group: FolioGroup) -> (key: MediaKey, cap: Int)?
    static func selectableIds(for item: FolioItem) -> [String]
    static func selectedKeys(items: [FolioItem], selected: Set<String>) -> [MediaKey]   // looks inside group members
    static func matches(_ item: FolioItem, query: String) -> Bool        // any member's loaded title
    static func foldSection(_ group: FolioGroup) -> String               // "series:<kind>:<seriesId>", page "collection"
}
enum FolioShelfChunks {                                                 // manga grid: band after the expanded group's grid row
    enum Chunk: Equatable { case grid([String]); case band(String) }
    static func split(ids: [String], columns: Int, expanded: Set<String>) -> [Chunk]
}
enum FolioGroupCopy {   // EN/DE via the `german` flag (KuroLocale.isGerman at call sites)
    static func switchTitle(german: Bool) -> String        // "Group seasons" / "Staffeln bündeln"
    static func showSeasons(_ n: Int, german: Bool) -> String   // "Show 3 seasons" / "3 Staffeln zeigen"
    static func hideSeasons(german: Bool) -> String        // "Hide seasons" / "Staffeln ausblenden"
    static func menuEdit(section: String, german: Bool) -> String   // "Edit S2" / "S2 bearbeiten"
    static func memberAccessibility(_ member: FolioMember, german: Bool) -> String
}
```
UI rules:
- **Index group row** is the existing `FolioIndexRow` layout. The numeral slot shows the group label ("S2 · 5/12"). Under it, a `KuroFoldButton(isExpanded: folds.binding(page: "collection", section: FolioGrouping.foldSection(group)), expandLabel: showSeasons(n), collapseLabel: hideSeasons)` with the default 44 pt label. Its `onCollapse` scrolls the group row back into view (F2).
- **Expanded members** render inline, inset by 52 pt, one 56 pt row each: section label, title, `FolioStatus` word, position line, and `KuroAdvanceKey` only where `FolioPolicy.keyPhase` is non-nil. Each member opens its own detail through `routes.openMedia`.
- No new sheet, no new navigation layer. The fold animates with `KuroFold.transaction`.
- **Shelf:** anime scenes (one column) put the band directly under the cell; the manga grid uses `FolioShelfChunks`. The group cell's caption shows the label and the fold control.
- **Select mode:** groups render expanded, member rows carry the selection marks, and the group header carries none. `selectedItemKeys()` in `EditorialCollectionView` must also look inside `group.members` (via `FolioGrouping.selectedKeys(items:selected:) -> [MediaKey]`). Today it filters `loadedItems` by `$0.id`, so a selected season inside a group would be skipped silently.
- **Display card.** A group item takes its title and cover from the display member (= anchor) feed item, which is always loaded because the anchor is what placed the row. Expanded members use their feed item or `seriesMemberMedia`, with `KuroBusyMark` while a member card loads. The +1 key stays hidden while the +1 target's own total is unknown.
- **Controls:** `FolioControlsRow` gains `groupSeasons: Binding<Bool>?`. When it is non-nil (`collection.isSeriesGroupingAvailable && collection.hasSeriesGroups(medium:)`), the row shows a word button in the density-word style: selected underline, `.isSelected` trait, `accessibilityValue` "On"/"Ein" / "Off"/"Aus". It stays within the existing `ViewThatFits` fallbacks.
- `EditorialCollectionView`:
  - `loadedItems` → `FolioGrouping.items(...)` when `collection.groupsSeasons`.
  - `counts` → `FolioGrouping.rowCounts(collection.seriesRows(medium:))` when grouping is on.
  - `advance(_:)` for a group uses `advanceRequest(group:)`.
  - `.task` / `reload()` call `collection.prepareSeriesGrouping(medium:loadedFeed:)` after the feed read.
  - `.onChange(of: library.loadState)` re-runs `prepareSeriesGrouping` when the state becomes `.loaded`. Otherwise a page mounted before the bootstrap Library read would prepare with an empty key set and never again. Repeat calls cost 0 requests for keys already checked.
  - The imported view never groups.

- [ ] **Step 1: Write the failing tests** (same suite):
```swift
@Test func expandShowsEverySeasonWithOwnStatus() throws {
    let s1 = folioItem(501, .completed, 12, total: 12, minutes: 30)   // re-rated last; S2 still decides
    let s2 = folioItem(502, .current, 5, total: 12, minutes: 20)
    let s3 = folioItem(503, .planning, 0, total: 13, minutes: 10)
    let m = membership("E", [(s1, 1), (s2, 2), (s3, 3)])
    let rows = SeriesListGrouping.rows([s1.entry, s2.entry, s3.entry], membership: m)   // newest first
    let all = [s1, s2, s3]
    let items = FolioGrouping.items(feed: [s2], index: SeriesListIndex(rows: rows),
                                    member: { key in all.first { $0.key == key } }, membership: m, german: false)
    let group = try #require(items.first?.group)
    #expect(items.count == 1 && group.label == "S2 · 5/12")
    #expect(group.row.status == .current && group.row.anchor == s2.key)
    #expect(group.members.map(\.sectionLabel) == ["S1", "S2", "S3"])
    #expect(group.members.map(\.item.status) == [.completed, .watching, .planned])
    #expect(group.members.map { FolioPolicy.keyPhase(status: $0.item.entry.status, progress: $0.item.progress,
                                                     total: $0.item.total, needsChoice: false, isPending: false) }
            == [nil, .advance, nil])
    let folds = KuroFoldMemory()
    let open = folds.binding(page: "collection", section: FolioGrouping.foldSection(group))
    #expect(open.wrappedValue == false)
    open.wrappedValue = true
    #expect(folds.isExpanded(page: "collection", section: "series:anime:E"))
    #expect(FolioShelfChunks.split(ids: ["a", "series:anime:E", "c", "d", "e"], columns: 2, expanded: ["series:anime:E"])
            == [.grid(["a", "series:anime:E"]), .band("series:anime:E"), .grid(["c", "d", "e"])])
}
```
  Then add the Task 5 pins that need `FolioGrouping` (`groupAppearsOnceInItsGroupStatusStrip`, `groupRowActionsTargetOneNamedSeason`, `groupAdvanceUsesTheActiveMembersOwnTotal`), plus:
  - `selectedSeasonOfGroupIsWrittenByBatch`: S1 is selected inside an expanded group → `FolioGrouping.selectedKeys(items:selected: [S1.item.id]) == [S1.key]`. Through `collection.applyBatchStatusChange(.completed, to: keys, …)` on the harness → exactly one write, to S1's key.
  - `prepareRunsAgainWhenLibraryLoads`: `prepareSeriesGrouping` before the Library has loaded sends 0 requests. After `library.refresh()` completes, a second call sends exactly 1 `series_entry_spans` request.
  - `groupRowRendersAtLargestTypeSize`: `ImageRenderer` on the expanded Index group row in German at `.accessibility3` with a 320 pt width. Assert a non-nil image and that the row's ideal height is greater than 0. Write the image only when `TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1` to `docs/tracker-gaps-2026-11/w6-grouping/`.
- [ ] **Step 2: Run, expect FAIL.** `xcodebuild … -only-testing:KuroTests/SeriesGroupingCollectionTests` → `cannot find 'FolioGrouping'`.
- [ ] **Step 3: Implement** `FolioGrouping.swift` and the view changes above. All strings go through the `FolioGroupCopy` EN/DE pairs. Colours are monochrome tokens only. No `ProgressView(` (use `KuroBusyMark` while member cards load).
- [ ] **Step 4: Run, expect PASS.** Run the suite, then `scripts/quality-gates/check_navigation.sh`, `check_branded_states.sh` and `check_architecture.sh` → 0 offenders each.
- [ ] **Step 5: Manual check on the owned simulator.** Boot `7FC4B58A-430C-457D-A017-6B0095723F3F`. Launch with `--ff-on=collection_series_grouping_v1` and a DEBUG fixture membership; if `FixtureHost` lacks spans, serve them from the fixture JSON. Confirm: one row "S2 · 5/12"; the fold opens and closes and is remembered for the run; +1 → "Ep. 6 marked." with Undo; the switch off shows three rows; relaunch keeps it off. Save screenshots to `docs/tracker-gaps-2026-11/w6-grouping/`.
- [ ] **Step 6: Commit.** `git add Kuro/Views/Lists/FolioGrouping.swift Kuro/Views/Lists/FolioModels.swift Kuro/Views/Lists/FolioItems.swift Kuro/Views/Lists/FolioHeader.swift Kuro/Views/EditorialCollectionView.swift KuroTests/SeriesGroupingCollectionTests.swift && git commit -m "W6: grouped Collection row with inline season fold and Group seasons switch"`

### Task 7: Membership population path (OWNER DECISION D-G; prepare only, nothing live)

**Do not start Steps 3–6 until the owner has chosen (a) or (b) in writing, or has approved the Task 8 pilot (option (a) at pilot scale, which needs Steps 3–4's tool).** Steps 1–2 may run now.

**Files:** Create `docs/tracker-gaps-2026-11/w6-grouping/MEMBERSHIP_POPULATION.md`, `scripts/series_continuity_proposals.js`, `scripts/series_continuity_proposals.test.js`.

**Interfaces.**
- Consumes the existing schema only: `mapping_revisions(state 'proposed', source, rule_revision, reviewer)`, `mapping_revision_spans(...)`, and service-role `publish_mapping_revision(uuid)`.
- Produces `node scripts/series_continuity_proposals.js --input <relations.json> --sheet <out.csv> --sql <out.sql> [--approved <sheet.csv>]`, offline. It reads a local JSON export and never connects to a database.
- Output: a review sheet (series title, medium, member ids, proposed section kind/ordinal/name, evidence link type) and an SQL file that only inserts **`proposed`** `series` + `mapping_revisions` + `mapping_revision_spans` rows.
- With `--approved`, it emits for each approved row `update mapping_revisions set reviewer = '<owner name>' where id = …;` followed by `select public.publish_mapping_revision('<id>');`, one series per statement. Rows without an `approved_by` value are never published.

- [ ] **Step 1: Write the decision note** `MEMBERSHIP_POPULATION.md`. It covers:
  - Evidence that reviewed membership is empty (Investigation findings).
  - Option (a): an owner-reviewed list. Candidates are proposed from AniList `SEQUEL`/`PREQUEL` chains of the same medium. The owner marks rows approved in the sheet; ordinals come from the owner's sheet column, never from position or calendar season.
  - Option (b): an explicitly approved rule, written out word for word. Its outputs still land as `proposed` and are published one series at a time with `reviewer = 'rule:<id> approved by <owner>'`.
  - Republish risk: INDEPENDENT_REVIEW line 159, section-scoped data is nulled, so each series is published once.
  - Rollback: a new revision that drops a span, then publish.
  - A recommendation: (a) for the first 50 most-tracked multi-season series.
- [ ] **Step 2: Commit.** `git add docs/tracker-gaps-2026-11/w6-grouping/MEMBERSHIP_POPULATION.md && git commit -m "W6: membership population options for owner decision D-G"`
- [ ] **Step 3 (after D-G, or after the owner approves the Task 8 pilot, which needs this tool): Write the failing test** `scripts/series_continuity_proposals.test.js`:
  - `node:test` "never publishes unapproved rows": an input of 3 chains and an approved sheet marking 1 → the SQL contains exactly one `publish_mapping_revision(`.
  - "ordinal only from the sheet": a chain with calendar seasons and no sheet ordinal → `section_ordinal` is `null`.
  - "one medium per series": a mixed anime/manga chain is split into two proposals.
  - "relations alone publish nothing": no `--approved` → 0 `publish_mapping_revision(`; every insert has `state 'proposed'`.

  Run `node --test scripts/series_continuity_proposals.test.js` → expect failure (module not found).
- [ ] **Step 4: Implement** the script. Run → `# fail 0`.
- [ ] **Step 5: Owner-gated live step (not part of this plan's execution).** The owner reviews the sheet and approves the SQL file by name and SHA-256. The operator runs it with the service role in one transaction. Verify read-only afterwards that `select count(*) from series where continuity='verified'` matches the approved count. Then the lead sets `collection_series_grouping_v1` per Q1.
- [ ] **Step 6: Commit.** `git add scripts/series_continuity_proposals.js scripts/series_continuity_proposals.test.js && git commit -m "W6: offline continuity proposal tool (proposed only; publish requires owner approval)"`

### Task 8: Reviewed-membership pilot (≈ 10 series; TestFlight evaluation behind the flag; OWNER-GATED)

**Why:** with production membership empty, W6 cannot be judged on a real phone. A small owner-reviewed set lets the owner and testers see grouping in TestFlight before D-G decides the broad population. **Nothing is published, and no flag or override row is written, without the owner's written approval of the exact file (name + SHA-256).** The pilot is option (a) of D-G at pilot scale; approving it decides those series only.

**Files:** Create `docs/tracker-gaps-2026-11/w6-grouping/PILOT.md`, `docs/tracker-gaps-2026-11/w6-grouping/pilot-sheet.csv`, `docs/tracker-gaps-2026-11/w6-grouping/pilot-publish.sql`, `docs/tracker-gaps-2026-11/w6-grouping/pilot-flag.sql`, `docs/tracker-gaps-2026-11/w6-grouping/pilot-verify.sql`.

**Interfaces.**
- Consumes Task 7's `scripts/series_continuity_proposals.js` (`--input`, `--sheet`, `--sql`, `--approved`), the existing service-role `publish_mapping_revision(uuid)`, `feature_flags` and the live per-account `feature_flag_overrides` (FK to `feature_flags.flag_name`, service-role writes only).
- Produces: a pilot sheet of ≈ 10 well-known multi-season series (owner picks; candidates are proposed from same-medium AniList SEQUEL/PREQUEL chains in the local catalogue export, never typed in from memory, so no AniList id is invented); `pilot-publish.sql` (one series per `publish_mapping_revision` statement, only rows with `approved_by`); `pilot-flag.sql` (`insert into feature_flags (flag_name, enabled, rollout_percentage, target_markets, description) values ('collection_series_grouping_v1', false, 0, '{}', 'W6: one row per series') on conflict (flag_name) do nothing;` plus one `feature_flag_overrides (user_id, flag_name, enabled=true)` row per owner-named TestFlight account); `pilot-verify.sql` (read-only).
- Rollout stays 0 %: the feature is visible only to the override accounts, so the capacity gate (Q1, D-H) is not crossed by a public rollout. Overrides work for any flag name: `FeatureFlags` loads every `feature_flag_overrides` row of the signed-in account into `accountOverrides` (`Kuro/Services/FeatureFlags.swift:123-140`), and `evaluate` returns an override before the global row's `enabled`/rollout (line 281). Only the offline 24 h cache is limited to the two `series_*` flags, so after a cold offline launch a tester sees grouping off until the next flag refresh.

- [ ] **Step 1: Candidate sheet (offline, may run once Task 7 Steps 3–4 exist).** `node scripts/series_continuity_proposals.js --input <local relations export> --sheet docs/tracker-gaps-2026-11/w6-grouping/pilot-sheet.csv --sql <scratch>/pilot-proposed.sql`, filtered to 20–30 candidates. Columns: title, medium, member AniList ids, proposed section kind / ordinal / name, evidence, `approved_by` (empty). Ordinals stay empty until the owner fills them (never from position or calendar season). Mix in at least one film and one extra section, and one manga series, so the "Film"/"Extra" labels and the manga Shelf are seen.
- [ ] **Step 2: Home impact check (before any publish; blocks Step 4).** Publishing is **not** gated by `collection_series_grouping_v1` for Home and detail readers (Investigation findings, "Other live readers"). For every pilot candidate, record in `PILOT.md`:
  - what `home_bundle_v1`, `series_detail_bundle_v1`, `home_events_page_v1` and `home_pending_page_v1` return differently once the series is published (read each function body in `20261007040000` / `20261101000000`, and grep `supabase/migrations` + `prepared-migrations` again for any newer reader of `series_entry_spans`; labels "S\(n)" from `section_ordinal`; `series_id` set);
  - whether two tracked seasons of one published series can appear together in one Home shelf with the same `HomeItem.id` (`seriesId`, `Kuro/Home/HomeContracts.swift:18`). Write a KuroTests check that decodes a `home_bundle_v1` fixture payload with two members of one series and asserts distinct identities, or show from the function body that the bundle returns one row per series. If two items can share an id, **stop**: report to the lead; the pilot waits for a separate, approved Home fix.
  - The owner approval in Step 3 must name this all-users effect: every user who tracks a pilot title sees its Home/detail labels change, flag or not.
- [ ] **Step 3: Owner approval.** The owner fills `approved_by` and ordinals for ≈ 10 rows and names the TestFlight accounts. Run `node scripts/series_continuity_proposals.js … --approved docs/tracker-gaps-2026-11/w6-grouping/pilot-sheet.csv --sql docs/tracker-gaps-2026-11/w6-grouping/pilot-publish.sql`; check `grep -c "publish_mapping_revision(" pilot-publish.sql` equals the approved row count. Write `pilot-flag.sql`. Record both files' SHA-256 in `PILOT.md`. The owner approves both by name + SHA-256 in writing. Without that, stop here.
- [ ] **Step 4: Apply (operator, service role, one transaction per file).** Before: run `pilot-verify.sql` and save its output (`select count(*) from series where continuity='verified'`; the spans of the pilot ids; `has_table_privilege` unchanged). Apply `pilot-publish.sql`, then `pilot-flag.sql`. After: `pilot-verify.sql` again; expected verified count = before + approved rows, exactly the approved ids have spans, no other series changed, and `select flag_name, enabled, rollout_percentage from feature_flags where flag_name='collection_series_grouping_v1'` = `(…, false, 0)` with one override row per named account. Each series is published once (republish nulls section-scoped data, INDEPENDENT_REVIEW line 159).
- [ ] **Step 5: TestFlight evaluation.** On a TestFlight build containing Tasks 1–6, signed in as an override account: Collection shows one row per pilot series with the correct "S\(n) · p/t" label; +1 advances the active season; the fold lists every season; "Group seasons" off restores rows; a non-override account sees no change in Collection (Home/detail labels change for everyone, as approved). Screenshots in `docs/tracker-gaps-2026-11/w6-grouping/pilot/`. The owner records keep/adjust/stop in `PILOT.md`. This evaluation is a learning step, not a release criterion.
- [ ] **Step 6: Rollback (prepared, not run).** `PILOT.md` lists: flag off for testers = delete the override rows (`delete from feature_flag_overrides where flag_name='collection_series_grouping_v1'`); membership rollback = a new revision that drops the series' spans, published once (Task 7 rollback). Both need owner approval.
- [ ] **Step 7: Commit** (docs only; the SQL files are evidence, not migrations). `git add docs/tracker-gaps-2026-11/w6-grouping/PILOT.md docs/tracker-gaps-2026-11/w6-grouping/pilot-sheet.csv docs/tracker-gaps-2026-11/w6-grouping/pilot-publish.sql docs/tracker-gaps-2026-11/w6-grouping/pilot-flag.sql docs/tracker-gaps-2026-11/w6-grouping/pilot-verify.sql && git commit -m "W6: reviewed-membership pilot sheet, approval record and verification"`

### Task 9: Docs, memory, verification, evidence

**Files:**
- Modify: `CURRENT_APP_STATE.md`, `CURRENT_APP_STATE_PLAIN.md`, `IMPLEMENTATION_PLAN_Variation1.md`, `docs/modules/README.md` (Collection + Catalog lines), `~/.claude/projects/-Users-max-Kuro-Anime-App/memory/MEMORY.md`.
- Create: `docs/tracker-gaps-2026-11/w6-grouping/EVIDENCE.md`, `docs/tracker-gaps-2026-11/acceptance/W6.json`.

- [ ] **Step 1: Rule 1 docs.**
  - Technical state: new files and counts (+3 app Swift files, +2 KuroTests, +1 package source, +1 package test); the flag `collection_series_grouping_v1` (0 %; no DB row until the Task 8 pilot, then a disabled 0 % row plus tester overrides); the group status rule (active member decides; Planning when all Planning; else most recent); the membership definition (verified + approved + approved section + same medium); and "reviewed membership empty live (or: N pilot series published on <date>); W6 visually inert outside the pilot until D-G". Append to the Change Log.
  - Plain-English state: the same in plain words.
  - Implementation plan: W6 status.
- [ ] **Step 2: Rule 2 memory.** Add new files, the per-account key `kuro.collection.groupSeasons.<16hex>`, and these gotchas:
  - `series.grouping_state` defaults to `'approved'`, so filter on `continuity='verified'` too;
  - `collection_series_page_v1` is unused by views;
  - members can live on unloaded feed pages, so rows are built from the Library;
  - FacadeHarness `userDefaults` / `launchArguments` parameters;
  - publishing a series changes Home/detail labels for every user, regardless of `collection_series_grouping_v1` (Task 8 Step 2);
  - membership/card reads run in a credential lease taken by `CollectionStore`; a cancelled read records no negative cache.
- [ ] **Step 3: Full verification** (record each output in `EVIDENCE.md`):
  - `cd Packages/KuroModules && swift test` → all pass; `swift test -c release --filter SeriesListGroupingTests/groupingTwoThousandEntriesWithinBudget` → pass.
  - `SKIP_IOS_BUILD=1 SKIP_IOS_TEST=1 scripts/quality-gates/run_all.sh` → green (WARN-only gates allowed).
  - `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,id=7FC4B58A-430C-457D-A017-6B0095723F3F' test -only-testing:KuroTests` → `** TEST SUCCEEDED **`.
  - `scripts/quality-gates/check_architecture.sh`, `check_navigation.sh`, `check_branded_states.sh` → 0 offenders; `scripts/quality-gates/check_bdd_traceability.sh` → every W6 scenario (7 + 2 added at plan review + 2 added by the 2026-11-09 corrections = 11) resolved.
  - `scripts/db/run_local_db_tests.sh` → `111_series_membership_read` PASS, no new failures.
  - `bash scripts/quality-gates/test_load_profiles.sh` → `# fail 0`.
  - `python3 scripts/quality-gates/check_docs_current_state.py` → `PASS` (Step 1 updated the inventory sentences from the script's expected text, recomputed at merge time).
  - Append `W6-grouping.feature` to `scripts/quality-gates/bdd_landed.txt` (F1 landed scope).
  - Build warnings: `xcodebuild -scheme Kuro -destination 'generic/platform=iOS' build 2>&1 | grep -c "warning:"`, unique Kuro-side count ≤ 60.
  - No Deno functions touched.
- [ ] **Step 4: Evidence note and acceptance record.**
  - `EVIDENCE.md`: the scenario → test → result table, the baseline link, the non-vacuity check outputs (Tasks 2–3), the screenshots, the pilot status (Task 8), and the open questions Q1–Q4 with their status (Q2 resolved).
  - `docs/tracker-gaps-2026-11/acceptance/W6.json` (brief item 6, F1 format): tested commit SHA (`git rev-parse HEAD`), one entry per scenario with result `pass` / `fail` / `blocked` / `insufficient`, the test command, the context (`local DB` for `@sql`, which counts only if `111_series_membership_read` ran and passed, not file existence; `load run id` for `@load`; simulator for `@swift`), and unresolved gates. The `@load:collection_series_membership` scenario stays `blocked` (no owner-approved run, or the preflight refused it because no membership is published) or `insufficient` (< 100 completions or < 30 in a subgroup) until a `--qualify` run id passes.
  - `scripts/quality-gates/check_bdd_traceability.sh --accepted W6` → expected to fail while the `@load` scenario is not `pass`; record the output. W6 is "resolved", not "accepted", until it passes. Write it in F1.3's schema: start from `python3 scripts/quality-gates/check_bdd_traceability.py --record-template W6`; workstream `W6` (the feature basename up to its first `-`, spec §4); `runs[]` with the exact command, `context` (`simulator` + UUID for `@swift`/`@ui`, `local-db` for `@sql`, `load-qualification` with report, `runKey` and cleanup report for `@load`) and a log under `docs/tracker-gaps-2026-11/acceptance/logs/W6-<run id>.txt`; one `scenarios[]` entry per non-gated scenario with its current tag. Commit order (F1.3 rule 2): make the docs/evidence commit first, run the gates on that clean commit, then commit only `docs/tracker-gaps-2026-11/acceptance/W6.json` and `acceptance/logs/` (message `W6: acceptance record`); nothing outside that folder may change after the tested commit.
- [ ] **Step 5: Commit.** `git add CURRENT_APP_STATE.md CURRENT_APP_STATE_PLAIN.md IMPLEMENTATION_PLAN_Variation1.md docs/modules/README.md docs/tracker-gaps-2026-11/w6-grouping/EVIDENCE.md scripts/quality-gates/bdd_landed.txt && git commit -m "W6: docs, verification and evidence"`. MEMORY.md lives outside the repository and is not committed.
