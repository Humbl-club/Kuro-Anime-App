// uses PosterView.swift
import SwiftUI

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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
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
            Color.white.ignoresSafeArea()
            
            VStack(spacing: 8) {
                Text("KURO")
                    .font(.system(size: 24, weight: .ultraLight, design: .serif))
                    .tracking(8)
                    .foregroundColor(.black)
                    .opacity(logoOpacity)
                
                Text("CURATED ANIME")
                    .font(.system(size: 10, weight: .light))
                    .tracking(3)
                    .foregroundColor(.black.opacity(0.5))
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
    // Removed: @State private var currentSection = 0
    // Removed: @State private var selectedMood: String? = nil
    // Removed: @State private var dragOffset: CGFloat = 0
    // Removed: let sections = ["DISCOVER", "COLLECTION", "SEARCH"]

    enum Section: Int, CaseIterable {
        case discover, concierge, collection, browse, search

        var title: String {
            switch self {
            case .discover:
                return "DISCOVER"
            case .concierge:
                return "CONCIERGE"
            case .collection:
                return "COLLECTION"
            case .browse:
                return "BROWSE"
            case .search:
                return "SEARCH"
            }
        }
    }

    @State private var selection: Section = .discover
    @State private var showProfile = false
    @State private var mountedSections: Set<Section> = [.discover]
    
	    var body: some View {
	        ZStack {
	            Color.white.ignoresSafeArea()
	            
	            VStack(spacing: 0) {
	                // Fixed Header - Three-part layout
	                KuroHeaderNew(selection: $selection, showProfile: $showProfile)
	                
	                // Keep tabs snappy without breaking vertical scrolling: mount on first visit, then keep alive.
                    ZStack {
                        if mountedSections.contains(.concierge) {
                            ConciergeView()
                                .opacity(selection == .concierge ? 1 : 0)
                                .allowsHitTesting(selection == .concierge)
                        }

                        EditorialDiscoverView()
                            .opacity(selection == .discover ? 1 : 0)
                            .allowsHitTesting(selection == .discover)

                        if mountedSections.contains(.collection) {
                            EditorialCollectionView()
                                .opacity(selection == .collection ? 1 : 0)
                                .allowsHitTesting(selection == .collection)
                        }

                        if mountedSections.contains(.browse) {
                            BrowseView()
                                .opacity(selection == .browse ? 1 : 0)
                                .allowsHitTesting(selection == .browse)
                        }

                        if mountedSections.contains(.search) {
                            EditorialSearchView()
                                .opacity(selection == .search ? 1 : 0)
                                .allowsHitTesting(selection == .search)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
	                .background(Color.clear)
	            }
	        }
            .onChange(of: selection) { _, newValue in
                mountedSections.insert(newValue)
            }
	        .sheet(isPresented: $showProfile) {
	            SettingsView()
        }
    }
}

// MARK: - New Responsive Header Component (Fixed)
struct KuroHeaderNew: View {
    @Binding var selection: KuroMainView.Section
    @Binding var showProfile: Bool
    
    private let swipeOrder: [KuroMainView.Section] = [.concierge, .discover, .collection, .browse, .search]
    private let swipeThreshold: CGFloat = 60
    
    private var currentTitle: String { selection.title }
    private var canSwipeLeft: Bool {
        guard let i = swipeOrder.firstIndex(of: selection) else { return false }
        return i > 0
    }
    private var canSwipeRight: Bool {
        guard let i = swipeOrder.firstIndex(of: selection) else { return false }
        return i < (swipeOrder.count - 1)
    }

	    var body: some View {
	        VStack(spacing: 0) {
            // Three-part layout with proper spacing
            HStack(alignment: .center) {
                // Left: Brand (30% opacity)
                Text("KURO")
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.5)
                    .foregroundColor(.black.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Center: Section (full opacity)
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.black.opacity(canSwipeLeft ? 0.25 : 0.0))
                            .frame(width: 10)
                            .accessibilityHidden(true)

                        Text(currentTitle)
                            .font(.system(size: 11, weight: .regular))
                            .tracking(1.5)
                            .foregroundColor(.black)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.black.opacity(canSwipeRight ? 0.25 : 0.0))
                            .frame(width: 10)
                            .accessibilityHidden(true)
                    }

                    Capsule(style: .continuous)
                        .fill(Color.black.opacity((canSwipeLeft || canSwipeRight) ? 0.14 : 0.0))
                        .frame(width: 34, height: 2)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                // Right: Action (minimal interaction)
                HStack {
                    Spacer()
                    Button(action: {
                        KuroAccessibility.impactHaptic(.light)
                        showProfile.toggle()
                    }) {
                        Circle()
                            .fill(Color.black.opacity(0.08))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text("M")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(.black)
                            )
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Opens settings")
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
            .gesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .local)
                    .onEnded { value in
                        let dx = value.translation.width
                        guard abs(dx) >= swipeThreshold else { return }
                        guard let currentIndex = swipeOrder.firstIndex(of: selection) else { return }
                        // User preference: swipe left -> concierge (previous), swipe right -> next.
                        let nextIndex = currentIndex + (dx < 0 ? -1 : 1)
                        guard swipeOrder.indices.contains(nextIndex) else { return }
                        // Keep the gesture snappy; avoid the page-swipe animation which can feel like a reload.
                        withTransaction(Transaction(animation: nil)) {
                            selection = swipeOrder[nextIndex]
                        }
                    }
            )

	            // Subtle divider
	            Rectangle()
	                .fill(Color.black.opacity(0.08))
	                .frame(height: 0.5)
	        }
	        .frame(height: 48)
	        .background(Color.white)
	        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 6)
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
                        .foregroundColor(.black.opacity(0.35))
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
                        .foregroundColor(.black.opacity(0.2))
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
                        .foregroundColor(.black.opacity(0.35))
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
            Text("LOADING YOUR COLLECTION...")
                .font(.system(size: 14, weight: .light))
                .tracking(1.0)
                .foregroundColor(.black.opacity(0.6))

            Text("Connecting to Supabase...")
                .font(.system(size: 12, weight: .light))
                .tracking(0.5)
                .foregroundColor(.black.opacity(0.3))

            ProgressView()
                .scaleEffect(0.8)
                .padding(.top, 20)
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

