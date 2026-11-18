//
//  LibraryTagsStoreTests.swift
//  KuroTests
//
//  W9: the tag owner behind `library_organise_v1`: whole-library tag filter, delta organise saves,
//  tag rules shared with the database, server error mapping and account safety. HTTP tests run the real
//  supabase-swift client against StubPostgREST (no network).
//

import Foundation
import KuroCore
import KuroLibrary
import Supabase
import Testing
@testable import Kuro

/// Shared by the W9 owner suites: one stub server, one account coordinator, one `FeatureFlags`.
@MainActor
struct OrganiseFixture {
    static let userA = "AAAAAAAA-0000-4000-8000-00000000000A"
    static let userB = "BBBBBBBB-0000-4000-8000-00000000000B"
    static let flagsOnJSON = "[\(flagRow("library_organise_v1", rollout: 100))]"

    let server = StubServer()
    let accountSession = AccountSessionCoordinator()
    let flags: FeatureFlags
    let defaults: UserDefaults
    private let suiteName = "kuro.tests.organise.\(UUID().uuidString)"

    init(flagOn: Bool = true) throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        flags = FeatureFlags(userDefaults: defaults, launchArguments: flagOn ? ["--ff-on=library_organise_v1"] : [])
        _ = accountSession.begin(userId: Self.userA)
    }

    var client: SupabaseClient { StubSupabase.makeClient(server: server) }

    func tags() -> LibraryTagsStore {
        LibraryTagsStore(client: client, accountSession: accountSession, flags: flags)
    }

    func requests(_ resource: String) -> [RecordedRequest] { server.requests.filter { $0.resource == resource } }

    func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        server.shutDown()
    }

    nonisolated static let pgrst202 = StubResponse.json(
        #"{"code":"PGRST202","message":"Could not find the function in the schema cache","details":null,"hint":null}"#, status: 404)

    nonisolated static func error(_ message: String) -> StubResponse {
        .json(#"{"code":"P0001","message":"\#(message)","details":null,"hint":null}"#, status: 400)
    }
}

@MainActor
@Suite("Library tags", .timeLimit(.minutes(1)))
struct LibraryTagsStoreTests {
    private let anime1 = MediaKey(kind: .anime, id: 1)

    @Test("Filter by tag covers the whole library, not only loaded pages")
    func filterByTagShowsOnlyTaggedEntries() async throws {
        let h = try FacadeHarness()
        let rows = (1...2000).map { id -> LibraryEntry in
            var row = FakeLibraryBackend.entry(.anime, id); row.revision = 1; row.lifecycleId = UUID(); return row
        }
        h.backend.setRows(rows, for: FacadeHarness.userA)
        h.server.respond { request in
            guard request.resource == "rpc/library_tag_index_v1" else { return .emptyArray }
            return .json(#"""
            [{"medium":"anime","media_id":5,"tags":["comfy"]},{"medium":"anime","media_id":1950,"tags":["comfy"]},
             {"medium":"anime","media_id":7,"tags":["rewatch"]},{"medium":"anime","media_id":3001,"tags":["Comfy"]}]
            """#)
        }
        await h.signIn()
        let flags = FeatureFlags(userDefaults: h.defaults, launchArguments: ["--ff-on=library_organise_v1"])
        let tags = LibraryTagsStore(client: StubSupabase.makeClient(server: h.server),
                                    accountSession: h.service.accountSession, flags: flags)
        let tracked = Set(h.service.library.allEntries.map(\.key))
        #expect(tracked.count == 2000)

        await tags.load()
        let wanted: Set<MediaKey> = [MediaKey(kind: .anime, id: 5), MediaKey(kind: .anime, id: 1950)]
        #expect(tags.keys(taggedWith: "COMFY", among: tracked) == wanted)
        let collection = h.service.collection
        collection.showTaggedTitles("comfy", keys: tags.keys(taggedWith: "COMFY", among: tracked))
        #expect(collection.importedTitleKeys == wanted)
        #expect(collection.selectionSource == .tag("comfy"))
        #expect(tags.allTags(kind: .anime, tracked: tracked) == ["comfy", "rewatch"])
        collection.clearImportedTitles()
        #expect(collection.selectionSource == nil)
        await h.tearDown()
    }

    @Test("Switch off: load, forced load and save send nothing; the switch is read at call time")
    func flagOffSendsNoRequest() async throws {
        let f = try OrganiseFixture(flagOn: false)
        defer { f.tearDown() }
        let tags = f.tags()
        let delta = TitleOrganisationDelta(key: anime1, addTags: ["comfy"], removeTags: [], addListIds: [], removeListIds: [])
        await tags.load()
        await tags.load(force: true)
        let saved = await tags.saveOrganisation(delta)
        #expect(f.server.requests.isEmpty)
        #expect(tags.loadState == .unavailable)
        #expect(saved == .failure(.unavailable))

        f.server.respond { request in
            request.resource == "feature_flags" ? .json(OrganiseFixture.flagsOnJSON) : .json("[]")
        }
        await f.flags.refresh(client: f.client, userId: nil)
        await tags.load()
        #expect(f.requests("rpc/library_tag_index_v1").count == 1)
        #expect(tags.loadState == .loaded)
    }

    @Test("A save sends only the delta and shows the server's state afterwards")
    func organiseSaveSendsOnlyTheDelta() async throws {
        let f = try OrganiseFixture()
        defer { f.tearDown() }
        let l1 = UUID(), l2 = UUID()
        f.server.respond { request in
            guard request.resource == "rpc/apply_title_organisation_delta_v1" else { return .emptyArray }
            return .json(#"{"tags":["rewatch","slow burn"],"items":[{"list_id":"\#(l2.uuidString)","item_id":"\#(UUID().uuidString)","position":1024}],"lists":[]}"#)
        }
        let tags = f.tags()
        let delta = TitleOrganisationDelta.between(
            key: anime1, originalTags: ["comfy"], editedTags: ["slow burn"], originalListIds: [l1], editedListIds: [])
        #expect(delta.addTags == ["slow burn"] && delta.removeTags == ["comfy"])
        #expect(delta.addListIds.isEmpty && delta.removeListIds == [l1])
        let result = await tags.saveOrganisation(delta)
        guard case .success = result else { Issue.record("save failed: \(result)"); return }
        let sent = try #require(f.requests("rpc/apply_title_organisation_delta_v1").first)
        #expect(sent.canonicalBody == #"{"p_add_list_ids":[],"p_add_tags":["slow burn"],"p_media_id":1,"p_medium":"anime","p_remove_list_ids":["\#(l1.uuidString)"],"p_remove_tags":["comfy"]}"#)
        #expect(tags.tags(for: anime1) == ["rewatch", "slow burn"])

        let same = TitleOrganisationDelta.between(
            key: anime1, originalTags: ["a"], editedTags: ["A"], originalListIds: [l1], editedListIds: [l1])
        #expect(same.isEmpty)
        _ = await tags.saveOrganisation(same)
        #expect(f.requests("rpc/apply_title_organisation_delta_v1").count == 1)
    }

    @Test("Tag rules normalise and count like the database; the server's answer is the truth")
    func normalisesAndCountsLikeTheDatabase() async throws {
        #expect(LibraryTagRules.validate(["Comfy", "comfy", " comfy "]) == .success(["Comfy"]))
        #expect(LibraryTagRules.validate(["cafe\u{301}", "caf\u{E9}"]) == .success(["caf\u{E9}"]))
        #expect(LibraryTagRules.validate(["Émotion", "émotion"]) == .success(["Émotion"]))
        #expect(LibraryTagRules.validate([String(repeating: "😀", count: 24)]) == .success([String(repeating: "😀", count: 24)]))
        #expect(LibraryTagRules.validate([String(repeating: "😀", count: 25)]) == .failure(.tooLong(String(repeating: "😀", count: 25))))
        #expect(LibraryTagRules.length("👩‍👩‍👧") == 5)
        #expect(LibraryTagRules.validate((1...11).map { "t\($0)" }) == .failure(.tooMany))
        #expect(LibraryTagRules.validate(["  "]) == .failure(.empty))
        #expect(TitleOrganisationDelta.between(key: anime1, originalTags: ["Comfy"], editedTags: ["comfy"],
                                               originalListIds: [], editedListIds: []).isEmpty)

        let f = try OrganiseFixture()
        defer { f.tearDown() }
        f.server.respond { _ in .json(#"{"tags":["Server Spelling"],"items":[],"lists":[]}"#) }
        let tags = f.tags()
        _ = await tags.saveOrganisation(TitleOrganisationDelta(key: anime1, addTags: ["client spelling"], removeTags: [],
                                                               addListIds: [], removeListIds: []))
        #expect(tags.tagsByKey[anime1] == ["Server Spelling"])
    }

    @Test("Server codes map to typed errors; a transport failure is offline")
    func saveMapsServerCodes() async throws {
        let f = try OrganiseFixture()
        defer { f.tearDown() }
        let tags = f.tags()
        let delta = TitleOrganisationDelta(key: anime1, addTags: ["x"], removeTags: [], addListIds: [], removeListIds: [])
        for (message, expected) in [("TAG_LIMIT", OrganiseError.tagLimit), ("ENTRY_NOT_FOUND", .notTracked),
                                    ("LIST_FULL", .listFull)] {
            f.server.respond { _ in OrganiseFixture.error(message) }
            #expect(await tags.saveOrganisation(delta) == .failure(expected), "\(message)")
        }
        f.server.respond { _ in .failure(.notConnectedToInternet) }
        #expect(await tags.saveOrganisation(delta) == .failure(.offline))
    }

    @Test("A not-yet-deployed reader is unavailable, not failed")
    func undeployedReaderIsUnavailableNotFailed() async throws {
        let f = try OrganiseFixture()
        defer { f.tearDown() }
        f.server.respond { _ in OrganiseFixture.pgrst202 }
        let tags = f.tags()
        await tags.load()
        #expect(tags.loadState == .unavailable)
        #expect(tags.tagsByKey.isEmpty)
    }

    @Test("Tags clear on account switch; a load that finishes after the switch publishes nothing")
    func tagsClearOnAccountSwitch() async throws {
        let f = try OrganiseFixture()
        defer { f.tearDown() }
        let gate = StubGate()
        f.server.respond { _ in .json(#"[{"medium":"anime","media_id":1,"tags":["mine"]}]"#).held(by: gate) }
        let tags = f.tags()
        let loading = Task { @MainActor in await tags.load() }
        _ = await f.server.waitForRequest { $0.resource == "rpc/library_tag_index_v1" }
        _ = f.accountSession.begin(userId: OrganiseFixture.userB)
        gate.open()
        await loading.value
        #expect(tags.tagsByKey.isEmpty)

        f.server.respond { _ in .json(#"[{"medium":"anime","media_id":1,"tags":["mine"]}]"#) }
        await tags.load(force: true)
        #expect(tags.tagsByKey[anime1] == ["mine"])
        tags.clearPrivateState()
        #expect(tags.tagsByKey.isEmpty && tags.loadState == .notLoaded)
    }
}
