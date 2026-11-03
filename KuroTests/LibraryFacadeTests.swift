//
//  LibraryFacadeTests.swift
//  KuroTests
//
//  `LibraryActions` (the Library writer mapping) over the Library store: Observation of the store, account
//  switches during a write, synchronous toggles, the explicit change sinks, the session funnel
//  (including the old session's teardown tail, N1) and server-side writers. The store runs over a
//  `FakeLibraryBackend`; the SDK client answers in-process (StubPostgREST), so the sinks' Collection
//  and Releases follow-up requests can be counted and nothing reaches the network.
//

import Testing
import Foundation
import KuroCore
import KuroLibrary
import Observation
import Synchronization
@testable import Kuro

@MainActor
struct FacadeHarness {
    static let userA = LifecycleFixtures.userA
    static let userB = LifecycleFixtures.userB

    let server: StubServer
    let backend: FakeLibraryBackend
    let service: AppGraph
    let defaults: UserDefaults
    let notifications: FakeNotificationCenter
    private let suiteName: String

    init(backend: FakeLibraryBackend = FakeLibraryBackend()) throws {
        server = StubServer()
        self.backend = backend
        suiteName = "kuro.tests.library-facade.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        notifications = FakeNotificationCenter()
        service = AppComposition.testingGraph(
            testingUserDefaults: defaults,
            notificationCenter: notifications,
            client: StubSupabase.makeClient(server: server),
            libraryBackend: backend
        )
    }

    /// Signs in and waits for the session funnel's Library refresh.
    func signIn(_ userId: String = LifecycleFixtures.userA) async {
        await service.session.applySession(userId: userId, email: "\(userId)@example.com")
        await service.libraryActions.libraryRefreshTask?.value
    }

    func requests(to resource: String) -> [RecordedRequest] {
        server.requests.filter { $0.resource == resource }
    }

    var fetchAllCount: Int {
        backend.calls.filter { if case .fetchAll = $0 { return true } else { return false } }.count
    }

    func count(_ resource: String) -> Int { requests(to: resource).count }

    /// [collection_anime_page, collection_manga_page, collection_feed_page] RPC counts.
    /// The card-page counts stay 0: the visible collection is the feed.
    var collectionCounts: [Int] {
        [count("rpc/collection_anime_page"), count("rpc/collection_manga_page"), count("rpc/collection_feed_page")]
    }

    /// Puts a title of `key` on the loaded Collection feed (as a feed fetch would).
    func seedCollectionCard(_ key: MediaKey) {
        service.collection.collectionFeedItems.append(Media(
            id: key.id, kind: key.kind, title: "T", imageURL: nil, year: "2024", displayDescription: "",
            episodes: nil, chapters: nil, rating: nil, genres: nil, statusRaw: nil, formatRaw: nil,
            popularityValue: nil, trendingValue: nil, createdAtValue: nil
        ))
    }

    func isOnCollectionPages(_ key: MediaKey) -> Bool {
        service.collection.collectionFeedItems.contains { $0.kind == key.kind && $0.id == key.id }
    }

    /// Waits for the follow-up work the change sinks started.
    func settleSinks() async {
        await service.collection.collectionChangeTask?.value
        await service.releases.libraryChangeTask?.value
    }

    func tearDown() async {
        await service.session.endSession()
        defaults.removePersistentDomain(forName: suiteName)
        server.shutDown()
    }
}

@MainActor
@Suite("Library facade: forwarders, writes, sinks and session funnel", .timeLimit(.minutes(1)))
struct LibraryFacadeTests {
    static let userA = FacadeHarness.userA
    static let userB = FacadeHarness.userB

    @Test("Reading the store inside an observation scope is invalidated by a LibraryActions write")
    func forwardersRegisterObservation() async throws {
        let harness = try FacadeHarness()
        let service = harness.service
        await harness.signIn()

        let membershipChanged = Mutex(false)
        let idsChanged = Mutex(false)
        withObservationTracking {
            _ = service.library.isTracked(MediaKey(kind: .anime, id: 42))
        } onChange: {
            membershipChanged.withLock { $0 = true }
        }
        withObservationTracking {
            _ = service.library.keys(withStatus: .planning, kind: .anime)
        } onChange: {
            idsChanged.withLock { $0 = true }
        }

        #expect(await service.libraryActions.save(MediaKey(kind: .anime, id: 42), status: .planning).error == nil)

        #expect(membershipChanged.withLock { $0 })
        #expect(idsChanged.withLock { $0 })
        #expect(service.library.keys(withStatus: .planning, kind: .anime) == [MediaKey(kind: .anime, id: 42)])
        await harness.settleSinks()
        await harness.tearDown()
    }

