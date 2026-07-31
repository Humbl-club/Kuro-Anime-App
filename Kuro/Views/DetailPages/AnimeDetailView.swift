import SwiftUI

// MARK: - ANIME DETAIL VIEW - iOS 26 Mobile-First
// Comprehensive anime detail page with elegant minimalism

struct AnimeDetailView: View {
    let anime: Anime
    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseService.self) private var supabaseService
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

    var body: some View {
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

                        NextUpSection(anime: anime)
                        
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

                        if FeatureFlags.shared.isCreditsCastV1Enabled {
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

                        if FeatureFlags.shared.isSocialActivityV1Enabled {
                            FriendsActivitySection(mediaId: anime.id, mediaType: "ANIME")
                        }

                        ShareLink(
                            item: URL(string: "kuro://anime/\(anime.id)")!,
                            subject: Text(anime.displayTitle)
                        ) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 11, weight: .medium))
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
            async let tags = supabaseService.fetchTopTagsForAnime(animeId: anime.id, limit: 12)
            async let sim = supabaseService.fetchSimilarAnime(seed: anime, limit: 14)
            async let ladder = supabaseService.fetchMediaLadder(mediaType: "ANIME", mediaId: anime.id)
            topTags = await tags
            similar = await sim
            mediaLadder = await ladder
            didLoadLadder = true
            await supabaseService.enqueueMediaRelationRefreshIfNeeded(
                mediaType: "ANIME",
                mediaId: anime.id,
                ladder: mediaLadder,
                reason: "detail_open"
            )

            // Condense long synopses on-device via Apple FM (no-op on unsupported devices)
            let sourceSynopsis = anime.displayDescription
            let hasReadyEnhanced = (anime.synopsisEnhancedState ?? "").lowercased() == "ready"
            if !hasReadyEnhanced, sourceSynopsis.count > 200 {
                condensedSynopsis = await supabaseService.fmService.condenseSynopsis(
                    mediaId: anime.id,
                    description: sourceSynopsis,
                    title: anime.displayTitle,
                    genres: anime.genreList ?? []
                )
            }
        }
        .task(id: "\(anime.id)-\(FeatureFlags.shared.isCreditsCastV1Enabled)") {
            guard FeatureFlags.shared.isCreditsCastV1Enabled else { return }
            async let studioFetch = supabaseService.fetchStudiosForAnime(animeId: anime.id)
            async let staffFetch = supabaseService.fetchStaffForAnime(animeId: anime.id)
            async let castFetch = supabaseService.fetchCharactersForAnime(animeId: anime.id)
            studios = await studioFetch
            staffItems = await staffFetch
            castItems = await castFetch
            didLoadCredits = true
        }
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

private struct AnimeUpcomingEpisodeDisplay {
    enum Timing {
        case scheduled(Date)
        case awaitingSchedule
    }

    let number: Int
    let timing: Timing

    var detailLine: String {
        switch timing {
        case .scheduled(let date):
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return formatter.localizedString(for: date, relativeTo: Date()).uppercased()
        case .awaitingSchedule:
            return "AIR DATE TBA"
        }
    }

    var sectionLine: String {
        switch timing {
        case .scheduled:
            return "Next airing episode \(number)."
        case .awaitingSchedule:
            return "Next episode \(number) is pending a schedule update."
        }
    }

    var fallbackTitle: String {
        switch timing {
        case .scheduled:
            return "Next airing episode"
        case .awaitingSchedule:
            return "Next episode"
        }
    }

    var fallbackBadge: String {
        switch timing {
        case .scheduled:
            return "SCHEDULED"
        case .awaitingSchedule:
            return "UPDATING"
        }
    }

    var fallbackSubtitle: String {
        switch timing {
        case .scheduled(let date):
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(for: date, relativeTo: Date())
        case .awaitingSchedule:
            return "Awaiting the next release time from the feed."
        }
    }
}

