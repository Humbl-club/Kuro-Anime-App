import Foundation
import KuroCore
import KuroLibrary
@testable import KuroSupabase
import Synchronization
import Testing

/// Records every request and answers with scripted outcomes in order (rows or a transport error).
/// It models PostgREST outcomes only; it never inspects or reshapes a request.
final class RecordingTransport: LibraryRowTransport {
    enum Request: Equatable, Sendable {
        case select(LibraryRowSelect)
        case patch(LibraryRowPatch)
        case insert(LibraryRowInsert)
        case delete(LibraryRowDelete)
    }

    private struct State {
        var requests: [Request] = []
        var replies: [Result<[LibraryRow], LibraryTransportError>]
    }

    private let state: Mutex<State>

    init(_ replies: [Result<[LibraryRow], LibraryTransportError>]) {
        state = Mutex(State(replies: replies))
    }

    var requests: [Request] {
        state.withLock { $0.requests }
    }

    private func reply(to request: Request) throws -> [LibraryRow] {
        let next: Result<[LibraryRow], LibraryTransportError> = state.withLock { state in
            state.requests.append(request)
            guard !state.replies.isEmpty else {
                return .failure(.server(status: 599, code: nil, message: "unscripted request"))
            }
            return state.replies.removeFirst()
        }
        return try next.get()
    }

    func select(_ request: LibraryRowSelect) async throws -> [LibraryRow] { try reply(to: .select(request)) }
    func patch(_ request: LibraryRowPatch) async throws -> [LibraryRow] { try reply(to: .patch(request)) }
    func insertIgnoringDuplicates(_ request: LibraryRowInsert) async throws -> [LibraryRow] { try reply(to: .insert(request)) }
    func delete(_ request: LibraryRowDelete) async throws { _ = try reply(to: .delete(request)) }
}

private enum Rows {
    /// The SDK reports `uuidString` upper-case; the list tables' captured RLS compares the TEXT
    /// `user_id` with `auth.uid()::text` (lower-case). F16: the adapter sends the canonical lower-case
    /// form, decided once by `UserIdText.value(for:)`.
    static let sessionUserId = "6F1C2A9E-4B7D-4F1E-9A51-0C2D3E4F5A6B"
    static let tableUserId = "6f1c2a9e-4b7d-4f1e-9a51-0c2d3e4f5a6b"
    static let account = AccountContext(userId: sessionUserId, generation: 1)
    static let date = Date(timeIntervalSince1970: 1_700_000_000)
    static let animeColumns = "id,user_id,anime_id,list_type,progress,rating,notes,verdict,created_at,updated_at"
    static let mangaColumns = "id,user_id,manga_id,list_type,progress,rating,notes,verdict,created_at,updated_at"

    static func anime(
        _ mediaId: Int, rowId: Int = 1, listType: String = "WATCHING", progress: Int = 0,
        rating: Int? = nil, notes: String? = nil, verdict: String? = nil,
        serverRevision: Int64? = nil, lifecycleId: UUID? = nil
    ) -> LibraryRow {
        LibraryRow(
            id: rowId, userId: tableUserId, animeId: mediaId, listType: listType, progress: progress,
            rating: rating, notes: notes, verdict: verdict, createdAt: date, updatedAt: date,
            serverRevision: serverRevision, lifecycleId: lifecycleId
        )
    }

    static func manga(_ mediaId: Int, rowId: Int = 1, listType: String = "READING") -> LibraryRow {
        LibraryRow(
            id: rowId, userId: tableUserId, mangaId: mediaId, listType: listType, progress: 0,
            createdAt: date, updatedAt: date
        )
    }

    static func json(_ body: [String: LibraryJSONValue]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(body), as: UTF8.self)
    }

    static func patchBody(_ request: RecordingTransport.Request?) -> [String: LibraryJSONValue]? {
        if case .patch(let patch) = request { return patch.body }
        return nil
    }
}

