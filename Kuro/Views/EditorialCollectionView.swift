// Editorial Collection View
// Vogue/Miu Miu inspired personal collection
// Refined grid, elegant filters, sophisticated presentation

import SwiftUI

struct EditorialCollectionView: View {
    @Environment(SupabaseService.self) private var supabaseService
    @State private var selectedFilter: CollectionFilter = .all
    @State private var didInitialLoad = false

    enum CollectionFilter: String, CaseIterable {
        case all = "ALL"
        case watching = "WATCHING"
        case completed = "COMPLETED"
        case planned = "PLANNED"
        case paused = "PAUSED"

        var displayName: String { rawValue }

        var listStatus: ListStatus? {
            switch self {
            case .all: return nil
            case .watching: return .current
            case .completed: return .completed
            case .planned: return .planning
            case .paused: return .paused
            }
        }
    }

    private var filteredAnime: [Anime] {
        let userAnimeIds: Set<Int> =
            selectedFilter == .all
            ? supabaseService.userMediaIds(mediaType: "anime")
            : (selectedFilter.listStatus.map { supabaseService.userMediaIds(mediaType: "anime", status: $0) } ?? [])
        return supabaseService.collectionAnimeItems.filter { userAnimeIds.contains($0.id) }
    }

    private var filteredManga: [Manga] {
        let userMangaIds: Set<Int> =
            selectedFilter == .all
            ? supabaseService.userMediaIds(mediaType: "manga")
            : (selectedFilter.listStatus.map { supabaseService.userMediaIds(mediaType: "manga", status: $0) } ?? [])
        return supabaseService.collectionMangaItems.filter { userMangaIds.contains($0.id) }
    }

    private var hasContent: Bool {
        !filteredAnime.isEmpty || !filteredManga.isEmpty
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Editorial Filter Bar
                EditorialFilterBar(
                    filters: CollectionFilter.allCases,
                    selectedFilter: $selectedFilter
                )
                .padding(.vertical, 20)

                // Collection Grid
                ScrollView(.vertical, showsIndicators: false) {
                    if supabaseService.isCollectionLoading {
                        EditorialCollectionLoading()
                    } else if let msg = supabaseService.collectionErrorMessage, !msg.isEmpty {
                        VStack(spacing: 8) {
                            Text("COULDN'T LOAD COLLECTION")
                                .font(.kuroCaption())
                                .tracking(1.5)
                                .foregroundColor(.black.opacity(0.5))
                            Text(msg)
                                .font(.kuroMicro(weight: .light))
                                .foregroundColor(.black.opacity(0.4))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        .padding(.top, 80)
                    } else if !hasContent {
                        EditorialCollectionEmpty()
                    } else {
                        VStack(spacing: 24) {
                            // Anime section
                            if !filteredAnime.isEmpty {
                                EditorialCollectionGrid(items: filteredAnime, geometry: geometry, title: "ANIME")
                            }

                            // Manga section
                            if !filteredManga.isEmpty {
                                EditorialCollectionGrid(items: filteredManga, geometry: geometry, title: "MANGA")
                            }
                        }
                    }
                }
                .scrollDisabled(false)
                .refreshable {
                    await supabaseService.fetchUserLists()
                    await supabaseService.fetchCollectionItems()
                }
                .background(Color.white)
            }
        }
        .task {
            if !didInitialLoad {
                didInitialLoad = true
                await supabaseService.fetchUserLists()
                await supabaseService.fetchCollectionItems()
            }
        }
        .onChange(of: selectedFilter) { _, _ in
            // Filter is handled in computed property filteredItems
            // No need to refetch - just refilter client-side
        }
    }
}

// MARK: - Editorial Filter Bar
struct EditorialFilterBar<Filter: RawRepresentable & CaseIterable & Hashable>: View where Filter.RawValue == String {
    let filters: [Filter]
    @Binding var selectedFilter: Filter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: EditorialLayout.gutterLarge) {
                ForEach(filters, id: \.self) { filter in
                    EditorialFilterTab(
                        title: filter.rawValue,
                        isSelected: selectedFilter == filter
                    ) {
                        withAnimation(KuroAnimation.editorial) {
                            selectedFilter = filter
                        }
                    }
                }
            }
            .padding(.horizontal, EditorialLayout.marginEditorial)
        }
    }
}

// MARK: - Editorial Filter Tab
struct EditorialFilterTab: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.kuroCaption())
                    .tracking(1.8)
                    .foregroundColor(isSelected ? .black : .black.opacity(0.4))

                // Underline indicator
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 1.5)
                    .opacity(isSelected ? 1.0 : 0.0)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Filters collection")
        .animation(KuroAnimation.editorial, value: isSelected)
    }
}

// MARK: - Editorial Collection Grid
struct EditorialCollectionGrid: View {
    let items: [any MediaDisplayable]
    let geometry: GeometryProxy
    let title: String?

