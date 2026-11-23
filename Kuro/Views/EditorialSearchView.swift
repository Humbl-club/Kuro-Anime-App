// Search (rulebook §14.6, spec D2)
// A journey opened from the header magnifier (and pushed from Profile → Find): `ShellJourneyPages.search`
// adds the chrome (✕ top-right, Back when pushed); result rows and the Browse entry push inside it. The scope is chosen by the caller (`initialScope`) and
// can be changed with ink words; refinements are ink words with an underline mark. The empty query
// shows this account's recent searches on this device and the way into the catalogue (Browse).
// Results are picture-first index rows. No results: "No titles match '…'." Failures and offline are
// their own states, never an empty result.

import KuroCore
import KuroLibrary
import SwiftUI

struct EditorialSearchResultItem: Identifiable {
    let id: String
    let media: any MediaDisplayable
    let rank: Double
    let popularity: Int
}

struct EditorialSearchView: View {
    @Environment(BannerCenter.self) private var banner
    @Environment(SearchStore.self) private var search
    @Environment(DiscoveryStore.self) private var discovery
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var scope: SearchScope
    @State private var selectedRefinements: Set<SearchRefinement> = []
    /// A qualifying query is waiting for its debounce or first page: no "no results" yet.
    @State private var isAwaitingResults = false
    /// Quick-add status changes inside Search share one Undo toast host.
    @State private var plans = TastePlanController()
    @FocusState private var isFieldFocused: Bool

    init(initialScope: SearchScope = .all) {
        _scope = State(initialValue: initialScope)
    }

    enum SearchScope: String, CaseIterable {
        case all = "ALL"
        case anime = "ANIME"
        case manga = "MANGA"

        func title(german: Bool) -> String {
            switch self {
            case .all: return german ? "Alle" : "All"
            case .anime: return "Anime"
            case .manga: return "Manga"
            }
        }
    }

    enum SearchRefinement: String, CaseIterable, Hashable {
        case trending = "TRENDING"
        case new = "NEW"
        case newSeason = "NEW SEASON"
        case classics = "CLASSICS"
        case hiddenGems = "HIDDEN GEMS"
        case airing = "AIRING"

        func title(german: Bool) -> String {
            switch self {
            case .trending: return german ? "Beliebt" : "Trending"
            case .new: return german ? "Neu" : "New"
            case .newSeason: return german ? "Neue Season" : "New this season"
            case .classics: return german ? "Klassiker" : "Classics"
            case .hiddenGems: return german ? "Verborgene Juwelen" : "Hidden gems"
            case .airing: return german ? "Läuft gerade" : "Airing"
            }
        }
    }

    private var availableRefinements: [SearchRefinement] {
        switch scope {
        case .all:
            return [.trending, .new, .classics, .hiddenGems]
        case .anime:
            return [.trending, .newSeason, .classics, .hiddenGems, .airing]
        case .manga:
            return [.trending, .new, .classics, .hiddenGems]
        }
    }

    private var activeSearchFilters: SearchStore.SearchFilters? {
        var filters = SearchStore.SearchFilters()
        if selectedRefinements.contains(.trending) { filters.trending = true }
        if selectedRefinements.contains(.classics) { filters.classics = true }
        if selectedRefinements.contains(.hiddenGems) { filters.hiddenGems = true }

        switch scope {
        case .all:
            if selectedRefinements.contains(.new) { filters.newSeason = true }
        case .anime:
            if selectedRefinements.contains(.newSeason) { filters.newSeason = true }
            if selectedRefinements.contains(.airing) { filters.airingOnly = true }
        case .manga:
            if selectedRefinements.contains(.new) { filters.newSeason = true }
        }

        let hasFilters = filters.trending || filters.newSeason || filters.classics || filters.hiddenGems || filters.airingOnly
        return hasFilters ? filters : nil
    }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A query or refinement the search runs for (the idle state shows otherwise).
    private var showsSearchContent: Bool {
        Self.shouldRunSearch(query: trimmedQuery, hasFilters: activeSearchFilters != nil)
    }

    private var hasActiveQueryOrFilter: Bool {
        !trimmedQuery.isEmpty || activeSearchFilters != nil
    }

    private var cachedPreviewPool: (anime: [AnimeCard], manga: [MangaCard]) {
        discovery.cachedSearchPreviewCards()
    }

