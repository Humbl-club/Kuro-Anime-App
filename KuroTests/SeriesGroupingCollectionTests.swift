import Foundation
import KuroCore
import KuroLibrary
import Testing
@testable import Kuro

/// W6: Collection grouping state (per-account switch, release switch, member cards, account safety).
@MainActor
@Suite struct SeriesGroupingCollectionTests {
    static let on = ["--ff-on=collection_series_grouping_v1"]

    nonisolated static func threeSeasons(ids: [Int]) -> [LibraryEntry] {
        ids.map { FakeLibraryBackend.entry(.anime, $0, rowId: $0, status: .current, progress: 1) }
    }

    /// Serves reviewed spans for `ids` (one series, ordinals 1...n) and, when `cards` is set, anime cards.
    nonisolated static func responder(series: String, ids: [Int], cards: Bool = false, gate: StubGate? = nil) -> StubServer.Responder {
        { request in
            switch request.resource {
            case "series_entry_spans":
                return ListRowJSON.response(ids.enumerated().map { index, id in
                    SeriesMembershipReaderTests.span(id, series: series, ordinal: index + 1)
                })
            case "anime" where cards:
                let asked = SeriesMembershipReaderTests.ids(request, column: "id")
                let response = ListRowJSON.response(asked.map { [
                    "id": $0, "title_romaji": "Title \($0)", "is_adult": false,
                    "created_at": ListRowJSON.createdAt, "updated_at": ListRowJSON.updatedAt,
                ] as [String: Any] })
                return gate.map { response.held(by: $0) } ?? response
            default:
                return .emptyArray
            }
        }
    }

    @Test func groupSeasonsSwitchIsRememberedPerAccount() async throws {
        let suite = "kuro.w6.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ids = [401, 402, 403]
        var h = try FacadeHarness(userDefaults: defaults, launchArguments: Self.on)
        h.backend.setRows(Self.threeSeasons(ids: ids), for: FacadeHarness.userA)
        h.server.respond(with: Self.responder(series: "D", ids: ids))
        await h.signIn()
        await h.service.collection.prepareSeriesGrouping(medium: .anime, loadedFeed: [])
        #expect(h.service.collection.groupsSeasons == true)                 // default on
        #expect(h.service.collection.seriesRows(medium: .anime).count == 1)
        h.service.collection.setGroupsSeasons(false)
        #expect(h.service.collection.seriesRows(medium: .anime).map(\.members.count) == [1, 1, 1])
        await h.tearDown()
        h = try FacadeHarness(userDefaults: defaults, launchArguments: Self.on)   // relaunch
        h.backend.setRows(Self.threeSeasons(ids: ids), for: FacadeHarness.userA)
        h.server.respond(with: Self.responder(series: "D", ids: ids))
        await h.signIn()
        #expect(h.service.collection.groupsSeasons == false)
        #expect(h.service.collection.seriesRows(medium: .anime).count == 3)
        await h.signIn(FacadeHarness.userB)                                  // another account on the phone
        #expect(h.service.collection.groupsSeasons == true)
        #expect(defaults.object(forKey: CollectionStore.groupSeasonsKey(userId: FacadeHarness.userA)) as? Bool == false)
        try await h.service.collection.removeDeletedAccountData(userId: FacadeHarness.userA)
        #expect(defaults.object(forKey: CollectionStore.groupSeasonsKey(userId: FacadeHarness.userA)) == nil)
        await h.tearDown()
    }

    @Test func groupSeasonsKeyHashesTheLowercasedUserId() {
        let key = CollectionStore.groupSeasonsKey(userId: "ABC")
        #expect(key == CollectionStore.groupSeasonsKey(userId: "abc"))
        #expect(key.hasPrefix("kuro.collection.groupSeasons.") && key.count == "kuro.collection.groupSeasons.".count + 16)
        #expect(!key.contains("abc"))
    }

    @Test func flagOffSendsNoRequest() async throws {
        let ids = [411, 412, 413]
        let h = try FacadeHarness()   // no launch argument: collection_series_grouping_v1 is off
        h.backend.setRows(Self.threeSeasons(ids: ids), for: FacadeHarness.userA)
        h.server.respond(with: Self.responder(series: "F", ids: ids, cards: true))
        await h.signIn()
        let collection = h.service.collection
        await collection.prepareSeriesGrouping(medium: .anime, loadedFeed: [])
        let account = try #require(h.service.accountSession.current)
        let entry = FakeLibraryBackend.entry(.anime, 499, status: .current)
        collection.libraryDidChange(LibraryChange(key: entry.key, kind: .added, previous: nil, current: entry,
                                                  mutationId: UUID(), account: account))
        await collection.seriesChangeTask?.value
        #expect(h.requests(to: "series_entry_spans").isEmpty)
        #expect(h.requests(to: "anime").isEmpty && h.requests(to: "manga").isEmpty)
        #expect(collection.isSeriesGroupingAvailable == false)
        #expect(collection.seriesRows(medium: .anime).map(\.members.count) == [1, 1, 1])
        await h.tearDown()
    }

