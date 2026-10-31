import Foundation
import KuroCore
import Observation

/// The single authoritative local tracking projection.
///
/// - One projection `[MediaKey: LibraryEntry]`; every lookup is derived from it at read time.
/// - Mutations are serialized per `MediaKey` (FIFO) and run concurrently across keys.
/// - A mutation is projected optimistically when it is issued, then replaced by the backend's
///   canonical row; on failure only that mutation is withdrawn and a typed error is returned.
/// - A refresh that started before a local mutation of key K never overwrites K.
/// - Bound to one `AccountContext`: work of an ended or replaced context returns
///   `.notAuthenticated`, never sends after the switch and never publishes.
/// - Progress uses an account-scoped durable outbox; other edits retain their existing online contract.
/// - `loadState` says whether the projection holds the bound account's rows yet: until a refresh of
///   the current binding has published, a title missing from the projection is UNKNOWN, not untracked
///   (`entry(for: LibraryKnowledgeQuery)`).
@MainActor
@Observable
public final class LibraryStore: LibraryReading, LibraryWriting {
    /// Whether the projection holds the bound account's rows (observable).
    public enum LoadState: Sendable, Equatable {
        /// Signed out, or bound to an account whose rows were not requested yet.
        case notLoaded
        /// The binding's first refresh is in flight (none has published for this binding yet).
        case loading
        /// A refresh of the bound account published its rows. Stays loaded through later refreshes,
        /// including failed ones (the projection keeps the published rows).
        case loaded
        /// The binding's latest refresh failed and none has published for this binding yet.
        case failed
    }

    private(set) var entries: [MediaKey: LibraryEntry] = [:] {
        didSet { orderedEntries = nil }
    }
    private(set) var context: AccountContext?
    /// Whether the projection holds the bound account's rows; reset with every new binding.
    public private(set) var loadState: LoadState = .notLoaded
    /// `allEntries` in display order, rebuilt at most once per projection change (dropped whenever
    /// `entries` is replaced or mutated), so repeated reads between mutations never re-sort.
    @ObservationIgnored private var orderedEntries: [LibraryEntry]?

    var progressState: LibraryProgressState?

    @ObservationIgnored private let backend: any LibraryBackend
    @ObservationIgnored private let sinks: [any LibraryChangeSink]
    @ObservationIgnored private let now: @Sendable () -> Date

    /// Tail of the FIFO chain per key.
    @ObservationIgnored private var queues: [MediaKey: Task<Void, Never>] = [:]
    /// Keys with issued-but-unsettled mutations: the last backend-confirmed entry plus the
    /// optimistic mutations layered on top of it, in issue order.
    @ObservationIgnored private var inFlight: [MediaKey: KeyMutations] = [:]
    /// Local publication sequence (monotonic) and the last value per key, for stale-refresh checks.
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var lastLocalChange: [MediaKey: Int] = [:]
    /// Refresh generations: an older refresh never replaces a newer one's result.
    @ObservationIgnored private var refreshesStarted = 0
    @ObservationIgnored private var newestPublishedRefresh = 0
    /// Bumped whenever the projection is dropped, so work started before a `reset()` stays stale
    /// even if the same context is bound again.
    @ObservationIgnored private var bindingEpoch = 0
    @ObservationIgnored var importUndoKeys: Set<MediaKey> = []

    public init(
        backend: any LibraryBackend,
        sinks: [any LibraryChangeSink] = [],
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.backend = backend
        self.sinks = sinks
        self.now = now
    }

    // MARK: Account binding

    /// Binds the store to `context`. Binding a different context drops the previous projection and
    /// every pending mutation's bookkeeping; the same context is a no-op (same-user refresh).
    public func bind(_ context: AccountContext) {
        guard context != self.context else { return }
        clearProjection()
        self.context = context
    }

    /// Signed out: drops the projection; in-flight work completes as `.notAuthenticated`.
    public func reset() {
        clearProjection()
        context = nil
    }

    private func clearProjection() {
        cancelProgressWork()
        progressState?.clearProjection()
        bindingEpoch += 1
        loadState = .notLoaded
        entries = [:]
        queues = [:]
        inFlight = [:]
        lastLocalChange = [:]
        importUndoKeys = []
    }