    init(items: [any MediaDisplayable], geometry: GeometryProxy, title: String? = nil) {
        self.items = items
        self.geometry = geometry
        self.title = title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Optional section title
            if let title = title {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(1.0)
                    .foregroundColor(.black.opacity(0.6))
                    .padding(.horizontal, 20)
            }

            // Calculate FIXED card dimensions
            let horizontalPadding: CGFloat = 20
            let spacing: CGFloat = 12
            let totalHorizontalPadding = horizontalPadding * 2
            let totalSpacing = spacing
            let availableWidth = geometry.size.width - totalHorizontalPadding - totalSpacing
            let cardWidth = floor(availableWidth / 2)
            let imageHeight = floor(cardWidth / 0.7)
            let textBlockHeight: CGFloat = 72
            let cardSpacing: CGFloat = 8
            let totalCardHeight = imageHeight + cardSpacing + textBlockHeight

            let columns = [
                GridItem(.fixed(cardWidth), spacing: spacing),
                GridItem(.fixed(cardWidth), spacing: spacing)
            ]

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(Array(items.prefix(50).enumerated()), id: \.offset) { _, media in
                    CollectionGridCard(media: media, cardWidth: cardWidth, cardHeight: totalCardHeight)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, title != nil ? 20 : 32)
    }
}

// MARK: - Editorial Collection Loading
struct EditorialCollectionLoading: View {
    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: EditorialLayout.gutterMedium),
                GridItem(.flexible(), spacing: EditorialLayout.gutterMedium)
            ],
            spacing: EditorialLayout.gutterLarge
        ) {
            ForEach(0..<12, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    Rectangle()
                        .fill(Color.black.opacity(0.03))
                        .aspectRatio(EditorialLayout.standardAspectRatio, contentMode: .fit)

                    VStack(alignment: .leading, spacing: 6) {
                        Rectangle()
                            .fill(Color.black.opacity(0.06))
                            .frame(height: 10)

                        Rectangle()
                            .fill(Color.black.opacity(0.04))
                            .frame(height: 8)
                            .frame(maxWidth: 100)
                    }
                }
            }
        }
        .padding(.horizontal, EditorialLayout.marginEditorial)
        .padding(.top, EditorialLayout.gutterSmall)
    }
}

// MARK: - Editorial Collection Empty
struct EditorialCollectionEmpty: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "tray")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundColor(.black.opacity(0.15))

                VStack(spacing: 8) {
                    Text("YOUR COLLECTION IS EMPTY")
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(1.0)
                        .foregroundColor(.black.opacity(0.4))

                    Text("Add anime or manga from Discover")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.black.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
            }

            // Instructions
            VStack(alignment: .leading, spacing: 12) {
                InstructionRow(
                    icon: "hand.tap",
                    text: "Tap any anime to view details"
                )
                InstructionRow(
                    icon: "hand.point.up",
                    text: "Long-press to add to collection"
                )
                InstructionRow(
                    icon: "checkmark.circle",
                    text: "Green checkmark shows collected items"
                )
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Instruction Row
struct InstructionRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .light))
                .foregroundColor(.black.opacity(0.4))
                .frame(width: 24)

            Text(text)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.black.opacity(0.6))

            Spacer()
        }
    }
}

// MARK: - Alternative: Editorial Masonry Layout
struct EditorialMasonryGrid: View {
    let items: [Anime]

    var body: some View {
        // Advanced masonry layout with varied sizes
        VStack(spacing: EditorialLayout.gutterMedium) {
            ForEach(Array(stride(from: 0, to: items.count, by: 3)), id: \.self) { index in
                if index < items.count {
                    masonryRow(startIndex: index)
                }
            }
        }
        .padding(.horizontal, EditorialLayout.marginEditorial)
        .padding(.top, EditorialLayout.gutterSmall)
        .padding(.bottom, EditorialLayout.gutterLarge)
    }

    @ViewBuilder
    private func masonryRow(startIndex: Int) -> some View {
        let rowItems = Array(items[startIndex..<min(startIndex + 3, items.count)])

        if rowItems.count == 3 {
            // 1 large + 2 small pattern
            HStack(alignment: .top, spacing: EditorialLayout.gutterMedium) {
                // Large (2/3 width)
                EditorialGridCard(media: rowItems[0], size: .large)
                    .frame(height: 360)

                // Two small (1/3 width each, stacked)
                VStack(spacing: EditorialLayout.gutterMedium) {
                    EditorialGridCard(media: rowItems[1], size: .small)
                        .frame(height: 172)

                    EditorialGridCard(media: rowItems[2], size: .small)
                        .frame(height: 172)
                }
            }
        } else if rowItems.count == 2 {
            HStack(spacing: EditorialLayout.gutterMedium) {
                EditorialFeatureCard(media: rowItems[0])
                EditorialFeatureCard(media: rowItems[1])
            }
        } else if let item = rowItems.first {
            EditorialFeatureCard(media: item)
        }
    }
}

