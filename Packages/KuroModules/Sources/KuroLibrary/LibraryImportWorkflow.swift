import Foundation

/// The structured import wire contract. SDK calls remain in the app's Imports owner.
public struct ImportSelection: Codable, Equatable, Sendable {
    public enum SourceKind: String, Codable, Sendable { case account, export }
    public var provider: LibraryProviderReference.Provider
    public var sourceKind: SourceKind
    public var sourceIdentity: String
    public var media: [String]
    public var statuses: [String]
    public init(provider: LibraryProviderReference.Provider, sourceKind: SourceKind,
                sourceIdentity: String, media: [String], statuses: [String] = []) {
        self.provider = provider; self.sourceKind = sourceKind; self.sourceIdentity = sourceIdentity
        self.media = media.map { $0.lowercased() }.sorted(); self.statuses = statuses.sorted()
    }
    public var mediumFilter: String { media.count == 2 ? "both" : media.first ?? "both" }
    enum CodingKeys: String, CodingKey {
        case provider, media, statuses
        case sourceKind = "source_kind", sourceIdentity = "source_identity"
    }
}

/// Omitted values preserve Kuro. An approved group is applied as one semantic value.
public enum ImportField: String, Codable, CaseIterable, Sendable {
    case status, progress, score, notes, privacy
    case volumes = "volumes_progress", repeats = "repeat_count", dates
    case memberships = "custom_lists", sourceOptions = "source_options"
}

public struct ImportValues: Codable, Equatable, Sendable {
    public var status: String?
    public var progress: Int?
    public var progressLabel: String?
    public var unitId: String?
    public var volumesProgress: Int?
    public var scoreRaw: String?
    public var scoreScale: String?
    public var normalizedRating: Int?
    public var notes: String?
    public var repeatCount: Int?
    public var startedRaw: String?
    public var finishedRaw: String?
    public var isPrivate: Bool?
    public var customLists: [String]?
    public var hiddenFromStatusLists: Bool?
    public var sourceListOptions: String?
    public var unavailableFields: [String]
    public init(draft: LibraryImportDraft) {
        status = draft.status
        let absent = draft.unavailableFields
        progress = absent.contains("progress") ? nil : draft.progress
        progressLabel = nil; unitId = nil; volumesProgress = draft.volumesProgress
        scoreRaw = draft.scoreRaw; scoreScale = draft.scoreScale; normalizedRating = draft.normalizedRating
        notes = draft.notes; repeatCount = absent.contains("repeat_count") ? nil : draft.repeatCount
        startedRaw = draft.startedRaw; finishedRaw = draft.finishedRaw
        isPrivate = absent.contains("private") ? nil : draft.isPrivate
        customLists = absent.contains("custom_lists") ? nil : draft.customLists
        hiddenFromStatusLists = absent.contains("hidden_from_status_lists") ? nil : draft.hiddenFromStatusLists
        sourceListOptions = draft.sourceListOptions; unavailableFields = absent.sorted()
    }
    enum CodingKeys: String, CodingKey {
        case status, progress, notes
        case progressLabel = "progress_label", unitId = "unit_id", volumesProgress = "volumes_progress"
        case scoreRaw = "score_raw", scoreScale = "score_scale", normalizedRating = "normalized_rating"
        case repeatCount = "repeat_count", startedRaw = "started_raw", finishedRaw = "finished_raw"
        case isPrivate = "private", customLists = "custom_lists", hiddenFromStatusLists = "hidden_from_status_lists"
        case sourceListOptions = "source_list_options", unavailableFields = "unavailable_fields"
    }
}

