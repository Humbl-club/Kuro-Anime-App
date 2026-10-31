//
//  ImportReconcilerTests.swift
//  KuroTests
//
//  The import reconciliation rules shared by the Concierge import review and the Profile AniList
//  import (`ImportReconciler`, E6b-V): auto-apply gate (0.85 threshold, ambiguous adaptations,
//  already-tracked titles), Add / Update / Skip, the apply items `concierge-apply` receives (status
//  kept on a progress-only update, stored rating and notes sent back, expected stored state), duplicate
//  lines and anime/manga with equal ids. The existing entry is always the Library's.
//

import Testing
import Foundation
import KuroCore
import KuroLibrary
@testable import Kuro

@MainActor
@Suite("Imports: reconciliation rules (ImportReconciler)")
struct ImportReconcilerTests {

    // MARK: Fixtures

    static func candidate(
        _ kind: MediaKind,
        _ id: Int,
        score: Double = 0.95,
        title: String? = nil,
        year: Int? = nil
    ) -> ConciergeCandidate {
        ConciergeCandidate(
            media_type: kind == .manga ? "MANGA" : "ANIME",
            media_id: id,
            variant_type: "main",
            title_raw: title ?? "Title \(id)",
            score: score,
            year: year,
            format: nil,
            cover_image_medium: nil
        )
    }

    static func parsed(
        status: String? = nil,
        episodes: Int? = nil,
        chapters: Int? = nil,
        volumes: Int? = nil,
        season: Int? = nil,
        episodeInSeason: Int? = nil,
        yearMention: Int? = nil,
        rating: Double? = nil
    ) -> ConciergeParseItemParsed {
        ConciergeParseItemParsed(
            mediaTypeHint: nil,
            status: status,
            progressEpisodes: episodes,
            progressChapters: chapters,
            progressVolumes: volumes,
            seasonNumber: season,
            episodeInSeason: episodeInSeason,
            caughtUp: nil,
            lastEpisode: nil,
            completed: nil,
            yearMention: yearMention,
            rating: rating,
            progressTotal: nil,
            progressUnit: nil
        )
    }

    static func item(
        _ raw: String,
        parsed: ConciergeParseItemParsed? = nil,
        candidates: [ConciergeCandidate],
        serverExisting: ConciergeExistingEntry? = nil,
        ambiguity: ConciergeAmbiguity? = nil
    ) -> ConciergeParseItem {
        ConciergeParseItem(
            raw: raw,
            normalized: raw.lowercased(),
            parsed: parsed ?? Self.parsed(),
            candidates: candidates,
            candidateError: nil,
            existing_entry: serverExisting,
            ambiguity: ambiguity
        )
    }

