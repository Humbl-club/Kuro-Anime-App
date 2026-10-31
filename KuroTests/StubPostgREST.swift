//
//  StubPostgREST.swift
//  KuroTests
//
//  A controlled HTTP endpoint for the real supabase-swift client: every request of a client built
//  by `StubSupabase.makeClient(server:)` is answered in-process by `StubURLProtocol` (no network).
//  Each server has its own host, so suites running in parallel never see each other's requests.
//  The server records requests exactly as the SDK sent them and answers with the test's script.
//

import Foundation
import Supabase
import Synchronization
import Testing
@testable import Kuro

/// One HTTP request as the SDK sent it.
struct RecordedRequest: Sendable, CustomStringConvertible {
    let method: String
    let path: String
    let queryItems: [URLQueryItem]
    let headers: [String: String]
    let body: Data?

    /// Table, view or `rpc/<name>` addressed under `/rest/v1/`, if any.
    var resource: String? {
        guard let range = path.range(of: "/rest/v1/") else { return nil }
        return String(path[range.upperBound...])
    }

    func query(_ name: String) -> String? {
        queryItems.first { $0.name == name }?.value
    }

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// The comma-separated `Prefer` directives.
    var preferences: Set<String> {
        Set((header("Prefer") ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    }

    /// The JSON body as a dictionary (`NSNull` for explicit nulls).
    var jsonObject: [String: Any]? {
        guard let body, !body.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }

    /// The JSON body re-serialized with sorted keys, for exact comparisons.
    var canonicalBody: String? {
        guard let body, !body.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    var isListTableWrite: Bool {
        guard let resource, resource == "anime_user_lists" || resource == "manga_user_lists" else { return false }
        return method != "GET" && method != "HEAD"
    }

    var description: String {
        let query = queryItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
        return "\(method) \(resource ?? path)?\(query) \(canonicalBody ?? "")"
    }

    /// The `sub` of the bearer token the SDK attached (the account the server attributes the request
    /// to); nil for the anon key or no bearer.
    var bearerSubject: String? {
        guard let authorization = header("Authorization"), authorization.hasPrefix("Bearer ") else { return nil }
        let token = String(authorization.dropFirst("Bearer ".count))
        return AuthCallbackGuard.jwtPayload(token)?["sub"] as? String
    }
}

/// The scripted answer to one request: an HTTP response, or a transport failure.
struct StubResponse: Sendable {
    var status: Int
    var body: Data
    var headers: [String: String] = ["Content-Type": "application/json"]
    var failure: URLError.Code? = nil
    /// When set, the answer is delivered only once the gate opens (a slow server response).
    var gate: StubGate? = nil

    static func json(_ text: String, status: Int = 200) -> StubResponse {
        StubResponse(status: status, body: Data(text.utf8))
    }

    /// This answer, held back until `gate` opens.
    func held(by gate: StubGate) -> StubResponse {
        var held = self
        held.gate = gate
        return held
    }

    static func text(_ text: String, status: Int) -> StubResponse {
        StubResponse(status: status, body: Data(text.utf8), headers: ["Content-Type": "text/plain"])
    }

    static func failure(_ code: URLError.Code) -> StubResponse {
        StubResponse(status: 0, body: Data(), failure: code)
    }

    static let emptyArray = StubResponse.json("[]")
}

/// Counts calls of a responder across the URL loading threads (`next()` is 1-based).
final class CallCounter: Sendable {
    private let count = Mutex(0)

    func next() -> Int {
        count.withLock { count in
            count += 1
            return count
        }
    }
}

/// Holds scripted answers back until the test opens it. No loading thread is blocked meanwhile:
/// the held deliveries run when `open()` is called.
final class StubGate: Sendable {
    private struct State {
        var isOpen = false
        var held: [@Sendable () -> Void] = []
    }

    private let state = Mutex(State())

    func open() {
        let held = state.withLock { state in
            state.isOpen = true
            defer { state.held = [] }
            return state.held
        }
        for deliver in held { deliver() }
    }

    /// Runs `deliver` now when the gate is open, otherwise once it opens.
    func whenOpen(_ deliver: @escaping @Sendable () -> Void) {
        let isOpen = state.withLock { state in
            if !state.isOpen { state.held.append(deliver) }
            return state.isOpen
        }
        if isOpen { deliver() }
    }
}

/// A per-test PostgREST endpoint: records requests, answers with `responder`.
final class StubServer: Sendable {
    typealias Responder = @Sendable (RecordedRequest) -> StubResponse

    private struct Waiter {
        let predicate: @Sendable (RecordedRequest) -> Bool
        let continuation: CheckedContinuation<RecordedRequest, Never>
    }

    private struct State {
        var requests: [RecordedRequest] = []
        var responder: Responder = { _ in .emptyArray }
        var waiters: [Waiter] = []
        /// Requests whose held answer was never delivered because the client stopped them.
        var stopped: [RecordedRequest] = []
        var stopWaiters: [Waiter] = []
        /// Arrivals and stops in the order they happened.
        var timeline: [TimelineEvent] = []
    }

    /// One arrival or stop, in server order (ordering assertions across requests).
    enum TimelineEvent: Sendable, CustomStringConvertible {
        case arrived(RecordedRequest)
        case stopped(RecordedRequest)

        var description: String {
            switch self {
            case .arrived(let request): return "arrived \(request)"
            case .stopped(let request): return "stopped \(request)"
            }
        }
    }

    /// Every arrival and stop, in the order the server saw them.
    var timeline: [TimelineEvent] {
        state.withLock { $0.timeline }
    }

    let host: String
    private let state = Mutex(State())

    init() {
        host = "t\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()).kuro.test"
        StubRegistry.register(self)
    }

    var baseURL: URL {
        URL(string: "https://\(host)")!
    }

    var requests: [RecordedRequest] {
        state.withLock { $0.requests }
    }

    var listTableWrites: [RecordedRequest] {
        requests.filter(\.isListTableWrite)
    }

    func respond(with responder: @escaping Responder) {
        state.withLock { $0.responder = responder }
    }

    /// Suspends until a request matching `predicate` was recorded (also one recorded earlier).
    func waitForRequest(where predicate: @escaping @Sendable (RecordedRequest) -> Bool) async -> RecordedRequest {
        await withCheckedContinuation { continuation in
            let earlier: RecordedRequest? = state.withLock { state in
                if let match = state.requests.first(where: predicate) { return match }
                state.waiters.append(Waiter(predicate: predicate, continuation: continuation))
                return nil
            }
            if let earlier { continuation.resume(returning: earlier) }
        }
    }

    /// Requests the client stopped (cancelled) while their answer was still held by a gate.
    var stoppedRequests: [RecordedRequest] {
        state.withLock { $0.stopped }
    }

    /// Suspends until a held request matching `predicate` was stopped by the client (also earlier).
    func waitForStop(where predicate: @escaping @Sendable (RecordedRequest) -> Bool) async -> RecordedRequest {
        await withCheckedContinuation { continuation in
            let earlier: RecordedRequest? = state.withLock { state in
                if let match = state.stopped.first(where: predicate) { return match }
                state.stopWaiters.append(Waiter(predicate: predicate, continuation: continuation))
                return nil
            }
            if let earlier { continuation.resume(returning: earlier) }
        }
    }

    func recordStop(_ request: RecordedRequest) {
        let ready: [Waiter] = state.withLock { state in
            state.stopped.append(request)
            state.timeline.append(.stopped(request))
            let ready = state.stopWaiters.filter { $0.predicate(request) }
            state.stopWaiters.removeAll { $0.predicate(request) }
            return ready
        }
        for waiter in ready { waiter.continuation.resume(returning: request) }
    }

    func handle(_ request: RecordedRequest) -> StubResponse {
        let (responder, ready): (Responder, [Waiter]) = state.withLock { state in
            state.requests.append(request)
            state.timeline.append(.arrived(request))
            let ready = state.waiters.filter { $0.predicate(request) }
            state.waiters.removeAll { $0.predicate(request) }
            return (state.responder, ready)
        }
        for waiter in ready { waiter.continuation.resume(returning: request) }
        return responder(request)
    }

    func shutDown() {
        StubRegistry.unregister(self)
    }
}

/// Routes intercepted requests to their server by host.
enum StubRegistry {
    private static let servers = Mutex<[String: StubServer]>([:])

    static func register(_ server: StubServer) {
        servers.withLock { $0[server.host] = server }
    }

    static func unregister(_ server: StubServer) {
        _ = servers.withLock { $0.removeValue(forKey: server.host) }
    }

    static func server(for host: String?) -> StubServer? {
        guard let host else { return nil }
        return servers.withLock { $0[host] }
    }
}

/// Answers every request of a stub session in-process; unknown hosts fail as offline.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    /// Delivery state of this load: `stopLoading` (e.g. the task was cancelled) before a held answer
    /// was delivered means it is never delivered, and the server records the stop.
    private struct Delivery {
        var stopped = false
        var delivered = false
        var held: (server: StubServer, request: RecordedRequest)? = nil
    }

    private let delivery = Mutex(Delivery())

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let server = StubRegistry.server(for: url.host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let recorded = RecordedRequest(
            method: request.httpMethod ?? "GET",
            path: components?.path ?? url.path,
            queryItems: components?.queryItems ?? [],
            headers: request.allHTTPHeaderFields ?? [:],
            body: Self.body(of: request)
        )
        let response = server.handle(recorded)
        guard let gate = response.gate else {
            deliver(response, for: url)
            return
        }
        delivery.withLock { $0.held = (server, recorded) }
        gate.whenOpen { [self] in
            let deliverNow = delivery.withLock { state -> Bool in
                guard !state.stopped else { return false }
                state.delivered = true
                return true
            }
            if deliverNow { deliver(response, for: url) }
        }
    }

    private func deliver(_ response: StubResponse, for url: URL) {
        if let failure = response.failure {
            client?.urlProtocol(self, didFailWithError: URLError(failure))
            return
        }
        guard let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1",
                                         headerFields: response.headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        let stoppedHeld = delivery.withLock { state -> (server: StubServer, request: RecordedRequest)? in
            state.stopped = true
            return state.delivered ? nil : state.held
        }
        if let stoppedHeld { stoppedHeld.server.recordStop(stoppedHeld.request) }
    }

    /// URLSession hands bodies to protocols as a stream.
    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// Session storage for test clients (no Keychain).
final class InMemoryAuthStorage: AuthLocalStorage {
    private let values = Mutex<[String: Data]>([:])

    func store(key: String, value: Data) throws { values.withLock { $0[key] = value } }
    func retrieve(key: String) throws -> Data? { values.withLock { $0[key] } }
    func remove(key: String) throws { _ = values.withLock { $0.removeValue(forKey: key) } }

    /// Everything the SDK stored (its persisted session), to put back later with `replace(with:)`.
    func snapshot() -> [String: Data] { values.withLock { $0 } }

    /// Replaces the SDK's persisted session at once (no SDK call): stands for the SDK having installed
    /// that session at exactly this point of an interleaving.
    func replace(with snapshot: [String: Data]) { values.withLock { $0 = snapshot } }
}

enum StubSupabase {
    /// The anon key every stub client sends as `apikey` (and as the bearer while signed out).
    static let anonKey = "test-anon-key"

    /// A real supabase-swift client whose every request is answered by `server`, persisting its session
    /// in `storage`.
    static func makeClient(server: StubServer, storage: InMemoryAuthStorage = InMemoryAuthStorage()) -> SupabaseClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return SupabaseClient(
            supabaseURL: server.baseURL,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                db: .init(encoder: PostgrestRequestEncoding.encoder(), decoder: ClubError.postgrestDecoder()),
                auth: .init(
                    storage: storage,
                    autoRefreshToken: false,
                    emitLocalSessionAsInitialSession: true
                ),
                global: .init(session: URLSession(configuration: configuration))
            )
        )
    }
}

/// Rows of the list tables as PostgREST returns them (`timestamptz` with microseconds).
enum ListRowJSON {
    static let createdAt = "2026-01-01T12:34:56.789012+00:00"
    static let updatedAt = "2026-02-03T04:05:06.123456+00:00"

