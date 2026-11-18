import Foundation
import KuroCore

// MARK: - Tracking vocabulary (moved verbatim from the app's SupabaseModels.swift; raw values are stable)

public enum Verdict: String, Codable, CaseIterable, Sendable {
    case masterpiece = "MASTERPIECE"
    case okay = "OKAY"
    case bad = "BAD"

    public var displayName: String {
        switch self {
        case .masterpiece: return "Masterpiece"
        case .okay: return "Okay"
        case .bad: return "Bad"
        }
    }

    public var displayNameDE: String {
        switch self {
        case .masterpiece: return "Meisterwerk"
        case .okay: return "Okay"
        case .bad: return "Schwach"
        }
    }
}

public enum ListStatus: String, Codable, CaseIterable, Sendable {
    case current = "CURRENT"
    case planning = "PLANNING"
    case completed = "COMPLETED"
    case dropped = "DROPPED"
    case paused = "PAUSED"
    case repeating = "REPEATING"

    public var displayName: String {
        switch self {
        case .current: return "Watching"
        case .planning: return "Planned"
        case .completed: return "Completed"
        case .dropped: return "Dropped"
        case .paused: return "Paused"
        case .repeating: return "Rewatching"
        }
    }

    public func displayName(for mediaType: String) -> String {
        guard mediaType.lowercased() == "manga" else { return displayName }
        switch self {
        case .current: return "Reading"
        case .repeating: return "Rereading"
        default: return displayName
        }
    }
}

// MARK: - Rating

/// A user rating on the database scale 1...10 (the `rating` CHECK constraint).
/// The legacy 0-100 `score` is a display projection only (`score100`); writers never send it.
public struct UserRating: Hashable, Sendable {
    public let value: Int

    /// `nil` for any value outside 1...10 (e.g. a 0-100 legacy score such as 80).
    public init?(value: Int) {
        guard (1...10).contains(value) else { return nil }
        self.value = value
    }

    /// Legacy 0-100 display projection (`UserList.score`).
    public var score100: Int { value * 10 }
}

// MARK: - Entry

/// Retained source fields are read-only here; absence means unknown, never a privacy decision.
public struct LibrarySourceMetadata: Equatable, Sendable {
    public var volumesProgress: Int?
    public var repeatCount: Int?
    public var scoreRaw: String?
    public var scoreScale: String?
    public var startedRaw: String?
    public var finishedRaw: String?
    public var isPrivate: Bool?
    public var customLists: [String]?
    public var hiddenFromStatusLists: Bool?
    public var sourceListOptions: String?
    public init(volumesProgress: Int? = nil, repeatCount: Int? = nil, scoreRaw: String? = nil,
        scoreScale: String? = nil, startedRaw: String? = nil, finishedRaw: String? = nil,
        isPrivate: Bool? = nil, customLists: [String]? = nil, hiddenFromStatusLists: Bool? = nil,
        sourceListOptions: String? = nil) {
        self.volumesProgress = volumesProgress; self.repeatCount = repeatCount
        self.scoreRaw = scoreRaw; self.scoreScale = scoreScale; self.startedRaw = startedRaw
        self.finishedRaw = finishedRaw; self.isPrivate = isPrivate; self.customLists = customLists
        self.hiddenFromStatusLists = hiddenFromStatusLists; self.sourceListOptions = sourceListOptions
    }
}

/// One tracked title as projected by `LibraryStore`.
public struct LibraryEntry: Equatable, Sendable {
    public let key: MediaKey
    /// Row id in the medium's own list table. Anime and manga row ids are independent and can be
    /// equal. `0` marks an optimistic entry that has not been confirmed by the backend yet.
    public let rowId: Int
    public var status: ListStatus
    public var progress: Int
    public var progressLabel: String?
    public var unitId: UUID?
    public var sourceMetadata: LibrarySourceMetadata?
    public var rating: UserRating?
    public var notes: String?
    public var verdict: Verdict?
    public var createdAt: Date
    public var updatedAt: Date
    /// `nil` until a server revision fence exists.
    public var revision: Int64?
    /// Changes on removal/re-add; receipts from an old row must never enter the new row.
    public var lifecycleId: UUID?

