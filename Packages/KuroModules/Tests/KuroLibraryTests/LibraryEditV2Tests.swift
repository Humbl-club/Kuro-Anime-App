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

    // MARK: Date fill (Task F2.3)

    /// 2026-03-01T23:30:00Z: still the 1st in UTC, already the 2nd in Berlin.
    private static let nearMidnight = Date(timeIntervalSince1970: 1_772_407_800)

    private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        return calendar
    }

    private static let berlin = calendar("Europe/Berlin")
    private static let utc = calendar("UTC")

    /// Loads `seeded`, applies `edit` and returns the request the backend received.
    private static func request(
        _ h: Harness, seeded: LibraryEntry, edit: LibraryEdit
    ) async throws -> (call: ControlledBackend.Call, sent: LibraryEdit, outcome: Task<LibraryOutcome, Never>) {
        try await h.load([seeded])
        let pending = Task { await h.store.apply(edit, to: key) }
        let call = try await h.nextCall()
        guard case .edit(let sent, _, _) = call.request else {
            Issue.record("expected an edit request, got \(call.request)")
            throw LibraryError.unavailable(message: "not an edit")
        }
        return (call, sent, pending)
    }

    @Test("Moving a title to Watching fills an empty start date with today; Undo restores both without refilling",
          .timeLimit(.minutes(1)))
    func statusChangeFillsEmptyDatesWithUndo() async throws {
        try await withHarness(now: Self.nearMidnight, calendar: Self.berlin, dateAutofill: true) { h in
            h.signIn(Fixture.userA)
            let seeded = Self.entry(LibrarySourceMetadata(repeatCount: 0), status: .planning)
            try await h.load([seeded])

            let pending = Task { await h.store.apply(LibraryEdit(status: .set(.current)), to: Self.key) }
            let call = try await h.nextCall()
            guard case .edit(let sent, _, _) = call.request else {
                Issue.record("expected an edit request, got \(call.request)")
                return
            }
            #expect(sent.status == .set(.current))
            #expect(sent.startedOn == .set(try Self.date("2026-03-02")))
            #expect(sent.finishedOn == .unchanged)

            let filled = Self.entry(
                LibrarySourceMetadata(repeatCount: 0, startedRaw: "2026-03-02"), status: .current, updatedAt: Fixture.now
            )
            call.answer(.write(LibraryWriteResult(entry: filled, created: false)))
            let change = try #require(await pending.value.change)
            #expect(h.store.entry(for: Self.key)?.startedOn?.raw == "2026-03-02")

            let undo = Task { await h.store.undo(change) }
            let undoCall = try await h.nextCall()
            #expect(undoCall.request == .edit(
                LibraryEdit(status: .set(.planning), startedOn: .clear), createIfMissing: nil, baseRevision: nil
            ))
            undoCall.answer(.write(LibraryWriteResult(
                entry: Self.entry(LibrarySourceMetadata(repeatCount: 0), status: .planning, updatedAt: Fixture.now),
                created: false
            )))
            _ = await undo.value
            #expect(h.store.entry(for: Self.key)?.status == .planning)
            #expect(h.store.entry(for: Self.key)?.startedOn == nil)
        }
    }

    @Test("Completing fills only the finish date", .timeLimit(.minutes(1)))
    func completedFillsFinishNotStart() async throws {
        try await withHarness(now: Self.nearMidnight, calendar: Self.berlin, dateAutofill: true) { h in
            h.signIn(Fixture.userA)
            let r = try await Self.request(h, seeded: Self.entry(LibrarySourceMetadata(repeatCount: 0), status: .current),
                                           edit: LibraryEdit(status: .set(.completed)))
            #expect(r.sent.finishedOn == .set(try Self.date("2026-03-02")))
            #expect(r.sent.startedOn == .unchanged)
            r.call.answer(.failure(.retryable(message: "end of test")))
            _ = await r.outcome.value
        }
    }

    @Test("Undo never fills dates: it restores the status and clears only the date the fill added",
          .timeLimit(.minutes(1)))
    func undoNeverFillsDates() async throws {
        try await withHarness(now: Self.nearMidnight, calendar: Self.berlin, dateAutofill: true) { h in
            h.signIn(Fixture.userA)
            let r = try await Self.request(h, seeded: Self.entry(LibrarySourceMetadata(repeatCount: 0), status: .current),
                                           edit: LibraryEdit(status: .set(.completed)))
            r.call.answer(.write(LibraryWriteResult(
                entry: Self.entry(LibrarySourceMetadata(repeatCount: 0, finishedRaw: "2026-03-02"),
                                  status: .completed, updatedAt: Fixture.now),
                created: false
            )))
            let change = try #require(await r.outcome.value.change)

            let undo = Task { await h.store.undo(change) }
            let undoCall = try await h.nextCall()
            guard case .edit(let sent, _, _) = undoCall.request else {
                Issue.record("expected an edit request, got \(undoCall.request)")
                return
            }
            // Going back to Watching must not fill a start date, although the start date is empty.
            #expect(sent.status == .set(.current))
            #expect(sent.finishedOn == .clear)
            #expect(sent.startedOn == .unchanged)
            undoCall.answer(.failure(.retryable(message: "end of test")))
            _ = await undo.value
        }
    }

    @Test("The fill uses the injected calendar: the same instant is the 1st in UTC", .timeLimit(.minutes(1)))
    func fillUsesInjectedCalendarNearMidnight() async throws {
        try await withHarness(now: Self.nearMidnight, calendar: Self.utc, dateAutofill: true) { h in
            h.signIn(Fixture.userA)
            let r = try await Self.request(h, seeded: Self.entry(LibrarySourceMetadata(repeatCount: 0), status: .planning),
                                           edit: LibraryEdit(status: .set(.current)))
            #expect(r.sent.startedOn == .set(try Self.date("2026-03-01")))
            r.call.answer(.failure(.retryable(message: "end of test")))
            _ = await r.outcome.value
        }
    }

    @Test("Unknown, unparseable or unchanged-status dates are never filled", .timeLimit(.minutes(1)),
          arguments: [
              (nil as LibrarySourceMetadata?, ListStatus.planning),
              (LibrarySourceMetadata(repeatCount: 0, startedRaw: "not-a-date"), ListStatus.planning),
              (LibrarySourceMetadata(repeatCount: 0), ListStatus.current),
          ])
    func unknownOrUnparseableDatesAreNeverFilled(metadata: LibrarySourceMetadata?, status: ListStatus) async throws {
        try await withHarness(now: Self.nearMidnight, calendar: Self.berlin, dateAutofill: true) { h in
            h.signIn(Fixture.userA)
            let r = try await Self.request(h, seeded: Self.entry(metadata, status: status),
                                           edit: LibraryEdit(status: .set(.current)))
            #expect(r.sent.startedOn == .unchanged)
            #expect(r.sent.finishedOn == .unchanged)
            r.call.answer(.failure(.retryable(message: "end of test")))
            _ = await r.outcome.value
        }
    }

    @Test("A cached row that first gets an optimistic notes edit stays unknown, so a later status change fills nothing",
          .timeLimit(.minutes(1)))
    func optimisticNotesEditDoesNotMakeDatesKnownForTheFill() async throws {
        try await withHarness(now: Self.nearMidnight, calendar: Self.berlin, dateAutofill: true) { h in
            h.signIn(Fixture.userA)
            try await h.load([Self.entry(nil, status: .planning)])

            let notes = Task { await h.store.apply(LibraryEdit(notes: .set("hi")), to: Self.key) }
            let notesCall = try await h.nextCall()
            let status = Task { await h.store.apply(LibraryEdit(status: .set(.current)), to: Self.key) }
            await h.waitUntil { h.store.entry(for: Self.key)?.status == .current }
            #expect(h.store.entry(for: Self.key)?.datesKnown == false)

            var answered = Self.entry(nil, status: .planning, updatedAt: Fixture.now)
            answered.notes = "hi"
            notesCall.answer(.write(LibraryWriteResult(entry: answered, created: false)))
            _ = await notes.value
            let statusCall = try await h.nextCall()
            guard case .edit(let sent, _, _) = statusCall.request else {
                Issue.record("expected an edit request, got \(statusCall.request)")
                return
            }
            #expect(sent.startedOn == .unchanged)
            statusCall.answer(.failure(.retryable(message: "end of test")))
            _ = await status.value
        }
    }

    @Test("A date the user has just set, still in flight, is not overwritten by the fill", .timeLimit(.minutes(1)))
    func pendingOptimisticDateBeatsFill() async throws {
        try await withHarness(now: Self.nearMidnight, calendar: Self.berlin, dateAutofill: true) { h in
            h.signIn(Fixture.userA)
            try await h.load([Self.entry(LibrarySourceMetadata(repeatCount: 0), status: .planning)])

            let manualDate = try Self.date("2020")
            let manual = Task { await h.store.apply(LibraryEdit(startedOn: .set(manualDate)), to: Self.key) }
            let manualCall = try await h.nextCall()
            let status = Task { await h.store.apply(LibraryEdit(status: .set(.current)), to: Self.key) }
            await h.waitUntil { h.store.entry(for: Self.key)?.status == .current }

            manualCall.answer(.failure(.retryable(message: "lost")))
            _ = await manual.value
            let statusCall = try await h.nextCall()
            guard case .edit(let sent, _, _) = statusCall.request else {
                Issue.record("expected an edit request, got \(statusCall.request)")
                return
            }
            // While the manual date was pending the fill saw it; nothing was auto-added.
            #expect(sent.startedOn == .unchanged)
            statusCall.answer(.failure(.retryable(message: "end of test")))
            _ = await status.value
        }
    }

    @Test("Creating a title as Watching fills its start date", .timeLimit(.minutes(1)))
    func creatingAsWatchingFillsStart() async throws {
        try await withHarness(now: Self.nearMidnight, calendar: Self.berlin, dateAutofill: true) { h in
            h.signIn(Fixture.userA)
            try await h.load([])
            let pending = Task {
                await h.store.apply(LibraryEdit(status: .set(.current)), to: Self.key, createIfMissing: .current)
            }
            let call = try await h.nextCall()
            guard case .edit(let sent, let create, _) = call.request else {
                Issue.record("expected an edit request, got \(call.request)")
                return
            }
            #expect(create == .current)
            #expect(sent.startedOn == .set(try Self.date("2026-03-02")))
            call.answer(.failure(.retryable(message: "end of test")))
            _ = await pending.value
        }
    }

    @Test("A date named by the edit beats the fill", .timeLimit(.minutes(1)))
    func explicitDateBeatsFill() async throws {
        try await withHarness(now: Self.nearMidnight, calendar: Self.berlin, dateAutofill: true) { h in
            h.signIn(Fixture.userA)
            let edit = LibraryEdit(status: .set(.current), startedOn: .set(try Self.date("2020")))
            let r = try await Self.request(h, seeded: Self.entry(LibrarySourceMetadata(repeatCount: 0), status: .planning),
                                           edit: edit)
            #expect(r.sent.startedOn == .set(try Self.date("2020")))
            r.call.answer(.failure(.retryable(message: "end of test")))
            _ = await r.outcome.value
        }
    }

    @Test("Flag off: a status change adds no date leg; a hand-edited date is still one normal write",
          .timeLimit(.minutes(1)))
    func flagOffSendsNoRequest() async throws {
        // Fence off: the single PATCH carries no date.
        try await withHarness(now: Self.nearMidnight, calendar: Self.berlin) { h in
            h.signIn(Fixture.userA)
            let r = try await Self.request(h, seeded: Self.entry(LibrarySourceMetadata(repeatCount: 0), status: .planning),
                                           edit: LibraryEdit(status: .set(.current)))
            #expect(r.sent.startedOn == .unchanged)
            r.call.answer(.failure(.retryable(message: "end of test")))
            _ = await r.outcome.value
        }

        // Fence on: one durable mutation, zero PATCH calls, then one normal write for a hand-edited date.
        let h = try await DurableDateHarness(autofill: false)
        defer { h.close() }
        let outcome = await h.store.apply(LibraryEdit(status: .set(.current)), to: h.key)
        #expect(outcome.change != nil)
        try await h.waitUntil { h.sender.calls.count == 1 }
        #expect(h.sender.calls[0].count == 1)
        #expect(h.sender.calls[0][0].status == "CURRENT")
        #expect(h.backend.edits.isEmpty)
        #expect(h.store.entry(for: h.key)?.startedOn == nil)

        let manual = try Self.date("2024-05")
        _ = await h.store.apply(LibraryEdit(startedOn: .set(manual)), to: h.key)
        #expect(h.backend.edits == [LibraryEdit(startedOn: .set(manual))])
    }

    @Test("Fence on: the fill is a second leg; a failed leg keeps the durable status and drops the date",
          .timeLimit(.minutes(1)))
    func offlineDurableStatusChangeStillAppliesWithoutDateFill() async throws {
        let h = try await DurableDateHarness(autofill: true)
        defer { h.close() }
        h.backend.failure = .retryable(message: "offline")
        let outcome = await h.store.apply(LibraryEdit(status: .set(.current)), to: h.key)
        #expect(outcome.change != nil, "the durable status change is the outcome; the fill is best effort")
        #expect(outcome.error == nil)
        #expect(h.store.entry(for: h.key)?.status == .current)
        #expect(h.store.entry(for: h.key)?.startedOn == nil)
        #expect(h.backend.edits.count == 1)
        #expect(h.backend.edits.first?.startedOn == .set(try Self.date("2026-03-02")))
        #expect(h.lease.calls == 1, "the added leg runs inside the credential lease")
    }

    @Test("Fence on: a caller's own notes failing still reports the old retryable message", .timeLimit(.minutes(1)))
    func failedOwnPatchLegStillReportsRetryable() async throws {
        let h = try await DurableDateHarness(autofill: true)
        defer { h.close() }
        h.backend.failure = .retryable(message: "offline")
        let outcome = await h.store.apply(LibraryEdit(status: .set(.current), notes: .set("n")), to: h.key)
        guard case .failed(.retryable(let message)) = outcome else {
            Issue.record("expected a retryable failure, got \(outcome)")
            return
        }
        #expect(message.hasPrefix("Progress is saved on this device; other fields could not be saved:"))
    }

    @Test("A lease that refuses (account switched) sends no date leg and keeps the status", .timeLimit(.minutes(1)))
    func refusedLeaseSendsNoDateLeg() async throws {
        let h = try await DurableDateHarness(autofill: true)
        defer { h.close() }
        h.lease.refuses = true
        let outcome = await h.store.apply(LibraryEdit(status: .set(.current)), to: h.key)
        #expect(outcome.change != nil)
        #expect(h.backend.edits.isEmpty)
        #expect(h.store.entry(for: h.key)?.startedOn == nil)
    }

    // MARK: Unparseable stored dates (ruling carried from F2.2)

    @Test("Restoring or reverting over an unparseable stored date never writes null; a blank one clears")
    func unparseableStoredDateIsNeverOverwrittenWithNull() throws {
        let unparseable = Self.entry(LibrarySourceMetadata(repeatCount: 0, startedRaw: "not-a-date", finishedRaw: "  "))
        let restored = LibraryEdit.restoring(unparseable)
        #expect(restored.startedOn == .unchanged)
        #expect(restored.finishedOn == .clear, "a blank value means no date")

        let current = Self.entry(LibrarySourceMetadata(repeatCount: 0, startedRaw: "2025", finishedRaw: "2025"))
        let reverted = LibraryEdit.reverting(current, to: unparseable)
        #expect(reverted.startedOn == .unchanged)
        #expect(reverted.finishedOn == .clear)
    }

    // MARK: fillingEmptyDates (pure)

    @Test("fillingEmptyDates: repeating fills nothing, and an unchanged status fills nothing")
    func repeatingAndSameStatusFillNothing() throws {
        let today = try Self.date("2026-03-02")
        let known = Self.entry(LibrarySourceMetadata(repeatCount: 0), status: .completed)
        let repeating = LibraryEdit(status: .set(.repeating)).fillingEmptyDates(current: known, creating: false, today: today)
        #expect(!repeating.autoFilled)
        #expect(repeating.edit == LibraryEdit(status: .set(.repeating)))
        let same = LibraryEdit(status: .set(.completed)).fillingEmptyDates(current: known, creating: false, today: today)
        #expect(!same.autoFilled)
    }
}

