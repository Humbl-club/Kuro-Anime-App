//
//  AssistantContractTests.swift
//  KuroTests
//
//  Imports, Concierge, Taste and DeviceIntelligence owners (E6b) asserted on the requests the real
//  supabase-swift client emits (StubPostgREST: in-process, no network, edge functions under
//  `/functions/v1/`) and on what they publish across account transitions. Stale-account answers are
//  tested both ways: cancelled by the session funnel (`server.stoppedRequests`) and delivered after
//  another account became current without the funnel (only the captured `AccountContext` protects).
//  Each test is named by the risk it covers.
//

import Testing
import Foundation
import KuroCore
import KuroLibrary
import Synchronization
@testable import Kuro

/// How the next account became current while the previous account's answer was in flight.
enum AccountHandOver: String, CaseIterable, Sendable {
    /// `applySession(B)`: the funnel cancels A's in-flight work (the held answer is never delivered).
    case funnelSwitch
    /// `accountSession.begin(B)` only: A's answer is delivered; only A's captured context protects B.
    case contextOnly
}

enum LateAnswer: String, CaseIterable, Sendable { case success, failure }

/// Counts answers of one kind of request and holds the first one behind a gate.
final class HoldFirst: Sendable {
    let gate = StubGate()
    private let count = Mutex(0)

    /// `answer` for the first matching request held by `gate`, later ones as they are.
    func answer(_ answer: StubResponse) -> StubResponse {
        let ordinal = count.withLock { value -> Int in
            value += 1
            return value
        }
        return ordinal == 1 ? answer.held(by: gate) : answer
    }
}

private func edgeText(_ request: RecordedRequest) -> String? {
    request.jsonObject?["text"] as? String
}

// MARK: - Imports