private extension Anime {
    var effectiveUpcomingEpisodeDisplay: AnimeUpcomingEpisodeDisplay? {
        guard let rawNextEpisode = nextEpisodeNumber, rawNextEpisode > 0 else { return nil }

        let now = Date()
        if let nextAiringAt, nextAiringAt > now {
            return AnimeUpcomingEpisodeDisplay(number: rawNextEpisode, timing: .scheduled(nextAiringAt))
        }

        guard status?.uppercased() == "RELEASING" else { return nil }

        if let totalEpisodes = episodeCount, rawNextEpisode < totalEpisodes {
            return AnimeUpcomingEpisodeDisplay(number: rawNextEpisode + 1, timing: .awaitingSchedule)
        }

        return nil
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

// MARK: - Next up (minimal)
struct NextUpSection: View {
    let anime: Anime

    var body: some View {
        if let nextRelease = anime.effectiveUpcomingEpisodeDisplay {
            HStack(spacing: 12) {
                Text("NEXT UP")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.8)
                    .foregroundColor(.kuroBlack80)

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("EP \(nextRelease.number)".uppercased())
                        .font(.kuroMicro(weight: .regular))
                        .tracking(1.2)
                        .foregroundColor(.kuroBlack80)

                    Text(nextRelease.detailLine)
                        .font(.kuroMicro(weight: .light))
                        .tracking(1.0)
                        .foregroundColor(.kuroBlack30)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
            )
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Minimal tag chips
struct TagChipsSection: View {
    let title: String
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.md) {
            Text(title)
                .font(.kuroMicro(weight: .medium))
                .tracking(1.5)
                .foregroundColor(.kuroBlack80)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tags.prefix(18), id: \.self) { t in
                        Text(t.uppercased())
                            .font(.kuroMicro(weight: .light))
                            .tracking(0.8)
                            .foregroundColor(.kuroBlack60)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().stroke(Color.black.opacity(0.10), lineWidth: 0.7)
                            )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    @Environment(SupabaseService.self) private var supabaseService
    @State private var showDetail = false

    private var userEntry: UserList? {
        supabaseService.userLists.first {
            $0.mediaId == mediaId && $0.mediaType.lowercased() == mediaType.lowercased()
        }
    }

    private var isCompleted: Bool {
        userEntry?.status == .completed
    }

    /// Best pick: prefer PLANNING items, then highest-scored item not already in the user's collection.
    private var pick: Anime? {
        guard isCompleted else { return nil }
        let collectionIds = supabaseService.userMediaIds(mediaType: "anime")
        let planningIds = supabaseService.userMediaIds(mediaType: "anime", status: .planning)

        // First try: PLANNING items from the similar list
        if let planned = similar.first(where: { planningIds.contains($0.id) }) {
            return planned
        }

        // Fallback: highest-scored item not in collection
        return similar
            .filter { !collectionIds.contains($0.id) }
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
                            .font(.system(size: 12, weight: .medium))
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

private struct KuroDetailScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
                .font(.system(size: ResponsiveLayout.fontSize(24), weight: .ultraLight, design: .serif))
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

// MARK: - Stats Grid
struct StatsGrid: View {
    let anime: Anime
    
    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: KuroSpacing.md
        ) {
            if let score = anime.averageScore {
                StatCard(
                    label: "SCORE",
                    value: String(format: "%.1f", Double(score) / 10.0),
                    icon: "star.fill"
                )
            }
            
            if let episodes = anime.episodeCount {
                StatCard(
                    label: "EPISODES",
                    value: "\(episodes)",
                    icon: "play.circle.fill"
                )
            }
            
            if let status = anime.status {
                StatCard(
                    label: "STATUS",
                    value: status.capitalized,
                    icon: "circle.fill"
                )
            }
        }
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: KuroSpacing.xs) {
            Image(systemName: icon)
                .font(.kuroMicro())
                .foregroundColor(.kuroBlack30)
            
            Text(value)
                .font(.kuroCardTitle(weight: .light))
                .foregroundColor(.kuroBlack)
            
            Text(label)
                .font(.kuroMicro(weight: .light))
                .tracking(0.5)
                .foregroundColor(.kuroBlack60)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, KuroSpacing.md)
        .background(Color.kuroBlack08)
        .cornerRadius(KuroRadius.sm)
    }
}

// MARK: - Description Section
struct DescriptionSection: View {
    let description: String
    @Binding var showFull: Bool
    var condensedSynopsis: String? = nil

    private var expandedParagraphs: [String] {
        description
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// When collapsed, prefer the FM-condensed hook over raw truncation.
    private var collapsedText: String {
        condensedSynopsis ?? description
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.md) {
            Text("SYNOPSIS")
                .font(.kuroMicro(weight: .medium))
                .tracking(1.5)
                .foregroundColor(.kuroBlack80)

            if showFull && expandedParagraphs.count > 1 {
                VStack(alignment: .leading, spacing: KuroSpacing.md) {
                    ForEach(Array(expandedParagraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.kuroBody(weight: .regular))
                            .tracking(0.2)
                            .foregroundColor(.kuroBlack80)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text(showFull ? description : collapsedText)
                    .font(.kuroBody(weight: .regular))
                    .tracking(0.2)
                    .foregroundColor(.kuroBlack80)
                    .lineSpacing(5)
                    .lineLimit(showFull ? nil : (condensedSynopsis != nil ? nil : 4))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if description.count > 200 {
                Button(action: {
                    withAnimation(KuroAnimation.spring) {
                        showFull.toggle()
                    }
                    KuroAccessibility.impactHaptic(.light)
                }) {
                    Text(showFull ? "SHOW LESS" : "READ MORE")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.0)
                        .foregroundColor(.kuroBlack80)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Genres Section
struct GenresSection: View {
    let genres: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.md) {
            Text("GENRES")
                .font(.kuroMicro(weight: .medium))
                .tracking(1.5)
                .foregroundColor(.kuroBlack80)
            
            FlowLayout(spacing: KuroSpacing.sm) {
                ForEach(genres, id: \.self) { genre in
                    GenreTag(genre: genre)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Genre Tag
struct GenreTag: View {
    let genre: String
    
    var body: some View {
        Text(genre.uppercased())
            .font(.kuroMicro(weight: .light))
            .tracking(0.5)
            .foregroundColor(.kuroBlack60)
            .padding(.horizontal, KuroSpacing.md)
            .padding(.vertical, KuroSpacing.xs)
            .background(
                Capsule()
                    .stroke(Color.kuroBlack.opacity(0.15), lineWidth: 0.5)
            )
    }
}

// MARK: - Episodes Section
struct EpisodesSection: View {
    let anime: Anime
    let episodeCount: Int
    let countLabel: String
    var onError: ((KuroToastState) -> Void)? = nil
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.openURL) private var openURL
    @State private var episodes: [Episode] = []
    @State private var isLoading: Bool = false
    @State private var showAllEpisodes: Bool = false
    @State private var markingEpisode: Int? = nil

    private var entry: UserList? {
        supabaseService.userListEntry(mediaType: "anime", mediaId: anime.id)
    }

    private var userProgress: Int {
        supabaseService.getProgress(for: anime.id) ?? 0
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
        VStack(alignment: .leading, spacing: KuroSpacing.md) {
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
                            hasOpenLink: validatedEpisodeURL(from: ep.streamUrl) != nil,
                            isMarking: markingEpisode == ep.number,
                            onOpen: { openEpisode(ep) },
                            onMarkWatched: { markWatched(ep) }
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
            await loadPreview()
        }
        .sheet(isPresented: $showAllEpisodes) {
            EpisodeListSheet(anime: anime, episodeCount: episodeCount)
                .environment(supabaseService)
        }
    }

    private func loadPreview() async {
        isLoading = true
        defer { isLoading = false }
        episodes = await supabaseService.fetchEpisodesNext(animeId: anime.id, fromNumber: nextEpisodeNumber, limit: 10)
    }

    /// Validate and normalize a raw URL string (trim whitespace, ensure http/https scheme).
    private func validatedEpisodeURL(from raw: String?) -> URL? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var candidate = trimmed.replacingOccurrences(of: " ", with: "%20")
        let lower = candidate.lowercased()
        if !(lower.hasPrefix("http://") || lower.hasPrefix("https://")) {
            guard !candidate.contains("://") else { return nil }
            candidate = "https://\(candidate)"
        }
        guard let url = URL(string: candidate) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    private func openEpisode(_ ep: Episode) {
        KuroAccessibility.impactHaptic(.light)
        if let url = validatedEpisodeURL(from: ep.streamUrl) {
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

    private func markWatched(_ ep: Episode) {
        let target = min(ep.number, episodeCount)
        markingEpisode = ep.number
        Task {
            await supabaseService.setUserProgress(mediaId: anime.id, mediaType: "anime", progress: target)
            if let msg = supabaseService.errorMessage, !msg.isEmpty {
                KuroAccessibility.errorHaptic()
                onError?(KuroToastState(kind: .error, title: "Update failed", subtitle: "Could not mark episode \(ep.number).", actionTitle: nil, onAction: nil))
                #if DEBUG
                print("markWatched failed for episode \(ep.number): \(msg)")
                #endif
            }
            await MainActor.run { markingEpisode = nil }
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.kuroBlack)
            } else {
                Button(action: {
                    KuroAccessibility.impactHaptic(.light)
                    onMarkWatched()
                }) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16, weight: .regular))
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
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var episodes: [Episode] = []
    @State private var isLoading: Bool = false
    @State private var hasLoadedOnce: Bool = false
    @State private var hasMore: Bool = true
    @State private var offset: Int = 0
    @State private var markingEpisode: Int? = nil
    @State private var toast: KuroToastState? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil

    private let pageSize: Int = 50

    private var userProgress: Int { supabaseService.getProgress(for: anime.id) ?? 0 }

    var body: some View {
        NavigationStack {
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
                            hasOpenLink: validatedEpisodeURL(from: ep.streamUrl) != nil,
                            isMarking: markingEpisode == ep.number,
                            onOpen: { openEpisode(ep) },
                            onMarkWatched: { markWatched(ep) }
                        )
                        .onAppear {
                            if index == episodes.count - 1, hasMore, !isLoading {
                                Task { await loadMore() }
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
            .task {
                await loadMore(reset: true)
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

    private func loadMore(reset: Bool = false) async {
        if reset {
            episodes = []
            offset = 0
            hasMore = true
            hasLoadedOnce = false
        }
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let page = await supabaseService.fetchEpisodesPage(animeId: anime.id, offset: offset, limit: pageSize)
        episodes.append(contentsOf: page)
        hasMore = page.count == pageSize
        if hasMore { offset += pageSize }
        hasLoadedOnce = true
    }

    /// Validate and normalize a raw URL string (trim whitespace, ensure http/https scheme).
    private func validatedEpisodeURL(from raw: String?) -> URL? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var candidate = trimmed.replacingOccurrences(of: " ", with: "%20")
        let lower = candidate.lowercased()
        if !(lower.hasPrefix("http://") || lower.hasPrefix("https://")) {
            guard !candidate.contains("://") else { return nil }
            candidate = "https://\(candidate)"
        }
        guard let url = URL(string: candidate) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    private func openEpisode(_ ep: Episode) {
        KuroAccessibility.impactHaptic(.light)
        if let url = validatedEpisodeURL(from: ep.streamUrl) {
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

    private func markWatched(_ ep: Episode) {
        let target = min(ep.number, episodeCount)
        markingEpisode = ep.number
        Task {
            await supabaseService.setUserProgress(mediaId: anime.id, mediaType: "anime", progress: target)
            if let msg = supabaseService.errorMessage, !msg.isEmpty {
                KuroAccessibility.errorHaptic()
                showToast(KuroToastState(kind: .error, title: "Update failed", subtitle: "Could not mark episode \(ep.number).", actionTitle: nil, onAction: nil))
                #if DEBUG
                print("markWatched failed for episode \(ep.number): \(msg)")
                #endif
            }
            await MainActor.run { markingEpisode = nil }
        }
    }
}

// MARK: - Action Buttons
struct ActionButtons: View {
    let anime: Anime
    let onToast: (KuroToastState) -> Void
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.openURL) private var openURL
    @State private var showAddToList = false
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
        supabaseService.isInCollection(mediaId: anime.id, mediaType: "anime")
    }

    private var userEntry: UserList? {
        supabaseService.userListEntry(mediaType: "anime", mediaId: anime.id)
    }

    private var hasWatchLink: Bool {
        watchLink.flatMap { validatedURL(from: $0.url) } != nil
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(action: toggleSaved) {
                    Image(systemName: isSaved ? "heart.fill" : "heart")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.kuroBlack)
                        .frame(width: 38, height: 38)
                        .background(Color.kuroBlack08)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSaved ? "Saved" : "Save")

                Button {
                    KuroAccessibility.impactHaptic(.medium)
                    showAddToList = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
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
                            .font(.system(size: 11, weight: .semibold))
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
                        .font(.system(size: 13, weight: .semibold))
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
        .task(id: supabaseService.getProgress(for: anime.id) ?? -1) {
            await refreshLinks()
        }
        .sheet(isPresented: $showAddToList) {
            AddToListSheet(media: anime)
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
                if let url = validatedURL(from: link.url) {
                    KuroAccessibility.impactHaptic(.light)
                    supabaseService.recordOutboundLink(mediaType: "ANIME", mediaId: anime.id, linkKind: "provider_sheet", provider: link.title)
                    openURL(url)
                } else {
                    onToast(.init(kind: .error, title: "Couldn’t open link", subtitle: "Try a different provider.", actionTitle: nil, onAction: nil))
                }
            }
        }
    }

    private func toggleSaved() {
        let currentlySaved = isSaved
        Task {
            let success: Bool
            if currentlySaved {
                success = await supabaseService.removeFromList(mediaId: anime.id, mediaType: "anime")
            } else {
                success = await supabaseService.addToList(mediaId: anime.id, mediaType: "anime", status: .planning)
            }

            await MainActor.run {
                if success {
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
                            subtitle: supabaseService.errorMessage,
                            actionTitle: nil,
                            onAction: nil
                        )
                    )
                }
            }
        }
    }

    private func handleWatchAction() {
        guard let link = watchLink, let linkURL = validatedURL(from: link.url) else {
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
            supabaseService.recordOutboundLink(mediaType: "ANIME", mediaId: anime.id, linkKind: "watch", provider: link.title)
            openURL(linkURL)
        }
    }

    private func refreshLinks() async {
        let progress = supabaseService.getProgress(for: anime.id)
        let locale = Locale.current.identifier
        let preferredAudio = locale.lowercased().hasPrefix("de") ? "de" : "en"
        let nextEpisode = max(1, (progress ?? 0) + 1)
        let episodeLink = await supabaseService.getStreamLinkForEpisode(animeId: anime.id, episodeNumber: nextEpisode)
        let links = await supabaseService.fetchLegalWatchLinks(
            mediaId: anime.id,
            locale: locale
        )
        var availabilityStatus: MediaAvailabilityStatus? = nil
        var requestedRefresh = false
        if FeatureFlags.shared.isStreamingAvailabilityV1Enabled {
            availabilityStatus = await supabaseService.mediaAvailabilityStatus(
                mediaId: anime.id,
                mediaType: "ANIME"
            )
            await supabaseService.fetchProviderAvailabilityV2(
                items: [(mediaType: "ANIME", mediaId: anime.id)],
                preferredAudioLang: preferredAudio,
                preferredSubLang: nil,
                includeUnknown: true
            )
            requestedRefresh = await supabaseService.enqueueAvailabilityRefreshIfStale(
                mediaType: "ANIME",
                mediaId: anime.id,
                reason: "detail_open"
            )
            if requestedRefresh {
                availabilityStatus = await supabaseService.mediaAvailabilityStatus(
                    mediaId: anime.id,
                    mediaType: "ANIME"
                )
            }
        }
        let availability = FeatureFlags.shared.isStreamingAvailabilityV1Enabled
            ? supabaseService.providerAvailability(mediaId: anime.id, mediaType: "ANIME")
            : []
        let verifiedItems = makeVerifiedProviderItems(
            providers: availability.filter { !$0.isStale },
            fallbackLinks: links,
            ranking: supabaseService.animeProviderRanking,
            preferredAudioLang: preferredAudio,
            preferredSubtitleLang: preferredAudio,
            originalLanguage: anime.inferredOriginalLanguageCode
        ).filter { validatedURL(from: $0.url) != nil }
        let catalogItems = makeCatalogProviderItems(
            from: links,
            ranking: supabaseService.animeProviderRanking,
            fallbackSubtitle: "Catalog link only. Availability may vary by region."
        ).filter { validatedURL(from: $0.url) != nil }
        let note = FeatureFlags.shared.isStreamingAvailabilityV1Enabled
            ? supabaseService.bestProviderAvailabilityNote(
                mediaId: anime.id,
                mediaType: "ANIME",
                preferredAudioLang: preferredAudio,
                preferredSubtitleLang: preferredAudio,
                originalLanguage: anime.inferredOriginalLanguageCode
            )
            : nil
        let displayedItems = verifiedItems.isEmpty ? catalogItems : verifiedItems
        let primary = preferredPrimaryProviderItem(
            from: displayedItems,
            preferredSite: episodeLink?.site
        ) ?? displayedItems.first
        await MainActor.run {
            self.watchLink = primary
            self.allLinks = displayedItems
            if !verifiedItems.isEmpty {
                self.watchAvailabilityNote = note?.displayText ?? "Verified providers for this title."
            } else if FeatureFlags.shared.isStreamingAvailabilityV1Enabled {
                self.watchAvailabilityNote = "Catalog links only. Verified availability is still being refreshed."
            } else {
                self.watchAvailabilityNote = "Availability, audio, and subtitle options may vary by region."
            }
            self.watchAvailabilityStatusCaption = providerAvailabilityStatusCaption(
                status: availabilityStatus,
                requestedRefresh: requestedRefresh,
                hasVerifiedProviders: !verifiedItems.isEmpty
            )
        }
    }

    private func validatedURL(from raw: String?) -> URL? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var candidate = trimmed.replacingOccurrences(of: " ", with: "%20")
        let lower = candidate.lowercased()
        if !(lower.hasPrefix("http://") || lower.hasPrefix("https://")) {
            guard !candidate.contains("://") else { return nil }
            candidate = "https://\(candidate)"
        }
        if let url = URL(string: candidate) {
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
            return url
        }
        // Percent-encode non-ASCII characters (CJK, Korean, etc.)
        guard let encoded = candidate.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encoded),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }

}


struct MediaProviderActionCard: View {
    let sectionTitle: String
    let systemImage: String
    let providerTitle: String?
    let primaryTitle: String
    let secondaryTitle: String
    let note: String
    let statusCaption: String?
    let badgeText: String
    let isAvailable: Bool
    let action: () -> Void

    private var badgeForeground: Color {
        isAvailable && badgeText == "Verified" ? .kuroBlack : .kuroBlack60
    }

    private var badgeBackground: Color {
        isAvailable && badgeText == "Verified" ? .kuroBlack08 : .kuroBlack05
    }

    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            action()
        }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Text(sectionTitle.uppercased())
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.0)
                        .foregroundColor(.kuroBlack80)
                    Spacer(minLength: KuroSpacing.sm)
                    Text(badgeText.uppercased())
                        .font(.kuroMicro(weight: .medium))
                        .tracking(0.8)
                        .foregroundColor(badgeForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(badgeBackground))
                }

                HStack(spacing: KuroSpacing.md) {
                    ProviderBrandMark(
                        providerTitle: providerTitle,
                        fallbackSystemImage: systemImage,
                        size: 42,
                        isAvailable: isAvailable
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(primaryTitle)
                            .font(.kuroBody(weight: .regular))
                            .foregroundColor(.kuroBlack)
                            .multilineTextAlignment(.leading)
                        Text(secondaryTitle)
                            .font(.kuroMicro(weight: .medium))
                            .foregroundColor(.kuroBlack60)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: KuroSpacing.md)

                    Image(systemName: isAvailable ? "chevron.right" : "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.kuroBlack30)
                }

                Text(note)
                    .font(.kuroMicro(weight: .light))
                    .foregroundColor(.kuroTextTertiary)
                    .multilineTextAlignment(.leading)

                if let statusCaption, !statusCaption.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.kuroBlack30)
                        Text(statusCaption)
                            .font(.kuroMicro(weight: .medium))
                            .foregroundColor(.kuroBlack60)
                    }
                }
            }
            .padding(KuroSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                    .fill(isAvailable ? Color.kuroBackground : Color.kuroBlack04)
                    .overlay(
                        RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                            .strokeBorder(Color.kuroBlack08, lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ProviderBrandPalette {
    let label: String
    let background: Color
    let foreground: Color
}

private struct ProviderBrandMark: View {
    let providerTitle: String?
    let fallbackSystemImage: String
    let size: CGFloat
    let isAvailable: Bool

    private var palette: ProviderBrandPalette? {
        providerTitle.map(providerBrandPalette(for:))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette?.background ?? (isAvailable ? Color.kuroBlack08 : Color.kuroBlack05))
                .frame(minWidth: palette == nil ? size : 64, minHeight: size)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke((palette?.foreground ?? .kuroBlack30).opacity(0.14), lineWidth: 0.8)
                )

            if let palette {
                Text(palette.label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(0.2)
                    .foregroundColor(palette.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
            } else {
                Image(systemName: fallbackSystemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isAvailable ? .kuroBlack : .kuroBlack30)
            }
        }
    }
}

private func providerBrandPalette(for title: String) -> ProviderBrandPalette {
    let normalized = normalizedProviderKey(title)
    switch normalized {
    case "crunchyroll":
        return .init(label: "Crunchyroll", background: Color.orange.opacity(0.18), foreground: Color.orange)
    case "netflix":
        return .init(label: "Netflix", background: Color.red.opacity(0.16), foreground: Color.red)
    case "amazon prime video", "prime video":
        return .init(label: "Prime", background: Color.blue.opacity(0.16), foreground: Color.blue)
    case "hulu":
        return .init(label: "Hulu", background: Color.green.opacity(0.16), foreground: Color.green)
    case "youtube":
        return .init(label: "YouTube", background: Color.red.opacity(0.14), foreground: Color.red)
    case "disney plus", "disneyplus":
        return .init(label: "Disney+", background: Color.cyan.opacity(0.16), foreground: Color.blue)
    default:
        let letters = title
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .prefix(2)
            .compactMap { $0.first.map { String($0).uppercased() } }
            .joined()
        return .init(
            label: letters.isEmpty ? "PL" : letters,
            background: Color.kuroBlack08,
            foreground: .kuroBlack80
        )
    }
}

// MARK: - Secondary Action Button
struct DetailSectionUtilityButton: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: KuroSpacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.0)
                    .foregroundColor(.kuroBlack80)
                Text(subtitle)
                    .font(.kuroMicro(weight: .light))
                    .foregroundColor(.kuroBlack60)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.kuroMicro())
                .foregroundColor(.kuroBlack30)
        }
        .padding(KuroSpacing.md)
        .background(Color.kuroBlack08)
        .cornerRadius(KuroRadius.sm)
    }
}

struct SecondaryActionButton: View {
    let icon: String
    let label: String
    var action: () -> Void = { }
    
    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            action()
        }) {
            HStack {
                Image(systemName: icon)
                    .font(.kuroMicro())
                
                Text(label)
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.0)
            }
            .foregroundColor(.kuroBlack80)
            .frame(maxWidth: .infinity)
            .padding(.vertical, KuroSpacing.md)
            .background(Color.kuroBlack08)
            .cornerRadius(KuroRadius.sm)
        }
    }
}

