import KuroCore
import SwiftUI

// MARK: - Home +1 toast (PROTOTYPE_SPEC.md §3.4, §6)
// After a +1 the prototype shows a toast at the screen foot: "Progress saved." (or "Caught up." when the
// key is now capped) with Undo and a dismiss ×; Undo restores the count and says "Undone."; a save that
// did not happen says "Not saved. Your progress is unchanged.". The toast is drawn by
// `TastePlanToastView`, the same toast the Taste Plan keys use, so the two read as one family.

/// The +1 toast's words and its pure rules, EN/DE (PROTOTYPE_SPEC.md §7.1 "Toasts").
nonisolated enum HomeProgressToastCopy {
    enum Result: Equatable {
        case saved, caughtUp, undone
        /// The +1 was not saved: the count never moved.
        case failed
        /// The +1 was saved and Undo could not reverse it: the count stays at `position`.
        case undoFailed(position: Int, manga: Bool)
    }

    static func message(_ result: Result, german: Bool) -> String {
        switch result {
        case .saved: return german ? "Fortschritt gespeichert." : "Progress saved."
        case .caughtUp: return german ? "Auf dem neuesten Stand." : "Caught up."
        case .undone: return german ? "Rückgängig gemacht." : "Undone."
        case .failed: return german ? "Nicht gespeichert. Dein Fortschritt ist unverändert."
                                    : "Not saved. Your progress is unchanged."
        case .undoFailed(let position, let manga):
            if german { return "Rückgängig nicht möglich. Dein Stand bleibt bei \(manga ? "Kapitel" : "Folge") \(position)." }
            return "Couldn't undo. Your progress stays at \(manga ? "Ch." : "Ep.") \(position)."
        }
    }

    /// What one +1 produced. A raised count is saved ("Caught up." when the key is now capped); no rise
    /// with a failed save is the failure; anything else (the title needs a choice on its page, the
    /// presentation changed, the key was already capped) shows no toast.
    static func advanceResult(before: Int, after: Int, caughtUpAfter: Bool, saveFailed: Bool) -> Result? {
        if after > before { return caughtUpAfter ? .caughtUp : .saved }
        return saveFailed ? .failed : nil
    }

    /// Whether Home's status line under the feed shows `status`.
    /// - Library's "Saved on this device" while a save is still pending in the outbox (`savePending`),
    ///   online or offline: Library keeps the message after the receipt, so the outbox, not the message,
    ///   says whether it is still true. Online it waits while the toast says "Progress saved.".
    /// - The not-saved line and Library's "already on its way" not while the toast tells the result.
    /// - Everything else as it is.
    static func statusLineShows(_ status: String, savedOnDevice: String, notSaved: String, onItsWay: String,
                                savePending: Bool, offline: Bool, toastShowing: Bool) -> Bool {
        if status == savedOnDevice { return savePending && (offline || !toastShowing) }
        if status == notSaved || status == onItsWay { return !toastShowing }
        return true
    }

    /// What Undo produced: the count back where it was before the +1, or the count that stays.
    static func undoResult(before: Int, after: Int, manga: Bool) -> Result {
        after == before ? .undone : .undoFailed(position: after, manga: manga)
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

    /// The +1 an Undo reverses: the title, the count before and after it, and the account that made it.
    struct Undo: Equatable {
        let medium: String
        let mediaId: Int
        let lifecycleId: String
        let before: Int
        let after: Int
        let account: AccountContext
    }

    private(set) var toast: Toast?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private let holdSeconds: Double
    @ObservationIgnored private let assistiveTechnologyRunning: @MainActor () -> Bool

    init(holdSeconds: Double = 4,
         assistiveTechnologyRunning: @escaping @MainActor () -> Bool = KuroToastHold.assistiveTechnologyRunning) {
        self.holdSeconds = holdSeconds
        self.assistiveTechnologyRunning = assistiveTechnologyRunning
    }

    func show(_ message: String, undo: Undo?) {
        dismissTask?.cancel()
        let toast = Toast(message: message, undo: undo)
        self.toast = toast
        // A VoiceOver or Switch Control user reaches Undo at their own pace: the toast waits for × (or
        // the next result) instead of leaving after the hold.
        guard !assistiveTechnologyRunning() else { dismissTask = nil; return }
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

    /// Reverses the toast's +1 and reports the result.
    /// 1. `HomeStore.undo` cancels the +1 while it is still unsent (nothing reaches the server).
    /// 2. Once the drain has attempted it (offline, or the request is on its way with no receipt yet),
    ///    Library keeps that intent as it is. Home then queues the reversal behind it: a save of the
    ///    count before the +1 (`HomeStore.setPosition`, the detail page's position write). The outbox
    ///    sends it after the +1 (rebased on its receipt), so the server ends where the reader asked.
    /// 3. The reversal is queued only while the count is still the one the +1 made: a count that moved
    ///    on since (another +1, another device) is never wound back, and the toast says where it stays.
    static func performUndo(_ undo: Undo, card: HomeCard, home: HomeStore,
                            session: AccountSessionCoordinator) async -> HomeProgressToastCopy.Result {
        let manga = undo.medium == "manga"
        var now = home.displayedProgress(for: card)
        // Only the count this +1 made is reversed: an edit made since (the title's page, another
        // device) is never cancelled or wound back.
        guard session.isCurrent(undo.account), home.medium == undo.medium, now == undo.after else {
            return HomeProgressToastCopy.undoResult(before: undo.before, after: now, manga: manga)
        }
        await home.undo(card)
        now = home.displayedProgress(for: card)
        if now == undo.before { return .undone }
        guard session.isCurrent(undo.account), home.medium == undo.medium, now == undo.after else {
            return .undoFailed(position: now, manga: manga)
        }
        await home.setPosition(medium: undo.medium, mediaId: card.mediaId, user: userState(card), position: undo.before)
        now = home.displayedProgress(for: card)
        return HomeProgressToastCopy.undoResult(before: undo.before, after: now, manga: manga)
    }

    /// The Library row a Home card stands for, as the position write takes it.
    private static func userState(_ card: HomeCard) -> SeriesDetailBundle.UserState {
        SeriesDetailBundle.UserState(serverRevision: card.serverRevision, lifecycleId: card.lifecycleId,
                                     progress: card.progress, progressLabel: card.progressLabel,
                                     listType: card.listType, notes: nil, unitId: card.unitId)
    }
}

/// When a result toast leaves by itself. With VoiceOver or Switch Control on it waits to be dismissed:
/// the announcement is read at once, but reaching its Undo takes longer than the 4 s hold.
enum KuroToastHold {
    nonisolated static func holdsUntilDismissed(voiceOver: Bool, switchControl: Bool) -> Bool {
        voiceOver || switchControl
    }

    @MainActor
    static func assistiveTechnologyRunning() -> Bool {
        #if canImport(UIKit)
        return holdsUntilDismissed(voiceOver: UIAccessibility.isVoiceOverRunning,
                                   switchControl: UIAccessibility.isSwitchControlRunning)
        #else
        return false
        #endif
    }
}
