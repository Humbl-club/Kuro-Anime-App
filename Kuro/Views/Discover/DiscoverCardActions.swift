import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Discover card actions (usability spec R3-R5, §5.2-§5.3, §13 "discoverMenu(for:)")
// Every Discover card is one tap (open) plus one quick action (the Plan key); everything else is in the
// long-press menu, and every menu action is also a VoiceOver custom action, so nothing depends on a
// long press. Integrated 2026-11-04 (lanes A + B):
//   - `discoverMenu(for:)` inside a Discover section gives the card lane B's `discoverTitleMenu`: the
//     lifted preview (`DiscoverTitlePreview`) and the five items over `TasteStore.recordDiscoverFeedback`.
//     Outside the Discover page the card keeps the shipped `DiscoverFrameMenu`.
//   - `DiscoverPlanKey` stamps on a confirmed add and restores on a failure (`stampsOnConfirm`, R4).
//   - `discoverPageHost(_:hides:plans:)` installs this page's `DiscoverPageFeedback` (session tallies and
//     the page's own §5.12 events) next to lane B's `discoverFeedbackHost` (the ONE toast slot for the
//     hide toast with Undo / "Add as Completed ›" and the Plan toast, D12).
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
    /// The section's heading, for the preview kicker (nil: the medium only).
    var title: String? = nil
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
    /// The card's long-press preview + menu and its VoiceOver custom actions (R3): lane B's
    /// `discoverTitleMenu` inside a Discover section, the shipped `DiscoverFrameMenu` elsewhere.
    func discoverMenu(for item: DiscoverCardItem) -> some View {
        modifier(DiscoverCardMenuModifier(item: item))
    }
}

private struct DiscoverCardMenuModifier: ViewModifier {
    let item: DiscoverCardItem

    @Environment(\.discoverSection) private var section
    @Environment(DiscoverPageFeedback.self) private var page: DiscoverPageFeedback?
    @Environment(DiscoverFeedbackController.self) private var hides: DiscoverFeedbackController?
    @Environment(LibraryStore.self) private var library
    @Environment(ClubsStore.self) private var clubs

    func body(content: Content) -> some View {
        if let section, page != nil, hides != nil {
            let card = item.card
            let position = item.position
            let page = page
            content.discoverTitleMenu(DiscoverMenuItem(
                card: card, section: section.id, position: position, reason: section.reason,
                sectionTitle: section.title, surface: "discover",
                onHidden: { receipt in page?.noteHidden(receipt, card: card) }))
        } else {
            content.contextMenu {
                DiscoverFrameMenu(media: item.card.media, isSaved: library.isTracked(item.card.key),
                                  hasClubs: !clubs.myClubs.isEmpty)
            }
        }
    }
}

/// The card's Plan key on Discover (R3): stamps on a confirmed add, restores on a failure (R4 beat 2).
struct DiscoverPlanKey: View {
    let card: TasteCard
    var variant: TastePlanKey.Variant = .leaf
    var compact: Bool = true

    var body: some View {
        TastePlanKey(card: card, variant: variant, compact: compact, stampsOnConfirm: true)
    }
}

// MARK: - Page feedback (tallies, telemetry)

/// Where a card sat when it was acted on.
struct DiscoverCardSlot: Equatable, Sendable {
    let section: String
    let position: Int
}

/// The Discover page's quick-action bookkeeping for one visit: the session tallies the end block reads
/// (§5.7) and the visit-end deltas, plus the page's own §5.12 events (opens from a card, jumps, Plan
/// results). The hide toast, its Undo and the hide/seen events are lane B's `DiscoverFeedbackController`;
/// it reports each answer and each Undo here (`noteHidden` / `noteUndone`), so nothing is counted twice.
@MainActor
@Observable
final class DiscoverPageFeedback {
    /// Session tallies (not persisted): plans added, titles hidden, titles marked as seen.
    private(set) var planned = 0
    private(set) var hidden = 0
    private(set) var seen = 0
    /// Opens, plans and hides this visit (telemetry `taps`; the late-Library rebuild guard, D5).
    private(set) var taps = 0

