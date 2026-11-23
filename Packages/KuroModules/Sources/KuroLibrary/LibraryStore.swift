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
/// Runs one private request inside the credential lease of an account. It throws (for example
/// `CancellationError`) when that account is no longer current, and then the request is not sent.
public protocol LibraryCredentialLease: Sendable {
    @MainActor
    func withLease<T: Sendable>(
        for account: AccountContext,
        _ operation: @escaping @MainActor @Sendable () async throws -> T
    ) async throws -> T
}

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
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let dateAutofillEnabled: @MainActor () -> Bool
    @ObservationIgnored private let credentialLease: (any LibraryCredentialLease)?

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
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent,
        dateAutofillEnabled: @escaping @MainActor () -> Bool = { false },
        credentialLease: (any LibraryCredentialLease)? = nil
    ) {
        self.backend = backend
        self.sinks = sinks
        self.now = now
        self.calendar = calendar
        self.dateAutofillEnabled = dateAutofillEnabled
        self.credentialLease = credentialLease
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
        let state = inFlight[key]
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
        if var flight = state {
            flight.confirmed = entry
            inFlight[key] = flight
            publish(key, flight.projection(for: key))
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
        // A verbatim date is restore-only: a user-facing write never carries one.
        if edit.startedRawVerbatim != nil { return .failed(.invalidValue(field: "startedRawVerbatim")) }
        if edit.finishedRawVerbatim != nil { return .failed(.invalidValue(field: "finishedRawVerbatim")) }
        return await apply(edit, to: key, createIfMissing: createIfMissing, fillsEmptyDates: true)
    }

    /// An Undo or restore: sends exactly `edit` and never fills a date, whatever the projection holds. Every
    /// Undo the app shows that goes through an edit (removal Undo, +1 Undo) uses this, never `apply`.
    ///
    /// `replacing` is the row a removal Undo brings back. When given, the restore first makes sure the title is
    /// not tracked by a DIFFERENT row (re-added on another device after the removal: another row id or
    /// lifecycle). In that case nothing is written, the server's row becomes the projection, and the outcome is
    /// `.conflict(server:)`. The check is an insert-if-missing, which never changes an existing row, so it is the
    /// same on the PATCH path and on the revision-fence path.
    public func restore(_ edit: LibraryEdit, to key: MediaKey, createIfMissing: ListStatus? = nil,
                        account: AccountContext, replacing removed: LibraryEntry? = nil) async -> LibraryOutcome {
        // Never restore one account's row onto another account's projection.
        guard account == context else { return .failed(.notAuthenticated) }
        if let removed {
            // The probe suspends: the account binding it started under must still be the bound one before
            // anything is written (the bound account never changes silently under an Undo).
            guard let lease = currentLease() else { return .failed(.notAuthenticated) }
            if let refusal = await refusalForNewerRow(than: removed, key: key) { return refusal }
            guard holds(lease), account == context else { return .failed(.notAuthenticated) }
        }
        return await apply(edit, to: key, createIfMissing: createIfMissing, fillsEmptyDates: false)
    }

    /// The same title row: same row id and the same lifecycle (nil on both sides while the fence is off).
    private static func isSameRow(_ lhs: LibraryEntry, _ rhs: LibraryEntry) -> Bool {
        lhs.rowId == rhs.rowId && lhs.lifecycleId == rhs.lifecycleId
    }

    /// nil when the restore may proceed: the title is untracked (it is then created here) or still tracked by the
    /// removed row itself. A failed probe fails the restore, as any write failure does.
    private func refusalForNewerRow(than removed: LibraryEntry, key: MediaKey) async -> LibraryOutcome? {
        if let local = entry(for: key) {
            return Self.isSameRow(local, removed) ? nil : .failed(.conflict(server: local))
        }
        let probe = await save(key, status: removed.status)
        guard case .applied(let change) = probe else { return probe }
        if change.kind == .added { return nil }
        guard let server = change.current else { return nil }
        return Self.isSameRow(server, removed) ? nil : .failed(.conflict(server: server))
    }

    /// `fillsEmptyDates` is `false` for Undo, which must restore exactly and never fill. The release switch is
    /// read once, here, before the optimistic projection and before any backend call.
    func apply(_ original: LibraryEdit, to key: MediaKey, createIfMissing: ListStatus?,
               fillsEmptyDates: Bool) async -> LibraryOutcome {
        guard !importUndoKeys.contains(key) else { return .failed(.retryable(message: "This title is being changed by an import. Try again after Apply or Undo finishes.")) }
        if let error = original.validationError { return .failed(error) }
        var edit = original
        var autoFilled = false
        if fillsEmptyDates, original.touchesStatus, dateAutofillEnabled() {
            let projected = entry(for: key)
            // Dates are judged on the confirmed row, never on the optimistic projection: a cached row that
            // received an optimistic edit still has unknown dates. A pending optimistic date counts as present.
            var confirmed = progressBaseline(for: key)
            if var row = confirmed, let projected {
                row.status = projected.status
                if let raw = projected.sourceMetadata?.startedRaw, !raw.isBlank { row.sourceMetadata?.startedRaw = raw }
                if let raw = projected.sourceMetadata?.finishedRaw, !raw.isBlank { row.sourceMetadata?.finishedRaw = raw }
                confirmed = row
            }
            // "Creating" is only known once the account's rows are loaded: while the projection is loading,
            // failed or unbound, a missing row may exist on the server with dates this device has not read.
            let creating = projected == nil && createIfMissing != nil && loadState == .loaded
            (edit, autoFilled) = original.fillingEmptyDates(
                current: confirmed, creating: creating, today: PartialDate.day(of: now(), in: calendar))
        }
        let jumpsWithFractionalLabel: Bool = {
            guard case .set(let label) = edit.progressLabel, Int(label) == nil else { return false }
            if case .set(let target) = edit.progress, let current = entry(for: key)?.progress {
                return target != current
            }
            return false
        }()
        if (edit.touchesProgress || edit.touchesStatus || !edit.progressLabel.isUnchanged), progressAvailable,
           !jumpsWithFractionalLabel,
           let row = entry(for: key), let lifecycle = row.lifecycleId, row.revision != nil,
           let lease = currentLease() {
            // Reserve the online fields before the first suspension. Admit progress immediately,
            // so a later +1 computes from this action even while its notes PATCH is in flight.
            // The caller's own online fields go out now. An auto-filled date is a separate best-effort leg that
            // is only dispatched after the durable status intent is accepted (below), never ahead of it.
            let patch = original.patchBodyOmittingProgress
            let patchTask = patch.isEmpty ? nil : issue(.edit(patch, createIfMissing: nil), on: key)
            let fillLeg = autoFilled ? edit.dateFillLeg(comparedTo: original) : nil
            let position: Int
            if case .set(let value) = edit.progress { position = value } else { position = row.progress }
            let outcome = await applyDurableProgress(edit, position: position, to: key)
            let patchOutcome = await patchTask?.value
            guard holds(lease) else { return .failed(.notAuthenticated) }
            guard entry(for: key)?.lifecycleId == lifecycle else { return .failed(.notFound) }
            if case .failed = outcome { return outcome }
            // A failed leg that only carried the auto-filled date is best effort: the durable change stands and
            // the date was already dropped from the projection when the mutation settled.
            if case .failed(let error) = patchOutcome {
                return .failed(.retryable(message: "Progress is saved on this device; other fields could not be saved: \(error)"))
            }
            if let fillLeg, fillLegStillApplies(fillLeg, key: key) {
                // The durable intent is committed. The fill is best effort: a failed leg keeps the status and the
                // projection drops the date when the mutation settles.
                _ = await issue(.edit(fillLeg, createIfMissing: nil), on: key, leased: true).value
                guard holds(lease) else { return .failed(.notAuthenticated) }
                guard entry(for: key)?.lifecycleId == lifecycle else { return .failed(.notFound) }
            }
            guard let change = outcome.change else { return outcome }
            return .applied(LibraryChange(key: key, kind: .updated, previous: row,
                current: entry(for: key), mutationId: change.mutationId, account: lease.context))
        }
        return await enqueue(.edit(edit, createIfMissing: createIfMissing), on: key)
    }

    /// The fill leg still applies when the date it would write is still empty: a date the user (or another
    /// writer) set between the durable acceptance and this dispatch is never overwritten.
    private func fillLegStillApplies(_ leg: LibraryEdit, key: MediaKey) -> Bool {
        guard let metadata = entry(for: key)?.sourceMetadata else { return false }
        func empty(_ raw: String?) -> Bool { raw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true }
        if !leg.startedOn.isUnchanged, !empty(metadata.startedRaw) { return false }
        if !leg.finishedOn.isUnchanged, !empty(metadata.finishedRaw) { return false }
        return true
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
            return await apply(.restoring(previous), to: change.key, createIfMissing: previous.status,
                               fillsEmptyDates: false)
        case .updated:
            guard let previous = change.previous, let current = change.current else {
                return .failed(.conflict(server: change.current))
            }
            return await apply(.reverting(current, to: previous), to: change.key, createIfMissing: nil,
                               fillsEmptyDates: false)
        }
    }

    // MARK: Mutation pipeline

    private func enqueue(_ intent: MutationIntent, on key: MediaKey) async -> LibraryOutcome {
        await issue(intent, on: key).value
    }

    /// Registers a key reservation synchronously. Mixed durable/online actions must register the
    /// online leg before any disk suspension, without creating another writer or FIFO.
    private func issue(_ intent: MutationIntent, on key: MediaKey, leased: Bool = false) -> Task<LibraryOutcome, Never> {
        guard let lease = currentLease() else { return Task { .failed(.notAuthenticated) } }
        let mutation = PendingMutation(id: UUID(), intent: intent, issuedAt: now(), leased: leased)
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
                let backend = self.backend
                let baseRevision = base?.revision
                let send: @MainActor @Sendable () async throws -> LibraryWriteResult = {
                    try await backend.edit(
                        edit, key: key, createIfMissing: createIfMissing,
                        mutationId: mutation.id, baseRevision: baseRevision, account: context
                    )
                }
                let result: LibraryWriteResult
                if mutation.leased, let credentialLease {
                    // The auto-filled date leg is a new private request: it runs inside the account's lease.
                    result = try await credentialLease.withLease(for: context, send)
                } else {
                    result = try await send()
                }
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
    /// The request runs inside the account's credential lease (the auto-filled date leg).
    var leased = false
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

private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
