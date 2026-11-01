import Foundation
import Testing
import Synchronization
import KuroCore
import KuroLibrary
@testable import Kuro

/// Real SDK transport and app owners; provider/database answers are controlled in-process.
/// These tests prove native orchestration, not provider fidelity or deployed SQL authorization.
@MainActor
private struct ImportWorkflowHarness {
    let server: StubServer
    let backend: FakeLibraryBackend
    let graph: AppGraph
    let journal: LibraryImportPageJournal
    let outbox: ProgressOutbox
    let directory: URL
    let defaults: UserDefaults
    private let suiteName: String

    init(backend: FakeLibraryBackend = FakeLibraryBackend()) throws {
        self.backend = backend
        server = StubServer()
        suiteName = "kuro.tests.import-workflow.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName, isDirectory: true)
        journal = try LibraryImportPageJournal(directory: directory.appendingPathComponent("imports"))
        outbox = try ProgressOutbox(path: directory.appendingPathComponent("progress.sqlite").path)
        graph = AppComposition.testingGraph(testingUserDefaults: defaults,
            notificationCenter: FakeNotificationCenter(), client: StubSupabase.makeClient(server: server),
            libraryBackend: backend, userListChannels: FakeUserListChannels(), progressOutbox: outbox)
    }

    func owner() -> ImportsService {
        let hook = LibraryRefreshHook()
        hook.connect(to: graph.libraryActions)
        return ImportsService(client: StubSupabase.makeClient(server: server), accountSession: graph.accountSession,
            library: graph.library, catalog: graph.catalog, libraryHook: hook, importJournal: journal,
            malCredentials: InMemoryMALCredentialStore())
    }

    func signIn() async {
        await graph.session.applySession(userId: LifecycleFixtures.userA, email: "import-test@example.com")
        await graph.libraryActions.libraryRefreshTask?.value
    }

    func requests(_ rpc: String) -> [RecordedRequest] { server.requests.filter { $0.resource == "rpc/\(rpc)" } }
    func manifests() async throws -> [ImportManifest] {
        try await journal.pendingWorkflows(accountId: LifecycleFixtures.userA)
    }
    func tearDown() async {
        await graph.session.endSession()
        defaults.removePersistentDomain(forName: suiteName)
        server.shutDown()
        try? FileManager.default.removeItem(at: directory)
    }
}

private enum ImportWorkflowReplies {
    static let job = "22222222-2222-2222-2222-222222222222"
    static let lifecycle = "33333333-3333-3333-3333-333333333333"
    static let source = #"{"success":true,"username":"fixture-source","types":["ANIME","MANGA"],"libraryItems":[{"medium":"anime","external_id":"7","title":"Anime Seven","status":"completed","progress":12,"notes":"provider note"},{"medium":"manga","external_id":"7","title":"Manga Seven","status":"current","progress":4}],"sourceExhausted":true}"#
    static let newAnime = #"{"medium":"anime","external_id":"7","media_id":701,"title":"Anime Seven","incoming":{"status":"completed","progress":12,"notes":"provider note","unavailable_fields":[]},"current":null,"disposition":"new","changed_fields":[]}"#
    static let newManga = #"{"medium":"manga","external_id":"7","media_id":702,"title":"Manga Seven","incoming":{"status":"current","progress":4,"unavailable_fields":[]},"current":null,"disposition":"new","changed_fields":[]}"#
    static let changedAnime = #"{"medium":"anime","external_id":"7","media_id":701,"title":"Anime Seven","incoming":{"status":"completed","progress":12,"notes":"provider note","unavailable_fields":[]},"current":{"status":"current","progress":3,"notes":"Kuro note","normalized_rating":9,"unavailable_fields":[]},"expected_revision":10,"expected_lifecycle":"33333333-3333-3333-3333-333333333333","disposition":"changes","changed_fields":["status","progress","notes"]}"#
    static let changedManga = #"{"medium":"manga","external_id":"7","media_id":702,"title":"Manga Seven","incoming":{"status":"completed","progress":4,"unavailable_fields":[]},"current":{"status":"current","progress":2,"unavailable_fields":[]},"expected_revision":20,"expected_lifecycle":"44444444-4444-4444-4444-444444444444","disposition":"changes","changed_fields":["status","progress"]}"#
    static let addedAnime = newAnime.replacingOccurrences(of: "\"disposition\":\"new\"", with: "\"disposition\":\"added\"")
    static let addedManga = newManga.replacingOccurrences(of: "\"disposition\":\"new\"", with: "\"disposition\":\"added\"")

