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
    @State private var selectedMediaType: MediaTypeFilter = .all
    @State private var selectedVerdictFilter: CompletedVerdictFilter = .all
    @State private var selectedServiceFilter: String? = nil
    @State private var selectedLanguageFilter: String? = nil
    @State private var includeUnknownLanguage: Bool = true
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var showBatchRemoveConfirm = false

    enum CollectionFilter: String, CaseIterable {
        case all = "ALL"
        case watching = "WATCHING"
        case completed = "COMPLETED"
        case planned = "PLANNED"
        case paused = "PAUSED"
        case dropped = "DROPPED"

        var displayName: String { rawValue }

        var listStatus: ListStatus? {
            switch self {
            case .all: return nil
            case .watching: return .current
            case .completed: return .completed
            case .planned: return .planning
            case .paused: return .paused
            case .dropped: return .dropped
            }
        }
    }

    enum MediaTypeFilter: String, CaseIterable {
        case all = "ALL"
        case anime = "ANIME"
        case manga = "MANGA"
    }

    enum CompletedVerdictFilter: String, CaseIterable {
        case all = "ALL"
        case unsorted = "UNSORTED"
        case masterpiece = "MASTERPIECE"
        case okay = "OKAY"
        case bad = "BAD"

        func displayName(isGerman: Bool) -> String {
            switch self {
            case .all: return isGerman ? "Alle" : "All"
            case .unsorted: return isGerman ? "Ohne Urteil" : "Unsorted"
            case .masterpiece: return isGerman ? "Meisterwerk" : "Masterpiece"
            case .okay: return "Okay"
            case .bad: return isGerman ? "Schwach" : "Bad"
            }
        }

        var verdict: Verdict? {
            switch self {
            case .all, .unsorted: return nil
            case .masterpiece: return .masterpiece
            case .okay: return .okay
            case .bad: return .bad
            }
        }
    }

    enum CollectionSort: String, CaseIterable {
        case lastUpdated = "LAST UPDATED"
        case titleAZ = "TITLE A-Z"
        case rating = "RATING"
        case myRating = "MY RATING"
        case progress = "PROGRESS"
    }

    private var items: [Media] { supabaseService.collectionFeedItems }
    private var isGermanLocale: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("de") == true
    }

    private var displayItems: [Media] {
        var base = searchResults ?? items

        // Media type filter
        switch selectedMediaType {
        case .all: break
        case .anime: base = base.filter { $0.kind == .anime }
        case .manga: base = base.filter { $0.kind == .manga }
        }

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

        if selectedFilter == .completed {
            base = base.filter { media in
                guard let entry = supabaseService.userListEntry(mediaType: media.kind.rawValue, mediaId: media.id) else {
                    return false
                }
                switch selectedVerdictFilter {
                case .all:
                    return true
                case .unsorted:
                    return entry.verdict == nil
                case .masterpiece, .okay, .bad:
                    return entry.verdict == selectedVerdictFilter.verdict
                }
            }
        }

        switch selectedSort {
        case .lastUpdated:
            return base
        case .titleAZ:
            return base.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .rating:
            return base.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        case .myRating:
            return base.sorted {
                (supabaseService.userListEntry(mediaType: $0.kind.rawValue, mediaId: $0.id)?.score ?? 0) >
                (supabaseService.userListEntry(mediaType: $1.kind.rawValue, mediaId: $1.id)?.score ?? 0)
            }
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

    private var statusCounts: [(label: String, count: Int)] {
        var counts: [String: Int] = [:]
        for media in items {
            if let entry = supabaseService.userListEntry(mediaType: media.kind.rawValue, mediaId: media.id) {
                let label: String
                switch entry.status {
                case .current: label = "WATCHING"
                case .completed: label = "COMPLETED"
                case .planning: label = "PLANNED"
                case .paused: label = "PAUSED"
                case .dropped: label = "DROPPED"
                case .repeating: label = "REWATCHING"
                }
                counts[label, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.map { (label: $0.key, count: $0.value) }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                statusSummarySection
                collectionHeaderSection
                searchFieldSection
                collectionContent(geometry: geometry)
                batchActionBar
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
        .confirmationDialog(
            "Remove \(selectedKeys.count) item\(selectedKeys.count == 1 ? "" : "s") from collection?",
            isPresented: $showBatchRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task { await confirmBatchRemove() }
            }
            Button("Cancel", role: .cancel) { }
        }
        .task {
            if !didInitialLoad {
                didInitialLoad = true
                await supabaseService.fetchUserLists()
                await supabaseService.fetchCollectionFeed(status: selectedFilter.listStatus)
                await prefetchCollectionMetadata(for: Array(supabaseService.collectionFeedItems.prefix(80)))
            }
        }
        .onChange(of: selectedFilter) { _, _ in
            searchText = ""
            searchResults = nil
            selectedVerdictFilter = .all
            Task {
                await supabaseService.fetchCollectionFeed(status: selectedFilter.listStatus)
            }
        }
    }

    private var completedUnsortedCount: Int {
        items.filter { media in
            guard let entry = supabaseService.userListEntry(mediaType: media.kind.rawValue, mediaId: media.id) else {
                return false
            }
            return entry.status == .completed && entry.verdict == nil
        }.count
    }

    @ViewBuilder
    private var statusSummarySection: some View {
        if !items.isEmpty && !statusCounts.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(statusCounts.enumerated()), id: \.element.label) { index, item in
                    if index > 0 {
                        Text(" · ")
                            .font(.kuroMicro(weight: .medium))
                            .foregroundColor(.kuroTextTertiary)
                    }
                    Text("\(item.count) \(item.label)")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.0)
                        .foregroundColor(.kuroTextSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    private var collectionHeaderSection: some View {
        VStack(spacing: 0) {
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

            collectionControlsSection
                .padding(.bottom, 12)

            if selectedFilter == .completed {
                completedVerdictFilterSection
                    .padding(.bottom, 12)
            }
        }
    }

    private var completedVerdictFilterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(CompletedVerdictFilter.allCases, id: \.self) { filter in
                        Button {
                            KuroAccessibility.impactHaptic(.light)
                            withAnimation(KuroAnimation.fast) {
                                selectedVerdictFilter = filter
                            }
                        } label: {
                            Text(filter.displayName(isGerman: isGermanLocale).uppercased())
                                .font(.system(size: 9, weight: .medium))
                                .tracking(1.0)
                                .foregroundColor(selectedVerdictFilter == filter ? .black : .black.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, EditorialLayout.marginEditorial)
            }

            if completedUnsortedCount > 0 {
                Text(
                    isGermanLocale
                        ? "\(completedUnsortedCount) fertige Titel haben noch kein Urteil."
                        : "\(completedUnsortedCount) completed titles still need a verdict."
                )
                .font(.kuroMicro(weight: .medium))
                .foregroundColor(.kuroTextSecondary)
                .padding(.horizontal, EditorialLayout.marginEditorial)
            }
        }
    }

    private var collectionControlsSection: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(CollectionSort.allCases, id: \.self) { sort in
                        sortButton(for: sort)
                    }
                }
                .padding(.horizontal, EditorialLayout.marginEditorial)
            }

            mediaTypeMenu
            serviceFilterMenu
            languageFilterMenu

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
                        if !isEditMode {
                            selectedKeys.removeAll()
                        }
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
    }

    private func sortButton(for sort: CollectionSort) -> some View {
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

    private var mediaTypeMenu: some View {
        Menu {
            ForEach(MediaTypeFilter.allCases, id: \.self) { type in
                Button(type.rawValue) {
                    selectedMediaType = type
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 9, weight: .regular))
                Text(selectedMediaType == .all ? "TYPE" : selectedMediaType.rawValue)
                    .font(.system(size: 9, weight: .medium))
                    .tracking(0.8)
            }
            .foregroundColor(selectedMediaType != .all ? .black : .black.opacity(0.35))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var serviceFilterMenu: some View {
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
    }

    @ViewBuilder
    private var languageFilterMenu: some View {
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
    }

    @ViewBuilder
    private var searchFieldSection: some View {
        if showSearch {
            HStack(spacing: 8) {
                TextField("Search your collection...", text: $searchText)
                    .font(.kuroBody())
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await performSearch() } }
                    .onChange(of: searchText) { _, newValue in
                        searchDebounceTask?.cancel()
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            searchResults = nil
                            return
                        }
                        searchDebounceTask = Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            guard !Task.isCancelled else { return }
                            searchResults = items.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
                        }
                    }

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
    }

    private func collectionContent(geometry: GeometryProxy) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            collectionScrollContent(geometry: geometry)
        }
        .scrollDisabled(false)
        .refreshable {
            await refreshCollection()
        }
        .background(Color.kuroBackground)
        .overlay(alignment: .top) {
            if let bannerMessage {
                KuroTransientBanner(message: bannerMessage)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private func collectionScrollContent(geometry: GeometryProxy) -> some View {
        if supabaseService.isCollectionLoading {
            EditorialCollectionLoading()
        } else if !hasContent {
            collectionEmptyState
        } else {
            collectionLoadedContent(geometry: geometry)
        }
    }

    @ViewBuilder
    private var collectionEmptyState: some View {
        if searchResults != nil {
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
            collectionErrorState(message: msg)
        } else {
            EditorialCollectionEmpty(
                onExploreDiscover: {
                    if let url = URL(string: "kuro://discover") {
                        UIApplication.shared.open(url)
                    }
                },
                onExploreConcierge: {
                    if let url = URL(string: "kuro://concierge") {
                        UIApplication.shared.open(url)
                    }
                }
            )
        }
    }

    private func collectionErrorState(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: networkMonitor.isConnected ? "exclamationmark.triangle" : "wifi.slash")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.kuroTextTertiary)
            Text(networkMonitor.isConnected ? "COULDN'T LOAD COLLECTION" : "YOU'RE OFFLINE")
                .font(.kuroCaption(weight: .medium))
                .tracking(1.6)
                .foregroundColor(.kuroTextSecondary)
            Text(networkMonitor.isConnected ? message : "Your collection will appear when you reconnect.")
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
    }

    @ViewBuilder
    private func collectionLoadedContent(geometry: GeometryProxy) -> some View {
        if !networkMonitor.isConnected {
            Text("SHOWING CACHED DATA")
                .font(.kuroMicro(weight: .medium))
                .tracking(1.2)
                .foregroundColor(.kuroTextTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 4)
        }

        if showListView {
            CollectionListView(
                items: displayItems,
                isEditMode: isEditMode,
                onQuickActionMessage: { message in showBanner(message) },
                selectedKeys: $selectedKeys
            )
        } else {
            EditorialCollectionGrid(
                items: displayItems,
                geometry: geometry,
                title: nil,
                isEditMode: isEditMode,
                onQuickActionMessage: { message in showBanner(message) },
                selectedKeys: $selectedKeys
            )
        }

        if searchResults == nil {
            collectionPaginationSentinel
        }
    }

    private var collectionPaginationSentinel: some View {
        KuroLoadMoreSentinel(
            itemCount: items.count,
            hasMore: supabaseService.hasMoreCollectionFeed,
            isLoading: supabaseService.isLoadingMoreCollectionFeed
        ) {
            let countBefore = supabaseService.collectionFeedItems.count
            let loaded = await supabaseService.fetchNextCollectionFeedPage(limit: 90)
            guard loaded else { return }
            let newItems = Array(supabaseService.collectionFeedItems.dropFirst(countBefore))
            await prefetchCollectionMetadata(for: newItems)
        }
    }

    @ViewBuilder
    private var batchActionBar: some View {
        if isEditMode && !selectedKeys.isEmpty {
            CollectionBatchBar(
                count: selectedKeys.count,
                onChangeStatus: { showBatchStatusPicker = true },
                onRemove: { batchRemove() }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
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
    private func refreshCollection() async {
        let hadContentBefore = hasContent
        await supabaseService.fetchUserLists()
        await supabaseService.fetchCollectionFeed(status: selectedFilter.listStatus)
        if hadContentBefore, let msg = supabaseService.collectionErrorMessage, !msg.isEmpty {
            showBanner("Couldn't refresh. Try again.")
            return
        }
        await prefetchCollectionMetadata(for: Array(supabaseService.collectionFeedItems.prefix(80)))
    }

    @MainActor
    private func prefetchCollectionMetadata(for mediaItems: [Media]) async {
        let urls = mediaItems.compactMap { URL(string: $0.imageURL ?? "") }
        if !urls.isEmpty {
            Task { await ImagePipeline.shared.prefetch(urls: urls) }
        }

        let feedItems = mediaItems.map {
            (mediaType: $0.kind == .anime ? "ANIME" : "MANGA", mediaId: $0.id)
        }

        guard !feedItems.isEmpty else { return }

        if FeatureFlags.shared.isSocialActivityV1Enabled {
            supabaseService.prefetchFriendCounts(items: feedItems)
        }
        if FeatureFlags.shared.isStreamingAvailabilityV1Enabled {
            let preferredAudio = Locale.current.identifier.lowercased().hasPrefix("de") ? "de" : "en"
            supabaseService.prefetchProviderAvailabilityV2(
                items: feedItems,
                preferredAudioLang: preferredAudio,
                preferredSubLang: nil,
                includeUnknown: true
            )
            supabaseService.prefetchProviders(items: feedItems)
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
                notes: nil,
                verdict: supabaseService.userListEntry(mediaType: media.kind.rawValue, mediaId: media.id)?.verdict
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

    private func batchRemove() {
        showBatchRemoveConfirm = true
    }

    @MainActor
    private func confirmBatchRemove() async {
        let selected = selectedMediaItems()
        guard !selected.isEmpty else { return }
        var removedCount = 0
        for media in selected {
            let type = media.kind.rawValue.lowercased()
            let removed = await supabaseService.removeFromList(
                mediaId: media.id,
                mediaType: type,
                skipRefresh: true
            )
            if removed { removedCount += 1 }
        }
        // Single refresh after all deletes (instead of 3 fetches per item)
        await supabaseService.fetchUserLists()
        await supabaseService.fetchCollectionItems(status: selectedFilter.listStatus)
        await supabaseService.fetchCollectionFeed(status: selectedFilter.listStatus)
        if removedCount == selected.count {
            KuroAccessibility.successHaptic()
            showBanner("Removed \(selected.count) item\(selected.count == 1 ? "" : "s")")
        } else if removedCount > 0 {
            KuroAccessibility.impactHaptic(.medium)
            showBanner("Removed \(removedCount) of \(selected.count) — \(selected.count - removedCount) failed")
        } else {
            KuroAccessibility.errorHaptic()
            showBanner("Couldn't remove items — check your connection")
        }
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

// Collection helper components extracted to EditorialCollectionComponents.swift
