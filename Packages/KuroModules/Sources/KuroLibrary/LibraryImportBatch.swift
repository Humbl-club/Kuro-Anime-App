import CryptoKit
import Foundation

/// Provider identities occupy a namespace distinct from Kuro's internal catalog IDs.
public struct LibraryProviderReference: Hashable, Codable, Sendable {
    public enum Provider: String, Codable, Sendable { case anilist, myanimelist }
    public enum Medium: String, Codable, Sendable { case anime, manga }
    public let provider: Provider
    public let medium: Medium
    public let externalId: String

    public init(provider: Provider, medium: Medium, externalId: String) {
        self.provider = provider
        self.medium = medium
        self.externalId = externalId
    }
}

/// Native OAuth correlation and PKCE values; provider registration chooses its supported method.
public struct LibraryOAuthAttempt: Equatable, Sendable {
    public enum ChallengeMethod: String, Sendable { case plain, s256 = "S256" }
    public let accountId: String
    public let generation: Int
    public let state: String
    public let verifier: String
    public let method: ChallengeMethod
    public let createdAt: Date

    public init(accountId: String, generation: Int, state: String, verifier: String,
                method: ChallengeMethod, createdAt: Date = Date()) {
        self.accountId = accountId.lowercased(); self.generation = generation
        self.state = state; self.verifier = verifier; self.method = method; self.createdAt = createdAt
    }

    public var challenge: String {
        if method == .plain { return verifier }
        return Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public func accepts(state: String?, accountId: String, generation: Int, now: Date = Date()) -> Bool {
        guard let state, !state.isEmpty, state == self.state,
              accountId.lowercased() == self.accountId, generation == self.generation else { return false }
        let age = now.timeIntervalSince(createdAt)
        return age >= 0 && age <= 600
    }
}

/// One structured import row. Notes/privacy stay owner-only; they never become club comments.
/// A score of 0 stays unset. Duplicate appearances union their shelf memberships.
public struct LibraryImportDraft: Codable, Equatable, Sendable {
    public var medium: String
    public var externalId: String
    public var sourceTitle: String?
    public var status: String
    public var progress: Int
    public var volumesProgress: Int?
    public var scoreRaw: String?
    public var scoreScale: String
    public var notes: String?
    public var repeatCount: Int
    public var startedRaw: String?
    public var finishedRaw: String?
    public var isPrivate: Bool
    public var customLists: [String]
    public var hiddenFromStatusLists: Bool
    public var sourceListOptions: String?
    public var normalizedRating: Int?

    public var unavailableFields: Set<String> {
        guard let sourceListOptions, let data = sourceListOptions.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fields = object["unavailable_fields"] as? [String] else { return [] }
        return Set(fields)
    }

    /// Preserve provider options while declaring fields the source did not supply.
    public static func options(_ existing: String?, unavailable fields: [String]) -> String? {
        guard !fields.isEmpty else { return existing }
        var object: [String: Any] = [:]
        if let existing, let data = existing.data(using: .utf8) {
            object = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? ["provider_options_raw": existing]
        }
        let prior = object["unavailable_fields"] as? [String] ?? []
        object["unavailable_fields"] = Array(Set(prior + fields)).sorted()
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return existing }
        return String(data: data, encoding: .utf8)
    }

    public init(
        medium: String,
        externalId: String,
        status: String,
        progress: Int,
        volumesProgress: Int? = nil,
        scoreRaw: String? = nil,
        scoreScale: String = "POINT_10",
        notes: String? = nil,
        repeatCount: Int = 0,
        startedRaw: String? = nil,
        finishedRaw: String? = nil,
        isPrivate: Bool = false,
        customLists: [String] = [],
        hiddenFromStatusLists: Bool = false,
        sourceListOptions: String? = nil,
        normalizedRating: Int? = nil,
        sourceTitle: String? = nil
    ) {
        self.medium = medium
        self.externalId = externalId
        self.status = status
        self.progress = progress
        self.volumesProgress = volumesProgress
        self.scoreRaw = scoreRaw
        self.scoreScale = scoreScale
        self.notes = notes
        self.repeatCount = repeatCount
        self.startedRaw = startedRaw
        self.finishedRaw = finishedRaw
        self.isPrivate = isPrivate
        self.customLists = customLists
        self.hiddenFromStatusLists = hiddenFromStatusLists
        self.sourceListOptions = sourceListOptions
        self.normalizedRating = normalizedRating
        self.sourceTitle = sourceTitle
    }
}

