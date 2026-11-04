import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Discover feedback: Not interested / Seen it, the toast and its Undo (spec 2026-11-04 §5.3, R4, R5)
// One controller per page (the Discover page, a See all journey, a mood journey). A hide goes through
// the data lane's ONE writer, `TasteStore.recordDiscoverFeedback` (the title leaves every Discover list
// at once, is remembered per account on the device and delivered as one deck signal: Not interested
// `.skip`, Seen it `.known`). The toast then offers Undo (`TasteStore.undoDiscoverFeedback`, same
// account only, once) and, for Seen it, "Add as Completed ›" (the tracking editor route preset to
// Completed; nothing is saved until the user saves there, D13).
//
// D12: a page shows ONE toast slot. `discoverFeedbackHost(_:plans:)` draws whichever of this controller's
// toast and the Plan controller's toast arrived last and dismisses the other.

@MainActor
@Observable
final class DiscoverFeedbackController {
    struct Toast: Identifiable, Equatable {
        let id: UUID
        let message: String
        let action: Action?
        /// The answer Undo reverses (nil: a result line without Undo, e.g. "Undone.").
        let receipt: DiscoverFeedbackReceipt?

        static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
    }

    enum Action: Equatable {
        case addAsCompleted(MediaKey)
    }

    /// Where an answer was given (telemetry only: ids and positions, never titles).
    struct Context: Equatable {
        let surface: String
        let section: String
        let position: Int
    }

    /// The toast on screen, if any.
    private(set) var toast: Toast?
    /// Answers given through this controller this visit (the end tally counts them).
    private(set) var hiddenCount = 0
    private(set) var seenCount = 0

    /// The title each answer was about (the editor needs title, poster and totals).
    @ObservationIgnored private var media: [MediaKey: any MediaDisplayable] = [:]
    @ObservationIgnored private var contexts: [MediaKey: Context] = [:]
    /// Titles whose last Plan came from the menu (telemetry `via: menu`).
    @ObservationIgnored private var menuPlans: Set<MediaKey> = []
    /// The page's tally hook, called after the toast's Undo reversed an answer (the Discover page
    /// keeps its own session tallies, `DiscoverPageFeedback.noteUndone`).
    @ObservationIgnored var onUndone: (DiscoverFeedbackReceipt) -> Void = { _ in }
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private let holdSeconds: Double
    @ObservationIgnored private let assistiveTechnologyRunning: @MainActor () -> Bool

    init(holdSeconds: Double = 4,
         assistiveTechnologyRunning: @escaping @MainActor () -> Bool = KuroToastHold.assistiveTechnologyRunning) {
        self.holdSeconds = holdSeconds
        self.assistiveTechnologyRunning = assistiveTechnologyRunning
    }

    // MARK: Answers

    /// Records one answer through Taste and shows its toast. nil (nothing recorded, no toast) when
    /// signed out; the menu does not offer the answers then.
    @discardableResult
    func record(_ feedback: DiscoverFeedback, for media: any MediaDisplayable, taste: TasteStore, german: Bool,
                context: Context? = nil, telemetry: InteractionTelemetry? = nil) -> DiscoverFeedbackReceipt? {
        let key = media.libraryKey
        guard let receipt = taste.recordDiscoverFeedback(feedback, for: key) else { return nil }
        self.media[key] = media
        if let context { contexts[key] = context }
        switch feedback {
        case .notInterested: hiddenCount += 1
        case .seenIt: seenCount += 1
        }
        if let context, let telemetry {
            Self.track(telemetry, feedback: feedback, result: feedback == .notInterested ? "hidden" : "marked",
                       key: key, context: context)
        }
        showHidden(receipt, german: german)
        return receipt
    }

    /// Shows the toast of an answer already recorded (§11 API: the page may record it itself).
    func showHidden(_ receipt: DiscoverFeedbackReceipt, german: Bool) {
        let action: Action? = receipt.feedback == .seenIt ? .addAsCompleted(receipt.key) : nil
        show(Toast(id: UUID(), message: DiscoverMenuCopy.toast(receipt.feedback, german: german),
                   action: action, receipt: receipt))
    }

    /// The toast's Undo: reverses the answer it reports, once, and only for the account that gave it.
    /// Returns the reversed receipt (nil: nothing to undo, or another account is signed in now).
    @discardableResult
    func undo(taste: TasteStore, german: Bool, telemetry: InteractionTelemetry? = nil) -> DiscoverFeedbackReceipt? {
        guard let receipt = toast?.receipt else { return nil }
        dismiss()
        guard taste.undoDiscoverFeedback(receipt) else { return nil }
        switch receipt.feedback {
        case .notInterested: hiddenCount = max(0, hiddenCount - 1)
        case .seenIt: seenCount = max(0, seenCount - 1)
        }
        if let telemetry, let context = contexts[receipt.key] {
            Self.track(telemetry, feedback: receipt.feedback, result: "undone", key: receipt.key, context: context)
        }
        onUndone(receipt)
        show(Toast(id: UUID(), message: DiscoverMenuCopy.undone(german: german), action: nil, receipt: nil))
        return receipt
    }

    /// The title an answer was about (for "Add as Completed ›").
    func media(for key: MediaKey) -> (any MediaDisplayable)? { media[key] }

