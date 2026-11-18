//
//  TrackingDraftTests.swift
//  KuroTests
//
//  The tracking editor's save rule (`TrackingDraft`, used by AddToListSheet): which fields one save
//  names, the 1...10 rating scale, clearing a rating/note the entry had, the completion progress
//  rule, and that the verdict is never part of the edit. One test runs a draft through the real
//  `LibraryStore` over `FakeLibraryBackend` to show the stored row afterwards. The quick status
//  chips' rule (`QuickStatusChange`) is tested alongside.
//

import Testing
import Foundation
import KuroCore
import KuroLibrary
@testable import Kuro

@MainActor
struct TrackingDraftTests {
    private static let key = MediaKey(kind: .anime, id: 42)

    private static func entry(
        status: ListStatus = .current,
        progress: Int = 3,
        rating: Int? = nil,
        notes: String? = nil,
        verdict: Verdict? = nil
    ) -> LibraryEntry {
        FakeLibraryBackend.entry(.anime, 42, status: status, progress: progress, rating: rating, notes: notes, verdict: verdict)
    }

    // MARK: Prefill

    @Test func untrackedTitleStartsPlannedAndEmpty() {
        let draft = TrackingDraft(entry: nil)
        #expect(draft.status == .planning)
        #expect(draft.progress == 0)
        #expect(draft.score == 0)
        #expect(draft.notes == "")
        #expect(draft.originalRating == nil)
        #expect(draft.originalNotes == nil)
    }

    @Test func prefillUsesTheDatabaseRatingScale() {
        let draft = TrackingDraft(entry: Self.entry(status: .paused, progress: 7, rating: 7, notes: "slow start"))
        #expect(draft.status == .paused)
        #expect(draft.progress == 7)
        #expect(draft.score == 7)
        #expect(draft.notes == "slow start")
    }

    // MARK: Rating

    @Test func unratedTitleThatStaysUnratedDoesNotTouchTheRating() {
        let edit = TrackingDraft(entry: nil).edit(maxProgress: 12)
        #expect(edit.rating == .unchanged)

        let tracked = TrackingDraft(entry: Self.entry(rating: nil)).edit(maxProgress: 12)
        #expect(tracked.rating == .unchanged)
    }

    @Test func emptyingAnExistingRatingClearsIt() {
        var draft = TrackingDraft(entry: Self.entry(rating: 8))
        draft.score = 0
        #expect(draft.edit(maxProgress: 12).rating == .clear)
    }

    @Test(arguments: 1...10)
    func scoreIsSentOnTheDatabaseScale(score: Int) throws {
        var draft = TrackingDraft(entry: nil)
        draft.score = score
        let expected = try #require(UserRating(value: score))
        #expect(draft.edit(maxProgress: 0).rating == .set(expected))
    }

    @Test func outOfScaleScoreIsNeverSentAndNeverClears() {
        var draft = TrackingDraft(entry: Self.entry(rating: 8))
        draft.score = 80
        #expect(draft.edit(maxProgress: 12).rating == .unchanged)
    }

    // MARK: Notes

    @Test func notesAreTrimmed() {
        var draft = TrackingDraft(entry: nil)
        draft.notes = "  rewatch the finale \n"
        #expect(draft.edit(maxProgress: 0).notes == .set("rewatch the finale"))
    }

    @Test func emptyingAnExistingNoteClearsIt() {
        var draft = TrackingDraft(entry: Self.entry(notes: "keep"))
        draft.notes = "   \n"
        #expect(draft.edit(maxProgress: 0).notes == .clear)
    }

    @Test func blankNoteOnATitleWithoutNoteIsNotSent() {
        var draft = TrackingDraft(entry: nil)
        draft.notes = "  "
        #expect(draft.edit(maxProgress: 0).notes == .unchanged)
    }

    // MARK: Status / progress

    @Test func completingWithNoProgressMarksEveryKnownEpisode() {
        var draft = TrackingDraft(entry: nil)
        draft.status = .completed
        let edit = draft.edit(maxProgress: 24)
        #expect(edit.status == .set(.completed))
        #expect(edit.progress == .set(24))
        #expect(draft.createIfMissing == .completed)
    }

    @Test func completingWithUnknownTotalKeepsTheEnteredProgress() {
        var draft = TrackingDraft(entry: nil)
        draft.status = .completed
        #expect(draft.edit(maxProgress: 0).progress == .set(0))

        draft.progress = 5
        #expect(draft.edit(maxProgress: 24).progress == .set(5))
    }

