import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - ANIME DETAIL VIEW - iOS 26 Mobile-First
// Comprehensive anime detail page with elegant minimalism
//
// Loading (the page's one documented load coordinator; docs/modules/detail-pages.md). Initial/keyed
// loads use SwiftUI tasks; unit-sheet sentinel paging owns a task cancelled on dismissal. Each run
// rejects cancelled/superseded results before publishing or changing loading state.
// Row limits: similar 14, sub-genre tags 12 (one row read, trimmed client-side), episode preview 10,
// episode sheet 50 per page, next-episode stream link 1. NOT row-limited: the credits queries (every
// studio / staff / cast row of the title), the ladder RPC and the title's external links.
//
// | Loader                                        | Key                       | Work                                                                                                   | Lifetime   |
// | --------------------------------------------- | ------------------------- | ------------------------------------------------------------------------------------------------------ | ---------- |
// | Screen (`AnimeDetailView`)                    | anime id                  | top tags, similar, ladder -> `enqueueMediaRelationRefreshIfNeeded` (server write, cooldown) -> FM synopsis | page       |
// | Credits (`AnimeDetailView`)                   | anime id + credits_cast_v1 | studios, staff, cast                                                                                   | page       |
// | Units preview (`EpisodesSection`)             | next episode number       | next 10 episodes                                                                                       | section    |
// | Units sheet (`EpisodeListSheet`)              | sheet appear + load-more  | episodes, pages of 50                                                                                  | sheet      |
// | Watch links (`ActionButtons`)                 | viewer progress           | `ProviderAvailabilityStore.resolveWatchLinks`: stream link of episode progress + 1 (`getStreamLinkForEpisode`), legal external links, and behind streaming_availability_v1 status / provider v2 / `enqueueAvailabilityRefreshIfStale` (server write); a cancelled (superseded) run publishes nothing | action bar |
// | `ClubActivitySection`, `FriendsActivitySection` | own `.task`             | club activity, friend comments                                                                         | section    |
//
// Shared chrome: DetailSharedComponents.swift; provider sheet: ProviderLinkViews.swift; link builders:
// Kuro/Providers/ProviderLinkBuilders.swift.