    /// "Add as Completed ›": the editor request preset to Completed (D13), or nil when the title is
    /// unknown. The toast leaves; the answer stays (the editor may still be cancelled).
    func completedRequest(for key: MediaKey, telemetry: InteractionTelemetry? = nil) -> TrackingEditorRequest? {
        guard let media = media[key] else { return nil }
        dismiss()
        if let telemetry, let context = contexts[key] {
            Self.track(telemetry, feedback: .seenIt, result: "completed_via_editor", key: key, context: context)
        }
        return TrackingEditorRequest(media: media, initialStatus: .completed)
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        toast = nil
    }

    // MARK: Plan telemetry (`via`)

    func noteMenuPlan(_ key: MediaKey) { menuPlans.insert(key) }

    /// Whether the title's latest Plan came from the menu (consumed once).
    func consumeMenuPlan(_ key: MediaKey) -> Bool { menuPlans.remove(key) != nil }

    // MARK: Toast timing

    /// With VoiceOver or Switch Control on it waits for × or the next result (`KuroToastHold`);
    /// otherwise it leaves after the hold.
    private func show(_ next: Toast) {
        dismissTask?.cancel()
        toast = next
        guard !assistiveTechnologyRunning() else { dismissTask = nil; return }
        let hold = holdSeconds
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(hold))
            guard !Task.isCancelled, let self, self.toast?.id == next.id else { return }
            self.toast = nil
        }
    }

    // MARK: Telemetry

    private static func track(_ telemetry: InteractionTelemetry, feedback: DiscoverFeedback, result: String,
                              key: MediaKey, context: Context) {
        telemetry.trackInteractionEvent(
            feedback == .notInterested ? "discover_not_interested" : "discover_seen",
            surface: context.surface, result: result,
            extra: DiscoverMenuTelemetry.titleExtra(section: context.section, position: context.position, key: key))
    }
}

/// The payloads the menu and the journeys send (pure; §5.12: section ids, positions and catalogue
/// ids only).
nonisolated enum DiscoverMenuTelemetry {
    static func titleExtra(section: String, position: Int, key: MediaKey) -> [String: Any] {
        ["section": section, "position": position, "media_type": key.kind.rawValue.uppercased(), "media_id": key.id]
    }
}

// MARK: - The page's toast slot (D12)

private struct DiscoverFeedbackHost: ViewModifier {
    let feedback: DiscoverFeedbackController
    let plans: TastePlanController

    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var actions
    @Environment(TasteStore.self) private var taste
    @Environment(InteractionTelemetry.self) private var telemetry: InteractionTelemetry?
    @Environment(\.kuroRoutes) private var routes

    func body(content: Content) -> some View {
        let german = KuroLocale.isGerman
        content
            .environment(plans)
            .environment(feedback)
            .overlay(alignment: .bottom) {
                if let toast = feedback.toast {
                    DiscoverFeedbackToastView(
                        message: toast.message,
                        actionTitle: toast.action.map { _ in DiscoverMenuCopy.addAsCompleted(german: german) },
                        actionSpoken: DiscoverMenuCopy.addAsCompletedSpoken(german: german),
                        showsUndo: toast.receipt != nil,
                        german: german,
                        onAction: {
                            guard case .addAsCompleted(let key)? = toast.action,
                                  let request = feedback.completedRequest(for: key, telemetry: telemetry) else { return }
                            routes.presentTrackingEditor(request)
                        },
                        onUndo: { feedback.undo(taste: taste, german: german, telemetry: telemetry) },
                        onDismiss: { feedback.dismiss() })
                        .id(toast.id)
                        .transition(.opacity)
                        .onAppear {
                            let spoken = toast.receipt != nil ? DiscoverMenuCopy.hiddenAnnouncement(german: german) : toast.message
                            AccessibilityNotification.Announcement(spoken).post()
                        }
                } else if let toast = plans.toast {
                    TastePlanToastView(toast: toast, german: german,
                                       onUndo: { plans.undo(library: library, actions: actions, german: german) },
                                       onDismiss: { plans.dismiss() })
                        .id(toast.id)
                        .transition(.opacity)
                        .onAppear { AccessibilityNotification.Announcement(toast.message).post() }
                }
            }
            .kuroAnimation(KuroMotion.contact, value: DiscoverToastSlot.visible(feedback: feedback.toast?.id, plan: plans.toast?.id))
            // One slot: the newer toast dismisses the other.
            .onChange(of: feedback.toast?.id) { _, id in if id != nil { plans.dismiss() } }
            .onChange(of: plans.toast?.id) { _, id in if id != nil { feedback.dismiss() } }
    }
}

/// Which toast the slot shows (pure; DUpreviewTests): the feedback toast while there is one (the
/// controllers dismiss each other, so at most one is set after a change), else the Plan toast.
nonisolated enum DiscoverToastSlot: Equatable {
    case none
    case feedback(UUID)
    case plan(UUID)

    static func visible(feedback: UUID?, plan: UUID?) -> DiscoverToastSlot {
        if let feedback { return .feedback(feedback) }
        if let plan { return .plan(plan) }
        return .none
    }
}

extension View {
    /// The page-foot toast for both controllers (D12): installs them for the cards below (Plan keys,
    /// the long-press menu) and draws one toast at the foot of the modified view. Put it outside the
    /// page's ScrollView. On Discover it replaces `tastePlanHost` (never stack both).
    func discoverFeedbackHost(_ feedback: DiscoverFeedbackController, plans: TastePlanController) -> some View {
        modifier(DiscoverFeedbackHost(feedback: feedback, plans: plans))
    }
}