struct SecondaryShareButton: View {
    let url: URL
    let title: String

    var body: some View {
        ShareLink(item: url, subject: Text(title)) {
            HStack {
                Image(systemName: "square.and.arrow.up")
                    .font(.kuroMicro())

                Text("SHARE")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.0)
            }
            .foregroundColor(.kuroBlack80)
            .frame(maxWidth: .infinity)
            .padding(.vertical, KuroSpacing.md)
            .background(Color.kuroBlack08)
            .cornerRadius(KuroRadius.sm)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { KuroAccessibility.impactHaptic(.light) })
    }
}

struct ProviderSheetItem: Identifiable, Equatable {
    let id: String
    let title: String
    let url: String
    let subtitle: String?
    let isVerified: Bool

    var badgeText: String { isVerified ? "Verified" : "Catalog" }
    var accessibilityLabel: String {
        isVerified ? "Open verified provider \(title)" : "Open catalog link \(title)"
    }
}

func makeVerifiedProviderItems(
    providers: [ProviderAvailabilityProvider],
    fallbackLinks: [ExternalLink],
    ranking: [String],
    preferredAudioLang: String?,
    preferredSubtitleLang: String?,
    originalLanguage: String?
) -> [ProviderSheetItem] {
    var seen = Set<String>()
    return providers
        .sorted { lhs, rhs in
            let left = providerRankingIndex(for: lhs.displayName, slug: lhs.slug, ranking: ranking)
            let right = providerRankingIndex(for: rhs.displayName, slug: rhs.slug, ranking: ranking)
            if left != right { return left < right }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        .compactMap { provider in
            let resolvedURL = provider.url ?? fallbackLinks.first(where: { providerMatches(site: $0.site, provider: provider) })?.url
            guard let resolvedURL, !resolvedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let key = "verified-\(provider.slug)"
            guard seen.insert(key).inserted else { return nil }
            let note = ProviderAvailabilityNoteBuilder.bestNote(
                from: [provider],
                preferredAudioLang: preferredAudioLang,
                preferredSubtitleLang: preferredSubtitleLang,
                originalLanguage: originalLanguage
            )?.displayText
            return ProviderSheetItem(
                id: key,
                title: provider.displayName,
                url: resolvedURL,
                subtitle: note.map { "Verified for this title. \($0)" } ?? "Verified for this title.",
                isVerified: true
            )
        }
}

func makeCatalogProviderItems(
    from links: [ExternalLink],
    ranking: [String],
    fallbackSubtitle: String
) -> [ProviderSheetItem] {
    links
        .sorted { lhs, rhs in
            let left = providerRankingIndex(for: lhs.site, slug: nil, ranking: ranking)
            let right = providerRankingIndex(for: rhs.site, slug: nil, ranking: ranking)
            if left != right { return left < right }
            return (lhs.site ?? "").localizedCaseInsensitiveCompare(rhs.site ?? "") == .orderedAscending
        }
        .map { link in
            ProviderSheetItem(
                id: "catalog-\(link.id)",
                title: link.site ?? "Provider",
                url: link.url,
                subtitle: fallbackSubtitle,
                isVerified: false
            )
        }
}

func preferredPrimaryProviderItem(
    from items: [ProviderSheetItem],
    preferredSite: String?
) -> ProviderSheetItem? {
    guard let preferredSite else { return nil }
    let normalizedSite = normalizedProviderKey(preferredSite)
    return items.first { normalizedProviderKey($0.title) == normalizedSite }
}

func providerMatches(site: String?, provider: ProviderAvailabilityProvider) -> Bool {
    let siteKey = normalizedProviderKey(site)
    guard !siteKey.isEmpty else { return false }
    let displayKey = normalizedProviderKey(provider.displayName)
    let slugKey = normalizedProviderKey(provider.slug)
    return siteKey == displayKey || siteKey == slugKey || siteKey.contains(displayKey) || displayKey.contains(siteKey) || siteKey.contains(slugKey) || slugKey.contains(siteKey)
}

func providerRankingIndex(for site: String?, slug: String?, ranking: [String]) -> Int {
    let siteKey = normalizedProviderKey(site)
    let slugKey = normalizedProviderKey(slug)
    return ranking.firstIndex(where: { key in
        let normalized = normalizedProviderKey(key)
        return (!siteKey.isEmpty && (siteKey == normalized || siteKey.contains(normalized) || normalized.contains(siteKey)))
            || (!slugKey.isEmpty && (slugKey == normalized || slugKey.contains(normalized) || normalized.contains(slugKey)))
    }) ?? 999
}

func normalizedProviderKey(_ raw: String?) -> String {
    guard let raw else { return "" }
    let lowered = raw.lowercased()
        .replacingOccurrences(of: "&", with: "and")
        .replacingOccurrences(of: "+", with: "plus")
    let allowed = lowered.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }.joined()
    return allowed
        .split(separator: " ")
        .joined(separator: " ")
}

