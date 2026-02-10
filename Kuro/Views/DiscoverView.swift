import SwiftUI

// MARK: - SLEEK DISCOVER VIEW - Completely Redesigned
// Premium, polished, well-designed anime discovery experience

struct DiscoverView: View {
    @Environment(SupabaseService.self) private var supabaseService
    @State private var featured: Anime? = nil
    // Server-driven sections
    @State private var serverTrending: [Anime] = []
    @State private var serverTrendingAiring: [Anime] = []
    @State private var serverCurrent: [Anime] = []
    @State private var serverNewly: [Anime] = []
    @State private var serverTop: [Anime] = []
    @State private var serverAiringSoon: [Anime] = []
    // Controls
    @State private var trendingAiringOnly: Bool = false
    @State private var selectedSeasonName: String = DiscoverView.currentSeasonName()
    @State private var selectedSeasonYear: Int = Calendar.current.component(.year, from: Date())

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                if supabaseService.isLoading {
                    DiscoverLoadingView(geometry: geometry)
                } else if supabaseService.animeItems.isEmpty {
                    DiscoverEmptyView()
                } else {
                    VStack(spacing: 0) {
                        // Hero Featured Section - Large Spotlight (Properly Constrained)
                        if let featured {
                            HeroFeaturedCard(anime: featured, geometry: geometry)
                                .padding(.horizontal, max(geometry.size.width * 0.05, 20))
                                .padding(.bottom, KuroSpacing.xl) // CONSISTENT 32pt spacing
                        }

                        // Current Season - Horizontal Scroll with controls
                        if !effectiveCurrentSeason.isEmpty {
                            HStack(spacing: 8) {
                                Button(action: { KuroAccessibility.impactHaptic(.light); previousSeason() }) {
                                    Image(systemName: "chevron.left").foregroundColor(.black.opacity(0.6))
                                }
                                Text("\(selectedSeasonName) \(selectedSeasonYear)")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(.black)
                                Button(action: { KuroAccessibility.impactHaptic(.light); nextSeason() }) {
                                    Image(systemName: "chevron.right").foregroundColor(.black.opacity(0.6))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 6)
                            HorizontalSection(
                                title: "Current Season",
                                subtitle: "Airing now",
                                items: effectiveCurrentSeason,
                                geometry: geometry
                            )
                        }

                        // Trending - Horizontal Scroll with toggle
                        if !effectiveTrending.isEmpty {
                            HStack {
                                Button(action: {
                                    KuroAccessibility.impactHaptic(.light)
                                    trendingAiringOnly.toggle()
                                    if trendingAiringOnly && serverTrendingAiring.isEmpty {
                                        Task { serverTrendingAiring = await supabaseService.fetchTrendingAnime(limit: 12, onlyAiring: true) }
                                    }
                                }) {
                                    Text(trendingAiringOnly ? "AIRING ONLY" : "ALL")
                                        .font(.system(size: 10, weight: .regular))
                                        .tracking(1.0)
                                        .foregroundColor(.black.opacity(0.8))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.2), lineWidth: 0.5))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            HorizontalSection(
                                title: "Trending",
                                subtitle: "Popular right now",
                                items: effectiveTrending,
                                geometry: geometry
                            )
                        }

                        // Top Rated - Vertical Grid
                        if !effectiveTopRated.isEmpty {
                            VerticalGridSection(
                                title: "Top Rated",
                                subtitle: "Highest scores",
                                items: effectiveTopRated,
                                geometry: geometry
                            )
                        }

                        // Newly Added - Vertical Grid
                        if !effectiveNewlyAdded.isEmpty {
                            VerticalGridSection(
                                title: "Just Added",
                                subtitle: "Fresh arrivals",
                                items: effectiveNewlyAdded,
                                geometry: geometry
                            )
                        }

                        // Airing Soon - Horizontal Scroll
                        if !serverAiringSoon.isEmpty {
                            HorizontalSection(
                                title: "Airing Soon",
                                subtitle: "Next 24 hours",
                                items: serverAiringSoon,
                                geometry: geometry
                            )
                        }

                        // API-backed Show More for Discover
                        if supabaseService.hasMoreAnime {
                            Button(action: {
                                KuroAccessibility.impactHaptic(.light)
                                Task { await supabaseService.fetchNextAnimePage() }
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
                            .padding(.horizontal, 20)
                            .padding(.top, KuroSpacing.md)
                        }
                    }
                    .padding(.top, KuroSpacing.sm) // CONSISTENT 8pt top spacing
                    .padding(.bottom, KuroSpacing.xl) // CONSISTENT 32pt bottom spacing
                }
            }
            .transaction { $0.animation = nil }
            .background(Color(.systemBackground))
            .scrollContentBackground(.hidden)
        }
        .onAppear {
            Task {
                if supabaseService.animeItems.isEmpty {
                    supabaseService.setPageSize(50)
                    let total = KuroScreen.isLargeScreen ? 500 : 300
                    await supabaseService.prefetchAnime(total: total)
                }
                featured = bestFeaturedCandidate(from: supabaseService.animeItems)
                // Fetch server-driven sections for accuracy
                async let t: [Anime] = supabaseService.fetchTrendingAnime(limit: 12, onlyAiring: false)
                async let ta: [Anime] = supabaseService.fetchTrendingAnime(limit: 12, onlyAiring: true)
                async let c: [Anime] = supabaseService.fetchSeasonAnime(season: selectedSeasonName, year: selectedSeasonYear, limit: 12, onlyAiring: true)
                async let n: [Anime] = supabaseService.fetchNewlyAddedAnime(limit: 12)
                async let r: [Anime] = supabaseService.fetchTopRatedAnime(limit: 12, minScore: 80)
                async let s: [Anime] = supabaseService.fetchAiringSoonAnime(hours: 24, limit: 12)
                let (tt, tta, cc, nn, rr, ss) = await (t, ta, c, n, r, s)
                serverTrending = tt
                serverTrendingAiring = tta
                serverCurrent = cc
                serverNewly = nn
                serverTop = rr
                serverAiringSoon = ss
            }
        }
        // Avoid requiring Anime: Equatable for onChange(of: [Anime])
        .onChange(of: supabaseService.animeItems.count) { _, _ in
            featured = bestFeaturedCandidate(from: supabaseService.animeItems)
        }
    }
}