    @Test("A write that outlives its account is rejected, publishes nothing and never lands as B's state")
    func accountSwitchMidWriteIsRejected() async throws {
        let gate = ControlledResponses<Bool>()
        let backend = FakeLibraryBackend(writeGate: gate)
        backend.setRows([FakeLibraryBackend.entry(.anime, 42, status: .current, progress: 3)], for: Self.userA)
        let harness = try FacadeHarness(backend: backend)
        let service = harness.service
        await harness.signIn(Self.userA)

        let rating = try #require(UserRating(value: 9))
        let write = Task {
            await service.libraryActions.apply(
                LibraryEdit(status: .set(.completed), progress: .set(12), rating: .set(rating)),
                to: MediaKey(kind: .anime, id: 42), createIfMissing: .completed
            )
        }
        #expect(await gate.waitForRequest("anime-42"))
        #expect(service.library.entry(for: MediaKey(kind: .anime, id: 42))?.status == .completed, "optimistic projection for A")

        await harness.signIn(Self.userB)
        gate.complete("anime-42", with: .success(true))
        let saved = await write.value

        #expect(saved.error != nil)
        #expect(service.libraryActions.errorMessage == nil)
        #expect(!service.library.isTracked(MediaKey(kind: .anime, id: 42)))
        #expect(service.library.allEntries.isEmpty)
        #expect(service.accountSession.current?.userId == Self.userB)
        #expect(harness.requests(to: "rpc/collection_feed_page").isEmpty, "no sink may run for A's write")
        #expect(service.collection.collectionChangeTask == nil)
        await harness.tearDown()
    }

    @Test("toggleInCollection flips synchronously, keeps the flip on success and rolls back on failure")
    func toggleFlipsSynchronously() async throws {
        let gate = ControlledResponses<Bool>()
        let harness = try FacadeHarness(backend: FakeLibraryBackend(writeGate: gate))
        let service = harness.service
        await harness.signIn()

        let add = service.libraryActions.toggleInCollection(mediaId: 42, mediaType: "anime")
        #expect(service.library.isTracked(MediaKey(kind: .anime, id: 42)), "Cards read isInCollection right after toggling")
        #expect(service.libraryActions.toggleInCollection(mediaId: 42, mediaType: "anime") == nil, "a double tap is ignored")
        #expect(await gate.waitForRequest("anime-42"))
        gate.complete("anime-42", with: .success(true))
        await add?.value
        #expect(service.library.isTracked(MediaKey(kind: .anime, id: 42)))
        #expect(service.banner.message == "Added to collection")
        #expect(harness.backend.writeCalls.count == 1, "one write for the double tap")
        #expect(service.libraryActions.togglingMediaKeys.isEmpty)

        harness.backend.failNextWrite(with: .retryable(message: "offline"))
        let failing = service.libraryActions.toggleInCollection(mediaId: 43, mediaType: "anime")
        #expect(service.library.isTracked(MediaKey(kind: .anime, id: 43)))
        #expect(await gate.waitForRequest("anime-43"))
        gate.complete("anime-43", with: .success(true))
        await failing?.value
        #expect(!service.library.isTracked(MediaKey(kind: .anime, id: 43)), "a failed add is rolled back")
        #expect(service.banner.message == "Couldn't update list. Try again.")
        #expect(service.libraryActions.errorMessage != nil)
        await harness.settleSinks()
        await harness.tearDown()
    }

