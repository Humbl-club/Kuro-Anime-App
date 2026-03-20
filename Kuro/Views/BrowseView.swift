// Browse View
// Filter anime/manga by Genre, Length, Status
// Practical discovery with smart filters

import SwiftUI

struct BrowseView: View {
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(NetworkMonitor.self) private var networkMonitor
    @State private var selectedGenre: String? = nil
    @State private var selectedLengthFilter: LengthFilter? = nil
    @State private var selectedStatusFilter: StatusFilter? = nil
    @State private var selectedSort: SupabaseService.BrowseSort = .popular
    @State private var selectedDecade: DecadeFilter? = nil
    @State private var selectedFormat: FormatFilter? = nil
    @State private var showAnime = true
    @State private var showFiltersSheet: Bool = false
    @State private var animeResults: [AnimeCard] = []
    @State private var mangaResults: [MangaCard] = []

    // Keyset cursor (depends on sort). We keep separate cursors per media type.
    @State private var animeCursorInt: Int? = nil
    @State private var animeCursorDate: Date? = nil
    @State private var animeCursorId: Int? = nil
    @State private var mangaCursorInt: Int? = nil
    @State private var mangaCursorDate: Date? = nil
    @State private var mangaCursorId: Int? = nil

    @State private var hasMore: Bool = true
    @State private var isLoadingResults: Bool = false
    @State private var reloadTask: Task<Void, Never>? = nil
    @State private var didInitialLoad = false
    @State private var reloadGeneration: Int = 0
    @State private var bannerMessage: String? = nil
    @State private var loadError = false

    private let pageSize: Int = 60
    private let allGenres: [String] = [
        "Action", "Adventure", "Comedy", "Drama", "Ecchi", "Fantasy", "Hentai", "Horror",
        "Mahou Shoujo", "Mecha", "Music", "Mystery", "Psychological", "Romance", "Sci-Fi",
        "Slice of Life", "Sports", "Supernatural", "Thriller"
    ]

    enum LengthFilter: String, CaseIterable {
        case short = "SHORT (1-13)"
        case standard = "STANDARD (14-26)"
        case long = "LONG (27-99)"
        case epic100 = "100+ EPS"
        case epic200 = "200+ EPS"
        case manga200 = "200+ CH"

        var episodeRange: (min: Int, max: Int?)? {
            switch self {
            case .short: return (1, 13)
            case .standard: return (14, 26)
            case .long: return (27, 99)
            case .epic100: return (100, nil)
            case .epic200: return (200, nil)
            case .manga200: return nil
            }
        }

        var chapterRange: (min: Int, max: Int?)? {
            switch self {
            case .manga200: return (200, nil)
            default: return nil
            }
        }
    }

    enum StatusFilter: String, CaseIterable {
        case finished = "FINISHED"
        case airing = "AIRING"

        var statusValue: String {
            switch self {
            case .finished: return "FINISHED"
            case .airing: return "RELEASING"
            }
        }
    }

    enum DecadeFilter: String, CaseIterable {
        case d2020s = "2020s"
        case d2010s = "2010s"
        case d2000s = "2000s"
        case d1990s = "1990s"
        case classic = "< 1990"

        var yearRange: (min: Int, max: Int?) {
            switch self {
            case .d2020s: return (2020, nil)
            case .d2010s: return (2010, 2019)
            case .d2000s: return (2000, 2009)
            case .d1990s: return (1990, 1999)
            case .classic: return (0, 1989)
            }
        }
    }

    enum FormatFilter: String, CaseIterable {
        case tv = "TV"
        case movie = "MOVIE"
        case ova = "OVA"
        case ona = "ONA"
        case special = "SPECIAL"
    }

    private var displayItems: [any MediaDisplayable] {
        let raw: [any MediaDisplayable] = showAnime
            ? animeResults.map { $0 as any MediaDisplayable }
            : mangaResults.map { $0 as any MediaDisplayable }
        return raw.filter { item in
            if let decade = selectedDecade {
                let yr = Int(item.year) ?? 0
                let range = decade.yearRange
                if yr < range.min { return false }
                if let max = range.max, yr > max { return false }
            }
            if let fmt = selectedFormat {
                guard let itemFmt = item.formatRaw else { return false }
                if itemFmt.uppercased() != fmt.rawValue { return false }
            }
            return true
        }
    }

    private var hasActiveFilters: Bool {
        selectedStatusFilter != nil
        || selectedLengthFilter != nil
        || selectedGenre != nil
        || selectedSort != .popular
        || selectedDecade != nil
        || selectedFormat != nil
    }

