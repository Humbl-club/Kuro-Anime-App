//
//  CollectionContractTests.swift
//  KuroTests
//
//  The Collection owner (`CollectionStore`): the interleaved feed, asserted on the HTTP requests
//  the real supabase-swift client emits (StubPostgREST: in-process, no network) and on what the
//  owner publishes. Unused anime/manga card-page RPCs stay at zero. Stale-account answers are
//  tested both ways: cancelled by the session funnel (`server.stoppedRequests`) and delivered after
//  another account became current (only the captured `AccountContext` protects). Each test is named
//  by the risk it covers.
//
//  Reused, not duplicated: the Library sink's prune-on-removed and one-refresh-per-change
//  (`LibraryFacadeTests.changeSinksFireOncePerAppliedChange`), the deferred batch and the skipRefresh
//  suppression (`LibraryFacadeTests.batchRemovalRefreshesPagesOnce`) and the private-state reset of
//  every Collection field (`AccountLifecycleTests`, PrivateStateResetTests). They run through the
//  service and its sinks against this owner.
//

import Testing
import Foundation
import KuroCore
import KuroLibrary
import Synchronization
@testable import Kuro

// MARK: - Fixtures

/// Collection page rows as the RPCs return them.
enum CollectionPages {
    /// `list_updated_at` of the row at `index`, newest first (one second older per row), with
    /// milliseconds, as PostgREST sends it.
    nonisolated static func stamp(_ index: Int) -> String {
        let seconds = 3_599 - index
        return String(format: "2026-02-03T04:%02d:%02d.123Z", seconds / 60, seconds % 60)
    }

    /// A timestamp the SDK sent or received, with an explicit timezone on the wire.
    nonisolated static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }

    /// Two timestamps name the same instant (millisecond precision).
    nonisolated static func sameInstant(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs, let rhs else { return false }
        return abs(lhs.timeIntervalSince(rhs)) < 0.0005
    }

    /// Feed row `index` (0-based) of a feed whose media ids start after `offset`: anime and manga
    /// alternate, `list_row_id` = 1000 + id.
    nonisolated static func feedRow(_ index: Int, offset: Int = 0) -> [String: Any] {
        let id = offset + index + 1
        return [
            "list_updated_at": stamp(index), "source_rank": index % 3, "list_row_id": 1_000 + id,
            "media_type": index % 2 == 0 ? "ANIME" : "MANGA", "id": id, "title_english": "Title \(id)",
        ]
    }

    /// A keyset-faithful `collection_feed_page`: the `p_limit` rows that follow the cursor row
    /// (`p_cursor_row_id`) in a feed of `total` rows; the first `p_limit` rows without a cursor.
    nonisolated static func feedPage(for request: RecordedRequest, total: Int, offset: Int = 0) -> StubResponse {
        let body = request.jsonObject ?? [:]
        let limit = body["p_limit"] as? Int ?? 0
        var start = 0
        if let cursor = body["p_cursor_row_id"] as? Int {
            start = min(total, max(0, cursor - 1_000 - offset))
        }
        let end = min(total, start + limit)
        return ListRowJSON.response((start..<end).map { feedRow($0, offset: offset) })
    }

    static let unavailable = StubResponse.json(#"{"message":"unavailable"}"#, status: 503)
}

/// Routes answers by a test-controlled phase and logs which requests arrived in which phase, so a
/// test can wait for a request it holds (also one that arrived earlier).
final class CollectionScript: Sendable {
    private struct Waiter {
        let key: String
        let continuation: CheckedContinuation<Void, Never>
    }

    private struct State {
        var phase: String
        var arrivals: [String] = []
        var waiters: [Waiter] = []
    }

    private let state: Mutex<State>

    init(phase: String) {
        state = Mutex(State(phase: phase))
    }

    func setPhase(_ phase: String) {
        state.withLock { $0.phase = phase }
    }

