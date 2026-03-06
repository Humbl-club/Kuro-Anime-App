// Editorial Search View
// Vogue/Miu Miu inspired search experience
// Refined search bar, elegant filters, sophisticated results

import SwiftUI

struct EditorialSearchResultItem: Identifiable {
    let id: String
    let media: any MediaDisplayable
}

struct EditorialSearchView: View {
    @Environment(SupabaseService.self) private var supabaseService
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var scope: SearchScope = .all
    @State private var selectedRefinements: Set<SearchRefinement> = []

    enum SearchScope: String, CaseIterable {
        case all = "ALL"
        case anime = "ANIME"
        case manga = "MANGA"
    }

    enum SearchRefinement: String, CaseIterable, Hashable {
        case trending = "TRENDING"
        case new = "NEW"
        case newSeason = "NEW SEASON"
        case classics = "CLASSICS"
        case hiddenGems = "HIDDEN GEMS"
        case airing = "AIRING"
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

    private var activeSearchFilters: SupabaseService.SearchFilters? {
        var filters = SupabaseService.SearchFilters()
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

    private var showsSearchContent: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || activeSearchFilters != nil
    }

    private var serverResults: [EditorialSearchResultItem] {
        let anime = supabaseService.searchAnimeItems.map { EditorialSearchResultItem(id: "anime-\($0.id)", media: $0) }
        let manga = supabaseService.searchMangaItems.map { EditorialSearchResultItem(id: "manga-\($0.id)", media: $0) }
        return anime + manga
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Editorial Search Bar
                EditorialSearchBar(searchText: $searchText)
                    .padding(.horizontal, EditorialLayout.marginEditorial)
                    .padding(.top, EditorialLayout.gutterMedium)
                    .padding(.bottom, EditorialLayout.gutterSmall)

                EditorialScopeToggle(scope: $scope)
                    .padding(.horizontal, EditorialLayout.marginEditorial)
                    .padding(.bottom, EditorialLayout.gutterSmall)

                if !availableRefinements.isEmpty {
                    EditorialSearchFilterStrip(
                        refinements: availableRefinements,
                        selectedRefinements: $selectedRefinements
                    )
                    .padding(.bottom, EditorialLayout.gutterMedium)
                }

                // Search Results
                ScrollView(.vertical, showsIndicators: false) {
                    if showsSearchContent {
                        if serverResults.isEmpty && !supabaseService.isSearching {
                            EditorialSearchEmpty(searchText: emptyStateQueryText) { suggestion in
                                searchText = suggestion
                            }
                        } else {
                            EditorialSearchResults(
                                results: serverResults,
                                query: searchText,
                                isLoading: supabaseService.isSearching,
                                hasMore: supabaseService.hasMoreSearch
                            ) {
                                if scope == .all {
                                    await supabaseService.fetchNextCombinedSearchPage()
                                } else {
                                    await supabaseService.fetchNextSearchPage()
                                }
                            }
                        }
                    } else {
                        EditorialSearchPlaceholder()
                    }
                }
                .scrollDisabled(false)
                .refreshable {
                    await supabaseService.refreshSearch()
                }
                .background(Color.kuroBackground)
            }
        }
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
            // No prefetch required: search and filter results are server-driven + paged.
        }
    }

    private var emptyStateQueryText: String {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return availableRefinements
            .filter { selectedRefinements.contains($0) }
            .map(\.rawValue)
            .joined(separator: " · ")
    }

    private func debounceSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled {
                await runSearch(reset: true)
            }
        }
    }

    private func runSearch(reset: Bool) async {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        supabaseService.setSearchFilters(activeSearchFilters)

        // Avoid blanking the UI for very short queries; wait until the user has typed enough.
        if trimmed.count < 2 && activeSearchFilters == nil {
            return
        }

        if reset {
            switch scope {
            case .all:
                supabaseService.resetCombinedSearch(query: trimmed)
            case .anime:
                supabaseService.resetSearch(query: trimmed, isManga: false)
            case .manga:
                supabaseService.resetSearch(query: trimmed, isManga: true)
            }
        }

        if trimmed.isEmpty { return }
        if scope == .all {
            await supabaseService.fetchNextCombinedSearchPage()
        } else {
            await supabaseService.fetchNextSearchPage()
        }
    }
}

