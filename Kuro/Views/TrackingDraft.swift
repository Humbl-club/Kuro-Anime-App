import Foundation
import KuroCore
import KuroLibrary

// MARK: - Tracking editor save rule

/// What the tracking editor (`AddToListSheet`) shows, and the ONE explicit `LibraryEdit` a save
/// sends: exactly the fields the user sees (status, progress, rating, notes).
///
/// - Status and progress are always written; a title that is not tracked yet is created with the
///   chosen status (`createIfMissing`).
/// - Completing a title whose progress is still 0 marks every known episode/chapter; with an
///   unknown total the progress stays as entered.
/// - `score` is the database scale 1...10 (`UserRating`), 0 = unrated. Emptying a rating the entry
///   had clears it; a title that stays unrated leaves the stored rating alone. Any other value is
///   never sent and never clears.
/// - Notes are trimmed; an empty note clears the note the entry had, otherwise stays unsent.
/// - The verdict is never part of this edit.
/// - The repeat count and the started / finished dates are sent only when they differ by value from the
///   entry the editor was filled from. A date the entry had and the user emptied is a deliberate clear; an
///   untouched date (also an imported one the editor cannot parse, or one whose server value was never
///   read) is never sent, so it can never be rewritten or blanked.
struct TrackingDraft: Equatable {
    var status: ListStatus
    var progress: Int
    /// 0 = unrated; otherwise 1...10.
    var score: Int
    var notes: String
    /// Rating and note of the entry the editor was filled from (nil when it had none, or when the
    /// title was not tracked): emptying one of them is a deliberate clear.
    let originalRating: UserRating?
    let originalNotes: String?
    /// Extra watches or reads (`0...999`).
    var repeatCount: Int
    var startedOn: PartialDate?
    var finishedOn: PartialDate?
    private(set) var originalRepeatCount: Int
    private(set) var originalStartedOn: PartialDate?
    private(set) var originalFinishedOn: PartialDate?
    /// `false` for a cached row whose repeat count and dates the server never confirmed: the editor shows
    /// them as unknown, does not let the user edit them, and `edit` never names them. They become editable
    /// when the stored values arrive (`adoptDates`).
    private(set) var datesKnown: Bool

    /// The stored repeat count and dates arrived for the entry this draft was filled from: show them and make
    /// them editable. They become the baseline, so adopting them is not a change. No-op when already known
    /// or when `entry` does not know them either.
    mutating func adoptDates(from entry: LibraryEntry) {
        guard !datesKnown, entry.datesKnown else { return }
        repeatCount = entry.repeatCount
        startedOn = entry.startedOn
        finishedOn = entry.finishedOn
        originalRepeatCount = entry.repeatCount
        originalStartedOn = entry.startedOn
        originalFinishedOn = entry.finishedOn
        datesKnown = true
    }

    /// The projection finished loading and the title is still not tracked: it is new, so its dates and repeat
    /// count are editable. No-op when already known or when the title turned out to be tracked.
    mutating func adoptLoadedProjection(entry: LibraryEntry?) {
        guard !datesKnown, entry == nil else { return }
        datesKnown = true
    }

    /// A draft filled from `entry`; a title that is not tracked starts as Planned with nothing set,
    /// or at `initialStatus` when the caller preset one (Discover "Add as Completed ›"). An entry's own
    /// status always wins over the preset.
    init(entry: LibraryEntry?, initialStatus: ListStatus? = nil, projectionLoaded: Bool = true) {
        status = entry?.status ?? initialStatus ?? .planning
        progress = entry?.progress ?? 0
        score = entry?.rating?.value ?? 0
        notes = entry?.notes ?? ""
        originalRating = entry?.rating
        originalNotes = entry?.notes
        repeatCount = entry?.repeatCount ?? 0
        startedOn = entry?.startedOn
        finishedOn = entry?.finishedOn
        originalRepeatCount = entry?.repeatCount ?? 0
        originalStartedOn = entry?.startedOn
        originalFinishedOn = entry?.finishedOn
        // No entry: a new title only when the account's rows are loaded; otherwise it may exist with values
        // this device has not read, so its repeat count and dates are unknown (locked, never sent).
        datesKnown = entry?.datesKnown ?? projectionLoaded
    }

    /// The status a missing entry is created with.
    var createIfMissing: ListStatus { status }

    /// Whether the editor holds input a Cancel would lose (navigation contract N7): any shown field
    /// differs from the draft the editor was filled with. Notes compare trimmed (whitespace alone is
    /// not a change, matching what a save would send).
    func hasChanges(from baseline: TrackingDraft) -> Bool {
        status != baseline.status
            || progress != baseline.progress
            || score != baseline.score
            || notes.trimmingCharacters(in: .whitespacesAndNewlines)
                != baseline.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            || repeatCount != baseline.repeatCount
            || startedOn != baseline.startedOn
            || finishedOn != baseline.finishedOn
    }

    /// The progress a save writes. `maxProgress` is the known episode/chapter total (0 = unknown).
    func resolvedProgress(maxProgress: Int) -> Int {
        if status == .completed && maxProgress > 0 && progress == 0 {
            return maxProgress
        }
        return max(0, progress)
    }

    /// The edit a save sends. `maxProgress` is the known episode/chapter total (0 = unknown).
    func edit(maxProgress: Int) -> LibraryEdit {
        LibraryEdit(
            status: .set(status),
            progress: .set(resolvedProgress(maxProgress: maxProgress)),
            rating: ratingChange,
            notes: notesChange,
            verdict: .unchanged,
            // From an unknown baseline these are never named: the editor cannot see what the server holds.
            repeatCount: !datesKnown || repeatCount == originalRepeatCount ? .unchanged
                : .set(min(max(0, repeatCount), LibraryEdit.maxRepeatCount)),
            startedOn: datesKnown ? dateChange(startedOn, original: originalStartedOn) : .unchanged,
            finishedOn: datesKnown ? dateChange(finishedOn, original: originalFinishedOn) : .unchanged
        )
    }

    /// By value: an unchanged date is not sent; a new one is set; one the entry had and the user emptied is
    /// cleared. When the original is nil (none, unparseable, or unknown) an empty date is never a clear.
    private func dateChange(_ value: PartialDate?, original: PartialDate?) -> FieldChange<PartialDate> {
        if value == original { return .unchanged }
        return value.map { .set($0) } ?? .clear
    }

    private var ratingChange: FieldChange<UserRating> {
        if let rating = UserRating(value: score) { return .set(rating) }
        guard score == 0 else { return .unchanged }
        return originalRating == nil ? .unchanged : .clear
    }

    private var notesChange: FieldChange<String> {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return .set(trimmed) }
        return originalNotes == nil ? .unchanged : .clear
    }
}

// MARK: - Quick status change rule

/// Save rule of the quick status/verdict actions (`QuickVerdictActionCard`, `QuickVerdictPickerSheet`):
/// a status change names the status and, only when the title becomes completed and its
/// episode/chapter total is known, the completion progress (every known episode/chapter, never
/// below the progress the projection holds). Any other status leaves the stored progress alone, so
/// a stale projection is never re-sent. Rating, notes and verdict are never part of it.
enum QuickStatusChange {
    /// `currentProgress` is the projection's progress (nil when not tracked); `total` is the known
    /// episode/chapter total (0 = unknown).
    static func edit(to status: ListStatus, currentProgress: Int?, total: Int) -> LibraryEdit {
        var edit = LibraryEdit(status: .set(status))
        if status == .completed, total > 0 {
            edit.progress = .set(max(total, currentProgress ?? 0))
        }
        return edit
    }
}
