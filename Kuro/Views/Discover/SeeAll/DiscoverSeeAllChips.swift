import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - See all: sections, sort words, quick filters (pure) and their controls (spec 2026-11-04 §5.5)
// A See all list is either BOUNDED (the section's own loaded rows: Essentials, Classics, New to you,
// Because you…, Manga new to you, This season, Airing today; sorted on the device) or a CATALOGUE list
// (Trending, Top rated, Just added and their manga twins: the whole catalogue, paged). The sort words
// and the chips map onto the data lane's `DiscoverSeeAllQuery` (`DiscoveryStore.seeAllPage`).
//
// Two rules the data lane's types do not carry, applied here on the device:
//   - "Over 50 episodes" (D10: the shipped long rule is > 50) is the data lane's `.long` bucket (51+
//     episodes, aligned at integration) and checked again on the row, so the words stay true whichever
//     reader answered.
//   - "Hide my list" hides titles on the viewer's list (independent of the other chips).

/// What a See all page lists.
struct DiscoverSeeAllSection: Equatable {
    /// How the list's own order reads: curated, personal or by the next airing time.
    enum OrderKind: Equatable { case curated, personal, airing }

    let key: DiscoverSectionKey
    let medium: MediaKind
    /// A catalogue list (paged) rather than the section's bounded rows.
    let isCatalogue: Bool
    let order: OrderKind

    static func of(_ route: EditorialDiscoverRoute) -> DiscoverSeeAllSection {
        let medium: MediaKind = route.isManga ? .manga : .anime
        switch route {
        case .animeEssentials, .mangaEssentials:
            return DiscoverSeeAllSection(key: .essentials, medium: medium, isCatalogue: false, order: .curated)
        case .animeClassics, .mangaClassics:
            return DiscoverSeeAllSection(key: .classics, medium: medium, isCatalogue: false, order: .curated)
        case .animeNewToYou, .mangaNewToYou:
            return DiscoverSeeAllSection(key: .newToYou, medium: medium, isCatalogue: false, order: .personal)
        case .animeBecauseYou:
            return DiscoverSeeAllSection(key: .becauseYou, medium: medium, isCatalogue: false, order: .personal)
        case .animeAiringToday:
            return DiscoverSeeAllSection(key: .airingToday, medium: medium, isCatalogue: false, order: .airing)
        case .animeCurrentSeason:
            return DiscoverSeeAllSection(key: .currentSeason, medium: medium, isCatalogue: false, order: .airing)
        case .animeTrending, .mangaTrending:
            return DiscoverSeeAllSection(key: .trending, medium: medium, isCatalogue: true, order: .curated)
        case .animeTopRated, .mangaTopRated:
            return DiscoverSeeAllSection(key: .topRated, medium: medium, isCatalogue: true, order: .curated)
        case .animeNewlyAdded, .mangaNewlyAdded:
            return DiscoverSeeAllSection(key: .newlyAdded, medium: medium, isCatalogue: true, order: .curated)
        }
    }

    /// The sort words, in order.
    var sortWords: [DiscoverSeeAllSortWord] {
        isCatalogue ? [.trending, .popular, .topRated, .justAdded] : [.ownOrder(order), .popular, .newest, .topRated]
    }

    /// The word selected when the page opens: the list's own order.
    var defaultSort: DiscoverSeeAllSortWord {
        guard isCatalogue else { return .ownOrder(order) }
        switch key {
        case .topRated: return .topRated
        case .newlyAdded: return .justAdded
        default: return .trending
        }
    }

    /// The chip groups this list offers (format and length are anime only).
    var chipGroups: [[DiscoverSeeAllChip]] {
        var groups: [[DiscoverSeeAllChip]] = []
        if medium == .anime {
            groups.append([.tv, .film])
            groups.append([.upTo13, .over50])
        }
        groups.append([.finished, .releasing])
        groups.append([.hideMyList])
        return groups
    }

    /// The owned rule of the list (R2): personal lists hide titles on the list, the rest mark them.
    var ownedPolicy: DiscoverOwnedPolicy { key.ownedPolicy }
}

/// One sort word.
enum DiscoverSeeAllSortWord: Hashable {
    case ownOrder(DiscoverSeeAllSection.OrderKind)
    case popular, newest, topRated
    /// Catalogue lists only.
    case trending, justAdded

    var telemetryName: String {
        switch self {
        case .ownOrder: return "default"
        case .popular: return "popular"
        case .newest: return "newest"
        case .topRated: return "top_rated"
        case .trending: return "trending"
        case .justAdded: return "just_added"
        }
    }
}

/// One quick filter chip.
enum DiscoverSeeAllChip: String, CaseIterable, Hashable {
    case tv, film, upTo13, over50, finished, releasing, hideMyList

    enum Group: Equatable { case format, length, status, list }

