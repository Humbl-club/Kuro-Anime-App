//
//  LibraryExportFlowTests.swift
//  KuroTests
//
//  W2 (list export), app side: the batched catalogue identity read on `CatalogStore` and the account-scoped
//  `LibraryExportService` (flag first, loaded Library only, leased identity lookup, protected files, cleanup).
//  The HTTP tests run the real supabase-swift client against StubPostgREST (in-process, no network).
//

import Foundation
import KuroCore
import KuroLibrary
import Synchronization
import Testing
@testable import Kuro

@MainActor
@Suite("Library export: catalogue identity read and owner", .timeLimit(.minutes(1)))
struct LibraryExportFlowTests {
    // MARK: - Helpers

    /// The ids of an `id=in.(1,2,3)` filter.
    nonisolated static func inList(_ request: RecordedRequest) -> [Int] {
        guard let value = request.query("id"), value.hasPrefix("in.(") else { return [] }
        return value.dropFirst("in.(".count).dropLast().split(separator: ",").compactMap { Int($0) }
    }

    nonisolated static func inListCount(_ request: RecordedRequest) -> Int {
        inList(request).count
    }

    /// One catalogue row as PostgREST returns it.
    nonisolated static func identityRow(
        id: Int, malId: Int?, anilistId: Int?, english: String? = nil, romaji: String? = nil, native: String? = nil
    ) -> [String: Any] {
        [
            "id": id, "mal_id": malId as Any? ?? NSNull(), "anilist_id": anilistId as Any? ?? NSNull(),
            "title_english": english as Any? ?? NSNull(), "title_romaji": romaji as Any? ?? NSNull(),
            "title_native": native as Any? ?? NSNull(),
        ]
    }

    /// Answers every `id=in.(…)` read with one row per requested id: `mal_id = id + 10_000`.
    nonisolated static func identityRows(for request: RecordedRequest) -> StubResponse {
        guard request.resource == "anime" || request.resource == "manga" else { return .emptyArray }
        let rows = inList(request).map {
            identityRow(id: $0, malId: $0 + 10_000, anilistId: $0 + 20_000, english: "Title \($0)")
        }
        return ListRowJSON.response(rows)
    }

    // MARK: - Tests

    @Test("The lookup sends at most 500 ids per GET, per medium, and never filters adult titles")
    func identityLookupBatchesAtMostFiveHundredIds() async throws {
        let harness = try PublicDataHarness { request in Self.identityRows(for: request) }
        let keys = Set((1...1_200).map { MediaKey(kind: .anime, id: $0) } + (1...300).map { MediaKey(kind: .manga, id: $0) })
        let rows = await harness.service.catalog.exportIdentities(for: keys)
        let requests = harness.server.requests.filter { $0.resource == "anime" || $0.resource == "manga" }
        #expect(requests.count == 4)   // 500 + 500 + 200 anime, 300 manga
        #expect(requests.allSatisfy { Self.inListCount($0) <= 500 && $0.method == "GET" })
        #expect(requests.allSatisfy { $0.query("is_adult") == nil })
        #expect(requests.allSatisfy { $0.query("select") == "id,anilist_id,mal_id,title_english,title_romaji,title_native" })
        #expect(requests.filter { $0.resource == "anime" }.map(Self.inListCount) == [500, 500, 200])
        #expect(requests.filter { $0.resource == "manga" }.map(Self.inListCount) == [300])
        #expect(rows.count == 1_500)
        #expect(rows[MediaKey(kind: .anime, id: 7)]?.malId == 10_007)
        #expect(rows[MediaKey(kind: .anime, id: 7)]?.anilistId == 20_007)
        #expect(rows[MediaKey(kind: .anime, id: 7)]?.title == "Title 7")
        #expect(rows[MediaKey(kind: .manga, id: 7)]?.malId == 10_007, "manga 7 is its own title, not anime 7")
        await harness.tearDown()
    }

