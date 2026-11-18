//
//  UpNextStoreTests.swift
//  KuroTests
//
//  W10 "Up next in your series": the pure contract (decoding, device filter, copy), the owner
//  `UpNextStore` against the in-process StubPostgREST, and the Collection section's placement rules.
//

import Testing
import Foundation
import KuroCore
import KuroLibrary
@testable import Kuro

@MainActor
@Suite("Up next", .serialized, .timeLimit(.minutes(1)))
struct UpNextStoreTests {
    // MARK: Pure contract

    @Test func rowsDecodeBothMedia() throws {
        let anime = Data("""
        {"media_type":"anime","media_id":1,"title":"Frieren S2","cover_image":null,"format":"TV","status":"NOT_YET_RELEASED",
         "start_year":2026,"total_units":12,"after_media_id":9,"after_title":"Frieren","link":"sequel"}
        """.utf8)
        let item = try JSONDecoder().decode(UpNextItem.self, from: anime)
        #expect(item.key == MediaKey(kind: .anime, id: 1))
        #expect(item.afterKey == MediaKey(kind: .anime, id: 9))
        #expect(item.link == .sequel)
        #expect(item.isAnnounced)
        let manga = Data("""
        {"media_type":"manga","media_id":5,"title":"B","after_media_id":4,"after_title":"A","link":"reviewed"}
        """.utf8)
        let m = try JSONDecoder().decode(UpNextItem.self, from: manga)
        #expect(m.key == MediaKey(kind: .manga, id: 5))
        #expect(m.afterKey == MediaKey(kind: .manga, id: 4))
        #expect(m.link == .reviewed)
        #expect(!m.isAnnounced)
        let film = Data("""
        {"media_type":"film","media_id":5,"title":"B","after_media_id":4,"after_title":"A","link":"sequel"}
        """.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(UpNextItem.self, from: film) }
    }

    @Test func trackedOrHiddenRowsNeverShow() {
        func item(_ id: Int) -> UpNextItem {
            UpNextItem(key: MediaKey(kind: .anime, id: id), title: "T\(id)", afterKey: MediaKey(kind: .anime, id: 100),
                       afterTitle: "P", link: .sequel)
        }
        let a1 = item(1), a2 = item(2), a3 = item(3)
        let tracked: Set<MediaKey> = [a2.key], hidden: Set<MediaKey> = [a3.key]
        #expect(UpNextPolicy.visible([a1, a2, a3], tracked: tracked, hidden: hidden).map(\.key) == [a1.key])
        #expect(UpNextPolicy.visible([a3, a1], tracked: tracked, hidden: hidden).map(\.key) == [a1.key])
        #expect(UpNextPolicy.visible([a1, a2, a3], tracked: [], hidden: []) == [a1, a2, a3])
    }

    @Test func copyIsEnglishAndGerman() {
        #expect(UpNextCopy.after("Frieren", german: false) == "Sequel to Frieren")
        #expect(UpNextCopy.after("Frieren", german: true) == "Fortsetzung von Frieren")
        #expect(UpNextCopy.heading(german: false) == "Up next in your series")
        #expect(UpNextCopy.heading(german: true) == "Als Nächstes in deinen Reihen")
        #expect(UpNextCopy.alreadyInLibrary(german: false) == "Already in your library.")
        #expect(UpNextCopy.alreadyInLibrary(german: true) == "Schon in deiner Bibliothek.")
        #expect(UpNextCopy.announced(german: true) == "Angekündigt")
        #expect(UpNextCopy.plan(german: true) == "Planen")
        #expect(UpNextCopy.dismissSubtitle(german: false) == "Also hidden on Discover.")
    }
}

// MARK: - The owner (UpNextStore) over the in-process stub server

private let upNextRPC = "rpc/library_up_next_v1"
private let upNextSignalRPC = "rpc/record_taste_deck_signal"
private let upNextRowJSON = """
[{"media_type":"anime","media_id":1201,"title":"Frieren S2","cover_image":null,"format":"TV","status":"FINISHED",
  "start_year":2026,"total_units":12,"after_media_id":1200,"after_title":"Frieren","link":"sequel"}]
"""
private let upNextItem = UpNextItem(
    key: MediaKey(kind: .anime, id: 1201), title: "Frieren S2",
    afterKey: MediaKey(kind: .anime, id: 1200), afterTitle: "Frieren", link: .sequel)

