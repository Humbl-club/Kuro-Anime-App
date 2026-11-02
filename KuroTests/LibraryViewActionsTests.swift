//
//  LibraryViewActionsTests.swift
//  KuroTests
//
//  The views' Library writes routed through `LibraryActions`, the ONE writer mapping over
//  `LibraryStore` (E6c2 ruling, G2/G6/G7): the cards' toggle, "+1" and removals go through the
//  typed adapters in `LibraryViewActions` (or `LibraryActions` itself), so its per-title double-tap
//  guard, account checks and `BannerCenter` result banners apply to every card. The store runs over a
//  `FakeLibraryBackend` whose writes the tests hold and release (`ControlledResponses`).
//

import Testing
import Foundation
import KuroCore
import KuroLibrary
@testable import Kuro

@MainActor
@Suite("Library view actions: routed through LibraryActions", .timeLimit(.minutes(1)))
struct LibraryViewActionsTests {
    static let anime42 = MediaKey(kind: .anime, id: 42)

    @Test("A second tap while the toggle is in flight is ignored: one write, one banner")
    func doubleTapIgnoredWhileInFlight() async throws {
        let gate = ControlledResponses<Bool>()
        let harness = try FacadeHarness(backend: FakeLibraryBackend(writeGate: gate))
        let service = harness.service
        let actions = service.libraryActions
        await harness.signIn()

        let first = LibraryViewActions.toggleTracked(Self.anime42, actions: actions)
        #expect(first != nil)
        #expect(service.library.isTracked(Self.anime42), "the cards read isTracked right after toggling")
        #expect(LibraryViewActions.toggleTracked(Self.anime42, actions: actions) == nil, "the quick second tap is ignored")
        #expect(service.library.isTracked(Self.anime42), "the ignored tap does not flip back")

        #expect(await gate.waitForRequest("anime-42"))
        gate.complete("anime-42", with: .success(true))
        await first?.value
        #expect(harness.backend.writeCalls.count == 1, "one write for the double tap")
        #expect(service.library.isTracked(Self.anime42))
        #expect(service.banner.message == "Added to collection")
        await harness.settleSinks()
        await harness.tearDown()
    }

    @Test("Add, then remove after the add completed: both writes run, the title ends untracked")
    func addThenRemoveAfterCompletion() async throws {
        let gate = ControlledResponses<Bool>()
        let harness = try FacadeHarness(backend: FakeLibraryBackend(writeGate: gate))
        let service = harness.service
        let actions = service.libraryActions
        await harness.signIn()

        let add = LibraryViewActions.toggleTracked(Self.anime42, actions: actions)
        #expect(await gate.waitForRequest("anime-42"))
        gate.complete("anime-42", with: .success(true))
        await add?.value
        #expect(service.banner.message == "Added to collection")

        let remove = LibraryViewActions.toggleTracked(Self.anime42, actions: actions)
        #expect(remove != nil, "the guard is released once the add completed")
        #expect(!service.library.isTracked(Self.anime42), "the removal flips at once")
        #expect(await gate.waitForRequest("anime-42"))
        gate.complete("anime-42", with: .success(true))
        await remove?.value

        #expect(!service.library.isTracked(Self.anime42))
        #expect(harness.backend.writeCalls.count == 2)
        #expect(harness.backend.writeCalls.last == .remove(Self.anime42))
        #expect(service.banner.message == "Removed from collection")
        await harness.settleSinks()
        await harness.tearDown()
    }

    @Test("A failed toggle rolls back and shows the failure banner")
    func failureShowsTheBanner() async throws {
        let gate = ControlledResponses<Bool>()
        let harness = try FacadeHarness(backend: FakeLibraryBackend(writeGate: gate))
        let service = harness.service
        await harness.signIn()

        harness.backend.failNextWrite(with: .retryable(message: "offline"))
        let failing = LibraryViewActions.toggleTracked(Self.anime42, actions: service.libraryActions)
        #expect(service.library.isTracked(Self.anime42))
        #expect(await gate.waitForRequest("anime-42"))
        gate.complete("anime-42", with: .success(true))
        await failing?.value

        #expect(!service.library.isTracked(Self.anime42), "a failed add is rolled back")
        #expect(service.banner.message == "Couldn't update list. Try again.")
        #expect(LibraryViewActions.toggleTracked(Self.anime42, actions: service.libraryActions) != nil, "the guard is released after a failure")
        await harness.settleSinks()
        await harness.tearDown()
    }