    static func anime(
        _ animeId: Int, rowId: Int = 1, userId: String, listType: String = "WATCHING", progress: Int = 0,
        rating: Int? = nil, notes: String? = nil, verdict: String? = nil
    ) -> [String: Any] {
        row(rowId: rowId, userId: userId, mediaColumn: "anime_id", mediaId: animeId, listType: listType,
            progress: progress, rating: rating, notes: notes, verdict: verdict)
    }

    static func manga(
        _ mangaId: Int, rowId: Int = 1, userId: String, listType: String = "READING", progress: Int = 0,
        rating: Int? = nil, notes: String? = nil, verdict: String? = nil
    ) -> [String: Any] {
        row(rowId: rowId, userId: userId, mediaColumn: "manga_id", mediaId: mangaId, listType: listType,
            progress: progress, rating: rating, notes: notes, verdict: verdict)
    }

    private static func row(
        rowId: Int, userId: String, mediaColumn: String, mediaId: Int, listType: String, progress: Int,
        rating: Int?, notes: String?, verdict: String?
    ) -> [String: Any] {
        [
            "id": rowId, "user_id": userId, mediaColumn: mediaId, "list_type": listType, "progress": progress,
            "rating": rating as Any? ?? NSNull(), "notes": notes as Any? ?? NSNull(),
            "verdict": verdict as Any? ?? NSNull(), "created_at": createdAt, "updated_at": updatedAt,
        ]
    }

