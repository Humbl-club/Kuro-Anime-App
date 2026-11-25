import KuroCore
import KuroLibrary
import SwiftUI
import UIKit

#if DEBUG
// Debug mode: Set this to true to see spacing visualization
let SHOW_SPACING_DEBUG = false
#endif

// MARK: - Type Aliases
// (Removed)

// MARK: - Utility Functions
fileprivate func pixelAlign(_ value: CGFloat, scale: CGFloat = 3.0) -> CGFloat {
    return floor(value * scale) / scale
}

// MARK: - KURO APP - Single Source of Truth
// "Elevated Minimalism" / "Editorial Minimalism" Design System

// MARK: - Content View
struct ContentView: View {
    @Binding var pendingDeepLink: DeepLink?

    var body: some View {
        KuroRootView(pendingDeepLink: $pendingDeepLink)
    }
}

// MARK: - Root View with Launch
struct KuroRootView: View {
    @Binding var pendingDeepLink: DeepLink?
    @State private var showLaunchOverlay = true
    @State private var launchOpacity: Double = 1
    @State private var launchDismissTask: Task<Void, Never>? = nil
    /// The app root's presenter + deep-link collapse (navigation contract N10; UI state only).
    @State private var navigation = KuroNavigationCoordinator()
    /// The session's open/closed sections (navigation contract F3; UI state only).
    @State private var foldMemory = KuroFoldMemory()
    /// Single root-observed Low Power Mode flag injected into `\.kuroLowPowerMode` so scrolling
    /// cards never spawn per-cell `NotificationCenter` streams.
    @State private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// Optional: test hosts without Releases keep rendering (W3a DEBUG fixture offer only).
    @Environment(ReleasesStore.self) private var releases: ReleasesStore?

    var body: some View {
        ZStack {
            KuroMainView(pendingDeepLink: $pendingDeepLink)
                // The app root's presentation context: pages open as journeys over the pager, and
                // `\.kuroNavigation` gives KuroMainView's deep links their collapse.
                .kuroRootNavigation(navigation)
                .environment(\.kuroFoldMemory, foldMemory)
                .environment(\.kuroLowPowerMode, lowPowerMode)

            if showLaunchOverlay {
                KuroLaunchView()
                    .opacity(launchOpacity)
                    .transition(.opacity)
                    .onAppear {
                        launchDismissTask?.cancel()
                        launchOpacity = 1
                        launchDismissTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 160_000_000)
                            guard !Task.isCancelled else { return }
                            withAnimation(.easeOut(duration: 0.25)) {
                                launchOpacity = 0
                            }
                            try? await Task.sleep(nanoseconds: 260_000_000)
                            guard !Task.isCancelled else { return }
                            showLaunchOverlay = false
                        }
                    }
                    .onDisappear {
                        launchDismissTask?.cancel()
                        launchDismissTask = nil
                    }
            }
        }
        // Keeps every Kuro type role in step with the user's text size while the app runs.
        .kuroDynamicTypeScale()
        .task {
            for await _ in NotificationCenter.default.notifications(named: .NSProcessInfoPowerStateDidChange) {
                lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
        #if DEBUG
        .task {
            // UI tests of the navigation contract (`--kuro-nav-fixture`, see NavigationFixture.swift):
            // once the launch overlay is gone, open the fixture journey on the root presenter.
            guard NavigationFixture.isActive, !NavigationFixture.didOpen else { return }
            try? await Task.sleep(for: .milliseconds(1_200))
            // Never over a deep link that already used the coordinator (a cold launch by URL), and once
            // per process.
            guard !Task.isCancelled, !NavigationFixture.didOpen, navigation.collapseGeneration == 0 else { return }
            NavigationFixture.didOpen = true
            navigation.collapseThenOpen(NavigationFixture.level(1))
        }
        .task {
            // UI tests of the release alert offer (`--kuro-offer-fixture`, W3a): publish one unbound offer
            // once the pager is up; with `--kuro-nav-fixture` only after its journey is presented, so no
            // pager host can bind it in the gap after launch.
            guard ProcessInfo.processInfo.arguments.contains("--kuro-offer-fixture") else { return }
            if NavigationFixture.isActive {
                var waited = 0
                while navigation.journey == nil && waited < 150 {
                    try? await Task.sleep(for: .milliseconds(100))
                    waited += 1
                }
                guard !Task.isCancelled, navigation.journey != nil else { return }
            } else {
                try? await Task.sleep(for: .milliseconds(1_800))
            }
            guard !Task.isCancelled else { return }
            releases?.installFixtureAlertOffer()
        }
        #endif
    }
}

// MARK: - Launch View
/// The launch overlay: the branded page loader (spec §5.4), the KURO wordmark settling letter by
/// letter above the scrub line. Reduce Motion and Low Power show it composed.
struct KuroLaunchView: View {
    var body: some View {
        ZStack {
            Color.kuroCanvasPage.ignoresSafeArea()
            KuroLoadingView(scope: .page)
        }
    }
}

// MARK: - Main View
struct KuroMainView: View {
    @Binding var pendingDeepLink: DeepLink?
    @Environment(LibraryStore.self) private var library
    @Environment(DiscoveryStore.self) private var discovery
    @Environment(ClubsStore.self) private var clubs
    @Environment(CollectionStore.self) private var collection
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(FeatureFlags.self) private var flags
    @Environment(HomeStore.self) private var home
    @Environment(ReleasesStore.self) private var releases
    @Environment(IdentityStore.self) private var identity
    @Environment(GuestSession.self) private var guest: GuestSession?
    @Environment(LibraryActions.self) private var libraryActions
    @Environment(InteractionTelemetry.self) private var interactionTelemetry
    @Environment(BannerCenter.self) private var banner
    @Environment(\.kuroRoutes) private var routes
    /// The root's collapse coordinator (navigation contract N10); nil only in previews/test hosts.
    @Environment(\.kuroNavigation) private var navigation
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Section: Int, CaseIterable {
        case taste, concierge, discover, browse, collection, clubs, home

        var title: String {
            switch self {
            case .taste:
                return "TASTE"
            case .home:
                return "HOME"
            case .concierge:
                return "CONCIERGE"
            case .discover:
                return "DISCOVER"
            case .browse:
                return "BROWSE"
            case .collection:
                return "COLLECTION"
            case .clubs:
                return "CLUBS"
            }
        }

        /// The section's name for VoiceOver (EN/DE).
        var spokenName: String {
            switch self {
            case .taste: return KuroLocale.text("Taste", "Geschmack")
            case .home: return KuroLocale.text("Home", "Start")
            case .concierge: return "Concierge"
            case .discover: return KuroLocale.text("Discover", "Entdecken")
            case .browse: return KuroLocale.text("Browse", "Katalog")
            case .collection: return KuroLocale.text("Collection", "Sammlung")
            case .clubs: return "Clubs"
            }
        }

        /// Five pages. The series-home flag replaces Browse with Home and keeps Taste on the left.
        static func pagerOrder(tasteDeck: Bool, seriesHome: Bool, guest: Bool = false) -> [Section] {
            // W5: a guest sees the live signed-in order with invitation pages; Browse is reached from Discover.
            if guest { return GuestPager.order }
            if seriesHome {
                return [.taste, .home, .discover, .collection, .clubs]
            }
            return tasteDeck
                ? [.taste, .discover, .browse, .collection, .clubs]
                : [.discover, .browse, .collection, .clubs]
        }
    }

