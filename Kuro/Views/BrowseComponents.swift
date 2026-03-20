import SwiftUI

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
                .font(.kuroMicro(weight: isSelected ? .semibold : .regular))
                .tracking(1.0)
                .foregroundColor(isSelected ? .kuroWhite : .kuroBlack60)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.kuroBlack : Color.kuroBlack05)
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
        VStack(spacing: 10) {
            HStack {
                BrowseModeToggle(showAnime: $showAnime)
                Spacer()
                Button(action: {
                    KuroAccessibility.impactHaptic(.light)
                    onOpenFilters()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.kuroCaption(weight: .semibold))
                        Text("FILTERS")
                            .font(.kuroMicro(weight: .semibold))
                            .tracking(1.2)
                        if hasActiveFilters {
                            Text("\(activeCount)")
                                .font(.kuroMicro(weight: .bold))
                                .foregroundColor(.kuroWhite)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.kuroBlack))
                                .accessibilityHidden(true)
                        }
                    }
                    .foregroundColor(.kuroBlack)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.kuroBlack05)
                            .overlay(Capsule().stroke(Color.kuroBlack12, lineWidth: 0.5))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hasActiveFilters ? "Filters, \(activeCount) active" : "Filters")
                .accessibilityHint("Opens filter editor")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

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
                        .font(.kuroMicro(weight: .regular))
                        .tracking(1.0)
                        .foregroundColor(.kuroTextSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 2)
                .accessibilityLabel("Active filters: \(activeFiltersLabel)")
            }

            Rectangle()
                .fill(Color.kuroBlack08)
                .frame(height: 0.5)
        }
        .background(
            LinearGradient(
                colors: [Color.kuroWhite, Color.kuroWhite, Color.kuroBlack02],
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
                    .font(.kuroCaption(weight: showAnime ? .semibold : .regular))
                    .tracking(1.0)
                    .foregroundColor(showAnime ? .kuroBlack : .kuroTextTertiary)
                    .padding(.vertical, 6)
                    .overlay(
                        Rectangle()
                            .fill(Color.kuroBlack)
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
                    .font(.kuroCaption(weight: showAnime ? .regular : .semibold))
                    .tracking(1.0)
                    .foregroundColor(showAnime ? .kuroTextTertiary : .kuroBlack)
                    .padding(.vertical, 6)
                    .overlay(
                        Rectangle()
                            .fill(Color.kuroBlack)
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
                .font(.kuroCaption(weight: .semibold))
            Text(label)
                .font(.kuroMicro(weight: .semibold))
                .tracking(1.0)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.kuroMicro(weight: .semibold))
                .opacity(0.55)
        }
        .foregroundColor(isActive ? .kuroWhite : .kuroBlack70)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(isActive ? Color.kuroBlack : Color.kuroBlack05)
                .overlay(Capsule().stroke(isActive ? Color.clear : Color.kuroBlack12, lineWidth: 0.5))
        )
    }
}

struct BrowseResultsHeader: View {
    let title: String
    let subtitle: String
    let countLabel: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.6)
                    .foregroundColor(.kuroTextSecondary)
                Text(subtitle)
                    .font(.kuroMicro(weight: .light))
                    .foregroundColor(.kuroTextTertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Text(countLabel)
                .font(.kuroMicro(weight: .medium))
                .tracking(1.2)
                .foregroundColor(.kuroTextTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.kuroBlack05)
                )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.kuroBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.kuroBlack08, lineWidth: 0.8)
                )
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
        let height = max(204, floor(width * 0.5))

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
                            .fill(Color.kuroBlack05)
                            .frame(width: width, height: height)
                    }
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                LinearGradient(
                    colors: [Color.kuroBlack.opacity(0.0), Color.kuroBlack75],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("PICK FOR YOU")
                            .font(.kuroMicro(weight: .semibold))
                            .tracking(1.8)
                            .foregroundColor(.kuroWhite80)
                        Spacer()
                        if isInCollection {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.kuroBody(weight: .semibold))
                                .foregroundColor(.kuroWhite85)
                        }
                    }

                    Text(media.title)
                        .font(.kuroHeadline(weight: .semibold))
                        .foregroundColor(.kuroWhite)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Text(media.year)
                            .font(.kuroCaption(weight: .regular))
                            .foregroundColor(.kuroWhite80)

                        if let episodes = media.episodes, episodes > 0 {
                            Text("· \(episodes) eps")
                                .font(.kuroCaption(weight: .regular))
                                .foregroundColor(.kuroWhite80)
                        } else if let chapters = media.chapters, chapters > 0 {
                            Text("· \(chapters) ch")
                                .font(.kuroCaption(weight: .regular))
                                .foregroundColor(.kuroWhite80)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.kuroCaption(weight: .semibold))
                            .foregroundColor(.kuroWhite90)
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
                    .font(.kuroCaption(weight: .regular))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        KuroAccessibility.impactHaptic(.light)
                        onApply(draft)
                        dismiss()
                    }
                    .font(.kuroCaption(weight: .semibold))
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
            .font(.kuroMicro(weight: .semibold))
            .tracking(1.6)
            .foregroundColor(.kuroTextSecondary)
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
                .font(.kuroMicro(weight: isSelected ? .semibold : .regular))
                .tracking(1.0)
                .foregroundColor(isSelected ? .kuroWhite : .kuroBlack70)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.kuroBlack : Color.kuroBlack05)
                        .overlay(Capsule().stroke(isSelected ? Color.clear : Color.kuroBlack12, lineWidth: 0.5))
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
        let textBlockHeight: CGFloat = 64
        let cardSpacing: CGFloat = 8
        let totalCardHeight = imageHeight + cardSpacing + textBlockHeight

        let columns = [
            GridItem(.fixed(cardWidth), spacing: spacing),
            GridItem(.fixed(cardWidth), spacing: spacing)
        ]

        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(0..<10, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.kuroBlack05)
                        .frame(width: cardWidth, height: imageHeight)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.kuroBlack06)
                            .frame(height: 10)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.kuroBlack05)
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
        .padding(.vertical, 14)
    }
}