struct EditorialScopeToggle: View {
    @Binding var scope: EditorialSearchView.SearchScope

    var body: some View {
        HStack(spacing: 16) {
            ForEach(EditorialSearchView.SearchScope.allCases, id: \.self) { s in
                Button(action: {
                    withAnimation(KuroAnimation.editorial) {
                        scope = s
                    }
                    KuroAccessibility.impactHaptic(.light)
                }) {
                    Text(s.rawValue)
                        .font(.kuroMicro(weight: scope == s ? .medium : .light))
                        .tracking(1.8)
                        .foregroundColor(scope == s ? .black : .black.opacity(0.4))
                        .padding(.vertical, 8)
                        .overlay(
                            Rectangle()
                                .fill(Color.black)
                                .frame(height: 1.5)
                                .opacity(scope == s ? 1 : 0),
                            alignment: .bottom
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityAddTraits(scope == s ? .isSelected : [])
                .accessibilityHint("Filters search scope")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }
}

struct EditorialSearchFilterStrip: View {
    let refinements: [EditorialSearchView.SearchRefinement]
    @Binding var selectedRefinements: Set<EditorialSearchView.SearchRefinement>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DISCOVERY REFINEMENTS")
                .font(.kuroMicro(weight: .medium))
                .tracking(1.4)
                .foregroundColor(.kuroTextTertiary)
                .padding(.horizontal, EditorialLayout.marginEditorial)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(refinements, id: \.self) { refinement in
                        EditorialCategoryPill(
                            title: refinement.rawValue,
                            isSelected: selectedRefinements.contains(refinement)
                        ) {
                            withAnimation(KuroAnimation.editorialBounce) {
                                if selectedRefinements.contains(refinement) {
                                    selectedRefinements.remove(refinement)
                                } else {
                                    selectedRefinements.insert(refinement)
                                }
                            }
                            KuroAccessibility.impactHaptic(.light)
                        }
                    }
                }
                .padding(.horizontal, EditorialLayout.marginEditorial)
            }
            .kuroSwipeExclusionZone()
        }
    }
}

// MARK: - Editorial Search Bar
struct EditorialSearchBar: View {
    @Binding var searchText: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .ultraLight))
                .foregroundColor(.kuroTextTertiary)

            TextField("", text: $searchText, prompt: Text("SEARCH").font(.kuroCaption()).tracking(1.8))
                .font(.kuroBody())
                .tracking(0.4)
                .foregroundColor(.black)
                .focused($isFocused)
                .textFieldStyle(PlainTextFieldStyle())

            if !searchText.isEmpty {
                Button(action: {
                    withAnimation(KuroAnimation.fast) {
                        searchText = ""
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.kuroTextTertiary)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.black.opacity(0.03))
                .overlay(
                    Rectangle()
                        .fill(Color.black.opacity(isFocused ? 0.15 : 0.08))
                        .frame(height: 1),
                    alignment: .bottom
                )
        )
        .animation(KuroAnimation.editorial, value: isFocused)
    }
}

// MARK: - Editorial Category Filters
struct EditorialCategoryFilters: View {
    let categories: [String]
    @Binding var selectedCategories: Set<String>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(categories, id: \.self) { category in
                    EditorialCategoryPill(
                        title: category,
                        isSelected: selectedCategories.contains(category)
                    ) {
                        withAnimation(KuroAnimation.editorialBounce) {
                            if selectedCategories.contains(category) {
                                selectedCategories.remove(category)
                            } else {
                                selectedCategories.insert(category)
                            }
                        }
                        KuroAccessibility.impactHaptic(.light)
                    }
                }
            }
            .padding(.horizontal, EditorialLayout.marginEditorial)
        }
        .kuroSwipeExclusionZone()
    }
}

