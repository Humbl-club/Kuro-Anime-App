import CryptoKit
import Foundation

extension LibraryImportPageJournal {
    public static let maxActiveAccountBytes = 64 * 1024 * 1024
    private static let maximumRecords = 10_240
    private static let cleanupRecordsPerPass = 256

    public func saveWorkflow(_ manifest: ImportManifest) throws {
        let account = try canonicalAccount(manifest.accountId)
        try requireWritableAccount(account)
        var attributed = manifest
        attributed.accountId = account
        let prior = try loadWorkflow(accountId: account, actionId: manifest.actionId)
        let folder = try workflowDirectory(account, manifest.actionId, create: false)
        let receipt = try terminalReceipt(folder, account: account, actionId: manifest.actionId)
        if receipt != nil,
           acknowledgedTerminal(manifest) || manifest.phase == .undoing {
            attributed.decisions = nil; attributed.appliedDecisionCount = 0
        }
        try validate(attributed)
        if let prior {
            guard !(prior.startAttempted == true && manifest.startAttempted != true &&
                    (prior.jobId != nil || manifest.jobId != nil)), prior.selection == manifest.selection,
                  prior.jobId == nil || prior.jobId == manifest.jobId,
                  prior.decisions == nil || prior.decisions == attributed.decisions ||
                    (terminal(prior.phase) && receipt != nil && attributed.decisions == nil),
                  prior.nextPage <= manifest.nextPage, prior.preparedPages <= manifest.preparedPages,
                  prior.appliedDecisionCount <= attributed.appliedDecisionCount ||
                    (terminal(prior.phase) && receipt != nil && attributed.decisions == nil),
                  !acknowledgedTerminal(prior) || terminal(manifest.phase) || manifest.phase == .undoing else {
                throw Failure.invalidCheckpoint
            }
        }
        let data = try encoded(attributed)
        let file = folder.appendingPathComponent("manifest.json")
        if !acknowledgedTerminal(attributed) {
            try enforceActiveBudget(accountId: account, incoming: data.count, replacing: prior.map(acknowledgedTerminal) == true ? nil : file)
        }
        _ = try workflowDirectory(account, manifest.actionId, create: true)
        try atomicWrite(data, to: file)
    }

    public func loadWorkflow(accountId: String, actionId: String) throws -> ImportManifest? {
        let account = try canonicalAccount(accountId)
        let folder = try workflowDirectory(account, actionId, create: false)
        let file = folder.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let value = try JSONDecoder().decode(ImportManifest.self, from: boundedData(file))
        guard value.accountId.lowercased() == account, value.actionId == actionId else { throw Failure.invalidCheckpoint }
        try validate(value)
        return value
    }

    /// Includes terminal manifests: callers can restore results/Undo as well as active preparation.
    public func pendingWorkflows(accountId: String) throws -> [ImportManifest] {
        let account = try canonicalAccount(accountId)
        let folder = try accountDirectory(account, create: false)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        var values: [ImportManifest] = []
        for actionFolder in try children(folder) {
            if actionFolder.lastPathComponent == "retention.json" { continue }
            try requireDirectory(actionFolder)
            let file = actionFolder.appendingPathComponent("manifest.json")
            guard FileManager.default.fileExists(atPath: file.path) else {
                // An interrupted first atomic write can leave only an empty attributed directory.
                guard try children(actionFolder).isEmpty else { throw Failure.invalidCheckpoint }
                continue
            }
            let manifest = try JSONDecoder().decode(ImportManifest.self, from: boundedData(file))
            guard manifest.accountId.lowercased() == account,
                  actionFolder.lastPathComponent == digest(manifest.actionId) else { throw Failure.invalidCheckpoint }
            try validate(manifest)
            values.append(manifest)
        }
        return values.sorted { $0.actionId < $1.actionId }
    }