    @Test("Without a session a toggle writes nothing and shows nothing")
    func noSessionNoWriteNoBanner() async throws {
        let harness = try FacadeHarness()
        let service = harness.service

        #expect(LibraryViewActions.toggleTracked(Self.anime42, actions: service.libraryActions) == nil)
        #expect(harness.backend.writeCalls.isEmpty)
        #expect(service.banner.message == nil)
        await harness.tearDown()
    }

    @Test("The heart (rating 10 through LibraryActions.apply), +1 and removal write one edit each")
    func heartProgressAndRemoval() async throws {
        let gate = ControlledResponses<Bool>()
        let backend = FakeLibraryBackend(writeGate: gate)
        backend.setRows([FakeLibraryBackend.entry(.anime, 42, status: .current, progress: 3)], for: FacadeHarness.userA)
        let harness = try FacadeHarness(backend: backend)
        let service = harness.service
        let actions = service.libraryActions
        await harness.signIn()

        // Heart: rating 10 through `LibraryActions.apply` (E8-C2: `toggleFavorite` and its double-tap
        // guard are deleted; its only view callers were the unreferenced `Cards.swift` cards).
        let ten = try #require(UserRating(value: 10))
        let heart = Task { await actions.apply(LibraryEdit(rating: .set(ten)), to: Self.anime42, createIfMissing: nil) }
        #expect(await gate.waitForRequest("anime-42"))
        gate.complete("anime-42", with: .success(true))
        #expect(await heart.value.error == nil)
        #expect(service.library.entry(for: Self.anime42)?.isFavorited == true)

        // "+1 EP": one past what the projection holds.
        let increment = Task { await LibraryViewActions.incrementProgress(Self.anime42, actions: actions) }
        #expect(await gate.waitForRequest("anime-42"))
        gate.complete("anime-42", with: .success(true))
        await increment.value
        #expect(service.library.entry(for: Self.anime42)?.progress == 4)
        #expect(harness.backend.writeCalls.last == .edit(LibraryEdit(progress: .set(4)), Self.anime42, createIfMissing: nil))

        // Removal (Collection card menu, batch removal): `true` only when applied.
        let removal = Task { await LibraryViewActions.remove(Self.anime42, actions: actions) }
        #expect(await gate.waitForRequest("anime-42"))
        gate.complete("anime-42", with: .success(true))
        #expect(await removal.value)
        #expect(!service.library.isTracked(Self.anime42))

        harness.backend.failNextWrite(with: .retryable(message: "offline"))
        let failedRemoval = Task { await LibraryViewActions.remove(MediaKey(kind: .manga, id: 42), actions: actions) }
        #expect(await gate.waitForRequest("manga-42"))
        gate.complete("manga-42", with: .success(true))
        #expect(await failedRemoval.value == false)
        #expect(harness.backend.writeCalls.count == 4, "heart, +1, removal, failed removal: one write each")
        await harness.settleSinks()
        await harness.tearDown()
    }

    @Test("The card toggle adds an untracked title as Planned (insert-if-missing: a save, never an edit) and removes a tracked one")
    func toggleAddsAsPlannedAndRemoves() async throws {
        let harness = try FacadeHarness()
        let service = harness.service
        let actions = service.libraryActions
        await harness.signIn()

        await LibraryViewActions.toggleTracked(Self.anime42, actions: actions)?.value
        #expect(service.library.entry(for: Self.anime42)?.status == .planning)
        #expect(service.banner.message == "Added to collection")
        await LibraryViewActions.toggleTracked(Self.anime42, actions: actions)?.value
        #expect(!service.library.isTracked(Self.anime42))
        #expect(service.banner.message == "Removed from collection")

        #expect(harness.backend.writeCalls == [.insertIfMissing(Self.anime42, .planning), .remove(Self.anime42)])
        await harness.settleSinks()
        await harness.tearDown()
    }

