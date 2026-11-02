import Foundation
import KuroCore
import KuroLibrary
import Testing

// Every store test drives the production `LibraryStore` against `ControlledBackend`, which only
// reports calls and returns what the test answers. "Returns without the test answering a call"
// proves that no request was sent: a sent request would wait for an answer (and hit the limit).

@MainActor
@Suite("LibraryStore: field ownership, rating scale and identity")
struct LibraryStoreFieldTests {
    @Test("A progress edit carries only progress; rating, notes and status keep their values", .timeLimit(.minutes(1)))
    func progressEditKeepsUnrelatedFields() async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)
            let rated = Fixture.entry(Fixture.anime42, progress: 4, rating: 8, notes: "rewatch")
            try await h.load([rated])

            let edit = LibraryEdit(progress: .set(5))
            let pending = Task { await h.store.apply(edit, to: Fixture.anime42) }
            let call = try await h.nextCall()
            #expect(call.request == .edit(edit, createIfMissing: nil, baseRevision: nil))
            let optimistic = try #require(h.store.entry(for: Fixture.anime42))
            #expect(optimistic.progress == 5)
            #expect(optimistic.rating == Fixture.rating(8))
            #expect(optimistic.notes == "rewatch")
            #expect(optimistic.status == .current)

            let canonical = Fixture.entry(Fixture.anime42, progress: 5, rating: 8, notes: "rewatch", updatedAt: Fixture.now)
            call.answer(.write(LibraryWriteResult(entry: canonical, created: false)))
            let change = try #require(await pending.value.change)
            #expect(change.kind == .updated)
            #expect(change.previous == rated)
            #expect(change.current == canonical)
            #expect(change.mutationId == call.mutationId)
            #expect(h.store.entry(for: Fixture.anime42) == canonical)
        }
    }

    @Test("allEntries is newest first, stable across repeated reads and follows every projection change",
          .timeLimit(.minutes(1)))
    func allEntriesOrderFollowsMutations() async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)
            let older = Fixture.entry(Fixture.anime42, updatedAt: Fixture.earlier)
            let newer = Fixture.entry(Fixture.manga7, updatedAt: Fixture.now)
            try await h.load([older, newer])
            #expect(h.store.allEntries == [newer, older])
            #expect(h.store.allEntries == [newer, older])

            let pending = Task { await h.store.apply(LibraryEdit(progress: .set(1)), to: Fixture.anime42) }
            let call = try await h.nextCall()
            let canonical = Fixture.entry(Fixture.anime42, progress: 1, updatedAt: Fixture.now.addingTimeInterval(60))
            call.answer(.write(LibraryWriteResult(entry: canonical, created: false)))
            _ = await pending.value
            #expect(h.store.allEntries == [canonical, newer])

            h.signOut()
            #expect(h.store.allEntries.isEmpty)
        }
    }

    @Test("Legacy 0-100 scores and out-of-range values are not ratings", arguments: [0, 11, 80, 100, -1])
    func legacyScoresAreRejected(value: Int) {
        #expect(UserRating(value: value) == nil)
    }

    @Test("Ratings 1...10 keep the legacy 0-100 projection and the score >= 90 favourite rule",
          arguments: [(1, false), (8, false), (9, true), (10, true)])
    func ratingProjectionAndFavourite(value: Int, favourite: Bool) throws {
        let rating = try #require(UserRating(value: value))
        #expect(rating.score100 == value * 10)
        #expect(Fixture.entry(Fixture.anime42, rating: value).isFavorited == favourite)
    }

    @Test("Edits that clear status/progress or set negative progress fail before any request or projection change",
          .timeLimit(.minutes(1)),
          arguments: [
              (LibraryEdit(status: .clear), "status"),
              (LibraryEdit(progress: .clear), "progress"),
              (LibraryEdit(progress: .set(-1)), "progress"),
          ])
    func invalidEditsNeverReachTheBackend(edit: LibraryEdit, field: String) async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)
            let entry = Fixture.entry(Fixture.anime42, progress: 3)
            try await h.load([entry])

            #expect(await h.store.apply(edit, to: Fixture.anime42) == .failed(.invalidValue(field: field)))
            #expect(h.store.entry(for: Fixture.anime42) == entry)
        }
    }

    @Test("Saving an already tracked title never overwrites it", .timeLimit(.minutes(1)))
    func saveNeverOverwrites() async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)
            let completed = Fixture.entry(Fixture.anime42, status: .completed, progress: 12, rating: 9)
            try await h.load([completed])

            let pending = Task { await h.store.save(Fixture.anime42, status: .planning) }
            let call = try await h.nextCall()
            #expect(call.request == .insertIfMissing(.planning))
            #expect(h.store.entry(for: Fixture.anime42) == completed, "no optimistic overwrite")
            call.answer(.write(LibraryWriteResult(entry: completed, created: false)))

            let change = try #require(await pending.value.change)
            #expect(change.kind == .updated)
            #expect(change.previous == completed)
            #expect(change.current == completed)
            #expect(h.store.entry(for: Fixture.anime42) == completed)
            #expect(h.sink.changes.isEmpty)
        }
    }

    @Test("Editing an entry removed elsewhere fails with notFound, never asks to recreate it and drops the stale entry",
          .timeLimit(.minutes(1)))
    func editOfRemovedEntry() async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)
            try await h.load([Fixture.entry(Fixture.anime42, progress: 3)])

            let edit = LibraryEdit(progress: .set(4))
            let pending = Task { await h.store.apply(edit, to: Fixture.anime42) }
            let call = try await h.nextCall()
            #expect(call.request == .edit(edit, createIfMissing: nil, baseRevision: nil))
            call.answer(.failure(.notFound))

            #expect(await pending.value == .failed(.notFound))
            #expect(!h.store.isTracked(Fixture.anime42))
        }
    }

    @Test("anime 7 and manga 7 are distinct keys with independent projections", .timeLimit(.minutes(1)))
    func equalNumericIdsStayIndependent() async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)
            let anime = Fixture.entry(Fixture.anime7, rowId: 5, status: .current, progress: 3)
            let manga = Fixture.entry(Fixture.manga7, rowId: 5, status: .planning)
            try await h.load([anime, manga])
            #expect(h.store.keys(withStatus: .current, kind: .anime) == [Fixture.anime7])
            #expect(h.store.keys(withStatus: .planning, kind: .manga) == [Fixture.manga7])
            #expect(h.store.keys(withStatus: .current, kind: .manga).isEmpty)

            let pending = Task { await h.store.remove(Fixture.manga7) }
            let call = try await h.nextCall()
            #expect(call.request == .remove)
            #expect(call.key == Fixture.manga7)
            call.answer(.removed)

            let change = try #require(await pending.value.change)
            #expect(change.kind == .removed)
            #expect(change.previous == manga)
            #expect(!h.store.isTracked(Fixture.manga7))
            #expect(h.store.entry(for: Fixture.anime7) == anime)
        }
    }
}

