import Foundation
import KuroCore
import KuroLibrary

/// `LibraryBackend` over `anime_user_lists` / `manga_user_lists` (contract §3.4).
///
/// - PATCH bodies contain only the edited columns; `.clear` is sent as an explicit JSON `null`.
/// - `rating` is written on the database scale 1...10 only (`UserRating.value`).
/// - `save` is insert-ignore-duplicates and never changes an existing row.
/// - `user_id` is `UserIdText.value(for:)` (the canonical lower-case TEXT id, F16); RLS enforces
///   ownership, and the explicit `user_id` filter keeps a request sent with another account's token
///   from matching any row (defence in depth for F33).
/// - When `fence` is set and `fenceEnabled` is true, progress, status and removal go through
///   `apply_progress_mutations_v1` / `apply_remove_mutations_v1`. Notes, rating and verdict stay
///   on PATCH; that PATCH still advances `server_revision`, so a progress mutation holding the
///   previous base revision conflicts.
/// - With the fence off, PATCH and DELETE stay the writers. That is the production path until
///   `series_foundation_v1` is enabled after the prepared migration is deployed.
public struct SupabaseLibraryBackend: LibraryBackend {
    private let transport: any LibraryRowTransport
    private let fence: (any LibraryFenceTransport)?
    private let fenceEnabled: @Sendable () -> Bool
    private let pageSize: Int
    private let maxPages: Int

    /// `pageSize` 1000 equals Supabase's default `max_rows`. A page shorter than `pageSize` ends a
    /// table, so the project's `max_rows` must not be lowered below this value.
    public init(transport: any LibraryRowTransport) {
        self.init(transport: transport, fence: nil, fenceEnabled: { false }, pageSize: 1000, maxPages: 100)
    }

    public init(
        transport: any LibraryRowTransport,
        fence: (any LibraryFenceTransport)?,
        fenceEnabled: @escaping @Sendable () -> Bool
    ) {
        self.init(transport: transport, fence: fence, fenceEnabled: fenceEnabled, pageSize: 1000, maxPages: 100)
    }

    init(transport: any LibraryRowTransport, pageSize: Int, maxPages: Int) {
        self.init(transport: transport, fence: nil, fenceEnabled: { false }, pageSize: pageSize, maxPages: maxPages)
    }

    init(
        transport: any LibraryRowTransport,
        fence: (any LibraryFenceTransport)?,
        fenceEnabled: @escaping @Sendable () -> Bool,
        pageSize: Int,
        maxPages: Int
    ) {
        self.transport = transport
        self.fence = fence
        self.fenceEnabled = fenceEnabled
        self.pageSize = max(1, pageSize)
        self.maxPages = max(1, maxPages)
    }

    private var usesFence: Bool { fence != nil && fenceEnabled() }

    // MARK: LibraryBackend

    public func fetchAll(for account: AccountContext) async throws -> [LibraryEntry] {
        let userId = UserIdText.value(for: account)
        var entries: [LibraryEntry] = []
        for kind in [MediaKind.anime, .manga] {
            entries += try await fetchTable(ListTable(kind, includeFenceColumns: usesFence), userId: userId)
        }
        return entries
    }