    @Test("Mark progress (episode/chapter rows, E8: through LibraryActions.apply): one absolute progress-only edit, a missing title created as Watching/Reading, a negative target clamped to 0; the typed outcome comes back with no banner")
    func markProgressRoutesThroughLibraryActions() async throws {
        let backend = FakeLibraryBackend()
        backend.setRows([FakeLibraryBackend.entry(.anime, 42, status: .completed, progress: 3, rating: 8)], for: FacadeHarness.userA)
        let harness = try FacadeHarness(backend: backend)
        let service = harness.service
        let actions = service.libraryActions
        await harness.signIn()

        let marked = try #require(await LibraryViewActions.markProgress(Self.anime42, to: 7, actions: actions).change)
        #expect(marked.kind == .updated)
        #expect(marked.current?.progress == 7 && marked.current?.status == .completed && marked.current?.rating?.value == 8,
                "progress only: status and rating stay as stored")

        let manga7 = MediaKey(kind: .manga, id: 7)
        let created = try #require(await LibraryViewActions.markProgress(manga7, to: -2, actions: actions).change)
        #expect(created.kind == .added)
        #expect(created.current?.status == .current && created.current?.progress == 0)

        #expect(harness.backend.writeCalls == [
            .edit(LibraryEdit(progress: .set(7)), Self.anime42, createIfMissing: .current),
            .edit(LibraryEdit(progress: .set(0)), manga7, createIfMissing: .current),
        ])
        #expect(service.banner.message == nil, "the rows show their own toast")
        #expect(actions.errorMessage == nil)
        await harness.settleSinks()
        await harness.tearDown()
    }
}

// MARK: - Outcome-returning primitives (E8)

/// `LibraryActions.save/apply/remove`: the primitives the views' explicit edits (mark progress, batch
/// status change, concierge quick-save, the detail pages' save toggle, QuickVerdict, AddToListSheet)
/// call instead of the store. They hand back exactly the store's typed outcome for exactly the store's
/// write, with no UI policy: no banner and no `errorMessage` (each view shows its own copy per case).
@MainActor
@Suite("Library actions: outcome-returning primitives", .timeLimit(.minutes(1)))
struct LibraryActionsPrimitiveTests {
    static let anime42 = MediaKey(kind: .anime, id: 42)
    static let manga7 = MediaKey(kind: .manga, id: 7)

    @Test("save: a missing title is added (.added); a tracked one is never changed (.updated, entry unchanged: 'Already in your list'); one insert-if-missing each; no banner, no errorMessage")
    func saveHandsBackTheStoresOutcome() async throws {
        let backend = FakeLibraryBackend()
        backend.setRows([FakeLibraryBackend.entry(.anime, 42, status: .completed, progress: 12, rating: 8)], for: FacadeHarness.userA)
        let harness = try FacadeHarness(backend: backend)
        let service = harness.service
        let actions = service.libraryActions
        await harness.signIn()
        let tracked = try #require(service.library.entry(for: Self.anime42))

        let kept = try #require(await actions.save(Self.anime42, status: .planning).change)
        #expect(kept.kind == .updated)
        #expect(kept.previous == tracked && kept.current == tracked)
        #expect(service.library.entry(for: Self.anime42) == tracked, "a save changed a tracked entry")

        let added = try #require(await actions.save(Self.manga7, status: .planning).change)
        #expect(added.kind == .added && added.previous == nil)
        #expect(added.current?.status == .planning)
        #expect(service.library.entry(for: Self.manga7)?.status == .planning)

        #expect(harness.backend.writeCalls == [.insertIfMissing(Self.anime42, .planning), .insertIfMissing(Self.manga7, .planning)])
        #expect(service.banner.message == nil)
        #expect(actions.errorMessage == nil)
        await harness.settleSinks()
        await harness.tearDown()
    }