@MainActor
@Suite("LibraryStore: sequencing, stale reads and account binding")
struct LibraryStoreSequencingTests {
    @Test("Overlapping edits of one title run in issue order and end on the last canonical row", .timeLimit(.minutes(1)))
    func overlappingEditsRunFIFO() async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)
            try await h.load([Fixture.entry(Fixture.anime42, progress: 3, revision: 1)])

            let first = LibraryEdit(progress: .set(4))
            let second = LibraryEdit(progress: .set(5), notes: .set("ep 5"))
            let firstTask = Task { await h.store.apply(first, to: Fixture.anime42) }
            let firstCall = try await h.nextCall()
            #expect(firstCall.request == .edit(first, createIfMissing: nil, baseRevision: 1))

            let secondTask = Task { await h.store.apply(second, to: Fixture.anime42) }
            await h.waitUntil { h.store.entry(for: Fixture.anime42)?.notes == "ep 5" }
            #expect(h.store.entry(for: Fixture.anime42)?.progress == 5, "both intents are projected while in flight")

            let afterFirst = Fixture.entry(Fixture.anime42, progress: 4, updatedAt: Fixture.now, revision: 2)
            firstCall.answer(.write(LibraryWriteResult(entry: afterFirst, created: false)))
            // The second request is built only after the first settled: it carries the first's revision.
            let secondCall = try await h.nextCall()
            #expect(secondCall.request == .edit(second, createIfMissing: nil, baseRevision: 2))
            #expect(secondCall.mutationId != firstCall.mutationId)

            let afterSecond = Fixture.entry(Fixture.anime42, progress: 5, notes: "ep 5", updatedAt: Fixture.now, revision: 3)
            secondCall.answer(.write(LibraryWriteResult(entry: afterSecond, created: false)))
            #expect(await firstTask.value.change?.current == afterFirst)
            #expect(await secondTask.value.change?.previous == afterFirst)
            #expect(h.store.entry(for: Fixture.anime42) == afterSecond)
        }
    }

    enum RefreshRace: String, CaseIterable, Sendable {
        case mutationIssuedAfterRefreshStarted
        case mutationIssuedBeforeRefreshStarted
        case mutationStillPendingWhenRefreshReturns
    }

    @Test("A refresh that started before a local mutation cannot overwrite that title",
          .timeLimit(.minutes(1)), arguments: RefreshRace.allCases)
    func staleRefreshCannotOverwriteNewerMutation(race: RefreshRace) async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)
            try await h.load([Fixture.entry(Fixture.anime42, progress: 3), Fixture.entry(Fixture.anime7)])

            let edit = LibraryEdit(progress: .set(5))
            let canonical = Fixture.entry(Fixture.anime42, progress: 5, updatedAt: Fixture.now)
            let staleRows = [Fixture.entry(Fixture.anime42, progress: 3), Fixture.entry(Fixture.anime7, progress: 9)]

            switch race {
            case .mutationIssuedAfterRefreshStarted:
                let refresh = Task { try await h.store.refresh() }
                let fetch = try await h.nextCall()
                let mutation = Task { await h.store.apply(edit, to: Fixture.anime42) }
                let write = try await h.nextCall()
                write.answer(.write(LibraryWriteResult(entry: canonical, created: false)))
                _ = await mutation.value
                fetch.answer(.entries(staleRows))
                try await refresh.value
            case .mutationIssuedBeforeRefreshStarted:
                let mutation = Task { await h.store.apply(edit, to: Fixture.anime42) }
                let write = try await h.nextCall()
                let refresh = Task { try await h.store.refresh() }
                let fetch = try await h.nextCall()
                write.answer(.write(LibraryWriteResult(entry: canonical, created: false)))
                _ = await mutation.value
                fetch.answer(.entries(staleRows))
                try await refresh.value
            case .mutationStillPendingWhenRefreshReturns:
                let mutation = Task { await h.store.apply(edit, to: Fixture.anime42) }
                let write = try await h.nextCall()
                let refresh = Task { try await h.store.refresh() }
                let fetch = try await h.nextCall()
                fetch.answer(.entries(staleRows))
                try await refresh.value
                #expect(h.store.entry(for: Fixture.anime42)?.progress == 5, "the pending intent stays projected")
                write.answer(.write(LibraryWriteResult(entry: canonical, created: false)))
                _ = await mutation.value
            }

            #expect(h.store.entry(for: Fixture.anime42) == canonical)
            #expect(h.store.entry(for: Fixture.anime7)?.progress == 9, "titles without local mutations take the refresh")
        }
    }

    @Test("An older refresh that returns late cannot replace a newer refresh's rows", .timeLimit(.minutes(1)))
    func olderRefreshCannotReplaceNewer() async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)
            let older = Task { try await h.store.refresh() }
            let olderCall = try await h.nextCall()
            let newer = Task { try await h.store.refresh() }
            let newerCall = try await h.nextCall()

            newerCall.answer(.entries([Fixture.entry(Fixture.anime42, progress: 8)]))
            try await newer.value
            olderCall.answer(.entries([Fixture.entry(Fixture.anime42, progress: 2)]))
            try await older.value
            #expect(h.store.entry(for: Fixture.anime42)?.progress == 8)
        }
    }

    @Test("A completion for a replaced account is rejected and never touches the new account's projection",
          .timeLimit(.minutes(1)), arguments: [false, true])
    func accountSwitchMidFlight(previousAccountFails: Bool) async throws {
        try await withHarness { h in
            let a = h.signIn(Fixture.userA)
            try await h.load([Fixture.entry(Fixture.anime42, progress: 3)])

            let inFlight = Task { await h.store.apply(LibraryEdit(progress: .set(4)), to: Fixture.anime42) }
            let callA = try await h.nextCall()
            #expect(callA.account == a)
            let queued = Task { await h.store.apply(LibraryEdit(progress: .set(5)), to: Fixture.anime42) }
            await h.waitUntil { h.store.entry(for: Fixture.anime42)?.progress == 5 }

            h.signIn(Fixture.userB)
            #expect(h.store.allEntries.isEmpty, "A's projection is dropped when B is bound")
            let rowsB = [
                Fixture.entry(Fixture.anime42, rowId: 90, status: .completed, progress: 24, rating: 7),
                Fixture.entry(Fixture.manga7, rowId: 91),
            ]
            try await h.load(rowsB)

            callA.answer(previousAccountFails
                ? .failure(.retryable(message: "timeout"))
                : .write(LibraryWriteResult(entry: Fixture.entry(Fixture.anime42, progress: 4, updatedAt: Fixture.now), created: false)))
            #expect(await inFlight.value == .failed(.notAuthenticated))
            // Never sent: it returned although no further call was answered.
            #expect(await queued.value == .failed(.notAuthenticated))
            #expect(h.store.allEntries == rowsB)
            #expect(h.sink.changes.isEmpty)

            h.signOut()
            #expect(h.store.allEntries.isEmpty)
            #expect(await h.store.apply(LibraryEdit(progress: .set(1)), to: Fixture.anime42) == .failed(.notAuthenticated))
        }
    }

    @Test("Undo of another account's change is refused without a request", .timeLimit(.minutes(1)))
    func undoIsBoundToTheChangesAccount() async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)
            try await h.load([])
            let saving = Task { await h.store.save(Fixture.anime7, status: .planning) }
            let createdForA = Fixture.entry(Fixture.anime7, rowId: 11, status: .planning, updatedAt: Fixture.now)
            try await h.nextCall().answer(.write(LibraryWriteResult(entry: createdForA, created: true)))
            let changeOfA = try #require(await saving.value.change)

            h.signIn(Fixture.userB)
            let trackedByB = Fixture.entry(Fixture.anime7, rowId: 70, status: .completed, progress: 12)
            try await h.load([trackedByB])

            #expect(await h.store.undo(changeOfA) == .failed(.notAuthenticated))
            #expect(h.store.entry(for: Fixture.anime7) == trackedByB)
        }
    }

    @Test("Work started before a reset stays stale even if the same context is bound again", .timeLimit(.minutes(1)))
    func resetInvalidatesWorkForTheSameContext() async throws {
        try await withHarness { h in
            let a = h.signIn(Fixture.userA)
            try await h.load([Fixture.entry(Fixture.anime42, progress: 3)])
            let pending = Task { await h.store.apply(LibraryEdit(progress: .set(4)), to: Fixture.anime42) }
            let call = try await h.nextCall()

            h.store.reset()
            h.store.bind(a)
            call.answer(.write(LibraryWriteResult(
                entry: Fixture.entry(Fixture.anime42, progress: 4, updatedAt: Fixture.now), created: false
            )))
            #expect(await pending.value == .failed(.notAuthenticated))
            #expect(h.store.allEntries.isEmpty)
            #expect(h.sink.changes.isEmpty)
        }
    }

    @Test("A failed refresh keeps the projection and returns the typed error", .timeLimit(.minutes(1)))
    func failedRefreshKeepsProjection() async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)
            let tracked = Fixture.entry(Fixture.anime42, progress: 3)
            try await h.load([tracked])

            let refresh = Task { () async -> LibraryError? in
                do throws(LibraryError) {
                    try await h.store.refresh()
                    return nil
                } catch {
                    return error
                }
            }
            try await h.nextCall().answer(.failure(.retryable(message: "offline")))
            #expect(await refresh.value == .retryable(message: "offline"))
            #expect(h.store.allEntries == [tracked])
        }
    }

    enum FailedMutation: String, CaseIterable, Sendable {
        case editOfTrackedTitle
        case saveOfUntrackedTitle
    }

    @Test("A failed mutation restores the prior projection and returns the typed error",
          .timeLimit(.minutes(1)), arguments: FailedMutation.allCases)
    func failureRollsBack(mutation: FailedMutation) async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)
            let tracked = Fixture.entry(Fixture.anime42, progress: 3, rating: 8)
            try await h.load([tracked])

            switch mutation {
            case .editOfTrackedTitle:
                let pending = Task { await h.store.apply(LibraryEdit(progress: .set(4)), to: Fixture.anime42) }
                let call = try await h.nextCall()
                #expect(h.store.entry(for: Fixture.anime42)?.progress == 4)
                call.answer(.failure(.retryable(message: "offline")))
                #expect(await pending.value == .failed(.retryable(message: "offline")))
                #expect(h.store.entry(for: Fixture.anime42) == tracked)
            case .saveOfUntrackedTitle:
                let pending = Task { await h.store.save(Fixture.anime7, status: .planning) }
                let call = try await h.nextCall()
                #expect(h.store.isTracked(Fixture.anime7))
                call.answer(.failure(.unavailable(message: "not configured")))
                #expect(await pending.value == .failed(.unavailable(message: "not configured")))
                #expect(!h.store.isTracked(Fixture.anime7))
            }
            #expect(h.sink.changes.isEmpty)
        }
    }

    @Test("A failed mutation withdraws only itself; a later queued mutation still applies", .timeLimit(.minutes(1)))
    func failureWithdrawsOnlyItsOwnIntent() async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)
            try await h.load([Fixture.entry(Fixture.anime42, progress: 3)])

            let failing = Task { await h.store.apply(LibraryEdit(progress: .set(4)), to: Fixture.anime42) }
            let failingCall = try await h.nextCall()
            let later = Task { await h.store.apply(LibraryEdit(notes: .set("later")), to: Fixture.anime42) }
            await h.waitUntil { h.store.entry(for: Fixture.anime42)?.notes == "later" }

            failingCall.answer(.failure(.retryable(message: "timeout")))
            #expect(await failing.value == .failed(.retryable(message: "timeout")))
            let projected = try #require(h.store.entry(for: Fixture.anime42))
            #expect(projected.progress == 3, "the failed progress intent is withdrawn")
            #expect(projected.notes == "later", "the queued notes intent is still projected")

            let laterCall = try await h.nextCall()
            let canonical = Fixture.entry(Fixture.anime42, progress: 3, notes: "later", updatedAt: Fixture.now)
            laterCall.answer(.write(LibraryWriteResult(entry: canonical, created: false)))
            _ = await later.value
            #expect(h.store.entry(for: Fixture.anime42) == canonical)
        }
    }
}