    @Test("A cancelled caller sends no further batch")
    func identityLookupStopsBetweenBatchesWhenCancelled() async throws {
        let gate = StubGate()
        let harness = try PublicDataHarness { request in
            Self.identityRows(for: request).held(by: gate)
        }
        let catalog = harness.service.catalog
        let keys = Set((1...1_500).map { MediaKey(kind: .anime, id: $0) })
        let lookup = Task { await catalog.exportIdentities(for: keys) }
        _ = await harness.server.waitForRequest { $0.resource == "anime" }
        lookup.cancel()
        gate.open()
        let rows = await lookup.value
        let animeRequests = harness.server.requests.filter { $0.resource == "anime" }
        #expect(animeRequests.count == 1, "the first batch was in flight; the second must never be sent")
        #expect(rows.count <= Self.inListCount(animeRequests[0]), "at most the first batch's rows")
        await harness.tearDown()
    }

    @Test("A failed batch leaves only its own keys absent; titles fall back English, romaji, native; blanks are nil")
    func identityLookupSkipsFailedBatchesAndPicksTitles() async throws {
        let harness = try PublicDataHarness { request in
            guard request.resource == "anime" else { return .emptyArray }
            // A 400 (not a transport failure: the SDK retries those) for the batch that starts at id 1.
            if Self.inList(request).first == 1 {
                return .json(#"{"code":"PGRST100","message":"rejected","details":null,"hint":null}"#, status: 400)
            }
            return ListRowJSON.response([
                Self.identityRow(id: 501, malId: nil, anilistId: 9, english: "  ", romaji: " Romaji Name ", native: "Native"),
                Self.identityRow(id: 502, malId: 5, anilistId: nil, native: "  Native Only "),
                Self.identityRow(id: 503, malId: 6, anilistId: 7, english: "", romaji: " "),
            ])
        }
        let keys = Set((1...600).map { MediaKey(kind: .anime, id: $0) })
        let rows = await harness.service.catalog.exportIdentities(for: keys)
        #expect(harness.server.requests.filter { $0.resource == "anime" }.count == 2, "the failed first batch does not stop the second")
        #expect(rows.count == 3, "the 500 keys of the failed batch are absent")
        #expect(rows[MediaKey(kind: .anime, id: 100)] == nil)
        #expect(rows[MediaKey(kind: .anime, id: 501)] == ExportCatalogueRow(title: "Romaji Name", anilistId: 9, malId: nil))
        #expect(rows[MediaKey(kind: .anime, id: 502)] == ExportCatalogueRow(title: "Native Only", anilistId: nil, malId: 5))
        #expect(rows[MediaKey(kind: .anime, id: 503)] == ExportCatalogueRow(title: nil, anilistId: 7, malId: 6))
        await harness.tearDown()
    }

    @Test("A transport failure stops the remaining batches; a rejected batch does not")
    func identityLookupStopsAfterTheFirstTransportFailure() async throws {
        let harness = try PublicDataHarness { request in
            request.resource == "anime" ? .failure(.notConnectedToInternet) : .emptyArray
        }
        let keys = Set((1...1_200).map { MediaKey(kind: .anime, id: $0) } + (1...10).map { MediaKey(kind: .manga, id: $0) })
        let rows = await harness.service.catalog.exportIdentities(for: keys)
        #expect(rows.isEmpty)
        // The SDK may resend the same GET (its own retries); what matters is that no later batch was sent.
        let batches = Set(harness.server.requests.filter { $0.resource == "anime" }.map(Self.inList))
        #expect(batches.count == 1, "only the first batch's ids were ever requested: \(batches.map(\.count))")
        #expect(harness.server.requests.filter { $0.resource == "manga" }.isEmpty, "manga was not tried after anime failed in transport")
        await harness.tearDown()
    }

    @Test("An empty key set sends no request")
    func identityLookupOfNothingSendsNothing() async throws {
        let harness = try PublicDataHarness { request in Self.identityRows(for: request) }
        let rows = await harness.service.catalog.exportIdentities(for: [])
        #expect(rows.isEmpty)
        #expect(harness.server.requests.isEmpty)
        await harness.tearDown()
    }
}

// MARK: - Owner and flow tests (Task 5)

/// What the identity read answers: every requested id (default), only some, a transport failure, or held.
final class ExportIdentityScript: Sendable {
    private struct State {
        var only: Set<Int>?
        var failure: URLError.Code?
        var gate: StubGate?
    }

    private let state = Mutex(State())

    func answer(only ids: Set<Int>?) { state.withLock { $0.only = ids } }
    func fail(with code: URLError.Code?) { state.withLock { $0.failure = code } }
    func hold(by gate: StubGate?) { state.withLock { $0.gate = gate } }

