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
    public var startedAtProgress: Int?
    public init(volumesProgress: Int? = nil, repeatCount: Int? = nil, scoreRaw: String? = nil,
        scoreScale: String? = nil, startedRaw: String? = nil, finishedRaw: String? = nil,
        isPrivate: Bool? = nil, customLists: [String]? = nil, hiddenFromStatusLists: Bool? = nil,
        sourceListOptions: String? = nil, startedAtProgress: Int? = nil) {
        self.volumesProgress = volumesProgress; self.repeatCount = repeatCount
        self.scoreRaw = scoreRaw; self.scoreScale = scoreScale; self.startedRaw = startedRaw
        self.finishedRaw = finishedRaw; self.isPrivate = isPrivate; self.customLists = customLists
        self.hiddenFromStatusLists = hiddenFromStatusLists; self.sourceListOptions = sourceListOptions
        self.startedAtProgress = startedAtProgress
    }
}

/// Computes net units genuinely consumed by subtracting any anime-to-manga bridge start offset.
public func effectiveUnitsConsumed(progress: Int, startedAt: Int?) -> Int {
    let clampedStart = max(0, startedAt ?? 0)
    return max(0, progress - clampedStart)
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
    /// Fractional or custom unit display label (`progress_label`, e.g. `"42.5"`).
    public var progressLabel: FieldChange<String>
    /// Completed volumes (`volumes_progress`, manga only). `0...99999`; never `.clear`.
    public var volumesProgress: FieldChange<Int>
    /// Honest start offset (`started_at_progress`, e.g. jumping to Ch. 64 from anime stores `63`).
    public var startedAtProgress: FieldChange<Int>
    /// Extra watches or reads (`repeat_count`, NOT NULL DEFAULT 0). `0...999`; never `.clear`.
    public var repeatCount: FieldChange<Int>
    /// The date the user started the title (`started_raw`); `.clear` writes `null`.
    public var startedOn: FieldChange<PartialDate>
    /// The date the user finished the title (`finished_raw`); `.clear` writes `null`.
    public var finishedOn: FieldChange<PartialDate>
    /// Restore only: the stored text of the start date, written exactly as it was (`2019-05-00`, or an
    /// imported text `PartialDate` cannot parse). Wins over `startedOn`; nil names nothing.
    public var startedRawVerbatim: String?
    /// Restore only: the stored text of the finish date; see `startedRawVerbatim`.
    public var finishedRawVerbatim: String?

    /// The largest repeat count the store accepts (`repeatCount` is `0...999`).
    public static let maxRepeatCount = 999
    /// The longest verbatim raw date text accepted (`started_raw` / `finished_raw` hold short date text).
    public static let maxVerbatimDateLength = 32

    public init(
        status: FieldChange<ListStatus> = .unchanged,
        progress: FieldChange<Int> = .unchanged,
        progressLabel: FieldChange<String> = .unchanged,
        volumesProgress: FieldChange<Int> = .unchanged,
        startedAtProgress: FieldChange<Int> = .unchanged,
        rating: FieldChange<UserRating> = .unchanged,
        notes: FieldChange<String> = .unchanged,
        verdict: FieldChange<Verdict> = .unchanged,
        repeatCount: FieldChange<Int> = .unchanged,
        startedOn: FieldChange<PartialDate> = .unchanged,
        finishedOn: FieldChange<PartialDate> = .unchanged,
        startedRawVerbatim: String? = nil,
        finishedRawVerbatim: String? = nil
    ) {
        self.status = status
        self.progress = progress
        self.progressLabel = progressLabel
        self.volumesProgress = volumesProgress
        self.startedAtProgress = startedAtProgress
        self.rating = rating
        self.notes = notes
        self.verdict = verdict
        self.repeatCount = repeatCount
        self.startedOn = startedOn
        self.finishedOn = finishedOn
        self.startedRawVerbatim = startedRawVerbatim
        self.finishedRawVerbatim = finishedRawVerbatim
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

    /// Notes, rating, verdict, repeat count, volumes, start offset and dates.
    package var patchBodyOmittingProgress: LibraryEdit {
        LibraryEdit(
            volumesProgress: volumesProgress, startedAtProgress: startedAtProgress,
            rating: rating, notes: notes, verdict: verdict,
            repeatCount: repeatCount, startedOn: startedOn, finishedOn: finishedOn,
            startedRawVerbatim: startedRawVerbatim, finishedRawVerbatim: finishedRawVerbatim
        )
    }

    /// `true` when the edit names no field.
    var isEmpty: Bool {
        status.isUnchanged && progress.isUnchanged && progressLabel.isUnchanged
            && volumesProgress.isUnchanged && startedAtProgress.isUnchanged
            && rating.isUnchanged && notes.isUnchanged && verdict.isUnchanged
            && repeatCount.isUnchanged && startedOn.isUnchanged && finishedOn.isUnchanged
            && startedRawVerbatim == nil && finishedRawVerbatim == nil
    }

    /// Whether the edit names fields held inside `sourceMetadata`.
    var touchesDatesOrRepeat: Bool {
        !(repeatCount.isUnchanged && volumesProgress.isUnchanged && startedAtProgress.isUnchanged
            && startedOn.isUnchanged && finishedOn.isUnchanged
            && startedRawVerbatim == nil && finishedRawVerbatim == nil)
    }

    /// The first rule the edit violates, if any. Checked before any request or projection change.
    package var validationError: LibraryError? {
        if case .clear = status { return .invalidValue(field: "status") }
        switch progress {
        case .clear: return .invalidValue(field: "progress")
        case .set(let value) where value < 0: return .invalidValue(field: "progress")
        default: break
        }
        if case .set(let label) = progressLabel {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.count > Self.maxVerbatimDateLength {
                return .invalidValue(field: "progressLabel")
            }
        }
        switch volumesProgress {
        case .clear: return .invalidValue(field: "volumesProgress")
        case .set(let value) where value < 0: return .invalidValue(field: "volumesProgress")
        default: break
        }
        switch startedAtProgress {
        case .clear: return .invalidValue(field: "startedAtProgress")
        case .set(let value) where value < 0: return .invalidValue(field: "startedAtProgress")
        default: break
        }
        switch repeatCount {
        case .clear: return .invalidValue(field: "repeatCount")
        case .set(let value) where !(0...Self.maxRepeatCount).contains(value): return .invalidValue(field: "repeatCount")
        default: break
        }
        func invalid(_ raw: String?) -> Bool {
            guard let raw else { return false }
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || raw.count > Self.maxVerbatimDateLength
        }
        if invalid(startedRawVerbatim) { return .invalidValue(field: "startedRawVerbatim") }
        if invalid(finishedRawVerbatim) { return .invalidValue(field: "finishedRawVerbatim") }
        return nil
    }

    /// An absolute edit that restores every field of `entry` (re-save after a removal). The repeat count
    /// and dates are restored only when `entry.datesKnown`: an unknown value is never sent. A stored date
    /// travels as its exact raw text (also an unparseable one); a blank one is cleared.
    public static func restoring(_ entry: LibraryEntry) -> LibraryEdit {
        var edit = LibraryEdit(
            status: .set(entry.status),
            progress: .set(entry.progress),
            progressLabel: entry.progressLabel.map { .set($0) } ?? .unchanged,
            rating: entry.rating.map { .set($0) } ?? .clear,
            notes: entry.notes.map { .set($0) } ?? .clear,
            verdict: entry.verdict.map { .set($0) } ?? .clear
        )
        if entry.key.kind == .manga, let vol = entry.sourceMetadata?.volumesProgress {
            edit.volumesProgress = .set(vol)
        }
        if let start = entry.sourceMetadata?.startedAtProgress {
            edit.startedAtProgress = .set(start)
        }
        if entry.datesKnown {
            edit.repeatCount = .set(entry.repeatCount)
            if let raw = entry.sourceMetadata?.startedRaw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { edit.startedRawVerbatim = raw } else { edit.startedOn = .clear }
            if let raw = entry.sourceMetadata?.finishedRaw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { edit.finishedRawVerbatim = raw } else { edit.finishedOn = .clear }
        }
        return edit
    }

    /// How to put a previous date back. A parsed date is set; a missing or blank stored value is cleared; a
    /// stored text that `PartialDate` cannot parse (an imported oddity) is left alone, never overwritten
    /// with null.
    private static func restoredDate(_ parsed: PartialDate?, raw: String?) -> FieldChange<PartialDate> {
        if let parsed { return .set(parsed) }
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .clear }
        return .unchanged
    }

    /// A compensating edit that moves only the fields that differ between `current` and `previous`
    /// back to their `previous` values. The repeat count and dates are compared by value (`2024-00-00` and
    /// `2024` are one date) and are reverted only when `previous.datesKnown`: a pre-image whose dates were
    /// never read cannot be restored, and an unknown value is never written back as empty.
    static func reverting(_ current: LibraryEntry, to previous: LibraryEntry) -> LibraryEdit {
        var edit = LibraryEdit()
        if current.status != previous.status { edit.status = .set(previous.status) }
        if current.progress != previous.progress { edit.progress = .set(previous.progress) }
        if current.progressLabel != previous.progressLabel {
            edit.progressLabel = previous.progressLabel.map { .set($0) } ?? .clear
        }
        if current.key.kind == .manga,
           let prevVol = previous.sourceMetadata?.volumesProgress,
           current.sourceMetadata?.volumesProgress != prevVol {
            edit.volumesProgress = .set(prevVol)
        }
        if let prevStart = previous.sourceMetadata?.startedAtProgress,
           current.sourceMetadata?.startedAtProgress != prevStart {
            edit.startedAtProgress = .set(prevStart)
        }
        if current.rating != previous.rating { edit.rating = previous.rating.map { .set($0) } ?? .clear }
        if current.notes != previous.notes { edit.notes = previous.notes.map { .set($0) } ?? .clear }
        if current.verdict != previous.verdict { edit.verdict = previous.verdict.map { .set($0) } ?? .clear }
        if previous.datesKnown {
            if current.repeatCount != previous.repeatCount { edit.repeatCount = .set(previous.repeatCount) }
            if current.startedOn != previous.startedOn {
                edit.startedOn = restoredDate(previous.startedOn, raw: previous.sourceMetadata?.startedRaw)
            }
            if current.finishedOn != previous.finishedOn {
                edit.finishedOn = restoredDate(previous.finishedOn, raw: previous.sourceMetadata?.finishedRaw)
            }
        }
        return edit
    }
}

