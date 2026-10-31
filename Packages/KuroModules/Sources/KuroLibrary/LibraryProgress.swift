import Foundation
import KuroCore
import Observation

/// A transport receipt, independent of the app's RPC/SDK representation.
public struct LibraryProgressReceipt: Sendable {
    public let mutationId: UUID
    public let outcome: String
    public let position: Int?
    public let revision: Int64?
    public init(mutationId: UUID, outcome: String, position: Int?, revision: Int64?) {
        self.mutationId = mutationId; self.outcome = outcome; self.position = position; self.revision = revision
    }
}

public struct LibraryProgressConflict: Sendable, Equatable {
    public let mutationId: UUID
    public let decisionIntent: ProgressIntent
    public let key: MediaKey
    public let localPosition: Int
    public let serverPosition: Int
    public let serverRevision: Int64
    public let lifecycleId: UUID
}

/// Subordinate bookkeeping owned exclusively by LibraryStore. It is observable so every Library
/// reader sees the same durable overlay, without a Home/Collection copy or an alternate writer.
@MainActor @Observable
final class LibraryProgressState {
    let outbox: ProgressOutbox
    let acceptsWrites: @MainActor @Sendable () -> Bool
    let send: @MainActor @Sendable ([ProgressIntent], AccountContext) async throws -> [LibraryProgressReceipt]
    var pending: [MediaKey: ProgressIntent] = [:]
    var confirmed: [MediaKey: ProgressIntent] = [:]
    var acknowledgements: [MediaKey: ProgressIntent] = [:]
    var conflict: LibraryProgressConflict?
    var message: String?
    @ObservationIgnored var generation = 0
    @ObservationIgnored var task: Task<Void, Never>?
    @ObservationIgnored var retry: Task<Void, Never>?
    @ObservationIgnored var taskToken: UUID?
    @ObservationIgnored var drainToken: UUID?
    @ObservationIgnored var retryAttempt = 0
    @ObservationIgnored var needsDrain = false

    init(outbox: ProgressOutbox, acceptsWrites: @escaping @MainActor @Sendable () -> Bool, send: @escaping @MainActor @Sendable ([ProgressIntent], AccountContext) async throws -> [LibraryProgressReceipt]) {
        self.outbox = outbox; self.send = send; self.acceptsWrites = acceptsWrites
    }
    func clearProjection() {
        generation += 1; pending = [:]; confirmed = [:]; acknowledgements = [:]; conflict = nil; message = nil
    }
}

extension LibraryStore {
    /// Composition supplies transport once. The closure must lease the exact supplied account.
    /// The owner controls persistence, projection, sequencing, receipts, recovery and retries.
    public func configureProgress(outbox: ProgressOutbox, acceptsWrites: @escaping @MainActor @Sendable () -> Bool = { true }, send: @escaping @MainActor @Sendable ([ProgressIntent], AccountContext) async throws -> [LibraryProgressReceipt]) {
        guard progressState == nil else { return }
        progressState = LibraryProgressState(outbox: outbox, acceptsWrites: acceptsWrites, send: send)
    }

    public var progressAvailable: Bool { progressState?.acceptsWrites() == true }
    public var progressConflict: LibraryProgressConflict? { progressState?.conflict }
    public func pendingTracking(for keys: Set<MediaKey>) -> Bool {
        keys.contains { isMutating($0) || progressState?.conflict?.key == $0 }
    }

    public func hasPendingTracking(for keys: Set<MediaKey>, account: AccountContext) async throws -> Bool {
        guard context == account else { throw LibraryError.notAuthenticated }
        if pendingTracking(for: keys) { return true }
        guard let state = progressState else { return false }
        let epoch = activeBindingEpoch
        let active = try await state.outbox.active(accountId: account.userId.lowercased())
        guard context == account, activeBindingEpoch == epoch else { throw LibraryError.notAuthenticated }
        if active.contains(where: { keys.contains(progressKey($0)) }) { return true }
        var cursor: Int64 = 0
        while true {
            let conflicts = try await state.outbox.conflicts(accountId: account.userId.lowercased(), afterSequence: cursor)
            guard context == account, activeBindingEpoch == epoch else { throw LibraryError.notAuthenticated }
            if conflicts.contains(where: { keys.contains(progressKey($0)) }) { return true }
            if conflicts.count < 50 { return pendingTracking(for: keys) }
            cursor = conflicts.last!.localSequence
        }
    }

