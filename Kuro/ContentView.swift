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
    @Environment(SupabaseService.self) private var supabaseService
    
    var body: some View {
        KuroRootView()
            .environment(supabaseService)
    }
}

// MARK: - Root View with Launch
struct KuroRootView: View {
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
            KuroMainView()
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
    @Environment(SupabaseService.self) private var supabaseService
    // Removed: @State private var currentSection = 0
    // Removed: @State private var selectedMood: String? = nil
    // Removed: @State private var dragOffset: CGFloat = 0
    // Removed: let sections = ["DISCOVER", "COLLECTION", "SEARCH"]

    enum Section: Int, CaseIterable {
        case concierge, discover, collection

        var title: String {
            switch self {
            case .concierge:
                return "CONCIERGE"
            case .discover:
                return "DISCOVER"
            case .collection:
                return "COLLECTION"
            }
        }
    }

	@State private var selection: Section = .discover
	@State private var showProfileSheet = false
	@State private var showSearchSheet = false
	@State private var showBrowseSheet = false
	@State private var mountedSections: Set<Section> = [.discover]
	@State private var swipeExclusions: [CGRect] = []
    @State private var suppressCardTaps = false
    @State private var tapSuppressionResetTask: Task<Void, Never>? = nil
    @State private var didTrackSuppressionThisGesture = false
    @State private var didApplyStartArgument = false
    @State private var showOnboarding = !OnboardingView.hasCompletedOnboarding
    @State private var edgeBounceOffset: CGFloat = 0
	// Three core tabs: Concierge | Discover | Collection
    private let swipeOrder: [Section] = [.concierge, .discover, .collection]
    private let swipeThreshold: CGFloat = 40
    private let swipeEdgeMargin: CGFloat = 24

