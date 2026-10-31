import Foundation
import KuroCore
import KuroLibrary

extension ImportsService {
    @discardableResult
    func discoverPendingImports() async throws -> [ImportManifest] {
        try await runWorkflow { origin in
            let records = try await self.workflowJournal().pendingWorkflows(accountId: origin.account.userId)
            try self.checkWorkflow(origin)
            self.pendingImports = records
            return records
        }
    }

    func importJobs() async throws -> [ImportOutcome] {
        try await runWorkflow { origin in
            var jobs: [ImportOutcome] = [], cursor: String?, seen = Set<String>()
            for _ in 0..<200 {
                let page: ImportJobsPage = try await self.workflowRPC("import_jobs_page_v2",
                    ImportJobsInput(p_cursor: cursor, p_limit: 50), origin: origin)
                jobs.append(contentsOf: page.jobs)
                guard let next = page.nextCursor else { return jobs }
                guard seen.insert(next).inserted else { throw ImportFailure.invalidInput("The jobs cursor repeated.") }
                cursor = next
            }
            throw ImportFailure.limit("The import history exceeded the supported page limit.")
        }
    }

    func reviewImport(jobId: String) async throws -> [ImportReviewItem] {
        try await runWorkflow { origin in try await self.loadReview(jobId: jobId, origin: origin) }
    }

    func loadReview(jobId: String, origin: WorkflowOrigin) async throws -> [ImportReviewItem] {
        var items: [ImportReviewItem] = [], cursor: String?, seen = Set<String>()
        for _ in 0..<2_000 {
            let page: ImportItemsPage = try await workflowRPC("import_items_page_v2",
                ImportItemsInput(p_job_id: jobId, p_cursor: cursor, p_limit: 50), origin: origin)
            items.append(contentsOf: page.items)
            guard let next = page.nextCursor else { return items }
            guard seen.insert(next).inserted else { throw ImportFailure.invalidInput("The review cursor repeated.") }
            cursor = next
        }
        throw ImportFailure.limit("This import exceeded the supported review size.")
    }

    func refreshImport(jobId: String) async throws -> ImportOutcome {
        try await runWorkflow { origin in
            let outcome: ImportOutcome = try await self.workflowRPC("import_job_status_v2", ImportJobInput(p_job_id: jobId), origin: origin)
            let local = try await self.localWorkflow(jobId: jobId, origin: origin)
            if var manifest = local, let published = Self.publishedOutcome(outcome, saved: manifest.outcome) {
                // Publication readiness is local; retention/Undo availability stays server-owned.
                manifest.outcome = published
                try await self.saveWorkflow(manifest, origin: origin)
                return published
            }
            self.activeImport = outcome
            return outcome
        }
    }

    static func publishedOutcome(_ server: ImportOutcome, saved: ImportOutcome?) -> ImportOutcome? {
        guard let saved, saved.projectionReady, saved.jobId == server.jobId,
              saved.selection == server.selection, saved.phase == server.phase,
              saved.homeRevisions == server.homeRevisions, saved.counts == server.counts else { return nil }
        var published = server; published.projectionReady = true
        return published
    }

