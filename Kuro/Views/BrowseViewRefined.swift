// MARK: - BROWSE VIEW REFINED
// Premium filter-based discovery with evolved card design
// Structure preserved, style elevated

import SwiftUI

struct BrowseViewRefined: View {
    @Environment(SupabaseService.self) private var supabaseService
    
    // MARK: - Filter State
    @State private var selectedGenre: String? = nil
    @State private var selectedLengthFilter: LengthFilter? = nil
    @State private var selectedStatusFilter: StatusFilter? = nil
    @State private var selectedSort: SupabaseService.BrowseSort = .popular
    @State private var showAnime = true
    @State private var showFiltersSheet: Bool = false
    
    // MARK: - Data State
    @State private var animeResults: [Anime] = []
    @State private var mangaResults: [Manga] = []
    @State private var currentPage: Int = 0
    @State private var hasMore: Bool = true
    @State private var isLoadingResults: Bool = false
    @State private var reloadTask: Task<Void, Never>? = nil
    
    private let pageSize: Int = 60
    private let allGenres: [String] = [
        "Action", "Adventure", "Comedy", "Drama", "Ecchi", "Fantasy", "Hentai", "Horror",
        "Mahou Shoujo", "Mecha", "Music", "Mystery", "Psychological", "Romance", "Sci-Fi",
        "Slice of Life", "Sports", "Supernatural", "Thriller"
    ]
    
    enum LengthFilter: String, CaseIterable {
        case short = "SHORT (1-13)"
        case standard = "STANDARD (14-26)"
        case long = "LONG (27-99)"
        case epic100 = "100+ EPS"
        case epic200 = "200+ EPS"
        case manga200 = "200+ CH"
        
        var episodeRange: (min: Int, max: Int?)? {
            switch self {
            case .short: return (1, 13)
            case .standard: return (14, 26)
            case .long: return (27, 99)
            case .epic100: return (100, nil)
            case .epic200: return (200, nil)
            case .manga200: return nil
            }
        }
        
        var chapterRange: (min: Int, max: Int?)? {
            switch self {
            case .manga200: return (200, nil)
            default: return nil
            }
        }
    }
    
    enum StatusFilter: String, CaseIterable {
        case finished = "FINISHED"
        case airing = "AIRING"
        
        var statusValue: String {
            switch self {
            case .finished: return "FINISHED"
            case .airing: return "RELEASING"
            }
        }
    }
    
    private var displayItems: [any MediaDisplayable] {
        showAnime ? animeResults : mangaResults
    }
    
