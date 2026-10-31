import Foundation
import KuroCore
import KuroLibrary
import Supabase

/// Exact v2 wire inputs. These remain private to Imports; no SDK rows reach rendering code.
nonisolated struct ImportStartInput: Encodable, Sendable { let p_selection: ImportSelection; let p_action_id: String }
nonisolated struct ImportJobInput: Encodable, Sendable { let p_job_id: String }
nonisolated struct ImportPrepareInput: Encodable, Sendable {
    let p_job_id: String; let p_items: [ImportSourceItem]; let p_exhausted_media: [String:Bool]
}
nonisolated struct ImportApplyInput: Encodable, Sendable {
    let p_job_id: String; let p_action_id: String; let p_decisions: [ImportDecision]
}
nonisolated struct ImportItemsInput: Encodable, Sendable { let p_job_id: String; let p_cursor: String?; let p_limit: Int }
nonisolated struct ImportJobsInput: Encodable, Sendable { let p_cursor: String?; let p_limit: Int }
nonisolated struct ImportUndoInput: Encodable, Sendable {
    let p_job_id: String; let p_action_id: String; let p_cursor: String?; let p_limit: Int
}

extension ImportsService {
    struct WorkflowOrigin: Sendable { let account: AccountContext; let token: UUID }

    func beginWorkflow(replacing: Bool = false) throws -> WorkflowOrigin {
        guard let account = accountSession.current, !Task.isCancelled else { throw CancellationError() }
        if workflowAccount != account { resetWorkflowPresentation() }
        guard replacing || !importBusy else { throw ImportFailure.activeJob }
        let origin = WorkflowOrigin(account: account, token: UUID())
        workflowAccount = account; workflowToken = origin.token; importBusy = true; importError = nil
        return origin
    }

    func checkWorkflow(_ origin: WorkflowOrigin) throws {
        guard !Task.isCancelled, accountSession.isCurrent(origin.account), workflowToken == origin.token else {
            throw CancellationError()
        }
    }

    func endWorkflow(_ origin: WorkflowOrigin, error: Error? = nil) {
        guard workflowToken == origin.token, accountSession.isCurrent(origin.account) else { return }
        importBusy = false
        if let error, !(error is CancellationError) { importError = Self.workflowFailure(error) }
    }

    func resetWorkflowPresentation() {
        activeImport = nil; importBusy = false; importError = nil; pendingImports = []; malAccountIdentity = nil
        workflowToken = nil; workflowAccount = nil
        importUndoReverted = 0; importUndoSkipped = 0
    }

    func workflowRPC<Result: Decodable & Sendable, Params: Encodable & Sendable>(
        _ name: String, _ params: Params, origin: WorkflowOrigin
    ) async throws -> Result {
        try checkWorkflow(origin)
        let client = self.client
        do {
            let value: Result = try await accountSession.withCredentialLease(for: origin.account) {
                guard let client else { throw MissingSupabaseConfiguration() }
                return try await client.rpc(name, params: params).execute().value
            }
            try checkWorkflow(origin)
            return value
        } catch {
            try checkWorkflow(origin)
            throw Self.workflowFailure(error)
        }
    }

    static func workflowFailure(_ error: Error) -> ImportFailure {
        if let failure = error as? ImportFailure { return failure }
        if let failure = error as? LibraryActions.ImportPublicationFailure { return .transient(failure.localizedDescription) }
        if let failure = error as? MALConnectionError {
            switch failure {
            case .registrationUnavailable, .invalidToken, .http(status: 401): return .reconnect
            case .providerRejected, .http(status: 403): return .denied
            default: return .transient("The provider connection could not be completed. Retry or reconnect.")
            }
        }
        if let failure = error as? MALAccountList.Failure {
            switch failure {
            case .sourceLimit, .bodyTooLarge: return .limit("The provider list exceeds the supported page/body limit.")
            case .invalidPage, .unsafeCursor: return .invalidInput("The provider returned a malformed or unsafe list page. Missing entries have not been removed.")
            }
        }
        if let failure = error as? FunctionsError {
            if case .httpError(let code, _) = failure {
                if [401, 403].contains(code) { return .denied }
                if code == 400 { return .invalidInput("The provider rejected this source selection or cursor.") }
                if code == 429 { return .transient("The provider is rate limited. Resume this same import later.") }
            }
        }
        if let failure = error as? MALExportError {
            return [.tooLarge, .tooManyItems].contains(failure) ? .limit("This file exceeds the supported import limit.") : .invalidInput("This is not a valid MAL export. Choose a valid XML file.")
        }
        if let failure = error as? LibraryImportPageJournal.Failure {
            switch failure {
            case .recordLimit, .accountBudget: return .limit("The import exceeds this device's protected journal limit. Stop an older active import or use a smaller export.")
            case .cleanupLimit: return .transient("Saved changes are retained. Resume to finish local cleanup.")
            default: return .invalidInput("The protected import record could not be read. Existing Library entries have not been removed.")
            }
        }
        if let failure = error as? PostgrestError {
            if failure.code == "42501" { return .denied }
            if failure.code == "23505" || (failure.code == "P0001" && failure.message == "IMPORT_ALREADY_ACTIVE") { return .activeJob }
            if failure.code == "22023" { return .invalidInput(failure.message) }
        }
        if let failure = error as? URLError {
            if [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(failure.code) { return .uncertainDelivery }
        }
        return .transient("The import could not finish. Saved pages and committed changes are retained; resume to continue.")
    }

    func workflowJournal() throws -> LibraryImportPageJournal {
        guard let importJournal else { throw ImportFailure.limit("Import cannot be safely saved on this device.") }
        return importJournal
    }

    func saveWorkflow(_ manifest: ImportManifest, origin: WorkflowOrigin) async throws {
        try checkWorkflow(origin)
        try await workflowJournal().saveWorkflow(manifest)
        try checkWorkflow(origin)
        if let index = pendingImports.firstIndex(where: { $0.actionId == manifest.actionId }) { pendingImports[index] = manifest }
        else { pendingImports.append(manifest) }
        if let outcome = manifest.outcome { activeImport = outcome }
        importUndoReverted = manifest.undoReverted ?? 0
        importUndoSkipped = manifest.undoSkipped ?? 0
    }

    func localWorkflow(jobId: String, origin: WorkflowOrigin) async throws -> ImportManifest? {
        let values = try await workflowJournal().pendingWorkflows(accountId: origin.account.userId)
        try checkWorkflow(origin)
        pendingImports = values
        return values.first { $0.jobId == jobId }
    }
    @discardableResult
    func completeWorkflowCleanup(_ manifest: ImportManifest, origin: WorkflowOrigin) async throws -> ImportManifest {
        // Journal deletion remains bounded per actor call. Continue its resumable page-only
        // cleanup without making the person tap Resume once for every 256 frozen pages.
        for _ in 0..<40 {
            try checkWorkflow(origin)
            do {
                let journal = try workflowJournal()
                try await journal.completeWorkflow(manifest)
                let records = try await journal.pendingWorkflows(accountId: manifest.accountId)
                try checkWorkflow(origin)
                pendingImports = records
                if let compact = records.first(where: { $0.actionId == manifest.actionId }) { return compact }
                // An old remote result may be outside the latest-ten local retention window.
                // Its current result remains displayable without retaining an approval payload.
                var summary = manifest; summary.decisions = nil; summary.appliedDecisionCount = 0
                return summary
            } catch LibraryImportPageJournal.Failure.cleanupLimit {
                await Task.yield()
            }
        }
        throw LibraryImportPageJournal.Failure.cleanupLimit
    }

}
