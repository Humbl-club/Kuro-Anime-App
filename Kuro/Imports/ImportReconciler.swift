import Foundation
import KuroCore
import KuroLibrary

// MARK: - Import reconciliation (Add / Update / Skip)
// The one set of rules behind both import surfaces: the Concierge import review (`ConciergeView`) and
// the Profile AniList import (`ProfileView`). Pure: parse items, the chosen candidates and a read of the
// Library projection in, decisions and `concierge-apply` items out; no SwiftUI, no SDK, no I/O.
//
// - Tracked = the server OR the Library: a title counts as already tracked when the parse's
//   `existing_entry` (the server's row, raw `list_type`) OR the Library (`LibraryStore.entry(for:)`, typed
//   `MediaKey`) has it. Neither source alone is enough: the Library is empty while a new device's first
//   load runs (and after a failed load), and a parse answer can predate a Library change.
//   `prepared(_:existing:)` keeps the server's copy when present and otherwise fills in the Library's
//   entry for the top candidate (the server's own lookup rule: top candidate scoring >= 0.60), so the
//   review card, the item action and the auto-apply gate read the same entry. The apply items are
//   reconciled again at confirm time against the SELECTED candidate's key (the user may have picked
//   another title than the top one).
// - Library load state (E6c1): the lookup is load-state aware (`LibraryKnowledge`: tracked / untracked /
//   unknown). The views pass the named adapter `libraryLookup(library)` (the store's
//   `entry(for: LibraryKnowledgeQuery)`, pinned by a declared type in one place, never by overload
//   resolution at the call sites). While the bound account's rows are not loaded, a title the
//   projection does not hold is UNKNOWN, never "not tracked": such a line is sent as an Update only when the server says
//   tracked, as an Add only when it is exactly the title the server looked up (top candidate >= 0.60)
//   and found untracked, and otherwise left out (needs the loaded Library: confirm again). No auto-apply
//   while a line is unknown (`shouldAutoApply(_:existing:)`). Apply gate (E8): the import surfaces start
//   `concierge-apply` only while `canApply(loadState:)` holds (the Library is loaded for the current
//   account); a confirm before that asks the user to try again while the Library refreshes.
// - Item action: `.add` without an entry, `.update` when status (compared in the medium's vocabulary),
//   progress or rating differ, `.skip` when the line changes nothing. The parse has no notes field, so
//   notes can never differ.
// - Auto-apply (CLAUDE.md): only when EVERY item's top candidate scores >= 0.85, no item has ambiguous
//   adaptations and no item is already in the library.
// - Review decisions (E6, moved out of the views): one pre-selection (top candidate >= 0.60 and not
//   ambiguous) behind `initialSelectionsFirstParse` / `initialSelectionsClarificationReparse`, and one
//   auto-apply decision (apply at once, nothing to apply, or review; composed from the gates above)
//   behind `conciergeAutoApplyPlan` / `profileImportPlan`. The named entry points carry the two
//   PRESERVED pre-existing differences between the surfaces (ambiguous lines' action on the first
//   parse; parser ambiguity blocking only the Profile auto-apply), pending an owner decision.
// - Apply item: `status` is required by `concierge-apply` (old and new edge); a line that states no status
//   keeps the STORED status of an existing entry (never PLANNING over it; the expected stored state is the
//   server's raw `list_type` when the parse had the row). Apply v26 writes only fields it is given, so
//   stored rating/notes are NOT resent (`sendsStoredRatingAndNotes == false`).
// - Duplicates: repeated lines (equal item ids) are reviewed once; two lines that resolve to the same title
//   (same `MediaKey`) produce ONE apply item, the later line winning. Anime 7 and manga 7 never mix.

/// What an import line does to the library.
enum ImportItemAction: String, Sendable {
    case add
    case update
    case skip
}

