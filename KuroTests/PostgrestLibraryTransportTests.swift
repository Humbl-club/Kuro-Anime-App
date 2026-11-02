//
//  PostgrestLibraryTransportTests.swift
//  KuroTests
//
//  The app's SDK binding of the list adapter, driven through `SupabaseLibraryBackend` (the only code
//  that builds requests) and the REAL supabase-swift 2.54.1 client. Every request is answered
//  in-process by StubPostgREST; the assertions are on the HTTP requests the SDK actually emitted and
//  on how responses and failures come back.
//

import Testing
import Foundation
import KuroCore
import KuroLibrary
import KuroSupabase
@testable import Kuro

@Suite("PostgrestLibraryTransport: requests and responses through the real SDK", .timeLimit(.minutes(1)))
struct PostgrestLibraryTransportTests {
    static let user = LifecycleFixtures.userA
    static let account = AccountContext(userId: user, generation: 1)
    static let anime42 = MediaKey(kind: .anime, id: 42)
    static let animeColumns = "id,user_id,anime_id,list_type,progress,rating,notes,verdict,created_at,updated_at"
    static let mangaColumns = "id,user_id,manga_id,list_type,progress,rating,notes,verdict,created_at,updated_at"
    /// `2026-01-01T12:34:56.789012+00:00` / `2026-02-03T04:05:06.123456+00:00` (ListRowJSON).
    static let createdAt = Date(timeIntervalSince1970: 1_767_270_896.789012)
    static let updatedAt = Date(timeIntervalSince1970: 1_770_091_506.123456)

    static func backend(_ responder: @escaping StubServer.Responder) -> (StubServer, SupabaseLibraryBackend) {
        let server = StubServer()
        server.respond(with: responder)
        let transport = PostgrestLibraryTransport(client: StubSupabase.makeClient(server: server))
        return (server, SupabaseLibraryBackend(transport: transport))
    }