	@State private var selection: Section = .discover
	@State private var showProfileSheet = false
	@State private var showSearchSheet = false
    @State private var searchSession = 0
    @State private var pendingSearchScope: EditorialSearchView.SearchScope = .all
	@State private var mountedSections: Set<Section> = [.discover]
	/// Home's new-account decision (`TastePageCopy.latchNewAccount` over the whole Library), held
	/// here so the page background and `HomeView` agree; cleared when the Library leaves `.loaded`.
	@State private var homeNewAccountLatch: Bool?
	/// Taste's selected medium, owned here so the pager and header canvas follow it (amendment 8).
	@State private var tasteMedium: MediaKind = .anime
	/// Discover's issue (All / Anime / Manga), owned here so the pager and header canvas follow it
	/// (Discover + Clubs redesign D3: manga Discover paints the manga canvas under the header too).
	@State private var discoverIssue: EditorialDiscoverView.DiscoverMediaTypeFilter = .all
	/// Discover's scroll position, held here like the issue so both survive journeys (usability R8).
	@State private var discoverScroll = ScrollPosition(edge: .top)
	/// Counts header-title taps on Discover (scroll to top, usability §5.10).
	@State private var discoverTopTick = 0
	/// Per-section scroll-to-top ticks triggered from the header wordmark or section menu.
	@State private var sectionTopTicks: [Section: Int] = [:]
    /// The measured size of the root (`kuro_root`) container: the pager's real width on any device.
    @State private var rootSize: CGSize = .zero
    @State private var suppressCardTaps = false
    /// The same suppression, read by the pages' routes at tap time (`KuroPagerTapGate`).
    @State private var pagerTapGate = KuroPagerTapGate()
    @State private var tapSuppressionResetTask: Task<Void, Never>? = nil
    @State private var didTrackSuppressionThisGesture = false
    @State private var didApplyStartArgument = false
    /// A start argument, a deep link, onboarding or the user's own paging chose the page. From then
    /// on, hydrating the series flags never moves the pager to Home (`pageAfterSeriesHomeChange`).
    @State private var pageChosen = false
    /// The page the flag rule itself selected last (its own selection change is not a choice).
    @State private var autoSelectedPage: Section? = nil
    /// Set on appear from the signed-in account's completion (this tree is keyed by the account).
    @State private var showOnboarding = false
    @State private var edgeBounceOffset: CGFloat = 0
    /// Isolated 120 Hz interactive drag state observed ONLY inside `KuroSectionPager`'s offset layer
    /// so horizontal finger tracking never re-evaluates `KuroMainView`, the header, or any tab page.
    @State private var pagerDrag = KuroPagerDragState()
    @State private var pendingJoinCode: String? = nil
    @State private var pendingConciergePrompt: String? = nil
    @State private var pendingPromptClearTask: Task<Void, Never>? = nil
    @State private var showConciergeSheet = false
    @State private var conciergeSheetPrompt: String? = nil
    /// A deep link that arrived while the onboarding cover was showing: it runs once the cover has
    /// finished closing (N10: the cover finishes first).
    @State private var linkAfterOnboarding: DeepLink? = nil
	// Taste-flagged funnel: [Taste] ← [Discover] → Browse → Collection → Clubs.
    // Flag off restores the legacy order with Concierge at index 0 (one DB UPDATE rollback).
    private var swipeOrder: [Section] {
        Section.pagerOrder(tasteDeck: flags.tasteDeckV1Enabled, seriesHome: flags.seriesHomeNativeV1Enabled,
                           guest: guest?.isGuest == true)
    }

    /// The mountain invitation. A saved anime or manga shelf is the white page instead.
    /// The approved empty-medium invitation, with the page picture behind it. A new account sees the
    /// prototype's new-account block on the plain Home canvas instead (`HomeShelfPolicy.showsNewAccount`).
    private var homeInvitation: Bool {
        guard selection == .home else { return false }
        let kind: MediaKind = home.medium == "manga" ? .manga : .anime
        let other: MediaKind = kind == .manga ? .anime : .manga
        let statuses = library.allEntries.filter { $0.key.kind == kind }.map(\.status)
        let scene = HomeShelfPolicy.scene(
            activeListTypes: home.bundle?.active.map(\.listType) ?? [],
            libraryStatuses: statuses
        )
        guard scene == .invitation else { return false }
        let otherCount = max(library.allEntries.filter { $0.key.kind == other }.count,
                             (other == .manga ? home.manga : home.anime)?.active.count ?? 0)
        let otherOccupied = HomeShelfPolicy.otherMediumOccupied(
            selectedMedium: home.medium,
            animeCount: other == .anime ? otherCount : 0,
            mangaCount: other == .manga ? otherCount : 0)
        return !HomeShelfPolicy.showsNewAccount(
            latched: homeNewAccountLatch,
            onlyPlannedTitles: HomeShelfPolicy.onlyBarePlans(library.allEntries),
            scene: scene, otherMediumOccupied: otherOccupied)
    }

    private func latchHomeNewAccount() {
        homeNewAccountLatch = TastePageCopy.latchNewAccount(current: homeNewAccountLatch,
                                                            loaded: library.loadState == .loaded,
                                                            entryCount: library.allEntries.count)
    }
    private let swipeThreshold: CGFloat = 40

    private var conciergeEditorialV1Enabled: Bool {
        // Concierge has fully migrated to the editorial shell.
        true
    }

    private var hidesHeaderForConcierge: Bool {
        // With the Deck at index 0 the header returns to standard behavior;
        // the concierge hide rule only applies to the legacy (flag-off) pager.
        !flags.tasteDeckV1Enabled && selection == .concierge && conciergeEditorialV1Enabled
    }

