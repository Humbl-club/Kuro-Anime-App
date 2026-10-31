import Foundation
import KuroCore
import KuroLibrary
import Observation

/// Presentation decisions only. The Imports owner freezes, persists and applies them.
struct ImportReviewApproval {
    private(set) var fieldsByItem: [String: Set<ImportField>] = [:]

    func contains(_ field: ImportField, for item: ImportReviewItem) -> Bool {
        fieldsByItem[item.id]?.contains(field) == true
    }

    mutating func set(_ field: ImportField, approved: Bool, for item: ImportReviewItem) {
        guard item.current != nil, item.changedFields.contains(field) else { return }
        if approved { fieldsByItem[item.id, default: []].insert(field) }
        else { fieldsByItem[item.id]?.remove(field) }
    }

    func decisions(for items: [ImportReviewItem]) -> [ImportDecision] {
        items.map { item in
            let fields = (fieldsByItem[item.id] ?? []).filter { item.changedFields.contains($0) }
                .sorted { $0.rawValue < $1.rawValue }
            if item.current != nil, [.existing, .changes].contains(item.disposition), !fields.isEmpty {
                return ImportDecision(item: item, action: .update, fields: fields)
            }
            return ImportDecision(item: item)
        }
    }
}

/// A mounted import screen. Durable source, replay, jobs and tracking belong to ImportsService.
@MainActor
@Observable
final class ImportWorkflowPresentation {
    let imports: ImportsService
    private let account: AccountContext?
    @ObservationIgnored private let scope = AccountActionScope()
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    private(set) var job: ImportOutcome?
    private(set) var items: [ImportReviewItem] = []
    private(set) var jobs: [ImportOutcome] = []
    private(set) var manifests: [ImportManifest] = []
    private(set) var busy = false
    private(set) var failure: ImportFailure?
    private(set) var reviewReady = false
    var approval = ImportReviewApproval()

    init(imports: ImportsService, job: ImportOutcome? = nil) {
        self.imports = imports; self.job = job; account = imports.accountSession.current
    }

    var isCurrentAccount: Bool { account != nil && imports.accountSession.isCurrent(account) }
    var visibleJob: ImportOutcome? {
        if let active = imports.activeImport, imports.importBusy, active.jobId == job?.jobId { return active }
        return job
    }
    var mayApply: Bool {
        guard let job, let manifest, manifest.phase == .reviewing, manifest.sourceExhausted, manifest.decisions == nil else { return false }
        return job.phase == .reviewing && job.selection.media.allSatisfy { job.exhaustedMedia[$0] == true }
            && reviewReady && failure == nil && !busy && !imports.importBusy && isCurrentAccount
    }
    var affectedKeys: Set<MediaKey> {
        Set(items.compactMap { item in
            guard [.added, .updated, .unchanged].contains(item.disposition), item.undoDisposition != "reverted",
                  let id = item.mediaId else { return nil }
            return MediaKey(mediaType: item.medium, id: id)
        })
    }
    var manifest: ImportManifest? {
        guard isCurrentAccount else { return nil }
        return imports.pendingImports.first { $0.jobId == job?.jobId }
            ?? manifests.first { $0.jobId == job?.jobId }
    }

    func activate() {
        guard isCurrentAccount else { return }
        scope.activate(session: imports.accountSession)
    }

    func close() {
        scope.deactivate()
        operationTask?.cancel(); operationTask = nil
        busy = false
        // Closing cancels presentation work, never stops the durable server job.
    }

    func load() async {
        await perform { origin in
            _ = try await self.imports.discoverPendingImports()
            guard self.isCurrent(origin) else { return }
            self.manifests = self.imports.pendingImports
            if let job = self.job {
                let current = try await self.imports.refreshImport(jobId: job.jobId)
                guard self.isCurrent(origin) else { return }
                self.job = current
                try await self.loadItems(origin)
            } else {
                let jobs = try await self.imports.importJobs()
                guard self.isCurrent(origin) else { return }
                self.jobs = jobs
            }
        }
    }

    func refreshPresentation() async {
        if let job, job.phase != .reviewing, !job.projectionReady, let manifest {
            await resume(actionId: manifest.actionId)
        } else { await load() }
    }

    func inspect(_ selected: ImportOutcome) async {
        guard scope.capture(session: imports.accountSession) != nil else { return }
        job = selected; items = []; reviewReady = false; approval = ImportReviewApproval(); failure = nil
        await load()
    }

