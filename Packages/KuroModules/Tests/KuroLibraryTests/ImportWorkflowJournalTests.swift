import Foundation
import Testing
@testable import KuroLibrary

@Suite(.serialized) struct ImportWorkflowJournalTests {
    private let a = "00000000-0000-0000-0000-00000000000a"
    private let b = "00000000-0000-0000-0000-00000000000b"
    private var selection: ImportSelection {
        ImportSelection(provider: .myanimelist, sourceKind: .export, sourceIdentity: "local-export", media: ["anime", "manga"])
    }
    private func temporary() throws -> URL {
        let value = FileManager.default.temporaryDirectory.appendingPathComponent("kuro-import-test-\(UUID())")
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: true)
        return value
    }
    private func page(notes: String? = nil) -> ImportSourcePage {
        .init(items: [.init(draft: .init(medium: "manga", externalId: "7", status: "reading", progress: 3,
                                       notes: notes, sourceTitle: "Source title"))], nextCursor: "next", exhaustedMedia: ["anime": true])
    }
    private func actionFolder(_ root: URL, account: String) throws -> URL {
        try #require(FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("accounts/\(account)"), includingPropertiesForKeys: nil).first)
    }

    @Test func frozenPageAndApprovalSurviveRestartWithoutReplacingIntent() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = try LibraryImportPageJournal(directory: root)
        var manifest = ImportManifest(accountId: a.uppercased(), selection: selection, actionId: "same-gesture")
        try await journal.saveWorkflow(manifest)
        // Crash between saving the body and advancing the manifest must replay exactly this body.
        try await journal.writeWorkflowPage(accountId: a, actionId: manifest.actionId, page: 0, value: page())
        let recovered = try LibraryImportPageJournal(directory: root)
        #expect(try await recovered.readWorkflowPage(accountId: a, actionId: manifest.actionId, page: 0) == page())
        try await recovered.writeWorkflowPage(accountId: a, actionId: manifest.actionId, page: 0, value: page())
        await #expect(throws: LibraryImportPageJournal.Failure.invalidCheckpoint) {
            try await recovered.writeWorkflowPage(accountId: a, actionId: manifest.actionId, page: 0, value: page(notes: "different"))
        }
        manifest.nextPage = 1; manifest.preparedPages = 1; manifest.jobId = "job"; manifest.phase = .applying
        let row = try JSONDecoder().decode(ImportReviewItem.self, from: Data(#"{"medium":"manga","external_id":"7","title":"Title","incoming":{"unavailable_fields":[]},"disposition":"new","changed_fields":[]}"#.utf8))
        manifest.decisions = [ImportDecision(item: row)]
        try await recovered.saveWorkflow(manifest)
        let reopened = try LibraryImportPageJournal(directory: root)
        // Atomic first-manifest failure may leave an empty account-owned folder, not an accepted job.
        try FileManager.default.createDirectory(at: root.appendingPathComponent("accounts/\(a)/interrupted-empty"), withIntermediateDirectories: false)
        #expect(try await reopened.pendingWorkflows(accountId: a).count == 1)
        #expect(try await reopened.loadWorkflow(accountId: a, actionId: manifest.actionId)?.decisions == manifest.decisions)
        #expect(try await reopened.pendingWorkflows(accountId: b).isEmpty)
        var changed = manifest; changed.decisions = []
        await #expect(throws: LibraryImportPageJournal.Failure.invalidCheckpoint) { try await reopened.saveWorkflow(changed) }
    }

    @Test func terminalMarkerPrecedesRepeatablePayloadCleanup() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = try LibraryImportPageJournal(directory: root)
        var manifest = ImportManifest(accountId: a, selection: selection)
        try await journal.saveWorkflow(manifest)
        try await journal.writeWorkflowPage(accountId: a, actionId: manifest.actionId, page: 0, value: page())
        let folder = try actionFolder(root, account: a)
        let body = try JSONEncoder().encode(page())
        // Model many already-frozen pages at the point where the process stops during cleanup.
        for number in 1...260 { try body.write(to: folder.appendingPathComponent("page-\(number).json"), options: .atomic) }
        manifest.phase = .ready
        await #expect(throws: LibraryImportPageJournal.Failure.cleanupLimit) { try await journal.completeWorkflow(manifest) }
        let restarted = try LibraryImportPageJournal(directory: root)
        #expect(try await restarted.loadWorkflow(accountId: a, actionId: manifest.actionId)?.phase == .ready)
        #expect(try await restarted.pendingWorkflows(accountId: a).count == 1)
        try await restarted.completeWorkflow(manifest)
        #expect(try Set(FileManager.default.contentsOfDirectory(atPath: folder.path)) == ["manifest.json", "terminal.json"])
        #expect(try await restarted.readWorkflowPage(accountId: a, actionId: manifest.actionId, page: 0) == nil)
        try await restarted.completeWorkflow(manifest)
    }

    @Test func recordAndActiveAccountBudgetsRejectBeforeChangingFrozenData() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = try LibraryImportPageJournal(directory: root)
        var manifest = ImportManifest(accountId: a, selection: selection)
        try await journal.saveWorkflow(manifest)
        await #expect(throws: LibraryImportPageJournal.Failure.recordLimit) {
            try await journal.writeWorkflowPage(accountId: a, actionId: manifest.actionId, page: 0,
                value: page(notes: String(repeating: "x", count: 8 * 1024 * 1024)))
        }
        let body = page(notes: String(repeating: "x", count: 15 * 1024 * 1024 / 2))
        for number in 0..<8 { try await journal.writeWorkflowPage(accountId: a, actionId: manifest.actionId, page: number, value: body) }
        await #expect(throws: LibraryImportPageJournal.Failure.accountBudget) {
            try await journal.writeWorkflowPage(accountId: a, actionId: manifest.actionId, page: 8, value: body)
        }
        #expect(try await journal.readWorkflowPage(accountId: a, actionId: manifest.actionId, page: 8) == nil)
        var large = ImportManifest(accountId: a, selection: selection)
        large.selection.sourceIdentity = String(repeating: "y", count: 15 * 1024 * 1024 / 2)
        await #expect(throws: LibraryImportPageJournal.Failure.accountBudget) { try await journal.saveWorkflow(large) }
        #expect(try await journal.pendingWorkflows(accountId: a).count == 1)
        manifest.phase = .ready
        try await journal.completeWorkflow(manifest)
        let next = ImportManifest(accountId: a, selection: selection)
        try await journal.saveWorkflow(next)
        try await journal.writeWorkflowPage(accountId: a, actionId: next.actionId, page: 0, value: body)
    }

    @Test func exactAccountDeletionIgnoresOtherCorruptionAndPreventsRecreation() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = try LibraryImportPageJournal(directory: root)
        let ma = ImportManifest(accountId: a, selection: selection)
        let mb = ImportManifest(accountId: b, selection: selection)
        try await journal.saveWorkflow(ma); try await journal.saveWorkflow(mb)
        try await journal.writeWorkflowPage(accountId: a, actionId: ma.actionId, page: 0, value: page())
        try await journal.writeWorkflowPage(accountId: b, actionId: mb.actionId, page: 0, value: page())
        try await journal.write(.init(cursor: "A"), key: "kuro.import.action.\(a).legacy")
        try await journal.write(.init(cursor: "B"), key: "kuro.import.action.\(b).legacy")
        try await journal.write(.init(cursor: "unknown"), key: "unattributed")
        let corrupt = root.appendingPathComponent("other-corrupt.json")
        try Data(repeating: 0, count: 9 * 1024 * 1024).write(to: corrupt)
        let folder = try actionFolder(root, account: a)
        let body = try JSONEncoder().encode(page())
        for number in 1...260 { try body.write(to: folder.appendingPathComponent("page-\(number).json")) }
        var passes = 0
        while true {
            passes += 1
            do { try await journal.removeDeletedAccountData(accountId: a); break }
            catch LibraryImportPageJournal.Failure.cleanupLimit { try #require(passes <= 4) }
        }
        let reopened = try LibraryImportPageJournal(directory: root)
        #expect(try await reopened.pendingWorkflows(accountId: a).isEmpty)
        #expect(try await reopened.loadWorkflow(accountId: b, actionId: mb.actionId) != nil)
        #expect(try await reopened.read(key: "kuro.import.action.\(b).legacy").cursor == "B")
        #expect(try await reopened.read(key: "unattributed").cursor == "unknown")
        #expect(FileManager.default.fileExists(atPath: corrupt.path))
        await #expect(throws: LibraryImportPageJournal.Failure.accountDeleted) { try await reopened.saveWorkflow(ma) }
        await #expect(throws: LibraryImportPageJournal.Failure.accountDeleted) {
            try await reopened.write(.init(cursor: "late"), key: "kuro.import.action.\(a).late")
        }
    }

    @Test func terminalRetentionCompactsApprovalsWithoutDiscardingActiveRecovery() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = try LibraryImportPageJournal(directory: root)
        let row = try JSONDecoder().decode(ImportReviewItem.self, from: Data(#"{"medium":"manga","external_id":"7","title":"Title","incoming":{"unavailable_fields":[]},"disposition":"new","changed_fields":[]}"#.utf8))
        var active = ImportManifest(accountId: a, selection: selection, actionId: "active")
        active.phase = .finalizing; active.decisions = [ImportDecision(item: row)]; active.appliedDecisionCount = 1
        try await journal.saveWorkflow(active)
        try await journal.writeWorkflowPage(accountId: a, actionId: active.actionId, page: 0, value: page())
        var pending: [ImportManifest] = []
        for phase in [ImportPhase.ready, .cancelled, .failed, .undone] {
            var value = active; value.actionId = "pending-" + phase.rawValue; value.phase = phase
            let raw = "{\"job_id\":\"pending\",\"selection\":\(String(data: try JSONEncoder().encode(selection), encoding: .utf8)!),\"phase\":\"\(phase.rawValue)\",\"counts\":{},\"exhausted_media\":{},\"home_revisions\":{},\"projection_ready\":false,\"undo_available\":false,\"history_available\":true}"
            value.outcome = try JSONDecoder().decode(ImportOutcome.self, from: Data(raw.utf8))
            try await journal.saveWorkflow(value)
            await #expect(throws: LibraryImportPageJournal.Failure.invalidCheckpoint) { try await journal.completeWorkflow(value) }
            pending.append(value)
        }
        var newest: ImportManifest!
        for number in 0..<12 {
            var value = ImportManifest(accountId: a, selection: selection, actionId: "terminal-\(number)")
            value.phase = .applying; value.jobId = "job-\(number)"; value.startAttempted = true
            value.decisions = [ImportDecision(item: row)]; value.appliedDecisionCount = 1
            try await journal.saveWorkflow(value)
            value.phase = .ready
            try await journal.completeWorkflow(value)
            newest = value
        }
        let restarted = try LibraryImportPageJournal(directory: root)
        let summaries = try await restarted.pendingWorkflows(accountId: a)
        #expect(summaries.filter { $0.phase == .ready && $0.outcome?.projectionReady != false }.count == 10)
        #expect(try await restarted.loadWorkflow(accountId: a, actionId: "terminal-0") == nil)
        #expect(summaries.filter { $0.phase == .ready && $0.outcome?.projectionReady != false }.allSatisfy { $0.decisions == nil && $0.appliedDecisionCount == 0 })
        #expect(try await restarted.loadWorkflow(accountId: a, actionId: active.actionId) == active)
        for value in pending { #expect(try await restarted.loadWorkflow(accountId: a, actionId: value.actionId) == value) }
        #expect(try await restarted.readWorkflowPage(accountId: a, actionId: active.actionId, page: 0) == page())
        // Replaying the old completion body cannot reintroduce its private approval array.
        try await restarted.completeWorkflow(newest)
        #expect(try await restarted.loadWorkflow(accountId: a, actionId: newest.actionId)?.decisions == nil)
        var undo = try #require(await restarted.loadWorkflow(accountId: a, actionId: newest.actionId))
        undo.phase = .undoing; undo.undoActionId = "same-undo"; undo.undoCursor = "next"
        try await restarted.saveWorkflow(undo)
        #expect(try await restarted.loadWorkflow(accountId: a, actionId: undo.actionId)?.phase == .undoing)
        var invalid = undo; invalid.startAttempted = false
        await #expect(throws: LibraryImportPageJournal.Failure.invalidCheckpoint) { try await restarted.saveWorkflow(invalid) }
        // A definitive jobless rejection is permitted to clear attempted admission.
        var rejected = ImportManifest(accountId: b, selection: selection)
        rejected.startAttempted = true; try await restarted.saveWorkflow(rejected)
        rejected.startAttempted = false; try await restarted.saveWorkflow(rejected)
    }

    @Test func interruptedRetirementKeepsDiscoveryAndCleanupRecoverable() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = try LibraryImportPageJournal(directory: root)
        var jobs: [ImportManifest] = []
        for index in 0..<10 {
            var value = ImportManifest(accountId: a, selection: selection, actionId: "retire-\(index)")
            value.phase = .ready; try await journal.completeWorkflow(value); jobs.append(value)
        }
        func folder(for action: String) throws -> URL {
            let account = root.appendingPathComponent("accounts/\(a)")
            return try #require(FileManager.default.contentsOfDirectory(at: account, includingPropertiesForKeys: nil).first { entry in
                guard entry.lastPathComponent != "retention.json", let data = try? Data(contentsOf: entry.appendingPathComponent("manifest.json")),
                      let value = try? JSONDecoder().decode(ImportManifest.self, from: data) else { return false }
                return value.actionId == action
            })
        }
        let first = try folder(for: jobs[0].actionId)
        // Crash after receipt removal: the manifest still attributes a terminal folder.
        try FileManager.default.removeItem(at: first.appendingPathComponent("terminal.json"))
        #expect(try await journal.pendingWorkflows(accountId: a).count == 10)
        var eleven = ImportManifest(accountId: a, selection: selection, actionId: "retire-10"); eleven.phase = .ready
        try await journal.completeWorkflow(eleven)
        #expect(!FileManager.default.fileExists(atPath: first.path))
        let second = try folder(for: jobs[1].actionId)
        // Crash after manifest-last removal: the retained candidate still attributes an empty folder.
        try FileManager.default.removeItem(at: second.appendingPathComponent("terminal.json"))
        try FileManager.default.removeItem(at: second.appendingPathComponent("manifest.json"))
        #expect(try await journal.pendingWorkflows(accountId: a).count == 9)
        var twelve = ImportManifest(accountId: a, selection: selection, actionId: "retire-11"); twelve.phase = .ready
        try await journal.completeWorkflow(twelve)
        #expect(!FileManager.default.fileExists(atPath: second.path))
        #expect(try await journal.pendingWorkflows(accountId: a).count == 10)
    }

    @Test func reviewDedupUnionsShelvesButNeverSilentlyOverwritesCoreFields() throws {
        let one = LibraryImportDraft(medium: "anime", externalId: "7", status: "watching", progress: 1, customLists: ["A"], sourceTitle: "First")
        var equivalent = one; equivalent.customLists = ["B"]; equivalent.sourceTitle = "Alternate display"
        var conflicting = equivalent; conflicting.progress = 2
        var otherMedium = one; otherMedium.medium = "manga"
        let result = LibraryImportBatch.prepareForReview([one, equivalent, conflicting, otherMedium])
        #expect(result.count == 3)
        #expect(result[0].customLists == ["A", "B"])
        #expect(result[0].progress == 1 && result[1].progress == 2)
        #expect(result[0].sourceTitle == "First")
        var displayOnly = one; displayOnly.sourceTitle = "Alternate display"
        #expect(LibraryImportBatch.payloadHash([one]) == LibraryImportBatch.payloadHash([displayOnly]))
        #expect(LibraryImportBatch.prepare([one, conflicting]).first?.progress == 2)
    }
}