    private var conciergeEditorialV1Enabled: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ff-off=concierge_editorial_v1") { return false }
        if args.contains("--ff-on=concierge_editorial_v1") { return true }
        return true
        #else
        return FeatureFlags.shared.isConciergeEditorialV1Enabled
        #endif
    }

    private var hidesHeaderForConcierge: Bool {
        selection == .concierge && conciergeEditorialV1Enabled
    }

    private func sectionFromLaunchArgument(_ raw: String) -> Section? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "concierge": return .concierge
        case "discover": return .discover
        case "collection": return .collection
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
    
    var body: some View {
	        ZStack {
	            Color(.systemBackground).ignoresSafeArea()

	            VStack(spacing: 0) {
                if !hidesHeaderForConcierge {
                    KuroHeaderNew(selection: $selection, showProfileSheet: $showProfileSheet, showSearchSheet: $showSearchSheet, showBrowseSheet: $showBrowseSheet)
                }

                // Header-driven pager: keeps sections mounted once visited.
	                KuroSectionPager(
	                    selection: $selection,
	                    mountedSections: $mountedSections,
	                    order: swipeOrder,
                        suppressCardTaps: suppressCardTaps
	                )
	                .offset(x: edgeBounceOffset)
	                .background(Color.clear)
	            }
	        }
	        .coordinateSpace(name: "kuro_root")
	        .onPreferenceChange(KuroSwipeExclusionPreferenceKey.self) { v in
	            swipeExclusions = v
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
                        guard !isSwipeExcluded(start: value.startLocation) else { return }

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

                        guard !isSwipeExcluded(start: value.startLocation) else { return }

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
	            }
	            .task {
	                // Warm the Discover bundle so the first Discover render feels instant.
                _ = await supabaseService.fetchDiscoverBundle(limit: 30, hours: 24)
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
            .sheet(isPresented: $showBrowseSheet) {
                NavigationStack {
                    BrowseView()
                        .environment(supabaseService)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(action: { showBrowseSheet = false }) {
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
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView {
                    showOnboarding = false
                }
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
            .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.92), value: selectionIndex)
        }
    }

    @ViewBuilder
    private func page(for section: Section) -> some View {
        let shouldMount = mountedSections.contains(section) || section == selection

        if shouldMount {
            switch section {
            case .concierge:
                ConciergeView(assistantEnabled: true)
            case .discover:
                EditorialDiscoverView()
            case .collection:
                EditorialCollectionView()
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
    @Binding var showBrowseSheet: Bool
    @Environment(SupabaseService.self) private var supabaseService

    private let swipeOrder: [KuroMainView.Section] = [.concierge, .discover, .collection]

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
                            Circle()
                                .fill(Color.black.opacity(section == selection ? 0.55 : 0.15))
                                .frame(width: 4, height: 4)
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
                        Button("Browse") {
                            showBrowseSheet = true
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

// MARK: - New Discover View (Single Column Sophistication)
struct DiscoverViewNew: View {
    @Environment(SupabaseService.self) private var supabaseService
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if supabaseService.isLoading {
                LoadingStateViewNew()
            } else if supabaseService.animeItems.isEmpty {
                DiscoverEmptyStateView()
            } else {
                VStack(spacing: 48) {
                    // CURRENT SEASON Section
                    DiscoverSectionNew(
                        title: "CURRENT SEASON",
                        subtitle: "Airing now",
                        items: currentSeasonItems
                    )

                    // TRENDING NOW Section
                    DiscoverSectionNew(
                        title: "TRENDING NOW",
                        subtitle: "Most popular this week",
                        items: trendingItems
                    )

                    // NEWLY ADDED Section
                    DiscoverSectionNew(
                        title: "NEWLY ADDED",
                        subtitle: "Fresh to the collection",
                        items: newlyAddedItems
                    )

                    // TOP RATED Section
                    DiscoverSectionNew(
                        title: "TOP RATED",
                        subtitle: "Highest scores",
                        items: topRatedItems
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            Task {
                supabaseService.setPageSize(50)
                let total = KuroScreen.isLargeScreen ? 500 : 300
                await supabaseService.prefetchAnime(total: total)
            }
        }
    }

    // MARK: - Content Filters

    private var currentSeasonItems: [Anime] {
        // Filter for current season (2024-2025) - Show 3 items for elegance
        supabaseService.animeItems.filter { anime in
            (anime.seasonYear ?? 0) >= 2024 && anime.status == "RELEASING"
        }.prefix(3).map { $0 }
    }

    private var trendingItems: [Anime] {
        // Sort by popularity/trending - Show 3 items
        supabaseService.animeItems.sorted { ($0.trending ?? 0) > ($1.trending ?? 0) }
            .prefix(3).map { $0 }
    }

    private var newlyAddedItems: [Anime] {
        // Sort by created_at (newest first) - Show 3 items
        supabaseService.animeItems.sorted { $0.createdAt > $1.createdAt }
            .prefix(3).map { $0 }
    }

    private var topRatedItems: [Anime] {
        // Sort by average score - Show 3 items
        supabaseService.animeItems.filter { ($0.averageScore ?? 0) > 75 }
            .sorted { ($0.averageScore ?? 0) > ($1.averageScore ?? 0) }
            .prefix(3).map { $0 }
    }
}

// MARK: - New Discover Section (Single Column)
struct DiscoverSectionNew: View {
    let title: String
    let subtitle: String
    let items: [Anime]

    var body: some View {
        VStack(spacing: 0) {
            // Refined Section Header - More Editorial
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: 12) {
                    Text(title)
                        .font(.system(size: 18, weight: .light, design: .serif))
                        .tracking(0.5)
                        .foregroundColor(.black)

                    Text(subtitle)
                        .font(.system(size: 10, weight: .light))
                        .tracking(0.8)
                        .foregroundColor(.kuroTextTertiary)
                        .padding(.bottom, 2)
                }

                Rectangle()
                    .fill(Color.black)
                    .frame(height: 0.5)
                    .frame(maxWidth: 60)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 24)

            // Section Content - Single column for sophistication
            VStack(spacing: 32) {
                ForEach(items, id: \.id) { anime in
                    SophisticatedAnimeCard(media: anime)
                }
            }
        }
    }
}

// MARK: - New Loading State View (Single Column)
struct LoadingStateViewNew: View {
    var body: some View {
        VStack(spacing: 48) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(spacing: 0) {
                    // Section header skeleton
                    VStack(alignment: .leading, spacing: 6) {
                        Rectangle()
                            .fill(Color.black.opacity(0.08))
                            .frame(width: 120, height: 11)

                        Rectangle()
                            .fill(Color.black.opacity(0.05))
                            .frame(width: 80, height: 9)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 16)

                    // Single column skeleton
                    VStack(spacing: 32) {
                        ForEach(0..<3, id: \.self) { _ in
                            SophisticatedCardLoading()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 48)
    }
}

// MARK: - Sophisticated Card Loading
struct SophisticatedCardLoading: View {
    var body: some View {
        HStack(spacing: 16) {
            // Left: Image placeholder
            Rectangle()
                .fill(Color.black.opacity(0.04))
                .frame(width: 100, height: 150)  // Fixed consistent size
                .overlay(
                    ProgressView()
                        .scaleEffect(0.5)
                        .foregroundColor(.kuroTextTertiary)
                )

            // Right: Text placeholders
            VStack(alignment: .leading, spacing: 8) {
                // Title placeholder
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(height: 16)
                    .frame(maxWidth: .infinity)

                // Metadata placeholder
                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(height: 10)
                    .frame(width: 80)

                // Description placeholders
                VStack(spacing: 4) {
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .frame(height: 11)
                        .frame(maxWidth: .infinity)
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .frame(height: 11)
                        .frame(maxWidth: .infinity)
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .frame(height: 11)
                        .frame(width: 120)
                }

                Spacer()

                // Genre placeholders
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .frame(width: 50, height: 16)
                        .cornerRadius(8)
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .frame(width: 40, height: 16)
                        .cornerRadius(8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 150)
    }
}

// MARK: - Comprehensive Discover View with Sections
// MARK: - Sophisticated Discover Section Component
struct DiscoverSection: View {
    let title: String
    let subtitle: String
    let items: [Anime]
    let geometry: GeometryProxy
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat
    let horizontalPadding: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            // Refined Section Header - More Editorial
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: 12) {
                    Text(title)
                        .font(.system(size: 18, weight: .light, design: .serif))
                        .tracking(0.5)
                        .foregroundColor(.black)

                    Text(subtitle)
                        .font(.system(size: 10, weight: .light))
                        .tracking(0.8)
                        .foregroundColor(.kuroTextTertiary)
                        .padding(.bottom, 2)
                }

                Rectangle()
                    .fill(Color.black)
                    .frame(height: 0.5)
                    .frame(maxWidth: 60)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, max(geometry.size.width * 0.06, 24))

            // Section Content - Single column for sophistication
            VStack(spacing: max(geometry.size.width * 0.08, 32)) {
                ForEach(items, id: \.id) { anime in
                    SophisticatedAnimeCard(media: anime)
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
    }
}

// MARK: - Loading State View
struct LoadingStateView: View {
    let geometry: GeometryProxy
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat
    let horizontalPadding: CGFloat

    var body: some View {
        VStack(spacing: max(geometry.size.width * 0.12, 48)) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(spacing: 0) {
                    // Section header skeleton
                    VStack(alignment: .leading, spacing: 6) {
                        Rectangle()
                            .fill(Color.black.opacity(0.08))
                            .frame(width: 120, height: 11)

                        Rectangle()
                            .fill(Color.black.opacity(0.05))
                            .frame(width: 80, height: 9)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, max(geometry.size.width * 0.04, 16))

                    // Local sizing constants for grid and cards
                    let padding: CGFloat = 20
                    let perfectSpacing: CGFloat = 16
                    let columnsCount: Int = 2
                    let totalSpacing = CGFloat(columnsCount - 1) * perfectSpacing
                    let availableWidth = geometry.size.width - (2 * padding) - totalSpacing
                    let cardWidth = floor(availableWidth / CGFloat(columnsCount))
                    let textHeight: CGFloat = 72
                    let imageHeight: CGFloat = cardWidth / 0.7
                    let cardHeight: CGFloat = floor(imageHeight + 8 + textHeight)

                    LazyVGrid(
                        columns: [
                            GridItem(.fixed(cardWidth), spacing: perfectSpacing, alignment: .top),
                            GridItem(.fixed(cardWidth), spacing: perfectSpacing, alignment: .top)
                        ],
                        alignment: .center,
                        spacing: rowSpacing
                    ) {
                        ForEach(0..<6, id: \.self) { _ in
                            DiscoverCardLoading()
                                .frame(width: cardWidth, height: cardHeight, alignment: .top)
                        }
                    }
                    .padding(.horizontal, padding)
                }
            }
        }
        .padding(.top, max(geometry.size.width * 0.06, 24))
        .padding(.bottom, max(geometry.size.width * 0.12, 48))
    }
}

// MARK: - Discover Empty State View
struct DiscoverEmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.black.opacity(0.25))

            Text("NO CONTENT FOUND")
                .font(.system(size: 14, weight: .medium))
                .tracking(1.5)
                .foregroundColor(.kuroTextTertiary)

            Text("Check your connection and try again.")
                .font(.system(size: 12, weight: .light))
                .tracking(0.5)
                .foregroundColor(.kuroTextTertiary)
        }
        .padding(.top, 80)
    }
}

struct CollectionViewSimple: View {
    @Environment(SupabaseService.self) private var supabaseService
    @State private var filter = "ALL"
    let filters = ["ALL", "WATCHING", "COMPLETED", "PLANNED"]
    @State private var mediaIsManga = false
    @State private var displayCount = 60
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Media toggle + Filter tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 32) {
                        FilterTabSimple(
                            title: mediaIsManga ? "MANGA" : "ANIME",
                            isSelected: true,
                            action: {
                                withAnimation(.easeInOut(duration: 0.3)) { mediaIsManga.toggle() }
                                if mediaIsManga && supabaseService.mangaItems.isEmpty {
                                    Task { await supabaseService.prefetchManga(total: 300) }
                                }
                            }
                        )
                        ForEach(filters, id: \.self) { filterOption in
                            FilterTabSimple(
                                title: filterOption,
                                isSelected: filter == filterOption,
                                action: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        filter = filterOption
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.vertical, 20)
                
                // Collection grid with PERFECT spacing to match reference
                ScrollView(.vertical, showsIndicators: false) {
                    // Collection grid with DESIGN-SYSTEM spacing & fixed card size
                    let metrics = KuroCardMetrics.grid(for: geometry.size.width, columns: 2)
                    let columns = metrics.columns
                    let cardWidth = metrics.cardWidth
                    let cardHeight = metrics.cardHeight
                    
                    // Create grid with PERFECT spacing to match reference
                    LazyVGrid(
                        columns: columns,
                        alignment: .center,
                        spacing: 16
                    ) {
                        if supabaseService.isLoading {
                            ForEach(0..<9, id: \.self) { _ in
                                CollectionCardLoading()
                                    .frame(width: cardWidth, height: cardHeight, alignment: .top)
                            }
                        } else if mediaIsManga, !collectionManga.isEmpty {
                            let items = Array(collectionManga.prefix(displayCount))
                            ForEach(items, id: \.id) { manga in
                                CollectionCardReal(media: manga)
                                    .frame(width: cardWidth, height: cardHeight, alignment: .top)
                                    .onAppear {
                                        if manga.id == items.last?.id {
                                            displayCount = min(displayCount + 60, collectionManga.count)
                                        }
                                    }
                            }
                        } else if !mediaIsManga, !collectionAnime.isEmpty {
                            let items = Array(collectionAnime.prefix(displayCount))
                            ForEach(items, id: \.id) { anime in
                                CollectionCardReal(media: anime)
                                    .frame(width: cardWidth, height: cardHeight, alignment: .top)
                                    .onAppear {
                                        if anime.id == items.last?.id {
                                            displayCount = min(displayCount + 60, collectionAnime.count)
                                        }
                                    }
                            }
                        } else {
                            // Fallback to general list if user collection is empty
                            if mediaIsManga {
                                let items = Array(supabaseService.mangaItems.prefix(displayCount))
                                ForEach(items, id: \.id) { manga in
                                    CollectionCardReal(media: manga)
                                        .frame(width: cardWidth, height: cardHeight, alignment: .top)
                                        .onAppear {
                                            if manga.id == items.last?.id {
                                                displayCount = min(displayCount + 60, supabaseService.mangaItems.count)
                                                if supabaseService.hasMoreManga {
                                                    Task { await supabaseService.fetchNextMangaPage() }
                                                }
                                            }
                                        }
                                }
                            } else {
                                let items = Array(supabaseService.animeItems.prefix(displayCount))
                                ForEach(items, id: \.id) { anime in
                                    CollectionCardReal(media: anime)
                                        .frame(width: cardWidth, height: cardHeight, alignment: .top)
                                        .onAppear {
                                            if anime.id == items.last?.id {
                                                displayCount = min(displayCount + 60, supabaseService.animeItems.count)
                                                if supabaseService.hasMoreAnime {
                                                    Task { await supabaseService.fetchNextAnimePage() }
                                                }
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, KuroCardMetrics.horizontalPadding)
                }
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            Task {
                await supabaseService.fetchUserLists()
                supabaseService.setPageSize(50)
                if supabaseService.animeItems.isEmpty { await supabaseService.prefetchAnime(total: 300) }
                if supabaseService.mangaItems.isEmpty { await supabaseService.prefetchManga(total: 300) }
            }
        }
    }

    // Map filter string to DB list type
    private var selectedStatus: ListStatus? {
        switch filter {
        case "WATCHING": return .current
        case "COMPLETED": return .completed
        case "PLANNED": return .planning
        default: return nil
        }
    }

    // Build collection items from user lists and available anime cache
    private var collectionAnime: [Anime] {
        let ids: Set<Int> = Set(
            supabaseService.userLists
                .filter { $0.mediaType.lowercased() == "anime" }
                .filter { entry in
                    guard let s = selectedStatus else { return true }
                    return entry.status == s
                }
                .map { $0.mediaId }
        )
        if ids.isEmpty { return [] }
        let lookup: [Int: Anime] = Dictionary(uniqueKeysWithValues: supabaseService.animeItems.map { ($0.id, $0) })
        return ids.compactMap { lookup[$0] }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var collectionManga: [Manga] {
        let ids: Set<Int> = Set(
            supabaseService.userLists
                .filter { $0.mediaType.lowercased() == "manga" }
                .filter { entry in
                    guard let s = selectedStatus else { return true }
                    return entry.status == s
                }
                .map { $0.mediaId }
        )
        if ids.isEmpty { return [] }
        let lookup: [Int: Manga] = Dictionary(uniqueKeysWithValues: supabaseService.mangaItems.map { ($0.id, $0) })
        return ids.compactMap { lookup[$0] }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}


struct SearchViewNew: View {
    var body: some View { EditorialSearchView() }
}

// MARK: - Search View with debounce
// MARK: - Enhanced Components

struct CategoryPillSelectable: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .regular))
                .tracking(1.0)
                .foregroundColor(.black.opacity(isSelected ? 1.0 : 0.6))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .stroke(Color.black.opacity(isSelected ? 0.8 : 0.15), lineWidth: 0.5)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(isSelected ? 0.05 : 0.0))
                        )
                )
        }
    }
}