    @Test func statusChangeOnExistingEntryNamesStatusAndProgressAndKeepsTheVerdict() throws {
        var draft = TrackingDraft(entry: Self.entry(status: .planning, progress: 3, rating: 6, notes: "n", verdict: .masterpiece))
        draft.status = .current
        let six = try #require(UserRating(value: 6))

        let edit = draft.edit(maxProgress: 12)
        #expect(edit == LibraryEdit(
            status: .set(.current),
            progress: .set(3),
            rating: .set(six),
            notes: .set("n"),
            verdict: .unchanged
        ))
        #expect(draft.createIfMissing == .current)
    }

    @Test func verdictIsNeverPartOfTheEdit() {
        for verdict in [Verdict.masterpiece, .okay, .bad] {
            var draft = TrackingDraft(entry: Self.entry(rating: 9, notes: "x", verdict: verdict))
            draft.status = .dropped
            draft.score = 0
            draft.notes = ""
            #expect(draft.edit(maxProgress: 12).verdict == .unchanged)
        }
    }

    // MARK: Through the store

    @Test func savingThroughTheStoreChangesExactlyTheEditedFields() async throws {
        let account = AccountContext(userId: "user-a", generation: 1)
        let backend = FakeLibraryBackend()
        backend.setRows([Self.entry(status: .current, progress: 3, rating: 8, notes: "keep", verdict: .okay)], for: account.userId)
        let library = LibraryStore(backend: backend)
        library.bind(account)
        try await library.refresh()

        var draft = TrackingDraft(entry: library.entry(for: Self.key))
        draft.status = .completed
        draft.progress = 0
        draft.score = 0

        let outcome = await library.apply(draft.edit(maxProgress: 12), to: Self.key, createIfMissing: draft.createIfMissing)

        #expect(outcome.error == nil)
        let stored = try #require(backend.rows(for: account.userId)[Self.key])
        #expect(stored.status == .completed)
        #expect(stored.progress == 12)
        #expect(stored.rating == nil)
        #expect(stored.notes == "keep")
        #expect(stored.verdict == .okay)
        #expect(library.entry(for: Self.key)?.verdict == .okay)
    }

    // MARK: Repeat count and dates (F2.4)

    private static func date(_ raw: String) throws -> PartialDate {
        try #require(PartialDate(raw: raw))
    }

    private static func datedEntry(
        started: String? = "2024-00-00", finished: String? = "2024-07-14", repeatCount: Int = 1
    ) -> LibraryEntry {
        var entry = Self.entry(status: .completed, progress: 12)
        entry.sourceMetadata = LibrarySourceMetadata(repeatCount: repeatCount, startedRaw: started, finishedRaw: finished)
        return entry
    }

    @Test func untouchedDatesSendNothing() {
        let edit = TrackingDraft(entry: Self.datedEntry()).edit(maxProgress: 12)
        #expect(edit.startedOn == .unchanged)
        #expect(edit.finishedOn == .unchanged)
        #expect(edit.repeatCount == .unchanged)
    }

    @Test func changedDatesAndRepeatAreSent() throws {
        var draft = TrackingDraft(entry: Self.datedEntry())
        draft.startedOn = try Self.date("2024-05")
        draft.finishedOn = nil
        draft.repeatCount = 2
        let edit = draft.edit(maxProgress: 12)
        #expect(edit.startedOn == .set(try Self.date("2024-05")))
        #expect(edit.finishedOn == .clear)
        #expect(edit.repeatCount == .set(2))
    }

    @Test func hasChangesSeesDatesAndRepeat() throws {
        let baseline = TrackingDraft(entry: Self.datedEntry())
        #expect(!TrackingDraft(entry: Self.datedEntry()).hasChanges(from: baseline))

        var finished = baseline
        finished.finishedOn = nil
        #expect(finished.hasChanges(from: baseline))

        var started = baseline
        started.startedOn = try Self.date("2023")
        #expect(started.hasChanges(from: baseline))

        var repeats = baseline
        repeats.repeatCount = 5
        #expect(repeats.hasChanges(from: baseline))
    }

    @Test func unknownDatesNeverCleared() {
        var cached = Self.entry()
        cached.sourceMetadata = nil
        let draft = TrackingDraft(entry: cached)
        #expect(!draft.datesKnown)
        let edit = draft.edit(maxProgress: 12)
        #expect(edit.repeatCount == .unchanged)
        #expect(edit.startedOn == .unchanged)
        #expect(edit.finishedOn == .unchanged)
    }

    @Test func unknownValuesCannotBeEditedOrSent() throws {
        var cached = Self.entry()
        cached.sourceMetadata = nil
        var draft = TrackingDraft(entry: cached)
        #expect(!draft.datesKnown)
        // Even if a binding writes into the draft, nothing is sent from an unknown baseline.
        draft.repeatCount = 5
        draft.startedOn = try Self.date("2024-05-07")
        draft.finishedOn = try Self.date("2024-06")
        let edit = draft.edit(maxProgress: 12)
        #expect(edit.repeatCount == .unchanged && edit.startedOn == .unchanged && edit.finishedOn == .unchanged)
        #expect(edit.startedRawVerbatim == nil && edit.finishedRawVerbatim == nil)
    }

    @Test func valuesBecomeEditableOnceTheyAreKnown() throws {
        var cached = Self.entry()
        cached.sourceMetadata = nil
        var draft = TrackingDraft(entry: cached)
        var known = cached
        known.sourceMetadata = LibrarySourceMetadata(repeatCount: 2, startedRaw: "2024-05")
        draft.adoptDates(from: known)
        #expect(draft.datesKnown && draft.repeatCount == 2 && draft.startedOn == PartialDate(raw: "2024-05"))
        #expect(draft.edit(maxProgress: 12).repeatCount == .unchanged, "adopting the stored values is not a change")
        draft.repeatCount = 3
        #expect(draft.edit(maxProgress: 12).repeatCount == .set(3))
    }

    @Test func unparseableImportedDateIsNeverRewrittenOrBlanked() throws {
        let draft = TrackingDraft(entry: Self.datedEntry(started: "not-a-date"))
        #expect(draft.startedOn == nil)
        #expect(draft.edit(maxProgress: 12).startedOn == .unchanged)

        var set = draft
        set.startedOn = try Self.date("2024-05-07")
        #expect(set.edit(maxProgress: 12).startedOn == .set(try Self.date("2024-05-07")))
    }

    @Test func spellingOfAnUntouchedDateDoesNotMatter() {
        // "2024-00-00" (import form) and "2024" are one date: an untouched draft sends nothing.
        let draft = TrackingDraft(entry: Self.datedEntry(started: "2024-00-00"))
        #expect(draft.startedOn == PartialDate(raw: "2024"))
        #expect(draft.edit(maxProgress: 12).startedOn == .unchanged)
    }

    @Test func untrackedTitleStartsWithNoDatesAndNoRepeat() {
        let draft = TrackingDraft(entry: nil)
        #expect(draft.repeatCount == 0 && draft.startedOn == nil && draft.finishedOn == nil)
        #expect(draft.datesKnown)
        let edit = draft.edit(maxProgress: 12)
        #expect(edit.repeatCount == .unchanged && edit.startedOn == .unchanged && edit.finishedOn == .unchanged)
    }
}

