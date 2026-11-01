//
//  MultiUserPageOrchestrationTests.swift
//  KuroTests
//
//  Layer B: three simultaneous AppGraphs (users A / B / C) exercise page surfaces as owner
//  calls — Concierge/Collection/Library (A), Clubs + private initials (B), Discover/Browse/Search
//  then an account switch (C). StubPostgREST only; no network; no production UI; rag_assist_v1
//  untouched. Does not claim the 16 device smoke journeys or G0–G7.
//

import Testing
import Foundation
import KuroCore
import KuroLibrary
import Synchronization
@testable import Kuro

@MainActor
@Suite("Multi-user page orchestration (Layer B)", .timeLimit(.minutes(2)))
struct MultiUserPageOrchestrationTests {
    static let userA = LifecycleFixtures.userA
    static let userB = LifecycleFixtures.userB
    /// Third concurrent graph (not in LifecycleFixtures).
    static let userC = "C0D1E2F3-A4B5-6789-C0D1-E2F3A4B56789"

    @Test("Three graphs: A imports/collection, B private club initials + ClubError details, C discover/browse/search then switch drops late work")
    func threeUsersGenerateDifferentPageWork() async throws {
        let aBackend = FakeLibraryBackend()
        // Existing server fixture: the later progress-only import must retain these fields.
        let stored = FakeLibraryBackend.entry(.anime, 107, status: .completed, progress: 12, rating: 8, notes: "keep me")
        aBackend.setRows([stored], for: Self.userA)
        let aServer = StubServer()
        let aChannels = FakeClubChannels()
        aServer.respond { request in
            if request.path == "/functions/v1/concierge-apply" {
                // Model server effects only when the production ImportsService actually dispatches.
                guard let items = request.jsonObject?["items"] as? [[String: Any]],
                      !items.isEmpty, items.count <= 100 else {
                    return .json(#"{"error":"Invalid import"}"#, status: 400)
                }
                var rows = aBackend.rows(for: Self.userA)
                for item in items {
                    guard let id = item["mediaId"] as? Int, item["mediaType"] as? String == "ANIME" else {
                        return .json(#"{"error":"Invalid media"}"#, status: 400)
                    }
                    let key = MediaKey(kind: .anime, id: id)
                    var row = rows[key] ?? FakeLibraryBackend.entry(.anime, id, status: .planning)
                    if let progress = item["progressEpisodes"] as? Int { row.progress = progress }
                    rows[key] = row
                }
                aBackend.setRows(Array(rows.values), for: Self.userA)
                let response: [String: Any] = [
                    "success": true, "sessionId": "s-a", "status": "applied",
                    "applied": items.map { ["mediaType": "ANIME", "mediaId": $0["mediaId"]!, "status": $0["status"]!] },
                ]
                return StubResponse(status: 200, body: try! JSONSerialization.data(withJSONObject: response))
            }
            if request.resource == "rpc/collection_feed_page" {
                let limit = request.jsonObject?["p_limit"] as? Int ?? 90
                let entries = aBackend.rows(for: Self.userA).values.sorted { $0.key.id < $1.key.id }
                return ListRowJSON.response(entries.prefix(limit).enumerated().map { index, entry in
                    var row = CollectionPages.feedRow(index)
                    row["id"] = entry.key.id
                    row["media_type"] = "ANIME"
                    return row
                })
            }
            return .emptyArray
        }
        let aSuite = "kuro.tests.multi.a.\(UUID().uuidString)"
        let aDefaults = try #require(UserDefaults(suiteName: aSuite))
        let graphA = AppComposition.testingGraph(
            testingUserDefaults: aDefaults,
            notificationCenter: FakeNotificationCenter(),
            client: StubSupabase.makeClient(server: aServer),
            libraryBackend: aBackend,
            clubChannels: aChannels
        )

        let bServer = StubServer()
        let bChannels = FakeClubChannels()
        bServer.respond { request in
            switch request.resource {
            case "rpc/fetch_my_clubs_enriched", "rpc/fetch_my_clubs_loading":
                return .json("""
                [
                  {"id":"club-private","name":"Private","sharing_level":"private","is_archived":false,
                   "created_at":"2026-01-01T00:00:00Z","member_count":3,"member_names":["Ada","Ben","Cara"]},
                  {"id":"club-status","name":"Status","sharing_level":"status","is_archived":false,
                   "created_at":"2026-01-01T00:00:00Z","member_count":2,"member_names":["Dee","Ed"]}
                ]
                """)
            case "rpc/add_club_rail_item":
                return ClubJSON.error(message: "Duplicate rail item", code: "23505", details: "DUPLICATE_ITEM")
            case "rpc/fetch_club_bundle":
                let clubId = request.jsonObject?["p_club_id"] as? String ?? "club-private"
                return .json(ClubJSON.bundle(clubId: clubId, mediaId: 501, role: "owner")
                    .replacingOccurrences(of: "m1", with: Self.userB.lowercased()))
            default:
                return .emptyArray
            }
        }
        let bSuite = "kuro.tests.multi.b.\(UUID().uuidString)"
        let bDefaults = try #require(UserDefaults(suiteName: bSuite))
        let graphB = AppComposition.testingGraph(
            testingUserDefaults: bDefaults,
            notificationCenter: FakeNotificationCenter(),
            client: StubSupabase.makeClient(server: bServer),
            clubChannels: bChannels,
            clubRefreshDebounce: .zero
        )

        let cBundleGate = StubGate()
        let cBundles = Mutex(0)
        // Signalled by the responder once the late (second) bundle request is held. Waiting on the
        // server's request waiters with a `cBundles >= 2` predicate cannot work: waiters are matched
        // before the responder runs, so the late request itself is always seen with a count of 1.
        let (lateBundleHeld, lateBundleHeldSignal) = AsyncStream<Void>.makeStream()
        let cServer = StubServer()
        cServer.respond { request in
            switch request.resource {
            case "rpc/discover_bundle":
                let n = cBundles.withLock { count -> Int in
                    count += 1
                    return count
                }
                if n == 1 {
                    return PublicRowJSON.bundle(newToYou: [301])
                }
                // Second (late) answer for C after switch: must not land on A.
                lateBundleHeldSignal.yield()
                return PublicRowJSON.bundle(newToYou: [999]).held(by: cBundleGate)
            case "rpc/browse_anime_page":
                return PublicRowJSON.cards([401, 402])
            case "rpc/search_anime_page":
                return PublicRowJSON.cards([501])
            default:
                return .emptyArray
            }
        }
        let cSuite = "kuro.tests.multi.c.\(UUID().uuidString)"
        let cDefaults = try #require(UserDefaults(suiteName: cSuite))
        let graphC = AppComposition.testingGraph(
            testingUserDefaults: cDefaults,
            notificationCenter: FakeNotificationCenter(),
            client: StubSupabase.makeClient(server: cServer)
        )

        defer {
            aDefaults.removePersistentDomain(forName: aSuite)
            bDefaults.removePersistentDomain(forName: bSuite)
            cDefaults.removePersistentDomain(forName: cSuite)
            aServer.shutDown()
            bServer.shutDown()
            cServer.shutDown()
        }

        // --- Sign in all three concurrently ---
        await graphA.session.applySession(userId: Self.userA, email: "a@example.com")
        await graphA.libraryActions.libraryRefreshTask?.value
        await graphB.session.applySession(userId: Self.userB, email: "b@example.com")
        await graphC.session.applySession(userId: Self.userC, email: "c@example.com")

        // --- A: Concierge apply limit + progress-only shape + Collection/Library ---
        #expect(ImportReconciler.sendsStoredRatingAndNotes == false)

        let lines: [ConciergeParseItem] = (1...105).map { id in
            ImportReconcilerTests.item("Title \(id)", candidates: [ImportReconcilerTests.candidate(.anime, id)])
        }
        let ready = ImportReconcilerTests.prepared(lines)
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
            existing: ImportReconcilerTests.library([])
        )
        #expect(batch.items.count == 100)
        #expect(batch.omitted == 5)
        #expect(ImportReconciler.omittedApplyCopy(omitted: 5, german: false) != nil)

        let progressLine = ImportReconcilerTests.item(
            "Frieren ep 13",
            parsed: ImportReconcilerTests.parsed(episodes: 13),
            candidates: [ImportReconcilerTests.candidate(.anime, 107)]
        )
        let progressPayload = try #require(
            ImportReconcilerTests.applyItems([progressLine], library: [stored]).first
        ).payload
        #expect(progressPayload["rating"] == nil)
        #expect(progressPayload["notes"] == nil)
        #expect(progressPayload["status"] as? String == "COMPLETED")

        let ambiguous = ImportReconcilerTests.prepared(
            ImportReconcilerTests.lines(for: .parserAmbiguity)
        )
        #expect(ImportReconciler.conciergeAutoApplyPlan(for: ambiguous, loadState: .loaded, existing: ImportReconcilerTests.library([])) == .review)
        #expect(ImportReconciler.profileImportPlan(for: ambiguous, loadState: .loaded, existing: ImportReconcilerTests.library([])) == .review)

        // Dispatch the reconciled batch through the production owner, then the view's feed refresh.
        let readsBeforeApply = aBackend.calls.count
        let feedsBeforeApply = aServer.requests.filter { $0.resource == "rpc/collection_feed_page" }.count
        let firstKey = UUID().uuidString.lowercased()
        let applied = try await graphA.imports.conciergeApply(items: batch.items.map(\.payload), idempotencyKey: firstKey)
        #expect(applied.success && applied.applied?.count == 100)
        await graphA.libraryActions.libraryRefreshTask?.value
        #expect(aBackend.calls.count == readsBeforeApply + 1, "one Library read after the server-side import")
        #expect(graphA.library.isTracked(MediaKey(kind: .anime, id: 1)))
        #expect(!graphA.library.isTracked(MediaKey(kind: .anime, id: 101)), "omitted inputs were not dispatched")
        await graphA.collection.fetchCollectionFeed()
        #expect(aServer.requests.filter { $0.resource == "rpc/collection_feed_page" }.count == feedsBeforeApply + 1)
        #expect(graphA.collection.collectionFeedItems.contains { $0.id == 1 })
        let firstRequest = try #require(aServer.requests.first { $0.path == "/functions/v1/concierge-apply" })
        let dispatched = try #require(firstRequest.jsonObject?["items"] as? [[String: Any]])
        #expect(dispatched.count == 100)
        #expect(dispatched.compactMap { $0["mediaId"] as? Int } == batch.items.map { $0.key.id })
        #expect(firstRequest.jsonObject?["idempotencyKey"] as? String == firstKey)

        // A second real dispatch updates progress while preserving server-owned rating/notes/status.
        let progressReads = aBackend.calls.count
        let progressFeeds = aServer.requests.filter { $0.resource == "rpc/collection_feed_page" }.count
        let progressKey = UUID().uuidString.lowercased()
        let progressed = try await graphA.imports.conciergeApply(items: [progressPayload], idempotencyKey: progressKey)
        #expect(progressed.applied?.first?.mediaId == 107)
        await graphA.libraryActions.libraryRefreshTask?.value
        #expect(aBackend.calls.count == progressReads + 1)
        await graphA.collection.fetchCollectionFeed()
        #expect(aServer.requests.filter { $0.resource == "rpc/collection_feed_page" }.count == progressFeeds + 1)
        let applyRequests = aServer.requests.filter { $0.path == "/functions/v1/concierge-apply" }
        #expect(applyRequests.count == 2)
        let progressRequest = try #require(applyRequests.last)
        #expect(progressRequest.jsonObject?["idempotencyKey"] as? String == progressKey)
        let sentProgress = try #require((progressRequest.jsonObject?["items"] as? [[String: Any]])?.first)
        #expect(sentProgress["progressEpisodes"] as? Int == 13)
        #expect(sentProgress["status"] as? String == "COMPLETED")
        #expect(sentProgress["rating"] == nil && sentProgress["notes"] == nil)
        let saved = try #require(graphA.library.entry(for: MediaKey(kind: .anime, id: 107)))
        #expect(saved.progress == 13 && saved.status == .completed)
        #expect(saved.rating?.value == 8 && saved.notes == "keep me")
        #expect(aBackend.writeCalls.isEmpty, "the client refreshes server effects; it never writes list rows locally")

        // B and C must not see A's library rows.
        #expect(!graphB.library.isTracked(MediaKey(kind: .anime, id: 1)))
        #expect(!graphC.library.isTracked(MediaKey(kind: .anime, id: 1)))
        #expect(graphB.collection.collectionFeedItems.isEmpty)
        #expect(graphC.collection.collectionFeedItems.isEmpty)

        // --- B: private vs status club initials + details-only ClubError ---
        await graphB.clubs.fetchMyClubs()
        let privateClub = try #require(graphB.clubs.myClubs.first { $0.sharing_level == "private" })
        let statusClub = try #require(graphB.clubs.myClubs.first { $0.sharing_level == "status" })
        #expect(ClubsListCardRules.memberInitials(sharingLevel: privateClub.sharing_level, memberNames: privateClub.member_names) == [])
        #expect(ClubsListCardRules.memberInitials(sharingLevel: statusClub.sharing_level, memberNames: statusClub.member_names) == ["D", "E"])

        let bundle = try await graphB.clubs.fetchClubBundle(clubId: "club-private")
        #expect(bundle.members.contains { $0.user_id == Self.userB.lowercased() })
        let rail = try #require(bundle.rails.first)
        let epoch = graphB.clubs.revocationEpoch("club-private")
        await #expect(throws: ClubError.duplicateItem) {
            _ = try await graphB.clubs.addRailItem(railId: rail.id, mediaType: "ANIME", mediaId: 501)
        }
        let writes = bServer.requests.filter { $0.resource == "rpc/add_club_rail_item" }
        #expect(writes.count == 1)
        #expect(writes.first?.jsonObject?["p_rail_id"] as? String == rail.id)
        #expect(writes.first?.jsonObject?["p_media_id"] as? Int == 501)
        #expect(graphB.clubs.revocationEpoch("club-private") == epoch, "duplicate item is not membership loss")

