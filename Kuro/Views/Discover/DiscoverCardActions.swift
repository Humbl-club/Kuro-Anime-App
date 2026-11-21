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
    /// The reason words for the preview, already localized ("in our canon"); the preview adds
    /// "Why it's here: " (`DiscoverMenuCopy.whyItsHere`).
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
                onHidden: { receipt in page?.noteHidden(receipt, card: card) },
                onOpened: { page?.noteMenuOpen() }))
        } else {
            content.contextMenu {
                DiscoverFrameMenu(media: item.card.media, isSaved: library.isTracked(item.card.key),
                                  hasClubs: !clubs.myClubs.isEmpty)
            }
        }
    }
}

/// The card's Plan key on Discover (R3): stamps on a confirmed add, restores on a failure (R4 beat 2).
/// Landscape cover stories keep the full `TastePlanKey`; portrait tiles and index rows use a calm
/// compact capsule pill inside a 44 pt hit target so 27 cards on a page don't shout with boxes.
struct DiscoverPlanKey: View {
    let card: TasteCard
    var variant: TastePlanKey.Variant = .leaf
    var compact: Bool = true
    var trailingAligned: Bool = false
    /// The corner badge face (cover tiles and index rows): a 30 pt circle in a 44 pt target.
    var badge: Bool = false
    /// True when placed inside a light `#FFFFFF` placard rather than a dark material foot.
    var onLightSurface: Bool = false

    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @Environment(\.kuroRoutes) private var routes
    @Environment(GuestSession.self) private var guest: GuestSession?
    @Environment(\.tasteGerman) private var germanOverride
    @Environment(TastePlanController.self) private var hostController: TastePlanController?
    @Environment(BannerCenter.self) private var banner: BannerCenter?
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    @State private var localController = TastePlanController()

    private static let savedLeafFace = Color.kuroControlInk

    static func compactLabel(action: TastePlanAction, status: ListStatus?, kind: MediaKind, german: Bool) -> String {
        switch status {
        case nil:
            return german ? "Liste" : "Add"
        case .planning:
            return german ? "Geplant" : "Planned"
        case .some(let tracked):
            return DiscoverIssueCopy.statusWord(tracked, progress: 0, kind: kind, german: german)
        }
    }

    static func landscapeLabel(status: ListStatus?, kind: MediaKind, german: Bool) -> String {
        switch status {
        case nil:
            return german ? "Zur Liste" : "Add to list"
        case .planning:
            return german ? "Geplant" : "Planned"
        case .some(let tracked):
            return DiscoverIssueCopy.statusWord(tracked, progress: 0, kind: kind, german: german)
        }
    }

    static func menuChoiceTitle(_ status: ListStatus, kind: MediaKind, german: Bool) -> String {
        switch (status, kind, german) {
        case (.current, .anime, false): return "Watching"
        case (.current, .anime, true): return "Schaue ich"
        case (.current, .manga, false): return "Reading"
        case (.current, .manga, true): return "Lese ich"
        case (.planning, .anime, false): return "Plan to watch"
        case (.planning, .anime, true): return "Will ich schauen"
        case (.planning, .manga, false): return "Plan to read"
        case (.planning, .manga, true): return "Will ich lesen"
        case (.completed, _, false): return "Completed"
        case (.completed, _, true): return "Abgeschlossen"
        default: return DiscoverIssueCopy.statusWord(status, progress: 0, kind: kind, german: german)
        }
    }

    static func spokenMenuLabel(status: ListStatus?, kind: MediaKind, title: String, german: Bool) -> String {
        guard let status else {
            return german ? "\(title) zur Liste hinzufügen" : "Add \(title) to list"
        }
        let word = DiscoverIssueCopy.statusWord(status, progress: 0, kind: kind, german: german)
        return german ? "\(title), \(word). Status ändern" : "\(title), \(word). Change status"
    }