// MARK: - Effective data sources
extension DiscoverView {
    private var effectiveTrending: [Anime] {
        if trendingAiringOnly {
            return serverTrendingAiring.isEmpty ? localTrending : serverTrendingAiring
        } else {
            return serverTrending.isEmpty ? localTrending : serverTrending
        }
    }
    private var effectiveCurrentSeason: [Anime] { serverCurrent.isEmpty ? localCurrentSeason : serverCurrent }
    private var effectiveNewlyAdded: [Anime] { serverNewly.isEmpty ? localNewlyAdded : serverNewly }
    private var effectiveTopRated: [Anime] { serverTop.isEmpty ? localTopRated : serverTop }

    private var localTrending: [Anime] {
        Array(supabaseService.animeItems.sorted { ($0.trending ?? 0) > ($1.trending ?? 0) }.prefix(12))
    }

    private var localCurrentSeason: [Anime] {
        let year = Calendar.current.component(.year, from: Date())
        return Array(supabaseService.animeItems
            .filter { $0.seasonYear == year && $0.status == "RELEASING" }
            .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
            .prefix(12))
    }

    private var localNewlyAdded: [Anime] {
        Array(supabaseService.animeItems.sorted { $0.createdAt > $1.createdAt }.prefix(12))
    }

    private var localTopRated: [Anime] {
        Array(supabaseService.animeItems.sorted { ($0.averageScore ?? 0) > ($1.averageScore ?? 0) }.prefix(12))
    }

    private func bestFeaturedCandidate(from items: [Anime]) -> Anime? {
        items
            .filter { $0.status == "RELEASING" && ($0.averageScore ?? 0) > 80 }
            .sorted { ($0.averageScore ?? 0) > ($1.averageScore ?? 0) }
            .first
    }

    static func currentSeasonName() -> String {
        let m = Calendar.current.component(.month, from: Date())
        switch m {
        case 12,1,2: return "WINTER"
        case 3,4,5: return "SPRING"
        case 6,7,8: return "SUMMER"
        default: return "FALL"
        }
    }

    private func previousSeason() {
        let order = ["WINTER","SPRING","SUMMER","FALL"]
        guard let idx = order.firstIndex(of: selectedSeasonName) else { return }
        let newIdx = (idx + 3) % 4
        if newIdx == 3 && idx == 0 { selectedSeasonYear -= 1 }
        selectedSeasonName = order[newIdx]
        Task { serverCurrent = await supabaseService.fetchSeasonAnime(season: selectedSeasonName, year: selectedSeasonYear, limit: 12, onlyAiring: true) }
    }