// MARK: - New Search View (Single Column)
struct SearchViewNew: View {
    @Environment(SupabaseService.self) private var supabaseService
    @State private var searchText: String = ""
    @State private var selectedCategories: Set<String> = []
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var sheetAnime: Anime? = nil
    @State private var mediaIsManga: Bool = false
    // Season filter (explicit control)
    @State private var selectedSeasonNameSearch: String = {
        let m = Calendar.current.component(.month, from: Date())
        switch m { case 12,1,2: return "WINTER"; case 3,4,5: return "SPRING"; case 6,7,8: return "SUMMER"; default: return "FALL" }
    }()
    @State private var selectedSeasonYearSearch: Int = Calendar.current.component(.year, from: Date())

    // Filter results based on search and categories
    private var filteredAnimeResults: [Anime] {
        let base = searchText.isEmpty ? supabaseService.animeItems : supabaseService.searchAnimeItems
        var results = base
        
        // Apply text search
        if !searchText.isEmpty {
            results = results.filter { media in
                media.title.localizedCaseInsensitiveContains(searchText) ||
                media.displayDescription.localizedCaseInsensitiveContains(searchText) ||
                media.genres?.contains { $0.localizedCaseInsensitiveContains(searchText) } ?? false
            }
        }
        
        // Apply category filters
        if !selectedCategories.isEmpty {
            results = results.filter { media in
                selectedCategories.contains { category in
                    switch category {
                    case "TRENDING":
                        return (media.averageScore ?? 0) > 80
                    case "NEW SEASON":
                        return Int(media.year) ?? 0 >= 2020
                    case "CLASSICS":
                        return Int(media.year) ?? 0 < 2010
                    case "HIDDEN GEMS":
                        return (media.averageScore ?? 0) > 85 && Int(media.year) ?? 0 < 2015
                    default:
                        return false
                    }
                }
            }
        }
        
        return results
    }
    
