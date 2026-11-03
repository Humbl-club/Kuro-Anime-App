import SwiftUI

// MARK: - Local refinement and the one rail (Discover + Clubs redesign §6.2 item 8)
// A rail's refinement is local (editorial-first rule: it filters the loaded rail, never the catalogue):
// 11 pt medium words "All · Short · Long · Finished" (the shipped `DiscoverRailFilter` labels), the
// unselected in `kuroMuted`, the selected in ink with a 16 × 1.5 rule, 16 pt apart, each a 44 pt
// target; VoiceOver hears the group as "Refine this rail". It keeps the page's medium choice and this
// choice visibly different (the page switch is the heavy issue switch).
// The rail: 106 × 150 covers (radius 4), a 12 pt title and a 10 pt line, 14 pt apart, bleeding past the
// trailing gutter; up to ten, then "See all {n} ›" under it.

struct DiscoverRefineRow: View {
    @Binding var selection: DiscoverRailFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(DiscoverRailFilter.allCases, id: \.self) { filter in
                    let selected = filter == selection
                    Button {
                        guard !selected else { return }
                        KuroAccessibility.impactHaptic(.light)
                        selection = filter
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(filter.title(german: KuroLocale.isGerman))
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
                    .accessibilityLabel(filter.title(german: KuroLocale.isGerman))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .scrollClipDisabled()
        .kuroSwipeExclusionZone()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(DiscoverIssueCopy.refineLabel(german: KuroLocale.isGerman))
    }
}

/// Trending (with its refinement) and Tonight's shelf: the page's one horizontal rail grammar.
struct DiscoverIssueRail: View {
    let anchor: String
    let title: String
    let summary: String?
    let cards: [TasteCard]
    /// The content column's width; `gutter` is the page's, so the rail bleeds to the column's edge.
    let column: CGFloat
    let gutter: CGFloat
    var refines: Bool = false
    var onSeeAll: (() -> Void)? = nil

    @State private var filter: DiscoverRailFilter = .all

    var body: some View {
        let compact = DiscoverIssueLayout.isCompact(column: column)
        let shown = refines
            ? cards.filter { filter.includes(episodes: $0.media.episodes, statusRaw: $0.media.statusRaw) }
            : cards
        let rail = Array(shown.prefix(DiscoverIssueLayout.railCap))
        VStack(alignment: .leading, spacing: 0) {
            DiscoverPageHeading(title: title, summary: summary, compact: compact)
                .padding(.horizontal, gutter)
                .padding(.bottom, refines ? 2 : DiscoverIssueLayout.headingToContent)
            if refines {
                DiscoverRefineRow(selection: $filter)
                    .padding(.horizontal, gutter)
                    .padding(.bottom, 6)
            }
            if rail.isEmpty {
                KuroStateView(.empty,
                              title: KuroLocale.text("Nothing here for this choice.", "Für diese Auswahl gibt es hier nichts."),
                              layout: .inline)
                    .padding(.horizontal, gutter)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: DiscoverIssueLayout.railSpacing) {
                        ForEach(rail) { card in
                            DiscoverCoverTile(card: card, width: DiscoverIssueLayout.railCover.width,
                                              height: DiscoverIssueLayout.railCover.height)
                        }
                    }
                    .padding(.horizontal, gutter)
                }
                .kuroSwipeExclusionZone()
            }
            if let onSeeAll, DiscoverIssueLayout.offersSeeAll(total: cards.count, shown: rail.count) {
                DiscoverTextAction(title: DiscoverIssueCopy.seeAll(cards.count, german: KuroLocale.isGerman),
                                   spoken: DiscoverIssueCopy.seeAllSpoken(cards.count, section: title, german: KuroLocale.isGerman),
                                   action: onSeeAll)
                    .padding(.horizontal, gutter)
                    .padding(.top, 4)
            }
        }
        .id(anchor)
    }
}