    private var idleTrendingCards: [TasteCard] {
        let pool = cachedPreviewPool
        switch scope {
        case .anime:
            return Array(pool.anime.prefix(10).map(TasteCard.init(anime:)))
        case .manga:
            return Array(pool.manga.prefix(10).map(TasteCard.init(manga:)))
        case .all:
            let anime = pool.anime.prefix(6).map(TasteCard.init(anime:))
            let manga = pool.manga.prefix(4).map(TasteCard.init(manga:))
            var merged: [TasteCard] = []
            for idx in 0..<max(anime.count, manga.count) {
                if idx < anime.count { merged.append(anime[idx]) }
                if idx < manga.count { merged.append(manga[idx]) }
            }
            return merged
        }
    }

    private var displayedResults: [EditorialSearchResultItem] {
        let query = trimmedQuery
        let pool = cachedPreviewPool
        let localPreview = selectedRefinements.isEmpty
            ? Self.localPreviewMatches(query: query, scope: scope, anime: pool.anime, manga: pool.manga)
            : []
        if query.count == 1 && activeSearchFilters == nil {
            return localPreview
        }
        guard showsSearchContent else { return [] }
        let server = serverResults
        if server.isEmpty {
            return (search.isSearching || isAwaitingResults) ? localPreview : []
        }
        guard !localPreview.isEmpty else { return server }
        let seen = Set(server.map(\.id))
        return server + localPreview.filter { !seen.contains($0.id) }
    }