@Suite("SupabaseLibraryBackend: request contract")
struct SupabaseLibraryBackendRequestTests {
    static let anime42 = MediaKey(kind: .anime, id: 42)

    @Test("An edit PATCHes only its own columns, with explicit null for cleared fields and ratings on the 1...10 scale",
          arguments: [
              (LibraryEdit(progress: .set(5)), #"{"progress":5}"#),
              (LibraryEdit(notes: .clear), #"{"notes":null}"#),
              (LibraryEdit(rating: UserRating(value: 8).map { .set($0) } ?? .unchanged), #"{"rating":8}"#),
              (LibraryEdit(rating: .clear, verdict: .clear), #"{"rating":null,"verdict":null}"#),
              (LibraryEdit(status: .set(.completed), verdict: .set(.masterpiece)), #"{"list_type":"COMPLETED","verdict":"MASTERPIECE"}"#),
          ])
    func editSendsOnlyEditedColumns(edit: LibraryEdit, expectedBody: String) async throws {
        let serverRow = Rows.anime(42, rowId: 9, progress: 5, rating: 8, notes: "kept")
        let transport = RecordingTransport([.success([serverRow])])
        let backend = SupabaseLibraryBackend(transport: transport)

        let result = try await backend.edit(
            edit, key: Self.anime42, createIfMissing: nil, mutationId: UUID(), baseRevision: nil, account: Rows.account
        )

        guard case .patch(let patch) = try #require(transport.requests.first), transport.requests.count == 1 else {
            Issue.record("expected exactly one PATCH, got \(transport.requests)")
            return
        }
        #expect(try Rows.json(patch.body) == expectedBody)
        #expect(patch.table == "anime_user_lists")
        #expect(patch.mediaColumn == "anime_id")
        #expect(patch.mediaId == 42)
        #expect(patch.userId == "6f1c2a9e-4b7d-4f1e-9a51-0c2d3e4f5a6b", "user_id must be the canonical lower-case text (F16)")
        #expect(UserIdText.value(for: Rows.account) == Rows.tableUserId)
        #expect(patch.columns == Rows.animeColumns)
        #expect(result == LibraryWriteResult(
            entry: LibraryEntry(
                key: MediaKey(kind: .anime, id: 42), rowId: 9, status: .current, progress: 5, rating: UserRating(value: 8),
                notes: "kept", createdAt: Rows.date, updatedAt: Rows.date
            ),
            created: false
        ))
    }

    @Test("save never overwrites: insert-ignore-duplicates, then the existing row is read back unchanged",
          arguments: [true, false])
    func saveIsInsertIgnoringDuplicates(rowExists: Bool) async throws {
        let existing = Rows.anime(42, rowId: 3, listType: "COMPLETED", progress: 12, rating: 9)
        let inserted = Rows.anime(42, rowId: 4, listType: "PLANNING")
        let transport = RecordingTransport(rowExists ? [.success([]), .success([existing])] : [.success([inserted])])
        let backend = SupabaseLibraryBackend(transport: transport)

        let result = try await backend.insertIfMissing(Self.anime42, status: .planning, account: Rows.account)

        let expectedInsert = RecordingTransport.Request.insert(LibraryRowInsert(
            table: "anime_user_lists",
            columns: Rows.animeColumns,
            onConflict: "user_id,anime_id",
            body: [
                "user_id": .string(Rows.tableUserId), "anime_id": .int(42),
                "list_type": .string("PLANNING"), "progress": .int(0),
            ]
        ))
        if rowExists {
            #expect(transport.requests == [
                expectedInsert,
                .select(LibraryRowSelect(
                    table: "anime_user_lists", columns: Rows.animeColumns, userId: Rows.tableUserId,
                    mediaColumn: "anime_id", mediaId: 42, orderColumn: "id", offset: 0, limit: 1
                )),
            ])
            #expect(result.created == false)
            #expect(result.entry.status == .completed)
            #expect(result.entry.progress == 12)
            #expect(result.entry.rating == UserRating(value: 9))
        } else {
            #expect(transport.requests == [expectedInsert])
            #expect(result.created)
            #expect(result.entry.status == .planning)
        }
    }