    var group: Group {
        switch self {
        case .tv, .film: return .format
        case .upTo13, .over50: return .length
        case .finished, .releasing: return .status
        case .hideMyList: return .list
        }
    }
}

/// The page's sort and chips (pure). Chips in one group are exclusive; "Hide my list" is independent.
struct DiscoverSeeAllSelection: Hashable {
    var sort: DiscoverSeeAllSortWord
    var format: DiscoverSeeAllChip?
    var length: DiscoverSeeAllChip?
    var status: DiscoverSeeAllChip?
    var hideMyList = false

    init(sort: DiscoverSeeAllSortWord) {
        self.sort = sort
    }

    func isOn(_ chip: DiscoverSeeAllChip) -> Bool {
        switch chip.group {
        case .format: return format == chip
        case .length: return length == chip
        case .status: return status == chip
        case .list: return hideMyList
        }
    }

    /// Selects `chip`, or clears it when it is already selected (a second tap).
    mutating func toggle(_ chip: DiscoverSeeAllChip) {
        let on = isOn(chip)
        switch chip.group {
        case .format: format = on ? nil : chip
        case .length: length = on ? nil : chip
        case .status: status = on ? nil : chip
        case .list: hideMyList.toggle()
        }
    }

    /// Chips on (the match line shows while any is).
    var activeCount: Int {
        [format, length, status].compactMap { $0 }.count + (hideMyList ? 1 : 0)
    }

    mutating func clearFilters() {
        format = nil
        length = nil
        status = nil
        hideMyList = false
    }

    /// The server / fallback query of this selection. Only the parts the server reads: "Hide my list"
    /// and the > 50 narrowing stay on the device (`includes`), so toggling them never re-reads.
    func query(for section: DiscoverSeeAllSection) -> DiscoverSeeAllQuery {
        var key = section.key
        let sort: DiscoverSeeAllSort
        switch self.sort {
        case .ownOrder: sort = .sectionOrder
        case .popular: sort = .popular
        case .newest: sort = .newest
        case .topRated: sort = .topRated
        case .trending:
            key = .trending
            sort = .sectionOrder
        case .justAdded:
            key = .newlyAdded
            sort = .sectionOrder
        }
        var query = DiscoverSeeAllQuery(section: key, medium: section.medium, sort: sort)
        switch format {
        case .tv?: query.format = "TV"
        case .film?: query.format = "MOVIE"
        default: break
        }
        switch length {
        case .upTo13?: query.length = .short
        case .over50?: query.length = .long
        default: break
        }
        switch status {
        case .finished?: query.status = .finished
        case .releasing?: query.status = .releasing
        default: break
        }
        return query
    }

    /// The device-side rules: "Over 50 episodes" is > 50 (the server's `long` bucket, 51+), "Hide my
    /// list" leaves out titles on the list, and every chip the server also applies is checked again on
    /// the row, so the words stay true whichever reader answered (a page from an older reader, a
    /// fallback that cannot filter).
    func includes(kind: MediaKind, episodes: Int?, formatRaw: String? = nil, statusRaw: String? = nil,
                  onList: Bool) -> Bool {
        if hideMyList, onList { return false }
        if kind == .anime {
            switch length {
            case .upTo13?:
                guard let episodes, (1...13).contains(episodes) else { return false }
            case .over50?:
                guard let episodes, episodes > 50 else { return false }
            default: break
            }
            switch format {
            case .tv?: if let formatRaw, formatRaw.uppercased() != "TV" { return false }
            case .film?: if let formatRaw, formatRaw.uppercased() != "MOVIE" { return false }
            default: break
            }
        }
        switch status {
        case .finished?: if let statusRaw, statusRaw.uppercased() != "FINISHED" { return false }
        case .releasing?: if let statusRaw, statusRaw.uppercased() != "RELEASING" { return false }
        default: break
        }
        return true
    }
}

// MARK: - Controls

