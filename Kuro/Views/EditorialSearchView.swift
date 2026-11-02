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
                .padding(.bottom, KuroDesignSpacing.sm)

                Rectangle()
                    .fill(Color.kuroHairline)
                    .frame(height: 1)

                if let transientBannerMessage = banner.message {
                    KuroTransientBanner(message: transientBannerMessage)
                        .padding(.horizontal, gutter)
                        .padding(.vertical, KuroDesignSpacing.sm)
                }

                ScrollView(.vertical, showsIndicators: false) {
                    resultsContent(gutter: gutter)
                        .padding(.bottom, KuroDesignSpacing.xl)
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
            // Place the cursor once the sheet has settled.
            try? await Task.sleep(nanoseconds: 350_000_000)
            if trimmedQuery.isEmpty { isFieldFocused = true }
        }
        .onDisappear {
            searchTask?.cancel()
        }
        // Inside the Search journey this forwards (rows push); outside one it presents a journey.
        .routePresenter()
    }

    @ViewBuilder
    private func resultsContent(gutter: CGFloat) -> some View {
        let results = serverResults
        if !showsSearchContent {
            SearchIdleState(
                recentSearches: discovery.recentSearches,
                gutter: gutter,
                onPick: { query in
                    searchText = query
                    discovery.recordRecentSearch(query)
                },
                onRemove: { discovery.removeRecentSearch($0) },
                onClear: { discovery.clearRecentSearches() }
            )
        } else if results.isEmpty && (search.isSearching || isAwaitingResults) {
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { _ in
                    SearchResultSkeletonRow()
                        .padding(.horizontal, gutter)
                }
            }
            .padding(.top, KuroDesignSpacing.sm)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(KuroLocale.text("Searching", "Suche läuft"))
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
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                    SearchResultRow(media: item.media, query: searchText, showsMedium: scope == .all) {
                        discovery.recordRecentSearch(searchText)
                    }
                    .padding(.horizontal, gutter)
                    .onAppear {
                        // Infinite scroll: when the last row appears, try the next page.
                        if index == results.count - 1, search.hasMoreSearch, !search.isSearching {
                            Task { await loadMore() }
                        }
                    }
                }
                if search.isSearching {
                    KuroBusyMark(width: 44)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(KuroLocale.text("Loading more", "Lädt weitere"))
                }
            }
            .padding(.top, KuroDesignSpacing.xs)
        }
    }

    private func debounceSearch() {
        searchTask?.cancel()
        isAwaitingResults = Self.shouldRunSearch(query: trimmedQuery, hasFilters: activeSearchFilters != nil)
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
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

/// Refinement words (multi-select): ink words with an underline mark (rulebook §14.6).
struct EditorialSearchFilterStrip: View {
    let refinements: [EditorialSearchView.SearchRefinement]
    @Binding var selectedRefinements: Set<EditorialSearchView.SearchRefinement>
    var gutter: CGFloat = KuroDesignSpacing.padding

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: KuroDesignSpacing.lg) {
                ForEach(refinements, id: \.self) { refinement in
                    DiscoverWordButton(
                        title: refinement.title(german: KuroLocale.isGerman),
                        isSelected: selectedRefinements.contains(refinement)
                    ) {
                        if selectedRefinements.contains(refinement) {
                            selectedRefinements.remove(refinement)
                        } else {
                            selectedRefinements.insert(refinement)
                        }
                        KuroAccessibility.impactHaptic(.light)
                    }
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

/// The field: magnifier, text, a labelled clear key, a hairline that turns ink while focused.
struct EditorialSearchBar: View {
    @Binding var searchText: String
    var prompt: String = KuroLocale.text("Search anime and manga", "Anime und Manga suchen")
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: KuroDesignSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.kuroBody(weight: .regular))
                .foregroundStyle(Color.kuroInkQuiet)
                .accessibilityHidden(true)

            TextField("", text: $searchText, prompt: Text(prompt).foregroundStyle(Color.kuroInkQuiet))
                .font(.kuroTitleName(weight: .regular))
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
                    searchText = ""
                    isFocused.wrappedValue = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.kuroMeta(weight: .medium))
                        .foregroundStyle(Color.kuroInkQuiet)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(KuroLocale.text("Clear search", "Suche leeren"))
            }
        }
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isFocused.wrappedValue ? Color.kuroInk : Color.kuroHairline)
                .frame(height: 1)
        }
        .kuroAnimation(KuroMotion.settle, value: isFocused.wrappedValue)
    }
}

// MARK: - Idle state