func providerAvailabilityStatusCaption(
    status: MediaAvailabilityStatus?,
    requestedRefresh: Bool,
    hasVerifiedProviders: Bool
) -> String? {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short

    if hasVerifiedProviders, let lastRefreshedAt = status?.lastRefreshedAt {
        return "Verified \(formatter.localizedString(for: lastRefreshedAt, relativeTo: Date()))."
    }
    if requestedRefresh || status?.status.lowercased() == "pending" {
        return "Refreshing verified availability now."
    }
    if let lastRefreshedAt = status?.lastRefreshedAt {
        return "Last checked \(formatter.localizedString(for: lastRefreshedAt, relativeTo: Date()))."
    }
    if let nextRefreshAt = status?.nextRefreshAt {
        return "Next verification \(formatter.localizedString(for: nextRefreshAt, relativeTo: Date()))."
    }
    return nil
}

struct ProviderSelectionSheet: View {
    let title: String
    let links: [ProviderSheetItem]
    let statusCaption: String?
    let onSelect: (ProviderSheetItem) -> Void
    @Environment(\.dismiss) private var dismiss

    private var isVerifiedOnly: Bool {
        !links.isEmpty && links.allSatisfy(\.isVerified)
    }

    private var explainerTitle: String {
        if links.isEmpty { return "No legal links yet" }
        return isVerifiedOnly ? "Verified for this title" : "Catalog fallback"
    }