/// The quick status chips' rule (`QuickStatusChange`, used by QuickVerdictActionCard and the
/// verdict picker): progress is named only when completing a title with a known total.
@MainActor
struct QuickStatusChangeTests {
    @Test(arguments: [ListStatus.planning, .current, .paused, .dropped, .repeating])
    func nonCompletedStatusNeverSendsTheProjectionsProgress(status: ListStatus) {
        let edit = QuickStatusChange.edit(to: status, currentProgress: 5, total: 24)
        #expect(edit == LibraryEdit(status: .set(status)))
    }

    @Test func completingWithKnownTotalMarksEveryEpisode() {
        #expect(QuickStatusChange.edit(to: .completed, currentProgress: 5, total: 24).progress == .set(24))
        #expect(QuickStatusChange.edit(to: .completed, currentProgress: nil, total: 24).progress == .set(24))
    }

    @Test func completingNeverLowersTheProgressHeld() {
        #expect(QuickStatusChange.edit(to: .completed, currentProgress: 30, total: 24).progress == .set(30))
    }

    @Test func completingWithUnknownTotalLeavesProgressAlone() {
        let edit = QuickStatusChange.edit(to: .completed, currentProgress: 5, total: 0)
        #expect(edit == LibraryEdit(status: .set(.completed)))
    }

    @Test func ratingNotesAndVerdictAreNeverNamed() {
        for status in ListStatus.allCases {
            let edit = QuickStatusChange.edit(to: status, currentProgress: 3, total: 12)
            #expect(edit.rating == .unchanged)
            #expect(edit.notes == .unchanged)
            #expect(edit.verdict == .unchanged)
        }
    }
}