    @Test("Editing a removed entry is notFound and never inserts a row")
    func editOfMissingRowIsNotFound() async throws {
        let transport = RecordingTransport([.success([])])
        let backend = SupabaseLibraryBackend(transport: transport)

        await #expect(throws: LibraryError.notFound) {
            try await backend.edit(
                LibraryEdit(progress: .set(3)), key: Self.anime42, createIfMissing: nil,
                mutationId: UUID(), baseRevision: nil, account: Rows.account
            )
        }
        #expect(transport.requests.count == 1)
        #expect(Rows.patchBody(transport.requests.first) == ["progress": .int(3)])
    }

    @Test("createIfMissing: PATCH, then insert-ignore-duplicates, then re-PATCH when the insert lost a race",
          arguments: [false, true])
    func createIfMissingSequence(insertLostRace: Bool) async throws {
        let row = Rows.anime(42, rowId: 5, listType: "WATCHING", progress: 2)
        let replies: [Result<[LibraryRow], LibraryTransportError>] = insertLostRace
            ? [.success([]), .success([]), .success([row])]
            : [.success([]), .success([row])]
        let transport = RecordingTransport(replies)
        let backend = SupabaseLibraryBackend(transport: transport)
        let edit = LibraryEdit(progress: .set(2))

        let result = try await backend.edit(
            edit, key: Self.anime42, createIfMissing: .current, mutationId: UUID(), baseRevision: nil, account: Rows.account
        )

        let patch = RecordingTransport.Request.patch(LibraryRowPatch(
            table: "anime_user_lists", columns: Rows.animeColumns, userId: Rows.tableUserId,
            mediaColumn: "anime_id", mediaId: 42, body: ["progress": .int(2)]
        ))
        let insert = RecordingTransport.Request.insert(LibraryRowInsert(
            table: "anime_user_lists", columns: Rows.animeColumns, onConflict: "user_id,anime_id",
            body: [
                "user_id": .string(Rows.tableUserId), "anime_id": .int(42),
                "list_type": .string("WATCHING"), "progress": .int(2),
            ]
        ))
        #expect(transport.requests == (insertLostRace ? [patch, insert, patch] : [patch, insert]))
        #expect(result.created == !insertLostRace)
        #expect(result.entry.progress == 2)
    }

    @Test("An edit that names no field never sends PATCH {}: it reads the row, or saves it when createIfMissing",
          arguments: [nil, ListStatus.planning])
    func emptyEditNeverPatches(createIfMissing: ListStatus?) async throws {
        let row = Rows.anime(42, rowId: 6, listType: "COMPLETED", progress: 12)
        let transport = RecordingTransport([.success([row])])
        let result = try await SupabaseLibraryBackend(transport: transport).edit(
            LibraryEdit(), key: Self.anime42, createIfMissing: createIfMissing,
            mutationId: UUID(), baseRevision: nil, account: Rows.account
        )
        #expect(result.entry.status == .completed)
        switch transport.requests.first {
        case .select(let select)?:
            #expect(createIfMissing == nil)
            #expect(select.mediaId == 42)
        case .insert(let insert)?:
            #expect(createIfMissing == .planning)
            #expect(insert.onConflict == "user_id,anime_id")
        default:
            Issue.record("unexpected requests \(transport.requests)")
        }
        #expect(transport.requests.count == 1)
    }

    @Test("anime 7 and manga 7 use their own tables and map to distinct keys even with equal row ids")
    func equalIdsUseDistinctTables() async throws {
        let transport = RecordingTransport([
            .success([Rows.anime(7, rowId: 5)]),
            .success([Rows.manga(7, rowId: 5)]),
            .success([Rows.manga(7, rowId: 5, listType: "COMPLETED")]),
        ])
        let backend = SupabaseLibraryBackend(transport: transport)

        let entries = try await backend.fetchAll(for: Rows.account)
        #expect(entries.map(\.key) == [MediaKey(kind: .anime, id: 7), MediaKey(kind: .manga, id: 7)])
        #expect(entries.map(\.rowId) == [5, 5])

        _ = try await backend.edit(
            LibraryEdit(status: .set(.completed)), key: MediaKey(kind: .manga, id: 7), createIfMissing: nil,
            mutationId: UUID(), baseRevision: nil, account: Rows.account
        )
        let requests = transport.requests
        guard requests.count == 3,
              case .select(let animeSelect) = requests[0],
              case .select(let mangaSelect) = requests[1],
              case .patch(let mangaPatch) = requests[2] else {
            Issue.record("unexpected requests \(requests)")
            return
        }
        #expect([animeSelect.table, animeSelect.mediaColumn, animeSelect.columns]
            == ["anime_user_lists", "anime_id", Rows.animeColumns])
        #expect([mangaSelect.table, mangaSelect.mediaColumn, mangaSelect.columns]
            == ["manga_user_lists", "manga_id", Rows.mangaColumns])
        #expect([mangaPatch.table, mangaPatch.mediaColumn] == ["manga_user_lists", "manga_id"])
        #expect(mangaPatch.mediaId == 7)
    }

    @Test("fetchAll pages by id in finite ranges and stops at the page cap instead of looping")
    func fetchAllPagesFinitely() async throws {
        let paged = RecordingTransport([
            .success([Rows.anime(1, rowId: 1), Rows.anime(2, rowId: 2)]),
            .success([Rows.anime(3, rowId: 3)]),
            .success([]),
        ])
        let entries = try await SupabaseLibraryBackend(transport: paged, pageSize: 2, maxPages: 10)
            .fetchAll(for: Rows.account)
        #expect(entries.count == 3)
        let ranges = paged.requests.compactMap { request -> [String]? in
            guard case .select(let select) = request else { return nil }
            return [select.table, select.orderColumn, "\(select.offset)", "\(select.limit)"]
        }
        #expect(ranges == [
            ["anime_user_lists", "id", "0", "2"],
            ["anime_user_lists", "id", "2", "2"],
            ["manga_user_lists", "id", "0", "2"],
        ])

        let endless = RecordingTransport(Array(repeating: .success([Rows.anime(1)]), count: 10))
        await #expect(throws: LibraryError.self) {
            try await SupabaseLibraryBackend(transport: endless, pageSize: 1, maxPages: 3).fetchAll(for: Rows.account)
        }
        #expect(endless.requests.count == 3)
    }
}

