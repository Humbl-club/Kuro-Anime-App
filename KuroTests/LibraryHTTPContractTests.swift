//
//  LibraryHTTPContractTests.swift
//  KuroTests
//
//  The list writes `LibraryActions` sends, asserted on the HTTP requests the real supabase-swift
//  client emits (StubPostgREST: in-process, no network). These assertions do not depend on how the
//  facade is implemented, so each defect test was first run against the old writers (red) and then
//  against the Library integration (green).
//

import Testing
import Foundation
import KuroCore
import KuroLibrary
@testable import Kuro

/// A service whose SDK client talks to a `StubServer` with scripted list tables.
@MainActor
struct LibraryHTTPHarness {
    static let user = LifecycleFixtures.userA

    let server: StubServer
    let service: AppGraph
    let defaults: UserDefaults
    let notifications: FakeNotificationCenter
    private let suiteName: String

    init(script: ListTablesScript) throws {
        server = StubServer()
        server.respond(with: script.responder())
        suiteName = "kuro.tests.library-http.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        notifications = FakeNotificationCenter()
        service = AppComposition.testingGraph(
            testingUserDefaults: defaults,
            notificationCenter: notifications,
            client: StubSupabase.makeClient(server: server)
        )
    }

    /// Signs in and loads the scripted lists into the service.
    func signInAndLoadLists() async {
        await service.session.applySession(userId: Self.user, email: "a@example.com")
        await service.libraryActions.fetchUserLists()
    }

    func tearDown() async {
        await service.session.endSession()
        defaults.removePersistentDomain(forName: suiteName)
        server.shutDown()
    }
}

@MainActor
@Suite("Library facade: HTTP contract of list writes", .timeLimit(.minutes(1)))
struct LibraryHTTPContractTests {
    static let user = LibraryHTTPHarness.user

    @Test("W-04: +1 on a rated entry sends a progress-only PATCH (never the 0-100 score as rating)")
    func incrementSendsOnlyProgress() async throws {
        let rated = ListRowJSON.anime(42, rowId: 5, userId: Self.user, progress: 3, rating: 8, notes: "keep")
        let harness = try LibraryHTTPHarness(script: ListTablesScript(anime: [rated]))
        await harness.signInAndLoadLists()

        await harness.service.libraryActions.incrementProgress(mediaId: 42, mediaType: "anime")

        let writes = harness.server.listTableWrites
        #expect(writes.count == 1, "writes: \(writes)")
        let write = try #require(writes.first)
        #expect(write.method == "PATCH")
        #expect(write.resource == "anime_user_lists")
        #expect(write.query("user_id") == "eq.\(Self.user.lowercased())")
        #expect(write.query("anime_id") == "eq.42")
        #expect(write.canonicalBody == #"{"progress":4}"#)
        #expect(harness.service.library.entry(for: MediaKey(kind: .anime, id: 42))?.progress == 4)
        #expect(harness.service.library.entry(for: MediaKey(kind: .anime, id: 42))?.rating?.score100 == 80)
        await harness.tearDown()
    }

    @Test("W-07: favouriting writes rating 10; un-favouriting clears the rating with an explicit null")
    func favoriteWritesDatabaseScale() async throws {
        let plain = ListRowJSON.anime(42, rowId: 5, userId: Self.user, progress: 1)
        let favourite = ListRowJSON.anime(43, rowId: 6, userId: Self.user, progress: 1, rating: 9)
        let harness = try LibraryHTTPHarness(script: ListTablesScript(anime: [plain, favourite]))
        await harness.signInAndLoadLists()
        #expect(!harness.service.library.isFavorited(MediaKey(kind: .anime, id: 42)))
        #expect(harness.service.library.isFavorited(MediaKey(kind: .anime, id: 43)))

        // E8-C2: `toggleFavorite` is deleted (no live caller); a heart is the rating edit through `LibraryActions.apply`.
        let ten = try #require(UserRating(value: 10))
        _ = await harness.service.libraryActions.apply(LibraryEdit(rating: .set(ten)), to: MediaKey(kind: .anime, id: 42), createIfMissing: nil)
        let favourited = await harness.server.waitForRequest { $0.isListTableWrite && $0.query("anime_id") == "eq.42" }
        #expect(favourited.method == "PATCH")
        #expect(favourited.canonicalBody == #"{"rating":10}"#)

        _ = await harness.service.libraryActions.apply(LibraryEdit(rating: .clear), to: MediaKey(kind: .anime, id: 43), createIfMissing: nil)
        let cleared = await harness.server.waitForRequest { $0.isListTableWrite && $0.query("anime_id") == "eq.43" }
        #expect(cleared.method == "PATCH")
        #expect(cleared.canonicalBody == #"{"rating":null}"#)
        await harness.tearDown()
    }

