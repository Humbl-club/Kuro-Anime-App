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

    var body: some View {
        ZStack {
            KuroMainView(pendingDeepLink: $pendingDeepLink)
                // The app root's presentation context: pages open as journeys over the pager, and
                // `\.kuroNavigation` gives KuroMainView's deep links their collapse.
                .kuroRootNavigation(navigation)
                .environment(\.kuroFoldMemory, foldMemory)

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
        static func pagerOrder(tasteDeck: Bool, seriesHome: Bool) -> [Section] {
            if seriesHome {
                return [.taste, .home, .discover, .collection, .clubs]
            }
            return tasteDeck
                ? [.taste, .discover, .browse, .collection, .clubs]
                : [.concierge, .discover, .browse, .collection, .clubs]
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
	/// Every swipe-exclusion frame reported in `kuro_root` space (filtered to the viewport on use).
	@State private var swipeExclusions: [CGRect] = []
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
        Section.pagerOrder(tasteDeck: flags.tasteDeckV1Enabled, seriesHome: flags.seriesHomeNativeV1Enabled)
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
    private let swipeEdgeMargin: CGFloat = KuroGesturePolicy.edgeMarginPt

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

    /// The root container's measured width (0 until the first layout; then no drag is excluded).
    private var rootWidth: CGFloat { rootSize.width }

    /// Returns true when the drag starts inside an exclusion zone and is NOT on a screen edge.
    private func isSwipeExcluded(start: CGPoint) -> Bool {
        let edgeAllowed = (start.x <= swipeEdgeMargin) || (start.x >= max(0, rootWidth - swipeEdgeMargin))
        let viewport = CGRect(origin: .zero, size: rootSize)
        let expanded = swipeExclusions.filter { $0.intersects(viewport) }.map { $0.insetBy(dx: -14, dy: -14) }
        return expanded.contains(where: { $0.contains(start) }) && !edgeAllowed
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

    private func isFastFlingOverride(_ value: DragGesture.Value) -> Bool {
        let dx = abs(value.translation.width)
        let dy = abs(value.translation.height)
        let predictedDx = abs(value.predictedEndTranslation.width)
        guard dx > dy * KuroGesturePolicy.fastFlingDirectionRatio else { return false }
        return predictedDx >= KuroGesturePolicy.fastFlingPredictedDxPt
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
                        discoverIssue: discoverIssue
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
                            bottomInset: pagerProxy.safeAreaInsets.bottom
	                    )
	                    .offset(x: edgeBounceOffset)
	                    .background(Color.clear)
	                    // Full-bleed for the Deck: the pager reaches the screen's
	                    // bottom edge; other sections restore the inset as padding.
	                    .ignoresSafeArea(.container, edges: .bottom)
	                }
	            }
	        }
	        .coordinateSpace(name: "kuro_root")
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                rootSize = size
            }
            .environment(\.kuroPagerWidth, rootSize.width)
	        .onPreferenceChange(KuroSwipeExclusionPreferenceKey.self) { v in
	            if v != swipeExclusions {
	                swipeExclusions = v
	            }
	        }
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
	        .simultaneousGesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .named("kuro_root"))
                    .onChanged { value in
                        guard flags.isSwipeTapGuardEnabled else { return }
                        guard !KuroGestureCoordinator.shared.isHorizontalRailDragging else { return }
                        let excluded = isSwipeExcluded(start: value.startLocation)
                        if excluded && !isFastFlingOverride(value) { return }

                        let dx = abs(value.translation.width)
                        let dy = abs(value.translation.height)
                        let predictedDx = abs(value.predictedEndTranslation.width)
                        let velocityHint = abs(value.predictedEndTranslation.width - value.translation.width)
                        guard dx > 12, dx > dy * 1.1 else { return }
                        guard predictedDx > 18 || velocityHint > 20 || dx > 24 else { return }
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
                    }
	                .onEnded { value in
                        let shouldManageSuppression = flags.isSwipeTapGuardEnabled
                        defer { didTrackSuppressionThisGesture = false }
                        if shouldManageSuppression && suppressCardTaps {
                            scheduleTapSuppressionReset()
                        }
                        // Fast intentional flings override BOTH the rail-drag guards
                        // and the exclusion zones — checked first so a full-page
                        // exclusion zone (the deck card rail-marks every horizontal
                        // drag) can never trap paging.
                        let fastFling = isFastFlingOverride(value)
                        if !fastFling {
                            guard !KuroGestureCoordinator.shared.isHorizontalRailDragging else { return }
                            guard !KuroGestureCoordinator.shared.recentlyDraggedRail(withinMs: KuroGesturePolicy.postSwipeTapCooldownMs) else { return }
                            guard !isSwipeExcluded(start: value.startLocation) else { return }
                        }

	                    let dx = value.translation.width
	                    let dy = value.translation.height
	                    guard abs(dx) > abs(dy) * 0.85 else { return }

	                    let predictedDx = value.predictedEndTranslation.width
	                    let effectiveDx = abs(predictedDx) > abs(dx) ? predictedDx : dx
	                    guard abs(effectiveDx) >= swipeThreshold else { return }

	                    guard let currentIndex = swipeOrder.firstIndex(of: selection) else { return }
	                    let nextIndex = currentIndex + (effectiveDx < 0 ? 1 : -1)
	                    guard swipeOrder.indices.contains(nextIndex) else {
	                        KuroAccessibility.impactHaptic(.rigid)
                            // Reduce Motion: the haptic alone marks the edge; no travel.
                            guard !reduceMotion else { return }
	                        let bounceDirection: CGFloat = effectiveDx < 0 ? -1 : 1
	                        // No overshoot (rulebook §8): a short push, then a settle back.
	                        withAnimation(KuroMotion.contact) {
	                            edgeBounceOffset = bounceDirection * 12
	                        }
	                        withAnimation(KuroMotion.settle.delay(0.12)) {
	                            edgeBounceOffset = 0
	                        }
	                        return
	                    }
	                    selection = swipeOrder[nextIndex]
	                    KuroAccessibility.impactHaptic(.light)

                        guard shouldManageSuppression else {
                            suppressCardTaps = false
                            pagerTapGate.isSuppressed = false
                            return
                        }
                        let delayNs: UInt64 = abs(predictedDx) > 220 ? 280_000_000 : 120_000_000
                        scheduleTapSuppressionReset(delayNs: delayNs)
	                }
	        )
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
	                // Warm the Discover bundle so the first Discover render feels instant.
                _ = await discovery.ensureDiscoverBundle(limit: 30, hours: 24)
                // Check club notifications
                await clubs.checkClubNotifications()
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
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                home.invalidateClubContent()
                Task {
                    await home.drain()
                    if flags.seriesHomeNativeV1Enabled { await home.load() }
                    // Elapsed releases drop out and the next unit is read (cheap: 5-minute cache).
                    await releases.refreshScheduleIfStale()
                }
            }
            .onChange(of: networkMonitor.reconnectionGeneration) { _, _ in
                guard networkMonitor.isConnected else { return }
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
                showOnboarding = !OnboardingView.hasCompletedOnboarding(for: identity.currentUserId)
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
        switch ShellLinkPolicy.action(for: link, onboardingOpen: showOnboarding,
                                      conciergeInPager: swipeOrder.contains(.concierge)) {
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

// MARK: - Interactive section pager (keeps tabs mounted once visited)
private struct KuroSectionPager: View {
    typealias Section = KuroMainView.Section

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
    /// Bottom safe-area inset captured before the pager ignores it. The Deck's art
    /// runs edge-to-edge; every other page gets the inset back as padding.
    var bottomInset: CGFloat = 0
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
                        // The Deck keeps the full height (its art reaches the screen's
                        // bottom edge); other pages restore their safe-area edge here.
                        .padding(.bottom, section == .taste ? 0 : bottomInset)
                        .frame(width: width, height: height)
                }
            }
            .environment(\.kuroSuppressCardTaps, suppressCardTaps)
            .modifier(KuroPagerTapGateModifier(gate: tapGate))
            .offset(x: (-CGFloat(selectionIndex) * width))
            .clipped()
            // Animate only when the selection changes (header-driven paging).
            // This avoids gesture conflicts with in-page horizontal carousels.
            .animation(reduceMotion ? nil : .snappy(duration: 0.22, extraBounce: 0.02), value: selectionIndex)
        }
    }

    @ViewBuilder
    private func page(for section: Section) -> some View {
        let sectionIdx = order.firstIndex(of: section) ?? 0
        let distance = abs(selectionIndex - sectionIdx)
        // Mount current page + immediate neighbors; unmount distant pages to save memory.
        let shouldMount = distance <= 1 || mountedSections.contains(section)

        if shouldMount {
            Group {
                switch section {
                case .taste:
                    TastePicksView(medium: $tasteMedium)
                case .home:
                    HomeView(onOpenImport: onOpenImport, onFindTitle: onFindTitle,
                             onOpenCollection: onOpenCollection, onImportNavigation: onImportNavigation,
                             onExploreTaste: onExploreTaste, onOpenClubs: onOpenClubs,
                             newAccountLatch: homeNewAccountLatch)
                case .concierge:
                    ConciergeView(assistantEnabled: true, initialPrompt: pendingConciergePrompt,
                                  onImportNavigation: onImportNavigation)
                case .discover:
                    EditorialDiscoverView(issue: $discoverIssue)
                case .browse:
                    BrowseView()
                case .collection:
                    EditorialCollectionView(onOpenBrowsePage: onOpenBrowse)
                case .clubs:
                    ClubsView(pendingJoinCode: $pendingJoinCode)
                }
            }
            // iPad: a readable centred column inside the full-width page (spec D3). iPhone: unchanged.
            .kuroReadableWidth()
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

    /// `rowWidth`: the row inside its side padding. `pageNames`: every page name in the pager (the
    /// centre is sized for the longest, so paging never moves it). `neighbourTitle`: the link's text, nil
    /// when the page has none. `traits` measures at that text size (tests); nil uses the current one.
    /// The link is only ever shown with the wordmark, and the shift never exceeds the room beside the
    /// centre, so the page name is never pushed past the leading edge.
    static func resolve(rowWidth: CGFloat, pageNames: [String], neighbourTitle: String?,
                        traits: UITraitCollection? = nil) -> KuroHeaderRowLayout {
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
        guard let neighbourWidth else {
            return KuroHeaderRowLayout(showsWordmark: withoutLink.fits, showsNeighbour: false, centreShift: withoutLink.shift)
        }
        let withLink = fit(rightWidth: actionsWidth + neighbourWidth)
        if withLink.fits { return KuroHeaderRowLayout(showsWordmark: true, showsNeighbour: true, centreShift: withLink.shift) }
        // The link steps aside first, then (largest text sizes on narrow rows) the wordmark too.
        return KuroHeaderRowLayout(showsWordmark: withoutLink.fits, showsNeighbour: false, centreShift: withoutLink.shift)
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
    @Environment(IdentityStore.self) private var identity
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
            seriesHome: flags.seriesHomeNativeV1Enabled
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

    /// The centred page name with its position dots: one adjustable VoiceOver control.
    private var sectionControl: some View {
        VStack(spacing: 5) {
            HeaderPageName(
                current: displayedSection.spokenName,
                previous: previousSection?.spokenName,
                progress: titleProgress,
                forward: isForwardTransition,
                onPicture: onPicture
            )

            // Smaller position dots (3 pt).
            HStack(spacing: 4) {
                ForEach(swipeOrder, id: \.self) { section in
                    ZStack {
                        Circle()
                            .fill(section == selection
                                  ? inkColor
                                  : inkColor.opacity(onPicture ? 0.28 : 0.18))
                            .frame(width: 3, height: 3)

                        // Badge dot for Clubs when unseen activity exists (monochrome).
                        if section == .clubs && clubs.hasUnseenClubActivity && selection != .clubs {
                            Circle()
                                .fill(Color.kuroBlack70)
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
        // One adjustable control: VoiceOver swipes up/down (and Switch Control) page the app.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KuroLocale.text("Section", "Bereich"))
        .accessibilityValue(sectionAccessibilityValue)
        .accessibilityHint(KuroLocale.text("Swipe up or down to change sections.",
                                           "Zum Wechseln nach oben oder unten wischen."))
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
            .accessibilityLabel(KuroLocale.text("Search", "Suche"))
            .accessibilityHint(KuroLocale.text("Opens search", "Öffnet die Suche"))

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
        .padding(.trailing, -6)
    }

    var body: some View {
        VStack(spacing: 0) {
            let layout = rowLayout
            ZStack {
                HStack(spacing: 0) {
                    if layout.showsWordmark {
                        Text("KURO")
                            .font(Self.wordmarkFont)
                            .tracking(KuroHeaderRowLayout.wordmarkTracking)
                            .foregroundStyle(inkColor)
                            .lineLimit(1)
                            .fixedSize()
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