    private func sectionFromLaunchArgument(_ raw: String) -> Section? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "taste": return .taste
        case "concierge": return .concierge
        case "discover": return .discover
        case "browse": return .browse
        case "home": return .home
        case "collection": return .collection
        case "clubs": return .clubs
        default: return nil
        }
    }

    // MARK: - Swipe conflict helpers (deduplicated from onChanged/onEnded)

    /// The root container's measured width (0 until the first layout).
    private var rootWidth: CGFloat { rootSize.width }

    private func triggerScrollToTop() {
        KuroAccessibility.impactHaptic(.light)
        if selection == .discover {
            discoverTopTick += 1
        } else {
            sectionTopTicks[selection, default: 0] += 1
        }
    }

    private func commitPagerStep(_ step: Int) {
        guard let currentIndex = swipeOrder.firstIndex(of: selection) else { return }
        let nextIndex = currentIndex + step
        guard swipeOrder.indices.contains(nextIndex) else {
            let hadLiveRubberBand = abs(pagerDrag.offset) > 1
            pagerDrag.isDragging = false
            pagerDrag.offset = 0
            KuroAccessibility.impactHaptic(.rigid)
            guard !reduceMotion, !hadLiveRubberBand else { return }
            let bounceDirection: CGFloat = step > 0 ? -1 : 1
            withAnimation(KuroMotion.contact) {
                edgeBounceOffset = bounceDirection * 12
            }
            withAnimation(KuroMotion.settle.delay(0.12)) {
                edgeBounceOffset = 0
            }
            return
        }
        pagerDrag.isDragging = false
        pagerDrag.offset = 0
        pageChosen = true
        selection = swipeOrder[nextIndex]
        mountedSections.insert(selection)
        KuroAccessibility.impactHaptic(.light)
    }

    private func scheduleTapSuppressionReset(delayNs: UInt64 = 120_000_000) {
        tapSuppressionResetTask?.cancel()
        tapSuppressionResetTask = Task {
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled else { return }
            suppressCardTaps = false
            pagerTapGate.isSuppressed = false
        }
    }
    
    var body: some View {
	        ZStack {
	            if homeInvitation {
	                HomePagePicture(isActive: scenePhase == .active)
	                    .ignoresSafeArea()
	                HomeInvitationWash()
	            } else {
	                selection.canvas(mangaHome: home.medium == "manga", mangaTaste: tasteMedium == .manga,
	                                 mangaDiscover: discoverIssue == .manga).ignoresSafeArea()
	                    .animation(KuroMotion.playsMotionNow(reduceMotion: reduceMotion) ? KuroMotion.medium : nil,
	                               value: selection.canvas(mangaHome: home.medium == "manga", mangaTaste: tasteMedium == .manga,
	                                                       mangaDiscover: discoverIssue == .manga))
	            }

	            VStack(spacing: 0) {
                if !hidesHeaderForConcierge {
                    KuroHeaderNew(
                        selection: $selection,
                        showProfileSheet: $showProfileSheet,
                        showSearchSheet: $showSearchSheet,
                        onOpenSearch: {
                            // Series Home: the selected medium is the default scope (rulebook 14.6).
                            pendingSearchScope = flags.seriesHomeNativeV1Enabled
                                ? (home.medium == "manga" ? .manga : .anime)
                                : .all
                            searchSession += 1
                            showSearchSheet = true
                        },
                        onPicture: homeInvitation,
                        tasteMedium: tasteMedium,
                        discoverIssue: discoverIssue,
                        onTitleTap: { triggerScrollToTop() }
                    )
                }

                // Header-driven pager: keeps sections mounted once visited.
	                GeometryReader { pagerProxy in
	                    KuroSectionPager(
	                        selection: $selection,
	                        mountedSections: $mountedSections,
	                        order: swipeOrder,
                            suppressCardTaps: suppressCardTaps,
                            tapGate: pagerTapGate,
                            pendingConciergePrompt: pendingConciergePrompt,
                            pendingJoinCode: $pendingJoinCode,
                            onOpenImport: { showProfileSheet = true },
                            onFindTitle: { kind in
                                // Find on the empty Home opens Search pre-scoped to that medium.
                                pendingSearchScope = kind == "manga" ? .manga : .anime
                                searchSession += 1
                                showSearchSheet = true
                            },
                            onOpenCollection: {
                                selection = .collection
                                mountedSections.insert(.collection)
                            },
                            onOpenBrowse: {
                                guard swipeOrder.contains(.browse) else { return }
                                selection = .browse
                                mountedSections.insert(.browse)
                            },
                            onImportNavigation: navigateFromImport,
                            onExploreTaste: {
                                guard swipeOrder.contains(.taste) else { return }
                                selection = .taste
                                mountedSections.insert(.taste)
                            },
                            onOpenClubs: {
                                guard swipeOrder.contains(.clubs) else { return }
                                selection = .clubs
                                mountedSections.insert(.clubs)
                            },
                            homeNewAccountLatch: homeNewAccountLatch,
                            tasteMedium: $tasteMedium,
                            discoverIssue: $discoverIssue,
                            discoverScroll: $discoverScroll,
                            discoverTopTick: discoverTopTick,
                            sectionTopTicks: sectionTopTicks,
                            onDiscoverSearch: {
                                // The end block's Search (usability §5.7): the same sheet as the header's,
                                // scoped to the issue, dropped while the pager is mid-swipe (N9).
                                guard !pagerTapGate.isSuppressed else { return }
                                pendingSearchScope = discoverIssue == .manga ? .manga : (discoverIssue == .anime ? .anime : .all)
                                searchSession += 1
                                showSearchSheet = true
                            },
                            bottomInset: pagerProxy.safeAreaInsets.bottom,
                            dragState: pagerDrag
	                    )
                    .offset(x: edgeBounceOffset)
                    .background(Color.clear)
                    // Extend the pager to the screen's bottom edge; individual sections restore
                    // `bottomInset` cleanly inside the pager.
                    .ignoresSafeArea(.container, edges: .bottom)
                    .background(
                        KuroRootPagerPanOverlay(
                            isEnabled: keyboardShortcutsEnabled,
                            swipeThreshold: swipeThreshold,
                            onSuppressTaps: {
                                guard flags.isSwipeTapGuardEnabled else { return }
                                if !suppressCardTaps {
                                    suppressCardTaps = true
                                }
                                pagerTapGate.isSuppressed = true
                                if !didTrackSuppressionThisGesture {
                                    didTrackSuppressionThisGesture = true
                                    interactionTelemetry.trackInteractionEvent(
                                        "card_tap_suppressed_during_swipe",
                                        surface: "root_pager",
                                        result: "active"
                                    )
                                }
                            },
                            onSwipeEnded: { fastFlick in
                                didTrackSuppressionThisGesture = false
                                guard flags.isSwipeTapGuardEnabled else {
                                    suppressCardTaps = false
                                    pagerTapGate.isSuppressed = false
                                    return
                                }
                                if suppressCardTaps {
                                    let delayNs: UInt64 = fastFlick ? 280_000_000 : 120_000_000
                                    scheduleTapSuppressionReset(delayNs: delayNs)
                                }
                            },
                            onCommitDirection: { step in
                                commitPagerStep(step)
                            },
                            onDragChanged: { dx in
                                guard !reduceMotion else { return }
                                pagerDrag.isDragging = true
                                pagerDrag.offset = dx
                            },
                            onDragCancelled: {
                                pagerDrag.isDragging = false
                                pagerDrag.offset = 0
                            }
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    )
                }
            }
        }
        .background {
            if keyboardShortcutsEnabled {
                keyboardShortcutCommands
            }
        }
	        .coordinateSpace(name: "kuro_root")
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                rootSize = size
            }
            .environment(\.kuroPagerWidth, rootSize.width)
            .onAppear { latchHomeNewAccount() }
            .onChange(of: library.loadState) { _, state in
                // Leaving `.loaded` (sign-out, account switch, reload) ends the decision; it is made
                // again from the next account's first load.
                if state != .loaded { homeNewAccountLatch = nil }
                latchHomeNewAccount()
            }
            .onAppear {
                // Debug support: launch directly into Concierge for screenshots or manual QA.
                // Example: `xcrun simctl launch booted com.Kuro.app --args --kuro-start=concierge`
                guard !didApplyStartArgument else { return }
                didApplyStartArgument = true
                let args = ProcessInfo.processInfo.arguments
                if let kv = args.first(where: { $0.hasPrefix("--kuro-start=") }),
                   let value = kv.split(separator: "=", maxSplits: 1).last
                {
                    let raw = String(value).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if raw == "concierge" && !swipeOrder.contains(.concierge) {
                        // Archived concierge opens as a sheet when the Deck owns index 0.
                        pageChosen = true
                        conciergeSheetPrompt = nil
                        showConciergeSheet = true
                    } else if let target = sectionFromLaunchArgument(raw) {
                        pageChosen = true
                        selection = target
                        mountedSections.insert(target)
                    }
                } else if args.contains("--kuro-start-concierge") {
                    pageChosen = true
                    if !swipeOrder.contains(.concierge) {
                        conciergeSheetPrompt = nil
                        showConciergeSheet = true
                    } else {
                        selection = .concierge
                        mountedSections.insert(.concierge)
                    }
                } else if flags.seriesHomeNativeV1Enabled, !pageChosen {
                    autoSelect(.home)
                }
            }
            .onChange(of: home.medium) { _, newMedium in
                let targetKind: MediaKind = newMedium == "manga" ? .manga : .anime
                if tasteMedium != targetKind {
                    tasteMedium = targetKind
                }
                if UserDefaults.standard.string(forKey: "kuro.folio.medium") != newMedium {
                    UserDefaults.standard.set(newMedium, forKey: "kuro.folio.medium")
                }
            }
            .onChange(of: tasteMedium) { _, newKind in
                let raw = newKind.rawValue
                if home.medium != raw {
                    home.selectMedium(raw)
                }
                if UserDefaults.standard.string(forKey: "kuro.folio.medium") != raw {
                    UserDefaults.standard.set(raw, forKey: "kuro.folio.medium")
                }
            }
            .onChange(of: selection, initial: true) { _, newValue in navigation?.pagerSelection = newValue }
	            .onChange(of: selection) { _, newValue in
                    // Any page change the flag rule did not make itself is a choice (paging, header,
                    // VoiceOver adjust, onboarding, import navigation, Profile's Collection link).
                    if newValue != autoSelectedPage { pageChosen = true }
                    autoSelectedPage = nil
	                mountedSections.insert(newValue)
                    if newValue == .clubs {
                        clubs.clearClubNotificationBadge()
                    }
	            }
	            .task {
	                // Warm the Discover bundle and daily feature concurrently so the first Discover render feels instant.
                async let bundleWarm = discovery.ensureDiscoverBundle(limit: 30, hours: 24)
                async let dailyWarm: DailyFeature? = guest?.isGuest == true ? nil : discovery.fetchDailyFeature()
                async let clubsWarm: Void = clubs.checkClubNotifications()
                _ = await (bundleWarm, dailyWarm, clubsWarm)
            }
            // Profile and Search are journeys (navigation contract §1): one sheet hosting a stack;
            // every tap inside pushes, ✕ / swipe-down collapses the whole sheet.
            .sheet(isPresented: $showProfileSheet) {
                ShellJourneyHost(root: ShellJourneyPages.profile(
                    onImportNavigation: navigateFromImport,
                    onOpenCollection: {
                        // N11: Collection cannot be shown inside the journey (one shared feed); the
                        // sheet collapses like ✕, then the pager switches.
                        collapseThen {
                            selection = .collection
                            mountedSections.insert(.collection)
                        }
                    }
                ), layer: "profile")
            }
            .kuroNavigationLayer("profile", isPresented: $showProfileSheet)
            .sheet(isPresented: $showSearchSheet) {
                ShellJourneyHost(root: ShellJourneyPages.search(scope: pendingSearchScope), layer: "search")
                    .id(searchSession)
            }
            .kuroNavigationLayer("search", isPresented: $showSearchSheet)
            .onDisappear {
                tapSuppressionResetTask?.cancel()
            }
            // W5: the title a guest tried to track or add to a club re-opens once, for the same account.
            // Observation, not `onAppear`: the replay sets the key after this tree appeared.
            .onChange(of: guest?.reopenAfterSignUp?.key, initial: true) { _, _ in
                guard let guest, let key = guest.takeReopenTitle(for: libraryActions.accountSession.current) else { return }
                if let navigation { navigation.collapseThenOpen(.media(MediaRoute(key))) } else { routes.openMedia(MediaRoute(key)) }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, guest?.isGuest != true else { return }
                home.invalidateClubContent()
                Task {
                    await home.drain()
                    if flags.seriesHomeNativeV1Enabled { await home.load() }
                    // Elapsed releases drop out and the next unit is read (cheap: 5-minute cache).
                    await releases.refreshScheduleIfStale()
                }
            }
            .onChange(of: networkMonitor.reconnectionGeneration) { _, _ in
                guard networkMonitor.isConnected, guest?.isGuest != true else { return }
                Task {
                    await home.drain()
                    switch selection {
                    case .collection:
                        try? await library.refresh()
                        await collection.fetchCollectionFeed(status: nil)
                    case .clubs:
                        await clubs.checkClubNotifications()
                    case .home:
                        await home.load()
                        await home.drain()
                    case .discover, .concierge, .browse, .taste:
                        // Discover reloads itself after a failed or empty load.
                        break
                    }
                }
            }
            .onChange(of: pendingDeepLink) { _, link in
                guard let link else { return }
                pendingDeepLink = nil
                handleDeepLink(link)
            }
            .onChange(of: flags.seriesHomeNativeV1Enabled) { _, enabled in
                // The flags hydrate about 1.4 s after launch: never override a start argument, a deep
                // link or the user's own paging (visual QA), but always leave a page the order lost.
                if let target = Self.pageAfterSeriesHomeChange(
                    enabled: enabled, current: selection, order: swipeOrder, pageChosen: pageChosen
                ) {
                    autoSelect(target)
                }
            }
            .onAppear {
                // A guest never sees onboarding; it runs in the new signed-in tree after sign-up.
                showOnboarding = guest?.isGuest != true && !OnboardingView.hasCompletedOnboarding(for: identity.currentUserId)
                // Consume a link stashed while logged out (or before this view existed);
                // onChange does not fire for a value that was already set.
                if let link = pendingDeepLink {
                    pendingDeepLink = nil
                    handleDeepLink(link)
                }
            }
            .sheet(isPresented: $showConciergeSheet) {
                ShellJourneyHost(root: ShellJourneyPages.concierge(prompt: conciergeSheetPrompt,
                                                                   onImportNavigation: navigateFromImport),
                                 layer: "concierge")
            }
            .kuroNavigationLayer("concierge", isPresented: $showConciergeSheet)
            .fullScreenCover(isPresented: $showOnboarding, onDismiss: {
                // N10: a link that arrived during onboarding runs after the cover has finished closing.
                guard let link = linkAfterOnboarding else { return }
                linkAfterOnboarding = nil
                handleDeepLink(link)
            }) {
                OnboardingView { destination in
                    showOnboarding = false
                    // The Taste page is TastePicksView in both pager orders (spec D7).
                    if destination == .tasteDeck && swipeOrder.contains(.taste) {
                        selection = .taste
                        mountedSections.insert(.taste)
                    }
                }
            }
            .kuroNavigationLayer("onboarding", kind: .cover, isPresented: $showOnboarding)
            if let transientBannerMessage = banner.message {
                VStack {
                    KuroTransientBanner(message: transientBannerMessage)
                        .padding(.top, hidesHeaderForConcierge ? 20 : 10)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
            }
    }

    /// A page the flag rule selects (not a choice; see `pageChosen`).
    private func autoSelect(_ target: Section) {
        guard selection != target else { return }
        autoSelectedPage = target
        selection = target
        mountedSections = [target]
    }

    private func navigateFromImport(_ destination: ImportResultDestination) {
        switch destination {
        case .importedTitles(let keys): collection.showImportedTitles(keys)
        case .fullCollection: collection.clearImportedTitles()
        }
        // N11: the import result lands on the Collection page; whatever is open (Profile, Concierge,
        // a journey) collapses first.
        collapseThen {
            selection = .collection
            mountedSections.insert(.collection)
        }
    }

    /// N10/N11: collapses every open sheet, tool and journey (the onboarding cover first), then runs
    /// `action`. Without a root coordinator (previews) the header sheets close and `action` runs now.
    private func collapseThen(_ action: @escaping () -> Void) {
        if let navigation {
            navigation.collapseThen(action)
        } else {
            showProfileSheet = false
            showSearchSheet = false
            showConciergeSheet = false
            action()
        }
    }

    private func handleDeepLink(_ link: DeepLink) {
        // A link (also one stashed before this view existed) decides the page; hydrating flags won't.
        pageChosen = true
        let linkAction = ShellLinkPolicy.action(for: link, onboardingOpen: showOnboarding,
                                                conciergeInPager: swipeOrder.contains(.concierge))
        // W5: a guest's club and Concierge links open the sign-up sheet instead (the club join is replayed
        // after sign-up); title, Discover and every other link open normally.
        if guest?.isGuest == true {
            switch linkAction {
            case .joinClub(let code):
                collapseThen {
                    selection = .clubs
                    mountedSections.insert(.clubs)
                    _ = GuestGate.allows(.joinClub(code: code), guest: guest, routes: routes)
                }
                return
            case .openJourney(let page):
                if case .club = page {
                    collapseThen {
                        selection = .clubs
                        mountedSections.insert(.clubs)
                        _ = GuestGate.allows(nil, guest: guest, routes: routes)
                    }
                    return
                }
            case .openConciergeSheet, .openConciergePage:
                collapseThen { _ = GuestGate.allows(nil, guest: guest, routes: routes) }
                return
            default:
                break
            }
        }
        switch linkAction {
        case .waitForOnboarding:
            // Replayed from the cover's onDismiss (after its animation), never under it.
            linkAfterOnboarding = link
        case .openJourney(let page):
            // N10: collapse everything, then open the target as a new journey (a target already on
            // top of the open journey keeps it).
            if let navigation { navigation.collapseThenOpen(page) } else { routes.openPage(page) }
        case .switchPage(let page):
            collapseThen {
                selection = page
                mountedSections.insert(page)
            }
        case .openConciergeSheet(let prompt):
            // Archived: Concierge is a sheet; the prompt reaches a fresh ConciergeView's initialPrompt
            // (consumed once on appear).
            collapseThen {
                conciergeSheetPrompt = prompt
                showConciergeSheet = true
            }
        case .openConciergePage(let prompt):
            collapseThen {
                selection = .concierge
                mountedSections.insert(.concierge)
                pendingConciergePrompt = prompt
                // Clear after next runloop so ConciergeView can consume it once
                pendingPromptClearTask?.cancel()
                pendingPromptClearTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard !Task.isCancelled else { return }
                    pendingConciergePrompt = nil
                }
            }
        case .joinClub(let code):
            // ClubsView consumes pendingJoinCode and opens the join sheet prefilled.
            collapseThen {
                selection = .clubs
                mountedSections.insert(.clubs)
                pendingJoinCode = code
            }
        case .none:
            break // Auth callbacks are handled at app level in KuroApp.swift, never reach here
        }
    }
}