    @Test func addingATitleReadsItsMembershipOnceWhenOn() async throws {
        let h = try FacadeHarness(launchArguments: Self.on)
        h.server.respond(with: Self.responder(series: "G", ids: []))
        await h.signIn()
        let account = try #require(h.service.accountSession.current)
        let entry = FakeLibraryBackend.entry(.anime, 498, status: .current)
        h.service.collection.libraryDidChange(LibraryChange(key: entry.key, kind: .added, previous: nil, current: entry,
                                                            mutationId: UUID(), account: account))
        await h.service.collection.seriesChangeTask?.value
        #expect(h.requests(to: "series_entry_spans").count == 1)
        await h.tearDown()
    }

    @Test func hydratesOffFeedMemberCardsWhileTheAccountIsCurrent() async throws {
        let ids = [421, 422]
        let h = try FacadeHarness(launchArguments: Self.on)
        h.backend.setRows(Self.threeSeasons(ids: ids), for: FacadeHarness.userA)
        h.server.respond(with: Self.responder(series: "H", ids: ids, cards: true))
        await h.signIn()
        await h.service.collection.prepareSeriesGrouping(medium: .anime, loadedFeed: [MediaKey(kind: .anime, id: 422)])
        #expect(h.service.collection.seriesMemberMedia.keys.map(\.id) == [421], "only the off-feed member is hydrated")
        #expect(h.service.collection.memberMedia(MediaKey(kind: .anime, id: 421))?.title == "Title 421")
        await h.tearDown()
    }

    @Test func memberHydrationFromPreviousAccountIsDropped() async throws {
        let ids = [431, 432]
        let gate = StubGate()
        let h = try FacadeHarness(launchArguments: Self.on)
        h.backend.setRows(Self.threeSeasons(ids: ids), for: FacadeHarness.userA)
        h.server.respond(with: Self.responder(series: "I", ids: ids, cards: true, gate: gate))
        await h.signIn()
        let collection = h.service.collection
        let task = Task { await collection.prepareSeriesGrouping(medium: .anime, loadedFeed: []) }
        _ = await h.server.waitForRequest { $0.resource == "anime" }
        await h.signIn(FacadeHarness.userB)
        gate.open()
        await task.value
        #expect(collection.seriesMemberMedia.isEmpty)
        await h.tearDown()
    }

    @Test func membershipReadNeverSendsPreviousAccountsIdsWithNewCredentials() async throws {
        let ids = [441, 442, 443]
        let suite = "kuro.w6.flags.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = FakeLibraryBackend()
        backend.setRows(Self.threeSeasons(ids: ids), for: StubAuth.userA)
        let h = try SessionSDKHarness(
            responder: StubAuth.signInResponder(rest: Self.responder(series: "J", ids: ids, cards: true)),
            libraryBackend: backend,
            flags: FeatureFlags(userDefaults: defaults, launchArguments: Self.on))
        let sessionB = try await CredentialLeaseTests.signedInAsAKeepingBsSession(h)
        let collection = h.graph.collection
        let prepare = Task.immediate { @MainActor in
            await collection.prepareSeriesGrouping(medium: .anime, loadedFeed: [])
        }
        // Before dispatch the SDK installs B's session and the funnel switches to B.
        h.storage.replace(with: sessionB)
        let switching = Task.immediate { @MainActor in
            _ = await h.session.applySession(userId: CredentialLeaseTests.userB, email: "b@example.com")
        }
        await prepare.value
        await switching.value
        let sent = h.server.requests.filter { $0.resource == "series_entry_spans" || $0.resource == "anime" }
        #expect(sent.isEmpty, "A's library ids were dispatched after A's account ended: \(sent)")
        #expect(!sent.contains { $0.bearerSubject == CredentialLeaseTests.userB.lowercased() })
        #expect(collection.seriesMemberMedia.isEmpty)
        #expect(h.graph.catalog.seriesMembershipCheckedAt.isEmpty)
        await h.tearDown()
    }
}