/// A graph over the stub client with a fenced fake Library backend (rows carry lifecycle id and revision).
@MainActor
private struct UpNextHarness {
    static let userA = "6F1C4C3E-0A7B-4D7E-9C55-3D2A1B0C9E8A"
    static let userB = "0B9E8D7C-6A5B-4C3D-8E2F-1A0B9C8D7E6F"

    let server = StubServer()
    let backend = FakeLibraryBackend(fence: true)
    let graph: AppGraph
    let defaults: UserDefaults
    private let suiteName: String

    init(launchArguments: [String] = ["--ff-on=collection_up_next_v1"],
         upNext: @escaping @Sendable (RecordedRequest) -> StubResponse = { _ in .json(upNextRowJSON) }) throws {
        server.respond { request in
            switch request.resource {
            case upNextRPC: return upNext(request)
            case upNextSignalRPC: return .json(#"{"ok":true}"#)
            default: return .emptyArray
            }
        }
        suiteName = "kuro.tests.up-next.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        graph = AppComposition.testingGraph(
            testingUserDefaults: defaults,
            notificationCenter: FakeNotificationCenter(),
            client: StubSupabase.makeClient(server: server),
            libraryBackend: backend,
            flags: FeatureFlags(userDefaults: defaults, launchArguments: launchArguments)
        )
    }

    var upNext: UpNextStore { graph.upNext }
    var library: LibraryStore { graph.library }
    var actions: LibraryActions { graph.libraryActions }

    func signIn(_ userId: String = UpNextHarness.userA) async {
        await graph.session.applySession(userId: userId, email: "\(userId)@example.com")
        await graph.libraryActions.libraryRefreshTask?.value
    }

    var rpcRequests: [RecordedRequest] { server.requests.filter { $0.resource == upNextRPC } }

    func sentSignals() -> [String] {
        server.requests.filter { $0.resource == upNextSignalRPC }.compactMap { request in
            guard let body = request.jsonObject, let action = body["p_action"] as? String,
                  let id = body["p_media_id"] as? Int, let type = body["p_media_type"] as? String else { return nil }
            return "\(action) \(type) \(id)"
        }
    }

    func tearDown() async {
        await graph.session.endSession()
        defaults.removePersistentDomain(forName: suiteName)
        server.shutDown()
    }
}

extension UpNextStoreTests {
    private static let key = MediaKey(kind: .anime, id: 1201)

    @Test func planFromUpNextAddsToPlanningAndRemovesRow() async throws {
        let h = try UpNextHarness()
        await h.signIn()
        await h.upNext.load(.anime)
        let item = try #require(h.upNext.visible(.anime).first)
        #expect(h.upNext.visible(.anime).map(\.key) == [Self.key])

        let receipt = try #require(await h.upNext.plan(item))
        let entry = try #require(h.library.entry(for: Self.key))
        #expect(receipt.created)
        #expect(entry.status == .planning)
        #expect(receipt.rowId == entry.rowId && receipt.lifecycleId == entry.lifecycleId && receipt.revision == entry.revision)
        #expect(entry.lifecycleId != nil && entry.revision != nil, "the fenced fake stamps identity")
        #expect(h.upNext.visible(.anime).isEmpty)
        #expect(h.rpcRequests.count == 1, "leaving the section needs no refetch")

        #expect(await h.upNext.undoPlan(receipt))
        #expect(h.library.entry(for: Self.key) == nil)
        #expect(h.upNext.visible(.anime).map(\.key) == [Self.key])
        await h.tearDown()
    }

    @Test func dismissHidesTitleForThisAccount() async throws {
        let h = try UpNextHarness()
        await h.signIn()
        await h.upNext.load(.anime)
        let item = try #require(h.upNext.visible(.anime).first)
        let receipt = try #require(h.upNext.dismiss(item))
        #expect(h.upNext.visible(.anime).isEmpty)
        #expect(h.graph.taste.isHiddenOnDiscover(Self.key))
        _ = await h.server.waitForRequest { $0.resource == upNextSignalRPC }
        #expect(h.sentSignals() == ["skip ANIME 1201"])

        await h.upNext.load(.anime, force: true)
        #expect(h.upNext.visible(.anime).isEmpty, "the server still returns the row; the device memory hides it")

        await h.signIn(UpNextHarness.userB)
        await h.upNext.load(.anime)
        #expect(h.upNext.visible(.anime).map(\.key) == [Self.key], "another account's dismissal never applies")
        await h.signIn(UpNextHarness.userA)
        await h.upNext.load(.anime)
        #expect(h.upNext.visible(.anime).isEmpty, "A's device memory comes back with A")
        _ = receipt
        await h.tearDown()
    }

