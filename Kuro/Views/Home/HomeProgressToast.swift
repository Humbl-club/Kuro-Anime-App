import KuroCore
import SwiftUI

// MARK: - Home +1 toast (PROTOTYPE_SPEC.md §3.4, §6)
// After a +1 the prototype shows a toast at the screen foot: "Progress saved." (or "Caught up." when the
// key is now capped) with Undo and a dismiss ×; Undo restores the count and says "Undone."; a save that
// did not happen says "Not saved. Your progress is unchanged.". The toast is drawn by
// `TastePlanToastView`, the same toast the Taste Plan keys use, so the two read as one family.

/// The +1 toast's words and its pure rules, EN/DE (PROTOTYPE_SPEC.md §7.1 "Toasts").
nonisolated enum HomeProgressToastCopy {
    enum Result: Equatable { case saved, caughtUp, undone, failed }

    static func message(_ result: Result, german: Bool) -> String {
        switch result {
        case .saved: return german ? "Fortschritt gespeichert." : "Progress saved."
        case .caughtUp: return german ? "Auf dem neuesten Stand." : "Caught up."
        case .undone: return german ? "Rückgängig gemacht." : "Undone."
        case .failed: return german ? "Nicht gespeichert. Dein Fortschritt ist unverändert."
                                    : "Not saved. Your progress is unchanged."
        }
    }

    /// What one +1 produced. A raised count is saved ("Caught up." when the key is now capped); no rise
    /// with a failed save is the failure; anything else (the title needs a choice on its page, the
    /// presentation changed, the key was already capped) shows no toast.
    static func advanceResult(before: Int, after: Int, caughtUpAfter: Bool, saveFailed: Bool) -> Result? {
        if after > before { return caughtUpAfter ? .caughtUp : .saved }
        return saveFailed ? .failed : nil
    }

    /// Whether Home's status line under the feed shows `status`. Library's "Saved on this device" only
    /// while offline (online the save is on its way; the toast already said "Progress saved."); the
    /// not-saved line not while the toast says it; everything else as it is.
    static func statusLineShows(_ status: String, savedOnDevice: String, notSaved: String, offline: Bool,
                                toastShowing: Bool) -> Bool {
        if status == savedOnDevice { return offline }
        if status == notSaved { return !toastShowing }
        return true
    }

    /// What Undo produced: the count back where it was before the +1, or the failure.
    static func undoResult(before: Int, after: Int) -> Result {
        after == before ? .undone : .failed
    }
}

/// Home's one +1 toast slot: the message, the Undo it offers (once) and its hold.
@MainActor
@Observable
final class HomeProgressToasts {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let undo: Undo?
    }

    /// The +1 an Undo reverses: the title, the count before it, and the account that made it.
    struct Undo: Equatable {
        let medium: String
        let mediaId: Int
        let lifecycleId: String
        let before: Int
        let account: AccountContext
    }

    private(set) var toast: Toast?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private let holdSeconds: Double

    init(holdSeconds: Double = 4) {
        self.holdSeconds = holdSeconds
    }

    func show(_ message: String, undo: Undo?) {
        dismissTask?.cancel()
        let toast = Toast(message: message, undo: undo)
        self.toast = toast
        let hold = holdSeconds
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(hold))
            guard !Task.isCancelled, let self, self.toast?.id == toast.id else { return }
            self.toast = nil
        }
    }

    /// The toast's Undo, once: the toast leaves as it is taken.
    func takeUndo() -> Undo? {
        guard let undo = toast?.undo else { return nil }
        dismiss()
        return undo
    }

    func dismiss() {
        dismissTask?.cancel()
        toast = nil
    }

    /// `HomeStore.undo` reverses only the last advanced title (same medium, id and lifecycle), so the
    /// toast offers Undo only while that is still this toast's title (never a dead button).
    nonisolated static func undoApplies(_ undo: Undo, lastKey: MediaKey?, lastLifecycle: String?) -> Bool {
        guard let lastKey, let lastLifecycle else { return false }
        return lastKey.kind.rawValue.lowercased() == undo.medium && lastKey.id == undo.mediaId
            && lastLifecycle.lowercased() == undo.lifecycleId.lowercased()
    }
}