/// The empty query: this account's recent searches (this device) and, where the pager has no
/// Browse page, the catalogue entry. A child
/// view so `routes` is the search sheet's own presenter (Browse opens on top of the sheet).
private struct SearchIdleState: View {
    let recentSearches: [String]
    let gutter: CGFloat
    let onPick: (String) -> Void
    let onRemove: (String) -> Void
    let onClear: () -> Void

    @Environment(\.kuroRoutes) private var routes
    @Environment(FeatureFlags.self) private var flags

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.xl) {
            if recentSearches.isEmpty {
                // No history: the refinements above, then the empty mark and one invitation (spec §5.3).
                KuroEmptyView(headline: SearchIdleCopy.noHistory(german: KuroLocale.isGerman)) {
                    // Only where the pager has no Browse page (spec D2).
                    if DiscoverBrowseEntry.isOffered(flags: flags) {
                        KuroOutlineButton(KuroLocale.text("Browse the catalogue", "Den Katalog durchstöbern")) {
                            routes.openBrowse()
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    KuroSectionHeader(
                        KuroLocale.text("Recent.", "Zuletzt gesucht."),
                        size: .title,
                        actionTitle: KuroLocale.text("Clear", "Löschen"),
                        action: onClear
                    )
                    .padding(.horizontal, gutter)

                    ForEach(recentSearches, id: \.self) { query in
                        HStack(spacing: KuroDesignSpacing.sm) {
                            Button {
                                KuroAccessibility.impactHaptic(.light)
                                onPick(query)
                            } label: {
                                Text(query)
                                    .font(.kuroBody(weight: .regular))
                                    .foregroundStyle(Color.kuroInk)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(KuroPressStyle())
                            .accessibilityHint(KuroLocale.text("Searches again", "Sucht erneut"))

                            Button {
                                onRemove(query)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.kuroMeta(weight: .regular))
                                    .foregroundStyle(Color.kuroInkQuiet)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(KuroLocale.text("Remove \(query)", "\(query) entfernen"))
                        }
                        .padding(.horizontal, gutter)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.kuroHairline)
                                .frame(height: 1)
                                .padding(.horizontal, gutter)
                        }
                    }
                }
            }

            // Only where the pager has no Browse page (spec D2); with no history it sits in the empty block.
            if !recentSearches.isEmpty && DiscoverBrowseEntry.isOffered(flags: flags) {
                KuroInkButton(KuroLocale.text("Browse the catalogue", "Den Katalog durchstöbern"), role: .secondary) {
                    routes.openBrowse()
                }
                .padding(.horizontal, gutter)
            }
        }
        .padding(.top, recentSearches.isEmpty ? 0 : KuroDesignSpacing.lg)
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
            if DiscoverBrowseEntry.isOffered(flags: flags) {
                KuroInkButton(KuroLocale.text("Browse the catalogue", "Den Katalog durchstöbern"), role: .secondary) {
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
        guard !q.isEmpty else { return Text(title) }
        guard let r = title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) else { return Text(title) }
        let prefix = String(title[..<r.lowerBound])
        let match = String(title[r])
        let suffix = String(title[r.upperBound...])
        return Text("\(prefix)\(Text(match).fontWeight(.semibold))\(suffix)")
    }

    var body: some View {
        let thumb = min(thumbWidth, 72)
        Button {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            onOpen?()
            routes.openMedia(MediaRoute(media.libraryKey))
        } label: {
            HStack(alignment: .center, spacing: KuroDesignSpacing.md) {
                DiscoverPicture(url: URL(string: media.imageURL ?? ""), maxPixelSize: 180)
                    .frame(width: thumb, height: floor(thumb / KuroCardMetrics.imageAspectRatio))
                    .clipShape(RoundedRectangle(cornerRadius: KuroRadius.xs, style: .continuous))

                VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                    highlightedTitle(media.title, query: query)
                        .font(.kuroBody(weight: .regular))
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

                if isSaved {
                    Image(systemName: "checkmark")
                        .font(.kuroMeta(weight: .medium))
                        .foregroundStyle(Color.kuroInkSecondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, KuroDesignSpacing.sm)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle(pressedScale: 0.99))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.kuroHairline)
                .frame(height: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([media.title, line].filter { !$0.isEmpty }.joined(separator: ", ")))
        .accessibilityValue(isSaved ? KuroLocale.text("On your list", "Auf deiner Liste") : "")
        .accessibilityHint(KuroLocale.text("Opens details", "Öffnet die Details"))
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            DiscoverFrameMenu(media: media, isSaved: isSaved, hasClubs: !clubs.myClubs.isEmpty)
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