    public func edit(
        _ edit: LibraryEdit,
        key: MediaKey,
        createIfMissing: ListStatus?,
        mutationId: UUID,
        baseRevision: Int64?,
        account: AccountContext
    ) async throws -> LibraryWriteResult {
        if let error = edit.validationError { throw error }
        let table = ListTable(key.kind, includeFenceColumns: usesFence)
        let userId = UserIdText.value(for: account)
        if usesFence, edit.touchesProgress || edit.touchesStatus {
            return try await editThroughFence(edit, key: key, table: table, userId: userId, createIfMissing: createIfMissing, mutationId: mutationId, baseRevision: baseRevision)
        }
        let body = Self.body(for: edit, kind: key.kind)

        // Never send `PATCH {}`.
        if body.isEmpty {
            if let createIfMissing {
                return try await insertIfMissing(key, status: createIfMissing, account: account)
            }
            guard let row = try await selectOne(table, userId: userId, mediaId: key.id) else {
                throw LibraryError.notFound
            }
            return LibraryWriteResult(entry: try table.entry(from: row), created: false)
        }

        if let row = try await patch(table, userId: userId, mediaId: key.id, body: body) {
            return LibraryWriteResult(entry: try table.entry(from: row), created: false)
        }
        // Zero rows: the entry does not exist. Never recreate it unless asked to.
        guard let createIfMissing else { throw LibraryError.notFound }

        var insertBody = body
        insertBody["user_id"] = .string(userId)
        insertBody[table.mediaColumn] = .int(key.id)
        if insertBody["list_type"] == nil {
            insertBody["list_type"] = .string(Self.dbListType(for: createIfMissing, kind: key.kind))
        }
        if let row = try await insert(table, body: insertBody) {
            return LibraryWriteResult(entry: try table.entry(from: row), created: true)
        }
        // The insert lost a race with a concurrent create: apply the edit to that row instead.
        if let row = try await patch(table, userId: userId, mediaId: key.id, body: body) {
            return LibraryWriteResult(entry: try table.entry(from: row), created: false)
        }
        throw LibraryError.notFound
    }

    public func insertIfMissing(_ key: MediaKey, status: ListStatus, account: AccountContext) async throws -> LibraryWriteResult {
        let table = ListTable(key.kind, includeFenceColumns: usesFence)
        let userId = UserIdText.value(for: account)
        let body: [String: LibraryJSONValue] = [
            "user_id": .string(userId),
            table.mediaColumn: .int(key.id),
            "list_type": .string(Self.dbListType(for: status, kind: key.kind)),
            "progress": .int(0),
        ]
        if let row = try await insert(table, body: body) {
            return LibraryWriteResult(entry: try table.entry(from: row), created: true)
        }
        // Ignored as a duplicate: return the existing row untouched.
        guard let row = try await selectOne(table, userId: userId, mediaId: key.id) else {
            throw LibraryError.retryable(message: "\(table.name) row \(key.id) changed during save")
        }
        return LibraryWriteResult(entry: try table.entry(from: row), created: false)
    }

    public func remove(_ key: MediaKey, account: AccountContext) async throws {
        try await remove(key, mutationId: UUID(), baseRevision: nil, account: account)
    }

    public func remove(_ key: MediaKey, mutationId: UUID, baseRevision: Int64?, account: AccountContext) async throws {
        if usesFence {
            try await removeThroughFence(key, mutationId: mutationId, baseRevision: baseRevision, account: account)
            return
        }
        let table = ListTable(key.kind, includeFenceColumns: false)
        let request = LibraryRowDelete(
            table: table.name,
            userId: UserIdText.value(for: account),
            mediaColumn: table.mediaColumn,
            mediaId: key.id
        )
        try await mapped { try await transport.delete(request) }
    }

    // MARK: Revision fence

    private func editThroughFence(
        _ edit: LibraryEdit,
        key: MediaKey,
        table: ListTable,
        userId: String,
        createIfMissing: ListStatus?,
        mutationId: UUID,
        baseRevision: Int64?
    ) async throws -> LibraryWriteResult {
        guard let fence else { throw LibraryError.unavailable(message: "revision fence is not configured") }
        var created = false
        var row = try await selectOne(table, userId: userId, mediaId: key.id)
        if row == nil {
            guard let createIfMissing else { throw LibraryError.notFound }
            let seeded = try await insertSeed(table, userId: userId, mediaId: key.id, status: createIfMissing, kind: key.kind)
            created = seeded.created
            row = seeded.row
        }
        guard let row else { throw LibraryError.notFound }
        guard let lifecycle = row.lifecycleId, let revision = row.serverRevision else {
            throw LibraryError.unavailable(message: "list row has no lifecycle or server revision")
        }

        let position: Int? = {
            if case .set(let value) = edit.progress { return value }
            return nil
        }()
        let status: String? = {
            if case .set(let value) = edit.status { return Self.dbListType(for: value, kind: key.kind) }
            return nil
        }()
        let mutation = LibraryFenceProgressMutation(
            mutationId: mutationId,
            medium: key.kind == .manga ? "manga" : "anime",
            mediaId: key.id,
            lifecycleId: lifecycle,
            baseRevision: baseRevision ?? revision,
            position: position,
            status: status
        )
        let batch = try await mapped { try await fence.applyProgressMutations([mutation]) }
        guard let item = batch.items.first else {
            throw LibraryError.unavailable(message: "progress fence returned no item")
        }
        switch item.outcome {
        case "applied", "already_applied":
            break
        case "conflict":
            throw LibraryError.conflict(server: conflictEntry(table: table, row: row, item: item))
        case "removed_entry":
            throw LibraryError.notFound
        default:
            throw LibraryError.unavailable(message: "progress fence outcome \(item.outcome)")
        }

        let side = edit.patchBodyOmittingProgress
        let sideBody = Self.body(for: side, kind: key.kind)
        let confirmed: LibraryRow
        if sideBody.isEmpty {
            guard let fresh = try await selectOne(table, userId: userId, mediaId: key.id) else {
                throw LibraryError.notFound
            }
            confirmed = fresh
        } else if let patched = try await patch(table, userId: userId, mediaId: key.id, body: sideBody) {
            confirmed = patched
        } else {
            throw LibraryError.notFound
        }
        return LibraryWriteResult(entry: try table.entry(from: confirmed), created: created)
    }