    static func entry(
        _ kind: MediaKind,
        _ id: Int,
        status: ListStatus,
        progress: Int = 0,
        rating: Int? = nil,
        notes: String? = nil
    ) -> LibraryEntry {
        LibraryEntry(
            key: MediaKey(kind: kind, id: id),
            rowId: id,
            status: status,
            progress: progress,
            rating: rating.flatMap { UserRating(value: $0) },
            notes: notes,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    /// A loaded Library holding exactly `entries` (anything else is untracked).
    static func library(_ entries: [LibraryEntry]) -> ImportReconciler.LibraryLookup {
        let byKey = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0) })
        return { byKey[$0.key].map(LibraryKnowledge.tracked) ?? .untracked }
    }

    /// The parse response as the views hold it (prepared against `entries`).
    static func prepared(_ items: [ConciergeParseItem], library entries: [LibraryEntry] = []) -> [ConciergeParseItem] {
        ImportReconciler.prepared(
            ConciergeParseResponse(success: true, userId: "u", items: items),
            existing: library(entries)
        ).items
    }

    /// What the Concierge confirm sends: the top candidate selected, the actions shown, nothing excluded.
    static func applyItems(_ items: [ConciergeParseItem], library entries: [LibraryEntry]) -> [ImportApplyItem] {
        let ready = prepared(items, library: entries)
        var selections: [String: ConciergeCandidate] = [:]
        var actions: [String: ImportItemAction] = [:]
        for item in ready {
            selections[item.id] = item.candidates.first
            actions[item.id] = ImportReconciler.action(for: item)
        }
        return ImportReconciler.applyItems(for: ready, selections: selections, actions: actions, existing: library(entries))
    }

    // MARK: Auto-apply gate

    @Test("Auto-apply threshold is >= 0.85 on the top candidate (exact boundary)",
          arguments: [(0.8499, false), (0.85, true), (0.8501, true), (0.99, true)])
    func autoApplyThreshold(score: Double, expected: Bool) {
        let items = Self.prepared([Self.item("Frieren", candidates: [Self.candidate(.anime, 1, score: score)])])
        #expect(ImportReconciler.shouldAutoApply(items, existing: Self.library([])) == expected)
    }

    @Test("Auto-apply needs EVERY item to qualify; an empty parse never auto-applies")
    func autoApplyNeedsAllItems() {
        let strong = Self.item("A", candidates: [Self.candidate(.anime, 1, score: 0.99)])
        let weak = Self.item("B", candidates: [Self.candidate(.anime, 2, score: 0.8499)])
        let noCandidate = Self.item("C", candidates: [])
        #expect(ImportReconciler.shouldAutoApply(Self.prepared([strong]), existing: Self.library([])))
        #expect(!ImportReconciler.shouldAutoApply(Self.prepared([strong, weak]), existing: Self.library([])))
        #expect(!ImportReconciler.shouldAutoApply(Self.prepared([strong, noCandidate]), existing: Self.library([])))
        #expect(!ImportReconciler.shouldAutoApply([], existing: Self.library([])))
    }

    enum AdaptationCase: String, CaseIterable, Sendable {
        case sameBaseTitleDifferentIds
        case yearNamesTheTop
        case yearNamesTheOther
        case sameId
        case differentBaseTitles
        case singleCandidate

        var yearMention: Int? {
            switch self {
            case .yearNamesTheTop: return 2011
            case .yearNamesTheOther: return 1999
            default: return nil
            }
        }

        var ambiguous: Bool {
            switch self {
            case .sameBaseTitleDifferentIds, .yearNamesTheOther: return true
            default: return false
            }
        }
    }

    static func candidates(for adaptation: AdaptationCase) -> [ConciergeCandidate] {
        let tv2011 = candidate(.anime, 11061, score: 0.99, title: "Hunter x Hunter (2011)", year: 2011)
        let tv1999 = candidate(.anime, 136, score: 0.97, title: "Hunter x Hunter: The Series", year: 1999)
        switch adaptation {
        case .sameBaseTitleDifferentIds, .yearNamesTheTop, .yearNamesTheOther: return [tv2011, tv1999]
        case .sameId: return [tv2011, candidate(.anime, 11061, score: 0.9, title: "Hunter x Hunter")]
        case .differentBaseTitles: return [tv2011, candidate(.anime, 5, score: 0.9, title: "Hunter Street")]
        case .singleCandidate: return [tv2011]
        }
    }

    @Test("Ambiguous adaptations block auto-apply even at 0.99", arguments: AdaptationCase.allCases)
    func ambiguousAdaptationBlocksAutoApply(adaptation: AdaptationCase) {
        let item = Self.item(
            "Hunter x Hunter",
            parsed: Self.parsed(yearMention: adaptation.yearMention),
            candidates: Self.candidates(for: adaptation)
        )
        #expect(ImportReconciler.hasAmbiguousAdaptations(candidates: item.candidates, yearMention: adaptation.yearMention) == adaptation.ambiguous)
        #expect(ImportReconciler.shouldAutoApply(Self.prepared([item]), existing: Self.library([])) == !adaptation.ambiguous)
    }

    /// The parse's server copy of a row (`concierge-parse` `existing_entry`: the raw `list_type`).
    static func serverEntry(_ kind: MediaKind, _ id: Int, listType: String, progress: Int, rating: Int? = nil) -> ConciergeExistingEntry {
        ConciergeExistingEntry(
            media_type: kind == .manga ? "MANGA" : "ANIME",
            media_id: id,
            status: listType,
            progress_episodes: kind == .anime ? progress : nil,
            progress_chapters: kind == .manga ? progress : nil,
            progress_volumes: nil,
            rating: rating,
            updated_at: "2026-10-01T00:00:00Z"
        )
    }

    enum TrackedSource: String, CaseIterable, Sendable {
        /// A returning user on a new device: the Library is still loading (empty), the server knows the row.
        case serverOnlyWhileLibraryLoads
        /// A stale parse (cache or race): the server copy says untracked, the Library has the row.
        case libraryOnly
        case both
        case neither
    }

    @Test("Tracked = the server's existing_entry OR the Library: a tracked line never auto-applies and is an Update",
          arguments: TrackedSource.allCases)
    func trackedIsTheUnionOfServerAndLibrary(source: TrackedSource) throws {
        let server = Self.serverEntry(.anime, 7, listType: "COMPLETED", progress: 12, rating: 8)
        let local = Self.entry(.anime, 7, status: .completed, progress: 12, rating: 8, notes: "with Sam")
        let serverSays = source == .serverOnlyWhileLibraryLoads || source == .both
        let librarySays = source == .libraryOnly || source == .both
        let line = Self.item(
            "Frieren ep 13",
            parsed: Self.parsed(episodes: 13),
            candidates: [Self.candidate(.anime, 7, score: 0.99)],
            serverExisting: serverSays ? server : nil
        )
        let stored = librarySays ? [local] : []
        let ready = Self.prepared([line], library: stored)
        let tracked = source != .neither

        #expect((ready[0].existing_entry != nil) == tracked)
        #expect(ImportReconciler.shouldAutoApply(ready, existing: Self.library(stored)) == !tracked, "a tracked title is never auto-applied")
        #expect(ImportReconciler.action(for: ready[0]) == (tracked ? .update : .add))

        let applied = try #require(Self.applyItems([line], library: stored).first)
        #expect(applied.action == (tracked ? .update : .add))
        #expect(applied.status == (tracked ? "COMPLETED" : "PLANNING"), "the stored status is kept, never PLANNING over it")
        #expect(applied.expectedExisting?.status == (tracked ? "COMPLETED" : nil))
        #expect(applied.expectedExisting?.progressEpisodes == (tracked ? 12 : nil))
    }

    @Test("The expected stored status is the server's raw list_type (a manga row stored as WATCHING is no conflict)")
    func expectedStatusIsTheServersRawListType() throws {
        let server = Self.serverEntry(.manga, 9, listType: "WATCHING", progress: 30)
        let local = Self.entry(.manga, 9, status: .current, progress: 30)
        let line = Self.item("Berserk ch 31", parsed: Self.parsed(chapters: 31), candidates: [Self.candidate(.manga, 9)], serverExisting: server)

        for stored in [[local], []] {
            let applied = try #require(Self.applyItems([line], library: stored).first)
            #expect(applied.action == .update)
            #expect(applied.expectedExisting == ImportApplyItem.ExpectedExisting(status: "WATCHING", progressEpisodes: nil, progressChapters: 30))
            #expect(applied.status == "WATCHING", "the row's stored status, unchanged")
        }
    }

    @Test("Without a server copy the Library entry is looked up for a top candidate scoring >= 0.60")
    func libraryLookupBoundary() {
        let tracked = Self.entry(.anime, 7, status: .current, progress: 3)
        let fresh = Self.prepared([Self.item("A", candidates: [Self.candidate(.anime, 7)])], library: [tracked])
        #expect(fresh[0].existing_entry?.status == "WATCHING")
        #expect(fresh[0].existing_entry?.progress_episodes == 3)

        let weak = Self.prepared([Self.item("A", candidates: [Self.candidate(.anime, 7, score: 0.5999)])], library: [tracked])
        #expect(weak[0].existing_entry == nil)
        let atBoundary = Self.prepared([Self.item("A", candidates: [Self.candidate(.anime, 7, score: 0.60)])], library: [tracked])
        #expect(atBoundary[0].existing_entry != nil)
    }

    // MARK: Identity

    @Test("anime 42 and manga 42 stay distinct: lookup, action and apply items")
    func equalNumericIdsStayDistinct() {
        let manga42 = Self.entry(.manga, 42, status: .completed, progress: 120)
        let animeLine = Self.item("Anime 42 ep 3", parsed: Self.parsed(episodes: 3), candidates: [Self.candidate(.anime, 42)])
        let mangaLine = Self.item("Manga 42 ch 120", parsed: Self.parsed(chapters: 120), candidates: [Self.candidate(.manga, 42)])

        let ready = Self.prepared([animeLine, mangaLine], library: [manga42])
        #expect(ready[0].existing_entry == nil, "manga 42 is not anime 42")
        #expect(ImportReconciler.action(for: ready[0]) == .add)
        #expect(ImportReconciler.action(for: ready[1]) == .skip, "manga 42 already at ch 120")

        let applied = Self.applyItems([animeLine, mangaLine], library: [manga42])
        #expect(applied.map(\.key) == [MediaKey(kind: .anime, id: 42)])
        #expect(applied.first?.action == .add)
        #expect(applied.first?.expectedExisting == nil)

        // Both media with the same id in one import: two apply items, never collapsed.
        let both = Self.applyItems(
            [animeLine, Self.item("Manga 42 ch 5", parsed: Self.parsed(chapters: 5), candidates: [Self.candidate(.manga, 42)])],
            library: []
        )
        #expect(Set(both.map(\.key)) == [MediaKey(kind: .anime, id: 42), MediaKey(kind: .manga, id: 42)])
    }

    @Test("The SELECTED candidate is reconciled, not the top one")
    func selectedCandidateIsReconciled() {
        let animeTop = Self.entry(.anime, 1, status: .completed, progress: 24, rating: 9)
        let line = Self.item("Title", parsed: Self.parsed(chapters: 4), candidates: [Self.candidate(.anime, 1), Self.candidate(.manga, 2, score: 0.7)])
        let ready = Self.prepared([line], library: [animeTop])
        let picked = ImportReconciler.applyItems(
            for: ready,
            selections: [line.id: Self.candidate(.manga, 2, score: 0.7)],
            actions: [line.id: ImportReconciler.action(for: ready[0])],
            existing: Self.library([animeTop])
        )
        #expect(picked.count == 1)
        #expect(picked[0].key == MediaKey(kind: .manga, id: 2))
        #expect(picked[0].action == .add)
        #expect(picked[0].expectedExisting == nil, "anime 1's stored state is never sent for manga 2")
        #expect(picked[0].rating == nil)
    }

    // MARK: Apply items (production rules)

    enum ApplyCase: String, CaseIterable, Sendable {
        /// The confirmed defect: "Frieren ep 13" on a COMPLETED title used to send PLANNING.
        case progressOnlyUpdateKeepsAnimeStatus
        case progressOnlyUpdateKeepsMangaStatus
        case statedStatusIsSent
        case untrackedLineWithoutStatusIsPlanned
        case storedRatingAndNotesAreSentBack
        case parsedRatingWins
        case seasonNoteLineDoesNotSendStoredNotes
        case mangaWatchingIsReading
        case animeReadingIsWatching
    }

    static func stored(for rule: ApplyCase) -> [LibraryEntry] {
        switch rule {
        case .progressOnlyUpdateKeepsAnimeStatus:
            return [entry(.anime, 7, status: .completed, progress: 12, rating: 8, notes: "with Sam")]
        case .progressOnlyUpdateKeepsMangaStatus:
            return [entry(.manga, 7, status: .current, progress: 30)]
        case .statedStatusIsSent, .storedRatingAndNotesAreSentBack, .parsedRatingWins:
            return [entry(.anime, 7, status: .current, progress: 5, rating: 8, notes: "with Sam")]
        case .seasonNoteLineDoesNotSendStoredNotes:
            return [entry(.anime, 7, status: .current, progress: 5, notes: "with Sam")]
        case .untrackedLineWithoutStatusIsPlanned, .mangaWatchingIsReading, .animeReadingIsWatching:
            return []
        }
    }

    static func line(for rule: ApplyCase) -> ConciergeParseItem {
        let anime7 = [candidate(.anime, 7)]
        let manga7 = [candidate(.manga, 7)]
        switch rule {
        case .progressOnlyUpdateKeepsAnimeStatus:
            return item("Frieren ep 13", parsed: parsed(episodes: 13), candidates: anime7)
        case .progressOnlyUpdateKeepsMangaStatus:
            return item("Berserk ch 31", parsed: parsed(chapters: 31), candidates: manga7)
        case .statedStatusIsSent:
            return item("dropped Frieren", parsed: parsed(status: "dropped"), candidates: anime7)
        case .untrackedLineWithoutStatusIsPlanned:
            return item("Frieren", candidates: anime7)
        case .storedRatingAndNotesAreSentBack:
            return item("Frieren ep 6", parsed: parsed(episodes: 6), candidates: anime7)
        case .parsedRatingWins:
            return item("Frieren 9/10", parsed: parsed(rating: 9), candidates: anime7)
        case .seasonNoteLineDoesNotSendStoredNotes:
            return item(
                "Frieren S2E5",
                parsed: parsed(episodes: 33, season: 2, episodeInSeason: 5),
                candidates: anime7
            )
        case .mangaWatchingIsReading:
            return item("watching Berserk", parsed: parsed(status: "WATCHING"), candidates: manga7)
        case .animeReadingIsWatching:
            return item("reading Frieren", parsed: parsed(status: "READING"), candidates: anime7)
        }
    }

    /// (action, status, rating, notes, expected stored status)
    /// Apply v26: only newly stated rating/notes are sent; stored ones stay out of the request.
    static func expected(for rule: ApplyCase) -> (action: ImportItemAction, status: String, rating: Double?, notes: String?, expectedStatus: String?) {
        switch rule {
        case .progressOnlyUpdateKeepsAnimeStatus: return (.update, "COMPLETED", nil, nil, "COMPLETED")
        case .progressOnlyUpdateKeepsMangaStatus: return (.update, "READING", nil, nil, "READING")
        case .statedStatusIsSent: return (.update, "DROPPED", nil, nil, "WATCHING")
        case .untrackedLineWithoutStatusIsPlanned: return (.add, "PLANNING", nil, nil, nil)
        case .storedRatingAndNotesAreSentBack: return (.update, "WATCHING", nil, nil, "WATCHING")
        case .parsedRatingWins: return (.update, "WATCHING", 9, nil, "WATCHING")
        // The edge writes "S2E5" as notes when none are sent (owner decision, pinned by the edge tests).
        case .seasonNoteLineDoesNotSendStoredNotes: return (.update, "WATCHING", nil, nil, "WATCHING")
        case .mangaWatchingIsReading: return (.add, "READING", nil, nil, nil)
        case .animeReadingIsWatching: return (.add, "WATCHING", nil, nil, nil)
        }
    }

    @Test("Apply items: status only when stated (else the stored one); stored rating/notes are not resent",
          arguments: ApplyCase.allCases)
    func applyItemRules(rule: ApplyCase) throws {
        let applied = Self.applyItems([Self.line(for: rule)], library: Self.stored(for: rule))
        let expected = Self.expected(for: rule)
        let item = try #require(applied.first)
        #expect(applied.count == 1)
        #expect(item.action == expected.action)
        #expect(item.status == expected.status)
        #expect(item.rating == expected.rating)
        #expect(item.notes == expected.notes)
        #expect(item.expectedExisting?.status == expected.expectedStatus)
    }

    @Test("A progress-only update is an Update whose request keeps the stored status (wire shape)")
    func progressOnlyUpdateRequestShape() throws {
        let stored = Self.entry(.anime, 7, status: .completed, progress: 12, rating: 8, notes: "with Sam")
        let line = Self.item("Frieren ep 13", parsed: Self.parsed(episodes: 13), candidates: [Self.candidate(.anime, 7)])
        let ready = Self.prepared([line], library: [stored])
        let existing = try #require(ready[0].existing_entry)
        let diff = try #require(ImportReconciler.diff(existing: existing, parsed: line.parsed))
        #expect(diff.status == nil)
        #expect(diff.progressEpisodes == ImportDiff.FieldDiff(from: 12, to: 13))
        #expect(ImportReconciler.action(for: ready[0]) == .update)

        let payload = try #require(Self.applyItems([line], library: [stored]).first).payload
        #expect(payload["status"] as? String == "COMPLETED")
        #expect(payload["action"] as? String == "update")
        #expect(payload["mediaType"] as? String == "ANIME")
        #expect(payload["mediaId"] as? Int == 7)
        #expect(payload["progressEpisodes"] as? Int == 13)
        #expect(payload["rating"] == nil)
        #expect(payload["notes"] == nil)
        let expected = try #require(payload["expectedExisting"] as? [String: Any])
        #expect(expected["status"] as? String == "COMPLETED")
        #expect(expected["progress_episodes"] as? Int == 12)
        #expect(expected["progress_chapters"] == nil)
    }

    // MARK: Diff and action

    enum ActionCase: String, CaseIterable, Sendable {
        case identicalIsSkip
        case statusOnlyDifferenceIsUpdate
        case progressOnlyDifferenceIsUpdate
        case ratingOnlyDifferenceIsUpdate
        case sameRatingIsSkip
        case outOfScaleRatingIsNoChange
        case untrackedIsAdd
    }

    static func parsed(for rule: ActionCase) -> ConciergeParseItemParsed {
        switch rule {
        case .identicalIsSkip: return parsed(status: "watching", episodes: 12)
        case .statusOnlyDifferenceIsUpdate: return parsed(status: "COMPLETED")
        case .progressOnlyDifferenceIsUpdate: return parsed(episodes: 13)
        case .ratingOnlyDifferenceIsUpdate: return parsed(rating: 9.5)
        case .sameRatingIsSkip: return parsed(rating: 7)
        case .outOfScaleRatingIsNoChange: return parsed(rating: 0.5)
        case .untrackedIsAdd: return parsed(episodes: 12)
        }
    }

    static func expected(for rule: ActionCase) -> ImportItemAction {
        switch rule {
        case .identicalIsSkip, .sameRatingIsSkip, .outOfScaleRatingIsNoChange: return .skip
        case .statusOnlyDifferenceIsUpdate, .progressOnlyDifferenceIsUpdate, .ratingOnlyDifferenceIsUpdate: return .update
        case .untrackedIsAdd: return .add
        }
    }

    @Test("Add / Update / Skip: status, progress and rating differences are updates; identical lines are skipped",
          arguments: ActionCase.allCases)
    func itemAction(rule: ActionCase) {
        let stored = rule == .untrackedIsAdd ? [] : [Self.entry(.anime, 7, status: .current, progress: 12, rating: 7)]
        let line = Self.item("Frieren", parsed: Self.parsed(for: rule), candidates: [Self.candidate(.anime, 7)])
        let ready = Self.prepared([line], library: stored)
        let expected = Self.expected(for: rule)
        #expect(ImportReconciler.action(for: ready[0]) == expected)
        // A skipped line is never written.
        #expect(Self.applyItems([line], library: stored).isEmpty == (expected == .skip))
    }

    @Test("A rating-only change is recorded in the diff (floored, 1...10)")
    func ratingDiff() throws {
        let stored = ImportReconciler.existingEntry(Self.entry(.anime, 7, status: .current, progress: 12, rating: 7))
        let diff = try #require(ImportReconciler.diff(existing: stored, parsed: Self.parsed(rating: 9.5)))
        #expect(diff.rating == ImportDiff.FieldDiff(from: 7, to: 9))
        #expect(diff.status == nil && diff.progressEpisodes == nil)
    }

    @Test("The status diff compares in the medium's vocabulary: 'watching' on a READING manga changes nothing")
    func statusDiffIsNormalized() throws {
        let stored = ImportReconciler.existingEntry(Self.entry(.manga, 9, status: .current, progress: 30))
        #expect(stored.status == "READING")
        #expect(ImportReconciler.diff(existing: stored, parsed: Self.parsed(status: "watching", chapters: 30)) == nil)

        let raw = Self.serverEntry(.manga, 9, listType: "WATCHING", progress: 30)
        #expect(ImportReconciler.diff(existing: raw, parsed: Self.parsed(status: "READING", chapters: 30)) == nil)

        // A real change shows what is sent (the normalized status).
        let anime = ImportReconciler.existingEntry(Self.entry(.anime, 7, status: .planning))
        let diff = try #require(ImportReconciler.diff(existing: anime, parsed: Self.parsed(status: "reading")))
        #expect(diff.status == ImportDiff.FieldDiff(from: "PLANNING", to: "WATCHING"))

        let line = Self.item("watching Berserk", parsed: Self.parsed(status: "watching", chapters: 30), candidates: [Self.candidate(.manga, 9)])
        let ready = Self.prepared([line], library: [Self.entry(.manga, 9, status: .current, progress: 30)])
        #expect(ImportReconciler.action(for: ready[0]) == .skip)
    }

    // MARK: Duplicates

    @Test("Repeated lines are reviewed once; two lines for one title make one apply item (the later wins)")
    func duplicates() {
        let line = Self.item("Frieren ep 3", parsed: Self.parsed(episodes: 3), candidates: [Self.candidate(.anime, 7)])
        let ready = Self.prepared([line, line, line])
        #expect(ready.map(\.id) == [line.id])

        let later = Self.item("Frieren ep 9", parsed: Self.parsed(episodes: 9), candidates: [Self.candidate(.anime, 7)])
        let other = Self.item("Berserk", candidates: [Self.candidate(.manga, 7)])
        let applied = Self.applyItems([line, other, later], library: [])
        #expect(applied.map(\.key) == [MediaKey(kind: .anime, id: 7), MediaKey(kind: .manga, id: 7)])
        #expect(applied.first?.progressEpisodes == 9)
        #expect(applied.first?.raw == "Frieren ep 9")
    }

    @Test("Excluded and unselected lines are left out")
    func exclusionsAndSelections() {
        let a = Self.item("A", candidates: [Self.candidate(.anime, 1)])
        let b = Self.item("B", candidates: [Self.candidate(.anime, 2)])
        let c = Self.item("C", candidates: [Self.candidate(.anime, 3)])
        let applied = ImportReconciler.applyItems(
            for: [a, b, c],
            selections: [a.id: Self.candidate(.anime, 1), b.id: Self.candidate(.anime, 2)],
            excluded: [b.id],
            actions: [:],
            existing: Self.library([])
        )
        #expect(applied.map(\.key.id) == [1])
    }
}