    func resumeImport(actionId: String) async throws -> ImportOutcome {
        try await runWorkflow { origin in
            guard var manifest = try await self.workflowJournal().loadWorkflow(accountId: origin.account.userId, actionId: actionId) else {
                throw ImportFailure.invalidInput("This device has no original import inputs. You can inspect or stop the remote job.")
            }
            try self.checkWorkflow(origin)
            switch manifest.phase {
            case .preparing: return try await self.prepareWorkflow(&manifest, origin: origin)
            case .reviewing:
                guard let jobId = manifest.jobId else { throw ImportFailure.invalidInput("The import job is missing.") }
                let outcome: ImportOutcome = try await self.workflowRPC("import_job_status_v2", ImportJobInput(p_job_id: jobId), origin: origin)
                if outcome.isTerminal { return try await self.publishWorkflow(outcome, manifest: &manifest, origin: origin) }
                manifest.outcome = outcome; try await self.saveWorkflow(manifest, origin: origin); return outcome
            case .applying: return try await self.applyFrozenWorkflow(&manifest, origin: origin)
            case .finalizing:
                guard let jobId = manifest.jobId else { throw ImportFailure.invalidInput("The import job is missing.") }
                let outcome: ImportOutcome = try await self.workflowRPC("import_job_status_v2", ImportJobInput(p_job_id: jobId), origin: origin)
                // A finish response can be lost before SQL commits or before the local checkpoint.
                if !outcome.isTerminal {
                    let finished: ImportOutcome = try await self.workflowRPC("finish_library_import_v2", ImportJobInput(p_job_id: jobId), origin: origin)
                    return try await self.publishWorkflow(finished, manifest: &manifest, origin: origin)
                }
                return try await self.publishWorkflow(outcome, manifest: &manifest, origin: origin)
            case .undoing: return try await self.undoWorkflow(&manifest, origin: origin)
            case .ready, .cancelled, .failed, .undone:
                guard let jobId = manifest.jobId else { throw ImportFailure.invalidInput("The import job is missing.") }
                let outcome: ImportOutcome = try await self.workflowRPC("import_job_status_v2", ImportJobInput(p_job_id: jobId), origin: origin)
                if let published = Self.publishedOutcome(outcome, saved: manifest.outcome) {
                    manifest.outcome = published
                    manifest = try await self.completeWorkflowCleanup(manifest, origin: origin)
                    try self.checkWorkflow(origin); self.activeImport = published
                    self.importUndoReverted = manifest.undoReverted ?? 0
                    self.importUndoSkipped = manifest.undoSkipped ?? 0
                    if let index = self.pendingImports.firstIndex(where: { $0.actionId == actionId }) { self.pendingImports[index] = manifest }
                    return published
                }
                return try await self.publishWorkflow(outcome, manifest: &manifest, origin: origin)
            }
        }
    }

    func applyImport(jobId: String, decisions: [ImportDecision]) async throws -> ImportOutcome {
        try await runWorkflow { origin in
            guard var manifest = try await self.localWorkflow(jobId: jobId, origin: origin) else {
                throw ImportFailure.invalidInput("Only the device holding the original frozen source can apply this job. Inspect or stop it here.")
            }
            guard [.reviewing, .applying].contains(manifest.phase), manifest.sourceExhausted,
                  manifest.preparedPages == manifest.nextPage else { throw ImportFailure.invalidInput("Finish preparing the source before approving it.") }
            if let frozen = manifest.decisions {
                guard frozen == decisions else { throw ImportFailure.invalidInput("This approval has already been attempted. Resume its original decisions.") }
            } else {
                let items = try await self.loadReview(jobId: jobId, origin: origin)
                try Self.validateApproval(decisions, items: items)
                manifest.decisions = decisions; manifest.phase = .applying
                // One immutable confirmation is durable before the FIRST apply dispatch.
                try await self.saveWorkflow(manifest, origin: origin)
            }
            return try await self.applyFrozenWorkflow(&manifest, origin: origin)
        }
    }

    static func validateApproval(_ decisions: [ImportDecision], items: [ImportReviewItem]) throws {
        guard Set(items.map(\.id)).count == items.count else { throw ImportFailure.invalidInput("The server returned duplicate review identities.") }
        let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let ids = decisions.map { $0.medium + "|" + $0.externalId }
        guard Set(ids).count == ids.count, Set(ids) == Set(byId.keys) else {
            throw ImportFailure.invalidInput("Review every source item once before applying.")
        }
        for decision in decisions {
            guard let item = byId[decision.medium + "|" + decision.externalId],
                  decision.expectedRevision == item.expectedRevision,
                  decision.expectedLifecycle == item.expectedLifecycle,
                  decision.resolvedMediaId == item.mediaId,
                  Set(decision.fields).count == decision.fields.count,
                  Set(decision.fields).isSubset(of: Set(item.changedFields)) else {
                throw ImportFailure.invalidInput("The review changed. Read the current item before approving it.")
            }
            switch decision.action {
            case .add:
                guard item.disposition == .new, decision.fields.isEmpty else { throw ImportFailure.invalidInput("Only new entries can be added without a field review.") }
            case .update:
                guard [.existing, .changes].contains(item.disposition), !decision.fields.isEmpty else {
                    throw ImportFailure.invalidInput("Select the fields to replace on an existing entry.")
                }
            case .keep:
                guard [.existing, .changes].contains(item.disposition), decision.fields.isEmpty else {
                    throw ImportFailure.invalidInput("Keep existing applies to an already matched entry.")
                }
            case .deferReview:
                guard decision.fields.isEmpty else { throw ImportFailure.invalidInput("Deferred entries cannot approve fields.") }
            }
        }
    }