    func apply() async {
        guard mayApply, let job else { return }
        let decisions = approval.decisions(for: items)
        await perform { origin in
            let result = try await self.imports.applyImport(jobId: job.jobId, decisions: decisions)
            guard self.isCurrent(origin) else { return }
            self.job = result
            try await self.loadItems(origin)
        }
    }

    func resume(actionId: String) async {
        await perform { origin in
            let result = try await self.imports.resumeImport(actionId: actionId)
            guard self.isCurrent(origin) else { return }
            self.job = result; self.items = []; self.reviewReady = false; self.approval = ImportReviewApproval()
            try await self.loadItems(origin)
            guard self.isCurrent(origin) else { return }
            _ = try await self.imports.discoverPendingImports()
            guard self.isCurrent(origin) else { return }
            self.manifests = self.imports.pendingImports
        }
    }

    func stopPreparation(actionId: String) async {
        guard manifests.contains(where: { $0.actionId == actionId && $0.jobId == nil }) else { return }
        await perform { origin in
            try await self.imports.stopPreparedImport(actionId: actionId)
            guard self.isCurrent(origin) else { return }
            _ = try await self.imports.discoverPendingImports()
            guard self.isCurrent(origin) else { return }
            self.manifests = self.imports.pendingImports
        }
    }

    func stop() async {
        guard let job else { return }
        // Abandon the awaited presentation operation, then let the owner stop future chunks.
        // The server lock/receipts decide whether an already admitted chunk committed.
        operationTask?.cancel(); operationTask = nil
        scope.deactivate(); activate(); busy = false
        await perform { origin in
            let result = try await self.imports.stopImport(jobId: job.jobId)
            guard self.isCurrent(origin) else { return }
            self.job = result
            try await self.loadItems(origin)
        }
    }

    func undo() async {
        guard let job, job.undoAvailable else { return }
        await perform { origin in
            let result = try await self.imports.undoImport(jobId: job.jobId)
            guard self.isCurrent(origin) else { return }
            self.job = result
            try await self.loadItems(origin)
        }
    }

    func reviewUnresolved() async {
        guard let job, job.isTerminal else { return }
        let ids = Set(items.filter { [.unmatched, .conflict, .sourceChanged].contains($0.disposition) }.map(\.id))
        guard !ids.isEmpty else { return }
        await perform { origin in
            let result = try await self.imports.prepareImportReviewRetry(jobId: job.jobId, itemIds: ids)
            guard self.isCurrent(origin) else { return }
            self.job = result; self.items = []; self.reviewReady = false; self.approval = ImportReviewApproval()
            try await self.loadItems(origin)
        }
    }

    func match(_ item: ImportReviewItem, mediaId: Int) async {
        guard let job, job.phase == .reviewing, item.mediaId == nil, item.disposition == .unmatched else { return }
        await perform { origin in
            let result = try await self.imports.matchImportItem(jobId: job.jobId, item: item, mediaId: mediaId)
            guard self.isCurrent(origin) else { return }
            self.job = result; self.approval = ImportReviewApproval()
            // Show the fresh baseline before any approval or application.
            try await self.loadItems(origin)
        }
    }

    private func loadItems(_ origin: AccountActionScope.Ticket) async throws {
        guard isCurrent(origin), let job else { return }
        reviewReady = false
        guard job.historyAvailable else { items = []; return }
        let items = try await imports.reviewImport(jobId: job.jobId)
        guard isCurrent(origin) else { return }
        self.items = items
        reviewReady = true
    }

    private func isCurrent(_ origin: AccountActionScope.Ticket) -> Bool {
        isCurrentAccount && scope.isCurrent(origin, session: imports.accountSession)
    }

    private func perform(_ operation: @escaping @MainActor (AccountActionScope.Ticket) async throws -> Void) async {
        guard !busy, isCurrentAccount, let origin = scope.capture(session: imports.accountSession) else { return }
        // Register immediately, before a queued second gesture can enter.
        busy = true; failure = nil
        guard let task = scope.launch(origin: origin, session: imports.accountSession, operation: { origin in
            defer { if self.isCurrent(origin) { self.busy = false } }
            do { try await operation(origin) }
            catch is CancellationError { return }
            catch {
                guard self.isCurrent(origin) else { return }
                self.failure = (error as? ImportFailure) ?? self.imports.importError ?? .transient(error.localizedDescription)
                // Saved counts remain visible if publication/source refresh failed after a commit.
                if let active = self.imports.activeImport, active.jobId == self.job?.jobId {
                    self.job = active
                    try? await self.loadItems(origin)
                }
            }
        }) else { busy = false; return }
        operationTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if isCurrent(origin) { operationTask = nil }
    }
}