// MARK: - Library load-state gate (E6c1)

/// The import rules while the Library projection is not loaded for the current account (cold start,
/// a new device's first load, a failed load). The reconciler reads the store exactly as the views do
/// (`existing: ImportReconciler.libraryLookup(library)`), over a real `LibraryStore` bound to the account.
@MainActor
@Suite("Imports: the Library load-state gate", .timeLimit(.minutes(1)))
struct ImportLoadStateGateTests {
    typealias Fixture = ImportReconcilerTests

    enum LibraryState: String, CaseIterable, Sendable {
        /// Bound, its first load not finished (or not started).
        case notLoaded
        /// Bound, its load failed.
        case failed
        /// Bound, its rows published.
        case loaded
    }

    /// A store bound to one account in `state` (`rows`: what a load publishes).
    static func store(_ state: LibraryState, rows: [LibraryEntry] = []) async throws -> LibraryStore {
        let source = ControlledResponses<[LibraryEntry]>()
        let store = LibraryStore(backend: FakeLibraryBackend(fetchSource: source))
        store.bind(AccountContext(userId: LifecycleFixtures.userA, generation: 1))
        guard state != .notLoaded else { return store }
        let refresh = Task { try? await store.refresh() }
        #expect(await source.waitForRequest(LifecycleFixtures.userA))
        source.complete(LifecycleFixtures.userA, with: state == .loaded ? .success(rows) : .failure(ControlledFailure()))
        await refresh.value
        #expect(store.loadState == (state == .loaded ? .loaded : .failed))
        return store
    }