    var body: some View {
        let entry = library.entry(for: card.key)
        let status = entry?.status
        let german = germanOverride ?? KuroLocale.isGerman
        let controller = hostController ?? localController
        Group {
            if guest?.isGuest == true || !TastePlanKey.acceptsTap(suppressCardTaps: suppressCardTaps) {
                Button {
                    guard TastePlanKey.acceptsTap(suppressCardTaps: suppressCardTaps) else { return }
                    KuroAccessibility.impactHaptic(.light)
                    _ = GuestGate.allows(.plan(card.key, title: card.media.title), guest: guest, routes: routes)
                } label: {
                    keyLabel(status: status, controller: controller, german: german)
                }
                .buttonStyle(KuroPressStyle(pressedScale: badge ? 0.94 : 0.97))
            } else {
                Button {
                    guard TastePlanKey.acceptsTap(suppressCardTaps: suppressCardTaps) else { return }
                    KuroAccessibility.impactHaptic(.light)
                    controller.tap(card, library: library, actions: libraryActions, routes: routes, german: german)
                } label: {
                    keyLabel(status: status, controller: controller, german: german)
                }
                .buttonStyle(KuroPressStyle(pressedScale: badge ? 0.94 : 0.97))
            }
        }
        .accessibilityLabel(Self.spokenMenuLabel(status: status, kind: card.media.kind, title: card.media.title, german: german))
        .accessibilityHint(status == nil
                           ? KuroLocale.text("Saves to your list", "Merkt den Titel vor")
                           : "")
        .accessibilityAddTraits(status != nil ? [.isSelected] : [])
        .onChange(of: localController.toast?.id) { _, _ in
            guard hostController == nil, let message = localController.toast?.message else { return }
            banner?.show(message)
        }
    }

