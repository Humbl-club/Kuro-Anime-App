import CryptoKit
import Foundation
import KuroCore
import KuroLibrary
import Supabase

extension ImportsService {
    func runWorkflow<T>(_ operation: (WorkflowOrigin) async throws -> T) async throws -> T {
        let origin = try beginWorkflow()
        do { let value = try await operation(origin); endWorkflow(origin); return value }
        catch { endWorkflow(origin, error: error); throw error is CancellationError ? error : Self.workflowFailure(error) }
    }

    func prepareAniListImport(username: String, types: [String] = ["ANIME", "MANGA"],
        statuses: [String] = ["CURRENT", "COMPLETED", "PLANNING", "PAUSED", "DROPPED", "REPEATING"],
        onActionId: (@MainActor (String) -> Void)? = nil
    ) async throws -> ImportOutcome {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let media = Array(Set(types.map { $0.lowercased() })).sorted()
        let filters = Array(Set(statuses.map { $0.uppercased() })).sorted()
        guard !user.isEmpty, user.utf8.count <= 64, !media.isEmpty,
              Set(media).isSubset(of: ["anime", "manga"]), !filters.isEmpty,
              Set(filters).isSubset(of: ["CURRENT", "COMPLETED", "PLANNING", "PAUSED", "DROPPED", "REPEATING"]) else {
            throw ImportFailure.invalidInput("Choose an AniList user, Anime/Manga and valid statuses.")
        }
        return try await runWorkflow { origin in
            var manifest = ImportManifest(accountId: origin.account.userId,
                selection: ImportSelection(provider: .anilist, sourceKind: .account, sourceIdentity: user,
                    media: media, statuses: filters))
            onActionId?(manifest.actionId)
            try await self.saveWorkflow(manifest, origin: origin)
            return try await self.prepareWorkflow(&manifest, origin: origin)
        }
    }

    @discardableResult
    func refreshMALAccountIdentity() async throws -> String? {
        guard let account = accountSession.current else { throw CancellationError() }
        let reader = try await malAccount.beginReader()
        guard accountSession.isCurrent(account), malAccount.isCurrent(reader) else { throw CancellationError() }
        if workflowAccount != account { resetWorkflowPresentation(); workflowAccount = account }
        malAccountIdentity = reader.providerName
        return reader.providerName
    }

    func prepareMALAccountImport(onActionId: (@MainActor (String) -> Void)? = nil) async throws -> ImportOutcome {
        try await runWorkflow { origin in
            let reader = try await self.malAccount.beginReader()
            try self.checkWorkflow(origin)
            guard self.malAccount.isCurrent(reader) else { throw CancellationError() }
            self.malAccountIdentity = reader.providerName
            var manifest = ImportManifest(accountId: origin.account.userId,
                selection: ImportSelection(provider: .myanimelist, sourceKind: .account,
                    sourceIdentity: String(reader.providerUserId), media: ["anime", "manga"]))
            onActionId?(manifest.actionId)
            try await self.saveWorkflow(manifest, origin: origin)
            return try await self.prepareWorkflow(&manifest, origin: origin, malReader: reader)
        }
    }

    func prepareMALFileImport(data: Data, label: String) async throws -> ImportOutcome {
        try await runWorkflow { origin in
            // Parsing is CPU/file work. The mounted account is checked again before any journal/RPC.
            let parsed = try await Task.detached(priority: .utility) {
                try Task.checkCancellation()
                return LibraryImportBatch.prepareForReview(try MALExportParser.parse(data).map { $0.draft() })
            }.value
            try self.checkWorkflow(origin)
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let media = Array(Set(parsed.map(\.medium))).sorted()
            var manifest = ImportManifest(accountId: origin.account.userId,
                selection: ImportSelection(provider: .myanimelist, sourceKind: .export,
                    sourceIdentity: String(label.prefix(128)) + "|" + hash,
                    media: media.isEmpty ? ["anime", "manga"] : media))
            try await self.saveWorkflow(manifest, origin: origin)
            // Freeze the complete export BEFORE admitting a server job. Once admitted, recovery
            // never requires the original security-scoped file or a new parse of changed data.
            let items = parsed.map { ImportSourceItem(draft: $0) }
            let chunks = Self.sourceChunks(items)
            for (index, chunk) in chunks.enumerated() {
                let exhaustion = index == chunks.count - 1 ? Dictionary(uniqueKeysWithValues: manifest.selection.media.map { ($0, true) }) : [:]
                try await self.freezeSourcePage(ImportSourcePage(items: chunk, nextCursor: nil, exhaustedMedia: exhaustion),
                    manifest: &manifest, origin: origin)
            }
            manifest.sourceExhausted = true
            try await self.saveWorkflow(manifest, origin: origin)
            return try await self.prepareWorkflow(&manifest, origin: origin)
        }
    }