    static func isClose(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince1970 - rhs.timeIntervalSince1970) < 0.000_01
    }

    @Test("fetchAll: one paged GET per table with the exact filters; rows and microsecond timestamps decode")
    func fetchAllRequestsAndDecoding() async throws {
        let (server, backend) = Self.backend { request in
            switch request.resource {
            case "anime_user_lists":
                return ListRowJSON.response([ListRowJSON.anime(
                    42, rowId: 9, userId: Self.user, listType: "COMPLETED", progress: 12, rating: 8,
                    notes: "rewatch", verdict: "OKAY"
                )])
            case "manga_user_lists":
                return ListRowJSON.response([ListRowJSON.manga(42, rowId: 9, userId: Self.user, progress: 3)])
            default:
                return .emptyArray
            }
        }
        defer { server.shutDown() }

        let entries = try await backend.fetchAll(for: Self.account)

        let requests = server.requests
        #expect(requests.map(\.resource) == ["anime_user_lists", "manga_user_lists"])
        for (request, columns) in zip(requests, [Self.animeColumns, Self.mangaColumns]) {
            #expect(request.method == "GET")
            #expect(request.query("select") == columns)
            #expect(request.query("user_id") == "eq.\(Self.user.lowercased())", "user_id is the canonical lower-case text (F16)")
            #expect(request.query("order") == "id.asc.nullslast")
            #expect(request.query("offset") == "0")
            #expect(request.query("limit") == "1000")
            #expect(request.query("anime_id") == nil && request.query("manga_id") == nil)
        }

        #expect(entries.map(\.key) == [Self.anime42, MediaKey(kind: .manga, id: 42)])
        let anime = try #require(entries.first)
        #expect(anime.rowId == 9)
        #expect(anime.status == .completed)
        #expect(anime.progress == 12)
        #expect(anime.rating == UserRating(value: 8))
        #expect(anime.notes == "rewatch")
        #expect(anime.verdict == .okay)
        #expect(Self.isClose(anime.createdAt, Self.createdAt), "created_at: \(anime.createdAt)")
        #expect(Self.isClose(anime.updatedAt, Self.updatedAt), "updated_at: \(anime.updatedAt)")
        #expect(entries.last?.status == .current)
    }

    @Test("edit: PATCH with both filters, only the edited columns and an explicit JSON null")
    func editSendsMaskedPatch() async throws {
        let (server, backend) = Self.backend { request in
            guard request.method == "PATCH" else { return .emptyArray }
            return ListRowJSON.response([ListRowJSON.anime(42, rowId: 9, userId: Self.user, progress: 5, rating: 8)])
        }
        defer { server.shutDown() }

        let result = try await backend.edit(
            LibraryEdit(progress: .set(5), notes: .clear), key: Self.anime42, createIfMissing: nil,
            mutationId: UUID(), baseRevision: nil, account: Self.account
        )

        let request = try #require(server.requests.first)
        #expect(server.requests.count == 1)
        #expect(request.method == "PATCH")
        #expect(request.resource == "anime_user_lists")
        #expect(request.query("user_id") == "eq.\(Self.user.lowercased())")
        #expect(request.query("anime_id") == "eq.42")
        #expect(request.query("select") == Self.animeColumns)
        #expect(request.preferences.contains("return=representation"))
        #expect(request.canonicalBody == #"{"notes":null,"progress":5}"#)
        #expect(result.created == false)
        #expect(result.entry.progress == 5)
        #expect(result.entry.notes == nil)
        #expect(result.entry.rating == UserRating(value: 8))
    }

    @Test("save: POST with on_conflict + resolution=ignore-duplicates; an ignored insert reads the row back")
    func saveIsInsertIgnoringDuplicates() async throws {
        let (server, backend) = Self.backend { request in
            switch request.method {
            case "POST": return .emptyArray // the row exists: the insert is ignored
            case "GET":
                return ListRowJSON.response([ListRowJSON.anime(42, rowId: 9, userId: Self.user, listType: "COMPLETED", progress: 12)])
            default: return .emptyArray
            }
        }
        defer { server.shutDown() }

        let result = try await backend.insertIfMissing(Self.anime42, status: .planning, account: Self.account)

        let requests = server.requests
        #expect(requests.map(\.method) == ["POST", "GET"])
        let insert = try #require(requests.first)
        #expect(insert.resource == "anime_user_lists")
        #expect(insert.query("on_conflict") == "user_id,anime_id")
        #expect(insert.query("select") == Self.animeColumns)
        #expect(insert.preferences.contains("resolution=ignore-duplicates"))
        #expect(insert.preferences.contains("return=representation"))
        #expect(!insert.preferences.contains("resolution=merge-duplicates"))
        #expect(insert.canonicalBody == #"{"anime_id":42,"list_type":"PLANNING","progress":0,"user_id":"\#(Self.user.lowercased())"}"#)
        let readBack = requests[1]
        #expect(readBack.query("anime_id") == "eq.42")
        #expect(readBack.query("user_id") == "eq.\(Self.user.lowercased())")
        #expect(readBack.query("limit") == "1")
        #expect(result.created == false)
        #expect(result.entry.status == .completed)
        #expect(result.entry.progress == 12)
    }

    @Test("remove: DELETE scoped by user and the medium's own id column")
    func removeIsScopedDelete() async throws {
        let (server, backend) = Self.backend { _ in .emptyArray }
        defer { server.shutDown() }

        try await backend.remove(MediaKey(kind: .manga, id: 7), account: Self.account)

        let request = try #require(server.requests.first)
        #expect(server.requests.count == 1)
        #expect(request.method == "DELETE")
        #expect(request.resource == "manga_user_lists")
        #expect(request.query("user_id") == "eq.\(Self.user.lowercased())")
        #expect(request.query("manga_id") == "eq.7")
        #expect(request.query("anime_id") == nil)
    }

    enum ExpectedError: Sendable, Equatable {
        case notAuthenticated, invalidValue(String), retryable, unavailable

        init(_ error: LibraryError) {
            switch error {
            case .notAuthenticated: self = .notAuthenticated
            case .invalidValue(let field): self = .invalidValue(field)
            case .retryable: self = .retryable
            default: self = .unavailable
            }
        }
    }

    struct FailureCase: Sendable, CustomTestStringConvertible {
        let name: String
        let method: String
        let response: StubResponse
        let expected: ExpectedError
        var testDescription: String { name }
    }

    static let failures: [FailureCase] = [
        FailureCase(name: "401 with a PostgREST JWT error body -> notAuthenticated", method: "PATCH",
                    response: .json(#"{"code":"PGRST301","details":null,"hint":null,"message":"JWT expired"}"#, status: 401),
                    expected: .notAuthenticated),
        FailureCase(name: "401 without a JSON error body -> notAuthenticated (HTTP status)", method: "PATCH",
                    response: .text("Unauthorized", status: 401), expected: .notAuthenticated),
        // The SDK decodes any JSON body with a `message` as PostgrestError and drops the HTTP status:
        // transient PostgREST/PostgreSQL codes are classified as retryable by code (contract §3.4) ...
        FailureCase(name: "503 with PGRST003 (connection pool timeout) -> retryable", method: "PATCH",
                    response: .json(#"{"code":"PGRST003","details":null,"hint":null,"message":"Timed out acquiring connection from connection pool."}"#, status: 503),
                    expected: .retryable),
        FailureCase(name: "500 with 57014 (statement timeout) -> retryable", method: "PATCH",
                    response: .json(#"{"code":"57014","details":null,"hint":null,"message":"canceling statement due to statement timeout"}"#, status: 500),
                    expected: .retryable),
        FailureCase(name: "500 on GET with 40P01 (deadlock) -> retryable", method: "GET",
                    response: .json(#"{"code":"40P01","details":null,"hint":null,"message":"deadlock detected"}"#, status: 500),
                    expected: .retryable),
        FailureCase(name: "500 with a non-transient code (XX000) -> unavailable", method: "PATCH",
                    response: .json(#"{"code":"XX000","details":null,"hint":null,"message":"internal error"}"#, status: 500),
                    expected: .unavailable),
        // ... and a gateway 401 without a PGRST code or "JWT" in its message stays unavailable (known limitation).
        FailureCase(name: "401 with a gateway JSON body (no code) -> unavailable (status lost by the SDK)", method: "PATCH",
                    response: .json(#"{"message":"Invalid authentication credentials"}"#, status: 401),
                    expected: .unavailable),
        FailureCase(name: "23514 check violation -> invalidValue(rating)", method: "PATCH",
                    response: .json(#"{"code":"23514","details":null,"hint":null,"message":"new row for relation \"anime_user_lists\" violates check constraint \"anime_user_lists_rating_check\""}"#, status: 400),
                    expected: .invalidValue("rating")),
        FailureCase(name: "500 on PATCH -> retryable", method: "PATCH",
                    response: .text("upstream error", status: 500), expected: .retryable),
        FailureCase(name: "500 on GET (not retried by the SDK) -> retryable", method: "GET",
                    response: .text("upstream error", status: 500), expected: .retryable),
        FailureCase(name: "offline on PATCH -> retryable", method: "PATCH",
                    response: .failure(.notConnectedToInternet), expected: .retryable),
    ]

    @Test("SDK failures map to typed library errors", arguments: failures)
    func failureMapping(_ testCase: FailureCase) async throws {
        let (server, backend) = Self.backend { _ in testCase.response }
        defer { server.shutDown() }

        do {
            if testCase.method == "GET" {
                _ = try await backend.fetchAll(for: Self.account)
            } else {
                _ = try await backend.edit(
                    LibraryEdit(rating: UserRating(value: 8).map { .set($0) } ?? .unchanged), key: Self.anime42,
                    createIfMissing: nil, mutationId: UUID(), baseRevision: nil, account: Self.account
                )
            }
            Issue.record("expected \(testCase.expected)")
        } catch let error as LibraryError {
            #expect(ExpectedError(error) == testCase.expected, "got \(error)")
        }
        #expect(server.requests.count == 1, "requests: \(server.requests)")
        #expect(server.requests.first?.method == testCase.method)
    }
}
