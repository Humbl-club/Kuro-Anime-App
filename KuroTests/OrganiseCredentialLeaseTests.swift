//
//  OrganiseCredentialLeaseTests.swift
//  KuroTests
//
//  W9: every organisation request (tags and custom lists) is a new private request. It runs inside the
//  account's credential lease, so a switch between acceptance and dispatch sends nothing as the next
//  account. Pattern: `CredentialLeaseTests.preDispatchSwitchForEveryFamily`.
//

import Foundation
import KuroCore
import KuroLibrary
import Testing
@testable import Kuro

@MainActor
@Suite("W9: organisation requests carry their own account's credential", .timeLimit(.minutes(1)))
struct OrganiseCredentialLeaseTests {
    static let userA = StubAuth.userA
    static let userB = StubAuth.userB
    static let list = UUID()
    static let items = [UUID(), UUID(), UUID()]

    enum OrganiseFamily: String, CaseIterable, Sendable {
        case tagIndex, listsLoad, organiseDelta, createList, renameList, deleteList, move, rebalance, seed

        func matches(_ request: RecordedRequest) -> Bool {
            switch self {
            case .tagIndex: return request.resource == "rpc/library_tag_index_v1"
            case .listsLoad: return request.resource == "rpc/custom_lists_v1"
            case .organiseDelta: return request.resource == "rpc/apply_title_organisation_delta_v1"
            case .createList: return request.resource == "rpc/create_custom_list_v1"
            case .renameList: return request.resource == "rpc/rename_custom_list_v1"
            case .deleteList: return request.resource == "rpc/delete_custom_list_v1"
            case .move: return request.resource == "rpc/move_custom_list_item_v1"
            case .rebalance: return request.resource == "rpc/rebalance_custom_list_v1"
            case .seed: return request.resource == "rpc/seed_custom_lists_v1"
            }
        }

        /// Starts the call for the signed-in account; true only when it reported success.
        func start(on graph: AppGraph) -> Task<Bool, Never> {
            Task.immediate { @MainActor in
                switch self {
                case .tagIndex:
                    await graph.libraryTags.load(force: true)
                    return graph.libraryTags.loadState == .loaded
                case .listsLoad:
                    await graph.customLists.load(force: true)
                    return graph.customLists.loadState == .loaded
                case .organiseDelta:
                    let delta = TitleOrganisationDelta(key: MediaKey(kind: .anime, id: 1), addTags: ["comfy"], removeTags: [],
                                                       addListIds: [], removeListIds: [])
                    if case .success = await graph.libraryTags.saveOrganisation(delta) { return true }
                    return false
                case .createList:
                    if case .success = await graph.customLists.create(name: "Winter") { return true }
                    return false
                case .renameList:
                    if case .success = await graph.customLists.rename(OrganiseCredentialLeaseTests.list, to: "Spring") { return true }
                    return false
                case .deleteList:
                    if case .success = await graph.customLists.delete(OrganiseCredentialLeaseTests.list) { return true }
                    return false
                case .move:
                    return await graph.customLists.move(in: OrganiseCredentialLeaseTests.list, fromOffsets: [2], toOffset: 1) == .moved
                case .rebalance:
                    return await graph.customLists.move(in: OrganiseCredentialLeaseTests.list, fromOffsets: [2], toOffset: 1) == .moved
                case .seed:
                    if case .success = await graph.customLists.seedFromImport() { return true }
                    return false
                }
            }
        }
    }

    private static func listsJSON(tight: Bool) -> String {
        let positions = tight ? ["1", "1.0000000000000002", "3"] : ["1024", "2048", "3072"]
        let rows = (0..<3).map {
            #"{"item_id":"\#(items[$0].uuidString)","medium":"anime","media_id":\#($0 + 1),"position":\#(positions[$0])}"#
        }.joined(separator: ",")
        return #"[{"id":"\#(list.uuidString)","name":"Winter","created_at":"2026-10-01T10:00:00+00:00","updated_at":"2026-10-01T10:00:00+00:00","revision":1,"items":[\#(rows)]}]"#
    }

    @Test("Pre-dispatch switch, every organisation request family: accepted while A was current, none is dispatched once the SDK holds B's session and the funnel switched to B; none reports success",
          arguments: OrganiseFamily.allCases)
    func preDispatchSwitchSendsNoOrganiseRequestAsB(family: OrganiseFamily) async throws {
        let suite = "kuro.tests.organise-lease.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let flags = FeatureFlags(userDefaults: defaults, launchArguments: ["--ff-on=library_organise_v1"])
        let listed = Self.listsJSON(tight: family == .rebalance)
        let backend = FakeLibraryBackend()
        let meta = LibrarySourceMetadata(customLists: ["Favourites"])
        backend.setRows((1...3).map { FakeLibraryBackend.entry(.anime, $0, sourceMetadata: meta) }, for: Self.userA)
        let h = try SessionSDKHarness(
            responder: StubAuth.signInResponder { request in
                request.resource == "rpc/custom_lists_v1" ? .json(listed) : .json("{}")
            },
            libraryBackend: backend,
            flags: flags
        )
        let sessionB = try await CredentialLeaseTests.signedInAsAKeepingBsSession(h)
        await h.graph.customLists.load(force: true)
        #expect(h.graph.customLists.lists.first?.items.count == 3, "A's list was not loaded")
        let before = h.server.requests.filter(family.matches).count

        let call = family.start(on: h.graph)
        h.storage.replace(with: sessionB)
        let switching = Task.immediate { @MainActor in
            _ = await h.session.applySession(userId: Self.userB, email: "b@example.com")
        }
        let succeeded = await call.value
        await switching.value

        let sent = h.server.requests.filter(family.matches)
        #expect(!sent.contains { $0.bearerSubject == Self.userB.lowercased() }, "\(family) was sent with B's credential: \(sent)")
        #expect(sent.count == before, "\(family) was dispatched after its account ended: \(sent)")
        #expect(!succeeded, "\(family) reported success after its account ended")
        await h.tearDown()
    }
}