    func applyFrozenWorkflow(_ manifest: inout ImportManifest, origin: WorkflowOrigin) async throws -> ImportOutcome {
        guard let jobId = manifest.jobId, let decisions = manifest.decisions else { throw ImportFailure.invalidInput("The original approval is unavailable.") }
        let status: ImportOutcome = try await workflowRPC("import_job_status_v2", ImportJobInput(p_job_id: jobId), origin: origin)
        if status.isTerminal { return try await publishWorkflow(status, manifest: &manifest, origin: origin) }
        guard [.reviewing, .applying].contains(status.phase) else {
            activeImport = status
            throw ImportFailure.invalidInput("This job is no longer accepting the original approval. Inspect its current state.")
        }
        let keys = Set(decisions.compactMap { decision -> MediaKey? in
            guard [.add, .update].contains(decision.action), let id = decision.resolvedMediaId, id > 0 else { return nil }
            return MediaKey(mediaType: decision.medium, id: id)
        })
        let original = manifest
        // The same Library FIFO that owns local edits governs actual import writes. A later
        // unsent progress/removal or admitted notes write cannot be displaced by an old review.
        // Terminal reconciliation above only publishes and does not require this write guard.
        let completed: ImportManifest = try await libraryHook.withImportMutationReservation(keys: keys, account: origin.account) {
            try self.checkWorkflow(origin)
            var local = original
            while local.appliedDecisionCount < decisions.count {
                let start = local.appliedDecisionCount
                let chunk = Array(decisions[start..<min(start + 100, decisions.count)])
                let outcome: ImportOutcome = try await self.workflowRPC("apply_import_chunk_v2",
                    ImportApplyInput(p_job_id: jobId, p_action_id: local.actionId, p_decisions: chunk), origin: origin)
                local.outcome = outcome; local.appliedDecisionCount += chunk.count
                try await self.saveWorkflow(local, origin: origin)
            }
            local.phase = .finalizing
            try await self.saveWorkflow(local, origin: origin)
            let finished: ImportOutcome = try await self.workflowRPC("finish_library_import_v2", ImportJobInput(p_job_id: jobId), origin: origin)
            _ = try await self.publishWorkflow(finished, manifest: &local, origin: origin)
            return local
        }
        manifest = completed
        guard let outcome = completed.outcome else { throw CancellationError() }
        return outcome
    }

    /// The server transaction is already committed. Retain counts while publication is pending.
    func publishWorkflow(_ server: ImportOutcome, manifest: inout ImportManifest, origin: WorkflowOrigin) async throws -> ImportOutcome {
        guard server.isTerminal else { throw ImportFailure.invalidInput("The server did not confirm a terminal import.") }
        var pending = server; pending.phase = .finalizing; pending.projectionReady = false
        manifest.phase = .finalizing; manifest.outcome = pending
        // Existing terminal records must not be reopened solely for publication. Their outcome
        // retains terminal phase and projectionReady=false, which resume treats as refresh pending.
        if let old = try await workflowJournal().loadWorkflow(accountId: manifest.accountId, actionId: manifest.actionId),
           old.outcome?.isTerminal == true {
            manifest.phase = server.phase; manifest.outcome = server
        }
        try await saveWorkflow(manifest, origin: origin)
        activeImport = pending
        try await libraryHook.publishImport(revisions: server.homeRevisions, for: origin.account)
        try checkWorkflow(origin)
        var ready = server; ready.projectionReady = true
        manifest.phase = server.phase; manifest.outcome = ready
        manifest = try await completeWorkflowCleanup(manifest, origin: origin)
        try checkWorkflow(origin)
        if let index = pendingImports.firstIndex(where: { $0.actionId == manifest.actionId }) { pendingImports[index] = manifest }
        activeImport = ready
        return ready
    }