    private var hasActiveFilters: Bool {
        selectedStatusFilter != nil
        || selectedLengthFilter != nil
        || selectedGenre != nil
        || selectedSort != .popular
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // MARK: - Control Bar
                BrowseControlBarRefined(
                    showAnime: $showAnime,
                    selectedSort: $selectedSort,
                    selectedStatusFilter: $selectedStatusFilter,
                    selectedLengthFilter: $selectedLengthFilter,
                    selectedGenre: $selectedGenre,
                    allGenres: allGenres,
                    hasActiveFilters: hasActiveFilters,
                    onOpenFilters: { showFiltersSheet = true },
                    onClear: clearFilters
                )
                
                // MARK: - Results
                ScrollView(.vertical, showsIndicators: false) {
                    if displayItems.isEmpty {
                        if isLoadingResults {
                            BrowseGridSkeletonRefined(geometry: geometry)
                        } else {
                            BrowseEmptyStateRefined()
                        }
                    } else {
                        BrowseResultsView(
                            items: displayItems,
                            geometry: geometry,
                            onLoadMore: fetchNextPage
                        )
                    }
                    
                    if isLoadingResults && !displayItems.isEmpty {
                        ProgressView()
                            .padding(.vertical, 24)
                    }
                }
                .refreshable {
                    reloadTask?.cancel()
                    await reload()
                }
            }
        }
        .background(Color.white)
        .sheet(isPresented: $showFiltersSheet) {
            BrowseFiltersSheetRefined(
                showAnime: showAnime,
                selectedSort: selectedSort,
                selectedStatusFilter: selectedStatusFilter,
                selectedLengthFilter: selectedLengthFilter,
                selectedGenre: selectedGenre,
                allGenres: allGenres,
                onApply: applyFilters
            )
        }
        .onAppear { scheduleReload() }
        .onChange(of: showAnime) { _, _ in scheduleReload() }
        .onChange(of: selectedGenre) { _, _ in scheduleReload() }
        .onChange(of: selectedLengthFilter) { _, _ in scheduleReload() }
        .onChange(of: selectedStatusFilter) { _, _ in scheduleReload() }
        .onChange(of: selectedSort) { _, _ in scheduleReload() }
    }
    
    private func clearFilters() {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedStatusFilter = nil
            selectedLengthFilter = nil
            selectedGenre = nil
            selectedSort = .popular
        }
    }
    
    private func applyFilters(_ selection: BrowseFiltersSheetRefined.Selection) {
        withAnimation(.easeInOut(duration: 0.2)) {
            showAnime = selection.showAnime
            selectedSort = selection.sort
            selectedStatusFilter = selection.status
            selectedLengthFilter = selection.length
            selectedGenre = selection.genre
        }
    }
    
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            if Task.isCancelled { return }
            await reload()
        }
    }
    
    private func reload() async {
        currentPage = 0
        hasMore = true
        if showAnime {
            animeResults = []
        } else {
            mangaResults = []
        }
        await fetchNextPage()
    }
    
    private func fetchNextPage() async {
        guard hasMore, !isLoadingResults else { return }
        isLoadingResults = true
        defer { isLoadingResults = false }
        
        if showAnime {
            let range = selectedLengthFilter?.episodeRange
            let page = await supabaseService.fetchBrowseAnimePage(
                genre: selectedGenre,
                status: selectedStatusFilter?.statusValue,
                minEpisodes: range?.min,
                maxEpisodes: range?.max,
                sort: selectedSort,
                page: currentPage,
                pageSize: pageSize
            )
            animeResults.append(contentsOf: page)
            hasMore = page.count == pageSize
        } else {
            let range = selectedLengthFilter?.chapterRange
            let page = await supabaseService.fetchBrowseMangaPage(
                genre: selectedGenre,
                status: selectedStatusFilter?.statusValue,
                minChapters: range?.min,
                maxChapters: range?.max,
                sort: selectedSort,
                page: currentPage,
                pageSize: pageSize
            )
            mangaResults.append(contentsOf: page)
            hasMore = page.count == pageSize
        }
        
        if hasMore { currentPage += 1 }
    }
}

// MARK: - Results View
struct BrowseResultsView: View {
    let items: [any MediaDisplayable]
    let geometry: GeometryProxy
    let onLoadMore: () async -> Void
    
    private var featured: (any MediaDisplayable)? { items.first }
    private var gridItems: [any MediaDisplayable] { Array(items.dropFirst()) }
    
    private var gridMetrics: (columns: [GridItem], cardWidth: CGFloat, cardHeight: CGFloat) {
        let spacing: CGFloat = 12
        let padding: CGFloat = 20
        let availableWidth = geometry.size.width - (2 * padding) - spacing
        let cardWidth = floor(availableWidth / 2)
        let imageHeight = cardWidth / 0.7
        let cardHeight = imageHeight + 8 + 52
        
        let columns = [
            GridItem(.fixed(cardWidth), spacing: spacing),
            GridItem(.fixed(cardWidth), spacing: spacing)
        ]
        
        return (columns, cardWidth, cardHeight)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Featured Hero
            if let featured = featured {
                VStack(alignment: .leading, spacing: 12) {
                    Text("PICK FOR YOU")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.5)
                        .foregroundColor(.black.opacity(0.5))
                        .padding(.horizontal, 20)
                    
                    KuroHeroCard(
                        media: featured,
                        width: geometry.size.width - 40
                    )
                    .padding(.horizontal, 20)
                }
                .padding(.top, 16)
            }
            