    @Test("Change sinks fire once per applied change; the Collection sink never re-reads the list tables")
    func changeSinksFireOncePerAppliedChange() async throws {
        let harness = try FacadeHarness()
        let service = harness.service
        await harness.signIn()
        #expect(harness.fetchAllCount == 1, "the session funnel's refresh")

        func count(_ resource: String) -> Int { harness.count(resource) }
        func collectionCounts() -> [Int] { harness.collectionCounts }
        func releasesCounts() -> [Int] { [count("anime"), count("user_airing_next")] }

        // Added anime (watching: only watched anime arm reminders): Collection refresh + Releases
        // (reminders read the title, upcoming refreshes).
        #expect(await service.libraryActions.save(MediaKey(kind: .anime, id: 42), status: .current).error == nil)
        await harness.settleSinks()
        #expect(collectionCounts() == [0, 0, 1])
        #expect(releasesCounts() == [1, 1])
        #expect(harness.requests(to: "anime").first?.query("id") == "eq.42")

        // Edit of a tracked anime: Collection refresh; Releases re-arms the reminder (one title read,
        // no upcoming refresh).
        _ = await service.libraryActions.apply(LibraryEdit(verdict: .set(.masterpiece)), to: MediaKey(kind: .anime, id: 42), createIfMissing: nil)
        await harness.settleSinks()
        #expect(collectionCounts() == [0, 0, 2])
        #expect(releasesCounts() == [2, 1])

        // Saving an already tracked title writes nothing: no sink.
        #expect(await service.libraryActions.save(MediaKey(kind: .anime, id: 42), status: .planning).error == nil)
        await harness.settleSinks()
        #expect(collectionCounts() == [0, 0, 2])

        // Removal: the card leaves the loaded pages at once, then one page refresh; Releases cancels
        // the reminders and drops the countdown.
        let anime42 = MediaKey(kind: .anime, id: 42)
        harness.seedCollectionCard(anime42)
        harness.notifications.pending = ["airing-42-start", "airing-42-1h", "airing-7-start"]
        service.releases.countdownByAnimeId[42] = "1h"
        #expect(await service.libraryActions.removeFromList(mediaId: 42, mediaType: "anime"))
        #expect(!harness.isOnCollectionPages(anime42), "pruned by the Collection sink before any refresh")
        await harness.settleSinks()
        #expect(collectionCounts() == [0, 0, 3])
        #expect(harness.notifications.pending == ["airing-7-start"])
        #expect(service.releases.countdownByAnimeId[42] == nil)

        // Removing an anime the projection did not hold, straight through the store as the views do:
        // still fanned out (the server may have held it), so its reminders and card go.
        let anime77 = MediaKey(kind: .anime, id: 77)
        harness.seedCollectionCard(anime77)
        harness.notifications.pending = ["airing-77-start", "airing-7-start"]
        #expect(await service.library.remove(anime77).change != nil)
        #expect(!harness.isOnCollectionPages(anime77))
        await harness.settleSinks()
        #expect(collectionCounts() == [0, 0, 4])
        #expect(harness.notifications.pending == ["airing-7-start"])
        #expect(releasesCounts() == [2, 1])

        // The list projection was never re-read after a write (no fetchUserLists).
        #expect(harness.fetchAllCount == 1)
        #expect(count("anime_user_lists") == 0 && count("manga_user_lists") == 0)
        await harness.tearDown()
    }

    @Test("Session funnel: sign-in binds and refreshes; sign-out drops the projection before suspending")
    func sessionFunnelBindsAndResets() async throws {
        let backend = FakeLibraryBackend()
        backend.setRows([FakeLibraryBackend.entry(.anime, 42), FakeLibraryBackend.entry(.manga, 42)], for: Self.userA)
        let harness = try FacadeHarness(backend: backend)
        let service = harness.service

        await harness.signIn(Self.userA)
        #expect(service.library.isTracked(MediaKey(kind: .anime, id: 42)))
        #expect(service.library.isTracked(MediaKey(kind: .manga, id: 42)))

        let ended = service.session.endSessionState()
        #expect(!service.library.isTracked(MediaKey(kind: .anime, id: 42)), "reset before the first suspension")
        #expect(service.library.allEntries.isEmpty)
        await service.session.finishSessionEnd(ended)
        await harness.tearDown()
    }

    @Test("N1: a sign-in during the old session's teardown tail keeps the new account's reminders")
    func oldTeardownTailKeepsNewAccountReminders() async throws {
        let harness = try FacadeHarness()
        let service = harness.service
        let ownerKey = ReminderScheduler.airingRemindersOwnerKey
        await harness.signIn(Self.userA)
        harness.notifications.pending = ["airing-1-start", "airing-1-1h"]
        harness.defaults.set(Self.userA.lowercased(), forKey: ownerKey)

        // A signs out; the SDK sign-out is still in flight when B signs in.
        let ended = service.session.endSessionState()
        await harness.signIn(Self.userB)
        #expect(harness.notifications.pending.isEmpty, "B's start removes A's reminders")
        // B saves a title and gets its own reminders.
        harness.notifications.pending = ["airing-2-start", "airing-2-1h"]
        harness.defaults.set(Self.userB.lowercased(), forKey: ownerKey)

        // A's teardown tail finally runs.
        await service.session.finishSessionEnd(ended)

        #expect(harness.notifications.pending == ["airing-2-start", "airing-2-1h"])
        #expect(harness.defaults.string(forKey: ownerKey) == Self.userB.lowercased())
        #expect(service.accountSession.current?.userId == Self.userB)
        #expect(service.identity.isAuthenticated)
        await harness.tearDown()
    }

