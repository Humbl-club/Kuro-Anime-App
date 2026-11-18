//
//  CustomListsStoreTests.swift
//  KuroTests
//
//  W9: the custom-lists owner: seed from imported names, revision-guarded moves with a retry only on
//  request, Undo, export objects, the switch and account safety. HTTP tests run the real supabase-swift
//  client against StubPostgREST.
//

import Foundation
import KuroCore
import KuroLibrary
import Testing
@testable import Kuro

@MainActor
@Suite("Custom lists", .timeLimit(.minutes(1)))
struct CustomListsStoreTests {
    private static let anime1 = MediaKey(kind: .anime, id: 1)
    private static let anime2 = MediaKey(kind: .anime, id: 2)
    private static let anime3 = MediaKey(kind: .anime, id: 3)
    private static let manga2 = MediaKey(kind: .manga, id: 2)

    struct Item { let id: UUID; let key: MediaKey; let position: String }

    /// One `custom_lists_v1` row as the server returns it.
    static func listJSON(_ id: UUID, _ name: String, revision: Int, created: String = "2026-10-01T10:00:00+00:00",
                         _ items: [Item]) -> String {
        let rows = items.map {
            #"{"item_id":"\#($0.id.uuidString)","medium":"\#($0.key.kind.rawValue)","media_id":\#($0.key.id),"position":\#($0.position)}"#
        }.joined(separator: ",")
        return #"{"id":"\#(id.uuidString)","name":"\#(name)","created_at":"\#(created)","updated_at":"\#(created)","revision":\#(revision),"items":[\#(rows)]}"#
    }

    /// The fixture, a bound Library holding `entries`, and the store under test.
    @MainActor
    struct Rig {
        let f: OrganiseFixture
        let library: LibraryStore
        let store: CustomListsStore

        init(flagOn: Bool = true, entries: [LibraryEntry] = []) async throws {
            f = try OrganiseFixture(flagOn: flagOn)
            let backend = FakeLibraryBackend()
            backend.setRows(entries, for: OrganiseFixture.userA)
            library = LibraryStore(backend: backend)
            if let account = f.accountSession.current {
                library.bind(account)
                try await library.refresh()
            }
            store = CustomListsStore(client: f.client, accountSession: f.accountSession, flags: f.flags)
            store.library = library
        }

        func count(_ resource: String) -> Int { f.requests(resource).count }
    }

    static func tracked(_ keys: MediaKey...) -> [LibraryEntry] { keys.map { FakeLibraryBackend.entry($0.kind, $0.id) } }

