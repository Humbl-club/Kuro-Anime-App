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