@MainActor
@Suite("Assistant: Imports", .timeLimit(.minutes(1)))
struct ImportsContractTests {
    static let userA = LifecycleFixtures.userA
    static let userB = LifecycleFixtures.userB
    nonisolated static let parseJSON = #"{"success":true,"userId":"a","items":[]}"#
    nonisolated static let rateLimited = StubResponse.json(#"{"error":"Rate limited","retry_after_s":30}"#, status: 429)

    @Test("The account-deletion barrier is terminal; unrelated forbidden errors stay unclassified")
    func deletionBarrierIsTerminal() async throws {
        let harness = try FacadeHarness()
        await harness.signIn()
        defer { harness.server.shutDown() }
        for knownBarrier in [true, false] {
            harness.server.respond { request in
                guard request.path == "/functions/v1/concierge-apply" else { return .emptyArray }
                return .json(knownBarrier
                    ? #"{"error":"Account deletion in progress","code":"ACCOUNT_DELETION_IN_PROGRESS","retryable":false}"#
                    : #"{"error":"Forbidden","code":"OTHER_PERMISSION_ERROR"}"#, status: 403)
            }
            do {
                _ = try await harness.service.imports.conciergeApply(items: [["mediaType": "ANIME", "mediaId": 7]])
                Issue.record("Expected server rejection")
            } catch {
                #expect(ImportApplyDelivery.of(error) == (knownBarrier ? .terminal : .uncertain))
                if knownBarrier {
                    let failure = try #require(error as? ConciergeRequestFailure)
                    if case .invalid(_, let code, _) = failure {
                        #expect(code == "ACCOUNT_DELETION_IN_PROGRESS")
                    } else { Issue.record("Deletion barrier must be a definitive rejection") }
                }
            }
        }
        await harness.tearDown()
    }

    @Test("Apply and Undo (server-side writers) fire the single Library hook once per success; failures refresh nothing")
    func applyAndUndoRefreshLibraryOnce() async throws {
        let harness = try FacadeHarness()
        let service = harness.service
        let imports = service.imports
        let fail = Mutex(false)
        harness.server.respond { request in
            if fail.withLock({ $0 }) {
                return request.path == "/functions/v1/concierge-undo"
                    ? .failure(.networkConnectionLost)
                    : .json(#"{"error":"boom"}"#, status: 500)
            }
            switch request.path {
            case "/functions/v1/concierge-apply":
                return .json(#"{"success":true,"sessionId":"s1","applied":[{"mediaType":"ANIME","mediaId":42,"status":"PLANNING"}]}"#)
            case "/functions/v1/concierge-undo":
                return .json(#"{"success":true,"sessionId":"s1","reverted":[{"mediaType":"ANIME","mediaId":42}]}"#)
            default:
                return .emptyArray
            }
        }
        await harness.signIn()
        #expect(harness.fetchAllCount == 1)

        // Apply: the edge function wrote server-side; the store reads fresh once, no local list write.
        harness.backend.setRows([FakeLibraryBackend.entry(.anime, 42, status: .planning)], for: Self.userA)
        let applied = try await imports.conciergeApply(items: [["mediaType": "ANIME", "mediaId": 42]])
        #expect(applied.applied?.first?.mediaId == 42)
        let applyBody = try #require(harness.server.requests.last { $0.path.contains("concierge-apply") }?.body)
        let applyJSON = try #require(JSONSerialization.jsonObject(with: applyBody) as? [String: Any])
        #expect(ImportApplyIdentity.isValid(applyJSON["idempotencyKey"] as? String ?? ""))
        await service.libraryActions.libraryRefreshTask?.value
        #expect(harness.fetchAllCount == 2)
        #expect(service.library.isTracked(MediaKey(kind: .anime, id: 42)))

        // Undo: likewise exactly one fresh read.
        harness.backend.setRows([], for: Self.userA)
        _ = try await imports.conciergeUndo(sessionId: "s1")
        await service.libraryActions.libraryRefreshTask?.value
        #expect(harness.fetchAllCount == 3)
        #expect(!service.library.isTracked(MediaKey(kind: .anime, id: 42)))
        #expect(harness.backend.writeCalls.isEmpty, "apply/undo never write a list row locally")

        // Failure paths (HTTP 500, transport failure, 429): no refresh.
        fail.withLock { $0 = true }
        await #expect(throws: (any Error).self) { _ = try await imports.conciergeApply(items: [["mediaType": "ANIME", "mediaId": 42]]) }
        await #expect(throws: (any Error).self) { _ = try await imports.conciergeUndo(sessionId: "s1") }
        harness.server.respond { _ in Self.rateLimited }
        await #expect(throws: ConciergeGuardrailsError.rateLimited(retryAfterSeconds: 30)) {
            _ = try await imports.conciergeApply(items: [["mediaType": "ANIME", "mediaId": 42]])
        }
        await service.libraryActions.libraryRefreshTask?.value
        #expect(harness.fetchAllCount == 3)
        await harness.tearDown()
    }

    @Test("A lost Apply response retries the frozen payload and key; Profile's partial session stays undoable after a retryable Undo failure")
    func lostApplyReplaysAndProfileUndoKeepsItsSession() async throws {
        let harness = try FacadeHarness()
        let imports = harness.service.imports
        let applyCalls = Mutex(0)
        let undoCalls = Mutex(0)
        harness.server.respond { request in
            if request.path.contains("concierge-undo") {
                let n = undoCalls.withLock { value -> Int in
                    value += 1
                    return value
                }
                if n == 1 {
                    return .json(#"{"error":"Undo could not be completed","status":"failed","retryable":true}"#, status: 500)
                }
                return .json(#"{"success":true,"sessionId":"s-replay","reverted":[{"mediaType":"ANIME","mediaId":7}],"skipped":[],"status":"undone"}"#)
            }
            guard request.path.contains("concierge-apply") else { return .emptyArray }
            let n = applyCalls.withLock { value -> Int in
                value += 1
                return value
            }
            if n == 1 { return .failure(.networkConnectionLost) }
            return .json(#"{"success":false,"sessionId":"s-replay","applied":[{"mediaType":"ANIME","mediaId":7,"status":"PLANNING","action":"add"}],"conflicts":[{"mediaType":"MANGA","mediaId":9,"error":"conflict"}],"errors":[],"status":"partial","undoable":true,"replayed":true}"#)
        }
        await harness.signIn()

        let attempt = ImportApplyAttempt()
        let original: [[String: Any]] = [["mediaType": "ANIME", "mediaId": 7, "status": "PLANNING"]]
        let first = attempt.begin(anchor: "profile:anilist-text", stamp: "profile") { original }
        do {
            _ = try await imports.conciergeApply(items: first.items, idempotencyKey: first.key)
            Issue.record("the first Apply was expected to lose its response")
        } catch {
            attempt.observe(error)
            #expect(attempt.frozenKey == first.key)
        }
        let retry = attempt.begin(anchor: "profile:anilist-text", stamp: "profile") {
            [["mediaType": "MANGA", "mediaId": 99, "status": "READING"]]
        }
        let applied = try await imports.conciergeApply(items: retry.items, idempotencyKey: retry.key)
        #expect(applied.replayed == true)
        #expect(applied.presentation.tone == .partial)
        let sessionId = try #require(applied.presentation.undoSessionId)
        #expect(sessionId == "s-replay")

        let applyBodies = harness.server.requests.filter { $0.path.contains("concierge-apply") }.compactMap(\.jsonObject)
        #expect(applyBodies.count == 2)
        #expect(applyBodies[0]["idempotencyKey"] as? String == first.key)
        #expect(applyBodies[1]["idempotencyKey"] as? String == first.key)
        #expect(Self.mediaId(in: applyBodies[0]) == 7)
        #expect(Self.mediaId(in: applyBodies[1]) == 7)

        do {
            _ = try await imports.conciergeUndo(sessionId: sessionId)
            Issue.record("the first Undo was expected to be retryable")
        } catch {
            #expect(ImportApplyDelivery.of(error) == .uncertain)
        }
        let undone = try await imports.conciergeUndo(sessionId: sessionId)
        #expect(undone.success)
        let undoIds = harness.server.requests.filter { $0.path.contains("concierge-undo") }.compactMap { $0.jsonObject?["sessionId"] as? String }
        #expect(undoIds == ["s-replay", "s-replay"])
        await harness.tearDown()
    }

    @Test("Profile's retry route replays the lost import before a tracked-title review decision")
    func profileRetryDispatchesBeforeReconciliation() async throws {
        let harness = try FacadeHarness()
        let applyCalls = Mutex(0)
        harness.server.respond { request in
            guard request.path.contains("concierge-apply") else { return .emptyArray }
            let n = applyCalls.withLock { value -> Int in
                value += 1
                return value
            }
            if n == 1 { return .failure(.networkConnectionLost) }
            return .json(#"{"success":true,"sessionId":"s-replay","applied":[{"mediaType":"ANIME","mediaId":7,"status":"PLANNING","action":"add"}],"status":"applied","undoable":true,"replayed":true}"#)
        }
        await harness.signIn()
        harness.backend.setRows([FakeLibraryBackend.entry(.anime, 7, status: .planning)], for: Self.userA)

        let attempt = ImportApplyAttempt()
        let original: [[String: Any]] = [["mediaType": "ANIME", "mediaId": 7, "status": "PLANNING"]]
        let first = attempt.begin(anchor: ProfileImportRecovery.anchor, stamp: ProfileImportRecovery.stamp) { original }
        do {
            _ = try await harness.service.imports.conciergeApply(items: first.items, idempotencyKey: first.key)
        } catch {
            attempt.observe(error)
        }
        #expect(ProfileImportRecovery.replayIfRetrying(intent: .newImport, attempt: attempt) == nil)
        let replay = try #require(ProfileImportRecovery.replayIfRetrying(intent: .retryUnresolved, attempt: attempt))
        let applied = try await harness.service.imports.conciergeApply(items: replay.items, idempotencyKey: replay.key)
        #expect(applied.replayed == true)
        #expect(applied.presentation.undoSessionId == "s-replay")
        let bodies = harness.server.requests.filter { $0.path.contains("concierge-apply") }.compactMap(\.jsonObject)
        #expect(bodies.count == 2)
        #expect(bodies[0]["idempotencyKey"] as? String == first.key)
        #expect(bodies[1]["idempotencyKey"] as? String == first.key)
        #expect(Self.mediaId(in: bodies[1]) == 7)
        await harness.tearDown()
    }

    @Test("A dismissed Profile card does not publish a late Undo success or failure")
    func dismissedProfileCardDropsLateUndo() async throws {
        let harness = try FacadeHarness()
        let gates = [StubGate(), StubGate()]
        let ordinal = Mutex(0)
        harness.server.respond { request in
            guard request.path.contains("concierge-undo") else { return .emptyArray }
            let index = ordinal.withLock { value -> Int in
                let current = value
                value += 1
                return current
            }
            if index == 0 {
                return .json(#"{"success":true,"sessionId":"s-replay","reverted":[],"skipped":[],"status":"undone"}"#).held(by: gates[0])
            }
            return .json(#"{"error":"Undo could not be completed","status":"failed","retryable":true}"#, status: 500).held(by: gates[1])
        }
        await harness.signIn()

        for index in 0..<2 {
            let lifetime = ProfileImportCardLifetime()
            let started = lifetime.generation
            let task = Task { @MainActor in
                do {
                    _ = try await harness.service.imports.conciergeUndo(sessionId: "s-replay")
                    return ProfileUndoPublication.mayApply(
                        startedGeneration: started,
                        generation: lifetime.generation,
                        visibleSession: nil,
                        startedSession: "s-replay"
                    )
                } catch {
                    return ProfileUndoPublication.mayApply(
                        startedGeneration: started,
                        generation: lifetime.generation,
                        visibleSession: nil,
                        startedSession: "s-replay"
                    )
                }
            }
            let seen = Mutex(0)
            let target = index + 1
            _ = await harness.server.waitForRequest { request in
                guard request.path.contains("concierge-undo") else { return false }
                let count = seen.withLock { value -> Int in
                    value += 1
                    return value
                }
                return count == target
            }
            lifetime.invalidate()
            gates[index].open()
            let published = await task.value
            #expect(!published)
        }
        await harness.tearDown()
    }

    private static func mediaId(in body: [String: Any]) -> Int? {
        guard let items = body["items"] as? [[String: Any]] else { return nil }
        if let id = items.first?["mediaId"] as? Int { return id }
        return (items.first?["mediaId"] as? NSNumber)?.intValue
    }

    @Test("Export text: anime 7 and manga 7 each export their own title (typed MediaKey, no id collision)")
    func exportTextKeepsEqualIdsApart() async throws {
        let backend = FakeLibraryBackend()
        backend.setRows([
            FakeLibraryBackend.entry(.anime, 7, status: .current, progress: 3),
            FakeLibraryBackend.entry(.manga, 7, rowId: 2, status: .completed),
        ], for: Self.userA)
        let harness = try FacadeHarness(backend: backend)
        harness.server.respond { request in
            switch request.resource {
            case "anime": return .json(#"[{"id":7,"title_english":"Anime Seven","title_romaji":null,"title_native":null}]"#)
            case "manga": return .json(#"[{"id":7,"title_english":"Manga Seven","title_romaji":null,"title_native":null}]"#)
            default: return .emptyArray
            }
        }
        await harness.signIn()

        let result = try #require(await harness.service.imports.conciergeLibraryExportText())

        #expect(Set(result.text.split(separator: "\n").map(String.init))
                == ["Anime Seven (watching ep 3)", "Manga Seven (completed)"], "\(result.text)")
        #expect(result.exportedItemCount == 2)
        #expect(harness.requests(to: "anime").map { $0.query("id") } == ["in.(7)"])
        #expect(harness.requests(to: "manga").map { $0.query("id") } == ["in.(7)"])
        await harness.tearDown()
    }

    @Test("Export text: an id missing from the catalog batch is listed as untitled, in one request for the batch")
    func exportTextNamesUnresolvedIds() async throws {
        let backend = FakeLibraryBackend()
        var manga = FakeLibraryBackend.entry(.manga, 9, status: .current, progress: 2)
        manga.progressLabel = "2.5"
        manga.unitId = UUID()
        backend.setRows([
            FakeLibraryBackend.entry(.anime, 7, status: .planning),
            FakeLibraryBackend.entry(.anime, 8, status: .completed),
            manga,
        ], for: Self.userA)
        let harness = try FacadeHarness(backend: backend)
        harness.server.respond { request in
            request.resource == "anime"
                ? .json(#"[{"id":7,"title_english":"Anime Seven","title_romaji":null,"title_native":null}]"#)
                : .json("[]", status: 500)
        }
        await harness.signIn()

        let result = try #require(await harness.service.imports.conciergeLibraryExportText())

        #expect(Set(result.text.split(separator: "\n").map(String.init)) == [
            "Anime Seven (planning)",
            "Untitled anime #8 (completed)",
            "Untitled manga #9 (reading ch 2.5)",
        ], "\(result.text)")
        #expect(result.exportedItemCount == 3)
        #expect(harness.requests(to: "anime").count == 1)
        #expect(harness.requests(to: "anime").map { $0.query("id") } == ["in.(7,8)"])
        #expect(harness.requests(to: "manga").count == 1)
        await harness.tearDown()
    }

    @Test("Export text of an account that ended while its titles were resolving is not handed out")
    func exportTextOfEndedAccountIsDropped() async throws {
        let slow = StubGate()
        let backend = FakeLibraryBackend()
        backend.setRows([FakeLibraryBackend.entry(.anime, 7, status: .planning)], for: Self.userA)
        let harness = try FacadeHarness(backend: backend)
        harness.server.respond { request in
            request.resource == "anime"
                ? StubResponse.json(#"[{"id":7,"title_english":"A's title","title_romaji":null,"title_native":null}]"#).held(by: slow)
                : .emptyArray
        }
        await harness.signIn()
        let imports = harness.service.imports
        let exportA = Task.immediate { @MainActor in await imports.conciergeLibraryExportText()?.text }
        _ = await harness.server.waitForRequest { $0.resource == "anime" }

        await harness.service.session.applySession(userId: Self.userB, email: "b@example.com")
        slow.open()

        #expect(await exportA.value == nil)
        #expect(harness.server.stoppedRequests.isEmpty, "the title answer was delivered")
        await harness.tearDown()
    }

    @Test("Parse cache is keyed by user and cleared on A -> B; A's late parse never publishes into B",
          arguments: LateAnswer.allCases, AccountHandOver.allCases)
    func lateParseOfPreviousAccountIsDropped(answer: LateAnswer, handOver: AccountHandOver) async throws {
        let hold = HoldFirst()
        let harness = try PublicDataHarness { request in
            guard request.path == "/functions/v1/concierge-parse" else { return .emptyArray }
            guard edgeText(request) == "naruto" else { return .json(Self.parseJSON) }
            switch answer {
            case .success: return hold.answer(.json(Self.parseJSON))
            case .failure: return hold.answer(.json(#"{"error":"unavailable"}"#, status: 503))
            }
        }
        let service = harness.service
        let imports = service.imports
        func parseRequests() -> Int { harness.server.requests.filter { $0.path == "/functions/v1/concierge-parse" }.count }
        await service.session.applySession(userId: Self.userA, email: "a@example.com")

        // A's warm entry: a second identical parse is served from the cache.
        _ = try await imports.conciergeParse(text: "bleach")
        _ = try await imports.conciergeParse(text: "bleach")
        #expect(parseRequests() == 1)
        #expect(imports.conciergeParseCache.keys.allSatisfy { $0.contains(Self.userA) })

        let parseA = Task.immediate { @MainActor in try await imports.conciergeParse(text: "naruto") }
        _ = await harness.server.waitForRequest { edgeText($0) == "naruto" }
        switch handOver {
        case .funnelSwitch:
            await service.session.applySession(userId: Self.userB, email: "b@example.com")
            _ = await harness.server.waitForStop { edgeText($0) == "naruto" }
            #expect(imports.conciergeParseCache.isEmpty, "cleared on A -> B")
        case .contextOnly:
            _ = service.accountSession.begin(userId: Self.userB)
        }
        hold.gate.open()
        await #expect(throws: CancellationError.self) { _ = try await parseA.value }
        #expect(!imports.conciergeParseCache.keys.contains { $0.contains("naruto") }, "A's late parse is never cached")
        if handOver == .contextOnly {
            #expect(harness.server.stoppedRequests.isEmpty, "the answer was delivered")
        }

        // B's own parse of the same text is B's request, never A's cached entry.
        _ = try await imports.conciergeParse(text: "bleach")
        #expect(parseRequests() == 3)
        #expect(imports.conciergeParseCache.keys.contains { $0.contains(Self.userB) && $0.contains("bleach") })
        await harness.tearDown()
    }

    enum EdgeCall: String, CaseIterable, Sendable {
        case parse, apply, undo, aniListPreview, aniListImport

        var path: String {
            switch self {
            case .parse: return "/functions/v1/concierge-parse"
            case .apply: return "/functions/v1/concierge-apply"
            case .undo: return "/functions/v1/concierge-undo"
            case .aniListPreview, .aniListImport: return "/functions/v1/concierge-import-anilist"
            }
        }

        var okBody: String {
            switch self {
            case .parse: return ImportsContractTests.parseJSON
            case .apply, .undo: return #"{"success":true,"sessionId":"s1"}"#
            case .aniListPreview, .aniListImport: return #"{"success":true,"username":"kuro_fan"}"#
            }
        }

        /// The exact JSON body the client sends (sorted keys).
        var expectedBody: String {
            switch self {
            case .parse:
                return #"{"clarification":{"status":"COMPLETED"},"limitPerItem":15,"scope":"anime","text":"Frieren ep 3"}"#
            case .apply:
                // The idempotency key is generated per call, so the apply assertion checks it separately.
                return #"{"items":[{"mediaId":42,"mediaType":"ANIME","progress":3,"status":"CURRENT"}]}"#
            case .undo:
                return #"{"sessionId":"s1"}"#
            case .aniListPreview:
                return #"{"maxItems":400,"mode":"preview","statuses":["CURRENT","COMPLETED","PLANNING"],"types":["ANIME","MANGA"],"username":"kuro_fan"}"#
            case .aniListImport:
                return #"{"maxItems":25,"mode":"import","statuses":["COMPLETED"],"text":"Frieren","types":["ANIME"],"username":"kuro_fan"}"#
            }
        }

        @MainActor
        func call(_ imports: ImportsService) async throws {
            switch self {
            case .parse:
                _ = try await imports.conciergeParse(text: "Frieren ep 3", scope: .anime, limitPerItem: 99, clarification: ["status": "COMPLETED"])
            case .apply:
                _ = try await imports.conciergeApply(items: [["mediaType": "ANIME", "mediaId": 42, "status": "CURRENT", "progress": 3]])
            case .undo:
                _ = try await imports.conciergeUndo(sessionId: "s1")
            case .aniListPreview:
                _ = try await imports.conciergePreviewAniListImport(username: "  kuro_fan ", maxItems: 1_000)
            case .aniListImport:
                _ = try await imports.conciergeImportAniList(
                    username: "kuro_fan", types: ["ANIME"], statuses: ["COMPLETED"], maxItems: 3, cachedText: "Frieren"
                )
            }
        }
    }

    @Test("Request shape: method, path and exact body of parse/apply/undo/AniList preview/import; 429 maps to the typed rate-limit error with Retry-After",
          arguments: EdgeCall.allCases)
    func edgeRequestShapes(call: EdgeCall) async throws {
        let limited = Mutex(false)
        let harness = try PublicDataHarness { request in
            guard request.path == call.path else { return .emptyArray }
            return limited.withLock { $0 } ? Self.rateLimited : .json(call.okBody)
        }
        let imports = harness.service.imports

        try await call.call(imports)
        let requests = harness.server.requests.filter { $0.path == call.path }
        #expect(requests.count == 1, "\(requests)")
        let request = try #require(requests.first)
        #expect(request.method == "POST")
        if call == .apply {
            var object = try #require(request.jsonObject)
            let key = try #require(object["idempotencyKey"] as? String)
            #expect(ImportApplyIdentity.isValid(key))
            object.removeValue(forKey: "idempotencyKey")
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            #expect(String(data: data, encoding: .utf8) == call.expectedBody)
        } else {
            #expect(request.canonicalBody == call.expectedBody)
        }

        limited.withLock { $0 = true }
        imports.conciergeParseCache.removeAll()
        await #expect(throws: ConciergeGuardrailsError.rateLimited(retryAfterSeconds: 30)) { try await call.call(imports) }
        #expect(harness.server.requests.filter { $0.path == call.path }.count == 2, "a 429 is not retried")
        await harness.tearDown()
    }

    @Test("A's apply/Undo finishing after B signed in: nothing handed out (CancellationError), no Library refresh, B's tracking copies kept",
          arguments: [EdgeCall.apply, EdgeCall.undo], LateAnswer.allCases)
    func lateServerWriteOfPreviousAccountIsDropped(call: EdgeCall, answer: LateAnswer) async throws {
        let hold = HoldFirst()
        let harness = try FacadeHarness()
        harness.server.respond { request in
            guard request.path == call.path else { return .emptyArray }
            return hold.answer(answer == .success ? .json(call.okBody) : .json(#"{"error":"boom"}"#, status: 500))
        }
        await harness.signIn()
        let service = harness.service
        let imports = service.imports
        let lateWrite = Task.immediate { @MainActor in try await call.call(imports) }
        _ = await harness.server.waitForRequest { $0.path == call.path }

        // B signs in (A's write is a credential lease of A: the switch cancels it, F33) and reads its lists.
        await service.session.applySession(userId: Self.userB, email: "b@example.com")
        await service.libraryActions.libraryRefreshTask?.value
        #expect(harness.fetchAllCount == 2)
        imports.conciergeParseCache["concierge_parse|\(Self.userB)|seed"] = .init(
            value: try LifecycleFixtures.decode(ConciergeParseResponse.self, Self.parseJSON), storedAt: Date()
        )
        hold.gate.open()

        await #expect(throws: CancellationError.self) { try await lateWrite.value }
        #expect(harness.server.stoppedRequests.contains { $0.path == call.path }, "A's write is a credential lease of A: the switch cancels it (F33)")
        await service.libraryActions.libraryRefreshTask?.value
        #expect(harness.fetchAllCount == 2, "no refresh for A's write")
        #expect(imports.conciergeParseCache.count == 1, "B's parse cache is not dropped")
        await harness.tearDown()
    }
}

// MARK: - Concierge

@MainActor
@Suite("Assistant: Concierge", .timeLimit(.minutes(1)))
struct ConciergeContractTests {
    static let userA = LifecycleFixtures.userA
    static let userB = LifecycleFixtures.userB
    nonisolated static let recommendJSON = #"{"success":true,"items":[{"mediaType":"ANIME","mediaId":101,"title":"A pick"}]}"#

    @Test("Recommend cache is keyed by user and cleared on A -> B; A's late answer never publishes into B",
          arguments: LateAnswer.allCases, AccountHandOver.allCases)
    func lateRecommendOfPreviousAccountIsDropped(answer: LateAnswer, handOver: AccountHandOver) async throws {
        let hold = HoldFirst()
        let harness = try PublicDataHarness { request in
            guard request.path == "/functions/v1/concierge-recommend" else { return .emptyArray }
            guard edgeText(request) == "dark fantasy" else { return .json(Self.recommendJSON) }
            switch answer {
            case .success: return hold.answer(.json(Self.recommendJSON))
            case .failure: return hold.answer(.json(#"{"error":"unavailable"}"#, status: 503))
            }
        }
        let service = harness.service
        let concierge = service.concierge
        func recommendRequests() -> [RecordedRequest] {
            harness.server.requests.filter { $0.path == "/functions/v1/concierge-recommend" }
        }
        await service.session.applySession(userId: Self.userA, email: "a@example.com")

        // A's warm entry: a second identical request is served from the cache; the body is the contract.
        _ = try await concierge.conciergeRecommend(text: "Cozy ", scope: .both, limit: 8)
        _ = try await concierge.conciergeRecommend(text: "Cozy ", scope: .both, limit: 8)
        #expect(recommendRequests().count == 1)
        #expect(recommendRequests().first?.canonicalBody == #"{"limit":8,"narrate":true,"scope":"both","text":"Cozy "}"#)

        let recommendA = Task.immediate { @MainActor in try await concierge.conciergeRecommend(text: "dark fantasy") }
        _ = await harness.server.waitForRequest { edgeText($0) == "dark fantasy" }
        switch handOver {
        case .funnelSwitch:
            await service.session.applySession(userId: Self.userB, email: "b@example.com")
            _ = await harness.server.waitForStop { edgeText($0) == "dark fantasy" }
            #expect(concierge.conciergeRecommendCache.isEmpty, "cleared on A -> B")
        case .contextOnly:
            _ = service.accountSession.begin(userId: Self.userB)
        }
        hold.gate.open()
        await #expect(throws: CancellationError.self) { _ = try await recommendA.value }
        #expect(!concierge.conciergeRecommendCache.keys.contains { $0.contains("dark fantasy") }, "A's late answer is never cached")
        if handOver == .contextOnly {
            #expect(harness.server.stoppedRequests.isEmpty, "the answer was delivered")
        }

        // B's own request for the same text is B's, never A's cached picks.
        _ = try await concierge.conciergeRecommend(text: "Cozy ", scope: .both, limit: 8)
        #expect(recommendRequests().count == 3)
        #expect(concierge.conciergeRecommendCache.keys.contains { $0.contains(Self.userB) })
        await harness.tearDown()
    }

    @Test("Request shape: the parse warmup and the retrieval feedback (empty optionals left out; a failed send never throws)")
    func warmupAndFeedbackRequestShapes() async throws {
        let failFeedback = Mutex(false)
        let harness = try PublicDataHarness { request in
            switch request.path {
            case "/functions/v1/concierge-parse": return .json(#"{"ok":true}"#)
            case "/functions/v1/concierge-retrieve-feedback":
                return failFeedback.withLock { $0 } ? .json(#"{"error":"boom"}"#, status: 500) : .json(#"{"ok":true}"#)
            default: return .emptyArray
            }
        }
        let concierge = harness.service.concierge

        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")
        await concierge.conciergeWarmup(priority: .userInitiated)
        await concierge.conciergeRetrieveFeedback(
            query: "Frieren", locale: "de", selectedEntityId: "anime:52991", accepted: false, rejectedReason: "wrong_title"
        )
        await concierge.conciergeRetrieveFeedback(query: "cozy", locale: "en", selectedEntityId: "", accepted: true)
        failFeedback.withLock { $0 = true }
        await concierge.conciergeRetrieveFeedback(query: "cozy", locale: "en", selectedEntityId: nil, accepted: true)

        let warmups = harness.server.requests.filter { $0.path == "/functions/v1/concierge-parse" }
        #expect(warmups.count == 1)
        let warmup = try #require(warmups.first)
        #expect(warmup.method == "POST" && warmup.query("warmup") == "true" && warmup.canonicalBody == #"{"text":""}"#)
        let feedback = harness.server.requests.filter { $0.path == "/functions/v1/concierge-retrieve-feedback" }
        #expect(feedback.allSatisfy { $0.method == "POST" })
        #expect(feedback.map(\.canonicalBody) == [
            #"{"accepted":false,"locale":"de","query":"Frieren","rejected_reason":"wrong_title","selected_entity_id":"anime:52991"}"#,
            #"{"accepted":true,"locale":"en","query":"cozy"}"#,
            #"{"accepted":true,"locale":"en","query":"cozy"}"#,
        ])
        await harness.tearDown()
    }
}

// MARK: - Taste

@MainActor
@Suite("Assistant: Taste", .timeLimit(.minutes(1)))
struct TasteContractTests {
    static let userA = LifecycleFixtures.userA
    static let userB = LifecycleFixtures.userB
    nonisolated static let signalRPC = "rpc/record_taste_deck_signal"

    nonisolated static func action(_ request: RecordedRequest) -> String? {
        request.jsonObject?["p_action"] as? String
    }

    nonisolated static func mediaId(_ request: RecordedRequest) -> Int? {
        request.jsonObject?["p_media_id"] as? Int
    }

    /// "<action> <id>" of every signal request, in order.
    static func signals(_ server: StubServer) -> [String] {
        server.requests.filter { $0.resource == signalRPC }.map { "\(action($0) ?? "?") \(mediaId($0) ?? -1)" }
    }

    nonisolated static let ok = StubResponse.json(#"{"ok":true}"#)
    nonisolated static let unavailable = StubResponse.json(#"{"message":"unavailable"}"#, status: 503)

    enum PersonalRead: String, CaseIterable, Sendable {
        case personalizedNewToYou, deckBatch, tasteProfile

        var resource: String {
            switch self {
            case .personalizedNewToYou: return "rpc/fetch_personalized_new_to_you"
            case .deckBatch: return "rpc/fetch_taste_deck_batch"
            case .tasteProfile: return "rpc/fetch_my_taste_profile"
            }
        }

        var body: String {
            switch self {
            case .personalizedNewToYou, .deckBatch:
                return #"[{"media_type":"ANIME","media_id":101,"title":"A's pick"}]"#
            case .tasteProfile:
                return #"[{"vector":{"genres":{"Drama":0.9},"confidence":0.2,"event_count":20},"updated_at":null}]"#
            }
        }

        /// What the read handed out (nil = nothing).
        @MainActor
        func read(_ taste: TasteStore) async -> String? {
            switch self {
            case .personalizedNewToYou:
                return await taste.fetchPersonalizedNewToYou(limit: 20, mediaType: "ANIME").map { "\($0.map(\.mediaId))" }
            case .deckBatch:
                return await taste.fetchTasteDeckBatch(limit: 12).map { "\($0.map(\.mediaId))" }
            case .tasteProfile:
                return await taste.fetchMyTasteProfile().map { "\($0.topGenres.map(\.name))" }
            }
        }
    }

    @Test("Personalised reads (NEW TO YOU rail, deck batch, taste profile): A's answer arriving after B signed in is not handed out",
          arguments: PersonalRead.allCases)
    func personalisedReadsOfEndedAccountAreDropped(read: PersonalRead) async throws {
        // Control: the current account gets its rows.
        let control = try PublicDataHarness { request in
            request.resource == read.resource ? StubResponse.json(read.body) : .emptyArray
        }
        await control.service.session.applySession(userId: Self.userA, email: "a@example.com")
        #expect(await read.read(control.service.taste) != nil)
        await control.tearDown()

        let slow = StubGate()
        let harness = try PublicDataHarness { request in
            request.resource == read.resource ? StubResponse.json(read.body).held(by: slow) : .emptyArray
        }
        let service = harness.service
        let taste = service.taste
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        let readA = Task.immediate { @MainActor in await read.read(taste) }
        _ = await harness.server.waitForRequest { $0.resource == read.resource }
        // B signs in; nothing tracks this read, so A's answer is delivered after B is current.
        await service.session.applySession(userId: Self.userB, email: "b@example.com")
        slow.open()

        #expect(await readA.value == nil)
        #expect(harness.server.stoppedRequests.isEmpty, "the answer was delivered")
        await harness.tearDown()
    }

    @Test("Outbox: a newer signal for a card replaces its queued or in-flight one; a superseded signal is never delivered after its successor")
    func supersededSignalIsNeverDeliveredLater() async throws {
        let loveOutage = Mutex(true)
        let firstLove8 = HoldFirst()
        let harness = try PublicDataHarness { request in
            guard request.resource == Self.signalRPC else { return .emptyArray }
            if Self.action(request) == "love", Self.mediaId(request) == 8 {
                return firstLove8.answer(Self.unavailable)
            }
            if Self.action(request) == "love", loveOutage.withLock({ $0 }) { return Self.unavailable }
            return Self.ok
        }
        let service = harness.service
        let taste = service.taste
        await service.session.applySession(userId: Self.userA, email: "a@example.com")

        // Queued: 'love 7' fails and waits; 'retract 7' replaces it and is delivered.
        await taste.submitSignal(mediaType: "ANIME", mediaId: 7, action: .love)?.value
        #expect(taste.pendingSignals.map(\.action) == [.love])
        #expect(harness.server.requests.first { $0.resource == Self.signalRPC }?.canonicalBody
                == #"{"p_action":"love","p_media_id":7,"p_media_type":"ANIME"}"#)
        await taste.submitSignal(mediaType: "ANIME", mediaId: 7, action: .retract)?.value
        #expect(taste.pendingSignals.isEmpty)
        loveOutage.withLock { $0 = false }
        await taste.drainSignalOutbox(force: true)?.value
        #expect(Self.signals(harness.server) == ["love 7", "retract 7"])

        // In flight: 'love 8' is on the wire when 'retract 8' replaces it; its late failure is not
        // re-queued and 'retract 8' is delivered once.
        let delivery = taste.submitSignal(mediaType: "ANIME", mediaId: 8, action: .love)
        _ = await harness.server.waitForRequest { Self.action($0) == "love" && Self.mediaId($0) == 8 }
        let joined = taste.submitSignal(mediaType: "ANIME", mediaId: 8, action: .retract)
        #expect(joined == delivery, "a second trigger joins the running delivery")
        firstLove8.gate.open()
        await delivery?.value
        #expect(Self.signals(harness.server) == ["love 7", "retract 7", "love 8", "retract 8"])
        #expect(taste.pendingSignals.isEmpty)
        #expect(!taste.signalsNeedAttention)
        await harness.tearDown()
    }

    @Test("Outbox is bounded: at most maxPendingSignals entries (oldest dropped), finite attempts with backoff")
    func outboxIsBounded() async throws {
        let server = StubServer()
        server.respond { request in request.resource == Self.signalRPC ? Self.unavailable : .emptyArray }
        defer { server.shutDown() }
        let clock = TestClock()
        let accountSession = AccountSessionCoordinator()
        _ = accountSession.begin(userId: Self.userA)
        let taste = TasteStore(
            client: StubSupabase.makeClient(server: server),
            accountSession: accountSession,
            libraryHook: LibraryRefreshHook(),
            now: { clock.now },
            retryBaseDelay: 10
        )
        let max = TasteStore.maxPendingSignals

        // Size: two more signals than the capacity; the two oldest are dropped.
        for id in 1...(max + 2) {
            taste.submitSignal(mediaType: "ANIME", mediaId: id, action: .skip)
        }
        #expect(taste.pendingSignals.count == max)
        #expect(taste.pendingSignals.first?.card == MediaKey(kind: .anime, id: 3))
        #expect(taste.signalsNeedAttention, "a dropped signal raises the banner")
        await taste.drainTask?.value
        #expect(Self.signals(server).count == max, "one attempt per queued entry")
        #expect(taste.pendingSignals.allSatisfy { $0.failures == 1 })

        // Attempts: one entry, retried only after its backoff (10 s, 20 s, ...), dropped after the cap.
        let single = TasteStore(
            client: StubSupabase.makeClient(server: server),
            accountSession: accountSession,
            libraryHook: LibraryRefreshHook(),
            now: { clock.now },
            retryBaseDelay: 10
        )
        let before = Self.signals(server).count
        func attempts() -> Int { Self.signals(server).count - before }
        await single.submitSignal(mediaType: "MANGA", mediaId: 7, action: .love)?.value
        #expect(attempts() == 1)
        #expect(!single.signalsNeedAttention)
        await single.drainSignalOutbox()?.value
        #expect(attempts() == 1, "not before the backoff")
        clock.now += 10
        await single.drainSignalOutbox()?.value
        #expect(attempts() == 2)
        clock.now += 19
        await single.drainSignalOutbox()?.value
        #expect(attempts() == 2, "the backoff doubles")
        clock.now += 1
        await single.drainSignalOutbox()?.value
        #expect(attempts() == 3)
        #expect(single.signalsNeedAttention, "third failure")
        await single.drainSignalOutbox(force: true)?.value
        await single.drainSignalOutbox(force: true)?.value
        #expect(attempts() == TasteStore.maxDeliveryAttempts)
        #expect(single.pendingSignals.isEmpty, "dropped after the last attempt")
        #expect(single.drainSignalOutbox(force: true) == nil)
        #expect(attempts() == TasteStore.maxDeliveryAttempts)
    }

    enum SessionEnd: String, CaseIterable, Sendable { case switchToB, signOut }

    @Test("Outbox is cleared on A -> B and on sign-out; A's in-flight delivery is cancelled and B's signals are B's",
          arguments: SessionEnd.allCases)
    func outboxClearedOnAccountTransition(end: SessionEnd) async throws {
        let hold = HoldFirst()
        let harness = try PublicDataHarness { request in
            guard request.resource == Self.signalRPC else { return .emptyArray }
            switch (Self.action(request), Self.mediaId(request)) {
            case ("love", 7): return Self.unavailable
            case ("skip", 8): return hold.answer(Self.ok)
            default: return Self.ok
            }
        }
        let service = harness.service
        let taste = service.taste
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        taste.submitSignal(mediaType: "ANIME", mediaId: 7, action: .love)
        taste.submitSignal(mediaType: "ANIME", mediaId: 8, action: .skip)
        _ = await harness.server.waitForRequest { Self.action($0) == "skip" }
        #expect(taste.pendingSignals.map(\.card.id) == [7, 8])

        switch end {
        case .switchToB: await service.session.applySession(userId: Self.userB, email: "b@example.com")
        case .signOut: await service.session.endSession()
        }
        #expect(taste.pendingSignals.isEmpty)
        #expect(!taste.signalsNeedAttention)
        #expect(taste.drainTask == nil)
        _ = await harness.server.waitForStop { Self.action($0) == "skip" }
        hold.gate.open()

        switch end {
        case .switchToB:
            await taste.submitSignal(mediaType: "ANIME", mediaId: 9, action: .known)?.value
            #expect(Self.signals(harness.server) == ["love 7", "skip 8", "known 9"])
        case .signOut:
            #expect(taste.submitSignal(mediaType: "ANIME", mediaId: 9, action: .known) == nil, "nothing is queued while signed out")
            #expect(Self.signals(harness.server) == ["love 7", "skip 8"])
        }
        #expect(taste.pendingSignals.isEmpty)
        await harness.tearDown()
    }

    @Test("Stale guard: A's delivery result arriving after B became current (nothing cancelled it) changes no queue entry, fires no Library hook and stops the delivery",
          arguments: LateAnswer.allCases)
    func lateDeliveryOfPreviousAccountIsDropped(answer: LateAnswer) async throws {
        let hold = HoldFirst()
        let harness = try FacadeHarness()
        harness.server.respond { request in
            guard request.resource == Self.signalRPC else { return .emptyArray }
            return hold.answer(answer == .success ? Self.ok : Self.unavailable)
        }
        let service = harness.service
        let taste = service.taste
        await harness.signIn()
        #expect(harness.fetchAllCount == 1)
        let delivery = taste.submitSignal(mediaType: "ANIME", mediaId: 7, action: .love)
        taste.submitSignal(mediaType: "ANIME", mediaId: 8, action: .skip)
        _ = await harness.server.waitForRequest { $0.resource == Self.signalRPC }

        _ = service.accountSession.begin(userId: Self.userB)
        hold.gate.open()
        await delivery?.value

        #expect(harness.server.stoppedRequests.isEmpty, "the answer was delivered")
        #expect(Self.signals(harness.server) == ["love 7"], "the delivery stopped")
        #expect(taste.pendingSignals.map(\.card.id) == [7, 8])
        #expect(taste.pendingSignals.allSatisfy { $0.failures == 0 })
        await service.libraryActions.libraryRefreshTask?.value
        #expect(harness.fetchAllCount == 1, "no Library refresh for B")
        await harness.tearDown()
    }

    /// A store over `server` on `accountSession`, with a hand-advanced clock and a 10 s first backoff
    /// (backed-off entries never come due by themselves while a test runs).
    static func store(
        server: StubServer,
        accountSession: AccountSessionCoordinator,
        clock: TestClock,
        libraryHook: LibraryRefreshHook? = nil
    ) -> TasteStore {
        TasteStore(
            client: StubSupabase.makeClient(server: server),
            accountSession: accountSession,
            libraryHook: libraryHook ?? LibraryRefreshHook(),
            now: { clock.now },
            retryBaseDelay: 10
        )
    }

    @Test("Outbox drained on the next success: a delivered signal retries the backed-off ones at once (no foreground needed)")
    func nextSuccessDrainsBackedOffSignals() async throws {
        let outage = Mutex(true)
        let server = StubServer()
        server.respond { request in
            guard request.resource == Self.signalRPC else { return .emptyArray }
            return outage.withLock { $0 } ? Self.unavailable : Self.ok
        }
        defer { server.shutDown() }
        let accountSession = AccountSessionCoordinator()
        _ = accountSession.begin(userId: Self.userA)
        let taste = Self.store(server: server, accountSession: accountSession, clock: TestClock())
        taste.submitSignal(mediaType: "ANIME", mediaId: 7, action: .skip)
        await taste.submitSignal(mediaType: "ANIME", mediaId: 8, action: .skip)?.value
        #expect(taste.pendingSignals.allSatisfy { $0.failures == 1 }, "both wait for their backoff")

        // The next commit (a plain, non-forced trigger) is delivered; the backed-off entries follow.
        outage.withLock { $0 = false }
        await taste.submitSignal(mediaType: "ANIME", mediaId: 9, action: .known)?.value

        #expect(Self.signals(server) == ["skip 7", "skip 8", "known 9", "skip 7", "skip 8"])
        #expect(taste.pendingSignals.isEmpty)
        #expect(!taste.signalsNeedAttention)
    }

    @Test("Outbox drained once on foreground: one registration per store, one forced drain per foreground notification, each queued signal delivered once; a delivered 'love' fires the Library hook once")
    func foregroundNotificationDrainsOnce() async throws {
        let outage = Mutex(true)
        let harness = try FacadeHarness()
        harness.server.respond { request in
            guard request.resource == Self.signalRPC else { return .emptyArray }
            return outage.withLock { $0 } ? Self.unavailable : Self.ok
        }
        await harness.signIn()
        let hook = LibraryRefreshHook()
        hook.connect(to: harness.service.libraryActions)
        let taste = Self.store(
            server: harness.server, accountSession: harness.service.accountSession, clock: TestClock(), libraryHook: hook
        )
        let center = NotificationCenter()
        let foreground = Notification.Name("kuro.tests.foreground")
        // A second install replaces the first, also while the caller still holds the first one.
        let first = taste.installForegroundDrain(notificationCenter: center, name: foreground)
        let registration = taste.installForegroundDrain(notificationCenter: center, name: foreground)

        taste.submitSignal(mediaType: "ANIME", mediaId: 7, action: .love)
        await taste.submitSignal(mediaType: "MANGA", mediaId: 7, action: .skip)?.value
        #expect(taste.pendingSignals.map(\.card) == [MediaKey(kind: .anime, id: 7), MediaKey(kind: .manga, id: 7)])
        #expect(harness.fetchAllCount == 1, "a failed 'love' fires no hook")

        outage.withLock { $0 = false }
        center.post(name: foreground, object: nil)
        #expect(taste.foregroundDrainCount == 1, "the second install replaced the first: one drain per notification")
        await taste.drainTask?.value

        #expect(Self.signals(harness.server) == ["love 7", "skip 7", "love 7", "skip 7"])
        #expect(taste.pendingSignals.isEmpty)
        #expect(!taste.signalsNeedAttention)
        await harness.service.libraryActions.libraryRefreshTask?.value
        #expect(harness.fetchAllCount == 2, "one fresh Library read for the delivered 'love'")

        // A cancelled registration no longer drains.
        registration.cancel()
        center.post(name: foreground, object: nil)
        #expect(taste.foregroundDrainCount == 1)
        first.cancel()

        // The observer does not keep its store alive; posting after the store went away is harmless.
        weak var released: TasteStore?
        do {
            let temporary = Self.store(server: harness.server, accountSession: harness.service.accountSession, clock: TestClock())
            temporary.installForegroundDrain(notificationCenter: center, name: foreground)
            released = temporary
        }
        #expect(released == nil)
        center.post(name: foreground, object: nil)
        #expect(Self.signals(harness.server).count == 4)
        await harness.tearDown()
    }

    @Test("Request shape: deck batch, personalised NEW TO YOU, taste profile, realm copy and a direct signal through the stub")
    func tasteRequestShapes() async throws {
        let harness = try PublicDataHarness { request in
            request.resource == Self.signalRPC ? Self.ok : .emptyArray
        }
        let taste = harness.service.taste

        #expect(await taste.fetchTasteDeckBatch(limit: 7)?.isEmpty == true)
        #expect(await taste.fetchPersonalizedNewToYou(limit: 5, mediaType: "MANGA")?.isEmpty == true)
        #expect(await taste.fetchMyTasteProfile() == nil, "zero rows: profile not computed yet")
        #expect(await taste.fetchRealmMeta().isEmpty)
        #expect(await taste.recordTasteDeckSignal(mediaType: "manga", mediaId: 3, action: .known))

        func only(_ resource: String) throws -> RecordedRequest {
            let requests = harness.requests(to: resource)
            #expect(requests.count == 1, "\(resource): \(requests)")
            return try #require(requests.first)
        }
        let deck = try only("rpc/fetch_taste_deck_batch")
        #expect(deck.method == "POST" && deck.canonicalBody == #"{"p_limit":7}"#)
        let newToYou = try only("rpc/fetch_personalized_new_to_you")
        #expect(newToYou.method == "POST" && newToYou.canonicalBody == #"{"p_limit":5,"p_media_type":"MANGA"}"#)
        let profile = try only("rpc/fetch_my_taste_profile")
        #expect(profile.method == "POST" && profile.canonicalBody == nil)
        let realms = try only("realm_meta")
        #expect(realms.method == "GET" && realms.query("select") == "*" && realms.query("order") == "sort.asc.nullslast")
        let signal = try only(Self.signalRPC)
        #expect(signal.method == "POST" && signal.canonicalBody == #"{"p_action":"known","p_media_id":3,"p_media_type":"MANGA"}"#)
        await harness.tearDown()
    }
}

/// A clock the outbox tests advance by hand (no sleeps).
@MainActor
final class TestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

// MARK: - DeviceIntelligence

@MainActor
@Suite("Assistant: composition")
struct AssistantCompositionTests {
    @Test("DeviceIntelligence: every object graph builds its own FM service (a testing graph never shares the app's), and the session funnel clears exactly the assistant owners the composition injects")
    func viewsGetTheInjectedFMService() throws {
        // Views read the owners from the environment (`KuroApp` injects the composition's instances);
        // the session funnel's account-scoped list must hold those same instances.
        let composition = AppComposition.shared
        let funnel = composition.session.accountScopedStates
        let store = try TestDefaults()
        let testing = AppComposition.testingGraph(testingUserDefaults: store.defaults, notificationCenter: FakeNotificationCenter())
        #expect(testing.deviceIntelligence !== composition.deviceIntelligence, "one FM service per object graph")
        #expect(funnel.contains { $0 === composition.imports })
        #expect(funnel.contains { $0 === composition.concierge })
        #expect(funnel.contains { $0 === composition.taste })
        store.tearDown()
    }
}

extension ImportsContractTests {
    @Test("Structured import replays its durable action after lost delivery and omits unavailable source fields")
    func structuredImportDurableReplayAndFieldAbsence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kuro-import-wire-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try LibraryImportPageJournal(directory: directory)
        let harness = try FacadeHarness()
        await harness.signIn()
        let hook = LibraryRefreshHook()
        hook.connect(to: harness.service.libraryActions)
        let imports = ImportsService(client: StubSupabase.makeClient(server: harness.server),
            accountSession: harness.service.accountSession, library: harness.service.library,
            catalog: harness.service.catalog, libraryHook: hook, importJournal: journal)
        let loseFirst = Mutex(true)
        harness.server.respond { request in
            switch request.path {
            case "/rest/v1/rpc/start_library_import_v1":
                return .json(#"{"job_id":"11111111-1111-1111-1111-111111111111","state":"running"}"#)
            case "/rest/v1/rpc/apply_import_chunk_v1":
                let lose = loseFirst.withLock { value -> Bool in let result = value; value = false; return result }
                if lose { return .failure(.networkConnectionLost) }
                return .json(#"{"added":1,"updated":0,"conflict":0,"unmatched":0}"#)
            case "/rest/v1/rpc/finish_library_import_v1":
                return .json(#"{"state":"running","counters":{"added":1},"home_revisions":{}}"#)
            default: return .emptyArray
            }
        }
        let draft = LibraryImportDraft(medium: "manga", externalId: "7", status: "reading", progress: 0,
            sourceListOptions: LibraryImportDraft.options(nil,
                unavailable: ["progress", "repeat_count", "private", "custom_lists", "hidden_from_status_lists"]))
        do {
            _ = try await imports.applyStructuredLibraryImport(provider: "myanimelist", sourceKind: "export",
                mediumFilter: "manga", drafts: [draft], exhausted: false)
            Issue.record("Expected unknown chunk delivery")
        } catch { #expect(error is URLError) }
        let counts = try await imports.applyStructuredLibraryImport(provider: "myanimelist", sourceKind: "export",
            mediumFilter: "manga", drafts: [draft], exhausted: false)
        #expect(counts.added == 1)
        let starts = harness.server.requests.filter { $0.path == "/rest/v1/rpc/start_library_import_v1" }.compactMap(\.jsonObject)
        #expect(starts.count == 2)
        #expect(starts[0]["p_idempotency_key"] as? String == starts[1]["p_idempotency_key"] as? String)
        let chunks = harness.server.requests.filter { $0.path == "/rest/v1/rpc/apply_import_chunk_v1" }.compactMap(\.body)
        #expect(chunks.count == 2)
        #expect(try JSONSerialization.jsonObject(with: chunks[0]) as? NSDictionary == JSONSerialization.jsonObject(with: chunks[1]) as? NSDictionary)
        let body = try #require(JSONSerialization.jsonObject(with: chunks[1]) as? [String: Any])
        let item = try #require((body["p_items"] as? [[String: Any]])?.first)
        for field in draft.unavailableFields { #expect(item[field] == nil) }
        #expect(item["external_id"] as? String == "7")
        #expect(item["medium"] as? String == "manga")
        await harness.tearDown()
    }
}

extension ImportsContractTests {
    @Test("Profile coordinator owns lost-response replay, failed Undo retention and stale-account rejection")
    func profileCoordinatorRetainsRecoveryAndRejectsAnotherAccount() async throws {
        let harness = try FacadeHarness()
        await harness.signIn()
        let loseApply = Mutex(true)
        harness.server.respond { request in
            switch request.path {
            case "/functions/v1/concierge-parse":
                return .json(#"{"success":true,"items":[{"raw":"Anime Seven","normalized":"anime seven","parsed":{"status":"PLANNING"},"candidates":[{"media_type":"ANIME","media_id":7,"variant_type":"main","title_raw":"Anime Seven","score":0.99}]}]}"#)
            case "/functions/v1/concierge-apply":
                let lose = loseApply.withLock { value -> Bool in let result = value; value = false; return result }
                if lose { return .failure(.networkConnectionLost) }
                return .json(#"{"success":true,"sessionId":"profile-owned-session","status":"applied","undoable":true,"applied":[{"mediaType":"ANIME","mediaId":7,"status":"PLANNING","action":"add"}]}"#)
            case "/functions/v1/concierge-undo":
                return .json(#"{"error":"Temporarily unavailable"}"#, status: 503)
            default: return .emptyArray
            }
        }
        let owner = ProfileImportCoordinator(imports: harness.service.imports, library: harness.service.library,
            collection: harness.service.collection, releases: harness.service.releases,
            flags: harness.service.flags, isGermanLocale: false)
        #expect(owner.beginAniListSelection())
        let response = try JSONDecoder().decode(ConciergeAniListImportResponse.self,
            from: Data(#"{"success":true,"text":"Anime Seven (planning)","truncated":false}"#.utf8))
        await owner.receiveAniList(response)
        #expect(owner.profileRetryOffered)
        await owner.retry()?.value
        #expect(owner.importResult?.undoSessionId == "profile-owned-session")
        #expect(!owner.profileRetryOffered)
        let applyRequests = harness.server.requests.filter { $0.path == "/functions/v1/concierge-apply" }.compactMap(\.jsonObject)
        #expect(applyRequests.count == 2)
        #expect(applyRequests[0]["idempotencyKey"] as? String == applyRequests[1]["idempotencyKey"] as? String)
        await owner.undo()?.value
        #expect(owner.importResult?.undoSessionId == "profile-owned-session")
        #expect(owner.beginAniListSelection())
        let prior = harness.server.requests.count
        await harness.signIn(Self.userB)
        await owner.receiveAniList(response)
        #expect(owner.importResult == nil)
        #expect(harness.server.requests.dropFirst(prior).allSatisfy { !$0.path.contains("concierge-") })
        owner.stop()
        await harness.tearDown()
    }
}

extension ImportsContractTests {
    @Test("Paused structured Profile preparation keeps its frozen page/action and never falls back to legacy Apply")
    func profileStructuredRetryResumesFrozenPage() async throws {
        let harness = try FacadeHarness()
        await harness.signIn()
        let loseChunk = Mutex(true)
        let foundationEnabled = Mutex(true)
        let selection = Mutex("{}")
        let phase = Mutex("preparing")
        let source = #"{"success":true,"libraryItems":[{"medium":"anime","external_id":"7","status":"current","progress":4}],"sourceExhausted":true}"#
        let outcome: @Sendable (String) -> String = { value in
            "{\"job_id\":\"22222222-2222-2222-2222-222222222222\",\"selection\":\(selection.withLock { $0 }),\"phase\":\"\(value)\",\"counts\":{\"pending\":1},\"exhausted_media\":{\"anime\":true,\"manga\":true},\"home_revisions\":{},\"projection_ready\":false,\"undo_available\":false,\"history_available\":true}"
        }
        harness.server.respond { request in
            switch request.path {
            case "/rest/v1/feature_flags":
                let enabled = foundationEnabled.withLock { $0 }
                return .json("[{\"flag_name\":\"series_foundation_v1\",\"enabled\":\(enabled),\"rollout_percentage\":100,\"target_markets\":[]}]")
            case "/functions/v1/concierge-import-anilist": return .json(source)
            case "/rest/v1/rpc/start_library_import_v2":
                if let selected = request.jsonObject?["p_selection"], let data = try? JSONSerialization.data(withJSONObject: selected) {
                    selection.withLock { $0 = String(decoding: data, as: UTF8.self) }
                }
                return .json(outcome("preparing"))
            case "/rest/v1/rpc/import_job_status_v2": return .json(outcome(phase.withLock { $0 }))
            case "/rest/v1/rpc/prepare_import_chunk_v2":
                let lose = loseChunk.withLock { value -> Bool in let result = value; value = false; return result }
                if lose { return .failure(.networkConnectionLost) }
                phase.withLock { $0 = "reviewing" }
                return .json(outcome("reviewing"))
            default: return .emptyArray
            }
        }
        let flags = FeatureFlags(userDefaults: harness.defaults, launchArguments: [])
        let flagClient = StubSupabase.makeClient(server: harness.server)
        await flags.refresh(client: flagClient, userId: Self.userA, accountSession: harness.service.accountSession)
        let owner = ProfileImportCoordinator(imports: harness.service.imports, library: harness.service.library,
            collection: harness.service.collection, releases: harness.service.releases, flags: flags, isGermanLocale: false)
        var response = try JSONDecoder().decode(ConciergeAniListImportResponse.self,
            from: Data("{\"success\":true,\"username\":\"fixture-\(UUID().uuidString)\",\"libraryItems\":[],\"text\":\"Cached display is not authoritative\"}".utf8))
        response.types = ["ANIME", "MANGA"]
        #expect(owner.beginAniListSelection())
        await owner.receiveAniList(response)
        #expect(owner.profileRetryOffered)
        foundationEnabled.withLock { $0 = false }
        await flags.refresh(client: flagClient, userId: Self.userA, accountSession: harness.service.accountSession)
        await owner.retry()?.value
        #expect(owner.profileRetryOffered)
        #expect(harness.server.requests.filter { $0.path == "/rest/v1/rpc/prepare_import_chunk_v2" }.count == 1)
        foundationEnabled.withLock { $0 = true }
        await flags.refresh(client: flagClient, userId: Self.userA, accountSession: harness.service.accountSession)
        await owner.retry()?.value
        #expect(!owner.profileRetryOffered)
        #expect(owner.workflowJob?.phase == .reviewing)
        #expect(harness.server.requests.filter { $0.path == "/functions/v1/concierge-import-anilist" }.count == 1)
        #expect(harness.server.requests.filter { $0.path == "/rest/v1/rpc/start_library_import_v2" }.count == 1)
        #expect(harness.server.requests.allSatisfy { !$0.path.contains("concierge-parse") && !$0.path.contains("concierge-apply") && !$0.path.contains("apply_import_chunk") })
        let chunks = harness.server.requests.filter { $0.path == "/rest/v1/rpc/prepare_import_chunk_v2" }.compactMap(\.jsonObject)
        try #require(chunks.count == 2)
        #expect(chunks[0] as NSDictionary == chunks[1] as NSDictionary)
        owner.stop()
        await harness.tearDown()
    }
}