    @Test("W-10: a rating outside the database scale 1...10 never leaves the client")
    func outOfRangeRatingIsRejectedLocally() async throws {
        let user = Self.user
        // The insert of the new row answers with the created row (the PATCH before it matches nothing).
        let harness = try LibraryHTTPHarness(script: ListTablesScript(writeReply: { request in
            request.method == "POST"
                ? ListRowJSON.response([ListRowJSON.anime(42, rowId: 5, userId: user, listType: "COMPLETED", progress: 12)])
                : .emptyArray
        }))
        await harness.signInAndLoadLists()

        // A legacy 0-100 score (8 -> 80), as AddToListSheet passed before E3-V moved it to `UserRating`.
        // E8: the Int-rating writer (`upsertUserListEntry`, which failed without a request) is gone; the
        // writers take a `UserRating`, which 80 is not, and the editor's save (its draft through
        // `LibraryActions.apply`) sends no rating for it.
        #expect(UserRating(value: 80) == nil)
        var draft = TrackingDraft(entry: nil)
        draft.status = .completed
        draft.progress = 12
        draft.score = 80
        let saved = await harness.service.libraryActions.apply(
            draft.edit(maxProgress: 12), to: MediaKey(kind: .anime, id: 42), createIfMissing: draft.createIfMissing
        )

        #expect(saved.error == nil)
        let writes = harness.server.listTableWrites
        #expect(!writes.isEmpty)
        #expect(writes.allSatisfy { !($0.canonicalBody ?? "").contains("rating") }, "writes: \(writes)")
        #expect(harness.service.library.entry(for: MediaKey(kind: .anime, id: 42))?.rating == nil)
        await harness.tearDown()
    }

    @Test("W-02/W-13: adding an already tracked title never resets its status or progress")
    func addToListKeepsExistingEntry() async throws {
        let completed = ListRowJSON.anime(42, rowId: 5, userId: Self.user, listType: "COMPLETED", progress: 12, rating: 9)
        let harness = try LibraryHTTPHarness(script: ListTablesScript(anime: [completed]))
        await harness.signInAndLoadLists()

        let added = await harness.service.libraryActions.save(MediaKey(kind: .anime, id: 42), status: .planning)

        #expect(added.error == nil)
        let writes = harness.server.listTableWrites
        #expect(!writes.isEmpty)
        for write in writes {
            #expect(write.method == "POST", "an add must not PATCH an existing row: \(write)")
            #expect(write.preferences.contains("resolution=ignore-duplicates"), "an add must not merge: \(write)")
            #expect(!write.preferences.contains("resolution=merge-duplicates"), "an add must not merge: \(write)")
            #expect(write.query("on_conflict") == "user_id,anime_id")
        }
        let entry = harness.service.library.entry(for: MediaKey(kind: .anime, id: 42))
        #expect(entry?.status == .completed)
        #expect(entry?.progress == 12)
        await harness.tearDown()
    }

    @Test("W-06: clearing a verdict sends an explicit null instead of an empty PATCH")
    func clearingVerdictSendsNull() async throws {
        let judged = ListRowJSON.anime(42, rowId: 5, userId: Self.user, listType: "COMPLETED", progress: 12, verdict: "MASTERPIECE")
        let harness = try LibraryHTTPHarness(script: ListTablesScript(anime: [judged]))
        await harness.signInAndLoadLists()

        _ = await harness.service.libraryActions.apply(LibraryEdit(verdict: .clear), to: MediaKey(kind: .anime, id: 42), createIfMissing: nil)

        let writes = harness.server.listTableWrites
        #expect(writes.count == 1, "writes: \(writes)")
        #expect(writes.first?.method == "PATCH")
        #expect(writes.first?.canonicalBody == #"{"verdict":null}"#)
        #expect(harness.service.library.entry(for: MediaKey(kind: .anime, id: 42))?.verdict == nil)
        await harness.tearDown()
    }