struct SearchResultRowReal: View {
    let media: any MediaDisplayable
    @State private var showDetail = false
    
    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        }) {
            HStack(alignment: .top, spacing: 16) { // Top alignment for consistent rows
                // Fixed-size image container
                KuroCachedAsyncImage(url: URL(string: media.imageURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.5)
                                .foregroundColor(.kuroTextTertiary)
                        )
                }
                .frame(width: 50, height: 70, alignment: .center) // Fixed dimensions
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                
                // Text content with consistent spacing
                VStack(alignment: .leading, spacing: 4) {
                    Text(media.title.uppercased())
                        .font(.system(size: 12, weight: .regular))
                        .tracking(0.5)
                        .foregroundColor(.black.opacity(0.8))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Text("\(media.year) · \(media.genres?.first ?? "Unknown")")
                        .font(.system(size: 10, weight: .light))
                        .tracking(0.5)
                        .foregroundColor(.black.opacity(0.5))
                    
                    if let episodes = media.episodes {
                        Text("\(episodes) EPS")
                            .font(.system(size: 9, weight: .light))
                            .tracking(0.5)
                            .foregroundColor(.kuroTextTertiary)
                    } else if let chapters = media.chapters {
                        Text("\(chapters) CH")
                            .font(.system(size: 9, weight: .light))
                            .tracking(0.5)
                            .foregroundColor(.kuroTextTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading) // Fill available space
                
                // Rating and chevron section
                VStack(alignment: .trailing, spacing: 8) {
                    if let rating = media.rating {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(.black.opacity(0.8))
                            
                            Text("★")
                                .font(.system(size: 8))
                                .foregroundColor(.kuroTextTertiary)
                        }
                    }
                    
                    Spacer() // Push chevron to bottom
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .light))
                        .foregroundColor(.kuroTextTertiary)
                }
                .frame(height: 70) // Match image height for consistent alignment
            }
            .frame(minHeight: 70) // Ensure consistent row height
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            if let anime = media as? Anime {
                AnimeDetailView(anime: anime)
            } else if let manga = media as? Manga {
                MangaDetailView(manga: manga)
            }
        }
    }
}