@Suite("SupabaseLibraryBackend: mapping rules")
struct SupabaseLibraryBackendMappingTests {
    @Test("Database list_type values map to ListStatus exactly as the app's statusFromDB (unknown -> planning)",
          arguments: [
              ("WATCHING", ListStatus.current), ("READING", .current), ("watching", .current),
              ("PLANNING", .planning), ("COMPLETED", .completed), ("DROPPED", .dropped), ("PAUSED", .paused),
              ("REPEATING", .planning), ("CURRENT", .planning), ("", .planning),
          ])
    func readStatusMapping(listType: String, expected: ListStatus) async throws {
        let transport = RecordingTransport([.success([Rows.anime(1, listType: listType)]), .success([])])
        let entries = try await SupabaseLibraryBackend(transport: transport).fetchAll(for: Rows.account)
        #expect(entries.map(\.status) == [expected])
    }

    @Test("ListStatus maps to list_type per medium; repeating is stored as WATCHING/READING",
          arguments: [
              (ListStatus.current, MediaKind.anime, "WATCHING"), (.current, .manga, "READING"),
              (.repeating, .anime, "WATCHING"), (.repeating, .manga, "READING"),
              (.planning, .manga, "PLANNING"), (.paused, .anime, "PAUSED"),
          ])
    func writeStatusMapping(status: ListStatus, kind: MediaKind, listType: String) async throws {
        let row = kind == .anime ? Rows.anime(1, listType: listType) : Rows.manga(1, listType: listType)
        let transport = RecordingTransport([.success([row])])
        _ = try await SupabaseLibraryBackend(transport: transport).edit(
            LibraryEdit(status: .set(status)), key: MediaKey(kind: kind, id: 1), createIfMissing: nil,
            mutationId: UUID(), baseRevision: nil, account: Rows.account
        )
        #expect(Rows.patchBody(transport.requests.first) == ["list_type": .string(listType)])
    }