// MARK: - Fence-on harness for the date leg

@MainActor
private final class DurableDateHarness {
    let key = MediaKey(kind: .anime, id: 1)
    let account = AccountContext(userId: "account-a", generation: 1)
    let url: URL
    let box: ProgressOutbox
    let store: LibraryStore
    let sender = RecordingSender()
    let backend: ScriptedPatchBackend
    let lease = CountingLease()

    init(autofill: Bool) async throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("kuro-datefill-\(UUID()).sqlite")
        box = try ProgressOutbox(path: url.path)
        let row = LibraryEntry(
            key: key, rowId: 1, status: .planning, progress: 0, createdAt: .distantPast, updatedAt: .distantPast,
            revision: 1, lifecycleId: UUID(), sourceMetadata: LibrarySourceMetadata(repeatCount: 0)
        )
        backend = ScriptedPatchBackend(row: row)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        store = LibraryStore(
            backend: backend, now: { Date(timeIntervalSince1970: 1_772_407_800) },
            calendar: calendar, dateAutofillEnabled: { autofill }, credentialLease: lease
        )
        store.bind(account)
        try await store.refresh()
        let sender = sender
        store.configureProgress(outbox: box) { items, _ in try await sender.send(items) }
    }

    func close() {
        store.cancelProgressWork()
        try? FileManager.default.removeItem(at: url)
    }

    func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate() {
            if ContinuousClock.now > deadline { throw LibraryError.unavailable(message: "Expected transition did not occur") }
            await Task.yield()
        }
    }
}

