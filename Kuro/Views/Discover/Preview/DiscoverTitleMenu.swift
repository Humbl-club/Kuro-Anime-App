import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - The long-press preview + menu on every Discover title card (spec 2026-11-04 §5.2, R3, R5)
// `.discoverTitleMenu(item)` gives a card the lifted preview (`DiscoverTitlePreview`) and the five
// items, in fixed order, none drawn destructive (red is kept for delete and leave):
//   1. the Plan item, mirroring the Plan key (`TastePlanAction`: plan / unplan / edit)  `bookmark`
//   2. Seen it / Already read (+ subtitle)                                           `eye`
//   3. Not interested (+ subtitle)                                                   `nosign`
//   4. Add to club… (only when the viewer is in a club)                              `person.2`
//   5. Open                                                                          `arrow.up.forward`
// 2 and 3 are left out when the title is on the viewer's list or nobody is signed in. The same
// actions are VoiceOver custom actions on the element the modifier is applied to, so nothing depends
// on a long press. Every route is read from `\.kuroRoutes`, so the pager's tap gate applies on pager
// pages; the menu also honours `\.kuroSuppressCardTaps`.
//
// Interface note (data lane as merged, 2026-11-04): answers go through `TasteStore`
// (`recordDiscoverFeedback` / `undoDiscoverFeedback`), so `onHidden` hands the page a
// `DiscoverFeedbackReceipt` (spec §11 named `DiscoverHideReceipt`). Franchise keys are the page's
// business (`DiscoveryStore.franchiseKeys(for:title:)`): the menu hides one title.

struct DiscoverMenuItem {
    /// The Plan key's card (media + key).
    let card: TasteCard
    /// The section id (`EditorialDiscoverRoute.id`, "tonightShelf", "hiddenGem", a journey's id).
    let section: String
    /// The card's position in its section (0-based), for telemetry.
    let position: Int
    /// "Why it's here" text (already localized), shown in the preview.
    let reason: String?
    /// The section's name for the preview kicker ("New to you"); nil: the medium only.
    var sectionTitle: String? = nil
    /// The telemetry surface: "discover", "discover_see_all" or "discover_mood".
    var surface: String = "discover"
    /// The page's refill hook, called after a hide was recorded.
    var onHidden: (DiscoverFeedbackReceipt) -> Void = { _ in }
}

/// What the menu offers for one title (pure; DUpreviewTests).
struct DiscoverMenuOffer: Equatable {
    let plan: TastePlanAction
    /// Seen it and Not interested: only for a title not on the list, with a session.
    let answers: Bool
    let addToClub: Bool

    static func offer(entry: LibraryEntry?, signedIn: Bool, inAClub: Bool) -> DiscoverMenuOffer {
        DiscoverMenuOffer(plan: TastePlanAction.action(for: entry), answers: signedIn && entry == nil, addToClub: inAClub)
    }
}

private struct DiscoverTitleMenuModifier: ViewModifier {
    let item: DiscoverMenuItem

    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @Environment(TasteStore.self) private var taste
    @Environment(ClubsStore.self) private var clubs
    @Environment(CatalogStore.self) private var catalog
    @Environment(ArtworkMaterialStore.self) private var materials: ArtworkMaterialStore?
    @Environment(TastePlanController.self) private var hostPlans: TastePlanController?
    @Environment(DiscoverFeedbackController.self) private var hostFeedback: DiscoverFeedbackController?
    @Environment(InteractionTelemetry.self) private var telemetry: InteractionTelemetry?
    @Environment(BannerCenter.self) private var banner: BannerCenter?
    @Environment(\.kuroRoutes) private var routes
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A card outside any host keeps its own controllers; its results go to the app banner (no Undo).
    @State private var localPlans = TastePlanController()

    private var german: Bool { KuroLocale.isGerman }
    private var key: MediaKey { item.card.key }
    private var plans: TastePlanController { hostPlans ?? localPlans }

    private var offer: DiscoverMenuOffer {
        DiscoverMenuOffer.offer(entry: library.entry(for: key),
                                signedIn: libraryActions.accountSession.current != nil,
                                inAClub: !clubs.myClubs.isEmpty)
    }

