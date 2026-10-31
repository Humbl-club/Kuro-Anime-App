import Foundation

// MARK: - Account session lifecycle
// One account context per signed-in user. Every async completion that publishes
// private state captures the context before its first suspension point and checks
// `isCurrent` before writing, so work started for a previous account is dropped.
//
// Credential leases (F33): a result guard is not enough for a private REQUEST. The Supabase SDK
// attaches the access token it holds when the request is DISPATCHED (supabase-swift 2.54.1
// `SupabaseClient.adapt(request:)` overwrites `Authorization` with `auth.session.accessToken`), not
// the account the app captured earlier. So a private request runs as a lease on its account context
// (`withCredentialLease`):
// - it is admitted only while that context is current and no credential change is in progress;
// - its work starts on a later turn of the main actor and is re-validated right before it runs, so a
//   transition between admission and dispatch sends nothing;
// - every transition that replaces or ends the context (`begin` of another user, `end`) cancels it;
// - the session funnel brackets every SDK call that installs a session (sign-in, sign-up, Apple,
//   callback) with `beginCredentialChange` / `endCredentialChange`: the gate closes, every lease in
//   flight finishes first, and none is admitted until the change ended. So the SDK never holds another
//   account's token while a lease can still be dispatched.
// No client-supplied user id is involved: the server keeps deriving the user from the JWT; the lease
// only guarantees that the JWT attached is the originating account's.

/// Identity of one signed-in account period. A new generation starts on every
/// sign-in of a different user and on every sign-out.
public struct AccountContext: Sendable, Equatable {
    public let userId: String
    public let generation: Int

    public init(userId: String, generation: Int) {
        self.userId = userId
        self.generation = generation
    }
}

/// Owns the current account context and its generation counter.
@MainActor
public final class AccountSessionCoordinator {
    public enum Transition: Equatable, Sendable {
        /// The same user is already current (token refresh, repeated sign-in, restore).
        case unchanged(AccountContext)
        /// A user signed in from the signed-out state.
        case started(AccountContext)
        /// A different user replaced the current one.
        case switched(from: AccountContext, to: AccountContext)
    }

    /// One credential change of the session funnel (see `beginCredentialChange`).
    public struct CredentialChange: Equatable, Sendable {
        fileprivate let token: Int
    }

    public private(set) var current: AccountContext?
    private var generation = 0

    /// A private request in flight on behalf of an account context.
    private struct Lease {
        let context: AccountContext?
        let cancel: @Sendable () -> Void
    }

    private var leases: [Int: Lease] = [:]
    private var nextLeaseToken = 0
    private var activeCredentialChange: CredentialChange?
    private var nextCredentialChangeToken = 0
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    /// Begins (or keeps) the session for `userId`. User ids compare case-insensitively
    /// because the SDK's `uuidString` is upper-case while JWT subjects are lower-case.
    /// A new context cancels every credential lease of the previous one.
    public func begin(userId: String) -> Transition {
        if let current, Self.sameUser(current.userId, userId) {
            return .unchanged(current)
        }
        generation += 1
        let next = AccountContext(userId: userId, generation: generation)
        let previous = current
        current = next
        revokeObsoleteLeases()
        if let previous {
            return .switched(from: previous, to: next)
        }
        return .started(next)
    }

    /// Ends the current session. Idempotent: ending while signed out changes nothing.
    /// Every credential lease of the ended context is cancelled.
    public func end() {
        guard current != nil else { return }
        generation += 1
        current = nil
        revokeObsoleteLeases()
    }

    /// `true` when `context` still describes the session in effect. A `nil` context
    /// (work started while signed out, e.g. public loads) is current only while signed out.
    public func isCurrent(_ context: AccountContext?) -> Bool {
        current == context
    }

    public nonisolated static func sameUser(_ lhs: String, _ rhs: String) -> Bool {
        lhs.lowercased() == rhs.lowercased()
    }

    // MARK: Credential leases (F33)

    /// Whether a credential lease is in flight (tests; the funnel waits for none to be left).
    public var hasCredentialLeases: Bool { !leases.isEmpty }

    /// Whether the session funnel is installing SDK credentials (no lease is admitted meanwhile).
    public var isChangingCredentials: Bool { activeCredentialChange != nil }

    /// Runs `operation` (a private request through the shared SDK client) as a credential lease of
    /// `context`. Throws `CancellationError`, without running it, when `context` is not current or a
    /// credential change is in progress, at admission and again right before it starts (it starts on a
    /// later turn). An account transition cancels it; a cancelled lease throws `CancellationError`
    /// whatever its request reported. Caller cancellation is forwarded.
    public func withCredentialLease<T: Sendable>(
        for context: AccountContext?,
        _ operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        guard admitsLease(for: context) else { throw CancellationError() }
        nextLeaseToken += 1
        let token = nextLeaseToken
        let task = Task<T, Error> { @MainActor in
            guard !Task.isCancelled, self.admitsLease(for: context) else { throw CancellationError() }
            return try await operation()
        }
        leases[token] = Lease(context: context, cancel: { task.cancel() })
        defer { finishLease(token) }
        let value: T
        do {
            value = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        } catch {
            if task.isCancelled { throw CancellationError() }
            throw error
        }
        // Revoked (its context ended) or abandoned by its caller while in flight: the outcome belongs to
        // nobody current.
        if task.isCancelled { throw CancellationError() }
        return value
    }

    /// Closes the credential gate for an SDK call that installs a session, and returns once every
    /// credential lease in flight has finished (leases of an ended context were cancelled by the
    /// transition; the current context's finish normally). No lease is admitted until
    /// `endCredentialChange` (or a newer change) ends it.
    public func beginCredentialChange() async -> CredentialChange {
        nextCredentialChangeToken += 1
        let change = CredentialChange(token: nextCredentialChangeToken)
        activeCredentialChange = change
        while !leases.isEmpty {
            await withCheckedContinuation { drainWaiters.append($0) }
        }
        return change
    }

    /// Reopens the gate closed by `change`; a no-op when a newer change replaced it (or it already ended).
    public func endCredentialChange(_ change: CredentialChange) {
        guard activeCredentialChange == change else { return }
        activeCredentialChange = nil
    }

    private func admitsLease(for context: AccountContext?) -> Bool {
        activeCredentialChange == nil && isCurrent(context)
    }

    private func revokeObsoleteLeases() {
        for lease in leases.values where lease.context != current {
            lease.cancel()
        }
    }

    private func finishLease(_ token: Int) {
        leases[token] = nil
        guard leases.isEmpty, !drainWaiters.isEmpty else { return }
        let waiters = drainWaiters
        drainWaiters = []
        for waiter in waiters { waiter.resume() }
    }
}