    private var serverResults: [EditorialSearchResultItem] {
        let anime = search.searchAnimeItems.map {
            EditorialSearchResultItem(
                id: "anime-\($0.id)",
                media: $0,
                rank: $0.rank ?? 0,
                popularity: $0.popularity ?? 0
            )
        }
        let manga = search.searchMangaItems.map {
            EditorialSearchResultItem(
                id: "manga-\($0.id)",
                media: $0,
                rank: $0.rank ?? 0,
                popularity: $0.popularity ?? 0
            )
        }

        return (anime + manga).sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
            if lhs.popularity != rhs.popularity { return lhs.popularity > rhs.popularity }
            return lhs.media.title.localizedCaseInsensitiveCompare(rhs.media.title) == .orderedAscending
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = DiscoverLayout.contentWidth(container: geometry.size.width, regularWidth: horizontalSizeClass == .regular)
            let gutter = DiscoverLayout.gutter(for: width)
            VStack(alignment: .leading, spacing: 0) {
                EditorialSearchBar(
                    searchText: $searchText,
                    prompt: Self.prompt(for: scope, german: KuroLocale.isGerman),
                    isFocused: $isFieldFocused,
                    onSubmit: { discovery.recordRecentSearch(searchText) }
                )
                .padding(.horizontal, gutter)
                .padding(.top, KuroDesignSpacing.sm)
                .padding(.bottom, 6)

                DiscoverWordPicker(
                    options: SearchScope.allCases.map { ($0, $0.title(german: KuroLocale.isGerman)) },
                    selection: $scope,
                    accessibilityLabel: KuroLocale.text("Search in", "Suchen in")
                )
                .contentMargins(.horizontal, gutter, for: .scrollContent)

                EditorialSearchFilterStrip(
                    refinements: availableRefinements,
                    selectedRefinements: $selectedRefinements,
                    gutter: gutter
                )
                .padding(.bottom, KuroDesignSpacing.xs)

                Rectangle()
                    .fill(Color.kuroHairline)
                    .frame(height: 0.5)

                ReleaseAlertOfferStack(hasToast: banner.message != nil) {
                    if let transientBannerMessage = banner.message {
                        KuroTransientBanner(message: transientBannerMessage)
                            .padding(.horizontal, gutter)
                            .padding(.vertical, KuroDesignSpacing.sm)
                    }
                }

                ScrollView(.vertical, showsIndicators: false) {
                    resultsContent(gutter: gutter)
                        .padding(.bottom, KuroDesignSpacing.xxl + 32)
                }
                .scrollDisabled(false)
                .scrollDismissesKeyboard(.interactively)
                // A new scope is a new list: start it at the top (it kept the old offset and hid the
                // first result under the pinned filters).
                .id(scope)
                // H4: Search is a journey's first page, where pull-down dismisses the sheet.
                .kuroJourneyRefreshable {
                    guard showsSearchContent else { return }
                    await search.refreshSearch()
                }
            }
            .frame(width: width)
            .frame(maxWidth: .infinity)
        }
        .background(Color.kuroCanvasPage)
        .tastePlanHost(plans, offerSlot: false)
        .onChange(of: searchText) { _, _ in
            debounceSearch()
        }
        .onChange(of: scope) { _, _ in
            selectedRefinements = selectedRefinements.intersection(Set(availableRefinements))
            debounceSearch()
        }
        .onChange(of: selectedRefinements) { _, _ in
            debounceSearch()
        }
        .onAppear {
            discovery.loadRecentSearches()
        }
        .task {
            // Focus without waiting on network; warm the preview pool in parallel if empty.
            async let warmPool: Void = {
                let cached = discovery.cachedSearchPreviewCards()
                if cached.anime.isEmpty && cached.manga.isEmpty {
                    _ = await discovery.ensureDiscoverBundle()
                }
            }()
            try? await Task.sleep(nanoseconds: 250_000_000)
            if trimmedQuery.isEmpty { isFieldFocused = true }
            _ = await warmPool
        }
        .onDisappear {
            searchTask?.cancel()
        }
        // Inside the Search journey this forwards (rows push); outside one it presents a journey.
        .routePresenter()
    }

    @ViewBuilder
    private func resultsContent(gutter: CGFloat) -> some View {
        let results = displayedResults
        let awaitingServer = showsSearchContent && (search.isSearching || isAwaitingResults)
        if !hasActiveQueryOrFilter {
            SearchIdleState(
                recentSearches: discovery.recentSearches,
                trendingCards: idleTrendingCards,
                showsMediumOnPopular: scope == .all,
                gutter: gutter,
                onPick: { query in
                    searchText = query
                    discovery.recordRecentSearch(query)
                },
                onRemove: { discovery.removeRecentSearch($0) },
                onClear: { discovery.clearRecentSearches() }
            )
        } else if results.isEmpty && awaitingServer {
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { _ in
                    SearchResultSkeletonRow()
                        .padding(.horizontal, gutter)
                }
            }
            .padding(.top, KuroDesignSpacing.sm)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(KuroLocale.text("Searching", "Suche läuft"))
        } else if results.isEmpty && trimmedQuery.count == 1 && activeSearchFilters == nil {
            Text(KuroLocale.text(
                "Type one more character to search the catalogue…",
                "Gib ein weiteres Zeichen ein, um im Katalog zu suchen …"
            ))
            .font(.kuroMeta())
            .foregroundStyle(Color.kuroMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, gutter)
            .padding(.top, KuroDesignSpacing.lg)
        } else if results.isEmpty && search.errorMessage != nil {
            KuroStateView(
                networkMonitor.isConnected ? .failed(hasCachedContent: false) : .offline(hasCachedContent: false),
                title: networkMonitor.isConnected
                    ? KuroLocale.text("Couldn't search.", "Suche nicht möglich.")
                    : nil,
                layout: .inline,
                retry: { Task { await runSearch(reset: true) } }
            )
            .padding(.horizontal, gutter)
        } else if results.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SearchNoResultsState(
                    title: Self.noResultsTitle(
                        query: trimmedQuery,
                        refinements: availableRefinements.filter { selectedRefinements.contains($0) },
                        german: KuroLocale.isGerman
                    ),
                    hasRefinements: !selectedRefinements.isEmpty,
                    gutter: gutter,
                    onClearRefinements: { selectedRefinements = [] }
                )
                SearchAdultFootnote(hiddenAdult: search.hiddenAdultCount)
                    .padding(.horizontal, gutter)
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !trimmedQuery.isEmpty && serverResults.isEmpty && awaitingServer {
                    HStack(spacing: 8) {
                        Text(KuroLocale.text("Instant matches", "Soforttreffer"))
                            .font(.kuroMicro(weight: .semibold))
                            .tracking(0.9)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.kuroMuted)
                        Spacer(minLength: 8)
                        KuroBusyMark(width: 24)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, gutter)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                }
                ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                    SearchResultRow(media: item.media, query: searchText, showsMedium: scope == .all) {
                        discovery.recordRecentSearch(searchText)
                    }
                    .padding(.horizontal, gutter)
                    .onAppear {
                        // Infinite scroll: when the last row appears, try the next page.
                        if showsSearchContent, index == results.count - 1, search.hasMoreSearch, !search.isSearching {
                            Task { await loadMore() }
                        }
                    }
                }
                if search.isSearching && !serverResults.isEmpty {
                    KuroBusyMark(width: 44)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(KuroLocale.text("Loading more", "Lädt weitere"))
                }
                SearchAdultFootnote(hiddenAdult: search.hiddenAdultCount)
                    .padding(.horizontal, gutter)
            }
            .padding(.top, KuroDesignSpacing.xs)
        }
    }

    private func debounceSearch() {
        searchTask?.cancel()
        isAwaitingResults = Self.shouldRunSearch(query: trimmedQuery, hasFilters: activeSearchFilters != nil)
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if !Task.isCancelled {
                await runSearch(reset: true)
            }
        }
    }

    private func runSearch(reset: Bool) async {
        let trimmed = trimmedQuery
        let hasFilters = activeSearchFilters != nil

        search.setSearchFilters(activeSearchFilters)

        // Avoid blanking the UI for very short queries; wait until the user has typed enough.
        guard Self.shouldRunSearch(query: trimmed, hasFilters: hasFilters) else {
            isAwaitingResults = false
            return
        }

        if reset {
            switch scope {
            case .all:
                search.resetCombinedSearch(query: trimmed)
            case .anime:
                search.resetSearch(query: trimmed, isManga: false)
            case .manga:
                search.resetSearch(query: trimmed, isManga: true)
            }
        }

        if scope == .all {
            await search.fetchNextCombinedSearchPage()
        } else {
            await search.fetchNextSearchPage()
        }
        if !Task.isCancelled {
            isAwaitingResults = false
        }
    }

    private func loadMore() async {
        if scope == .all {
            await search.fetchNextCombinedSearchPage()
        } else {
            await search.fetchNextSearchPage()
        }
    }

    static func shouldRunSearch(query: String, hasFilters: Bool) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasFilters { return true }
        return trimmed.count >= 2
    }

    /// 0 ms local preview over the cached Discover catalogue while typing (from character 1).
    static func localPreviewMatches(
        query: String,
        scope: SearchScope,
        anime: [AnimeCard],
        manga: [MangaCard],
        limit: Int = 12
    ) -> [EditorialSearchResultItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, limit > 0 else { return [] }

        func acronym(of title: String) -> String {
            let words = title.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .map { $0.lowercased() }
                .filter { $0.count >= 2 && $0.allSatisfy(\.isLetter) }
            guard words.count >= 3, words.count <= 10 else { return "" }
            return String(words.compactMap(\.first))
        }

        let loweredQuery = trimmed.lowercased()

        func matchRank(_ titles: [String?]) -> Double? {
            let candidates = titles.compactMap { raw -> String? in
                guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
                return value
            }
            var best: Double?
            for candidate in candidates {
                if let range = candidate.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) {
                    let rank: Double = range.lowerBound == candidate.startIndex ? 2.0 : 1.0
                    if best.map({ rank > $0 }) ?? true { best = rank }
                    continue
                }
                if loweredQuery.count >= 3, acronym(of: candidate) == loweredQuery {
                    let rank = 1.8
                    if best.map({ rank > $0 }) ?? true { best = rank }
                }
            }
            return best
        }

        var items: [EditorialSearchResultItem] = []
        if scope == .all || scope == .anime {
            for card in anime {
                if let rank = matchRank([card.title, card.titleEnglish, card.titleRomaji]) {
                    items.append(EditorialSearchResultItem(
                        id: "anime-\(card.id)",
                        media: card,
                        rank: rank,
                        popularity: card.popularity ?? 0
                    ))
                }
            }
        }
        if scope == .all || scope == .manga {
            for card in manga {
                if let rank = matchRank([card.title, card.titleEnglish, card.titleRomaji]) {
                    items.append(EditorialSearchResultItem(
                        id: "manga-\(card.id)",
                        media: card,
                        rank: rank,
                        popularity: card.popularity ?? 0
                    ))
                }
            }
        }

        items.sort { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
            if lhs.popularity != rhs.popularity { return lhs.popularity > rhs.popularity }
            return lhs.media.title.localizedCaseInsensitiveCompare(rhs.media.title) == .orderedAscending
        }
        return Array(items.prefix(limit))
    }

    /// The field prompt for the scope.
    static func prompt(for scope: SearchScope, german: Bool) -> String {
        switch scope {
        case .all: return german ? "Anime und Manga suchen" : "Search anime and manga"
        case .anime: return german ? "Anime suchen" : "Search anime"
        case .manga: return german ? "Manga suchen" : "Search manga"
        }
    }

    /// "No titles match '…'." (rulebook §14.6), or the refinements when there is no text.
    static func noResultsTitle(query: String, refinements: [SearchRefinement], german: Bool) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return german ? "Keine Titel passen zu \u{201E}\(trimmed)\u{201C}." : "No titles match \u{2018}\(trimmed)\u{2019}."
        }
        let names = refinements.map { $0.title(german: german) }.joined(separator: " · ")
        if names.isEmpty {
            return german ? "Keine Titel gefunden." : "No titles found."
        }
        return german ? "Keine Titel für \(names)." : "No titles for \(names)."
    }
}