    @Test("Transport failures map to typed library errors",
          arguments: [
              (LibraryTransportError.server(status: 401, code: nil, message: "Unauthorized"), LibraryError.notAuthenticated),
              (.server(status: nil, code: "PGRST301", message: "JWT expired"), .notAuthenticated),
              (.server(status: nil, code: nil, message: "JWT expired"), .notAuthenticated),
              (.server(status: 400, code: "23514",
                       message: #"new row for relation "anime_user_lists" violates check constraint "anime_user_lists_rating_check""#),
               .invalidValue(field: "rating")),
              (.network(message: "The request timed out."), .retryable(message: "The request timed out.")),
              (.server(status: 503, code: nil, message: "Service Unavailable"), .retryable(message: "Service Unavailable")),
              (.server(status: 403, code: "42501", message: "new row violates row-level security policy"),
               .unavailable(message: "new row violates row-level security policy")),
              (.server(status: 409, code: "23505", message: "duplicate key"), .unavailable(message: "duplicate key")),
              // supabase-swift hides the status of PostgREST JSON errors: transient codes are retryable.
              (.server(status: nil, code: "PGRST003", message: "Timed out acquiring connection"),
               .retryable(message: "Timed out acquiring connection")),
              (.server(status: nil, code: "57014", message: "canceling statement due to statement timeout"),
               .retryable(message: "canceling statement due to statement timeout")),
              (.server(status: nil, code: "53300", message: "too many connections"), .retryable(message: "too many connections")),
              (.server(status: nil, code: "08006", message: "connection failure"), .retryable(message: "connection failure")),
              (.server(status: nil, code: "40P01", message: "deadlock detected"), .retryable(message: "deadlock detected")),
              (.server(status: nil, code: "XX000", message: "internal error"), .unavailable(message: "internal error")),
              (.server(status: nil, code: "PGRST116", message: "no rows"), .unavailable(message: "no rows")),
          ])
    func transportErrorMapping(failure: LibraryTransportError, expected: LibraryError) async throws {
        let transport = RecordingTransport([.failure(failure)])
        await #expect(throws: expected) {
            try await SupabaseLibraryBackend(transport: transport).remove(MediaKey(kind: .anime, id: 1), account: Rows.account)
        }
        #expect(transport.requests == [.delete(LibraryRowDelete(
            table: "anime_user_lists", userId: Rows.tableUserId, mediaColumn: "anime_id", mediaId: 1
        ))])
    }

    @Test("With the fence on, progress and status use the receipt RPC and notes stay on PATCH")
    func fenceRoutesProgressAndLeavesNotesOnPatch() async throws {
        let life = UUID()
        let mutation = UUID()
        let current = Rows.anime(42, rowId: 9, progress: 3, notes: "kept", serverRevision: 4, lifecycleId: life)
        let after = Rows.anime(42, rowId: 9, progress: 5, notes: "kept", serverRevision: 5, lifecycleId: life)
        let noted = Rows.anime(42, rowId: 9, progress: 5, notes: "later", serverRevision: 6, lifecycleId: life)
        let transport = RecordingTransport([.success([current]), .success([after]), .success([noted])])
        let fence = RecordingFence(outcome: "applied")
        let backend = SupabaseLibraryBackend(transport: transport, fence: fence, fenceEnabled: { true })

        let progress = try await backend.edit(
            LibraryEdit(progress: .set(5)),
            key: MediaKey(kind: .anime, id: 42),
            createIfMissing: nil,
            mutationId: mutation,
            baseRevision: 4,
            account: Rows.account
        )
        #expect(progress.entry.progress == 5)
        #expect(progress.entry.revision == 5)
        #expect(fence.progress.count == 1)
        #expect(fence.progress[0].mutationId == mutation)
        #expect(fence.progress[0].baseRevision == 4)
        #expect(fence.progress[0].position == 5)
        #expect(fence.progress[0].lifecycleId == life)
        #expect(transport.requests.count == 2)

        let notes = try await backend.edit(
            LibraryEdit(notes: .set("later")),
            key: MediaKey(kind: .anime, id: 42),
            createIfMissing: nil,
            mutationId: UUID(),
            baseRevision: 5,
            account: Rows.account
        )
        #expect(notes.entry.notes == "later")
        #expect(fence.progress.count == 1, "a note does not go through the progress receipt")
        #expect(Rows.patchBody(transport.requests.last) == ["notes": .string("later")])
    }

    @Test("A stale progress base returns conflict and does not PATCH")
    func fenceConflictDoesNotPatch() async throws {
        let life = UUID()
        let current = Rows.anime(42, rowId: 9, progress: 3, serverRevision: 8, lifecycleId: life)
        let transport = RecordingTransport([.success([current])])
        let fence = RecordingFence(outcome: "conflict", serverRevision: 8, position: 3)
        let backend = SupabaseLibraryBackend(transport: transport, fence: fence, fenceEnabled: { true })

        do {
            _ = try await backend.edit(
                LibraryEdit(progress: .set(9)),
                key: MediaKey(kind: .anime, id: 42),
                createIfMissing: nil,
                mutationId: UUID(),
                baseRevision: 4,
                account: Rows.account
            )
            Issue.record("expected a revision conflict")
        } catch let error as LibraryError {
            guard case .conflict(let server) = error else {
                Issue.record("expected conflict, got \(error)")
                return
            }
            #expect(server?.progress == 3)
            #expect(server?.revision == 8)
        }
        #expect(transport.requests.count == 1)
    }
}