struct CollectionCardLoading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .aspectRatio(0.7, contentMode: .fill)
                .frame(maxWidth: .infinity, alignment: .center) // Center alignment for loading
                .overlay(
                    ProgressView()
                        .scaleEffect(0.6)
                        .foregroundColor(.kuroTextTertiary)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Rectangle()
                    .fill(Color.black.opacity(0.1))
                    .frame(height: 10)
                    .frame(maxWidth: .infinity)
                
                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(height: 9)
                    .frame(width: 40)
            }
            .frame(height: 72)
            .frame(maxWidth: .infinity, alignment: .leading) // Consistent text width
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.kuroBackground)
                .shadow(color: .black.opacity(0.04), radius: 20, x: 0, y: 10)
                .shadow(color: .black.opacity(0.02), radius: 5, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                )
        )
    }
}

struct CollectionCardReal: View {
    let media: any MediaDisplayable
    @State private var showDetail = false
    
    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        }) {
            VStack(alignment: .leading, spacing: 0) {
                KuroCachedAsyncImage(url: URL(string: media.imageURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.6)
                                .foregroundColor(.kuroTextTertiary)
                        )
                }
                .aspectRatio(0.7, contentMode: .fill)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                
                // Text content with fixed height container
                VStack(alignment: .leading, spacing: 4) {
                    Text(media.title.uppercased())
                        .font(.system(size: 10, weight: .regular))
                        .tracking(0.5)
                        .foregroundColor(.black.opacity(0.8))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Text("\(media.year) · \(episodeText)")
                        .font(.system(size: 9, weight: .light))
                        .tracking(0.5)
                        .foregroundColor(.black.opacity(0.5))
                    
                    if let rating = media.rating {
                        HStack(spacing: 2) {
                            Text("★")
                                .font(.system(size: 8))
                                .foregroundColor(.black.opacity(0.4))
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 8, weight: .light))
                                .foregroundColor(.black.opacity(0.4))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading) // Consistent text width
                .frame(height: 72) // Fixed text area height to enforce uniform card height
                .padding(.top, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.kuroBackground)
                    .shadow(color: .black.opacity(0.04), radius: 20, x: 0, y: 10)
                    .shadow(color: .black.opacity(0.02), radius: 5, x: 0, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            if let anime = media as? Anime {
                AnimeDetailView(anime: anime)
            } else if let manga = media as? Manga {
                MangaDetailView(manga: manga)
            }
        }
    }

    private var episodeText: String {
        if let episodes = media.episodes {
            return "\(episodes) EPS"
        } else if let chapters = media.chapters {
            return "\(chapters) CH"
        } else {
            return "Movie"
        }
    }
}