/// Field-level difference between a stored entry and a parsed import line.
struct ImportDiff: Sendable, Equatable {
    struct FieldDiff<T: Sendable & Equatable>: Sendable, Equatable {
        let from: T
        let to: T
    }
    var status: FieldDiff<String>?
    var progressEpisodes: FieldDiff<Int>?
    var progressChapters: FieldDiff<Int>?
    var progressVolumes: FieldDiff<Int>?
    var rating: FieldDiff<Int?>?

    var isEmpty: Bool {
        status == nil && progressEpisodes == nil && progressChapters == nil && progressVolumes == nil && rating == nil
    }
}

/// One item of the `concierge-apply` request, as decided by `ImportReconciler`.
struct ImportApplyItem: Sendable, Equatable {
    /// The state the client expects the stored row to have (`concierge-apply` TOCTOU check).
    struct ExpectedExisting: Sendable, Equatable {
        let status: String
        let progressEpisodes: Int?
        let progressChapters: Int?
    }

    let raw: String
    let key: MediaKey
    /// `.add` or `.update` (a skipped line produces no apply item).
    let action: ImportItemAction
    /// Database vocabulary (WATCHING / READING / PLANNING / COMPLETED / DROPPED / PAUSED).
    let status: String
    let confidence: Double
    var progressEpisodes: Int? = nil
    var progressChapters: Int? = nil
    var progressVolumes: Int? = nil
    var seasonNumber: Int? = nil
    var episodeInSeason: Int? = nil
    var caughtUp: Bool? = nil
    var lastEpisode: Bool? = nil
    var completed: Bool? = nil
    /// The parsed rating, or the stored one sent back unchanged.
    var rating: Double? = nil
    /// The stored notes sent back unchanged (the parse never carries notes).
    var notes: String? = nil
    var expectedExisting: ExpectedExisting? = nil

    /// The JSON object `ImportsService.conciergeApply(items:)` sends (same keys as before).
    var payload: [String: Any] {
        var payload: [String: Any] = [
            "raw": raw,
            "mediaType": key.kind == .manga ? "MANGA" : "ANIME",
            "mediaId": key.id,
            "status": status,
            "confidence": confidence,
            "action": action.rawValue,
        ]
        if let progressEpisodes { payload["progressEpisodes"] = progressEpisodes }
        if let progressChapters { payload["progressChapters"] = progressChapters }
        if let progressVolumes { payload["progressVolumes"] = progressVolumes }
        if let seasonNumber { payload["seasonNumber"] = seasonNumber }
        if let episodeInSeason { payload["episodeInSeason"] = episodeInSeason }
        if let caughtUp { payload["caughtUp"] = caughtUp }
        if let lastEpisode { payload["lastEpisode"] = lastEpisode }
        if let completed { payload["completed"] = completed }
        if let rating { payload["rating"] = rating }
        if let notes { payload["notes"] = notes }
        if let expectedExisting {
            var expected: [String: Any] = ["status": expectedExisting.status]
            if let episodes = expectedExisting.progressEpisodes { expected["progress_episodes"] = episodes }
            if let chapters = expectedExisting.progressChapters { expected["progress_chapters"] = chapters }
            payload["expectedExisting"] = expected
        }
        return payload
    }
}

/// The review's starting state for a parse (`ImportReconciler.initialSelectionsFirstParse(for:)` /
/// `initialSelectionsClarificationReparse(for:)`).
struct ImportPreselection {
    /// Item id -> the pre-selected top candidate.
    var selections: [String: ConciergeCandidate] = [:]
    /// Item id -> the action the review shows (Add / Update / Skip).
    var actions: [String: ImportItemAction] = [:]
    /// Items left unselected because their adaptations are ambiguous (top candidate >= 0.60), in parse
    /// order: the on-device disambiguation may pick one.
    var ambiguousItems: [ConciergeParseItem] = []
}