    /// Apply, Resume and Undo share the existing per-title FIFO and close only affected admission.
    public func withImportMutationReservation<T: Sendable>(keys: Set<MediaKey>, account: AccountContext,
        operation: @escaping @MainActor @Sendable () async throws -> T) async throws -> T {
        guard context == account else { throw LibraryError.notAuthenticated }
        guard importUndoKeys.isDisjoint(with: keys) else { throw ImportFailure.pendingTracking }
        let epoch = activeBindingEpoch
        importUndoKeys.formUnion(keys)
        defer { if context == account, activeBindingEpoch == epoch { importUndoKeys.subtract(keys) } }
        return try await withMutationReservation(keys: Array(keys), account: account) { [self] in
            guard try await !hasPendingTracking(for: keys, account: account) else { throw ImportFailure.pendingTracking }
            return try await operation()
        }
    }
    /// Compatibility entrypoint: Undo follows the same import mutation admission contract.
    public func withImportUndoReservation<T: Sendable>(keys: Set<MediaKey>, account: AccountContext,
        operation: @escaping @MainActor @Sendable () async throws -> T) async throws -> T {
        try await withImportMutationReservation(keys: keys, account: account, operation: operation)
    }
    public var progressMessage: String? { progressState?.message }

    public func pendingProgress(for key: MediaKey) -> ProgressIntent? {
        guard let pending = progressState?.pending[key] else { return nil }
        if let row = entries[key] { return row.lifecycleId == pending.lifecycleId ? pending : nil }
        return loadState == .loaded ? nil : pending
    }

    public func displayedProgress(for key: MediaKey, server: Int, lifecycleId: UUID?) -> Int {
        guard let lifecycleId else { return entries[key]?.progress ?? server }
        if let pending = pendingProgress(for: key), pending.lifecycleId == lifecycleId { return pending.position }
        let confirmed = progressState?.confirmed[key]
        let fallback = confirmed?.lifecycleId == lifecycleId ? confirmed : nil
        if let row = entries[key], row.lifecycleId == lifecycleId, (row.revision ?? 0) >= (fallback?.baseRevision ?? 0) {
            return row.progress
        }
        return loadState == .loaded && entries[key] == nil ? server : fallback?.position ?? server
    }

    public func displayedProgressLabel(for key: MediaKey, serverLabel: String?, lifecycleId: UUID?, serverRevision: Int64? = nil) -> String? {
        if let item = pendingProgress(for: key), item.lifecycleId == lifecycleId, item.writesPosition {
            return item.positionLabel ?? String(item.position)
        }
        if let item = progressState?.confirmed[key], item.lifecycleId == lifecycleId,
           (item.baseRevision ?? 0) >= max(entries[key]?.revision ?? 0, serverRevision ?? 0), item.writesPosition {
            return item.positionLabel ?? String(item.position)
        }
        if let row = entries[key] {
            guard row.lifecycleId == lifecycleId else { return nil }
            if let revision = row.revision, revision >= (serverRevision ?? 0) { return row.progressLabel }
        }
        return serverLabel
    }

    public func displayedUnitId(for key: MediaKey, serverUnitId: UUID?, lifecycleId: UUID?, serverRevision: Int64? = nil) -> UUID? {
        if let item = pendingProgress(for: key), item.lifecycleId == lifecycleId, item.writesPosition { return item.unitId }
        if let item = progressState?.confirmed[key], item.lifecycleId == lifecycleId,
           (item.baseRevision ?? 0) >= max(entries[key]?.revision ?? 0, serverRevision ?? 0), item.writesPosition { return item.unitId }
        if let row = entries[key] {
            guard row.lifecycleId == lifecycleId else { return nil }
            if let revision = row.revision, revision >= (serverRevision ?? 0) { return row.unitId }
        }
        return serverUnitId
    }

    /// Explicit remote deletion purges only the captured account. Signout deliberately retains
    /// its durable queue; deletion is different and cannot silently keep private notes/labels.
    public func removeDeletedAccountData(accountId: String) async throws {
        guard let state = progressState else { return }
        try await state.outbox.removeAccount(accountId: accountId)
        if context?.userId.lowercased() == accountId.lowercased() {
            cancelProgressWork(); state.clearProjection(); invalidateProgressOrdering()
        }
    }