@MainActor
@Suite("LibraryStore: Undo and change fan-out")
struct LibraryStoreUndoTests {
    @Test("Undo of an edit is a compensating edit of only the changed fields", .timeLimit(.minutes(1)))
    func undoUpdateRestoresChangedFieldsOnly() async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)
            let before = Fixture.entry(Fixture.anime42, progress: 3, rating: 8, notes: "n")
            try await h.load([before])

            let edit = LibraryEdit(progress: .set(5), notes: .clear)
            let applying = Task { await h.store.apply(edit, to: Fixture.anime42) }
            let after = Fixture.entry(Fixture.anime42, progress: 5, rating: 8, updatedAt: Fixture.now)
            try await h.nextCall().answer(.write(LibraryWriteResult(entry: after, created: false)))
            let change = try #require(await applying.value.change)

            let undoing = Task { await h.store.undo(change) }
            let undoCall = try await h.nextCall()
            #expect(undoCall.request == .edit(LibraryEdit(progress: .set(3), notes: .set("n")), createIfMissing: nil, baseRevision: nil))
            let restored = Fixture.entry(Fixture.anime42, progress: 3, rating: 8, notes: "n", updatedAt: Fixture.now)
            undoCall.answer(.write(LibraryWriteResult(entry: restored, created: false)))
            #expect(await undoing.value.change?.current == restored)
            #expect(h.store.entry(for: Fixture.anime42) == restored)
        }
    }

    @Test("Undo of a save that created the entry removes it", .timeLimit(.minutes(1)))
    func undoAddRemoves() async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)
            try await h.load([])

            let saving = Task { await h.store.save(Fixture.anime7, status: .planning) }
            let created = Fixture.entry(Fixture.anime7, rowId: 11, status: .planning, updatedAt: Fixture.now)
            try await h.nextCall().answer(.write(LibraryWriteResult(entry: created, created: true)))
            let change = try #require(await saving.value.change)
            #expect(change.kind == .added)

            let undoing = Task { await h.store.undo(change) }
            let undoCall = try await h.nextCall()
            #expect(undoCall.request == .remove)
            #expect(undoCall.key == Fixture.anime7)
            undoCall.answer(.removed)
            #expect(await undoing.value.change?.kind == .removed)
            #expect(!h.store.isTracked(Fixture.anime7))
        }
    }

    @Test("Undo of a removal re-saves every prior field", .timeLimit(.minutes(1)))
    func undoRemoveResaves() async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)
            let removedEntry = Fixture.entry(
                Fixture.anime42, status: .completed, progress: 12, rating: 9, notes: "x", verdict: .masterpiece
            )
            try await h.load([removedEntry])

            let removing = Task { await h.store.remove(Fixture.anime42) }
            try await h.nextCall().answer(.removed)
            let change = try #require(await removing.value.change)

            let undoing = Task { await h.store.undo(change) }
            let undoCall = try await h.nextCall()
            let expected = LibraryEdit(
                status: .set(.completed), progress: .set(12), rating: .set(try #require(Fixture.rating(9))),
                notes: .set("x"), verdict: .set(.masterpiece)
            )
            #expect(undoCall.request == .edit(expected, createIfMissing: .completed, baseRevision: nil))
            let resaved = Fixture.entry(
                Fixture.anime42, rowId: 2, status: .completed, progress: 12, rating: 9, notes: "x", verdict: .masterpiece,
                updatedAt: Fixture.now
            )
            undoCall.answer(.write(LibraryWriteResult(entry: resaved, created: true)))
            #expect(await undoing.value.change?.kind == .added)
            #expect(h.store.entry(for: Fixture.anime42) == resaved)
        }
    }

    @Test("Undo never acts without a known prior state, and a no-op change undoes without a request",
          .timeLimit(.minutes(1)))
    func undoWithoutPriorStateDoesNotWrite() async throws {
        try await withHarness { h in
            let a = h.signIn(Fixture.userA)
            let existing = Fixture.entry(Fixture.anime42, status: .completed)
            try await h.load([existing])

            let unknownPrior = LibraryChange(
                key: Fixture.anime42, kind: .updated, previous: nil, current: existing, mutationId: UUID(), account: a
            )
            #expect(await h.store.undo(unknownPrior) == .failed(.conflict(server: existing)))

            let noOp = LibraryChange(
                key: Fixture.anime42, kind: .updated, previous: existing, current: existing, mutationId: UUID(), account: a
            )
            let outcome = await h.store.undo(noOp)
            #expect(outcome.change?.current == existing)
            #expect(h.store.entry(for: Fixture.anime42) == existing)
        }
    }

    @Test("Change sinks receive added/updated/removed after the projection reflects them; refresh and failures are not fanned out",
          .timeLimit(.minutes(1)))
    func sinksReceiveAppliedChanges() async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)
            let tracked = Fixture.entry(Fixture.anime42, progress: 3)
            try await h.load([tracked])
            #expect(h.sink.changes.isEmpty)

            let saving = Task { await h.store.save(Fixture.anime7, status: .planning) }
            let added = Fixture.entry(Fixture.anime7, rowId: 11, status: .planning, updatedAt: Fixture.now)
            try await h.nextCall().answer(.write(LibraryWriteResult(entry: added, created: true)))
            _ = await saving.value

            let editing = Task { await h.store.apply(LibraryEdit(progress: .set(4)), to: Fixture.anime42) }
            let updated = Fixture.entry(Fixture.anime42, progress: 4, updatedAt: Fixture.now)
            try await h.nextCall().answer(.write(LibraryWriteResult(entry: updated, created: false)))
            _ = await editing.value

            let removing = Task { await h.store.remove(Fixture.anime7) }
            try await h.nextCall().answer(.removed)
            _ = await removing.value

            let failing = Task { await h.store.apply(LibraryEdit(progress: .set(5)), to: Fixture.anime42) }
            try await h.nextCall().answer(.failure(.retryable(message: "offline")))
            _ = await failing.value

            // Removing a title the projection never held is still delivered (F7).
            let removingUnknown = Task { await h.store.remove(Fixture.manga7) }
            try await h.nextCall().answer(.removed)
            _ = await removingUnknown.value

            #expect(h.sink.changes.map(\.kind) == [.added, .updated, .removed, .removed])
            #expect(h.sink.changes.map(\.key) == [Fixture.anime7, Fixture.anime42, Fixture.anime7, Fixture.manga7])
            #expect(h.sink.changes.map(\.previous) == [nil, tracked, added, nil])
            #expect(h.sink.changes.map(\.current) == [added, updated, nil, nil])
            #expect(h.sink.projectionAtDelivery == [added, updated, nil, nil])
        }
    }
}