            // Grid
            if !gridItems.isEmpty {
                let metrics = gridMetrics
                
                LazyVGrid(columns: metrics.columns, spacing: 16) {
                    ForEach(Array(gridItems.enumerated()), id: \.offset) { index, media in
                        KuroPortraitCard(
                            media: media,
                            cardWidth: metrics.cardWidth,
                            cardHeight: metrics.cardHeight
                        )
                        .onAppear {
                            if index == gridItems.count - 1 {
                                Task { await onLoadMore() }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 24)
    }
}

// MARK: - Refined Control Bar
struct BrowseControlBarRefined: View {
    @Binding var showAnime: Bool
    @Binding var selectedSort: SupabaseService.BrowseSort
    @Binding var selectedStatusFilter: BrowseViewRefined.StatusFilter?
    @Binding var selectedLengthFilter: BrowseViewRefined.LengthFilter?
    @Binding var selectedGenre: String?
    
    let allGenres: [String]
    let hasActiveFilters: Bool
    let onOpenFilters: () -> Void
    let onClear: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Top Row: Mode Toggle + Filters Button
            HStack(spacing: 0) {
                // Mode Toggle
                HStack(spacing: 0) {
                    ModeToggleButton(
                        title: "ANIME",
                        isSelected: showAnime
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAnime = true
                        }
                    }
                    
                    ModeToggleButton(
                        title: "MANGA",
                        isSelected: !showAnime
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAnime = false
                        }
                    }
                }
                
                Spacer()
                
                // Filters Button
                Button(action: {
                    KuroAccessibility.impactHaptic(.light)
                    onOpenFilters()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .semibold))
                        Text("FILTERS")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.0)
                        
                        if hasActiveFilters {
                            FilterCountBadge()
                        }
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.04))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.black.opacity(0.1), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            
            // Filter Pills Row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterPillRefined(
                        label: selectedSort.rawValue,
                        isActive: selectedSort != .popular
                    )
                    
                    FilterPillRefined(
                        label: selectedStatusFilter?.rawValue ?? "ALL STATUS",
                        isActive: selectedStatusFilter != nil
                    )
                    
                    FilterPillRefined(
                        label: selectedLengthFilter?.rawValue ?? (showAnime ? "ANY LENGTH" : "ANY CHAPTERS"),
                        isActive: selectedLengthFilter != nil
                    )
                    
                    FilterPillRefined(
                        label: selectedGenre?.uppercased() ?? "ALL GENRES",
                        isActive: selectedGenre != nil
                    )
                    
                    if hasActiveFilters {
                        ClearFiltersButton(onTap: onClear)
                    }
                }
                .padding(.horizontal, 20)
            }
            .kuroSwipeExclusionZone()
            
            // Divider
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 0.5)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - Mode Toggle Button
struct ModeToggleButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            action()
        }) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .tracking(0.5)
                .foregroundColor(isSelected ? .black : .black.opacity(0.4))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Rectangle()
                        .fill(Color.clear)
                        .overlay(
                            Rectangle()
                                .fill(Color.black)
                                .frame(height: isSelected ? 2 : 0)
                                .opacity(isSelected ? 1 : 0),
                            alignment: .bottom
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Filter Count Badge
struct FilterCountBadge: View {
    var body: some View {
        Text("●")
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.black)
            )
    }
}

// MARK: - Filter Pill Refined
struct FilterPillRefined: View {
    let label: String
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: isActive ? .semibold : .medium))
                .tracking(0.8)
            
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .opacity(0.5)
        }
        .foregroundColor(isActive ? .white : .black.opacity(0.7))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(isActive ? Color.black : Color.black.opacity(0.04))
        )
        .overlay(
            Capsule()
                .stroke(Color.black.opacity(isActive ? 0 : 0.1), lineWidth: 0.5)
        )
    }
}

// MARK: - Clear Filters Button
struct ClearFiltersButton: View {
    let onTap: () -> Void
    
    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            onTap()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                Text("CLEAR")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
            }
            .foregroundColor(.black.opacity(0.6))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .stroke(Color.black.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Skeleton Loading
struct BrowseGridSkeletonRefined: View {
    let geometry: GeometryProxy
    
    var body: some View {
        let spacing: CGFloat = 12
        let padding: CGFloat = 20
        let availableWidth = geometry.size.width - (2 * padding) - spacing
        let cardWidth = floor(availableWidth / 2)
        let imageHeight = cardWidth / 0.7
        
        LazyVGrid(
            columns: [
                GridItem(.fixed(cardWidth), spacing: spacing),
                GridItem(.fixed(cardWidth), spacing: spacing)
            ],
            spacing: 16
        ) {
            ForEach(0..<8, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.05))
                        .frame(width: cardWidth, height: imageHeight)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.black.opacity(0.08))
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.black.opacity(0.05))
                            .frame(height: 10)
                            .frame(maxWidth: cardWidth * 0.6)
                    }
                    .frame(height: 36)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .redacted(reason: .placeholder)
    }
}

