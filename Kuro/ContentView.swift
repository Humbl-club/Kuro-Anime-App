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

    var body: some View {
        ZStack {
            KuroMainView(pendingDeepLink: $pendingDeepLink)
                // The app root's presentation context; KuroMainView's deep links read its routes.
                .routePresenter()

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
    }
}

// MARK: - Launch View
struct KuroLaunchView: View {
    @State private var logoOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    
    var body: some View {
        ZStack {
            Color.kuroBackground.ignoresSafeArea()

            VStack(spacing: 8) {
                Text("KURO")
                    .font(.kuroHeadline(weight: .ultraLight))
                    .tracking(8)
                    .foregroundColor(.kuroBlack)
                    .opacity(logoOpacity)

                Text("CURATED ANIME")
                    .font(.kuroMicro(weight: .light))
                    .tracking(3)
                    .foregroundColor(.kuroTextTertiary)
                    .opacity(subtitleOpacity)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.2)) {
                    logoOpacity = 1.0
                }
                withAnimation(.easeOut(duration: 1.2).delay(0.3)) {
                    subtitleOpacity = 1.0
                }
            }
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
    @Environment(IdentityStore.self) private var identity
    @Environment(InteractionTelemetry.self) private var interactionTelemetry
    @Environment(BannerCenter.self) private var banner
    @Environment(\.kuroRoutes) private var routes
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
	/// Every swipe-exclusion frame reported in `kuro_root` space (filtered to the viewport on use).
	@State private var swipeExclusions: [CGRect] = []
    /// The measured size of the root (`kuro_root`) container: the pager's real width on any device.
    @State private var rootSize: CGSize = .zero
    @State private var suppressCardTaps = false
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
	// Taste-flagged funnel: [Taste] ← [Discover] → Browse → Collection → Clubs.
    // Flag off restores the legacy order with Concierge at index 0 (one DB UPDATE rollback).
    private var swipeOrder: [Section] {
        Section.pagerOrder(tasteDeck: flags.tasteDeckV1Enabled, seriesHome: flags.seriesHomeNativeV1Enabled)
    }