    static func prepared(_ items: [ConciergeParseItem], _ library: LibraryStore) -> [ConciergeParseItem] {
        ImportReconciler.prepared(
            ConciergeParseResponse(success: true, userId: "u", items: items),
            existing: ImportReconciler.libraryLookup(library)
        ).items
    }

    /// "Frieren" with the top candidate anime 1 (the one the server looked up) and anime 2 that the user
    /// (or the on-device disambiguation) may pick instead.
    static func line(serverExisting: ConciergeExistingEntry? = nil) -> ConciergeParseItem {
        Fixture.item(
            "Frieren",
            parsed: Fixture.parsed(episodes: 3),
            candidates: [Fixture.candidate(.anime, 1, score: 0.95), Fixture.candidate(.anime, 2, score: 0.7)],
            serverExisting: serverExisting
        )
    }

    static func apply(_ line: ConciergeParseItem, picking id: Int, _ library: LibraryStore) -> [ImportApplyItem] {
        let ready = prepared([line], library)
        return ImportReconciler.applyItems(
            for: ready,
            selections: [line.id: line.candidates.first { $0.media_id == id } ?? Fixture.candidate(.anime, id)],
            actions: [line.id: ImportReconciler.action(for: ready[0])],
            existing: ImportReconciler.libraryLookup(library)
        )
    }

    @Test("A picked title the server did not look up is never sent as an Add while the Library is not loaded (it may be tracked); once loaded, an untracked one is",
          arguments: LibraryState.allCases)
    func unknownPickIsNeverAnAdd(state: LibraryState) async throws {
        let library = try await Self.store(state)
        let picked = Self.apply(Self.line(), picking: 2, library)
        if state == .loaded {
            #expect(picked.map(\.key) == [MediaKey(kind: .anime, id: 2)])
            #expect(picked.first?.action == .add)
        } else {
            #expect(picked.isEmpty, "unknown tracking state sent as \(picked.map(\.action))")
        }
    }

    @Test("The title the server looked up keeps the server's answer in every Library state: untracked -> Add, tracked -> Update with its stored state",
          arguments: LibraryState.allCases)
    func serverAnsweredLinesKeepTheServersAnswer(state: LibraryState) async throws {
        let library = try await Self.store(state)
        let added = try #require(Self.apply(Self.line(), picking: 1, library).first)
        #expect(added.key == MediaKey(kind: .anime, id: 1) && added.action == .add)

        let server = Fixture.serverEntry(.anime, 1, listType: "COMPLETED", progress: 12, rating: 8)
        let updated = try #require(Self.apply(Self.line(serverExisting: server), picking: 1, library).first)
        #expect(updated.action == .update)
        #expect(updated.status == "COMPLETED", "a progress-only line keeps the stored status")
        #expect(updated.expectedExisting == ImportApplyItem.ExpectedExisting(status: "COMPLETED", progressEpisodes: 12, progressChapters: nil))
    }

    @Test("A title the Library already holds is an Update even before its load finished (tracked is never unknown)")
    func trackedTitleIsKnownBeforeTheLoad() async throws {
        let source = ControlledResponses<[LibraryEntry]>()
        let backend = FakeLibraryBackend(fetchSource: source)
        let library = LibraryStore(backend: backend)
        library.bind(AccountContext(userId: LifecycleFixtures.userA, generation: 1))
        // A save made before the first load finished (the user tapped Add on a card).
        #expect(await library.save(MediaKey(kind: .anime, id: 2), status: .planning).change != nil)
        #expect(library.loadState == .notLoaded)

        let picked = Self.apply(Self.line(), picking: 2, library)
        #expect(picked.first?.action == .update)
        #expect(picked.first?.expectedExisting?.status == "PLANNING")
    }

    @Test("No auto-apply while the Library does not know the line's title (not loaded or failed); auto-apply once loaded",
          arguments: LibraryState.allCases)
    func autoApplyWaitsForTheLoadedLibrary(state: LibraryState) async throws {
        let library = try await Self.store(state)
        let strong = Fixture.item("Frieren", candidates: [Fixture.candidate(.anime, 1, score: 0.99)])
        let ready = Self.prepared([strong], library)
        #expect(ImportReconciler.shouldAutoApply(ready, existing: Fixture.library([])), "with a loaded Library the same line would auto-apply")
        #expect(ImportReconciler.shouldAutoApply(ready, existing: ImportReconciler.libraryLookup(library)) == (state == .loaded))
    }
}

// MARK: - Apply gate (E8)

/// `ImportReconciler.canApply(loadState:)`: the import surfaces start `concierge-apply` only while it
/// holds (ConciergeView's confirm and its auto-apply, ProfileView's auto-apply). Until the Library holds
/// the current account's rows, a failed or ignored server lookup reads as "untracked" (its Add would be
/// upserted over a tracked row) and a picked title the server did not look up would be left out.
@MainActor
@Suite("Imports: the apply gate (canApply)", .timeLimit(.minutes(1)))
struct ImportApplyGateTests {
    static let userA = LifecycleFixtures.userA
    static let userB = LifecycleFixtures.userB

    @Test("Applying needs the loaded Library: not loaded, loading and failed never apply",
          arguments: [
              (LibraryStore.LoadState.notLoaded, false),
              (LibraryStore.LoadState.loading, false),
              (LibraryStore.LoadState.failed, false),
              (LibraryStore.LoadState.loaded, true),
          ])
    func canApplyOnlyWhenLoaded(state: LibraryStore.LoadState, expected: Bool) {
        #expect(ImportReconciler.canApply(loadState: state) == expected)
    }

    @Test("A real store through its load states (the views pass library.loadState): closed until a load publishes, closed again while a failed load retries")
    func storeLoadStates() async throws {
        let source = ControlledResponses<[LibraryEntry]>()
        let store = LibraryStore(backend: FakeLibraryBackend(fetchSource: source))
        store.bind(AccountContext(userId: Self.userA, generation: 1))
        #expect(store.loadState == .notLoaded)
        #expect(!ImportReconciler.canApply(loadState: store.loadState))

        let failing = Task { try? await store.refresh() }
        #expect(await source.waitForRequest(Self.userA))
        #expect(store.loadState == .loading)
        #expect(!ImportReconciler.canApply(loadState: store.loadState))
        source.complete(Self.userA, with: .failure(ControlledFailure()))
        await failing.value
        #expect(store.loadState == .failed)
        #expect(!ImportReconciler.canApply(loadState: store.loadState))

        // The confirm tap's view-path refresh retries the load.
        let retry = Task { try? await store.refresh() }
        #expect(await source.waitForRequest("\(Self.userA)#2"))
        #expect(store.loadState == .loading)
        #expect(!ImportReconciler.canApply(loadState: store.loadState))
        source.complete("\(Self.userA)#2", with: .success([FakeLibraryBackend.entry(.anime, 1)]))
        await retry.value
        #expect(store.loadState == .loaded)
        #expect(ImportReconciler.canApply(loadState: store.loadState))
    }

    @Test("The blocked confirm's view-path refresh (LibraryActions.fetchUserLists) re-reads a Library whose session load failed, so the next confirm can apply")
    func blockedConfirmRefreshRetriesAFailedLoad() async throws {
        let source = ControlledResponses<[LibraryEntry]>()
        let harness = try FacadeHarness(backend: FakeLibraryBackend(fetchSource: source))
        let service = harness.service
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        #expect(await source.waitForRequest(Self.userA), "the session funnel's load")
        source.complete(Self.userA, with: .failure(ControlledFailure()))
        await service.libraryActions.libraryRefreshTask?.value
        #expect(service.library.loadState == .failed)
        #expect(!ImportReconciler.canApply(loadState: service.library.loadState))

        // ConciergeView.confirmImport while blocked: toast, then `await libraryActions.fetchUserLists()`.
        let retry = Task { await service.libraryActions.fetchUserLists() }
        #expect(await source.waitForRequest("\(Self.userA)#2"), "a finished (failed) load is never joined: a new read starts")
        #expect(!ImportReconciler.canApply(loadState: service.library.loadState))
        source.complete("\(Self.userA)#2", with: .success([FakeLibraryBackend.entry(.anime, 1)]))
        await retry.value
        #expect(service.library.loadState == .loaded)
        #expect(ImportReconciler.canApply(loadState: service.library.loadState))
        #expect(harness.fetchAllCount == 2)
        await harness.tearDown()
    }