extension KuroMainView {
    private var keyboardShortcutsEnabled: Bool {
        !showOnboarding && !showSearchSheet && !showProfileSheet && !showConciergeSheet && navigation?.slot.presented == nil
    }

    @ViewBuilder
    private var keyboardShortcutCommands: some View {
        ZStack {
            Button("") {
                openQuickSearchShortcut()
            }
            .keyboardShortcut("k", modifiers: .command)

            sectionShortcut("1", index: 0)
            sectionShortcut("2", index: 1)
            sectionShortcut("3", index: 2)
            sectionShortcut("4", index: 3)
        }
        .frame(width: 0, height: 0)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func sectionShortcut(_ key: KeyEquivalent, index: Int) -> some View {
        if swipeOrder.indices.contains(index) {
            Button("") {
                let target = swipeOrder[index]
                pageChosen = true
                selection = target
                mountedSections.insert(target)
            }
            .keyboardShortcut(key, modifiers: .command)
        }
    }

    private func openQuickSearchShortcut() {
        switch selection {
        case .discover:
            pendingSearchScope = discoverIssue == .manga ? .manga : (discoverIssue == .anime ? .anime : .all)
        case .home:
            pendingSearchScope = flags.seriesHomeNativeV1Enabled ? (home.medium == "manga" ? .manga : .anime) : .all
        default:
            pendingSearchScope = .all
        }
        searchSession += 1
        showSearchSheet = true
    }

    /// The page after `series_home_native_v1` hydrates or flips; `nil` keeps the current page.
    /// Flag on: Home only while nothing chose a page yet (a start argument, a deep link, onboarding or
    /// the user's own paging win), otherwise only when the current page left the order. Flag off: a
    /// page the live order no longer has (Home) falls back to Discover.
    static func pageAfterSeriesHomeChange(
        enabled: Bool,
        current: Section,
        order: [Section],
        pageChosen: Bool
    ) -> Section? {
        if enabled {
            if !pageChosen { return current == .home ? nil : .home }
            return order.contains(current) ? nil : .home
        }
        return order.contains(current) ? nil : .discover
    }
}

/// Isolated 120 Hz horizontal drag state so live finger-tracking only invalidates the pager's
/// `.offset(x:)` modifier and never re-renders the header or individual section pages.
@MainActor
@Observable
private final class KuroPagerDragState {
    var offset: CGFloat = 0
    var isDragging: Bool = false
}

/// Applies the live pager offset (`-selectionIndex * width + dampedDrag`) in its own view layer so
/// `KuroSectionPager` and its mounted children are not re-evaluated on every drag frame.
private struct KuroPagerOffsetModifier: ViewModifier {
    let selectionIndex: Int
    let pageCount: Int
    let width: CGFloat
    let dragState: KuroPagerDragState
    let reduceMotion: Bool

