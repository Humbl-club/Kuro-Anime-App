// Editorial Discover View - REDESIGNED
// Functional-first anime discovery with refined aesthetics
// Dense content, efficient browsing, elegant presentation

import SwiftUI

struct EditorialDiscoverView: View {
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(NetworkMonitor.self) private var networkMonitor
    @State private var vm = DiscoverViewModel()
    @State private var isLoadingSections = false
    @State private var didInitialLoad = false
    @State private var bannerMessage: String? = nil
    @State private var loadError = false

    // Premium rails
    @State private var showFullEssentials = false
    @State private var showFullClassics = false
    @State private var showFullNewToYou = false

    @State private var showFullEssentialsManga = false
    @State private var showFullClassicsManga = false
    @State private var showFullNewToYouManga = false

    @State private var showFullTopRated = false
    @State private var showFullTrending = false
    @State private var showFullNewlyAdded = false
    @State private var showFullAiringToday = false
    @State private var showFullCurrentSeason = false

    @State private var showMoreSections = UserDefaults.standard.bool(forKey: "kuro_discover_show_more")
    @State private var selectedMediaType: DiscoverMediaTypeFilter = .all

    enum DiscoverMediaTypeFilter: String, CaseIterable {
        case all = "ALL"
        case anime = "ANIME"
        case manga = "MANGA"
    }

    private var secondarySectionCount: Int {
        var count = 0
        if !vm.classics.isEmpty { count += 1 }
        if !vm.currentSeason.isEmpty { count += 1 }
        if !vm.topRated.isEmpty { count += 1 }
        if !vm.newlyAdded.isEmpty { count += 1 }
        if !vm.classicsManga.isEmpty { count += 1 }
        if !vm.trendingManga.isEmpty { count += 1 }
        if !vm.topRatedManga.isEmpty { count += 1 }
        return count
    }

    private var hasAnyContent: Bool {
        !vm.essentials.isEmpty ||
        !vm.classics.isEmpty ||
        !vm.newToYou.isEmpty ||
        !vm.airingToday.isEmpty ||
        !vm.currentSeason.isEmpty ||
        !vm.trending.isEmpty ||
        !vm.topRated.isEmpty ||
        !vm.newlyAdded.isEmpty ||
        !vm.essentialsManga.isEmpty ||
        !vm.classicsManga.isEmpty ||
        !vm.newToYouManga.isEmpty ||
        !vm.trendingManga.isEmpty ||
        !vm.topRatedManga.isEmpty ||
        !vm.newlyAddedManga.isEmpty
    }