    /// Logs a request to `resource` in the current phase and returns that phase.
    func arrive(_ resource: String) -> String {
        let (phase, ready): (String, [Waiter]) = state.withLock { state in
            let key = "\(state.phase)|\(resource)"
            state.arrivals.append(key)
            let ready = state.waiters.filter { $0.key == key }
            state.waiters.removeAll { $0.key == key }
            return (state.phase, ready)
        }
        for waiter in ready { waiter.continuation.resume() }
        return phase
    }

    /// Suspends until a request to `resource` arrived in `phase`.
    func waitForArrival(of resource: String, in phase: String) async {
        let key = "\(phase)|\(resource)"
        await withCheckedContinuation { continuation in
            let arrived = state.withLock { state in
                if state.arrivals.contains(key) { return true }
                state.waiters.append(Waiter(key: key, continuation: continuation))
                return false
            }
            if arrived { continuation.resume() }
        }
    }

    /// How many requests to `resource` arrived in `phase`.
    func arrivals(of resource: String, in phase: String) -> Int {
        let key = "\(phase)|\(resource)"
        return state.withLock { $0.arrivals.filter { $0 == key }.count }
    }
}

// MARK: - Request counts

@MainActor
@Suite("Collection: request counts", .timeLimit(.minutes(1)))
struct CollectionRequestCountTests {

    @Test("Request regression: a cold start reads the Collection feed once; one Library change re-reads it once more and never the list tables or the unused card pages")
    func coldStartAndOneChangeRequestCounts() async throws {
        let harness = try FacadeHarness()
        let service = harness.service
        await harness.signIn()
        #expect(harness.collectionCounts == [0, 0, 0], "the session funnel itself reads no Collection page")

        // The session bootstrap's Collection read, issued exactly as `bootstrapAfterAuth` issues it.
        await service.collection.fetchCollectionFeed()
        #expect(harness.collectionCounts == [0, 0, 1])

        // One applied Library change: the Collection sink refreshes the feed once.
        #expect(await service.libraryActions.save(MediaKey(kind: .anime, id: 42), status: .planning).error == nil)
        await harness.settleSinks()
        #expect(harness.collectionCounts == [0, 0, 2])
        #expect(harness.fetchAllCount == 1, "the list projection is read by the session funnel only")
        #expect(harness.count("anime_user_lists") == 0 && harness.count("manga_user_lists") == 0)
        await harness.tearDown()
    }
}

// MARK: - Pages, account scope, latest wins, sink

@MainActor
@Suite("Collection: feed", .timeLimit(.minutes(1)))
struct CollectionContractTests {
    static let userA = FacadeHarness.userA
    static let userB = FacadeHarness.userB
    nonisolated static let feed = "rpc/collection_feed_page"
    nonisolated static let anime = "rpc/collection_anime_page"
    nonisolated static let manga = "rpc/collection_manga_page"

    /// Names of Collection fields that still hold a value after an account transition.
    static func leaks(in collection: CollectionStore) -> [String] {
        var leaks: [String] = []
        func check(_ name: String, _ isClear: Bool) { if !isClear { leaks.append(name) } }
        check("collectionFeedItems", collection.collectionFeedItems.isEmpty)
        check("hasMoreCollectionFeed", collection.hasMoreCollectionFeed)
        check("isLoadingMoreCollectionFeed", !collection.isLoadingMoreCollectionFeed)
        check("feed cursor", collection.collectionFeedCursorUpdatedAt == nil && collection.collectionFeedCursorSourceRank == nil
              && collection.collectionFeedCursorRowId == nil)
        check("currentCollectionStatusFilter", collection.currentCollectionStatusFilter == nil)
        check("isCollectionLoading", !collection.isCollectionLoading)
        check("collectionErrorMessage", collection.collectionErrorMessage == nil)
        return leaks
    }

    // MARK: (2) Keyset paging