// MARK: - Refinements

/// Refinement chips (multi-select): tactile neutral capsules distinct from scope words.
struct EditorialSearchFilterStrip: View {
    let refinements: [EditorialSearchView.SearchRefinement]
    @Binding var selectedRefinements: Set<EditorialSearchView.SearchRefinement>
    var gutter: CGFloat = KuroDesignSpacing.padding

    private func symbol(for refinement: EditorialSearchView.SearchRefinement) -> String {
        switch refinement {
        case .trending: return "flame"
        case .new, .newSeason: return "sparkles"
        case .classics: return "building.columns"
        case .hiddenGems: return "suit.diamond"
        case .airing: return "dot.radiowaves.left.and.right"
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(refinements, id: \.self) { refinement in
                    let isSelected = selectedRefinements.contains(refinement)
                    Button {
                        if isSelected {
                            selectedRefinements.remove(refinement)
                        } else {
                            selectedRefinements.insert(refinement)
                        }
                        KuroAccessibility.impactHaptic(.light)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: symbol(for: refinement))
                                .font(.system(size: 11, weight: .semibold))
                                .accessibilityHidden(true)
                            Text(refinement.title(german: KuroLocale.isGerman))
                                .font(.kuroCustom(12.5, weight: .medium, relativeTo: .footnote, maxSize: 22))
                                .lineLimit(1)
                        }
                        .foregroundStyle(isSelected ? Color.white : Color.kuroControlInk)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(isSelected ? Color.kuroControlInk : Color.kuroControlFill,
                                    in: Capsule(style: .continuous))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(isSelected ? Color.kuroControlInk : Color.black.opacity(0.05), lineWidth: 0.5)
                        )
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(KuroPressStyle(pressedScale: 0.96))
                    .kuroAnimation(KuroMotion.contact, value: isSelected)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    .accessibilityHint(KuroLocale.text("Narrows the results", "Grenzt die Ergebnisse ein"))
                }
            }
            .padding(.horizontal, gutter)
        }
        .kuroSwipeExclusionZone()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(KuroLocale.text("Refine", "Eingrenzen"))
    }
}

