import Foundation
import KuroLibrary

// MARK: - Import models
// Wire shapes of the import edge functions (`concierge-parse`, `concierge-apply`, `concierge-undo`,
// `concierge-import-anilist`) and the library export result, moved verbatim from the former
// `SupabaseService` nested types (field names are the JSON keys). Owner: `ImportsService`.
// Account-scoped content: `ConciergeExistingEntry` echoes the caller's list row and gates auto-apply;
// a parse response therefore belongs to the account that asked.

struct ConciergeCandidate: Decodable, Sendable, Hashable {
    let media_type: String
    let media_id: Int
    let variant_type: String
    let title_raw: String
    let score: Double
    let year: Int?
    let format: String?
    let cover_image_medium: String?
}

struct ConciergeParseItemParsed: Decodable, Sendable {
    let mediaTypeHint: String?
    let status: String?
    let progressEpisodes: Int?
    let progressChapters: Int?
    let progressVolumes: Int?
    let seasonNumber: Int?
    let episodeInSeason: Int?
    let caughtUp: Bool?
    let lastEpisode: Bool?
    let completed: Bool?
    let yearMention: Int?
    let rating: Double?
    let progressTotal: Int?
    let progressUnit: String?
}

struct ConciergeExistingEntry: Decodable, Sendable {
    let media_type: String
    let media_id: Int
    let status: String
    let progress_episodes: Int?
    let progress_chapters: Int?
    let progress_volumes: Int?
    let rating: Int?
    let updated_at: String
}

struct ConciergeAmbiguity: Decodable, Sendable {
    let kind: String             // "status_unclear", "unit_unclear", "intent_unclear"
    let options: [String]?       // e.g. ["COMPLETED", "CURRENT"] or ["episode", "season", "chapter", "volume"]
    let suggested_question: String?
    let title_context: String?   // title the ambiguity relates to
    let number_context: String?  // the ambiguous number (for unit_unclear)
}

struct ConciergeParseItem: Decodable, Sendable, Identifiable {
    let raw: String
    let normalized: String
    let parsed: ConciergeParseItemParsed
    let candidates: [ConciergeCandidate]
    let candidateError: String?
    let existing_entry: ConciergeExistingEntry?
    let ambiguity: ConciergeAmbiguity?

    var id: String { raw + "|" + normalized }
}

struct ConciergeParseResponse: Decodable, Sendable {
    let success: Bool
    let userId: String?
    let items: [ConciergeParseItem]
}

struct ConciergeApplyResponse: Decodable, Sendable {
    let success: Bool
    let sessionId: String?
    struct Applied: Decodable, Sendable {
        let mediaType: String
        let mediaId: Int
        let status: String
        let action: String?
    }
    struct Skipped: Decodable, Sendable {
        let mediaType: String
        let mediaId: Int
    }
    struct Conflict: Decodable, Sendable {
        let mediaType: String?
        let mediaId: Int?
        let error: String
    }
    struct ApplyError: Decodable, Sendable {
        let mediaType: String?
        let mediaId: Int?
        let error: String
    }
    let applied: [Applied]?
    let skipped: [Skipped]?
    let conflicts: [Conflict]?
    let errors: [ApplyError]?
    /// Wire v2 (`applied` / `partial` / `failed` / `none`). Absent on the deployed server.
    let status: String?
    /// Wire v2. Absent on the deployed server, which is undoable only when `success` and `sessionId` are set.
    let undoable: Bool?
    /// Wire v2: the same idempotency key returned the stored outcome and wrote nothing new.
    let replayed: Bool?

