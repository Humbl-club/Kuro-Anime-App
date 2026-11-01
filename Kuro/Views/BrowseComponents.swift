import KuroCore
import KuroLibrary
import SwiftUI

// Browse helper components: the control bar (medium switch, filter words), the filter sheet, the
// equal-frame grid and its placeholders, and the empty state. Ink tokens only; words, not chips.

// MARK: - Filter Chip (used by the unreferenced genre picker sheet)
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
                .font(.kuroMeta(weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.kuroWhite : Color.kuroInkSecondary)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.kuroInk : Color.kuroCanvasQuiet)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(KuroLocale.text("Filters results", "Filtert die Ergebnisse"))
    }
}

extension DiscoveryStore.BrowseSort {
    func title(german: Bool) -> String {
        switch self {
        case .popular: return german ? "Beliebt" : "Popular"
        case .trending: return german ? "Im Trend" : "Trending"
        case .topRated: return german ? "Bestbewertet" : "Top rated"
        case .newlyAdded: return german ? "Neu im Katalog" : "Newly added"
        }
    }
}

// MARK: - Control Bar
struct BrowseControlBar: View {
    @Binding var showAnime: Bool
    @Binding var selectedSort: DiscoveryStore.BrowseSort
    @Binding var selectedStatusFilter: BrowseView.StatusFilter?
    @Binding var selectedLengthFilter: BrowseView.LengthFilter?
    @Binding var selectedGenre: String?
    @Binding var selectedDecade: BrowseView.DecadeFilter?
    @Binding var selectedFormat: BrowseView.FormatFilter?

    let allGenres: [String]
    let hasActiveFilters: Bool
    let activeFiltersLabel: String
    var gutter: CGFloat = KuroDesignSpacing.padding
    let onOpenFilters: () -> Void
    let onClear: () -> Void

    private var medium: Binding<MediaKind> {
        Binding(
            get: { showAnime ? .anime : .manga },
            set: { next in
                withAnimation(KuroMotion.resolve(KuroMotion.contextChange)) {
                    showAnime = next == .anime
                }
            }
        )
    }