// MARK: - Search Bar

/// Rounded gallery-white search field on `#f4f4f5`, with clear button and focus outline.
struct EditorialSearchBar: View {
    @Binding var searchText: String
    var prompt: String = KuroLocale.text("Search anime and manga", "Anime und Manga suchen")
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: KuroDesignSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.kuroCustom(15, weight: .semibold, relativeTo: .body, maxSize: 24))
                .foregroundStyle(isFocused.wrappedValue ? Color.kuroControlInk : Color.kuroInkSecondary)
                .accessibilityHidden(true)

            TextField("", text: $searchText, prompt: Text(prompt).foregroundStyle(Color.kuroInkQuiet))
                .font(.kuroBody(weight: .regular))
                .foregroundStyle(Color.kuroInk)
                .focused(isFocused)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { onSubmit?() }
                .accessibilityLabel(prompt)

            if !searchText.isEmpty {
                Button {
                    KuroAccessibility.selectionHaptic()
                    searchText = ""
                    isFocused.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color.kuroInkQuiet)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(KuroLocale.text("Clear search", "Suche leeren"))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, searchText.isEmpty ? 14 : 2)
        .frame(minHeight: 48)
        .background(Color.kuroControlFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isFocused.wrappedValue ? Color.kuroControlInk.opacity(0.28) : Color.clear, lineWidth: 1)
        )
        .kuroAnimation(KuroMotion.contact, value: isFocused.wrappedValue)
    }
}