    /// The mountain invitation. A saved anime or manga shelf is the white page instead.
    private var homeInvitation: Bool {
        guard selection == .home else { return false }
        let kind: MediaKind = home.medium == "manga" ? .manga : .anime
        let statuses = library.allEntries.filter { $0.key.kind == kind }.map(\.status)
        return HomeShelfPolicy.scene(
            activeListTypes: home.bundle?.active.map(\.listType) ?? [],
            libraryStatuses: statuses
        ) == .invitation
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
	                Color.kuroBackground.ignoresSafeArea()
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
                        onPicture: homeInvitation
                    )
                }

                // Header-driven pager: keeps sections mounted once visited.
	                GeometryReader { pagerProxy in
	                    KuroSectionPager(
	                        selection: $selection,
	                        mountedSections: $mountedSections,
	                        order: swipeOrder,
                            suppressCardTaps: suppressCardTaps,
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
            .sheet(isPresented: $showProfileSheet) {
                ProfileView(
                    onOpenConciergeImportReview: { prompt in
                        showProfileSheet = false
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            handleDeepLink(.concierge(prompt: prompt))
                        }
                    },
                    onImportNavigation: navigateFromImport,
                    onOpenCollection: {
                        showProfileSheet = false
                        selection = .collection
                        mountedSections.insert(.collection)
                    }
                )
            }
            .sheet(isPresented: $showSearchSheet) {
                NavigationStack {
                    EditorialSearchView(initialScope: pendingSearchScope)
                        .id(searchSession)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(action: { showSearchSheet = false }) {
                                    Image(systemName: "xmark")
                                        .font(.kuroBody(weight: .light))
                                        .foregroundColor(.kuroBlack60)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(KuroLocale.text("Close", "Schließen"))
                            }
                        }
                }
            }
            .onDisappear {
                tapSuppressionResetTask?.cancel()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                home.invalidateClubContent()
                Task {
                    await home.drain()
                    if flags.seriesHomeNativeV1Enabled { await home.load() }
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
                NavigationStack {
                    ConciergeView(assistantEnabled: true, initialPrompt: conciergeSheetPrompt,
                                  onImportNavigation: navigateFromImport)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showConciergeSheet = false }
                                    .font(.kuroBody(weight: .light))
                            }
                        }
                        // The Concierge sheet's own presentation context (ConciergeView reads its routes).
                        .routePresenter()
                }
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView { destination in
                    showOnboarding = false
                    // The Taste page is TastePicksView in both pager orders (spec D7).
                    if destination == .tasteDeck && swipeOrder.contains(.taste) {
                        selection = .taste
                        mountedSections.insert(.taste)
                    }
                }
            }
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
        showProfileSheet = false
        showConciergeSheet = false
        selection = .collection
        mountedSections.insert(.collection)
    }

    private func handleDeepLink(_ link: DeepLink) {
        // A link (also one stashed before this view existed) decides the page; hydrating flags won't.
        pageChosen = true
        switch link {
        case .anime(let id):
            routes.openMedia(MediaRoute(kind: .anime, id: id))
        case .manga(let id):
            routes.openMedia(MediaRoute(kind: .manga, id: id))
        case .club(let id):
            routes.openClub(id)
        case .collection:
            selection = .collection
            mountedSections.insert(.collection)
        case .discover:
            selection = .discover
        case .concierge(let prompt):
            if !swipeOrder.contains(.concierge) {
                // Archived: present Concierge as a sheet; prompt injection is preserved
                // via ConciergeView's initialPrompt (consumed once on appear).
                conciergeSheetPrompt = prompt
                showConciergeSheet = true
            } else {
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
            selection = .clubs
            mountedSections.insert(.clubs)
            pendingJoinCode = code
        case .authCallback:
            break // Handled at app level in KuroApp.swift, never reaches here
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
    var pendingConciergePrompt: String?
    @Binding var pendingJoinCode: String?
    var onOpenImport: () -> Void
    var onFindTitle: (String) -> Void = { _ in }
    var onOpenCollection: () -> Void = {}
    /// Collection's "Find a title" in the live order (the pager's own Browse page; spec D2).
    var onOpenBrowse: () -> Void = {}
    var onImportNavigation: (ImportResultDestination) -> Void
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
                    TastePicksView()
                case .home:
                    HomeView(onOpenImport: onOpenImport, onFindTitle: onFindTitle,
                             onOpenCollection: onOpenCollection, onImportNavigation: onImportNavigation)
                case .concierge:
                    ConciergeView(assistantEnabled: true, initialPrompt: pendingConciergePrompt,
                                  onImportNavigation: onImportNavigation)
                case .discover:
                    EditorialDiscoverView()
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

// MARK: - New Responsive Header Component (Fixed)
struct KuroHeaderNew: View {
    @Binding var selection: KuroMainView.Section
    @Binding var showProfileSheet: Bool
    @Binding var showSearchSheet: Bool
    var onOpenSearch: () -> Void = {}
    /// Empty Home paints the picture through this header. A saved shelf keeps the white header.
    var onPicture: Bool = false
    @Environment(IdentityStore.self) private var identity
    @Environment(SessionController.self) private var session
    @Environment(ClubsStore.self) private var clubs
    @Environment(FeatureFlags.self) private var flags
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var swipeOrder: [KuroMainView.Section] {
        KuroMainView.Section.pagerOrder(
            tasteDeck: flags.tasteDeckV1Enabled,
            seriesHome: flags.seriesHomeNativeV1Enabled
        )
    }

    private static let windowTextPaddingX: CGFloat = 14
    private static let windowTextPaddingY: CGFloat = 7
    private static let windowTextSlack: CGFloat = 10

    @State private var displayedSection: KuroMainView.Section = .discover
    @State private var previousSection: KuroMainView.Section? = nil
    @State private var isForwardTransition = true
    @State private var titleProgress: CGFloat = 1.0
    @State private var titleTextWidth: CGFloat = 92
    @State private var previousSectionCleanupTask: Task<Void, Never>? = nil
    /// The header row's width inside its side padding (0 until the first layout).
    @State private var rowWidth: CGFloat = 0

    private var canSwipeLeft: Bool {
        guard let i = swipeOrder.firstIndex(of: selection) else { return false }
        return i > 0
    }
    private var canSwipeRight: Bool {
        guard let i = swipeOrder.firstIndex(of: selection) else { return false }
        return i < (swipeOrder.count - 1)
    }

    private static let titleTracking: CGFloat = 1.5

    /// Measured with the same scaled size `kuroNavigation` draws with, so long titles never clip
    /// at larger text sizes.
    private static func measureTitleWidth(_ title: String) -> CGFloat {
        let font = UIFont.systemFont(ofSize: KuroTypeRole.navigation.pointSize, weight: .regular)
        let base = (title as NSString).size(withAttributes: [.font: font]).width
        let tracking = titleTracking * CGFloat(max(0, title.count - 1))
        return ceil(base + tracking)
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

    private var titleWindow: some View {
        let hint = (canSwipeLeft || canSwipeRight)
        // Rounded "window" with edge shading (no heavy fill) for a physical mask feel.
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let innerMask = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let titleHeight: CGFloat = ceil(KuroTypeRole.navigation.pointSize * 1.45)
        let travel = (titleTextWidth + (Self.windowTextPaddingX * 2) + 28)

        return ZStack {
            shape
                .fill(Color.clear)
                // Tiny fill keeps the shape "present" so the shadow reads, without tinting the interior.
                .background(shape.fill(onPicture ? Color.white.opacity(0.55) : Color.kuroWhite.opacity(0.001)))
                .overlay(
                    shape
                        .stroke(
                            hint
                                ? (onPicture ? Color.kuroInk.opacity(0.45) : Color.kuroBlack12)
                                : (onPicture ? Color.kuroInk.opacity(0.22) : Color.kuroBlack06),
                            lineWidth: onPicture ? 0.8 : 0.6
                        )
                )
                // Subtle highlight to sell the "window" edge without changing the interior color.
                .overlay(
                    shape
                        .stroke(Color.kuroWhite80, lineWidth: 0.6)
                        .blendMode(.overlay)
                )
                .shadow(color: Color.kuroBlack06, radius: 10, x: 0, y: 6)

            TitleWindowAnimator(
                current: displayedSection.title,
                previous: previousSection?.title,
                progress: titleProgress,
                forward: isForwardTransition,
                travel: travel
            )
            // Keep the window tight to the current word, but during the transition ensure
            // we have enough width for BOTH titles so nothing gets clipped mid-slide.
            .frame(width: max(54, titleTextWidth), height: titleHeight, alignment: .center)
            .padding(.horizontal, Self.windowTextPaddingX)
            .padding(.vertical, Self.windowTextPaddingY)
            // Clip only the moving text layer (cheaper than masking the whole window).
            .clipShape(innerMask)
        }
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityHidden(true)
    }

    /// A 32 pt circle with a 44 pt hit area (rulebook §5 touch targets).
    @ViewBuilder
    private func headerIconCircle<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Circle()
            .fill(onPicture ? Color.white.opacity(0.82) : Color.kuroBlack06)
            .frame(width: 32, height: 32)
            .overlay { content() }
            .overlay(
                Circle().stroke(onPicture ? Color.kuroInk.opacity(0.28) : Color.kuroBlack10, lineWidth: 0.7)
            )
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    /// The two header buttons: 44 pt targets, the trailing inset keeps the circles where they were.
    private static let actionsWidth: CGFloat = 44 * 2 - 6
    /// Breathing room between the wordmark and the section window.
    private static let wordmarkGap: CGFloat = 8

    /// Where the section window sits and whether the wordmark fits beside it. Sized for the longest
    /// title in the order (plus the Concierge mark where it can show), so paging never moves it.
    private var rowLayout: (showsWordmark: Bool, centreShift: CGFloat) {
        guard rowWidth > 0 else { return (!dynamicTypeSize.isAccessibilitySize, 0) }
        let longestTitle = swipeOrder.map { Self.measureTitleWidth($0.title) + Self.windowTextSlack }.max() ?? 0
        var centreWidth = max(54, longestTitle) + Self.windowTextPaddingX * 2
        if swipeOrder.contains(.concierge) && !dynamicTypeSize.isAccessibilitySize { centreWidth += 40 }
        let sideRoom = (rowWidth - centreWidth) / 2
        let shift = max(0, Self.actionsWidth - sideRoom)
        let leftRoom = sideRoom - shift
        let wordmarkWidth = Self.measureTitleWidth("KURO")
        return (leftRoom - Self.wordmarkGap >= wordmarkWidth, shift)
    }

    /// The centred section window with its position dots: one adjustable VoiceOver control.
    private var sectionControl: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                if selection == .concierge && !dynamicTypeSize.isAccessibilitySize {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 30, height: 30)
                        .overlay(
                            Circle().stroke(Color.kuroBlack10, lineWidth: 0.7)
                        )
                        .overlay(
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.kuroCustom(13, weight: .semibold, relativeTo: .caption1))
                                .foregroundColor(.kuroBlack70)
                        )
                        .accessibilityHidden(true)
                }

                titleWindow
            }

            // Dot indicators for positional context
            HStack(spacing: 5) {
                ForEach(swipeOrder, id: \.self) { section in
                    ZStack {
                            Circle()
                            .fill(section == selection
                                  ? (onPicture ? Color.kuroInk : Color.kuroTextSecondary)
                                  : (onPicture ? Color.kuroInk.opacity(0.28) : Color.kuroBlack15))
                            .frame(width: 4, height: 4)

                        // Badge dot for Clubs when unseen activity exists
                        if section == .clubs && clubs.hasUnseenClubActivity && selection != .clubs {
                            Circle()
                                .fill(Color.kuroBlack70)
                                .frame(width: 6, height: 6)
                                .offset(x: 5, y: -3)
                        }
                    }
                }
            }
            .animation(.easeOut(duration: 0.18), value: selection)
            .accessibilityHidden(true)
        }
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

    private var actionButtons: some View {
        HStack(spacing: 0) {
            Button(action: {
                KuroAccessibility.impactHaptic(.light)
                onOpenSearch()
            }) {
                headerIconCircle {
                    // Fixed inside its 32 pt circle: the glyph stops growing where the circle does.
                    Image(systemName: "magnifyingglass")
                        .font(.kuroCustom(13, weight: .regular, relativeTo: .caption1, maxSize: 15))
                        .foregroundColor(onPicture ? Color.kuroInk : Color.kuroBlack60)
                }
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
                headerIconCircle {
                    Text(identity.currentUserInitial)
                        .font(.kuroCustom(12, weight: .medium, relativeTo: .caption1, maxSize: 14))
                        .lineLimit(1)
                        .foregroundColor(onPicture ? Color.kuroInk : Color.kuroBlack80)
                }
            }
            .buttonStyle(KuroHeaderIconButtonStyle())
            .accessibilityLabel(KuroLocale.text("Profile", "Profil"))
            .accessibilityHint(KuroLocale.text("Opens account menu", "Öffnet das Kontomenü"))
        }
        .padding(.trailing, -6)
    }

    var body: some View {
        VStack(spacing: 0) {
            // The section window stays centred on the row at every text size; the wordmark and the two
            // buttons sit on its sides. The wordmark steps aside only when the row is too narrow for it
            // (largest text sizes on the narrowest phones), and the window moves off centre only when
            // it would otherwise run under the buttons.
            let layout = rowLayout
            ZStack {
                HStack(spacing: 0) {
                    if layout.showsWordmark {
                        Text("KURO")
                            .font(.kuroNavigation(weight: onPicture ? .medium : .regular))
                            .tracking(Self.titleTracking)
                            .foregroundColor(onPicture ? Color.kuroInk : Color.kuroTextTertiary)
                            .lineLimit(1)
                            .fixedSize()
                            .accessibilitySortPriority(3)
                    }
                    Spacer(minLength: 0)
                    actionButtons
                        .accessibilityElement(children: .contain)
                        .accessibilitySortPriority(1)
                }

                sectionControl
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.trailing, layout.centreShift * 2)
                    .accessibilitySortPriority(2)
            }
            // The ZStack declares the section control last; explicit priorities keep the reading
            // order wordmark, section, search, profile (as in the former single HStack).
            .accessibilityElement(children: .contain)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
            .padding(.horizontal, 20)
            // 44 pt targets + 5 pt keeps the header at its 54 pt height at the default text size.
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            // The wordmark, the section control and the two buttons stay separate VoiceOver elements.
            .onChange(of: KuroTypeScale.current.category) { _, _ in
                titleTextWidth = Self.measureTitleWidth(displayedSection.title) + Self.windowTextSlack
            }
            .onAppear {
                displayedSection = selection
                previousSection = nil
                titleProgress = 1.0
                titleTextWidth = Self.measureTitleWidth(selection.title) + Self.windowTextSlack
            }
            .onChange(of: selection) { _, newValue in
                let oldIndex = swipeOrder.firstIndex(of: displayedSection) ?? 0
                let newIndex = swipeOrder.firstIndex(of: newValue) ?? 0
                isForwardTransition = newIndex > oldIndex
                let from = displayedSection
                let fromWidth = Self.measureTitleWidth(from.title) + Self.windowTextSlack
                let toWidth = Self.measureTitleWidth(newValue.title) + Self.windowTextSlack

                previousSection = from
                displayedSection = newValue
                titleTextWidth = max(fromWidth, toWidth)

                titleProgress = 0.0
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                    titleProgress = 1.0
                }

                // Clear previous after animation; avoids unnecessary layout work.
                previousSectionCleanupTask?.cancel()
                previousSectionCleanupTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard !Task.isCancelled else { return }
                    if displayedSection == newValue {
                        previousSection = nil
                        withAnimation(.easeOut(duration: 0.12)) {
                            titleTextWidth = toWidth
                        }
                    }
                }
            }
            .onDisappear {
                previousSectionCleanupTask?.cancel()
                previousSectionCleanupTask = nil
            }

            // Subtle divider — omitted only while the empty-Home picture runs through the header.
            if !onPicture {
                Rectangle()
                    .fill(Color.kuroBlack08)
                    .frame(height: 0.5)
            }
        }
        // Grows with the text size instead of clipping it.
        .frame(minHeight: 54)
        .background(onPicture ? Color.clear : Color.kuroBackground)
        .shadow(
            color: onPicture ? Color.clear : Color.kuroBlack08,
            radius: 10,
            x: 0,
            y: 6
        )
    }
}

private struct TitleWindowAnimator: View {
    let current: String
    let previous: String?
    let progress: CGFloat
    let forward: Bool
    let travel: CGFloat

    var body: some View {
        let dir: CGFloat = forward ? 1 : -1

        return ZStack {
            if let previous {
                Text(previous)
                    .font(.kuroNavigation(weight: .regular))
                    .tracking(1.5)
                    .foregroundColor(.kuroBlack)
                    .lineLimit(1)
                    .offset(x: (-progress) * dir * travel)
            }

            Text(current)
                .font(.kuroNavigation(weight: .regular))
                .tracking(1.5)
                .foregroundColor(.kuroBlack)
                .lineLimit(1)
                .offset(x: (1 - progress) * dir * travel)
        }
    }
}

private struct KuroHeaderIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .rotationEffect(.degrees(configuration.isPressed ? -4 : 0))
            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.82), value: configuration.isPressed)
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