    private var activeFilterCount: Int {
        var n = 0
        if selectedSort != .popular { n += 1 }
        if selectedStatusFilter != nil { n += 1 }
        if selectedLengthFilter != nil { n += 1 }
        if selectedGenre != nil { n += 1 }
        if selectedDecade != nil { n += 1 }
        if selectedFormat != nil { n += 1 }
        return n
    }

    private var activeFiltersLabel: String {
        var parts: [String] = []
        if let s = selectedStatusFilter { parts.append(s.rawValue) }
        if let l = selectedLengthFilter { parts.append(l.rawValue) }
        if let g = selectedGenre { parts.append(g.uppercased()) }
        if selectedSort != .popular { parts.append(selectedSort.rawValue) }
        if let d = selectedDecade { parts.append(d.rawValue) }
        if let f = selectedFormat { parts.append(f.rawValue) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                BrowseControlBar(
                    showAnime: $showAnime,
                    selectedSort: $selectedSort,
                    selectedStatusFilter: $selectedStatusFilter,
                    selectedLengthFilter: $selectedLengthFilter,
                    selectedGenre: $selectedGenre,
                    selectedDecade: $selectedDecade,
                    selectedFormat: $selectedFormat,
                    allGenres: allGenres,
                    hasActiveFilters: hasActiveFilters,
                    activeFiltersLabel: activeFiltersLabel
                ) {
                    showFiltersSheet = true
                } onClear: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedStatusFilter = nil
                        selectedLengthFilter = nil
                        selectedGenre = nil
                        selectedSort = .popular
                        selectedDecade = nil
                        selectedFormat = nil
                    }
                }