/// What an import does once no clarification is asked (`ImportReconciler.conciergeAutoApplyPlan` /
/// `profileImportPlan`).
enum ImportAutoApplyPlan: Equatable {
    /// Apply these items at once, without the confirm step. `omitted` is how many more resolved
    /// titles were not sent because Apply accepts at most `ImportReconciler.applyItemLimit`.
    case apply(items: [ImportApplyItem], omitted: Int)
    /// The gate is open but no item is left to apply (every line excluded).
    case nothingToApply
    /// The import goes through the review (confirm step).
    case review
}

enum ImportReconciler {
    /// Minimum top-candidate score for auto-apply (inclusive).
    static let autoApplyMinimumScore = 0.85
    /// Minimum top-candidate score for pre-selection and for the existing-entry lookup (inclusive).
    static let preselectMinimumScore = 0.60

    /// A load-state-aware read of the Library projection (`LibraryStore.entry(for: LibraryKnowledgeQuery)`;
    /// the views pass `libraryLookup(library)`).
    typealias LibraryLookup = (LibraryKnowledgeQuery) -> LibraryKnowledge

    /// The import surfaces' lookup over `library`: its load-state-aware read (tracked / untracked /
    /// unknown), never the plain projection read `entry(for: MediaKey)` that cannot tell "not loaded"
    /// from "not tracked". The one place that names the overload (the query's declared type selects it).
    static func libraryLookup(_ library: LibraryStore) -> LibraryLookup {
        { (query: LibraryKnowledgeQuery) -> LibraryKnowledge in library.entry(for: query) }
    }

    // MARK: Identity

    /// The candidate's typed key ("ANIME" / "MANGA", any case); nil for anything else.
    static func mediaKey(of candidate: ConciergeCandidate) -> MediaKey? {
        switch candidate.media_type.lowercased() {
        case "anime": return MediaKey(kind: .anime, id: candidate.media_id)
        case "manga": return MediaKey(kind: .manga, id: candidate.media_id)
        default: return nil
        }
    }

    // MARK: Preparation (duplicates + existing entries)

    /// The parse response with repeated lines removed (first occurrence kept; equal ids carry equal
    /// text). Every item's `existing_entry` is the server's copy when the parse reported one, otherwise the
    /// Library's entry of the item's top candidate when it scores >= `preselectMinimumScore`, otherwise
    /// none: a line is tracked when EITHER source has the row.
    static func prepared(_ response: ConciergeParseResponse, existing: LibraryLookup) -> ConciergeParseResponse {
        var seen = Set<String>()
        let items = response.items
            .filter { seen.insert($0.id).inserted }
            .map { rebased($0, existing: existing) }
        return ConciergeParseResponse(success: response.success, userId: response.userId, items: items)
    }

    static func rebased(_ item: ConciergeParseItem, existing: LibraryLookup) -> ConciergeParseItem {
        var entry: ConciergeExistingEntry? = item.existing_entry
        if entry == nil, let top = item.candidates.first, top.score >= preselectMinimumScore,
           let key = mediaKey(of: top), let stored = existing(LibraryKnowledgeQuery(key)).entry {
            entry = existingEntry(stored)
        }
        return ConciergeParseItem(
            raw: item.raw,
            normalized: item.normalized,
            parsed: item.parsed,
            candidates: item.candidates,
            candidateError: item.candidateError,
            existing_entry: entry,
            ambiguity: item.ambiguity
        )
    }

    /// The review card's shape of a Library entry (progress in the medium's own unit).
    static func existingEntry(_ entry: LibraryEntry) -> ConciergeExistingEntry {
        let isManga = entry.key.kind == .manga
        return ConciergeExistingEntry(
            media_type: isManga ? "MANGA" : "ANIME",
            media_id: entry.key.id,
            status: storedStatus(entry.status, kind: entry.key.kind),
            progress_episodes: isManga ? nil : entry.progress,
            progress_chapters: isManga ? entry.progress : nil,
            progress_volumes: nil,
            rating: entry.rating?.value,
            updated_at: ISO8601DateFormatter().string(from: entry.updatedAt)
        )
    }