    var body: some View {
        GeometryReader { geo in
            let currentWidth = max(320, geo.size.width)
            ScrollView(.vertical, showsIndicators: false) {
                if isLoadingSections && !hasAnyContent {
                    EditorialLoadingView()
                } else if loadError && !hasAnyContent {
                    VStack(spacing: KuroDesignSpacing.md) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 28, weight: .light))
                            .foregroundColor(.black.opacity(0.25))
                        Text("COULDN'T LOAD")
                            .font(.kuroCaption(weight: .medium))
                            .tracking(1.6)
                            .foregroundColor(.black.opacity(0.55))
                        Text("Check your connection and try again.")
                            .font(.kuroBody(weight: .light))
                            .foregroundColor(.black.opacity(0.40))
                        Button {
                            Task { await refreshSections() }
                        } label: {
                            Text("RETRY")
                                .font(.kuroCaption(weight: .medium))
                                .tracking(1.6)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(Color.black))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, KuroDesignSpacing.sm)
                    }
                    .padding(.top, 80)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Failed to load discover content. Retry button available.")
                } else if !isLoadingSections && !hasAnyContent {
                    EditorialEmptyView(onRetry: {
                        await refreshSections()
                    })
                } else {
                    VStack(spacing: 24) {
                    // Stale data indicator when offline but showing cached content
                    if !networkMonitor.isConnected && hasAnyContent {
                        Text("SHOWING CACHED DATA")
                            .font(.kuroMicro(weight: .medium))
                            .tracking(1.2)
                            .foregroundColor(.kuroTextTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.bottom, 4)
                    }

                    // MARK: Media type filter
                    HStack {
                        Spacer()
                        Menu {
                            ForEach(DiscoverMediaTypeFilter.allCases, id: \.self) { type in
                                Button(type.rawValue) {
                                    selectedMediaType = type
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "rectangle.stack")
                                    .font(.system(size: 9, weight: .regular))
                                Text(selectedMediaType == .all ? "TYPE" : selectedMediaType.rawValue)
                                    .font(.system(size: 9, weight: .medium))
                                    .tracking(0.8)
                            }
                            .foregroundColor(selectedMediaType != .all ? .black : .black.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)

                    // MARK: Primary sections (always visible, ordered by user value)

                    if let featured = vm.featured, (selectedMediaType == .all || selectedMediaType == .anime) {
                        KuroHeroCard(media: featured, width: currentWidth - 40)
                            .padding(.horizontal, 20)
                    }

                    if !vm.airingToday.isEmpty && (selectedMediaType == .all || selectedMediaType == .anime) {
                        CompactHorizontalSection(
                            title: "AIRING TODAY",
                            subtitle: "Next 24 hours",
                            items: Array(vm.airingToday.prefix(10)),
                            containerWidth: currentWidth,
                            onSeeAll: { showFullAiringToday = true }
                        )
                    }

                    if !vm.newToYou.isEmpty && (selectedMediaType == .all || selectedMediaType == .anime) {
                        Dense2ColumnSectionFixed(
                            title: "NEW TO YOU",
                            subtitle: "High score, not in your list",
                            items: Array(vm.newToYou.prefix(8)),
                            screenWidth: currentWidth,
                            onSeeAll: { showFullNewToYou = true }
                        )
                    }

                    if !vm.essentials.isEmpty && (selectedMediaType == .all || selectedMediaType == .anime) {
                        CompactHorizontalSection(
                            title: "ESSENTIAL ANIME",
                            subtitle: "Gateway picks (high confidence)",
                            items: Array(vm.essentials.prefix(10)),
                            containerWidth: currentWidth,
                            onSeeAll: { showFullEssentials = true }
                        )
                    }

                    if !vm.newToYouManga.isEmpty && (selectedMediaType == .all || selectedMediaType == .manga) {
                        Dense2ColumnMangaSectionFixed(
                            title: "NEW TO YOU (MANGA)",
                            subtitle: "High score, not in your list",
                            items: Array(vm.newToYouManga.prefix(8)),
                            screenWidth: currentWidth,
                            onSeeAll: { showFullNewToYouManga = true }
                        )
                    }

                    if !vm.trending.isEmpty && (selectedMediaType == .all || selectedMediaType == .anime) {
                        CompactHorizontalSection(
                            title: "TRENDING",
                            subtitle: "Popular right now",
                            items: vm.trending,
                            containerWidth: currentWidth,
                            onSeeAll: { showFullTrending = true },
                            showFilters: true
                        )
                    }

                    if !vm.essentialsManga.isEmpty && (selectedMediaType == .all || selectedMediaType == .manga) {
                        CompactHorizontalMangaSection(
                            title: "ESSENTIAL MANGA",
                            subtitle: "Foundational reads",
                            items: Array(vm.essentialsManga.prefix(10)),
                            containerWidth: currentWidth,
                            onSeeAll: { showFullEssentialsManga = true }
                        )
                    }

                    // MARK: "Show More" expansion

                    if !showMoreSections && secondarySectionCount > 0 {
                        Button {
                            withAnimation(KuroAnimation.editorial) {
                                showMoreSections = true
                            }
                            UserDefaults.standard.set(true, forKey: "kuro_discover_show_more")
                        } label: {
                            HStack(spacing: 6) {
                                Text("\(secondarySectionCount) MORE SECTIONS")
                                    .font(.kuroCaption(weight: .medium))
                                    .tracking(1.6)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.black.opacity(0.55))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                                    .stroke(Color.black.opacity(0.10), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                    }

                    // MARK: Secondary sections (behind "Show More")

                    if showMoreSections {
                        if !vm.classics.isEmpty && (selectedMediaType == .all || selectedMediaType == .anime) {
                            Dense2ColumnSectionFixed(
                                title: "CLASSICS",
                                subtitle: "Proven greats",
                                items: Array(vm.classics.prefix(8)),
                                screenWidth: currentWidth,
                                onSeeAll: { showFullClassics = true }
                            )
                        }

                        if !vm.currentSeason.isEmpty && (selectedMediaType == .all || selectedMediaType == .anime) {
                            CompactHorizontalSection(
                                title: "CURRENT SEASON",
                                subtitle: "Airing now",
                                items: Array(vm.currentSeason.prefix(10)),
                                containerWidth: currentWidth,
                                onSeeAll: { showFullCurrentSeason = true }
                            )
                        }

                        if !vm.topRated.isEmpty && (selectedMediaType == .all || selectedMediaType == .anime) {
                            Dense2ColumnSectionFixed(
                                title: "TOP RATED",
                                subtitle: "Highest scores",
                                items: vm.topRated,
                                screenWidth: currentWidth,
                                onSeeAll: { showFullTopRated = true },
                                showFilters: true
                            )
                        }

                        if !vm.newlyAdded.isEmpty && (selectedMediaType == .all || selectedMediaType == .anime) {
                            Dense2ColumnSectionFixed(
                                title: "JUST ADDED",
                                subtitle: "Fresh arrivals",
                                items: Array(vm.newlyAdded.prefix(8)),
                                screenWidth: currentWidth,
                                onSeeAll: { showFullNewlyAdded = true }
                            )
                        }

                        if !vm.classicsManga.isEmpty && (selectedMediaType == .all || selectedMediaType == .manga) {
                            Dense2ColumnMangaSectionFixed(
                                title: "MANGA CLASSICS",
                                subtitle: "Proven greats",
                                items: Array(vm.classicsManga.prefix(8)),
                                screenWidth: currentWidth,
                                onSeeAll: { showFullClassicsManga = true }
                            )
                        }

                        if !vm.trendingManga.isEmpty && (selectedMediaType == .all || selectedMediaType == .manga) {
                            CompactHorizontalMangaSection(
                                title: "TRENDING MANGA",
                                subtitle: "Popular manga",
                                items: Array(vm.trendingManga.prefix(10)),
                                containerWidth: currentWidth
                            )
                        }

                        if !vm.topRatedManga.isEmpty && (selectedMediaType == .all || selectedMediaType == .manga) {
                            Dense2ColumnMangaSectionFixed(
                                title: "TOP RATED MANGA",
                                subtitle: "Highest scores",
                                items: Array(vm.topRatedManga.prefix(8)),
                                screenWidth: currentWidth
                            )
                        }
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            }
            // A parent `.scrollDisabled(true)` (e.g. on a paging container) can propagate via environment.
            // Keep Discover scrollable regardless.
            .scrollDisabled(false)
            .background(Color.kuroBackground)
            .refreshable {
                await refreshSections()
            }
            .overlay(alignment: .top) {
                if let bannerMessage {
                    KuroTransientBanner(message: bannerMessage)
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .task {
                if !didInitialLoad {
                    didInitialLoad = true
                    await refreshSections()
                }
            }
        }
        .sheet(isPresented: $showFullEssentials) {
            FullSectionView(title: "ESSENTIAL ANIME", items: vm.essentials)
        }
        .sheet(isPresented: $showFullClassics) {
            FullSectionView(title: "CLASSICS", items: vm.classics)
        }
        .sheet(isPresented: $showFullNewToYou) {
            FullSectionView(title: "NEW TO YOU", items: vm.newToYou)
        }
        .sheet(isPresented: $showFullAiringToday) {
            FullSectionView(title: "AIRING TODAY", items: vm.airingToday)
        }
        .sheet(isPresented: $showFullCurrentSeason) {
            FullSectionView(title: "CURRENT SEASON", items: vm.currentSeason)
        }
        .sheet(isPresented: $showFullTrending) {
            FullSectionView(title: "TRENDING", items: vm.trending)
        }
        .sheet(isPresented: $showFullTopRated) {
            FullSectionView(title: "TOP RATED", items: vm.topRated)
        }
        .sheet(isPresented: $showFullNewlyAdded) {
            FullSectionView(title: "JUST ADDED", items: vm.newlyAdded)
        }
        .sheet(isPresented: $showFullEssentialsManga) {
            FullMangaSectionView(title: "ESSENTIAL MANGA", items: vm.essentialsManga)
        }
        .sheet(isPresented: $showFullClassicsManga) {
            FullMangaSectionView(title: "MANGA CLASSICS", items: vm.classicsManga)
        }
        .sheet(isPresented: $showFullNewToYouManga) {
            FullMangaSectionView(title: "NEW TO YOU (MANGA)", items: vm.newToYouManga)
        }
    }

    private func refreshSections() async {
        let perf = KuroPerf.begin("discover.refresh")
        let shouldSkip = await MainActor.run { () -> Bool in
            if isLoadingSections { return true }
            isLoadingSections = true
            return false
        }
        if shouldSkip {
            KuroPerf.end(perf, message: "skipped (already loading)")
            return
        }
        defer {
            Task { @MainActor in
                isLoadingSections = false
            }
        }

        let hadContentBefore = await MainActor.run { hasAnyContent }

        // Keep local list state up to date for badges/progress, while fetching the server bundle.
        async let _ = supabaseService.fetchUserLists()
        let bundle = await supabaseService.fetchDiscoverBundle(limit: 30, hours: 24, force: true)

        let gotAnyNew = bundle.map { b in
            !(b.anime.essentials.isEmpty && b.anime.classics.isEmpty && b.anime.newToYou.isEmpty &&
              b.anime.trending.isEmpty && b.anime.topRated.isEmpty && b.anime.newlyAdded.isEmpty &&
              b.anime.airingToday.isEmpty && b.anime.currentSeason.isEmpty &&
              b.manga.essentials.isEmpty && b.manga.classics.isEmpty && b.manga.newToYou.isEmpty &&
              b.manga.trending.isEmpty && b.manga.topRated.isEmpty && b.manga.newlyAdded.isEmpty)
        } ?? false

        await MainActor.run {
            guard let bundle else {
                if hadContentBefore {
                    showBanner("Couldn't refresh. Try again.")
                } else {
                    loadError = true
                }
                return
            }
            loadError = false

            vm.essentials = bundle.anime.essentials
            vm.classics = bundle.anime.classics
            vm.newToYou = bundle.anime.newToYou
            vm.trending = bundle.anime.trending
            vm.topRated = bundle.anime.topRated
            vm.newlyAdded = bundle.anime.newlyAdded
            vm.airingToday = bundle.anime.airingToday
            vm.currentSeason = bundle.anime.currentSeason

            vm.essentialsManga = bundle.manga.essentials
            vm.classicsManga = bundle.manga.classics
            vm.newToYouManga = bundle.manga.newToYou
            vm.trendingManga = bundle.manga.trending
            vm.topRatedManga = bundle.manga.topRated
            vm.newlyAddedManga = bundle.manga.newlyAdded

            // Featured: best available from current season, else trending.
            let featuredCandidates = vm.currentSeason.isEmpty ? vm.trending : vm.currentSeason
            vm.featured = featuredCandidates
                .filter { ($0.averageScore ?? 0) > 80 }
                .sorted { ($0.averageScore ?? 0) > ($1.averageScore ?? 0) }
                .first ?? featuredCandidates.first

            if hadContentBefore && !gotAnyNew {
                showBanner("Couldn't refresh. Try again.")
            }
        }

        KuroPerf.end(perf, message: gotAnyNew ? "ok" : "no new data")

        // Prefetch friend tracking counts for card indicators
        if FeatureFlags.shared.isSocialActivityV1Enabled {
            let items: [(mediaType: String, mediaId: Int)] = await MainActor.run {
                let anime = (vm.essentials + vm.trending + vm.topRated + vm.newToYou + vm.newlyAdded + vm.currentSeason)
                    .map { (mediaType: "ANIME", mediaId: $0.id) }
                let manga = (vm.essentialsManga + vm.trendingManga + vm.topRatedManga + vm.newToYouManga + vm.newlyAddedManga)
                    .map { (mediaType: "MANGA", mediaId: $0.id) }
                return Array((anime + manga).prefix(100))
            }
            if !items.isEmpty {
                supabaseService.prefetchFriendCounts(items: items)
            }
        }

        let ladderCandidates: [(mediaType: String, mediaId: Int)] = await MainActor.run {
            var items: [(mediaType: String, mediaId: Int)] = []
            if let featured = vm.featured {
                items.append((mediaType: "ANIME", mediaId: featured.id))
            }
            items += Array(vm.currentSeason.prefix(4)).map { ("ANIME", $0.id) }
            items += Array(vm.trending.prefix(4)).map { ("ANIME", $0.id) }
            items += Array(vm.essentialsManga.prefix(4)).map { ("MANGA", $0.id) }
            return items
        }
        if !ladderCandidates.isEmpty {
            supabaseService.prefetchMediaRelationRefreshRequests(
                items: ladderCandidates,
                reason: "discover_primary"
            )
        }

        // Prefetch covers so the next scroll feels instant.
        let urls: [URL] = await MainActor.run {
            let anime = (vm.essentials.prefix(14) + vm.newToYou.prefix(14) + vm.trending.prefix(14) + vm.topRated.prefix(10))
                .compactMap { URL(string: $0.imageURL ?? "") }
            let manga = (vm.essentialsManga.prefix(14) + vm.newToYouManga.prefix(14) + vm.trendingManga.prefix(14) + vm.topRatedManga.prefix(10))
                .compactMap { URL(string: $0.imageURL ?? "") }
            return Array((anime + manga).prefix(70))
        }
        if !urls.isEmpty {
            Task { await ImagePipeline.shared.prefetch(urls: urls) }
        }
    }

    private func currentSeasonQueryParams() -> (season: String, year: Int) {
        let m = Calendar.current.component(.month, from: Date())
        let season: String
        switch m {
        case 12, 1, 2: season = "WINTER"
        case 3, 4, 5: season = "SPRING"
        case 6, 7, 8: season = "SUMMER"
        default: season = "FALL"
        }
        return (season, Calendar.current.component(.year, from: Date()))
    }

    @MainActor
    private func showBanner(_ message: String) {
        withAnimation(.easeInOut(duration: 0.18)) {
            bannerMessage = message
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation(.easeInOut(duration: 0.18)) {
                bannerMessage = nil
            }
        }
    }
}

// MARK: - Compact Horizontal Section
// Dense horizontal scroll showing many anime
struct CompactHorizontalSection<Item: MediaDisplayable>: View {
    let title: String
    let subtitle: String
    let items: [Item]
    var containerWidth: CGFloat
    var onSeeAll: (() -> Void)? = nil
    var showFilters: Bool = false

    @State private var selectedFilter: AnimeFilter = .all

    enum AnimeFilter: String, CaseIterable {
        case all = "All"
        case short = "Short"
        case long = "Long"
        case completed = "Completed"
    }

    private var filteredItems: [Item] {
        switch selectedFilter {
        case .all:
            return items
        case .short:
            return items.filter { ($0.episodes ?? 0) > 0 && ($0.episodes ?? 0) <= 13 }
        case .long:
            return items.filter { ($0.episodes ?? 0) > 50 }
        case .completed:
            return items.filter { $0.statusRaw == "FINISHED" }
        }
    }

    private var cardWidth: CGFloat {
        // Scale up horizontal cards on large screens while preserving density.
        let candidate = floor((containerWidth - 56) / 2.8)
        return min(144, max(112, candidate))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Clean section header with See All button
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(.black)
                        .accessibilityAddTraits(.isHeader)

                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .tracking(0.3)
                        .foregroundColor(.black.opacity(0.5))
                }

                Spacer()

                if onSeeAll != nil {
                    Button(action: { onSeeAll?() }) {
                        Text("See All")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.black.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 20)

            // Filter chips
            if showFilters {
                VStack(alignment: .leading, spacing: 8) {
                    Text("REFINE THIS RAIL")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.2)
                        .foregroundColor(.kuroTextTertiary)
                        .padding(.horizontal, 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(AnimeFilter.allCases, id: \.self) { filter in
                                FilterChip(
                                    title: filter.rawValue,
                                    isSelected: selectedFilter == filter,
                                    action: { selectedFilter = filter }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .kuroSwipeExclusionZone()
                }
            }

            // Horizontal scroll with compact cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(filteredItems, id: \.id) { anime in
                        KuroCompactCard(media: anime, width: cardWidth)
                    }
                }
                .padding(.horizontal, 20)
            }
            .kuroSwipeExclusionZone()
        }
    }
}

// MARK: - Dense 2-Column Section
// Efficient grid showing maximum anime with infinite scroll
struct Dense2ColumnSection: View {
    let title: String
    let subtitle: String
    let items: [Anime]
    let geometry: GeometryProxy
    @Environment(SupabaseService.self) private var supabaseService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Clean section header
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(.black)

                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .tracking(0.3)
                    .foregroundColor(.black.opacity(0.5))
            }
            .padding(.horizontal, 20)

            // Dense 2-column grid with FIXED card dimensions
            let horizontalPadding: CGFloat = 20
            let spacing: CGFloat = 12
            let totalHorizontalPadding = horizontalPadding * 2
            let totalSpacing = spacing
            let availableWidth = geometry.size.width - totalHorizontalPadding - totalSpacing
            let cardWidth = floor(availableWidth / 2)
            let imageHeight = floor(cardWidth / 0.7)
            let textBlockHeight: CGFloat = 56
            let cardSpacing: CGFloat = 8
            let totalCardHeight = imageHeight + cardSpacing + textBlockHeight

            let columns = [
                GridItem(.fixed(cardWidth), spacing: spacing),
                GridItem(.fixed(cardWidth), spacing: spacing)
            ]

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items, id: \.id) { anime in
                    GridAnimeCard(media: anime, cardWidth: cardWidth, cardHeight: totalCardHeight)
                        .onAppear {
                            // Load more when reaching last item
                            if anime.id == items.last?.id && supabaseService.hasMoreAnime {
                                Task {
                                    await supabaseService.fetchNextAnimePage()
                                }
                            }
                        }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Compact Anime Card (for horizontal scrolls)
// Small, efficient, shows key info
struct CompactAnimeCard: View {
    let media: any MediaDisplayable
    var cardWidth: CGFloat = 110
    @State private var showDetail = false
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    var body: some View {
        let imageHeight: CGFloat = floor(cardWidth / 0.6667)
        // Keep a fixed total height so horizontal rows never "wobble" based on title wrapping.
        let titleHeight: CGFloat = 34
        let metaHeight: CGFloat = 12
        let innerSpacingImageToText: CGFloat = 8
        let innerSpacingTitleToMeta: CGFloat = 4
        let totalHeight = imageHeight + innerSpacingImageToText + titleHeight + innerSpacingTitleToMeta + metaHeight

        VStack(alignment: .leading, spacing: 8) {
                // Image with score badge
                ZStack(alignment: .topTrailing) {
                    KuroCachedAsyncImage(url: URL(string: media.imageURL ?? ""), maxPixelSize: 420) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: cardWidth, height: imageHeight)
                                .clipped()
                        case .failure, .empty:
                            Rectangle()
                                .fill(Color.black.opacity(0.05))
                                .frame(width: cardWidth, height: imageHeight)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: cardWidth, height: imageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    if let rating = media.rating, rating > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.75))
                        )
                        .padding(6)
                    }
                }

                // Title and info
                VStack(alignment: .leading, spacing: 4) {
                    Text(media.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.black)
                        .lineLimit(2)
                        .frame(height: titleHeight, alignment: .top)

                    HStack(spacing: 4) {
                        Text(media.year)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.black.opacity(0.6))

                        if let episodes = media.episodes, episodes > 0 {
                            Text("·")
                                .foregroundColor(.black.opacity(0.4))
                            Text("\(episodes) eps")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(.black.opacity(0.6))
                        } else if let chapters = media.chapters, chapters > 0 {
                            Text("·")
                                .foregroundColor(.black.opacity(0.4))
                            Text("\(chapters) ch")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(.black.opacity(0.6))
                        }
                    }
                    .frame(height: metaHeight, alignment: .topLeading)
                }
                .frame(width: cardWidth)
        }
        .frame(width: cardWidth, height: totalHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .kuroDeliberateTap {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText())
        .accessibilityHint("Opens details")
        .accessibilityAddTraits(.isButton)
        .sheet(isPresented: $showDetail) {
            MediaDetailSheet(kind: media.kind, id: media.id)
        }
    }

    private func accessibilityLabelText() -> Text {
        var parts: [String] = []
        parts.append(media.title)
        if !media.year.isEmpty { parts.append(media.year) }
        if let episodes = media.episodes, episodes > 0 { parts.append("\(episodes) episodes") }
        if let chapters = media.chapters, chapters > 0 { parts.append("\(chapters) chapters") }
        if let rating = media.rating, rating > 0 { parts.append(String(format: "Rating %.1f", rating)) }
        return Text(parts.joined(separator: ", "))
    }
}

