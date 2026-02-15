// Browse View
// Filter anime/manga by Genre, Length, Status
// Practical discovery with smart filters

import SwiftUI

struct BrowseView: View {
    @Environment(SupabaseService.self) private var supabaseService
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
                        } else {
                            BrowseEmptyState()
                        }
                    } else {
                        VStack(spacing: 18) {
                            if let hero {
                                BrowseHeroCard(media: hero, geometry: geometry)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 14)
                            }

                            if !gridItems.isEmpty {
                                BrowseGrid(items: gridItems, geometry: geometry) {
                                    await fetchNextPage()
                                }
                            }
                        }
                        .padding(.bottom, 12)

                        if isLoadingResults {
                            ProgressView()
                                .padding(.vertical, 16)
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
        .onChange(of: showAnime) { _, _ in
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

            hasMore = page0.count == pageSize
            if let last = page0.last {
                updateAnimeCursor(from: last)
            }

            let urls = page0.prefix(48).compactMap { URL(string: $0.imageURL ?? "") }
            if !urls.isEmpty { Task { await ImagePipeline.shared.prefetch(urls: urls) } }
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

            hasMore = page0.count == pageSize
            if let last = page0.last {
                updateMangaCursor(from: last)
            }

            let urls = page0.prefix(48).compactMap { URL(string: $0.imageURL ?? "") }
            if !urls.isEmpty { Task { await ImagePipeline.shared.prefetch(urls: urls) } }
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
        }
    }

    private func fetchAnimePage(cursorInt: Int?, cursorDate: Date?, cursorId: Int?) async -> [AnimeCard] {
        let range = selectedLengthFilter?.episodeRange
        return await supabaseService.fetchBrowseAnimePageKeyset(
            genre: selectedGenre,
            status: selectedStatusFilter?.statusValue,
            minEpisodes: range?.min,
            maxEpisodes: range?.max,
            sort: selectedSort,
            cursorInt: cursorInt,
            cursorDate: cursorDate,
            cursorId: cursorId,
            limit: pageSize
        )
    }

    private func fetchMangaPage(cursorInt: Int?, cursorDate: Date?, cursorId: Int?) async -> [MangaCard] {
        let range = selectedLengthFilter?.chapterRange
        return await supabaseService.fetchBrowseMangaPageKeyset(
            genre: selectedGenre,
            status: selectedStatusFilter?.statusValue,
            minChapters: range?.min,
            maxChapters: range?.max,
            sort: selectedSort,
            cursorInt: cursorInt,
            cursorDate: cursorDate,
            cursorId: cursorId,
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

// MARK: - Filter Chip
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            action()
            KuroAccessibility.impactHaptic(.light)
        }) {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .tracking(1.0)
                .foregroundColor(isSelected ? .white : .black.opacity(0.6))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.black : Color.black.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Filters results")
    }
}

// MARK: - Control Bar (browse as a "lens" instead of a wall of chips)
struct BrowseControlBar: View {
    @Binding var showAnime: Bool
    @Binding var selectedSort: SupabaseService.BrowseSort
    @Binding var selectedStatusFilter: BrowseView.StatusFilter?
    @Binding var selectedLengthFilter: BrowseView.LengthFilter?
    @Binding var selectedGenre: String?
    @Binding var selectedDecade: BrowseView.DecadeFilter?
    @Binding var selectedFormat: BrowseView.FormatFilter?