// MARK: - Simple Components
struct MoodPillSimple: View {
    let mood: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(mood.uppercased())
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.5)
                    .foregroundColor(.black.opacity(isSelected ? 1.0 : 0.3))
                
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 0.5)
                    .scaleEffect(x: isSelected ? 1.0 : 0.0, anchor: .center)
                    .opacity(isSelected ? 1.0 : 0.0)
                    .animation(.easeOut(duration: 0.3), value: isSelected)
            }
        }
    }
}

struct FeaturedCardSimple: View {
    let title: String
    let year: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Placeholder image
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(maxWidth: .infinity)
                .frame(height: 420)
                .overlay(
                    Text("IMAGE")
                        .font(.system(size: 24, weight: .ultraLight))
                        .foregroundColor(.kuroTextTertiary)
                )
            
            VStack(alignment: .leading, spacing: 12) {
                Text(title.uppercased())
                    .font(.system(size: 20, weight: .ultraLight, design: .serif))
                    .tracking(0.5)
                    .foregroundColor(.black)
                
                Text(year)
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.5)
                    .foregroundColor(.black.opacity(0.5))
                
                Text(description)
                    .font(.system(size: 11, weight: .light))
                    .tracking(1.0)
                    .foregroundColor(.black.opacity(0.6))
                    .lineSpacing(4)
            }
            .padding(.vertical, 24)
        }
    }
}

