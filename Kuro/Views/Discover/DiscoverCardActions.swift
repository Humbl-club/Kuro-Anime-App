import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Discover card actions (usability spec R3-R5, §5.2-§5.3, §13 "discoverMenu(for:)")
// Every Discover card is one tap (open) plus one quick action (the Plan key); everything else is in the
// long-press menu, and every menu action is also a VoiceOver custom action, so nothing depends on a
// long press. This file is the ONE swap point for lane B (preview, See all, mood journeys):
//   - `discoverMenu(for:)`: today the five-item menu below over the live data lane API
//     (`TasteStore.recordDiscoverFeedback` / `undoDiscoverFeedback`). The integrator swaps its body
//     for `discoverTitleMenu(DiscoverMenuItem(...))` (preview + the same items) after merging B.
//   - `DiscoverPlanKey`: today `TastePlanKey(...)`; the integrator adds `stampsOnConfirm: true`.
//   - `DiscoverPageFeedback` + `discoverPageFeedbackHost`: the page's interim hide toast (one toast
//     slot with the Plan toast, D12); B's `DiscoverFeedbackController` / `discoverFeedbackHost`
//     replace them. The session tallies and the telemetry stay here (lane A's).
//   - "Add as Completed ›" opens the tracking editor through the route (D13). It is not preset to
//     Completed until B adds `TrackingEditorRequest.initialStatus`. Nothing is saved silently.
// Every route is read from `\.kuroRoutes`, so the pager tap gate applies (navigation contract N9).

/// Which Discover section a card sits in (visit memory, telemetry, "Why it's here", NEW marks). The
/// page installs it per section; nil outside the Discover page (cards then keep `DiscoverFrameMenu`).
struct DiscoverSectionContext: Equatable {
    /// `DiscoverIssueSections.Section.id` ("animeNewToYou", "tonightShelf", "lead" ...).
    var id: String
    /// Titles shown now that the section's last-visit snapshot lacks (§5.8).
    var newKeys: Set<MediaKey> = []
    /// "Why it's here: …" (already localized), for the preview.
    var reason: String? = nil
}

extension EnvironmentValues {
    /// The section a Discover card sits in (nil outside the Discover page).
    @Entry var discoverSection: DiscoverSectionContext? = nil
    /// The All issue: every card shows its ANIME / MANGA kicker (§5.11).
    @Entry var discoverKindKicker: Bool = false
}

/// One card's place, for the menu, telemetry and the hide hook.
struct DiscoverCardItem {
    let card: TasteCard
    /// 0-based position in its section.
    let position: Int
}

extension View {
    /// The card's long-press menu and its VoiceOver custom actions (R3). The swap point for lane B's
    /// `discoverTitleMenu` (§13): outside the Discover page it keeps the shipped `DiscoverFrameMenu`.
    func discoverMenu(for item: DiscoverCardItem) -> some View {
        modifier(DiscoverCardMenuModifier(item: item))
    }
}

private struct DiscoverCardMenuModifier: ViewModifier {
    let item: DiscoverCardItem

    @Environment(\.discoverSection) private var section
    @Environment(DiscoverPageFeedback.self) private var feedback: DiscoverPageFeedback?
    @Environment(LibraryStore.self) private var library
    @Environment(ClubsStore.self) private var clubs

    func body(content: Content) -> some View {
        if let section, feedback != nil {
            content
                .contextMenu { DiscoverCardMenu(item: item, section: section) }
                .modifier(DiscoverCardAccessibilityActions(item: item, section: section))
        } else {
            content.contextMenu {
                DiscoverFrameMenu(media: item.card.media, isSaved: library.isTracked(item.card.key),
                                  hasClubs: !clubs.myClubs.isEmpty)
            }
        }
    }
}