    private var explainerBody: String {
        if links.isEmpty { return "We do not have a legal provider link for this title yet." }
        return isVerifiedOnly
            ? "These providers are matched to this title directly. Language and subtitle options can still vary by region."
            : "These are legal catalog links from the provider directory. Title-specific availability may still vary by region."
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: KuroSpacing.lg) {
                    ProviderSelectionExplainerCard(
                        title: explainerTitle,
                        message: explainerBody,
                        linkCount: links.count,
                        isVerifiedOnly: isVerifiedOnly,
                        statusCaption: statusCaption
                    )

                    VStack(spacing: KuroSpacing.sm) {
                        ForEach(links) { link in
                            Button(action: {
                                onSelect(link)
                                dismiss()
                            }) {
                                ProviderSelectionLinkCard(link: link)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, ResponsiveLayout.padding())
                .padding(.top, KuroSpacing.md)
                .padding(.bottom, KuroSpacing.xl)
            }
            .background(Color.kuroBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .font(.kuroMicro(weight: .medium))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ProviderSelectionExplainerCard: View {
    let title: String
    let message: String
    let linkCount: Int
    let isVerifiedOnly: Bool
    let statusCaption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: isVerifiedOnly ? "checkmark.seal.fill" : "rectangle.stack.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isVerifiedOnly ? .kuroBlack : .kuroBlack60)
                Text(title.uppercased())
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.0)
                    .foregroundColor(.kuroBlack80)
                Spacer(minLength: KuroSpacing.md)
                if linkCount > 0 {
                    Text("\(linkCount) \(linkCount == 1 ? "LINK" : "LINKS")")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(0.8)
                        .foregroundColor(.kuroBlack60)
                }
            }

            Text(message)
                .font(.kuroMicro(weight: .light))
                .foregroundColor(.kuroBlack60)
                .fixedSize(horizontal: false, vertical: true)

            if let statusCaption, !statusCaption.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.kuroBlack30)
                    Text(statusCaption)
                        .font(.kuroMicro(weight: .medium))
                        .foregroundColor(.kuroBlack60)
                }
            }
        }
        .padding(KuroSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                .fill(Color.kuroBlack05)
                .overlay(
                    RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                        .stroke(Color.kuroBlack08, lineWidth: 0.8)
                )
        )
    }
}

