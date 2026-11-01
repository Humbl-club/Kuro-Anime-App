import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - MANGA DETAIL VIEW - iOS 26 Mobile-First
// Comprehensive manga detail page with elegant minimalism
//
// Loading (the page's one documented load coordinator; docs/modules/detail-pages.md). Initial/keyed
// loads use SwiftUI tasks; unit-sheet sentinel paging owns a task cancelled on dismissal. Each run
// rejects cancelled/superseded results before publishing or changing loading state.
// Row limits: similar 14, sub-genre tags 12 (one row read, trimmed client-side), chapter preview 10,
// chapter sheet 50 per page, chapter status one row. NOT row-limited: the credits queries (every
// author / cast row of the title), the ladder RPC and the title's external links.
//
// | Loader                                        | Key                        | Work                                                                                                   | Lifetime   |
// | --------------------------------------------- | -------------------------- | ------------------------------------------------------------------------------------------------------ | ---------- |
// | Screen (`MangaDetailView`)                    | manga id                   | top tags, similar, ladder -> `enqueueMediaRelationRefreshIfNeeded` (server write, cooldown) -> FM synopsis | page       |
// | Credits (`MangaDetailView`)                   | manga id + credits_cast_v1 | authors, cast                                                                                          | page       |
// | Units preview (`ChaptersSection`)             | next chapter number        | next 10 chapters, chapter status, best legal read link (`getBestLegalReadLink`)                        | section    |
// | Units sheet (`ChapterListSheet`)              | sheet appear + load-more   | chapters, pages of 50, best legal read link                                                            | sheet      |
// | Read links (`MangaActionButtons`)             | manga id                   | `ProviderAvailabilityStore.resolveReadLinks`: legal external links, and behind streaming_availability_v1 status / provider v2 / `enqueueAvailabilityRefreshIfStale` (server write); a cancelled (superseded) run publishes nothing | action bar |
// | `ClubActivitySection`, `FriendsActivitySection` | own `.task`              | club activity, friend comments                                                                         | section    |
//
// Chapter rows open the catalog best link (`getBestLegalReadLink`) while the action bar uses the
// verified-or-catalog snapshot: preserved as found (a product question, not changed here).
// Shared chrome: DetailSharedComponents.swift; provider sheet: ProviderLinkViews.swift; link builders:
// Kuro/Providers/ProviderLinkBuilders.swift.