    let allGenres: [String]
    let hasActiveFilters: Bool
    let activeFiltersLabel: String
    let onOpenFilters: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                BrowseModeToggle(showAnime: $showAnime)
                Spacer()
                Button(action: {
                    KuroAccessibility.impactHaptic(.light)
                    onOpenFilters()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .semibold))
                        Text("FILTERS")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.2)
                        if hasActiveFilters {
                            Text("\(activeCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.black))
                                .accessibilityHidden(true)
                        }
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.05))
                            .overlay(Capsule().stroke(Color.black.opacity(0.12), lineWidth: 0.5))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hasActiveFilters ? "Filters, \(activeCount) active" : "Filters")
                .accessibilityHint("Opens filter editor")
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Menu {
                        ForEach(SupabaseService.BrowseSort.allCases, id: \.self) { sort in
                            Button(sort.rawValue) { selectedSort = sort }
                        }
                    } label: {
                        FilterPill(label: selectedSort.rawValue, isActive: selectedSort != .popular, icon: "arrow.up.arrow.down")
                    }

                    Menu {
                        Button("ALL") { selectedStatusFilter = nil }
                        ForEach(BrowseView.StatusFilter.allCases, id: \.self) { s in
                            Button(s.rawValue) { selectedStatusFilter = s }
                        }
                    } label: {
                        FilterPill(label: selectedStatusFilter?.rawValue ?? "ALL", isActive: selectedStatusFilter != nil, icon: "dot.radiowaves.left.and.right")
                    }

                    Menu {
                        Button("ANY LENGTH") { selectedLengthFilter = nil }
                        let valid = BrowseView.LengthFilter.allCases.filter { f in
                            (showAnime && f != .manga200) || (!showAnime && f == .manga200)
                        }
                        ForEach(valid, id: \.self) { l in
                            Button(l.rawValue) { selectedLengthFilter = l }
                        }
                    } label: {
                        FilterPill(label: selectedLengthFilter?.rawValue ?? "ANY LENGTH", isActive: selectedLengthFilter != nil, icon: "clock")
                    }

                    Menu {
                        Button("ALL GENRES") { selectedGenre = nil }
                        ForEach(allGenres, id: \.self) { g in
                            Button(g.uppercased()) { selectedGenre = g }
                        }
                    } label: {
                        FilterPill(label: (selectedGenre ?? "ALL GENRES").uppercased(), isActive: selectedGenre != nil, icon: "tag")
                    }

                    Menu {
                        Button("ANY YEAR") { selectedDecade = nil }
                        ForEach(BrowseView.DecadeFilter.allCases, id: \.self) { d in
                            Button(d.rawValue) { selectedDecade = d }
                        }
                    } label: {
                        FilterPill(label: selectedDecade?.rawValue ?? "ANY YEAR", isActive: selectedDecade != nil, icon: "calendar")
                    }

                    Menu {
                        Button("ANY FORMAT") { selectedFormat = nil }
                        ForEach(BrowseView.FormatFilter.allCases, id: \.self) { f in
                            Button(f.rawValue) { selectedFormat = f }
                        }
                    } label: {
                        FilterPill(label: selectedFormat?.rawValue ?? "ANY FORMAT", isActive: selectedFormat != nil, icon: "film")
                    }

                    if hasActiveFilters {
                        Button(action: {
                            KuroAccessibility.impactHaptic(.light)
                            onClear()
                        }) {
                            FilterPill(label: "CLEAR", isActive: true, icon: "xmark")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear filters")
                    }
                }
                .padding(.horizontal, 20)
            }
            .kuroSwipeExclusionZone()

            if hasActiveFilters {
                HStack(spacing: 12) {
                    Text(activeFiltersLabel)
                        .font(.system(size: 10, weight: .regular))
                        .tracking(1.0)
                        .foregroundColor(.black.opacity(0.55))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 2)
                .accessibilityLabel("Active filters: \(activeFiltersLabel)")
            }

            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 0.5)
        }
        .background(
            LinearGradient(
                colors: [Color.white, Color.white, Color.black.opacity(0.015)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var activeCount: Int {
        var n = 0
        if selectedSort != .popular { n += 1 }
        if selectedStatusFilter != nil { n += 1 }
        if selectedLengthFilter != nil { n += 1 }
        if selectedGenre != nil { n += 1 }
        if selectedDecade != nil { n += 1 }
        if selectedFormat != nil { n += 1 }
        return n
    }
}

struct BrowseModeToggle: View {
    @Binding var showAnime: Bool

    var body: some View {
        HStack(spacing: 16) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showAnime = true
                }
                KuroAccessibility.impactHaptic(.light)
            }) {
                Text("ANIME")
                    .font(.system(size: 12, weight: showAnime ? .semibold : .regular))
                    .tracking(1.0)
                    .foregroundColor(showAnime ? .black : .black.opacity(0.45))
                    .padding(.vertical, 6)
                    .overlay(
                        Rectangle()
                            .fill(Color.black)
                            .frame(height: 1.5)
                            .opacity(showAnime ? 1 : 0),
                        alignment: .bottom
                    )
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(showAnime ? .isSelected : [])

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showAnime = false
                }
                KuroAccessibility.impactHaptic(.light)
            }) {
                Text("MANGA")
                    .font(.system(size: 12, weight: showAnime ? .regular : .semibold))
                    .tracking(1.0)
                    .foregroundColor(showAnime ? .black.opacity(0.45) : .black)
                    .padding(.vertical, 6)
                    .overlay(
                        Rectangle()
                            .fill(Color.black)
                            .frame(height: 1.5)
                            .opacity(showAnime ? 0 : 1),
                        alignment: .bottom
                    )
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(showAnime ? [] : .isSelected)
        }
    }
}