    @Test("Account switch: A's loaded Library never lets B apply (not even A's late answer); B applies once its own rows are loaded; sign-out closes the gate")
    func accountSwitchClosesTheGate() async throws {
        let source = ControlledResponses<[LibraryEntry]>()
        let store = LibraryStore(backend: FakeLibraryBackend(fetchSource: source))
        store.bind(AccountContext(userId: Self.userA, generation: 1))
        let loadA = Task { try? await store.refresh() }
        #expect(await source.waitForRequest(Self.userA))
        source.complete(Self.userA, with: .success([FakeLibraryBackend.entry(.anime, 1)]))
        await loadA.value
        #expect(ImportReconciler.canApply(loadState: store.loadState), "A's rows are loaded")

        // A refresh of A is still in flight when B signs in.
        let lateA = Task { try? await store.refresh() }
        #expect(await source.waitForRequest("\(Self.userA)#2"))
        store.bind(AccountContext(userId: Self.userB, generation: 2))
        #expect(!ImportReconciler.canApply(loadState: store.loadState), "A's loaded state is not B's")
        source.complete("\(Self.userA)#2", with: .success([FakeLibraryBackend.entry(.anime, 1)]))
        await lateA.value
        #expect(store.loadState == .notLoaded, "A's late answer never marks B's Library loaded")
        #expect(!ImportReconciler.canApply(loadState: store.loadState))

        let loadB = Task { try? await store.refresh() }
        #expect(await source.waitForRequest(Self.userB))
        #expect(!ImportReconciler.canApply(loadState: store.loadState), "B's first load is in flight")
        source.complete(Self.userB, with: .success([]))
        await loadB.value
        #expect(ImportReconciler.canApply(loadState: store.loadState), "B's own rows are loaded")

        store.reset()
        #expect(!ImportReconciler.canApply(loadState: store.loadState), "signed out")
    }
}

// MARK: - Review decisions moved out of the views (E6)

/// `ImportReconciler.initialSelections` (the one pre-selection of both Concierge review paths) and
/// `ImportReconciler.autoApplyPlan` (the one auto-apply decision of the Concierge first parse and the
/// Profile AniList import). Characterized against the pre-E6 view code: the two compositions below are
/// that code, copied verbatim from ConciergeView/ProfileView (only the view state became parameters).
extension ImportReconcilerTests {

    // MARK: Pre-selection

    enum PreselectCase: String, CaseIterable, Sendable {
        case topAtTheBoundary
        case topJustBelowTheBoundary
        case noCandidates
        case ambiguousAdaptations
        case ambiguousButTheYearNamesTheTop
        case ambiguousBelowTheBoundary
        case trackedUnchanged
        case trackedWithNewProgress
    }

    static func line(for rule: PreselectCase) -> ConciergeParseItem {
        let hxh2011 = candidate(.anime, 11061, score: 0.99, title: "Hunter x Hunter (2011)", year: 2011)
        let hxh1999 = candidate(.anime, 136, score: 0.97, title: "Hunter x Hunter: The Series", year: 1999)
        switch rule {
        case .topAtTheBoundary: return item("Frieren", candidates: [candidate(.anime, 1, score: 0.60)])
        case .topJustBelowTheBoundary: return item("Frieren", candidates: [candidate(.anime, 1, score: 0.5999)])
        case .noCandidates: return item("zzz", candidates: [])
        case .ambiguousAdaptations: return item("Hunter x Hunter", candidates: [hxh2011, hxh1999])
        case .ambiguousButTheYearNamesTheTop:
            return item("Hunter x Hunter 2011", parsed: parsed(yearMention: 2011), candidates: [hxh2011, hxh1999])
        case .ambiguousBelowTheBoundary:
            return item("Hunter x Hunter", candidates: [
                candidate(.anime, 11061, score: 0.55, title: "Hunter x Hunter (2011)", year: 2011),
                candidate(.anime, 136, score: 0.5, title: "Hunter x Hunter: The Series", year: 1999),
            ])
        case .trackedUnchanged: return item("Frieren ep 12", parsed: parsed(episodes: 12), candidates: [candidate(.anime, 7)])
        case .trackedWithNewProgress: return item("Frieren ep 13", parsed: parsed(episodes: 13), candidates: [candidate(.anime, 7)])
        }
    }

    /// (selected, listed for disambiguation, action written on the first parse, action on a re-parse)
    static func expected(for rule: PreselectCase) -> (selected: Bool, ambiguous: Bool, firstParse: ImportItemAction?, reparse: ImportItemAction) {
        switch rule {
        case .topAtTheBoundary: return (true, false, .add, .add)
        case .topJustBelowTheBoundary: return (false, false, .add, .add)
        case .noCandidates: return (false, false, .add, .add)
        // Pre-existing divergence: the first parse leaves an ambiguous line's action unset (shown as Add).
        case .ambiguousAdaptations: return (false, true, nil, .add)
        case .ambiguousButTheYearNamesTheTop: return (true, false, .add, .add)
        case .ambiguousBelowTheBoundary: return (false, false, .add, .add)
        case .trackedUnchanged: return (true, false, .skip, .skip)
        case .trackedWithNewProgress: return (true, false, .update, .update)
        }
    }

    /// The two named pre-selection entry points (Concierge first parse / clarification re-parse).
    enum PreselectPath: String, CaseIterable, Sendable {
        case firstParse
        case clarificationReparse
    }

    static func preselect(_ path: PreselectPath, _ items: [ConciergeParseItem]) -> ImportPreselection {
        switch path {
        case .firstParse: return ImportReconciler.initialSelectionsFirstParse(for: items)
        case .clarificationReparse: return ImportReconciler.initialSelectionsClarificationReparse(for: items)
        }
    }