struct CollectionCardSimple: View {
    let title: String
    let year: String
    let episodeText: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .aspectRatio(0.7, contentMode: .fill)
                .overlay(
                    Text("IMG")
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(.kuroTextTertiary)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .regular))
                    .tracking(0.5)
                    .foregroundColor(.black.opacity(0.8))
                    .lineLimit(2)
                
                Text("\(year) · \(episodeText)")
                    .font(.system(size: 9, weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.black.opacity(0.5))
            }
            .frame(height: 72)
            .padding(.top, 8)
        }
    }
}

struct FilterTabSimple: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.5)
                    .foregroundColor(.black.opacity(isSelected ? 1.0 : 0.3))
                
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 0.5)
                    .scaleEffect(x: isSelected ? 1.0 : 0.0, anchor: .center)
                    .opacity(isSelected ? 1.0 : 0.0)
            }
        }
    }
}

struct CategoryPillSimple: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .regular))
            .tracking(1.0)
            .foregroundColor(.black.opacity(0.6))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .stroke(Color.black.opacity(0.15), lineWidth: 0.5)
            )
    }
}

struct SearchResultRowSimple: View {
    let title: String
    let year: String
    let genre: String
    
    var body: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(width: 50, height: 70)
                .overlay(
                    Text("IMG")
                        .font(.system(size: 8, weight: .light))
                        .foregroundColor(.kuroTextTertiary)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .regular))
                    .tracking(0.5)
                    .foregroundColor(.black.opacity(0.8))
                    .lineLimit(1)
                
                Text("\(year) · \(genre)")
                    .font(.system(size: 10, weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.black.opacity(0.5))
                
                Text("12 EPS")
                    .font(.system(size: 9, weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.kuroTextTertiary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .light))
                .foregroundColor(.kuroTextTertiary)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Sophisticated Single-Column Card (Grown-Up Design)
struct SophisticatedAnimeCard: View {
    let media: any MediaDisplayable
    @State private var showDetail = false

    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.medium)
            showDetail = true
        }) {
            HStack(spacing: 16) {
                // Left: Portrait Cover Image
                KuroCachedAsyncImage(url: URL(string: media.imageURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.black.opacity(0.04))
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.5)
                                .foregroundColor(.kuroTextTertiary)
                        )
                }
                .frame(width: 100, height: 150)  // Fixed consistent size
                .clipped()
                .cornerRadius(0)

                // Right: Elegant Info Section
                VStack(alignment: .leading, spacing: 8) {
                    // Title - Large Serif
                    Text(media.title.uppercased())
                        .font(.system(size: 16, weight: .light, design: .serif))
                        .tracking(0.3)
                        .foregroundColor(.black)
                        .lineLimit(3)
                        .lineSpacing(2)

                    // Metadata Line
                    HStack(spacing: 6) {
                        Text(media.year)
                            .font(.system(size: 10, weight: .light))
                            .tracking(1.0)
                            .foregroundColor(.black.opacity(0.4))

                        if let rating = media.rating {
                            Text("·")
                                .foregroundColor(.kuroTextTertiary)
                            HStack(spacing: 2) {
                                Text("★")
                                    .font(.system(size: 9))
                                    .foregroundColor(.black.opacity(0.4))
                                Text(String(format: "%.1f", rating))
                                    .font(.system(size: 10, weight: .medium))
                                    .tracking(0.5)
                                    .foregroundColor(.black.opacity(0.6))
                            }
                        }

                        if let episodes = media.episodes {
                            Text("·")
                                .foregroundColor(.kuroTextTertiary)
                            Text("\(episodes) EP")
                                .font(.system(size: 10, weight: .light))
                                .tracking(0.8)
                                .foregroundColor(.black.opacity(0.4))
                        }
                    }

                    // Description - Sophisticated
                    if !media.displayDescription.isEmpty {
                        Text(media.displayDescription)
                            .font(.system(size: 11, weight: .light))
                            .tracking(0.2)
                            .foregroundColor(.black.opacity(0.5))
                            .lineLimit(3)
                            .lineSpacing(3)
                    }

                    Spacer()

                    // Genres - Minimal Pills
                    if let genres = media.genres?.prefix(3) {
                        HStack(spacing: 6) {
                            ForEach(Array(genres), id: \.self) { genre in
                                Text(genre.uppercased())
                                    .font(.system(size: 8, weight: .medium))
                                    .tracking(0.8)
                                    .foregroundColor(.black.opacity(0.6))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .stroke(Color.black.opacity(0.15), lineWidth: 0.5)
                                    )
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 150)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(Text("\(media.title), \(media.year)"))
        .accessibilityHint("Opens details")
        .sheet(isPresented: $showDetail) {
            if let anime = media as? Anime {
                AnimeDetailView(anime: anime)
            } else if let manga = media as? Manga {
                MangaDetailView(manga: manga)
            }
        }
    }
}