// MARK: - Editorial Category Pill
struct EditorialCategoryPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.kuroMicro())
                .tracking(2.0)
                .foregroundColor(isSelected ? .white : .black.opacity(0.6))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.black : Color.clear)
                        .overlay(
                            Capsule()
                                .stroke(Color.black.opacity(isSelected ? 0.0 : 0.2), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Filters results")
    }
}

// MARK: - Editorial Search Results
struct EditorialSearchResults: View {
    let results: [EditorialSearchResultItem]
    let query: String
    let isLoading: Bool
    let hasMore: Bool
    let loadMore: () async -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Result count
            HStack {
                Text("\(results.count) RESULTS")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(.black.opacity(0.5))

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // Results as list with dividers
            VStack(spacing: 0) {
                if results.isEmpty && isLoading {
                    ForEach(0..<8, id: \.self) { _ in
                        SearchResultSkeletonRow()
                            .padding(.horizontal, 20)
                        Rectangle()
                            .fill(Color.black.opacity(0.08))
                            .frame(height: 0.5)
                            .padding(.horizontal, 20)
                    }
                }
                ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                    VStack(spacing: 0) {
                        SearchResultRow(media: item.media, query: query)
                            .padding(.horizontal, 20)
                            .onAppear {
                                // Infinite scroll: when the last visible row appears, try fetching the next page.
                                if index == results.count - 1, hasMore, !isLoading {
                                    Task { await loadMore() }
                                }
                            }

                        Rectangle()
                            .fill(Color.black.opacity(0.08))
                            .frame(height: 0.5)
                            .padding(.horizontal, 20)
                    }
                }
            }

            if isLoading {
                ProgressView()
                    .padding(.vertical, 16)
            }
        }
        .padding(.top, 12)
    }
}

// MARK: - Search Result Row
struct SearchResultRow: View {
    let media: any MediaDisplayable
    let query: String
    @State private var showDetail = false
    @State private var showAddToList = false
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    private var mediaTypeLabel: String {
        switch media.kind {
        case .anime: return "ANIME"
        case .manga: return "MANGA"
        }
    }

    private var mediaType: String {
        media.kind.rawValue
    }

    private var isSaved: Bool {
        supabaseService.isInCollection(mediaId: media.id, mediaType: mediaType)
    }

    private func highlightedTitle(_ title: String, query: String) -> Text {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Text(title) }
        guard let r = title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) else { return Text(title) }
        return Text(title[..<r.lowerBound])
        + Text(title[r]).fontWeight(.semibold)
        + Text(title[r.upperBound...])
    }

    var body: some View {
        Button(action: {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        }) {
            HStack(spacing: 12) {
                // Thumbnail
                KuroCachedAsyncImage(url: URL(string: media.imageURL ?? ""), maxPixelSize: 180) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 90)
                            .clipped()
                    case .failure, .empty:
                        Rectangle()
                            .fill(Color.black.opacity(0.05))
                            .frame(width: 60, height: 90)
                    @unknown default:
                        EmptyView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    highlightedTitle(media.title, query: query)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.black)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(media.year)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.black.opacity(0.6))

                        if let episodes = media.episodes, episodes > 0 {
                            Text("· \(episodes) eps")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(.black.opacity(0.6))
                        }

                        if let rating = media.rating, rating > 0 {
                            Text("·")
                                .foregroundColor(.black.opacity(0.4))
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                Text(String(format: "%.1f", rating))
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(.black.opacity(0.8))
                        }
                    }

                }

                Spacer()

                VStack(alignment: .trailing, spacing: 10) {
                    HStack(spacing: 8) {
                        if isSaved {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.black.opacity(0.55))
                                .accessibilityHidden(true)
                        }
                        MediaTypeBadge(label: mediaTypeLabel)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.kuroTextTertiary)
                }
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText())
        .accessibilityHint("Opens details")
        .contextMenu {
            Button(action: {
                KuroAccessibility.impactHaptic(.light)
                supabaseService.toggleInCollection(mediaId: media.id, mediaType: mediaType)
            }) {
                Label(
                    isSaved ? "Remove from List" : "Quick Add (Planned)",
                    systemImage: isSaved ? "minus.circle" : "plus.circle"
                )
            }

            Button(action: {
                KuroAccessibility.impactHaptic(.light)
                showAddToList = true
            }) {
                Label(
                    isSaved ? "Edit List" : "Add to List\u{2026}",
                    systemImage: "slider.horizontal.3"
                )
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
        parts.append(mediaTypeLabel.capitalized)
        parts.append(media.title)
        if !media.year.isEmpty { parts.append(media.year) }
        if let episodes = media.episodes, episodes > 0 { parts.append("\(episodes) episodes") }
        if let chapters = media.chapters, chapters > 0 { parts.append("\(chapters) chapters") }
        if let rating = media.rating, rating > 0 { parts.append(String(format: "Rating %.1f", rating)) }
        if isSaved { parts.append("Saved") }
        return Text(parts.joined(separator: ", "))
    }
}