    // MARK: Adaptation ambiguity

    /// True when the two best candidates are different titles with the same base title (e.g. two
    /// adaptations) and the text did not name the top one's year.
    static func hasAmbiguousAdaptations(candidates: [ConciergeCandidate], yearMention: Int?) -> Bool {
        guard candidates.count >= 2 else { return false }

        let top = candidates[0]
        let second = candidates[1]

        guard top.media_id != second.media_id else { return false }

        let baseTop = strippedBaseTitle(top.title_raw)
        let baseSecond = strippedBaseTitle(second.title_raw)
        guard baseTop == baseSecond else { return false }

        if let mentioned = yearMention, let topYear = top.year, topYear == mentioned {
            return false
        }

        return true
    }

    static func strippedBaseTitle(_ raw: String) -> String {
        var title = raw
        if let range = title.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) {
            title.removeSubrange(range)
        }
        if let range = title.range(of: ": ") {
            title = String(title[title.startIndex..<range.lowerBound])
        }
        return title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: Diff and action

    /// What the parsed line would change on the stored entry; nil when nothing. Statuses are compared in
    /// the medium's vocabulary (a manga "watching" line on a READING row changes nothing); `to` is the
    /// status that is sent.
    static func diff(existing: ConciergeExistingEntry, parsed: ConciergeParseItemParsed) -> ImportDiff? {
        var diff = ImportDiff()

        let kind: MediaKind = existing.media_type.lowercased() == "manga" ? .manga : .anime
        if let parsedStatus = normalizedStatus(parsed.status, kind: kind),
           parsedStatus != normalizedStatus(existing.status, kind: kind) {
            diff.status = ImportDiff.FieldDiff(from: existing.status, to: parsedStatus)
        }
        if let episodes = parsed.progressEpisodes,
           episodes != (existing.progress_episodes ?? 0) {
            diff.progressEpisodes = ImportDiff.FieldDiff(from: existing.progress_episodes ?? 0, to: episodes)
        }
        if let chapters = parsed.progressChapters,
           chapters != (existing.progress_chapters ?? 0) {
            diff.progressChapters = ImportDiff.FieldDiff(from: existing.progress_chapters ?? 0, to: chapters)
        }
        if let volumes = parsed.progressVolumes,
           volumes != (existing.progress_volumes ?? 0) {
            diff.progressVolumes = ImportDiff.FieldDiff(from: existing.progress_volumes ?? 0, to: volumes)
        }
        if let rating = parsedRating(parsed), rating != existing.rating {
            diff.rating = ImportDiff.FieldDiff(from: existing.rating, to: rating)
        }

        return diff.isEmpty ? nil : diff
    }

    /// The parsed rating as the edge stores it (floored); nil outside the database scale 1...10.
    static func parsedRating(_ parsed: ConciergeParseItemParsed) -> Int? {
        guard let rating = parsed.rating, rating.isFinite else { return nil }
        let floored = Int(rating.rounded(.down))
        return (1...10).contains(floored) ? floored : nil
    }

    /// Add / Update / Skip of a prepared item (its `existing_entry` is the Library's).
    static func action(for item: ConciergeParseItem) -> ImportItemAction {
        guard let existing = item.existing_entry else { return .add }
        if let diff = diff(existing: existing, parsed: item.parsed), !diff.isEmpty { return .update }
        return .skip
    }

    // MARK: Auto-apply

    /// One prepared item qualifies when its top candidate scores >= 0.85, its adaptations are not
    /// ambiguous and the title is not in the library yet.
    static func qualifiesForAutoApply(_ item: ConciergeParseItem) -> Bool {
        guard item.existing_entry == nil, let top = item.candidates.first else { return false }
        return top.score >= autoApplyMinimumScore
            && !hasAmbiguousAdaptations(candidates: item.candidates, yearMention: item.parsed.yearMention)
    }