@Suite struct MALInputFidelityTests {
    private func xml(_ fields: String, medium: String = "manga") -> Data {
        Data("<myanimelist><\(medium)>\(fields)</\(medium)></myanimelist>".utf8)
    }
    private var identity: String { "<series_mangadb_id>7</series_mangadb_id><my_status>Reading</my_status>" }

    @Test func scoresAndMissingFieldsRemainDistinctAndTitlesSurvive() throws {
        let fields = identity + "<series_title>Source &amp; title</series_title><my_read_chapters>3</my_read_chapters><my_read_volumes>2</my_read_volumes><my_score>8</my_score><my_comments><![CDATA[ keep this \n]]></my_comments><my_times_read>1</my_times_read><my_start_date>2024-02-29</my_start_date><my_finish_date>2025-00-00</my_finish_date>"
        let item = try #require(MALExportParser.parse(xml(fields)).first)
        #expect(item.draft().normalizedRating == 8 && item.scoreRaw == "8")
        #expect(item.draft().sourceTitle == "Source & title")
        #expect(item.notes == " keep this \n")
        #expect(item.finishedRaw == "2025-00-00")
        let missing = try #require(MALExportParser.parse(xml(identity)).first).draft()
        #expect(missing.unavailableFields.isSuperset(of: ["progress", "score", "notes", "repeat_count", "volumes_progress"]))
        let zero = try #require(MALExportParser.parse(xml(identity + "<my_score>0</my_score>")).first).draft()
        #expect(zero.scoreRaw == nil && zero.normalizedRating == nil && !zero.unavailableFields.contains("score"))
    }