    var body: some View {
        let german = KuroLocale.isGerman
        VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
            HStack(alignment: .center) {
                KuroMediumSwitch(selection: medium, size: .compact)
                Spacer(minLength: KuroDesignSpacing.md)
                Button {
                    KuroAccessibility.impactHaptic(.light)
                    onOpenFilters()
                } label: {
                    HStack(spacing: KuroDesignSpacing.xs) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.kuroMeta(weight: .regular))
                        Text(hasActiveFilters
                             ? KuroLocale.text("Filters · \(activeCount)", "Filter · \(activeCount)")
                             : KuroLocale.text("Filters", "Filter"))
                            .font(.kuroMeta(weight: .medium))
                    }
                    .foregroundStyle(Color.kuroInk)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(KuroPressStyle())
                .accessibilityLabel(hasActiveFilters
                                    ? KuroLocale.text("Filters, \(activeCount) active", "Filter, \(activeCount) aktiv")
                                    : KuroLocale.text("Filters", "Filter"))
                .accessibilityHint(KuroLocale.text("Opens all filters", "Öffnet alle Filter"))
            }
            .padding(.horizontal, gutter)
            .padding(.top, KuroDesignSpacing.sm)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: KuroDesignSpacing.lg) {
                    Menu {
                        ForEach(DiscoveryStore.BrowseSort.allCases, id: \.self) { sort in
                            Button(sort.title(german: german)) { selectedSort = sort }
                        }
                    } label: {
                        BrowseMenuWord(title: selectedSort.title(german: german), isActive: selectedSort != .popular)
                    }
                    .accessibilityLabel(KuroLocale.text("Sort: \(selectedSort.title(german: false))", "Sortierung: \(selectedSort.title(german: true))"))

                    Menu {
                        Button(KuroLocale.text("Any status", "Jeder Status")) { selectedStatusFilter = nil }
                        ForEach(BrowseView.StatusFilter.allCases, id: \.self) { s in
                            Button(s.title(german: german, anime: showAnime)) { selectedStatusFilter = s }
                        }
                    } label: {
                        BrowseMenuWord(
                            title: selectedStatusFilter?.title(german: german, anime: showAnime) ?? KuroLocale.text("Any status", "Jeder Status"),
                            isActive: selectedStatusFilter != nil
                        )
                    }

                    Menu {
                        Button(KuroLocale.text("Any length", "Jede Länge")) { selectedLengthFilter = nil }
                        let valid = BrowseView.LengthFilter.allCases.filter { f in
                            (showAnime && f != .manga200) || (!showAnime && f == .manga200)
                        }
                        ForEach(valid, id: \.self) { l in
                            Button(l.title(german: german)) { selectedLengthFilter = l }
                        }
                    } label: {
                        BrowseMenuWord(
                            title: selectedLengthFilter?.title(german: german) ?? KuroLocale.text("Any length", "Jede Länge"),
                            isActive: selectedLengthFilter != nil
                        )
                    }

                    Menu {
                        Button(KuroLocale.text("All genres", "Alle Genres")) { selectedGenre = nil }
                        ForEach(allGenres, id: \.self) { g in
                            Button(BrowseView.genreTitle(g, german: german)) { selectedGenre = g }
                        }
                    } label: {
                        BrowseMenuWord(
                            title: selectedGenre.map { BrowseView.genreTitle($0, german: german) } ?? KuroLocale.text("All genres", "Alle Genres"),
                            isActive: selectedGenre != nil
                        )
                    }

                    Menu {
                        Button(KuroLocale.text("Any year", "Jedes Jahr")) { selectedDecade = nil }
                        ForEach(BrowseView.DecadeFilter.allCases, id: \.self) { d in
                            Button(d.title(german: german)) { selectedDecade = d }
                        }
                    } label: {
                        BrowseMenuWord(
                            title: selectedDecade?.title(german: german) ?? KuroLocale.text("Any year", "Jedes Jahr"),
                            isActive: selectedDecade != nil
                        )
                    }

                    Menu {
                        Button(KuroLocale.text("Any format", "Jedes Format")) { selectedFormat = nil }
                        ForEach(BrowseView.FormatFilter.allCases, id: \.self) { f in
                            Button(f.title(german: german)) { selectedFormat = f }
                        }
                    } label: {
                        BrowseMenuWord(
                            title: selectedFormat?.title(german: german) ?? KuroLocale.text("Any format", "Jedes Format"),
                            isActive: selectedFormat != nil
                        )
                    }

                    if hasActiveFilters {
                        Button {
                            KuroAccessibility.impactHaptic(.light)
                            onClear()
                        } label: {
                            Text(KuroLocale.text("Clear", "Zurücksetzen"))
                                .font(.kuroMeta(weight: .medium))
                                .foregroundStyle(Color.kuroInk)
                                .underline()
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(KuroPressStyle())
                        .accessibilityLabel(KuroLocale.text("Clear filters", "Filter zurücksetzen"))
                    }
                }
                .padding(.horizontal, gutter)
            }
            .kuroSwipeExclusionZone()

            if hasActiveFilters {
                Text(activeFiltersLabel)
                    .font(.kuroMeta())
                    .foregroundStyle(Color.kuroInkSecondary)
                    .lineLimit(2)
                    .padding(.horizontal, gutter)
                    .padding(.bottom, KuroDesignSpacing.xs)
                    .accessibilityLabel(KuroLocale.text("Active filters: \(activeFiltersLabel)", "Aktive Filter: \(activeFiltersLabel)"))
            }

            Rectangle()
                .fill(Color.kuroHairline)
                .frame(height: 1)
        }
        .background(Color.kuroCanvasPage)
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

