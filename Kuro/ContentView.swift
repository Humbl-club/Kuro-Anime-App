// uses PosterView.swift
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
    @Environment(SupabaseService.self) private var supabaseService

    var body: some View {
        KuroRootView(pendingDeepLink: $pendingDeepLink)
            .environment(supabaseService)
    }
}

// MARK: - Root View with Launch
struct KuroRootView: View {
    @Binding var pendingDeepLink: DeepLink?
    @State private var showLaunch = true

    var body: some View {
        if showLaunch {
            KuroLaunchView()
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            showLaunch = false
                        }
                    }
                }
        } else {
            KuroMainView(pendingDeepLink: $pendingDeepLink)
        }
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
                    .foregroundColor(.black)
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
    @Environment(SupabaseService.self) private var supabaseService

    enum Section: Int, CaseIterable {
        case concierge, discover, browse, collection, clubs

        var title: String {
            switch self {
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
    }

	@State private var selection: Section = .discover
	@State private var showProfileSheet = false
	@State private var showSearchSheet = false
	@State private var mountedSections: Set<Section> = [.discover]
	@State private var swipeExclusions: [CGRect] = []
    @State private var suppressCardTaps = false
    @State private var tapSuppressionResetTask: Task<Void, Never>? = nil
    @State private var didTrackSuppressionThisGesture = false
    @State private var didApplyStartArgument = false
    @State private var showOnboarding = !OnboardingView.hasCompletedOnboarding
    @State private var edgeBounceOffset: CGFloat = 0
    @State private var deepLinkAnimeId: Int? = nil
    @State private var deepLinkMangaId: Int? = nil
    @State private var deepLinkClubId: String? = nil
    @State private var pendingConciergePrompt: String? = nil
	// Five-page discovery funnel: Concierge ← [Discover] → Browse → Collection → Clubs
    private let swipeOrder: [Section] = [.concierge, .discover, .browse, .collection, .clubs]
    private let swipeThreshold: CGFloat = 40
    private let swipeEdgeMargin: CGFloat = 24

    private var conciergeEditorialV1Enabled: Bool {
        // Concierge has fully migrated to the editorial shell.
        true
    }

    private var hidesHeaderForConcierge: Bool {
        selection == .concierge && conciergeEditorialV1Enabled
    }

    private func sectionFromLaunchArgument(_ raw: String) -> Section? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "concierge": return .concierge
        case "discover": return .discover
        case "browse": return .browse
        case "collection": return .collection
        case "clubs": return .clubs
        default: return nil
        }
    }

    // MARK: - Swipe conflict helpers (deduplicated from onChanged/onEnded)

    private var rootWidth: CGFloat {
        #if os(iOS)
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.width) ?? 393
        #else
        1024
        #endif
    }

    /// Returns true when the drag starts inside an exclusion zone and is NOT on a screen edge.
    private func isSwipeExcluded(start: CGPoint) -> Bool {
        let edgeAllowed = (start.x <= swipeEdgeMargin) || (start.x >= max(0, rootWidth - swipeEdgeMargin))
        let expanded = swipeExclusions.map { $0.insetBy(dx: -14, dy: -14) }
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
	            Color(.systemBackground).ignoresSafeArea()

	            VStack(spacing: 0) {
                if !hidesHeaderForConcierge {
                    KuroHeaderNew(selection: $selection, showProfileSheet: $showProfileSheet, showSearchSheet: $showSearchSheet)
                }

                // Header-driven pager: keeps sections mounted once visited.
	                KuroSectionPager(
	                    selection: $selection,
	                    mountedSections: $mountedSections,
	                    order: swipeOrder,
                        suppressCardTaps: suppressCardTaps,
                        pendingConciergePrompt: pendingConciergePrompt
	                )
	                .offset(x: edgeBounceOffset)
	                .background(Color.clear)
	            }
	        }
	        .coordinateSpace(name: "kuro_root")
	        .onPreferenceChange(KuroSwipeExclusionPreferenceKey.self) { v in
	            let viewport = CGRect(x: 0, y: 0, width: rootWidth, height: 2000)
	            let visible = v.filter { $0.intersects(viewport) }
	            if visible != swipeExclusions {
	                swipeExclusions = visible
	            }
	        }
            .onAppear {
                // Debug support: launch directly into Concierge for screenshots or manual QA.
                // Example: `xcrun simctl launch booted com.kuro.app --args --kuro-start=concierge`
                guard !didApplyStartArgument else { return }
                didApplyStartArgument = true
                let args = ProcessInfo.processInfo.arguments
                if let kv = args.first(where: { $0.hasPrefix("--kuro-start=") }),
                   let value = kv.split(separator: "=", maxSplits: 1).last,
                   let target = sectionFromLaunchArgument(String(value))
                {
                    selection = target
                    mountedSections.insert(target)
                } else if args.contains("--kuro-start-concierge") {
                    selection = .concierge
                    mountedSections.insert(.concierge)
                }
            }
	        .simultaneousGesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .named("kuro_root"))
                    .onChanged { value in
                        guard FeatureFlags.shared.isSwipeTapGuardEnabled else { return }
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
                            supabaseService.trackInteractionEvent(
                                "card_tap_suppressed_during_swipe",
                                surface: "root_pager",
                                result: "active"
                            )
                        }
                    }
	                .onEnded { value in
                        let shouldManageSuppression = FeatureFlags.shared.isSwipeTapGuardEnabled
                        defer { didTrackSuppressionThisGesture = false }
                        if shouldManageSuppression && suppressCardTaps {
                            scheduleTapSuppressionReset()
                        }
                        guard !KuroGestureCoordinator.shared.isHorizontalRailDragging else { return }
                        guard !KuroGestureCoordinator.shared.recentlyDraggedRail(withinMs: KuroGesturePolicy.postSwipeTapCooldownMs) else { return }

                        let excluded = isSwipeExcluded(start: value.startLocation)
                        if excluded && !isFastFlingOverride(value) { return }

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
	                        let bounceDirection: CGFloat = effectiveDx < 0 ? -1 : 1
	                        withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
	                            edgeBounceOffset = bounceDirection * 12
	                        }
	                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.1)) {
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
	                mountedSections.insert(newValue)
                    if newValue == .clubs {
                        supabaseService.clearClubNotificationBadge()
                    }
	            }
	            .task {
	                // Warm the Discover bundle so the first Discover render feels instant.
                _ = await supabaseService.fetchDiscoverBundle(limit: 30, hours: 24)
                // Check club notifications
                await supabaseService.checkClubNotifications()
            }
            .sheet(isPresented: $showProfileSheet) {
                ProfileView()
                    .environment(supabaseService)
            }
            .sheet(isPresented: $showSearchSheet) {
                NavigationStack {
                    EditorialSearchView()
                        .environment(supabaseService)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(action: { showSearchSheet = false }) {
                                    Image(systemName: "xmark")
                                        .font(.kuroBody(weight: .light))
                                        .foregroundColor(.kuroBlack60)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                }
            }
            .onDisappear {
                tapSuppressionResetTask?.cancel()
            }
            .onChange(of: pendingDeepLink) { _, link in
                guard let link else { return }
                pendingDeepLink = nil
                handleDeepLink(link)
            }
            .sheet(isPresented: Binding(
                get: { deepLinkAnimeId != nil },
                set: { if !$0 { deepLinkAnimeId = nil } }
            )) {
                if let animeId = deepLinkAnimeId {
                    MediaDetailSheet(kind: .anime, id: animeId)
                        .environment(supabaseService)
                }
            }
            .sheet(isPresented: Binding(
                get: { deepLinkMangaId != nil },
                set: { if !$0 { deepLinkMangaId = nil } }
            )) {
                if let mangaId = deepLinkMangaId {
                    MediaDetailSheet(kind: .manga, id: mangaId)
                        .environment(supabaseService)
                }
            }
            .sheet(isPresented: Binding(
                get: { deepLinkClubId != nil },
                set: { if !$0 { deepLinkClubId = nil } }
            )) {
                if let clubId = deepLinkClubId {
                    NavigationStack {
                        ClubDetailView(clubId: clubId)
                            .environment(supabaseService)
                    }
                }
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView {
                    showOnboarding = false
                }
            }
    }

    private func handleDeepLink(_ link: DeepLink) {
        switch link {
        case .anime(let id):
            deepLinkAnimeId = id
        case .manga(let id):
            deepLinkMangaId = id
        case .club(let id):
            deepLinkClubId = id
        case .collection:
            selection = .collection
            mountedSections.insert(.collection)
        case .discover:
            selection = .discover
        case .concierge(let prompt):
            selection = .concierge
            mountedSections.insert(.concierge)
            pendingConciergePrompt = prompt
            // Clear after next runloop so ConciergeView can consume it once
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pendingConciergePrompt = nil
            }
        case .authCallback:
            break // Handled at app level in KuroApp.swift, never reaches here
        }
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
                        .frame(width: width, height: height)
                }
            }
            .environment(\.kuroSuppressCardTaps, suppressCardTaps)
            .offset(x: (-CGFloat(selectionIndex) * width))
            .clipped()
            // Animate only when the selection changes (header-driven paging).
            // This avoids gesture conflicts with in-page horizontal carousels.
            .animation(.snappy(duration: 0.22, extraBounce: 0.02), value: selectionIndex)
        }
    }

    @ViewBuilder
    private func page(for section: Section) -> some View {
        let sectionIdx = order.firstIndex(of: section) ?? 0
        let distance = abs(selectionIndex - sectionIdx)
        // Mount current page + immediate neighbors; unmount distant pages to save memory.
        let shouldMount = distance <= 1 || mountedSections.contains(section)

        if shouldMount {
            switch section {
            case .concierge:
                ConciergeView(assistantEnabled: true, initialPrompt: pendingConciergePrompt)
            case .discover:
                EditorialDiscoverView()
            case .browse:
                BrowseView()
            case .collection:
                EditorialCollectionView()
            case .clubs:
                ClubsView()
            }
        } else {
            // Placeholder keeps layout stable without triggering `.task` in heavy pages.
            Color(.systemBackground)
        }
    }
}