    @Test("Request regression: cold start, concurrent view refreshes and a post-apply refresh read each list table once per refresh")
    func listReadsAreCoalesced() async throws {
        let script = ListTablesScript(anime: [ListRowJSON.anime(42, rowId: 5, userId: Self.user)])
        let harness = try LibraryHTTPHarness(script: script)
        let lists = script.responder()
        harness.server.respond { request in
            request.path == "/functions/v1/concierge-apply" ? .json(#"{"success":true,"sessionId":"s1"}"#) : lists(request)
        }
        let service = harness.service
        func listReads() -> [RecordedRequest] {
            harness.server.requests.filter {
                $0.method == "GET" && ($0.resource == "anime_user_lists" || $0.resource == "manga_user_lists")
            }
        }

        // Cold start: the session funnel's refresh, joined by two views asking at the same time.
        await service.session.applySession(userId: Self.user, email: "a@example.com")
        let viewA = Task { await service.libraryActions.fetchUserLists() }
        let viewB = Task { await service.libraryActions.fetchUserLists() }
        await viewA.value
        await viewB.value
        await service.libraryActions.libraryRefreshTask?.value
        #expect(listReads().map(\.resource) == ["anime_user_lists", "manga_user_lists"])
        #expect(service.library.isTracked(MediaKey(kind: .anime, id: 42)))

        // After a server-side write: one fresh refresh, which a view refresh right after joins.
        _ = try await service.imports.conciergeApply(items: [["mediaType": "ANIME", "mediaId": 42]])
        await service.libraryActions.fetchUserLists()
        await service.libraryActions.libraryRefreshTask?.value
        #expect(listReads().count == 4)
        await harness.tearDown()
    }

    @Test("F16: the session's upper-case UUID (with hex letters) leaves the client only as the canonical lower-case TEXT user_id: list reads filter it and a new row's body carries it")
    func userIdIsSentAsCanonicalLowerCase() async throws {
        let lower = Self.user.lowercased()
        #expect(lower != Self.user, "the fixture id must contain hex letters")
        var script = ListTablesScript()
        script.writeReply = { request in
            guard request.method == "POST" else { return .emptyArray }
            return ListRowJSON.response([ListRowJSON.anime(77, rowId: 11, userId: lower, listType: "PLANNING")])
        }
        let harness = try LibraryHTTPHarness(script: script)
        await harness.signInAndLoadLists()

        let added = await harness.service.libraryActions.save(MediaKey(kind: .anime, id: 77), status: .planning)

        #expect(added.error == nil)
        let reads = harness.server.requests.filter {
            $0.method == "GET" && ($0.resource == "anime_user_lists" || $0.resource == "manga_user_lists")
        }
        #expect(!reads.isEmpty)
        #expect(reads.allSatisfy { $0.query("user_id") == "eq.\(lower)" }, "\(reads)")
        let insert = try #require(harness.server.listTableWrites.first { $0.method == "POST" })
        #expect(insert.jsonObject?["user_id"] as? String == lower)
        #expect(!harness.server.requests.contains { $0.description.contains(Self.user) },
                "the upper-case id left the client: \(harness.server.requests)")
        await harness.tearDown()
    }

    @Test("anime 7 and manga 7 stay distinct: removing manga 7 deletes only the manga row")
    func equalIdsStayDistinct() async throws {
        let harness = try LibraryHTTPHarness(script: ListTablesScript(
            anime: [ListRowJSON.anime(7, rowId: 3, userId: Self.user, progress: 2)],
            manga: [ListRowJSON.manga(7, rowId: 3, userId: Self.user, progress: 9)]
        ))
        await harness.signInAndLoadLists()
        #expect(harness.service.library.entry(for: MediaKey(kind: .anime, id: 7))?.progress == 2)
        #expect(harness.service.library.entry(for: MediaKey(kind: .manga, id: 7))?.progress == 9)

        let removed = await harness.service.libraryActions.removeFromList(mediaId: 7, mediaType: "manga")

        #expect(removed)
        let writes = harness.server.listTableWrites
        #expect(writes.count == 1, "writes: \(writes)")
        #expect(writes.first?.method == "DELETE")
        #expect(writes.first?.resource == "manga_user_lists")
        #expect(writes.first?.query("manga_id") == "eq.7")
        #expect(writes.first?.query("user_id") == "eq.\(Self.user.lowercased())")
        #expect(harness.service.library.isTracked(MediaKey(kind: .anime, id: 7)))
        await harness.tearDown()
    }
}