    // MARK: Reading

    public func entry(for key: MediaKey) -> LibraryEntry? {
        entries[key].map { projectDurableProgress($0) }
    }

    /// The confirmed baseline excludes durable/online optimistic overlays from cached rows.
    public func progressBaseline(for key: MediaKey) -> LibraryEntry? { inFlight[key]?.confirmed ?? entries[key] }

    /// A bounded personal snapshot knows only these rows. Missing titles remain UNKNOWN and a
    /// successful complete server refresh remains the only authority for definitive absence.
    public func restoreCachedProgressBaselines(_ rows: [LibraryEntry], account: AccountContext) {
        guard context == account, loadState != .loaded else { return }
        for row in rows where entries[row.key] == nil && lastLocalChange[row.key] == nil && inFlight[row.key] == nil {
            guard row.rowId > 0, row.lifecycleId != nil, row.revision != nil else { continue }
            entries[row.key] = row
        }
    }

    public func isMutating(_ key: MediaKey) -> Bool { inFlight[key] != nil || pendingProgress(for: key) != nil }

    public func isTracked(_ key: MediaKey) -> Bool {
        entries[key] != nil
    }

    /// What the store knows about one title: its entry, untracked (the bound account's rows are
    /// loaded and do not hold it), or unknown (not loaded yet, or the load failed). Callers that must
    /// not mistake "not loaded" for "not tracked" (import reconciliation) call it with an explicit
    /// `LibraryKnowledgeQuery`, never through a function reference whose overload the compiler picks.
    public func entry(for query: LibraryKnowledgeQuery) -> LibraryKnowledge {
        if let entry = entry(for: query.key) { return .tracked(entry) }
        return loadState == .loaded ? .untracked : .unknown
    }

    public func keys(withStatus status: ListStatus, kind: MediaKind) -> Set<MediaKey> {
        Set(allEntries.lazy.filter { $0.key.kind == kind && $0.status == status }.map(\.key))
    }