// MARK: - Elegant 2-Column Discover Card (Legacy - Kept for Collection/Search)
struct DiscoverCardElegant: View {
    let media: any MediaDisplayable
    @State private var showDetail = false

    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        }) {
            VStack(alignment: .leading, spacing: 0) {
                // Cover image with elegant portrait aspect ratio
                KuroCachedAsyncImage(url: URL(string: media.imageURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.6)
                                .foregroundColor(.kuroTextTertiary)
                        )
                }
                .aspectRatio(0.7, contentMode: .fill) // Elegant portrait ratio
                .clipped()
                .cornerRadius(0) // Sharp corners for minimalism

                // Minimal info section
                VStack(alignment: .leading, spacing: 6) {
                    // Title - elegant serif
                    Text(media.title.uppercased())
                        .font(.system(size: 13, weight: .light, design: .serif))
                        .tracking(0.5)
                        .foregroundColor(.black.opacity(0.9))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Year and type - minimal metadata
                    HStack(spacing: 4) {
                        Text(media.year)
                            .font(.system(size: 9, weight: .light))
                            .tracking(0.8)
                            .foregroundColor(.black.opacity(0.5))

                        if let rating = media.rating {
                            Text("·")
                                .foregroundColor(.kuroTextTertiary)
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 9, weight: .light))
                                .tracking(0.8)
                                .foregroundColor(.black.opacity(0.5))
                        }
                    }
                }
                .frame(height: 72)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(Text("\(media.title), \(media.year)"))
        .accessibilityHint("Opens details")
        .sheet(isPresented: $showDetail) {
            if let anime = media as? Anime {
                AnimeDetailView(anime: anime)
            } else if let manga = media as? Manga {
                MangaDetailView(manga: manga)
            }
        }
    }
}