    @ObservationIgnored var telemetry: InteractionTelemetry?
    @ObservationIgnored var surface = "discover"
    /// The page's slots by title (a Plan result names only its title).
    @ObservationIgnored var slots: [MediaKey: DiscoverCardSlot] = [:]
    /// The last hide's card (the page's franchise rule reads Taste directly, D16).
    @ObservationIgnored var onHidden: (DiscoverFeedback, TasteCard) -> Void = { _, _ in }
    @ObservationIgnored private var lastPlanAdded: MediaKey?
    @ObservationIgnored private var lastPlanToken: Int?

    init() {}

    /// A new visit: the tallies start again (D18).
    func resetSession() {
        planned = 0; hidden = 0; seen = 0; taps = 0
        lastPlanAdded = nil
    }

    // MARK: Answers (reported by lane B's menu and controller)

    /// One Not interested / Seen it was recorded (the controller already sent its event).
    func noteHidden(_ receipt: DiscoverFeedbackReceipt, card: TasteCard) {
        taps += 1
        switch receipt.feedback {
        case .notInterested: hidden += 1
        case .seenIt: seen += 1
        }
        onHidden(receipt.feedback, card)
    }

    /// The toast's Undo reversed an answer (the controller already sent its event).
    func noteUndone(_ receipt: DiscoverFeedbackReceipt) {
        switch receipt.feedback {
        case .notInterested: hidden = max(0, hidden - 1)
        case .seenIt: seen = max(0, seen - 1)
        }
    }

    // MARK: Plan results

    /// One Plan result (`TastePlanController.lastResult`): the tally and the `discover_plan` event.
    /// `viaMenu`: the result's title was planned from the long-press menu or a VoiceOver action.
    func notePlanResult(_ result: TastePlanController.Result?, viaMenu: Bool) {
        guard let result, result.token != lastPlanToken else { return }
        lastPlanToken = result.token
        var key = result.key
        let outcome: String
        switch result.outcome {
        case .added:
            outcome = "added"
            planned += 1
            taps += 1
            lastPlanAdded = key
        case .removed:
            outcome = "removed"
            taps += 1
            lastPlanAdded = nil
        case .undone:
            outcome = "undone"
            if let added = lastPlanAdded, added == result.key {
                planned = max(0, planned - 1)
                key = added
                lastPlanAdded = nil
            }
        case .failed:
            outcome = "failed"
        }
        var extra: [String: Any] = ["via": viaMenu ? "menu" : "key"]
        extra.merge(Self.mediaExtra(key, slot: slots[key])) { $1 }
        telemetry?.trackInteractionEvent("discover_plan", surface: surface, result: outcome, extra: extra)
    }

    // MARK: Page events

    func trackOpen(_ key: MediaKey, slot: DiscoverCardSlot?, via: String) {
        taps += 1
        var extra = Self.mediaExtra(key, slot: slot)
        extra["via"] = via
        telemetry?.trackInteractionEvent("discover_open", surface: surface, result: "opened", extra: extra)
    }

    func trackJump(_ result: String, target: String) {
        telemetry?.trackInteractionEvent("discover_jump", surface: surface, result: result, extra: ["target": target])
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
}

/// Installs the page's bookkeeping for the cards below and lane B's one toast slot at the page foot
/// (D12). Put it outside the page's ScrollView; it replaces `tastePlanHost` (never stack both).
private struct DiscoverPageHost: ViewModifier {
    let page: DiscoverPageFeedback
    let hides: DiscoverFeedbackController
    let plans: TastePlanController

    func body(content: Content) -> some View {
        content
            .environment(page)
            .discoverFeedbackHost(hides, plans: plans)
            .onChange(of: plans.lastResult?.token) { _, _ in
                guard let result = plans.lastResult else { return }
                page.notePlanResult(result, viaMenu: hides.consumeMenuPlan(result.key))
            }
    }
}

extension View {
    func discoverPageHost(_ page: DiscoverPageFeedback, hides: DiscoverFeedbackController,
                          plans: TastePlanController) -> some View {
        modifier(DiscoverPageHost(page: page, hides: hides, plans: plans))
    }
}