private struct ProviderSelectionLinkCard: View {
    let link: ProviderSheetItem

    var body: some View {
        HStack(alignment: .top, spacing: KuroSpacing.md) {
            ProviderBrandMark(
                providerTitle: link.title,
                fallbackSystemImage: link.isVerified ? "play.fill" : "link",
                size: 42,
                isAvailable: true
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(link.title)
                        .font(.kuroBody(weight: .regular))
                        .foregroundColor(.kuroBlack)
                    Spacer(minLength: KuroSpacing.sm)
                    Text(link.badgeText.uppercased())
                        .font(.kuroMicro(weight: .medium))
                        .tracking(0.8)
                        .foregroundColor(link.isVerified ? .kuroBlack : .kuroBlack60)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(link.isVerified ? Color.kuroBlack08 : Color.kuroBlack05)
                        )
                }

                if let subtitle = link.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.kuroMicro(weight: .light))
                        .foregroundColor(.kuroBlack60)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer(minLength: KuroSpacing.md)

            VStack(spacing: 6) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.kuroBlack30)
                Text("OPEN")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(0.8)
                    .foregroundColor(.kuroBlack60)
            }
            .padding(.top, 2)
        }
        .padding(KuroSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                .fill(link.isVerified ? Color.kuroBackground : Color.kuroBlack04)
                .overlay(
                    RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                        .stroke(Color.kuroBlack08, lineWidth: 1)
                )
        )
    }
}