// MARK: - Grid Anime Card (for 2-column grids)
// Vertical card optimized for grid layouts with FIXED dimensions
struct GridAnimeCard: View {
    let media: any MediaDisplayable
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    @State private var showDetail = false
    @State private var showAddToList = false
    @State private var showAddToClub = false
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    private var mediaType: String {
        media.kind.rawValue
    }

    private var isInCollection: Bool {
        supabaseService.isInCollection(mediaId: media.id, mediaType: mediaType)
    }

    private static let countFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private func countString(_ value: Int) -> String {
        Self.countFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private var metaLine: String? {
        var parts: [String] = []

        let digits = media.year.filter(\.isNumber)
        if digits.count >= 4 {
            parts.append(String(digits.prefix(4)))
        }

        if let episodes = media.episodes, episodes > 0 {
            parts.append("\(countString(episodes)) eps")
        } else if let chapters = media.chapters, chapters > 0 {
            parts.append("\(countString(chapters)) ch")
        } else if let status = media.statusRaw?.uppercased() {
            if status == "RELEASING" { parts.append("airing") }
            if status == "FINISHED" { parts.append("finished") }
        } else if let format = media.formatRaw, !format.isEmpty {
            parts.append(format.lowercased())
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
                // Image with score - FIXED HEIGHT
                let imageHeight = max(100, floor(cardWidth / 0.7))

                ZStack(alignment: .top) {
                    KuroCachedAsyncImage(url: URL(string: media.imageURL ?? ""), maxPixelSize: 520) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: cardWidth, height: imageHeight)
                                .clipped()
                        case .failure, .empty:
                            Rectangle()
                                .fill(Color.black.opacity(0.05))
                                .frame(width: cardWidth, height: imageHeight)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: cardWidth, height: imageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    HStack(alignment: .top) {
                        Spacer()

                        VStack(alignment: .trailing, spacing: 6) {
                            if let rating = media.rating, rating > 0 {
                                KuroScoreBadge(score: rating)
                            }

                            if isInCollection {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.black.opacity(0.55))
                                    .background(
                                        Circle()
                                            .fill(Color.white)
                                            .frame(width: 18, height: 18)
                                    )
                            }
                        }
                    }
                    .padding(6)
                }

                // Title and info
                VStack(alignment: .leading, spacing: 2) {
                    Text(KuroCardText.sanitizeTitleForCard(media.title))
                        .font(.system(size: 13, weight: .light, design: .serif))
                        .textCase(.uppercase)
                        .tracking(media.title.count >= 26 ? 0.3 : 0.6)
                        .foregroundColor(.black.opacity(0.9))
                        .lineLimit(2)
                        .minimumScaleFactor(0.92)
                        .allowsTightening(true)
                        .truncationMode(.tail)
                        .frame(height: 34, alignment: .top)

                    if let metaLine {
                        Text(metaLine)
                            .font(.system(size: 9, weight: .light))
                            .foregroundColor(.black.opacity(0.5))
                            .lineLimit(1)
                    }

                }
                .frame(width: cardWidth, alignment: .topLeading)
        }
        .frame(width: cardWidth, height: cardHeight, alignment: .top)
        .contentShape(Rectangle())
        .kuroDeliberateTap {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText())
        .accessibilityHint("Opens details")
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            Button(action: {
                KuroAccessibility.impactHaptic(.light)
                supabaseService.toggleInCollection(mediaId: media.id, mediaType: mediaType)
            }) {
                Label(
                    isInCollection ? "Remove from List" : "Quick Add (Planned)",
                    systemImage: isInCollection ? "minus.circle" : "plus.circle"
                )
            }