@MainActor
@Suite("LibraryStore: load state")
struct LibraryStoreLoadStateTests {
    static func knowledge(_ h: Harness, _ key: MediaKey) -> LibraryKnowledge {
        h.store.entry(for: LibraryKnowledgeQuery(key))
    }

    @Test("bind -> notLoaded (unknown); first refresh -> loading -> loaded; same-user rebind keeps it; reset -> notLoaded",
          .timeLimit(.minutes(1)))
    func loadStateFollowsBindingAndRefresh() async throws {
        try await withHarness { h in
            #expect(h.store.loadState == .notLoaded)
            h.signIn(Fixture.userA)
            #expect(h.store.loadState == .notLoaded)
            #expect(Self.knowledge(h, Fixture.anime7) == .unknown)

            let refresh = Task { try await h.store.refresh() }
            let call = try await h.nextCall()
            #expect(h.store.loadState == .loading)
            #expect(Self.knowledge(h, Fixture.anime7) == .unknown)
            let tracked = Fixture.entry(Fixture.anime42, progress: 3)
            call.answer(.entries([tracked]))
            try await refresh.value
            #expect(h.store.loadState == .loaded)
            #expect(Self.knowledge(h, Fixture.anime42) == .tracked(tracked))
            #expect(Self.knowledge(h, Fixture.anime7) == .untracked)

            h.signIn(Fixture.userA)
            #expect(h.store.loadState == .loaded, "a same-user session event keeps the binding")

            h.signOut()
            #expect(h.store.loadState == .notLoaded)
            #expect(Self.knowledge(h, Fixture.anime42) == .unknown)
        }
    }