#Preview {
    EditorialCollectionView()
        .environment(SupabaseService.shared)
}

// MARK: - Collection Grid Card (with countdown)
struct CollectionGridCard: View {
    let media: any MediaDisplayable
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    @State private var showDetail = false
    @State private var showAddToList = false
    @Environment(SupabaseService.self) private var supabaseService

    // Countdown currently depends on the full Anime row (next airing fields aren't present on cards).
    private var animeForCountdown: Anime? { media as? Anime }

    private var mediaType: String {
        media.kind.rawValue
    }

    private var isInCollection: Bool {
        supabaseService.isInCollection(mediaId: media.id, mediaType: mediaType)
    }

    private var userProgress: (watched: Int, total: Int)? {
        guard media.kind == .anime else { return nil }
        guard let watched = supabaseService.userListProgress(mediaType: "anime", mediaId: media.id) else { return nil }
        guard let total = media.episodes, total > 0 else { return nil }
        return (watched, total)
    }

    private var mangaProgress: (read: Int, total: Int)? {
        guard media.kind == .manga else { return nil }
        guard let read = supabaseService.userListProgress(mediaType: "manga", mediaId: media.id) else { return nil }
        guard let total = media.chapters, total > 0 else { return nil }
        return (read, total)
    }

    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        }) {
            VStack(alignment: .leading, spacing: 8) {
            // Image with score - FIXED HEIGHT
            let imageHeight = floor(cardWidth / 0.7)

            ZStack(alignment: .topTrailing) {
                KuroCachedAsyncImage(url: URL(string: media.imageURL ?? "")) { phase in
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
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .trailing, spacing: 6) {
                    // Score badge
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
                    }

                    // Collection indicator
                    if isInCollection {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.green)
                            .background(
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 18, height: 18)
                            )
                    }
                }
                .padding(6)
            }

            // Title and info - FIXED HEIGHT
            VStack(alignment: .leading, spacing: 4) {
                Text(media.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.black)
                    .lineLimit(2)
                    .frame(height: 36, alignment: .top)

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

                // PROGRESS DISPLAY (anime or manga)
                if let progress = userProgress {
                    Text("\(progress.watched)/\(progress.total) WATCHED")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(0.5)
                        .foregroundColor(.black.opacity(0.7))
                } else if let progress = mangaProgress {
                    Text("\(progress.read)/\(progress.total) READ")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(0.5)
                        .foregroundColor(.black.opacity(0.7))
                }

                // COUNTDOWN TIMER FOR AIRING ANIME
                if let anime = animeForCountdown, anime.shouldShowCountdown {
                    NextEpisodeCountdown(
                        nextAiringAt: anime.nextAiringAt,
                        nextEpisodeNumber: anime.nextAiringEpisode
                    )
                }

                if let genres = media.genres?.prefix(2) {
                    Text(genres.joined(separator: ", "))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.black.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .frame(width: cardWidth, height: 64, alignment: .top)
        }
        .frame(width: cardWidth, height: cardHeight, alignment: .top)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText())
        .accessibilityHint("Opens details")
        .contextMenu {
            Button(action: {
                KuroAccessibility.impactHaptic(.light)
                showAddToList = true
            }) {
                Label("Edit List", systemImage: "slider.horizontal.3")
            }

            Button(role: .destructive, action: {
                KuroAccessibility.impactHaptic(.light)
                Task { await supabaseService.removeFromList(mediaId: media.id, mediaType: mediaType) }
            }) {
                Label("Remove from List", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showDetail) {
            MediaDetailSheet(kind: media.kind, id: media.id)
        }
        .sheet(isPresented: $showAddToList) {
            AddToListSheet(media: media)
        }
    }

    private func accessibilityLabelText() -> Text {
        var parts: [String] = []
        parts.append(media.title)
        if !media.year.isEmpty { parts.append(media.year) }
        if let episodes = media.episodes, episodes > 0 { parts.append("\(episodes) episodes") }
        if let chapters = media.chapters, chapters > 0 { parts.append("\(chapters) chapters") }
        if let rating = media.rating, rating > 0 { parts.append(String(format: "Rating %.1f", rating)) }
        if let p = userProgress { parts.append("\(p.watched) of \(p.total) watched") }
        if let p = mangaProgress { parts.append("\(p.read) of \(p.total) read") }
        if let anime = animeForCountdown, anime.shouldShowCountdown, let countdown = supabaseService.countdownByAnimeId[anime.id] {
            parts.append("Next episode in \(countdown)")
        }
        return Text(parts.joined(separator: ", "))
    }
}