    @Test("Concierge apply and undo re-read the Library projection after the server-side write")
    func conciergeWritersRefreshLibrary() async throws {
        let harness = try FacadeHarness()
        let service = harness.service
        harness.server.respond { request in
            switch request.path {
            case "/functions/v1/concierge-apply":
                return .json(#"{"success":true,"sessionId":"s1","applied":[{"mediaType":"ANIME","mediaId":42,"status":"PLANNING"}]}"#)
            case "/functions/v1/concierge-undo":
                return .json(#"{"success":true,"sessionId":"s1","reverted":[{"mediaType":"ANIME","mediaId":42}]}"#)
            default:
                return .emptyArray
            }
        }
        await harness.signIn()
        #expect(!service.library.isTracked(MediaKey(kind: .anime, id: 42)))

        // The edge function wrote the row server-side; the parse cache's existing_entry copies are stale.
        try Self.seedParseCache(service)
        harness.backend.setRows([FakeLibraryBackend.entry(.anime, 42, status: .planning)], for: Self.userA)
        _ = try await service.imports.conciergeApply(items: [["mediaType": "ANIME", "mediaId": 42]])
        #expect(service.imports.conciergeParseCache.isEmpty)
        await service.libraryActions.libraryRefreshTask?.value
        #expect(service.library.isTracked(MediaKey(kind: .anime, id: 42)))

        // A local tracking change drops the parse cache too (Concierge sink).
        try Self.seedParseCache(service)
        _ = await service.libraryActions.apply(LibraryEdit(verdict: .set(.okay)), to: MediaKey(kind: .anime, id: 42), createIfMissing: nil)
        #expect(service.imports.conciergeParseCache.isEmpty)
        await harness.settleSinks()

        harness.backend.setRows([], for: Self.userA)
        _ = try await service.imports.conciergeUndo(sessionId: "s1")
        await service.libraryActions.libraryRefreshTask?.value
        #expect(!service.library.isTracked(MediaKey(kind: .anime, id: 42)))
        #expect(harness.fetchAllCount == 3)
        await harness.tearDown()
    }

    static func seedParseCache(_ service: AppGraph) throws {
        service.imports.conciergeParseCache["concierge_parse|a"] = .init(
            value: try LifecycleFixtures.decode(
                ConciergeParseResponse.self, #"{"success":true,"userId":"a","items":[]}"#
            ),
            storedAt: Date()
        )
    }

    @Test("Releases: progress patches avoid reminder reads; status changes re-arm watched anime only (paused/planned get none), manga never; removal cancels")
    func releasesReArmReminders() async throws {
        let backend = FakeLibraryBackend()
        backend.setRows([
            FakeLibraryBackend.entry(.anime, 42, progress: 3),
            FakeLibraryBackend.entry(.manga, 7, progress: 1),
        ], for: Self.userA)
        let harness = try FacadeHarness(backend: backend)
        let service = harness.service
        let airAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3 * 86_400))
        let animeRow = #"{"id":42,"title_english":"Title","title_romaji":null,"next_episode_number":5,"next_airing_at":"\#(airAt)"}"#
        harness.server.respond { request in
            request.resource == "anime" ? .json(animeRow) : .emptyArray
        }
        await harness.signIn()

        // Progress-only patches do not refetch the catalog or upcoming releases on every tap.
        await service.libraryActions.incrementProgress(mediaId: 42, mediaType: "anime")
        await harness.settleSinks()
        #expect(service.library.entry(for: MediaKey(kind: .anime, id: 42))?.progress == 4)
        #expect(harness.notifications.scheduled.isEmpty)
        #expect(harness.count("user_airing_next") == 0)

        // Another progress tap also avoids request growth.
        await service.libraryActions.incrementProgress(mediaId: 42, mediaType: "anime")
        await harness.settleSinks()
        #expect(service.library.entry(for: MediaKey(kind: .anime, id: 42))?.progress == 5)
        #expect(harness.notifications.scheduled.isEmpty)
        #expect(harness.count("anime") == 0)

        // A tracking status change to Paused arms no reminders (item 10: only watched titles notify),
        // and (since own-write realtime echoes are suppressed, `LibraryRealtimeEcho`) the Releases sink
        // itself refreshes upcoming airings when the status changes: the first change reads
        // `user_airing_next` once (the stub answers []), which records a successful read.
        #expect(await service.libraryActions.apply(LibraryEdit(status: .set(.paused)),
            to: MediaKey(kind: .anime, id: 42), createIfMissing: nil).error == nil)
        await harness.settleSinks()
        #expect(harness.notifications.scheduled.isEmpty, "a paused anime got episode reminders")
        #expect(harness.count("user_airing_next") == 1)
        // The second change also asks for a refresh, but it lands inside
        // `ReleasesStore.upcomingThrottle` (20 s) of that successful read for the same 7-day window,
        // so it is throttled: still exactly one read.
        #expect(await service.libraryActions.apply(LibraryEdit(status: .set(.current)),
            to: MediaKey(kind: .anime, id: 42), createIfMissing: nil).error == nil)
        await harness.settleSinks()
        #expect(harness.notifications.scheduled == ["airing-42-start", "airing-42-1h"], "watching again re-arms them")
        #expect(harness.count("user_airing_next") == 1)

        // A manga edit never touches airing reminders.
        await service.libraryActions.incrementProgress(mediaId: 7, mediaType: "manga")
        await harness.settleSinks()
        #expect(service.library.entry(for: MediaKey(kind: .manga, id: 7))?.progress == 2)
        #expect(harness.notifications.scheduled.count == 2)
        #expect(harness.count("anime") == 1)

        // Removing an anime the projection did not hold (through the store, as the views do) cancels.
        harness.notifications.pending += ["airing-99-start", "airing-99-1h"]
        _ = await service.library.remove(MediaKey(kind: .anime, id: 99))
        #expect(harness.notifications.pending == ["airing-42-start", "airing-42-1h"])

        // Removing the tracked anime cancels its reminders.
        #expect(await service.libraryActions.removeFromList(mediaId: 42, mediaType: "anime"))
        #expect(harness.notifications.pending.isEmpty)
        await harness.settleSinks()
        await harness.tearDown()
    }

    @Test("A refresh after a server-side write never joins a read that started before the write")
    func serverWriteRefreshIsFresh() async throws {
        let source = ControlledResponses<[LibraryEntry]>()
        let harness = try FacadeHarness(backend: FakeLibraryBackend(fetchSource: source))
        let service = harness.service
        harness.server.respond { request in
            request.path == "/functions/v1/concierge-apply" ? .json(#"{"success":true,"sessionId":"s1"}"#) : .emptyArray
        }
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        #expect(await source.waitForRequest(Self.userA), "the session funnel's read is held open")
        let viewRefresh = Task { await service.libraryActions.fetchUserLists() }

        _ = try await service.imports.conciergeApply(items: [["mediaType": "ANIME", "mediaId": 42]])
        #expect(await source.waitForRequest("\(Self.userA)#2"), "a second, fresh read started while the first is held")
        #expect(harness.fetchAllCount == 2, "the view refresh joined the funnel's read")

        source.complete(Self.userA, with: .success([]))
        source.complete("\(Self.userA)#2", with: .success([FakeLibraryBackend.entry(.anime, 42)]))
        await viewRefresh.value
        await service.libraryActions.libraryRefreshTask?.value
        #expect(service.library.isTracked(MediaKey(kind: .anime, id: 42)))
        #expect(service.libraryActions.errorMessage == nil)
        await harness.tearDown()
    }

    @Test("Cancelling a caller (e.g. the realtime debounce) never cancels the Library refresh it started")
    func cancelledCallerDoesNotCancelRefresh() async throws {
        let source = ControlledResponses<[LibraryEntry]>()
        let harness = try FacadeHarness(backend: FakeLibraryBackend(fetchSource: source))
        let service = harness.service
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        #expect(await source.waitForRequest(Self.userA))
        source.complete(Self.userA, with: .success([]))
        await service.libraryActions.libraryRefreshTask?.value

        let caller = Task { await service.libraryActions.fetchUserLists() }
        #expect(await source.waitForRequest("\(Self.userA)#2"))
        caller.cancel()
        source.complete("\(Self.userA)#2", with: .success([FakeLibraryBackend.entry(.anime, 42)]))
        await caller.value
        await service.libraryActions.libraryRefreshTask?.value

        #expect(service.library.isTracked(MediaKey(kind: .anime, id: 42)))
        #expect(service.libraryActions.errorMessage == nil, "no spurious 'Failed to fetch lists: cancelled'")
        await harness.tearDown()
    }

    @Test("Batch removal: cards leave the pages at once; ONE page refresh for the batch, none for skipRefresh")
    func batchRemovalRefreshesPagesOnce() async throws {
        let backend = FakeLibraryBackend()
        let keys = [1, 2, 3].map { MediaKey(kind: .anime, id: $0) }
        backend.setRows(keys.map { FakeLibraryBackend.entry(.anime, $0.id) } + [FakeLibraryBackend.entry(.manga, 9)], for: Self.userA)
        let harness = try FacadeHarness(backend: backend)
        let service = harness.service
        await harness.signIn()
        for key in keys { harness.seedCollectionCard(key) }

        await service.collection.withCollectionRefreshDeferred {
            for key in keys { _ = await service.library.remove(key) }
            #expect(keys.allSatisfy { !harness.isOnCollectionPages($0) }, "pruned while the refresh is deferred")
            #expect(harness.collectionCounts == [0, 0, 0])
        }
        #expect(harness.collectionCounts == [0, 0, 1], "one feed refresh for the whole batch")

        // skipRefresh: the caller refreshes the pages itself, the sink does not.
        #expect(await service.libraryActions.removeFromList(mediaId: 9, mediaType: "manga", skipRefresh: true))
        await harness.settleSinks()
        #expect(harness.collectionCounts == [0, 0, 1])
        await harness.tearDown()
    }
}