    @Test("A failed first load is failed (titles stay unknown) until a retry loads; a failure after a load keeps it loaded",
          .timeLimit(.minutes(1)))
    func failedLoadsAndRetries() async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)

            let firstFailure = try await Self.refresh(h, answering: .failure(.retryable(message: "offline")))
            #expect(firstFailure == .retryable(message: "offline"))
            #expect(h.store.loadState == .failed)
            #expect(Self.knowledge(h, Fixture.anime7) == .unknown)

            let retry = try await Self.refresh(h, answering: .entries([]))
            #expect(retry == nil)
            #expect(h.store.loadState == .loaded)
            #expect(Self.knowledge(h, Fixture.anime7) == .untracked)

            let laterFailure = try await Self.refresh(h, answering: .failure(.retryable(message: "offline")))
            #expect(laterFailure == .retryable(message: "offline"))
            #expect(h.store.loadState == .loaded, "the published rows are still the account's")
        }
    }

    /// Runs one refresh, checks it is in flight (`.loading` unless already loaded) and answers it.
    static func refresh(_ h: Harness, answering answer: ControlledBackend.Answer) async throws -> LibraryError? {
        let wasLoaded = h.store.loadState == .loaded
        let task = Task { () async -> LibraryError? in
            do throws(LibraryError) {
                try await h.store.refresh()
                return nil
            } catch {
                return error
            }
        }
        let call = try await h.nextCall()
        #expect(h.store.loadState == (wasLoaded ? .loaded : .loading))
        call.answer(answer)
        return await task.value
    }

    @Test("Account switch mid-load: the previous account's late answer never marks the new binding loaded or failed",
          .timeLimit(.minutes(1)), arguments: [false, true])
    func accountSwitchMidLoad(previousAccountFails: Bool) async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)
            let refreshA = Task { () async -> LibraryError? in
                do throws(LibraryError) {
                    try await h.store.refresh()
                    return nil
                } catch {
                    return error
                }
            }
            let callA = try await h.nextCall()
            #expect(h.store.loadState == .loading)

            h.signIn(Fixture.userB)
            #expect(h.store.loadState == .notLoaded)
            callA.answer(previousAccountFails
                ? .failure(.retryable(message: "timeout"))
                : .entries([Fixture.entry(Fixture.anime42)]))
            #expect(await refreshA.value == .notAuthenticated)
            #expect(h.store.loadState == .notLoaded)
            #expect(Self.knowledge(h, Fixture.anime42) == .unknown)

            try await h.load([])
            #expect(h.store.loadState == .loaded)
            #expect(Self.knowledge(h, Fixture.anime42) == .untracked)
        }
    }
}