// MARK: - Idle state

/// Empty query: recent searches as compact chips, cached Trending strip, and (when offered) Browse.
private struct SearchIdleState: View {
    let recentSearches: [String]
    let trendingCards: [TasteCard]
    let showsMediumOnPopular: Bool
    let gutter: CGFloat
    let onPick: (String) -> Void
    let onRemove: (String) -> Void
    let onClear: () -> Void

    @Environment(\.kuroRoutes) private var routes
    @Environment(FeatureFlags.self) private var flags
    @Environment(GuestSession.self) private var guest: GuestSession?

    var body: some View {
        let german = KuroLocale.isGerman
        VStack(alignment: .leading, spacing: KuroDesignSpacing.xl) {
            if recentSearches.isEmpty && trendingCards.isEmpty {
                // No history and no cached posters: clean empty mark + optional Browse button.
                KuroEmptyView(headline: SearchIdleCopy.noHistory(german: german)) {
                    if DiscoverBrowseEntry.isOffered(flags: flags, guest: guest?.isGuest == true) {
                        KuroOutlineButton(KuroLocale.text("Explore by genre & year", "Nach Genre & Jahr entdecken")) {
                            routes.openBrowse()
                        }
                        .accessibilityIdentifier("search.browseEntry")
                    }
                }
            } else {
                if !recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        KuroSectionHeader(
                            KuroLocale.text("Recent", "Zuletzt"),
                            size: .title,
                            actionTitle: KuroLocale.text("Clear", "Löschen"),
                            action: onClear
                        )
                        .padding(.horizontal, gutter)

                        FlowLayout(spacing: 8) {
                            ForEach(recentSearches, id: \.self) { query in
                                HStack(spacing: 2) {
                                    Button {
                                        KuroAccessibility.impactHaptic(.light)
                                        onPick(query)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "clock.arrow.circlepath")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(Color.kuroMuted)
                                                .accessibilityHidden(true)
                                            Text(query)
                                                .font(.kuroCustom(13, weight: .medium, relativeTo: .footnote, maxSize: 22))
                                                .foregroundStyle(Color.kuroInk)
                                                .lineLimit(1)
                                        }
                                        .padding(.leading, 12)
                                        .padding(.trailing, 4)
                                        .frame(minHeight: 40)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(HomeContactStyle())
                                    .accessibilityHint(KuroLocale.text("Searches again", "Sucht erneut"))

                                    Button {
                                        onRemove(query)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Color.kuroInkQuiet)
                                            .frame(width: 32, height: 40)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(KuroLocale.text("Remove \(query)", "\(query) entfernen"))
                                }
                                .background(Color.kuroControlFill, in: Capsule(style: .continuous))
                            }
                        }
                        .padding(.horizontal, gutter)
                    }
                }

                if !trendingCards.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(KuroLocale.text("Popular right now", "Gerade beliebt"))
                            .font(.kuroCustom(19, weight: .semibold, relativeTo: .title3, maxSize: 32))
                            .tracking(-0.5)
                            .foregroundStyle(Color.kuroInk)
                            .padding(.horizontal, gutter)
                            .accessibilityAddTraits(.isHeader)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(trendingCards) { card in
                                    SearchIdlePosterTile(card: card, showsMedium: showsMediumOnPopular)
                                }
                            }
                            .padding(.horizontal, gutter)
                            .padding(.vertical, 4)
                        }
                        .kuroSwipeExclusionZone()
                    }
                }

                if DiscoverBrowseEntry.isOffered(flags: flags, guest: guest?.isGuest == true) {
                    KuroInkButton(KuroLocale.text("Explore by genre & year", "Nach Genre & Jahr entdecken"), role: .secondary) {
                        routes.openBrowse()
                    }
                    .accessibilityIdentifier("search.browseEntry")
                    .padding(.horizontal, gutter)
                }
            }
        }
        .padding(.top, recentSearches.isEmpty && trendingCards.isEmpty ? 0 : KuroDesignSpacing.md)
    }
}

/// Poster card inside Search's idle Popular strip: cover + corner quick-add badge + title + year.
private struct SearchIdlePosterTile: View {
    let card: TasteCard
    let showsMedium: Bool

    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    @Environment(\.kuroRoutes) private var routes