    @Test func invalidNumericStatusAndHierarchyRejectInsteadOfDefaulting() throws {
        for field in ["<my_score>11</my_score>", "<my_score>-1</my_score>", "<my_score>oops</my_score>",
                      "<my_read_chapters>-1</my_read_chapters>", "<my_read_chapters></my_read_chapters>",
                      "<my_read_volumes>2147483648</my_read_volumes>", "<my_start_date>2025-02-29</my_start_date>",
                      "<my_score>3</my_score><my_score>4</my_score>"] {
            #expect(throws: MALExportError.malformed) { try MALExportParser.parse(xml(identity + field)) }
        }
        for text in ["<wrapper><myanimelist></myanimelist></wrapper>",
                     "<myanimelist><wrapper><manga>\(identity)</manga></wrapper></myanimelist>",
                     "<myanimelist><manga>\(identity)<my_comments><manga/></my_comments></manga></myanimelist>",
                     "<myanimelist><manga><series_mangadb_id>7</series_mangadb_id><my_status>nonsense</my_status></manga></myanimelist>"] {
            #expect(throws: MALExportError.malformed) { try MALExportParser.parse(Data(text.utf8)) }
        }
        #expect(try MALExportParser.parse(Data("<myanimelist><myinfo><user_name>tester</user_name></myinfo></myanimelist>".utf8)).isEmpty)
    }

    @Test func accountPageTitleZeroScoreAndTypedInvalidCursor() throws {
        let body = Data(#"{"data":[{"node":{"id":7,"title":"Actual provider title"},"list_status":{"status":"reading","score":0,"num_chapters_read":3}}],"paging":{}}"#.utf8)
        let draft = try #require(MALAccountList.decode(body, medium: .manga, offset: 0).drafts.first)
        #expect(draft.sourceTitle == "Actual provider title" && draft.scoreRaw == nil && draft.normalizedRating == nil)
        #expect(!draft.unavailableFields.contains("score"))
        #expect(throws: MALAccountList.Failure.unsafeCursor) { try MALAccountImportCursor.decode("not json") }
        #expect(throws: MALAccountList.Failure.unsafeCursor) { try MALAccountList.decode(body, medium: .manga, offset: -1) }
        #expect(throws: MALAccountList.Failure.invalidPage) {
            try MALAccountList.decode(Data(String(decoding: body, as: UTF8.self).replacingOccurrences(of: "\"id\":7", with: "\"id\":2147483648").utf8), medium: .manga, offset: 0)
        }
    }
}