    static func outcome(_ phase: String, counts: String = "{}", undo: Bool = false, selection: ImportSelection? = nil) -> String {
        let selected = selection ?? ImportSelection(provider: .anilist, sourceKind: .account,
            sourceIdentity: "fixture-source", media: ["anime", "manga"], statuses: ["CURRENT"])
        let wireSelection = String(decoding: try! JSONEncoder().encode(selected), as: UTF8.self)
        return """
        {"job_id":"\(job)","selection":\(wireSelection),"phase":"\(phase)","counts":\(counts),"exhausted_media":{"anime":true,"manga":true},"home_revisions":{"anime":1,"manga":1},"projection_ready":false,"undo_available":\(undo),"history_available":true}
        """
    }

    static func items(_ rows: [String], cursor: String? = nil) -> StubResponse {
        .json("{\"items\":[\(rows.joined(separator: ","))],\"next_cursor\":\(cursor.map { "\"\($0)\"" } ?? "null")}")
    }

    static func publication(_ request: RecordedRequest) -> StubResponse {
        if request.resource == "rpc/home_bundle_v1" {
            let medium = request.jsonObject?["p_medium"] as? String ?? "anime"
            return .json("{\"medium\":\"\(medium)\",\"window_days\":7,\"home_revision\":1,\"active\":[],\"upcoming\":[],\"pending\":[],\"schedule_state\":\"ready\",\"club\":{\"state\":\"empty\",\"label\":\"Between us.\",\"items\":[]}}")
        }
        return .emptyArray
    }

    static func standard(_ request: RecordedRequest, review: [String] = [newAnime, newManga]) -> StubResponse {
        switch request.resource {
        case "rpc/start_library_import_v2": return .json(outcome("preparing"))
        case "rpc/prepare_import_chunk_v2", "rpc/import_job_status_v2": return .json(outcome("reviewing"))
        case "rpc/import_items_page_v2": return items(review)
        case "rpc/apply_import_chunk_v2": return .json(outcome("applying", counts: "{\"added\":2}", undo: true))
        case "rpc/finish_library_import_v2": return .json(outcome("ready", counts: "{\"added\":2}", undo: true))
        default:
            return request.path == "/functions/v1/concierge-import-anilist" ? .json(source) : publication(request)
        }
    }
}

@MainActor
@Suite("Import workflow integration: owners, review, recovery and Undo", .timeLimit(.minutes(2)))
struct ImportWorkflowIntegrationTests {
    @Test("Typed AniList preparation and paged review preserve both media identities without a Library write")
    func aniListPreparationReadsBeforeWriting() async throws {
        let h = try ImportWorkflowHarness()
        h.server.respond { request in
            if request.resource == "rpc/import_items_page_v2" {
                return request.jsonObject?["p_cursor"] as? String == "opaque-page-two"
                    ? ImportWorkflowReplies.items([ImportWorkflowReplies.newManga])
                    : ImportWorkflowReplies.items([ImportWorkflowReplies.newAnime], cursor: "opaque-page-two")
            }
            return ImportWorkflowReplies.standard(request)
        }
        await h.signIn()
        let imports = h.owner()
        let job = try await imports.prepareAniListImport(username: "fixture-source", types: ["ANIME", "MANGA"], statuses: ["CURRENT"])
        let review = try await imports.reviewImport(jobId: job.jobId)
        #expect(job.phase == .reviewing)
        #expect(review.map(\.id) == ["anime|7", "manga|7"])
        #expect(review.map(\.mediaId) == [701, 702], "provider 7 must not become internal ID 7")
        let start = try #require(h.requests("start_library_import_v2").first?.jsonObject)
        let selection = try #require(start["p_selection"] as? [String: Any])
        #expect(selection["provider"] as? String == "anilist")
        #expect(selection["media"] as? [String] == ["anime", "manga"])
        let prepared = h.requests("prepare_import_chunk_v2").flatMap { $0.jsonObject?["p_items"] as? [[String: Any]] ?? [] }
        let identities = prepared.compactMap { row in
            (row["medium"] as? String).map { $0 + "|" + (row["external_id"] as? String ?? "") }
        }
        #expect(Set(identities) == ["anime|7", "manga|7"])
        #expect(h.requests("apply_import_chunk_v2").isEmpty)
        #expect(h.backend.writeCalls.isEmpty && h.server.listTableWrites.isEmpty)
        #expect(h.graph.library.allEntries.isEmpty)
        #expect(try await h.manifests().first?.sourceExhausted == true)
        await h.tearDown()
    }