struct AnimeDetailView: View {
    let anime: Anime
    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogStore.self) private var catalog
    @Environment(RecommendationsReader.self) private var recommendations
    @Environment(AppleFMService.self) private var deviceIntelligence
    @Environment(FeatureFlags.self) private var flags
    @State private var scrollOffset: CGFloat = 0
    @State private var showFullDescription = false
    @State private var toast: KuroToastState? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil
    @State private var topTags: [TagFacet] = []
    @State private var similar: [Anime] = []
    @State private var condensedSynopsis: String?
    @State private var studios: [Studio] = []
    @State private var staffItems: [(staff: Staff, role: String)] = []
    @State private var castItems: [(character: Character, role: String)] = []
    @State private var mediaLadder: MediaLadderResponse = .empty
    @State private var didLoadCredits = false
    @State private var didLoadLadder = false
    @State private var screenLoadGeneration = UUID()
    @State private var creditsLoadGeneration = UUID()
    @State private var releaseItems: [ReleaseScheduleItem]?
    @State private var releaseSongs: [ThemeSong]?

    var body: some View {
        if flags.seriesHomeNativeV1Enabled {
            // Spec D15: the series page shows these legacy sections when its bundle has no series data.
            SeriesAnimeDetailView(anime: anime, legacy: { AnyView(legacyAnimeDetail) })
        } else {
            legacyAnimeDetail
        }
    }

    private var legacyAnimeDetail: some View {
        GeometryReader { geometry in
            // In sheets, SwiftUI sometimes reserves a top "cap" area that isn't reflected as a
            // typical safe-area inset on some OS/device combinations. Enforce a minimum so the
            // hero always reaches the sheet's top edge.
            let safeTop = max(geometry.safeAreaInsets.top, 24)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: KuroDetailScrollOffsetPreferenceKey.self,
                                value: proxy.frame(in: .named("detail_scroll")).minY
                            )
                    }
                    .frame(height: 0)

                    // Hero Section with Parallax Effect
                    // In a sheet presentation, SwiftUI can reserve top insets (rounded corners / drag affordance)
                    // which can leave a visible cap above the hero image. Pull the hero up by the sheet-safe inset
                    // so the banner truly reaches the top edge.
                    HeroSection(anime: anime, geometry: geometry, scrollOffset: $scrollOffset)
                        .offset(y: -safeTop)
                        .padding(.bottom, -safeTop)
                    
                    // Content Section
                    VStack(spacing: KuroDesignSpacing.adaptive(KuroSpacing.xl, for: geometry.size.width)) {
                        // Title & Quick Info
                        TitleSection(anime: anime)
                        
                        MetaLineSection(anime: anime)

                        DetailNextReleaseSection(items: releaseItems ?? DetailNextReleaseSection.seed(for: anime))
                        
                        // Description
                        if anime.hasMeaningfulSynopsis {
                            DescriptionSection(
                                description: anime.displayDescription,
                                showFull: $showFullDescription,
                                condensedSynopsis: condensedSynopsis
                            )
                        }
                        
                        // Genres
                        if let genres = anime.genreList, !genres.isEmpty {
                            GenresSection(genres: genres)
                        }

                        if !topTags.isEmpty {
                            TagChipsSection(title: "SUB‑GENRES", tags: topTags.map(\.name))
                        }

                        if flags.isCreditsCastV1Enabled {
                            if didLoadCredits {
                                if !castItems.isEmpty {
                                    CastSection(characters: castItems)
                                }

                                if !studios.isEmpty || !staffItems.isEmpty {
                                    ProductionSection(studios: studios, staffItems: staffItems)
                                }
                            } else {
                                DetailCreditsSkeleton()
                            }
                        }

                        if didLoadLadder {
                            AdaptationPathSection(ladder: mediaLadder, mediaType: .anime)
                        } else {
                            DetailLadderSkeleton()
                        }

                        // Episodes Section (if available)
                        if let episodeCount = anime.episodeCount ?? anime.nextEpisodeNumber.map({ max(0, $0 - 1) }), episodeCount > 0 {
                            EpisodesSection(
                                anime: anime,
                                episodeCount: episodeCount,
                                countLabel: anime.episodeCount == nil ? "SO FAR" : "TOTAL",
                                onError: showToast
                            )
                        }

                        DetailSongsSection(songs: releaseSongs ?? [])

                        // "NEXT" pick when user has completed this series
                        if !similar.isEmpty {
                            NextPickSection(
                                mediaId: anime.id,
                                mediaType: "anime",
                                similar: similar
                            )
                        }

                        if !similar.isEmpty {
                            SimilarSection(title: "MORE LIKE THIS", items: similar, containerWidth: geometry.size.width)
                        }

                        ClubActivitySection(mediaId: anime.id, mediaType: "ANIME")

                        if flags.isSocialActivityV1Enabled {
                            FriendsActivitySection(mediaId: anime.id, mediaType: "ANIME")
                        }

                        // The page's deep link; it always parses for an integer id (no force unwrap).
                        if let shareURL = URL(string: "kuro://anime/\(anime.id)") {
                            ShareLink(
                                item: shareURL,
                                subject: Text(anime.displayTitle)
                            ) {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.kuroCustom(11, weight: .medium, maxSize: 18))
                                    Text("SHARE")
                                        .font(.kuroMicro(weight: .medium))
                                        .tracking(1.2)
                                }
                                .foregroundColor(.kuroTextSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.black.opacity(0.04))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(TapGesture().onEnded { KuroAccessibility.impactHaptic(.light) })
                        }

                    }
                    .padding(.horizontal, ResponsiveLayout.padding())
                    .padding(.top, KuroDesignSpacing.adaptive(KuroSpacing.lg, for: geometry.size.width))
                    .padding(.bottom, KuroDesignSpacing.adaptive(KuroSpacing.xl, for: geometry.size.width))
                }
            }
            .transaction { $0.animation = nil }
            .coordinateSpace(name: "detail_scroll")
            .onPreferenceChange(KuroDetailScrollOffsetPreferenceKey.self) { v in
                scrollOffset = v
            }
            .background(Color.kuroBackground)
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .topLeading) {
                // Custom Back Button
                BackButton(dismiss: dismiss)
                    .padding(.top, safeTop + KuroSpacing.md)
                    .padding(.leading, ResponsiveLayout.padding())
            }
            .safeAreaInset(edge: .bottom) {
                ActionButtons(anime: anime, onToast: showToast)
                    .padding(.horizontal, ResponsiveLayout.padding())
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                    .background(
                        Rectangle()
                            .fill(Color.kuroBackground.opacity(0.92))
                            .overlay(
                                Rectangle()
                                    .fill(Color.black.opacity(0.08))
                                    .frame(height: 0.5),
                                alignment: .top
                            )
                            .ignoresSafeArea()
                    )
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    KuroToast(toast: toast)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 96)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        // In a SwiftUI sheet, the root view is often constrained to the sheet's safe area, which can
        // leave a visible "white cap" above the hero image. Make the entire detail view truly
        // full-bleed within the sheet container.
        .background(Color.kuroBackground.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        #else
        .toolbar(.hidden, for: .windowToolbar)
        #endif
        .task(id: anime.id) {
            guard !Task.isCancelled else { return }
            let generation = UUID()
            screenLoadGeneration = generation
            async let tags = catalog.fetchTopTagsForAnime(animeId: anime.id, limit: 12)
            async let sim = recommendations.fetchSimilarAnime(seed: anime, limit: 14)
            async let ladder = catalog.fetchMediaLadder(mediaType: "ANIME", mediaId: anime.id)
            let loadedTags = await tags
            guard !Task.isCancelled, screenLoadGeneration == generation else { return }
            topTags = loadedTags
            let loadedSimilar = await sim
            guard !Task.isCancelled, screenLoadGeneration == generation else { return }
            similar = loadedSimilar
            let loadedLadder = await ladder
            guard !Task.isCancelled, screenLoadGeneration == generation else { return }
            mediaLadder = loadedLadder
            didLoadLadder = true
            await catalog.enqueueMediaRelationRefreshIfNeeded(
                mediaType: "ANIME",
                mediaId: anime.id,
                ladder: mediaLadder,
                reason: "detail_open"
            )

            guard !Task.isCancelled, screenLoadGeneration == generation else { return }

            // Condense long synopses on-device via Apple FM (no-op on unsupported devices)
            let sourceSynopsis = anime.displayDescription
            let hasReadyEnhanced = (anime.synopsisEnhancedState ?? "").lowercased() == "ready"
            if !hasReadyEnhanced, sourceSynopsis.count > 200 {
                let synopsis = await deviceIntelligence.condenseSynopsis(
                    mediaKind: "ANIME",
                    mediaId: anime.id,
                    description: sourceSynopsis,
                    title: anime.displayTitle,
                    genres: anime.genreList ?? []
                )
                guard !Task.isCancelled, screenLoadGeneration == generation else { return }
                condensedSynopsis = synopsis
            }
        }
        .task(id: "\(anime.id)-\(flags.isCreditsCastV1Enabled)") {
            guard !Task.isCancelled else { return }
            let generation = UUID()
            creditsLoadGeneration = generation
            guard flags.isCreditsCastV1Enabled else { return }
            async let studioFetch = catalog.fetchStudiosForAnime(animeId: anime.id)
            async let staffFetch = catalog.fetchStaffForAnime(animeId: anime.id)
            async let castFetch = catalog.fetchCharactersForAnime(animeId: anime.id)
            let loadedStudios = await studioFetch
            guard !Task.isCancelled, creditsLoadGeneration == generation, flags.isCreditsCastV1Enabled else { return }
            studios = loadedStudios
            let loadedStaffItems = await staffFetch
            guard !Task.isCancelled, creditsLoadGeneration == generation, flags.isCreditsCastV1Enabled else { return }
            staffItems = loadedStaffItems
            let loadedCastItems = await castFetch
            guard !Task.isCancelled, creditsLoadGeneration == generation, flags.isCreditsCastV1Enabled else { return }
            castItems = loadedCastItems
            didLoadCredits = true
        }
        .onDisappear {
            screenLoadGeneration = UUID()
            creditsLoadGeneration = UUID()
            toastDismissTask?.cancel()
        }
        .detailReleases(kind: .anime, id: anime.id, schedule: $releaseItems, songs: $releaseSongs)
        // This detail sheet's own presentation context: the cards and the action bar inside open their
        // routes here (stacked on this detail, as before).
        .routePresenter()
    }

    @MainActor
    private func showToast(_ next: KuroToastState) {
        toastDismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            toast = next
        }
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(2.2 * 1_000_000_000))
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.2)) {
                    toast = nil
                }
            }
        }
    }
}