            Button(action: {
                KuroAccessibility.impactHaptic(.light)
                showAddToList = true
            }) {
                Label(
                    isInCollection ? "Edit List" : "Add to List…",
                    systemImage: "slider.horizontal.3"
                )
            }

            if !supabaseService.myClubs.isEmpty {
                Button(action: {
                    KuroAccessibility.impactHaptic(.light)
                    showAddToClub = true
                }) {
                    Label("Add to Club\u{2026}", systemImage: "person.2.circle")
                }
            }
        }
        .sheet(isPresented: $showDetail) {
            MediaDetailSheet(kind: media.kind, id: media.id)
        }
        .sheet(isPresented: $showAddToList) {
            AddToListSheet(media: media)
        }
        .sheet(isPresented: $showAddToClub) {
            AddToClubRailSheet(mediaId: media.id, mediaType: mediaType.uppercased())
        }
    }

    private func accessibilityLabelText() -> Text {
        var parts: [String] = []
        parts.append(media.title)
        if !media.year.isEmpty { parts.append(media.year) }
        if let episodes = media.episodes, episodes > 0 { parts.append("\(episodes) episodes") }
        if let chapters = media.chapters, chapters > 0 { parts.append("\(chapters) chapters") }
        if let rating = media.rating, rating > 0 { parts.append(String(format: "Rating %.1f", rating)) }
        if isInCollection { parts.append("Saved") }
        return Text(parts.joined(separator: ", "))
    }
}

