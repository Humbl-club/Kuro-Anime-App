import Foundation
import KuroCore
@testable import KuroLibrary
import Testing

// Library contract v2: `LibraryEdit` carries the repeat count and the started / finished dates, and
// `LibraryEntry` reads them back. Every store test drives the production `LibraryStore` against
// `ControlledBackend` (see `LibraryStoreTests.swift`).

@MainActor
@Suite("Library contract v2: repeat count and dates")
struct LibraryEditV2Tests {
    private static let key = MediaKey(kind: .anime, id: 1)

    /// A tracked title on row 7. `metadata == nil` models a cached row whose server dates are unknown.
    private static func entry(
        _ metadata: LibrarySourceMetadata?,
        status: ListStatus = .current,
        updatedAt: Date = Fixture.earlier
    ) -> LibraryEntry {
        LibraryEntry(
            key: key, rowId: 7, status: status, progress: 0,
            createdAt: Fixture.earlier, updatedAt: updatedAt, sourceMetadata: metadata
        )
    }

    private static func date(_ raw: String) throws -> PartialDate {
        try #require(PartialDate(raw: raw))
    }

    // MARK: Traced

    @Test("Repeat count and dates (year, year-month, full) are edited through LibraryEdit and read back from LibraryEntry",
          .timeLimit(.minutes(1)))
    func repeatCountAndDatesTravelThroughLibraryEdit() async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)
            // Known and empty: the dates were read from the server and there is no value.
            let seeded = Self.entry(LibrarySourceMetadata(repeatCount: 0))
            #expect(seeded.datesKnown)
            try await h.load([seeded])

            let started = try Self.date("2024-05")
            let finished = try Self.date("2024-07-14")
            let edit = LibraryEdit(repeatCount: .set(2), startedOn: .set(started), finishedOn: .set(finished))
            let pending = Task { await h.store.apply(edit, to: Self.key) }
            let call = try await h.nextCall()

            #expect(call.request == .edit(edit, createIfMissing: nil, baseRevision: nil))
            guard case .edit(let sent, _, _) = call.request else {
                Issue.record("expected an edit request, got \(call.request)")
                return
            }
            #expect(sent.status == .unchanged)
            #expect(sent.progress == .unchanged)
            #expect(sent.rating == .unchanged)
            #expect(sent.notes == .unchanged)
            #expect(sent.verdict == .unchanged)
            #expect(sent.repeatCount == .set(2))
            #expect(sent.startedOn == .set(started))
            #expect(sent.finishedOn == .set(finished))

            // The optimistic projection is read before the backend answers.
            #expect(h.store.entry(for: Self.key)?.repeatCount == 2)
            #expect(h.store.entry(for: Self.key)?.startedOn?.raw == "2024-05")
            #expect(h.store.entry(for: Self.key)?.finishedOn?.raw == "2024-07-14")

            let canonical = Self.entry(
                LibrarySourceMetadata(repeatCount: 2, startedRaw: "2024-05", finishedRaw: "2024-07-14"),
                updatedAt: Fixture.now
            )
            call.answer(.write(LibraryWriteResult(entry: canonical, created: false)))
            let change = try #require(await pending.value.change)

            #expect(h.store.entry(for: Self.key)?.repeatCount == 2)
            #expect(h.store.entry(for: Self.key)?.startedOn?.precision == .month)
            #expect(h.store.entry(for: Self.key)?.finishedOn?.raw == "2024-07-14")
            // The pre-image is limited to what the edit changed: known, and empty.
            #expect(change.previous?.repeatCount == 0)
            #expect(change.previous?.startedOn == nil)
            #expect(change.previous?.finishedOn == nil)
            #expect(change.previous?.datesKnown == true)
        }
    }

    // MARK: Validation

    @Test("A repeat count outside 0...999, or cleared, fails before any request or projection change",
          .timeLimit(.minutes(1)),
          arguments: [
              LibraryEdit(repeatCount: .set(-1)),
              LibraryEdit(repeatCount: .set(1000)),
              LibraryEdit(repeatCount: .clear),
          ])
    func validationRejectsNegativeOrHugeRepeatCountAndClear(edit: LibraryEdit) async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)
            let seeded = Self.entry(LibrarySourceMetadata(repeatCount: 1))
            try await h.load([seeded])

            #expect(await h.store.apply(edit, to: Self.key) == .failed(.invalidValue(field: "repeatCount")))
            // A sent request would wait for an answer and hit the time limit; the projection is untouched.
            #expect(h.store.entry(for: Self.key) == seeded)
        }
    }

    @Test("The bounds 0 and 999 are valid, and dates can be set and cleared", arguments: [
        LibraryEdit(repeatCount: .set(0)),
        LibraryEdit(repeatCount: .set(999)),
        LibraryEdit(startedOn: .clear),
        LibraryEdit(finishedOn: .clear),
    ])
    func boundsAndDateClearsAreValid(edit: LibraryEdit) {
        #expect(edit.validationError == nil)
        #expect(!edit.isEmpty)
    }

    // MARK: isProgressOnly

    @Test("A change that differs only in a date or the repeat count is not progress-only",
          arguments: [
              (LibrarySourceMetadata(repeatCount: 0), LibrarySourceMetadata(repeatCount: 0, startedRaw: "2024")),
              (LibrarySourceMetadata(repeatCount: 0, finishedRaw: "2024-05"), LibrarySourceMetadata(repeatCount: 0)),
              (LibrarySourceMetadata(repeatCount: 0), LibrarySourceMetadata(repeatCount: 3)),
          ])
    func dateOnlyChangeIsNotProgressOnly(before: LibrarySourceMetadata, after: LibrarySourceMetadata) {
        let previous = Self.entry(before)
        let current = Self.entry(after)
        let change = LibraryChange(
            key: Self.key, kind: .updated, previous: previous, current: current,
            mutationId: UUID(), account: AccountContext(userId: Fixture.userA, generation: 1)
        )
        #expect(!change.isProgressOnly)
    }

    @Test("A position-only change, and a change whose dates differ only in spelling, stay progress-only")
    func progressAndSpellingChangesStayProgressOnly() {
        var moved = Self.entry(LibrarySourceMetadata(repeatCount: 0, startedRaw: "2024-00-00"))
        moved.progress = 4
        let before = Self.entry(LibrarySourceMetadata(repeatCount: 0, startedRaw: "2024-00-00"))
        let progress = LibraryChange(
            key: Self.key, kind: .updated, previous: before, current: moved,
            mutationId: UUID(), account: AccountContext(userId: Fixture.userA, generation: 1)
        )
        #expect(progress.isProgressOnly)

        let respelled = Self.entry(LibrarySourceMetadata(repeatCount: 0, startedRaw: "2024"))
        let spelling = LibraryChange(
            key: Self.key, kind: .updated, previous: before, current: respelled,
            mutationId: UUID(), account: AccountContext(userId: Fixture.userA, generation: 1)
        )
        #expect(spelling.isProgressOnly, "2024-00-00 and 2024 are the same date")
    }

    // MARK: Helpers

    @Test("patchBodyOmittingProgress keeps the repeat count and both dates with the other side fields")
    func patchBodyKeepsRepeatCountAndDates() throws {
        let started = try Self.date("2024-05")
        let edit = LibraryEdit(
            status: .set(.completed), progress: .set(3), notes: .set("n"),
            repeatCount: .set(1), startedOn: .set(started), finishedOn: .clear
        )
        #expect(edit.patchBodyOmittingProgress == LibraryEdit(
            notes: .set("n"), repeatCount: .set(1), startedOn: .set(started), finishedOn: .clear
        ))
    }

    @Test("reverting restores an empty date with .clear and moves nothing else")
    func revertingRestoresEmptyDatesWithClear() {
        let current = Self.entry(LibrarySourceMetadata(repeatCount: 0, startedRaw: "2024"))
        let previous = Self.entry(LibrarySourceMetadata(repeatCount: 0))
        #expect(previous.datesKnown)

        let edit = LibraryEdit.reverting(current, to: previous)
        #expect(edit.startedOn == .clear)
        #expect(edit.status == .unchanged)
        #expect(edit.finishedOn == .unchanged)
        #expect(edit.repeatCount == .unchanged)
    }

    @Test("reverting restores a previous date and repeat count by value")
    func revertingRestoresPreviousValues() throws {
        let current = Self.entry(LibrarySourceMetadata(repeatCount: 2, startedRaw: "2025-01-02", finishedRaw: "2025-03"))
        let previous = Self.entry(LibrarySourceMetadata(repeatCount: 1, startedRaw: "2024-00-00", finishedRaw: "2025-03-00"))

        let edit = LibraryEdit.reverting(current, to: previous)
        #expect(edit.repeatCount == .set(1))
        #expect(edit.startedOn == .set(try Self.date("2024")))
        // 2025-03 and 2025-03-00 are one date: untouched.
        #expect(edit.finishedOn == .unchanged)
    }

    @Test("reverting never writes dates back to a pre-image whose dates were never read")
    func revertingNeverGuessesUnknownDates() {
        let current = Self.entry(LibrarySourceMetadata(repeatCount: 2, startedRaw: "2024"))
        let previous = Self.entry(nil)
        #expect(!previous.datesKnown)

        let edit = LibraryEdit.reverting(current, to: previous)
        #expect(edit.repeatCount == .unchanged)
        #expect(edit.startedOn == .unchanged)
        #expect(edit.finishedOn == .unchanged)
    }

    @Test("restoring a removed entry re-sends its dates when known, clears an empty one, and sends nothing when unknown")
    func restoringSendsDatesOnlyWhenKnown() throws {
        let known = Self.entry(LibrarySourceMetadata(repeatCount: 2, startedRaw: "2024-05", finishedRaw: nil))
        let restored = LibraryEdit.restoring(known)
        #expect(restored.repeatCount == .set(2))
        #expect(restored.startedOn == .set(try Self.date("2024-05")))
        #expect(restored.finishedOn == .clear)

        let unknown = LibraryEdit.restoring(Self.entry(nil))
        #expect(unknown.repeatCount == .unchanged)
        #expect(unknown.startedOn == .unchanged)
        #expect(unknown.finishedOn == .unchanged)
    }

    // MARK: Projection

    @Test("An optimistic edit that names no date leaves a cached row's dates unknown", .timeLimit(.minutes(1)))
    func optimisticEditWithoutDatesKeepsDatesUnknown() async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)
            let cached = Self.entry(nil)
            try await h.load([cached])

            let pending = Task { await h.store.apply(LibraryEdit(notes: .set("hi")), to: Self.key) }
            let call = try await h.nextCall()
            let optimistic = try #require(h.store.entry(for: Self.key))
            #expect(optimistic.notes == "hi")
            #expect(!optimistic.datesKnown, "a notes edit must not turn unknown dates into known-empty ones")
            #expect(optimistic.sourceMetadata == nil)

            var canonical = Self.entry(LibrarySourceMetadata(repeatCount: 0, startedRaw: "2020"), updatedAt: Fixture.now)
            canonical.notes = "hi"
            call.answer(.write(LibraryWriteResult(entry: canonical, created: false)))
            let change = try #require(await pending.value.change)
            #expect(h.store.entry(for: Self.key)?.startedOn?.raw == "2020")
            // The notes edit named no date, so the pre-image keeps the canonical dates.
            #expect(change.previous?.startedOn?.raw == "2020")
        }
    }

    @Test("A date edit on a cached row is projected at once, and its pre-image keeps the dates unknown",
          .timeLimit(.minutes(1)))
    func dateEditOnCachedRowKeepsPreImageUnknown() async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)
            try await h.load([Self.entry(nil)])

            let started = try Self.date("2024-05-07")
            let pending = Task { await h.store.apply(LibraryEdit(startedOn: .set(started)), to: Self.key) }
            let call = try await h.nextCall()
            #expect(h.store.entry(for: Self.key)?.startedOn == started)

            let canonical = Self.entry(
                LibrarySourceMetadata(repeatCount: 0, startedRaw: "2024-05-07"), updatedAt: Fixture.now
            )
            call.answer(.write(LibraryWriteResult(entry: canonical, created: false)))
            let change = try #require(await pending.value.change)

            #expect(change.current?.startedOn == started)
            #expect(change.previous?.datesKnown == false, "the value before the edit was never read")
            // Undo cannot restore what was never read, so it must not invent an empty date.
            let undo = LibraryEdit.reverting(try #require(change.current), to: try #require(change.previous))
            #expect(undo.startedOn == .unchanged)
        }
    }

    @Test("Undo of a date edit writes the previous date back, by value", .timeLimit(.minutes(1)))
    func undoRestoresThePreviousDate() async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)
            let seeded = Self.entry(LibrarySourceMetadata(repeatCount: 0, startedRaw: "2024-05-00"))
            try await h.load([seeded])

            let pending = Task { await h.store.apply(LibraryEdit(startedOn: .set(try Self.date("2025"))), to: Self.key) }
            let call = try await h.nextCall()
            let after = Self.entry(LibrarySourceMetadata(repeatCount: 0, startedRaw: "2025"), updatedAt: Fixture.now)
            call.answer(.write(LibraryWriteResult(entry: after, created: false)))
            let change = try #require(await pending.value.change)
            #expect(change.previous?.startedOn?.raw == "2024-05")

            let undo = Task { await h.store.undo(change) }
            let undoCall = try await h.nextCall()
            #expect(undoCall.request == .edit(
                LibraryEdit(startedOn: .set(try Self.date("2024-05"))), createIfMissing: nil, baseRevision: nil
            ))
            undoCall.answer(.write(LibraryWriteResult(
                entry: Self.entry(LibrarySourceMetadata(repeatCount: 0, startedRaw: "2024-05"), updatedAt: Fixture.now),
                created: false
            )))
            _ = await undo.value
            #expect(h.store.entry(for: Self.key)?.startedOn?.raw == "2024-05")
        }
    }
}