/// The anime's own next airing (catalogue row), used by the episode preview before any episode rows
/// load. Only a future airing time counts: an episode number is never guessed from a past time.
private struct AnimeUpcomingEpisodeDisplay {
    let number: Int
    let airingAt: Date

    private func relative(_ style: RelativeDateTimeFormatter.UnitsStyle) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = style
        formatter.locale = KuroLocale.locale
        return formatter.localizedString(for: airingAt, relativeTo: Date())
    }

    var sectionLine: String {
        KuroLocale.text("Next airing: episode \(number).", "Als Nächstes: Folge \(number).")
    }

    var fallbackTitle: String {
        KuroLocale.text("Next airing episode", "Nächste Folge")
    }

    var fallbackBadge: String {
        KuroLocale.text("SCHEDULED", "GEPLANT")
    }

    var fallbackSubtitle: String {
        relative(.full)
    }
}

private extension Anime {
    var effectiveUpcomingEpisodeDisplay: AnimeUpcomingEpisodeDisplay? {
        guard let rawNextEpisode = nextEpisodeNumber, rawNextEpisode > 0,
              let nextAiringAt, nextAiringAt > Date() else { return nil }
        return AnimeUpcomingEpisodeDisplay(number: rawNextEpisode, airingAt: nextAiringAt)
    }
}

// MARK: - Swiss-minimal metadata line (replaces grids)
struct MetaLineSection: View {
    let anime: Anime

    private var scoreText: String? {
        guard let score = anime.averageScore, score > 0 else { return nil }
        return String(format: "%.1f", Double(score) / 10.0)
    }

    private var episodeText: String? {
        if let e = anime.episodeCount, e > 0 { return "\(e) EPS" }
        if let next = anime.nextEpisodeNumber, next > 1 { return "\(max(0, next - 1)) EPS" }
        return nil
    }

