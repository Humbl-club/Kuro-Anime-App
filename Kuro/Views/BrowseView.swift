// Browse (the catalogue; spec D2, rulebook §5/§9)
// Filter anime or manga by sort, status, length, genre, year and format, in an equal-frame grid of
// issue frames whose column count follows the width (readable column on iPad). Reached as a pager
// page in the live order and through the Browse route from Discover and Search. A failed page is a
// failure (offline or failed state), never "no matches".

import KuroCore
import SwiftUI

struct BrowseView: View {
    @Environment(SocialActivityStore.self) private var social
    @Environment(DiscoveryStore.self) private var discovery
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(FeatureFlags.self) private var flags
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedGenre: String? = nil
    @State private var selectedLengthFilter: LengthFilter? = nil
    @State private var selectedStatusFilter: StatusFilter? = nil
    @State private var selectedSort: DiscoveryStore.BrowseSort = .popular
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
    @State private var bannerTask: Task<Void, Never>? = nil
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

        func title(german: Bool) -> String {
            switch self {
            case .short: return german ? "1\u{2013}13 Folgen" : "1\u{2013}13 eps"
            case .standard: return german ? "14\u{2013}26 Folgen" : "14\u{2013}26 eps"
            case .long: return german ? "27\u{2013}99 Folgen" : "27\u{2013}99 eps"
            case .epic100: return german ? "100+ Folgen" : "100+ eps"
            case .epic200: return german ? "200+ Folgen" : "200+ eps"
            case .manga200: return german ? "200+ Kapitel" : "200+ chapters"
            }
        }

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

        func title(german: Bool, anime: Bool) -> String {
            switch self {
            case .finished: return german ? "Abgeschlossen" : "Finished"
            case .airing:
                if german { return anime ? "Läuft" : "Erscheint" }
                return anime ? "Airing" : "Publishing"
            }
        }

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

        func title(german: Bool) -> String {
            switch self {
            case .d2020s: return german ? "2020er" : "2020s"
            case .d2010s: return german ? "2010er" : "2010s"
            case .d2000s: return german ? "2000er" : "2000s"
            case .d1990s: return german ? "1990er" : "1990s"
            case .classic: return german ? "Vor 1990" : "Before 1990"
            }
        }

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