    public var allEntries: [LibraryEntry] {
        // Reading `entries` first registers Observation tracking even when the order is cached.
        let projection = entries
        _ = progressState?.pending
        _ = progressState?.confirmed
        if let orderedEntries { return orderedEntries }
        let ordered = projection.values.map { projectDurableProgress($0) }.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            if lhs.key.kind != rhs.key.kind { return lhs.key.kind == .anime }
            return lhs.key.id < rhs.key.id
        }
        orderedEntries = ordered
        return ordered
    }

    var activeBindingEpoch: Int { bindingEpoch }

    func invalidateProgressOrdering() { orderedEntries = nil }

    // MARK: Refresh

    /// Replaces the projection with the backend's rows, except for keys with a local mutation that
    /// is still pending or was published after this refresh started. Change sinks are not called.
    public func refresh() async throws(LibraryError) {
        guard let lease = currentLease() else { throw .notAuthenticated }
        refreshesStarted += 1
        let generation = refreshesStarted
        let startedAtSequence = sequence
        if loadState != .loaded { loadState = .loading }

        let rows: [LibraryEntry]
        do {
            rows = try await backend.fetchAll(for: lease.context)
        } catch {
            guard holds(lease) else { throw .notAuthenticated }
            if loadState != .loaded { loadState = .failed }
            throw Self.libraryError(error)
        }
        guard holds(lease) else { throw .notAuthenticated }
        guard generation > newestPublishedRefresh else { return }
        newestPublishedRefresh = generation
        loadState = .loaded

        var next: [MediaKey: LibraryEntry] = [:]
        for row in rows { next[row.key] = row }
        for key in Set(entries.keys).union(next.keys) where isLocallyNewer(key, than: startedAtSequence) {
            next[key] = entries[key]
        }
        entries = next
    }

    /// The outbox uses the same FIFO admission as edits/removals. Reserve the complete batch
    /// synchronously, before any suspension; disjoint keys continue independently.
    public func withMutationReservation<T: Sendable>(
        keys: [MediaKey], account: AccountContext,
        operation: @escaping @MainActor @Sendable () async throws -> T
    ) async throws -> T {
        guard let lease = currentLease(), lease.context == account else { throw LibraryError.notAuthenticated }
        let unique = Array(Set(keys))
        let predecessors = unique.compactMap { queues[$0] }
        let result = Task { @MainActor in
            for predecessor in predecessors { await predecessor.value }
            guard self.holds(lease), !Task.isCancelled else { throw LibraryError.notAuthenticated }
            let value = try await operation()
            guard self.holds(lease) else { throw LibraryError.notAuthenticated }
            return value
        }
        let tail = Task { _ = await result.result }
        for key in unique { queues[key] = tail }
        defer { for key in unique where queues[key] == tail { queues[key] = nil } }
        return try await withTaskCancellationHandler {
            try await result.value
        } onCancel: {
            result.cancel()
        }
    }

    /// A receipt only patches its own account/lifecycle, and never lowers a confirmed revision.
    /// Later optimistic Library edits stay layered over the patched confirmed base.
    public func adoptServerProgress(key: MediaKey, account: AccountContext, lifecycleId: UUID,
                                    progress: Int, revision: Int64, status: ListStatus? = nil, mutationId: UUID? = nil, progressLabel: String? = nil, unitId: UUID? = nil, writesPosition: Bool = true) {
        guard context == account else { return }
        var state = inFlight[key]
        guard var entry = state?.confirmed ?? entries[key], entry.lifecycleId == lifecycleId,
              revision >= (entry.revision ?? 0) else { return }
        let previous = entry
        let changed = entry.progress != progress || (status != nil && entry.status != status)
            || (writesPosition && (entry.progressLabel != progressLabel || entry.unitId != unitId))
        entry.progress = progress
        if writesPosition { entry.progressLabel = progressLabel; entry.unitId = unitId }
        if let status { entry.status = status }
        entry.revision = revision
        entry.updatedAt = now()
        if state != nil {
            state!.confirmed = entry
            inFlight[key] = state
            publish(key, state!.projection(for: key))
        } else { publish(key, entry) }
        if changed, let mutationId {
            let change = LibraryChange(key: key,kind: .updated,previous: previous,current: entry,
                mutationId: mutationId,account: account)
            for sink in sinks { sink.libraryDidChange(change) }
        }
    }

    private func isLocallyNewer(_ key: MediaKey, than startedAtSequence: Int) -> Bool {
        // Import Undo reserves admission without adding an optimistic Library mutation.
        // Its own authoritative post-compensation read must replace/remove those rows.
        (queues[key] != nil && !importUndoKeys.contains(key)) || inFlight[key] != nil || (lastLocalChange[key] ?? 0) > startedAtSequence
    }

    // MARK: Writing

    public func save(_ key: MediaKey, status: ListStatus) async -> LibraryOutcome {
        guard !importUndoKeys.contains(key) else { return .failed(.retryable(message: "This title is being changed by an import. Try again after Apply or Undo finishes.")) }
        return await enqueue(.save(status), on: key)
    }

    public func apply(_ edit: LibraryEdit, to key: MediaKey, createIfMissing: ListStatus? = nil) async -> LibraryOutcome {
        guard !importUndoKeys.contains(key) else { return .failed(.retryable(message: "This title is being changed by an import. Try again after Apply or Undo finishes.")) }
        if let error = edit.validationError { return .failed(error) }
        if (edit.touchesProgress || edit.touchesStatus), progressAvailable,
           let row = entry(for: key), let lifecycle = row.lifecycleId, row.revision != nil,
           let lease = currentLease() {
            // Reserve the online fields before the first suspension. Admit progress immediately,
            // so a later +1 computes from this action even while its notes PATCH is in flight.
            let patch = edit.patchBodyOmittingProgress
            let patchTask = patch.isEmpty ? nil : issue(.edit(patch, createIfMissing: nil), on: key)
            let position: Int
            if case .set(let value) = edit.progress { position = value } else { position = row.progress }
            let outcome = await applyDurableProgress(edit, position: position, to: key)
            let patchOutcome = await patchTask?.value
            guard holds(lease) else { return .failed(.notAuthenticated) }
            guard entry(for: key)?.lifecycleId == lifecycle else { return .failed(.notFound) }
            if case .failed = outcome { return outcome }
            if case .failed(let error) = patchOutcome {
                return .failed(.retryable(message: "Progress is saved on this device; other fields could not be saved: \(error)"))
            }
            guard let change = outcome.change else { return outcome }
            return .applied(LibraryChange(key: key, kind: .updated, previous: row,
                current: entry(for: key), mutationId: change.mutationId, account: lease.context))
        }
        return await enqueue(.edit(edit, createIfMissing: createIfMissing), on: key)
    }

    public func remove(_ key: MediaKey) async -> LibraryOutcome {
        guard !importUndoKeys.contains(key) else { return .failed(.retryable(message: "This title is being changed by an import. Try again after Apply or Undo finishes.")) }
        return await enqueue(.remove, on: key)
    }

    public func undo(_ change: LibraryChange) async -> LibraryOutcome {
        // Never compensate one account's change on another account's rows.
        guard change.account == context else { return .failed(.notAuthenticated) }
        switch change.kind {
        case .added:
            return await remove(change.key)
        case .removed:
            guard let previous = change.previous else { return .failed(.conflict(server: nil)) }
            return await apply(.restoring(previous), to: change.key, createIfMissing: previous.status)
        case .updated:
            guard let previous = change.previous, let current = change.current else {
                return .failed(.conflict(server: change.current))
            }
            return await apply(.reverting(current, to: previous), to: change.key, createIfMissing: nil)
        }
    }

    // MARK: Mutation pipeline

    private func enqueue(_ intent: MutationIntent, on key: MediaKey) async -> LibraryOutcome {
        await issue(intent, on: key).value
    }

    /// Registers a key reservation synchronously. Mixed durable/online actions must register the
    /// online leg before any disk suspension, without creating another writer or FIFO.
    private func issue(_ intent: MutationIntent, on key: MediaKey) -> Task<LibraryOutcome, Never> {
        guard let lease = currentLease() else { return Task { .failed(.notAuthenticated) } }
        let mutation = PendingMutation(id: UUID(), intent: intent, issuedAt: now())
        var state = inFlight[key] ?? KeyMutations(confirmed: entries[key], pending: [])
        state.pending.append(mutation)
        inFlight[key] = state
        publish(key, state.projection(for: key))
        let predecessor = queues[key]
        let task = Task { () -> LibraryOutcome in
            _ = await predecessor?.value
            return await self.execute(mutation, on: key, lease: lease)
        }
        let tail = Task { _ = await task.value }
        queues[key] = tail
        return Task {
            let outcome = await task.value
            if self.queues[key] == tail { self.queues[key] = nil }
            return outcome
        }
    }

    private func execute(_ mutation: PendingMutation, on key: MediaKey, lease: Lease) async -> LibraryOutcome {
        // Obsolete account work never sends.
        guard holds(lease) else { return .failed(.notAuthenticated) }
        let context = lease.context
        let base = inFlight[key]?.confirmed
        func change(_ kind: LibraryChange.Kind, _ previous: LibraryEntry?, _ current: LibraryEntry?) -> LibraryChange {
            LibraryChange(key: key, kind: kind, previous: previous, current: current, mutationId: mutation.id, account: context)
        }

        do {
            let applied: LibraryChange
            switch mutation.intent {
            case .save(let status):
                let result = try await backend.insertIfMissing(key, status: status, account: context)
                guard holds(lease) else { return .failed(.notAuthenticated) }
                applied = result.created
                    ? change(.added, nil, result.entry)
                    : change(.updated, result.entry, result.entry)
                settle(mutation, on: key, .confirm(result.entry))

            case .edit(let edit, let createIfMissing):
                if edit.isEmpty, let base {
                    settle(mutation, on: key, .keepBase)
                    return .applied(change(.updated, base, base))
                }
                let result = try await backend.edit(
                    edit,
                    key: key,
                    createIfMissing: createIfMissing,
                    mutationId: mutation.id,
                    baseRevision: base?.revision,
                    account: context
                )
                guard holds(lease) else { return .failed(.notAuthenticated) }
                if result.created {
                    applied = change(.added, nil, result.entry)
                } else {
                    // Pre-image limited to the edited fields; unknown when the projection lacked the row.
                    let previous = base.map { result.entry.withEditedFields(of: edit, from: $0) }
                    applied = change(.updated, previous, result.entry)
                }
                settle(mutation, on: key, .confirm(result.entry))

            case .remove:
                try await backend.remove(key, mutationId: mutation.id, baseRevision: base?.revision, account: context)
                guard holds(lease) else { return .failed(.notAuthenticated) }
                applied = change(.removed, base, nil)
                settle(mutation, on: key, .confirm(nil))
            }

            // A removal is always fanned out: the server may have held a row the projection did not
            // (finding F7), so reminders and pages keyed by the title must still go.
            if applied.previous != applied.current || applied.kind == .removed {
                for sink in sinks { sink.libraryDidChange(applied) }
            }
            return .applied(applied)
        } catch {
            guard holds(lease) else { return .failed(.notAuthenticated) }
            let failure = Self.libraryError(error)
            // `.notFound` is the server's answer that the row is gone: confirm the absence.
            settle(mutation, on: key, failure == .notFound ? .confirm(nil) : .keepBase)
            return .failed(failure)
        }
    }

    /// Withdraws `mutation` from the key's pending list, optionally replacing the confirmed base,
    /// and republishes the key.
    private func settle(_ mutation: PendingMutation, on key: MediaKey, _ settlement: Settlement) {
        guard var state = inFlight[key] else { return }
        state.pending.removeAll { $0.id == mutation.id }
        if case .confirm(let entry) = settlement { state.confirmed = entry }
        inFlight[key] = state.pending.isEmpty ? nil : state
        publish(key, state.projection(for: key))
    }

    private func publish(_ key: MediaKey, _ entry: LibraryEntry?) {
        sequence += 1
        lastLocalChange[key] = sequence
        if entries[key] != entry { entries[key] = entry }
    }

    /// The binding an operation was started under.
    private struct Lease {
        let context: AccountContext
        let epoch: Int
    }

    private func currentLease() -> Lease? {
        context.map { Lease(context: $0, epoch: bindingEpoch) }
    }

    private func holds(_ lease: Lease) -> Bool {
        context == lease.context && bindingEpoch == lease.epoch
    }

    private static func libraryError(_ error: any Error) -> LibraryError {
        if let error = error as? LibraryError { return error }
        if error is CancellationError { return .retryable(message: "cancelled") }
        return .retryable(message: String(describing: error))
    }
}