private final class RecordingFence: LibraryFenceTransport, @unchecked Sendable {
    var progress: [LibraryFenceProgressMutation] = []
    var removals: [LibraryFenceRemoveMutation] = []
    let outcome: String
    let serverRevision: Int64
    let position: Int?

    init(outcome: String, serverRevision: Int64 = 5, position: Int? = 5) {
        self.outcome = outcome
        self.serverRevision = serverRevision
        self.position = position
    }

    func applyProgressMutations(_ mutations: [LibraryFenceProgressMutation]) async throws -> LibraryFenceBatchResult {
        progress.append(contentsOf: mutations)
        return LibraryFenceBatchResult(items: mutations.map { item in
            LibraryFenceItemResult(
                mutationId: item.mutationId.uuidString,
                outcome: outcome,
                serverRevision: serverRevision,
                position: position,
                notes: nil,
                rating: nil,
                status: item.status
            )
        })
    }

    func applyRemoveMutations(_ mutations: [LibraryFenceRemoveMutation]) async throws -> LibraryFenceBatchResult {
        removals.append(contentsOf: mutations)
        return LibraryFenceBatchResult(items: mutations.map { item in
            LibraryFenceItemResult(
                mutationId: item.mutationId.uuidString,
                outcome: outcome,
                serverRevision: serverRevision,
                position: nil,
                notes: nil,
                rating: nil,
                status: nil
            )
        })
    }
}