    @Test("Mounted review keeps existing Kuro fields by default; a double Apply sends only one explicitly approved decision")
    func approvalAndApplyAreSerialized() async throws {
        let h = try ImportWorkflowHarness()
        h.backend.setRows([FakeLibraryBackend.entry(.anime, 701, progress: 3, notes: "Kuro note"),
                           FakeLibraryBackend.entry(.manga, 702, progress: 2)], for: LifecycleFixtures.userA)
        let gate = StubGate()
        h.server.respond { request in
            switch request.resource {
            case "rpc/apply_import_chunk_v2":
                return .json(ImportWorkflowReplies.outcome("applying", counts: "{\"updated\":1,\"unchanged\":1}", undo: true)).held(by: gate)
            case "rpc/finish_library_import_v2":
                return .json(ImportWorkflowReplies.outcome("ready", counts: "{\"updated\":1,\"unchanged\":1}", undo: true))
            default:
                return ImportWorkflowReplies.standard(request, review: [ImportWorkflowReplies.changedAnime, ImportWorkflowReplies.changedManga])
            }
        }
        await h.signIn()
        let imports = h.owner()
        let job = try await imports.prepareAniListImport(username: "fixture-source", statuses: ["CURRENT"])
        let screen = ImportWorkflowPresentation(imports: imports, job: job)
        screen.activate()
        await screen.load()
        #expect(screen.approval.decisions(for: screen.items).allSatisfy { $0.action == .keep && $0.fields.isEmpty })
        let anime = try #require(screen.items.first { $0.medium == "anime" })
        screen.approval.set(.status, approved: true, for: anime)
        let first = Task { await screen.apply() }
        _ = await h.server.waitForRequest { $0.resource == "rpc/apply_import_chunk_v2" }
        await screen.apply()
        #expect(screen.busy && h.requests("apply_import_chunk_v2").count == 1)
        gate.open()
        await first.value
        let body = try #require(h.requests("apply_import_chunk_v2").first?.jsonObject)
        let decisions = try #require(body["p_decisions"] as? [[String: Any]])
        let approved = try #require(decisions.first { $0["medium"] as? String == "anime" })
        let kept = try #require(decisions.first { $0["medium"] as? String == "manga" })
        #expect(approved["action"] as? String == "update" && approved["fields"] as? [String] == ["status"])
        #expect(approved["expected_revision"] as? Int == 10)
        #expect(approved["expected_lifecycle"] as? String == ImportWorkflowReplies.lifecycle)
        #expect(kept["action"] as? String == "keep" && kept["fields"] as? [String] == [])
        #expect(h.backend.writeCalls.isEmpty && h.server.listTableWrites.isEmpty, "the Library hook reads the committed projection; views do not issue raw writes")
        #expect(screen.job?.counts.updated == 1 && screen.job?.counts.unchanged == 1)
        #expect(screen.job?.projectionReady == true && screen.failure == nil)
        screen.close()
        await h.tearDown()
    }