    @Test("Pre-selection: the top candidate is selected at >= 0.60 unless its adaptations are ambiguous; every line gets its action",
          arguments: PreselectCase.allCases)
    func preselection(rule: PreselectCase) {
        let stored = [Self.entry(.anime, 7, status: .current, progress: 12)]
        let ready = Self.prepared([Self.line(for: rule)], library: stored)
        let id = ready[0].id
        let expected = Self.expected(for: rule)
        for path in PreselectPath.allCases {
            let pre = Self.preselect(path, ready)
            #expect((pre.selections[id] != nil) == expected.selected)
            if expected.selected { #expect(pre.selections[id] == ready[0].candidates.first) }
            #expect(pre.ambiguousItems.map(\.id) == (expected.ambiguous ? [id] : []))
            #expect(pre.actions[id] == (path == .clarificationReparse ? expected.reparse : expected.firstParse), "\(path)")
        }
    }

    @Test("Pre-selection divergence (pinned): a tracked line with ambiguous adaptations has no action on the first parse, its real action on the clarification re-parse")
    func preselectionActionDivergence() {
        let stored = [Self.entry(.anime, 11061, status: .completed, progress: 148)]
        let ready = Self.prepared([Self.line(for: .ambiguousAdaptations)], library: stored)
        #expect(ImportReconciler.action(for: ready[0]) == .skip)
        #expect(ImportReconciler.initialSelectionsFirstParse(for: ready).actions.isEmpty)
        #expect(ImportReconciler.initialSelectionsClarificationReparse(for: ready).actions == [ready[0].id: .skip])
    }

    @Test("Pre-selection over a whole parse keeps the parse order of the ambiguous lines")
    func preselectionOrder() {
        let rules: [PreselectCase] = [.ambiguousAdaptations, .topAtTheBoundary, .ambiguousButTheYearNamesTheTop, .noCandidates]
        let ambiguousManga = Self.item("Berserk", candidates: [
            Self.candidate(.manga, 30, score: 0.9, title: "Berserk"),
            Self.candidate(.manga, 31, score: 0.8, title: "Berserk (Deluxe)"),
        ])
        let ready = Self.prepared(rules.map { Self.line(for: $0) } + [ambiguousManga])
        let pre = ImportReconciler.initialSelectionsFirstParse(for: ready)
        #expect(pre.ambiguousItems.map(\.raw) == ["Hunter x Hunter", "Berserk"])
        #expect(Set(pre.selections.keys) == [ready[1].id, ready[2].id])
        #expect(pre.actions.count == 3)
    }

    // MARK: Auto-apply plan

    enum PlanCase: String, CaseIterable, Sendable {
        case strongUntrackedLines
        case atTheThreshold
        case justBelowTheThreshold
        case ambiguousAdaptations
        case trackedInTheLibrary
        case trackedByTheServer
        case emptyParse
        case aLineWithoutCandidates
        case everyLineExcluded
        case oneOfTwoLinesExcluded
        case parserAmbiguity
    }

    static func lines(for rule: PlanCase) -> [ConciergeParseItem] {
        let frieren = item("Frieren", candidates: [candidate(.anime, 1, score: 0.99)])
        let berserk = item("Berserk", candidates: [candidate(.manga, 2, score: 0.9)])
        switch rule {
        case .strongUntrackedLines, .everyLineExcluded, .oneOfTwoLinesExcluded: return [frieren, berserk]
        case .atTheThreshold: return [item("Frieren", candidates: [candidate(.anime, 1, score: 0.85)])]
        case .justBelowTheThreshold: return [frieren, item("Berserk", candidates: [candidate(.manga, 2, score: 0.8499)])]
        case .ambiguousAdaptations: return [frieren, line(for: .ambiguousAdaptations)]
        case .trackedInTheLibrary: return [frieren, item("Frieren ep 13", candidates: [candidate(.anime, 7, score: 0.99)])]
        case .trackedByTheServer:
            return [item("Frieren", candidates: [candidate(.anime, 1, score: 0.99)], serverExisting: serverEntry(.anime, 1, listType: "COMPLETED", progress: 28))]
        case .emptyParse: return []
        case .aLineWithoutCandidates: return [frieren, item("zzz", candidates: [])]
        case .parserAmbiguity:
            let ambiguity = ConciergeAmbiguity(kind: "status_unclear", options: ["COMPLETED", "CURRENT"], suggested_question: "Finished or still watching?", title_context: "Frieren", number_context: nil)
            return [item("I watched Frieren", candidates: [candidate(.anime, 1, score: 0.99)], ambiguity: ambiguity), berserk]
        }
    }

    static func excluded(for rule: PlanCase, _ ready: [ConciergeParseItem]) -> Set<String> {
        switch rule {
        case .everyLineExcluded: return Set(ready.map(\.id))
        case .oneOfTwoLinesExcluded: return [ready[0].id]
        default: return []
        }
    }

    /// Expected plan with a loaded Library: "apply:<raws>" / "nothingToApply" / "review". Parser
    /// ambiguity: Profile reviews, Concierge does not block (preserved pre-existing difference).
    static func expected(for rule: PlanCase, surface: PlanSurface) -> String {
        switch rule {
        case .strongUntrackedLines: return "apply:Frieren,Berserk"
        case .atTheThreshold: return "apply:Frieren"
        case .justBelowTheThreshold, .ambiguousAdaptations, .trackedInTheLibrary, .trackedByTheServer, .emptyParse, .aLineWithoutCandidates:
            return "review"
        case .everyLineExcluded: return "nothingToApply"
        case .oneOfTwoLinesExcluded: return "apply:Berserk"
        case .parserAmbiguity: return "review"
        }
    }

    /// The two named auto-apply entry points (Concierge first parse / Profile AniList import).
    enum PlanSurface: String, CaseIterable, Sendable {
        case concierge
        case profile
    }

    static func plan(
        _ surface: PlanSurface,
        _ items: [ConciergeParseItem],
        loadState: LibraryStore.LoadState,
        excluded: Set<String> = [],
        existing: @escaping ImportReconciler.LibraryLookup
    ) -> ImportAutoApplyPlan {
        switch surface {
        case .concierge:
            return ImportReconciler.conciergeAutoApplyPlan(for: items, loadState: loadState, excluded: excluded, existing: existing)
        case .profile:
            return ImportReconciler.profileImportPlan(for: items, loadState: loadState, excluded: excluded, existing: existing)
        }
    }

    static func describe(_ plan: ImportAutoApplyPlan) -> String {
        switch plan {
        case .apply(let items, _): return "apply:" + items.map(\.raw).joined(separator: ",")
        case .nothingToApply: return "nothingToApply"
        case .review: return "review"
        }
    }

    @Test("Auto-apply plan: apply at once only with the Library loaded and every line qualifying; all excluded = nothing to apply; else review",
          arguments: PlanCase.allCases, PlanSurface.allCases)
    func autoApplyPlan(rule: PlanCase, surface: PlanSurface) {
        let stored = [Self.entry(.anime, 7, status: .current, progress: 12)]
        let ready = Self.prepared(Self.lines(for: rule), library: stored)
        let excluded = Self.excluded(for: rule, ready)
        for state in [LibraryStore.LoadState.notLoaded, .loading, .failed, .loaded] {
            let plan = Self.plan(surface, ready, loadState: state, excluded: excluded, existing: Self.library(stored))
            let expected = state == .loaded ? Self.expected(for: rule, surface: surface) : "review"
            #expect(Self.describe(plan) == expected, "\(state)")
            if case .apply(let items, _) = plan {
                #expect(items.allSatisfy { $0.action == .add && $0.status == "PLANNING" && $0.expectedExisting == nil })
            }
        }
    }

    @Test("Auto-apply plan: a title the Library does not know (unknown) is never auto-applied, even with a loaded state")
    func autoApplyPlanUnknownTitle() {
        let ready = Self.prepared(Self.lines(for: .strongUntrackedLines))
        for surface in PlanSurface.allCases {
            #expect(Self.plan(surface, ready, loadState: .loaded, existing: { _ in .unknown }) == .review, "\(surface)")
        }
    }

    // MARK: Named entry points (the preserved Concierge / Profile differences)

    @Test("First parse (preserved): a tracked line with ambiguous adaptations is listed for disambiguation, unselected, and gets NO action")
    func firstParseEntryPoint() {
        let stored = [Self.entry(.anime, 11061, status: .completed, progress: 148)]
        let ready = Self.prepared([Self.line(for: .ambiguousAdaptations), Self.line(for: .topAtTheBoundary)], library: stored)
        let pre = ImportReconciler.initialSelectionsFirstParse(for: ready)
        #expect(pre.ambiguousItems.map(\.id) == [ready[0].id])
        #expect(pre.selections[ready[0].id] == nil)
        #expect(pre.actions[ready[0].id] == nil, "shown as Add although its real action is Skip")
        #expect(pre.actions[ready[1].id] == .add)
    }

    @Test("Clarification re-parse (preserved): the same line gets its real action (Skip); it stays unselected and listed")
    func clarificationReparseEntryPoint() {
        let stored = [Self.entry(.anime, 11061, status: .completed, progress: 148)]
        let ready = Self.prepared([Self.line(for: .ambiguousAdaptations), Self.line(for: .topAtTheBoundary)], library: stored)
        let pre = ImportReconciler.initialSelectionsClarificationReparse(for: ready)
        #expect(pre.ambiguousItems.map(\.id) == [ready[0].id])
        #expect(pre.selections[ready[0].id] == nil)
        #expect(pre.actions[ready[0].id] == .skip)
        #expect(pre.actions[ready[1].id] == .add)
    }

    @Test("Concierge plan (locked): a PARSER ambiguity blocks auto-apply; ambiguous ADAPTATIONS still do")
    func conciergePlanEntryPoint() {
        let parserAmbiguous = Self.prepared(Self.lines(for: .parserAmbiguity))
        #expect(ImportReconciler.conciergeAutoApplyPlan(for: parserAmbiguous, loadState: .loaded, existing: Self.library([])) == .review)
        let adaptations = Self.prepared(Self.lines(for: .ambiguousAdaptations))
        #expect(ImportReconciler.conciergeAutoApplyPlan(for: adaptations, loadState: .loaded, existing: Self.library([])) == .review)
        #expect(ImportReconciler.conciergeAutoApplyPlan(for: parserAmbiguous, loadState: .notLoaded, existing: Self.library([])) == .review)
    }

    @Test("Profile plan (locked): ANY parser ambiguity forces review; without one the same lines auto-apply")
    func profilePlanEntryPoint() {
        let parserAmbiguous = Self.prepared(Self.lines(for: .parserAmbiguity))
        #expect(ImportReconciler.profileImportPlan(for: parserAmbiguous, loadState: .loaded, existing: Self.library([])) == .review)
        let clean = Self.prepared(Self.lines(for: .strongUntrackedLines))
        #expect(Self.describe(ImportReconciler.profileImportPlan(for: clean, loadState: .loaded, existing: Self.library([])))
                == "apply:Frieren,Berserk")
        let adaptations = Self.prepared(Self.lines(for: .ambiguousAdaptations))
        #expect(ImportReconciler.profileImportPlan(for: adaptations, loadState: .loaded, existing: Self.library([])) == .review)
    }

