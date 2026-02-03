import SwiftUI

// MARK: - MANGA DETAIL VIEW - iOS 26 Mobile-First
// Comprehensive manga detail page with elegant minimalism

struct MangaDetailView: View {
    let manga: Manga
    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseService.self) private var supabaseService
    @State private var scrollOffset: CGFloat = 0
    @State private var showFullDescription = false
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Hero Section with Parallax Effect
                    MangaHeroSection(manga: manga, geometry: geometry, scrollOffset: $scrollOffset)
                    
                    // Content Section
                    VStack(spacing: KuroDesignSpacing.adaptive(KuroSpacing.lg, for: geometry.size.width)) {
                        // Title & Quick Info
                        MangaTitleSection(manga: manga)
                        
                        // Stats Grid
                        MangaStatsGrid(manga: manga)
                        
                        // Description
                        DescriptionSection(
                            description: manga.displayDescription,
                            showFull: $showFullDescription
                        )
                        
                        // Genres
                        if let genres = manga.genreList, !genres.isEmpty {
                            GenresSection(genres: genres)
                        }
                        
                        // Chapters Section (if available)
                        if let chapterCount = manga.chapterCount {
                            ChaptersSection(manga: manga, chapterCount: chapterCount)
                        }
                        
                        // Volumes Section (if available)
                        if let volumeCount = manga.volumeCount {
                            VolumesSection(manga: manga, volumeCount: volumeCount)
                        }
                        
                        // Action Buttons
                        MangaActionButtons(manga: manga)
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

// MARK: - Manga Hero Section
struct MangaHeroSection: View {
    let manga: Manga
    let geometry: GeometryProxy
    @Binding var scrollOffset: CGFloat
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Cover Image with Parallax
            KuroCachedAsyncImage(url: URL(string: manga.displayImage)) { image in
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
                KuroStyle.mediaBadge("MANGA", isAnime: false)
            }
            .padding(.horizontal, ResponsiveLayout.padding())
            .padding(.bottom, KuroSpacing.lg)
        }
        .frame(height: ResponsiveLayout.imageHeight(320))
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
    let chapterCount: Int
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.openURL) private var openURL
    @State private var chapters: [MangaChapter] = []
    @State private var isLoading: Bool = false
    @State private var showAllChapters: Bool = false
    @State private var markingChapter: Int? = nil

    private var userProgress: Int {
        supabaseService.userLists.first(where: { $0.mediaType.lowercased() == "manga" && $0.mediaId == manga.id })?.progress ?? 0
    }

    private var nextChapterNumber: Int {
        max(1, userProgress + 1)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.md) {
            HStack {
                Text("CHAPTERS")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(.kuroBlack80)
                
                Spacer()
                
                Text("\(chapterCount) TOTAL")
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
                        Text("No chapter data yet")
                            .font(.kuroMicro(weight: .light))
                            .foregroundColor(.kuroBlack60)
                        Spacer()
                    }
                    .padding(KuroSpacing.md)
                    .background(Color.kuroBlack08)
                    .cornerRadius(KuroRadius.sm)
                } else {
                    ForEach(chapters.prefix(5)) { ch in
                        ChapterItemRow(
                            chapter: ch,
                            isRead: ch.number <= userProgress,
                            isMarking: markingChapter == ch.number,
                            onOpen: { openChapter(ch) },
                            onMarkRead: { markRead(ch) }
                        )
                    }
                }

                if chapterCount > 5 {
                    Button(action: {
                        KuroAccessibility.impactHaptic(.light)
                        showAllChapters = true
                    }) {
                        HStack {
                            Text("VIEW ALL \(chapterCount) CHAPTERS")
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
        }
        .sheet(isPresented: $showAllChapters) {
            ChapterListSheet(manga: manga, chapterCount: chapterCount)
                .environment(supabaseService)
        }
    }

    private func loadPreview() async {
        isLoading = true
        defer { isLoading = false }
        chapters = await supabaseService.fetchChaptersNext(mangaId: manga.id, fromNumber: nextChapterNumber, limit: 10)
    }

    private func openChapter(_ ch: MangaChapter) {
        KuroAccessibility.impactHaptic(.light)
        if let urlString = manga.siteUrl, let url = URL(string: urlString) {
            openURL(url)
        }
    }

    private func markRead(_ ch: MangaChapter) {
        let target = min(ch.number, chapterCount)
        markingChapter = ch.number
        Task {
            await supabaseService.setUserProgress(mediaId: manga.id, mediaType: "manga", progress: target)
            await MainActor.run { markingChapter = nil }
        }
    }
}