// MARK: - Empty State
struct BrowseEmptyStateRefined: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles.magnifyingglass")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundColor(.black.opacity(0.12))
            
            VStack(spacing: 6) {
                Text("NO MATCHES")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1.0)
                    .foregroundColor(.black.opacity(0.5))
                
                Text("Try adjusting your filters")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.black.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }
}

// MARK: - Filters Sheet
struct BrowseFiltersSheetRefined: View {
    struct Selection {
        var showAnime: Bool
        var sort: SupabaseService.BrowseSort
        var status: BrowseViewRefined.StatusFilter?
        var length: BrowseViewRefined.LengthFilter?
        var genre: String?
    }
    
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Selection
    
    let allGenres: [String]
    let onApply: (Selection) -> Void
    
    init(
        showAnime: Bool,
        selectedSort: SupabaseService.BrowseSort,
        selectedStatusFilter: BrowseViewRefined.StatusFilter?,
        selectedLengthFilter: BrowseViewRefined.LengthFilter?,
        selectedGenre: String?,
        allGenres: [String],
        onApply: @escaping (Selection) -> Void
    ) {
        self._draft = State(initialValue: Selection(
            showAnime: showAnime,
            sort: selectedSort,
            status: selectedStatusFilter,
            length: selectedLengthFilter,
            genre: selectedGenre
        ))
        self.allGenres = allGenres
        self.onApply = onApply
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Mode
                    FilterSection(title: "MODE") {
                        ModeToggleButton(
                            title: "ANIME",
                            isSelected: draft.showAnime
                        ) { draft.showAnime = true }
                        
                        ModeToggleButton(
                            title: "MANGA",
                            isSelected: !draft.showAnime
                        ) { draft.showAnime = false }
                    }
                    
                    // Sort
                    FilterSection(title: "SORT BY") {
                        FlowLayout(spacing: 10) {
                            ForEach(SupabaseService.BrowseSort.allCases, id: \.self) { sort in
                                FilterOptionChip(
                                    title: sort.rawValue,
                                    isSelected: draft.sort == sort
                                ) { draft.sort = sort }
                            }
                        }
                    }
                    
                    // Status
                    FilterSection(title: "STATUS") {
                        FlowLayout(spacing: 10) {
                            FilterOptionChip(
                                title: "ALL",
                                isSelected: draft.status == nil
                            ) { draft.status = nil }
                            
                            ForEach(BrowseViewRefined.StatusFilter.allCases, id: \.self) { status in
                                FilterOptionChip(
                                    title: status.rawValue,
                                    isSelected: draft.status == status
                                ) { draft.status = status }
                            }
                        }
                    }
                    
                    // Length
                    FilterSection(title: draft.showAnime ? "EPISODE COUNT" : "CHAPTER COUNT") {
                        FlowLayout(spacing: 10) {
                            FilterOptionChip(
                                title: "ANY",
                                isSelected: draft.length == nil
                            ) { draft.length = nil }
                            
                            let validFilters = BrowseViewRefined.LengthFilter.allCases.filter { f in
                                (draft.showAnime && f != .manga200) || (!draft.showAnime && f == .manga200)
                            }
                            
                            ForEach(validFilters, id: \.self) { length in
                                FilterOptionChip(
                                    title: length.rawValue,
                                    isSelected: draft.length == length
                                ) { draft.length = length }
                            }
                        }
                    }
                    
                    // Genre
                    FilterSection(title: "GENRE") {
                        FlowLayout(spacing: 10) {
                            FilterOptionChip(
                                title: "ALL",
                                isSelected: draft.genre == nil
                            ) { draft.genre = nil }
                            
                            ForEach(allGenres, id: \.self) { genre in
                                FilterOptionChip(
                                    title: genre.uppercased(),
                                    isSelected: draft.genre == genre
                                ) { draft.genre = genre }
                            }
                        }
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.white)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        KuroAccessibility.impactHaptic(.light)
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .regular))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        KuroAccessibility.impactHaptic(.light)
                        onApply(draft)
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .semibold))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Filter Section
struct FilterSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(.black.opacity(0.5))
                .padding(.horizontal, 20)
            
            content
                .padding(.horizontal, 20)
        }
    }
}

// MARK: - Filter Option Chip
struct FilterOptionChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            action()
        }) {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                .tracking(0.8)
                .foregroundColor(isSelected ? .white : .black.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.black : Color.black.opacity(0.04))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(isSelected ? 0 : 0.1), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}