                // Results Grid
                ScrollView(.vertical, showsIndicators: false) {
                    let hero = displayItems.first
                    let gridItems = Array(displayItems.dropFirst())

                    if displayItems.isEmpty {
                        if isLoadingResults {
                            BrowseGridSkeleton(geometry: geometry)
                        } else if loadError {
                            VStack(spacing: KuroDesignSpacing.md) {
                                Image(systemName: "wifi.slash")
                                    .font(.system(size: 32, weight: .light))
                                    .foregroundColor(.kuroTextTertiary)
                                Text("COULDN'T LOAD")
                                    .font(.kuroCaption(weight: .medium))
                                    .tracking(1.6)
                                    .foregroundColor(.kuroTextSecondary)
                                Text("Check your connection and try again.")
                                    .font(.kuroBody())
                                    .foregroundColor(.kuroTextTertiary)
                                    .multilineTextAlignment(.center)
                                Button {
                                    loadError = false
                                    Task { await reload(mode: .pullToRefresh) }
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
                            BrowseEmptyState(
                                activeFilterCount: activeFilterCount,
                                activeFilterSummary: activeFiltersLabel,
                                onClearFilters: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedStatusFilter = nil
                                        selectedLengthFilter = nil
                                        selectedGenre = nil
                                        selectedSort = .popular
                                        selectedDecade = nil
                                        selectedFormat = nil
                                    }
                                }
                            )
                        }
                    } else {
                        if !isLoadingResults {
                            BrowseResultsHeader(
                                title: showAnime ? "ANIME BROWSE" : "MANGA BROWSE",
                                subtitle: hasActiveFilters ? activeFiltersLabel : "Hero pick first, then a denser grid",
                                countLabel: "\(displayItems.count)"
                            )
                            .padding(.top, 8)
                        }

                        VStack(spacing: 14) {
                            if let hero {
                                BrowseHeroCard(media: hero, geometry: geometry)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 10)
                            }

                            if !gridItems.isEmpty {
                                BrowseGrid(items: gridItems, geometry: geometry) {
                                    await fetchNextPage()
                                }
                            }
                        }
                        .padding(.bottom, 10)

                        if isLoadingResults, !displayItems.isEmpty {
                            BrowsePaginationSkeleton(geometry: geometry)
                        }
                    }
                }
                // Keep vertical scrolling enabled even if an ancestor disables scroll via environment.
                .scrollDisabled(false)
                .refreshable {
                    reloadTask?.cancel()
                    await reload(mode: .pullToRefresh)
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
        }
        .background(Color.kuroBackground)
        .sheet(isPresented: $showFiltersSheet) {
            BrowseFiltersSheet(
                showAnime: showAnime,
                selectedSort: selectedSort,
                selectedStatusFilter: selectedStatusFilter,
                selectedLengthFilter: selectedLengthFilter,
                selectedGenre: selectedGenre,
                selectedDecade: selectedDecade,
                selectedFormat: selectedFormat,
                allGenres: allGenres
            ) { next in
                withAnimation(.easeInOut(duration: 0.2)) {
                    showAnime = next.showAnime
                    selectedSort = next.sort
                    selectedStatusFilter = next.status
                    selectedLengthFilter = next.length
                    selectedGenre = next.genre
                    selectedDecade = next.decade
                    selectedFormat = next.format
                }
            }
        }
        .task {
            if !didInitialLoad {
                didInitialLoad = true
                await reload(mode: .initial)
            }
        }
        .onDisappear {
            reloadTask?.cancel()
        }
        .onChange(of: networkMonitor.reconnectionGeneration) { _, _ in
            guard networkMonitor.isConnected, loadError else { return }
            reloadTask?.cancel()
            reloadTask = Task {
                await reload(mode: .pullToRefresh)
            }
        }
        .onChange(of: showAnime) { _, isAnime in
            if isAnime {
                if selectedLengthFilter == .manga200 {
                    selectedLengthFilter = nil
                    return
                }
            } else if let selectedLengthFilter, selectedLengthFilter != .manga200 {
                self.selectedLengthFilter = nil
                return
            }
            scheduleReload()
        }
        .onChange(of: selectedGenre) { _, _ in
            scheduleReload()
        }
        .onChange(of: selectedLengthFilter) { _, _ in
            scheduleReload()
        }
        .onChange(of: selectedStatusFilter) { _, _ in
            scheduleReload()
        }
        .onChange(of: selectedSort) { _, _ in
            scheduleReload()
        }
        .onChange(of: selectedDecade) { _, _ in
            scheduleReload()
        }
        .onChange(of: selectedFormat) { _, _ in
            scheduleReload()
        }
    }

    private enum ReloadMode {
        case initial
        case pullToRefresh
        case filtersChanged
    }

    @MainActor
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            // Coalesce rapid changes (e.g. toggling media type also clears a length filter).
            try? await Task.sleep(nanoseconds: 120_000_000)
            if Task.isCancelled { return }
            await reload(mode: .filtersChanged)
        }
    }

    @MainActor
    private func reload(mode: ReloadMode) async {
        let perf = KuroPerf.begin("browse.reload")
        reloadGeneration += 1
        let gen = reloadGeneration
        isLoadingResults = true
        defer {
            if gen == reloadGeneration { isLoadingResults = false }
            KuroPerf.end(perf, message: showAnime ? "anime" : "manga")
        }

        // Snapshot old results so pull-to-refresh doesn't "blank" the UI on transient errors.
        let oldAnime = animeResults
        let oldManga = mangaResults

        if showAnime {
            // Reset keyset cursor for a fresh query.
            animeCursorInt = nil
            animeCursorDate = nil
            animeCursorId = nil

            let page0 = await fetchAnimePage(cursorInt: nil, cursorDate: nil, cursorId: nil)
            guard gen == reloadGeneration else { return }
            hasMore = true

            if mode == .pullToRefresh, page0.isEmpty, !oldAnime.isEmpty {
                // Keep old content if refresh failed (service returns [] on error).
                animeResults = oldAnime
                showBanner("Couldn't refresh. Try again.")
            } else {
                animeResults = page0
            }

            loadError = page0.isEmpty && !networkMonitor.isConnected

            hasMore = page0.count == pageSize
            if let last = page0.last {
                updateAnimeCursor(from: last)
            }

            let urls = page0.prefix(48).compactMap { URL(string: $0.imageURL ?? "") }
            if !urls.isEmpty { Task { await ImagePipeline.shared.prefetch(urls: urls) } }

            if FeatureFlags.shared.isSocialActivityV1Enabled, !page0.isEmpty {
                supabaseService.prefetchFriendCounts(items: page0.map { (mediaType: "ANIME", mediaId: $0.id) })
            }
        } else {
            mangaCursorInt = nil
            mangaCursorDate = nil
            mangaCursorId = nil

            let page0 = await fetchMangaPage(cursorInt: nil, cursorDate: nil, cursorId: nil)
            guard gen == reloadGeneration else { return }
            hasMore = true

            if mode == .pullToRefresh, page0.isEmpty, !oldManga.isEmpty {
                mangaResults = oldManga
                showBanner("Couldn't refresh. Try again.")
            } else {
                mangaResults = page0
            }

            loadError = page0.isEmpty && !networkMonitor.isConnected

            hasMore = page0.count == pageSize
            if let last = page0.last {
                updateMangaCursor(from: last)
            }

            let urls = page0.prefix(48).compactMap { URL(string: $0.imageURL ?? "") }
            if !urls.isEmpty { Task { await ImagePipeline.shared.prefetch(urls: urls) } }

            if FeatureFlags.shared.isSocialActivityV1Enabled, !page0.isEmpty {
                supabaseService.prefetchFriendCounts(items: page0.map { (mediaType: "MANGA", mediaId: $0.id) })
            }
        }
    }

    @MainActor
    private func fetchNextPage() async {
        guard hasMore, !isLoadingResults else { return }
        let gen = reloadGeneration
        isLoadingResults = true
        defer { isLoadingResults = false }

        if showAnime {
            let page = await fetchAnimePage(cursorInt: animeCursorInt, cursorDate: animeCursorDate, cursorId: animeCursorId)
            guard gen == reloadGeneration else { return }
            animeResults.append(contentsOf: page)
            hasMore = page.count == pageSize
            if let last = page.last {
                updateAnimeCursor(from: last)
            }

            let urls = page.prefix(48).compactMap { URL(string: $0.imageURL ?? "") }
            if !urls.isEmpty { Task { await ImagePipeline.shared.prefetch(urls: urls) } }

            if FeatureFlags.shared.isSocialActivityV1Enabled, !page.isEmpty {
                supabaseService.prefetchFriendCounts(items: page.map { (mediaType: "ANIME", mediaId: $0.id) })
            }
        } else {
            let page = await fetchMangaPage(cursorInt: mangaCursorInt, cursorDate: mangaCursorDate, cursorId: mangaCursorId)
            guard gen == reloadGeneration else { return }
            mangaResults.append(contentsOf: page)
            hasMore = page.count == pageSize
            if let last = page.last {
                updateMangaCursor(from: last)
            }

            let urls = page.prefix(48).compactMap { URL(string: $0.imageURL ?? "") }
            if !urls.isEmpty { Task { await ImagePipeline.shared.prefetch(urls: urls) } }

            if FeatureFlags.shared.isSocialActivityV1Enabled, !page.isEmpty {
                supabaseService.prefetchFriendCounts(items: page.map { (mediaType: "MANGA", mediaId: $0.id) })
            }
        }
    }

    private func fetchAnimePage(cursorInt: Int?, cursorDate: Date?, cursorId: Int?) async -> [AnimeCard] {
        let range = selectedLengthFilter?.episodeRange
        let yearRange = selectedDecade?.yearRange
        return await supabaseService.fetchBrowseAnimePageKeyset(
            genre: selectedGenre,
            status: selectedStatusFilter?.statusValue,
            minEpisodes: range?.min,
            maxEpisodes: range?.max,
            sort: selectedSort,
            cursorInt: cursorInt,
            cursorDate: cursorDate,
            cursorId: cursorId,
            minYear: yearRange?.min,
            maxYear: yearRange?.max,
            format: selectedFormat?.rawValue,
            limit: pageSize
        )
    }

    private func fetchMangaPage(cursorInt: Int?, cursorDate: Date?, cursorId: Int?) async -> [MangaCard] {
        let range = selectedLengthFilter?.chapterRange
        let yearRange = selectedDecade?.yearRange
        return await supabaseService.fetchBrowseMangaPageKeyset(
            genre: selectedGenre,
            status: selectedStatusFilter?.statusValue,
            minChapters: range?.min,
            maxChapters: range?.max,
            sort: selectedSort,
            cursorInt: cursorInt,
            cursorDate: cursorDate,
            cursorId: cursorId,
            minYear: yearRange?.min,
            maxYear: yearRange?.max,
            format: selectedFormat?.rawValue,
            limit: pageSize
        )
    }

    private func updateAnimeCursor(from last: AnimeCard) {
        animeCursorId = last.id
        switch selectedSort {
        case .popular:
            animeCursorInt = last.popularity
            animeCursorDate = nil
        case .trending:
            animeCursorInt = last.trending
            animeCursorDate = nil
        case .topRated:
            animeCursorInt = last.averageScore
            animeCursorDate = nil
        case .newlyAdded:
            animeCursorInt = nil
            animeCursorDate = last.createdAt
        }
    }

    private func updateMangaCursor(from last: MangaCard) {
        mangaCursorId = last.id
        switch selectedSort {
        case .popular:
            mangaCursorInt = last.popularity
            mangaCursorDate = nil
        case .trending:
            mangaCursorInt = last.trending
            mangaCursorDate = nil
        case .topRated:
            mangaCursorInt = last.averageScore
            mangaCursorDate = nil
        case .newlyAdded:
            mangaCursorInt = nil
            mangaCursorDate = last.createdAt
        }
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

// Browse helper components extracted to BrowseComponents.swift
