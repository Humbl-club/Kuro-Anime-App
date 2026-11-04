import SwiftUI

// MARK: - Local refinement and the one rail (Discover + Clubs redesign §6.2 item 8; usability R6, D10)
// A rail's refinement is local (editorial-first rule: it filters the loaded rail, never the catalogue,
// and never resets the page): 11 pt medium words "Any length · Up to 13 episodes · Over 50 episodes ·
// Finished" (Discover's own words, D10; `DiscoverRailFilter`'s labels stay for its other users), the
// unselected in `kuroMuted`, the selected in ink with a 16 × 1.5 rule, wrapping so they never clip at
// 288, each a 44 pt target; VoiceOver hears the group as "Refine this rail".
// The rail: 2 : 3 covers (radius 4) sized by the edge-peek rule (100 × 150 at 390, a slice of the next
// cover always showing; details-songs spec §5.1), a 12 pt title, a 10 pt line and the Plan key (R3),
// 14 pt apart, bleeding past the trailing gutter; up to ten, then "See all {n} ›" under it.

struct DiscoverRefineRow: View {
    @Binding var selection: DiscoverRailFilter

    var body: some View {
        FlowLayout(spacing: 16) {
            ForEach(DiscoverRailFilter.allCases, id: \.self) { filter in
                let selected = filter == selection
                let word = DiscoverIssueCopy.refineWord(filter, german: KuroLocale.isGerman)
                Button {
                    guard !selected else { return }
                    KuroAccessibility.impactHaptic(.light)
                    selection = filter
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(word)
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
                .accessibilityLabel(word)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(DiscoverIssueCopy.refineLabel(german: KuroLocale.isGerman))
    }
}

/// Trending (with its refinement) and Tonight's shelf: the page's one horizontal rail grammar.
struct DiscoverIssueRail: View {
    let anchor: String
    let title: String
    let purpose: String?
    var newMarker: String? = nil
    /// The section's titles still on the page, in claim order.
    let cards: [TasteCard]
    /// What "See all {n}" counts (after dedupe and hiding).
    let total: Int
    /// The content column's width; `gutter` is the page's, so the rail bleeds to the column's edge.
    let column: CGFloat
    let gutter: CGFloat
    var refines: Bool = false
    var onSeeAll: (() -> Void)? = nil

    @State private var filter: DiscoverRailFilter = .all
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let compact = DiscoverIssueLayout.isCompact(column: column)
        let shown = refines
            ? cards.filter { filter.includes(episodes: $0.media.episodes, statusRaw: $0.media.statusRaw) }
            : cards
        let rail = Array(shown.prefix(DiscoverIssueLayout.railCap))
        let motion = KuroMotion.playsMotionNow(reduceMotion: reduceMotion)
        VStack(alignment: .leading, spacing: 0) {
            DiscoverSectionHeader(title: title, purpose: purpose, newMarker: newMarker, compact: compact)
                .padding(.horizontal, gutter)
                .padding(.bottom, purpose == nil ? (refines ? 2 : DiscoverIssueLayout.headingToContent) : 0)
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
                let cover = DiscoverIssueLayout.railCover(column: column, gutter: gutter)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: DiscoverIssueLayout.railSpacing) {
                        ForEach(Array(rail.enumerated()), id: \.element.id) { index, card in
                            DiscoverCoverTile(card: card, width: cover.width, height: cover.height, position: index)
                                .transition(DiscoverCardMotion.transition(motion: motion))
                        }
                    }
                    .padding(.horizontal, gutter)
                }
                .kuroSwipeExclusionZone()
            }
            if let onSeeAll, DiscoverIssueLayout.offersSeeAll(total: total, shown: rail.count) {
                DiscoverTextAction(title: DiscoverIssueCopy.seeAll(total, german: KuroLocale.isGerman),
                                   spoken: DiscoverIssueCopy.seeAllSpoken(total, section: title, german: KuroLocale.isGerman),
                                   action: onSeeAll)
                    .padding(.horizontal, gutter)
                    .padding(.top, 4)
            }
        }
        .animation(motion ? KuroMotion.settle : nil, value: cards.map(\.id))
        .id(anchor)
    }
}