// MARK: - Editorial Loading View
struct EditorialLoadingView: View {
    var body: some View {
        VStack(spacing: 24) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    Rectangle()
                        .fill(Color.black.opacity(0.06))
                        .frame(width: 120, height: 16)
                        .kuroShimmer()
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(.horizontal, 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<5, id: \.self) { _ in
                                Rectangle()
                                    .fill(Color.black.opacity(0.04))
                                    .frame(width: 110, height: 200)
                                    .kuroShimmer()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .kuroSwipeExclusionZone()
                }
            }
        }
        .padding(.top, 12)
    }
}

// MARK: - Editorial Empty View
struct EditorialEmptyView: View {
    var onRetry: (() async -> Void)? = nil

    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.black.opacity(0.25))

            Text("NO CONTENT FOUND")
                .font(.system(size: 14, weight: .medium))
                .tracking(1.5)
                .foregroundColor(.kuroTextTertiary)

            Text("Pull to refresh or tap retry.")
                .font(.system(size: 12, weight: .light))
                .tracking(0.5)
                .foregroundColor(.kuroTextTertiary)

            if let onRetry {
                Button(action: {
                    guard !isRetrying else { return }
                    KuroAccessibility.impactHaptic(.light)
                    isRetrying = true
                    Task {
                        await onRetry()
                        isRetrying = false
                    }
                }) {
                    HStack(spacing: 6) {
                        if isRetrying {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(.black.opacity(0.6))
                        }
                        Text(isRetrying ? "LOADING" : "RETRY")
                            .font(.system(size: 11, weight: .medium))
                            .tracking(1.5)
                            .foregroundColor(.black.opacity(0.6))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .stroke(Color.black.opacity(0.15), lineWidth: 0.5)
                    )
                }
                .disabled(isRetrying)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 120)
    }
}

