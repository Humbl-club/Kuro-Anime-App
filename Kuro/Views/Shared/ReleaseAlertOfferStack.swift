import SwiftUI

// MARK: - Release alert offer slot (W3a)
// The offer row is drawn inside the foot slot a page already has for its own toast (detail toast,
// Collection notice, Home progress toast, Discover / Taste toast, Search banner): one shared stack
// draws the row directly above that toast, in the same overlay. No page gets a second toast slot.
//
// WHICH host draws is decided by what is visible, never by attach order: the pager mounts the selected
// page, its neighbours and every page already visited, and a journey sheet covers the pager without
// detaching those hosts. `ReleaseAlertOfferSlotPolicy.presenter` takes the pager's selected section and
// the topmost presentation layer the root coordinator knows. A host that is not the presenter draws
// nothing, and never binds or expires the offer.

/// The topmost presentation layer (derived by `ReleaseAlertOfferSlotPolicy.topmostLayer`).
enum OfferLayer: Hashable {
    /// Nothing is presented over the pager.
    case pager
    /// A journey (the root one or a header sheet's) and the id of its top page.
    case journey(ObjectIdentifier, top: String)
    /// No host is visible: a cover, a tool, a sheet over a journey page, a foreign or unregistered sheet,
    /// a dismissal in flight, or more than one page-level presentation.
    case blocked
}

/// One attached foot slot and where it lives.
struct OfferHost: Equatable {
    let id: UUID
    /// Pager hosts: their page; journey hosts: nil.
    let section: KuroMainView.Section?
    /// Pager hosts: `.pager`; journey hosts: `.journey(journeyID, top: own page id)`.
    let layer: OfferLayer
}

/// What the topmost-layer rule reads from the coordinator.
struct OfferLayerSnapshot: Equatable {
    var collapse: NavigationCollapsePolicy.Snapshot
    /// The open root journey's navigator.
    var rootJourney: ObjectIdentifier?
    /// Open header sheet layer key -> its journey navigator.
    var sheetJourneys: [String: ObjectIdentifier]
}

enum ReleaseAlertOfferSlotPolicy {
    /// The host that may draw now. `hosts` are in attach order; several matches (should not happen: one
    /// host per page) pick the last attached among them; no match is none (never guess).
    static func presenter(selectedSection: KuroMainView.Section?, topmostLayer: OfferLayer, hosts: [OfferHost]) -> UUID? {
        switch topmostLayer {
        case .blocked:
            return nil
        case .pager:
            guard let selectedSection else { return nil }
            return hosts.last { $0.layer == .pager && $0.section == selectedSection }?.id
        case .journey:
            return hosts.last { $0.layer == topmostLayer }?.id
        }
    }

    /// Pure derivation of the topmost layer.
    static func topmostLayer(_ snapshot: OfferLayerSnapshot) -> OfferLayer {
        let c = snapshot.collapse
        if c.coverOpen || c.dismissalInFlight || c.foreignSheetOpen || c.rootToolOpen { return .blocked }
        let rootJourneyOpen = c.journeyTop != nil
        if (rootJourneyOpen && !c.openSheets.isEmpty) || c.openSheets.count > 1 { return .blocked }
        if rootJourneyOpen {
            if c.journeyToolOpen || !(c.journeySheets[NavigationCollapsePolicy.rootJourney] ?? []).isEmpty { return .blocked }
            guard let journey = snapshot.rootJourney, let top = c.journeyTop else { return .blocked }
            return .journey(journey, top: top.id)
        }
        if let key = c.openSheets.first {
            guard let journey = snapshot.sheetJourneys[key], let top = c.sheetJourneyTops[key] else { return .blocked }
            if c.sheetJourneyTools.contains(key) || !(c.journeySheets[key] ?? []).isEmpty { return .blocked }
            return .journey(journey, top: top.id)
        }
        return .pager
    }
}

extension EnvironmentValues {
    /// The pager section a page is mounted for (set per page in `KuroSectionPager`; nil elsewhere).
    @Entry var kuroPagerSection: KuroMainView.Section? = nil
    /// The id of the journey page a view sits on (set by `JourneyHost`; nil outside a journey).
    @Entry var kuroJourneyPageID: String? = nil
}

/// The page's foot slot: the offer row (when this host is the presenter) above the page's own toast.
struct ReleaseAlertOfferStack<Toast: View>: View {
    private let hasToast: Bool
    private let toast: Toast

    /// `hasToast`: the page has a toast of its own at this moment (the row then does not lead with "Saved.").
    init(hasToast: Bool, @ViewBuilder toast: () -> Toast) {
        self.hasToast = hasToast
        self.toast = toast()
    }

    @Environment(ReleasesStore.self) private var releases: ReleasesStore?
    @Environment(\.kuroNavigation) private var navigation
    @Environment(\.kuroJourney) private var journey
    @Environment(\.kuroJourneyPageID) private var journeyPageID
    @Environment(\.kuroPagerSection) private var pagerSection
    @State private var hostId = UUID()
    @State private var resultLine: String?

