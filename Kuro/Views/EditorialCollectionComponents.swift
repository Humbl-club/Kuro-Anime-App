import SwiftUI

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
        .kuroSwipeExclusionZone()
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
                    .foregroundColor(isSelected ? .kuroBlack : .kuroBlack40)

                // Underline indicator
                Rectangle()
                    .fill(Color.kuroBlack)
                    .frame(height: 1.5)
                    .opacity(isSelected ? 1.0 : 0.0)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("\(title) filter")
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
    var isEditMode: Bool = false
    @Binding var selectedKeys: Set<String>

    init(items: [any MediaDisplayable], geometry: GeometryProxy, title: String? = nil, isEditMode: Bool = false, selectedKeys: Binding<Set<String>> = .constant([])) {
        self.items = items
        self.geometry = geometry
        self.title = title
        self.isEditMode = isEditMode
        self._selectedKeys = selectedKeys
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Optional section title
            if let title = title {
                Text(title)
                    .font(.kuroBody(weight: .semibold))
                    .tracking(1.0)
                    .foregroundColor(.kuroBlack60)
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
                ForEach(items, id: \.stableKey) { media in
                    CollectionGridCard(
                        media: media,
                        cardWidth: cardWidth,
                        cardHeight: totalCardHeight,
                        isEditMode: isEditMode,
                        isSelected: selectedKeys.contains(media.stableKey)
                    ) {
                        let key = media.stableKey
                        if selectedKeys.contains(key) {
                            selectedKeys.remove(key)
                        } else {
                            selectedKeys.insert(key)
                        }
                    }
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
                        .fill(Color.kuroBlack02)
                        .aspectRatio(EditorialLayout.standardAspectRatio, contentMode: .fit)

                    VStack(alignment: .leading, spacing: 6) {
                        Rectangle()
                            .fill(Color.kuroBlack06)
                            .frame(height: 10)

                        Rectangle()
                            .fill(Color.kuroBlack04)
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
    var onExploreDiscover: (() -> Void)? = nil
    var onExploreConcierge: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "tray")
                    .font(.kuroCustom(48, weight: .ultraLight, relativeTo: .largeTitle))
                    .foregroundColor(.kuroBlack15)

                VStack(spacing: 8) {
                    Text("YOUR COLLECTION IS EMPTY")
                        .font(.kuroBody(weight: .semibold))
                        .tracking(1.0)
                        .foregroundColor(.kuroBlack40)

                    Text("Add anime or manga from Discover")
                        .font(.kuroBody(weight: .regular))
                        .foregroundColor(.kuroBlack45)
                        .multilineTextAlignment(.center)
                }
            }

            VStack(spacing: 10) {
                if let onExploreDiscover {
                    Button {
                        KuroAccessibility.impactHaptic(.light)
                        onExploreDiscover()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.grid.2x2")
                                .font(.kuroCaption(weight: .medium))
                            Text("EXPLORE DISCOVER")
                                .font(.kuroCaption(weight: .semibold))
                                .tracking(1.5)
                        }
                        .foregroundColor(.kuroBlack)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(Color.kuroBlack06)
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.kuroBlack12, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let onExploreConcierge {
                    Button {
                        KuroAccessibility.impactHaptic(.light)
                        onExploreConcierge()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.kuroCaption(weight: .medium))
                            Text("TRY THE CONCIERGE")
                                .font(.kuroCaption(weight: .semibold))
                                .tracking(1.5)
                        }
                        .foregroundColor(.kuroBlack)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(Color.kuroBlack06)
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.kuroBlack12, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
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
                    text: "Checkmark shows collected items"
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
                .font(.kuroBody(weight: .light))
                .foregroundColor(.kuroBlack40)
                .frame(width: 24)

            Text(text)
                .font(.kuroBody(weight: .regular))
                .foregroundColor(.kuroBlack60)

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
    var isEditMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)? = nil
    @State private var showDetail = false
    @State private var showAddToList = false
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    private var upcomingAiring: SupabaseService.UpcomingAiring? {
        guard media.kind == .anime else { return nil }
        return supabaseService.upcomingAirings.first(where: { $0.anime_id == media.id })
    }

    private var shouldShowCountdown: Bool {
        guard media.kind == .anime else { return false }
        guard media.statusRaw == "RELEASING" else { return false }
        guard let at = upcomingAiring?.next_airing_at else { return false }
        return at > Date()
    }

    private var mediaType: String {
        media.kind.rawValue
    }

    private var isInCollection: Bool {
        supabaseService.isInCollection(mediaId: media.id, mediaType: mediaType)
    }

    private var userEntry: UserList? {
        supabaseService.userListEntry(mediaType: mediaType, mediaId: media.id)
    }

    private var canIncrementProgress: Bool {
        guard let entry = userEntry, entry.status == .current else { return false }
        let total = media.episodes ?? media.chapters ?? 0
        return total == 0 || entry.progress < total
    }

    private var incrementLabel: String {
        media.kind == .anime ? "+1 EP" : "+1 CH"
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
            if isEditMode {
                KuroAccessibility.impactHaptic(.light)
                onToggleSelection?()
                return
            }
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        }) {
            VStack(alignment: .leading, spacing: 8) {
            // Image with score - FIXED HEIGHT
            let imageHeight = floor(cardWidth / 0.7)

            ZStack(alignment: .topTrailing) {
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
                            .fill(Color.kuroBlack05)
                            .frame(width: cardWidth, height: imageHeight)
                    @unknown default:
                        EmptyView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Type badge (helps when the feed is mixed anime + manga).
                Text(media.kind == .anime ? "ANIME" : "MANGA")
                    .font(.kuroMicro(weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(.kuroBlack70)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.kuroWhite92)
                    )
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                VStack(alignment: .trailing, spacing: 6) {
                    // Score badge
                    if let rating = media.rating, rating > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.kuroCustom(8, relativeTo: .caption2))
                            Text(String(format: "%.1f", rating))
                                .font(.kuroCustom(10, weight: .semibold, relativeTo: .caption1))
                        }
                        .foregroundColor(.kuroWhite)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.kuroBlack75)
                        )
                    }

                    // Collection indicator
                    if isInCollection && !isEditMode {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.kuroCustom(16, relativeTo: .body))
                            .foregroundColor(.kuroTextSecondary)
                            .background(
                                Circle()
                                    .fill(Color.kuroWhite)
                                    .frame(width: 18, height: 18)
                            )
                    }
                }
                .padding(6)

                // Edit mode selection overlay
                if isEditMode {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.kuroBlack.opacity(isSelected ? 0.25 : 0.0))
                        .allowsHitTesting(false)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.kuroCustom(22, weight: .regular, relativeTo: .title3))
                        .foregroundColor(isSelected ? .kuroBlack80 : .kuroBlack40)
                        .background(
                            Circle()
                                .fill(Color.kuroWhite.opacity(isSelected ? 0.92 : 0.70))
                                .frame(width: 26, height: 26)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(8)
                }
            }

            // Title and info - FIXED HEIGHT
            VStack(alignment: .leading, spacing: 4) {
                Text(media.title)
                    .font(.kuroBody(weight: .medium))
                    .foregroundColor(.kuroBlack)
                    .lineLimit(2)
                    .frame(height: 36, alignment: .top)

                HStack(spacing: 4) {
                    Text(media.year)
                        .font(.kuroCaption(weight: .regular))
                        .foregroundColor(.kuroBlack60)

                    if let episodes = media.episodes, episodes > 0 {
                        Text("·")
                            .foregroundColor(.kuroBlack40)
                        Text("\(episodes) eps")
                            .font(.kuroCaption(weight: .regular))
                            .foregroundColor(.kuroBlack60)
                    } else if let chapters = media.chapters, chapters > 0 {
                        Text("·")
                            .foregroundColor(.kuroBlack40)
                        Text("\(chapters) ch")
                            .font(.kuroCaption(weight: .regular))
                            .foregroundColor(.kuroBlack60)
                    }
                }

                // PROGRESS DISPLAY (anime or manga) with +1 button
                if let progress = userProgress {
                    HStack(spacing: 6) {
                        Text("\(progress.watched)/\(progress.total) WATCHED")
                            .font(.kuroCaption(weight: .medium))
                            .tracking(0.5)
                            .foregroundColor(.kuroBlack70)
                        if canIncrementProgress {
                            Button {
                                KuroAccessibility.impactHaptic(.light)
                                Task { await supabaseService.incrementProgress(mediaId: media.id, mediaType: mediaType) }
                            } label: {
                                Text("+1 EP")
                                    .font(.kuroMicro(weight: .semibold))
                                    .tracking(0.8)
                                    .foregroundColor(.kuroTextSecondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(Color.kuroBlack06)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if let progress = mangaProgress {
                    HStack(spacing: 6) {
                        Text("\(progress.read)/\(progress.total) READ")
                            .font(.kuroCaption(weight: .medium))
                            .tracking(0.5)
                            .foregroundColor(.kuroBlack70)
                        if canIncrementProgress {
                            Button {
                                KuroAccessibility.impactHaptic(.light)
                                Task { await supabaseService.incrementProgress(mediaId: media.id, mediaType: mediaType) }
                            } label: {
                                Text("+1 CH")
                                    .font(.kuroMicro(weight: .semibold))
                                    .tracking(0.8)
                                    .foregroundColor(.kuroTextSecondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(Color.kuroBlack06)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // COUNTDOWN TIMER FOR AIRING ANIME (via upcomingAirings)
                if shouldShowCountdown {
                    NextEpisodeCountdown(
                        nextAiringAt: upcomingAiring?.next_airing_at,
                        nextEpisodeNumber: upcomingAiring?.next_episode_number
                    )
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
            if canIncrementProgress {
                Button(action: {
                    KuroAccessibility.impactHaptic(.light)
                    Task { await supabaseService.incrementProgress(mediaId: media.id, mediaType: mediaType) }
                }) {
                    Label(incrementLabel, systemImage: "plus.circle")
                }
            }

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
        if shouldShowCountdown, let countdown = supabaseService.countdownByAnimeId[media.id] {
            parts.append("Next episode in \(countdown)")
        }
        return Text(parts.joined(separator: ", "))
    }
}

// MARK: - Collection List View (compact rows)
struct CollectionListView: View {
    let items: [any MediaDisplayable]
    var isEditMode: Bool = false
    @Binding var selectedKeys: Set<String>

    init(items: [any MediaDisplayable], isEditMode: Bool = false, selectedKeys: Binding<Set<String>> = .constant([])) {
        self.items = items
        self.isEditMode = isEditMode
        self._selectedKeys = selectedKeys
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(items, id: \.stableKey) { media in
                CollectionListRow(
                    media: media,
                    isEditMode: isEditMode,
                    isSelected: selectedKeys.contains(media.stableKey)
                ) {
                    let key = media.stableKey
                    if selectedKeys.contains(key) {
                        selectedKeys.remove(key)
                    } else {
                        selectedKeys.insert(key)
                    }
                }
                Rectangle()
                    .fill(Color.kuroBlack06)
                    .frame(height: 0.5)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 32)
    }
}

// MARK: - Collection List Row
private struct CollectionListRow: View {
    let media: any MediaDisplayable
    var isEditMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)? = nil
    @State private var showDetail = false
    @Environment(SupabaseService.self) private var supabaseService

    private var mediaType: String { media.kind.rawValue }

    private var userEntry: UserList? {
        supabaseService.userListEntry(mediaType: mediaType, mediaId: media.id)
    }

    private var statusLabel: String {
        guard let entry = userEntry else { return "" }
        switch entry.status {
        case .current: return media.kind == .anime ? "WATCHING" : "READING"
        case .planning: return "PLANNED"
        case .completed: return "COMPLETED"
        case .dropped: return "DROPPED"
        case .paused: return "PAUSED"
        case .repeating: return media.kind == .anime ? "REWATCHING" : "REREADING"
        }
    }

    private var progressText: String? {
        guard let entry = userEntry, entry.progress > 0 else { return nil }
        let total = media.episodes ?? media.chapters ?? 0
        let unit = media.kind == .anime ? "ep" : "ch"
        if total > 0 {
            return "\(entry.progress)/\(total) \(unit)"
        }
        return "\(entry.progress) \(unit)"
    }

    private var canIncrement: Bool {
        guard let entry = userEntry, entry.status == .current else { return false }
        let total = media.episodes ?? media.chapters ?? 0
        return total == 0 || entry.progress < total
    }

    var body: some View {
        Button {
            if isEditMode {
                KuroAccessibility.impactHaptic(.light)
                onToggleSelection?()
                return
            }
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        } label: {
            HStack(spacing: 12) {
                // Edit mode checkbox
                if isEditMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.kuroCustom(20, weight: .regular, relativeTo: .title3))
                        .foregroundColor(isSelected ? .kuroBlack80 : .kuroBlack30)
                }

                KuroCachedAsyncImage(url: URL(string: media.imageURL ?? ""), maxPixelSize: 120) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 56).clipped()
                    case .failure, .empty:
                        Rectangle().fill(Color.kuroBlack05)
                            .frame(width: 40, height: 56)
                    @unknown default:
                        EmptyView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(media.title)
                        .font(.kuroBody(weight: .medium))
                        .foregroundColor(.kuroBlack)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(statusLabel)
                            .font(.kuroMicro(weight: .medium))
                            .tracking(0.8)
                            .foregroundColor(.kuroTextSecondary)

                        if let progressText {
                            Text(progressText)
                                .font(.kuroMicro(weight: .regular))
                                .foregroundColor(.kuroBlack40)
                        }
                    }
                }

                Spacer(minLength: 0)

                if !isEditMode && canIncrement {
                    Button {
                        KuroAccessibility.impactHaptic(.light)
                        Task { await supabaseService.incrementProgress(mediaId: media.id, mediaType: mediaType) }
                    } label: {
                        Text(media.kind == .anime ? "+1 EP" : "+1 CH")
                            .font(.kuroMicro(weight: .semibold))
                            .tracking(0.8)
                            .foregroundColor(.kuroTextSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(Color.kuroBlack06)
                            )
                    }
                    .buttonStyle(.plain)
                }

                if !isEditMode {
                    Image(systemName: "chevron.right")
                        .font(.kuroCaption(weight: .regular))
                        .foregroundColor(.kuroBlack30)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(media.title)\(statusLabel.isEmpty ? "" : ", \(statusLabel)")\(progressText.map { ", \($0)" } ?? "")")
        .accessibilityHint("Opens details")
        .sheet(isPresented: $showDetail) {
            MediaDetailSheet(kind: media.kind, id: media.id)
        }
    }
}

// MARK: - Batch Action Bar
struct CollectionBatchBar: View {
    let count: Int
    let onChangeStatus: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text("\(count) SELECTED")
                .font(.kuroMicro(weight: .semibold))
                .tracking(1.0)
                .foregroundColor(.kuroBlack60)

            Spacer(minLength: 0)

            Button {
                KuroAccessibility.impactHaptic(.light)
                onChangeStatus()
            } label: {
                Text("STATUS")
                    .font(.kuroMicro(weight: .semibold))
                    .tracking(1.0)
                    .foregroundColor(.kuroBlack)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(Color.kuroBlack06)
                    )
                    .overlay(
                        Capsule().stroke(Color.kuroBlack12, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)

            Button {
                KuroAccessibility.impactHaptic(.medium)
                onRemove()
            } label: {
                Text("REMOVE")
                    .font(.kuroMicro(weight: .semibold))
                    .tracking(1.0)
                    .foregroundColor(.red.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(Color.red.opacity(0.06))
                    )
                    .overlay(
                        Capsule().stroke(Color.red.opacity(0.12), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(Color.kuroBlack02)
                )
                .shadow(color: Color.kuroBlack08, radius: 10, x: 0, y: -4)
        )
    }
}