@MainActor
@Suite("Shared Home/Library mutation admission")
struct HomeLibraryReservationTests {
    @Test("A queued Library edit uses the Home receipt's confirmed revision and preserves its optimistic fields", .timeLimit(.minutes(1)))
    func receiptAndEditShareFIFO() async throws {
        try await withHarness { h in
            let account = h.signIn(Fixture.userA)
            let lifecycle = UUID()
            var original = Fixture.entry(Fixture.anime42, progress: 3, revision: 1)
            original.lifecycleId = lifecycle
            try await h.load([original])
            let (signal, signalSink) = AsyncStream<Void>.makeStream()
            let (gate, gateSink) = AsyncStream<Void>.makeStream()
            let receipt = Task { try await h.store.withMutationReservation(keys: [Fixture.anime42], account: account) {
                signalSink.yield(())
                for await _ in gate { break }
                h.store.adoptServerProgress(key: Fixture.anime42, account: account, lifecycleId: lifecycle, progress: 4, revision: 2)
            } }
            for await _ in signal { break }
            let edit = LibraryEdit(status: .set(.completed))
            let write = Task { await h.store.apply(edit, to: Fixture.anime42) }
            await h.waitUntil { h.store.entry(for: Fixture.anime42)?.status == .completed }
            gateSink.yield(())
            try await receipt.value
            let call = try await h.nextCall()
            #expect(call.request == .edit(edit, createIfMissing: nil, baseRevision: 2))
            #expect(h.store.entry(for: Fixture.anime42)?.progress == 4)
            #expect(h.store.entry(for: Fixture.anime42)?.status == .completed)
            var canonical = original; canonical.progress = 4; canonical.status = .completed; canonical.revision = 3
            call.answer(.write(LibraryWriteResult(entry: canonical, created: false)))
            _ = await write.value
            h.store.adoptServerProgress(key: Fixture.anime42, account: account, lifecycleId: lifecycle, progress: 1, revision: 2)
            #expect(h.store.entry(for: Fixture.anime42)?.revision == 3)
            #expect(h.store.entry(for: Fixture.anime42)?.progress == 4)
            signalSink.finish(); gateSink.finish()
        }
    }

    @Test("An old lifecycle or account receipt cannot enter a replacement row", .timeLimit(.minutes(1)))
    func replacementRowRejectsOldReceipt() async throws {
        try await withHarness { h in
            let account = h.signIn(Fixture.userA)
            let oldLifecycle = UUID()
            var replacement = Fixture.entry(Fixture.anime42, progress: 1, revision: 1)
            replacement.lifecycleId = UUID()
            try await h.load([replacement])
            h.store.adoptServerProgress(key: Fixture.anime42, account: account, lifecycleId: oldLifecycle, progress: 30, revision: 50)
            #expect(h.store.entry(for: Fixture.anime42) == replacement)
            _ = h.signIn(Fixture.userB)
            try await h.load([replacement])
            h.store.adoptServerProgress(key: Fixture.anime42, account: account, lifecycleId: replacement.lifecycleId!, progress: 30, revision: 50)
            #expect(h.store.entry(for: Fixture.anime42) == replacement)
        }
    }
}