// MARK: - Back Button
struct BackButton: View {
    let dismiss: DismissAction
    
    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            dismiss()
        }) {
            Circle()
                .fill(Color.kuroWhite.opacity(0.9))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.kuroBlack)
                )
                .shadow(color: .kuroBlack08, radius: 8, x: 0, y: 4)
        }
    }
}

// MARK: - Flow Layout Helper
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > width {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                x += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
            
            self.size = CGSize(width: width, height: y + lineHeight)
        }
    }
}

// MARK: - Detail Page Skeleton Placeholders

private struct DetailCreditsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.md) {
            // "CAST" caption placeholder
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.black.opacity(0.06))
                .frame(width: 40, height: 10)
                .kuroShimmer()

            // Circle avatars row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(0..<5, id: \.self) { _ in
                        Circle()
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 64, height: 64)
                            .kuroShimmer()
                    }
                }
            }

            // "PRODUCTION" caption placeholder
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.black.opacity(0.06))
                .frame(width: 80, height: 10)
                .kuroShimmer()

            // Text line placeholders
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.black.opacity(0.05))
                .frame(width: 180, height: 12)
                .kuroShimmer()

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.black.opacity(0.05))
                .frame(width: 140, height: 12)
                .kuroShimmer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DetailLadderSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.sm) {
            // Caption placeholder
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.black.opacity(0.06))
                .frame(width: 100, height: 10)
                .kuroShimmer()

            // Body text placeholder
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.black.opacity(0.04))
                .frame(width: 220, height: 14)
                .kuroShimmer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