public struct LibraryImportCounts: Codable, Equatable, Sendable {
    public var added: Int
    public var updated: Int
    public var conflict: Int
    public var unmatched: Int

    public init(added: Int = 0, updated: Int = 0, conflict: Int = 0, unmatched: Int = 0) {
        self.added = added
        self.updated = updated
        self.conflict = conflict
        self.unmatched = unmatched
    }
    enum CodingKeys: String, CodingKey { case added, updated, conflict, unmatched }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        added = try values.decodeIfPresent(Int.self, forKey: .added) ?? 0
        updated = try values.decodeIfPresent(Int.self, forKey: .updated) ?? 0
        conflict = try values.decodeIfPresent(Int.self, forKey: .conflict) ?? 0
        unmatched = try values.decodeIfPresent(Int.self, forKey: .unmatched) ?? 0
    }

}

public enum LibraryImportBatch {
    public static let chunkSize = 100

    /// Last provider copy wins, shelf membership is unioned, and score 0 remains unset.
    public static func prepare(_ drafts: [LibraryImportDraft]) -> [LibraryImportDraft] {
        var order: [String] = []
        var byKey: [String: LibraryImportDraft] = [:]
        for draft in drafts {
            var copy = draft
            if copy.scoreRaw == "0" || copy.scoreRaw == "0.0" || copy.scoreRaw == "0.00" {
                copy.scoreRaw = nil
            }
            let key = "\(copy.medium)|\(copy.externalId)"
            var seen: Set<String> = []
            copy.customLists = (copy.customLists + (byKey[key]?.customLists ?? [])).filter { seen.insert($0).inserted }
            if byKey[key] == nil { order.append(key) }
            byKey[key] = copy
        }
        return order.compactMap { byKey[$0] }
    }

    /// Review staging collapses equivalent rows but retains contradictory copies for source_changed.
    /// The SQL owner produces one canonical disposition; legacy `prepare` remains compatible.
    public static func prepareForReview(_ drafts: [LibraryImportDraft]) -> [LibraryImportDraft] {
        var result: [LibraryImportDraft] = []
        var indexes: [String: [Int]] = [:]
        for draft in drafts {
            var copy = draft
            if let raw = copy.scoreRaw, let score = Decimal(string: raw), score == 0 {
                copy.scoreRaw = nil; copy.normalizedRating = nil
            }
            copy.customLists = Array(Set(copy.customLists.filter { !$0.isEmpty })).sorted()
            let key = "\(copy.medium)|\(copy.externalId)"
            if let index = indexes[key]?.first(where: { index in
                var prior = result[index]; prior.customLists = []; prior.sourceTitle = nil
                var next = copy; next.customLists = []; next.sourceTitle = nil
                return prior == next
            }) {
                result[index].customLists = Array(Set(result[index].customLists + copy.customLists)).sorted()
                if result[index].sourceTitle == nil { result[index].sourceTitle = copy.sourceTitle }
            } else {
                indexes[key, default: []].append(result.count)
                result.append(copy)
            }
        }
        return result
    }

    public static func chunks(_ drafts: [LibraryImportDraft]) -> [[LibraryImportDraft]] {
        let prepared = prepare(drafts)
        if prepared.isEmpty { return [] }
        var result: [[LibraryImportDraft]] = []
        var index = 0
        while index < prepared.count {
            let end = min(index + chunkSize, prepared.count)
            result.append(Array(prepared[index..<end]))
            index = end
        }
        return result
    }