// MARK: - Elegant Loading Card for 2-Column Grid
struct DiscoverCardLoading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image placeholder
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .aspectRatio(0.7, contentMode: .fill)
                .overlay(
                    ProgressView()
                        .scaleEffect(0.6)
                        .foregroundColor(.kuroTextTertiary)
                )

            // Info placeholder
            VStack(alignment: .leading, spacing: 6) {
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(height: 13)
                    .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(height: 9)
                    .frame(width: 60)
            }
            .frame(height: 72)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }
}

// MARK: - Real Firebase Data Components (Original Featured Card - kept for reference)
struct FeaturedCardReal: View {
    let media: any MediaDisplayable
    @State private var showDetail = false
    
    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        }) {
            VStack(alignment: .leading, spacing: 0) {
                // Real image or placeholder
                KuroCachedAsyncImage(url: URL(string: media.imageURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .overlay(
                            Text("IMAGE")
                                .font(.system(size: 24, weight: .ultraLight))
                                .foregroundColor(.kuroTextTertiary)
                        )
                }
                .frame(maxWidth: .infinity)
                .frame(height: 420)
                .clipped()
                
                VStack(alignment: .leading, spacing: 12) {
                    Text(media.title.uppercased())
                        .font(.system(size: 20, weight: .ultraLight, design: .serif))
                        .tracking(0.5)
                        .foregroundColor(.black)
                    
                    Text("\(media.year)")
                        .font(.system(size: 11, weight: .regular))
                        .tracking(1.5)
                        .foregroundColor(.black.opacity(0.5))
                    
                    Text(media.displayDescription)
                        .font(.system(size: 11, weight: .light))
                        .tracking(1.0)
                        .foregroundColor(.black.opacity(0.6))
                        .lineSpacing(4)
                        .lineLimit(3)
                }
                .padding(.vertical, 24)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            if let anime = media as? Anime {
                AnimeDetailView(anime: anime)
            } else if let manga = media as? Manga {
                MangaDetailView(manga: manga)
            }
        }
    }
}

struct FeaturedCardLoading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(maxWidth: .infinity)
                .frame(height: 420)
                .overlay(
                    ProgressView()
                        .scaleEffect(0.8)
                        .foregroundColor(.kuroTextTertiary)
                )
            
            VStack(alignment: .leading, spacing: 12) {
                Rectangle()
                    .fill(Color.black.opacity(0.1))
                    .frame(height: 20)
                    .frame(maxWidth: .infinity)
                
                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(height: 12)
                    .frame(width: 60)
                
                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(height: 12)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 24)
        }
    }
}



// MARK: - Preview
#Preview {
    ContentView()
        .environment(SupabaseService.shared)
}