    /// Auto-apply only when there is something to apply, EVERY prepared item qualifies, and the Library
    /// knows every item's top title: never while one is unknown (its rows are not loaded for the current
    /// account), so a line that might be tracked always goes through the confirm step. The import
    /// surfaces (ConciergeView, ProfileView) pass `libraryLookup(library)`.
    static func shouldAutoApply(_ items: [ConciergeParseItem], existing: LibraryLookup) -> Bool {
        !items.isEmpty && items.allSatisfy { qualifiesForAutoApply($0) } && items.allSatisfy { item in
            guard let top = item.candidates.first, let key = mediaKey(of: top) else { return false }
            return existing(LibraryKnowledgeQuery(key)) != .unknown
        }
    }

    // MARK: Pre-selection

    /// Pre-selection of the Concierge FIRST parse (`handleImportFlow`): see `initialSelections`. A line
    /// whose adaptations are ambiguous (top candidate >= 0.60) is listed for the on-device disambiguation
    /// and gets NO action, so the review groups it under Add even when it is tracked.
    /// PRESERVED pre-existing behavior (differs from `initialSelectionsClarificationReparse`), pending an
    /// owner decision: do not change it here.
    static func initialSelectionsFirstParse(for items: [ConciergeParseItem]) -> ImportPreselection {
        initialSelections(for: items, actionsForAmbiguousItems: false)
    }

    /// Pre-selection of the Concierge clarification RE-PARSE (`handleClarification`): see
    /// `initialSelections`. Every line gets its real action, ambiguous adaptations included.
    /// PRESERVED pre-existing behavior (differs from `initialSelectionsFirstParse`), pending an owner
    /// decision: do not change it here.
    static func initialSelectionsClarificationReparse(for items: [ConciergeParseItem]) -> ImportPreselection {
        initialSelections(for: items, actionsForAmbiguousItems: true)
    }

    /// The review's starting state for a prepared parse (both Concierge review paths, through the named
    /// entry points above): every item whose top candidate scores >= `preselectMinimumScore` and whose
    /// adaptations are not ambiguous has its top candidate selected; an item whose top candidate scores
    /// >= `preselectMinimumScore` but whose adaptations ARE ambiguous stays unselected and is listed for
    /// the on-device disambiguation. Every item gets its `action(for:)`, except that with
    /// `actionsForAmbiguousItems == false` a listed ambiguous item gets none. The view merges the result
    /// into its state (keys are only ever set, never removed).
    private static func initialSelections(
        for items: [ConciergeParseItem],
        actionsForAmbiguousItems: Bool
    ) -> ImportPreselection {
        var result = ImportPreselection()
        for item in items {
            if let top = item.candidates.first, top.score >= preselectMinimumScore {
                if hasAmbiguousAdaptations(candidates: item.candidates, yearMention: item.parsed.yearMention) {
                    result.ambiguousItems.append(item)
                    if !actionsForAmbiguousItems { continue }
                } else {
                    result.selections[item.id] = top
                }
            }
            result.actions[item.id] = action(for: item)
        }
        return result
    }

    // MARK: Auto-apply plan

    /// The auto-apply plan of the Concierge first parse once no clarify card is shown: see
    /// `autoApplyPlan`. A line's PARSER ambiguity blocks auto-apply here too (locked product rule:
    /// ambiguous "I watched X" does not auto-apply when `clarify_v2` is off; same rule as Profile).
    /// Ambiguous ADAPTATIONS still block via `shouldAutoApply`.
    static func conciergeAutoApplyPlan(
        for items: [ConciergeParseItem],
        loadState: LibraryStore.LoadState,
        excluded: Set<String> = [],
        existing: LibraryLookup
    ) -> ImportAutoApplyPlan {
        autoApplyPlan(for: items, parserAmbiguityBlocks: true, loadState: loadState, excluded: excluded, existing: existing)
    }