struct ChapterItemRow: View {
    let chapter: MangaChapter
    let isRead: Bool
    let isMarking: Bool
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

            Image(systemName: "chevron.right")
                .font(.kuroMicro())
                .foregroundColor(.kuroBlack30)
        }
        .padding(KuroSpacing.md)
        .background(Color.kuroBlack08)
        .cornerRadius(KuroRadius.sm)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabelText())
        .accessibilityValue(accessibilityValueText())
        .accessibilityHint("Opens chapter")
        .accessibilityAction { onOpen() }
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
    let chapterCount: Int
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var chapters: [MangaChapter] = []
    @State private var isLoading: Bool = false
    @State private var hasLoadedOnce: Bool = false
    @State private var hasMore: Bool = true
    @State private var offset: Int = 0
    @State private var markingChapter: Int? = nil

    private let pageSize: Int = 50

    private var userProgress: Int {
        supabaseService.userLists.first(where: { $0.mediaType.lowercased() == "manga" && $0.mediaId == manga.id })?.progress ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: KuroSpacing.sm) {
                    if hasLoadedOnce && chapters.isEmpty && !isLoading {
                        VStack(spacing: 10) {
                            Text("NO CHAPTERS FOUND")
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.2)
                                .foregroundColor(.kuroBlack60)
                            Text("Chapter data may still be importing.")
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
            }
        }
        .presentationDetents([.medium, .large])
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

    private func openChapter(_ ch: MangaChapter) {
        KuroAccessibility.impactHaptic(.light)
        if let urlString = manga.siteUrl, let url = URL(string: urlString) {
            openURL(url)
        }
    }

    private func markRead(_ ch: MangaChapter) {
        let target = min(ch.number, chapterCount)
        markingChapter = ch.number
        Task {
            await supabaseService.setUserProgress(mediaId: manga.id, mediaType: "manga", progress: target)
            await MainActor.run { markingChapter = nil }
        }
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
            
            if volumeCount > 6 {
                Button(action: {
                    // Navigate to full volume list
                    KuroAccessibility.impactHaptic(.light)
                }) {
                    HStack {
                        Text("VIEW ALL \(volumeCount) VOLUMES")
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
        VStack(spacing: KuroSpacing.md) {
            if let link = readLink, !link.url.isEmpty {
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
                    .padding(.vertical, KuroSpacing.lg)
                    .padding(.horizontal, KuroSpacing.md)
                    .background(Color.kuroBlack)
                    .cornerRadius(KuroRadius.sm)
                }
            }

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
                .padding(.vertical, KuroSpacing.lg)
                .background(Color.kuroBlack)
                .cornerRadius(KuroRadius.sm)
            }
            .sheet(isPresented: $showAddToList) {
                AddToListSheet(media: manga)
            }

            HStack(spacing: KuroSpacing.md) {
                SecondaryActionButton(
                    icon: isSaved ? "heart.fill" : "heart",
                    label: isSaved ? "SAVED" : "SAVE"
                ) {
                    toggleSaved()
                }

                if let urlString = manga.siteUrl, let url = URL(string: urlString) {
                    SecondaryShareButton(url: url, title: manga.displayTitle)
                } else {
                    SecondaryActionButton(icon: "square.and.arrow.up", label: "SHARE") { }
                }
            }
        }
        .task(id: manga.id) {
            await refreshLinks()
        }
        .sheet(isPresented: $showProviders) {
            ProviderSelectionSheet(title: "Read On", links: allLinks) { link in
                if let url = URL(string: link.url) {
                    KuroAccessibility.impactHaptic(.light)
                    openURL(url)
                }
            }
        }
    }

    private func refreshLinks() async {
        let links = await supabaseService.fetchExternalLinks(mediaType: "MANGA", mediaId: manga.id)
        let best = await supabaseService.getBestReadLink(manga: manga)
        await MainActor.run {
            self.allLinks = links
            self.readLink = best
        }
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
            } else {
                KuroAccessibility.successHaptic()
            }
        }
    }
}