    func response(for request: RecordedRequest) -> StubResponse {
        guard request.resource == "anime" || request.resource == "manga" else { return .emptyArray }
        let snapshot = state.withLock { $0 }
        if let failure = snapshot.failure { return .failure(failure) }
        let ids = LibraryExportFlowTests.inList(request).filter { snapshot.only?.contains($0) ?? true }
        let rows = ids.map {
            LibraryExportFlowTests.identityRow(id: $0, malId: $0 + 10_000, anilistId: $0 + 20_000, english: "Title \($0)")
        }
        let answer = ListRowJSON.response(rows)
        return snapshot.gate.map(answer.held(by:)) ?? answer
    }
}

/// Writes for real (so the files exist) and records what the owner asked for.
final class ExportWriteProbe: Sendable {
    private struct State {
        var options: [Data.WritingOptions] = []
        var failWrites = false
    }

    private let state = Mutex(State())

    var lastOptions: Data.WritingOptions { state.withLock { $0.options.last ?? [] } }
    var writeCount: Int { state.withLock { $0.options.count } }
    func failWrites() { state.withLock { $0.failWrites = true } }

    func write(_ data: Data, _ url: URL, _ options: Data.WritingOptions) throws {
        let fails = state.withLock { state -> Bool in
            state.options.append(options)
            return state.failWrites
        }
        if fails { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: url, options: options)
    }
}

/// What the fixture's organisation providers and connectivity answer.
@MainActor
final class ExportProbe {
    var online = true
    var organisationAvailable = true
    var lists: [ExportCustomList] = []
    private(set) var organisationCalls = 0

    func tags() -> [MediaKey: [String]]? {
        organisationCalls += 1
        return organisationAvailable ? [:] : nil
    }

    func customLists() -> [ExportCustomList]? {
        organisationCalls += 1
        return organisationAvailable ? lists : nil
    }
}

/// The export `build` seam with a gate: the FIRST call blocks (on a background thread, where the owner's detached
/// build runs) until `open()`; later calls build at once. Lets a test hold one run inside its detached work while
/// another run starts, finishes, or the account ends.
final class BuildBlocker: Sendable {
    private struct State {
        var calls = 0
        var entered = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let release = DispatchSemaphore(value: 0)
    private let state = Mutex(State())

    var buildCalls: Int { state.withLock { $0.calls } }

    /// Suspends until the first build call is blocked inside the seam.
    func waitUntilBlocked() async {
        await withCheckedContinuation { continuation in
            let alreadyBlocked = state.withLock { state -> Bool in
                if state.entered { return true }
                state.waiters.append(continuation)
                return false
            }
            if alreadyBlocked { continuation.resume() }
        }
    }

    /// Lets the blocked build go on.
    func open() { release.signal() }

    func build(_ input: LibraryExportInput, _ formats: Set<LibraryExportFormat>, _ exportedAt: Date, _ zone: TimeZone) -> LibraryExportBundle {
        let (isFirst, waiters) = state.withLock { state -> (Bool, [CheckedContinuation<Void, Never>]) in
            state.calls += 1
            guard state.calls == 1 else { return (false, []) }
            state.entered = true
            defer { state.waiters = [] }
            return (true, state.waiters)
        }
        if isFirst {
            for waiter in waiters { waiter.resume() }
            release.wait()
        }
        return LibraryExport.build(input, formats: formats, exportedAt: exportedAt, timeZone: zone)
    }
}

/// A signed-in account with `titles` anime in its library, over the real SDK client (StubPostgREST) and
/// the production graph builder.
@MainActor
struct ExportFixture {
    let harness: SessionSDKHarness
    let backend: FakeLibraryBackend
    let keys: [MediaKey]
    let directory: URL
    let writer = ExportWriteProbe()
    let script = ExportIdentityScript()
    let probe = ExportProbe()
    private let flagsDefaults: UserDefaults
    private let flagsSuite: String

    var graph: AppGraph { harness.graph }
    var server: StubServer { harness.server }
    var service: LibraryExportService { harness.graph.libraryExport }

