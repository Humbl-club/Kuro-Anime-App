import Foundation
import KuroCore
import KuroLibrary

extension ImportsService {
    /// A single replay-safe job contains two independently advancing source streams. A committed
    /// Anime terminal page is retained while Manga fails; neither denial nor a failed page is empty.
    func importCompleteMALAccount() async throws -> LibraryImportCounts {
        guard let context = accountSession.current, streamToken == nil else { throw CancellationError() }
        guard let importJournal else { throw MALAccountList.Failure.invalidPage }
        let token = UUID(); streamToken = token
        defer { if streamToken == token { streamToken = nil } }
        let reader = try await malAccount.beginReader()
        guard accountSession.isCurrent(context), malAccount.isCurrent(reader) else { throw CancellationError() }
        let fingerprint = LibraryImportBatch.payloadHash([], provider: "myanimelist",
            sourceKind: "mal.account.v1|\(reader.providerUserId)|both")
        let checkpoint = "kuro.import.stream.\(context.userId.lowercased()).\(fingerprint)"
        var saved = try await importJournal.read(key: checkpoint)
        while true {
            guard accountSession.isCurrent(context), malAccount.isCurrent(reader) else { throw CancellationError() }
            let page: LibraryImportPageJournal.Page
            if let persisted = saved.page { page = persisted }
            else {
                var cursor = try MALAccountImportCursor.decode(saved.cursor)
                guard let medium = cursor.nextMedium, let offset = cursor.offset(for: medium) else { throw MALAccountList.Failure.invalidPage }
                let fetched = try await malAccount.readPage(medium: medium, offset: offset, session: reader)
                guard accountSession.isCurrent(context), malAccount.isCurrent(reader) else { throw CancellationError() }
                cursor.advance(medium, to: fetched.nextOffset)
                page = LibraryImportPageJournal.Page(drafts: fetched.drafts,
                    nextCursor: try cursor.encode(), exhausted: cursor.nextMedium == nil)
                saved = LibraryImportPageJournal.Checkpoint(cursor: saved.cursor, page: page)
                try await importJournal.write(saved, key: checkpoint)
            }
            let counts = try await applyStructuredLibraryImport(provider: "myanimelist", sourceKind: "account",
                mediumFilter: "both", drafts: page.drafts, exhausted: page.exhausted, streamIdentity: fingerprint)
            guard accountSession.isCurrent(context), malAccount.isCurrent(reader) else { throw CancellationError() }
            if page.exhausted {
                try await importJournal.remove(key: checkpoint)
                try await importJournal.remove(key: "kuro.import.action.\(context.userId.lowercased()).\(fingerprint)")
                return counts
            }
            saved = LibraryImportPageJournal.Checkpoint(cursor: page.nextCursor)
            try await importJournal.write(saved, key: checkpoint)
        }
    }
}
