//
//  LibraryTestSupport.swift
//  KuroTests
//
//  A `LibraryBackend` that models only what the server would store and answer: rows per user,
//  the outcome of each write, and (optionally) a fetch or write held open until the test answers it
//  (`ControlledResponses`, shared with the E1 lifecycle tests). It holds no ordering, merging,
//  validation or account policy: that belongs to `LibraryStore` and `LibraryActions` under test.
//

import Foundation
import KuroCore
import KuroLibrary
import Synchronization

final class FakeLibraryBackend: LibraryBackend {
    enum Call: Equatable, Sendable {
        case fetchAll(userId: String)
        case edit(LibraryEdit, MediaKey, createIfMissing: ListStatus?)
        case insertIfMissing(MediaKey, ListStatus)
        case remove(MediaKey)
    }

    private struct State {
        var rows: [String: [MediaKey: LibraryEntry]] = [:]
        var calls: [Call] = []
        var nextRowId = 100
        var failNextWrite: LibraryError?
        var fetchesByUser: [String: Int] = [:]
    }

    static let date = Date(timeIntervalSince1970: 1_767_225_600)

    private let state = Mutex(State())
    /// When set, `fetchAll` answers with what the test completes for the label `<userId>` (the
    /// user's first fetch), `<userId>#2`, `<userId>#3`, ... (later fetches).
    let fetchSource: ControlledResponses<[LibraryEntry]>?
    /// When set, each write waits until the test completes the label `<kind>-<id>`; a failure
    /// completion makes the write fail with that error.
    let writeGate: ControlledResponses<Bool>?

    init(fetchSource: ControlledResponses<[LibraryEntry]>? = nil, writeGate: ControlledResponses<Bool>? = nil) {
        self.fetchSource = fetchSource
        self.writeGate = writeGate
    }

    var calls: [Call] { state.withLock { $0.calls } }

    var writeCalls: [Call] {
        calls.filter { if case .fetchAll = $0 { return false } else { return true } }
    }

    /// Stores `entries` as the server's rows of `userId` (replacing earlier ones).
    func setRows(_ entries: [LibraryEntry], for userId: String) {
        state.withLock { state in
            state.rows[userId.lowercased()] = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0) })
        }
    }

    func rows(for userId: String) -> [MediaKey: LibraryEntry] {
        state.withLock { $0.rows[userId.lowercased()] ?? [:] }
    }

    func failNextWrite(with error: LibraryError) {
        state.withLock { $0.failNextWrite = error }
    }

    static func entry(
        _ kind: MediaKind, _ id: Int, rowId: Int = 1, status: ListStatus = .current, progress: Int = 0,
        rating: Int? = nil, notes: String? = nil, verdict: Verdict? = nil
    ) -> LibraryEntry {
        LibraryEntry(
            key: MediaKey(kind: kind, id: id), rowId: rowId, status: status, progress: progress,
            rating: rating.flatMap { UserRating(value: $0) }, notes: notes, verdict: verdict,
            createdAt: date, updatedAt: date
        )
    }

    // MARK: LibraryBackend

    func fetchAll(for account: AccountContext) async throws -> [LibraryEntry] {
        let ordinal = state.withLock { state in
            state.calls.append(.fetchAll(userId: account.userId))
            state.fetchesByUser[account.userId, default: 0] += 1
            return state.fetchesByUser[account.userId, default: 1]
        }
        let rows: [LibraryEntry]
        if let fetchSource {
            rows = try await fetchSource.value(for: ordinal == 1 ? account.userId : "\(account.userId)#\(ordinal)")
        } else {
            rows = state.withLock { Array(($0.rows[account.userId.lowercased()] ?? [:]).values) }
        }
        // Like the SDK, a read whose task was cancelled fails instead of answering.
        try Task.checkCancellation()
        return rows
    }

    func edit(
        _ edit: LibraryEdit,
        key: MediaKey,
        createIfMissing: ListStatus?,
        mutationId: UUID,
        baseRevision: Int64?,
        account: AccountContext
    ) async throws -> LibraryWriteResult {
        try await recordWrite(.edit(edit, key, createIfMissing: createIfMissing), key: key)
        return try state.withLock { state in
            let user = account.userId.lowercased()
            if var entry = state.rows[user]?[key] {
                Self.apply(edit, to: &entry)
                state.rows[user, default: [:]][key] = entry
                return LibraryWriteResult(entry: entry, created: false)
            }
            guard let createIfMissing else { throw LibraryError.notFound }
            state.nextRowId += 1
            var entry = Self.entry(key.kind, key.id, rowId: state.nextRowId, status: createIfMissing)
            Self.apply(edit, to: &entry)
            state.rows[user, default: [:]][key] = entry
            return LibraryWriteResult(entry: entry, created: true)
        }
    }

    func insertIfMissing(_ key: MediaKey, status: ListStatus, account: AccountContext) async throws -> LibraryWriteResult {
        try await recordWrite(.insertIfMissing(key, status), key: key)
        return state.withLock { state in
            let user = account.userId.lowercased()
            if let existing = state.rows[user]?[key] {
                return LibraryWriteResult(entry: existing, created: false)
            }
            state.nextRowId += 1
            let entry = Self.entry(key.kind, key.id, rowId: state.nextRowId, status: status)
            state.rows[user, default: [:]][key] = entry
            return LibraryWriteResult(entry: entry, created: true)
        }
    }

    func remove(_ key: MediaKey, account: AccountContext) async throws {
        try await recordWrite(.remove(key), key: key)
        state.withLock { _ = $0.rows[account.userId.lowercased()]?.removeValue(forKey: key) }
    }

    // MARK: Helpers

    private func recordWrite(_ call: Call, key: MediaKey) async throws {
        let failure: LibraryError? = state.withLock { state in
            state.calls.append(call)
            defer { state.failNextWrite = nil }
            return state.failNextWrite
        }
        if let writeGate {
            _ = try await writeGate.value(for: "\(key.kind.rawValue)-\(key.id)")
        }
        if let failure { throw failure }
    }

    /// The stored row after the server applied `edit` (fields it does not name stay unchanged).
    private static func apply(_ edit: LibraryEdit, to entry: inout LibraryEntry) {
        if case .set(let status) = edit.status { entry.status = status }
        if case .set(let progress) = edit.progress { entry.progress = progress }
        switch edit.rating {
        case .set(let rating): entry.rating = rating
        case .clear: entry.rating = nil
        case .unchanged: break
        }
        switch edit.notes {
        case .set(let notes): entry.notes = notes
        case .clear: entry.notes = nil
        case .unchanged: break
        }
        switch edit.verdict {
        case .set(let verdict): entry.verdict = verdict
        case .clear: entry.verdict = nil
        case .unchanged: break
        }
    }
}