    private func insertSeed(
        _ table: ListTable,
        userId: String,
        mediaId: Int,
        status: ListStatus,
        kind: MediaKind
    ) async throws -> (row: LibraryRow?, created: Bool) {
        let body: [String: LibraryJSONValue] = [
            "user_id": .string(userId),
            table.mediaColumn: .int(mediaId),
            "list_type": .string(Self.dbListType(for: status, kind: kind)),
            "progress": .int(0),
        ]
        if let row = try await insert(table, body: body) {
            return (row, true)
        }
        let existing = try await selectOne(table, userId: userId, mediaId: mediaId)
        return (existing, false)
    }

    private func removeThroughFence(
        _ key: MediaKey,
        mutationId: UUID,
        baseRevision: Int64?,
        account: AccountContext
    ) async throws {
        guard let fence else { throw LibraryError.unavailable(message: "revision fence is not configured") }
        let table = ListTable(key.kind, includeFenceColumns: true)
        let userId = UserIdText.value(for: account)
        guard let row = try await selectOne(table, userId: userId, mediaId: key.id) else { return }
        guard let lifecycle = row.lifecycleId, let revision = row.serverRevision else {
            throw LibraryError.unavailable(message: "list row has no lifecycle or server revision")
        }
        let mutation = LibraryFenceRemoveMutation(
            mutationId: mutationId,
            medium: key.kind == .manga ? "manga" : "anime",
            mediaId: key.id,
            lifecycleId: lifecycle,
            baseRevision: baseRevision ?? revision
        )
        let batch = try await mapped { try await fence.applyRemoveMutations([mutation]) }
        guard let item = batch.items.first else {
            throw LibraryError.unavailable(message: "remove fence returned no item")
        }
        switch item.outcome {
        case "applied", "already_applied":
            return
        case "conflict":
            throw LibraryError.conflict(server: conflictEntry(table: table, row: row, item: item))
        case "removed_entry":
            throw LibraryError.notFound
        default:
            throw LibraryError.unavailable(message: "remove fence outcome \(item.outcome)")
        }
    }

    private func conflictEntry(table: ListTable, row: LibraryRow, item: LibraryFenceItemResult) -> LibraryEntry? {
        var entry = try? table.entry(from: row)
        if let position = item.position { entry?.progress = position }
        if let revision = item.serverRevision { entry?.revision = revision }
        if let status = item.status { entry?.status = Self.status(fromDB: status) }
        if let notes = item.notes { entry?.notes = notes }
        if let rating = item.rating { entry?.rating = UserRating(value: rating) }
        return entry
    }

    // MARK: Requests

    private func fetchTable(_ table: ListTable, userId: String) async throws -> [LibraryEntry] {
        var entries: [LibraryEntry] = []
        var offset = 0
        for _ in 0..<maxPages {
            let request = LibraryRowSelect(
                table: table.name,
                columns: table.columns,
                userId: userId,
                mediaColumn: table.mediaColumn,
                mediaId: nil,
                orderColumn: "id",
                offset: offset,
                limit: pageSize
            )
            let rows = try await mapped { try await transport.select(request) }
            entries += try rows.map { try table.entry(from: $0) }
            if rows.count < pageSize { return entries }
            offset += pageSize
        }
        throw LibraryError.unavailable(message: "\(table.name) exceeds \(maxPages * pageSize) rows")
    }