    @Test("Apply sends at most 100 items; the rest are reported as not added")
    func applyItemLimitCapsAndReportsOmitted() {
        let lines: [ConciergeParseItem] = (1...105).map { id in
            Self.item("Title \(id)", candidates: [Self.candidate(.anime, id)])
        }
        let ready = Self.prepared(lines)
        var selections: [String: ConciergeCandidate] = [:]
        var actions: [String: ImportItemAction] = [:]
        for item in ready {
            selections[item.id] = item.candidates[0]
            actions[item.id] = .add
        }
        let batch = ImportReconciler.applyBatch(
            for: ready,
            selections: selections,
            actions: actions,
            existing: Self.library([])
        )
        #expect(batch.items.count == 100)
        #expect(batch.omitted == 5)
        #expect(ImportReconciler.omittedApplyCopy(omitted: batch.omitted, german: false)
                == "5 more titles were not added (Apply accepts at most 100).")
    }

    // MARK: Equivalence with the pre-E6 view compositions

    /// ConciergeView.handleImportFlow before E6 (pre-select loop, gate, `buildApplyPayload`, the silent
    /// return of `autoApplyImport` on an empty payload), with its view state as parameters.
    static func legacyConciergePlan(
        _ items: [ConciergeParseItem],
        loadState: LibraryStore.LoadState,
        selected priorSelected: [String: ConciergeCandidate],
        actions priorActions: [String: ImportItemAction],
        excluded: Set<String>,
        existing: @escaping ImportReconciler.LibraryLookup
    ) -> (plan: ImportAutoApplyPlan, selected: [String: ConciergeCandidate], actions: [String: ImportItemAction], ambiguous: [String]) {
        var selectedByItemId = priorSelected
        var itemActions = priorActions
        var ambiguousItemsNeedingHelp: [ConciergeParseItem] = []
        for item in items {
            if let top = item.candidates.first, top.score >= ImportReconciler.preselectMinimumScore {
                if ImportReconciler.hasAmbiguousAdaptations(candidates: item.candidates, yearMention: item.parsed.yearMention) {
                    ambiguousItemsNeedingHelp.append(item)
                    continue
                }
                selectedByItemId[item.id] = top
            }
            let action = ImportReconciler.action(for: item)
            itemActions[item.id] = action
        }
        let plan: ImportAutoApplyPlan
        if items.contains(where: { $0.ambiguity != nil }) {
            plan = .review
        } else if ImportReconciler.canApply(loadState: loadState),
           ImportReconciler.shouldAutoApply(items, existing: existing) {
            let chosen = ImportReconciler.applyItems(
                for: items,
                selections: selectedByItemId,
                excluded: excluded,
                actions: itemActions,
                existing: existing
            )
            plan = chosen.isEmpty ? .nothingToApply : .apply(items: chosen, omitted: 0)
        } else {
            plan = .review
        }
        return (plan, selectedByItemId, itemActions, ambiguousItemsNeedingHelp.map(\.id))
    }

    /// ConciergeView.handleClarification before E6 (its pre-select loop).
    static func legacyClarificationPreselect(
        _ items: [ConciergeParseItem],
        selected priorSelected: [String: ConciergeCandidate],
        actions priorActions: [String: ImportItemAction]
    ) -> (selected: [String: ConciergeCandidate], actions: [String: ImportItemAction]) {
        var selectedByItemId = priorSelected
        var itemActions = priorActions
        for item in items {
            if let top = item.candidates.first, top.score >= ImportReconciler.preselectMinimumScore {
                if !ImportReconciler.hasAmbiguousAdaptations(candidates: item.candidates, yearMention: item.parsed.yearMention) {
                    selectedByItemId[item.id] = top
                }
            }
            let action = ImportReconciler.action(for: item)
            itemActions[item.id] = action
        }
        return (selectedByItemId, itemActions)
    }

    /// ProfileView.profileImportDecision before E6 (nil = needs review, else the apply payload's items).
    static func legacyProfileDecision(
        _ items: [ConciergeParseItem],
        loadState: LibraryStore.LoadState,
        existing: @escaping ImportReconciler.LibraryLookup
    ) -> [ImportApplyItem]? {
        guard !items.contains(where: { $0.ambiguity != nil }),
              ImportReconciler.canApply(loadState: loadState),
              ImportReconciler.shouldAutoApply(items, existing: existing)
        else {
            return nil
        }
        var selectedByItemId: [String: ConciergeCandidate] = [:]
        var itemActions: [String: ImportItemAction] = [:]
        for item in items {
            guard let top = item.candidates.first else { return nil }
            selectedByItemId[item.id] = top
            itemActions[item.id] = ImportReconciler.action(for: item)
        }
        let payload = ImportReconciler.applyItems(
            for: items,
            selections: selectedByItemId,
            actions: itemActions,
            existing: existing
        )
        guard !payload.isEmpty else { return nil }
        return payload
    }

    @Test("The shared decisions equal the pre-E6 Concierge and Profile compositions over a fixture matrix (lines x load states x exclusions x stale view state)")
    func sharedDecisionsMatchTheViewCompositions() {
        let ambiguity = ConciergeAmbiguity(kind: "status_unclear", options: nil, suggested_question: nil, title_context: nil, number_context: nil)
        let pool: [ConciergeParseItem] = [
            Self.item("A strong", candidates: [Self.candidate(.anime, 1, score: 0.99)]),
            Self.item("B manga", candidates: [Self.candidate(.manga, 2, score: 0.9)]),
            Self.item("C weak", candidates: [Self.candidate(.anime, 3, score: 0.8499)]),
            Self.item("D boundary", candidates: [Self.candidate(.anime, 4, score: 0.85)]),
            Self.line(for: .ambiguousAdaptations),
            Self.item("F tracked", parsed: Self.parsed(episodes: 13), candidates: [Self.candidate(.anime, 7, score: 0.99)]),
            Self.item("G server", candidates: [Self.candidate(.anime, 8, score: 0.95)], serverExisting: Self.serverEntry(.anime, 8, listType: "PAUSED", progress: 2)),
            Self.item("H none", candidates: []),
            Self.item("I asks", candidates: [Self.candidate(.anime, 9, score: 0.99)], ambiguity: ambiguity),
            Self.item("J low", candidates: [Self.candidate(.anime, 10, score: 0.5)]),
            Self.item("K same title", candidates: [Self.candidate(.anime, 1, score: 0.95)]),
        ]
        let stored = [Self.entry(.anime, 7, status: .current, progress: 12)]
        var parses: [[ConciergeParseItem]] = pool.map { [$0] }
        for i in pool.indices { for j in pool.indices where j > i { parses.append([pool[i], pool[j]]) } }
        for i in pool.indices { for j in pool.indices where j > i { for k in pool.indices where k > j { parses.append([pool[i], pool[j], pool[k]]) } } }

        var compared = 0
        for parse in parses {
            let ready = Self.prepared(parse, library: stored)
            let ids = ready.map(\.id)
            // Stale view state from an earlier message about the same lines (other picks, other actions).
            let stale = (
                selected: Dictionary(uniqueKeysWithValues: ids.map { ($0, Self.candidate(.anime, 999, score: 0.1)) }),
                actions: Dictionary(uniqueKeysWithValues: ids.map { ($0, ImportItemAction.skip) })
            )
            for state in [LibraryStore.LoadState.notLoaded, .failed, .loaded] {
                let lookup: ImportReconciler.LibraryLookup = state == .loaded ? Self.library(stored) : { query in
                    stored.first { $0.key == query.key }.map(LibraryKnowledge.tracked) ?? .unknown
                }
                for excluded in [Set<String>(), Set(ids.prefix(1)), Set(ids)] {
                    for prior in [(selected: [String: ConciergeCandidate](), actions: [String: ImportItemAction]()), stale] {
                        let legacy = Self.legacyConciergePlan(ready, loadState: state, selected: prior.selected, actions: prior.actions, excluded: excluded, existing: lookup)
                        let pre = ImportReconciler.initialSelectionsFirstParse(for: ready)
                        #expect(prior.selected.merging(pre.selections) { _, new in new } == legacy.selected)
                        #expect(prior.actions.merging(pre.actions) { _, new in new } == legacy.actions)
                        #expect(pre.ambiguousItems.map(\.id) == legacy.ambiguous)
                        // Concierge reaches the plan with or without clarify_v2; parser ambiguity blocks.
                        let concierge = ImportReconciler.conciergeAutoApplyPlan(for: ready, loadState: state, excluded: excluded, existing: lookup)
                        #expect(concierge == legacy.plan, "\(ready.map(\.raw)) \(state) excluded \(excluded.count)")

                        let reparse = Self.legacyClarificationPreselect(ready, selected: prior.selected, actions: prior.actions)
                        let pre2 = ImportReconciler.initialSelectionsClarificationReparse(for: ready)
                        #expect(prior.selected.merging(pre2.selections) { _, new in new } == reparse.selected)
                        #expect(prior.actions.merging(pre2.actions) { _, new in new } == reparse.actions)
                        compared += 1
                    }
                }
                let profile = ImportReconciler.profileImportPlan(for: ready, loadState: state, existing: lookup)
                let legacyProfile = Self.legacyProfileDecision(ready, loadState: state, existing: lookup)
                switch profile {
                case .apply(let items, _): #expect(items == legacyProfile, "\(ready.map(\.raw)) \(state)")
                case .nothingToApply, .review: #expect(legacyProfile == nil, "\(ready.map(\.raw)) \(state)")
                }
            }
        }
        #expect(compared == parses.count * 3 * 3 * 2)
        #expect(parses.count == 11 + 55 + 165)
    }
}