    private var dampedDragOffset: CGFloat {
        let raw = dragState.offset
        guard raw != 0 else { return 0 }
        let atLeadingEdge = selectionIndex == 0 && raw > 0
        let atTrailingEdge = selectionIndex >= max(0, pageCount - 1) && raw < 0
        if atLeadingEdge || atTrailingEdge {
            // Soft rubber-band resistance at the ends of the pager.
            return raw * 0.24
        }
        return max(-width, min(width, raw))
    }

    func body(content: Content) -> some View {
        let targetX = (-CGFloat(selectionIndex) * width) + dampedDragOffset
        let settleAnimation: Animation? = (reduceMotion || dragState.isDragging)
            ? nil
            : .spring(response: 0.30, dampingFraction: 0.88)
        content
            .offset(x: targetX)
            .animation(settleAnimation, value: selectionIndex)
            .animation(settleAnimation, value: dragState.offset)
    }
}

// MARK: - Interactive section pager (keeps tabs mounted once visited)
private struct KuroSectionPager: View {
    typealias Section = KuroMainView.Section
    @Environment(GuestSession.self) private var guest: GuestSession?

    @Binding var selection: Section
    @Binding var mountedSections: Set<Section>
    let order: [Section]
    let suppressCardTaps: Bool
    /// Drops page opens while the pager is mid-swipe (navigation contract N9).
    let tapGate: KuroPagerTapGate
    var pendingConciergePrompt: String?
    @Binding var pendingJoinCode: String?
    var onOpenImport: () -> Void
    var onFindTitle: (String) -> Void = { _ in }
    var onOpenCollection: () -> Void = {}
    /// Collection's "Find a title" in the live order (the pager's own Browse page; spec D2).
    var onOpenBrowse: () -> Void = {}
    var onImportNavigation: (ImportResultDestination) -> Void
    /// Home's "Explore Taste ←" and the club room's "+N other clubs ›".
    var onExploreTaste: () -> Void = {}
    var onOpenClubs: () -> Void = {}
    /// Home's new-account decision (`KuroMainView.homeNewAccountLatch`).
    var homeNewAccountLatch: Bool?
    /// Taste's selected medium (`KuroMainView.tasteMedium`).
    @Binding var tasteMedium: MediaKind
    /// Discover's issue (`KuroMainView.discoverIssue`).
    @Binding var discoverIssue: EditorialDiscoverView.DiscoverMediaTypeFilter
    /// Discover's scroll position, header scroll-to-top tick and gated Search (`KuroMainView`).
    @Binding var discoverScroll: ScrollPosition
    var discoverTopTick: Int = 0
    var sectionTopTicks: [Section: Int] = [:]
    var onDiscoverSearch: () -> Void = {}
    /// Bottom safe-area inset captured before the pager ignores it. The Deck's art
    /// runs edge-to-edge; every other page gets the inset back as padding.
    var bottomInset: CGFloat = 0
    let dragState: KuroPagerDragState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectionIndex: Int {
        order.firstIndex(of: selection) ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let height = max(1, geo.size.height)

            HStack(spacing: 0) {
                ForEach(order, id: \.self) { section in
                    page(for: section)
                        // Restore the bottom safe-area inset for every pager section so bottom
                        // toasts and scroll ends clear the Home Indicator cleanly.
                        .padding(.bottom, bottomInset)
                        .frame(width: width, height: height)
                        .allowsHitTesting(section == selection)
                        .accessibilityHidden(section != selection)
                }
            }
            .environment(\.kuroSuppressCardTaps, suppressCardTaps)
            .modifier(KuroPagerTapGateModifier(gate: tapGate))
            .modifier(KuroPagerOffsetModifier(
                selectionIndex: selectionIndex,
                pageCount: order.count,
                width: width,
                dragState: dragState,
                reduceMotion: reduceMotion
            ))
            .clipped()
        }
    }

    @ViewBuilder
    private func page(for section: Section) -> some View {
        let sectionIdx = order.firstIndex(of: section) ?? 0
        let distance = abs(selectionIndex - sectionIdx)
        // Keep visited sections warm alongside immediate neighbors so tab switches never tear down
        // and synchronously remount heavy SwiftUI trees mid-transition.
        let shouldMount = mountedSections.contains(section) || distance <= 1

        if shouldMount {
            Group {
                if guest?.isGuest == true, GuestPager.invitationSections.contains(section) {
                    // W5: Taste, Home, Collection and Clubs are accounts' pages; a guest sees an invitation.
                    GuestInvitationPage(section: section)
                } else {
                switch section {
                case .taste:
                    TastePicksView(medium: $tasteMedium, scrollToTopTick: sectionTopTicks[.taste, default: 0])
                case .home:
                    HomeView(onOpenImport: onOpenImport, onFindTitle: onFindTitle,
                             onOpenCollection: onOpenCollection, onImportNavigation: onImportNavigation,
                             onExploreTaste: onExploreTaste, onOpenClubs: onOpenClubs,
                             newAccountLatch: homeNewAccountLatch,
                             scrollToTopTick: sectionTopTicks[.home, default: 0])
                case .concierge:
                    ConciergeView(assistantEnabled: true, initialPrompt: pendingConciergePrompt,
                                  onImportNavigation: onImportNavigation)
                case .discover:
                    EditorialDiscoverView(issue: $discoverIssue, scrollPosition: $discoverScroll,
                                          isCurrent: selection == .discover, scrollToTopTick: discoverTopTick,
                                          onOpenSearch: onDiscoverSearch)
                case .browse:
                    BrowseView()
                case .collection:
                    EditorialCollectionView(onOpenBrowsePage: onOpenBrowse,
                                            scrollToTopTick: sectionTopTicks[.collection, default: 0])
                case .clubs:
                    ClubsView(pendingJoinCode: $pendingJoinCode,
                              scrollToTopTick: sectionTopTicks[.clubs, default: 0])
                }
                }
            }
            // iPad: a readable centred column inside the full-width page (spec D3). iPhone: unchanged.
            .kuroReadableWidth()
            // Which pager page this is: the release alert offer slot draws only on the selected one (W3a).
            .environment(\.kuroPagerSection, section)
        } else {
            // Placeholder keeps layout stable without triggering `.task` in heavy pages.
            Color.kuroBackground
        }
    }
}