        // A and C never received B's clubs.
        #expect(graphA.clubs.myClubs.isEmpty)
        #expect(graphC.clubs.myClubs.isEmpty)

        // --- C: Discover / Browse / Search, then switch mid-flight ---
        #expect(await graphC.discovery.fetchDiscoverBundle()?.anime.newToYou.map(\.id) == [301])
        let browse = await graphC.discovery.fetchBrowseAnimePageKeyset(
            genre: nil, status: nil, minEpisodes: nil, maxEpisodes: nil,
            cursorInt: nil, cursorDate: nil, cursorId: nil, limit: 60
        )
        #expect(browse.map(\.id) == [401, 402])
        graphC.search.resetSearch(query: "frieren", isManga: false)
        await graphC.search.fetchNextSearchPage()
        #expect(graphC.search.searchAnimeItems.map(\.id) == [501])

        // Start a forced Discover refetch held open, then switch C → A on graphC.
        let lateBundle = Task.immediate { @MainActor in
            await graphC.discovery.fetchDiscoverBundle(force: true)
        }
        var lateHeld = lateBundleHeld.makeAsyncIterator()
        _ = await lateHeld.next()
        #expect(cBundles.withLock { $0 } == 2, "exactly one late bundle request is in flight")

        await graphC.session.applySession(userId: Self.userA, email: "a-on-c@example.com")
        #expect(graphC.discovery.discoverBundleCache.isEmpty, "account switch must clear C's Discover cache")
        #expect(graphC.identity.currentUserId == Self.userA)

        cBundleGate.open()
        _ = await lateBundle.value
        // Late C bundle (999) must not publish into A's cache key on this graph.
        #expect(
            graphC.discovery.discoverBundleCache.values.contains { $0.value.anime.newToYou.map(\.id) == [999] } == false,
            "C's late Discover answer leaked onto A"
        )

        // Cross-graph isolation still holds for A and B graphs.
        #expect(graphA.library.isTracked(MediaKey(kind: .anime, id: 1)))
        #expect(graphB.clubs.myClubs.contains { $0.id == "club-private" })

        await graphA.session.endSession()
        await graphB.session.endSession()
        await graphC.session.endSession()
    }
}