    public func advanceProgress(for key: MediaKey, cap: Int? = nil) async -> LibraryOutcome {
        guard let account = context, let previous = entry(for: key) else { return .failed(.notFound) }
        let epoch = activeBindingEpoch
        if displayedUnitId(for: key, serverUnitId: previous.unitId, lifecycleId: previous.lifecycleId) != nil {
            return .failed(.invalidValue(field: "next unit: choose an episode or chapter"))
        }
        if let label = displayedProgressLabel(for: key, serverLabel: previous.progressLabel, lifecycleId: previous.lifecycleId),
           Int(label) != previous.progress {
            return .failed(.invalidValue(field: "next unit: choose an episode or chapter"))
        }
        guard progressAvailable, let lifecycle = previous.lifecycleId, let revision = previous.revision else {
            return await apply(LibraryEdit(progress: .set(previous.progress + 1)), to: key)
        }
        do {
            let intent = try await storeProgress(ProgressIntent(accountId: account.userId.lowercased(),
                medium: key.kind.rawValue.lowercased(), mediaId: key.id, lifecycleId: lifecycle,
                baseRevision: revision, position: previous.progress, priorPosition: previous.progress), advancing: true, cap: cap)
            guard context == account, activeBindingEpoch == epoch else { return .failed(.notAuthenticated) }
            return .applied(LibraryChange(key: key, kind: .updated, previous: previous,
                current: entry(for: key), mutationId: intent.mutationId, account: account))
        } catch let error as LibraryError { return .failed(error) }
        catch { return .failed(.unavailable(message: "Progress could not be saved on this device.")) }
    }

    func applyDurableProgress(_ edit: LibraryEdit, position: Int, to key: MediaKey) async -> LibraryOutcome {
        guard let account = context, let previous = entry(for: key), let lifecycle = previous.lifecycleId,
              let revision = previous.revision else { return .failed(.notFound) }
        let epoch = activeBindingEpoch
        do {
            let status: String?
            if case .set(let value) = edit.status { status = value.rawValue } else { status = nil }
            let intent = try await storeProgress(ProgressIntent(accountId: account.userId.lowercased(),
                medium: key.kind.rawValue.lowercased(), mediaId: key.id, lifecycleId: lifecycle,
                baseRevision: revision, position: position, writesPosition: edit.touchesProgress,
                status: status, priorPosition: previous.progress))
            guard context == account, activeBindingEpoch == epoch else { return .failed(.notAuthenticated) }
            return .applied(LibraryChange(key: key, kind: .updated, previous: previous,
                current: entry(for: key), mutationId: intent.mutationId, account: account))
        } catch let error as LibraryError { return .failed(error) }
        catch { return .failed(.unavailable(message: "Progress could not be saved on this device.")) }
    }

    func projectDurableProgress(_ row: LibraryEntry) -> LibraryEntry {
        var row = row
        if let pending = pendingProgress(for: row.key), pending.lifecycleId == row.lifecycleId {
            row.progress = pending.position
            if pending.writesPosition { row.progressLabel = pending.positionLabel; row.unitId = pending.unitId }
            if let status = pending.status.flatMap(ListStatus.init(rawValue:)) { row.status = status }
        } else if let confirmed = progressState?.confirmed[row.key], confirmed.lifecycleId == row.lifecycleId,
                  (confirmed.baseRevision ?? 0) > (row.revision ?? 0) {
            row.progress = confirmed.position; row.revision = confirmed.baseRevision
            if confirmed.writesPosition { row.progressLabel = confirmed.positionLabel; row.unitId = confirmed.unitId }
            if let status = confirmed.status.flatMap(ListStatus.init(rawValue:)) { row.status = status }
        }
        return row
    }