public struct ImportSourceItem: Codable, Equatable, Sendable {
    public var medium: String
    public var externalId: String
    public var title: String?
    public var values: ImportValues
    public var resolvedMediaId: Int?
    public init(draft: LibraryImportDraft, title: String? = nil) {
        medium = draft.medium; externalId = draft.externalId; self.title = title ?? draft.sourceTitle
        values = ImportValues(draft: draft)
    }
    public init(medium: String, externalId: String, title: String?, values: ImportValues, resolvedMediaId: Int? = nil) {
        self.medium = medium; self.externalId = externalId; self.title = title
        self.values = values; self.resolvedMediaId = resolvedMediaId
    }
    enum CodingKeys: String, CodingKey {
        case medium, title, values
        case externalId = "external_id", resolvedMediaId = "resolved_media_id"
    }
}

public enum ImportDisposition: String, Codable, Sendable {
    case new, existing, changes, pending, added, updated, unchanged, conflict, unmatched, invalid
    case sourceChanged = "source_changed"
}

public struct ImportReviewItem: Codable, Equatable, Identifiable, Sendable {
    public var medium: String
    public var externalId: String
    public var mediaId: Int?
    public var title: String
    public var incoming: ImportValues
    public var current: ImportValues?
    public var expectedRevision: Int64?
    public var expectedLifecycle: String?
    public var disposition: ImportDisposition
    public var detail: String?
    public var changedFields: [ImportField]
    public var undoDisposition: String?
    public var id: String { medium + "|" + externalId }
    enum CodingKeys: String, CodingKey {
        case medium, title, incoming, current, disposition, detail
        case externalId = "external_id", mediaId = "media_id", expectedRevision = "expected_revision"
        case expectedLifecycle = "expected_lifecycle", changedFields = "changed_fields", undoDisposition = "undo_disposition"
    }
}

public struct ImportDecision: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable { case add, keep, update; case deferReview = "defer" }
    public var medium: String
    public var externalId: String
    public var action: Action
    public var fields: [ImportField]
    public var expectedRevision: Int64?
    public var expectedLifecycle: String?
    public var resolvedMediaId: Int?
    public init(item: ImportReviewItem, action: Action? = nil, fields: [ImportField] = [], resolvedMediaId: Int? = nil) {
        medium = item.medium; externalId = item.externalId
        self.action = action ?? (item.disposition == .new ? .add :
            ([.existing, .changes].contains(item.disposition) ? .keep : .deferReview))
        self.fields = fields; expectedRevision = item.expectedRevision
        expectedLifecycle = item.expectedLifecycle; self.resolvedMediaId = resolvedMediaId ?? item.mediaId
    }
    enum CodingKeys: String, CodingKey {
        case medium, action, fields
        case externalId = "external_id", expectedRevision = "expected_revision"
        case expectedLifecycle = "expected_lifecycle", resolvedMediaId = "resolved_media_id"
    }
}

public struct ImportCounts: Codable, Equatable, Sendable {
    public var added: Int = 0
    public var updated: Int = 0
    public var unchanged: Int = 0
    public var conflict: Int = 0
    public var unmatched: Int = 0
    public var invalid: Int = 0
    public var pending: Int = 0
    public init() {}
    public var applied: Int { added + updated }
    public var needsReview: Int { conflict + unmatched + invalid }
    enum CodingKeys: String, CodingKey { case added, updated, unchanged, conflict, unmatched, invalid, pending }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        added = try c.decodeIfPresent(Int.self, forKey: .added) ?? 0
        updated = try c.decodeIfPresent(Int.self, forKey: .updated) ?? 0
        unchanged = try c.decodeIfPresent(Int.self, forKey: .unchanged) ?? 0
        conflict = try c.decodeIfPresent(Int.self, forKey: .conflict) ?? 0
        unmatched = try c.decodeIfPresent(Int.self, forKey: .unmatched) ?? 0
        invalid = try c.decodeIfPresent(Int.self, forKey: .invalid) ?? 0
        pending = try c.decodeIfPresent(Int.self, forKey: .pending) ?? 0
    }
}

public enum ImportPhase: String, Codable, Sendable {
    case preparing, reviewing, applying, finalizing, ready, cancelled, failed, undoing, undone
}