    public static func payloadHash(_ drafts: [LibraryImportDraft], provider: String = "", sourceKind: String = "", mediumFilter: String = "both") -> String {
        struct Payload: Encodable {
            let version: Int
            let provider: String
            let sourceKind: String
            let mediumFilter: String
            let items: [LibraryImportDraft]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let identityItems = prepare(drafts).map { draft in
            var value = draft; value.sourceTitle = nil
            return value
        }
        let payload = Payload(version: 2, provider: provider, sourceKind: sourceKind, mediumFilter: mediumFilter, items: identityItems)
        // All fields are finite scalar/list values; encoding cannot fail for this contract.
        let data = try! encoder.encode(payload)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// One protected, atomic checkpoint per import action. A fetched page is saved BEFORE any
/// chunk is sent; retry never refetches different provider bodies for already-committed items.
public actor LibraryImportPageJournal {
    public enum Failure: Error, Equatable {
        case invalidAccount, invalidCheckpoint, unattributedCheckpoint, cleanupLimit, accountDeleted, recordLimit, accountBudget
    }
    static let maxCheckpointBytes = 8 * 1024 * 1024
    public struct Page: Codable, Equatable, Sendable {
        public let drafts: [LibraryImportDraft]
        public let nextCursor: String?
        public let exhausted: Bool
        public init(drafts: [LibraryImportDraft], nextCursor: String?, exhausted: Bool) {
            self.drafts=drafts; self.nextCursor=nextCursor; self.exhausted=exhausted
        }
    }
    public struct Checkpoint: Codable, Equatable, Sendable {
        public let cursor: String?
        public let page: Page?
        public let actionId: String?
        public let accountId: String?
        public init(cursor: String? = nil, page: Page? = nil, actionId: String? = nil, accountId: String? = nil) {
            self.cursor=cursor; self.page=page; self.actionId=actionId; self.accountId=accountId
        }
    }
    let directory: URL
    var deletedAccounts: Set<String> = []
    public init(directory: URL) throws {
        self.directory=directory
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let root = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard root.isDirectory == true, root.isSymbolicLink != true else { throw Failure.invalidCheckpoint }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:directory.path)
        #endif
        var excluded=directory
        var values=URLResourceValues(); values.isExcludedFromBackup=true
        try excluded.setResourceValues(values)
    }
    private func url(_ key: String) -> URL {
        let digest=SHA256.hash(data:Data(key.utf8)).map { String(format:"%02x",$0) }.joined()
        return directory.appendingPathComponent(digest+".json")
    }
    public func read(key: String) throws -> Checkpoint {
        let file=url(key)
        guard FileManager.default.fileExists(atPath:file.path) else { return Checkpoint() }
        let data = try boundedData(file)
        let checkpoint = try JSONDecoder().decode(Checkpoint.self, from: data)
        if let account = Self.account(from: key) {
            guard checkpoint.accountId == nil || checkpoint.accountId?.lowercased() == account else {
                throw Failure.invalidCheckpoint
            }
            if checkpoint.accountId == nil {
                // A known key can safely attribute a legacy file when that account resumes it.
                try write(checkpoint, key: key)
                return Checkpoint(cursor: checkpoint.cursor, page: checkpoint.page,
                    actionId: checkpoint.actionId, accountId: account)
            }
        }
        return checkpoint
    }
    public func write(_ checkpoint: Checkpoint, key: String) throws {
        let file=url(key)
        let account = Self.account(from: key)
        if let account { try requireWritableAccount(account) }
        guard checkpoint.accountId == nil || account == checkpoint.accountId?.lowercased() else {
            throw Failure.invalidCheckpoint
        }
        let attributed = Checkpoint(cursor: checkpoint.cursor, page: checkpoint.page,
            actionId: checkpoint.actionId, accountId: account)
        let data = try JSONEncoder().encode(attributed)
        guard data.count <= Self.maxCheckpointBytes else { throw Failure.recordLimit }
        if let account { try enforceActiveBudget(accountId: account, incoming: data.count, replacing: file) }
        #if os(iOS)
        try data.write(to:file,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to:file,options:.atomic)
        #endif
    }
    /// Resolving and saving an identity is one actor operation, including concurrent starts.
    public func beginAction(key: String, legacyActionId: String? = nil) throws -> String {
        let existing = try read(key: key)
        if let actionId = existing.actionId { return actionId }
        let actionId = legacyActionId ?? UUID().uuidString.lowercased()
        try write(.init(actionId: actionId), key: key)
        return actionId
    }
    public func completeAction(key: String, actionId: String) throws {
        guard try read(key: key).actionId == actionId else { return }
        try remove(key: key)
    }
    public func remove(key: String) throws {
        let file=url(key)
        if FileManager.default.fileExists(atPath:file.path) { try FileManager.default.removeItem(at:file) }
    }

    /// Exact attributed deletion progresses in bounded passes; unknown legacy files are preserved.
    public func removeDeletedAccountData(accountId: String) throws {
        try removeWorkflowAccountData(accountId: accountId)
    }

    func boundedData(_ file: URL) throws -> Data {
        let values = try file.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey, .isRegularFileKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true, let size = values.fileSize,
              size >= 0, size <= Self.maxCheckpointBytes else { throw Failure.invalidCheckpoint }
        return try Data(contentsOf: file)
    }

    private static func account(from key: String) -> String? {
        for prefix in ["kuro.import.action.", "kuro.import.stream."] where key.hasPrefix(prefix) {
            let remainder = key.dropFirst(prefix.count)
            guard let end = remainder.firstIndex(of: ".") else { return nil }
            return UUID(uuidString: String(remainder[..<end]))?.uuidString.lowercased()
        }
        return nil
    }
}