@MainActor
@Suite("Structured import publication", .timeLimit(.minutes(1)))
struct ImportPublicationContractTests {
    @Test("A failed authoritative read cannot publish Home readiness; recovery repeats reads only")
    func failedLibraryRefreshPreservesPublicationRecovery() async throws {
        let source = ControlledResponses<[LibraryEntry]>()
        let h = try FacadeHarness(backend: FakeLibraryBackend(fetchSource: source))
        await h.service.session.applySession(userId: FacadeHarness.userA, email: "a@example.com")
        #expect(await source.waitForRequest(FacadeHarness.userA))
        source.complete(FacadeHarness.userA, with: .success([]))
        await h.service.libraryActions.libraryRefreshTask?.value
        let account = try #require(h.service.accountSession.current)
        let homeReads = h.count("rpc/home_bundle_v1")
        let failed = Task { try await h.service.libraryActions.publishImport(revisions:["anime":1],for:account) }
        #expect(await source.waitForRequest("\(FacadeHarness.userA)#2"))
        source.complete("\(FacadeHarness.userA)#2", with: .failure(LibraryError.retryable(message:"503 after commit")))
        await #expect(throws: LibraryActions.ImportPublicationFailure.self) { try await failed.value }
        #expect(h.count("rpc/home_bundle_v1") == homeReads)
        #expect(h.backend.writeCalls.isEmpty)
        let recovery = Task { try await h.service.libraryActions.publishImport(revisions:[:],for:account) }
        #expect(await source.waitForRequest("\(FacadeHarness.userA)#3"))
        source.complete("\(FacadeHarness.userA)#3", with: .success([]))
        try await recovery.value
        #expect(h.backend.writeCalls.isEmpty)
        await h.tearDown()
    }