    @Test func dismissUndoShowsTheRowAgain() async throws {
        let h = try UpNextHarness()
        await h.signIn()
        await h.upNext.load(.anime)
        let receipt = try #require(h.upNext.dismiss(upNextItem))
        #expect(h.upNext.undoDismiss(receipt))
        #expect(h.upNext.visible(.anime).map(\.key) == [Self.key])
        await h.tearDown()
    }

    @Test func loadFinishingAfterAccountSwitchPublishesNothing() async throws {
        let gate = StubGate()
        let h = try UpNextHarness(upNext: { _ in StubResponse.json(upNextRowJSON).held(by: gate) })
        await h.signIn()
        let load = Task.immediate { @MainActor in await h.upNext.load(.anime) }
        _ = await h.server.waitForRequest { $0.resource == upNextRPC }
        await h.signIn(UpNextHarness.userB)
        gate.open()
        await load.value
        #expect(h.upNext.visible(.anime).isEmpty)
        #expect(h.upNext.phase[.anime] != .loaded)
        await h.upNext.load(.anime)
        #expect(h.upNext.visible(.anime).map(\.key) == [Self.key])
        #expect(h.upNext.phase[.anime] == .loaded)
        await h.tearDown()
    }

    @Test func undeployedContractHidesSectionSilently() async throws {
        let h = try UpNextHarness(upNext: { _ in
            .json(#"{"code":"PGRST202","message":"Could not find the function","details":null,"hint":null}"#, status: 404)
        })
        await h.signIn()
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        h.upNext.now = { clock }
        await h.upNext.load(.anime)
        #expect(h.upNext.phase[.anime] == .hidden)
        #expect(h.upNext.visible(.anime).isEmpty)
        let first = h.rpcRequests.count
        #expect(first == 1)
        await h.upNext.load(.anime, force: true)
        #expect(h.rpcRequests.count == first, "not asked again within 30 minutes")
        clock = clock.addingTimeInterval(UpNextPolicy.undeployedRetry + 60)
        await h.upNext.load(.anime)
        #expect(h.rpcRequests.count == first + 1)
        await h.tearDown()
    }

    @Test func offlineWithoutRowsShowsBrandedOffline() async throws {
        let h = try UpNextHarness(upNext: { _ in .failure(.notConnectedToInternet) })
        await h.signIn()
        await h.upNext.load(.anime)
        #expect(h.upNext.phase[.anime] == .offline)
        #expect(h.upNext.visible(.anime).isEmpty)

        h.server.respond { request in request.resource == upNextRPC ? .json(upNextRowJSON) : .emptyArray }
        await h.upNext.load(.anime, force: true)
        #expect(h.upNext.phase[.anime] == .loaded)
        h.server.respond { request in request.resource == upNextRPC ? .failure(.notConnectedToInternet) : .emptyArray }
        await h.upNext.load(.anime, force: true)
        #expect(h.upNext.phase[.anime] == .loaded, "an offline reload keeps the rows")
        #expect(h.upNext.visible(.anime).map(\.key) == [Self.key])
        await h.tearDown()
    }

    @Test func flagOffSendsNoRequest() async throws {
        let h = try UpNextHarness(launchArguments: [])
        await h.signIn()
        await h.upNext.load(.anime)
        await h.upNext.load(.anime, force: true)
        #expect(h.rpcRequests.isEmpty)
        #expect(h.upNext.phase[.anime] == .hidden)
        #expect(h.upNext.visible(.anime).isEmpty)
        #expect(await h.upNext.plan(upNextItem) == nil)
        #expect(h.upNext.dismiss(upNextItem) == nil)
        #expect(h.backend.writeCalls.isEmpty)
        #expect(h.sentSignals().isEmpty)
        await h.tearDown()
    }

    @Test func planOfAnExistingEntryOffersNoUndo() async throws {
        let h = try UpNextHarness()
        h.backend.setRows([FakeLibraryBackend.entry(.anime, 1201, rowId: 7, status: .planning)],
                          for: UpNextHarness.userA)
        await h.signIn()
        #expect(h.library.isTracked(Self.key))
        let receipt = try #require(await h.upNext.plan(upNextItem))
        #expect(!receipt.created && !receipt.offersUndo)
        #expect(await h.upNext.undoPlan(receipt) == false)
        #expect(h.library.entry(for: Self.key) != nil)
        #expect(!h.backend.writeCalls.contains { if case .remove = $0 { return true } else { return false } })
        await h.tearDown()
    }

    enum InterveningChange: CaseIterable, Sendable {
        case progress, dateOnly, repeatCount, ratingSetThenCleared, removeAndReAdd
    }

    @Test(arguments: InterveningChange.allCases)
    func undoPlanRefusedAfterTheEntryChanged(change: InterveningChange) async throws {
        let h = try UpNextHarness()
        await h.signIn()
        await h.upNext.load(.anime)
        let receipt = try #require(await h.upNext.plan(upNextItem))
        #expect(receipt.created)
        let key = Self.key
        switch change {
        case .progress:
            _ = await h.actions.apply(LibraryEdit(progress: .set(2)), to: key, createIfMissing: nil)
        case .dateOnly:
            _ = await h.actions.apply(LibraryEdit(startedOn: .set(try #require(PartialDate(raw: "2026-11")))), to: key, createIfMissing: nil)
        case .repeatCount:
            _ = await h.actions.apply(LibraryEdit(repeatCount: .set(1)), to: key, createIfMissing: nil)
        case .ratingSetThenCleared:
            _ = await h.actions.apply(LibraryEdit(rating: .set(try #require(UserRating(value: 7)))), to: key, createIfMissing: nil)
            _ = await h.actions.apply(LibraryEdit(rating: .clear), to: key, createIfMissing: nil)
        case .removeAndReAdd:
            _ = await h.actions.remove(key)
            _ = await h.actions.save(key, status: .planning)
        }
        let before = h.backend.writeCalls.count
        #expect(await h.upNext.undoPlan(receipt) == false)
        #expect(h.library.entry(for: key) != nil)
        #expect(h.backend.writeCalls.count == before, "no remove is sent after the change")
        await h.tearDown()
    }

    @Test func undoPlanRefusedForAnotherAccount() async throws {
        let h = try UpNextHarness()
        await h.signIn()
        let receipt = try #require(await h.upNext.plan(upNextItem))
        let other = UpNextPlanReceipt(key: receipt.key, account: AccountContext(userId: "someone-else", generation: 99),
                                      rowId: receipt.rowId, lifecycleId: receipt.lifecycleId,
                                      revision: receipt.revision, created: true)
        let before = h.backend.writeCalls.count
        #expect(await h.upNext.undoPlan(other) == false)
        #expect(h.backend.writeCalls.count == before)
        await h.tearDown()
    }

    @Test func preDispatchSwitchNeverSendsUpNextReadAsB() async throws {
        let defaults = try #require(UserDefaults(suiteName: "kuro.tests.up-next.flags.\(UUID().uuidString)"))
        let h = try SessionSDKHarness(
            responder: StubAuth.signInResponder { request in request.resource == upNextRPC ? .json(upNextRowJSON) : .emptyArray },
            flags: FeatureFlags(userDefaults: defaults, launchArguments: ["--ff-on=collection_up_next_v1"]))
        let sessionB = try await CredentialLeaseTests.signedInAsAKeepingBsSession(h)
        let load = Task.immediate { @MainActor in await h.graph.upNext.load(.anime, force: true) }
        h.storage.replace(with: sessionB)
        let switching = Task.immediate { @MainActor in
            _ = await h.session.applySession(userId: CredentialLeaseTests.userB, email: "b@example.com")
        }
        await load.value
        await switching.value
        let reads = h.server.requests.filter { $0.resource == upNextRPC }
        #expect(!reads.contains { $0.bearerSubject == CredentialLeaseTests.userB.lowercased() }, "sent as B: \(reads)")
        #expect(reads.isEmpty, "A's read was dispatched after its account ended: \(reads)")
        #expect(h.graph.upNext.phase[.anime] != .loaded)
        await h.tearDown()
    }

    @Test func signedOutLoadSendsNothing() async throws {
        let h = try UpNextHarness()
        await h.upNext.load(.anime)
        #expect(h.rpcRequests.isEmpty)
        #expect(await h.upNext.plan(upNextItem) == nil)
        #expect(h.upNext.dismiss(upNextItem) == nil)
        await h.tearDown()
    }
}
