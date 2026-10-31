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

    /// A draft filled from `entry`; a title that is not tracked starts as Planned with nothing set.
    init(entry: LibraryEntry?) {
        status = entry?.status ?? .planning
        progress = entry?.progress ?? 0
        score = entry?.rating?.value ?? 0
        notes = entry?.notes ?? ""
        originalRating = entry?.rating
        originalNotes = entry?.notes
    }

    /// The status a missing entry is created with.
    var createIfMissing: ListStatus { status }

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
            verdict: .unchanged
        )
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