/// The five items in their fixed order (§5.2): Plan, Seen it, Not interested, Add to club…, Open.
/// Seen it and Not interested are absent for a title on the list and without a session.
private struct DiscoverCardMenu: View {
    let item: DiscoverCardItem
    let section: DiscoverSectionContext

    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var actions
    @Environment(ClubsStore.self) private var clubs
    @Environment(TasteStore.self) private var taste
    @Environment(TastePlanController.self) private var plans: TastePlanController?
    @Environment(DiscoverPageFeedback.self) private var feedback: DiscoverPageFeedback?
    @Environment(\.kuroRoutes) private var routes

    private var german: Bool { KuroLocale.isGerman }

    var body: some View {
        let card = item.card
        let slot = DiscoverCardSlot(section: section.id, position: item.position)
        Button {
            KuroAccessibility.impactHaptic(.light)
            feedback?.plan(card, slot: slot, via: "menu", plans: plans, library: library, actions: actions, routes: routes)
        } label: {
            Label(DiscoverIssueCopy.menuPlan(TastePlanAction.action(for: library.entry(for: card.key)),
                                             kind: card.media.kind, german: german),
                  systemImage: "bookmark")
        }
        if DiscoverPageFeedback.offersHide(tracked: library.isTracked(card.key), signedIn: actions.accountSession.current != nil) {
            Button {
                feedback?.record(.seenIt, card: card, slot: slot, taste: taste, plans: plans)
            } label: {
                Label {
                    Text(DiscoverIssueCopy.menuSeen(kind: card.media.kind, german: german))
                    Text(DiscoverIssueCopy.menuSeenSubtitle(german: german))
                } icon: { Image(systemName: "eye") }
            }
            Button {
                feedback?.record(.notInterested, card: card, slot: slot, taste: taste, plans: plans)
            } label: {
                Label {
                    Text(DiscoverIssueCopy.menuNotInterested(german: german))
                    Text(DiscoverIssueCopy.menuNotInterestedSubtitle(german: german))
                } icon: { Image(systemName: "nosign") }
            }
        }
        if !clubs.myClubs.isEmpty {
            Button {
                KuroAccessibility.impactHaptic(.light)
                routes.presentAddToClub(card.key)
            } label: {
                Label(DiscoverIssueCopy.menuAddToClub(german: german), systemImage: "person.2")
            }
        }
        Button {
            KuroAccessibility.impactHaptic(.light)
            feedback?.trackOpen(card.key, slot: slot, via: "menu")
            routes.openMedia(MediaRoute(card.key))
        } label: {
            Label(DiscoverIssueCopy.menuOpen(german: german), systemImage: "arrow.up.forward")
        }
    }
}

/// The menu as VoiceOver custom actions (Plan, Seen it, Not interested, Add to club), so nothing on a
/// card needs the long press (§5.2 "VoiceOver").
private struct DiscoverCardAccessibilityActions: ViewModifier {
    let item: DiscoverCardItem
    let section: DiscoverSectionContext

    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var actions
    @Environment(ClubsStore.self) private var clubs
    @Environment(TasteStore.self) private var taste
    @Environment(TastePlanController.self) private var plans: TastePlanController?
    @Environment(DiscoverPageFeedback.self) private var feedback: DiscoverPageFeedback?
    @Environment(\.kuroRoutes) private var routes

    func body(content: Content) -> some View {
        let german = KuroLocale.isGerman
        let card = item.card
        let slot = DiscoverCardSlot(section: section.id, position: item.position)
        let hides = DiscoverPageFeedback.offersHide(tracked: library.isTracked(card.key),
                                                    signedIn: actions.accountSession.current != nil)
        content
            .accessibilityAction(named: Text(DiscoverIssueCopy.menuPlan(TastePlanAction.action(for: library.entry(for: card.key)),
                                                                        kind: card.media.kind, german: german))) {
                feedback?.plan(card, slot: slot, via: "menu", plans: plans, library: library, actions: actions, routes: routes)
            }
            .accessibilityActions {
                if hides {
                    Button(DiscoverIssueCopy.menuSeen(kind: card.media.kind, german: german)) {
                        feedback?.record(.seenIt, card: card, slot: slot, taste: taste, plans: plans)
                    }
                    Button(DiscoverIssueCopy.menuNotInterested(german: german)) {
                        feedback?.record(.notInterested, card: card, slot: slot, taste: taste, plans: plans)
                    }
                }
                if !clubs.myClubs.isEmpty {
                    Button(DiscoverIssueCopy.menuAddToClub(german: german)) { routes.presentAddToClub(card.key) }
                }
            }
    }
}

