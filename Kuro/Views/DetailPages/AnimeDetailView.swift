import SwiftUI

// MARK: - ANIME DETAIL VIEW - iOS 26 Mobile-First
// Comprehensive anime detail page with elegant minimalism

struct AnimeDetailView: View {
    let anime: Anime
    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseService.self) private var supabaseService
    @State private var scrollOffset: CGFloat = 0
    @State private var showFullDescription = false
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: KuroDesignSpacing.adaptive(KuroSpacing.lg, for: geometry.size.width)) {
                    // Hero Section with Parallax Effect
                    HeroSection(anime: anime, geometry: geometry, scrollOffset: $scrollOffset)
                    
                    // Content Section
                    VStack(spacing: KuroDesignSpacing.adaptive(KuroSpacing.lg, for: geometry.size.width)) {
                        // Title & Quick Info
                        TitleSection(anime: anime)
                        
                        // Stats Grid
                        StatsGrid(anime: anime)
                        
                        // Description
                        DescriptionSection(
                            description: anime.displayDescription,
                            showFull: $showFullDescription
                        )
                        
                        // Genres
                        if let genres = anime.genreList, !genres.isEmpty {
                            GenresSection(genres: genres)
                        }
                        
                        // Episodes Section (if available)
                        if let episodeCount = anime.episodeCount {
                            EpisodesSection(anime: anime, episodeCount: episodeCount)
                        }
                        
                        // Action Buttons
                        ActionButtons(anime: anime)
                    }
                    .padding(.horizontal, ResponsiveLayout.padding())
                    .padding(.top, KuroDesignSpacing.adaptive(KuroSpacing.lg, for: geometry.size.width))
                    .padding(.bottom, KuroDesignSpacing.adaptive(KuroSpacing.xl, for: geometry.size.width))
                }
            }
            .transaction { $0.animation = nil }
            .background(Color.kuroBackground)
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .topLeading) {
                // Custom Back Button
                BackButton(dismiss: dismiss)
                    .padding(.top, KuroScreen.safeAreaTop + KuroSpacing.sm)
                    .padding(.leading, ResponsiveLayout.padding())
            }
        }
        #if os(iOS)
        .navigationBarHidden(true)
        #else
        .toolbar(.hidden, for: .windowToolbar)
        #endif
    }
}

// MARK: - Hero Section with Parallax
struct HeroSection: View {
    let anime: Anime
    let geometry: GeometryProxy
    @Binding var scrollOffset: CGFloat
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Banner/Cover Image with Parallax
            KuroCachedAsyncImage(url: URL(string: anime.bannerImage ?? anime.displayImage)) { image in
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
            .frame(width: geometry.size.width, height: ResponsiveLayout.imageHeight(320))
            .clipped()
            .offset(y: scrollOffset * 0.5) // Parallax effect
            
            // Gradient Overlay
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.kuroBackground.opacity(0.8),
                    Color.kuroBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)
            