/// A row of words in `DiscoverRefineRow` grammar (11 pt medium, the selected in ink over a 16 × 1.5
/// rule, the rest `kuroMuted`, 44 pt targets), for sort words, mood words and the medium pair.
struct DiscoverWordRow<Word: Hashable>: View {
    let words: [Word]
    let selection: Word
    let label: String
    let title: (Word) -> String
    let onSelect: (Word) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(words, id: \.self) { word in
                    let selected = word == selection
                    Button {
                        guard !selected else { return }
                        KuroAccessibility.impactHaptic(.light)
                        onSelect(word)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title(word))
                                .font(.kuroCustom(11, weight: .medium, relativeTo: .caption1, maxSize: 22))
                                .foregroundStyle(selected ? Color.kuroInk : Color.kuroMuted)
                                .lineLimit(1)
                                .fixedSize()
                            Rectangle()
                                .fill(selected ? Color.kuroInk : Color.clear)
                                .frame(width: 16, height: 1.5)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(HomeContactStyle())
                    .accessibilityLabel(title(word))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// One chip: drawn 30 pt tall in a 44 pt hit area. Selected: the ink fill, white 12 pt medium text and
/// a leading ✓. Unselected: Home's glance face (`glanceFill`, 1 pt `glanceBorder`) with ink text.
struct DiscoverChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            action()
        } label: {
            HStack(spacing: 4) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.kuroCustom(12, weight: .medium, relativeTo: .footnote, maxSize: 24))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(selected ? Color.white : Color.kuroInk)
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .background(selected ? Color.kuroInk : HomeInk.glanceFill, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.kuroInk : HomeInk.glanceBorder, lineWidth: 1))
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// The chip groups in a wrapping layout, groups separated by a 1 pt hairline (only between two chips
/// on the same line: a group that wraps starts its line without one).
struct DiscoverChipGroups: View {
    let groups: [[DiscoverSeeAllChip]]
    let medium: MediaKind
    let selection: DiscoverSeeAllSelection
    let onToggle: (DiscoverSeeAllChip) -> Void

    var body: some View {
        let german = KuroLocale.isGerman
        DiscoverChipFlow {
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                if index > 0 { DiscoverChipSeparator() }
                ForEach(group, id: \.self) { chip in
                    DiscoverChip(title: DiscoverSeeAllCopy.chip(chip, medium: medium, german: german),
                                 selected: selection.isOn(chip)) { onToggle(chip) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(DiscoverSeeAllCopy.filtersLabel(german: german))
    }
}

/// The hairline between two chip groups: 1 × 20 pt `kuroHairline`, drawn only where the flow places it.
struct DiscoverChipSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.kuroHairline)
            .frame(maxWidth: 1, maxHeight: 20)
            .layoutValue(key: DiscoverChipSeparatorKey.self, value: true)
            .accessibilityHidden(true)
    }
}

private struct DiscoverChipSeparatorKey: LayoutValueKey {
    static let defaultValue = false
}

/// Chips 6 pt apart in wrapping lines (each chip carries its own 44 pt hit area); a separator stands
/// between two chips of the same line, 6 pt either side, and is dropped (zero size) at a line break.
struct DiscoverChipFlow: Layout {
    static let spacing: CGFloat = 6
    static let separatorSize = CGSize(width: 1, height: 20)

    /// Where each subview goes (nil: a dropped separator), and the total size (pure; DUpreviewTests).
    static func arrange(sizes: [CGSize], separators: [Bool], maxWidth: CGFloat) -> (frames: [CGRect?], size: CGSize) {
        var frames: [CGRect?] = Array(repeating: nil, count: sizes.count)
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, width: CGFloat = 0
        var pendingSeparator: Int?
        func newLine() {
            y += lineHeight
            x = 0
            lineHeight = 0
        }
        for index in sizes.indices {
            if separators[index] {
                pendingSeparator = x > 0 ? index : nil
                continue
            }
            let size = sizes[index]
            if let separator = pendingSeparator {
                let needed = spacing + separatorSize.width + spacing + size.width
                if x + needed <= maxWidth {
                    frames[separator] = CGRect(x: x + spacing, y: 0, width: separatorSize.width, height: separatorSize.height)
                    x += spacing + separatorSize.width
                } else {
                    newLine()
                }
                pendingSeparator = nil
            }
            if x > 0, x + spacing + size.width > maxWidth { newLine() }
            let originX = x > 0 ? x + spacing : 0
            frames[index] = CGRect(x: originX, y: y, width: size.width, height: size.height)
            // A separator placed on this line is centred on the line's chips.
            x = originX + size.width
            lineHeight = max(lineHeight, size.height)
            width = max(width, x)
        }
        // Vertically centre each placed separator on its line (the line's chips share one height).
        for index in frames.indices where separators[index] {
            guard let frame = frames[index], let next = frames[(index + 1)...].lazy.compactMap({ $0 }).first else { continue }
            frames[index] = CGRect(x: frame.minX, y: next.midY - frame.height / 2, width: frame.width, height: frame.height)
        }
        return (frames, CGSize(width: width, height: y + lineHeight))
    }

    private func layout(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect?], size: CGSize) {
        let separators = subviews.map { $0[DiscoverChipSeparatorKey.self] }
        let sizes = subviews.indices.map { separators[$0] ? Self.separatorSize : subviews[$0].sizeThatFits(.unspecified) }
        return Self.arrange(sizes: sizes, separators: separators, maxWidth: width)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        return layout(subviews, width: width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = layout(subviews, width: bounds.width).frames
        for (index, subview) in subviews.enumerated() {
            if let frame = frames[index] {
                subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                              proposal: ProposedViewSize(frame.size))
            } else {
                subview.place(at: bounds.origin, proposal: .zero)
            }
        }
    }
}