struct BrowsePaginationSkeleton: View {
    let geometry: GeometryProxy

    var body: some View {
        let horizontalPadding: CGFloat = 20
        let spacing: CGFloat = 12
        let totalHorizontalPadding = horizontalPadding * 2
        let totalSpacing = spacing
        let availableWidth = geometry.size.width - totalHorizontalPadding - totalSpacing
        let cardWidth = floor(availableWidth / 2)
        let imageHeight = floor(cardWidth / 0.7)
        let textBlockHeight: CGFloat = 64
        let cardSpacing: CGFloat = 8
        let totalCardHeight = imageHeight + cardSpacing + textBlockHeight

        let columns = [
            GridItem(.fixed(cardWidth), spacing: spacing),
            GridItem(.fixed(cardWidth), spacing: spacing)
        ]

        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(0..<4, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.kuroBlack05)
                        .frame(width: cardWidth, height: imageHeight)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.kuroBlack06)
                            .frame(height: 10)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.kuroBlack04)
                            .frame(width: cardWidth * 0.6, height: 10)
                    }
                    .frame(height: textBlockHeight, alignment: .top)
                }
                .frame(width: cardWidth, height: totalCardHeight, alignment: .top)
                .kuroShimmer()
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 14)
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
        let textBlockHeight: CGFloat = 64
        let cardSpacing: CGFloat = 8
        let totalCardHeight = imageHeight + cardSpacing + textBlockHeight

        let columns = [
            GridItem(.fixed(cardWidth), spacing: spacing),
            GridItem(.fixed(cardWidth), spacing: spacing)
        ]

        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(items, id: \.id) { media in
                GridAnimeCard(media: media, cardWidth: cardWidth, cardHeight: totalCardHeight)
                    .onAppear {
                        if media.id == items.last?.id {
                            Task { await loadMore() }
                        }
                    }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: - Browse Empty State
struct BrowseEmptyState: View {
    let activeFilterCount: Int
    let activeFilterSummary: String
    let onClearFilters: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "slider.horizontal.3")
                .font(.kuroCustom(40, weight: .ultraLight, relativeTo: .largeTitle))
                .foregroundColor(.kuroBlack15)

            VStack(spacing: 8) {
                if activeFilterCount > 0 {
                    Text("NO MATCHES FOR \(activeFilterCount) FILTER\(activeFilterCount == 1 ? "" : "S")")
                        .font(.kuroCaption(weight: .semibold))
                        .tracking(1.0)
                        .foregroundColor(.kuroTextTertiary)

                    Text(activeFilterSummary)
                        .font(.kuroMicro(weight: .regular))
                        .tracking(0.8)
                        .foregroundColor(.kuroTextSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    Button {
                        KuroAccessibility.impactHaptic(.light)
                        onClearFilters()
                    } label: {
                        Text("CLEAR FILTERS")
                            .font(.kuroCaption(weight: .medium))
                            .tracking(1.6)
                            .foregroundColor(.kuroWhite)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.kuroBlack))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, KuroDesignSpacing.sm)
                    .accessibilityLabel("Clear all filters")
                } else {
                    Text("NO MATCHES")
                        .font(.kuroCaption(weight: .semibold))
                        .tracking(1.0)
                        .foregroundColor(.kuroTextTertiary)

                    Text("Try different filters")
                        .font(.kuroMicro(weight: .regular))
                        .tracking(0.8)
                        .foregroundColor(.kuroTextSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
    }
}

#Preview {
    BrowseView()
        .environment(SupabaseService.shared)
        .environment(NetworkMonitor())
}