            // Media Type Badge
            HStack {
                Spacer()
                KuroStyle.mediaBadge("ANIME", isAnime: true)
            }
            .padding(.horizontal, ResponsiveLayout.padding())
            .padding(.bottom, KuroSpacing.lg)
        }
        .frame(height: ResponsiveLayout.imageHeight(320))
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.md) {
            Text("SYNOPSIS")
                .font(.kuroMicro(weight: .medium))
                .tracking(1.5)
                .foregroundColor(.kuroBlack80)
            
            Text(description)
                .font(.kuroBody(weight: .light))
                .tracking(0.5)
                .foregroundColor(.kuroBlack60)
                .lineSpacing(6)
                .lineLimit(showFull ? nil : 4)
            
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
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.openURL) private var openURL
    @State private var episodes: [Episode] = []
    @State private var isLoading: Bool = false
    @State private var showAllEpisodes: Bool = false
    @State private var markingEpisode: Int? = nil

    private var userProgress: Int {
        supabaseService.getProgress(for: anime.id) ?? 0
    }

    private var nextEpisodeNumber: Int {
        max(1, userProgress + 1)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.md) {
            HStack {
                Text("EPISODES")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(.kuroBlack80)
                
                Spacer()
                
                Text("\(episodeCount) TOTAL")
                    .font(.kuroMicro(weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.kuroBlack60)
            }
            
            VStack(spacing: KuroSpacing.sm) {
                if isLoading && episodes.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in
                        EpisodeSkeletonRow()
                    }
                } else if episodes.isEmpty {
                    HStack {
                        Text("No episode data yet")
                            .font(.kuroMicro(weight: .light))
                            .foregroundColor(.kuroBlack60)
                        Spacer()
                    }
                    .padding(KuroSpacing.md)
                    .background(Color.kuroBlack08)
                    .cornerRadius(KuroRadius.sm)
                } else {
                    ForEach(episodes.prefix(5)) { ep in
                        EpisodeItemRow(
                            episode: ep,
                            isWatched: ep.number <= userProgress,
                            isMarking: markingEpisode == ep.number,
                            onOpen: { openEpisode(ep) },
                            onMarkWatched: { markWatched(ep) }
                        )
                    }
                }

                if episodeCount > 5 {
                    Button(action: {
                        KuroAccessibility.impactHaptic(.light)
                        showAllEpisodes = true
                    }) {
                        HStack {
                            Text("VIEW ALL \(episodeCount) EPISODES")
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.0)
                                .foregroundColor(.kuroBlack80)

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

    private func openEpisode(_ ep: Episode) {
        KuroAccessibility.impactHaptic(.light)
        if let urlString = ep.streamUrl, let url = URL(string: urlString) {
            openURL(url)
        } else if let urlString = anime.siteUrl, let url = URL(string: urlString) {
            openURL(url)
        }
    }

    private func markWatched(_ ep: Episode) {
        let target = min(ep.number, episodeCount)
        markingEpisode = ep.number
        Task {
            await supabaseService.setUserProgress(mediaId: anime.id, mediaType: "anime", progress: target)
            await MainActor.run { markingEpisode = nil }
        }
    }
}

struct EpisodeItemRow: View {
    let episode: Episode
    let isWatched: Bool
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
        .onTapGesture(perform: onOpen)
        // Make the whole row operable in VoiceOver (plus-button stays visual; action is exposed below).
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabelText())
        .accessibilityValue(accessibilityValueText())
        .accessibilityHint("Opens episode")
        .accessibilityAction { onOpen() }
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
        .presentationDetents([.medium, .large])
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

    private func openEpisode(_ ep: Episode) {
        KuroAccessibility.impactHaptic(.light)
        if let urlString = ep.streamUrl, let url = URL(string: urlString) {
            openURL(url)
        } else if let urlString = anime.siteUrl, let url = URL(string: urlString) {
            openURL(url)
        }
    }

    private func markWatched(_ ep: Episode) {
        let target = min(ep.number, episodeCount)
        markingEpisode = ep.number
        Task {
            await supabaseService.setUserProgress(mediaId: anime.id, mediaType: "anime", progress: target)
            await MainActor.run { markingEpisode = nil }
        }
    }
}

// MARK: - Action Buttons
struct ActionButtons: View {
    let anime: Anime
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.openURL) private var openURL
    @State private var showAddToList = false
    @State private var showProviders = false
    @State private var watchLink: (url: String, site: String, label: String)? = nil
    @State private var allLinks: [ExternalLink] = []

    private var isSaved: Bool {
        supabaseService.isInCollection(mediaId: anime.id, mediaType: "anime")
    }

    var body: some View {
        VStack(spacing: KuroSpacing.md) {
            if let link = watchLink, !link.url.isEmpty {
                Button(action: {
                    if allLinks.count > 1 {
                        showProviders = true
                    } else if let url = URL(string: link.url) {
                        KuroAccessibility.impactHaptic(.medium)
                        openURL(url)
                    }
                }) {
                    HStack {
                        Text(link.label)
                            .font(.kuroMicro(weight: .medium))
                            .tracking(1.0)
                        Spacer()
                        Image(systemName: allLinks.count > 1 ? "list.bullet" : "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.kuroWhite)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, KuroSpacing.md)
                    .padding(.horizontal, KuroSpacing.md)
                    .background(Color.kuroBlack)
                    .cornerRadius(KuroRadius.sm)
                }
            }

            // Add to List Button
            Button(action: {
                KuroAccessibility.impactHaptic(.medium)
                showAddToList = true
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.kuroBody())
                    
                    Text("ADD TO LIST")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.5)
                }
                .foregroundColor(.kuroWhite)
                .frame(maxWidth: .infinity)
                .padding(.vertical, KuroSpacing.md)
                .background(Color.kuroBlack)
                .cornerRadius(KuroRadius.sm)
            }
            .sheet(isPresented: $showAddToList) {
                AddToListSheet(media: anime)
            }
            
            // Secondary Actions
            HStack(spacing: KuroSpacing.md) {
                SecondaryActionButton(
                    icon: isSaved ? "heart.fill" : "heart",
                    label: isSaved ? "SAVED" : "SAVE"
                ) {
                    toggleSaved()
                }

                if let urlString = anime.siteUrl, let url = URL(string: urlString) {
                    SecondaryShareButton(url: url, title: anime.displayTitle)
                } else {
                    SecondaryActionButton(icon: "square.and.arrow.up", label: "SHARE") { }
                }
            }
        }
        .task(id: supabaseService.getProgress(for: anime.id) ?? -1) {
            await refreshLinks()
        }
        .sheet(isPresented: $showProviders) {
            ProviderSelectionSheet(title: "Watch On", links: allLinks) { link in
                if let url = URL(string: link.url) {
                    KuroAccessibility.impactHaptic(.light)
                    openURL(url)
                }
            }
        }
    }

    private func refreshLinks() async {
        let progress = supabaseService.getProgress(for: anime.id)
        let best = await supabaseService.getBestWatchLink(anime: anime, userProgress: progress)
        let links = await supabaseService.fetchExternalLinks(mediaType: "ANIME", mediaId: anime.id)
        await MainActor.run {
            self.watchLink = best
            self.allLinks = links
        }
    }

    private func toggleSaved() {
        let currentlySaved = isSaved
        Task {
            if currentlySaved {
                await supabaseService.removeFromList(mediaId: anime.id, mediaType: "anime")
            } else {
                await supabaseService.addToList(mediaId: anime.id, mediaType: "anime", status: .planning)
            }
            if let msg = supabaseService.errorMessage, !msg.isEmpty {
                KuroAccessibility.errorHaptic()
            } else {
                KuroAccessibility.successHaptic()
            }
        }
    }
}

// MARK: - Secondary Action Button
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

struct ProviderSelectionSheet: View {
    let title: String
    let links: [ExternalLink]
    let onSelect: (ExternalLink) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(links) { link in
                Button(action: {
                    onSelect(link)
                    dismiss()
                }) {
                    HStack {
                        Text(link.site ?? "Provider")
                            .font(.kuroBody(weight: .regular))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.kuroBlack30)
                    }
                    .padding(.vertical, KuroSpacing.sm)
                }
            }
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