    private var statusText: String? {
        anime.status?.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    var body: some View {
        let parts: [String] = [
            scoreText.map { "SCORE \($0)" },
            anime.displayYear.isEmpty ? nil : anime.displayYear,
            anime.format?.uppercased(),
            episodeText,
            statusText
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.kuroMicro(weight: .light))
                .tracking(1.2)
                .foregroundColor(.kuroBlack60)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Similar rail (minimal)
struct SimilarSection: View {
    let title: String
    let items: [Anime]
    let containerWidth: CGFloat

    private var cardWidth: CGFloat {
        let candidate = floor((containerWidth - 56) / 2.8)
        return min(144, max(112, candidate))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.md) {
            Text(title)
                .font(.kuroMicro(weight: .medium))
                .tracking(1.5)
                .foregroundColor(.kuroBlack80)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items.prefix(14), id: \.id) { item in
                        KuroCompactCard(media: item, width: cardWidth)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - "NEXT" suggestion when user completed this series (heuristic pick)
struct NextPickSection: View {
    let mediaId: Int
    let mediaType: String
    let similar: [Anime]
    @Environment(LibraryStore.self) private var library
    @State private var showDetail = false

    private var userEntry: LibraryEntry? {
        MediaKey(mediaType: mediaType, id: mediaId).flatMap { library.entry(for: $0) }
    }

    private var isCompleted: Bool {
        userEntry?.status == .completed
    }

    /// Best pick: prefer PLANNING items, then highest-scored item not already in the user's collection.
    private var pick: Anime? {
        guard isCompleted else { return nil }
        // First try: PLANNING items from the similar list
        if let planned = similar.first(where: { library.entry(for: $0.libraryKey)?.status == .planning }) {
            return planned
        }

        // Fallback: highest-scored item not in collection
        return similar
            .filter { !library.isTracked($0.libraryKey) }
            .max(by: { ($0.averageScore ?? 0) < ($1.averageScore ?? 0) })
    }

    var body: some View {
        if let anime = pick {
            VStack(alignment: .leading, spacing: KuroSpacing.md) {
                Text("NEXT")
                    .font(.kuroCaption(weight: .medium))
                    .tracking(1.6)
                    .foregroundColor(.kuroBlack80)

                Button {
                    KuroAccessibility.impactHaptic(.light)
                    showDetail = true
                } label: {
                    HStack(spacing: 12) {
                        KuroCachedAsyncImage(url: URL(string: anime.displayImage), maxPixelSize: 200) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            case .failure, .empty:
                                Rectangle().fill(Color.kuroBlack08)
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(width: 48, height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(anime.displayTitle)
                                .font(.kuroBody(weight: .regular))
                                .foregroundColor(.kuroBlack)
                                .lineLimit(2)

                            HStack(spacing: 4) {
                                Text(anime.displayYear)
                                if let fmt = anime.format {
                                    Text("·")
                                    Text(fmt.uppercased())
                                }
                            }
                            .font(.kuroCaption())
                            .foregroundColor(.kuroBlack60)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.kuroCustom(12, weight: .medium, maxSize: 19))
                            .foregroundColor(.kuroBlack30)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showDetail) {
                    MediaDetailSheet(kind: .anime, id: anime.id)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Hero Section with Parallax
struct HeroSection: View {
    let anime: Anime
    let geometry: GeometryProxy
    @Binding var scrollOffset: CGFloat
    
    var body: some View {
        let baseHeight = ResponsiveLayout.imageHeight(320)
        let stretch = max(scrollOffset, 0)
        let parallax = min(scrollOffset, 0) * 0.32

        ZStack(alignment: .bottom) {
            // Banner/Cover Image with Parallax
            KuroCachedAsyncImage(url: URL(string: anime.bannerImage ?? anime.displayImage), maxPixelSize: 1400) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.kuroBlack08, Color.kuroBlack.opacity(0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .frame(width: geometry.size.width, height: baseHeight + stretch)
            .clipped()
            // Pull-down stretch + subtle parallax (prevents top whitespace while keeping it calm/minimal).
            .offset(y: parallax - stretch)
            
            // Tiny seam fade so the hero feels "full-bleed" (no big white wash).
            LinearGradient(
                colors: [Color.clear, Color.kuroBackground.opacity(0.92), Color.kuroBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 88)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
            
            HStack(alignment: .bottom, spacing: 12) {
                KuroCachedAsyncImage(url: URL(string: anime.displayImage), maxPixelSize: 520) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.kuroBlack08)
                }
                .frame(width: 92, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.65), lineWidth: 0.6)
                        .blendMode(.overlay)
                )
                .shadow(color: Color.black.opacity(0.22), radius: 18, x: 0, y: 12)

                Spacer(minLength: 0)

                KuroStyle.mediaBadge("ANIME", isAnime: true)
            }
            .padding(.horizontal, ResponsiveLayout.padding())
            .padding(.bottom, 16)
        }
        .frame(height: baseHeight)
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Title Section
struct TitleSection: View {
    let anime: Anime
    
    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.sm) {
            // Japanese/Native Title
            if let nativeTitle = anime.titleNative {
                Text(nativeTitle)
                    .font(.kuroMicro(weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.kuroBlack60)
            }
            
            // Main Title
            Text(anime.displayTitle.uppercased())
                .font(.kuroCustom(24, weight: .ultraLight, design: .serif, relativeTo: .title2, maxSize: 40))
                .tracking(0.5)
                .foregroundColor(.kuroBlack)
                .lineSpacing(4)
            
            // Year & Format
            HStack(spacing: KuroSpacing.sm) {
                Text(anime.displayYear)
                    .font(.kuroMicro(weight: .regular))
                    .tracking(1.0)
                    .foregroundColor(.kuroBlack60)
                
                if let format = anime.format {
                    Text("•")
                        .foregroundColor(.kuroBlack30)
                    Text(format)
                        .font(.kuroMicro(weight: .light))
                        .tracking(1.0)
                        .foregroundColor(.kuroBlack60)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Episodes Section
struct EpisodesSection: View {
    let anime: Anime
    let episodeCount: Int
    let countLabel: String
    var onError: ((KuroToastState) -> Void)? = nil
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @State private var progressActionScope = AccountActionScope()
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.openURL) private var openURL
    @State private var episodes: [Episode] = []
    @State private var isLoading: Bool = false
    @State private var showAllEpisodes: Bool = false
    @State private var markingEpisode: Int? = nil
    @State private var previewGeneration = UUID()

    private var entry: LibraryEntry? {
        library.entry(for: anime.libraryKey)
    }

    private var userProgress: Int {
        entry?.progress ?? 0
    }

    private var shouldUseProgress: Bool {
        guard let status = entry?.status else { return userProgress > 0 }
        return userProgress > 0 || status == .current || status == .repeating
    }

    private var nextEpisodeNumber: Int {
        if shouldUseProgress {
            return max(1, userProgress + 1)
        }
        if let releasePreview = anime.effectiveUpcomingEpisodeDisplay {
            return releasePreview.number
        }
        return 1
    }

    private var hasEpisodePreview: Bool {
        !episodes.isEmpty
    }

    private var fallbackPreview: AnimeUpcomingEpisodeDisplay? {
        guard episodes.isEmpty, !shouldUseProgress else { return nil }
        return anime.effectiveUpcomingEpisodeDisplay
    }

    private var progressLine: String? {
        if shouldUseProgress {
            guard hasEpisodePreview else { return nil }
            return "Continue with episode \(nextEpisodeNumber)."
        }
        if let releasePreview = anime.effectiveUpcomingEpisodeDisplay {
            return releasePreview.sectionLine
        }
        return nil
    }
    
    var body: some View {
        let origin = progressActionScope.capture(session: libraryActions.accountSession)
        return VStack(alignment: .leading, spacing: KuroSpacing.md) {
            HStack {
                Text("EPISODES")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(.kuroBlack80)
                
                Spacer()
                
                if hasEpisodePreview {
                    Text("\(episodeCount) \(countLabel)")
                        .font(.kuroMicro(weight: .light))
                        .tracking(0.5)
                        .foregroundColor(.kuroBlack60)
                }
            }

            if let progressLine {
                Text(progressLine)
                    .font(.kuroMicro(weight: .medium))
                    .foregroundColor(.kuroBlack60)
            }
            
            VStack(spacing: KuroSpacing.sm) {
                if isLoading && episodes.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in
                        EpisodeSkeletonRow()
                    }
                } else if let fallbackPreview {
                    EpisodePreviewFallbackRow(preview: fallbackPreview)
                } else if episodes.isEmpty {
                    HStack {
                        Text("Episode data coming soon")
                            .font(.kuroMicro(weight: .light))
                            .foregroundColor(.kuroBlack60)
                        Spacer()
                    }
                    .padding(KuroSpacing.md)
                    .background(Color.kuroBlack08)
                    .cornerRadius(KuroRadius.sm)
                } else {
                    ForEach(episodes.prefix(1)) { ep in
                        EpisodeItemRow(
                            episode: ep,
                            isWatched: ep.number <= userProgress,
                            hasOpenLink: ProviderAvailabilityStore.validatedOutboundURL(ep.streamUrl) != nil,
                            isMarking: markingEpisode == ep.number,
                            onOpen: { openEpisode(ep) },
                            onMarkWatched: { markWatched(ep, origin: origin) }
                        )
                    }
                }

                if hasEpisodePreview && episodeCount > 5 {
                    Button(action: {
                        KuroAccessibility.impactHaptic(.light)
                        showAllEpisodes = true
                    }) {
                        DetailSectionUtilityButton(
                            title: "VIEW ALL \(episodeCount) EPISODES",
                            subtitle: "Browse the full release list"
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: nextEpisodeNumber) {
            guard !Task.isCancelled else { return }
            let generation = UUID()
            previewGeneration = generation
            let fromNumber = nextEpisodeNumber
            await loadPreview(generation: generation, fromNumber: fromNumber)
        }
        .sheet(isPresented: $showAllEpisodes) {
            EpisodeListSheet(anime: anime, episodeCount: episodeCount)
        }
        .onAppear { progressActionScope.activate(session: libraryActions.accountSession) }
        .onDisappear {
            progressActionScope.deactivate()
            markingEpisode = nil
            previewGeneration = UUID()
            isLoading = false
        }
    }

    private func isCurrentPreview(_ generation: UUID, fromNumber: Int) -> Bool {
        !Task.isCancelled && previewGeneration == generation && nextEpisodeNumber == fromNumber
    }

    private func loadPreview(generation: UUID, fromNumber: Int) async {
        guard isCurrentPreview(generation, fromNumber: fromNumber) else { return }
        isLoading = true
        defer {
            if isCurrentPreview(generation, fromNumber: fromNumber) { isLoading = false }
        }
        let preview = await catalog.fetchEpisodesNext(animeId: anime.id, fromNumber: fromNumber, limit: 10)
        guard isCurrentPreview(generation, fromNumber: fromNumber) else { return }
        episodes = preview
    }

    private func openEpisode(_ ep: Episode) {
        KuroAccessibility.impactHaptic(.light)
        if let url = ProviderAvailabilityStore.validatedOutboundURL(ep.streamUrl) {
            openURL(url)
        } else {
            onError?(
                KuroToastState(
                    kind: .info,
                    title: "No legal stream link yet",
                    subtitle: "This episode does not have a verified legal provider.",
                    actionTitle: nil,
                    onAction: nil
                )
            )
        }
    }

    private func markWatched(_ ep: Episode, origin: AccountActionScope.Ticket?) {
        guard progressActionScope.isCurrent(origin, session: libraryActions.accountSession) else { return }
        let target = min(ep.number, episodeCount)
        markingEpisode = ep.number
        progressActionScope.launch(origin: origin, session: libraryActions.accountSession) { ticket in
            let outcome = await LibraryViewActions.markProgress(anime.libraryKey, to: target, actions: libraryActions)
            guard progressActionScope.isCurrent(ticket, session: libraryActions.accountSession) else { return }
            if outcome.error != nil {
                KuroAccessibility.errorHaptic()
                onError?(KuroToastState(kind: .error, title: "Update failed", subtitle: "Could not mark episode \(ep.number).", actionTitle: nil, onAction: nil))
                #if DEBUG
                print("markWatched failed for episode \(ep.number): \(outcome)")
                #endif
            }
            markingEpisode = nil
        }
    }
}

struct EpisodeItemRow: View {
    let episode: Episode
    let isWatched: Bool
    let hasOpenLink: Bool
    let isMarking: Bool
    let onOpen: () -> Void
    let onMarkWatched: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("EP \(episode.number)".uppercased())
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.0)
                    .foregroundColor(.kuroBlack80)

                if let title = episode.title ?? episode.titleRomaji, !title.isEmpty {
                    Text(title)
                        .font(.kuroMicro(weight: .light))
                        .foregroundColor(.kuroBlack60)
                        .lineLimit(1)
                } else if let site = episode.streamSite, !site.isEmpty {
                    Text(site.uppercased())
                        .font(.kuroMicro(weight: .light))
                        .foregroundColor(.kuroBlack60)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(hasOpenLink ? "WATCH READY" : "LINK PENDING")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(0.8)
                        .foregroundColor(hasOpenLink ? .kuroBlack80 : .kuroBlack60)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(hasOpenLink ? Color.kuroBlack08 : Color.kuroBlack05)
                        )
                }
            }

            Spacer()

            if isMarking {
                ProgressView()
                    .scaleEffect(0.75)
            } else if isWatched {
                Image(systemName: "checkmark.circle.fill")
                    .font(.kuroCustom(14, weight: .semibold, maxSize: 22))
                    .foregroundColor(.kuroBlack)
            } else {
                Button(action: {
                    KuroAccessibility.impactHaptic(.light)
                    onMarkWatched()
                }) {
                    Image(systemName: "plus.circle")
                        .font(.kuroCustom(16, weight: .regular, maxSize: 26))
                        .foregroundColor(.kuroBlack80)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark watched")
            }

            Image(systemName: "chevron.right")
                .font(.kuroMicro())
                .foregroundColor(.kuroBlack30)
        }
        .padding(KuroSpacing.md)
        .background(Color.kuroBlack08)
        .cornerRadius(KuroRadius.sm)
        .contentShape(Rectangle())
        .onTapGesture { if hasOpenLink { onOpen() } }
        // Make the whole row operable in VoiceOver (plus-button stays visual; action is exposed below).
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabelText())
        .accessibilityValue(accessibilityValueText())
        .accessibilityHint(hasOpenLink ? "Opens episode" : "Legal stream link not available yet")
        .accessibilityAction { if hasOpenLink { onOpen() } }
        .accessibilityAction(named: "Mark watched") {
            if !isWatched && !isMarking { onMarkWatched() }
        }
    }

    private func accessibilityLabelText() -> Text {
        var parts: [String] = []
        parts.append("Episode \(episode.number)")
        if let title = episode.title ?? episode.titleRomaji, !title.isEmpty {
            parts.append(title)
        } else if let site = episode.streamSite, !site.isEmpty {
            parts.append(site)
        }
        return Text(parts.joined(separator: ", "))
    }

    private func accessibilityValueText() -> Text {
        if isMarking { return Text("Updating") }
        return Text(isWatched ? "Watched" : "Not watched")
    }
}

struct EpisodeSkeletonRow: View {
    var body: some View {
        HStack {
            Rectangle()
                .fill(Color.kuroBlack.opacity(0.08))
                .frame(height: 10)
                .frame(maxWidth: 90, alignment: .leading)
            Spacer()
            Rectangle()
                .fill(Color.kuroBlack.opacity(0.06))
                .frame(width: 14, height: 14)
        }
        .padding(KuroSpacing.md)
        .background(Color.kuroBlack08)
        .cornerRadius(KuroRadius.sm)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

private struct EpisodePreviewFallbackRow: View {
    let preview: AnimeUpcomingEpisodeDisplay

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("EP \(preview.number)")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.0)
                    .foregroundColor(.kuroBlack80)

                Text(preview.fallbackTitle)
                    .font(.kuroMicro(weight: .light))
                    .foregroundColor(.kuroBlack60)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(preview.fallbackBadge)
                        .font(.kuroMicro(weight: .medium))
                        .tracking(0.8)
                        .foregroundColor(.kuroBlack80)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.kuroBlack05)
                        )
                }
            }

            Spacer(minLength: 0)

            Text(preview.fallbackSubtitle)
                .font(.kuroMicro(weight: .light))
                .foregroundColor(.kuroBlack60)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120, alignment: .trailing)
        }
        .padding(KuroSpacing.md)
        .background(Color.kuroBlack08)
        .cornerRadius(KuroRadius.sm)
        .accessibilityElement(children: .combine)
    }
}

struct EpisodeListSheet: View {
    let anime: Anime
    let episodeCount: Int
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @State private var progressActionScope = AccountActionScope()
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var episodes: [Episode] = []
    @State private var isLoading: Bool = false
    @State private var hasLoadedOnce: Bool = false
    @State private var hasMore: Bool = true
    @State private var offset: Int = 0
    @State private var pagingGeneration = UUID()
    @State private var pagingTask: Task<Void, Never>? = nil
    @State private var markingEpisode: Int? = nil
    @State private var toast: KuroToastState? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil

    private let pageSize: Int = 50

    private var userProgress: Int { library.entry(for: anime.libraryKey)?.progress ?? 0 }

    var body: some View {
        let origin = progressActionScope.capture(session: libraryActions.accountSession)
        return NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: KuroSpacing.sm) {
                    if hasLoadedOnce && episodes.isEmpty && !isLoading {
                        VStack(spacing: 10) {
                            Text("NO EPISODES FOUND")
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.2)
                                .foregroundColor(.kuroBlack60)
                            Text("Episode data may still be importing.")
                                .font(.kuroMicro(weight: .light))
                                .foregroundColor(.kuroBlack30)
                        }
                        .padding(.vertical, 32)
                    }

                    ForEach(Array(episodes.enumerated()), id: \.element.id) { index, ep in
                        EpisodeItemRow(
                            episode: ep,
                            isWatched: ep.number <= userProgress,
                            hasOpenLink: ProviderAvailabilityStore.validatedOutboundURL(ep.streamUrl) != nil,
                            isMarking: markingEpisode == ep.number,
                            onOpen: { openEpisode(ep) },
                            onMarkWatched: { markWatched(ep, origin: origin) }
                        )
                        .onAppear {
                            if index == episodes.count - 1, hasMore, !isLoading {
                                startLoadMore()
                            }
                        }
                    }

                    if isLoading {
                        ProgressView()
                            .padding(.vertical, 16)
                    }
                }
                .padding(.horizontal, ResponsiveLayout.padding())
                .padding(.top, KuroSpacing.md)
                .padding(.bottom, KuroSpacing.xl)
            }
            .background(Color.kuroBackground)
            .navigationTitle("Episodes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .font(.kuroMicro(weight: .medium))
                }
            }
            .task(id: anime.id) {
                guard !Task.isCancelled else { return }
                pagingTask?.cancel()
                pagingTask = nil
                let generation = UUID()
                pagingGeneration = generation
                await loadMore(reset: true, generation: generation)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                KuroToast(toast: toast)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { progressActionScope.activate(session: libraryActions.accountSession) }
        .onDisappear {
            progressActionScope.deactivate()
            markingEpisode = nil
            pagingGeneration = UUID()
            pagingTask?.cancel()
            pagingTask = nil
            toastDismissTask?.cancel()
            isLoading = false
        }
    }

    @MainActor
    private func showToast(_ next: KuroToastState) {
        toastDismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { toast = next }
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(2.2 * 1_000_000_000))
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.2)) { toast = nil }
            }
        }
    }

    private func startLoadMore() {
        guard hasMore, !isLoading, pagingTask == nil else { return }
        let generation = UUID()
        pagingGeneration = generation
        pagingTask = Task { await loadMore(generation: generation) }
    }

    private func loadMore(reset: Bool = false, generation: UUID) async {
        guard !Task.isCancelled, pagingGeneration == generation else { return }
        if reset {
            isLoading = false
            episodes = []
            offset = 0
            hasMore = true
            hasLoadedOnce = false
        }
        guard hasMore, !isLoading else { return }
        let requestedOffset = offset
        isLoading = true
        defer {
            if !Task.isCancelled, pagingGeneration == generation {
                isLoading = false
                pagingTask = nil
            }
        }

        let page = await catalog.fetchEpisodesPage(animeId: anime.id, offset: requestedOffset, limit: pageSize)
        guard !Task.isCancelled, pagingGeneration == generation, offset == requestedOffset else { return }
        episodes.append(contentsOf: page)
        hasMore = page.count == pageSize
        if hasMore { offset = requestedOffset + pageSize }
        hasLoadedOnce = true
    }

    private func openEpisode(_ ep: Episode) {
        KuroAccessibility.impactHaptic(.light)
        if let url = ProviderAvailabilityStore.validatedOutboundURL(ep.streamUrl) {
            openURL(url)
        } else {
            showToast(
                KuroToastState(
                    kind: .info,
                    title: "No legal stream link yet",
                    subtitle: "This episode does not have a verified legal provider.",
                    actionTitle: nil,
                    onAction: nil
                )
            )
        }
    }

    private func markWatched(_ ep: Episode, origin: AccountActionScope.Ticket?) {
        guard progressActionScope.isCurrent(origin, session: libraryActions.accountSession) else { return }
        let target = min(ep.number, episodeCount)
        markingEpisode = ep.number
        progressActionScope.launch(origin: origin, session: libraryActions.accountSession) { ticket in
            let outcome = await LibraryViewActions.markProgress(anime.libraryKey, to: target, actions: libraryActions)
            guard progressActionScope.isCurrent(ticket, session: libraryActions.accountSession) else { return }
            if outcome.error != nil {
                KuroAccessibility.errorHaptic()
                showToast(KuroToastState(kind: .error, title: "Update failed", subtitle: "Could not mark episode \(ep.number).", actionTitle: nil, onAction: nil))
                #if DEBUG
                print("markWatched failed for episode \(ep.number): \(outcome)")
                #endif
            }
            markingEpisode = nil
        }
    }
}