    func stopImport(jobId: String) async throws -> ImportOutcome {
        // Invalidate any previous preparation/application between its bounded RPCs. An RPC already
        // admitted may commit; SQL cancel locks and receipts preserve those committed entries.
        let origin = try beginWorkflow(replacing: true)
        do {
            var manifest = try await localWorkflow(jobId: jobId, origin: origin)
            let stopped: ImportOutcome = try await workflowRPC("cancel_library_import_v2", ImportJobInput(p_job_id: jobId), origin: origin)
            if manifest == nil {
                manifest = ImportManifest(accountId: origin.account.userId, selection: stopped.selection)
                manifest?.jobId = jobId
            }
            guard var record = manifest else { throw CancellationError() }
            let result = try await publishWorkflow(stopped, manifest: &record, origin: origin)
            endWorkflow(origin); return result
        } catch { endWorkflow(origin, error: error); throw error is CancellationError ? error : Self.workflowFailure(error) }
    }

    /// Explicit abandonment of a fully attributed local preparation. No server result is
    /// fabricated when a file/quota interruption happened before server-job admission.
    func stopPreparedImport(actionId: String) async throws {
        let origin = try beginWorkflow(replacing: true)
        do {
            guard var manifest = try await workflowJournal().loadWorkflow(accountId: origin.account.userId, actionId: actionId) else {
                throw ImportFailure.invalidInput("This device has no preparation with that identity.")
            }
            try checkWorkflow(origin)
            if manifest.jobId == nil, manifest.startAttempted == true {
                try await startWorkflow(&manifest, origin: origin)
            }
            if let jobId = manifest.jobId {
                let stopped: ImportOutcome = try await workflowRPC("cancel_library_import_v2", ImportJobInput(p_job_id: jobId), origin: origin)
                _ = try await publishWorkflow(stopped, manifest: &manifest, origin: origin)
            } else {
                manifest.phase = .cancelled
                manifest = try await completeWorkflowCleanup(manifest, origin: origin)
                try checkWorkflow(origin)
                if let index = pendingImports.firstIndex(where: { $0.actionId == actionId }) { pendingImports[index] = manifest }
                activeImport = nil
            }
            endWorkflow(origin)
        } catch { endWorkflow(origin, error: error); throw error is CancellationError ? error : Self.workflowFailure(error) }
    }

    func undoImport(jobId: String) async throws -> ImportOutcome {
        try await runWorkflow { origin in
            var record = try await self.localWorkflow(jobId: jobId, origin: origin)
            if record == nil {
                let job: ImportOutcome = try await self.workflowRPC("import_job_status_v2", ImportJobInput(p_job_id: jobId), origin: origin)
                guard job.historyAvailable, job.undoAvailable else { throw ImportFailure.invalidInput("This import no longer has an Undo receipt.") }
                var manifest = ImportManifest(accountId: origin.account.userId, selection: job.selection)
                manifest.jobId = jobId; manifest.outcome = job; record = manifest
                try await self.saveWorkflow(manifest, origin: origin)
            }
            guard var manifest = record else { throw CancellationError() }
            return try await self.undoWorkflow(&manifest, origin: origin)
        }
    }

