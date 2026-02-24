import SwiftUI

// MARK: - MANGA DETAIL VIEW - iOS 26 Mobile-First
// Comprehensive manga detail page with elegant minimalism

struct MangaDetailView: View {
    let manga: Manga
    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseService.self) private var supabaseService
    @State private var scrollOffset: CGFloat = 0
    @State private var showFullDescription = false
    @State private var toast: KuroToastState? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil
    @State private var topTags: [TagFacet] = []
    @State private var similar: [Manga] = []
    @State private var condensedSynopsis: String?

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
                    MangaHeroSection(manga: manga, geometry: geometry, scrollOffset: $scrollOffset)
                        .offset(y: -safeTop)
                        .padding(.bottom, -safeTop)
                    
                    // Content Section
                    VStack(spacing: KuroDesignSpacing.adaptive(KuroSpacing.lg, for: geometry.size.width)) {
                        // Title & Quick Info
                        MangaTitleSection(manga: manga)
                        
                        MangaMetaLineSection(manga: manga)

                        MangaNextUpSection(manga: manga)
                        
                        // Description
                        DescriptionSection(
                            description: manga.displayDescription,
                            showFull: $showFullDescription,
                            condensedSynopsis: condensedSynopsis
                        )
                        
                        // Genres
                        if let genres = manga.genreList, !genres.isEmpty {
                            GenresSection(genres: genres)
                        }

                        if !topTags.isEmpty {
                            TagChipsSection(title: "SUB‑GENRES", tags: topTags.map(\.name))
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
                            MangaSimilarSection(title: "MORE LIKE THIS", items: similar)
                        }

                        ClubActivitySection(mediaId: manga.id, mediaType: "MANGA")

                        if FeatureFlags.shared.isSocialActivityV1Enabled {
                            FriendsActivitySection(mediaId: manga.id, mediaType: "MANGA")
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
            async let tags = supabaseService.fetchTopTagsForManga(mangaId: manga.id, limit: 12)
            async let sim = supabaseService.fetchSimilarManga(seed: manga, limit: 14)
            topTags = await tags
            similar = await sim

            // Condense long synopses on-device via Apple FM (no-op on unsupported devices)
            let sourceSynopsis = manga.displayDescription
            let hasReadyEnhanced = (manga.synopsisEnhancedState ?? "").lowercased() == "ready"
            if !hasReadyEnhanced, sourceSynopsis.count > 200 {
                condensedSynopsis = await supabaseService.fmService.condenseSynopsis(
                    mediaId: manga.id,
                    description: sourceSynopsis,
                    title: manga.displayTitle,
                    genres: manga.genreList ?? []
                )
            }
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

// MARK: - Next up (minimal)
struct MangaNextUpSection: View {
    let manga: Manga
    @Environment(SupabaseService.self) private var supabaseService

    private var progress: Int {
        supabaseService.userLists.first(where: { $0.mediaType.lowercased() == "manga" && $0.mediaId == manga.id })?.progress ?? 0
    }
    private var nextNumber: Int { max(1, progress + 1) }

    var body: some View {
        HStack(spacing: 12) {
            Text("NEXT UP")
                .font(.kuroMicro(weight: .medium))
                .tracking(1.8)
                .foregroundColor(.kuroBlack80)

            Spacer(minLength: 0)

            Text("CH \(nextNumber)".uppercased())
                .font(.kuroMicro(weight: .regular))
                .tracking(1.2)
                .foregroundColor(.kuroBlack80)
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

struct MangaSimilarSection: View {
    let title: String
    let items: [Manga]

    private var cardWidth: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let candidate = floor((screenWidth - 56) / 2.8)
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
    @Environment(SupabaseService.self) private var supabaseService
    @State private var showDetail = false

    private var userEntry: UserList? {
        supabaseService.userLists.first {
            $0.mediaId == mediaId && $0.mediaType.lowercased() == "manga"
        }
    }

    private var isCompleted: Bool {
        userEntry?.status == .completed
    }

    private var pick: Manga? {
        guard isCompleted else { return nil }
        let collectionIds = supabaseService.userMediaIds(mediaType: "manga")
        let planningIds = supabaseService.userMediaIds(mediaType: "manga", status: .planning)

        if let planned = similar.first(where: { planningIds.contains($0.id) }) {
            return planned
        }

        return similar
            .filter { !collectionIds.contains($0.id) }
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
                    MediaDetailSheet(kind: .manga, id: manga.id)
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
                .font(.system(size: ResponsiveLayout.fontSize(24), weight: .ultraLight, design: .serif))
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

// MARK: - Manga Stats Grid
struct MangaStatsGrid: View {
    let manga: Manga
    
    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: KuroSpacing.md
        ) {
            if let score = manga.averageScore {
                StatCard(
                    label: "SCORE",
                    value: String(format: "%.1f", Double(score) / 10.0),
                    icon: "star.fill"
                )
            }
            
            if let chapters = manga.chapterCount {
                StatCard(
                    label: "CHAPTERS",
                    value: "\(chapters)",
                    icon: "book.fill"
                )
            }
            
            if let volumes = manga.volumeCount {
                StatCard(
                    label: "VOLUMES",
                    value: "\(volumes)",
                    icon: "books.vertical.fill"
                )
            }
        }
    }
}

// MARK: - Chapters Section
struct ChaptersSection: View {
    let manga: Manga
    let chapterCount: Int?
    var onError: ((KuroToastState) -> Void)? = nil
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.openURL) private var openURL
    @State private var chapters: [MangaChapter] = []
    @State private var chapterStatus: MangaChapterStatus? = nil
    @State private var isLoading: Bool = false
    @State private var showAllChapters: Bool = false
    @State private var markingChapter: Int? = nil
    @State private var legalReadLink: (url: String, site: String, label: String)? = nil

    private var userProgress: Int {
        supabaseService.userLists.first(where: { $0.mediaType.lowercased() == "manga" && $0.mediaId == manga.id })?.progress ?? 0
    }

    private var nextChapterNumber: Int {
        max(1, userProgress + 1)
    }

    private var knownChapterTotal: Int {
        if let chapterCount { return chapterCount }
        if let statusCount = chapterStatus?.chapterRows { return statusCount }
        return chapters.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.md) {
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
                            onMarkRead: { markRead(ch) }
                        )
                    }
                }

                if !chapters.isEmpty && legalReadLink == nil {
                    HStack {
                        Text("No legal read link is available yet.")
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
                        HStack {
                            Text("VIEW ALL \(knownChapterTotal) CHAPTERS")
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
        .task(id: nextChapterNumber) {
            await loadPreview()
            await refreshChapterStatus()
            await refreshLegalReadLink()
        }
        .sheet(isPresented: $showAllChapters) {
            ChapterListSheet(manga: manga, chapterCount: chapterCount, chapterStatus: chapterStatus)
                .environment(supabaseService)
        }
    }

    private func loadPreview() async {
        isLoading = true
        defer { isLoading = false }
        chapters = await supabaseService.fetchChaptersNext(mangaId: manga.id, fromNumber: nextChapterNumber, limit: 10)
    }

    private func refreshChapterStatus() async {
        let status = await supabaseService.fetchMangaChapterStatus(mangaId: manga.id)
        await MainActor.run { chapterStatus = status }
    }

    private func openChapter(_ _: MangaChapter) {
        guard let legalReadLink else { return }
        KuroAccessibility.impactHaptic(.light)
        guard let url = validatedURL(from: legalReadLink.url) else { return }
        openURL(url)
    }

    private func refreshLegalReadLink() async {
        let best = await supabaseService.getBestLegalReadLink(
            manga: manga,
            locale: Locale.current.identifier
        )
        await MainActor.run {
            legalReadLink = best.flatMap { validatedURL(from: $0.url) != nil ? $0 : nil }
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
        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    private func markRead(_ ch: MangaChapter) {
        let target = chapterCount.map { min(ch.number, $0) } ?? ch.number
        markingChapter = ch.number
        Task {
            await supabaseService.setUserProgress(mediaId: manga.id, mediaType: "manga", progress: target)
            if let msg = supabaseService.errorMessage, !msg.isEmpty {
                KuroAccessibility.errorHaptic()
                onError?(KuroToastState(kind: .error, title: "Update failed", subtitle: "Could not mark chapter \(ch.number).", actionTitle: nil, onAction: nil))
                #if DEBUG
                print("markRead failed for chapter \(ch.number): \(msg)")
                #endif
            }
            await MainActor.run { markingChapter = nil }
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
            }

            Spacer()

            if isMarking {
                ProgressView()
                    .scaleEffect(0.75)
            } else if isRead {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.kuroBlack)
            } else {
                Button(action: {
                    KuroAccessibility.impactHaptic(.light)
                    onMarkRead()
                }) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.kuroBlack80)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark read")
            }

            if hasExternalLink {
                Image(systemName: "link.circle")
                    .font(.system(size: 14, weight: .regular))
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
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var chapters: [MangaChapter] = []
    @State private var isLoading: Bool = false
    @State private var hasLoadedOnce: Bool = false
    @State private var hasMore: Bool = true
    @State private var offset: Int = 0
    @State private var markingChapter: Int? = nil
    @State private var toast: KuroToastState? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil
    @State private var legalReadLink: (url: String, site: String, label: String)? = nil

    private let pageSize: Int = 50

    private var userProgress: Int {
        supabaseService.userLists.first(where: { $0.mediaType.lowercased() == "manga" && $0.mediaId == manga.id })?.progress ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: KuroSpacing.sm) {
                    if legalReadLink == nil {
                        HStack {
                            Text("No legal read provider is available yet.")
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
                            onMarkRead: { markRead(ch) }
                        )
                        .onAppear {
                            if index == chapters.count - 1, hasMore, !isLoading {
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
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .font(.kuroMicro(weight: .medium))
                }
            }
            .task {
                await loadMore(reset: true)
                await refreshLegalReadLink()
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
            chapters = []
            offset = 0
            hasMore = true
            hasLoadedOnce = false
        }
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let page = await supabaseService.fetchChaptersPage(mangaId: manga.id, offset: offset, limit: pageSize)
        chapters.append(contentsOf: page)
        hasMore = page.count == pageSize
        if hasMore { offset += pageSize }
        hasLoadedOnce = true
    }

    private func openChapter(_ _: MangaChapter) {
        guard let legalReadLink else { return }
        KuroAccessibility.impactHaptic(.light)
        guard let url = validatedURL(from: legalReadLink.url) else { return }
        openURL(url)
    }

    private func markRead(_ ch: MangaChapter) {
        let target = chapterCount.map { min(ch.number, $0) } ?? ch.number
        markingChapter = ch.number
        Task {
            await supabaseService.setUserProgress(mediaId: manga.id, mediaType: "manga", progress: target)
            if let msg = supabaseService.errorMessage, !msg.isEmpty {
                KuroAccessibility.errorHaptic()
                showToast(KuroToastState(kind: .error, title: "Update failed", subtitle: "Could not mark chapter \(ch.number).", actionTitle: nil, onAction: nil))
                #if DEBUG
                print("markRead failed for chapter \(ch.number): \(msg)")
                #endif
            }
            await MainActor.run { markingChapter = nil }
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

    private func refreshLegalReadLink() async {
        let best = await supabaseService.getBestLegalReadLink(
            manga: manga,
            locale: Locale.current.identifier
        )
        await MainActor.run {
            legalReadLink = best.flatMap { validatedURL(from: $0.url) != nil ? $0 : nil }
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
        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
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
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.openURL) private var openURL
    @State private var showAddToList = false
    @State private var showProviders = false
    @State private var readLink: (url: String, site: String, label: String)? = nil
    @State private var allLinks: [ExternalLink] = []

    private var isSaved: Bool {
        supabaseService.isInCollection(mediaId: manga.id, mediaType: "manga")
    }

    var body: some View {
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

            Button(action: {
                KuroAccessibility.impactHaptic(.medium)
                showAddToList = true
            }) {
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
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showAddToList) {
                AddToListSheet(media: manga)
            }

            if let link = readLink, let linkURL = validatedURL(from: link.url) {
                Button(action: {
                    if allLinks.count > 1 {
                        showProviders = true
                    } else {
                        KuroAccessibility.impactHaptic(.medium)
                        openURL(linkURL)
                    }
                }) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.kuroBlack)
                        .frame(width: 38, height: 38)
                        .background(Color.kuroBlack08)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(link.label)
            } else {
                Button(action: {
                    KuroAccessibility.impactHaptic(.light)
                    onToast(
                        .init(
                            kind: .info,
                            title: "No legal read link yet",
                            subtitle: "We only show verified legal providers.",
                            actionTitle: nil,
                            onAction: nil
                        )
                    )
                }) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.kuroBlack30)
                        .frame(width: 38, height: 38)
                        .background(Color.kuroBlack08)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("No legal read link available")
            }
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
        .task(id: manga.id) {
            await refreshLinks()
        }
        .sheet(isPresented: $showProviders) {
            ProviderSelectionSheet(title: "Read On", links: allLinks) { link in
                if let url = validatedURL(from: link.url) {
                    KuroAccessibility.impactHaptic(.light)
                    openURL(url)
                } else {
                    onToast(.init(kind: .error, title: "Couldn’t open link", subtitle: "Try a different provider.", actionTitle: nil, onAction: nil))
                }
            }
        }
    }

    private func refreshLinks() async {
        let links = await supabaseService.fetchLegalReadLinks(
            mediaId: manga.id,
            locale: Locale.current.identifier
        )
        let best = await supabaseService.getBestLegalReadLink(
            manga: manga,
            locale: Locale.current.identifier
        )
        await MainActor.run {
            self.allLinks = links.filter { validatedURL(from: $0.url) != nil }
            self.readLink = best.flatMap { validatedURL(from: $0.url) != nil ? $0 : nil }
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

    private func toggleSaved() {
        let currentlySaved = isSaved
        Task {
            if currentlySaved {
                await supabaseService.removeFromList(mediaId: manga.id, mediaType: "manga")
            } else {
                await supabaseService.addToList(mediaId: manga.id, mediaType: "manga", status: .planning)
            }
            if let msg = supabaseService.errorMessage, !msg.isEmpty {
                KuroAccessibility.errorHaptic()
                await MainActor.run {
                    onToast(.init(kind: .error, title: "Couldn’t save", subtitle: msg, actionTitle: nil, onAction: nil))
                }
            } else {
                KuroAccessibility.successHaptic()
                await MainActor.run {
                    onToast(
                        .init(
                            kind: .success,
                            title: currentlySaved ? "Removed" : "Saved",
                            subtitle: currentlySaved ? "Removed from your list" : "Added to Planning",
                            actionTitle: nil,
                            onAction: nil
                        )
                    )
                }
            }
        }
    }
}