    /// The auto-apply plan of the Profile AniList import: see `autoApplyPlan`. ANY parser ambiguity forces
    /// review (the Profile has no clarify card; the review happens in Concierge). Same locked rule as
    /// `conciergeAutoApplyPlan`.
    static func profileImportPlan(
        for items: [ConciergeParseItem],
        loadState: LibraryStore.LoadState,
        excluded: Set<String> = [],
        existing: LibraryLookup
    ) -> ImportAutoApplyPlan {
        autoApplyPlan(for: items, parserAmbiguityBlocks: true, loadState: loadState, excluded: excluded, existing: existing)
    }

    /// The one auto-apply decision behind both import surfaces (through the named entry points above),
    /// in this order:
    /// 1. `parserAmbiguityBlocks` and any line carries a parser ambiguity -> `.review`;
    /// 2. the Library is not loaded for this account (`canApply`) -> `.review`;
    /// 3. not every item qualifies (`shouldAutoApply`) -> `.review`;
    /// 4. an item without a candidate -> `.review`;
    /// 5. the apply items for the top candidates (their `action(for:)`, `excluded` left out) are empty ->
    ///    `.nothingToApply` (Concierge then shows nothing more, Profile reviews);
    /// 6. otherwise `.apply` with those items.
    private static func autoApplyPlan(
        for items: [ConciergeParseItem],
        parserAmbiguityBlocks: Bool,
        loadState: LibraryStore.LoadState,
        excluded: Set<String> = [],
        existing: LibraryLookup
    ) -> ImportAutoApplyPlan {
        if parserAmbiguityBlocks, items.contains(where: { $0.ambiguity != nil }) {
            return .review
        }
        guard canApply(loadState: loadState), shouldAutoApply(items, existing: existing) else {
            return .review
        }

        var selections: [String: ConciergeCandidate] = [:]
        var actions: [String: ImportItemAction] = [:]
        for item in items {
            guard let top = item.candidates.first else { return .review }
            selections[item.id] = top
            actions[item.id] = action(for: item)
        }

        let chosen = applyBatch(
            for: items,
            selections: selections,
            excluded: excluded,
            actions: actions,
            existing: existing
        )
        return chosen.items.isEmpty ? .nothingToApply : .apply(items: chosen.items, omitted: chosen.omitted)
    }

    // MARK: Apply gate

    /// Whether an import may be applied now: only once the Library holds the current account's rows
    /// (`LibraryStore.loadState == .loaded`; the store resets it on every new account binding, so a
    /// loaded state is always the current account's). Not loaded, loading or failed: the import
    /// surfaces never start `concierge-apply` (a line that looks untracked may be tracked, and a picked
    /// title the server did not look up would be left out); the confirm step asks the user to try
    /// again while the Library refreshes.
    static func canApply(loadState: LibraryStore.LoadState) -> Bool {
        loadState == .loaded
    }

    // MARK: Apply items

    /// The `concierge-apply` items for the chosen candidates. Items without a candidate, excluded by the
    /// user or shown as `.skip` are left out. Each item is reconciled against its SELECTED candidate:
    /// tracked when the prepared item's entry is that title's (server copy or Library at parse time) or
    /// the Library has it now -> `.update` with the expected stored state, otherwise `.add`. While the
    /// Library does not know the title (not loaded), an untracked-looking line is an `.add` only when the
    /// server looked up exactly that title (`serverLookedUp`); otherwise it is left out (it may be
    /// tracked: never an Add over an unknown row). Lines resolving to the same title collapse into one
    /// item (the later line wins). Apply accepts at most `applyItemLimit` items (AniList may return 200);
    /// the rest are omitted and the surfaces say they were not added.
    static let applyItemLimit = 100

    /// One Apply batch: the first `applyItemLimit` resolved rows, and how many more were not sent.
    struct ApplyBatch: Sendable, Equatable {
        let items: [ImportApplyItem]
        let omitted: Int
    }