    static func sourceChunks(_ items: [ImportSourceItem]) -> [[ImportSourceItem]] {
        if items.isEmpty { return [[]] }
        return stride(from: 0, to: items.count, by: 100).map { Array(items[$0..<min($0 + 100, items.count)]) }
    }

    func freezeSourcePage(_ page: ImportSourcePage, manifest: inout ImportManifest, origin: WorkflowOrigin) async throws {
        try checkWorkflow(origin)
        try await workflowJournal().writeWorkflowPage(accountId: manifest.accountId, actionId: manifest.actionId,
            page: manifest.nextPage, value: page)
        try checkWorkflow(origin)
        manifest.nextPage += 1; manifest.cursor = page.nextCursor
        manifest.sourceExhausted = manifest.selection.media.allSatisfy { page.exhaustedMedia[$0] == true }
        try await saveWorkflow(manifest, origin: origin)
    }

    func prepareWorkflow(_ manifest: inout ImportManifest, origin: WorkflowOrigin,
        malReader: MALNativeAccountConnector.ReaderSession? = nil
    ) async throws -> ImportOutcome {
        if let jobId = manifest.jobId {
            let status: ImportOutcome = try await workflowRPC("import_job_status_v2", ImportJobInput(p_job_id: jobId), origin: origin)
            if status.isTerminal { return try await publishWorkflow(status, manifest: &manifest, origin: origin) }
        }
        // Recover a page atomically written immediately before a lost manifest update.
        while let page = try await workflowJournal().readWorkflowPage(accountId: manifest.accountId,
            actionId: manifest.actionId, page: manifest.nextPage) {
            try checkWorkflow(origin)
            manifest.nextPage += 1; manifest.cursor = page.nextCursor
            manifest.sourceExhausted = manifest.selection.media.allSatisfy { page.exhaustedMedia[$0] == true }
            try await saveWorkflow(manifest, origin: origin)
        }
        if manifest.selection.sourceKind == .export && !manifest.sourceExhausted {
            throw ImportFailure.invalidInput("The file was interrupted before it was fully saved. Choose the original export again; no server changes were started.")
        }
        if manifest.jobId == nil {
            try await startWorkflow(&manifest, origin: origin)
        }
        var reader = malReader
        if manifest.selection.provider == .myanimelist, manifest.selection.sourceKind == .account, !manifest.sourceExhausted {
            if reader == nil { reader = try await malAccount.beginReader() }
            try checkWorkflow(origin)
            guard let reader, malAccount.isCurrent(reader), String(reader.providerUserId) == manifest.selection.sourceIdentity else {
                throw ImportFailure.reconnect
            }
            malAccountIdentity = reader.providerName
        }
        while true {
            try checkWorkflow(origin)
            while manifest.preparedPages < manifest.nextPage {
                guard let page = try await workflowJournal().readWorkflowPage(accountId: manifest.accountId,
                    actionId: manifest.actionId, page: manifest.preparedPages), let jobId = manifest.jobId else {
                    throw ImportFailure.invalidInput("An original source page is unavailable. Stop remaining work; committed entries are retained.")
                }
                let chunks = Self.sourceChunks(page.items)
                for (index, chunk) in chunks.enumerated() {
                    let outcome: ImportOutcome = try await workflowRPC("prepare_import_chunk_v2",
                        ImportPrepareInput(p_job_id: jobId, p_items: chunk,
                            p_exhausted_media: index == chunks.count - 1 ? page.exhaustedMedia : [:]), origin: origin)
                    manifest.outcome = outcome; activeImport = outcome
                }
                manifest.preparedPages += 1
                try await saveWorkflow(manifest, origin: origin)
            }
            if manifest.sourceExhausted { break }
            let page: ImportSourcePage
            if manifest.selection.provider == .anilist { page = try await fetchAniListPage(manifest, origin: origin) }
            else {
                guard let reader, malAccount.isCurrent(reader) else { throw ImportFailure.reconnect }
                var cursor = try MALAccountImportCursor.decode(manifest.cursor)
                guard let medium = cursor.nextMedium, let offset = cursor.offset(for: medium) else { throw ImportFailure.invalidInput("The source cursor is invalid.") }
                let fetched = try await malAccount.readPage(medium: medium, offset: offset, session: reader)
                try checkWorkflow(origin)
                guard malAccount.isCurrent(reader) else { throw CancellationError() }
                cursor.advance(medium, to: fetched.nextOffset)
                page = ImportSourcePage(items: LibraryImportBatch.prepareForReview(fetched.drafts).map { ImportSourceItem(draft: $0) },
                    nextCursor: try cursor.encode(), exhaustedMedia: ["anime": cursor.anime == nil, "manga": cursor.manga == nil])
            }
            try await freezeSourcePage(page, manifest: &manifest, origin: origin)
        }
        guard let outcome = manifest.outcome, manifest.selection.media.allSatisfy({ outcome.exhaustedMedia[$0] == true }) else {
            throw ImportFailure.invalidInput("The provider streams have not completed. Resume preparation before reviewing.")
        }
        manifest.phase = .reviewing
        try await saveWorkflow(manifest, origin: origin)
        return outcome
    }

