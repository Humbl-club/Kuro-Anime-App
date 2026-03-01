// Editorial Collection View
// Vogue/Miu Miu inspired personal collection
// Refined grid, elegant filters, sophisticated presentation

import SwiftUI

struct EditorialCollectionView: View {
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(NetworkMonitor.self) private var networkMonitor
    @State private var selectedFilter: CollectionFilter = .all
    @State private var selectedSort: CollectionSort = .lastUpdated
    @State private var showListView = false
    @State private var didInitialLoad = false
    @State private var bannerMessage: String? = nil
    @State private var showSearch = false
    @State private var searchText = ""
    @State private var searchResults: [Media]?
    @State private var isEditMode = false
    @State private var selectedKeys: Set<String> = []
    @State private var showBatchStatusPicker = false
    @State private var selectedServiceFilter: String? = nil
    @State private var selectedLanguageFilter: String? = nil
    @State private var includeUnknownLanguage: Bool = true

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

    enum CollectionSort: String, CaseIterable {
        case lastUpdated = "LAST UPDATED"
        case titleAZ = "TITLE A-Z"
        case rating = "RATING"
        case progress = "PROGRESS"
    }

    private var items: [Media] { supabaseService.collectionFeedItems }

    private var displayItems: [Media] {
        var base = searchResults ?? items

        // Streaming service filter
        if FeatureFlags.shared.isStreamingAvailabilityV1Enabled, let slug = selectedServiceFilter {
            let available = supabaseService.collectionItemsAvailableOn(slug: slug)
            base = base.filter { available.contains("\($0.kind == .anime ? "ANIME" : "MANGA")-\($0.id)") }
        }

        // Language filter
        if FeatureFlags.shared.isStreamingAvailabilityV1Enabled, let lang = selectedLanguageFilter {
            let available = supabaseService.collectionItemsWithLanguage(lang: lang, includeUnknown: includeUnknownLanguage)
            base = base.filter { available.contains("\($0.kind == .anime ? "ANIME" : "MANGA")-\($0.id)") }
        }

        switch selectedSort {
        case .lastUpdated:
            return base
        case .titleAZ:
            return base.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .rating:
            return base.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        case .progress:
            return base.sorted {
                let p0 = supabaseService.userListProgress(mediaType: $0.kind.rawValue, mediaId: $0.id) ?? 0
                let p1 = supabaseService.userListProgress(mediaType: $1.kind.rawValue, mediaId: $1.id) ?? 0
                return p0 > p1
            }
        }
    }