extension LibraryEdit {
    /// The edit plus auto-filled dates: status to `.current` fills `startedOn`, to `.completed` fills
    /// `finishedOn`, only when the status actually changes (`current?.status != new`, or `creating`), the edit
    /// leaves that date `.unchanged`, and the date is empty: creating, or `current.datesKnown` and the stored
    /// raw is nil or blank. Never when the raw exists but does not parse, never for `.repeating`, never when
    /// the dates are unknown. `current` must be the confirmed entry, not the optimistic projection.
    package func fillingEmptyDates(current: LibraryEntry?, creating: Bool, today: PartialDate)
        -> (edit: LibraryEdit, autoFilled: Bool) {
        guard case .set(let new) = status, new == .current || new == .completed else { return (self, false) }
        if !creating {
            guard let current, current.status != new else { return (self, false) }
        }
        func isEmpty(_ raw: (LibrarySourceMetadata) -> String?) -> Bool {
            if creating { return true }
            guard let current, current.datesKnown, let metadata = current.sourceMetadata else { return false }
            guard let value = raw(metadata) else { return true }
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        var filled = self
        switch new {
        case .current where startedOn.isUnchanged && startedRawVerbatim == nil && isEmpty({ $0.startedRaw }):
            filled.startedOn = .set(today)
        case .completed where finishedOn.isUnchanged && finishedRawVerbatim == nil && isEmpty({ $0.finishedRaw }):
            filled.finishedOn = .set(today)
        default:
            return (self, false)
        }
        return (filled, true)
    }
}

extension LibraryEdit {
    /// The date-only edit holding what the auto-fill added to `original`; nil when it added nothing.
    func dateFillLeg(comparedTo original: LibraryEdit) -> LibraryEdit? {
        var leg = LibraryEdit()
        if startedOn != original.startedOn { leg.startedOn = startedOn }
        if finishedOn != original.finishedOn { leg.finishedOn = finishedOn }
        return leg.isEmpty ? nil : leg
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
        switch edit.progressLabel {
        case .set(let label): entry.progressLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        case .clear: entry.progressLabel = nil
        case .unchanged: break
        }
        entry.rating = edit.rating.resolved(rating)
        entry.notes = edit.notes.resolved(notes)
        entry.verdict = edit.verdict.resolved(verdict)
        if edit.touchesDatesOrRepeat {
            // Metadata is created only here: an edit that names none of these fields leaves a cached row's
            // nil metadata nil, so an optimistic edit never turns unknown dates into known-empty ones.
            var metadata = entry.sourceMetadata ?? LibrarySourceMetadata()
            if case .set(let vol) = edit.volumesProgress { metadata.volumesProgress = vol }
            if case .set(let start) = edit.startedAtProgress { metadata.startedAtProgress = start }
            if case .set(let count) = edit.repeatCount { metadata.repeatCount = count }
            if !edit.startedOn.isUnchanged { metadata.startedRaw = edit.startedOn.resolved(nil)?.raw }
            if !edit.finishedOn.isUnchanged { metadata.finishedRaw = edit.finishedOn.resolved(nil)?.raw }
            if let raw = edit.startedRawVerbatim { metadata.startedRaw = raw }
            if let raw = edit.finishedRawVerbatim { metadata.finishedRaw = raw }
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
                if !edit.volumesProgress.isUnchanged { metadata.volumesProgress = prior.sourceMetadata?.volumesProgress }
                if !edit.startedAtProgress.isUnchanged { metadata.startedAtProgress = prior.sourceMetadata?.startedAtProgress }
                if !edit.repeatCount.isUnchanged { metadata.repeatCount = prior.sourceMetadata?.repeatCount }
                if !edit.startedOn.isUnchanged || edit.startedRawVerbatim != nil { metadata.startedRaw = prior.sourceMetadata?.startedRaw }
                if !edit.finishedOn.isUnchanged || edit.finishedRawVerbatim != nil { metadata.finishedRaw = prior.sourceMetadata?.finishedRaw }
                entry.sourceMetadata = metadata
            }
        }
        if edit.touchesProgress || !edit.progressLabel.isUnchanged {
            entry.progressLabel = prior.progressLabel
        }
        if edit.touchesProgress {
            entry.unitId = prior.unitId
        }
        entry.updatedAt = prior.updatedAt
        entry.revision = prior.revision
        return entry
    }
}