@Test func importedMetadataProjectsOnlyBehindFencedColumns() async throws {
    let json = #"{"id":1,"user_id":"a","manga_id":7,"list_type":"READING","progress":8,"created_at":"2026-10-08T00:00:00Z","updated_at":"2026-10-08T00:00:00Z","server_revision":3,"lifecycle_id":"00000000-0000-0000-0000-000000000007","volumes_progress":2,"repeat_count":1,"score_raw":8.5,"score_scale":"POINT_10_DECIMAL","started_raw":"2024-00-00","entry_private":true,"source_custom_lists":["Favorites"]}"#
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let row = try decoder.decode(LibraryRow.self, from: Data(json.utf8))
    let enabled = RecordingTransport([.success([]),.success([row])])
    let projected = try await SupabaseLibraryBackend(transport: enabled,
        fence: RecordingFence(outcome:"applied"),fenceEnabled:{ true }).fetchAll(for:Rows.account)
    #expect(projected.first?.sourceMetadata?.scoreRaw == "8.5")
    #expect(projected.first?.sourceMetadata?.startedRaw == "2024-00-00")
    #expect(projected.first?.sourceMetadata?.volumesProgress == 2)
    #expect(projected.first?.sourceMetadata?.repeatCount == 1)
    #expect(projected.first?.sourceMetadata?.isPrivate == true)
    #expect(projected.first?.sourceMetadata?.customLists == ["Favorites"])
    if case .select(let request)? = enabled.requests.first { #expect(!request.columns.contains("volumes_progress")) }
    if case .select(let request)? = enabled.requests.last { #expect(request.columns.contains("volumes_progress")) }
    let disabled = RecordingTransport([.success([]),.success([row])])
    let oldClient = try await SupabaseLibraryBackend(transport:disabled).fetchAll(for:Rows.account)
    #expect(oldClient.first?.sourceMetadata == nil)
    if case .select(let request)? = disabled.requests.first { #expect(!request.columns.contains("score_raw")) }
}

/// The reviewed schema has Manga volumes only. PostgREST rejects unknown selected columns even
/// for zero rows, so an empty tester account must exercise request validation rather than fake rows.
private struct FoundationSchemaTransport: LibraryRowTransport {
    func select(_ request: LibraryRowSelect) async throws -> [LibraryRow] {
        let common = Set("id,user_id,list_type,progress,rating,notes,verdict,created_at,updated_at,server_revision,lifecycle_id,progress_label,unit_id,repeat_count,score_raw,score_scale,started_raw,finished_raw,entry_private,source_custom_lists,source_hidden,source_list_options".split(separator: ",").map(String.init))
        let allowed = common.union(request.table == "anime_user_lists" ? ["anime_id"] : ["manga_id", "volumes_progress"])
        if let missing = request.columns.split(separator: ",").map(String.init).first(where: { !allowed.contains($0) }) {
            throw LibraryTransportError.server(status:400,code:"42703",message:"column \(request.table).\(missing) does not exist")
        }
        return []
    }
    func patch(_ request: LibraryRowPatch) async throws -> [LibraryRow] { throw LibraryTransportError.server(status:599,code:nil,message:"unexpected write") }
    func insertIgnoringDuplicates(_ request: LibraryRowInsert) async throws -> [LibraryRow] { throw LibraryTransportError.server(status:599,code:nil,message:"unexpected write") }
    func delete(_ request: LibraryRowDelete) async throws { throw LibraryTransportError.server(status:599,code:nil,message:"unexpected write") }
}

@MainActor
@Test func emptyFoundationLibraryValidatesEachMediumSchemaBeforeReadiness() async throws {
    let rejected = LibraryRowSelect(table:"anime_user_lists",columns:"id,anime_id,volumes_progress",
        userId:Rows.tableUserId,mediaColumn:"anime_id",mediaId:nil,orderColumn:"id",offset:0,limit:1000)
    await #expect(throws:LibraryTransportError.self) {
        _ = try await FoundationSchemaTransport().select(rejected)
    }
    let backend = SupabaseLibraryBackend(transport:FoundationSchemaTransport(),
        fence:RecordingFence(outcome:"applied"),fenceEnabled:{ true })
    let library = LibraryStore(backend:backend)
    library.bind(Rows.account)
    try await library.refresh()
    #expect(library.loadState == .loaded)
    #expect(library.allEntries.isEmpty)
}