    @Test("Keyset continuity: page 2 carries page 1's last cursor and appends without a duplicate or a gap")
    func keysetCursorContinuity() async throws {
        let previousTimeZone = NSTimeZone.default
        NSTimeZone.default = try #require(TimeZone(identifier: "America/Los_Angeles"))
        defer { NSTimeZone.default = previousTimeZone }
        #expect(NSTimeZone.default.secondsFromGMT() != 0)
        let harness = try FacadeHarness()
        harness.server.respond { request in
            request.resource == Self.feed ? CollectionPages.feedPage(for: request, total: 120) : .emptyArray
        }
        await harness.signIn()
        let collection = harness.service.collection

        await collection.fetchCollectionFeed(status: .current)

        // Feed page 1: a full page (90 of 120 rows), requested without a cursor.
        let page1 = try #require(harness.requests(to: Self.feed).first?.jsonObject)
        #expect(page1["p_cursor_row_id"] == nil && page1["p_cursor_updated_at"] == nil && page1["p_cursor_source_rank"] == nil)
        #expect(page1["p_list_type_anime"] as? String == "WATCHING" && page1["p_list_type_manga"] as? String == "READING")
        #expect(collection.collectionFeedItems.count == 90 && collection.hasMoreCollectionFeed)

        // Page 2 (load-more): page 1's last row is the cursor; the active filter is kept.
        #expect(await collection.fetchNextCollectionFeedPage(limit: 90))
        let feedRequests = harness.requests(to: Self.feed)
        #expect(feedRequests.count == 2)
        let page2 = try #require(feedRequests.last?.jsonObject)
        let lastOfPage1 = CollectionPages.feedRow(89)
        #expect(page2["p_cursor_updated_at"] as? String == CollectionPages.stamp(89), "fractional UTC cursor survives the actual owner/SDK route")
        #expect(page2["p_cursor_row_id"] as? Int == lastOfPage1["list_row_id"] as? Int)
        #expect(page2["p_cursor_source_rank"] as? Int == lastOfPage1["source_rank"] as? Int)
        #expect(CollectionPages.sameInstant(
            CollectionPages.date(page2["p_cursor_updated_at"] as? String),
            CollectionPages.date(CollectionPages.stamp(89))
        ), "\(page2["p_cursor_updated_at"] ?? "nil")")
        #expect(page2["p_list_type_anime"] as? String == "WATCHING" && page2["p_list_type_manga"] as? String == "READING")

        // Every row exactly once, in the server's order; the short last page ends the paging.
        #expect(collection.collectionFeedItems.map(\.id) == Array(1...120))
        #expect(!collection.hasMoreCollectionFeed)
        #expect(collection.collectionFeedCursorRowId == 1_120)
        #expect(!(await collection.fetchNextCollectionFeedPage(limit: 90)))
        #expect(harness.count(Self.feed) == 2, "no request past the last page")
        #expect(harness.count(Self.anime) == 0 && harness.count(Self.manga) == 0, "the feed does not load card pages")
        await harness.tearDown()
    }

    // MARK: (1) Account transitions

    /// A's work in flight at the switch: a feed refetch (owned, cancelled by the funnel), or
    /// a feed load-more (run in its caller's task) answered with rows or an error.
    enum InFlight: String, CaseIterable, Sendable { case refetch, loadMoreRows, loadMoreFailure }

    @Test("A -> B through the session funnel: A's pages, cursors, flags, filter and error are cleared at once, A's in-flight fetches are cancelled and no late A page, success or failure, publishes into B; B's own pages land",
          arguments: InFlight.allCases)
    func accountSwitchClearsAndCancels(inFlight: InFlight) async throws {
        let held = StubGate()
        let script = CollectionScript(phase: "A")
        let harness = try FacadeHarness()
        harness.server.respond { request in
            guard request.resource == Self.feed else { return .emptyArray }
            let phase = script.arrive(Self.feed)
            let accountA = phase != "B"
            let answer = CollectionPages.feedPage(for: request, total: accountA ? 120 : 2, offset: accountA ? 0 : 2_000)
            guard phase == "A-late" else { return answer }
            return (inFlight == .loadMoreFailure ? CollectionPages.unavailable : answer).held(by: held)
        }
        await harness.signIn(Self.userA)
        let service = harness.service
        let collection = service.collection

        // A's Collection: a full feed page (more to load), the Planned filter.
        await collection.fetchCollectionFeed(status: .planning)
        try #require(collection.collectionFeedItems.count == 90 && collection.hasMoreCollectionFeed)

        // A's next page is in flight (held) when B signs in.
        script.setPhase("A-late")
        let lateA: Task<Void, Never>
        switch inFlight {
        case .refetch:
            lateA = Task.immediate { @MainActor in
                await collection.fetchCollectionFeed(status: .planning)
            }
        case .loadMoreRows, .loadMoreFailure:
            lateA = Task.immediate { @MainActor in _ = await collection.fetchNextCollectionFeedPage(limit: 90) }
        }
        await script.waitForArrival(of: Self.feed, in: "A-late")

        script.setPhase("B")
        await service.session.applySession(userId: Self.userB, email: "b@example.com")
        #expect(Self.leaks(in: collection).isEmpty, "\(Self.leaks(in: collection))")
        #expect(collection.collectionFeedFetchInFlight == nil)

        if inFlight == .refetch {
            // The funnel cancelled A's fetch: its held request was stopped at the transport.
            _ = await harness.server.waitForStop { $0.resource == Self.feed }
            await lateA.value
            held.open()
            #expect(harness.server.stoppedRequests.count == 1)
        } else {
            // A load-more runs in its caller's task: its request is not stopped; its answer (rows or an
            // error) is delivered after the switch and dropped (bumped generation, A's context).
            held.open()
            await lateA.value
            #expect(harness.server.stoppedRequests.isEmpty)
        }
        #expect(Self.leaks(in: collection).isEmpty, "\(Self.leaks(in: collection))")
        #expect(harness.count(Self.anime) == 0 && harness.count(Self.manga) == 0, "card pages are not loaded")

        // B's own feed is what lands.
        await collection.fetchCollectionFeed()
        #expect(collection.collectionFeedItems.map(\.id) == [2_001, 2_002])
        #expect(collection.collectionErrorMessage == nil)
        await harness.tearDown()
    }

    enum Outcome: String, CaseIterable, Sendable { case success, failure }

    @Test("Stale guard: A's feed answer that arrives after B became current (nothing cancelled it) publishes nothing, restores nothing and writes no error",
          arguments: Outcome.allCases)
    func lateAnswerIsRejectedByItsContext(outcome: Outcome) async throws {
        let heldA = StubGate()
        let script = CollectionScript(phase: "A")
        let harness = try FacadeHarness()
        harness.server.respond { request in
            guard request.resource == Self.feed else { return .emptyArray }
            switch script.arrive(Self.feed) {
            case "A":
                return CollectionPages.feedPage(for: request, total: 120)
            case "A-late":
                let rows = CollectionPages.feedPage(for: request, total: 3, offset: 5_000)
                return (outcome == .success ? rows : CollectionPages.unavailable).held(by: heldA)
            default:
                return CollectionPages.feedPage(for: request, total: 2, offset: 2_000)
            }
        }
        await harness.signIn(Self.userA)
        let service = harness.service
        let collection = service.collection

        // A's loaded feed (the snapshot a failed refetch would restore).
        await collection.fetchCollectionFeed(status: .planning)
        try #require(collection.collectionFeedItems.count == 90)

        // A's refetch is held. It has already reset the feed; only its captured context may publish.
        script.setPhase("A-late")
        let lateA = Task.immediate { @MainActor in
            await collection.fetchCollectionFeed(status: .planning)
        }
        await script.waitForArrival(of: Self.feed, in: "A-late")

        // B becomes current WITHOUT the funnel's cancel, so A's request stays in flight.
        _ = service.accountSession.begin(userId: Self.userB)
        script.setPhase("B")
        heldA.open()
        await lateA.value
        #expect(harness.server.stoppedRequests.isEmpty, "A's answer was delivered, not cancelled")
        #expect(collection.collectionFeedItems.isEmpty, "\(collection.collectionFeedItems.map(\.id).prefix(5))")
        #expect(collection.collectionFeedCursorRowId == nil && collection.hasMoreCollectionFeed)
        #expect(collection.collectionErrorMessage == nil)
        #expect(collection.isCollectionLoading, "A's completion does not clear loading after the account changed")

        // B's own feed is what lands.
        await collection.fetchCollectionFeed()
        #expect(!collection.isCollectionLoading)
        #expect(collection.collectionFeedItems.map(\.id) == [2_001, 2_002])
        #expect(harness.count(Self.anime) == 0 && harness.count(Self.manga) == 0)
        await harness.tearDown()
    }

    // MARK: (3) Latest wins

    @Test("Latest wins: a second fetchCollectionFeed(status:) supersedes the first; the first's request is stopped, its cancellation is not surfaced and the second's filter and rows win")
    func secondFetchSupersedesFirst() async throws {
        let held = StubGate()
        let harness = try FacadeHarness()
        harness.server.respond { request in
            guard request.resource == Self.feed else { return .emptyArray }
            switch request.jsonObject?["p_list_type_anime"] as? String {
            case "PLANNING":
                return CollectionPages.feedPage(for: request, total: 1, offset: 110).held(by: held)
            case "COMPLETED":
                return CollectionPages.feedPage(for: request, total: 2, offset: 221)
            default:
                return .emptyArray
            }
        }
        await harness.signIn()
        let collection = harness.service.collection

        let first = Task.immediate { @MainActor in await collection.fetchCollectionFeed(status: .planning) }
        _ = await harness.server.waitForRequest { $0.resource == Self.feed }
        await collection.fetchCollectionFeed(status: .completed)
        let stopped = await harness.server.waitForStop { $0.resource == Self.feed }
        await first.value
        held.open()

        #expect(stopped.jsonObject?["p_list_type_anime"] as? String == "PLANNING")
        #expect(collection.currentCollectionStatusFilter == .completed)
        #expect(collection.collectionFeedItems.map(\.id) == [222, 223])
        #expect(collection.collectionErrorMessage == nil, "the superseded fetch's cancellation is not an error")
        #expect(!collection.isCollectionLoading && !collection.isLoadingMoreCollectionFeed)
        #expect(harness.count(Self.anime) == 0 && harness.count(Self.manga) == 0)
        await harness.tearDown()
    }

    @Test("Latest wins: a load-more superseded by a new feed fetch publishes nothing and leaves the loading flag to the new generation")
    func supersededLoadMoreKeepsTheNewFlag() async throws {
        let heldLoadMore = StubGate()
        let heldRefetch = StubGate()
        let script = CollectionScript(phase: "seed")
        let harness = try FacadeHarness()
        harness.server.respond { request in
            guard let resource = request.resource, resource == Self.feed else { return .emptyArray }
            let phase = script.arrive(resource)
            let page = CollectionPages.feedPage(for: request, total: 120)
            if request.jsonObject?["p_cursor_row_id"] != nil { return page.held(by: heldLoadMore) }
            return phase == "refetch" ? page.held(by: heldRefetch) : page
        }
        await harness.signIn()
        let collection = harness.service.collection
        await collection.fetchCollectionFeed()
        try #require(collection.collectionFeedItems.count == 90 && collection.hasMoreCollectionFeed)

        // Load-more of page 2 is out ...
        let loadMore = Task.immediate { @MainActor in await collection.fetchNextCollectionFeedPage(limit: 90) }
        _ = await harness.server.waitForRequest { $0.resource == Self.feed && $0.jsonObject?["p_cursor_row_id"] != nil }
        #expect(collection.isLoadingMoreCollectionFeed)

        // ... when a pull-to-refresh starts a new generation, whose first page is held too.
        script.setPhase("refetch")
        let refetch = Task.immediate { @MainActor in await collection.fetchCollectionFeed() }
        await script.waitForArrival(of: Self.feed, in: "refetch")
        #expect(collection.isLoadingMoreCollectionFeed, "the new generation's page is loading")

        // The superseded load-more's answer is delivered (nothing cancelled it) and dropped.
        heldLoadMore.open()
        let loaded = await loadMore.value
        #expect(!loaded)
        #expect(harness.server.stoppedRequests.isEmpty)
        #expect(collection.isLoadingMoreCollectionFeed, "the superseded page left the flag to the new generation")
        #expect(collection.collectionFeedItems.isEmpty, "its rows never land in the new generation's feed")

        heldRefetch.open()
        await refetch.value
        #expect(!collection.isLoadingMoreCollectionFeed)
        #expect(collection.collectionFeedItems.map(\.id) == Array(1...90))
        await harness.tearDown()
    }

    // MARK: (4) Library change sink

    @Test("Library sink: a second change while the first feed refresh is in flight cancels it (latest wins); the first feed is stopped and the second runs once")
    func sinkRefreshIsLatestWins() async throws {
        let held = StubGate()
        let script = CollectionScript(phase: "first")
        let harness = try FacadeHarness()
        harness.server.respond { request in
            guard request.resource == Self.feed else { return .emptyArray }
            let phase = script.arrive(Self.feed)
            if phase == "first" {
                return CollectionPages.feedPage(for: request, total: 1, offset: 110).held(by: held)
            }
            return CollectionPages.feedPage(for: request, total: 2, offset: 10)
        }
        await harness.signIn()
        let service = harness.service
        let collection = service.collection

        #expect(await service.libraryActions.save(MediaKey(kind: .anime, id: 42), status: .planning).error == nil)
        let firstRefresh = try #require(collection.collectionChangeTask)
        await script.waitForArrival(of: Self.feed, in: "first")

        script.setPhase("second")
        #expect(await service.libraryActions.save(MediaKey(kind: .manga, id: 43), status: .planning).error == nil)
        let secondRefresh = try #require(collection.collectionChangeTask)
        _ = await harness.server.waitForStop { $0.resource == Self.feed }
        await secondRefresh.value
        await firstRefresh.value
        held.open()
        await harness.settleSinks()

        #expect(firstRefresh.isCancelled, "the newer refresh cancelled its predecessor")
        #expect(harness.collectionCounts == [0, 0, 2], "\(harness.collectionCounts)")
        #expect(harness.server.stoppedRequests.count == 1)
        #expect(collection.collectionFeedItems.map(\.id) == [11, 12])
        await harness.tearDown()
    }

    @Test("Library sink: a skipRefresh removal inside a deferred batch keeps the batch's single page refresh")
    func skippedRemovalInsideDeferredBatch() async throws {
        let backend = FakeLibraryBackend()
        backend.setRows([FakeLibraryBackend.entry(.anime, 1), FakeLibraryBackend.entry(.anime, 2)], for: Self.userA)
        let harness = try FacadeHarness(backend: backend)
        let service = harness.service
        await harness.signIn()
        let keys = [1, 2].map { MediaKey(kind: .anime, id: $0) }
        for key in keys { harness.seedCollectionCard(key) }

        await service.collection.withCollectionRefreshDeferred {
            _ = await service.library.remove(keys[0])
            #expect(await service.libraryActions.removeFromList(mediaId: 2, mediaType: "anime", skipRefresh: true))
            #expect(keys.allSatisfy { !harness.isOnCollectionPages($0) }, "both cards pruned at once")
            #expect(harness.collectionCounts == [0, 0, 0])
        }
        #expect(harness.collectionCounts == [0, 0, 1], "the batch's one feed refresh survives the skipped removal inside it")
        await harness.settleSinks()
        #expect(harness.collectionCounts == [0, 0, 1])
        await harness.tearDown()
    }

    @Test("Batch status: the screen's workflow writes each item, keeps one failure, and refreshes the visible feed once")
    func batchStatusRefreshesTheVisibleFeedOnce() async throws {
        let backend = FakeLibraryBackend()
        let keys = [1, 2, 3].map { MediaKey(kind: .anime, id: $0) }
        backend.setRows(keys.map { FakeLibraryBackend.entry(.anime, $0.id) }, for: Self.userA)
        let harness = try FacadeHarness(backend: backend)
        let service = harness.service
        let collection = service.collection
        await harness.signIn()
        backend.failNextWrite(with: .retryable(message: "offline"))
        // A different active filter must not win: the refresh reads the filter the screen is showing.
        collection.currentCollectionStatusFilter = .dropped

        let outcomes = await collection.applyBatchStatusChange(
            .completed,
            to: keys,
            visibleFilter: .planning
        ) { edit, key, createIfMissing in
            #expect(harness.collectionCounts == [0, 0, 0], "no feed refresh until the batch ends")
            #expect(edit == LibraryEdit(status: .set(.completed)))
            #expect(createIfMissing == .completed)
            return await service.libraryActions.apply(edit, to: key, createIfMissing: createIfMissing)
        }

        #expect(outcomes.count == 3)
        #expect(outcomes[0].error == .retryable(message: "offline"))
        #expect(outcomes[0].change == nil)
        #expect(outcomes[1].error == nil && outcomes[1].change?.key == keys[1])
        #expect(outcomes[2].error == nil && outcomes[2].change?.key == keys[2])
        #expect(service.library.entry(for: keys[0])?.status == .current, "the failed write stays as it was")
        #expect(service.library.entry(for: keys[1])?.status == .completed)
        #expect(service.library.entry(for: keys[2])?.status == .completed)
        #expect(backend.writeCalls == keys.map {
            .edit(LibraryEdit(status: .set(.completed)), $0, createIfMissing: .completed)
        })
        #expect(harness.collectionCounts == [0, 0, 1], "one feed refresh, no card pages: \(harness.collectionCounts)")
        let page = try #require(harness.requests(to: Self.feed).first?.jsonObject)
        #expect(page["p_list_type_anime"] as? String == "PLANNING")
        #expect(page["p_list_type_manga"] as? String == "PLANNING")
        #expect(collection.currentCollectionStatusFilter == .planning)
        await harness.settleSinks()
        #expect(harness.collectionCounts == [0, 0, 1], "the sink does not start a second feed refresh")
        await harness.tearDown()
    }

    @Test("A held batch cannot dispatch its second edit as B or end B's Collection/Home removal scope")
    func batchAccountSwitchKeepsNewAccountScope() async throws {
        let gate = ControlledResponses<Bool>()
        let backend = FakeLibraryBackend(writeGate: gate)
        let aKeys = [1, 2].map { MediaKey(kind: .anime, id: $0) }
        let bKeys = [11, 12].map { MediaKey(kind: .anime, id: $0) }
        backend.setRows(aKeys.map { FakeLibraryBackend.entry(.anime, $0.id) }, for: Self.userA)
        backend.setRows((bKeys + [aKeys[1]]).map { FakeLibraryBackend.entry(.anime, $0.id) }, for: Self.userB)
        let script = CollectionScript(phase: "bootstrap")
        let harness = try SessionSDKHarness(responder: StubAuth.signInResponder { request in
            if let resource = request.resource { _ = script.arrive(resource) }
            if request.resource == "rpc/home_bundle_v1" {
                return .json(#"{"medium":"anime","window_days":7,"home_revision":0,"active":[],"upcoming":[],"pending":[],"schedule_state":"ready","club":{"state":"empty","label":"Between us.","items":[]}}"#)
            }
            return .emptyArray
        }, libraryBackend: backend)
        let service = harness.graph
        let collection = service.collection
        try await harness.session.signInWithEmail(email: "a@example.com", password: "pw")
        await service.libraryActions.libraryRefreshTask?.value

        // Complete an unwanted second write if the regression returns, so it fails assertions
        // instead of hanging the test at a fake transport gate.
        let unexpectedSecond = Task {
            if await gate.waitForRequest("anime-2") {
                gate.complete("anime-2", with: .success(true))
            }
        }
        let oldBatch = Task {
            await collection.applyBatchStatusChange(.completed, to: aKeys, visibleFilter: .planning) {
                await service.libraryActions.apply($0, to: $1, createIfMissing: $2)
            }
        }
        #expect(await gate.waitForRequest("anime-1"))
        #expect(collection.collectionRefreshDeferrals == 1)

        try await harness.session.signInWithEmail(email: "b@example.com", password: "pw")
        await service.libraryActions.libraryRefreshTask?.value
        // Real SDK sign-in bootstraps each account's feed. A mounted Home must also
        // have a confirmed bundle before its change sink schedules another read.
        await service.home.load()
        #expect(service.home.bundle != nil)
        let afterBootstrap = harness.server.requests.count
        script.setPhase("batch")
        collection.currentCollectionStatusFilter = .paused
        #expect(collection.collectionRefreshDeferrals == 0, "A's scopes were invalidated at the account boundary")
        let newBatch = Task {
            await collection.applyBatchRemoval(to: bKeys) {
                await LibraryViewActions.remove($0, actions: service.libraryActions)
            }
        }
        #expect(await gate.waitForRequest("anime-11"))
        gate.complete("anime-11", with: .success(true))
        #expect(await gate.waitForRequest("anime-12"))
        #expect(collection.collectionRefreshDeferrals == 1 && collection.collectionRefreshDeferred)

        gate.complete("anime-1", with: .success(true))
        let obsoleteOutcomes = await oldBatch.value
        gate.callerFinished("anime-2")
        await unexpectedSecond.value
        #expect(obsoleteOutcomes.isEmpty, "an obsolete result is not a current batch outcome")
        #expect(!gate.requests.contains("anime-2"), "A's second edit must never be dispatched as B")
        #expect(backend.rows(for: Self.userB)[aKeys[1]]?.status == .current)
        #expect(collection.currentCollectionStatusFilter == .paused)
        #expect(collection.collectionRefreshDeferrals == 1 && collection.collectionRefreshDeferred,
                "A's completion must not decrement or flush B's pending scope")
        #expect(script.arrivals(of: Self.feed, in: "batch") == 0)
        #expect(script.arrivals(of: "rpc/home_bundle_v1", in: "batch") == 0)

        gate.complete("anime-12", with: .success(true))
        #expect(await newBatch.value == 2)
        #expect(collection.collectionRefreshDeferrals == 0 && !collection.collectionRefreshDeferred)
        #expect(collection.currentCollectionStatusFilter == .paused)
        let feeds = harness.server.requests.dropFirst(afterBootstrap).filter { $0.resource == Self.feed }
        #expect(feeds.count == 1, "only B's batch refreshes the feed")
        let feed = try #require(feeds.first)
        #expect(feed.bearerSubject?.lowercased() == Self.userB.lowercased())
        #expect(feed.jsonObject?["p_list_type_anime"] as? String == "PAUSED")
        await script.waitForArrival(of: "rpc/home_bundle_v1", in: "batch")
        let home = try #require(harness.server.requests.dropFirst(afterBootstrap).first { $0.resource == "rpc/home_bundle_v1" })
        #expect(script.arrivals(of: "rpc/home_bundle_v1", in: "batch") == 1)
        #expect(home.bearerSubject?.lowercased() == Self.userB.lowercased(),
                "B's Home refresh is not stuck behind A's abandoned deferral")
        await harness.tearDown()
    }

}