    private var filteredMangaResults: [Manga] {
        let base = searchText.isEmpty ? supabaseService.mangaItems : supabaseService.searchMangaItems
        var results = base
        if !searchText.isEmpty {
            results = results.filter { media in
                media.title.localizedCaseInsensitiveContains(searchText) ||
                media.displayDescription.localizedCaseInsensitiveContains(searchText) ||
                media.genres?.contains { $0.localizedCaseInsensitiveContains(searchText) } ?? false
            }
        }
        if !selectedCategories.isEmpty {
            results = results.filter { media in
                selectedCategories.contains { category in
                    switch category {
                    case "TRENDING":
                        return (media.averageScore ?? 0) > 80
                    case "NEW SEASON":
                        return (media.startDateYear ?? 0) >= 2020
                    case "CLASSICS":
                        return (media.startDateYear ?? 0) < 2010
                    case "HIDDEN GEMS":
                        return (media.averageScore ?? 0) > 85 && (media.startDateYear ?? 0) < 2015
                    default:
                        return false
                    }
                }
            }
        }
        return results
    }
    
    var body: some View {
        GeometryReader { geometry in
            let horizontalPadding = max(geometry.size.width * 0.05, 20)
            
            VStack(spacing: 0) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.black.opacity(0.3))
                        .font(.system(size: 16, weight: .light))
                    
                    TextField("SEARCH ANIME", text: $searchText)
                        .font(.system(size: 14, weight: .light))
                        .tracking(0.5)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.black.opacity(0.05))
                .cornerRadius(0)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 24)
                
                // Category pills with selection
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // Media toggle
                        CategoryPillSelectable(
                            title: mediaIsManga ? "MANGA" : "ANIME",
                            isSelected: true,
                            action: {
                                mediaIsManga.toggle()
                                if mediaIsManga && supabaseService.mangaItems.isEmpty {
                                    Task { await supabaseService.prefetchManga(total: 300) }
                                }
                            }
                        )
                        ForEach(["TRENDING", "TRENDING AIRING", "AIRING", "THIS SEASON", "SEASON", "NEW SEASON", "CLASSICS", "HIDDEN GEMS"], id: \.self) { category in
                            CategoryPillSelectable(
                                title: category,
                                isSelected: selectedCategories.contains(category)
                            ) {
                                if selectedCategories.contains(category) {
                                    selectedCategories.remove(category)
                                } else {
                                    selectedCategories.insert(category)
                                }
                                // Trigger debounced search with new filters
                                debounceSearch()
                            }
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                }
                .padding(.vertical, 20)

                // Reset filters
                HStack {
                    Button(action: {
                        KuroAccessibility.impactHaptic(.light)
                        selectedCategories.removeAll()
                        // Reset season selector to current
                        let m = Calendar.current.component(.month, from: Date())
                        selectedSeasonNameSearch = (m == 12 || m == 1 || m == 2) ? "WINTER" : (m <= 5 ? "SPRING" : (m <= 8 ? "SUMMER" : "FALL"))
                        selectedSeasonYearSearch = Calendar.current.component(.year, from: Date())
                        debounceSearch()
                    }) {
                        Text("RESET FILTERS")
                            .font(.system(size: 10, weight: .regular))
                            .tracking(1.2)
                            .foregroundColor(.black.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.black.opacity(0.2), lineWidth: 0.5)
                            )
                    }
                    Spacer()
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 8)
                
                // Season picker controls (visible when SEASON facet is active)
                if selectedCategories.contains("SEASON") {
                    HStack(spacing: 8) {
                        Button(action: {
                            KuroAccessibility.impactHaptic(.light)
                            previousSeasonSearch()
                            debounceSearch()
                        }) {
                            Image(systemName: "chevron.left").foregroundColor(.black.opacity(0.6))
                        }
                        Text("\(selectedSeasonNameSearch) \(selectedSeasonYearSearch)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.black)
                        Button(action: {
                            KuroAccessibility.impactHaptic(.light)
                            nextSeasonSearch()
                            debounceSearch()
                        }) {
                            Image(systemName: "chevron.right").foregroundColor(.black.opacity(0.6))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, horizontalPadding)
                }
                
                // Search Results with single column layout
                if !searchText.isEmpty || !selectedCategories.isEmpty {
                    if supabaseService.isLoading {
                        ProgressView("Searching...")
                            .padding(.top, 40)
                    } else if filteredAnimeResults.isEmpty {
                        VStack(spacing: 8) {
                            Text("NO RESULTS FOUND")
                                .font(.system(size: 11, weight: .regular))
                                .tracking(1.5)
                                .foregroundColor(.black.opacity(0.3))
                            
                            Text("Try adjusting your search or filters")
                                .font(.system(size: 10, weight: .light))
                                .tracking(1.0)
                                .foregroundColor(.black.opacity(0.2))
                        }
                        .padding(.top, 60)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            // Collection grid with DESIGN-SYSTEM spacing & fixed card size
                            let metrics = KuroCardMetrics.grid(for: geometry.size.width, columns: 2)
                            let columns = metrics.columns
                            let cardWidth = metrics.cardWidth
                            let cardHeight = metrics.cardHeight
                            
                            LazyVGrid(
                                columns: columns,
                                alignment: .center,
                                spacing: 16
                            ) {
                                if mediaIsManga {
                                    ForEach(filteredMangaResults) { manga in
                                        CollectionCardReal(media: manga)
                                            .frame(width: cardWidth, height: cardHeight, alignment: .top)
                                    }
                                } else {
                                    ForEach(filteredAnimeResults) { anime in
                                        CollectionCardReal(media: anime)
                                            .frame(width: cardWidth, height: cardHeight, alignment: .top)
                                    }
                                }
                            }
                            .padding(.horizontal, KuroCardMetrics.horizontalPadding)
                            .padding(.bottom, 40)
                            
                            // Show More for search base set (API-backed)
                            if mediaIsManga ? supabaseService.hasMoreManga : supabaseService.hasMoreAnime {
                                Button(action: {
                                    KuroAccessibility.impactHaptic(.light)
                                    Task {
                                        if !searchText.isEmpty {
                                            await supabaseService.fetchNextSearchPage()
                                        } else {
                                            if mediaIsManga { await supabaseService.fetchNextMangaPage() }
                                            else { await supabaseService.fetchNextAnimePage() }
                                        }
                                    }
                                }) {
                                    Text("SHOW MORE")
                                        .font(.system(size: 11, weight: .regular))
                                        .tracking(1.5)
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.black.opacity(0.2), lineWidth: 0.5)
                                        )
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, KuroCardMetrics.horizontalPadding)
                                .padding(.top, 8)
                                .padding(.bottom, 20)
                            }
                        }
                        .sheet(item: $sheetAnime) { anime in
                            AnimeDetailView(anime: anime)
                        }
                    }
                } else {
                    Spacer()
                    
                    VStack(spacing: 8) {
                        Text("BEGIN TYPING TO SEARCH")
                            .font(.system(size: 11, weight: .regular))
                            .tracking(1.5)
                            .foregroundColor(.black.opacity(0.3))
                        
                        Text("DISCOVER YOUR NEXT OBSESSION")
                            .font(.system(size: 10, weight: .light))
                            .tracking(1.0)
                            .foregroundColor(.black.opacity(0.2))
                    }
                    .padding(.top, 80)
                    
                    Spacer()
                }
            }
        }
        .onChange(of: searchText) { _, _ in
            debounceSearch()
        }
        .onAppear {
            // Load data if not already loaded
            Task {
                supabaseService.setPageSize(50)
                if supabaseService.animeItems.isEmpty { await supabaseService.prefetchAnime(total: 300) }
                if supabaseService.mangaItems.isEmpty { await supabaseService.prefetchManga(total: 300) }
            }
        }
    }
    
    private func performSearch() {
        Task {
            supabaseService.resetSearch(query: searchText, isManga: mediaIsManga)
            var filters = SupabaseService.SearchFilters(
                trending: selectedCategories.contains("TRENDING") || selectedCategories.contains("TRENDING AIRING"),
                newSeason: selectedCategories.contains("NEW SEASON"),
                classics: selectedCategories.contains("CLASSICS"),
                hiddenGems: selectedCategories.contains("HIDDEN GEMS"),
                airingOnly: selectedCategories.contains("AIRING") || selectedCategories.contains("TRENDING AIRING")
            )
            if selectedCategories.contains("THIS SEASON") {
                let m = Calendar.current.component(.month, from: Date())
                let season: String = (m == 12 || m == 1 || m == 2) ? "WINTER" : (m <= 5 ? "SPRING" : (m <= 8 ? "SUMMER" : "FALL"))
                filters.seasonName = season
                filters.seasonYear = Calendar.current.component(.year, from: Date())
            }
            if selectedCategories.contains("SEASON") {
                filters.seasonName = selectedSeasonNameSearch
                filters.seasonYear = selectedSeasonYearSearch
            }
            supabaseService.setSearchFilters(filters)
            await supabaseService.fetchNextSearchPage()
        }
    }

    private func previousSeasonSearch() {
        let order = ["WINTER","SPRING","SUMMER","FALL"]
        guard let idx = order.firstIndex(of: selectedSeasonNameSearch) else { return }
        let newIdx = (idx + 3) % 4
        if newIdx == 3 && idx == 0 { selectedSeasonYearSearch -= 1 }
        selectedSeasonNameSearch = order[newIdx]
    }

    private func nextSeasonSearch() {
        let order = ["WINTER","SPRING","SUMMER","FALL"]
        guard let idx = order.firstIndex(of: selectedSeasonNameSearch) else { return }
        let newIdx = (idx + 1) % 4
        if newIdx == 0 && idx == 3 { selectedSeasonYearSearch += 1 }
        selectedSeasonNameSearch = order[newIdx]
    }
    
    private func debounceSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled {
                performSearch()
            }
        }
    }
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
                                .foregroundColor(.black.opacity(0.3))
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
                            .foregroundColor(.black.opacity(0.3))
                    } else if let chapters = media.chapters {
                        Text("\(chapters) CH")
                            .font(.system(size: 9, weight: .light))
                            .tracking(0.5)
                            .foregroundColor(.black.opacity(0.3))
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
                                .foregroundColor(.black.opacity(0.3))
                        }
                    }
                    
                    Spacer() // Push chevron to bottom
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .light))
                        .foregroundColor(.black.opacity(0.2))
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
                        .foregroundColor(.black.opacity(0.3))
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
                .fill(Color.white)
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
                                .foregroundColor(.black.opacity(0.3))
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
                    .fill(Color.white)
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
                        .foregroundColor(.black.opacity(0.3))
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
                        .foregroundColor(.black.opacity(0.3))
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
                        .foregroundColor(.black.opacity(0.3))
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
                    .foregroundColor(.black.opacity(0.3))
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .light))
                .foregroundColor(.black.opacity(0.2))
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
                                .foregroundColor(.black.opacity(0.2))
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
                                .foregroundColor(.black.opacity(0.2))
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
                                .foregroundColor(.black.opacity(0.2))
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
                                .foregroundColor(.black.opacity(0.3))
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
                                .foregroundColor(.black.opacity(0.3))
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
                        .foregroundColor(.black.opacity(0.3))
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
                                .foregroundColor(.black.opacity(0.3))
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
                        .foregroundColor(.black.opacity(0.3))
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