// MARK: - Manga Section Components

// Compact Horizontal Manga Section
struct CompactHorizontalMangaSection<Item: MediaDisplayable>: View {
    let title: String
    let subtitle: String
    let items: [Item]
    var containerWidth: CGFloat
    var onSeeAll: (() -> Void)? = nil

    private var cardWidth: CGFloat {
        let candidate = floor((containerWidth - 56) / 2.8)
        return min(144, max(112, candidate))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(.black)
                        .accessibilityAddTraits(.isHeader)

                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .tracking(0.3)
                        .foregroundColor(.black.opacity(0.5))
                }

                Spacer()

                if onSeeAll != nil {
                    Button(action: { onSeeAll?() }) {
                        Text("See All")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.black.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items, id: \.id) { manga in
                        CompactAnimeCard(media: manga, cardWidth: cardWidth)
                    }
                }
                .padding(.horizontal, 20)
            }
            .kuroSwipeExclusionZone()
        }
    }
}

// Dense 2-Column Manga Section
struct Dense2ColumnMangaSection<Item: MediaDisplayable>: View {
    let title: String
    let subtitle: String
    let items: [Item]
    let geometry: GeometryProxy

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(.black)

                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .tracking(0.3)
                    .foregroundColor(.black.opacity(0.5))
            }
            .padding(.horizontal, 20)

            let horizontalPadding: CGFloat = 20
            let spacing: CGFloat = 12
            let totalHorizontalPadding = horizontalPadding * 2
            let totalSpacing = spacing
            let availableWidth = geometry.size.width - totalHorizontalPadding - totalSpacing
            let cardWidth = floor(availableWidth / 2)
            let imageHeight = floor(cardWidth / 0.7)
            let textBlockHeight: CGFloat = 56
            let cardSpacing: CGFloat = 8
            let totalCardHeight = imageHeight + cardSpacing + textBlockHeight

            let columns = [
                GridItem(.fixed(cardWidth), spacing: spacing),
                GridItem(.fixed(cardWidth), spacing: spacing)
            ]

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items, id: \.id) { manga in
                    GridAnimeCard(media: manga, cardWidth: cardWidth, cardHeight: totalCardHeight)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

#Preview {
    EditorialDiscoverView()
        .environment(SupabaseService.shared)
}