    private let width: CGFloat = 106
    private let height: CGFloat = 158

    private var factsLine: String? {
        DiscoverIssueCopy.facts(kind: card.media.kind, year: card.media.year, formatRaw: card.media.formatRaw,
                                episodes: nil, chapters: nil, length: false, german: KuroLocale.isGerman,
                                kindShown: showsMedium)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard !suppressCardTaps else { return }
                KuroAccessibility.impactHaptic(.light)
                routes.openMedia(MediaRoute(card.key))
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HomeArtwork(url: card.media.imageURL.flatMap(URL.init(string:)), maxPixelSize: 320,
                                placeholder: HomeInk.posterFill, seedHex: card.media.coverImageColor,
                                usesMaterialWash: true)
                        .frame(width: width, height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.10), radius: 5, y: 2.5)
                    if showsMedium {
                        DiscoverKindKicker(kind: card.media.kind)
                            .padding(.top, 8)
                    }
                    Text(KuroCardText.sanitizeTitleForCard(card.media.title))
                        .font(.kuroCustom(13, weight: .semibold, relativeTo: .footnote, maxSize: 22))
                        .tracking(-0.1)
                        .foregroundStyle(Color.kuroInk)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                        .padding(.top, showsMedium ? 3 : 8)
                    Text(factsLine ?? " ")
                        .font(.kuroCustom(11, relativeTo: .caption2, maxSize: 18))
                        .monospacedDigit()
                        .foregroundStyle(Color.kuroMuted)
                        .lineLimit(1)
                        .padding(.top, 2)
                        .accessibilityHidden(factsLine == nil)
                }
                .frame(width: width, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(HomeArtworkPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(DiscoverCardSpoken.label(title: card.media.title, kind: card.media.kind,
                                                         kindKicker: showsMedium, line: factsLine, isNew: false))
            .accessibilityHint(KuroLocale.text("Opens details", "Öffnet die Details"))
            .overlay(alignment: .topLeading) {
                DiscoverPlanKey(card: card, variant: .leaf, compact: true, badge: true)
                    .padding(.trailing, 1)
                    .padding(.bottom, 1)
                    .frame(width: width, height: height, alignment: .bottomTrailing)
            }
        }
        .frame(width: width, alignment: .topLeading)
    }
}

/// The empty query's words, EN/DE.
nonisolated enum SearchIdleCopy {
    /// No recent searches on this device yet.
    static func noHistory(german: Bool) -> String {
        german ? "Fang mit einem Titel an, den du liebst." : "Start with a title you love."
    }
}

/// No results: the rulebook line, a way to drop the refinements, and the catalogue entry.
private struct SearchNoResultsState: View {
    let title: String
    let hasRefinements: Bool
    let gutter: CGFloat
    let onClearRefinements: () -> Void

    @Environment(\.kuroRoutes) private var routes
    @Environment(FeatureFlags.self) private var flags
    @Environment(GuestSession.self) private var guest: GuestSession?

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
            Text(title)
                .font(.kuroTitle(weight: .regular))
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if hasRefinements {
                KuroInkButton(KuroLocale.text("Clear refinements", "Eingrenzungen entfernen"), role: .secondary, haptic: false) {
                    onClearRefinements()
                }
            }

            // Only where the pager has no Browse page (spec D2).
            if DiscoverBrowseEntry.isOffered(flags: flags, guest: guest?.isGuest == true) {
                KuroInkButton(KuroLocale.text("Explore by genre & year", "Nach Genre & Jahr entdecken"), role: .secondary) {
                    routes.openBrowse()
                }
            }
        }
        .padding(.horizontal, gutter)
        .padding(.top, KuroDesignSpacing.lg)
    }
}

// MARK: - Search Result Row

/// A picture-first index row: cover thumb, title (query words in semibold), one line, a saved mark.
struct SearchResultRow: View {
    let media: any MediaDisplayable
    let query: String
    var showsMedium: Bool = true
    var onOpen: (() -> Void)? = nil

    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @Environment(ClubsStore.self) private var clubs
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    @Environment(\.kuroRoutes) private var routes
    @ScaledMetric(relativeTo: .body) private var thumbWidth: CGFloat = 46

    private var isSaved: Bool {
        library.isTracked(media.libraryKey)
    }