/// Soft field over the empty-Home picture. Strong enough to read the header and the type, and open at the bottom so it does not end in a line.
private struct HomeInvitationWash: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.72), location: 0.00),
                .init(color: Color.white.opacity(0.42), location: 0.14),
                .init(color: Color.white.opacity(0.04), location: 0.30),
                .init(color: Color.white.opacity(0.20), location: 0.48),
                .init(color: Color.white.opacity(0.58), location: 0.66),
                .init(color: Color.white.opacity(0.36), location: 0.84),
                .init(color: Color.white.opacity(0.12), location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Header (prototype-fidelity Task 3; PROTOTYPE_SPEC.md §4 "Header", §8.12)
// One header on every pager page in the prototype's style: the KURO wordmark left (SF 18 w800,
// tracking 3, ink), the page name centred in the prototype's small sans (SF 11, muted) with smaller
// position dots under it, and on the right the neighbour link ("‹ Taste" on Home, "Home ›" on Taste,
// SF 12 ink, 44 pt target) followed by Search and Profile as quiet ink glyphs (native additions the
// prototype does not draw). The page name slides on a page change (settle timing; still under
// Reduce Motion). The wordmark steps aside only when the row is too narrow (largest text sizes on the
// narrowest phones); the centre moves off centre only when it would run under the right controls.

/// The header's neighbour link between Home and Taste (pure; tested).
enum KuroHeaderNeighbour {
    /// Home links to Taste and Taste to Home, only when the pager holds both pages.
    static func link(for section: KuroMainView.Section, order: [KuroMainView.Section]) -> KuroMainView.Section? {
        guard order.contains(.home), order.contains(.taste) else { return nil }
        switch section {
        case .home: return .taste
        case .taste: return .home
        default: return nil
        }
    }

    /// "‹ Taste" / "Home ›" (DE "‹ Geschmack" / "Start ›"): the arrow points where the page sits.
    static func title(to target: KuroMainView.Section, german: Bool) -> String {
        switch target {
        case .taste: return german ? "‹ Geschmack" : "‹ Taste"
        case .home: return german ? "Start ›" : "Home ›"
        default: return ""
        }
    }

    /// VoiceOver label: "Go to Taste" / "Go to Home".
    static func spokenTitle(to target: KuroMainView.Section, german: Bool) -> String {
        switch target {
        case .taste: return german ? "Zu Geschmack" : "Go to Taste"
        case .home: return german ? "Zum Start" : "Go to Home"
        default: return ""
        }
    }
}

/// How the header row shares its width (pure given the fonts; tested). The page name stays centred
/// unless it would run under the right controls; then it moves left. Priority when the row is short:
/// the wordmark stays, then the neighbour link steps aside (swipe and the dots still reach Taste), and
/// only when even that is not enough (largest text sizes) does the wordmark step aside too.
struct KuroHeaderRowLayout: Equatable {
    var showsWordmark: Bool
    var showsNeighbour: Bool
    /// How far the centre moves left of the true centre.
    var centreShift: CGFloat

    /// Search and Profile: two 44 pt targets, the trailing inset keeps the glyphs on the gutter.
    static let actionsWidth: CGFloat = 44 * 2 - 6
    /// Breathing room between the wordmark and the centre.
    static let wordmarkGap: CGFloat = 8
    /// The prototype wordmark's tracking (SF 18 w800, tracking 3).
    static let wordmarkTracking: CGFloat = 3

    /// A font size scaled with Dynamic Type for `style`, capped. `traits` nil: the current text size.
    static func scaled(_ size: CGFloat, _ style: UIFont.TextStyle, max cap: CGFloat,
                       traits: UITraitCollection? = nil) -> CGFloat {
        let metrics = UIFontMetrics(forTextStyle: style)
        let value = traits.map { metrics.scaledValue(for: size, compatibleWith: $0) } ?? metrics.scaledValue(for: size)
        return min(value, cap)
    }

    /// The page name's size (the navigation role) at `traits`, or at the current text size.
    static func pageNameSize(traits: UITraitCollection?) -> CGFloat {
        guard let traits else { return KuroTypeRole.navigation.pointSize }
        let spec = KuroTypeRole.navigation.spec
        return scaled(spec.base, spec.style, max: spec.cap, traits: traits)
    }

    /// The centre's width (sized for the longest page name) and the room on each side of it.
    static func metrics(rowWidth: CGFloat, pageNames: [String],
                        traits: UITraitCollection? = nil) -> (centreWidth: CGFloat, sideRoom: CGFloat) {
        let nameSize = pageNameSize(traits: traits)
        let longest = pageNames.map { measure($0, size: nameSize, weight: .regular) }.max() ?? 0
        let centreWidth = max(44, longest + 8)
        return (centreWidth, (rowWidth - centreWidth) / 2)
    }

    /// The width of `text` in the system font.
    static func measure(_ text: String, size: CGFloat, weight: UIFont.Weight, tracking: CGFloat = 0) -> CGFloat {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        let base = (text as NSString).size(withAttributes: [.font: font]).width
        return ceil(base + tracking * CGFloat(max(0, text.count - 1)))
    }

    private struct ResolveCacheKey: Hashable {
        let widthBucket: Int
        let pageNames: [String]
        let neighbourTitle: String?
        let contentSizeCategory: String
        let isBoldTextEnabled: Bool
    }

    @MainActor private static var resolveCache: [ResolveCacheKey: KuroHeaderRowLayout] = [:]

    /// `rowWidth`: the row inside its side padding. `pageNames`: every page name in the pager (the
    /// centre is sized for the longest, so paging never moves it). `neighbourTitle`: the link's text, nil
    /// when the page has none. `traits` measures at that text size (tests); nil uses the current one.
    /// The link is only ever shown with the wordmark, and the shift never exceeds the room beside the
    /// centre, so the page name is never pushed past the leading edge.
    @MainActor
    static func resolve(rowWidth: CGFloat, pageNames: [String], neighbourTitle: String?,
                        traits: UITraitCollection? = nil) -> KuroHeaderRowLayout {
        let cacheKey: ResolveCacheKey? = (traits == nil && rowWidth.isFinite)
            ? ResolveCacheKey(
                widthBucket: Int(floor(rowWidth)),
                pageNames: pageNames,
                neighbourTitle: neighbourTitle,
                contentSizeCategory: UIApplication.shared.preferredContentSizeCategory.rawValue,
                isBoldTextEnabled: UIAccessibility.isBoldTextEnabled
            )
            : nil
        if let cacheKey, let cached = resolveCache[cacheKey] {
            return cached
        }
        let (_, sideRoom) = metrics(rowWidth: rowWidth, pageNames: pageNames, traits: traits)
        let wordmarkWidth = measure("KURO", size: scaled(18, .headline, max: 26, traits: traits), weight: .heavy,
                                    tracking: wordmarkTracking)
        let neighbourWidth = neighbourTitle.map {
            max(44, measure($0, size: scaled(12, .footnote, max: 20, traits: traits), weight: .regular) + 12)
        }
        func fit(rightWidth: CGFloat) -> (fits: Bool, shift: CGFloat) {
            let shift = min(max(0, rightWidth - sideRoom), max(0, sideRoom))
            return (sideRoom - shift - wordmarkGap >= wordmarkWidth, shift)
        }
        let withoutLink = fit(rightWidth: actionsWidth)
        let resolved: KuroHeaderRowLayout
        if let neighbourWidth {
            let withLink = fit(rightWidth: actionsWidth + neighbourWidth)
            if withLink.fits {
                resolved = KuroHeaderRowLayout(showsWordmark: true, showsNeighbour: true, centreShift: withLink.shift)
            } else {
                // The link steps aside first, then (largest text sizes on narrow rows) the wordmark too.
                resolved = KuroHeaderRowLayout(showsWordmark: withoutLink.fits, showsNeighbour: false, centreShift: withoutLink.shift)
            }
        } else {
            resolved = KuroHeaderRowLayout(showsWordmark: withoutLink.fits, showsNeighbour: false, centreShift: withoutLink.shift)
        }
        if let cacheKey {
            if resolveCache.count >= 64 { resolveCache.removeAll() }
            resolveCache[cacheKey] = resolved
        }
        return resolved
    }
}

extension KuroMainView.Section {
    /// The page canvas behind the pager and the header (PROTOTYPE_SPEC.md §2): the warm Home canvas
    /// `#fffef8` on Home and Taste, the manga Home canvas `#f5f5f3` while Home (or Taste, amendment 8:
    /// "Taste follows its reference") shows manga, the white page elsewhere. Taste paints the same
    /// tokens (`TastePageContent.canvas(for:)`), so no seam shows under the header or beside the
    /// readable column on iPad. Discover follows its issue (All and Anime warm, Manga the manga
    /// canvas) and Clubs is warm (Discover + Clubs redesign D2, §5); both pages paint the same tokens.
    func canvas(mangaHome: Bool, mangaTaste: Bool = false, mangaDiscover: Bool = false) -> Color {
        switch self {
        case .home: return mangaHome ? Color.kuroCanvasHomeManga : Color.kuroCanvasHome
        case .taste: return mangaTaste ? Color.kuroCanvasHomeManga : Color.kuroCanvasHome
        case .discover: return mangaDiscover ? Color.kuroCanvasHomeManga : Color.kuroCanvasHome
        case .clubs: return Color.kuroCanvasHome
        default: return Color.kuroBackground
        }
    }
}

struct KuroHeaderNew: View {
    @Binding var selection: KuroMainView.Section
    @Binding var showProfileSheet: Bool
    @Binding var showSearchSheet: Bool
    var onOpenSearch: () -> Void = {}
    /// Empty Home paints the picture through this header. A saved shelf keeps the solid header.
    var onPicture: Bool = false
    /// Taste's medium: manga Taste paints the manga canvas under the header too.
    var tasteMedium: MediaKind = .anime
    /// Discover's issue: manga Discover paints the manga canvas under the header too.
    var discoverIssue: EditorialDiscoverView.DiscoverMediaTypeFilter = .all
    /// While Discover is the page, tapping the centred name scrolls it to the top (usability §5.10).
    var onTitleTap: (() -> Void)? = nil
    @Environment(IdentityStore.self) private var identity
    @Environment(GuestSession.self) private var guest: GuestSession?
    @Environment(\.kuroRoutes) private var routes
    @Environment(SessionController.self) private var session
    @Environment(ClubsStore.self) private var clubs
    @Environment(FeatureFlags.self) private var flags
    @Environment(HomeStore.self) private var home
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Reduce Motion and Low Power show the composed final frame (no slide, no dot travel, no fade).
    private var playsMotion: Bool { KuroMotion.playsMotionNow(reduceMotion: reduceMotion) }

    /// This page's canvas (Home's follows its medium).
    private var canvas: Color {
        selection.canvas(mangaHome: home.medium == "manga", mangaTaste: tasteMedium == .manga,
                         mangaDiscover: discoverIssue == .manga)
    }

    private var swipeOrder: [KuroMainView.Section] {
        KuroMainView.Section.pagerOrder(
            tasteDeck: flags.tasteDeckV1Enabled,
            seriesHome: flags.seriesHomeNativeV1Enabled,
            guest: guest?.isGuest == true
        )
    }

    @State private var displayedSection: KuroMainView.Section = .discover
    @State private var previousSection: KuroMainView.Section? = nil
    @State private var isForwardTransition = true
    @State private var titleProgress: CGFloat = 1.0
    @State private var previousSectionCleanupTask: Task<Void, Never>? = nil
    /// The header row's width inside its side padding (0 until the first layout).
    @State private var rowWidth: CGFloat = 0

    /// Prototype wordmark: SF 18 w800 (tracking `KuroHeaderRowLayout.wordmarkTracking`).
    private static let wordmarkFont = Font.kuroCustom(18, weight: .heavy, relativeTo: .headline, maxSize: 26)
    /// Prototype neighbour link: SF 12 w400.
    private static let neighbourFont = Font.kuroCustom(12, relativeTo: .footnote, maxSize: 20)

    private var neighbour: KuroMainView.Section? {
        KuroHeaderNeighbour.link(for: selection, order: swipeOrder)
    }

    /// "Discover, 3 of 5" plus the Clubs activity note (VoiceOver value of the section control).
    private var sectionAccessibilityValue: String {
        let index = (swipeOrder.firstIndex(of: selection) ?? 0) + 1
        var value = KuroLocale.text("\(selection.spokenName), \(index) of \(swipeOrder.count)",
                                    "\(selection.spokenName), \(index) von \(swipeOrder.count)")
        if clubs.hasUnseenClubActivity && selection != .clubs && swipeOrder.contains(.clubs) {
            value += KuroLocale.text(". New club activity", ". Neue Club-Aktivität")
        }
        return value
    }

    /// Moves the pager one section (VoiceOver adjustable action, Switch Control).
    private func moveSection(by step: Int) {
        guard let index = swipeOrder.firstIndex(of: selection) else { return }
        let next = index + step
        guard swipeOrder.indices.contains(next) else { return }
        selection = swipeOrder[next]
    }

    private var rowLayout: KuroHeaderRowLayout {
        guard rowWidth > 0 else {
            let roomy = !dynamicTypeSize.isAccessibilitySize
            return KuroHeaderRowLayout(showsWordmark: roomy, showsNeighbour: roomy && neighbour != nil, centreShift: 0)
        }
        return KuroHeaderRowLayout.resolve(
            rowWidth: rowWidth,
            pageNames: swipeOrder.map(\.spokenName),
            neighbourTitle: neighbour.map { KuroHeaderNeighbour.title(to: $0, german: KuroLocale.isGerman) }
        )
    }

    private var inkColor: Color { Color.kuroInk }

    /// The centred page name with its position dots: 1-tap section switcher Menu + scroll-to-top,
    /// while remaining one adjustable VoiceOver control.
    private var sectionControl: some View {
        let german = KuroLocale.isGerman
        return Menu {
            if let onTitleTap {
                Button {
                    KuroAccessibility.impactHaptic(.light)
                    onTitleTap()
                } label: {
                    Label(german ? "Nach oben scrollen" : "Scroll to top", systemImage: "arrow.up.to.line")
                }
                Divider()
            }
            ForEach(swipeOrder, id: \.self) { target in
                Button {
                    guard target != selection else {
                        onTitleTap?()
                        return
                    }
                    KuroAccessibility.selectionHaptic()
                    selection = target
                } label: {
                    if target == selection {
                        Label(target.spokenName, systemImage: "checkmark")
                    } else if target == .clubs && clubs.hasUnseenClubActivity {
                        Label(target.spokenName, systemImage: "circle.fill")
                    } else {
                        Text(target.spokenName)
                    }
                }
            }
        } label: {
            VStack(spacing: 5) {
                HStack(spacing: 3) {
                    HeaderPageName(
                        current: displayedSection.spokenName,
                        previous: previousSection?.spokenName,
                        progress: titleProgress,
                        forward: isForwardTransition,
                        onPicture: onPicture
                    )
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(inkColor.opacity(0.45))
                        .accessibilityHidden(true)
                }

                // Position indicators (active pill capsule vs. 3 pt dots).
                HStack(spacing: 4) {
                    ForEach(swipeOrder, id: \.self) { section in
                        ZStack {
                            Capsule(style: .continuous)
                                .fill(section == selection
                                      ? Color.kuroControlInk
                                      : inkColor.opacity(onPicture ? 0.30 : 0.20))
                                .frame(width: section == selection ? 12 : 3, height: 3)

                            // Badge dot for Clubs when unseen activity exists (monochrome).
                            if section == .clubs && clubs.hasUnseenClubActivity && selection != .clubs {
                                Circle()
                                    .fill(Color.kuroControlInk)
                                    .frame(width: 5, height: 5)
                                    .offset(x: 4, y: -3)
                            }
                        }
                    }
                }
                .animation(playsMotion ? KuroMotion.settle : nil, value: selection)
                .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // One adjustable control: VoiceOver swipes up/down (and Switch Control) page the app.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(german ? "\(selection.spokenName), Bereich wählen" : "\(selection.spokenName), switch section")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTitleTap?() }
        .accessibilityValue(sectionAccessibilityValue)
        .accessibilityHint(KuroLocale.text("Tap to jump sections or swipe up or down.",
                                           "Tippen zum Wechseln oder nach oben/unten wischen."))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: moveSection(by: 1)
            case .decrement: moveSection(by: -1)
            @unknown default: break
            }
        }
    }

    @ViewBuilder
    private var neighbourLink: some View {
        if let neighbour {
            Button {
                KuroAccessibility.selectionHaptic()
                selection = neighbour
            } label: {
                Text(KuroHeaderNeighbour.title(to: neighbour, german: KuroLocale.isGerman))
                    .font(Self.neighbourFont)
                    .foregroundStyle(inkColor)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(KuroHeaderIconButtonStyle())
            .accessibilityLabel(KuroHeaderNeighbour.spokenTitle(to: neighbour, german: KuroLocale.isGerman))
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 0) {
            Button(action: {
                KuroAccessibility.impactHaptic(.light)
                onOpenSearch()
            }) {
                // A quiet ink glyph; fixed so it stops growing with the row.
                Image(systemName: "magnifyingglass")
                    .font(.kuroCustom(15, weight: .regular, relativeTo: .body, maxSize: 19))
                    .foregroundStyle(inkColor)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(KuroHeaderIconButtonStyle())
            .keyboardShortcut("f", modifiers: .command)
            .accessibilityLabel(KuroLocale.text("Search", "Suche"))
            .accessibilityHint(KuroLocale.text("Opens search", "Öffnet die Suche"))
            .accessibilityIdentifier("header.search")

            if guest?.isGuest == true {
                // W5: a guest has no profile or sign-out; one "Sign in" opens the sign-up sheet on Sign in.
                Button(KuroLocale.text("Sign in", "Anmelden")) {
                    KuroAccessibility.impactHaptic(.light)
                    _ = GuestGate.allows(nil, guest: guest, routes: routes, mode: .signIn)
                }
                .font(.kuroCustom(13, weight: .medium, relativeTo: .footnote, maxSize: 20))
                .foregroundStyle(inkColor)
                .frame(minWidth: 44, minHeight: 44)
                .buttonStyle(KuroHeaderIconButtonStyle())
                .accessibilityIdentifier("header.signIn")
            } else {
            Menu {
                Button(KuroLocale.text("Profile", "Profil")) {
                    showProfileSheet = true
                }
                Button(KuroLocale.text("Sign out", "Abmelden"), role: .destructive) {
                    Task { await session.signOut() }
                }
            } label: {
                // The account initial in a hairline ink ring: a quiet glyph, not a filled chip.
                Circle()
                    .strokeBorder(inkColor.opacity(0.55), lineWidth: 1)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Text(identity.currentUserInitial)
                            .font(.kuroCustom(11, weight: .medium, relativeTo: .caption1, maxSize: 13))
                            .lineLimit(1)
                            .foregroundStyle(inkColor)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(KuroHeaderIconButtonStyle())
            .accessibilityLabel(KuroLocale.text("Profile", "Profil"))
            .accessibilityHint(KuroLocale.text("Opens account menu", "Öffnet das Kontomenü"))
            }
        }
        .padding(.trailing, -6)
    }

    var body: some View {
        VStack(spacing: 0) {
            let layout = rowLayout
            ZStack {
                HStack(spacing: 0) {
                    if layout.showsWordmark {
                        Button {
                            onTitleTap?()
                        } label: {
                            Text("KURO")
                                .font(Self.wordmarkFont)
                                .tracking(KuroHeaderRowLayout.wordmarkTracking)
                                .foregroundStyle(inkColor)
                                .lineLimit(1)
                                .fixedSize()
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(KuroLocale.text("KURO, scroll to top", "KURO, nach oben scrollen"))
                        .accessibilitySortPriority(3)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 0) {
                        if layout.showsNeighbour {
                            neighbourLink
                        }
                        actionButtons
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilitySortPriority(1)
                }

                sectionControl
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.trailing, layout.centreShift * 2)
                    .accessibilitySortPriority(2)
            }
            // The ZStack declares the section control last; explicit priorities keep the reading
            // order wordmark, section, neighbour link, search, profile.
            .accessibilityElement(children: .contain)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
            .padding(.horizontal, 22)
            .padding(.top, 4)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .onAppear {
                displayedSection = selection
                previousSection = nil
                titleProgress = 1.0
            }
            .onChange(of: selection) { _, newValue in
                let oldIndex = swipeOrder.firstIndex(of: displayedSection) ?? 0
                let newIndex = swipeOrder.firstIndex(of: newValue) ?? 0
                isForwardTransition = newIndex > oldIndex
                previousSection = displayedSection
                displayedSection = newValue

                titleProgress = 0.0
                withAnimation(playsMotion ? KuroMotion.settle : nil) {
                    titleProgress = 1.0
                }

                // Clear the previous name after the slide; avoids layout work.
                previousSectionCleanupTask?.cancel()
                previousSectionCleanupTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 240_000_000)
                    guard !Task.isCancelled else { return }
                    if displayedSection == newValue {
                        previousSection = nil
                    }
                }
            }
            .onDisappear {
                previousSectionCleanupTask?.cancel()
                previousSectionCleanupTask = nil
            }

            // Hairline (`--line`), omitted while the empty-Home picture runs through the header.
            if !onPicture {
                Rectangle()
                    .fill(Color.kuroLine)
                    .frame(height: 0.5)
            }
        }
        // Grows with the text size instead of clipping it.
        .frame(minHeight: 54)
        .background(onPicture ? Color.clear : canvas)
        .animation(playsMotion ? KuroMotion.medium : nil, value: canvas)
    }
}

/// The page name in the prototype's small sans (SF 11, muted), sliding between pages.
private struct HeaderPageName: View {
    let current: String
    let previous: String?
    let progress: CGFloat
    let forward: Bool
    let onPicture: Bool

    private var color: Color { onPicture ? Color.kuroInk : Color.kuroMuted }

    var body: some View {
        let direction: CGFloat = forward ? 1 : -1
        let travel: CGFloat = 24
        ZStack {
            if let previous {
                Text(previous)
                    .font(.kuroNavigation(weight: .regular))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize()
                    .offset(x: -progress * direction * travel)
                    .opacity(1 - progress)
            }
            Text(current)
                .font(.kuroNavigation(weight: .regular))
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
                .offset(x: (1 - progress) * direction * travel)
                .opacity(previous == nil ? 1 : progress)
        }
        .accessibilityHidden(true)
    }
}

/// The prototype's contact on header controls: dimmed to 0.6 and a shallow scale, 120 ms.
private struct KuroHeaderIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .kuroAnimation(KuroMotion.contact, value: configuration.isPressed)
    }
}


// MARK: - Preview
#Preview {
    ContentView(pendingDeepLink: .constant(nil))
        .environment(AppComposition.shared.identity)
        .environment(AppComposition.shared.auth)
        .environment(AppComposition.shared.session)
        .environment(AppComposition.shared.library)
}