    /// How a surface should present this response. A partial v2 outcome (`success == false`,
    /// `undoable == true`) is not a total failure. A deployed response without `status` keeps the
    /// old meaning: `success` is a completed apply.
    var presentation: ConciergeApplyPresentation {
        let known = status.flatMap(ConciergeApplySessionStatus.init(rawValue:))
        let sessionStatus = known ?? (success ? .applied : .failed)
        let canUndo = undoable ?? (success && sessionId != nil)
        let adds = applied?.filter { $0.action == "add" }.count ?? 0
        let updates = applied?.filter { $0.action == "update" }.count ?? 0
        let accepted = applied?.count ?? 0
        let conflictCount = conflicts?.count ?? 0
        let errorCount = errors?.count ?? 0
        let rejected = conflictCount + errorCount
        let tone: ConciergeApplyPresentation.Tone
        switch sessionStatus {
        case .failed:
            tone = .failed
        case .none:
            // `none` is "nothing written". Rejections are a failed import, not a clean no-op.
            tone = rejected > 0 ? .failed : .empty
        case .partial:
            tone = accepted > 0 && canUndo ? .partial : .failed
        case .applied:
            if accepted > 0 {
                tone = .applied
            } else {
                tone = rejected > 0 ? .failed : .empty
            }
        }
        let undoSessionId = (tone == .applied || tone == .partial) && canUndo ? sessionId : nil
        return ConciergeApplyPresentation(
            tone: tone,
            addCount: adds,
            updateCount: updates,
            acceptedCount: accepted,
            conflictCount: conflictCount,
            errorCount: errorCount,
            firstError: errors?.first?.error ?? conflicts?.first?.error,
            undoSessionId: undoSessionId,
            replayed: replayed == true
        )
    }
}

enum ConciergeApplySessionStatus: String, Sendable {
    case applied
    case partial
    case failed
    case none
}

struct ConciergeApplyPresentation: Equatable, Sendable {
    enum Tone: Equatable, Sendable {
        case applied
        case partial
        case empty
        case failed
    }

    var tone: Tone
    var addCount: Int
    var updateCount: Int
    var acceptedCount: Int
    var conflictCount: Int
    var errorCount: Int
    var firstError: String?
    var undoSessionId: String?
    var replayed: Bool
}

/// Whether an Apply error is a definitive server answer or an unknown delivery.
/// A lost response keeps the original action identity so a retry can replay it.
enum ImportApplyDelivery: Equatable, Sendable {
    case terminal
    case uncertain

    static func of(_ error: Error) -> ImportApplyDelivery {
        if error is CancellationError { return .terminal }
        if error is URLError { return .uncertain }
        if let failure = error as? ConciergeRequestFailure {
            return failure.isRetryable ? .uncertain : .terminal
        }
        if error is ConciergeGuardrailsError { return .terminal }
        return .uncertain
    }
}

/// One in-flight Apply. A retry of the same anchor and form stamp resends the frozen payload and key.
/// A new anchor, an edited form, a terminal result, or abandonment starts a new identity, even when
/// the rebuilt payload would be identical.
@MainActor
final class ImportApplyAttempt {
    private struct Frozen {
        let key: String
        let items: [[String: Any]]
        let anchor: String
        let stamp: String
    }

    private var frozen: Frozen?

    var frozenKey: String? { frozen?.key }

    /// The stored action when this is a retry of the same anchor and stamp. Does not rebuild.
    func frozenReplay(anchor: String, stamp: String) -> (key: String, items: [[String: Any]])? {
        guard let frozen, frozen.anchor == anchor, frozen.stamp == stamp else { return nil }
        return (frozen.key, frozen.items)
    }

    func begin(anchor: String, stamp: String, build: () -> [[String: Any]]) -> (key: String, items: [[String: Any]]) {
        if let frozen, frozen.anchor == anchor, frozen.stamp == stamp {
            return (frozen.key, frozen.items)
        }
        let items = build()
        let key = UUID().uuidString.lowercased()
        frozen = Frozen(key: key, items: items, anchor: anchor, stamp: stamp)
        return (key, items)
    }

    /// Keeps the frozen action when delivery is uncertain. Clears it on a terminal result.
    func observe(_ error: Error) {
        if ImportApplyDelivery.of(error) == .terminal {
            frozen = nil
        }
    }

    func complete() {
        frozen = nil
    }