    init(
        titles: Int,
        now: Date,
        exportEnabled: Bool = true,
        fenceOn: Bool = false,
        build: (@Sendable (LibraryExportInput, Set<LibraryExportFormat>, Date, TimeZone) -> LibraryExportBundle)? = nil
    ) throws {
        keys = (0..<titles).map { MediaKey(kind: .anime, id: $0 + 1) }
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kuro-export-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        backend = FakeLibraryBackend()
        backend.setRows(keys.map { FakeLibraryBackend.entry(.anime, $0.id, rowId: $0.id, status: .current, progress: 3, rating: 8) },
                        for: StubAuth.userA)
        flagsSuite = "kuro.tests.export-flags.\(UUID().uuidString)"
        flagsDefaults = try #require(UserDefaults(suiteName: flagsSuite))
        var arguments: [String] = []
        if exportEnabled { arguments.append("--ff-on=library_export_v1") }
        if fenceOn { arguments.append("--ff-on=series_foundation_v1") }
        let flags = FeatureFlags(userDefaults: flagsDefaults, launchArguments: arguments)

        let script = script
        let probe = probe
        let writer = writer
        var seams = LibraryExportSeams()
        seams.isOnline = { probe.online }
        seams.directory = directory
        seams.now = { now }
        seams.timeZone = { TimeZone(identifier: "Europe/Berlin") ?? .gmt }
        seams.tagsByKey = { probe.tags() }
        seams.customLists = { probe.customLists() }
        seams.write = { try writer.write($0, $1, $2) }
        if let build { seams.build = build }
        harness = try SessionSDKHarness(
            responder: StubAuth.signInResponder { script.response(for: $0) },
            libraryBackend: backend, flags: flags, exportSeams: seams
        )
    }

    func signInAndLoad() async throws {
        try await harness.signIn()
        #expect(graph.library.loadState == .loaded)
    }

    /// The lookup reads (`anime` / `manga` by `id=in.(…)`) the server received.
    var identityRequests: [RecordedRequest] {
        server.requests.filter { ($0.resource == "anime" || $0.resource == "manga") && $0.query("id")?.hasPrefix("in.(") == true }
    }

    /// The ids every lookup asked for.
    var requestedIds: Set<Int> {
        Set(identityRequests.flatMap(LibraryExportFlowTests.inList))
    }

    /// Files anywhere under this fixture's export directory (empty when the directory is gone).
    var filesOnDisk: [URL] { Self.files(under: directory) }

    /// Regular files anywhere under `directory`; empty when it does not exist (the owner deletes the whole
    /// directory on every account transition, so a missing directory means "no files").
    static func files(under directory: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }

    func tearDown() async {
        await harness.tearDown()
        flagsDefaults.removePersistentDomain(forName: flagsSuite)
        try? FileManager.default.removeItem(at: directory)
    }
}

extension LibraryExportFlowTests {
    /// 12:00 in Berlin on 9 November 2026.
    static let nov9Noon: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12)) ?? Date(timeIntervalSince1970: 1_794_222_000)
    }()

    /// CSV records in `url` (every record ends with CRLF; no fixture note holds a line break).
    static func csvLineCount(_ url: URL) throws -> Int {
        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        return text.components(separatedBy: "\r\n").count - 1
    }

    static func jsonObject(_ url: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    @Test("A signed-in account's CSV export is written with complete file protection and named for the day")
    func exportSheetSharesFilesForSignedInAccount() async throws {
        let fixture = try ExportFixture(titles: 25, now: Self.nov9Noon)
        try await fixture.signInAndLoad()
        await fixture.service.export(.csv)
        guard case .ready(let result) = fixture.service.state else { Issue.record("not ready: \(fixture.service.state)"); return }
        #expect(result.format == .csv)
        #expect(result.files.map(\.lastPathComponent) == ["kuro-list-2026-11-09.csv"])
        #expect(try Self.csvLineCount(result.files[0]) == 26)
        #expect(fixture.writer.lastOptions.contains(.completeFileProtection))   // the real protection class is a device check
        #expect(result.summary.entryCount == 25 && result.summary.identityUnavailable.isEmpty)
        // One request per medium batch, anime only, every id once.
        #expect(fixture.identityRequests.count == 1)
        #expect(fixture.requestedIds == Set(fixture.keys.map(\.id)))
        #expect(fixture.identityRequests.allSatisfy { $0.bearerSubject == StubAuth.userA.lowercased() })
        await fixture.tearDown()
    }

    @Test("Offline, the export is decided before any lookup: cached identities are used, the rest is reported as unavailable, tags and lists as unavailable")
    func exportWorksOfflineWithCachedCatalogueOrReportsMissingIds() async throws {
        let fixture = try ExportFixture(titles: 10, now: Self.nov9Noon)
        try await fixture.signInAndLoad()
        let online = Set(fixture.keys.prefix(6).map(\.id))
        fixture.script.answer(only: online)                                   // online: 6 rows found, 4 absent
        await fixture.service.export(.json)                                   // fills the owner's cache with 6
        #expect(Set(fixture.service.identityCache.keys.map(\.id)) == online)
        guard case .ready(let first) = fixture.service.state else { Issue.record("not ready"); return }
        #expect(first.summary.identityUnavailable.count == 4, "a key the lookup did not return is unavailable, never 'no MAL id'")
        #expect(first.summary.withoutMalId.isEmpty)

        fixture.probe.online = false                                          // now offline
        fixture.probe.organisationAvailable = false
        let before = fixture.server.requests.count
        await fixture.service.export(.csv)
        guard case .ready(let result) = fixture.service.state else { Issue.record("not ready"); return }
        #expect(fixture.server.requests.count == before, "offline: no lookup batch was sent, so none walked through the SDK's retries")
        #expect(try Self.csvLineCount(result.files[0]) == 11)                 // header + all 10
        #expect(result.summary.identityUnavailable.count == 4)
        #expect(Set(result.summary.identityUnavailable.map(\.key)) == Set(fixture.keys.suffix(4)))
        #expect(result.summary.organisationUnavailable)                       // never silent
        await fixture.tearDown()
    }

    @Test("Only keys the cache lacks are requested")
    func onlyUncachedKeysAreRequested() async throws {
        let fixture = try ExportFixture(titles: 10, now: Self.nov9Noon)
        try await fixture.signInAndLoad()
        fixture.script.answer(only: Set(fixture.keys.prefix(6).map(\.id)))
        await fixture.service.export(.csv)
        fixture.script.answer(only: nil)
        let seen = fixture.identityRequests.count
        await fixture.service.export(.csv)
        let second = Array(fixture.identityRequests.dropFirst(seen))
        #expect(second.count == 1)
        #expect(Set(second.flatMap(Self.inList)) == Set(fixture.keys.suffix(4).map(\.id)))
        guard case .ready(let result) = fixture.service.state else { Issue.record("not ready"); return }
        #expect(result.summary.identityUnavailable.isEmpty)
        // Everything is cached now: a third export sends nothing.
        let total = fixture.identityRequests.count
        await fixture.service.export(.csv)
        #expect(fixture.identityRequests.count == total)
        await fixture.tearDown()
    }

    @Test("A transport failure while online stops the lookup after its first batch and reports every id as unavailable")
    func transportFailureStopsTheLookup() async throws {
        let fixture = try ExportFixture(titles: 600, now: Self.nov9Noon)
        try await fixture.signInAndLoad()
        fixture.script.fail(with: .notConnectedToInternet)
        await fixture.service.export(.csv)
        guard case .ready(let result) = fixture.service.state else { Issue.record("not ready"); return }
        let batches = Set(fixture.identityRequests.map(Self.inList))
        #expect(batches.count == 1, "only the first batch was ever requested")
        #expect(result.summary.identityUnavailable.count == 600)
        #expect(fixture.service.identityCache.isEmpty)
        await fixture.tearDown()
    }

    @Test("The export is refused until the Library holds the account's rows")
    func exportRefusesUntilLibraryLoaded() async throws {
        let source = ControlledResponses<[LibraryEntry]>()
        let backend = FakeLibraryBackend(fetchSource: source)
        let script = ExportIdentityScript()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kuro-export-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "kuro.tests.export-flags.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        var seams = LibraryExportSeams()
        seams.directory = directory
        let h = try SessionSDKHarness(
            responder: StubAuth.signInResponder { script.response(for: $0) }, libraryBackend: backend,
            flags: FeatureFlags(userDefaults: defaults, launchArguments: ["--ff-on=library_export_v1"]), exportSeams: seams
        )
        try await h.session.signInWithEmail(email: "a@example.com", password: "pw")
        // The Library's first fetch is held open: signed in, but nothing loaded.
        #expect(await source.waitForRequest(StubAuth.userA))
        #expect(h.graph.library.loadState != .loaded)
        await h.graph.libraryExport.export(.json)
        #expect(h.graph.libraryExport.state == .failed(.notLoaded))
        #expect(ExportFixture.files(under: directory).isEmpty)
        #expect(h.server.requests.filter { $0.resource == "anime" || $0.resource == "manga" }.isEmpty)
        source.complete(StubAuth.userA, with: .success([]))
        await h.tearDown()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("Signed out, the export fails as signed out and sends nothing")
    func exportSignedOutFails() async throws {
        let fixture = try ExportFixture(titles: 3, now: Self.nov9Noon)
        await fixture.service.export(.csv)
        #expect(fixture.service.state == .failed(.signedOut))
        #expect(fixture.identityRequests.isEmpty)
        await fixture.tearDown()
    }

    @Test("An account switch during the identity lookup publishes nothing, deletes the files, caches nothing and never sends the old library with the new credential")
    func accountSwitchMidExportPublishesNothingAndDeletesFiles() async throws {
        let fixture = try ExportFixture(titles: 5, now: Self.nov9Noon)
        try await fixture.signInAndLoad()
        let gate = StubGate()
        fixture.script.hold(by: gate)
        let export = Task.immediate { @MainActor in await fixture.service.export(.malXML) }
        let sent = await fixture.server.waitForRequest { $0.resource == "anime" }
        #expect(sent.bearerSubject == StubAuth.userA.lowercased())

        _ = await fixture.harness.session.applySession(userId: StubAuth.userB, email: "b@example.com")
        gate.open()
        await export.value

        #expect(fixture.service.state == .idle)
        #expect(fixture.filesOnDisk.isEmpty)
        #expect(fixture.service.identityCache.isEmpty)
        #expect(!fixture.identityRequests.contains { $0.bearerSubject == StubAuth.userB.lowercased() })
        await fixture.tearDown()
    }

    @Test("Deleting the account removes the cached identities and the export directory")
    func deletedAccountDataIsRemoved() async throws {
        let fixture = try ExportFixture(titles: 4, now: Self.nov9Noon)
        try await fixture.signInAndLoad()
        await fixture.service.export(.json)
        guard case .ready = fixture.service.state else { Issue.record("not ready"); return }
        #expect(!fixture.service.identityCache.isEmpty && !fixture.filesOnDisk.isEmpty)
        try await fixture.service.removeDeletedAccountData(userId: StubAuth.userA)
        #expect(fixture.service.identityCache.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path))
        #expect(fixture.service.state == .idle)
        await fixture.tearDown()
    }

    @Test("Dismissing deletes the folder and returns to idle; so does sign-out")
    func discardAndSignOutDeleteTheFiles() async throws {
        let fixture = try ExportFixture(titles: 4, now: Self.nov9Noon)
        try await fixture.signInAndLoad()
        await fixture.service.export(.csv)
        guard case .ready(let result) = fixture.service.state else { Issue.record("not ready"); return }
        #expect(FileManager.default.fileExists(atPath: result.files[0].path))
        fixture.service.discardFiles()
        #expect(fixture.service.state == .idle)
        #expect(fixture.filesOnDisk.isEmpty)

        await fixture.service.export(.csv)
        guard case .ready = fixture.service.state else { Issue.record("not ready"); return }
        await fixture.harness.session.signOut()
        #expect(fixture.service.state == .idle)
        #expect(fixture.filesOnDisk.isEmpty)
        #expect(fixture.service.identityCache.isEmpty)
        await fixture.tearDown()
    }

    @Test("A cancelled caller leaves no files, no cache and no state behind")
    func cancelledExportCachesNothing() async throws {
        let fixture = try ExportFixture(titles: 4, now: Self.nov9Noon)
        try await fixture.signInAndLoad()
        let gate = StubGate()
        fixture.script.hold(by: gate)
        let export = Task.immediate { @MainActor in await fixture.service.export(.csv) }
        _ = await fixture.server.waitForRequest { $0.resource == "anime" }
        export.cancel()
        gate.open()
        await export.value
        #expect(fixture.service.state == .idle)
        #expect(fixture.service.identityCache.isEmpty)
        #expect(fixture.filesOnDisk.isEmpty)
        await fixture.tearDown()
    }

    @Test("The release flag is checked before any request, provider call or file")
    func flagOffSendsNoRequest() async throws {
        let fixture = try ExportFixture(titles: 25, now: Self.nov9Noon, exportEnabled: false)
        try await fixture.signInAndLoad()
        let before = fixture.server.requests.count
        await fixture.service.export(.json)
        #expect(fixture.service.state == .failed(.disabled))
        #expect(fixture.server.requests.count == before)                      // no anime/manga lookup, no organisation read
        #expect(fixture.probe.organisationCalls == 0)
        #expect(fixture.filesOnDisk.isEmpty)
        await fixture.tearDown()
    }

    @Test("The lookup is leased: A's library ids are never dispatched once the SDK holds B's credentials")
    func identityLookupNeverSendsOldLibraryWithNewCredentials() async throws {
        // Positive control: while A is current the ids go out with A's bearer.
        let control = try ExportFixture(titles: 3, now: Self.nov9Noon)
        control.backend.setRows([11, 12, 13].map { FakeLibraryBackend.entry(.anime, $0, rowId: $0) }, for: StubAuth.userA)
        try await control.signInAndLoad()
        await control.service.export(.csv)
        let sent = try #require(control.identityRequests.first)
        #expect(Set(Self.inList(sent)).isSuperset(of: [11, 12, 13]))
        #expect(sent.bearerSubject == StubAuth.userA.lowercased())
        await control.tearDown()

        // Switch: A accepted the export; before the lookup is dispatched the SDK holds B's session and the
        // funnel moved to B. (B's session is kept from an earlier B sign-in, as CredentialLeaseTests does.)
        let fixture = try ExportFixture(titles: 3, now: Self.nov9Noon)
        fixture.backend.setRows([11, 12, 13].map { FakeLibraryBackend.entry(.anime, $0, rowId: $0) }, for: StubAuth.userA)
        let sessionB = try await CredentialLeaseTests.signedInAsAKeepingBsSession(fixture.harness)
        #expect(fixture.graph.library.loadState == .loaded)

        let harness = fixture.harness
        let export = Task.immediate { @MainActor in await fixture.service.export(.csv) }
        // Queued behind the export's own task: it reaches the credential lease first, and the switch runs
        // before the lease's request does.
        let switching = Task { @MainActor in
            harness.storage.replace(with: sessionB)
            _ = await harness.session.applySession(userId: StubAuth.userB, email: "b@example.com")
        }
        await export.value
        await switching.value

        #expect(!fixture.identityRequests.contains { $0.bearerSubject == StubAuth.userB.lowercased() },
                "A's library ids were sent with B's credential: \(fixture.identityRequests)")
        #expect(fixture.identityRequests.isEmpty, "A's ids were dispatched after A's session ended: \(fixture.identityRequests)")
        #expect(fixture.service.state == .idle)
        #expect(fixture.service.identityCache.isEmpty)
        #expect(fixture.filesOnDisk.isEmpty)
        await fixture.tearDown()
    }

    @Test("A requested format that could not be built is a failed export: no file is published")
    func failedFormatPublishesNothing() async throws {
        let fixture = try ExportFixture(titles: 3, now: Self.nov9Noon, build: { input, formats, exportedAt, zone in
            var bundle = LibraryExport.build(input, formats: formats, exportedAt: exportedAt, timeZone: zone)
            bundle = LibraryExportBundle(files: bundle.files, summary: {
                var summary = bundle.summary
                summary.failedFormats = [.json]
                return summary
            }())
            return bundle
        })
        try await fixture.signInAndLoad()
        await fixture.service.export(.json)
        #expect(fixture.service.state == .failed(.buildFailed))
        #expect(fixture.filesOnDisk.isEmpty)
        #expect(fixture.writer.writeCount == 0)
        await fixture.tearDown()
    }

    @Test("A write that fails leaves nothing behind and reports the failure")
    func writeFailureDeletesTheFolder() async throws {
        let fixture = try ExportFixture(titles: 3, now: Self.nov9Noon)
        try await fixture.signInAndLoad()
        fixture.writer.failWrites()
        await fixture.service.export(.csv)
        #expect(fixture.service.state == .failed(.writeFailed))
        #expect(fixture.filesOnDisk.isEmpty)
        await fixture.tearDown()
    }

    @Test("List items outside the library are part of the lookup and keep their title in the JSON")
    func listItemsOutsideTheLibraryAreLookedUp() async throws {
        let fixture = try ExportFixture(titles: 3, now: Self.nov9Noon)
        fixture.probe.lists = [ExportCustomList(
            id: UUID(), name: "Weekend", createdAt: Self.nov9Noon,
            items: [MediaKey(kind: .anime, id: 2), MediaKey(kind: .anime, id: 999)]
        )]
        try await fixture.signInAndLoad()
        await fixture.service.export(.json)
        guard case .ready(let result) = fixture.service.state else { Issue.record("not ready"); return }
        #expect(fixture.requestedIds.contains(999))
        #expect(result.summary.listItemsOutsideLibrary == 1)
        let object = try Self.jsonObject(result.files[0])
        let lists = try #require(object["lists"] as? [[String: Any]])
        let items = try #require(lists.first?["items"] as? [[String: Any]])
        #expect(items.map { $0["media_id"] as? Int } == [2, 999])
        #expect(items.last?["in_library"] as? Bool == false)
        #expect(items.last?["title"] as? String == "Title 999")
        await fixture.tearDown()
    }

    @Test("A Library read without the fenced columns is reported as a gap; with them the export is complete")
    func fenceOffExportIsNotComplete() async throws {
        let off = try ExportFixture(titles: 3, now: Self.nov9Noon)
        try await off.signInAndLoad()
        await off.service.export(.json)
        guard case .ready(let offResult) = off.service.state else { Issue.record("not ready"); return }
        #expect(offResult.summary.gaps == [.trackingDetailUnavailable])
        #expect(!offResult.summary.isComplete)
        let object = try Self.jsonObject(offResult.files[0])
        #expect(object["complete"] as? Bool == false)
        #expect(object["gaps"] as? [String] == ["tracking_detail_unavailable"])
        await off.tearDown()

        let on = try ExportFixture(titles: 3, now: Self.nov9Noon, fenceOn: true)
        try await on.signInAndLoad()
        await on.service.export(.json)
        guard case .ready(let onResult) = on.service.state else { Issue.record("not ready"); return }
        #expect(onResult.summary.isComplete)
        await on.tearDown()
    }

    @Test("A superseded run's detached work never deletes the export that replaced it, and writes nothing")
    func supersededRunCannotDeleteTheReplacementExport() async throws {
        let blocker = BuildBlocker()
        let fixture = try ExportFixture(titles: 5, now: Self.nov9Noon, build: { blocker.build($0, $1, $2, $3) })
        try await fixture.signInAndLoad()

        // Run 1 is inside its detached build (a large MAL XML, say) when the person prepares again.
        let first = Task.immediate { @MainActor in await fixture.service.export(.csv) }
        await blocker.waitUntilBlocked()
        await fixture.service.export(.json)
        guard case .ready(let result) = fixture.service.state else { Issue.record("run 2 not ready: \(fixture.service.state)"); blocker.open(); return }
        #expect(result.format == .json)
        let published = result.files
        #expect(published.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })

        blocker.open()
        await first.value

        #expect(fixture.service.state == .ready(result), "run 1 neither changed the state nor replaced the files")
        #expect(published.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }, "run 2's files were deleted by run 1: \(fixture.filesOnDisk)")
        #expect(Set(fixture.filesOnDisk.map(\.path)) == Set(published.map(\.path)), "nothing else is on disk")
        #expect(fixture.writer.writeCount == 1, "run 1 wrote nothing after it was superseded")
        await fixture.tearDown()
    }

    @Test("Signing out while a build is blocked: once it is released it writes nothing and leaves no folder")
    func signOutDuringBuildLeavesNothingOnDisk() async throws {
        let blocker = BuildBlocker()
        let fixture = try ExportFixture(titles: 5, now: Self.nov9Noon, build: { blocker.build($0, $1, $2, $3) })
        try await fixture.signInAndLoad()
        let first = Task.immediate { @MainActor in await fixture.service.export(.csv) }
        await blocker.waitUntilBlocked()

        await fixture.harness.session.signOut()
        #expect(fixture.service.state == .idle)
        blocker.open()
        await first.value

        #expect(fixture.service.state == .idle)
        #expect(fixture.writer.writeCount == 0, "the old account's notes were written after sign-out")
        #expect(fixture.filesOnDisk.isEmpty)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: fixture.directory.path)) ?? []
        #expect(leftovers.isEmpty, "a per-export folder was recreated after sign-out: \(leftovers)")
        #expect(fixture.service.identityCache.isEmpty)
        await fixture.tearDown()
    }
}