    @Test("apply: the one edit is sent as given (createIfMissing included); a progress-only edit creates a missing title as Watching, a status-only edit keeps the stored progress; a missing entry without createIfMissing and a failed write hand back the typed error unchanged, with no banner and no errorMessage")
    func applyHandsBackTheStoresOutcome() async throws {
        let backend = FakeLibraryBackend()
        backend.setRows([FakeLibraryBackend.entry(.anime, 42, status: .current, progress: 3)], for: FacadeHarness.userA)
        let harness = try FacadeHarness(backend: backend)
        let service = harness.service
        let actions = service.libraryActions
        await harness.signIn()

        // Mark progress (`createIfMissing: .current`) on a title that is not tracked yet.
        let progressEdit = LibraryEdit(progress: .set(5))
        let marked = try #require(await actions.apply(progressEdit, to: Self.manga7, createIfMissing: .current).change)
        #expect(marked.kind == .added)
        #expect(marked.current?.status == .current && marked.current?.progress == 5)

        // Batch status change: status only; progress stays as stored.
        let statusEdit = LibraryEdit(status: .set(.completed))
        let changed = try #require(await actions.apply(statusEdit, to: Self.anime42, createIfMissing: .completed).change)
        #expect(changed.kind == .updated)
        #expect(changed.current?.status == .completed && changed.current?.progress == 3)

        // A verdict-only edit of a title that is not tracked: never created.
        let verdictEdit = LibraryEdit(verdict: .set(.masterpiece))
        let missing = await actions.apply(verdictEdit, to: MediaKey(kind: .anime, id: 9), createIfMissing: nil)
        #expect(missing == .failed(.notFound))

        harness.backend.failNextWrite(with: .retryable(message: "offline"))
        let failed = await actions.apply(LibraryEdit(progress: .set(4)), to: Self.anime42, createIfMissing: nil)
        #expect(failed == .failed(.retryable(message: "offline")))
        #expect(service.library.entry(for: Self.anime42)?.progress == 3, "the failed edit is withdrawn")

        #expect(harness.backend.writeCalls == [
            .edit(progressEdit, Self.manga7, createIfMissing: .current),
            .edit(statusEdit, Self.anime42, createIfMissing: .completed),
            .edit(verdictEdit, MediaKey(kind: .anime, id: 9), createIfMissing: nil),
            .edit(LibraryEdit(progress: .set(4)), Self.anime42, createIfMissing: nil),
        ])
        #expect(service.banner.message == nil, "failure UI policy belongs to the caller")
        #expect(actions.errorMessage == nil)
        await harness.settleSinks()
        await harness.tearDown()
    }

    @Test("remove: a tracked title is removed (.removed with its entry); a failed removal hands back the typed error and keeps the title; no banner, no errorMessage")
    func removeHandsBackTheStoresOutcome() async throws {
        let backend = FakeLibraryBackend()
        let stored = FakeLibraryBackend.entry(.anime, 42, status: .current, progress: 3)
        backend.setRows([stored, FakeLibraryBackend.entry(.manga, 7, rowId: 2, status: .planning)], for: FacadeHarness.userA)
        let harness = try FacadeHarness(backend: backend)
        let service = harness.service
        let actions = service.libraryActions
        await harness.signIn()

        let removed = try #require(await actions.remove(Self.anime42).change)
        #expect(removed.kind == .removed)
        #expect(removed.previous == stored && removed.current == nil)
        #expect(!service.library.isTracked(Self.anime42))

        harness.backend.failNextWrite(with: .conflict(server: nil))
        #expect(await actions.remove(Self.manga7) == .failed(.conflict(server: nil)))
        #expect(service.library.isTracked(Self.manga7), "a failed removal is rolled back")

        #expect(harness.backend.writeCalls == [.remove(Self.anime42), .remove(Self.manga7)])
        #expect(service.banner.message == nil, "failure UI policy belongs to the caller")
        #expect(actions.errorMessage == nil)
        await harness.settleSinks()
        await harness.tearDown()
    }

    @Test("Without a session every primitive answers .notAuthenticated and sends nothing")
    func noSessionSendsNothing() async throws {
        let harness = try FacadeHarness()
        let actions = harness.service.libraryActions

        #expect(await actions.save(Self.anime42, status: .planning) == .failed(.notAuthenticated))
        #expect(await actions.apply(LibraryEdit(progress: .set(1)), to: Self.anime42, createIfMissing: .current) == .failed(.notAuthenticated))
        #expect(await actions.remove(Self.anime42) == .failed(.notAuthenticated))
        #expect(harness.backend.writeCalls.isEmpty)
        #expect(harness.service.banner.message == nil)
        await harness.tearDown()
    }
}