    func body(content: Content) -> some View {
        let offer = offer
        let medium = item.card.media.kind
        content
            .contextMenu {
                Button { plan() } label: {
                    Label(DiscoverMenuCopy.planItem(offer.plan, medium: medium, german: german), systemImage: "bookmark")
                }
                if offer.answers {
                    Button { answer(.seenIt) } label: {
                        Label(DiscoverMenuCopy.seenIt(medium: medium, german: german), systemImage: "eye")
                        Text(DiscoverMenuCopy.seenItSubtitle(german: german))
                    }
                    Button { answer(.notInterested) } label: {
                        Label(DiscoverMenuCopy.notInterested(german: german), systemImage: "nosign")
                        Text(DiscoverMenuCopy.notInterestedSubtitle(german: german))
                    }
                }
                if offer.addToClub {
                    Button { addToClub() } label: {
                        Label(DiscoverMenuCopy.addToClub(german: german), systemImage: "person.2")
                    }
                }
                Button { open() } label: {
                    Label(DiscoverMenuCopy.open(german: german), systemImage: "arrow.up.forward")
                }
            } preview: {
                DiscoverTitlePreview(card: item.card, section: item.sectionTitle, reason: item.reason,
                                     onShown: trackPreview)
                    .environment(catalog)
                    .environment(materials)
            }
            .accessibilityAction(named: Text(DiscoverMenuCopy.spokenPlan(offer.plan, medium: medium, german: german))) { plan() }
            .accessibilityActions {
                if offer.answers {
                    Button(DiscoverMenuCopy.seenIt(medium: medium, german: german)) { answer(.seenIt) }
                    Button(DiscoverMenuCopy.notInterested(german: german)) { answer(.notInterested) }
                }
                if offer.addToClub {
                    Button(DiscoverMenuCopy.addToClub(german: german)) { addToClub() }
                }
            }
            .onChange(of: localPlans.toast?.id) { _, _ in
                guard hostPlans == nil, let message = localPlans.toast?.message else { return }
                banner?.show(message)
            }
    }

    // MARK: Actions

    private var context: DiscoverFeedbackController.Context {
        DiscoverFeedbackController.Context(surface: item.surface, section: item.section, position: item.position)
    }

    private func plan() {
        guard !suppressCardTaps else { return }
        KuroAccessibility.impactHaptic(.light)
        hostFeedback?.noteMenuPlan(key)
        plans.tap(item.card, library: library, actions: libraryActions, routes: routes, german: german)
    }

    private func answer(_ feedback: DiscoverFeedback) {
        guard !suppressCardTaps else { return }
        KuroAccessibility.impactHaptic(.rigid)
        let record = {
            if let hostFeedback {
                return hostFeedback.record(feedback, for: item.card.media, taste: taste, german: german,
                                           context: context, telemetry: telemetry)
            }
            let receipt = taste.recordDiscoverFeedback(feedback, for: key)
            if receipt != nil {
                banner?.show(DiscoverMenuCopy.toast(feedback, german: german))
                if let telemetry {
                    telemetry.trackInteractionEvent(
                        feedback == .notInterested ? "discover_not_interested" : "discover_seen",
                        surface: item.surface, result: feedback == .notInterested ? "hidden" : "marked",
                        extra: DiscoverMenuTelemetry.titleExtra(section: item.section, position: item.position, key: key))
                }
            }
            return receipt
        }
        // The title leaves its list at once: shrink + fade over `contact`, the gap closing over
        // `settle`; a cross-fade under Reduce Motion / Low Power.
        let receipt: DiscoverFeedbackReceipt?
        if KuroMotion.playsMotionNow(reduceMotion: reduceMotion) {
            receipt = withAnimation(KuroMotion.settle) { record() }
        } else {
            receipt = withAnimation(.linear(duration: 0.12)) { record() }
        }
        if let receipt { item.onHidden(receipt) }
    }

    private func addToClub() {
        guard !suppressCardTaps else { return }
        KuroAccessibility.impactHaptic(.light)
        routes.presentAddToClub(key)
    }

    private func open() {
        guard !suppressCardTaps else { return }
        KuroAccessibility.impactHaptic(.light)
        telemetry?.trackInteractionEvent(
            "discover_open", surface: item.surface, result: "opened",
            extra: DiscoverMenuTelemetry.titleExtra(section: item.section, position: item.position, key: key)
                .merging(["via": "menu"]) { _, new in new })
        routes.openMedia(MediaRoute(key))
    }

    private func trackPreview() {
        telemetry?.trackInteractionEvent(
            "discover_preview", surface: item.surface, result: "shown",
            extra: ["section": item.section, "media_type": key.kind.rawValue.uppercased(), "media_id": key.id])
    }
}

extension View {
    /// Preview + the five-item menu + VoiceOver actions (spec §5.2). Reads `TastePlanController`,
    /// `DiscoverFeedbackController` (both optional: `discoverFeedbackHost`), `TasteStore`,
    /// `LibraryStore`, `ClubsStore` and `\.kuroRoutes` from the environment. Apply it to the card's
    /// open element (the one VoiceOver focuses), not to its Plan key.
    func discoverTitleMenu(_ item: DiscoverMenuItem) -> some View {
        modifier(DiscoverTitleMenuModifier(item: item))
    }
}