struct MangaDetailView: View {
    let manga: Manga
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
    @State private var similar: [Manga] = []
    @State private var condensedSynopsis: String?
    @State private var authorItems: [(author: Author, role: String)] = []
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
            SeriesMangaDetailView(manga: manga, legacy: { AnyView(legacyMangaDetail) })
        } else {
            legacyMangaDetail
        }
    }

    private var legacyMangaDetail: some View {
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
                    MangaHeroSection(manga: manga, geometry: geometry, scrollOffset: $scrollOffset)
                        .offset(y: -safeTop)
                        .padding(.bottom, -safeTop)
                    
                    // Content Section
                    VStack(spacing: KuroDesignSpacing.adaptive(KuroSpacing.xl, for: geometry.size.width)) {
                        // Title & Quick Info
                        MangaTitleSection(manga: manga)
                        
                        MangaMetaLineSection(manga: manga)

                        // Next chapter / volume with its certainty; hidden until a source dates one.
                        DetailNextReleaseSection(items: releaseItems ?? [])

                        // Description
                        if manga.hasMeaningfulSynopsis {
                            DescriptionSection(
                                description: manga.displayDescription,
                                showFull: $showFullDescription,
                                condensedSynopsis: condensedSynopsis
                            )
                        }
                        
                        // Genres
                        if let genres = manga.genreList, !genres.isEmpty {
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

                                if !authorItems.isEmpty {
                                    MangaProductionSection(authorItems: authorItems)
                                }
                            } else {
                                DetailCreditsSkeleton()
                            }
                        }

                        if didLoadLadder {
                            AdaptationPathSection(ladder: mediaLadder, mediaType: .manga)
                        } else {
                            DetailLadderSkeleton()
                        }

                        // Chapters Section (rows-first; count is optional)
                        ChaptersSection(manga: manga, chapterCount: manga.chapterCount, onError: showToast)
                        
                        // Volumes Section (if available)
                        if let volumeCount = manga.volumeCount {
                            VolumesSection(manga: manga, volumeCount: volumeCount)
                        }

                        // "NEXT" pick when user has completed this series
                        if !similar.isEmpty {
                            MangaNextPickSection(
                                mediaId: manga.id,
                                similar: similar
                            )
                        }

                        if !similar.isEmpty {
                            MangaSimilarSection(title: "MORE LIKE THIS", items: similar, containerWidth: geometry.size.width)
                        }

                        ClubActivitySection(mediaId: manga.id, mediaType: "MANGA")

                        if flags.isSocialActivityV1Enabled {
                            FriendsActivitySection(mediaId: manga.id, mediaType: "MANGA")
                        }

                        // The page's deep link; it always parses for an integer id (no force unwrap).
                        if let shareURL = URL(string: "kuro://manga/\(manga.id)") {
                            ShareLink(
                                item: shareURL,
                                subject: Text(manga.displayTitle)
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

                        ExternalLinksSection(
                            anilistId: manga.id,
                            malId: manga.idMal,
                            mediaType: "manga"
                        )
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
                MangaActionButtons(manga: manga, onToast: showToast)
                    .padding(.horizontal, ResponsiveLayout.padding())
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                    .background(
                        Rectangle()
                            .fill(Color.kuroBackground.opacity(0.86))
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
        // Same full-bleed fix as AnimeDetailView (prevents the sheet's top safe-area cap from
        // showing through above the hero image).
        .background(Color.kuroBackground.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        #else
        .toolbar(.hidden, for: .windowToolbar)
        #endif
        .task(id: manga.id) {
            guard !Task.isCancelled else { return }
            let generation = UUID()
            screenLoadGeneration = generation
            async let tags = catalog.fetchTopTagsForManga(mangaId: manga.id, limit: 12)
            async let sim = recommendations.fetchSimilarManga(seed: manga, limit: 14)
            async let ladder = catalog.fetchMediaLadder(mediaType: "MANGA", mediaId: manga.id)
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
                mediaType: "MANGA",
                mediaId: manga.id,
                ladder: mediaLadder,
                reason: "detail_open"
            )

            guard !Task.isCancelled, screenLoadGeneration == generation else { return }

            // Condense long synopses on-device via Apple FM (no-op on unsupported devices)
            let sourceSynopsis = manga.displayDescription
            let hasReadyEnhanced = (manga.synopsisEnhancedState ?? "").lowercased() == "ready"
            if !hasReadyEnhanced, sourceSynopsis.count > 200 {
                let synopsis = await deviceIntelligence.condenseSynopsis(
                    mediaKind: "MANGA",
                    mediaId: manga.id,
                    description: sourceSynopsis,
                    title: manga.displayTitle,
                    genres: manga.genreList ?? []
                )
                guard !Task.isCancelled, screenLoadGeneration == generation else { return }
                condensedSynopsis = synopsis
            }
        }
        .task(id: "\(manga.id)-\(flags.isCreditsCastV1Enabled)") {
            guard !Task.isCancelled else { return }
            let generation = UUID()
            creditsLoadGeneration = generation
            guard flags.isCreditsCastV1Enabled else { return }
            async let authorFetch = catalog.fetchAuthorsForManga(mangaId: manga.id)
            async let castFetch = catalog.fetchCharactersForManga(mangaId: manga.id)
            let loadedAuthorItems = await authorFetch
            guard !Task.isCancelled, creditsLoadGeneration == generation, flags.isCreditsCastV1Enabled else { return }
            authorItems = loadedAuthorItems
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
        .detailReleases(kind: .manga, id: manga.id, schedule: $releaseItems, songs: $releaseSongs)
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

// MARK: - Swiss-minimal metadata line (replaces grids)
struct MangaMetaLineSection: View {
    let manga: Manga

    private var scoreText: String? {
        guard let score = manga.averageScore, score > 0 else { return nil }
        return String(format: "%.1f", Double(score) / 10.0)
    }

    private var chaptersText: String? {
        manga.chapterCount.map { "\($0) CH" }
    }

    private var volumesText: String? {
        manga.volumeCount.map { "\($0) VOL" }
    }

    private var statusText: String? {
        manga.status?.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    var body: some View {
        let parts: [String] = [
            scoreText.map { "SCORE \($0)" },
            manga.year.isEmpty ? nil : manga.year,
            manga.format?.uppercased(),
            chaptersText,
            volumesText,
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

struct MangaSimilarSection: View {
    let title: String
    let items: [Manga]
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

// MARK: - "NEXT" suggestion when user completed this manga (heuristic pick)
struct MangaNextPickSection: View {
    let mediaId: Int
    let similar: [Manga]
    @Environment(LibraryStore.self) private var library
    @State private var showDetail = false

    private var userEntry: LibraryEntry? {
        library.entry(for: MediaKey(kind: .manga, id: mediaId))
    }

    private var isCompleted: Bool {
        userEntry?.status == .completed
    }

    private var pick: Manga? {
        guard isCompleted else { return nil }
        if let planned = similar.first(where: { library.entry(for: $0.libraryKey)?.status == .planning }) {
            return planned
        }

        return similar
            .filter { !library.isTracked($0.libraryKey) }
            .max(by: { ($0.averageScore ?? 0) < ($1.averageScore ?? 0) })
    }

    var body: some View {
        if let manga = pick {
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
                        KuroCachedAsyncImage(url: URL(string: manga.displayImage), maxPixelSize: 200) { phase in
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
                            Text(manga.displayTitle)
                                .font(.kuroBody(weight: .regular))
                                .foregroundColor(.kuroBlack)
                                .lineLimit(2)

                            HStack(spacing: 4) {
                                Text(manga.year)
                                if let fmt = manga.format {
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
                    MediaDetailSheet(kind: .manga, id: manga.id)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Manga Hero Section
struct MangaHeroSection: View {
    let manga: Manga
    let geometry: GeometryProxy
    @Binding var scrollOffset: CGFloat
    
    var body: some View {
        let baseHeight = ResponsiveLayout.imageHeight(320)
        let stretch = max(scrollOffset, 0)
        let parallax = min(scrollOffset, 0) * 0.32

        ZStack(alignment: .bottom) {
            // Cover Image with Parallax
            KuroCachedAsyncImage(url: URL(string: manga.displayImage), maxPixelSize: 1100) { image in
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
            .offset(y: parallax - stretch)
            
            LinearGradient(
                colors: [Color.clear, Color.kuroBackground.opacity(0.92), Color.kuroBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 88)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
            
            HStack(alignment: .bottom, spacing: 12) {
                KuroCachedAsyncImage(url: URL(string: manga.displayImage), maxPixelSize: 520) { image in
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

                KuroStyle.mediaBadge("MANGA", isAnime: false)
            }
            .padding(.horizontal, ResponsiveLayout.padding())
            .padding(.bottom, 16)
        }
        .frame(height: baseHeight)
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Manga Title Section
struct MangaTitleSection: View {
    let manga: Manga
    
    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.sm) {
            // Japanese/Native Title
            if let nativeTitle = manga.titleNative {
                Text(nativeTitle)
                    .font(.kuroMicro(weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.kuroBlack60)
            }
            
            // Main Title
            Text(manga.displayTitle.uppercased())
                .font(.kuroCustom(24, weight: .ultraLight, design: .serif, relativeTo: .title2, maxSize: 40))
                .tracking(0.5)
                .foregroundColor(.kuroBlack)
                .lineSpacing(4)
            
            // Year & Format
            HStack(spacing: KuroSpacing.sm) {
                Text(manga.year)
                    .font(.kuroMicro(weight: .regular))
                    .tracking(1.0)
                    .foregroundColor(.kuroBlack60)
                
                if let format = manga.format {
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

// MARK: - Chapters Section
struct ChaptersSection: View {
    let manga: Manga
    let chapterCount: Int?
    var onError: ((KuroToastState) -> Void)? = nil
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @State private var progressActionScope = AccountActionScope()
    @Environment(ProviderAvailabilityStore.self) private var availability
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.openURL) private var openURL
    @State private var chapters: [MangaChapter] = []
    @State private var chapterStatus: MangaChapterStatus? = nil
    @State private var isLoading: Bool = false
    @State private var showAllChapters: Bool = false
    @State private var markingChapter: Int? = nil
    @State private var previewGeneration = UUID()
    @State private var legalReadLink: (url: String, site: String, label: String)? = nil

    private var entry: LibraryEntry? {
        library.entry(for: manga.libraryKey)
    }

    private var userProgress: Int {
        entry?.progress ?? 0
    }

    private var nextChapterNumber: Int {
        max(1, userProgress + 1)
    }

    private var shouldShowContinueLine: Bool {
        guard let status = entry?.status else { return userProgress > 0 }
        return userProgress > 0 || status == .current || status == .repeating
    }

    private var knownChapterTotal: Int {
        if let chapterCount { return chapterCount }
        if let statusCount = chapterStatus?.chapterRows { return statusCount }
        return chapters.count
    }
    
    var body: some View {
        let origin = progressActionScope.capture(session: libraryActions.accountSession)
        return VStack(alignment: .leading, spacing: KuroSpacing.md) {
            HStack {
                Text("CHAPTERS")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(.kuroBlack80)
                
                Spacer()
                
                Text("\(knownChapterTotal) TOTAL")
                    .font(.kuroMicro(weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.kuroBlack60)
            }

            if shouldShowContinueLine {
                Text("Continue with chapter \(nextChapterNumber).")
                    .font(.kuroMicro(weight: .medium))
                    .foregroundColor(.kuroBlack60)
            }
            
            VStack(spacing: KuroSpacing.sm) {
                if isLoading && chapters.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in
                        ChapterSkeletonRow()
                    }
                } else if chapters.isEmpty {
                    HStack {
                        Text(emptyStateMessage())
                            .font(.kuroMicro(weight: .light))
                            .foregroundColor(.kuroBlack60)
                        Spacer()
                    }
                    .padding(KuroSpacing.md)
                    .background(Color.kuroBlack08)
                    .cornerRadius(KuroRadius.sm)
                } else {
                    ForEach(chapters.prefix(1)) { ch in
                        ChapterItemRow(
                            chapter: ch,
                            isRead: ch.number <= userProgress,
                            isMarking: markingChapter == ch.number,
                            hasExternalLink: legalReadLink != nil,
                            onOpen: { openChapter(ch) },
                            onMarkRead: { markRead(ch, origin: origin) }
                        )
                    }
                }

                if !chapters.isEmpty && legalReadLink == nil {
                    HStack {
                        Text("Link coming soon.")
                            .font(.kuroMicro(weight: .light))
                            .foregroundColor(.kuroBlack60)
                        Spacer()
                    }
                    .padding(.horizontal, KuroSpacing.md)
                }

                if knownChapterTotal > 5 {
                    Button(action: {
                        KuroAccessibility.impactHaptic(.light)
                        showAllChapters = true
                    }) {
                        DetailSectionUtilityButton(
                            title: "VIEW ALL \(knownChapterTotal) CHAPTERS",
                            subtitle: "Browse the full release list"
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: nextChapterNumber) {
            guard !Task.isCancelled else { return }
            let generation = UUID()
            previewGeneration = generation
            let fromNumber = nextChapterNumber
            await loadPreview(generation: generation, fromNumber: fromNumber)
            guard isCurrentPreview(generation, fromNumber: fromNumber) else { return }
            await refreshChapterStatus(generation: generation, fromNumber: fromNumber)
            guard isCurrentPreview(generation, fromNumber: fromNumber) else { return }
            await refreshLegalReadLink(generation: generation, fromNumber: fromNumber)
        }
        .sheet(isPresented: $showAllChapters) {
            ChapterListSheet(manga: manga, chapterCount: chapterCount, chapterStatus: chapterStatus)
        }
        .onAppear { progressActionScope.activate(session: libraryActions.accountSession) }
        .onDisappear {
            progressActionScope.deactivate()
            markingChapter = nil
            previewGeneration = UUID()
            isLoading = false
        }
    }

    private func isCurrentPreview(_ generation: UUID, fromNumber: Int) -> Bool {
        !Task.isCancelled && previewGeneration == generation && nextChapterNumber == fromNumber
    }

    private func loadPreview(generation: UUID, fromNumber: Int) async {
        guard isCurrentPreview(generation, fromNumber: fromNumber) else { return }
        isLoading = true
        defer {
            if isCurrentPreview(generation, fromNumber: fromNumber) { isLoading = false }
        }
        let preview = await catalog.fetchChaptersNext(mangaId: manga.id, fromNumber: fromNumber, limit: 10)
        guard isCurrentPreview(generation, fromNumber: fromNumber) else { return }
        chapters = preview
    }

    private func refreshChapterStatus(generation: UUID, fromNumber: Int) async {
        let status = await catalog.fetchMangaChapterStatus(mangaId: manga.id)
        guard isCurrentPreview(generation, fromNumber: fromNumber) else { return }
        chapterStatus = status
    }

    private func openChapter(_ _: MangaChapter) {
        guard let legalReadLink else { return }
        KuroAccessibility.impactHaptic(.light)
        guard let url = ProviderAvailabilityStore.validatedOutboundURL(legalReadLink.url) else { return }
        openURL(url)
    }

    private func refreshLegalReadLink(generation: UUID, fromNumber: Int) async {
        let best = await availability.getBestLegalReadLink(
            manga: manga,
            locale: Locale.current.identifier
        )
        guard isCurrentPreview(generation, fromNumber: fromNumber) else { return }
        legalReadLink = best.flatMap { ProviderAvailabilityStore.validatedOutboundURL($0.url) != nil ? $0 : nil }
    }

    private func markRead(_ ch: MangaChapter, origin: AccountActionScope.Ticket?) {
        guard progressActionScope.isCurrent(origin, session: libraryActions.accountSession) else { return }
        let target = chapterCount.map { min(ch.number, $0) } ?? ch.number
        markingChapter = ch.number
        progressActionScope.launch(origin: origin, session: libraryActions.accountSession) { ticket in
            let outcome = await LibraryViewActions.markProgress(manga.libraryKey, to: target, actions: libraryActions)
            guard progressActionScope.isCurrent(ticket, session: libraryActions.accountSession) else { return }
            if outcome.error != nil {
                KuroAccessibility.errorHaptic()
                onError?(KuroToastState(kind: .error, title: "Update failed", subtitle: "Could not mark chapter \(ch.number).", actionTitle: nil, onAction: nil))
                #if DEBUG
                print("markRead failed for chapter \(ch.number): \(outcome)")
                #endif
            }
            markingChapter = nil
        }
    }

    private func emptyStateMessage() -> String {
        switch chapterStatus?.mappingStatus.lowercased() {
        case "syncing":
            return "Syncing chapter data..."
        case "unresolved":
            return "Chapter data is still being matched for this title."
        case "no_source":
            return "Chapter data is not available for this title yet."
        default:
            return "No chapter data yet"
        }
    }
}

struct ChapterItemRow: View {
    let chapter: MangaChapter
    let isRead: Bool
    let isMarking: Bool
    let hasExternalLink: Bool
    let onOpen: () -> Void
    let onMarkRead: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CH \(chapter.number)".uppercased())
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.0)
                    .foregroundColor(.kuroBlack80)

                if let title = chapter.title ?? chapter.titleRomaji, !title.isEmpty {
                    Text(title)
                        .font(.kuroMicro(weight: .light))
                        .foregroundColor(.kuroBlack60)
                        .lineLimit(1)
                } else if let date = chapter.releaseDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted).uppercased())
                        .font(.kuroMicro(weight: .light))
                        .foregroundColor(.kuroBlack60)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(hasExternalLink ? "READ READY" : "LINK PENDING")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(0.8)
                        .foregroundColor(hasExternalLink ? .kuroBlack80 : .kuroBlack60)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(hasExternalLink ? Color.kuroBlack08 : Color.kuroBlack05)
                        )
                }
            }

            Spacer()

            if isMarking {
                ProgressView()
                    .scaleEffect(0.75)
            } else if isRead {
                Image(systemName: "checkmark.circle.fill")
                    .font(.kuroCustom(14, weight: .semibold, maxSize: 22))
                    .foregroundColor(.kuroBlack)
            } else {
                Button(action: {
                    KuroAccessibility.impactHaptic(.light)
                    onMarkRead()
                }) {
                    Image(systemName: "plus.circle")
                        .font(.kuroCustom(16, weight: .regular, maxSize: 26))
                        .foregroundColor(.kuroBlack80)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark read")
            }

            if hasExternalLink {
                Image(systemName: "link.circle")
                    .font(.kuroCustom(14, weight: .regular, maxSize: 22))
                    .foregroundColor(.kuroBlack30)
            }
        }
        .padding(KuroSpacing.md)
        .background(Color.kuroBlack08)
        .cornerRadius(KuroRadius.sm)
        .contentShape(Rectangle())
        .onTapGesture { if hasExternalLink { onOpen() } }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabelText())
        .accessibilityValue(accessibilityValueText())
        .accessibilityHint(hasExternalLink ? "Opens legal read provider" : "")
        .accessibilityAction { if hasExternalLink { onOpen() } }
        .accessibilityAction(named: "Mark read") {
            if !isRead && !isMarking { onMarkRead() }
        }
    }

    private func accessibilityLabelText() -> Text {
        var parts: [String] = []
        parts.append("Chapter \(chapter.number)")
        if let title = chapter.title ?? chapter.titleRomaji, !title.isEmpty {
            parts.append(title)
        } else if let date = chapter.releaseDate {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        return Text(parts.joined(separator: ", "))
    }

    private func accessibilityValueText() -> Text {
        if isMarking { return Text("Updating") }
        return Text(isRead ? "Read" : "Not read")
    }
}

struct ChapterSkeletonRow: View {
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

struct ChapterListSheet: View {
    let manga: Manga
    let chapterCount: Int?
    let chapterStatus: MangaChapterStatus?
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @State private var progressActionScope = AccountActionScope()
    @Environment(ProviderAvailabilityStore.self) private var availability
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var chapters: [MangaChapter] = []
    @State private var isLoading: Bool = false
    @State private var hasLoadedOnce: Bool = false
    @State private var hasMore: Bool = true
    @State private var offset: Int = 0
    @State private var pagingGeneration = UUID()
    @State private var pagingTask: Task<Void, Never>? = nil
    // Paging must not supersede the legal link, which belongs to the sheet lifetime.
    @State private var linkGeneration = UUID()
    @State private var markingChapter: Int? = nil
    @State private var toast: KuroToastState? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil
    @State private var legalReadLink: (url: String, site: String, label: String)? = nil

    private let pageSize: Int = 50

    private var userProgress: Int {
        library.entry(for: manga.libraryKey)?.progress ?? 0
    }

    var body: some View {
        let origin = progressActionScope.capture(session: libraryActions.accountSession)
        return NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: KuroSpacing.sm) {
                    if legalReadLink == nil {
                        HStack {
                            Text("Link coming soon.")
                                .font(.kuroMicro(weight: .light))
                                .foregroundColor(.kuroBlack60)
                            Spacer()
                        }
                        .padding(.horizontal, KuroSpacing.md)
                        .padding(.vertical, KuroSpacing.sm)
                        .background(Color.kuroBlack08)
                        .cornerRadius(KuroRadius.sm)
                    }

                    if hasLoadedOnce && chapters.isEmpty && !isLoading {
                        VStack(spacing: 10) {
                            Text("NO CHAPTERS FOUND")
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.2)
                                .foregroundColor(.kuroBlack60)
                            Text(emptyStateMessage())
                                .font(.kuroMicro(weight: .light))
                                .foregroundColor(.kuroBlack30)
                        }
                        .padding(.vertical, 32)
                    }

                    ForEach(Array(chapters.enumerated()), id: \.element.id) { index, ch in
                        ChapterItemRow(
                            chapter: ch,
                            isRead: ch.number <= userProgress,
                            isMarking: markingChapter == ch.number,
                            hasExternalLink: legalReadLink != nil,
                            onOpen: { openChapter(ch) },
                            onMarkRead: { markRead(ch, origin: origin) }
                        )
                        .onAppear {
                            if index == chapters.count - 1, hasMore, !isLoading {
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
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .font(.kuroMicro(weight: .medium))
                }
            }
            .task(id: manga.id) {
                guard !Task.isCancelled else { return }
                pagingTask?.cancel()
                pagingTask = nil
                let generation = UUID()
                pagingGeneration = generation
                let legalLinkGeneration = UUID()
                linkGeneration = legalLinkGeneration
                await loadMore(reset: true, generation: generation)
                guard !Task.isCancelled, linkGeneration == legalLinkGeneration else { return }
                await refreshLegalReadLink(generation: legalLinkGeneration)
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
            markingChapter = nil
            pagingGeneration = UUID()
            linkGeneration = UUID()
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
            chapters = []
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

        let page = await catalog.fetchChaptersPage(mangaId: manga.id, offset: requestedOffset, limit: pageSize)
        guard !Task.isCancelled, pagingGeneration == generation, offset == requestedOffset else { return }
        chapters.append(contentsOf: page)
        hasMore = page.count == pageSize
        if hasMore { offset = requestedOffset + pageSize }
        hasLoadedOnce = true
    }

    private func openChapter(_ _: MangaChapter) {
        guard let legalReadLink else { return }
        KuroAccessibility.impactHaptic(.light)
        guard let url = ProviderAvailabilityStore.validatedOutboundURL(legalReadLink.url) else { return }
        openURL(url)
    }

    private func markRead(_ ch: MangaChapter, origin: AccountActionScope.Ticket?) {
        guard progressActionScope.isCurrent(origin, session: libraryActions.accountSession) else { return }
        let target = chapterCount.map { min(ch.number, $0) } ?? ch.number
        markingChapter = ch.number
        progressActionScope.launch(origin: origin, session: libraryActions.accountSession) { ticket in
            let outcome = await LibraryViewActions.markProgress(manga.libraryKey, to: target, actions: libraryActions)
            guard progressActionScope.isCurrent(ticket, session: libraryActions.accountSession) else { return }
            if outcome.error != nil {
                KuroAccessibility.errorHaptic()
                showToast(KuroToastState(kind: .error, title: "Update failed", subtitle: "Could not mark chapter \(ch.number).", actionTitle: nil, onAction: nil))
                #if DEBUG
                print("markRead failed for chapter \(ch.number): \(outcome)")
                #endif
            }
            markingChapter = nil
        }
    }

    private func emptyStateMessage() -> String {
        switch chapterStatus?.mappingStatus.lowercased() {
        case "syncing":
            return "Chapter data may still be importing."
        case "unresolved":
            return "Matching is still in progress for this title."
        case "no_source":
            return "No chapter source is available yet."
        default:
            return "Chapter data may still be importing."
        }
    }

    private func refreshLegalReadLink(generation: UUID) async {
        let best = await availability.getBestLegalReadLink(
            manga: manga,
            locale: Locale.current.identifier
        )
        guard !Task.isCancelled, linkGeneration == generation else { return }
        legalReadLink = best.flatMap { ProviderAvailabilityStore.validatedOutboundURL($0.url) != nil ? $0 : nil }
    }
}

// MARK: - Volumes Section
struct VolumesSection: View {
    let manga: Manga
    let volumeCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.md) {
            HStack {
                Text("VOLUMES")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(.kuroBlack80)
                
                Spacer()
                
                Text("\(volumeCount) TOTAL")
                    .font(.kuroMicro(weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.kuroBlack60)
            }
            
            // Volume grid
            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: KuroSpacing.md
            ) {
                ForEach(1...min(volumeCount, 6), id: \.self) { volume in
                    VolumeCard(volumeNumber: volume)
                }
            }
            
            // "VIEW ALL VOLUMES" removed — no volume detail destination exists yet.
            // Re-add when volume browsing is implemented.
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Volume Card
struct VolumeCard: View {
    let volumeNumber: Int
    
    var body: some View {
        VStack(spacing: KuroSpacing.xs) {
            Image(systemName: "book.fill")
                .font(.kuroBody())
                .foregroundColor(.kuroBlack30)
            
            Text("VOL \(volumeNumber)")
                .font(.kuroMicro(weight: .medium))
                .tracking(0.5)
                .foregroundColor(.kuroBlack80)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, KuroSpacing.md)
        .background(Color.kuroBlack08)
        .cornerRadius(KuroRadius.sm)
    }
}

// MARK: - Manga Action Buttons
struct MangaActionButtons: View {
    let manga: Manga
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
    @State private var readLink: ProviderSheetItem? = nil
    @State private var allLinks: [ProviderSheetItem] = []
    @State private var readAvailabilityNote: String? = nil
    @State private var readAvailabilityStatusCaption: String? = nil

    private var isGermanLocale: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("de") == true
    }

    private var isSaved: Bool {
        library.isTracked(manga.libraryKey)
    }

    private var userEntry: LibraryEntry? {
        library.entry(for: manga.libraryKey)
    }

    private var hasReadLink: Bool {
        readLink.flatMap { ProviderAvailabilityStore.validatedOutboundURL($0.url) } != nil
    }

    private var verdictButtonTitle: String {
        guard let verdict = userEntry?.verdict else { return isGermanLocale ? "Urteil" : "Verdict" }
        return isGermanLocale ? verdict.displayNameDE : verdict.displayName
    }

    private var readStatusLine: String {
        if let status = readAvailabilityStatusCaption, !status.isEmpty {
            return status
        }
        if let note = readAvailabilityNote, !note.isEmpty {
            return note
        }
        return hasReadLink
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
                    routes.presentTrackingEditor(TrackingEditorRequest(media: manga))
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

                Button(action: handleReadAction) {
                    Image(systemName: hasReadLink ? "book.fill" : "book.closed")
                        .font(.kuroCustom(13, weight: .semibold, maxSize: 21))
                        .foregroundColor(hasReadLink ? .kuroBlack : .kuroBlack30)
                        .frame(width: 38, height: 38)
                        .background(Color.kuroBlack08)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    hasReadLink
                        ? (allLinks.count > 1 ? "Choose reading provider" : "Open reading provider")
                        : "No legal reading link available"
                )
            }

            Text(readStatusLine)
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
        .task(id: manga.id) {
            await refreshLinks()
        }
        .sheet(isPresented: $showQuickVerdict) {
            QuickVerdictPickerSheet(media: manga, onToast: onToast)
        }
        .sheet(isPresented: $showProviders) {
            ProviderSelectionSheet(
                title: "Read On",
                links: allLinks,
                statusCaption: readAvailabilityStatusCaption
            ) { link in
                if let url = ProviderAvailabilityStore.validatedOutboundURL(link.url) {
                    KuroAccessibility.impactHaptic(.light)
                    outboundLinks.recordOutboundLink(mediaType: "MANGA", mediaId: manga.id, linkKind: "provider_sheet", provider: link.title)
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
        let key = manga.libraryKey
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

    private func handleReadAction() {
        guard let link = readLink, let linkURL = ProviderAvailabilityStore.validatedOutboundURL(link.url) else {
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
            outboundLinks.recordOutboundLink(mediaType: "MANGA", mediaId: manga.id, linkKind: "read", provider: link.title)
            openURL(linkURL)
        }
    }

    /// Resolves the read links through the ProviderAvailability owner (keyed on the manga id; the
    /// primary is the first item) and publishes them unless this run was superseded.
    private func refreshLinks() async {
        guard let snapshot = await availability.resolveReadLinks(mangaId: manga.id),
              !Task.isCancelled else { return }
        allLinks = snapshot.all
        readLink = snapshot.primary
        readAvailabilityNote = snapshot.note
        readAvailabilityStatusCaption = snapshot.statusCaption
    }
}