    /// Atomic disk admission computes increments from the latest durable position, even when taps
    /// overlap across actor suspension. Success means local commit; transport is a separate step.
    @discardableResult
    public func storeProgress(_ intent: ProgressIntent, advancing: Bool = false, cap: Int? = nil) async throws -> ProgressIntent {
        guard progressAvailable else { throw LibraryError.unavailable(message:"Progress sync is paused.") }
        guard let state = progressState, let account = context,
              account.userId.lowercased() == intent.accountId.lowercased(),
              let lifecycle = intent.lifecycleId else { throw LibraryError.notAuthenticated }
        let epoch = activeBindingEpoch
        guard intent.position >= 0, intent.medium == "anime" || intent.medium == "manga" else { throw LibraryError.invalidValue(field: "progress") }
        let key = progressKey(intent)
        guard !importUndoKeys.contains(key) else { throw LibraryError.retryable(message: "This title is being changed by an import. Try again after Apply or Undo finishes.") }
        if let row = entries[key], row.lifecycleId != lifecycle { throw LibraryError.notFound }
        if loadState == .loaded && entries[key] == nil { throw LibraryError.notFound }
        state.generation += 1
        var input = intent
        input.accountId = account.userId.lowercased()
        if let row = entries[key], row.lifecycleId == lifecycle {
            input.baseRevision = max(input.baseRevision ?? 0, row.revision ?? 0)
        }
        let saved = try await (advancing ? state.outbox.advance(input, cap: cap) : state.outbox.enqueue(input))
        guard context == account, activeBindingEpoch == epoch, progressState === state else { throw LibraryError.notAuthenticated }
        if let row = entries[key], row.lifecycleId != lifecycle { throw LibraryError.notFound }
        if loadState == .loaded && entries[key] == nil { throw LibraryError.notFound }
        try await restoreProgress()
        guard context == account, activeBindingEpoch == epoch else { throw LibraryError.notAuthenticated }
        state.message = "Saved on this device"
        scheduleProgressDrain()
        return saved
    }

    /// Undo an unattempted edit, or compensate the newest acknowledged edit using its lifecycle.
    /// An attempted request with no receipt remains immutable and is never replaced by Undo.
    public func undoProgress(for key: MediaKey, lifecycleId: UUID) async throws {
        guard let state = progressState, let account = context else { throw LibraryError.notAuthenticated }
        let epoch = activeBindingEpoch
        guard entries[key] == nil || entries[key]?.lifecycleId == lifecycleId else { throw LibraryError.notFound }
        state.generation += 1
        let prior = try await state.outbox.cancelPending(accountId: account.userId.lowercased(), medium: key.kind.rawValue.lowercased(), mediaId: key.id, lifecycleId: lifecycleId)
        guard context == account, activeBindingEpoch == epoch else { throw LibraryError.notAuthenticated }
        if prior == nil {
            guard let ack = state.acknowledgements[key], ack.lifecycleId == lifecycleId,
                  ack.priorPosition != nil else { throw LibraryError.retryable(message: "That save is already on its way.") }
            do { _ = try await state.outbox.compensateAcknowledged(ack) }
            catch { throw LibraryError.retryable(message: "That save is already on its way.") }
            guard context == account, activeBindingEpoch == epoch else { throw LibraryError.notAuthenticated }
            state.acknowledgements[key] = nil
        }
        try await restoreProgress()
        guard context == account, activeBindingEpoch == epoch else { throw LibraryError.notAuthenticated }
        state.message = nil
        scheduleProgressDrain()
    }

    public func resolveProgressConflict(reapply: Bool, expected: LibraryProgressConflict? = nil) async throws {
        guard let state = progressState, let conflict = state.conflict, let account = context else { return }
        guard expected == nil || expected == conflict else { return }
        let epoch = activeBindingEpoch
        state.generation += 1
        _ = try await state.outbox.resolveConflict(accountId: account.userId.lowercased(), medium: conflict.key.kind.rawValue.lowercased(),
            mediaId: conflict.key.id, lifecycleId: conflict.lifecycleId, serverRevision: conflict.serverRevision,
            serverPosition: conflict.serverPosition, reapply: reapply,
            expectedMutationId: conflict.mutationId, expectedDecision: conflict.decisionIntent)
        guard context == account, activeBindingEpoch == epoch else { throw LibraryError.notAuthenticated }
        state.message = nil
        try await restoreProgress()
        scheduleProgressDrain()
    }