// MARK: - Dense 2-Column Section Fixed (No GeometryReader)
struct Dense2ColumnSectionFixed<Item: MediaDisplayable>: View {
    let title: String
    let subtitle: String
    let items: [Item]
    let screenWidth: CGFloat
    var onSeeAll: (() -> Void)? = nil
    var showFilters: Bool = false

    @State private var selectedFilter: AnimeFilter = .all

    enum AnimeFilter: String, CaseIterable {
        case all = "All"
        case short = "Short"
        case long = "Long"
        case completed = "Completed"
    }

    private var filteredItems: [Item] {
        switch selectedFilter {
        case .all:
            return items
        case .short:
            return items.filter { ($0.episodes ?? 0) > 0 && ($0.episodes ?? 0) <= 13 }
        case .long:
            return items.filter { ($0.episodes ?? 0) > 50 }
        case .completed:
            return items.filter { $0.statusRaw == "FINISHED" }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(.black)
                        .accessibilityAddTraits(.isHeader)

                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .tracking(0.3)
                        .foregroundColor(.black.opacity(0.5))
                }

                Spacer()

                if onSeeAll != nil {
                    Button(action: { onSeeAll?() }) {
                        Text("See All")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.black.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 20)

            // Filter chips
            if showFilters {
                VStack(alignment: .leading, spacing: 8) {
                    Text("REFINE THIS RAIL")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.2)
                        .foregroundColor(.kuroTextTertiary)
                        .padding(.horizontal, 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(AnimeFilter.allCases, id: \.self) { filter in
                                FilterChip(
                                    title: filter.rawValue,
                                    isSelected: selectedFilter == filter,
                                    action: { selectedFilter = filter }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .kuroSwipeExclusionZone()
                }
            }

            let horizontalPadding: CGFloat = 20
            let spacing: CGFloat = 12
            let totalHorizontalPadding = horizontalPadding * 2
            let totalSpacing = spacing
            let availableWidth = screenWidth - totalHorizontalPadding - totalSpacing
            let cardWidth = floor(availableWidth / 2)
            let imageHeight = floor(cardWidth / 0.7)
            let textBlockHeight: CGFloat = 56
            let cardSpacing: CGFloat = 8
            let totalCardHeight = imageHeight + cardSpacing + textBlockHeight

            let columns = [
                GridItem(.fixed(cardWidth), spacing: spacing),
                GridItem(.fixed(cardWidth), spacing: spacing)
            ]

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filteredItems, id: \.id) { anime in
                    GridAnimeCard(media: anime, cardWidth: cardWidth, cardHeight: totalCardHeight)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Dense 2-Column Manga Section Fixed
struct Dense2ColumnMangaSectionFixed<Item: MediaDisplayable>: View {
    let title: String
    let subtitle: String
    let items: [Item]
    let screenWidth: CGFloat
    var onSeeAll: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(.black)
                        .accessibilityAddTraits(.isHeader)

                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .tracking(0.3)
                        .foregroundColor(.black.opacity(0.5))
                }

                Spacer()

                if onSeeAll != nil {
                    Button(action: { onSeeAll?() }) {
                        Text("See All")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.black.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 20)

            let horizontalPadding: CGFloat = 20
            let spacing: CGFloat = 12
            let totalHorizontalPadding = horizontalPadding * 2
            let totalSpacing = spacing
            let availableWidth = screenWidth - totalHorizontalPadding - totalSpacing
            let cardWidth = floor(availableWidth / 2)
            let imageHeight = floor(cardWidth / 0.7)
            let textBlockHeight: CGFloat = 56
            let cardSpacing: CGFloat = 8
            let totalCardHeight = imageHeight + cardSpacing + textBlockHeight

            let columns = [
                GridItem(.fixed(cardWidth), spacing: spacing),
                GridItem(.fixed(cardWidth), spacing: spacing)
            ]

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items, id: \.id) { manga in
                    GridAnimeCard(media: manga, cardWidth: cardWidth, cardHeight: totalCardHeight)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Full Section View (for "See All")
struct FullSectionView<Item: MediaDisplayable>: View {
    let title: String
    let items: [Item]
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    private var filtered: [Item] {
        if searchText.isEmpty {
            return items
        }
        return items.filter { media in
            media.title.localizedCaseInsensitiveContains(searchText) ||
            media.displayDescription.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationView {
            GeometryReader { geo in
                let metrics = KuroCardMetrics.grid(for: geo.size.width, columns: 2)

                ScrollView(.vertical, showsIndicators: false) {
                    Text("EDITORIAL RAIL")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.4)
                        .foregroundColor(.kuroTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, KuroCardMetrics.horizontalPadding)
                        .padding(.top, 12)

                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.kuroTextTertiary)
                        TextField("Search \(title.lowercased())...", text: $searchText)
                            .font(.system(size: 14))
                    }
                    .padding(12)
                    .background(Color.black.opacity(0.05))
                    .padding(.horizontal, KuroCardMetrics.horizontalPadding)
                    .padding(.top, 12)

                    // Results count
                    Text("\(filtered.count) RESULTS")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.5)
                        .foregroundColor(.black.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, KuroCardMetrics.horizontalPadding)
                        .padding(.top, 16)

                    // Grid (no fixed height; allow ScrollView to size content correctly)
                    LazyVGrid(
                        columns: metrics.columns,
                        alignment: .center,
                        spacing: KuroCardMetrics.rowSpacing
                    ) {
                        ForEach(filtered, id: \.id) { anime in
                            GridAnimeCard(media: anime, cardWidth: metrics.cardWidth, cardHeight: metrics.cardHeight)
                                .frame(width: metrics.cardWidth, height: metrics.cardHeight, alignment: .top)
                        }
                    }
                    .padding(.horizontal, KuroCardMetrics.horizontalPadding)
                    .padding(.bottom, 24)
                }
                // Ensure the last rows can scroll fully above the home indicator / tab chrome.
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 24)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.black)
                    }
                }
            }
        }
    }
}