    func startWorkflow(_ manifest: inout ImportManifest, origin: WorkflowOrigin) async throws {
        manifest.startAttempted = true
        try await saveWorkflow(manifest, origin: origin)
        do {
            let outcome: ImportOutcome = try await workflowRPC("start_library_import_v2",
                ImportStartInput(p_selection: manifest.selection, p_action_id: manifest.actionId), origin: origin)
            guard outcome.selection == manifest.selection else { throw ImportFailure.uncertainDelivery }
            manifest.jobId = outcome.jobId; manifest.outcome = outcome
            try await saveWorkflow(manifest, origin: origin)
        } catch let failure as ImportFailure {
            // Only a definitive rejected admission establishes that this action made no job.
            // Transport/decoding/5xx failure retains true and frozen input for start reconciliation.
            switch failure {
            case .denied, .activeJob, .invalidInput:
                manifest.startAttempted = false
                try await saveWorkflow(manifest, origin: origin)
            default: break
            }
            throw failure
        }
    }

    func fetchAniListPage(_ manifest: ImportManifest, origin: WorkflowOrigin) async throws -> ImportSourcePage {
        try checkWorkflow(origin)
        let types = manifest.selection.media.map { $0.uppercased() }
        var body: [String:Any] = ["mode":"import", "stream":true, "username":manifest.selection.sourceIdentity,
            "types":types, "statuses":manifest.selection.statuses, "maxItems":200, "perPage":50]
        if let cursor = manifest.cursor { body["cursor"] = cursor }
        let encoded = try JSONSerialization.data(withJSONObject: body)
        let client = self.client
        let response: ConciergeAniListImportResponse = try await accountSession.withCredentialLease(for: origin.account) {
            guard let client else { throw MissingSupabaseConfiguration() }
            return try await client.functions.invoke("concierge-import-anilist", options: FunctionInvokeOptions(method: .post, body: encoded))
        }
        try checkWorkflow(origin)
        guard response.success, let items = response.libraryItems, let exhausted = response.sourceExhausted,
              items.count <= 200, items.allSatisfy({ manifest.selection.media.contains($0.medium.lowercased()) }) else {
            if response.publicListOnly == true { throw ImportFailure.denied }
            throw ImportFailure.transient("The provider page was not confirmed. Resume retains the original action.")
        }
        let flags = try Self.aniListExhaustion(selection: manifest.selection, cursor: response.nextCursor,
            previousCursor: manifest.cursor, exhausted: exhausted)
        return ImportSourcePage(items: LibraryImportBatch.prepareForReview(items.map { $0.draft() }).map { ImportSourceItem(draft: $0) },
            nextCursor: response.nextCursor, exhaustedMedia: flags)
    }

    static func aniListExhaustion(selection: ImportSelection, cursor: String?, previousCursor: String?, exhausted: Bool) throws -> [String:Bool] {
        if exhausted {
            guard cursor == nil else { throw ImportFailure.invalidInput("A completed source returned another cursor.") }
            return Dictionary(uniqueKeysWithValues: selection.media.map { ($0, true) })
        }
        guard let cursor, cursor != previousCursor, cursor.utf8.count <= 4096,
              let data = Data(base64Encoded: cursor), let raw = try JSONSerialization.jsonObject(with: data) as? [String:Any],
              raw["username"] as? String == selection.sourceIdentity,
              raw["types"] as? [String] == selection.media.map({ $0.uppercased() }),
              raw["statuses"] as? [String] == selection.statuses,
              let index = raw["typeIndex"] as? Int, selection.media.indices.contains(index),
              let page = raw["page"] as? Int, (1...100_000).contains(page),
              let offset = raw["offset"] as? Int, (0..<50).contains(offset) else {
            throw ImportFailure.invalidInput("The provider returned an invalid or unchanged cursor.")
        }
        if let previousCursor, let oldData = Data(base64Encoded: previousCursor),
           let old = try JSONSerialization.jsonObject(with: oldData) as? [String:Any],
           let oldIndex = old["typeIndex"] as? Int, let oldPage = old["page"] as? Int, let oldOffset = old["offset"] as? Int {
            guard index > oldIndex || (index == oldIndex && (page > oldPage || (page == oldPage && offset > oldOffset))) else {
                throw ImportFailure.invalidInput("The provider cursor did not advance.")
            }
        }
        return Dictionary(uniqueKeysWithValues: selection.media.enumerated().map { ($0.element, $0.offset < index) })
    }
}