    private var hasContent: Bool {
        !displayItems.isEmpty
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Editorial Filter Bar + Search Toggle
                HStack(spacing: 0) {
                    EditorialFilterBar(
                        filters: CollectionFilter.allCases,
                        selectedFilter: $selectedFilter
                    )

                    Button {
                        withAnimation(KuroAnimation.fast) {
                            showSearch.toggle()
                            if !showSearch {
                                searchText = ""
                                searchResults = nil
                            }
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(showSearch ? .black : .black.opacity(0.40))
                    }
                    .padding(.trailing, EditorialLayout.marginEditorial)
                }
                .padding(.vertical, 20)

                // Sort + View Toggle Bar
                HStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(CollectionSort.allCases, id: \.self) { sort in
                                Button {
                                    KuroAccessibility.impactHaptic(.light)
                                    withAnimation(KuroAnimation.fast) {
                                        selectedSort = sort
                                    }
                                } label: {
                                    Text(sort.rawValue)
                                        .font(.system(size: 9, weight: .medium))
                                        .tracking(1.0)
                                        .foregroundColor(selectedSort == sort ? .black : .black.opacity(0.35))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Sort by \(sort.rawValue)")
                                .accessibilityAddTraits(selectedSort == sort ? .isSelected : [])
                            }
                        }
                        .padding(.horizontal, EditorialLayout.marginEditorial)
                    }

                    // Streaming service filter pill
                    if FeatureFlags.shared.isStreamingAvailabilityV1Enabled,
                       !supabaseService.userStreamingServices.isEmpty {
                        Menu {
                            Button("ALL SERVICES") {
                                selectedServiceFilter = nil
                            }
                            ForEach(supabaseService.streamingServiceRegistry.filter({
                                supabaseService.userStreamingServices.contains($0.slug)
                            })) { svc in
                                Button(svc.display_name) {
                                    selectedServiceFilter = svc.slug
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "play.tv")
                                    .font(.system(size: 9, weight: .regular))
                                Text(selectedServiceFilter != nil
                                     ? (supabaseService.streamingServiceRegistry.first(where: { $0.slug == selectedServiceFilter })?.display_name ?? "SERVICE")
                                     : "SERVICE")
                                    .font(.system(size: 9, weight: .medium))
                                    .tracking(0.8)
                            }
                            .foregroundColor(selectedServiceFilter != nil ? .black : .black.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                    }

                    // Language filter pill
                    if FeatureFlags.shared.isStreamingAvailabilityV1Enabled {
                        Menu {
                            Button("ANY LANGUAGE") {
                                selectedLanguageFilter = nil
                            }
                            Button("ENGLISH") { selectedLanguageFilter = "en" }
                            Button("GERMAN") { selectedLanguageFilter = "de" }
                            Button("JAPANESE") { selectedLanguageFilter = "ja" }
                            Divider()
                            Toggle("Include unlabeled", isOn: $includeUnknownLanguage)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "globe")
                                    .font(.system(size: 9, weight: .regular))
                                Text(selectedLanguageFilter?.uppercased() ?? "LANG")
                                    .font(.system(size: 9, weight: .medium))
                                    .tracking(0.8)
                            }
                            .foregroundColor(selectedLanguageFilter != nil ? .black : .black.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 8)

                    Button {
                        KuroAccessibility.impactHaptic(.light)
                        withAnimation(KuroAnimation.fast) {
                            showListView.toggle()
                        }
                    } label: {
                        Image(systemName: showListView ? "square.grid.2x2" : "list.bullet")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.black.opacity(0.45))
                    }
                    .buttonStyle(.plain)

                    if hasContent {
                        Button {
                            KuroAccessibility.impactHaptic(.light)
                            withAnimation(KuroAnimation.fast) {
                                isEditMode.toggle()
                                if !isEditMode { selectedKeys.removeAll() }
                            }
                        } label: {
                            Text(isEditMode ? "DONE" : "EDIT")
                                .font(.kuroMicro(weight: .semibold))
                                .tracking(1.0)
                                .foregroundColor(isEditMode ? .black : .black.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 12)
                    }

                    Spacer().frame(width: EditorialLayout.marginEditorial)
                }
                .padding(.bottom, 12)

                // Search field
                if showSearch {
                    HStack(spacing: 8) {
                        TextField("Search your collection...", text: $searchText)
                            .font(.kuroBody())
                            .textFieldStyle(.plain)
                            .onSubmit { Task { await performSearch() } }

                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                searchResults = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.kuroTextTertiary)
                            }
                        }
                    }
                    .padding(.horizontal, EditorialLayout.marginEditorial)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Collection Grid
                ScrollView(.vertical, showsIndicators: false) {
                    if supabaseService.isCollectionLoading {
                        EditorialCollectionLoading()
                    } else if !hasContent {
                        if searchResults != nil {
                            // Empty search results state
                            VStack(spacing: 8) {
                                Text("NO RESULTS")
                                    .font(.kuroCaption())
                                    .tracking(1.5)
                                    .foregroundColor(.black.opacity(0.5))
                                Text("Try a different search term")
                                    .font(.kuroMicro(weight: .light))
                                    .foregroundColor(.black.opacity(0.4))
                            }
                            .padding(.top, 80)
                        } else if let msg = supabaseService.collectionErrorMessage, !msg.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: networkMonitor.isConnected ? "exclamationmark.triangle" : "wifi.slash")
                                    .font(.system(size: 32, weight: .light))
                                    .foregroundColor(.kuroTextTertiary)
                                Text(networkMonitor.isConnected ? "COULDN'T LOAD COLLECTION" : "YOU'RE OFFLINE")
                                    .font(.kuroCaption(weight: .medium))
                                    .tracking(1.6)
                                    .foregroundColor(.kuroTextSecondary)
                                Text(networkMonitor.isConnected ? msg : "Your collection will appear when you reconnect.")
                                    .font(.kuroBody())
                                    .foregroundColor(.kuroTextTertiary)
                                    .multilineTextAlignment(.center)
                                Button {
                                    Task {
                                        await supabaseService.fetchUserLists()
                                        await supabaseService.fetchCollectionFeed(status: nil)
                                    }
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
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            EditorialCollectionEmpty()
                        }
                    } else {
                        if !networkMonitor.isConnected {
                            Text("SHOWING CACHED DATA")
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.2)
                                .foregroundColor(.kuroTextTertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.bottom, 4)
                        }
                        if showListView {
                            CollectionListView(items: displayItems, isEditMode: isEditMode, selectedKeys: $selectedKeys)
                        } else {
                            EditorialCollectionGrid(items: displayItems, geometry: geometry, title: nil, isEditMode: isEditMode, selectedKeys: $selectedKeys)
                        }
                        if searchResults == nil {
                            KuroLoadMoreSentinel(
                                itemCount: items.count,
                                hasMore: supabaseService.hasMoreCollectionFeed,
                                isLoading: supabaseService.isLoadingMoreCollectionFeed
                            ) {
                                _ = await supabaseService.fetchNextCollectionFeedPage(limit: 90)
                            }
                        }
                    }
                }
                .scrollDisabled(false)
                .refreshable {
                    let hadContentBefore = hasContent
                    await supabaseService.fetchUserLists()
                    await supabaseService.fetchCollectionFeed(status: selectedFilter.listStatus)
                    if hadContentBefore, let msg = supabaseService.collectionErrorMessage, !msg.isEmpty {
                        showBanner("Couldn't refresh. Try again.")
                        return
                    }

                    let urls: [URL] = await MainActor.run {
                        Array(supabaseService.collectionFeedItems.prefix(80).compactMap { URL(string: $0.imageURL ?? "") })
                    }
                    if !urls.isEmpty {
                        Task { await ImagePipeline.shared.prefetch(urls: urls) }
                    }
                }
                .background(Color.kuroBackground)
                .overlay(alignment: .top) {
                    if let bannerMessage {
                        KuroTransientBanner(message: bannerMessage)
                            .padding(.top, 10)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

                // Batch action bar
                if isEditMode && !selectedKeys.isEmpty {
                    CollectionBatchBar(
                        count: selectedKeys.count,
                        onChangeStatus: { showBatchStatusPicker = true },
                        onRemove: { Task { await batchRemove() } }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .confirmationDialog(
            "Change status for \(selectedKeys.count) item\(selectedKeys.count == 1 ? "" : "s")",
            isPresented: $showBatchStatusPicker,
            titleVisibility: .visible
        ) {
            Button("Watching") { Task { await batchChangeStatus(.current) } }
            Button("Completed") { Task { await batchChangeStatus(.completed) } }
            Button("Planned") { Task { await batchChangeStatus(.planning) } }
            Button("Paused") { Task { await batchChangeStatus(.paused) } }
            Button("Cancel", role: .cancel) { }
        }
        .task {
            if !didInitialLoad {
                didInitialLoad = true
                await supabaseService.fetchUserLists()
                await supabaseService.fetchCollectionFeed(status: selectedFilter.listStatus)

                let urls: [URL] = await MainActor.run {
                    Array(supabaseService.collectionFeedItems.prefix(80).compactMap { URL(string: $0.imageURL ?? "") })
                }
                if !urls.isEmpty {
                    Task { await ImagePipeline.shared.prefetch(urls: urls) }
                }

                let feedItems: [(mediaType: String, mediaId: Int)] = await MainActor.run {
                    supabaseService.collectionFeedItems.prefix(80).map {
                        (mediaType: $0.kind == .anime ? "ANIME" : "MANGA", mediaId: $0.id)
                    }
                }
                if !feedItems.isEmpty {
                    if FeatureFlags.shared.isSocialActivityV1Enabled {
                        supabaseService.prefetchFriendCounts(items: feedItems)
                    }
                    if FeatureFlags.shared.isStreamingAvailabilityV1Enabled {
                        supabaseService.prefetchProviders(items: feedItems)
                    }
                }
            }
        }
        .onChange(of: selectedFilter) { _, _ in
            searchText = ""
            searchResults = nil
            Task {
                await supabaseService.fetchCollectionFeed(status: selectedFilter.listStatus)
            }
        }
    }

    @MainActor
    private func performSearch() async {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = nil
            return
        }

        // Try FM intent parsing first (no-op on unsupported devices)
        if let intent = await supabaseService.fmService.parseSearchIntent(query: searchText) {
            var filtered = items
            if let genre = intent.genre, !genre.isEmpty {
                filtered = filtered.filter { media in
                    media.genres?.contains(where: { $0.localizedCaseInsensitiveContains(genre) }) == true
                }
            }
            if let status = intent.status, !status.isEmpty {
                filtered = filtered.filter { $0.statusRaw?.uppercased() == status.uppercased() }
            }
            if let yearFrom = intent.yearFrom {
                filtered = filtered.filter { media in
                    guard let y = Int(media.year) else { return true }
                    return y >= yearFrom
                }
            }
            if let yearTo = intent.yearTo {
                filtered = filtered.filter { media in
                    guard let y = Int(media.year) else { return true }
                    return y <= yearTo
                }
            }
            if !intent.keywords.isEmpty {
                filtered = filtered.filter { media in
                    intent.keywords.contains(where: { keyword in
                        media.title.localizedCaseInsensitiveContains(keyword)
                    })
                }
            }
            searchResults = filtered
        } else {
            // Fallback: simple substring match
            searchResults = items.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
    }

    @MainActor
    private func batchChangeStatus(_ status: ListStatus) async {
        let selected = selectedMediaItems()
        guard !selected.isEmpty else { return }
        for media in selected {
            await supabaseService.upsertUserListEntry(
                mediaId: media.id,
                mediaType: media.kind.rawValue,
                status: status,
                progress: supabaseService.userListProgress(mediaType: media.kind.rawValue, mediaId: media.id) ?? 0,
                rating: nil,
                notes: nil
            )
        }
        KuroAccessibility.successHaptic()
        showBanner("Updated \(selected.count) item\(selected.count == 1 ? "" : "s")")
        withAnimation(KuroAnimation.fast) {
            selectedKeys.removeAll()
            isEditMode = false
        }
        await supabaseService.fetchCollectionFeed(status: selectedFilter.listStatus)
    }

    @MainActor
    private func batchRemove() async {
        let selected = selectedMediaItems()
        guard !selected.isEmpty else { return }
        for media in selected {
            supabaseService.toggleInCollection(mediaId: media.id, mediaType: media.kind.rawValue)
        }
        KuroAccessibility.successHaptic()
        showBanner("Removed \(selected.count) item\(selected.count == 1 ? "" : "s")")
        withAnimation(KuroAnimation.fast) {
            selectedKeys.removeAll()
            isEditMode = false
        }
    }

    private func selectedMediaItems() -> [Media] {
        displayItems.filter { selectedKeys.contains($0.stableKey) }
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
                    .foregroundColor(isSelected ? .black : .black.opacity(0.4))

                // Underline indicator
                Rectangle()
                    .fill(Color.black)
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
    var onExploreDiscover: (() -> Void)? = nil

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

            if let onExploreDiscover {
                Button {
                    KuroAccessibility.impactHaptic(.light)
                    onExploreDiscover()
                } label: {
                    Text("EXPLORE DISCOVER")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.06))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
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
                            .fill(Color.black.opacity(0.05))
                            .frame(width: cardWidth, height: imageHeight)
                    @unknown default:
                        EmptyView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Type badge (helps when the feed is mixed anime + manga).
                Text(media.kind == .anime ? "ANIME" : "MANGA")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(.black.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.92))
                    )
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

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
                    if isInCollection && !isEditMode {
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
                .padding(6)

                // Edit mode selection overlay
                if isEditMode {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(isSelected ? 0.25 : 0.0))
                        .allowsHitTesting(false)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(isSelected ? .black.opacity(0.80) : .black.opacity(0.40))
                        .background(
                            Circle()
                                .fill(Color.white.opacity(isSelected ? 0.92 : 0.70))
                                .frame(width: 26, height: 26)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(8)
                }
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

                // PROGRESS DISPLAY (anime or manga) with +1 button
                if let progress = userProgress {
                    HStack(spacing: 6) {
                        Text("\(progress.watched)/\(progress.total) WATCHED")
                            .font(.system(size: 10, weight: .medium))
                            .tracking(0.5)
                            .foregroundColor(.black.opacity(0.7))
                        if canIncrementProgress {
                            Button {
                                KuroAccessibility.impactHaptic(.light)
                                Task { await supabaseService.incrementProgress(mediaId: media.id, mediaType: mediaType) }
                            } label: {
                                Text("+1 EP")
                                    .font(.system(size: 9, weight: .semibold))
                                    .tracking(0.8)
                                    .foregroundColor(.black.opacity(0.55))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(Color.black.opacity(0.06))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if let progress = mangaProgress {
                    HStack(spacing: 6) {
                        Text("\(progress.read)/\(progress.total) READ")
                            .font(.system(size: 10, weight: .medium))
                            .tracking(0.5)
                            .foregroundColor(.black.opacity(0.7))
                        if canIncrementProgress {
                            Button {
                                KuroAccessibility.impactHaptic(.light)
                                Task { await supabaseService.incrementProgress(mediaId: media.id, mediaType: mediaType) }
                            } label: {
                                Text("+1 CH")
                                    .font(.system(size: 9, weight: .semibold))
                                    .tracking(0.8)
                                    .foregroundColor(.black.opacity(0.55))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(Color.black.opacity(0.06))
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
                    .fill(Color.black.opacity(0.06))
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
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(isSelected ? .black.opacity(0.80) : .black.opacity(0.30))
                }

                KuroCachedAsyncImage(url: URL(string: media.imageURL ?? ""), maxPixelSize: 120) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 56).clipped()
                    case .failure, .empty:
                        Rectangle().fill(Color.black.opacity(0.05))
                            .frame(width: 40, height: 56)
                    @unknown default:
                        EmptyView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(media.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.black)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(statusLabel)
                            .font(.system(size: 9, weight: .medium))
                            .tracking(0.8)
                            .foregroundColor(.black.opacity(0.55))

                        if let progressText {
                            Text(progressText)
                                .font(.system(size: 9, weight: .regular))
                                .foregroundColor(.black.opacity(0.4))
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
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.8)
                            .foregroundColor(.black.opacity(0.55))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(Color.black.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }

                if !isEditMode {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.black.opacity(0.25))
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
private struct CollectionBatchBar: View {
    let count: Int
    let onChangeStatus: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text("\(count) SELECTED")
                .font(.kuroMicro(weight: .semibold))
                .tracking(1.0)
                .foregroundColor(.black.opacity(0.60))

            Spacer(minLength: 0)

            Button {
                KuroAccessibility.impactHaptic(.light)
                onChangeStatus()
            } label: {
                Text("STATUS")
                    .font(.kuroMicro(weight: .semibold))
                    .tracking(1.0)
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(Color.black.opacity(0.06))
                    )
                    .overlay(
                        Capsule().stroke(Color.black.opacity(0.10), lineWidth: 0.5)
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
                        .fill(Color.black.opacity(0.02))
                )
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: -4)
        )
    }
}