    public func writeWorkflowPage(accountId: String, actionId: String, page: Int, value: ImportSourcePage) throws {
        let account = try canonicalAccount(accountId)
        try requireWritableAccount(account)
        guard let manifest = try loadWorkflow(accountId: account, actionId: actionId), !terminal(manifest.phase),
              page >= 0, page < Self.maximumRecords else { throw Failure.invalidCheckpoint }
        let data = try encoded(value)
        let folder = try workflowDirectory(account, actionId, create: false)
        let file = folder.appendingPathComponent("page-\(page).json")
        if FileManager.default.fileExists(atPath: file.path) {
            guard try JSONDecoder().decode(ImportSourcePage.self, from: boundedData(file)) == value else { throw Failure.invalidCheckpoint }
            return
        }
        try enforceActiveBudget(accountId: account, incoming: data.count, replacing: nil)
        try atomicWrite(data, to: file)
    }

    public func readWorkflowPage(accountId: String, actionId: String, page: Int) throws -> ImportSourcePage? {
        let account = try canonicalAccount(accountId)
        guard page >= 0, page < Self.maximumRecords else { throw Failure.invalidCheckpoint }
        let folder = try workflowDirectory(account, actionId, create: false)
        let file = folder.appendingPathComponent("page-\(page).json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(ImportSourcePage.self, from: boundedData(file))
    }

    public func completeWorkflow(_ manifest: ImportManifest) throws {
        guard acknowledgedTerminal(manifest) else {
            throw Failure.invalidCheckpoint
        }
        // Commit the terminal acknowledgment before removing any recovery body. A receipt fixes
        // ordering across repeated cleanup and allows subsequent saves to stay compact.
        try saveWorkflow(manifest)
        let account = try canonicalAccount(manifest.accountId)
        let folder = try workflowDirectory(account, manifest.actionId, create: false)
        var saved = try loadWorkflow(accountId: account, actionId: manifest.actionId)!
        let receipt = try acknowledgeTerminal(saved, folder: folder)
        saved.decisions = nil; saved.appliedDecisionCount = 0
        try atomicWrite(try encoded(saved), to: folder.appendingPathComponent("manifest.json"))
        var remaining = Self.cleanupRecordsPerPass
        guard try cleanPayload(folder, remaining: &remaining) else { throw Failure.cleanupLimit }
        try retainTerminalSummaries(account: account, current: receipt, remaining: &remaining)
    }

    private struct TerminalReceipt: Codable {
        var accountId: String
        var actionId: String
        var phase: ImportPhase
        var acknowledgedAt: Date
    }
    private struct RetentionState: Codable {
        var accountId: String
        var cursor: String?
        var candidates: [TerminalReceipt] = []
    }
    private func terminalReceipt(_ folder: URL, account: String, actionId: String) throws -> TerminalReceipt? {
        let file = folder.appendingPathComponent("terminal.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let receipt = try JSONDecoder().decode(TerminalReceipt.self, from: boundedData(file))
        guard receipt.accountId == account, receipt.actionId == actionId, terminal(receipt.phase) else { throw Failure.invalidCheckpoint }
        return receipt
    }
    private func acknowledgeTerminal(_ value: ImportManifest, folder: URL, inheritedDate: Date? = nil) throws -> TerminalReceipt {
        if let old = try terminalReceipt(folder, account: value.accountId, actionId: value.actionId), old.phase == value.phase { return old }
        let receipt = TerminalReceipt(accountId: value.accountId, actionId: value.actionId, phase: value.phase, acknowledgedAt: inheritedDate ?? Date())
        try atomicWrite(try encoded(receipt), to: folder.appendingPathComponent("terminal.json"))
        return receipt
    }
    private func cleanPayload(_ folder: URL, remaining: inout Int) throws -> Bool {
        let pages = try children(folder).filter { $0.lastPathComponent.hasPrefix("page-") }
        for file in pages {
            guard remaining > 0 else { return false }
            let attributes = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard attributes.isRegularFile == true || attributes.isSymbolicLink == true else { throw Failure.invalidCheckpoint }
            try FileManager.default.removeItem(at: file); remaining -= 1
        }
        return true
    }
    /// Only acknowledged, attributed terminal jobs are retired. Cursor/candidates make a large
    /// inherited journal progress over bounded passes instead of rereading a fixed prefix.
    private func retainTerminalSummaries(account: String, current: TerminalReceipt, remaining: inout Int) throws {
        let folder = try accountDirectory(account, create: false)
        let file = folder.appendingPathComponent("retention.json")
        var state = FileManager.default.fileExists(atPath: file.path)
            ? try JSONDecoder().decode(RetentionState.self, from: boundedData(file)) : RetentionState(accountId: account)
        guard state.accountId == account, state.candidates.count <= Self.maximumRecords,
              state.candidates.allSatisfy({ $0.accountId == account && terminal($0.phase) }) else { throw Failure.invalidCheckpoint }
        state.candidates.removeAll { $0.actionId == current.actionId }
        state.candidates.append(current)
        let actions = try children(folder).filter { $0.lastPathComponent != "retention.json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var scannedBytes = 0
        do {
            try pruneCandidates(&state, remaining: &remaining)
            for action in actions where state.cursor == nil || action.lastPathComponent > state.cursor! {
                guard remaining > 0, scannedBytes < Self.maxActiveAccountBytes else { throw Failure.cleanupLimit }
                remaining -= 1
                let manifestFile = action.appendingPathComponent("manifest.json")
                if let size = try? recordSize(manifestFile) { scannedBytes += size }
                // Unknown/corrupt attribution is preserved and does not block other valid records.
                if (try? requireDirectory(action)) != nil,
                   var value = try? JSONDecoder().decode(ImportManifest.self, from: boundedData(manifestFile)),
                   value.accountId == account, action.lastPathComponent == digest(value.actionId),
                   (try? validate(value)) != nil, acknowledgedTerminal(value) {
                    let modified = try manifestFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                    let receipt = try acknowledgeTerminal(value, folder: action, inheritedDate: modified)
                    if value.decisions != nil || value.appliedDecisionCount != 0 {
                        value.decisions = nil; value.appliedDecisionCount = 0
                        try atomicWrite(try encoded(value), to: manifestFile)
                    }
                    state.candidates.removeAll { $0.actionId == receipt.actionId }
                    state.candidates.append(receipt)
                }
                state.cursor = action.lastPathComponent
                try pruneCandidates(&state, remaining: &remaining)
            }
            state.cursor = nil
            try atomicWrite(try encoded(state), to: file)
        } catch {
            try atomicWrite(try encoded(state), to: file)
            throw error
        }
    }
    private func pruneCandidates(_ state: inout RetentionState, remaining: inout Int) throws {
        var eligible: [TerminalReceipt] = []
        for candidate in state.candidates {
            if let value = try? loadWorkflow(accountId: state.accountId, actionId: candidate.actionId) {
                if acknowledgedTerminal(value) { eligible.append(candidate) }
            } else if let folder = try? workflowDirectory(state.accountId, candidate.actionId, create: false),
                      FileManager.default.fileExists(atPath: folder.path), (try? children(folder).isEmpty) == true {
                // The manifest is removed last: a crash after its unlink leaves only this empty
                // directory, whose retirement attribution survives in the protected candidate list.
                guard remaining > 0 else { throw Failure.cleanupLimit }
                try FileManager.default.removeItem(at: folder); remaining -= 1
            }
        }
        state.candidates = eligible
        state.candidates.sort {
            $0.acknowledgedAt == $1.acknowledgedAt ? $0.actionId > $1.actionId : $0.acknowledgedAt > $1.acknowledgedAt
        }
        while state.candidates.count > 10 {
            let old = state.candidates.last!
            let folder = try workflowDirectory(state.accountId, old.actionId, create: false)
            if let value = try? loadWorkflow(accountId: state.accountId, actionId: old.actionId), acknowledgedTerminal(value) {
                guard try cleanPayload(folder, remaining: &remaining), remaining >= 2 else { throw Failure.cleanupLimit }
                let files = try children(folder)
                // Do not retire unexpected files whose provenance is not established by this journal.
                guard files.allSatisfy({ ["manifest.json", "terminal.json"].contains($0.lastPathComponent) }) else {
                    state.candidates.removeLast(); continue
                }
                // Keep the attributed terminal manifest until every other known file is gone.
                // Interrupted retirement can then be rediscovered; after its final unlink the
                // remaining empty directory is safe to reclaim on the next bounded pass.
                for file in files.sorted(by: { $0.lastPathComponent == "terminal.json" && $1.lastPathComponent != "terminal.json" }) {
                    try FileManager.default.removeItem(at: file); remaining -= 1
                }
                try FileManager.default.removeItem(at: folder)
            }
            state.candidates.removeLast()
        }
    }

    func requireWritableAccount(_ account: String) throws {
        if deletedAccounts.contains(account) || FileManager.default.fileExists(atPath: deletionMarker(account).path) {
            throw Failure.accountDeleted
        }
    }

    /// The budget includes legacy attributed checkpoints and all payload of active workflows.
    func enforceActiveBudget(accountId: String, incoming: Int, replacing: URL?) throws {
        var bytes = 0
        var records = 0
        let folder = try accountDirectory(accountId, create: false)
        if FileManager.default.fileExists(atPath: folder.path) {
            for action in try children(folder) {
                if action.lastPathComponent == "retention.json" { continue }
                try requireDirectory(action)
                let manifestFile = action.appendingPathComponent("manifest.json")
                let manifest = try? JSONDecoder().decode(ImportManifest.self, from: boundedData(manifestFile))
                if manifest.map(acknowledgedTerminal) == true { continue }
                for file in try children(action) where file != replacing {
                    records += 1
                    guard records < Self.maximumRecords else { throw Failure.accountBudget }
                    bytes += try recordSize(file)
                    if bytes + incoming > Self.maxActiveAccountBytes { throw Failure.accountBudget }
                }
            }
        }
        for file in try children(directory) where file.pathExtension == "json" && file != replacing {
            guard let checkpoint = try? JSONDecoder().decode(Checkpoint.self, from: boundedData(file)),
                  checkpoint.accountId?.lowercased() == accountId else { continue }
            bytes += try recordSize(file)
            if bytes + incoming > Self.maxActiveAccountBytes { throw Failure.accountBudget }
        }
        guard bytes + incoming <= Self.maxActiveAccountBytes else { throw Failure.accountBudget }
    }

    private struct DeletionProgress: Codable {
        var legacyCursor: String?
        var complete: Bool = false
    }

    func removeWorkflowAccountData(accountId: String) throws {
        let account = try canonicalAccount(accountId)
        deletedAccounts.insert(account)
        try ensureAccountsRoot()
        let marker = deletionMarker(account)
        var progress = (try? JSONDecoder().decode(DeletionProgress.self, from: boundedData(marker))) ?? DeletionProgress()
        try atomicWrite(try encoded(progress), to: marker)
        let folder = try accountDirectory(account, create: false)
        var remaining = Self.cleanupRecordsPerPass
        if FileManager.default.fileExists(atPath: folder.path) {
            try removeAttributedTree(folder, remaining: &remaining, depth: 0)
        }
        guard remaining > 0 else { throw Failure.cleanupLimit }
        // A separate cursor prevents another account's corrupt/large legacy files from repeatedly
        // consuming the same bounded scan. Unknown legacy files are preserved, not guessed away.
        let legacy = try children(directory).filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .filter { progress.legacyCursor == nil || $0.lastPathComponent > progress.legacyCursor! }
        var scannedBytes = 0
        for file in legacy {
            if remaining == 0 || scannedBytes >= 32 * 1024 * 1024 {
                try atomicWrite(try encoded(progress), to: marker)
                throw Failure.cleanupLimit
            }
            remaining -= 1
            if let size = try? recordSize(file) { scannedBytes += size }
            if let checkpoint = try? JSONDecoder().decode(Checkpoint.self, from: boundedData(file)),
               checkpoint.accountId?.lowercased() == account {
                try FileManager.default.removeItem(at: file)
            }
            progress.legacyCursor = file.lastPathComponent
        }
        progress.complete = true
        try atomicWrite(try encoded(progress), to: marker)
    }

    private func removeAttributedTree(_ folder: URL, remaining: inout Int, depth: Int) throws {
        guard depth <= 8 else { throw Failure.cleanupLimit }
        try requireDirectory(folder)
        for file in try children(folder) {
            guard remaining > 0 else { throw Failure.cleanupLimit }
            let attributes = try file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if attributes.isDirectory == true && attributes.isSymbolicLink != true {
                try removeAttributedTree(file, remaining: &remaining, depth: depth + 1)
            } else {
                try FileManager.default.removeItem(at: file)
                remaining -= 1
            }
        }
        try FileManager.default.removeItem(at: folder)
    }

    private func canonicalAccount(_ raw: String) throws -> String {
        guard let value = UUID(uuidString: raw) else { throw Failure.invalidAccount }
        return value.uuidString.lowercased()
    }
    private func terminal(_ phase: ImportPhase?) -> Bool {
        guard let phase else { return false }
        return [.ready, .cancelled, .failed, .undone].contains(phase)
    }
    private func acknowledgedTerminal(_ manifest: ImportManifest) -> Bool {
        terminal(manifest.phase) && manifest.outcome?.projectionReady != false
    }
    private func validate(_ manifest: ImportManifest) throws {
        guard !manifest.actionId.isEmpty, manifest.actionId.utf8.count <= 256,
              manifest.nextPage >= 0, manifest.nextPage <= Self.maximumRecords,
              manifest.preparedPages >= 0, manifest.preparedPages <= manifest.nextPage,
              manifest.appliedDecisionCount >= 0,
              manifest.appliedDecisionCount <= (manifest.decisions?.count ?? 0) else { throw Failure.invalidCheckpoint }
    }
    private func digest(_ action: String) -> String { SHA256.hash(data: Data(action.utf8)).map { String(format: "%02x", $0) }.joined() }
    private func deletionMarker(_ account: String) -> URL { directory.appendingPathComponent("accounts/deleted-\(account).json") }
    private func ensureAccountsRoot() throws {
        try requireDirectory(directory)
        let root = directory.appendingPathComponent("accounts", isDirectory: true)
        if FileManager.default.fileExists(atPath: root.path) { try requireDirectory(root) }
        else { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false) }
    }
    private func accountDirectory(_ account: String, create: Bool) throws -> URL {
        try requireDirectory(directory)
        let root = directory.appendingPathComponent("accounts", isDirectory: true)
        if FileManager.default.fileExists(atPath: root.path) { try requireDirectory(root) }
        if create { try ensureAccountsRoot() }
        let folder = directory.appendingPathComponent("accounts/\(account)", isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) { try requireDirectory(folder) }
        else if create { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false) }
        return folder
    }
    private func workflowDirectory(_ account: String, _ action: String, create: Bool) throws -> URL {
        guard !action.isEmpty, action.utf8.count <= 256 else { throw Failure.invalidCheckpoint }
        let accountFolder = try accountDirectory(account, create: create)
        let folder = accountFolder.appendingPathComponent(digest(action), isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) { try requireDirectory(folder) }
        else if create { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false) }
        return folder
    }
    private func requireDirectory(_ folder: URL) throws {
        let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw Failure.invalidCheckpoint }
    }
    private func children(_ folder: URL) throws -> [URL] {
        let values = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        guard values.count <= Self.maximumRecords else { throw Failure.cleanupLimit }
        return values
    }
    private func recordSize(_ file: URL) throws -> Int {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size >= 0, size <= Self.maxCheckpointBytes else { throw Failure.invalidCheckpoint }
        return size
    }
    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard data.count <= Self.maxCheckpointBytes else { throw Failure.recordLimit }
        return data
    }
    private func atomicWrite(_ data: Data, to file: URL) throws {
        if FileManager.default.fileExists(atPath: file.path) {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.invalidCheckpoint }
        }
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: .atomic)
        #endif
    }
}