    /// Where this host lives. Inside a journey the journey page decides (the pager section can leak into
    /// a sheet through the environment); a journey without a page id has no place.
    private var place: OfferHost? {
        if let journey {
            guard let journeyID = journey.journeyID, let pageID = journeyPageID else { return nil }
            return OfferHost(id: hostId, section: nil, layer: .journey(journeyID, top: pageID))
        }
        guard let pagerSection else { return nil }
        return OfferHost(id: hostId, section: pagerSection, layer: .pager)
    }

    private var offer: ReleaseAlertOffer? {
        guard navigation?.isOfferPresenter(hostId) == true else { return nil }
        return releases?.visibleAlertOffer(forPresenter: hostId)
    }

    var body: some View {
        let german = KuroLocale.isGerman
        let offer = offer
        VStack(spacing: 6) {
            if let resultLine {
                TastePlanToastView(message: resultLine, showsUndo: false, german: german, onUndo: {}, onDismiss: { self.resultLine = nil })
            } else if let offer {
                ReleaseAlertOfferRow(
                    prompt: ReleaseAlertOfferCopy.prompt(offer.item, german: german),
                    leadsWithSaved: !hasToast, german: german,
                    onNotify: { accept(offer) },
                    onNotNow: { releases?.declineAlertOffer(offer.id) })
                    .padding(.horizontal, 13)
                    .padding(.bottom, hasToast ? 0 : 12)
            }
            toast
        }
        .overlay { hostProbe }
        .task(id: offer?.id) { await hold(offer) }
    }

    /// A zero-size marker that registers this slot (an empty stack may draw nothing at all).
    private var hostProbe: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { if let place { navigation?.attachOfferHost(place) } }
            .onChange(of: place) { _, new in
                if let new { navigation?.attachOfferHost(new) } else { navigation?.detachOfferHost(hostId) }
            }
            .onDisappear { navigation?.detachOfferHost(hostId) }
    }

    /// Binds the offer to this host and, without assistive technology, lets it go after the hold. A
    /// cancelled sleep (this host stopped being the presenter) returns without expiring it.
    private func hold(_ offer: ReleaseAlertOffer?) async {
        guard let offer, let releases else { return }
        releases.alertOfferPresented(offer.id, by: hostId)
        guard !KuroToastHold.assistiveTechnologyRunning() else { return }
        do { try await Task.sleep(for: .seconds(ReleaseAlertOfferPolicy.hold)) } catch { return }
        releases.expireAlertOffer(offer.id, by: hostId)
    }

    private func accept(_ offer: ReleaseAlertOffer) {
        guard let releases else { return }
        Task { @MainActor in
            let german = KuroLocale.isGerman
            let change: DetailReminderRule.Change
            switch await releases.acceptAlertOffer(offer.id) {
            case .enabled?, nil: return
            case .permissionDenied?: change = .denied
            case .disabled?: change = .off
            case .signedOut?: change = .failed
            }
            resultLine = DetailReminderRule.toast(change, german: german)
            try? await Task.sleep(for: .seconds(3))
            resultLine = nil
        }
    }
}

/// The offer: "Notify me when episode N airs" with two 44 pt text buttons, in the family of
/// `TastePlanToastView` (same fill, radius and type). Buttons move under the text when the row does not
/// fit on one line (German at 320 pt, large type).
struct ReleaseAlertOfferRow: View {
    let prompt: String
    let leadsWithSaved: Bool
    let german: Bool
    let onNotify: () -> Void
    let onNotNow: () -> Void

    private var message: String {
        leadsWithSaved ? "\(ReleaseAlertOfferCopy.saved(german: german)) \(prompt)" : prompt
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                Text(message)
                    .font(.kuroCustom(12, relativeTo: .footnote, maxSize: 22))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                buttons
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(message)
                    .font(.kuroCustom(12, relativeTo: .footnote, maxSize: 22))
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 9)
                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    buttons
                }
            }
        }
        .padding(.leading, 14)
        .padding([.top, .bottom, .trailing], 5)
        .background(Color(hex: "282F2B", opacity: Double(0xF5) / 255),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color(hex: "18241C", opacity: Double(0x30) / 255), radius: 15, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("release-alert-offer")
        .onAppear { AccessibilityNotification.Announcement(message).post() }
    }

    private var buttons: some View {
        HStack(spacing: 0) {
            Button(action: onNotNow) { label(ReleaseAlertOfferCopy.notNow(german: german), weight: .regular) }
                .buttonStyle(KuroPressStyle(pressedScale: 0.97))
                .accessibilityIdentifier("release-alert-offer-not-now")
            Button(action: onNotify) { label(ReleaseAlertOfferCopy.notifyMe(german: german), weight: .semibold) }
                .buttonStyle(KuroPressStyle(pressedScale: 0.97))
                .accessibilityIdentifier("release-alert-offer-notify")
        }
        .fixedSize()
    }

    private func label(_ text: String, weight: Font.Weight) -> some View {
        Text(text)
            .font(.kuroCustom(12, weight: weight, relativeTo: .footnote, maxSize: 22))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

extension View {
    /// A host with no toast of its own (Search's banner position): the offer row alone, above the content's foot.
    func releaseAlertOfferHost() -> some View {
        overlay(alignment: .bottom) { ReleaseAlertOfferStack(hasToast: false) { EmptyView() } }
    }
}