    @ViewBuilder
    private func quickStatusMenu(entry: LibraryEntry?, status: ListStatus?, controller: TastePlanController, german: Bool) -> some View {
        let kind = card.media.kind
        let choices: [(ListStatus, String)] = [
            (.current, kind == .manga ? "book" : "play"),
            (.planning, "bookmark"),
            (.completed, "checkmark.circle"),
        ]
        ForEach(choices, id: \.0) { choice, symbol in
            Button {
                KuroAccessibility.impactHaptic(.light)
                controller.setStatus(card, to: choice, library: library, actions: libraryActions, german: german)
            } label: {
                Label(Self.menuChoiceTitle(choice, kind: kind, german: german),
                      systemImage: status == choice ? "checkmark" : symbol)
            }
        }
        if let entry {
            Divider()
            Button {
                KuroAccessibility.impactHaptic(.light)
                routes.presentTrackingEditor(TrackingEditorRequest(media: card.media))
            } label: {
                Label(german ? "Details bearbeiten…" : "Edit details…", systemImage: "slider.horizontal.3")
            }
            if TastePlanController.isBareEntry(entry) {
                Button(role: .destructive) {
                    KuroAccessibility.impactHaptic(.light)
                    controller.removeEntry(card, library: library, actions: libraryActions, german: german)
                } label: {
                    Label(german ? "Von Liste entfernen" : "Remove from list", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func keyLabel(status: ListStatus?, controller: TastePlanController, german: Bool) -> some View {
        if badge {
            badgeFace(status: status, controller: controller)
        } else if variant == .landscape {
            landscapeFace(status: status, controller: controller, german: german)
        } else {
            compactPillFace(status: status, controller: controller, german: german)
        }
    }

    /// The glyph a tracked badge shows: what the title is on the list as.
    static func badgeSymbol(status: ListStatus?, kind: MediaKind) -> String {
        switch status {
        case nil: return "plus"
        case .planning: return "bookmark.fill"
        case .current, .repeating: return kind == .manga ? "book.fill" : "play.fill"
        case .some: return "checkmark"
        }
    }

    /// The corner quick-add badge (2026-11-20 Discover pass): a 30 pt circle in a 44 pt target that
    /// floats on the cover's bottom-trailing corner. White with a crisp `plus` when the title is not on
    /// the list; near-black with the status glyph once it is. Opens the same 3-choice status menu.
    private func badgeFace(status: ListStatus?, controller: TastePlanController) -> some View {
        let saved = status != nil
        let stamp = TastePlanKey.stampTokens(controller.stampCounts[card.key])
        return ZStack {
            Circle()
                .fill(saved ? Color.kuroControlInk : Color.white)
                .overlay(Circle().strokeBorder(saved ? Color.white.opacity(0.18) : Color.black.opacity(0.16),
                                               lineWidth: saved ? 0.5 : 1))
                .shadow(color: Color.black.opacity(saved ? 0.22 : 0.28), radius: saved ? 4 : 5, y: saved ? 1.5 : 2)
                .frame(width: 30, height: 30)
            ZStack {
                Image(systemName: Self.badgeSymbol(status: status, kind: card.media.kind))
                    .font(.system(size: saved ? 11 : 13, weight: .semibold))
                    .kuroRestore(trigger: stamp.restore)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .kuroConfirmStamp(trigger: stamp.confirm)
            }
            .foregroundStyle(saved ? Color.white : Color.kuroControlInk)
            .accessibilityHidden(true)
            .sensoryFeedback(.success, trigger: stamp.confirm)
            .sensoryFeedback(.warning, trigger: stamp.failure)
        }
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .kuroAnimation(KuroMotion.contact, value: status)
    }

    private func landscapeFace(status: ListStatus?, controller: TastePlanController, german: Bool) -> some View {
        let saved = status != nil
        let stamp = TastePlanKey.stampTokens(controller.stampCounts[card.key])
        let label = Self.landscapeLabel(status: status, kind: card.media.kind, german: german)
        let artRaw = card.bannerURL ?? card.media.imageURL
        let foreground: Color = (saved || onLightSurface) ? .white : .kuroControlInk
        let border: Color = saved
            ? Color.white.opacity(0.26)
            : (onLightSurface ? Color.white.opacity(0.20) : Color.white.opacity(0.92))

        return HStack(spacing: 6) {
            Text(label)
                .font(.kuroCustom(12, weight: .semibold, relativeTo: .caption1, maxSize: 20))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Spacer(minLength: 4)
            ZStack {
                Image(systemName: saved ? "checkmark" : "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .kuroRestore(trigger: stamp.restore)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .kuroConfirmStamp(trigger: stamp.confirm)
            }
            .frame(width: 22, height: 28)
            .accessibilityHidden(true)
            .sensoryFeedback(.success, trigger: stamp.confirm)
            .sensoryFeedback(.warning, trigger: stamp.failure)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background {
            if saved {
                Color.kuroControlInk
            } else if onLightSurface {
                KuroBlurredArtworkFill(
                    raw: artRaw,
                    top: Color(hex: "222634"),
                    bottom: Color(hex: "151821"),
                    leadingScrim: 0.56,
                    trailingScrim: 0.38
                )
            } else {
                KuroBlurredArtworkFill(raw: artRaw, frostedLight: true)
            }
        }
        .clipShape(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(border, lineWidth: 1)
        )
        .kuroAnimation(KuroMotion.contact, value: status)
    }

    private func compactPillFace(status: ListStatus?, controller: TastePlanController, german: Bool) -> some View {
        let action = TastePlanAction.action(for: library.entry(for: card.key))
        let isDarkFace = status == .planning || status == .current || status == .repeating
        let isTrackedOther = status != nil && !isDarkFace
        let label = Self.compactLabel(action: action, status: status, kind: card.media.kind, german: german)
        let stamp = TastePlanKey.stampTokens(controller.stampCounts[card.key])

        return HStack(spacing: 4) {
            if isDarkFace {
                ZStack {
                    Image(systemName: status == .planning ? "bookmark.fill" : (card.media.kind == .manga ? "book.fill" : "play.fill"))
                        .font(.system(size: 8.5, weight: .semibold))
                        .kuroRestore(trigger: stamp.restore)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .kuroConfirmStamp(trigger: stamp.confirm)
                }
                .frame(width: 11, height: 11)
                .accessibilityHidden(true)
                .sensoryFeedback(.success, trigger: stamp.confirm)
                .sensoryFeedback(.warning, trigger: stamp.failure)
            } else {
                Image(systemName: isTrackedOther ? "checkmark" : "plus")
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(label)
                .font(.kuroCustom(10.5, weight: .medium, relativeTo: .caption1, maxSize: 20))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(isDarkFace ? Color.white : Color.kuroInk)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            isDarkFace ? Self.savedLeafFace : (isTrackedOther ? Color.black.opacity(0.055) : Color.white.opacity(0.80)),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .strokeBorder(isDarkFace ? Self.savedLeafFace : Color.black.opacity(0.10), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, minHeight: 44, alignment: trailingAligned ? .trailing : .leading)
        .contentShape(Rectangle())
        .kuroAnimation(KuroMotion.contact, value: status)
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

    /// Open from the long-press menu (lane B already sent `discover_open` with `via: menu`): one tap.
    func noteMenuOpen() { taps += 1 }

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