// MARK: - Full Manga Section View (for "See All")
struct FullMangaSectionView<Item: MediaDisplayable>: View {
    let title: String
    let items: [Item]
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [Item] {
        if searchText.isEmpty { return items }
        return items.filter { media in
            media.title.localizedCaseInsensitiveContains(searchText) ||
            media.displayDescription.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationView {
            GeometryReader { geo in
                let metrics = KuroCardMetrics.grid(for: geo.size.width, columns: 2)

                ScrollView(.vertical, showsIndicators: false) {
                    Text("EDITORIAL RAIL")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.4)
                        .foregroundColor(.kuroTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, KuroCardMetrics.horizontalPadding)
                        .padding(.top, 12)

                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.kuroTextTertiary)
                        TextField("Search \(title.lowercased())...", text: $searchText)
                            .font(.system(size: 14))
                    }
                    .padding(12)
                    .background(Color.black.opacity(0.05))
                    .padding(.horizontal, KuroCardMetrics.horizontalPadding)
                    .padding(.top, 12)

                    Text("\(filtered.count) RESULTS")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.5)
                        .foregroundColor(.black.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, KuroCardMetrics.horizontalPadding)
                        .padding(.top, 16)

                    LazyVGrid(
                        columns: metrics.columns,
                        alignment: .center,
                        spacing: KuroCardMetrics.rowSpacing
                    ) {
                        ForEach(filtered, id: \.id) { manga in
                            GridAnimeCard(media: manga, cardWidth: metrics.cardWidth, cardHeight: metrics.cardHeight)
                                .frame(width: metrics.cardWidth, height: metrics.cardHeight, alignment: .top)
                        }
                    }
                    .padding(.horizontal, KuroCardMetrics.horizontalPadding)
                    .padding(.bottom, 24)
                }
                // Ensure the last rows can scroll fully above the home indicator / tab chrome.
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 24)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.black)
                    }
                }
            }
        }
    }
}

// MARK: - Genre Picker Sheet
struct GenrePickerSheet: View {
    let genres: [String]
    let onSelect: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    FilterChip(
                        title: "Cancel",
                        isSelected: false,
                        action: {
                            onSelect(nil)
                            dismiss()
                        }
                    )

                    ForEach(genres, id: \.self) { genre in
                        FilterChip(
                            title: genre,
                            isSelected: false,
                            action: {
                                onSelect(genre)
                                dismiss()
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .navigationTitle("Genres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.black.opacity(0.8))
                }
            }
        }
    }
}