/// The card's Plan key on Discover (R3). The swap point for lane B's stamp: the integrator adds
/// `stampsOnConfirm: true` here once `TastePlanKey` carries it (R4 beat 2).
struct DiscoverPlanKey: View {
    let card: TasteCard
    var variant: TastePlanKey.Variant = .leaf
    var compact: Bool = true

    var body: some View {
        TastePlanKey(card: card, variant: variant, compact: compact)
    }
}

// MARK: - Page feedback (interim toast, tallies, telemetry)

/// Where a card sat when it was acted on.
struct DiscoverCardSlot: Equatable, Sendable {
    let section: String
    let position: Int
}

/// The Discover page's quick-action state for one visit: the hide toast (one slot shared with the
/// Plan toast, D12), the session tallies the end block reads (§5.7), and the §5.12 events.
@MainActor
@Observable
final class DiscoverPageFeedback {
    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        /// The answer Undo reverses (nil: "Undone.").
        let receipt: DiscoverFeedbackReceipt?
        /// Seen it's "Add as Completed ›" opens the editor for this title (D13).
        let editorMedia: Media?
    }

    private(set) var toast: Toast?
    /// Session tallies (not persisted): plans added, titles hidden, titles marked as seen.
    private(set) var planned = 0
    private(set) var hidden = 0
    private(set) var seen = 0
    /// Opens, plans and hides this visit (telemetry `taps`).
    private(set) var taps = 0

    @ObservationIgnored var telemetry: InteractionTelemetry?
    @ObservationIgnored var surface = "discover"
    /// The page's slots by title (the Plan toast names only its title).
    @ObservationIgnored var slots: [MediaKey: DiscoverCardSlot] = [:]
    /// The last hide's card, for the page's franchise removal (D16).
    @ObservationIgnored var onHidden: (DiscoverFeedback, TasteCard) -> Void = { _, _ in }
    @ObservationIgnored private var pendingPlanVia = "key"
    @ObservationIgnored private var lastPlanAdded: MediaKey?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private let holdSeconds: Double
    @ObservationIgnored private let assistiveTechnologyRunning: @MainActor () -> Bool

    init(holdSeconds: Double = 4,
         assistiveTechnologyRunning: @escaping @MainActor () -> Bool = KuroToastHold.assistiveTechnologyRunning) {
        self.holdSeconds = holdSeconds
        self.assistiveTechnologyRunning = assistiveTechnologyRunning
    }

    /// Seen it / Not interested are offered for a title that is not on the list, with a session.
    nonisolated static func offersHide(tracked: Bool, signedIn: Bool) -> Bool { !tracked && signedIn }

    /// A new visit: the tallies start again (D18).
    func resetSession() {
        planned = 0; hidden = 0; seen = 0; taps = 0
        lastPlanAdded = nil
    }

    // MARK: Actions

    /// Not interested / Seen it: hidden at once (the data lane's memory), one deck signal through the
    /// outbox, the toast with Undo. False without a session (nothing recorded).
    @discardableResult
    func record(_ feedback: DiscoverFeedback, card: TasteCard, slot: DiscoverCardSlot, taste: TasteStore,
                plans: TastePlanController?, german: Bool = KuroLocale.isGerman) -> Bool {
        guard let receipt = taste.recordDiscoverFeedback(feedback, for: card.key) else { return false }
        KuroAccessibility.impactHaptic(.rigid)
        taps += 1
        switch feedback {
        case .notInterested: hidden += 1
        case .seenIt: seen += 1
        }
        onHidden(feedback, card)
        track(feedback == .notInterested ? "discover_not_interested" : "discover_seen",
              result: feedback == .notInterested ? "hidden" : "marked", key: card.key, slot: slot)
        plans?.dismiss()
        show(Toast(message: feedback == .notInterested ? DiscoverIssueCopy.hiddenToast(german: german)
                                                      : DiscoverIssueCopy.seenToast(german: german),
                   receipt: receipt, editorMedia: feedback == .seenIt ? card.media : nil))
        AccessibilityNotification.Announcement(DiscoverIssueCopy.hiddenSpoken(german: german)).post()
        return true
    }

    /// The toast's Undo: the title comes back into its slot (once, same account only).
    @discardableResult
    func undo(taste: TasteStore, german: Bool = KuroLocale.isGerman) -> Bool {
        guard let receipt = toast?.receipt else { return false }
        toast = nil
        guard taste.undoDiscoverFeedback(receipt) else { return false }
        switch receipt.feedback {
        case .notInterested: hidden = max(0, hidden - 1)
        case .seenIt: seen = max(0, seen - 1)
        }
        track(receipt.feedback == .notInterested ? "discover_not_interested" : "discover_seen",
              result: "undone", key: receipt.key, slot: slots[receipt.key])
        show(Toast(message: TastePlanCopy.message(.undone, german: german), receipt: nil, editorMedia: nil))
        return true
    }

    /// "Add as Completed ›": the editor tool, which returns here (N7); nothing is saved until Save.
    func addAsCompleted(routes: KuroRoutes) {
        guard let media = toast?.editorMedia else { return }
        let key = media.libraryKey
        dismiss()
        track("discover_seen", result: "completed_via_editor", key: key, slot: slots[key])
        routes.presentTrackingEditor(TrackingEditorRequest(media: media))
    }

    func dismiss() {
        dismissTask?.cancel()
        toast = nil
    }

    /// A Plan from the menu or a VoiceOver action (the key itself goes through `TastePlanKey`).
    func plan(_ card: TasteCard, slot: DiscoverCardSlot, via: String, plans: TastePlanController?,
              library: LibraryStore, actions: LibraryActions, routes: KuroRoutes) {
        pendingPlanVia = via
        slots[card.key] = slot
        plans?.tap(card, library: library, actions: actions, routes: routes, german: KuroLocale.isGerman)
    }

    /// Reads one Plan toast (the controller reports its result only there): the tally and the event.
    func notePlanToast(_ toast: TastePlanController.Toast?, german: Bool = KuroLocale.isGerman) {
        guard let toast else { return }
        // D12: a Plan toast takes the one slot.
        dismiss()
        let via = pendingPlanVia
        pendingPlanVia = "key"
        let result: String
        var key: MediaKey? = toast.undo?.key
        switch toast.undo?.step {
        case .remove?:
            result = "added"
            planned += 1
            taps += 1
            lastPlanAdded = key
        case .replan?:
            result = "removed"
            taps += 1
            lastPlanAdded = nil
        case nil:
            if toast.message == TastePlanCopy.message(.undone, german: german) {
                result = "undone"
                if let added = lastPlanAdded { planned = max(0, planned - 1); key = added; lastPlanAdded = nil }
            } else {
                result = "failed"
            }
        }
        var extra: [String: Any] = ["via": via]
        if let key { extra.merge(Self.mediaExtra(key, slot: slots[key])) { $1 } }
        telemetry?.trackInteractionEvent("discover_plan", surface: surface, result: result, extra: extra)
    }

    func trackOpen(_ key: MediaKey, slot: DiscoverCardSlot?, via: String) {
        taps += 1
        var extra = Self.mediaExtra(key, slot: slot)
        extra["via"] = via
        telemetry?.trackInteractionEvent("discover_open", surface: surface, result: "opened", extra: extra)
    }

    func trackJump(_ result: String, target: String) {
        telemetry?.trackInteractionEvent("discover_jump", surface: surface, result: result, extra: ["target": target])
    }

    private func track(_ event: String, result: String, key: MediaKey, slot: DiscoverCardSlot?) {
        telemetry?.trackInteractionEvent(event, surface: surface, result: result, extra: Self.mediaExtra(key, slot: slot))
    }

    /// Catalogue ids and the slot only (no titles, no free text; §5.12).
    nonisolated static func mediaExtra(_ key: MediaKey, slot: DiscoverCardSlot?) -> [String: Any] {
        var extra: [String: Any] = ["media_type": key.kind == .manga ? "MANGA" : "ANIME", "media_id": key.id]
        if let slot {
            extra["section"] = slot.section
            extra["position"] = slot.position
        }
        return extra
    }

    private func show(_ next: Toast) {
        dismissTask?.cancel()
        toast = next
        guard !assistiveTechnologyRunning() else { dismissTask = nil; return }
        let hold = holdSeconds
        let id = next.id
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(hold))
            guard !Task.isCancelled, let self, self.toast?.id == id else { return }
            self.toast = nil
        }
    }
}