    @Test("A mounted series Collection republishes its current query once without resetting it")
    func publicationRefreshesVisibleSeriesQueryOnce() async throws {
        let h = try FacadeHarness()
        h.backend.setRows([FakeLibraryBackend.entry(.anime,42)],for:FacadeHarness.userA)
        let airingDate = ISO8601DateFormatter().string(from:Date().addingTimeInterval(3 * 86_400))
        h.server.respond { request in
            switch request.resource {
            case "rpc/collection_series_page_v1": return .json(#"{"groups":[],"next_cursor":null}"#)
            case "user_airing_next": return .json(#"[{"anime_id":42,"title_english":"Title","next_episode_number":5,"next_airing_at":"\#(airingDate)"}]"#)
            default: return .emptyArray
            }
        }
        await h.signIn()
        let account = try #require(h.service.accountSession.current)
        await h.service.collection.fetchSeriesPage(medium:"manga",status:"READING",query:"naruto",reset:true)
        let prior = h.count("rpc/collection_series_page_v1"), releases = h.count("user_airing_next"), reads = h.fetchAllCount
        try await h.service.libraryActions.publishImport(revisions:[:],for:account)
        #expect(h.fetchAllCount == reads + 1)
        #expect(h.count("rpc/collection_series_page_v1") == prior + 1)
        #expect(h.count("user_airing_next") == releases + 1)
        #expect(h.count("anime") == 0) // Already-fetched airing metadata schedules without per-title reads.
        #expect(h.notifications.scheduled.contains("airing-42-start"))
        let request = try #require(h.requests(to:"rpc/collection_series_page_v1").last)
        #expect(request.jsonObject?["p_medium"] as? String == "manga")
        #expect(request.jsonObject?["p_status"] as? String == "READING")
        #expect(request.jsonObject?["p_query"] as? String == "naruto")
        #expect(!h.service.collection.isCollectionLoading)
        await h.tearDown()
    }

    @Test("Imported subset uses both-medium canonical entries and removes reverted additions")
    func importedSubsetKeepsCanonicalMembershipAndRegularState() async throws {
        let h = try FacadeHarness()
        var anime = FakeLibraryBackend.entry(.anime,7), manga = FakeLibraryBackend.entry(.manga,7)
        anime.revision = 1; anime.lifecycleId = UUID(); manga.revision = 1; manga.lifecycleId = UUID()
        h.backend.setRows([anime,manga],for:FacadeHarness.userA)
        h.server.respond { request in
            switch request.resource {
            case "anime": return .json(#"[{"id":7,"title_english":"Anime seven"}]"#)
            case "manga": return .json(#"[{"id":7,"title_english":"Manga seven"}]"#)
            case "rpc/collection_series_page_v1": return .json(#"{"groups":[],"next_cursor":null}"#)
            default: return .emptyArray
            }
        }
        await h.signIn()
        let c = h.service.collection
        await c.fetchSeriesPage(medium:"manga",status:"READING",query:"retained query",reset:true)
        c.showImportedTitles([anime.key,manga.key])
        await c.fetchSeriesPage(medium:"anime",status:"COMPLETED",query:"ignored while subset",reset:true)
        #expect(c.displayedSeriesGroups.count == 2)
        #expect(Set(c.displayedFeedItems.map(\.libraryKey)) == [anime.key,manga.key])
        h.backend.setRows([manga],for:FacadeHarness.userA)
        try await h.service.library.refresh()
        #expect(c.displayedFeedItems.map(\.libraryKey) == [manga.key])
        c.clearImportedTitles()
        try await c.publishImport(for: try #require(h.service.accountSession.current))
        let restored = try #require(h.requests(to:"rpc/collection_series_page_v1").last)
        #expect(restored.jsonObject?["p_query"] as? String == "retained query")
        #expect(c.importedTitleKeys == nil)
        await h.tearDown()
    }
}

@MainActor
@Test func importedSubsetPaginationDoesNotSkipAfterEarlierRemoval() async throws {
    let h = try FacadeHarness()
    let rows = (1...31).map { id -> LibraryEntry in
        var row = FakeLibraryBackend.entry(.anime,id); row.revision = 1; row.lifecycleId = UUID(); return row
    }
    h.backend.setRows(rows,for:FacadeHarness.userA)
    h.server.respond { request in
        guard request.resource == "anime" else { return .emptyArray }
        let ids = (request.query("id") ?? "").split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return ListRowJSON.response(ids.map { ["id":$0,"title_english":"Title \($0)"] })
    }
    await h.signIn()
    let c = h.service.collection
    c.showImportedTitles(Set(rows.map(\.key)))
    await c.fetchSeriesPage(medium:"anime",status:nil,query:nil,reset:true)
    #expect(c.displayedFeedItems.count == 30)
    h.backend.setRows(Array(rows.dropFirst()),for:FacadeHarness.userA)
    try await h.service.library.refresh()
    await c.fetchSeriesPage(medium:"anime",status:nil,query:nil,reset:false)
    #expect(c.displayedFeedItems.contains { $0.id == 31 })
    #expect(!c.displayedFeedItems.contains { $0.id == 1 })
    await h.tearDown()
}