// MARK: - Action Buttons
struct ActionButtons: View {
    let anime: Anime
    let onToast: (KuroToastState) -> Void
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @State private var actionScope = AccountActionScope()
    @Environment(OutboundLinkTelemetry.self) private var outboundLinks
    @Environment(ProviderAvailabilityStore.self) private var availability
    @Environment(\.openURL) private var openURL
    @Environment(\.kuroRoutes) private var routes
    @State private var showQuickVerdict = false
    @State private var showProviders = false
    @State private var watchLink: ProviderSheetItem? = nil
    @State private var allLinks: [ProviderSheetItem] = []
    @State private var watchAvailabilityNote: String? = nil
    @State private var watchAvailabilityStatusCaption: String? = nil

    private var isGermanLocale: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("de") == true
    }

    private var isSaved: Bool {
        library.isTracked(anime.libraryKey)
    }

    private var userEntry: LibraryEntry? {
        library.entry(for: anime.libraryKey)
    }

    private var hasWatchLink: Bool {
        watchLink.flatMap { ProviderAvailabilityStore.validatedOutboundURL($0.url) } != nil
    }

    private var verdictButtonTitle: String {
        guard let verdict = userEntry?.verdict else { return isGermanLocale ? "Urteil" : "Verdict" }
        return isGermanLocale ? verdict.displayNameDE : verdict.displayName
    }

    private var watchStatusLine: String {
        if let status = watchAvailabilityStatusCaption, !status.isEmpty {
            return status
        }
        if let note = watchAvailabilityNote, !note.isEmpty {
            return note
        }
        return hasWatchLink
            ? (isGermanLocale ? "Rechtlich verfuegbaren Link oeffnen." : "Open legal provider link.")
            : (isGermanLocale ? "Noch kein legaler Link verfuegbar." : "No legal provider link is available yet.")
    }

    var body: some View {
        let origin = actionScope.capture(session: libraryActions.accountSession)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button { toggleSaved(origin: origin) } label: {
                    Image(systemName: isSaved ? "heart.fill" : "heart")
                        .font(.kuroCustom(14, weight: .semibold, maxSize: 22))
                        .foregroundColor(.kuroBlack)
                        .frame(width: 38, height: 38)
                        .background(Color.kuroBlack08)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSaved ? "Saved" : "Save")

                Button {
                    KuroAccessibility.impactHaptic(.medium)
                    routes.presentTrackingEditor(TrackingEditorRequest(media: anime))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.kuroCustom(14, weight: .semibold, maxSize: 22))
                        Text(isSaved ? "EDIT LIST" : "ADD TO LIST")
                            .font(.kuroMicro(weight: .medium))
                            .tracking(1.1)
                    }
                    .foregroundColor(.kuroWhite)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.kuroBlack)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    KuroAccessibility.impactHaptic(.light)
                    showQuickVerdict = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tag")
                            .font(.kuroCustom(11, weight: .semibold, maxSize: 18))
                        Text(verdictButtonTitle.uppercased())
                            .font(.kuroMicro(weight: .medium))
                            .tracking(0.9)
                            .lineLimit(1)
                    }
                    .foregroundColor(.kuroBlack70)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.kuroBlack06)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.kuroBlack12, lineWidth: 0.6)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(userEntry?.verdict == nil ? "Set verdict" : "Edit verdict")

                Button(action: handleWatchAction) {
                    Image(systemName: hasWatchLink ? "play.fill" : "play.slash")
                        .font(.kuroCustom(13, weight: .semibold, maxSize: 21))
                        .foregroundColor(hasWatchLink ? .kuroBlack : .kuroBlack30)
                        .frame(width: 38, height: 38)
                        .background(Color.kuroBlack08)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    hasWatchLink
                        ? (allLinks.count > 1 ? "Choose watch provider" : "Open watch provider")
                        : "No legal watch link available"
                )
            }

            Text(watchStatusLine)
                .font(.kuroMicro(weight: .light))
                .foregroundColor(.kuroTextTertiary)
                .lineLimit(2)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.kuroBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.8)
                )
        )
        .onAppear { actionScope.activate(session: libraryActions.accountSession) }
        .onDisappear { actionScope.deactivate() }
        .task(id: userEntry?.progress ?? -1) {
            await refreshLinks()
        }
        .sheet(isPresented: $showQuickVerdict) {
            QuickVerdictPickerSheet(media: anime, onToast: onToast)
        }
        .sheet(isPresented: $showProviders) {
            ProviderSelectionSheet(
                title: "Watch On",
                links: allLinks,
                statusCaption: watchAvailabilityStatusCaption
            ) { link in
                if let url = ProviderAvailabilityStore.validatedOutboundURL(link.url) {
                    KuroAccessibility.impactHaptic(.light)
                    outboundLinks.recordOutboundLink(mediaType: "ANIME", mediaId: anime.id, linkKind: "provider_sheet", provider: link.title)
                    openURL(url)
                } else {
                    onToast(.init(kind: .error, title: "Couldn’t open link", subtitle: "Try a different provider.", actionTitle: nil, onAction: nil))
                }
            }
        }
    }

    private func toggleSaved(origin: AccountActionScope.Ticket?) {
        guard actionScope.isCurrent(origin, session: libraryActions.accountSession) else { return }
        let currentlySaved = isSaved
        let key = anime.libraryKey
        actionScope.launch(origin: origin, session: libraryActions.accountSession) { ticket in
            let outcome = currentlySaved
                ? await libraryActions.remove(key)
                : await libraryActions.save(key, status: .planning)

            guard actionScope.isCurrent(ticket, session: libraryActions.accountSession) else { return }
            await MainActor.run {
                guard actionScope.isCurrent(ticket, session: libraryActions.accountSession) else { return }
                if outcome.change != nil {
                    KuroAccessibility.successHaptic()
                    onToast(
                        .init(
                            kind: .success,
                            title: currentlySaved ? "Removed" : "Saved",
                            subtitle: currentlySaved ? "Removed from your list" : "Added to Planning",
                            actionTitle: nil,
                            onAction: nil
                        )
                    )
                } else {
                    KuroAccessibility.errorHaptic()
                    onToast(
                        .init(
                            kind: .error,
                            title: "Couldn't save",
                            subtitle: outcome.error.map { friendlyListMutationMessage($0, isGerman: false) },
                            actionTitle: nil,
                            onAction: nil
                        )
                    )
                }
            }
        }
    }

    private func handleWatchAction() {
        guard let link = watchLink, let linkURL = ProviderAvailabilityStore.validatedOutboundURL(link.url) else {
            KuroAccessibility.impactHaptic(.light)
            onToast(
                .init(
                    kind: .info,
                    title: "Link coming soon",
                    subtitle: "No legal provider link is available yet.",
                    actionTitle: nil,
                    onAction: nil
                )
            )
            return
        }

        KuroAccessibility.impactHaptic(.medium)
        if allLinks.count > 1 {
            showProviders = true
        } else {
            outboundLinks.recordOutboundLink(mediaType: "ANIME", mediaId: anime.id, linkKind: "watch", provider: link.title)
            openURL(linkURL)
        }
    }

    /// Resolves the watch links through the ProviderAvailability owner (keyed on the viewer's progress:
    /// the primary is the next episode's provider) and publishes them unless this run was superseded.
    private func refreshLinks() async {
        let progress = library.entry(for: anime.libraryKey)?.progress
        guard let snapshot = await availability.resolveWatchLinks(
            animeId: anime.id,
            originalLanguage: anime.inferredOriginalLanguageCode,
            progress: progress
        ), !Task.isCancelled else { return }
        watchLink = snapshot.primary
        allLinks = snapshot.all
        watchAvailabilityNote = snapshot.note
        watchAvailabilityStatusCaption = snapshot.statusCaption
    }
}