    func abandon() {
        frozen = nil
    }
}

enum ImportApplyIdentity {
    static func isValid(_ key: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        return (1...128).contains(key.count) && key.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    static func signature(of items: [[String: Any]]) -> String {
        guard JSONSerialization.isValidJSONObject(items),
              let data = try? JSONSerialization.data(withJSONObject: items, options: [.sortedKeys])
        else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// User-controlled import form. Library knowledge is not part of the stamp, so a refresh does not
/// rebuild a lost request. The chosen candidate's medium and id are, so editing the title does.
enum ImportSelectionStamp {
    struct Choice: Equatable, Sendable {
        var lineId: String
        var mediaType: String
        var mediaId: Int
        var action: String?
        var excluded: Bool
    }

    static func make(choices: [Choice]) -> String {
        choices
            .sorted { $0.lineId < $1.lineId }
            .map { choice in
                let type = choice.mediaType.uppercased()
                let action = choice.action ?? ""
                return "\(choice.lineId)=\(type):\(choice.mediaId)|\(action)|\(choice.excluded)"
            }
            .joined(separator: ";")
    }
}

/// Profile import. A retry of the unresolved action replays the frozen payload before any fresh
/// reconciliation. A new import gesture does not.
enum ProfileImportIntent: Equatable, Sendable {
    case retryUnresolved
    case newImport
}

enum ProfileImportRecovery {
    static let anchor = "profile-unresolved"
    static let stamp = "profile"

    @MainActor
    static func replayIfRetrying(
        intent: ProfileImportIntent,
        attempt: ImportApplyAttempt
    ) -> (key: String, items: [[String: Any]])? {
        guard intent == .retryUnresolved else { return nil }
        return attempt.frozenReplay(anchor: anchor, stamp: stamp)
    }
}

/// Profile Undo may publish only into the card that started it.
@MainActor
final class ProfileImportCardLifetime {
    private(set) var generation = 0

    func invalidate() {
        generation += 1
    }
}

enum ProfileUndoPublication {
    static func mayApply(
        startedGeneration: Int,
        generation: Int,
        visibleSession: String?,
        startedSession: String
    ) -> Bool {
        generation == startedGeneration && visibleSession == startedSession
    }
}

/// Titles in a partial confirmation. Anime 7 and Manga 7 are different lines.
enum ImportApplyConfirmation {
    struct Line: Equatable, Sendable {
        var mediaType: String
        var mediaId: Int
        var title: String
    }

    static func text(summary: String, applied: [Line], rejected: [Line]) -> String {
        var parts = [summary]
        if !applied.isEmpty {
            parts.append(applied.map { "· \($0.title)" }.joined(separator: "\n"))
        }
        if !rejected.isEmpty {
            parts.append("Needs review:")
            parts.append(rejected.map { "· \($0.title)" }.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n")
    }
}

struct ConciergeUndoResponse: Decodable, Sendable {
    let success: Bool
    let sessionId: String?
    struct Reverted: Decodable, Sendable {
        let mediaType: String
        let mediaId: Int
        let undoType: String?
        let fields: [String]?
    }
    struct Skipped: Decodable, Sendable {
        let mediaType: String?
        let mediaId: Int?
        let reason: String?
        let fields: [String]?
    }
    struct Warning: Decodable, Sendable {
        let mediaType: String?
        let mediaId: Int?
        let id: String?
        let reason: String?
        let fields: [String]?
    }
    struct UndoError: Decodable, Sendable {
        let id: String?
        let error: String
    }
    let reverted: [Reverted]?
    let skipped: [Skipped]?
    let warnings: [Warning]?
    let errors: [UndoError]?
    /// Wire v2 (`undone` on 200). Absent on the deployed server.
    let status: String?

    /// Later edits and deletions the Undo left in place.
    var keptCount: Int { skipped?.count ?? 0 }
}

// MARK: - Library export

struct ConciergeLibraryExportResult: Sendable {
    let text: String
    let exportedItemCount: Int
    let truncated: Bool
}

// MARK: - AniList import

struct ConciergeAniListPreviewItem: Decodable, Sendable, Identifiable {
    let mediaId: Int
    let type: String
    let line: String?
    let title: String?
    let status: String
    let progress: Int?
    let year: Int?
    let updatedAt: Int?

    var id: String { "\(type)-\(mediaId)" }

    var titleDisplay: String {
        title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? line?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "AniList \(type) \(mediaId)"
    }
}

struct ConciergeAniListPreviewResponse: Decodable, Sendable {
    let success: Bool
    let source: String?
    let username: String?
    let itemCount: Int?
    let truncated: Bool?
    let countsByType: [String: Int]?
    let countsByStatus: [String: Int]?
    let sampleItems: [ConciergeAniListPreviewItem]?
    let text: String?
    let publicListOnly: Bool?
    let retry_after_s: Int?
    let error: String?
}

struct ConciergeAniListLibraryItem: Decodable, Sendable {
    let medium: String
    let externalId: String
    let title: String?
    let status: String
    let progress: Int?
    let volumesProgress: Int?
    let scoreRaw: String?
    let scoreScale: String?
    let notes: String?
    let repeatCount: Int?
    let startedRaw: String?
    let finishedRaw: String?
    let isPrivate: Bool?
    let customLists: [String]?
    let hiddenFromStatusLists: Bool?
    let sourceListOptions: String?
    let normalizedRating: Int?

    enum CodingKeys: String, CodingKey {
        case medium, status, notes, title
        case externalId = "external_id"
        case progress
        case volumesProgress = "volumes_progress"
        case scoreRaw = "score_raw"
        case scoreScale = "score_scale"
        case repeatCount = "repeat_count"
        case startedRaw = "started_raw"
        case finishedRaw = "finished_raw"
        case isPrivate = "private"
        case customLists = "custom_lists"
        case hiddenFromStatusLists = "hidden_from_status_lists"
        case sourceListOptions = "source_list_options"
        case normalizedRating = "normalized_rating"
    }

    func draft() -> LibraryImportDraft {
        var unavailable: [String] = []
        if progress == nil { unavailable.append("progress") }
        if repeatCount == nil { unavailable.append("repeat_count") }
        if isPrivate == nil { unavailable.append("private") }
        if customLists == nil { unavailable.append("custom_lists") }
        if hiddenFromStatusLists == nil { unavailable.append("hidden_from_status_lists") }
        return LibraryImportDraft(
            medium: medium,
            externalId: externalId,
            status: status,
            progress: progress ?? 0,
            volumesProgress: volumesProgress,
            scoreRaw: scoreRaw,
            scoreScale: scoreScale ?? "ANILIST_RAW",
            notes: notes,
            repeatCount: repeatCount ?? 0,
            startedRaw: startedRaw,
            finishedRaw: finishedRaw,
            isPrivate: isPrivate ?? false,
            customLists: customLists ?? [],
            hiddenFromStatusLists: hiddenFromStatusLists ?? false,
            sourceListOptions: LibraryImportDraft.options(sourceListOptions, unavailable: unavailable),
            normalizedRating: normalizedRating,
            sourceTitle: title
        )
    }
}

struct ConciergeAniListImportResponse: Decodable, Sendable {
    let success: Bool
    let source: String?
    let username: String?
    let itemCount: Int?
    let truncated: Bool?
    let text: String?
    let publicListOnly: Bool?
    let retry_after_s: Int?
    let error: String?
    var types: [String]? = nil
    var statuses: [String]? = nil
    var nextCursor: String? = nil
    var sourceExhausted: Bool? = nil
    let libraryItems: [ConciergeAniListLibraryItem]?

    enum CodingKeys: String, CodingKey {
        case success, source, username, itemCount, truncated, text, publicListOnly, retry_after_s, error
        case libraryItems = "libraryItems"
        case types,statuses,nextCursor,sourceExhausted
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