    @Test("A committed import whose Library refresh fails retains counts and finalization; a new owner resumes publication without applying again")
    func committedProjectionFailureSurvivesOwnerRestart() async throws {
        let reads = ControlledResponses<[LibraryEntry]>()
        let h = try ImportWorkflowHarness(backend: FakeLibraryBackend(fetchSource: reads))
        let serverPhase = Mutex("preparing")
        h.server.respond { request in
            if request.resource == "rpc/import_job_status_v2" {
                let phase = serverPhase.withLock { $0 }
                return .json(ImportWorkflowReplies.outcome(phase, counts: phase == "ready" ? "{\"added\":2}" : "{}", undo: phase == "ready"))
            }
            if request.resource == "rpc/prepare_import_chunk_v2" { serverPhase.withLock { $0 = "reviewing" } }
            if request.resource == "rpc/finish_library_import_v2" { serverPhase.withLock { $0 = "ready" } }
            return ImportWorkflowReplies.standard(request)
        }
        await h.graph.session.applySession(userId: LifecycleFixtures.userA, email: "import-test@example.com")
        #expect(await reads.waitForRequest(LifecycleFixtures.userA))
        reads.complete(LifecycleFixtures.userA, with: .success([]))
        await h.graph.libraryActions.libraryRefreshTask?.value
        let imports = h.owner()
        let job = try await imports.prepareAniListImport(username: "fixture-source", statuses: ["CURRENT"])
        let decisions = try await imports.reviewImport(jobId: job.jobId).map { ImportDecision(item: $0) }
        let applying = Task { try await imports.applyImport(jobId: job.jobId, decisions: decisions) }
        #expect(await reads.waitForRequest("\(LifecycleFixtures.userA)#2"))
        reads.complete("\(LifecycleFixtures.userA)#2", with: .failure(LibraryError.unavailable(message: "projection offline")))
        do { _ = try await applying.value; Issue.record("A failed authoritative Library read cannot report ready") }
        catch { #expect(imports.importError != nil) }
        #expect(imports.activeImport?.counts.added == 2 && imports.activeImport?.projectionReady == false)
        let saved = try #require(try await h.manifests().first)
        #expect(saved.phase == .finalizing && saved.appliedDecisionCount == 2)
        #expect(saved.outcome?.counts.added == 2)
        let restarted = h.owner()
        #expect(try await restarted.discoverPendingImports().map(\.actionId) == [saved.actionId])
        let resuming = Task { try await restarted.resumeImport(actionId: saved.actionId) }
        #expect(await reads.waitForRequest("\(LifecycleFixtures.userA)#3"))
        reads.complete("\(LifecycleFixtures.userA)#3", with: .success([
            FakeLibraryBackend.entry(.anime, 701, status: .completed, progress: 12),
            FakeLibraryBackend.entry(.manga, 702, progress: 4)
        ]))
        let ready = try await resuming.value
        #expect(ready.phase == .ready && ready.projectionReady && ready.counts.added == 2)
        #expect(h.graph.library.entry(for: MediaKey(kind: .anime, id: 701))?.progress == 12)
        #expect(h.graph.library.entry(for: MediaKey(kind: .manga, id: 702))?.progress == 4)
        #expect(h.requests("apply_import_chunk_v2").count == 1 && h.requests("finish_library_import_v2").count == 1)
        #expect(h.requests("start_library_import_v2").count == 1)
        #expect(try await h.manifests().first?.phase == .ready)
        await h.tearDown()
    }

    @Test("Lost Apply delivery is discoverable after restart and replays the immutable approval rather than starting another import")
    func lostApplyUsesFrozenReplayAndVisibleServerJobs() async throws {
        let h = try ImportWorkflowHarness()
        let firstApply = CallCounter()
        h.server.respond { request in
            if request.resource == "rpc/apply_import_chunk_v2", firstApply.next() == 1 { return .failure(.networkConnectionLost) }
            if request.resource == "rpc/import_jobs_page_v2" {
                let job = ImportWorkflowReplies.outcome("applying", counts: "{\"added\":2}", undo: true)
                if request.jsonObject?["p_cursor"] as? String == "server-page-two" {
                    let remote = job.replacingOccurrences(of: ImportWorkflowReplies.job, with: "55555555-5555-5555-5555-555555555555")
                    return .json("{\"jobs\":[\(remote)],\"next_cursor\":null}")
                }
                return .json("{\"jobs\":[\(job)],\"next_cursor\":\"server-page-two\"}")
            }
            return ImportWorkflowReplies.standard(request)
        }
        await h.signIn()
        let imports = h.owner()
        let job = try await imports.prepareAniListImport(username: "fixture-source", statuses: ["CURRENT"])
        let review = try await imports.reviewImport(jobId: job.jobId)
        let decisions = review.map { ImportDecision(item: $0) }
        do { _ = try await imports.applyImport(jobId: job.jobId, decisions: decisions); Issue.record("Lost delivery must remain resumable") }
        catch { #expect(error as? ImportFailure == .uncertainDelivery) }
        let saved = try #require(try await h.manifests().first)
        #expect(saved.phase == .applying && saved.appliedDecisionCount == 0 && saved.decisions == decisions)
        let restarted = h.owner()
        #expect(try await restarted.discoverPendingImports().first?.actionId == saved.actionId)
        let jobs = try await restarted.importJobs()
        #expect(jobs.map(\.jobId) == [job.jobId, "55555555-5555-5555-5555-555555555555"])
        let edited = review.map { ImportDecision(item: $0, action: .deferReview) }
        do { _ = try await restarted.applyImport(jobId: job.jobId, decisions: edited); Issue.record("An attempted approval cannot be replaced") }
        catch { #expect(h.requests("apply_import_chunk_v2").count == 1) }
        let completed = try await restarted.resumeImport(actionId: saved.actionId)
        #expect(completed.projectionReady && completed.counts.added == 2)
        let apply = h.requests("apply_import_chunk_v2")
        #expect(apply.count == 2 && apply[0].canonicalBody == apply[1].canonicalBody)
        #expect(apply.first?.jsonObject?["p_action_id"] as? String == saved.actionId)
        #expect(h.requests("start_library_import_v2").count == 1 && h.requests("prepare_import_chunk_v2").count == 1)
        #expect(h.server.requests.filter { $0.path == "/functions/v1/concierge-import-anilist" }.count == 1)
        await h.tearDown()
    }

    @Test("Durable pending tracking blocks Undo before stop or compensation; guarded paged Undo preserves a later edit")
    func undoHonorsDurableTrackingAndGuardedReceipts() async throws {
        let h = try ImportWorkflowHarness()
        let retained = FakeLibraryBackend.entry(.anime, 701, progress: 99, notes: "later Kuro edit")
        h.backend.setRows([retained, FakeLibraryBackend.entry(.manga, 702, progress: 4)], for: LifecycleFixtures.userA)
        let backend = h.backend
        let compensated = Mutex(false)
        h.server.respond { request in
            switch request.resource {
            case "rpc/import_job_status_v2":
                return .json(ImportWorkflowReplies.outcome(compensated.withLock { $0 } ? "undone" : "ready", counts: "{\"added\":2}", undo: !compensated.withLock { $0 }))
            case "rpc/import_items_page_v2":
                let anime = compensated.withLock { $0 }
                    ? ImportWorkflowReplies.addedAnime.replacingOccurrences(of: "\"changed_fields\":[]", with: "\"changed_fields\":[],\"undo_disposition\":\"skipped\"")
                    : ImportWorkflowReplies.addedAnime
                return ImportWorkflowReplies.items([anime, ImportWorkflowReplies.addedManga])
            case "rpc/cancel_library_import_v2":
                return .json(ImportWorkflowReplies.outcome("cancelled", counts: "{\"added\":2}", undo: true))
            case "rpc/undo_library_import_chunk_v2":
                if request.jsonObject?["p_cursor"] as? String == "undo-page-two" {
                    compensated.withLock { $0 = true }
                    backend.setRows([retained], for: LifecycleFixtures.userA)
                    return .json("{\"job\":\(ImportWorkflowReplies.outcome("undone", counts: "{\"added\":2}")),\"reverted\":1,\"skipped\":1,\"next_cursor\":null}")
                }
                return .json("{\"job\":\(ImportWorkflowReplies.outcome("undoing", counts: "{\"added\":2}", undo: true)),\"reverted\":0,\"skipped\":1,\"next_cursor\":\"undo-page-two\"}")
            default: return ImportWorkflowReplies.standard(request)
            }
        }
        await h.signIn()
        #expect(h.graph.library.isTracked(MediaKey(kind: .manga, id: 702)))
        let imports = h.owner()
        var manifest = ImportManifest(accountId: LifecycleFixtures.userA,
            selection: ImportSelection(provider: .anilist, sourceKind: .account, sourceIdentity: "fixture-source", media: ["anime", "manga"], statuses: ["CURRENT"]))
        manifest.jobId = ImportWorkflowReplies.job
        manifest.phase = .ready
        manifest.outcome = try JSONDecoder().decode(ImportOutcome.self, from: Data(ImportWorkflowReplies.outcome("ready", counts: "{\"added\":2}", undo: true).utf8))
        try await h.journal.saveWorkflow(manifest)
        let intent = try await h.outbox.enqueue(ProgressIntent(accountId: LifecycleFixtures.userA.lowercased(), medium: "anime", mediaId: 701,
            lifecycleId: UUID(uuidString: ImportWorkflowReplies.lifecycle), position: 100, priorPosition: 99))
        do { _ = try await imports.undoImport(jobId: ImportWorkflowReplies.job); Issue.record("Unsent progress must guard compensation") }
        catch { #expect(error as? ImportFailure == .pendingTracking) }
        #expect(h.requests("cancel_library_import_v2").isEmpty && h.requests("undo_library_import_chunk_v2").isEmpty)
        #expect(try await h.outbox.active(accountId: LifecycleFixtures.userA.lowercased()).contains { $0.mutationId == intent.mutationId })
        try await h.outbox.markResolved(intent.mutationId, state: "acknowledged")
        let undone = try await imports.undoImport(jobId: ImportWorkflowReplies.job)
        #expect(undone.phase == .undone && undone.projectionReady)
        #expect(imports.importUndoReverted == 1 && imports.importUndoSkipped == 1, "cumulative server totals are not summed a second time across pages")
        let calls = h.requests("undo_library_import_chunk_v2")
        #expect(calls.count == 2)
        #expect(calls[0].jsonObject?["p_action_id"] as? String == calls[1].jsonObject?["p_action_id"] as? String)
        #expect(calls[1].jsonObject?["p_cursor"] as? String == "undo-page-two")
        let ordered = h.server.requests.compactMap(\.resource).filter { ["rpc/cancel_library_import_v2", "rpc/undo_library_import_chunk_v2"].contains($0) }
        #expect(ordered == ["rpc/cancel_library_import_v2", "rpc/undo_library_import_chunk_v2", "rpc/undo_library_import_chunk_v2"])
        let review = try await imports.reviewImport(jobId: ImportWorkflowReplies.job)
        #expect(review.first { $0.medium == "anime" }?.undoDisposition == "skipped")
        #expect(h.graph.library.entry(for: MediaKey(kind: .anime, id: 701))?.progress == 99)
        #expect(h.graph.library.entry(for: MediaKey(kind: .anime, id: 701))?.notes == "later Kuro edit")
        #expect(!h.graph.library.isTracked(MediaKey(kind: .manga, id: 702)), "the fresh server removal must survive the Undo reservation overlay")
        #expect(h.backend.writeCalls.isEmpty && h.server.listTableWrites.isEmpty)
        let restarted = h.owner()
        _ = try await restarted.refreshImport(jobId: ImportWorkflowReplies.job)
        #expect(restarted.importUndoReverted == 1 && restarted.importUndoSkipped == 1)
        await h.tearDown()
    }

    @Test("A preparation without a server job can be stopped; an orphaned final export page resumes without the original file")
    func joblessStopAndOrphanedFinalPageRecovery() async throws {
        let h = try ImportWorkflowHarness()
        let selection = ImportSelection(provider: .myanimelist, sourceKind: .export,
            sourceIdentity: "frozen-export", media: ["anime", "manga"])
        h.server.respond { request in
            switch request.resource {
            case "rpc/start_library_import_v2": return .json(ImportWorkflowReplies.outcome("preparing", selection: selection))
            case "rpc/prepare_import_chunk_v2": return .json(ImportWorkflowReplies.outcome("reviewing", selection: selection))
            default: return ImportWorkflowReplies.publication(request)
            }
        }
        await h.signIn()
        let incomplete = ImportManifest(accountId: LifecycleFixtures.userA, selection: selection)
        try await h.journal.saveWorkflow(incomplete)
        let imports = h.owner()
        try await imports.stopPreparedImport(actionId: incomplete.actionId)
        let stopped = try #require(try await h.journal.loadWorkflow(accountId: LifecycleFixtures.userA, actionId: incomplete.actionId))
        #expect(stopped.phase == .cancelled && stopped.jobId == nil && stopped.outcome == nil)
        #expect(h.requests("start_library_import_v2").isEmpty && h.requests("cancel_library_import_v2").isEmpty)

        let orphan = ImportManifest(accountId: LifecycleFixtures.userA, selection: selection)
        try await h.journal.saveWorkflow(orphan)
        let original = try JSONDecoder().decode([ImportReviewItem].self,
            from: Data("[\(ImportWorkflowReplies.newAnime),\(ImportWorkflowReplies.newManga)]".utf8))
        let page = ImportSourcePage(items: original.map { ImportSourceItem(medium: $0.medium, externalId: $0.externalId,
            title: $0.title, values: $0.incoming) }, nextCursor: nil, exhaustedMedia: ["anime": true, "manga": true])
        // Crash boundary: the page exists atomically, while its manifest still says nextPage=0.
        try await h.journal.writeWorkflowPage(accountId: LifecycleFixtures.userA, actionId: orphan.actionId, page: 0, value: page)
        let restarted = h.owner()
        let job = try await restarted.resumeImport(actionId: orphan.actionId)
        #expect(job.phase == .reviewing && job.selection == selection)
        let recovered = try #require(try await h.journal.loadWorkflow(accountId: LifecycleFixtures.userA, actionId: orphan.actionId))
        #expect(recovered.nextPage == 1 && recovered.preparedPages == 1 && recovered.sourceExhausted)
        #expect(h.requests("start_library_import_v2").count == 1 && h.requests("prepare_import_chunk_v2").count == 1)
        #expect(h.server.requests.allSatisfy { !$0.path.contains("concierge-import-anilist") })
        #expect(h.requests("apply_import_chunk_v2").isEmpty && h.backend.writeCalls.isEmpty)
        await h.tearDown()
    }

    @Test("Stopping an uncertain job start recovers its original action before cancelling the admitted server job")
    func uncertainStartStopRecoversAdmission() async throws {
        let h = try ImportWorkflowHarness()
        let selection = ImportSelection(provider: .myanimelist, sourceKind: .export,
            sourceIdentity: "frozen-export", media: ["anime", "manga"])
        h.server.respond { request in
            switch request.resource {
            case "rpc/start_library_import_v2": return .json(ImportWorkflowReplies.outcome("preparing", selection: selection))
            case "rpc/cancel_library_import_v2": return .json(ImportWorkflowReplies.outcome("cancelled", selection: selection))
            default: return ImportWorkflowReplies.publication(request)
            }
        }
        await h.signIn()
        var lost = ImportManifest(accountId: LifecycleFixtures.userA, selection: selection)
        lost.startAttempted = true
        lost.nextPage = 1
        lost.sourceExhausted = true
        try await h.journal.saveWorkflow(lost)
        try await h.journal.writeWorkflowPage(accountId: LifecycleFixtures.userA, actionId: lost.actionId,
            page: 0, value: ImportSourcePage(items: [], nextCursor: nil, exhaustedMedia: ["anime": true, "manga": true]))
        let restarted = h.owner()
        try await restarted.stopPreparedImport(actionId: lost.actionId)
        let start = try #require(h.requests("start_library_import_v2").first?.jsonObject)
        #expect(start["p_action_id"] as? String == lost.actionId)
        let replayedSelection = try #require(start["p_selection"])
        #expect(try JSONDecoder().decode(ImportSelection.self, from: JSONSerialization.data(withJSONObject: replayedSelection)) == selection)
        let stopped = try #require(try await h.journal.loadWorkflow(accountId: LifecycleFixtures.userA, actionId: lost.actionId))
        #expect(stopped.jobId == ImportWorkflowReplies.job && stopped.phase == .cancelled)
        #expect(stopped.outcome?.projectionReady == true)
        let ordered = h.server.requests.compactMap(\.resource).filter { ["rpc/start_library_import_v2", "rpc/cancel_library_import_v2"].contains($0) }
        #expect(ordered == ["rpc/start_library_import_v2", "rpc/cancel_library_import_v2"])
        #expect(h.requests("prepare_import_chunk_v2").isEmpty && h.requests("apply_import_chunk_v2").isEmpty)
        #expect(try await h.journal.readWorkflowPage(accountId: LifecycleFixtures.userA, actionId: lost.actionId, page: 0) == nil)
        await h.tearDown()
    }

    @Test("Retrying the same mounted AniList gesture after a lost start response reuses its durable action and source")
    func sameGestureRetryPreservesPreparationIdentity() async throws {
        let h = try ImportWorkflowHarness()
        let starts = CallCounter()
        h.server.respond { request in
            if request.resource == "rpc/start_library_import_v2", starts.next() == 1 { return .failure(.networkConnectionLost) }
            return ImportWorkflowReplies.standard(request)
        }
        await h.signIn()
        let imports = h.owner()
        let screen = ConciergeAniListImportCoordinator()
        screen.activate(using: imports)
        #expect(await screen.prepare(using: imports, username: "fixture-source", types: ["ANIME", "MANGA"], statuses: ["CURRENT"]) == nil)
        #expect(screen.phase == .error)
        let saved = try #require(try await h.manifests().first)
        #expect(saved.startAttempted == true && saved.jobId == nil)
        let ready = await screen.prepare(using: imports, username: "fixture-source", types: ["ANIME", "MANGA"], statuses: ["CURRENT"])
        #expect(ready?.phase == .reviewing && screen.phase == .ready)
        let calls = h.requests("start_library_import_v2")
        #expect(calls.count == 2 && calls[0].canonicalBody == calls[1].canonicalBody)
        #expect(calls[0].jsonObject?["p_action_id"] as? String == saved.actionId)
        #expect(try await h.manifests().count == 1)
        #expect(h.server.requests.filter { $0.path == "/functions/v1/concierge-import-anilist" }.count == 1)
        #expect(h.requests("apply_import_chunk_v2").isEmpty && h.server.listTableWrites.isEmpty)
        screen.stop()
        await h.tearDown()
    }

    @Test("Closing preparation and switching accounts discards late presentation while retaining only the original account's recovery input")
    func closedPreparationCannotPublishIntoAnotherAccount() async throws {
        let h = try ImportWorkflowHarness()
        let gate = StubGate()
        h.server.respond { request in
            if request.resource == "rpc/prepare_import_chunk_v2" {
                return .json(ImportWorkflowReplies.outcome("reviewing")).held(by: gate)
            }
            return ImportWorkflowReplies.standard(request)
        }
        await h.signIn()
        let imports = h.owner()
        let screen = ConciergeAniListImportCoordinator()
        screen.activate(using: imports)
        let preparing = Task { await screen.prepare(using: imports, username: "fixture-source", types: ["ANIME", "MANGA"], statuses: ["CURRENT"]) }
        _ = await h.server.waitForRequest { $0.resource == "rpc/prepare_import_chunk_v2" }
        screen.stop()
        await h.graph.session.applySession(userId: LifecycleFixtures.userB, email: "other-test@example.com")
        await h.graph.libraryActions.libraryRefreshTask?.value
        gate.open()
        #expect(await preparing.value == nil)
        #expect(screen.preparedImport == nil && screen.errorMessage == nil && screen.phase == .form)
        #expect(imports.activeImport == nil && imports.pendingImports.isEmpty)
        #expect(try await h.manifests().count == 1, "A's frozen source remains recoverable on A")
        #expect(try await h.journal.pendingWorkflows(accountId: LifecycleFixtures.userB).isEmpty)
        let prior = h.server.requests.count
        #expect(await screen.prepare(using: imports, username: "fixture-source", types: ["ANIME", "MANGA"], statuses: ["CURRENT"]) == nil)
        #expect(h.server.requests.count == prior, "an unmounted screen cannot launch under B")
        #expect(h.requests("apply_import_chunk_v2").isEmpty)
        await h.tearDown()
    }

    @Test("A definitive active-job admission rejection leaves no uncertain start; Stop cleans only this local preparation")
    func rejectedAdmissionCanStopWithoutTouchingAnotherJob() async throws {
        let h = try ImportWorkflowHarness()
        h.server.respond { request in
            if request.resource == "rpc/start_library_import_v2" {
                return .json(#"{"code":"P0001","message":"IMPORT_ALREADY_ACTIVE","details":null,"hint":null}"#, status: 400)
            }
            return ImportWorkflowReplies.publication(request)
        }
        await h.signIn()
        let selection = ImportSelection(provider: .myanimelist, sourceKind: .export,
            sourceIdentity: "blocked-export", media: ["anime", "manga"])
        var prepared = ImportManifest(accountId: LifecycleFixtures.userA, selection: selection)
        prepared.nextPage = 1; prepared.sourceExhausted = true
        try await h.journal.saveWorkflow(prepared)
        try await h.journal.writeWorkflowPage(accountId: LifecycleFixtures.userA, actionId: prepared.actionId,
            page: 0, value: ImportSourcePage(items: [], nextCursor: nil, exhaustedMedia: ["anime": true, "manga": true]))
        let imports = h.owner()
        do { _ = try await imports.resumeImport(actionId: prepared.actionId); Issue.record("The other active job must block admission") }
        catch { #expect(error as? ImportFailure == .activeJob) }
        let rejected = try #require(try await h.journal.loadWorkflow(accountId: LifecycleFixtures.userA, actionId: prepared.actionId))
        #expect(rejected.startAttempted == false && rejected.jobId == nil)
        try await imports.stopPreparedImport(actionId: prepared.actionId)
        #expect(h.requests("start_library_import_v2").count == 1)
        #expect(h.requests("cancel_library_import_v2").isEmpty && h.requests("apply_import_chunk_v2").isEmpty)
        #expect(try await h.journal.readWorkflowPage(accountId: LifecycleFixtures.userA, actionId: prepared.actionId, page: 0) == nil)
        #expect(try await h.journal.loadWorkflow(accountId: LifecycleFixtures.userA, actionId: prepared.actionId)?.phase == .cancelled)
        #expect(h.backend.writeCalls.isEmpty && h.server.listTableWrites.isEmpty)
        await h.tearDown()
    }

    @Test("Post-review durable progress blocks Apply and resume before dispatch; acknowledging it resumes only the original approval")
    func applyPreservesPostReviewDurableLibraryIntent() async throws {
        let h = try ImportWorkflowHarness()
        h.backend.setRows([FakeLibraryBackend.entry(.anime, 701, progress: 3, notes: "Kuro note")], for: LifecycleFixtures.userA)
        h.server.respond { request in
            ImportWorkflowReplies.standard(request, review: [ImportWorkflowReplies.changedAnime, ImportWorkflowReplies.newManga])
        }
        await h.signIn()
        let imports = h.owner()
        let job = try await imports.prepareAniListImport(username: "fixture-source", statuses: ["CURRENT"])
        let review = try await imports.reviewImport(jobId: job.jobId)
        let decisions = review.map { item in
            item.medium == "anime" ? ImportDecision(item: item, action: .update, fields: [.status]) : ImportDecision(item: item)
        }
        let pending = try await h.outbox.enqueue(ProgressIntent(accountId: LifecycleFixtures.userA.lowercased(),
            medium: "anime", mediaId: 701, lifecycleId: UUID(uuidString: ImportWorkflowReplies.lifecycle),
            baseRevision: 10, position: 4, priorPosition: 3))
        do { _ = try await imports.applyImport(jobId: job.jobId, decisions: decisions); Issue.record("Apply cannot displace an unsynced Library edit") }
        catch { #expect(error as? ImportFailure == .pendingTracking && imports.importError == .pendingTracking) }
        let saved = try #require(try await h.manifests().first)
        #expect(saved.phase == .applying && saved.decisions == decisions && saved.appliedDecisionCount == 0)
        do { _ = try await imports.resumeImport(actionId: saved.actionId); Issue.record("Resume must honor the same pending edit") }
        catch { #expect(error as? ImportFailure == .pendingTracking) }
        #expect(h.requests("apply_import_chunk_v2").isEmpty && h.requests("finish_library_import_v2").isEmpty)
        #expect(try await h.outbox.active(accountId: LifecycleFixtures.userA.lowercased()).contains { $0 == pending })
        #expect(h.graph.library.entry(for: MediaKey(kind: .anime, id: 701))?.progress == 3)
        try await h.outbox.markResolved(pending.mutationId, state: "acknowledged")
        let completed = try await imports.resumeImport(actionId: saved.actionId)
        #expect(completed.projectionReady)
        let apply = try #require(h.requests("apply_import_chunk_v2").first?.jsonObject)
        #expect(h.requests("apply_import_chunk_v2").count == 1 && h.requests("finish_library_import_v2").count == 1)
        #expect(apply["p_action_id"] as? String == saved.actionId)
        let replayed = try #require(apply["p_decisions"])
        #expect(try JSONDecoder().decode([ImportDecision].self, from: JSONSerialization.data(withJSONObject: replayed)) == decisions)
        #expect(h.requests("start_library_import_v2").count == 1)
        #expect(h.backend.writeCalls.isEmpty && h.server.listTableWrites.isEmpty)
        await h.tearDown()
    }
}