        func title(german: Bool) -> String {
            DiscoverFrameCopy.formatName(rawValue, german: german)
        }
    }

    /// A genre's reading name (the AniList genre stays the filter value).
    static func genreTitle(_ genre: String, german: Bool) -> String {
        guard german else { return genre }
        switch genre {
        case "Adventure": return "Abenteuer"
        case "Comedy": return "Komödie"
        case "Mystery": return "Mystery"
        case "Psychological": return "Psychologisch"
        case "Romance": return "Romantik"
        case "Slice of Life": return "Alltag"
        case "Sports": return "Sport"
        case "Supernatural": return "Übernatürlich"
        default: return genre
        }
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
        let german = KuroLocale.isGerman
        var parts: [String] = []
        if let s = selectedStatusFilter { parts.append(s.title(german: german, anime: showAnime)) }
        if let l = selectedLengthFilter { parts.append(l.title(german: german)) }
        if let g = selectedGenre { parts.append(Self.genreTitle(g, german: german)) }
        if selectedSort != .popular { parts.append(selectedSort.title(german: german)) }
        if let d = selectedDecade { parts.append(d.title(german: german)) }
        if let f = selectedFormat { parts.append(f.title(german: german)) }
        return parts.joined(separator: " · ")
    }

    private func clearFilters() {
        withAnimation(KuroMotion.resolve(KuroMotion.settle)) {
            selectedStatusFilter = nil
            selectedLengthFilter = nil
            selectedGenre = nil
            selectedSort = .popular
            selectedDecade = nil
            selectedFormat = nil
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = DiscoverLayout.contentWidth(container: geometry.size.width, regularWidth: horizontalSizeClass == .regular)
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
                    activeFiltersLabel: activeFiltersLabel,
                    gutter: DiscoverLayout.gutter(for: width)
                ) {
                    showFiltersSheet = true
                } onClear: {
                    clearFilters()
                }
                .frame(width: width)

                // Results Grid
                ScrollView(.vertical, showsIndicators: false) {
                    Group {
                        // One switch on the branded state (`BrowsePageRules.brandedState`, tested in
                        // RestyleLaneTests); results on screen draw the grid.
                        switch BrowsePageRules.brandedState(isLoading: isLoadingResults, hasResults: !displayItems.isEmpty,
                                                            failed: loadError, isConnected: networkMonitor.isConnected) {
                        case .loading:
                            BrowseGridSkeleton(width: width)
                        case .failed(hasContent: false):
                            KuroErrorView(headline: KuroLocale.text("Couldn't load the catalogue.", "Der Katalog konnte nicht geladen werden."),
                                          retry: { Task { await reload(mode: .pullToRefresh) } })
                                .frame(minHeight: geometry.size.height * 0.6)
                        case .offline(hasContent: false):
                            KuroOfflineView(hasContent: false, retry: { Task { await reload(mode: .pullToRefresh) } })
                                .frame(minHeight: geometry.size.height * 0.6)
                        case .empty:
                            BrowseEmptyState(
                                activeFilterCount: activeFilterCount,
                                activeFilterSummary: activeFiltersLabel,
                                onClearFilters: { clearFilters() }
                            )
                        case .offline(hasContent: true), .failed(hasContent: true), nil:
                            if !networkMonitor.isConnected {
                                // The branded offline band over the results already on screen.
                                KuroOfflineView(hasContent: true)
                            }
                            BrowseGrid(items: displayItems, width: width) {
                                await fetchNextPage()
                            }

                            if isLoadingResults {
                                BrowsePaginationSkeleton(width: width)
                            }
                        }
                    }
                    .frame(width: width)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, KuroDesignSpacing.lg)
                }
                // Keep vertical scrolling enabled even if an ancestor disables scroll via environment.
                .scrollDisabled(false)
                .refreshable {
                    reloadTask?.cancel()
                    await reload(mode: .pullToRefresh)
                }
                .background(Color.kuroCanvasPage)
                .overlay(alignment: .top) {
                    if let bannerMessage {
                        KuroTransientBanner(message: bannerMessage)
                            .padding(.top, 10)
                            .transition(.opacity)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.kuroCanvasPage)
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
                withAnimation(KuroMotion.resolve(KuroMotion.settle)) {
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
            bannerTask?.cancel()
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

            let fetched = await fetchAnimePage(cursorInt: nil, cursorDate: nil, cursorId: nil)
            guard gen == reloadGeneration else { return }
            hasMore = true
            let page0 = fetched ?? []

            if fetched == nil, mode == .pullToRefresh, !oldAnime.isEmpty {
                // A failed refresh of the same filters keeps the old content.
                animeResults = oldAnime
                showBanner(KuroLocale.text("Couldn't refresh. Try again.", "Konnte nicht aktualisiert werden. Versuch es noch einmal."))
                loadError = false
                hasMore = false
                return
            }
            animeResults = page0
            loadError = fetched == nil

            hasMore = page0.count == pageSize
            if let last = page0.last {
                updateAnimeCursor(from: last)
            }

            let urls = page0.prefix(48).compactMap { URL(string: $0.imageURL ?? "") }
            if !urls.isEmpty { Task { await ImagePipeline.shared.prefetch(urls: urls, maxPixelSize: 360) } }

            if flags.isSocialActivityV1Enabled, !page0.isEmpty {
                social.prefetchFriendCounts(items: page0.map { (mediaType: "ANIME", mediaId: $0.id) })
            }
        } else {
            mangaCursorInt = nil
            mangaCursorDate = nil
            mangaCursorId = nil

            let fetched = await fetchMangaPage(cursorInt: nil, cursorDate: nil, cursorId: nil)
            guard gen == reloadGeneration else { return }
            hasMore = true
            let page0 = fetched ?? []

            if fetched == nil, mode == .pullToRefresh, !oldManga.isEmpty {
                mangaResults = oldManga
                showBanner(KuroLocale.text("Couldn't refresh. Try again.", "Konnte nicht aktualisiert werden. Versuch es noch einmal."))
                loadError = false
                hasMore = false
                return
            }
            mangaResults = page0
            loadError = fetched == nil

            hasMore = page0.count == pageSize
            if let last = page0.last {
                updateMangaCursor(from: last)
            }

            let urls = page0.prefix(48).compactMap { URL(string: $0.imageURL ?? "") }
            if !urls.isEmpty { Task { await ImagePipeline.shared.prefetch(urls: urls, maxPixelSize: 360) } }

            if flags.isSocialActivityV1Enabled, !page0.isEmpty {
                social.prefetchFriendCounts(items: page0.map { (mediaType: "MANGA", mediaId: $0.id) })
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
            let fetched = await fetchAnimePage(cursorInt: animeCursorInt, cursorDate: animeCursorDate, cursorId: animeCursorId)
            guard gen == reloadGeneration else { return }
            guard let page = fetched else {
                // The next page failed: stop paging until a reload, and say so once.
                hasMore = false
                showBanner(KuroLocale.text("Couldn't load more. Pull to refresh.", "Konnte nicht mehr laden. Zum Aktualisieren ziehen."))
                return
            }
            animeResults.append(contentsOf: page)
            hasMore = page.count == pageSize
            if let last = page.last {
                updateAnimeCursor(from: last)
            }

            let urls = page.prefix(48).compactMap { URL(string: $0.imageURL ?? "") }
            if !urls.isEmpty { Task { await ImagePipeline.shared.prefetch(urls: urls, maxPixelSize: 360) } }

            if flags.isSocialActivityV1Enabled, !page.isEmpty {
                social.prefetchFriendCounts(items: page.map { (mediaType: "ANIME", mediaId: $0.id) })
            }
        } else {
            let fetched = await fetchMangaPage(cursorInt: mangaCursorInt, cursorDate: mangaCursorDate, cursorId: mangaCursorId)
            guard gen == reloadGeneration else { return }
            guard let page = fetched else {
                hasMore = false
                showBanner(KuroLocale.text("Couldn't load more. Pull to refresh.", "Konnte nicht mehr laden. Zum Aktualisieren ziehen."))
                return
            }
            mangaResults.append(contentsOf: page)
            hasMore = page.count == pageSize
            if let last = page.last {
                updateMangaCursor(from: last)
            }

            let urls = page.prefix(48).compactMap { URL(string: $0.imageURL ?? "") }
            if !urls.isEmpty { Task { await ImagePipeline.shared.prefetch(urls: urls, maxPixelSize: 360) } }

            if flags.isSocialActivityV1Enabled, !page.isEmpty {
                social.prefetchFriendCounts(items: page.map { (mediaType: "MANGA", mediaId: $0.id) })
            }
        }
    }

    private func fetchAnimePage(cursorInt: Int?, cursorDate: Date?, cursorId: Int?) async -> [AnimeCard]? {
        let range = selectedLengthFilter?.episodeRange
        let yearRange = selectedDecade?.yearRange
        return await discovery.browseAnimePage(
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

    private func fetchMangaPage(cursorInt: Int?, cursorDate: Date?, cursorId: Int?) async -> [MangaCard]? {
        let range = selectedLengthFilter?.chapterRange
        let yearRange = selectedDecade?.yearRange
        return await discovery.browseMangaPage(
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
        bannerTask?.cancel()
        withAnimation(KuroMotion.resolve(KuroMotion.settle)) {
            bannerMessage = message
        }
        bannerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(KuroMotion.resolve(KuroMotion.settle)) {
                bannerMessage = nil
            }
        }
    }
}

// Browse helper components extracted to BrowseComponents.swift

// MARK: - Branded state (prototype-fidelity Task 9)

/// What the Browse results area draws instead of the grid. Pure. Results on screen always win (with
/// the offline band when the connection is gone), then a first page in flight, then a failed read
/// (offline when the connection is gone), then the empty state (no titles / no matches).
nonisolated enum BrowsePageRules {
    static func brandedState(isLoading: Bool, hasResults: Bool, failed: Bool, isConnected: Bool) -> KuroBrandedState? {
        if hasResults { return isConnected ? nil : .offline(hasContent: true) }
        if isLoading { return .loading }
        if failed { return isConnected ? .failed(hasContent: false) : .offline(hasContent: false) }
        return .empty
    }
}