    static func response(_ rows: [[String: Any]], status: Int = 200) -> StubResponse {
        let data = (try? JSONSerialization.data(withJSONObject: rows)) ?? Data("[]".utf8)
        return StubResponse(status: status, body: data)
    }
}

/// Scripted list tables: reads return the seeded rows (filtered by the media column when the request
/// names one); a PATCH of a seeded row answers with that row after the body was applied (PostgREST's
/// `return=representation`); other writes answer with `writeReply`; everything else answers `[]`.
struct ListTablesScript {
    var anime: [[String: Any]] = []
    var manga: [[String: Any]] = []
    /// The answer to any other write (POST, DELETE, PATCH of an unknown row); default: no row.
    var writeReply: @Sendable (RecordedRequest) -> StubResponse = { _ in .emptyArray }

    func responder() -> StubServer.Responder {
        let anime = SendableRows(rows: anime)
        let manga = SendableRows(rows: manga)
        let writeReply = writeReply
        return { request in
            let table: (rows: [[String: Any]], column: String)
            switch request.resource {
            case "anime_user_lists": table = (anime.rows, "anime_id")
            case "manga_user_lists": table = (manga.rows, "manga_id")
            default: return .emptyArray
            }
            let filter = request.query(table.column)
            let matching = table.rows.filter { filter == nil || "eq.\($0[table.column] ?? "")" == filter }
            if request.method == "PATCH", filter != nil, var row = matching.first {
                for (key, value) in request.jsonObject ?? [:] { row[key] = value }
                return ListRowJSON.response([row])
            }
            guard request.method == "GET" else { return writeReply(request) }
            if let offset = request.query("offset"), offset != "0" { return .emptyArray }
            return ListRowJSON.response(matching)
        }
    }