@MainActor
private final class RecordingSender {
    var calls: [[ProgressIntent]] = []
    func send(_ items: [ProgressIntent]) async throws -> [LibraryProgressReceipt] {
        calls.append(items)
        return items.map {
            LibraryProgressReceipt(mutationId: $0.mutationId, outcome: "applied", position: $0.position,
                                   revision: ($0.baseRevision ?? 0) + 1)
        }
    }
}

@MainActor
private final class ScriptedPatchBackend: LibraryBackend {
    var row: LibraryEntry
    var edits: [LibraryEdit] = []
    var failure: LibraryError?
    init(row: LibraryEntry) { self.row = row }
    func fetchAll(for account: AccountContext) async throws -> [LibraryEntry] { [row] }
    func insertIfMissing(_ key: MediaKey, status: ListStatus, account: AccountContext) async throws -> LibraryWriteResult {
        throw LibraryError.unavailable(message: "Unexpected insert")
    }
    func edit(_ edit: LibraryEdit, key: MediaKey, createIfMissing: ListStatus?, mutationId: UUID,
              baseRevision: Int64?, account: AccountContext) async throws -> LibraryWriteResult {
        edits.append(edit)
        if let failure { throw failure }
        if case .set(let date) = edit.startedOn {
            var metadata = row.sourceMetadata ?? LibrarySourceMetadata()
            metadata.startedRaw = date.raw
            row.sourceMetadata = metadata
        }
        row.revision = (row.revision ?? 0) + 1
        return LibraryWriteResult(entry: row, created: false)
    }
    func remove(_ key: MediaKey, account: AccountContext) async throws {
        throw LibraryError.unavailable(message: "Unexpected remove")
    }
}

@MainActor
private final class CountingLease: LibraryCredentialLease {
    var calls = 0
    var refuses = false
    func withLease<T: Sendable>(
        for account: AccountContext, _ operation: @escaping @MainActor @Sendable () async throws -> T
    ) async throws -> T {
        calls += 1
        if refuses { throw CancellationError() }
        return try await operation()
    }
}