    static func applyBatch(
        for items: [ConciergeParseItem],
        selections: [String: ConciergeCandidate],
        excluded: Set<String> = [],
        actions: [String: ImportItemAction],
        existing: LibraryLookup
    ) -> ApplyBatch {
        var result: [ImportApplyItem] = []
        var indexByKey: [MediaKey: Int] = [:]
        for item in items {
            guard let candidate = selections[item.id], !excluded.contains(item.id) else { continue }
            guard (actions[item.id] ?? .add) != .skip else { continue }
            guard let key = mediaKey(of: candidate) else { continue }

            let reviewed = item.existing_entry.flatMap { entryKey(of: $0) == key ? $0 : nil }
            let knowledge = existing(LibraryKnowledgeQuery(key))
            // Unknown to the Library and not answered by the server: never an Add (it may be tracked).
            // Defensive: the import surfaces call this only when `canApply(loadState:)` holds, and then
            // no title is unknown; the rule stays so a caller without the gate still never sends one.
            if reviewed == nil, knowledge == .unknown, !serverLookedUp(item, key: key) { continue }
            let applyItem = makeApplyItem(item, candidate: candidate, key: key, reviewed: reviewed, live: knowledge.entry)
            if let index = indexByKey[key] {
                result[index] = applyItem
            } else {
                indexByKey[key] = result.count
                result.append(applyItem)
            }
        }
        let omitted = max(0, result.count - applyItemLimit)
        return ApplyBatch(items: Array(result.prefix(applyItemLimit)), omitted: omitted)
    }

    static func applyItems(
        for items: [ConciergeParseItem],
        selections: [String: ConciergeCandidate],
        excluded: Set<String> = [],
        actions: [String: ImportItemAction],
        existing: LibraryLookup
    ) -> [ImportApplyItem] {
        applyBatch(for: items, selections: selections, excluded: excluded, actions: actions, existing: existing).items
    }

    /// Copy for "N titles were not added" when AniList/parse produced more than Apply accepts.
    static func omittedApplyCopy(omitted: Int, german: Bool) -> String? {
        guard omitted > 0 else { return nil }
        return german
            ? "\(omitted) weitere Titel wurden nicht hinzugefügt (Apply nimmt höchstens \(applyItemLimit))."
            : "\(omitted) more titles were not added (Apply accepts at most \(applyItemLimit))."
    }

    /// Whether `concierge-parse` looked up `key` for this line: the server checks only the top candidate,
    /// and only when it scores >= `preselectMinimumScore`. Its lookup is best effort (a failed lookup
    /// also reports no entry).
    static func serverLookedUp(_ item: ConciergeParseItem, key: MediaKey) -> Bool {
        guard let top = item.candidates.first, top.score >= preselectMinimumScore else { return false }
        return mediaKey(of: top) == key
    }

    /// - `reviewed`: the entry the review showed for this title (the server's raw row when the parse had
    ///   one); its status and progress are the expected stored state, so a row that changed since the
    ///   review is reported as a conflict by `concierge-apply` instead of being overwritten.
    /// - `live`: the Library's entry now (the only source for the notes).
    private static func makeApplyItem(
        _ item: ConciergeParseItem,
        candidate: ConciergeCandidate,
        key: MediaKey,
        reviewed: ConciergeExistingEntry?,
        live: LibraryEntry?
    ) -> ImportApplyItem {
        let parsed = item.parsed
        let expected: ImportApplyItem.ExpectedExisting?
        if let reviewed {
            expected = ImportApplyItem.ExpectedExisting(
                status: reviewed.status,
                progressEpisodes: reviewed.progress_episodes,
                progressChapters: reviewed.progress_chapters
            )
        } else if let live {
            expected = ImportApplyItem.ExpectedExisting(
                status: storedStatus(live.status, kind: key.kind),
                progressEpisodes: key.kind == .anime ? live.progress : nil,
                progressChapters: key.kind == .manga ? live.progress : nil
            )
        } else {
            expected = nil
        }
        var applyItem = ImportApplyItem(
            raw: item.raw,
            key: key,
            action: expected == nil ? .add : .update,
            status: statusToSend(parsed: parsed.status, kind: key.kind, storedStatus: expected?.status),
            confidence: candidate.score,
            progressEpisodes: parsed.progressEpisodes,
            progressChapters: parsed.progressChapters,
            progressVolumes: parsed.progressVolumes,
            seasonNumber: parsed.seasonNumber,
            episodeInSeason: parsed.episodeInSeason,
            caughtUp: parsed.caughtUp,
            lastEpisode: parsed.lastEpisode,
            completed: parsed.completed,
            rating: parsed.rating
        )
        if expected != nil, sendsStoredRatingAndNotes {
            if applyItem.rating == nil {
                applyItem.rating = (live?.rating?.value ?? reviewed?.rating).map { Double($0) }
            }
            if !writesSeasonNote(parsed, kind: key.kind) {
                applyItem.notes = live?.notes
            }
        }
        applyItem.expectedExisting = expected
        return applyItem
    }

