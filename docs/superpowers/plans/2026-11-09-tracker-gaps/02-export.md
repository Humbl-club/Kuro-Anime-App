# W2 Export your list Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** People can export their whole Kuro library from Profile, for free, as MyAnimeList XML (one file per medium, split into numbered parts when it would exceed what `MALExportParser` accepts, every part re-importable), RFC 4180 CSV (formula cells neutralised) and full-fidelity JSON (exact text, custom lists as separate objects), and share the files with the system share sheet.

**Corrections applied (2026-11-09, owner-approved corrections brief):** JSON lists as objects in manual order (incl. empty lists and items no longer in the library) through an ordered list-objects provider W9 supplies; tracking-unit identity (`unit_id`, `progress_label`); summary distinguishes complete / `identityUnavailable` / `organisationUnavailable`; MAL XML whole-file split at `MALExportParser.maxBytes` / `maxItems`; CSV formula neutralisation by default (O3 resolved), JSON exact; credential lease on the id lookup; service-level `library_export_v1` check before any request (`flagOffSendsNoRequest`); acceptance record (brief item 6); no manufactured red (item 7).

**Architecture:** Pure, Foundation-only exporters live in package `KuroLibrary` (`LibraryExport*.swift`) and take one Sendable value, `LibraryExportInput`. The app owner `LibraryExportService` (`Kuro/Library/`, `AccountScopedState`) first checks `library_export_v1` (off → no request, no file), reads `LibraryStore`, asks `CatalogStore` for one stateless batched catalogue identity read (≤ 500 ids per request, public table) inside a credential lease of the exporting account (the id set is that account's library and the shared SDK client attaches the bearer at dispatch, so the read is account-bound even though the table is public), and keeps the answers in its own account-scoped cache for offline exports (cleared on every account change and deletion). It asks two organisation providers (tags; ordered custom-list objects, supplied by W9), runs the exporters off the main actor and writes protected temporary files that the Profile tool sheet `LibraryExportSheet` shares through `ShareLink`.

**Tech Stack:** Swift 6.2 toolchain (package in Swift 5 mode, app Swift 5 + MainActor default), SwiftUI `ShareLink`, `XMLParser` (round-trip anchor), Swift Testing, supabase-swift PostgREST (`StubPostgREST` in tests), Node load harness.

**Spec:** docs/superpowers/specs/2026-11-09-tracker-gaps-design.md + features/W2-export.feature

## Global Constraints
- "every new or changed backend read/write is assigned to one existing budget class, added to `scripts/load/backend_workload.js` (F3), and covered by an SQL-plan check. A workstream that adds backend traffic is not released to users while the qualification is NOT QUALIFIED" → the Profile row is behind flag `library_export_v1` (default off; program plan release gate).
- "p95 end-to-end thresholds: **Browse/Search/Clubs/Progress ≤ 750 ms**" → the identity lookup is in the Browse class.
- "On-device budgets in this spec are **proposed, confirm after baseline**" → the 2,000-title ≤ 2 s export budget is measured first on simulator `7FC4B58A-430C-457D-A017-6B0095723F3F`, then gated.
- "one `@MainActor @Observable final class` owner per capability in `Kuro/<Capability>/`, built once in `AppComposition`; views read owners with `@Environment(Type.self)` and import no Supabase SDK module; account-scoped owners conform to `AccountScopedState`, capture `AccountContext` at the start of every async operation and check `isCurrent` before every private write, and are registered in `makeAccountScopedStates`; tracking reads/writes only through `LibraryStore` / `LibraryActions`; no second Supabase client; no Combine; `print` only inside `#if DEBUG`; no force unwraps."
- "New sheets register `.kuroNavigationLayer`; tool sheets use `.kuroLeavesJourney()`; unsaved input uses `.kuroDiscardGuard`." (The export sheet holds no unsaved input; no discard guard.)
- "every user-facing string through `KuroLocale` (EN + DE); monochrome only, no coloured status; branded states only (`check_branded_states.sh`); light only until W8 ships."
- "Kuro will not charge for tracking, ordinary discovery, search/filter/sort, history, import/export or useful reminders." "No upgrade modal, artificial daily tracking limit, reward-ad requirement, paid export or pay-to-sort mechanism."
- "Preserve imported IDs through grouping and export." "Do not interpret missing source history as newly deleted data."
- "Process: Rule 1 (three state docs) and Rule 2 (memory) after every workstream; quality gates `scripts/quality-gates/run_all.sh` green; build warning count does not rise above the 2026-10-31 baseline (60 unique Kuro-side warnings)."
- Binding cross-plan names (planner brief): F2 `PartialDate` (`init?(raw:)`, `raw`, `precision: .year/.month/.day`), `LibraryEntry.repeatCount: Int`, `.startedOn: PartialDate?`, `.finishedOn: PartialDate?`; W2 input `LibraryExportInput { entries; catalogue: [MediaKey: ExportCatalogueRow]; tagsByKey = [:]; customLists: [ExportCustomList] = [] }` in `KuroLibrary` (corrections brief: `customListsByKey` is replaced by ordered list objects; the service provider is `customLists: @MainActor () async -> [ExportCustomList]?`, which W9 supplies as `CustomListsStore.exportLists()`).
- Corrections brief, binding: "Every user-visible workstream has a server feature flag (`feature_flags`, read via the injected `FeatureFlags`), default 0 %, checked BEFORE any request is sent" → `library_export_v1` is checked by `LibraryExportService.export(_:)` itself, not only by the Profile row; pinned by `LibraryExportFlowTests/flagOffSendsNoRequest`.
- Corrections brief, binding: "Every new private (account-scoped) SDK request runs inside `accountSession.withCredentialLease(for: account) { … }`" → the identity lookup (its id set is the account's library); pinned by `LibraryExportFlowTests/identityLookupNeverSendsOldLibraryWithNewCredentials`.
- Corrections brief, binding: "'Accepted' requires an execution record `docs/tracker-gaps-2026-11/acceptance/<workstream>.json`" and "No manufactured red" → Task 8 Step 3b; every red below is a missing type/member/behaviour.

## Review Focus
1. **Notes that break XML** (an `&`, `<`, `]]>`, `<!DOCTYPE` text, CRLF, C0 control characters, > 16,384 UTF-8 bytes). The parser rejects the whole file for an illegal character or a > 16,384-byte element, and its raw `<!DOCTYPE`/`<!ENTITY` byte scan would reject a CDATA section containing that text. Rule: entity-escape (never CDATA), `\r` → `&#13;`, drop C0 controls except TAB/LF/CR and U+FFFE/U+FFFF, omit `my_comments` above 16,384 bytes; every adjusted entry is listed in the summary. Pinned by `LibraryExportTests/malXmlNotesSurviveEscapingAndAreReportedWhenAdjusted` (Task 2).
2. **Partial and malformed dates.** Stored `started_raw`/`finished_raw` come from AniList (`YYYY-MM-DD`), MAL XML (`YYYY-MM-00`, `YYYY-00-00`) and the MAL account API (`YYYY`, `YYYY-MM`); some may not parse. MAL XML must zero-pad (`2024-03-00`), omit an unparseable date (parser then marks it unavailable, never "clear"), and JSON keeps the raw string verbatim. Pinned by `LibraryExportTests/malDatesZeroPadEveryPrecisionAndOmitUnparseable` (Task 2).
3. **`.repeating` and statuses MAL does not have.** `status(fromDB:)` never returns `.repeating` (the DB stores WATCHING/READING), so the round trip compares statuses after the DB mapping. `.repeating` exports as `Watching`/`Reading` + rewatch flag 1, never the word "Repeating". Pinned inside the round-trip test (Task 2) and by `LibraryExportTests/statusTableCoversEveryListStatusAndMedium`.
4. **Exporting a half-loaded library.** `restoreCachedProgressBaselines` fills entries before the first refresh publishes; an export then would silently miss titles. Export is refused unless `library.loadState == .loaded`; `sourceMetadata == nil` (fence columns not selected) exports `null`/omits fields, never `0` or "no dates". Pinned by `LibraryExportFlowTests/exportRefusesUntilLibraryLoaded` and `LibraryExportTests/missingSourceMetadataExportsNullNotZero`.
5. **Account switch / deletion while files exist.** Files hold private notes. They live in a per-export protected folder; an account change mid-export never publishes, and dismiss, `clearPrivateState()` and `removeDeletedAccountData` delete the folder. Pinned by `LibraryExportFlowTests/accountSwitchMidExportPublishesNothingAndDeletesFiles` (Task 5).
6. **Account A's id set sent with account B's bearer.** supabase-swift reads the token at dispatch, so an `isCurrent` check before publishing is not enough. The lookup runs inside `withCredentialLease(for:)`; `exportIdentities` stops between batches when cancelled; the cache is written only after the lease returns and the context is still current. Pinned by `LibraryExportFlowTests/identityLookupNeverSendsOldLibraryWithNewCredentials` (Task 5).
7. **Spreadsheet formula injection.** A note or title starting with `=`, `+`, `-`, `@`, TAB or CR runs as a formula when the CSV is opened in a spreadsheet. CSV prefixes such cells with `'` (OWASP CSV injection guidance), before RFC 4180 quoting; JSON keeps the exact text. Pinned by `LibraryExportTests/csvNeutralisesFormulaCellsAndJsonKeepsExactText` (Task 3).
8. **A MAL file the importer refuses as a whole.** `MALExportParser` rejects a file above `maxBytes` (32 MiB) or `maxItems` (20,000). The writer measures the whole escaped document and splits a medium into numbered parts, each a complete document within both limits. Pinned by `LibraryExportTests/malXmlSplitsLargeLibrariesIntoReimportableParts` (worst case: 2,000 entries with 16,384-byte notes of `&<>"`) and `malXmlSplitsAtTheParserItemLimit` (Task 2).
9. **Lists silently missing or reordered.** Lists export as separate objects in their manual order, empty lists included, items kept when the title left the library (`in_library: false`). A provider that could not load returns `nil` → `lists: null` and `organisationUnavailable`, never `[]`. Pinned by `LibraryExportTests/jsonExportsListsInManualOrderWithItemsOutsideTheLibrary` and `summaryDistinguishesCompleteIdentityAndOrganisationGaps` (Task 3).

## Success parameters
| Spec §5.2 W2 | Measured by | Expected |
|---|---|---|
| Round trip: Kuro → MAL XML → `MALExportParser` returns identical status, progress, score, notes, repeat count and dates for every entry with a MAL id | `cd Packages/KuroModules && swift test --filter LibraryExportTests` | `malXmlRoundTripPreservesEveryMappedEntry` passes; 0 failures |
| Titles without a MAL id are listed in a report and kept in CSV/JSON | same command | `entriesWithoutMalIdAreReportedNotDropped` passes |
| Export works offline for library fields | `xcodebuild … -only-testing:KuroTests/LibraryExportFlowTests` | `exportWorksOfflineWithCachedCatalogueOrReportsMissingIds` passes |
| Catalogue id lookup batched ≤ 500 ids per request, Browse class ≤ 750 ms | `node --test scripts/load/profiles/export-mal-id-lookup.test.js` (offline) + `scripts/db/run_local_db_tests.sh --only 110_export` + later owner-approved load run | profile `export-mal-id-lookup` registered, class `browse`, 0.2 rps, ≤ 500 ids; EXPLAIN shows `Index Scan`/`Bitmap Index Scan` on `anime_pkey`/`manga_pkey`; load run p95 ≤ 750 ms |
| MAL files are always re-importable (whole-file limits) | `swift test --filter LibraryExportTests` | `malXmlSplitsLargeLibrariesIntoReimportableParts`, `malXmlSplitsAtTheParserItemLimit` pass: every part ≤ `MALExportParser.maxBytes` and ≤ `maxItems`, every part parses, all entries come back |
| CSV safe in spreadsheets, JSON exact | same command | `csvNeutralisesFormulaCellsAndJsonKeepsExactText` passes |
| Lists, unit identity and completeness are exported | same command | `jsonExportsListsInManualOrderWithItemsOutsideTheLibrary`, `jsonCarriesIdsTagsListsAndDates`, `summaryDistinguishesCompleteIdentityAndOrganisationGaps` pass |
| Release switch and credential binding | `xcodebuild … -only-testing:KuroTests/LibraryExportFlowTests` | `flagOffSendsNoRequest` (0 requests, 0 files with the flag off) and `identityLookupNeverSendsOldLibraryWithNewCredentials` pass |
| Proposed: 2,000-title export written in ≤ 2 s (confirm after baseline) | `LibraryExportFlowTests/twoThousandTitleExportBaseline` on the owned simulator, three runs, median recorded in `docs/tracker-gaps-2026-11/W2-export/baseline.md` | baseline recorded; gate set to max(2 s, 1.5 × baseline median) only after the owner confirms |

## File Structure
| File | Responsibility |
|---|---|
| `Packages/KuroModules/Sources/KuroLibrary/LibraryExportInput.swift` (new) | `LibraryExportInput`, `ExportCatalogueRow`, `ExportCustomList`, `LibraryExportFormat`, `LibraryExportFile`, `LibraryExportSummary`, `LibraryExportGap`, `ExportReportLine` |
| `Packages/KuroModules/Sources/KuroLibrary/RFC4180.swift` (new) | RFC 4180 field/row encoder (also used by W4's unresolved file) |
| `Packages/KuroModules/Sources/KuroLibrary/LibraryExportMAL.swift` (new) | MAL status table, MAL date form, XML text escaping, per-medium XML writer with whole-file split into parts |
| `Packages/KuroModules/Sources/KuroLibrary/LibraryExportTabular.swift` (new) | CSV writer (documented header, formula neutralisation) and JSON writer (entries + list objects) |
| `Packages/KuroModules/Sources/KuroLibrary/LibraryExport.swift` (new) | `LibraryExport.build(_:formats:exportedAt:timeZone:)` → files + summary; file names |
| `Packages/KuroModules/Tests/KuroLibraryTests/LibraryExportTests.swift` (new) | package tests incl. the round-trip anchor and an RFC 4180 test reader |
| `Kuro/Catalog/CatalogStore+ExportIdentities.swift` (new) | stateless batched public identity read (`id, anilist_id, mal_id, titles`), ≤ 500 ids per request |
| `Kuro/Library/LibraryExportService.swift` (new) | account-scoped owner: flag check before any request, gate on load state, leased identity lookup + per-account identity cache (offline), organisation providers, build off-main, protected temp files, cleanup |
| `Kuro/Composition/AppComposition.swift` (modify) | build the owner once; add to `AppGraph`, to `makeAccountScopedStates` after `support` |
| `Kuro/KuroApp.swift` (modify) | `@State` + `.environment(libraryExport)` |
| `Kuro/Services/FeatureFlags.swift` (modify) | `var libraryExportV1Enabled: Bool { evaluate("library_export_v1") }` |
| `Kuro/Views/Profile/LibraryExportSheet.swift` (new) | the tool sheet: format choice, prepare, `ShareLink`, summary, offline line |
| `Kuro/Views/Profile/LibraryExportCopy.swift` (new) | EN/DE copy (pure, testable) |
| `Kuro/Views/ProfileView.swift` (modify) | "Export your list" row in Account and privacy; `.sheet` + `.kuroNavigationLayer("profile.export", …)` |
| `KuroTests/LibraryExportFlowTests.swift` (new) | owner/flow tests over `testingGraph` + `FakeLibraryBackend` + `StubPostgREST` |
| `KuroTests/IdentityCompositionTests.swift` (modify) | expected account-scoped list gains `g.libraryExport` after `g.support` |
| `scripts/load/profiles/export-mal-id-lookup.js`, `scripts/load/profiles/export-mal-id-lookup.test.js` (new); `scripts/load/workloads/tracker-gaps-combined.js` (one line) | profile `export-mal-id-lookup` in F3's profile contract (GET via F3.1b, 0.2 rps, qualify fields via F3.1c) |
| `scripts/quality-gates/bdd_landed.txt` (new), `scripts/quality-gates/run_all.sh` (modify) | F1 landed scope starts with `W2-export.feature`; `bdd-traceability` flips to blocking (spec §4) |
| `supabase/tests/rls/110_export_identity_lookup_plan.sql` (new) | EXPLAIN check: the ≤ 500-id lookup uses the primary key for anon and authenticated |
| `web/legal/datenschutz.html` (modify) | Art. 20 lines (DE + EN) name Profile → Export your list |
| `docs/tracker-gaps-2026-11/W2-export/` (new) | baseline + evidence note |
| `docs/tracker-gaps-2026-11/acceptance/W2.json` (new) | F1 acceptance record: tested SHA, per-scenario result, commands, context (corrections brief item 6) |
| `CURRENT_APP_STATE.md`, `CURRENT_APP_STATE_PLAIN.md`, `IMPLEMENTATION_PLAN_Variation1.md`, memory `MEMORY.md` | Rules 1–2 |

No migration: `anime`/`manga` have the policy `"Public read access" … for select to public using (true)` (`20260807000000_baseline_capture_v1.sql:2139`) and both carry `mal_id integer` with `UNIQUE (mal_id)`; the existing `ImportsService.resolveLibraryTitles` already reads them by `id in (…)` in chunks of 200. No `is_adult` filter: the export is the owner's own list.

---

### Task 1: Export value types and the RFC 4180 encoder

**Files:** create `Packages/KuroModules/Sources/KuroLibrary/LibraryExportInput.swift`, `RFC4180.swift`, `Packages/KuroModules/Tests/KuroLibraryTests/LibraryExportTests.swift`.

**Interfaces — Produces:**
```swift
public struct ExportCatalogueRow: Equatable, Sendable {
    public var title: String?        // english ?? romaji ?? native, trimmed; nil when the row has none
    public var anilistId: Int?
    public var malId: Int?
    public init(title: String?, anilistId: Int?, malId: Int?)
}
/// One custom list as W9 holds it (supplied by `CustomListsStore.exportLists()`).
public struct ExportCustomList: Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let createdAt: Date
    /// Manual drag order (W9's slot order). Includes titles no longer in the library (W9 rows are keyed
    /// by title, not lifecycle, and survive library removal). May be empty.
    public let items: [MediaKey]
    public init(id: UUID, name: String, createdAt: Date, items: [MediaKey])
}
public struct LibraryExportInput: Sendable {
    public var entries: [LibraryEntry]
    /// Missing key = identity unknown (lookup unavailable); present with malId nil = no MAL id.
    /// Covers library keys and list-item keys outside the library.
    public var catalogue: [MediaKey: ExportCatalogueRow]
    public var tagsByKey: [MediaKey: [String]] = [:]
    /// Lists in the order W9 shows them; empty lists included. `inLibrary` and per-entry list names are
    /// derived by the exporter from `entries` (one source of truth), never taken from W9.
    public var customLists: [ExportCustomList] = []
    /// Set by the service when a provider returned nil: JSON writes `tags`/`custom_lists`/`lists` as null.
    public var organisationUnavailable: Bool = false
    public init(entries:catalogue:tagsByKey:customLists:organisationUnavailable:)
}
public enum LibraryExportFormat: String, CaseIterable, Sendable { case malXML = "mal_xml", csv, json }
public struct LibraryExportFile: Equatable, Sendable { public let name: String; public let data: Data; public let contentType: String }
public struct ExportReportLine: Equatable, Sendable { public let key: MediaKey; public let title: String }
public struct LibraryExportSummary: Equatable, Sendable {
    public var entryCount: Int
    public var malExported: [MediaKind: Int]
    public var withoutMalId: [ExportReportLine]        // catalogue row present, malId nil
    public var identityUnavailable: [ExportReportLine]  // library entries with no catalogue row (offline / lookup failed); a list item
                                                        // outside the library without a row only exports title null and is not a gap
    public var notesAdjusted: [ExportReportLine]        // MAL file only: controls dropped or note omitted (> 16,384 bytes)
    public var datesOmitted: [ExportReportLine]         // MAL file only: unparseable raw date
    /// Tags/custom lists could not be loaded (offline, W9 store not loaded). Summary copy: "Tags and lists couldn't be loaded. Export again when you're online to include them." / "Tags und Listen konnten nicht geladen werden. Exportiere erneut, wenn du online bist, um sie mitzunehmen."
    public var organisationUnavailable: Bool = false
    /// MAL files per medium (1 = unsplit; > 1 = numbered parts, see Task 2).
    public var malParts: [MediaKind: Int] = [:]
    /// List items whose title is no longer in the library (JSON keeps them with in_library false; CSV has no row for them).
    public var listItemsOutsideLibrary: Int = 0
    /// Empty = complete. Both gaps can hold at once (offline: ids and organisation missing).
    public var gaps: Set<LibraryExportGap> { get }   // .identityUnavailable iff !identityUnavailable.isEmpty; .organisationUnavailable iff organisationUnavailable
    public var isComplete: Bool { get }              // gaps.isEmpty
    /// Public (the app's copy tests build summaries across the module boundary); new fields default.
    public init(entryCount: Int, malExported: [MediaKind: Int], withoutMalId: [ExportReportLine], identityUnavailable: [ExportReportLine],
                notesAdjusted: [ExportReportLine], datesOmitted: [ExportReportLine], organisationUnavailable: Bool = false,
                malParts: [MediaKind: Int] = [:], listItemsOutsideLibrary: Int = 0)
}
public enum LibraryExportGap: String, Hashable, Sendable, CaseIterable {
    case identityUnavailable = "identity_unavailable", organisationUnavailable = "organisation_unavailable"
}
public enum RFC4180 {
    public static func field(_ value: String) -> String   // quotes when value has , " CR LF; doubles "
    public static func row(_ fields: [String]) -> String   // joined by ",", terminated by "\r\n"
}
```
`ExportReportLine.title` is the catalogue title or the fallback `"Anime #<id>"` / `"Manga #<id>"` (same wording as `ImportsService.unresolvedExportTitle`). `withoutMalId`, `notesAdjusted` and `datesOmitted` are MAL-format limits, not gaps: CSV/JSON still hold those entries completely. `RFC4180` stays exactly as specified here (W4 may create this file verbatim); formula neutralisation lives in Task 3's tabular writer, not in `RFC4180.field`.

- [ ] **Step 1: failing test** `@Test func rfc4180FieldQuotesOnlyWhenNeeded()` in `@Suite struct LibraryExportTests`:
```swift
#expect(RFC4180.field("plain") == "plain")
#expect(RFC4180.field("a,b") == "\"a,b\"")
#expect(RFC4180.field("say \"hi\"") == "\"say \"\"hi\"\"\"")
#expect(RFC4180.field("line1\nline2") == "\"line1\nline2\"")
#expect(RFC4180.field("cr\r") == "\"cr\r\"")
#expect(RFC4180.row(["a", "b,c"]) == "a,\"b,c\"\r\n")
```
- [ ] **Step 2:** `cd Packages/KuroModules && swift test --filter LibraryExportTests` → FAIL: `cannot find 'RFC4180' in scope`.
- [ ] **Step 3:** implement both files (types above; `RFC4180` exactly per RFC 4180 §2.6–2.7).
- [ ] **Step 4:** same command → PASS (1 test).
- [ ] **Step 5:** `git add Packages/KuroModules/Sources/KuroLibrary/LibraryExportInput.swift Packages/KuroModules/Sources/KuroLibrary/RFC4180.swift Packages/KuroModules/Tests/KuroLibraryTests/LibraryExportTests.swift && git commit -m "W2: export value types and RFC 4180 encoder"`

### Task 2: MAL XML writer and the round-trip anchor

**Files:** create `Packages/KuroModules/Sources/KuroLibrary/LibraryExportMAL.swift`; extend `LibraryExportTests.swift`.

**Interfaces — Consumes:** F2 `PartialDate`, `LibraryEntry.repeatCount/startedOn/finishedOn`; `MALExportParser.parse(_:)` (unchanged). **Produces:**
```swift
public enum MALExportMapping {
    /// MAL word status written to `my_status` and the rewatch/reread flag.
    public static func malStatus(_ status: ListStatus, kind: MediaKind) -> (word: String, repeating: Bool)
    /// The Kuro status the import path stores for a parsed MAL status string (mirror of SQL `_import_v2_status`
    /// + `SupabaseLibraryBackend.status(fromDB:)`): watching/reading/repeating → .current, plan_to_* → .planning,
    /// completed, dropped, on_hold → .paused. nil for anything else.
    public static func storedStatus(fromParsed raw: String) -> ListStatus?
    /// `YYYY-MM-DD` with 00 for unknown month/day; nil for a nil or unparseable date.
    public static func malDate(_ date: PartialDate?) -> String?
    /// XML 1.0 text: & < > " ' as entities, "\r" as "&#13;", C0 controls (except TAB, LF, CR), U+FFFE and U+FFFF dropped.
    /// `changed` is true when a character was dropped.
    public static func xmlText(_ value: String) -> (text: String, changed: Bool)
    public static let notesByteLimit = 16_384   // MALExportParser's per-element limit
}
extension LibraryExport {
    /// `<myanimelist>` documents for `kind`, entries with a MAL id only, sorted by MAL id. Usually one;
    /// more when one document would exceed `MALExportParser.maxBytes` or `.maxItems` (see split rule).
    /// Sets `summary.malParts[kind]`.
    static func malXML(_ input: LibraryExportInput, kind: MediaKind, summary: inout LibraryExportSummary) -> [Data]
}
```
Pinned status table (`malStatus`): anime `.current` → ("Watching", false), `.repeating` → ("Watching", true), `.planning` → "Plan to Watch", `.completed` → "Completed", `.paused` → "On-Hold", `.dropped` → "Dropped"; manga uses "Reading" / "Plan to Read" for `.current`/`.repeating`/`.planning`, the rest identical.

Document shape (element names are the MAL export schema the parser reads; unknown elements are ignored by the parser):
- Root `<?xml version="1.0" encoding="UTF-8"?>` then `<myanimelist>`, first child `<myinfo><user_export_type>1</user_export_type></myinfo>` (anime) or `2` (manga).
- Anime row children in order: `series_animedb_id`, `series_title`, `my_watched_episodes` (= `progress`), `my_start_date`, `my_finish_date`, `my_score` (= `rating?.value ?? 0`; never `scoreRaw`), `my_status`, `my_comments`, `my_times_watched`, `my_rewatching` (`1`/`0`), `update_on_import` (`1`).
- Manga row: `series_mangadb_id`, `series_title`, `my_read_volumes` (= `sourceMetadata?.volumesProgress`, element omitted when nil), `my_read_chapters`, `my_start_date`, `my_finish_date`, `my_score`, `my_status`, `my_comments`, `my_times_read`, `my_rereadingg` (MAL's own spelling), `update_on_import`.
- When `entry.sourceMetadata == nil`, omit `my_times_*`, `my_start_date`, `my_finish_date` (parser marks them unavailable; import never clears). When a date does not convert, omit that element and add the entry to `summary.datesOmitted`.
- `my_comments`: `xmlText(notes)`; if the de-controlled note is > `notesByteLimit` UTF-8 bytes, omit the element; either adjustment adds the entry to `summary.notesAdjusted`.
- **Whole-file split (corrections brief).** The size that counts is the whole escaped document in UTF-8 bytes: XML declaration, `<myanimelist>`, `<myinfo>…</myinfo>`, every escaped row and the closing tag. Rows are serialised once (escaped bytes), then packed greedily in MAL-id order into parts so that each part's total bytes ≤ `MALExportParser.maxBytes` and its row count ≤ `MALExportParser.maxItems` (the parser rejects only `>`; equal is accepted). Each part is a complete document with its own `<myinfo>`, so each re-imports on its own. Parts are contiguous by MAL id. One part → the unsplit name (`kuro-anime-2026-11-09.xml`); several → `kuro-anime-2026-11-09-part1.xml` … `-partN.xml` (Task 3 `fileName(_:kind:part:…)`). A single row can never exceed the limit (notes ≤ 16,384 bytes before escaping, ≤ ~100 KB escaped).
- Implementer must confirm `my_rewatching` / `my_rereadingg` against one real MAL export file before merge (record the file's element list, without personal data, in the evidence note). The parser does not read them, so the round trip does not depend on them.

- [ ] **Step 1: failing tests** (fixture helper `static func entry(_ kind: MediaKind, _ id: Int, _ status: ListStatus, progress: Int, rating: Int?, notes: String?, repeatCount: Int?, started: String?, finished: String?, volumes: Int? = nil) -> LibraryEntry` builds `sourceMetadata` with those raws).
```swift
@Test func statusTableCoversEveryListStatusAndMedium() {
    for kind in [MediaKind.anime, .manga] { for status in ListStatus.allCases {
        let (word, repeating) = MALExportMapping.malStatus(status, kind: kind)
        #expect(repeating == (status == .repeating))
        #expect(!word.lowercased().contains("repeat"))
    } }
    #expect(MALExportMapping.malStatus(.paused, kind: .anime).word == "On-Hold")
    #expect(MALExportMapping.malStatus(.planning, kind: .manga).word == "Plan to Read")
    #expect(MALExportMapping.storedStatus(fromParsed: "on_hold") == .paused)
    #expect(MALExportMapping.storedStatus(fromParsed: "repeating") == .current)
    #expect(MALExportMapping.storedStatus(fromParsed: "plan_to_read") == .planning)
}

@Test func malXmlRoundTripPreservesEveryMappedEntry() throws {
    // 12 entries: anime + manga × all six statuses; progress 0...140; ratings nil, 1, 10;
    // notes nil, "", "a & b <c> \"d\" 'e'", "line1\r\nline2", "  padded  ", "Grüße 🌸";
    // repeatCount 0 and 3; dates nil, "2024", "2024-03", "2024-03-05", "2024-03-00";
    // every entry has a catalogue row with a MAL id (anime 1001..., manga 2001...).
    let input = Self.everyStatusInput()
    let bundle = LibraryExport.build(input, formats: [.malXML], exportedAt: Self.now, timeZone: Self.berlin)
    #expect(bundle.files.map(\.name) == ["kuro-anime-2026-11-09.xml", "kuro-manga-2026-11-09.xml"])
    let parsed = try bundle.files.flatMap { try MALExportParser.parse($0.data) }
    #expect(parsed.count == 12)
    for entry in input.entries {
        let malId = try #require(input.catalogue[entry.key]?.malId)
        let row = try #require(parsed.first { $0.medium == entry.key.kind.rawValue && $0.externalId == String(malId) })
        #expect(MALExportMapping.storedStatus(fromParsed: row.status) == Self.storedEquivalent(entry.status)) // .repeating → .current
        #expect(row.progress == entry.progress)
        #expect(row.scoreRaw.flatMap(Int.init) == entry.rating?.value)
        #expect((row.notes ?? "") == (entry.notes ?? ""))          // "" and nil are the same "no note"
        #expect(row.repeatCount == entry.repeatCount)
        #expect(row.startedRaw.flatMap(PartialDate.init(raw:)) == entry.startedOn)
        #expect(row.finishedRaw.flatMap(PartialDate.init(raw:)) == entry.finishedOn)
        if entry.key.kind == .manga { #expect(row.volumesProgress == entry.sourceMetadata?.volumesProgress) }
    }
    #expect(bundle.summary.notesAdjusted.isEmpty && bundle.summary.datesOmitted.isEmpty)
}

@Test func malDatesZeroPadEveryPrecisionAndOmitUnparseable() {
    #expect(MALExportMapping.malDate(PartialDate(raw: "2024")) == "2024-00-00")
    #expect(MALExportMapping.malDate(PartialDate(raw: "2024-03")) == "2024-03-00")
    #expect(MALExportMapping.malDate(PartialDate(raw: "2024-03-05")) == "2024-03-05")
    #expect(MALExportMapping.malDate(PartialDate(raw: "2024-03-00")) == "2024-03-00")
    #expect(MALExportMapping.malDate(nil) == nil)
    // An entry whose started_raw is "spring 2019" (PartialDate(raw:) == nil): no <my_start_date>, listed in datesOmitted.
}

@Test func malXmlNotesSurviveEscapingAndAreReportedWhenAdjusted() throws {
    // notes: "<!DOCTYPE x> ]]> & <" → parses back identical, not adjusted;
    // "bell\u{07}tab\tend" → parses back "belltab\tend", entry in notesAdjusted;
    // String(repeating: "é", count: 8_192) (16,384 bytes) → parses back identical;
    // String(repeating: "é", count: 8_193) (16,386 bytes) → no <my_comments>, parsed notes nil, entry in notesAdjusted;
    // the whole file parses (no MALExportError) in every case.
}

@Test func missingSourceMetadataExportsNullNotZero() throws {
    // entry with sourceMetadata == nil: XML row has no my_times_watched/my_start_date/my_finish_date,
    // parsed item has repeatCount nil and unavailableFields ⊇ ["repeat_count","started_raw","finished_raw"].
    // (JSON half asserted in Task 3.)
}

@Test(.timeLimit(.minutes(3))) func malXmlSplitsLargeLibrariesIntoReimportableParts() throws {
    // Worst case: 2,000 anime entries with MAL ids 1...2000, each note EXACTLY MALExportMapping.notesByteLimit
    // (16,384) one-byte characters: String(repeating: "&<>\"", count: 4_096). One byte more and the note is
    // omitted, the file stays small and the test passes vacuously, so assert the note length first:
    let note = String(repeating: "&<>\"", count: 4_096)
    #expect(note.utf8.count == MALExportMapping.notesByteLimit)
    let input = Self.largeLibrary(count: 2_000, kind: .anime, note: note)          // ≈ 78 KB per escaped row, ≈ 156 MB
    let bundle = LibraryExport.build(input, formats: [.malXML], exportedAt: Self.now, timeZone: Self.berlin)
    let parts = bundle.files
    #expect(parts.count >= 2)
    #expect(parts.map(\.name) == (1...parts.count).map { "kuro-anime-2026-11-09-part\($0).xml" })
    #expect(bundle.summary.malParts[.anime] == parts.count)
    var parsed: [MALImportItem] = []                                                  // the parser's item type
    for part in parts {
        #expect(part.data.count <= MALExportParser.maxBytes)
        let items = try MALExportParser.parse(part.data)                              // throws on any limit breach
        #expect(items.count <= MALExportParser.maxItems)
        parsed += items
    }
    #expect(parsed.count == 2_000)
    #expect(Set(parsed.compactMap { Int($0.externalId) }) == Set(1...2_000))          // nothing lost, nothing doubled
    #expect(parsed.allSatisfy { $0.notes == note })
    #expect(bundle.summary.notesAdjusted.isEmpty)
    // parts are contiguous by MAL id: max id of part k < min id of part k+1
}

@Test func malXmlSplitsAtTheParserItemLimit() throws {
    // 20,001 manga entries with short notes (well under maxBytes): 2 parts of 20,000 and 1; both parse;
    // 20,000 entries exactly: 1 part with the unsplit name "kuro-manga-2026-11-09.xml" (equal to the limit is accepted).
}
```
(`MALImportItem` stands for whatever item type `MALExportParser.parse(_:)` returns today; use its real name.)
- [ ] **Step 2:** `swift test --filter LibraryExportTests` → FAIL: `cannot find 'MALExportMapping' in scope` (and `type 'LibraryExport' has no member 'build'`).
- [ ] **Step 3:** implement `LibraryExportMAL.swift` per the interface and pinned values above (including the split rule), and a minimal `LibraryExport.build` that emits the MAL files with their part names (completed in Task 3). Escape with entities only (no CDATA: the parser's raw-byte `<!DOCTYPE`/`<!ENTITY` scan would reject a CDATA note containing that text).
- [ ] **Step 4:** same command → PASS (all tests so far).
- [ ] **Step 5:** `git add Packages/KuroModules/Sources/KuroLibrary/LibraryExportMAL.swift Packages/KuroModules/Sources/KuroLibrary/LibraryExport.swift Packages/KuroModules/Tests/KuroLibraryTests/LibraryExportTests.swift && git commit -m "W2: MAL XML export with round trip through MALExportParser"`

### Task 3: CSV, JSON, the summary and file names

**Files:** create `Packages/KuroModules/Sources/KuroLibrary/LibraryExportTabular.swift`; complete `LibraryExport.swift`; extend tests.

**Interfaces — Produces:**
```swift
public struct LibraryExportBundle: Equatable, Sendable { public let files: [LibraryExportFile]; public let summary: LibraryExportSummary }
public enum LibraryExport {
    public static let csvHeader: [String]
    /// MAL: one file per medium that has ≥ 1 entry with a MAL id (or its numbered parts); CSV and JSON: one file, both media, every entry.
    public static func build(_ input: LibraryExportInput, formats: Set<LibraryExportFormat>,
                             exportedAt: Date, timeZone: TimeZone) -> LibraryExportBundle
    /// "kuro-list-YYYY-MM-DD.csv" / ".json", "kuro-anime-YYYY-MM-DD.xml", "kuro-manga-YYYY-MM-DD.xml";
    /// with `part` (MAL only, split files): "kuro-anime-YYYY-MM-DD-part1.xml".
    /// The date is `exportedAt` in `timeZone` (Gregorian, en_US_POSIX).
    public static func fileName(_ format: LibraryExportFormat, kind: MediaKind?, part: Int? = nil, exportedAt: Date, timeZone: TimeZone) -> String
    /// CSV cell text with spreadsheet formula triggers neutralised: a value whose first character is
    /// `=`, `+`, `-`, `@`, TAB (U+0009) or CR (U+000D) gets a leading `'`. Applied to every CSV cell, before
    /// `RFC4180.field` quoting. JSON never uses it.
    public static func csvSafeText(_ value: String) -> String
}
```
Pinned CSV contract (documented in the file header comment and in `CURRENT_APP_STATE.md`): UTF-8 with BOM (`EF BB BF`, so spreadsheet apps read umlauts), CRLF rows, header exactly
`kind,kuro_id,anilist_id,mal_id,title,status,progress,progress_label,unit_id,volumes_progress,rating,verdict,repeat_count,started_on,finished_on,notes,tags,custom_lists,created_at,updated_at` (20 columns).
Values: `kind` = `anime`/`manga`; `status` = `ListStatus.rawValue`; empty cell for nil; `progress_label` / `unit_id` = the entry's tracking-unit identity as stored (`LibraryEntry.progressLabel`, `.unitId` lower-case UUID), empty when absent (a local progress edit clears both, `LibraryValues.swift:273`; never inferred); `rating` 1–10; dates = `PartialDate.raw` when it parses, else the stored raw string; `tags` joined with `"; "`; `custom_lists` = names of the lists (from `input.customLists`, in list order) that contain the entry, joined with `"; "` (CSV is not the lossless format; JSON is); timestamps ISO 8601 UTC. Rows sorted by `kind` (anime first) then `kuro_id`. List items outside the library have no CSV row (they are in JSON; the summary counts them).
**Formula neutralisation (O3 resolved: neutralise by default).** Every cell goes through `csvSafeText` before `RFC4180.field`: a value starting with `=`, `+`, `-`, `@`, TAB or CR is written with a leading `'` (OWASP CSV injection guidance). The documented consequence: such a note reads back from CSV with one extra leading `'`; the JSON file keeps the exact text and is the lossless format. Stated in the CSV writer's header comment and in `CURRENT_APP_STATE.md` (no new UI copy).

Pinned JSON contract (`JSONSerialization`, `.sortedKeys`, `.prettyPrinted`, `.withoutEscapingSlashes`): `{"format":"kuro-library-export","version":1,"exported_at":"<ISO 8601 UTC>","complete":<Bool>,"gaps":["identity_unavailable"|"organisation_unavailable", …],"entries":[…],"lists":[…]|null}`; each entry: `kind, kuro_id, anilist_id, mal_id, title, status, progress, progress_label, unit_id, volumes_progress, rating, verdict, notes, repeat_count, started_on, finished_on, tags, custom_lists, source, created_at, updated_at`. Text is exact (no neutralisation). `unit_id` = lower-case UUID string or `null`; `progress_label` string or `null`. `started_on`/`finished_on` = `{"raw": <stored raw>, "precision": "year"|"month"|"day"|null}` or `null`; `repeat_count` = `null` when `sourceMetadata == nil`; `source` = `null` or `{"score_raw","score_scale","private","imported_custom_lists","hidden_from_status_lists","list_options"}` with `list_options` the raw stored string. Missing catalogue → `anilist_id`/`mal_id`/`title` null. `tags` / `custom_lists` per entry (list names, derived from `lists`) are `null` when `organisationUnavailable`, else arrays (possibly empty).
`lists` (corrections brief: "lists as separate objects `{ id, name, createdAt, items: [{ medium, mediaId, position, inLibrary: Bool }] }` in manual order", written in this file's snake_case): `[{"id":"<uuid>","name":…,"created_at":"<ISO 8601 UTC>","items":[{"medium":"anime"|"manga","media_id":Int,"position":Int,"in_library":Bool,"title":String|null}]}]`. Lists in `input.customLists` order, empty lists included (`"items":[]`). Items in manual drag order; `position` is the 1-based ordinal in that order (W9's stored fractional rank is an implementation detail and is not exported); `in_library` = the key is among `input.entries`; `title` from the catalogue row when known (the identity lookup covers list keys outside the library too), else `null`. `lists` is `null` (not `[]`) when the provider could not load.

- [ ] **Step 1: failing tests**
```swift
@Test func entriesWithoutMalIdAreReportedNotDropped() throws {
    // 6 entries; "Kaiju Diary" (anime 7) and "Moon Ledger" (manga 9) have catalogue rows with malId nil.
    let bundle = LibraryExport.build(Self.twoWithoutMalId(), formats: [.malXML, .csv, .json], exportedAt: Self.now, timeZone: Self.berlin)
    let parsed = try bundle.files.filter { $0.name.hasSuffix(".xml") }.flatMap { try MALExportParser.parse($0.data) }
    #expect(parsed.count == 4)
    #expect(bundle.summary.withoutMalId.map(\.title).sorted() == ["Kaiju Diary", "Moon Ledger"])
    #expect(try Self.csvRows(bundle.file("kuro-list-2026-11-09.csv")).count == 1 + 6)   // header + every entry
    #expect(try Self.jsonEntries(bundle.file("kuro-list-2026-11-09.json")).count == 6)
}

@Test func csvHasDocumentedHeaderAndEscapesText() throws {
    let note = "first, \"quoted\"\r\nsecond line"
    let rows = try Self.csvRows(LibraryExport.build(Self.single(notes: note), formats: [.csv], exportedAt: Self.now, timeZone: Self.berlin).files[0])
    #expect(rows[0] == LibraryExport.csvHeader)
    #expect(LibraryExport.csvHeader.first == "kind" && LibraryExport.csvHeader.count == 20)
    let notesColumn = try #require(LibraryExport.csvHeader.firstIndex(of: "notes"))
    #expect(rows[1][notesColumn] == note)
}

@Test func jsonCarriesIdsTagsListsAndDates() throws {
    // entry anime 42: catalogue anilistId 9253, malId 9253; tags ["slow burn","rewatch"]; customLists [ExportCustomList "Comfort" ∋ anime 42];
    // progressLabel "S2 E5", unitId 6F1C…(fixed UUID); started_raw "2019-04" (month precision); finished_raw nil;
    // sourceMetadata.customLists ["Imported A"]. A second entry has progressLabel nil, unitId nil.
    let entry = try #require(Self.jsonEntries(...).first)
    #expect(entry["kuro_id"] as? Int == 42 && entry["anilist_id"] as? Int == 9253 && entry["mal_id"] as? Int == 9253)
    #expect(entry["progress_label"] as? String == "S2 E5")
    #expect(entry["unit_id"] as? String == Self.unitId.uuidString.lowercased())
    #expect(entry["tags"] as? [String] == ["slow burn", "rewatch"])
    #expect(entry["custom_lists"] as? [String] == ["Comfort"])
    #expect((entry["started_on"] as? [String: Any])?["raw"] as? String == "2019-04")
    #expect((entry["started_on"] as? [String: Any])?["precision"] as? String == "month")
    #expect(entry["finished_on"] is NSNull)
    #expect(((entry["source"] as? [String: Any])?["imported_custom_lists"] as? [String]) == ["Imported A"])
    // second entry: unit_id and progress_label are NSNull (never "" and never inferred); the CSV row has empty cells for both
}

@Test func jsonExportsListsInManualOrderWithItemsOutsideTheLibrary() throws {
    // entries: anime 1, anime 2, manga 3. customLists (in this order):
    //   "Comfort"   (created 2026-10-01) items [manga 3, anime 1, anime 99]   // anime 99 left the library
    //   "Empty one" (created 2026-10-02) items []
    // catalogue has a row for anime 99 (title "Old Flame").
    let bundle = LibraryExport.build(Self.listsInput(), formats: [.json, .csv], exportedAt: Self.now, timeZone: Self.berlin)
    let lists = try Self.jsonLists(bundle.file("kuro-list-2026-11-09.json"))
    #expect(lists.map { $0["name"] as? String } == ["Comfort", "Empty one"])            // order kept, empty list kept
    let items = try #require(lists[0]["items"] as? [[String: Any]])
    #expect(items.map { $0["media_id"] as? Int } == [3, 1, 99])                         // manual order
    #expect(items.map { $0["medium"] as? String } == ["manga", "anime", "anime"])
    #expect(items.map { $0["position"] as? Int } == [1, 2, 3])
    #expect(items.map { $0["in_library"] as? Bool } == [true, true, false])
    #expect(items[2]["title"] as? String == "Old Flame")
    #expect((lists[1]["items"] as? [Any])?.isEmpty == true)
    #expect(lists[0]["created_at"] as? String == "2026-10-01T00:00:00Z" && lists[0]["id"] is String)
    #expect(bundle.summary.listItemsOutsideLibrary == 1)
    #expect(try Self.csvRows(bundle.file("kuro-list-2026-11-09.csv")).count == 1 + 3)  // no CSV row for anime 99
    // organisationUnavailable input: "lists" is NSNull and every entry's "tags"/"custom_lists" is NSNull (not [])
}

@Test func csvNeutralisesFormulaCellsAndJsonKeepsExactText() throws {
    // six entries whose notes are "=HYPERLINK(\"http://x\")", "+1", "-2", "@SUM(A1)", "\tTab", "\rCR";
    // a seventh whose title (catalogue) is "=cmd" and notes "a=b" (trigger not leading).
    let bundle = LibraryExport.build(Self.formulaInput(), formats: [.csv, .json], exportedAt: Self.now, timeZone: Self.berlin)
    let rows = try Self.csvRows(bundle.file("kuro-list-2026-11-09.csv"))
    let notes = try #require(LibraryExport.csvHeader.firstIndex(of: "notes"))
    let title = try #require(LibraryExport.csvHeader.firstIndex(of: "title"))
    #expect(rows.dropFirst().prefix(6).map { $0[notes] } == Self.formulaNotes.map { "'" + $0 })
    #expect(rows[7][title] == "'=cmd" && rows[7][notes] == "a=b")
    #expect(try Self.jsonEntries(bundle.file("kuro-list-2026-11-09.json")).prefix(6).map { $0["notes"] as? String } == Self.formulaNotes)
    #expect(LibraryExport.csvSafeText("plain") == "plain" && LibraryExport.csvSafeText("") == "")
}

@Test func summaryDistinguishesCompleteIdentityAndOrganisationGaps() throws {
    // all identities known, organisation loaded → summary.isComplete, gaps == [], JSON "complete": true, "gaps": []
    // 2 keys without a catalogue row → gaps == [.identityUnavailable]
    // organisationUnavailable input → gaps == [.organisationUnavailable]
    // both → gaps == [.identityUnavailable, .organisationUnavailable], JSON "complete": false, "gaps" sorted
    // withoutMalId / notesAdjusted / datesOmitted alone never make the export incomplete
}

@Test func fileNamesUseLocalDateAroundMidnight() throws {
    let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
    #expect(LibraryExport.fileName(.csv, kind: nil, exportedAt: Date(timeIntervalSince1970: 1_794_265_170), timeZone: berlin) == "kuro-list-2026-11-09.csv") // 22:59:30Z = 23:59:30 local
    #expect(LibraryExport.fileName(.csv, kind: nil, exportedAt: Date(timeIntervalSince1970: 1_794_265_230), timeZone: berlin) == "kuro-list-2026-11-10.csv") // 23:00:30Z = 00:00:30 local
}
```
`csvRows` is a test-only RFC 4180 reader (strips the BOM, honours quoted CR/LF and doubled quotes) in the test file; `jsonLists` reads the top-level `lists`; tests use `try #require` for every optional (no `!` in shipped or test code). Extend `missingSourceMetadataExportsNullNotZero` with the JSON half (`repeat_count` is `NSNull`, `source` is `NSNull`).
- [ ] **Step 2:** `swift test --filter LibraryExportTests` → FAIL: `type 'LibraryExport' has no member 'csvHeader'` (and `csvSafeText`).
- [ ] **Step 3:** implement `LibraryExportTabular.swift` and finish `LibraryExport.build` (summary filled once; MAL files skipped for a medium with zero MAL-id entries; `gaps` derived; `listItemsOutsideLibrary` counted).
- [ ] **Step 4:** same command → PASS (every `LibraryExportTests` test; `swift test` whole package green).
- [ ] **Step 5:** `git add Packages/KuroModules/Sources/KuroLibrary/LibraryExportTabular.swift Packages/KuroModules/Sources/KuroLibrary/LibraryExport.swift Packages/KuroModules/Tests/KuroLibraryTests/LibraryExportTests.swift && git commit -m "W2: CSV and JSON export with documented columns"`

### Task 4: Batched catalogue identity read on CatalogStore

**Files:** create `Kuro/Catalog/CatalogStore+ExportIdentities.swift`, `KuroTests/LibraryExportFlowTests.swift`.

**Interfaces — Produces:**
```swift
extension CatalogStore {
    static let exportIdentityBatchSize = 500
    /// Public identity rows for `keys`: one `GET /rest/v1/{anime|manga}?select=id,anilist_id,mal_id,title_english,title_romaji,title_native&id=in.(…)`
    /// per ≤ 500 ids, sequential per medium. Stateless (no cache here: the key set is account data and CatalogStore
    /// survives sign-out). A failed batch leaves its keys absent; never throws. Checks `Task.isCancelled` before
    /// each batch and returns what it has without sending further batches (cancellation is not a failed batch to
    /// skip past: the caller's credential lease cancels it on an account transition).
    func exportIdentities(for keys: Set<MediaKey>) async -> [MediaKey: ExportCatalogueRow]
}
```
The caller (`LibraryExportService`, Task 5) runs this inside `accountSession.withCredentialLease(for:)`. `CatalogStore` has no `accountSession` before W5, so the lease is taken by the account-scoped caller, not here.
- [ ] **Step 1: failing test** in `@MainActor @Suite struct LibraryExportFlowTests`:
```swift
@Test func identityLookupBatchesAtMostFiveHundredIds() async throws {
    let harness = try PublicDataHarness { request in Self.identityRows(for: request) }   // answers id=in.(…) with mal_id = id + 10_000
    let keys = Set((1...1_200).map { MediaKey(kind: .anime, id: $0) } + (1...300).map { MediaKey(kind: .manga, id: $0) })
    let rows = await harness.catalog.exportIdentities(for: keys)
    let requests = harness.server.requests.filter { $0.resource == "anime" || $0.resource == "manga" }
    #expect(requests.count == 4)                                   // 500 + 500 + 200 anime, 300 manga
    #expect(requests.allSatisfy { Self.inListCount($0) <= 500 && $0.method == "GET" })
    #expect(requests.allSatisfy { $0.query("is_adult") == nil })
    #expect(rows.count == 1_500 && rows[MediaKey(kind: .anime, id: 7)]?.malId == 10_007)
}

@Test func identityLookupStopsBetweenBatchesWhenCancelled() async throws {
    // 1,500 anime keys; the first batch is held open (ControlledResponses); cancel the calling task; release
    // → exactly 1 anime request was sent, the result holds at most that batch's rows
}
```
(If `PublicDataHarness` exposes the owner under another name, use it; it lives in `KuroTests/StubPostgREST.swift`.)
- [ ] **Step 2:** `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,id=7FC4B58A-430C-457D-A017-6B0095723F3F' test -only-testing:KuroTests/LibraryExportFlowTests` → FAIL: `value of type 'CatalogStore' has no member 'exportIdentities'`.
- [ ] **Step 3:** implement (decode `id, anilist_id, mal_id, title_english, title_romaji, title_native`; title = first non-empty trimmed of english, romaji, native; `#if DEBUG` print on a failed batch only).
- [ ] **Step 4:** same command → PASS.
- [ ] **Step 5:** `git add Kuro/Catalog/CatalogStore+ExportIdentities.swift KuroTests/LibraryExportFlowTests.swift && git commit -m "W2: batched catalogue identity read for export"`

### Task 5: LibraryExportService owner, composition and flag

**Files:** create `Kuro/Library/LibraryExportService.swift`; modify `Kuro/Composition/AppComposition.swift`, `Kuro/KuroApp.swift`, `Kuro/Services/FeatureFlags.swift`, `KuroTests/IdentityCompositionTests.swift` (expected order; `SessionSDKHarness.init`'s `flags: FeatureFlags? = nil` parameter is added by F2.3, which merges first; add it here only if missing); extend `KuroTests/LibraryExportFlowTests.swift`.

**Interfaces — Consumes:** `FeatureFlags.libraryExportV1Enabled` (through an injected `isEnabled` closure); `LibraryStore.loadState`, `.allEntries`; `CatalogStore.exportIdentities(for:)`; `AccountSessionCoordinator.current` / `isCurrent(_:)` / `withCredentialLease(for:_:)` (`Packages/KuroModules/Sources/KuroCore/AccountSession.swift:120`; usage pattern `Kuro/Home/HomeStore.swift:99`); package `LibraryExport.build`. W9's `LibraryTagsStore` / `CustomListsStore` are NOT referenced: the owner takes two providers so W2 merges before or after W9.
- **W9 must supply** `CustomListsStore.exportLists() -> [ExportCustomList]?` (`nil` before its first load or while unavailable) and the flag accessor `FeatureFlags.libraryOrganiseV1Enabled`: lists in W9's display order, each with `id`, `name`, `createdAt` (from `custom_lists_v1`) and `items` in slot (manual drag) order, empty lists included, items whose title left the library included. W9's `CustomList` (`09-lists.md`, Task W9.5) has neither `createdAt` nor exposes slot order in `listNamesByKey()`, so W9 adds this method; `listNamesByKey()` is no longer W2's input.
- Whichever of W2/W9 lands second wires them in `makeGraph` (`00-program.md` → Shared files and merge order). A provider returns `nil` when it could not load (never a silent empty value, which would look complete), and returns empty without any request while W9's `library_organise_v1` is off (no organisation feature ≠ unavailable):
  - `tagsByKey: { [weak flags, weak libraryTags] in guard flags?.libraryOrganiseV1Enabled == true else { return [:] }; await libraryTags?.load(); return libraryTags?.loadState == .loaded ? libraryTags?.tagsByKey : nil }`
  - `customLists: { [weak flags, weak customLists] in guard flags?.libraryOrganiseV1Enabled == true else { return [] }; await customLists?.load(); return customLists?.loadState == .loaded ? customLists?.exportLists() : nil }`
  (W9's `load(force: false)` reads only when not yet loaded; a not-yet-loaded owner is loaded first, so an export made before Collection was opened still carries tags and lists. W9's stores take their own credential leases.)
- **Flag before any request.** `export(_:)` checks `isEnabled()` first; off → `.failed(.disabled)`, no lookup, no provider call, no file.
- **Leased lookup.** Uncached keys (library keys ∪ list-item keys outside the library) are looked up as `try await accountSession.withCredentialLease(for: context) { await catalog.exportIdentities(for: uncached) }`. A `CancellationError` (account transition) publishes nothing and returns to `.idle`; the identity cache is written only after the lease returned and `isCurrent(context)` still holds. Why a public read is leased: the id set is the account's library and the shared client attaches the bearer at dispatch (F33, `KuroTests/CredentialLeaseTests.swift` header), so without the lease A's library ids could be sent under B's credential.

**Produces:**
```swift
enum LibraryExportFailure: Equatable, Sendable { case disabled, notLoaded, signedOut, writeFailed }
enum LibraryExportState: Equatable { case idle, preparing(LibraryExportFormat), ready(LibraryExportResult), failed(LibraryExportFailure) }
struct LibraryExportResult: Equatable { let format: LibraryExportFormat; let files: [URL]; let summary: LibraryExportSummary }

@MainActor @Observable final class LibraryExportService: AccountScopedState {
    init(library: LibraryStore, catalog: CatalogStore, accountSession: AccountSessionCoordinator,
         isEnabled: @escaping @MainActor () -> Bool,                                            // { [weak flags] in flags?.libraryExportV1Enabled ?? false }
         directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("kuro-export", isDirectory: true),
         now: @escaping @Sendable () -> Date = { Date() }, timeZone: @escaping @Sendable () -> TimeZone = { .current },
         tagsByKey: @escaping @MainActor () async -> [MediaKey: [String]]? = { [:] },          // feeds LibraryExportInput.tagsByKey; nil = could not load → summary.organisationUnavailable
         customLists: @escaping @MainActor () async -> [ExportCustomList]? = { [] },          // feeds LibraryExportInput.customLists (ordered list objects, W9); nil = could not load → summary.organisationUnavailable
         write: @escaping @Sendable (Data, URL, Data.WritingOptions) throws -> Void = { try $0.write(to: $1, options: $2) })
    private(set) var state: LibraryExportState = .idle
    /// Identity rows of earlier lookups for the current account (offline exports); only uncached keys are requested.
    @ObservationIgnored private(set) var identityCache: [MediaKey: ExportCatalogueRow] = [:]
    /// Checks isEnabled() before anything else (off → .failed(.disabled), no request); captures the AccountContext;
    /// refuses unless loadState == .loaded; looks up uncached identities inside withCredentialLease(for: context);
    /// calls both organisation providers; builds the input on the main actor, runs LibraryExport.build in
    /// Task.detached(priority: .userInitiated); writes each file with .completeFileProtection into
    /// directory/<UUID>/ ; publishes only if the context is still current.
    func export(_ format: LibraryExportFormat) async
    /// Deletes the current export folder and returns to .idle (sheet dismiss).
    func discardFiles()
    func cancelAccountWork()            // cancels the in-flight export task
    func clearPrivateState()            // discardFiles() + identityCache = [:] + delete `directory` entirely
    func removeDeletedAccountData(userId: String) async throws   // identityCache = [:] + delete `directory`
}
```
Composition: `makeLibraryExport(library:catalog:accountSession:flags:)` builder used by `makeGraph` (passes `isEnabled: { [weak flags] in flags?.libraryExportV1Enabled ?? false }`); `AppGraph.libraryExport`; `makeAccountScopedStates` order becomes `… + [support, libraryExport, widgets] + …` (new parameter `libraryExport:`). `FeatureFlags.libraryExportV1Enabled`.

- [ ] **Step 1: failing tests**
```swift
@Test func exportSheetSharesFilesForSignedInAccount() async throws {
    let fixture = try ExportFixture(titles: 25, now: Self.nov9Noon)        // testingGraph + FakeLibraryBackend rows + PublicDataHarness identities
    try await fixture.signInAndLoad()
    await fixture.graph.libraryExport.export(.csv)
    guard case .ready(let result) = fixture.graph.libraryExport.state else { Issue.record("not ready"); return }
    #expect(result.files.map(\.lastPathComponent) == ["kuro-list-2026-11-09.csv"])
    #expect(try Self.csvLineCount(result.files[0]) == 26)
    #expect(fixture.writer.lastOptions.contains(.completeFileProtection))   // injected writer; the real protection class is a device check
}

@Test func exportWorksOfflineWithCachedCatalogueOrReportsMissingIds() async throws {
    let fixture = try ExportFixture(titles: 10, now: Self.nov9Noon)
    try await fixture.signInAndLoad()
    fixture.server.answerIdentitiesOnly(for: Set(fixture.keys.prefix(6)))               // online: 6 rows found, 4 batches fail
    await fixture.graph.libraryExport.export(.json)                                     // fills the owner's cache with 6
    fixture.server.failAll(with: .transport(URLError(.notConnectedToInternet)))          // now offline
    await fixture.graph.libraryExport.export(.csv)
    guard case .ready(let result) = fixture.graph.libraryExport.state else { Issue.record("not ready"); return }
    #expect(try Self.csvLineCount(result.files[0]) == 11)                               // header + all 10
    #expect(result.summary.identityUnavailable.count == 4)
    #expect(Set(result.summary.identityUnavailable.map(\.key)) == Set(fixture.keys.suffix(4)))
    #expect(result.summary.organisationUnavailable == true)                          // fixture's tag provider returns nil while offline; never silent
}

@Test func exportRefusesUntilLibraryLoaded() async throws {
    // library bound, fetch held open (ControlledResponses) → export(.json) → state == .failed(.notLoaded), no file in directory
}

@Test func accountSwitchMidExportPublishesNothingAndDeletesFiles() async throws {
    // identity request held open; start export(.malXML); switch account (session funnel); release request
    // → state == .idle, directory has no files, identityCache.isEmpty, no identity request carries B's bearer
    //   (the risk is A's library ids sent with B's credential, not the reverse);
    // then removeDeletedAccountData(userId:) on a service with a filled cache → identityCache.isEmpty, directory gone
}

@Test func flagOffSendsNoRequest() async throws {
    let fixture = try ExportFixture(titles: 25, now: Self.nov9Noon, exportEnabled: false)   // FeatureFlags(launchArguments: []) → flag off
    try await fixture.signInAndLoad()
    let before = fixture.server.requests.count
    await fixture.graph.libraryExport.export(.json)
    #expect(fixture.graph.libraryExport.state == .failed(.disabled))
    #expect(fixture.server.requests.count == before)                  // no anime/manga lookup, no organisation read
    #expect(fixture.organisationProviderCalls == 0)
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).isEmpty)
}

@Test func identityLookupNeverSendsOldLibraryWithNewCredentials() async throws {
    // Pattern: CredentialLeaseTests/preDispatchSwitchSendsNothingAsB (KuroTests/CredentialLeaseTests.swift:48) over the real SDK
    // client: SessionSDKHarness (KuroTests/IdentityCompositionTests.swift:361), storage.replace(with:), bearerSubject;
    // lease semantics pinned by AccountSessionTests/leaseIsRevalidatedBeforeItStarts and transitionCancelsRunningLease.
    // Harness: SessionSDKHarness(responder:libraryBackend:flags:) with a FakeLibraryBackend holding 3 anime rows for A
    // (ids 11, 12, 13) and flags = FeatureFlags(userDefaults: h.defaults, launchArguments: ["--ff-on=library_export_v1"]);
    // without rows the export has no ids to look up and the test proves nothing; without the flag it stops at .disabled.
    // Positive control first (no switch): export(.csv) sends ≥ 1 anime request whose id=in.(…) ⊇ {11,12,13} and whose
    //   bearerSubject == userA (the "sent normally while current" half, as in outboundLinkTapIsBoundToItsAccount).
    // Then a fresh harness: A signed in, library loaded, B's session kept; export(.csv) starts (Task.immediate) and is accepted;
    // before the lookup is dispatched: h.storage.replace(with: sessionB) and the funnel switches to B
    // → no anime/manga request carries bearerSubject == userB; no request at all for A's ids after the switch;
    //   state == .idle; identityCache.isEmpty; directory holds no file
}
```
`ExportFixture` turns the flag on by default (`FeatureFlags(userDefaults:launchArguments: ["--ff-on=library_export_v1"])`, the pattern in `KuroTests/NavdetailTests.swift:238`; `exportEnabled: false` passes `[]`), so the existing flow tests keep running with the service-level check in place. `ExportFixture` gives every test its own `directory` (`temporaryDirectory/kuro-export-test-<UUID>`) because Swift Testing runs tests in parallel and `clearPrivateState()` deletes the whole folder; the owner writes through an injected `write: @Sendable (Data, URL, Data.WritingOptions) throws -> Void` (default `Data.write(to:options:)`) so the test can check the `.completeFileProtection` option (the simulator does not reliably report the protection class; verify it on a device in the evidence note). In `IdentityCompositionTests.expectedAccountScopedStates`, insert `g.libraryExport` between `g.support` and `g.widgets` (this changes the existing test first, so it fails until composition is updated).
- [ ] **Step 2:** run `-only-testing:KuroTests/LibraryExportFlowTests -only-testing:KuroTests/IdentityCompositionTests` → FAIL: `value of type 'AppGraph' has no member 'libraryExport'`.
- [ ] **Step 3:** implement the owner (flag check first, leased lookup, providers), composition, `KuroApp` injection (`@State private var libraryExport = AppComposition.shared.libraryExport` + `.environment(libraryExport)`) and the flag accessor. Do not read the owner from `ProfileView` (four snapshot hosts render `ProfileView` without it).
- [ ] **Step 4:** same command → PASS; then `scripts/quality-gates/check_architecture.sh` → 0 offenders.
- [ ] **Step 5:** `git add Kuro/Library/LibraryExportService.swift Kuro/Composition/AppComposition.swift Kuro/KuroApp.swift Kuro/Services/FeatureFlags.swift KuroTests/LibraryExportFlowTests.swift KuroTests/IdentityCompositionTests.swift && git commit -m "W2: LibraryExportService owner, composition and flag"`

### Task 6: Profile → "Export your list" tool sheet, copy and privacy text

**Files:** create `Kuro/Views/Profile/LibraryExportSheet.swift`, `Kuro/Views/Profile/LibraryExportCopy.swift`; modify `Kuro/Views/ProfileView.swift`, `web/legal/datenschutz.html`; extend `KuroTests/LibraryExportFlowTests.swift`.

**Interfaces — Produces:**
```swift
nonisolated enum LibraryExportCopy {
    static func rowTitle(german: Bool) -> String        // "Export your list" / "Liste exportieren"
    static func rowSubtitle(german: Bool) -> String     // "CSV, MyAnimeList or JSON. Free." / "CSV, MyAnimeList oder JSON. Kostenlos."
    static func formatTitle(_ f: LibraryExportFormat, german: Bool) -> String   // "Spreadsheet (CSV)", "MyAnimeList (XML)", "Everything (JSON)" / "Tabelle (CSV)", "MyAnimeList (XML)", "Alles (JSON)"
    static func summaryLines(_ s: LibraryExportSummary, format: LibraryExportFormat, german: Bool) -> [String]
    // e.g. "2 titles have no MyAnimeList id and are not in the MAL file. They are in CSV and JSON."
    //      "2 Titel haben keine MyAnimeList-ID und fehlen in der MAL-Datei. Sie sind in CSV und JSON."
    //      "4 titles could not be looked up offline; their ids are missing." / "4 Titel konnten offline nicht nachgeschlagen werden; ihre IDs fehlen."
    //      organisationUnavailable: the Task 1 sentence ("Tags and lists couldn't be loaded. …" / "Tags und Listen konnten nicht geladen werden. …")
    //      malParts[.anime] == 3 (MAL format): "Your anime list is in 3 files so importers accept it. Import all 3." /
    //                                          "Deine Anime-Liste ist auf 3 Dateien verteilt, damit Importe sie annehmen. Importiere alle 3."
    //      listItemsOutsideLibrary == 2 (CSV/MAL format): "2 list entries are no longer in your library; they are in the JSON file." /
    //                                                     "2 Listeneinträge sind nicht mehr in deiner Bibliothek; sie stehen in der JSON-Datei."
    //      A complete export with nothing to report returns no lines (the sheet shows only Share).
    static func offlineNote(german: Bool) -> String     // "You're offline. Your list exports; some catalogue ids may be missing." / "Du bist offline. Deine Liste wird exportiert; manche Katalog-IDs können fehlen."
    static func failure(_ f: LibraryExportFailure, german: Bool) -> String   // .disabled: "Export isn't available yet." / "Export ist noch nicht verfügbar."
}
struct LibraryExportSheet: View   // @Environment(LibraryExportService.self), @Environment(NetworkMonitor.self)
```
Sheet: Contact-sheet grammar (white page, `kuroRoleText(.headline)` heading "Export your list." / "Liste exportieren.", ink rule, three quiet format rows, one `KuroInkButton` "Prepare file" / "Datei vorbereiten" showing `KuroBusyMark` while `.preparing`; when `.ready`, `ShareLink(items: result.files)` labelled "Share" / "Teilen" plus `summaryLines`; offline uses `KuroOfflineView(hasContent: true)`-style band with `offlineNote`; ✕ close top-trailing; `.presentationDragIndicator(.visible)`; `.onDisappear { export.discardFiles() }`). Profile: in `accountSection`, a `ProfileQuietRow` after "Sign out" shown only when `flags.libraryExportV1Enabled`; `@State private var showExport = false`; `.sheet(isPresented: $showExport) { LibraryExportSheet().kuroLeavesJourney().environment(\.shellPageLifetime, nil) }` and `.kuroNavigationLayer("profile.export", isPresented: $showExport)`. Do not retrofit the other Profile sheets (DO-NOT 16).
Privacy: in both Art. 20 list items append "– direkt in der App unter Profil → „Liste exportieren“ (CSV, MyAnimeList-XML, JSON)" / "– directly in the app under Profile → “Export your list” (CSV, MyAnimeList XML, JSON)". The page has no inline script, so `vercel.json`'s CSP hash is untouched (verify `grep -c "<script" web/legal/datenschutz.html` → `0`).

- [ ] **Step 1: failing tests**
```swift
@Test func exportCopyIsBilingualAndCountsTitles() {
    var s = LibraryExportSummary(entryCount: 10, malExported: [.anime: 8], withoutMalId: [line("A"), line("B")], identityUnavailable: [], notesAdjusted: [], datesOmitted: [])
    #expect(LibraryExportCopy.summaryLines(s, format: .malXML, german: false).first == "2 titles have no MyAnimeList id and are not in the MAL file. They are in CSV and JSON.")
    #expect(LibraryExportCopy.summaryLines(s, format: .malXML, german: true).first == "2 Titel haben keine MyAnimeList-ID und fehlen in der MAL-Datei. Sie sind in CSV und JSON.")
    s.withoutMalId = []; #expect(LibraryExportCopy.summaryLines(s, format: .csv, german: false).isEmpty)   // complete: no lines
}
@Test func exportCopyNamesEachGapAndSplit() {
    // identityUnavailable 4 → the "4 titles could not be looked up offline" line (EN/DE);
    // organisationUnavailable → the tags-and-lists line; both → both lines, identity first;
    // malParts[.anime] = 3 with format .malXML → the "in 3 files" line; listItemsOutsideLibrary = 2 with .csv → the JSON line;
    // failure(.disabled, german:) non-empty and EN != DE
}
@Test func exportSheetFitsPhoneWidthAtLargestTypeSizeInGerman() throws {
    // host LibraryExportSheet (.ready state, German copy, .dynamicTypeSize(.accessibility3)) in a UIHostingController
    // (pattern: HomeCompositionSnapshotTests); sizeThatFits(in: CGSize(width: 375, height: .greatestFiniteMagnitude)).width <= 375
}
```
- [ ] **Step 2:** run `-only-testing:KuroTests/LibraryExportFlowTests` → FAIL: `cannot find 'LibraryExportCopy' in scope`.
- [ ] **Step 3:** implement copy, sheet, Profile row/sheet, privacy text.
- [ ] **Step 4:** same command → PASS; `scripts/quality-gates/check_navigation.sh` and `check_branded_states.sh` → 0 offenders.
- [ ] **Step 5:** `git add Kuro/Views/Profile/LibraryExportSheet.swift Kuro/Views/Profile/LibraryExportCopy.swift Kuro/Views/ProfileView.swift web/legal/datenschutz.html KuroTests/LibraryExportFlowTests.swift && git commit -m "W2: Profile export tool sheet, EN/DE copy, privacy text"`

### Task 7: Load profile `export-mal-id-lookup` and the query-plan check

**Files:** create `scripts/load/profiles/export-mal-id-lookup.js`, `scripts/load/profiles/export-mal-id-lookup.test.js`, `supabase/tests/rls/110_export_identity_lookup_plan.sql`, `docs/tracker-gaps-2026-11/W2-export/identity-lookup-plan.md`; modify `scripts/load/workloads/tracker-gaps-combined.js` (one line).

**Interfaces — Consumes:** F3's profile contract exactly as `00-foundation.md` defines it: F3.1 (registry, `ratePerSecond`, separate absolute-rate lane; a `weight` field makes `loadProfiles` throw), F3.1b (GET option, `core`), F3.1c (`emptyExamples`, `validate(…, ctx)` with `ctx.mode`, `--qualify`, `tracker-gaps-combined`). `backend_workload.js` is not edited; profiles never enter `WEIGHTS`. **Produces** (`scripts/load/profiles/export-mal-id-lookup.js`):
```js
module.exports = {
  name: "export-mal-id-lookup",
  budgetClass: "browse",          // 750 ms
  ratePerSecond: 0.2,             // old weight 1 × 0.2 (F3.1 conversion); on-demand export is rare
  librarySizes: [25, 100, 2000],  // a size-0 account has nothing to export
  writes: false,
  emptyExamples: [[], {}, null],  // validate(…, { mode: "qualify" }) must reject each (F3.1c; checked by loadProfiles)
  request(actor, fixture, seq, random, core) {  // medium = seq % 3 === 0 ? "manga" : "anime"; ≤ 500 ids from fixture.media[medium],
                                                // offset (seq * 500) % size; the actor's bearer is sent (the app leases this read)
    return { method: "GET", path: "/rest/v1/" + medium + "?select=id,anilist_id,mal_id,title_english,title_romaji,title_native&id=in.(" + ids.join(",") + ")" };
  },
  // ctx.mode "wiring" (default, never release evidence) accepts an empty array; "qualify" requires a non-empty
  // answer containing only requested ids (populated fixture: the ids are real catalogue ids).
  validate(data, actor, request, ctx) {
    if (!Array.isArray(data) || data.length > 500 || !data.every((x) => Number.isInteger(x.id))) return false;
    if (ctx?.mode !== "qualify") return true;
    const m = decodeURIComponent(request?.path ?? "").match(/id=in\.\(([^)]*)\)/);
    if (!m) return false;
    const asked = new Set(m[1].split(",").map(Number));
    return data.length >= 1 && data.every((x) => asked.has(x.id));
  },
};
```
- Combined workload line (`scripts/load/workloads/tracker-gaps-combined.js`): `"export-mal-id-lookup": 0.2`.
- Qualification arithmetic (F3.1c preflight): 0.2 rps × 600 s = 120 expected completions ≥ 100; ÷ 3 covered subgroups = 40 ≥ 30. A shorter run is refused by the preflight; a run with drops below those numbers reports `insufficient`, never `pass`. The run id of an owner-approved `--qualify` run is what Task 8's acceptance record cites for the `@load` scenario.
- [ ] **Step 1: failing test** `scripts/load/profiles/export-mal-id-lookup.test.js`:
```js
test("export-mal-id-lookup is a Browse-class GET of at most 500 ids at 0.2 rps", () => {
  const before = JSON.stringify(W.WEIGHTS);
  const p = W.loadProfiles()["export-mal-id-lookup"];
  assert.equal(p.budgetClass, "browse"); assert.equal(p.ratePerSecond, 0.2); assert.ok(!("weight" in p));
  assert.equal(W.selectProfiles({ names: ["export-mal-id-lookup"] }).limits["export-mal-id-lookup"], 750);
  assert.equal(W.loadWorkload("tracker-gaps-combined").profiles["export-mal-id-lookup"], 0.2);
  const fixture = { media: { anime: Array.from({ length: 2000 }, (_, i) => i + 1), manga: [1, 2] } };
  const core = { requestFor: W.requestFor, validateResponse: W.validateResponse, ORIGIN: W.ORIGIN, now: () => new Date(0) };
  for (let seq = 0; seq < 8; seq++) {
    const r = p.request({ librarySize: 2000 }, fixture, seq, Math.random, core);
    assert.equal(r.method, "GET"); assert.equal(r.body, undefined); assert.notEqual(r.anonymous, true);
    const ids = decodeURIComponent(r.path).match(/id=in\.\(([^)]*)\)/)[1].split(",");
    assert.ok(ids.length >= 1 && ids.length <= 500);
  }
  const req = p.request({ librarySize: 2000 }, fixture, 0, Math.random, core);
  const firstId = Number(decodeURIComponent(req.path).match(/id=in\.\(([^)]*)\)/)[1].split(",")[0]);
  const wiring = { mode: "wiring" }, qualify = { mode: "qualify" };
  assert.ok(p.validate([{ id: firstId }], {}, req, qualify));
  assert.ok(!p.validate({}, {}, req, wiring)); assert.ok(p.validate([], {}, req, wiring));   // wiring mode: empty is accepted
  for (const e of p.emptyExamples) assert.ok(!p.validate(e, {}, req, qualify));
  assert.ok(!p.validate([{ id: -1 }], {}, req, qualify));
  assert.equal(JSON.stringify(W.WEIGHTS), before); assert.ok(!("export-mal-id-lookup" in W.WEIGHTS));  // base mix untouched
});
```
(`const W = require("../backend_workload.js")` is fine in the test file; only profile files must not require it.)
- [ ] **Step 2:** `node --test scripts/load/profiles/export-mal-id-lookup.test.js` → FAIL: `Cannot read properties of undefined (reading 'budgetClass')` (the profile does not exist).
- [ ] **Step 3:** implement the profile file and add its line to `tracker-gaps-combined.js`.
- [ ] **Step 4:** `bash scripts/quality-gates/test_load_profiles.sh` → PASS (F3's frozen-digest test unchanged; `combined workload names every profile with an explicit rate` passes with the new line).
- [ ] **Step 5: SQL-plan check (a plan check, not a red/green test: W2 changes no SQL).** Create `supabase/tests/rls/110_export_identity_lookup_plan.sql` (header `-- @requires table public.anime`, `-- @requires table public.manga`; `begin; … rollback;` like `102_load_hotpaths.sql`): insert 22,000 anime and 22,000 manga rows with `generate_series` (ids `9100000+n`, as 102 does), `analyze public.anime, public.manga`, then for each medium under `set local role anon` and `set local role authenticated` run `explain (analyze, format json) select id,anilist_id,mal_id,title_english,title_romaji,title_native from public.<medium> where id = any(<500 of the generated ids>)` into a temp table and assert `tests.ok('identity lookup uses the primary key', <plan text contains anime_pkey / manga_pkey and no "Seq Scan">)` and `tests.ok('lookup returns 500 rows', <top-level "Actual Rows" = 500>)`. Negative control (F3.2 pair, so the positive check means something): inside the same transaction `alter table public.<medium> drop constraint <medium>_pkey cascade;` (rolled back) and assert the same plan no longer names `<medium>_pkey`. Run `scripts/db/run_local_db_tests.sh --only 110_export` → PASS; copy the JSON plans into `identity-lookup-plan.md`.
- [ ] **Step 6:** `git add scripts/load/profiles/export-mal-id-lookup.js scripts/load/profiles/export-mal-id-lookup.test.js scripts/load/workloads/tracker-gaps-combined.js supabase/tests/rls/110_export_identity_lookup_plan.sql docs/tracker-gaps-2026-11/W2-export/identity-lookup-plan.md && git commit -m "W2: export-mal-id-lookup load profile and plan check"`

### Task 8: Baseline, docs, full verification, evidence

**Files:** extend `KuroTests/LibraryExportFlowTests.swift`; create `docs/tracker-gaps-2026-11/W2-export/baseline.md`, `docs/tracker-gaps-2026-11/W2-export/EVIDENCE.md`; modify `CURRENT_APP_STATE.md`, `CURRENT_APP_STATE_PLAIN.md`, `IMPLEMENTATION_PLAN_Variation1.md`, `~/.claude/projects/-Users-max-Kuro-Anime-App/memory/MEMORY.md`.

- [ ] **Step 1:** add `@Test func twoThousandTitleExportBaseline()` (2,000 entries, all three formats, cached identities; measures `ContinuousClock` duration of `export(_:)` per format and records it with `#expect(duration < .seconds(10))` as a sanity ceiling only). Run it three times on `7FC4B58A-430C-457D-A017-6B0095723F3F`; write the medians to `baseline.md`; propose the gate (spec: ≤ 2 s) for owner confirmation. Do not tighten the assertion until confirmed.
- [ ] **Step 2:** docs per Rule 1 (export feature, CSV/JSON contracts incl. formula neutralisation and list objects, MAL part files, new files, flag `library_export_v1` at 0 %, Change Log) and Rule 2 (memory: new files, counts, gotchas: no CDATA, zero-padded dates, `.repeating` not stored, sheet reads the owner not ProfileView, the public identity read is leased because its id set is account data, CSV `'` prefix is by design, providers return nil for "could not load"). Update the inventory sentences `check_docs_current_state.py` checks (app Swift: `CatalogStore+ExportIdentities`, `LibraryExportService`, `LibraryExportSheet`, `LibraryExportCopy`; package: 5 sources + 1 test; KuroTests +1); take the exact numbers from the script's expected text and recompute at merge time, then run `python3 scripts/quality-gates/check_docs_current_state.py` → `PASS`.
- [ ] **Step 2b: F1 turns blocking (spec §4: "WARN … until W2 lands, then blocking").** Create `scripts/quality-gates/bdd_landed.txt` with a header comment and the line `W2-export.feature`; in `run_all.sh` change `"bdd-traceability:check_bdd_traceability.sh:0"` to `:1`. Run `bash scripts/quality-gates/check_bdd_traceability.sh; echo "exit=$?"` → `0 unresolved` for W2, other features `pending (not landed)`, `exit=0`.
- [ ] **Step 3: gates.**
  - `cd Packages/KuroModules && swift test` → all pass.
  - `SKIP_IOS_BUILD=1 SKIP_IOS_TEST=1 scripts/quality-gates/run_all.sh` → green.
  - `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,id=7FC4B58A-430C-457D-A017-6B0095723F3F' test -only-testing:KuroTests` → all pass; warning count ≤ 60 unique Kuro-side.
  - `scripts/quality-gates/check_architecture.sh`, `check_navigation.sh`, `check_branded_states.sh` → 0 offenders.
  - `scripts/quality-gates/check_bdd_traceability.sh` → all 13 W2 scenarios resolved; run_all row `bdd-traceability PASS` (now blocking). "Resolved" proves each tag names an existing test, not that it passed (Step 3b).
  - `bash scripts/quality-gates/test_load_profiles.sh` → pass. `scripts/db/run_local_db_tests.sh` → no new failures (no migration in W2).
- [ ] **Step 3b: acceptance record (corrections brief item 6, F1.3).** After Step 3's runs, store each run's output under `docs/tracker-gaps-2026-11/acceptance/logs/W2-<run id>.txt`, start from `python3 scripts/quality-gates/check_bdd_traceability.py --record-template W2` and write `docs/tracker-gaps-2026-11/acceptance/W2.json` in F1.3's schema (`schemaVersion`, `workstream: "W2"` — the feature basename up to its first `-`, spec §4 — `testedCommit`, `recordedAt`, `runs[]` with `layer`/`command`/`context`/`exitCode`/`log`, `scenarios[]` with `feature`/`scenario`/`tag`/`result`/`run`, `unresolvedGates[]`), one scenario entry per W2 scenario (13). `@pkg`/`@swift` entries cite the Step 3 runs (`context.kind` `local` / `simulator` with the UUID); the `@load:export-mal-id-lookup` entry is `blocked` (or `insufficient`) until an owner-approved `--qualify` run exists, and is `pass` only with that run's report, `runKey` and cleanup report; `unresolvedGates` names it. Run `bash scripts/quality-gates/check_bdd_traceability.sh --accepted W2; echo "exit=$?"` → expected `exit=1` (`not accepted: blocked` for the load scenario only) until the qualification run; record the output in `EVIDENCE.md`. W2 is not called accepted before that check exits 0 on the tested HEAD. Commit order (F1.3 rule 2: HEAD may differ from `testedCommit` only under `docs/tracker-gaps-2026-11/acceptance/`, with a clean tree): make Step 5's commit first, run Step 3 on that clean commit, then commit only the record and its logs: `git add docs/tracker-gaps-2026-11/acceptance/W2.json docs/tracker-gaps-2026-11/acceptance/logs/ && git commit -m "W2: acceptance record"`.
- [ ] **Step 4:** `EVIDENCE.md`: test names with red/green output excerpts, the MAL element list from a real export, baseline, plan check, open owner questions.
- [ ] **Step 5:** `git add docs/tracker-gaps-2026-11/W2-export CURRENT_APP_STATE.md CURRENT_APP_STATE_PLAIN.md IMPLEMENTATION_PLAN_Variation1.md KuroTests/LibraryExportFlowTests.swift scripts/quality-gates/bdd_landed.txt scripts/quality-gates/run_all.sh && git commit -m "W2: export docs, baseline and evidence"` (memory lives outside the repo; update it, do not stage it).

## Owner / lead questions
- O1 (F2), resolved at plan review: F2.1 pins zero-padded `YYYY-00-00` / `YYYY-MM-00` acceptance (`acceptsEveryStoredImportForm`) and value equality (`equalityIsByValueNotSpelling`).
- O2 (F3), resolved at plan review: GET requests and the per-profile `validate` are F3.1b / F3.1.
- O3, resolved by the owner-approved corrections brief (2026-11-09): neutralise. CSV cells starting with `=`, `+`, `-`, `@`, TAB or CR get a leading `'` (OWASP); documented; JSON keeps the exact text. Pinned by `csvNeutralisesFormulaCellsAndJsonKeepsExactText`.
- O4: the Profile row stays behind `library_export_v1` (0 %) until the capacity qualification passes, per the program plan, although the lookup is ≤ 5 on-demand reads per export. The service checks the same flag before any request (`flagOffSendsNoRequest`).
- O5 (lead, W9 coordination), resolved in `09-lists.md` W9.5/W9.6 and `00-program.md`: W9 adds `CustomListsStore.exportLists() -> [ExportCustomList]?` (plain `MediaKey` items; W2 derives `position`, `in_library` and `title`; ordered lists with `createdAt`, items in manual order, empty lists and items outside the library included) and its flag accessor `FeatureFlags.libraryOrganiseV1Enabled`; `00-program.md`'s W2 ↔ W9 wiring row should read `LibraryExportService(tagsByKey:customLists:)`.
- O6 (lead, W4): W4's unresolved-titles CSV could reuse `LibraryExport.csvSafeText` if the same neutralisation is wanted there; W2 does not change `RFC4180`.