public struct ImportOutcome: Codable, Equatable, Identifiable, Sendable {
    public var jobId: String
    public var selection: ImportSelection
    public var phase: ImportPhase
    public var counts: ImportCounts
    public var exhaustedMedia: [String: Bool]
    public var homeRevisions: [String: Int64]
    public var projectionReady: Bool
    public var undoAvailable: Bool
    public var undoActionId: String?
    public var historyAvailable: Bool
    public var id: String { jobId }
    public var isTerminal: Bool { [.ready, .cancelled, .failed, .undone].contains(phase) }
    public var allRejected: Bool { counts.applied == 0 && counts.unchanged == 0 && counts.needsReview > 0 }
    enum CodingKeys: String, CodingKey {
        case selection, phase, counts
        case jobId = "job_id", exhaustedMedia = "exhausted_media", homeRevisions = "home_revisions"
        case projectionReady = "projection_ready", undoAvailable = "undo_available"
        case undoActionId = "undo_action_id", historyAvailable = "history_available"
    }
}

public struct ImportItemsPage: Codable, Sendable {
    public var items: [ImportReviewItem]
    public var nextCursor: String?
    enum CodingKeys: String, CodingKey { case items; case nextCursor = "next_cursor" }
}

public struct ImportJobsPage: Codable, Sendable {
    public var jobs: [ImportOutcome]
    public var nextCursor: String?
    enum CodingKeys: String, CodingKey { case jobs; case nextCursor = "next_cursor" }
}

public struct ImportUndoOutcome: Codable, Sendable {
    public var job: ImportOutcome
    public var reverted: Int
    public var skipped: Int
    public var nextCursor: String?
    enum CodingKeys: String, CodingKey { case job, reverted, skipped; case nextCursor = "next_cursor" }
}

public enum ImportFailure: Error, Equatable, Sendable, LocalizedError {
    case transient(String), uncertainDelivery, reconnect, denied, invalidInput(String), limit(String), activeJob, pendingTracking
    public var errorDescription: String? {
        switch self {
        case .transient(let text), .invalidInput(let text), .limit(let text): return text
        case .uncertainDelivery: return "The response was lost. Resume to check saved changes."
        case .reconnect: return "Reconnect your provider account to continue."
        case .denied: return "The provider did not allow this list to be read. Nothing missing will be removed."
        case .activeJob: return "An import is already active. Resume it or stop remaining work first."
        case .pendingTracking: return "Sync your pending changes before applying or undoing this import."
        }
    }
}

/// One atomically replaced account-owned record ties source pages, decisions and completion together.
public struct ImportManifest: Codable, Equatable, Identifiable, Sendable {
    public var accountId: String
    public var actionId: String
    public var jobId: String?
    public var startAttempted: Bool?
    public var selection: ImportSelection
    public var phase: ImportPhase
    public var cursor: String?
    public var nextPage: Int
    public var preparedPages: Int
    public var sourceExhausted: Bool
    public var decisions: [ImportDecision]?
    public var appliedDecisionCount: Int
    public var undoActionId: String?
    public var undoCursor: String?
    public var undoReverted: Int?
    public var undoSkipped: Int?
    public var outcome: ImportOutcome?
    public var id: String { actionId }
    public init(accountId: String, selection: ImportSelection, actionId: String = UUID().uuidString.lowercased()) {
        self.accountId = accountId.lowercased(); self.actionId = actionId
        self.selection = selection; phase = .preparing; nextPage = 0; preparedPages = 0
        sourceExhausted = false; appliedDecisionCount = 0
    }
}

public struct ImportSourcePage: Codable, Equatable, Sendable {
    public var items: [ImportSourceItem]
    public var nextCursor: String?
    public var exhaustedMedia: [String: Bool]
    public init(items: [ImportSourceItem], nextCursor: String?, exhaustedMedia: [String: Bool]) {
        self.items = items; self.nextCursor = nextCursor; self.exhaustedMedia = exhaustedMedia
    }
}