    /// `[[String: Any]]` is immutable here; wrapped for capture in a `@Sendable` closure.
    private struct SendableRows: @unchecked Sendable {
        let rows: [[String: Any]]
    }
}

/// A service whose SDK client talks to a `StubServer` answering with `responder` (shared by the
/// public-data, personal-data and clubs contract tests).
@MainActor
struct PublicDataHarness {
    let server: StubServer
    let service: AppGraph
    let defaults: UserDefaults
    /// The graph's device notification center (reminder tests drive it).
    let notifications: FakeNotificationCenter
    private let suiteName: String

    init(
        notifications: FakeNotificationCenter? = nil,
        responder: @escaping StubServer.Responder = { _ in .emptyArray }
    ) throws {
        server = StubServer()
        server.respond(with: responder)
        suiteName = "kuro.tests.public-data.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        let center = notifications ?? FakeNotificationCenter()
        self.notifications = center
        service = AppComposition.testingGraph(
            testingUserDefaults: defaults,
            notificationCenter: center,
            client: StubSupabase.makeClient(server: server)
        )
    }

    func requests(to resource: String) -> [RecordedRequest] {
        server.requests.filter { $0.resource == resource }
    }

    func tearDown() async {
        await service.session.endSession()
        defaults.removePersistentDomain(forName: suiteName)
        server.shutDown()
    }
}