    @Test("Imported custom-list names seed Kuro lists in one request")
    func importedCustomListNamesCanSeedLists() async throws {
        let meta1 = LibrarySourceMetadata(customLists: ["Favourites", "To rewatch"])
        let metaManga = LibrarySourceMetadata(customLists: ["favourites"])
        let entries = [
            FakeLibraryBackend.entry(.anime, 1, sourceMetadata: meta1),
            FakeLibraryBackend.entry(.manga, 2, sourceMetadata: metaManga),
            FakeLibraryBackend.entry(.anime, 3),
        ]
        let rig = try await Rig(entries: entries)
        defer { rig.f.tearDown() }
        let fav = UUID(), rewatch = UUID()
        let listed = [
            Self.listJSON(fav, "Favourites", revision: 1, [Item(id: UUID(), key: Self.anime1, position: "1024"), Item(id: UUID(), key: Self.manga2, position: "2048")]),
            Self.listJSON(rewatch, "To rewatch", revision: 1, [Item(id: UUID(), key: Self.anime1, position: "1024")]),
        ].joined(separator: ",")
        rig.f.server.respond { request in
            switch request.resource {
            case "rpc/seed_custom_lists_v1": return .json(#"{"created":["Favourites","To rewatch"],"reused":[],"skipped":[],"added":3}"#)
            case "rpc/custom_lists_v1": return .json("[\(listed)]")
            default: return .emptyArray
            }
        }
        let wanted = rig.store.importedListNames()
        #expect(wanted.map(\.name) == ["Favourites", "To rewatch"])
        #expect(wanted.first?.keys == [Self.anime1, Self.manga2])
        #expect(wanted.last?.keys == [Self.anime1])

        let result = await rig.store.seedFromImport()
        guard case .success(let report) = result else { Issue.record("seed failed: \(result)"); return }
        #expect(report.added == 3 && report.created == ["Favourites", "To rewatch"])
        let sent = rig.f.requests("rpc/seed_custom_lists_v1")
        #expect(sent.count == 1)
        #expect(sent.first?.canonicalBody == #"{"p_lists":[{"items":[{"media_id":1,"medium":"anime"},{"media_id":2,"medium":"manga"}],"name":"Favourites"},{"items":[{"media_id":1,"medium":"anime"}],"name":"To rewatch"}]}"#)
        #expect(rig.store.lists.map(\.name) == ["Favourites", "To rewatch"])
        #expect(rig.store.lists[0].items == [Self.anime1, Self.manga2])
    }

    @Test("Switch off: nothing is sent and nothing is reported")
    func flagOffSendsNoRequest() async throws {
        let rig = try await Rig(flagOn: false, entries: Self.tracked(Self.anime1))
        defer { rig.f.tearDown() }
        await rig.store.load()
        await rig.store.load(force: true)
        let created = await rig.store.create(name: "Winter")
        let moved = await rig.store.move(in: UUID(), fromOffsets: [0], toOffset: 1)
        let seeded = await rig.store.seedFromImport()
        let removal = await rig.store.remove(Self.anime1, from: UUID())
        #expect(rig.f.server.requests.isEmpty)
        #expect(rig.store.loadState == .unavailable)
        #expect(rig.store.exportLists() == nil)
        #expect(created.isFailure(.unavailable))
        #expect(moved == .failed(.unavailable))
        #expect(seeded.isFailure(.unavailable))
        #expect(removal == nil)
    }

    @Test("Once the lists exist nothing is re-seeded; the server's skipped names surface")
    func seedingTwiceCreatesNoDuplicatesAndReportsSkips() async throws {
        let meta = LibrarySourceMetadata(customLists: ["Favourites"])
        let rig = try await Rig(entries: [FakeLibraryBackend.entry(.anime, 1, sourceMetadata: meta)])
        defer { rig.f.tearDown() }
        let fav = UUID()
        let json = Self.listJSON(fav, "Favourites", revision: 1, [Item(id: UUID(), key: Self.anime1, position: "1024")])
        rig.f.server.respond { request in
            request.resource == "rpc/custom_lists_v1" ? .json("[\(json)]") : .emptyArray
        }
        await rig.store.load()
        #expect(rig.store.importedListNames().isEmpty)
        let again = await rig.store.seedFromImport()
        #expect(again == .success(CustomListSeedReport(created: [], reused: [], skipped: [], added: 0)))
        #expect(rig.count("rpc/seed_custom_lists_v1") == 0)

        let extra = LibrarySourceMetadata(customLists: ["Extra"])
        let rig2 = try await Rig(entries: [FakeLibraryBackend.entry(.anime, 1, sourceMetadata: extra)])
        defer { rig2.f.tearDown() }
        rig2.f.server.respond { request in
            switch request.resource {
            case "rpc/seed_custom_lists_v1": return .json(#"{"created":[],"reused":[],"skipped":[{"name":"Extra","reason":"LIST_LIMIT"}],"added":0}"#)
            default: return .emptyArray
            }
        }
        let report = try #require(try? await rig2.store.seedFromImport().get())
        #expect(report.skipped == ["Extra"])
    }

    @Test("A move writes one row; an exhausted gap sends a rebalance of the full order")
    func moveSendsOneRowThenRebalancesWhenExhausted() async throws {
        let rig = try await Rig(entries: Self.tracked(Self.anime1, Self.anime2, Self.anime3))
        defer { rig.f.tearDown() }
        let list = UUID(), a = UUID(), b = UUID(), c = UUID()
        let spaced = Self.listJSON(list, "Winter", revision: 4, [
            Item(id: a, key: Self.anime1, position: "1024"), Item(id: b, key: Self.anime2, position: "2048"),
            Item(id: c, key: Self.anime3, position: "3072")])
        rig.f.server.respond { request in
            switch request.resource {
            case "rpc/custom_lists_v1": return .json("[\(spaced)]")
            case "rpc/move_custom_list_item_v1": return .json(#"{"item_id":"\#(c.uuidString)","position":1536,"revision":5}"#)
            default: return .emptyArray
            }
        }
        await rig.store.load()
        let outcome = await rig.store.move(in: list, fromOffsets: [2], toOffset: 1)
        #expect(outcome == .moved)
        let sent = try #require(rig.f.requests("rpc/move_custom_list_item_v1").first)
        #expect(sent.canonicalBody == #"{"p_after_position":1024,"p_before_position":2048,"p_expected_list_revision":4,"p_item_id":"\#(c.uuidString)","p_list_id":"\#(list.uuidString)"}"#)
        #expect(rig.store.meta[list]?.revision == 5)
        #expect(rig.store.lists.first?.items == [Self.anime1, Self.anime3, Self.anime2])

        let tight = Self.listJSON(list, "Winter", revision: 9, [
            Item(id: a, key: Self.anime1, position: "1"), Item(id: b, key: Self.anime2, position: "1.0000000000000002"),
            Item(id: c, key: Self.anime3, position: "3")])
        rig.f.server.respond { request in
            switch request.resource {
            case "rpc/custom_lists_v1": return .json("[\(tight)]")
            case "rpc/rebalance_custom_list_v1":
                return .json(#"{"revision":10,"items":[{"item_id":"\#(a.uuidString)","position":1024},{"item_id":"\#(c.uuidString)","position":2048},{"item_id":"\#(b.uuidString)","position":3072}]}"#)
            default: return .emptyArray
            }
        }
        await rig.store.load(force: true)
        let second = await rig.store.move(in: list, fromOffsets: [2], toOffset: 1)
        #expect(second == .moved)
        let rebalance = try #require(rig.f.requests("rpc/rebalance_custom_list_v1").first)
        #expect((rebalance.jsonObject?["p_item_ids"] as? [String])?.map { $0.lowercased() } == [a, c, b].map { $0.uuidString.lowercased() })
        #expect((rebalance.jsonObject?["p_expected_list_revision"] as? Int) == 9)
        #expect(rig.store.meta[list]?.revision == 10)
        #expect(rig.f.requests("rpc/move_custom_list_item_v1").count == 1, "the exhausted gap sends no single move")
    }

    @Test("A stale move reloads and tells the person; it is retried only on request, and only once")
    func staleReorderReloadsAndRetriesOnlyOnRequest() async throws {
        let rig = try await Rig(entries: Self.tracked(Self.anime1, Self.anime2, Self.anime3))
        defer { rig.f.tearDown() }
        let list = UUID(), a = UUID(), b = UUID(), c = UUID()
        let before = Self.listJSON(list, "Winter", revision: 4, [
            Item(id: a, key: Self.anime1, position: "1024"), Item(id: b, key: Self.anime2, position: "2048"),
            Item(id: c, key: Self.anime3, position: "3072")])
        let after = Self.listJSON(list, "Winter", revision: 7, [
            Item(id: c, key: Self.anime3, position: "1024"), Item(id: b, key: Self.anime2, position: "2048"),
            Item(id: a, key: Self.anime1, position: "3072")])
        let reloads = CallCounter()
        rig.f.server.respond { request in
            switch request.resource {
            case "rpc/custom_lists_v1": return .json("[\(reloads.next() == 1 ? before : after)]")
            case "rpc/move_custom_list_item_v1": return OrganiseFixture.error("STALE_LIST")
            default: return .emptyArray
            }
        }
        await rig.store.load()
        let outcome = await rig.store.move(in: list, fromOffsets: [2], toOffset: 1)
        guard case .stale(let pending) = outcome else { Issue.record("expected stale: \(outcome)"); return }
        #expect(rig.count("rpc/custom_lists_v1") == 2, "one reload")
        #expect(rig.count("rpc/move_custom_list_item_v1") == 1, "no silent retry")
        #expect(rig.store.lists.first?.items == [Self.anime3, Self.anime2, Self.anime1], "the server's order")
        #expect(pending.afterItemId == a && pending.beforeItemId == b && !pending.isRetry)

        let second = await rig.store.retry(pending)
        #expect(second == .failed(.staleList))
        let moves = rig.f.requests("rpc/move_custom_list_item_v1")
        #expect(moves.count == 2)
        #expect(moves.last?.jsonObject?["p_expected_list_revision"] as? Int == 7, "against the reloaded revision")
        #expect(moves.last?.jsonObject?["p_after_position"] as? Double == 3072)

        // A retry of an account that is no longer current sends nothing.
        _ = rig.f.accountSession.begin(userId: OrganiseFixture.userB)
        let third = await rig.store.retry(pending)
        #expect(third == .failed(.failed))
        #expect(rig.f.requests("rpc/move_custom_list_item_v1").count == 2)
    }

    @Test("Removing the middle title and tapping Undo restores its place")
    func removeAndUndoRestoresPosition() async throws {
        let rig = try await Rig(entries: Self.tracked(Self.anime1, Self.anime2, Self.anime3))
        defer { rig.f.tearDown() }
        let list = UUID(), a = UUID(), b = UUID(), c = UUID(), b2 = UUID()
        let json = Self.listJSON(list, "Winter", revision: 5, [
            Item(id: a, key: Self.anime1, position: "1024"), Item(id: b, key: Self.anime2, position: "2048"),
            Item(id: c, key: Self.anime3, position: "3072")])
        let deltas = CallCounter()
        rig.f.server.respond { request in
            switch request.resource {
            case "rpc/custom_lists_v1": return .json("[\(json)]")
            case "rpc/apply_title_organisation_delta_v1":
                if deltas.next() == 1 {
                    return .json(#"{"tags":[],"items":[],"lists":[{"list_id":"\#(list.uuidString)","revision_before":5,"revision":6}]}"#)
                }
                return .json(#"{"tags":[],"items":[{"list_id":"\#(list.uuidString)","item_id":"\#(b2.uuidString)","position":4096}],"lists":[{"list_id":"\#(list.uuidString)","revision_before":6,"revision":7}]}"#)
            case "rpc/move_custom_list_item_v1": return .json(#"{"item_id":"\#(b2.uuidString)","position":2048,"revision":8}"#)
            default: return .emptyArray
            }
        }
        await rig.store.load()
        let removal = try #require(await rig.store.remove(Self.anime2, from: list))
        #expect(rig.store.lists.first?.items == [Self.anime1, Self.anime3])
        #expect(removal.revisionAfter == 6)
        #expect(await rig.store.undo(removal))
        let deltaRequests = rig.f.requests("rpc/apply_title_organisation_delta_v1")
        #expect((deltaRequests.last?.jsonObject?["p_add_list_ids"] as? [String])?.map { $0.lowercased() } == [list.uuidString.lowercased()])
        #expect((deltaRequests.last?.jsonObject?["p_remove_list_ids"] as? [String]) == [])
        let move = try #require(rig.f.requests("rpc/move_custom_list_item_v1").first)
        #expect(move.jsonObject?["p_after_position"] as? Double == 1024)
        #expect(move.jsonObject?["p_before_position"] as? Double == 3072)
        #expect(move.jsonObject?["p_expected_list_revision"] as? Int == 7)
        #expect(rig.store.lists.first?.items == [Self.anime1, Self.anime2, Self.anime3])

        // Another device changed the list in between: the title returns at the end, no move is sent.
        let rig2 = try await Rig(entries: Self.tracked(Self.anime1, Self.anime2, Self.anime3))
        defer { rig2.f.tearDown() }
        let again = CallCounter()
        rig2.f.server.respond { request in
            switch request.resource {
            case "rpc/custom_lists_v1": return .json("[\(json)]")
            case "rpc/apply_title_organisation_delta_v1":
                if again.next() == 1 {
                    return .json(#"{"tags":[],"items":[],"lists":[{"list_id":"\#(list.uuidString)","revision_before":5,"revision":6}]}"#)
                }
                return .json(#"{"tags":[],"items":[{"list_id":"\#(list.uuidString)","item_id":"\#(b2.uuidString)","position":4096}],"lists":[{"list_id":"\#(list.uuidString)","revision_before":9,"revision":10}]}"#)
            default: return .emptyArray
            }
        }
        await rig2.store.load()
        let removal2 = try #require(await rig2.store.remove(Self.anime2, from: list))
        #expect(await rig2.store.undo(removal2))
        #expect(rig2.count("rpc/move_custom_list_item_v1") == 0)
        #expect(rig2.store.lists.first?.items == [Self.anime1, Self.anime3, Self.anime2])
    }

    @Test("A title no longer in the library can leave a list, with no Undo")
    func orphanRemovalOffersNoUndo() async throws {
        let rig = try await Rig(entries: Self.tracked(Self.anime1))
        defer { rig.f.tearDown() }
        let list = UUID(), orphan = MediaKey(kind: .anime, id: 99)
        let json = Self.listJSON(list, "Winter", revision: 2, [
            Item(id: UUID(), key: Self.anime1, position: "1024"), Item(id: UUID(), key: orphan, position: "2048")])
        rig.f.server.respond { request in
            switch request.resource {
            case "rpc/custom_lists_v1": return .json("[\(json)]")
            case "rpc/apply_title_organisation_delta_v1":
                return .json(#"{"tags":[],"items":[],"lists":[{"list_id":"\#(list.uuidString)","revision_before":2,"revision":3}]}"#)
            default: return .emptyArray
            }
        }
        await rig.store.load()
        let removal = await rig.store.remove(orphan, from: list)
        #expect(removal == nil)
        #expect(rig.count("rpc/apply_title_organisation_delta_v1") == 1)
        #expect(rig.store.lists.first?.items == [Self.anime1])
    }

    @Test("The export objects keep manual order, empty lists and titles no longer in the library")
    func exportListsKeepManualOrderEmptyListsAndRemovedTitles() async throws {
        let rig = try await Rig(entries: Self.tracked(Self.anime1))
        defer { rig.f.tearDown() }
        #expect(rig.store.exportLists() == nil)
        let comfort = UUID(), later = UUID()
        let json = [
            Self.listJSON(comfort, "Comfort", revision: 3, created: "2026-10-01T10:00:00.123456+00:00", [
                Item(id: UUID(), key: Self.anime1, position: "2048"), Item(id: UUID(), key: Self.manga2, position: "1024")]),
            Self.listJSON(later, "Later", revision: 0, created: "2026-10-02T10:00:00+00:00", []),
        ].joined(separator: ",")
        rig.f.server.respond { request in
            request.resource == "rpc/custom_lists_v1" ? .json("[\(json)]") : .emptyArray
        }
        await rig.store.load()
        let exported = try #require(rig.store.exportLists())
        #expect(exported.map(\.id) == [comfort, later])
        #expect(exported.map(\.name) == ["Comfort", "Later"])
        #expect(exported[0].items == [Self.manga2, Self.anime1])
        #expect(exported[1].items.isEmpty)
        let base = ISO8601DateFormatter().date(from: "2026-10-01T10:00:00Z") ?? .distantPast
        #expect(abs(exported[0].createdAt.timeIntervalSince(base) - 0.123456) < 0.001)
        #expect(rig.store.isTracked(Self.anime1))
        #expect(!rig.store.isTracked(Self.manga2), "the list page shows 'No longer in your library'")
    }

    @Test("Work from the previous account never publishes, and its Undo is refused")
    func workFromPreviousAccountNeverPublishes() async throws {
        let rig = try await Rig(entries: Self.tracked(Self.anime1, Self.anime2, Self.anime3))
        defer { rig.f.tearDown() }
        let list = UUID(), a = UUID(), b = UUID(), c = UUID()
        let json = Self.listJSON(list, "Winter", revision: 4, [
            Item(id: a, key: Self.anime1, position: "1024"), Item(id: b, key: Self.anime2, position: "2048"),
            Item(id: c, key: Self.anime3, position: "3072")])
        let gate = StubGate()
        rig.f.server.respond { request in
            switch request.resource {
            case "rpc/custom_lists_v1": return .json("[\(json)]")
            case "rpc/apply_title_organisation_delta_v1":
                return .json(#"{"tags":[],"items":[],"lists":[{"list_id":"\#(list.uuidString)","revision_before":4,"revision":5}]}"#)
            case "rpc/move_custom_list_item_v1":
                return StubResponse.json(#"{"item_id":"\#(c.uuidString)","position":1536,"revision":6}"#).held(by: gate)
            default: return .emptyArray
            }
        }
        await rig.store.load()
        let removal = try #require(await rig.store.remove(Self.anime2, from: list))
        let deltasBefore = rig.count("rpc/apply_title_organisation_delta_v1")

        let moving = Task { @MainActor in await rig.store.move(in: list, fromOffsets: [1], toOffset: 0) }
        _ = await rig.f.server.waitForRequest { $0.resource == "rpc/move_custom_list_item_v1" }
        _ = rig.f.accountSession.begin(userId: OrganiseFixture.userB)
        rig.store.cancelAccountWork()
        rig.store.clearPrivateState()
        gate.open()
        _ = await moving.value
        #expect(rig.store.lists.isEmpty && rig.store.slots.isEmpty && rig.store.meta.isEmpty)
        #expect(await rig.store.undo(removal) == false)
        #expect(rig.count("rpc/apply_title_organisation_delta_v1") == deltasBefore)
    }

    @Test("A seed held across an account switch publishes nothing")
    func seedFromPreviousAccountNeverPublishes() async throws {
        let meta = LibrarySourceMetadata(customLists: ["Favourites"])
        let rig = try await Rig(entries: [FakeLibraryBackend.entry(.anime, 1, sourceMetadata: meta)])
        defer { rig.f.tearDown() }
        let gate = StubGate()
        rig.f.server.respond { request in
            request.resource == "rpc/seed_custom_lists_v1"
                ? StubResponse.json(#"{"created":["Favourites"],"reused":[],"skipped":[],"added":1}"#).held(by: gate)
                : .emptyArray
        }
        let seeding = Task { @MainActor in await rig.store.seedFromImport() }
        _ = await rig.f.server.waitForRequest { $0.resource == "rpc/seed_custom_lists_v1" }
        _ = rig.f.accountSession.begin(userId: OrganiseFixture.userB)
        rig.store.clearPrivateState()
        gate.open()
        let result = await seeding.value
        #expect(result.isFailure(.failed))
        #expect(rig.store.lists.isEmpty)
        #expect(rig.count("rpc/custom_lists_v1") == 0, "no reload for the previous account")
    }

    @Test("Server limits map to typed errors with EN and DE copy; a stale rebalance is stale")
    func listLimitAndNameErrorsMapToCopy() async throws {
        let rig = try await Rig(entries: Self.tracked(Self.anime1, Self.anime2, Self.anime3))
        defer { rig.f.tearDown() }
        rig.f.server.respond { _ in OrganiseFixture.error("LIST_LIMIT") }
        #expect((await rig.store.create(name: "x")).isFailure(.listLimit))
        rig.f.server.respond { _ in OrganiseFixture.error("LIST_NAME_TAKEN") }
        #expect((await rig.store.create(name: "x")).isFailure(.nameTaken))

        let list = UUID()
        let tight = Self.listJSON(list, "Winter", revision: 2, [
            Item(id: UUID(), key: Self.anime1, position: "1"), Item(id: UUID(), key: Self.anime2, position: "1.0000000000000002"),
            Item(id: UUID(), key: Self.anime3, position: "3")])
        rig.f.server.respond { request in
            switch request.resource {
            case "rpc/custom_lists_v1": return .json("[\(tight)]")
            case "rpc/rebalance_custom_list_v1": return OrganiseFixture.error("STALE_LIST")
            default: return .emptyArray
            }
        }
        await rig.store.load()
        let outcome = await rig.store.move(in: list, fromOffsets: [2], toOffset: 1)
        guard case .stale = outcome else { Issue.record("expected stale: \(outcome)"); return }
        for error in [OrganiseError.listLimit, .staleList] {
            let de = OrganiseCopy.error(error, german: true), en = OrganiseCopy.error(error, german: false)
            #expect(!de.isEmpty && de != en)
        }
    }
}

private extension Result where Failure == OrganiseError {
    func isFailure(_ expected: OrganiseError) -> Bool {
        if case .failure(let error) = self { return error == expected }
        return false
    }
}