    /// DEPLOYMENT SWITCH (E7): Apply v26 writes only the fields it is given, so an update must NOT send
    /// a stored rating/notes back (a stale local copy would overwrite a newer server value, and those
    /// fields would enter the Undo ledger). Kept as an explicit switch so a rollback of the edge can
    /// restore the old client shape without hunting call sites. `ImportReconcilerTests` (`applyItemRules`,
    /// `progressOnlyUpdateRequestShape`) pin the false shape.
    static let sendsStoredRatingAndNotes = false

    /// The typed key of an entry ("ANIME" / "MANGA", any case).
    static func entryKey(of entry: ConciergeExistingEntry) -> MediaKey? {
        switch entry.media_type.lowercased() {
        case "anime": return MediaKey(kind: .anime, id: entry.media_id)
        case "manga": return MediaKey(kind: .manga, id: entry.media_id)
        default: return nil
        }
    }

    /// Whether the deployed Apply writes its season note ("S{n}E{m}") for this line when no notes are
    /// sent: anime, a season number and an episode-in-season of at least 1. With
    /// `sendsStoredRatingAndNotes == false` the client never sends stored notes anyway; this stays as
    /// the pure rule the edge and the tests share for "S2E5"-style lines.
    static func writesSeasonNote(_ parsed: ConciergeParseItemParsed, kind: MediaKind) -> Bool {
        kind == .anime && parsed.seasonNumber != nil && (parsed.episodeInSeason ?? 0) >= 1
    }

    // MARK: Status

    /// The status `concierge-apply` receives (required by the old and the new edge): the line's own
    /// status when it states one; otherwise the STORED status of a tracked title (a progress-only update
    /// never moves it); PLANNING only for a title that is not tracked yet.
    static func statusToSend(parsed: String?, kind: MediaKind, storedStatus: String?) -> String {
        if let stated = normalizedStatus(parsed, kind: kind) { return stated }
        if let storedStatus { return storedStatus }
        return "PLANNING"
    }

    /// The parsed status in the medium's vocabulary (WATCHING for anime, READING for manga); nil when
    /// the line stated none.
    static func normalizedStatus(_ raw: String?, kind: MediaKind) -> String? {
        let status = (raw ?? "").uppercased()
        if kind == .manga, status == "WATCHING" { return "READING" }
        if kind == .anime, status == "READING" { return "WATCHING" }
        return status.isEmpty ? nil : status
    }

    /// Database vocabulary of a Library status (the mapping of `SupabaseLibraryBackend.dbListType`:
    /// `.current` and `.repeating` are stored as WATCHING / READING).
    static func storedStatus(_ status: ListStatus, kind: MediaKind) -> String {
        let isManga = kind == .manga
        switch status {
        case .current, .repeating: return isManga ? "READING" : "WATCHING"
        case .planning: return "PLANNING"
        case .completed: return "COMPLETED"
        case .dropped: return "DROPPED"
        case .paused: return "PAUSED"
        }
    }
}