struct MediaTypeBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .medium))
            .tracking(1.2)
            .foregroundColor(.black.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.04))
                    .overlay(
                        Capsule().stroke(Color.black.opacity(0.12), lineWidth: 0.5)
                    )
            )
            .accessibilityHidden(true)
    }
}

struct SearchResultSkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.05))
                .frame(width: 60, height: 90)
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 12)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black.opacity(0.05))
                    .frame(height: 10)
                    .frame(maxWidth: 160, alignment: .leading)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.05))
                .frame(width: 46, height: 18)
        }
        .padding(.vertical, 12)
        .redacted(reason: .placeholder)
    }
}

// MARK: - Editorial Search Empty
struct EditorialSearchEmpty: View {
    let searchText: String
    var onSuggestionTap: ((String) -> Void)? = nil

    private let suggestions = [
        "Attack on Titan",
        "Jujutsu Kaisen",
        "One Piece",
        "Chainsaw Man"
    ]

    var body: some View {
        VStack(spacing: EditorialLayout.gutterMedium) {
            Spacer()

            VStack(spacing: 12) {
                EditorialLayout.divider(thickness: 1, opacity: 0.15)
                    .frame(width: 60)

                Text("NO RESULTS")
                    .font(.kuroHeadline())
                    .tracking(1.5)
                    .foregroundColor(.kuroTextTertiary)

                if !searchText.isEmpty {
                    Text("No matches for '\(searchText)'")
                        .font(.kuroBody())
                        .tracking(0.5)
                        .foregroundColor(.black.opacity(0.4))
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    Text("TRY SEARCHING FOR")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(2.0)
                        .foregroundColor(.black.opacity(0.35))
                        .padding(.top, 8)

                    VStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { title in
                            Button(action: {
                                KuroAccessibility.impactHaptic(.light)
                                onSuggestionTap?(title)
                            }) {
                                Text(title)
                                    .font(.kuroBody(weight: .light))
                                    .tracking(0.4)
                                    .foregroundColor(.black.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: 280)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

// MARK: - Editorial Search Placeholder
struct EditorialSearchPlaceholder: View {
    var body: some View {
        VStack(spacing: EditorialLayout.gutterLarge) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundColor(.black.opacity(0.12))

                VStack(spacing: 8) {
                    Text("DISCOVER")
                        .font(.kuroDisplay())
                        .tracking(1.0)
                        .foregroundColor(.kuroTextTertiary)

                    Text("Begin your search for the extraordinary")
                        .font(.kuroBody())
                        .tracking(0.5)
                        .foregroundColor(.kuroTextTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 280)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

#Preview {
    EditorialSearchView()
        .environment(SupabaseService.shared)
}