/// A filter menu's label: an ink word with a disclosure chevron, underlined while it narrows.
struct BrowseMenuWord: View {
    let title: String
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
            HStack(spacing: KuroDesignSpacing.xs) {
                Text(title)
                    .font(.kuroMeta(weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.down")
                    .font(.kuroCaption(weight: .regular))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(isActive ? Color.kuroInk : Color.kuroInkSecondary)
            Rectangle()
                .fill(isActive ? Color.kuroInk : Color.clear)
                .frame(width: 16, height: 1.5)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

// MARK: - Filters Sheet
struct BrowseFiltersSheet: View {
    struct Selection {
        var showAnime: Bool
        var sort: DiscoveryStore.BrowseSort
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
        selectedSort: DiscoveryStore.BrowseSort,
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

    private var medium: Binding<MediaKind> {
        Binding(
            get: { draft.showAnime ? .anime : .manga },
            set: { next in
                draft.showAnime = next == .anime
                // A length that does not exist for the other medium is dropped.
                if let length = draft.length, (draft.showAnime && length == .manga200) || (!draft.showAnime && length != .manga200) {
                    draft.length = nil
                }
            }
        )
    }

    var body: some View {
        let german = KuroLocale.isGerman
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                    KuroMediumSwitch(selection: medium, size: .compact)

                    group(KuroLocale.text("Sort", "Sortierung")) {
                        ForEach(DiscoveryStore.BrowseSort.allCases, id: \.self) { s in
                            DiscoverWordButton(title: s.title(german: german), isSelected: draft.sort == s) {
                                draft.sort = s
                            }
                        }
                    }

                    group(KuroLocale.text("Status", "Status")) {
                        DiscoverWordButton(title: KuroLocale.text("Any", "Alle"), isSelected: draft.status == nil) {
                            draft.status = nil
                        }
                        ForEach(BrowseView.StatusFilter.allCases, id: \.self) { s in
                            DiscoverWordButton(title: s.title(german: german, anime: draft.showAnime), isSelected: draft.status == s) {
                                draft.status = s
                            }
                        }
                    }

                    group(draft.showAnime ? KuroLocale.text("Episodes", "Folgen") : KuroLocale.text("Chapters", "Kapitel")) {
                        DiscoverWordButton(title: KuroLocale.text("Any", "Alle"), isSelected: draft.length == nil) {
                            draft.length = nil
                        }
                        let valid = BrowseView.LengthFilter.allCases.filter { f in
                            (draft.showAnime && f != .manga200) || (!draft.showAnime && f == .manga200)
                        }
                        ForEach(valid, id: \.self) { l in
                            DiscoverWordButton(title: l.title(german: german), isSelected: draft.length == l) {
                                draft.length = l
                            }
                        }
                    }

                    group(KuroLocale.text("Genre", "Genre")) {
                        DiscoverWordButton(title: KuroLocale.text("All", "Alle"), isSelected: draft.genre == nil) {
                            draft.genre = nil
                        }
                        ForEach(allGenres, id: \.self) { g in
                            DiscoverWordButton(title: BrowseView.genreTitle(g, german: german), isSelected: draft.genre == g) {
                                draft.genre = g
                            }
                        }
                    }

                    group(KuroLocale.text("Year", "Jahr")) {
                        DiscoverWordButton(title: KuroLocale.text("Any", "Alle"), isSelected: draft.decade == nil) {
                            draft.decade = nil
                        }
                        ForEach(BrowseView.DecadeFilter.allCases, id: \.self) { d in
                            DiscoverWordButton(title: d.title(german: german), isSelected: draft.decade == d) {
                                draft.decade = d
                            }
                        }
                    }

                    group(KuroLocale.text("Format", "Format")) {
                        DiscoverWordButton(title: KuroLocale.text("Any", "Alle"), isSelected: draft.format == nil) {
                            draft.format = nil
                        }
                        ForEach(BrowseView.FormatFilter.allCases, id: \.self) { f in
                            DiscoverWordButton(title: f.title(german: german), isSelected: draft.format == f) {
                                draft.format = f
                            }
                        }
                    }
                }
                .padding(.horizontal, KuroDesignSpacing.padding)
                .padding(.top, KuroDesignSpacing.md)
                .padding(.bottom, KuroDesignSpacing.xl)
                .kuroReadableWidth()
            }
            .background(Color.kuroCanvasPage)
            .navigationTitle(KuroLocale.text("Filters", "Filter"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(KuroLocale.text("Cancel", "Abbrechen")) {
                        KuroAccessibility.impactHaptic(.light)
                        dismiss()
                    }
                    .font(.kuroMeta(weight: .regular))
                    .foregroundStyle(Color.kuroInk)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(KuroLocale.text("Apply", "Anwenden")) {
                        KuroAccessibility.impactHaptic(.light)
                        onApply(draft)
                        dismiss()
                    }
                    .font(.kuroMeta(weight: .semibold))
                    .foregroundStyle(Color.kuroInk)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// One labelled group of choice words, wrapping across lines.
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
            Text(title)
                .font(.kuroMeta(weight: .semibold))
                .foregroundStyle(Color.kuroInk)
                .accessibilityAddTraits(.isHeader)
            FlowLayout(spacing: KuroDesignSpacing.md) {
                content()
            }
        }
    }
}

// MARK: - Grid

/// Grid metrics shared by the grid and its placeholders (columns follow the width, at least two).
private struct BrowseGridMetrics {
    let gutter: CGFloat
    let columns: Int
    let frameWidth: CGFloat

    init(width: CGFloat, accessibilitySize: Bool = false) {
        gutter = DiscoverLayout.gutter(for: width)
        let inner = max(0, width - gutter * 2)
        columns = DiscoverLayout.columnCount(for: inner, accessibilitySize: accessibilitySize)
        frameWidth = DiscoverLayout.gridFrameWidth(for: inner, columns: columns)
    }

    var gridItems: [GridItem] {
        Array(repeating: GridItem(.fixed(frameWidth), spacing: DiscoverLayout.frameSpacing, alignment: .top), count: columns)
    }
}

struct BrowseGridSkeleton: View {
    let width: CGFloat

    var body: some View {
        BrowsePlaceholderGrid(width: width, count: 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(KuroLocale.text("Loading", "Wird geladen"))
    }
}

struct BrowsePaginationSkeleton: View {
    let width: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        BrowsePlaceholderGrid(width: width, count: BrowseGridMetrics(width: width, accessibilitySize: dynamicTypeSize.isAccessibilitySize).columns * 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(KuroLocale.text("Loading more", "Lädt weitere"))
    }
}

private struct BrowsePlaceholderGrid: View {
    let width: CGFloat
    let count: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let metrics = BrowseGridMetrics(width: width, accessibilitySize: dynamicTypeSize.isAccessibilitySize)
        LazyVGrid(columns: metrics.gridItems, alignment: .leading, spacing: KuroDesignSpacing.lg) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                    RoundedRectangle(cornerRadius: KuroRadius.xs, style: .continuous)
                        .fill(Color.kuroBlack05)
                        .frame(width: metrics.frameWidth, height: floor(metrics.frameWidth / KuroCardMetrics.imageAspectRatio))
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.kuroBlack05)
                        .frame(width: metrics.frameWidth * 0.8, height: 12)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.kuroBlack05)
                        .frame(width: metrics.frameWidth * 0.5, height: 10)
                }
            }
        }
        .padding(.horizontal, metrics.gutter)
        .padding(.vertical, KuroDesignSpacing.md)
    }
}