struct FilterPill: View {
    let label: String
    let isActive: Bool
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.0)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .opacity(0.55)
        }
        .foregroundColor(isActive ? .white : .black.opacity(0.7))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(isActive ? Color.black : Color.black.opacity(0.05))
                .overlay(Capsule().stroke(Color.black.opacity(isActive ? 0.0 : 0.12), lineWidth: 0.5))
        )
    }
}

struct BrowseHeroCard: View {
    let media: any MediaDisplayable
    let geometry: GeometryProxy
    @State private var showDetail = false
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    @Environment(SupabaseService.self) private var supabaseService

    private var isInCollection: Bool {
        supabaseService.isInCollection(mediaId: media.id, mediaType: media.kind.rawValue)
    }

    var body: some View {
        let width = geometry.size.width - 40
        let height = max(220, floor(width * 0.54))

        Button(action: {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        }) {
            ZStack(alignment: .bottomLeading) {
                KuroCachedAsyncImage(url: URL(string: media.imageURL ?? ""), maxPixelSize: 700) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: width, height: height)
                            .clipped()
                    default:
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.black.opacity(0.05))
                            .frame(width: width, height: height)
                    }
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                LinearGradient(
                    colors: [Color.black.opacity(0.0), Color.black.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("PICK FOR YOU")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.8)
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        if isInCollection {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }

                    Text(media.title)
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Text(media.year)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.8))

                        if let episodes = media.episodes, episodes > 0 {
                            Text("· \(episodes) eps")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(.white.opacity(0.8))
                        } else if let chapters = media.chapters, chapters > 0 {
                            Text("· \(chapters) ch")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(.white.opacity(0.8))
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .padding(18)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(media.title), \(media.year)")
        .accessibilityHint("Opens details")
        .sheet(isPresented: $showDetail) {
            MediaDetailSheet(kind: media.kind, id: media.id)
        }
    }
}

struct BrowseFiltersSheet: View {
    struct Selection {
        var showAnime: Bool
        var sort: SupabaseService.BrowseSort
        var status: BrowseView.StatusFilter?
        var length: BrowseView.LengthFilter?
        var genre: String?
        var decade: BrowseView.DecadeFilter?
        var format: BrowseView.FormatFilter?
    }

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Selection

    let allGenres: [String]
    let onApply: (Selection) -> Void