    func undoWorkflow(_ manifest: inout ImportManifest, origin: WorkflowOrigin) async throws -> ImportOutcome {
        guard let jobId = manifest.jobId else { throw ImportFailure.invalidInput("The import job is missing.") }
        let items = try await loadReview(jobId: jobId, origin: origin)
        let keys = Set(items.compactMap { item -> MediaKey? in
            guard [.added, .updated].contains(item.disposition), item.undoDisposition != "reverted",
                  let id = item.mediaId else { return nil }
            return MediaKey(mediaType: item.medium, id: id)
        })
        // Reserve the Library's affected keys across pending-check, stop and compensation. New
        // edits on those keys cannot slip between checking disk and dispatching Undo.
        let original = manifest
        let finished: ImportManifest = try await libraryHook.withImportUndoReservation(keys: keys, account: origin.account) {
            try self.checkWorkflow(origin)
            var local = original
            if local.phase != .undoing {
                let stopped: ImportOutcome = try await self.workflowRPC("cancel_library_import_v2", ImportJobInput(p_job_id: jobId), origin: origin)
                local.outcome = stopped; local.phase = .undoing
                local.undoActionId = local.undoActionId ?? stopped.undoActionId ?? UUID().uuidString.lowercased()
                try await self.saveWorkflow(local, origin: origin)
            }
            guard let action = local.undoActionId else { throw ImportFailure.invalidInput("The Undo action is missing.") }
            var seen = Set<String>()
            for _ in 0..<1_000 {
                let response: ImportUndoOutcome = try await self.workflowRPC("undo_library_import_chunk_v2",
                    ImportUndoInput(p_job_id: jobId, p_action_id: action, p_cursor: local.undoCursor, p_limit: 100), origin: origin)
                local.outcome = response.job; local.undoCursor = response.nextCursor
                local.undoReverted = response.reverted; local.undoSkipped = response.skipped
                try await self.saveWorkflow(local, origin: origin)
                guard let next = response.nextCursor else {
                    _ = try await self.publishWorkflow(response.job, manifest: &local, origin: origin)
                    return local
                }
                guard seen.insert(next).inserted else { throw ImportFailure.invalidInput("The Undo cursor repeated.") }
            }
            throw ImportFailure.limit("Undo exceeded the supported receipt page limit; resume its saved cursor.")
        }
        manifest = finished
        guard let outcome = finished.outcome else { throw CancellationError() }
        return outcome
    }

    func prepareImportReviewRetry(jobId: String, itemIds: Set<String>) async throws -> ImportOutcome {
        try await runWorkflow { origin in
            let previous: ImportOutcome = try await self.workflowRPC("import_job_status_v2", ImportJobInput(p_job_id: jobId), origin: origin)
            guard previous.isTerminal, previous.historyAvailable, !itemIds.isEmpty else { throw ImportFailure.invalidInput("Choose unresolved items from a completed import.") }
            let selected = try await self.loadReview(jobId: jobId, origin: origin).filter { itemIds.contains($0.id) }
            guard Set(selected.map(\.id)) == itemIds,
                  selected.allSatisfy({ [.unmatched, .conflict, .sourceChanged].contains($0.disposition) }) else {
                throw ImportFailure.invalidInput("Only retained unresolved items can start a fresh review.")
            }
            var selection = previous.selection
            // Retained input is already a frozen source, not a fresh read of the provider account.
            selection.sourceKind = .export
            selection.sourceIdentity = "review|" + jobId
            var manifest = ImportManifest(accountId: origin.account.userId, selection: selection)
            try await self.saveWorkflow(manifest, origin: origin)
            let chunks = Self.sourceChunks(selected.map { ImportSourceItem(medium: $0.medium, externalId: $0.externalId, title: $0.title, values: $0.incoming) })
            for (index, chunk) in chunks.enumerated() {
                let flags = index == chunks.count - 1 ? Dictionary(uniqueKeysWithValues: selection.media.map { ($0, true) }) : [:]
                try await self.freezeSourcePage(ImportSourcePage(items: chunk, nextCursor: nil, exhaustedMedia: flags), manifest: &manifest, origin: origin)
            }
            return try await self.prepareWorkflow(&manifest, origin: origin)
        }
    }

    func matchImportItem(jobId: String, item: ImportReviewItem, mediaId: Int) async throws -> ImportOutcome {
        try await runWorkflow { origin in
            guard mediaId > 0, item.mediaId == nil, item.disposition == .unmatched,
                  var manifest = try await self.localWorkflow(jobId: jobId, origin: origin),
                  manifest.phase == .reviewing, manifest.decisions == nil else {
                throw ImportFailure.invalidInput("Only an unmatched item in an unapproved review can be mapped.")
            }
            let latest = try await self.loadReview(jobId: jobId, origin: origin)
            guard latest.first(where: { $0.id == item.id }) == item else { throw ImportFailure.invalidInput("The item changed. Review its current source first.") }
            let source = ImportSourceItem(medium: item.medium, externalId: item.externalId, title: item.title,
                values: item.incoming, resolvedMediaId: mediaId)
            let outcome: ImportOutcome = try await self.workflowRPC("prepare_import_chunk_v2",
                ImportPrepareInput(p_job_id: jobId, p_items: [source], p_exhausted_media: [:]), origin: origin)
            manifest.outcome = outcome; try await self.saveWorkflow(manifest, origin: origin)
            return outcome
        }
    }
}