    public init(
        key: MediaKey,
        rowId: Int,
        status: ListStatus,
        progress: Int,
        rating: UserRating? = nil,
        notes: String? = nil,
        verdict: Verdict? = nil,
        createdAt: Date,
        updatedAt: Date,
        revision: Int64? = nil,
        lifecycleId: UUID? = nil,
        progressLabel: String? = nil,
        unitId: UUID? = nil,
        sourceMetadata: LibrarySourceMetadata? = nil
    ) {
        self.key = key
        self.rowId = rowId
        self.status = status
        self.progress = progress
        self.progressLabel = progressLabel
        self.unitId = unitId
        self.sourceMetadata = sourceMetadata
        self.rating = rating
        self.notes = notes
        self.verdict = verdict
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.lifecycleId = lifecycleId
    }

    /// Legacy favourite rule (`score >= 90` on the 0-100 projection) expressed on the 1...10 scale.
    public var isFavorited: Bool { (rating?.value ?? 0) >= 9 }

    /// How many extra times the title was watched or read (`repeat_count`); `0` when none or unknown.
    public var repeatCount: Int { sourceMetadata?.repeatCount ?? 0 }

    /// The date the user started the title (`started_raw`). `nil` when there is none, when the stored text
    /// is not a date `PartialDate` accepts, or when the server value is unknown (`datesKnown == false`).
    /// Every stored spelling of one date (`2024-00-00`, `2024`) reads as the same value.
    public var startedOn: PartialDate? { sourceMetadata?.startedRaw.flatMap(PartialDate.init(raw:)) }

    /// The date the user finished the title (`finished_raw`); `nil` under the same conditions as `startedOn`.
    public var finishedOn: PartialDate? { sourceMetadata?.finishedRaw.flatMap(PartialDate.init(raw:)) }

    /// `true` when the repeat count and dates were read from the server, so an empty date means "none".
    /// `false` for a cached or provisional row: the server value is unknown, and callers must neither show
    /// it as empty nor fill, restore or clear it.
    public var datesKnown: Bool { sourceMetadata != nil }
}

// MARK: - Edit

/// Intent for one field of an edit. `.clear` is only valid for nullable columns.
public enum FieldChange<T: Sendable & Equatable>: Sendable, Equatable {
    case unchanged
    case set(T)
    case clear

    /// The field value after applying this change to `current`.
    func resolved(_ current: T?) -> T? {
        switch self {
        case .unchanged: return current
        case .set(let value): return value
        case .clear: return nil
        }
    }

    var isUnchanged: Bool {
        if case .unchanged = self { return true }
        return false
    }
}

/// An edit changes exactly the fields it names; every other field is left as the server has it.
public struct LibraryEdit: Sendable, Equatable {
    /// Never `.clear` (NOT NULL).
    public var status: FieldChange<ListStatus>
    /// Absolute desired position, never an increment. Never `.clear` (NOT NULL), never negative.
    public var progress: FieldChange<Int>
    public var rating: FieldChange<UserRating>
    public var notes: FieldChange<String>
    public var verdict: FieldChange<Verdict>
    /// Extra watches or reads (`repeat_count`, NOT NULL DEFAULT 0). `0...999`; never `.clear`.
    public var repeatCount: FieldChange<Int>
    /// The date the user started the title (`started_raw`); `.clear` writes `null`.
    public var startedOn: FieldChange<PartialDate>
    /// The date the user finished the title (`finished_raw`); `.clear` writes `null`.
    public var finishedOn: FieldChange<PartialDate>

    /// The largest repeat count the store accepts (`repeatCount` is `0...999`).
    public static let maxRepeatCount = 999