    init(
        showAnime: Bool,
        selectedSort: SupabaseService.BrowseSort,
        selectedStatusFilter: BrowseView.StatusFilter?,
        selectedLengthFilter: BrowseView.LengthFilter?,
        selectedGenre: String?,
        selectedDecade: BrowseView.DecadeFilter?,
        selectedFormat: BrowseView.FormatFilter?,
        allGenres: [String],
        onApply: @escaping (Selection) -> Void
    ) {
        self._draft = State(initialValue: Selection(showAnime: showAnime, sort: selectedSort, status: selectedStatusFilter, length: selectedLengthFilter, genre: selectedGenre, decade: selectedDecade, format: selectedFormat))
        self.allGenres = allGenres
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    SectionTitle(title: "MODE")
                    BrowseModeToggle(showAnime: $draft.showAnime)
                        .padding(.horizontal, 20)

                    SectionTitle(title: "SORT")
                    FlowLayout(spacing: 10) {
                        ForEach(SupabaseService.BrowseSort.allCases, id: \.self) { s in
                            OptionChip(title: s.rawValue, isSelected: draft.sort == s) {
                                draft.sort = s
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    SectionTitle(title: "STATUS")
                    FlowLayout(spacing: 10) {
                        OptionChip(title: "ALL", isSelected: draft.status == nil) {
                            draft.status = nil
                        }
                        ForEach(BrowseView.StatusFilter.allCases, id: \.self) { s in
                            OptionChip(title: s.rawValue, isSelected: draft.status == s) {
                                draft.status = s
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    SectionTitle(title: draft.showAnime ? "EPISODE LENGTH" : "CHAPTER LENGTH")
                    FlowLayout(spacing: 10) {
                        OptionChip(title: "ANY", isSelected: draft.length == nil) {
                            draft.length = nil
                        }
                        let valid = BrowseView.LengthFilter.allCases.filter { f in
                            (draft.showAnime && f != .manga200) || (!draft.showAnime && f == .manga200)
                        }
                        ForEach(valid, id: \.self) { l in
                            OptionChip(title: l.rawValue, isSelected: draft.length == l) {
                                draft.length = l
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    SectionTitle(title: "GENRE")
                    FlowLayout(spacing: 10) {
                        OptionChip(title: "ALL", isSelected: draft.genre == nil) {
                            draft.genre = nil
                        }
                        ForEach(allGenres, id: \.self) { g in
                            OptionChip(title: g.uppercased(), isSelected: draft.genre == g) {
                                draft.genre = g
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    SectionTitle(title: "YEAR")
                    FlowLayout(spacing: 10) {
                        OptionChip(title: "ANY", isSelected: draft.decade == nil) {
                            draft.decade = nil
                        }
                        ForEach(BrowseView.DecadeFilter.allCases, id: \.self) { d in
                            OptionChip(title: d.rawValue, isSelected: draft.decade == d) {
                                draft.decade = d
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    SectionTitle(title: "FORMAT")
                    FlowLayout(spacing: 10) {
                        OptionChip(title: "ANY", isSelected: draft.format == nil) {
                            draft.format = nil
                        }
                        ForEach(BrowseView.FormatFilter.allCases, id: \.self) { f in
                            OptionChip(title: f.rawValue, isSelected: draft.format == f) {
                                draft.format = f
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 24)
                }
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .background(Color.kuroBackground)
            .navigationTitle("FILTERS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        KuroAccessibility.impactHaptic(.light)
                        dismiss()
                    }
                    .font(.system(size: 12, weight: .regular))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        KuroAccessibility.impactHaptic(.light)
                        onApply(draft)
                        dismiss()
                    }
                    .font(.system(size: 12, weight: .semibold))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct SectionTitle: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.6)
            .foregroundColor(.black.opacity(0.55))
            .padding(.horizontal, 20)
    }
}

struct OptionChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            action()
        }) {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .tracking(1.0)
                .foregroundColor(isSelected ? .white : .black.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.black : Color.black.opacity(0.05))
                        .overlay(Capsule().stroke(Color.black.opacity(isSelected ? 0.0 : 0.12), lineWidth: 0.5))
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct BrowseGridSkeleton: View {
    let geometry: GeometryProxy

    var body: some View {
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
            ForEach(0..<10, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.05))
                        .frame(width: cardWidth, height: imageHeight)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.black.opacity(0.06))
                            .frame(height: 10)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.black.opacity(0.05))
                            .frame(height: 9)
                            .frame(maxWidth: cardWidth * 0.6, alignment: .leading)
                    }
                    .frame(height: textBlockHeight, alignment: .top)
                }
                .frame(width: cardWidth, height: totalCardHeight, alignment: .top)
                .redacted(reason: .placeholder)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// MARK: - Browse Grid
struct BrowseGrid: View {
    let items: [any MediaDisplayable]
    let geometry: GeometryProxy
    let loadMore: () async -> Void

    var body: some View {
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
            ForEach(Array(items.enumerated()), id: \.offset) { index, media in
                GridAnimeCard(media: media, cardWidth: cardWidth, cardHeight: totalCardHeight)
                    .onAppear {
                        if index == items.count - 1 {
                            Task { await loadMore() }
                        }
                    }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// MARK: - Browse Empty State
struct BrowseEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundColor(.black.opacity(0.15))

            VStack(spacing: 8) {
                Text("NO MATCHES")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(1.0)
                    .foregroundColor(.black.opacity(0.4))

                Text("Try different filters")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.black.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

#Preview {
    BrowseView()
        .environment(SupabaseService.shared)
}