    /// Restores both pending and confirmed disk rows. The generation guard prevents an older read
    /// from clearing an edit admitted while that read was suspended.
    public func restoreProgress() async throws {
        guard let state = progressState, let account = context else { return }
        let epoch = activeBindingEpoch
        let version = state.generation
        let pending = try await state.outbox.active(accountId: account.userId.lowercased())
        let confirmed = try await state.outbox.confirmations(accountId: account.userId.lowercased())
        var conflicts: [ProgressIntent] = []
        var conflictCursor: Int64 = 0
        // Filter after bounded pages, not after a permanent oldest-50 ceiling. Old
        // removed lifecycles can never make the next actionable conflict unreachable.
        while true {
            let page = try await state.outbox.conflicts(accountId: account.userId.lowercased(), afterSequence: conflictCursor)
            guard context == account,activeBindingEpoch == epoch,progressState === state,state.generation == version else { return }
            conflicts = page.filter { item in
                if let row = entries[progressKey(item)] { return row.lifecycleId == item.lifecycleId }
                return loadState != .loaded
            }
            if !conflicts.isEmpty || page.count < 50 { break }
            conflictCursor = page.last!.localSequence
        }
        guard context == account, activeBindingEpoch == epoch, progressState === state, state.generation == version else { return }
        func current(_ intent: ProgressIntent) -> Bool {
            if let row = entries[progressKey(intent)] { return row.lifecycleId == intent.lifecycleId }
            return loadState != .loaded
        }
        invalidateProgressOrdering()
        state.pending = pending.filter(current).reduce(into: [:]) { $0[progressKey($1)] = $1 }
        state.confirmed = confirmed.filter(current).reduce(into: [:]) { $0[progressKey($1)] = $1 }
        state.conflict = conflicts.filter(current).compactMap { item in
            guard let lifecycle = item.lifecycleId, let revision = item.conflictRevision, let position = item.conflictPosition else { return nil }
            let decision = state.pending[progressKey(item)] ?? item
            return LibraryProgressConflict(mutationId: item.mutationId, decisionIntent: decision,
                key: progressKey(item), localPosition: decision.position,
                serverPosition: position, serverRevision: revision, lifecycleId: lifecycle)
        }.first
    }

    public func cancelProgressWork() {
        guard let state = progressState else { return }
        state.task?.cancel(); state.retry?.cancel(); state.task = nil; state.retry = nil
        state.taskToken = nil; state.drainToken = nil; state.generation += 1; state.retryAttempt = 0; state.needsDrain = false
    }

    public func scheduleProgressDrain() {
        guard let state = progressState else { return }
        if state.task != nil { state.needsDrain = true; return }
        state.needsDrain = false
        let token = UUID(); state.taskToken = token
        state.task = Task { [weak self] in
            await self?.drainProgress()
            if state.taskToken == token {
                state.task = nil; state.taskToken = nil
                if state.needsDrain { self?.scheduleProgressDrain() }
            }
        }
    }

