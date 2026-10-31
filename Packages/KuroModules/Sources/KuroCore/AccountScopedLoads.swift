import Foundation

/// De-duplicates in-flight loads per key without letting work cross accounts.
/// - A call joins an existing entry only for the same key AND the same account context.
/// - An entry for a different context is cancelled and replaced.
/// - A finished load clears its slot only if the slot still holds its own entry,
///   so an obsolete completion can never remove its successor.
@MainActor
public final class AccountScopedLoads<Key: Hashable, Value: Sendable> {
    private struct Entry {
        let token: Int
        let context: AccountContext?
        let task: Task<Value, Error>
    }

    private var entries: [Key: Entry] = [:]
    private var nextToken = 0

    public init() {}

    /// Runs `work` for `key` on behalf of `context`, joining an in-flight entry only when it was
    /// started for the same key and context; an entry for another context is cancelled and replaced.
    public func run(
        key: Key,
        context: AccountContext?,
        priority: TaskPriority? = nil,
        work: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        if let existing = entries[key] {
            if existing.context == context {
                return try await existing.task.value
            }
            existing.task.cancel()
        }
        return try await start(key: key, context: context, priority: priority, work: work)
    }

    /// Starts new work for `key` even when an entry for the same context is in flight: for a read that
    /// must observe a write which completed after that entry started. The earlier entry is not
    /// cancelled (its callers still get its value) but is no longer joined; later `run` calls for the
    /// same context join this one. An entry for another context is cancelled, as in `run`.
    public func runFresh(
        key: Key,
        context: AccountContext?,
        priority: TaskPriority? = nil,
        work: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        if let existing = entries[key], existing.context != context {
            existing.task.cancel()
        }
        return try await start(key: key, context: context, priority: priority, work: work)
    }

    private func start(
        key: Key,
        context: AccountContext?,
        priority: TaskPriority?,
        work: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        nextToken += 1
        let token = nextToken
        let task = Task(priority: priority) { try await work() }
        entries[key] = Entry(token: token, context: context, task: task)
        defer {
            if entries[key]?.token == token { entries[key] = nil }
        }
        return try await task.value
    }

    /// Whether an entry for `key` is in flight.
    public func isRunning(_ key: Key) -> Bool {
        entries[key] != nil
    }

    /// Whether an entry for `key` is in flight for exactly `context`.
    public func isRunning(_ key: Key, for context: AccountContext?) -> Bool {
        guard let entry = entries[key] else { return false }
        return entry.context == context
    }

    /// Cancels every entry and forgets it (session end / account switch).
    public func cancelAll() {
        for entry in entries.values { entry.task.cancel() }
        entries.removeAll()
    }
}