    private var line: String {
        let german = KuroLocale.isGerman
        var parts: [String] = []
        if showsMedium { parts.append(media.kind == .anime ? "Anime" : "Manga") }
        if let detail = DiscoverFrameCopy.line(
            kind: media.kind,
            year: media.year,
            episodes: media.episodes,
            chapters: media.chapters,
            statusRaw: media.statusRaw,
            formatRaw: media.formatRaw,
            german: german,
            locale: KuroLocale.locale,
            timeZone: KuroLocale.timeZone
        ) {
            parts.append(detail)
        }
        return parts.joined(separator: " · ")
    }

    private func highlightedTitle(_ title: String, query: String) -> Text {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Text(title).foregroundColor(Color.kuroInk) }
        guard let r = title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return Text(title).foregroundColor(Color.kuroInk)
        }
        let prefix = Text(String(title[..<r.lowerBound])).foregroundColor(Color.kuroInkSecondary)
        let match = Text(String(title[r])).fontWeight(.bold).foregroundColor(Color.kuroInk)
        let suffix = Text(String(title[r.upperBound...])).foregroundColor(Color.kuroInkSecondary)
        return Text("\(prefix)\(match)\(suffix)")
    }

    var body: some View {
        let thumb = min(thumbWidth, 72)
        HStack(alignment: .center, spacing: 10) {
            Button {
                guard !suppressCardTaps else { return }
                KuroAccessibility.impactHaptic(.light)
                onOpen?()
                routes.openMedia(MediaRoute(media.libraryKey))
            } label: {
                HStack(alignment: .center, spacing: KuroDesignSpacing.md) {
                    DiscoverPicture(url: URL(string: media.imageURL ?? ""), maxPixelSize: 180)
                        .frame(width: thumb, height: floor(thumb / KuroCardMetrics.imageAspectRatio))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                        )

                    VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                        highlightedTitle(media.title, query: query)
                            .font(.kuroBody(weight: .medium))
                            .foregroundStyle(Color.kuroInk)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if !line.isEmpty {
                            Text(line)
                                .font(.kuroMeta())
                                .foregroundStyle(Color.kuroInkQuiet)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, KuroDesignSpacing.sm)
                .frame(minHeight: 68)
                .contentShape(Rectangle())
            }
            .buttonStyle(KuroPressStyle(pressedScale: 0.99))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text([media.title, line].filter { !$0.isEmpty }.joined(separator: ", ")))
            .accessibilityValue(isSaved ? KuroLocale.text("On your list", "Auf deiner Liste") : "")
            .accessibilityHint(KuroLocale.text("Opens details", "Öffnet die Details"))
            .accessibilityAddTraits(.isButton)
            .contextMenu {
                DiscoverFrameMenu(media: media, isSaved: isSaved, hasClubs: !clubs.myClubs.isEmpty)
            }

            // Quick-add status badge stays a sibling of the row button (never nested inside it).
            DiscoverPlanKey(card: TasteCard(displayable: media), variant: .leaf, compact: true, badge: true)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.kuroHairline)
                .frame(height: 0.5)
        }
    }
}

/// A result row's placeholder at the real row geometry.
struct SearchResultSkeletonRow: View {
    @ScaledMetric(relativeTo: .body) private var thumbWidth: CGFloat = 46

    var body: some View {
        let thumb = min(thumbWidth, 72)
        HStack(spacing: KuroDesignSpacing.md) {
            RoundedRectangle(cornerRadius: KuroRadius.xs, style: .continuous)
                .fill(Color.kuroBlack05)
                .frame(width: thumb, height: floor(thumb / KuroCardMetrics.imageAspectRatio))
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.kuroBlack05)
                    .frame(height: 14)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.kuroBlack05)
                    .frame(height: 11)
                    .frame(maxWidth: 160, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, KuroDesignSpacing.sm)
        .frame(minHeight: 64)
    }
}

#Preview {
    EditorialSearchView()
        .environment(AppComposition.shared.identity)
        .environment(AppComposition.shared.library)
        .environment(AppComposition.shared.search)
        .environment(AppComposition.shared.discovery)
        .environment(AppComposition.shared.clubs)
        .environment(AppComposition.shared.banner)
        .environment(AppComposition.shared.libraryActions)
        .environment(NetworkMonitor())
}