/// Installs the page's feedback for the cards below and draws its toast at the page foot. One toast
/// slot (D12): a Plan toast dismisses the hide toast, and a hide dismisses the Plan toast.
struct DiscoverPageFeedbackHost: ViewModifier {
    let feedback: DiscoverPageFeedback
    let plans: TastePlanController

    @Environment(TasteStore.self) private var taste
    @Environment(\.kuroRoutes) private var routes

    func body(content: Content) -> some View {
        let german = KuroLocale.isGerman
        content
            .environment(feedback)
            .overlay(alignment: .bottom) {
                if let toast = feedback.toast {
                    DiscoverFeedbackToastBar(
                        message: toast.message,
                        action: toast.editorMedia == nil ? nil : DiscoverIssueCopy.addAsCompleted(german: german),
                        showsUndo: toast.receipt != nil,
                        german: german,
                        onAction: { feedback.addAsCompleted(routes: routes) },
                        onUndo: { feedback.undo(taste: taste, german: german) },
                        onDismiss: { feedback.dismiss() })
                        .id(toast.id)
                        .transition(.opacity)
                }
            }
            .kuroAnimation(KuroMotion.contact, value: feedback.toast?.id)
            .onChange(of: plans.toast?.id) { _, _ in
                feedback.notePlanToast(plans.toast, german: german)
            }
    }
}