    public init(
        status: FieldChange<ListStatus> = .unchanged,
        progress: FieldChange<Int> = .unchanged,
        rating: FieldChange<UserRating> = .unchanged,
        notes: FieldChange<String> = .unchanged,
        verdict: FieldChange<Verdict> = .unchanged,
        repeatCount: FieldChange<Int> = .unchanged,
        startedOn: FieldChange<PartialDate> = .unchanged,
        finishedOn: FieldChange<PartialDate> = .unchanged
    ) {
        self.status = status
        self.progress = progress
        self.rating = rating
        self.notes = notes
        self.verdict = verdict
        self.repeatCount = repeatCount
        self.startedOn = startedOn
        self.finishedOn = finishedOn
    }

    /// Progress or status is named. Those fields go through the revision fence.
    package var touchesProgress: Bool {
        if case .set = progress { return true }
        return false
    }

    package var touchesStatus: Bool {
        if case .set = status { return true }
        return false
    }

    /// Notes, rating, verdict, repeat count and dates. These stay on direct PATCH (the durable progress
    /// outbox and `apply_progress_mutations_v1` carry only position and status) and still advance
    /// `server_revision`.
    package var patchBodyOmittingProgress: LibraryEdit {
        LibraryEdit(
            rating: rating, notes: notes, verdict: verdict,
            repeatCount: repeatCount, startedOn: startedOn, finishedOn: finishedOn
        )
    }

    /// `true` when the edit names no field.
    var isEmpty: Bool {
        status.isUnchanged && progress.isUnchanged && rating.isUnchanged
            && notes.isUnchanged && verdict.isUnchanged
            && repeatCount.isUnchanged && startedOn.isUnchanged && finishedOn.isUnchanged
    }

    /// Whether the edit names the repeat count or either date, the fields held in `sourceMetadata`.
    var touchesDatesOrRepeat: Bool {
        !(repeatCount.isUnchanged && startedOn.isUnchanged && finishedOn.isUnchanged)
    }

    /// The first rule the edit violates, if any. Checked before any request or projection change.
    package var validationError: LibraryError? {
        if case .clear = status { return .invalidValue(field: "status") }
        switch progress {
        case .clear: return .invalidValue(field: "progress")
        case .set(let value) where value < 0: return .invalidValue(field: "progress")
        default: break
        }
        switch repeatCount {
        case .clear: return .invalidValue(field: "repeatCount")
        case .set(let value) where !(0...Self.maxRepeatCount).contains(value): return .invalidValue(field: "repeatCount")
        default: return nil
        }
    }

    /// An absolute edit that restores every field of `entry` (re-save after a removal). The repeat count
    /// and dates are restored only when `entry.datesKnown`: an unknown value is never sent.
    static func restoring(_ entry: LibraryEntry) -> LibraryEdit {
        var edit = LibraryEdit(
            status: .set(entry.status),
            progress: .set(entry.progress),
            rating: entry.rating.map { .set($0) } ?? .clear,
            notes: entry.notes.map { .set($0) } ?? .clear,
            verdict: entry.verdict.map { .set($0) } ?? .clear
        )
        if entry.datesKnown {
            edit.repeatCount = .set(entry.repeatCount)
            edit.startedOn = entry.startedOn.map { .set($0) } ?? .clear
            edit.finishedOn = entry.finishedOn.map { .set($0) } ?? .clear
        }
        return edit
    }