    /// All dispatch shares Library's key reservations with notes/status/removal. Failed or missing
    /// receipts release only still-in-flight claims; acknowledged rows cannot be reopened.
    public func drainProgress() async {
        guard progressAvailable, let state = progressState, let account = context, state.drainToken == nil else { return }
        let epoch = activeBindingEpoch
        let token = UUID(); state.drainToken = token
        defer { if state.drainToken == token { state.drainToken = nil } }
        var claimed: [UUID] = []
        do {
            for _ in 0..<50 {
                guard progressAvailable, context == account, activeBindingEpoch == epoch, !Task.isCancelled, state.drainToken == token else { throw CancellationError() }
                let heads = try await state.outbox.pending(accountId: account.userId.lowercased(), limit: 50)
                guard !heads.isEmpty else { state.retryAttempt = 0; return }
                try await withMutationReservation(keys: heads.map(progressKey), account: account) { [self] in
                    guard context == account, activeBindingEpoch == epoch, !Task.isCancelled else { throw CancellationError() }
                    for head in heads {
                        let key = progressKey(head)
                        if let row = entries[key], row.lifecycleId == head.lifecycleId, row.progress == head.priorPosition,
                           let lifecycle = head.lifecycleId, let revision = row.revision {
                            try await state.outbox.rebaseUnsent(accountId: head.accountId, medium: head.medium, mediaId: head.mediaId,
                                lifecycleId: lifecycle, revision: revision)
                        }
                    }
                    let candidates = try await state.outbox.claim(accountId: account.userId.lowercased(), limit: 50, mutationIds: heads.map(\.mutationId))
                    claimed = candidates.map(\.mutationId)
                    var batch: [ProgressIntent] = []
                    for intent in candidates {
                        let row = entries[progressKey(intent)]
                        if intent.lifecycleId == nil || intent.baseRevision == nil {
                            try await state.outbox.markResolved(intent.mutationId, state: "invalid_target")
                        } else if (row != nil && row?.lifecycleId != intent.lifecycleId) || (loadState == .loaded && row == nil) {
                            try await state.outbox.markResolved(intent.mutationId, state: "removed_entry")
                        } else { batch.append(intent) }
                    }
                    guard !batch.isEmpty else { claimed = []; try await restoreProgress(); return }
                    guard progressAvailable else { throw CancellationError() }
                    let receipts = try await state.send(batch, account)
                    guard context == account, activeBindingEpoch == epoch, state.drainToken == token else { throw CancellationError() }
                    var handled: Set<UUID> = []
                    for receipt in receipts {
                        guard let source = batch.first(where: { $0.mutationId == receipt.mutationId }), handled.insert(receipt.mutationId).inserted else { continue }
                        let key = progressKey(source)
                        switch receipt.outcome {
                        case "applied", "already_applied":
                            guard let position = receipt.position, position >= 0, let revision = receipt.revision, revision >= (source.baseRevision ?? 0) else { continue }
                            try await state.outbox.acknowledge(receipt.mutationId, revision: revision, position: position)
                            guard context == account, activeBindingEpoch == epoch, state.drainToken == token else { throw CancellationError() }
                            state.generation += 1
                            adoptServerProgress(key: key, account: account, lifecycleId: source.lifecycleId!, progress: position, revision: revision,
                                status: source.status.flatMap(ListStatus.init(rawValue:)), mutationId: source.mutationId,
                                progressLabel: source.positionLabel, unitId: source.unitId, writesPosition: source.writesPosition)
                            var ack = source; ack.baseRevision = revision; ack.position = position
                            state.acknowledgements[key] = ack
                        case "conflict":
                            guard let position = receipt.position, position >= 0, let revision = receipt.revision, revision >= (source.baseRevision ?? 0) else { continue }
                            try await state.outbox.recordConflict(receipt.mutationId, revision: revision, position: position)
                            guard context == account, activeBindingEpoch == epoch, state.drainToken == token else { throw CancellationError() }
                            state.generation += 1
                        case "removed_entry", "rejected_payload", "invalid_target":
                            try await state.outbox.markResolved(receipt.mutationId, state: receipt.outcome)
                            guard context == account, activeBindingEpoch == epoch, state.drainToken == token else { throw CancellationError() }
                            state.generation += 1; state.message = "That progress needs another look."
                        default: break
                        }
                    }
                    let unresolved = try await state.outbox.active(accountId: account.userId.lowercased()).filter { claimed.contains($0.mutationId) && $0.state == "in_flight" }
                    try await state.outbox.release(unresolved.map(\.mutationId)); claimed = []
                    try await restoreProgress()
                    if !unresolved.isEmpty { throw LibraryError.retryable(message: "Incomplete progress receipts") }
                }
            }
            scheduleProgressRetry(state, account: account)
        } catch {
            try? await state.outbox.release(claimed)
            guard context == account, activeBindingEpoch == epoch, state.drainToken == token else { return }
            state.message = "Saved on this device"
            if !(error is CancellationError) { scheduleProgressRetry(state, account: account) }
        }
    }

    private func scheduleProgressRetry(_ state: LibraryProgressState, account: AccountContext) {
        guard progressAvailable, context == account, state.retry == nil else { return }
        state.retryAttempt = min(5, state.retryAttempt + 1)
        let delay = UInt64(1 << state.retryAttempt) * 1_000_000_000
        state.retry = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard let self, self.context == account, !Task.isCancelled else { return }
            state.retry = nil; self.scheduleProgressDrain()
        }
    }

    private func progressKey(_ intent: ProgressIntent) -> MediaKey {
        MediaKey(kind: intent.medium == "manga" ? .manga : .anime, id: intent.mediaId)
    }
}
