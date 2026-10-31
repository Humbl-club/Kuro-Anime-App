import Foundation
import KuroCore

// MARK: - Outcomes

/// What one completed library mutation changed. `previous`/`current` are the entry before and
/// after the write (`nil` = not tracked); `previous` is limited to what this mutation changed.
public struct LibraryChange: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case added
        case updated
        case removed
    }

    public let key: MediaKey
    public let kind: Kind
    public let previous: LibraryEntry?
    public let current: LibraryEntry?
    /// Generated once per operation.
    public let mutationId: UUID
    /// The account the change was made for; Undo is refused for any other account.
    public let account: AccountContext

    /// A receipt-only progress patch does not change membership, filters or reminders.
    public var isProgressOnly: Bool {
        guard kind == .updated, let previous, let current else { return false }
        return previous.lifecycleId == current.lifecycleId && previous.status == current.status
            && previous.rating == current.rating && previous.notes == current.notes && previous.verdict == current.verdict
    }

    public init(
        key: MediaKey,
        kind: Kind,
        previous: LibraryEntry?,
        current: LibraryEntry?,
        mutationId: UUID,
        account: AccountContext
    ) {
        self.key = key
        self.kind = kind
        self.previous = previous
        self.current = current
        self.mutationId = mutationId
        self.account = account
    }
}

public enum LibraryError: Error, Sendable, Equatable {
    /// Session lost, or the account changed while the operation was in flight.
    case notAuthenticated
    /// e.g. rating outside 1...10, negative progress, clearing a NOT NULL field.
    case invalidValue(field: String)
    /// Edit of a removed entry; the entry is never recreated.
    case notFound
    /// Reserved for revision conflicts; also returned by `undo` when the prior state is unknown.
    case conflict(server: LibraryEntry?)
    /// Transport failure, timeout or server error; the same request may succeed later.
    case retryable(message: String)
    /// Capability not configured or a non-retryable server rejection.
    case unavailable(message: String)
}

public enum LibraryOutcome: Sendable, Equatable {
    case applied(LibraryChange)
    case failed(LibraryError)

    public var change: LibraryChange? {
        if case .applied(let change) = self { return change }
        return nil
    }

    public var error: LibraryError? {
        if case .failed(let error) = self { return error }
        return nil
    }
}

// MARK: - Backend port

/// A canonical row returned by a write, plus whether this write created it. `created` lets Undo
/// delete only rows the undone operation inserted (an ignored insert or a PATCH is never `created`).
public struct LibraryWriteResult: Sendable, Equatable {
    public let entry: LibraryEntry
    public let created: Bool

    public init(entry: LibraryEntry, created: Bool) {
        self.entry = entry
        self.created = created
    }
}

/// Persistence port of the tracking domain. Implementations throw `LibraryError`.
public protocol LibraryBackend: Sendable {
    func fetchAll(for account: AccountContext) async throws -> [LibraryEntry]
    func edit(
        _ edit: LibraryEdit,
        key: MediaKey,
        createIfMissing: ListStatus?,
        mutationId: UUID,
        baseRevision: Int64?,
        account: AccountContext
    ) async throws -> LibraryWriteResult
    /// Ensures the title is tracked; never changes an existing row.
    func insertIfMissing(_ key: MediaKey, status: ListStatus, account: AccountContext) async throws -> LibraryWriteResult
    /// Idempotent: removing an untracked title succeeds.
    func remove(_ key: MediaKey, account: AccountContext) async throws
    /// Removal with the caller's mutation id and base revision, so a retry hits the same receipt.
    func remove(_ key: MediaKey, mutationId: UUID, baseRevision: Int64?, account: AccountContext) async throws
}

extension LibraryBackend {
    public func remove(_ key: MediaKey, mutationId: UUID, baseRevision: Int64?, account: AccountContext) async throws {
        try await remove(key, account: account)
    }
}

// MARK: - Load-state-aware lookup

/// A lookup of one title that must tell "not tracked" from "not known yet"
/// (`LibraryStore.entry(for: LibraryKnowledgeQuery)`).
public struct LibraryKnowledgeQuery: Sendable, Hashable {
    public let key: MediaKey

    public init(_ key: MediaKey) {
        self.key = key
    }
}

/// What the Library knows about one title.
public enum LibraryKnowledge: Sendable, Equatable {
    /// The projection holds the title (confirmed or pending local entry).
    case tracked(LibraryEntry)
    /// The bound account's rows are loaded and do not hold the title.
    case untracked
    /// The bound account's rows are not loaded (yet, or the load failed): the title may be tracked.
    case unknown

    /// The entry when tracked.
    public var entry: LibraryEntry? {
        if case .tracked(let entry) = self { return entry }
        return nil
    }
}

// MARK: - Reader / writer / change fan-out

@MainActor
public protocol LibraryReading {
    func entry(for key: MediaKey) -> LibraryEntry?
    func isTracked(_ key: MediaKey) -> Bool
    func keys(withStatus status: ListStatus, kind: MediaKind) -> Set<MediaKey>
    /// Ordered by `updatedAt`, newest first.
    var allEntries: [LibraryEntry] { get }
}

extension LibraryReading {
    /// Legacy favourite rule: rating 9 or 10.
    public func isFavorited(_ key: MediaKey) -> Bool {
        entry(for: key)?.isFavorited ?? false
    }
}

@MainActor
public protocol LibraryWriting {
    /// Ensures the title is tracked. Never overwrites an existing entry.
    func save(_ key: MediaKey, status: ListStatus) async -> LibraryOutcome
    func apply(_ edit: LibraryEdit, to key: MediaKey, createIfMissing: ListStatus?) async -> LibraryOutcome
    func remove(_ key: MediaKey) async -> LibraryOutcome
    /// Compensating absolute edit, re-save or removal built from `change.previous`.
    func undo(_ change: LibraryChange) async -> LibraryOutcome
}

extension LibraryWriting {
    public func apply(_ edit: LibraryEdit, to key: MediaKey) async -> LibraryOutcome {
        await apply(edit, to: key, createIfMissing: nil)
    }
}

/// Receives every local mutation the backend applied, on the main actor, after the projection
/// reflects it. Not called for refreshes, failures, or operations that wrote nothing (saving an
/// already tracked title, an empty edit). Every applied removal is delivered, also of a title the
/// projection did not hold (`previous == nil`): the server may have held it. Registered explicitly
/// by app composition (no global bus).
@MainActor
public protocol LibraryChangeSink {
    func libraryDidChange(_ change: LibraryChange)
}