// MARK: - Browse Grid
struct BrowseGrid: View {
    let items: [any MediaDisplayable]
    let width: CGFloat
    let loadMore: () async -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let metrics = BrowseGridMetrics(width: width, accessibilitySize: dynamicTypeSize.isAccessibilitySize)
        LazyVGrid(columns: metrics.gridItems, alignment: .leading, spacing: KuroDesignSpacing.lg) {
            ForEach(items, id: \.stableKey) { media in
                DiscoverFrame(media: media, width: metrics.frameWidth)
                    .onAppear {
                        if media.stableKey == items.last?.stableKey {
                            Task { await loadMore() }
                        }
                    }
            }
        }
        .padding(.horizontal, metrics.gutter)
        .padding(.vertical, KuroDesignSpacing.md)
    }
}

// MARK: - Browse Empty State
struct BrowseEmptyState: View {
    let activeFilterCount: Int
    let activeFilterSummary: String
    let onClearFilters: () -> Void

    var body: some View {
        VStack(spacing: KuroDesignSpacing.md) {
            if activeFilterCount > 0 {
                KuroStateView(
                    .empty,
                    title: KuroLocale.text("No titles match these filters.", "Keine Titel passen zu diesen Filtern."),
                    message: activeFilterSummary
                )
                KuroInkButton(KuroLocale.text("Clear filters", "Filter zurücksetzen"), role: .secondary) {
                    onClearFilters()
                }
                .frame(maxWidth: 280)
            } else {
                KuroStateView(
                    .empty,
                    title: KuroLocale.text("No titles here yet.", "Hier sind noch keine Titel."),
                    message: KuroLocale.text("Pull to refresh.", "Zum Aktualisieren ziehen.")
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, KuroDesignSpacing.xl)
    }
}

#Preview {
    BrowseView()
        .environment(AppComposition.shared.identity)
        .environment(AppComposition.shared.library)
        .environment(AppComposition.shared.discovery)
        .environment(AppComposition.shared.social)
        .environment(AppComposition.shared.availability)
        .environment(AppComposition.shared.clubs)
        .environment(AppComposition.shared.flags)
        .environment(AppComposition.shared.libraryActions)
        .environment(NetworkMonitor())
}