// MARK: - Pending mutation bookkeeping

private enum MutationIntent: Sendable {
    case save(ListStatus)
    case edit(LibraryEdit, createIfMissing: ListStatus?)
    case remove

    /// Optimistic projection of this intent onto `entry`.
    func project(_ entry: LibraryEntry?, key: MediaKey, at time: Date) -> LibraryEntry? {
        switch self {
        case .save(let status):
            return entry ?? .provisional(key, status: status, at: time)
        case .edit(let edit, let createIfMissing):
            if let entry { return entry.applying(edit, at: time) }
            guard let createIfMissing else { return nil }
            return LibraryEntry.provisional(key, status: createIfMissing, at: time).applying(edit, at: time)
        case .remove:
            return nil
        }
    }
}

private enum Settlement {
    /// The backend's answer for the key (`nil` = not tracked) becomes the confirmed base.
    case confirm(LibraryEntry?)
    /// The confirmed base stays as it was (failure, no-op).
    case keepBase
}

private struct PendingMutation: Sendable {
    let id: UUID
    let intent: MutationIntent
    let issuedAt: Date
}

private struct KeyMutations {
    var confirmed: LibraryEntry?
    var pending: [PendingMutation]

    func projection(for key: MediaKey) -> LibraryEntry? {
        pending.reduce(confirmed) { entry, mutation in
            mutation.intent.project(entry, key: key, at: mutation.issuedAt)
        }
    }
}