    private func nextSeason() {
        let order = ["WINTER","SPRING","SUMMER","FALL"]
        guard let idx = order.firstIndex(of: selectedSeasonName) else { return }
        let newIdx = (idx + 1) % 4
        if newIdx == 0 && idx == 3 { selectedSeasonYear += 1 }
        selectedSeasonName = order[newIdx]
        Task { serverCurrent = await supabaseService.fetchSeasonAnime(season: selectedSeasonName, year: selectedSeasonYear, limit: 12, onlyAiring: true) }
    }
}

// MARK: - Hero Featured Card (Large Spotlight)
struct HeroFeaturedCard: View {
    let anime: Anime
    let geometry: GeometryProxy
    @State private var showDetail = false
    @State private var pressed = false
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    var body: some View {
        Button(action: {
            guard !suppressCardTaps else { return }
            pressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { pressed = false }
            KuroAccessibility.impactHaptic(.medium)
            showDetail = true
        }) {
            ZStack(alignment: .bottomLeading) {
                // Large Banner Image - Properly constrained
                KuroCachedAsyncImage(url: URL(string: anime.bannerImage ?? anime.coverImageLarge ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.black.opacity(0.03), Color.black.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .frame(width: geometry.size.width - 40, height: max(geometry.size.width * 0.42, 180)) // Constrain width
                .clipped()

                // Gradient Overlay
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.25),
                        Color.black.opacity(0.65)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: geometry.size.width - 40, height: max(geometry.size.width * 0.42, 180)) // Match image constraints

                // Info Overlay
                VStack(alignment: .leading, spacing: 8) {
                    Text("FEATURED")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(2.0)
                        .foregroundColor(.white.opacity(0.7))

                    Text(anime.displayTitle.uppercased())
                        .font(.system(size: max(geometry.size.width * 0.05, 18), weight: .light, design: .serif))
                        .tracking(0.5)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .lineSpacing(2)

                    HStack(spacing: 8) {
                        if let score = anime.averageScore {
                            HStack(spacing: 3) {
                                Text("★")
                                    .font(.system(size: 11))
                                Text(String(format: "%.1f", Double(score) / 10.0))
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.white)
                        }

                        if let episodes = anime.episodeCount {
                            Text("·")
                                .foregroundColor(.white.opacity(0.5))
                            Text("\(episodes) Episodes")
                                .font(.system(size: 11, weight: .light))
                                .foregroundColor(.white.opacity(0.9))
                        }

                        if anime.status == "RELEASING" {
                            Text("·")
                                .foregroundColor(.white.opacity(0.5))
                            Text("AIRING")
                                .font(.system(size: 10, weight: .medium))
                                .tracking(1.0)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                }
                .padding(max(geometry.size.width * 0.05, 20))
            }
            .frame(width: geometry.size.width - 40) // Ensure container respects bounds
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)) // Changed from 16
            .shadow(color: .black.opacity(0.08), radius: 30, x: 0, y: 15) // Enhanced shadow
            .shadow(color: .black.opacity(0.03), radius: 10, x: 0, y: 5) // Double shadow layer
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .frame(height: max(geometry.size.width * 0.42, 180))
            .scaleEffect(pressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: pressed)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            AnimeDetailView(anime: anime)
        }
    }
}

// MARK: - Horizontal Scrolling Section
struct HorizontalSection: View {
    let title: String
    let subtitle: String
    let items: [Anime]
    let geometry: GeometryProxy
    
    @State private var sheetAnime: Anime? = nil

    var body: some View {
        let padding = KuroDesignSpacing.perfectPadding
        let spacing = KuroDesignSpacing.perfectContainerSpacing // UNIVERSAL 16pt spacing
        let cardWidth: CGFloat = 140 // FIXED width

        return VStack(alignment: .leading, spacing: spacing) {
            // Section Header
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 14, weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(.black)

                Text(subtitle)
                    .font(.system(size: 10, weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.black.opacity(0.4))
            }
            .padding(.horizontal, padding)

            // Horizontal Scroll with UNIVERSAL spacing
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: spacing) { // UNIVERSAL 16pt spacing
                    ForEach(items, id: \.id) { anime in
                        SharedHorizontalAnimeCard(
                            anime: anime,
                            width: cardWidth,
                            height: 210,
                            showBadge: true,
                            tap: {
                                KuroAccessibility.impactHaptic(.light)
                                sheetAnime = anime
                            }
                        )
                        .frame(width: cardWidth)
                    }
                }
                .padding(.horizontal, padding) // Apply padding inside scroll view
            }
            .kuroSwipeExclusionZone()
            .scrollTargetBehavior(.viewAligned)
            .scrollBounceBehavior(.basedOnSize)
            .highPriorityGesture(DragGesture())
        }
        .padding(.bottom, KuroSpacing.xl) // CONSISTENT 32pt spacing
        .sheet(item: $sheetAnime) { anime in
            AnimeDetailView(anime: anime)
        }
    }
}