// MARK: - New Responsive Header Component (Fixed)
struct KuroHeaderNew: View {
    @Binding var selection: KuroMainView.Section
    @Binding var showProfileSheet: Bool
    @Binding var showSearchSheet: Bool
    @Environment(SupabaseService.self) private var supabaseService

    private let swipeOrder: [KuroMainView.Section] = [.concierge, .discover, .browse, .collection, .clubs]

    private static let windowTextPaddingX: CGFloat = 14
    private static let windowTextPaddingY: CGFloat = 7
    private static let windowTextSlack: CGFloat = 10

    @State private var displayedSection: KuroMainView.Section = .discover
    @State private var previousSection: KuroMainView.Section? = nil
    @State private var isForwardTransition = true
    @State private var titleProgress: CGFloat = 1.0
    @State private var titleTextWidth: CGFloat = 92

    private var currentTitle: String { selection.title }
    private var canSwipeLeft: Bool {
        guard let i = swipeOrder.firstIndex(of: selection) else { return false }
        return i > 0
    }
    private var canSwipeRight: Bool {
        guard let i = swipeOrder.firstIndex(of: selection) else { return false }
        return i < (swipeOrder.count - 1)
    }

    private static let titleFont = UIFont.systemFont(ofSize: 11, weight: .regular)
    private static let titleTracking: CGFloat = 1.5