extension View {
    func discoverPageFeedbackHost(_ feedback: DiscoverPageFeedback, plans: TastePlanController) -> some View {
        modifier(DiscoverPageFeedbackHost(feedback: feedback, plans: plans))
    }
}

/// The hide toast: `TastePlanToastView`'s anatomy (`#282f2bf5`, 12 pt white, radius 18, 5/5/5/14) plus
/// one optional text action ("Add as Completed ›"). Interim until lane B's `DiscoverFeedbackToastView`.
private struct DiscoverFeedbackToastBar: View {
    let message: String
    let action: String?
    let showsUndo: Bool
    let german: Bool
    let onAction: () -> Void
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(message)
                .font(.kuroCustom(12, relativeTo: .footnote, maxSize: 22))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                textButton(action, weight: .regular, run: onAction)
            }
            if showsUndo {
                textButton(TastePlanCopy.undo(german: german), weight: .semibold, run: onUndo)
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(KuroPressStyle(pressedScale: 0.97))
            .accessibilityLabel(TastePlanCopy.dismiss(german: german))
        }
        .padding(.leading, 14)
        .padding([.top, .bottom, .trailing], 5)
        // measured: the Taste toast face `#282f2bf5` and its drop `#18241c30` (TastePlanToastView).
        .background(Color(hex: "282F2B", opacity: Double(0xF5) / 255),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color(hex: "18241C", opacity: Double(0x30) / 255), radius: 15, y: 8)
        .padding(.horizontal, 13)
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
    }

    private func textButton(_ title: String, weight: Font.Weight, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title)
                .font(.kuroCustom(12, weight: weight, relativeTo: .footnote, maxSize: 22))
                .foregroundStyle(Color.white)
                .fixedSize()
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle(pressedScale: 0.97))
    }
}