// MARK: - Vertical Grid Section
struct VerticalGridSection: View {
    let title: String
    let subtitle: String
    let items: [Anime]
    let geometry: GeometryProxy
    
    var body: some View {
        let metrics = KuroCardMetrics.grid(for: geometry.size.width, columns: 2)
        let spacing = KuroCardMetrics.interItemSpacing
        let cardWidth = metrics.cardWidth
        let cardHeight = metrics.cardHeight

        VStack(alignment: .leading, spacing: spacing) {
            // Section Header
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 14, weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(.black)

                Text(subtitle)
                    .font(.system(size: 10, weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.black.opacity(0.4))
            }
            .padding(.horizontal, 20)

                LazyVGrid(
                columns: metrics.columns,
                alignment: .center,
                spacing: spacing
            ) {
                ForEach(items, id: \.id) { anime in
                    KuroPortraitCard(
                        media: anime,
                        cardWidth: cardWidth,
                        cardHeight: cardHeight
                    )
                    .frame(width: cardWidth, height: cardHeight, alignment: .top)
                }
            }
            .padding(.horizontal, KuroCardMetrics.horizontalPadding)
        }
        .padding(.bottom, 32)
    }
}

// MARK: - Vertical Grid Card Component
struct VerticalGridCard: View {
    let anime: Anime
    let cardWidth: CGFloat
    @Binding var sheetAnime: Anime?
    
    var body: some View {
        let imageAspect: CGFloat = 0.68
        let imageHeight: CGFloat = cardWidth / imageAspect
        let textBlockHeight: CGFloat = 64
        let verticalSpacing: CGFloat = KuroSpacing.sm
        let totalHeight: CGFloat = imageHeight + verticalSpacing + textBlockHeight

        VStack(alignment: .leading, spacing: KuroSpacing.sm) {
            PosterView(
                url: URL(string: anime.displayImage),
                cornerRadius: 12,
                showsShadow: false,
                badgeText: anime.averageScore.map { String(format: "★ %.1f", Double($0)/10.0) },
                showsShimmer: true
            )
            .frame(width: cardWidth, height: imageHeight)
            .onTapGesture {
                KuroAccessibility.impactHaptic(.light)
                sheetAnime = anime
            }

            VStack(alignment: .leading, spacing: KuroSpacing.xs) {
                Text(anime.displayTitle.uppercased())
                    .font(.system(size: KuroScreen.isSmallScreen ? 9 : 10, weight: .regular))
                    .tracking(0.5)
                    .foregroundColor(.black.opacity(0.8))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    if let year = anime.seasonYear { Text(String(year)) }
                    if anime.seasonYear != nil && (anime.episodeCount ?? 0) > 0 { Text("·") }
                    Text(anime.episodeText)
                }
                .font(.system(size: KuroScreen.isSmallScreen ? 8 : 9, weight: .light))
                .foregroundColor(.black.opacity(0.5))
            }
            .frame(width: cardWidth, height: textBlockHeight, alignment: .topLeading)
        }
        .frame(width: cardWidth, height: totalHeight, alignment: .top)
    }
}

// MARK: - Loading View
struct DiscoverLoadingView: View {
    let geometry: GeometryProxy

    var body: some View {
        VStack(spacing: 32) {
            // Hero skeleton
            Rectangle()
                .fill(Color.black.opacity(0.04))
                .frame(height: max(geometry.size.width * 0.45, 200))

            // Section skeletons
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    Rectangle()
                        .fill(Color.black.opacity(0.06))
                        .frame(width: 120, height: 14)
                        .padding(.horizontal, 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<4, id: \.self) { _ in
                                Rectangle()
                                    .fill(Color.black.opacity(0.04))
                                    .frame(width: 120, height: 180)
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

// MARK: - Empty View
struct DiscoverEmptyView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("NO CONTENT")
                .font(.system(size: 14, weight: .medium))
                .tracking(1.5)
                .foregroundColor(.black.opacity(0.3))

            ProgressView()
                .scaleEffect(0.8)
        }
        .padding(.top, 80)
    }
}


#Preview {
    DiscoverView()
        .environment(SupabaseService.shared)
}