    private func selectOne(_ table: ListTable, userId: String, mediaId: Int) async throws -> LibraryRow? {
        let request = LibraryRowSelect(
            table: table.name,
            columns: table.columns,
            userId: userId,
            mediaColumn: table.mediaColumn,
            mediaId: mediaId,
            orderColumn: "id",
            offset: 0,
            limit: 1
        )
        return try await mapped { try await transport.select(request) }.first
    }

    private func patch(_ table: ListTable, userId: String, mediaId: Int, body: [String: LibraryJSONValue]) async throws -> LibraryRow? {
        let request = LibraryRowPatch(
            table: table.name,
            columns: table.columns,
            userId: userId,
            mediaColumn: table.mediaColumn,
            mediaId: mediaId,
            body: body
        )
        return try await mapped { try await transport.patch(request) }.first
    }

    private func insert(_ table: ListTable, body: [String: LibraryJSONValue]) async throws -> LibraryRow? {
        let request = LibraryRowInsert(
            table: table.name,
            columns: table.columns,
            onConflict: "user_id,\(table.mediaColumn)",
            body: body
        )
        return try await mapped { try await transport.insertIgnoringDuplicates(request) }.first
    }

    private func mapped<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw Self.libraryError(from: error)
        }
    }

    // MARK: Mapping rules

    /// Only the edited columns. `status`/`progress` can never be cleared (validated before).
    static func body(for edit: LibraryEdit, kind: MediaKind) -> [String: LibraryJSONValue] {
        var body: [String: LibraryJSONValue] = [:]
        if case .set(let status) = edit.status { body["list_type"] = .string(dbListType(for: status, kind: kind)) }
        if case .set(let progress) = edit.progress { body["progress"] = .int(progress) }
        switch edit.rating {
        case .set(let rating): body["rating"] = .int(rating.value)
        case .clear: body["rating"] = .null
        case .unchanged: break
        }
        switch edit.notes {
        case .set(let notes): body["notes"] = .string(notes)
        case .clear: body["notes"] = .null
        case .unchanged: break
        }
        switch edit.verdict {
        case .set(let verdict): body["verdict"] = .string(verdict.rawValue)
        case .clear: body["verdict"] = .null
        case .unchanged: break
        }
        return body
    }

    /// Same mapping as the app's `dbListType(for:mediaType:)`: `.repeating` has no database value
    /// and is stored as WATCHING/READING.
    static func dbListType(for status: ListStatus, kind: MediaKind) -> String {
        let isManga = kind == .manga
        switch status {
        case .current: return isManga ? "READING" : "WATCHING"
        case .planning: return "PLANNING"
        case .completed: return "COMPLETED"
        case .dropped: return "DROPPED"
        case .paused: return "PAUSED"
        case .repeating: return isManga ? "READING" : "WATCHING"
        }
    }

    /// Same mapping as the app's `statusFromDB(_:)`, including unknown values (and the literal
    /// `CURRENT`) falling back to `.planning`.
    static func status(fromDB listType: String) -> ListStatus {
        switch listType.uppercased() {
        case "READING": return .current
        case "WATCHING": return .current
        case "PLANNING": return .planning
        case "COMPLETED": return .completed
        case "DROPPED": return .dropped
        case "PAUSED": return .paused
        default: return .planning
        }
    }

    /// 401/JWT -> notAuthenticated; 23514 -> invalidValue; network, timeout, 5xx and transient
    /// PostgREST/PostgreSQL codes -> retryable; everything else -> unavailable.
    static func libraryError(from error: any Error) -> LibraryError {
        switch error {
        case let error as LibraryError:
            return error
        case LibraryTransportError.network(let message):
            return .retryable(message: message)
        case LibraryTransportError.server(let status, let code, let message):
            if status == 401 || ["PGRST301", "PGRST302", "PGRST303"].contains(code ?? "") {
                return .notAuthenticated
            }
            if code == "23514" { return .invalidValue(field: checkedField(in: message)) }
            if let code, isRetryableCode(code) { return .retryable(message: message) }
            if let status, status >= 500 || status == 408 { return .retryable(message: message) }
            if status == nil, message.localizedCaseInsensitiveContains("jwt") { return .notAuthenticated }
            return .unavailable(message: message)
        case is CancellationError:
            return .retryable(message: "cancelled")
        case let error as URLError:
            return .retryable(message: error.localizedDescription)
        default:
            return .unavailable(message: String(describing: error))
        }
    }

    /// Transient PostgREST / PostgreSQL error codes. supabase-swift drops the HTTP status of an error
    /// whose body is PostgREST JSON, so these classify 5xx-class failures by code: PGRST000-003
    /// (connection / pool), 08xxx (connection exception), 53xxx (insufficient resources), 57014 (query
    /// cancelled, e.g. statement timeout), 40001 / 40P01 (serialization failure / deadlock).
    static func isRetryableCode(_ code: String) -> Bool {
        let codes: Set<String> = ["PGRST000", "PGRST001", "PGRST002", "PGRST003", "57014", "40001", "40P01"]
        if codes.contains(code) { return true }
        return code.count == 5 && (code.hasPrefix("08") || code.hasPrefix("53"))
    }

    /// The field named by a CHECK violation such as `anime_user_lists_rating_check`.
    private static func checkedField(in message: String) -> String {
        let fields = [("list_type", "status"), ("progress", "progress"), ("rating", "rating"), ("verdict", "verdict")]
        for (column, field) in fields where message.contains("\(column)_check") { return field }
        return "unknown"
    }
}