@Suite("Imports: apply and undo wire outcomes")
struct ImportApplyOutcomeTests {
    @Test("A deployed success stays undoable, a partial stays undoable, and a no-write rejection is a failure")
    func presentationKeepsOldPartialAndRejected() throws {
        let old = try JSONDecoder().decode(ConciergeApplyResponse.self, from: Data(#"{"success":true,"sessionId":"s1","applied":[{"mediaType":"ANIME","mediaId":7,"status":"PLANNING","action":"add"}]}"#.utf8))
        #expect(old.presentation.tone == .applied)
        #expect(old.presentation.undoSessionId == "s1")
        #expect(old.presentation.replayed == false)

        let partial = try JSONDecoder().decode(
            ConciergeApplyResponse.self,
            from: Data(#"{"success":false,"sessionId":"s2","applied":[{"mediaType":"MANGA","mediaId":9,"status":"READING","action":"add"}],"conflicts":[{"mediaType":"ANIME","mediaId":3,"error":"conflict"}],"errors":[],"status":"partial","undoable":true,"replayed":false}"#.utf8)
        )
        #expect(partial.presentation.tone == .partial)
        #expect(partial.presentation.undoSessionId == "s2")
        #expect(partial.presentation.addCount == 1)
        #expect(partial.presentation.conflictCount == 1)

        let failed = try JSONDecoder().decode(ConciergeApplyResponse.self, from: Data(#"{"success":false,"errors":[{"error":"nope"}]}"#.utf8))
        #expect(failed.presentation.tone == .failed)
        #expect(failed.presentation.undoSessionId == nil)

        let cleanNone = try JSONDecoder().decode(ConciergeApplyResponse.self, from: Data(#"{"success":true,"applied":[],"conflicts":[],"errors":[],"status":"none","undoable":false}"#.utf8))
        #expect(cleanNone.presentation.tone == .empty)
        #expect(cleanNone.presentation.undoSessionId == nil)

        let rejectedNone = try JSONDecoder().decode(
            ConciergeApplyResponse.self,
            from: Data(#"{"success":false,"applied":[],"conflicts":[],"errors":[{"mediaType":"ANIME","mediaId":7,"error":"invalid progress"}],"status":"none","undoable":false}"#.utf8)
        )
        #expect(rejectedNone.presentation.tone == .failed)
        #expect(rejectedNone.presentation.errorCount == 1)
        #expect(rejectedNone.presentation.firstError == "invalid progress")

        let allConflicts = try JSONDecoder().decode(
            ConciergeApplyResponse.self,
            from: Data(#"{"success":false,"applied":[],"conflicts":[{"mediaType":"ANIME","mediaId":7,"error":"conflict"}],"errors":[],"status":"none","undoable":false}"#.utf8)
        )
        #expect(allConflicts.presentation.tone == .failed)
        #expect(allConflicts.presentation.undoSessionId == nil)
    }

    @Test("A lost response retries the frozen payload and key; a new action does not, even with the same items")
    @MainActor
    func lostResponseKeepsTheAction() {
        let attempt = ImportApplyAttempt()
        let original: [[String: Any]] = [["mediaType": "ANIME", "mediaId": 7, "status": "PLANNING"]]
        var builds = 0
        let first = attempt.begin(anchor: "confirm:m1", stamp: "sel") {
            builds += 1
            return original
        }
        #expect(ImportApplyIdentity.isValid(first.key))
        #expect(builds == 1)
        attempt.observe(URLError(.networkConnectionLost))
        attempt.observe(URLError(.timedOut))
        attempt.observe(URLError(.notConnectedToInternet))
        let retry = attempt.begin(anchor: "confirm:m1", stamp: "sel") {
            builds += 1
            return [["mediaType": "ANIME", "mediaId": 99, "status": "COMPLETED"]]
        }
        #expect(retry.key == first.key)
        #expect(ImportApplyIdentity.signature(of: retry.items) == ImportApplyIdentity.signature(of: original))
        #expect(builds == 1, "a library change must not rebuild the lost action")

        let other = attempt.begin(anchor: "confirm:m2", stamp: "sel") { original }
        #expect(other.key != first.key)
        attempt.complete()
        let again = attempt.begin(anchor: "confirm:m2", stamp: "sel") { original }
        #expect(again.key != other.key)

        let invalid = ConciergeRequestFailure.invalid(message: "no", code: "INVALID_ITEM", index: 0)
        _ = attempt.begin(anchor: "confirm:m2", stamp: "sel") { original }
        attempt.observe(invalid)
        let afterRejection = attempt.begin(anchor: "confirm:m2", stamp: "sel") { original }
        #expect(afterRejection.key != again.key)
    }

    @Test("A partial confirmation names only the applied title, and Undo keeps skipped edits")
    func partialConfirmationAndUndo() throws {
        let text = ImportApplyConfirmation.text(
            summary: "1 item added, some need review",
            applied: [ImportApplyConfirmation.Line(mediaType: "ANIME", mediaId: 7, title: "Frieren")],
            rejected: [ImportApplyConfirmation.Line(mediaType: "MANGA", mediaId: 7, title: "Berserk")]
        )
        #expect(text.contains("· Frieren"))
        #expect(text.contains("Needs review:"))
        #expect(text.contains("· Berserk"))
        #expect(!text.contains("· Frieren\n· Berserk"))

        let undo = try JSONDecoder().decode(
            ConciergeUndoResponse.self,
            from: Data(#"{"success":true,"sessionId":"s1","reverted":[{"mediaType":"ANIME","mediaId":7,"undoType":"restored"}],"skipped":[{"mediaType":"ANIME","mediaId":8,"reason":"edited_since_import"}],"warnings":[],"errors":[],"status":"undone"}"#.utf8)
        )
        #expect(undo.keptCount == 1)
        #expect(undo.reverted?.first?.undoType == "restored")
        #expect(ImportApplyDelivery.of(URLError(.networkConnectionLost)) == .uncertain)
        #expect(ImportApplyDelivery.of(ConciergeRequestFailure.retryable(message: "Import could not be saved", retryAfterSeconds: nil)) == .uncertain)
        #expect(ImportApplyDelivery.of(ConciergeRequestFailure.invalid(message: "no", code: "INVALID_ITEM", index: 0)) == .terminal)
    }

    @Test("Editing the selected candidate starts a new action; an unedited retry stays frozen")
    @MainActor
    func editedCandidateDoesNotReplayTheOldTitle() {
        let line = "line-1"
        func choice(type: String, id: Int) -> ImportSelectionStamp.Choice {
            ImportSelectionStamp.Choice(lineId: line, mediaType: type, mediaId: id, action: nil, excluded: false)
        }
        let animeStamp = ImportSelectionStamp.make(choices: [choice(type: "ANIME", id: 7)])
        let mangaStamp = ImportSelectionStamp.make(choices: [choice(type: "MANGA", id: 99)])
        #expect(animeStamp != mangaStamp)

        let attempt = ImportApplyAttempt()
        let anime: [[String: Any]] = [["mediaType": "ANIME", "mediaId": 7, "status": "PLANNING"]]
        let manga: [[String: Any]] = [["mediaType": "MANGA", "mediaId": 99, "status": "READING"]]
        let first = attempt.begin(anchor: "confirm:m1", stamp: animeStamp) { anime }
        attempt.observe(URLError(.networkConnectionLost))
        let edited = attempt.begin(anchor: "confirm:m1", stamp: mangaStamp) { manga }
        #expect(edited.key != first.key)
        #expect(ImportApplyIdentity.signature(of: edited.items) == ImportApplyIdentity.signature(of: manga))

        attempt.observe(URLError(.timedOut))
        let unedited = attempt.begin(anchor: "confirm:m1", stamp: mangaStamp) {
            [["mediaType": "ANIME", "mediaId": 1, "status": "COMPLETED"]]
        }
        #expect(unedited.key == edited.key)
        #expect(ImportApplyIdentity.signature(of: unedited.items) == ImportApplyIdentity.signature(of: manga))
    }

    @Test("Profile retries a lost import before reconciliation, and a new import does not")
    @MainActor
    func profileRetrySkipsFreshReconciliation() {
        let attempt = ImportApplyAttempt()
        let original: [[String: Any]] = [["mediaType": "ANIME", "mediaId": 7, "status": "PLANNING"]]
        let first = attempt.begin(anchor: ProfileImportRecovery.anchor, stamp: ProfileImportRecovery.stamp) { original }
        attempt.observe(URLError(.networkConnectionLost))

        let replay = ProfileImportRecovery.replayIfRetrying(intent: .retryUnresolved, attempt: attempt)
        #expect(replay?.key == first.key)
        #expect(ImportApplyIdentity.signature(of: replay?.items ?? []) == ImportApplyIdentity.signature(of: original))
        #expect(ProfileImportRecovery.replayIfRetrying(intent: .newImport, attempt: attempt) == nil)

        attempt.abandon()
        let restarted = attempt.begin(anchor: ProfileImportRecovery.anchor, stamp: ProfileImportRecovery.stamp) {
            [["mediaType": "MANGA", "mediaId": 3, "status": "READING"]]
        }
        #expect(restarted.key != first.key)
    }

    @Test("A late Profile Undo does not publish into a dismissed or replaced card")
    @MainActor
    func lateProfileUndoDoesNotRestoreTheCard() {
        let lifetime = ProfileImportCardLifetime()
        let started = lifetime.generation
        #expect(ProfileUndoPublication.mayApply(
            startedGeneration: started,
            generation: lifetime.generation,
            visibleSession: "s-replay",
            startedSession: "s-replay"
        ))

        lifetime.invalidate()
        #expect(!ProfileUndoPublication.mayApply(
            startedGeneration: started,
            generation: lifetime.generation,
            visibleSession: nil,
            startedSession: "s-replay"
        ))
        #expect(!ProfileUndoPublication.mayApply(
            startedGeneration: started,
            generation: lifetime.generation,
            visibleSession: "s-newer",
            startedSession: "s-replay"
        ))
    }
}