    /// A compensating edit that moves only the fields that differ between `current` and `previous`
    /// back to their `previous` values. The repeat count and dates are compared by value (`2024-00-00` and
    /// `2024` are one date) and are reverted only when `previous.datesKnown`: a pre-image whose dates were
    /// never read cannot be restored, and an unknown value is never written back as empty.
    static func reverting(_ current: LibraryEntry, to previous: LibraryEntry) -> LibraryEdit {
        var edit = LibraryEdit()
        if current.status != previous.status { edit.status = .set(previous.status) }
        if current.progress != previous.progress { edit.progress = .set(previous.progress) }
        if current.rating != previous.rating { edit.rating = previous.rating.map { .set($0) } ?? .clear }
        if current.notes != previous.notes { edit.notes = previous.notes.map { .set($0) } ?? .clear }
        if current.verdict != previous.verdict { edit.verdict = previous.verdict.map { .set($0) } ?? .clear }
        if previous.datesKnown {
            if current.repeatCount != previous.repeatCount { edit.repeatCount = .set(previous.repeatCount) }
            if current.startedOn != previous.startedOn { edit.startedOn = previous.startedOn.map { .set($0) } ?? .clear }
            if current.finishedOn != previous.finishedOn { edit.finishedOn = previous.finishedOn.map { .set($0) } ?? .clear }
        }
        return edit
    }
}

extension LibraryEntry {
    static let provisionalRowId = 0

    /// Optimistic placeholder for a title that is being created.
    static func provisional(_ key: MediaKey, status: ListStatus, at time: Date) -> LibraryEntry {
        LibraryEntry(key: key, rowId: provisionalRowId, status: status, progress: 0, createdAt: time, updatedAt: time)
    }

    /// This entry with the fields named by `edit` applied.
    func applying(_ edit: LibraryEdit, at time: Date) -> LibraryEntry {
        var entry = self
        if let status = edit.status.resolved(status) { entry.status = status }
        if let progress = edit.progress.resolved(progress) {
            entry.progress = progress
            if edit.touchesProgress { entry.progressLabel = nil; entry.unitId = nil }
        }
        entry.rating = edit.rating.resolved(rating)
        entry.notes = edit.notes.resolved(notes)
        entry.verdict = edit.verdict.resolved(verdict)
        if edit.touchesDatesOrRepeat {
            // Metadata is created only here: an edit that names none of these fields leaves a cached row's
            // nil metadata nil, so an optimistic edit never turns unknown dates into known-empty ones.
            var metadata = entry.sourceMetadata ?? LibrarySourceMetadata()
            if case .set(let count) = edit.repeatCount { metadata.repeatCount = count }
            if !edit.startedOn.isUnchanged { metadata.startedRaw = edit.startedOn.resolved(nil)?.raw }
            if !edit.finishedOn.isUnchanged { metadata.finishedRaw = edit.finishedOn.resolved(nil)?.raw }
            entry.sourceMetadata = metadata
        }
        entry.updatedAt = time
        return entry
    }

    /// This entry with the fields named by `edit` taken from `prior` instead: the pre-image of an
    /// edit whose canonical result is `self`, limited to the fields the edit changed.
    func withEditedFields(of edit: LibraryEdit, from prior: LibraryEntry) -> LibraryEntry {
        var entry = self
        if !edit.status.isUnchanged { entry.status = prior.status }
        if !edit.progress.isUnchanged { entry.progress = prior.progress }
        if !edit.rating.isUnchanged { entry.rating = prior.rating }
        if !edit.notes.isUnchanged { entry.notes = prior.notes }
        if !edit.verdict.isUnchanged { entry.verdict = prior.verdict }
        if edit.touchesDatesOrRepeat {
            if prior.sourceMetadata == nil {
                // The values before the edit were never read: the pre-image keeps them unknown.
                entry.sourceMetadata = nil
            } else {
                var metadata = entry.sourceMetadata ?? LibrarySourceMetadata()
                if !edit.repeatCount.isUnchanged { metadata.repeatCount = prior.sourceMetadata?.repeatCount }
                if !edit.startedOn.isUnchanged { metadata.startedRaw = prior.sourceMetadata?.startedRaw }
                if !edit.finishedOn.isUnchanged { metadata.finishedRaw = prior.sourceMetadata?.finishedRaw }
                entry.sourceMetadata = metadata
            }
        }
        if edit.touchesProgress { entry.progressLabel = prior.progressLabel; entry.unitId = prior.unitId }
        entry.updatedAt = prior.updatedAt
        entry.revision = prior.revision
        return entry
    }
}