/// Table, media column and selected columns for one medium.
struct ListTable: Sendable {
    let kind: MediaKind
    let includeFenceColumns: Bool

    init(_ kind: MediaKind, includeFenceColumns: Bool = false) {
        self.kind = kind
        self.includeFenceColumns = includeFenceColumns
    }

    var name: String { kind == .anime ? "anime_user_lists" : "manga_user_lists" }
    var mediaColumn: String { kind == .anime ? "anime_id" : "manga_id" }
    var columns: String {
        var base = "id,user_id,\(mediaColumn),list_type,progress,rating,notes,verdict,created_at,updated_at"
        if includeFenceColumns {
            base += ",server_revision,lifecycle_id,progress_label,unit_id,repeat_count,score_raw,score_scale,started_raw,finished_raw,entry_private,source_custom_lists,source_hidden,source_list_options"
            if kind == .manga { base += ",volumes_progress" }
        }
        return base
    }

    /// Row -> entry. A rating outside 1...10 or an unknown verdict cannot pass the table's CHECK
    /// constraints; if one ever arrives it is projected as `nil` instead of failing the whole read.
    func entry(from row: LibraryRow) throws -> LibraryEntry {
        guard let mediaId = kind == .anime ? row.animeId : row.mangaId else {
            throw LibraryError.unavailable(message: "\(name) row \(row.id) has no \(mediaColumn)")
        }
        return LibraryEntry(
            key: MediaKey(kind: kind, id: mediaId),
            rowId: row.id,
            status: SupabaseLibraryBackend.status(fromDB: row.listType),
            progress: row.progress,
            rating: row.rating.flatMap { UserRating(value: $0) },
            notes: row.notes,
            verdict: row.verdict.flatMap { Verdict(rawValue: $0) },
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            revision: row.serverRevision,
            lifecycleId: row.lifecycleId,
            progressLabel: row.progressLabel,
            unitId: row.unitId,
            sourceMetadata: includeFenceColumns ? LibrarySourceMetadata(volumesProgress: row.volumesProgress,
                repeatCount: row.repeatCount, scoreRaw: row.scoreRaw?.value, scoreScale: row.scoreScale,
                startedRaw: row.startedRaw, finishedRaw: row.finishedRaw, isPrivate: row.entryPrivate,
                customLists: row.sourceCustomLists, hiddenFromStatusLists: row.sourceHidden,
                sourceListOptions: row.sourceListOptions) : nil
        )
    }
}