    private static func measureTitleWidth(_ title: String) -> CGFloat {
        let base = (title as NSString).size(withAttributes: [.font: titleFont]).width
        let tracking = titleTracking * CGFloat(max(0, title.count - 1))
        return ceil(base + tracking)
    }

    private var titleWindow: some View {
        let hint = (canSwipeLeft || canSwipeRight)
        // Rounded "window" with edge shading (no heavy fill) for a physical mask feel.
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let innerMask = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let titleHeight: CGFloat = 16
        let travel = (titleTextWidth + (Self.windowTextPaddingX * 2) + 28)

        return ZStack {
            shape
                .fill(Color.clear)
                // Tiny fill keeps the shape "present" so the shadow reads, without tinting the interior.
                .background(shape.fill(Color.white.opacity(0.001)))
                .overlay(
                    shape
                        .stroke(Color.black.opacity(hint ? 0.12 : 0.06), lineWidth: 0.6)
                )
                // Subtle highlight to sell the "window" edge without changing the interior color.
                .overlay(
                    shape
                        .stroke(Color.white.opacity(0.75), lineWidth: 0.6)
                        .blendMode(.overlay)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 6)

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

    var body: some View {
        VStack(spacing: 0) {
            // Three-part layout with proper spacing
            HStack(alignment: .center) {
                // Left: Brand (30% opacity)
                HStack(spacing: 10) {
                    Text("KURO")
                        .font(.system(size: 11, weight: .regular))
                        .tracking(1.5)
                        .foregroundColor(.kuroTextTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Center: Section (full opacity)
                VStack(spacing: 4) {
                    HStack(spacing: 10) {
                        if selection == .concierge {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle().stroke(Color.black.opacity(0.10), lineWidth: 0.7)
                                )
                                .overlay(
                                    Image(systemName: "bubble.left.and.bubble.right.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.black.opacity(0.70))
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
                                    .fill(Color.black.opacity(section == selection ? 0.55 : 0.15))
                                    .frame(width: 4, height: 4)

                                // Badge dot for Clubs when unseen activity exists
                                if section == .clubs && supabaseService.hasUnseenClubActivity && selection != .clubs {
                                    Circle()
                                        .fill(Color.black.opacity(0.70))
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Section")
                .accessibilityValue(currentTitle)
                .accessibilityHint("Swipe left or right to change sections.")
                .frame(maxWidth: .infinity, alignment: .center)

                // Right: Actions
                HStack(spacing: 10) {
                    Spacer()

                    Button(action: {
                        KuroAccessibility.impactHaptic(.light)
                        showSearchSheet = true
                    }) {
                        Circle()
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(.black.opacity(0.60))
                            )
                            .overlay(
                                Circle().stroke(Color.black.opacity(0.10), lineWidth: 0.7)
                            )
                    }
                    .buttonStyle(KuroHeaderIconButtonStyle())
                    .accessibilityLabel("Search")
                    .accessibilityHint("Opens search")

                    Menu {
                        Button("Profile") {
                            showProfileSheet = true
                        }
                        Button("Sign Out", role: .destructive) {
                            Task { await supabaseService.signOut() }
                        }
                    } label: {
                        Circle()
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(supabaseService.currentUserInitial)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.black.opacity(0.80))
                            )
                            .overlay(
                                Circle().stroke(Color.black.opacity(0.10), lineWidth: 0.7)
                            )
                    }
                    .buttonStyle(KuroHeaderIconButtonStyle())
                    .accessibilityLabel("Profile")
                    .accessibilityHint("Opens account menu")
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Section navigation")
            .accessibilityValue(currentTitle)
            .accessibilityHint("Swipe left or right to change sections.")
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
                withAnimation(.easeOut(duration: 0.18)) {
                    titleProgress = 1.0
                }

                // Clear previous after animation; avoids unnecessary layout work.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                    if displayedSection == newValue {
                        previousSection = nil
                        withAnimation(.easeOut(duration: 0.12)) {
                            titleTextWidth = toWidth
                        }
                    }
                }
            }

            // Subtle divider
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 0.5)
        }
        .frame(height: 54)
        .background(Color.kuroBackground)
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 6)
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
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.5)
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .offset(x: (-progress) * dir * travel)
            }

            Text(current)
                .font(.system(size: 11, weight: .regular))
                .tracking(1.5)
                .foregroundColor(.black)
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
        .environment(SupabaseService.shared)
}
