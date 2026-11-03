import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Numbered index (Discover + Clubs redesign §6.2 items 7 and 13)
// Essential anime / Essential manga, and every folded section: the page section heading, five rows
// (three on the All issue),
// then "See all {n} ›". A row is Home's quiet row with its minimum height raised to 76: the curated
// number ("01", 13 pt medium mono, `kuroMuted`, a 22 pt column), the 40 × 60 cover (radius 2), the
// title (15 pt medium −0.2, two lines) over "{year} · {format} · {n} eps", then the leaf `TastePlanKey`
// (at least 96 pt wide, 84 compact), and a 0.5 pt `kuroHairline` under it. The number is the curated
// order, never a rank. At accessibility sizes the key moves under the title.

struct DiscoverIndexSection: View {
    let anchor: String
    let title: String
    let summary: String?
    let cards: [TasteCard]
    let column: CGFloat
    /// The section's local refinement (Top rated), drawn between the heading and the rows.
    var refinement: Binding<DiscoverRailFilter>? = nil
    /// Rows shown before "See all" (`DiscoverIssueLayout.indexRows(onAll:)`).
    var rowLimit: Int = DiscoverIssueLayout.indexRows
    let onSeeAll: () -> Void

    var body: some View {
        let compact = DiscoverIssueLayout.isCompact(column: column)
        let filtered = refinement.map { filter in
            cards.filter { filter.wrappedValue.includes(episodes: $0.media.episodes, statusRaw: $0.media.statusRaw) }
        } ?? cards
        let rows = Array(filtered.prefix(rowLimit))
        VStack(alignment: .leading, spacing: 0) {
            DiscoverPageHeading(title: title, summary: summary, compact: compact)
                .padding(.bottom, refinement == nil ? DiscoverIssueLayout.headingToContent - 6 : 2)
            if let refinement {
                DiscoverRefineRow(selection: refinement)
                    .padding(.bottom, 4)
            }
            if rows.isEmpty {
                KuroStateView(.empty,
                              title: KuroLocale.text("Nothing here for this choice.", "Für diese Auswahl gibt es hier nichts."),
                              layout: .inline)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, card in
                    DiscoverIndexRow(position: index + 1, card: card, compact: compact)
                }
            }
            // "See all" opens the whole section (the refinement is local), so it counts the whole
            // section, as the rail does.
            if DiscoverIssueLayout.offersSeeAll(total: cards.count, shown: rows.count) {
                DiscoverTextAction(title: DiscoverIssueCopy.seeAll(cards.count, german: KuroLocale.isGerman),
                                   spoken: DiscoverIssueCopy.seeAllSpoken(cards.count, section: title, german: KuroLocale.isGerman),
                                   action: onSeeAll)
                    .padding(.top, 4)
            }
        }
        .id(anchor)
    }
}

struct DiscoverIndexRow: View {
    let position: Int
    let card: TasteCard
    let compact: Bool

    @Environment(LibraryStore.self) private var library
    @Environment(ClubsStore.self) private var clubs
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    @Environment(\.kuroRoutes) private var routes
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var german: Bool { KuroLocale.isGerman }

    private var meta: String? {
        DiscoverIssueCopy.facts(kind: card.media.kind, year: card.media.year, formatRaw: card.media.formatRaw,
                                episodes: card.media.episodes, chapters: card.media.chapters, length: true, german: german)
    }

    var body: some View {
        let accessibility = dynamicTypeSize.isAccessibilitySize
        Group {
            if accessibility {
                VStack(alignment: .leading, spacing: 8) {
                    openButton
                    key.padding(.leading, 22 + 12)
                }
                .padding(.vertical, 10)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    openButton
                    DiscoverAtLeastWidth(minimum: DiscoverIssueLayout.indexKeyWidth(compact: compact)) { key }
                }
                .frame(minHeight: DiscoverIssueLayout.indexRowMinHeight)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.kuroHairline).frame(height: 0.5).accessibilityHidden(true)
        }
    }

    private var key: some View {
        TastePlanKey(card: card, variant: .leaf, compact: true)
    }

    private var openButton: some View {
        let meta = meta
        return Button {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            routes.openMedia(MediaRoute(card.key))
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Text(DiscoverIssueCopy.indexNumber(position))
                    .font(.kuroCustom(13, weight: .medium, relativeTo: .footnote, maxSize: 24))
                    .monospacedDigit()
                    .foregroundStyle(Color.kuroMuted)
                    .frame(width: 22, alignment: .leading)
                HomeArtwork(url: card.media.imageURL.flatMap { URL(string: $0) }, maxPixelSize: 160,
                            placeholder: HomeInk.posterFill)
                    .frame(width: 40, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                VStack(alignment: .leading, spacing: 3) {
                    Text(KuroCardText.sanitizeTitleForCard(card.media.title))
                        .font(.kuroCustom(15, weight: .medium, relativeTo: .subheadline, maxSize: 30))
                        .tracking(-0.2)
                        .foregroundStyle(Color.kuroInk)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let meta {
                        Text(meta)
                            .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                            .foregroundStyle(Color.kuroMuted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text([DiscoverIssueCopy.indexSpoken(position, german: german), card.media.title, meta]
            .compactMap { $0 }.joined(separator: ", ")))
        .accessibilityValue(library.isTracked(card.key) ? DiscoverIssueCopy.onYourList(german: german) : "")
        .accessibilityHint(KuroLocale.text("Opens details", "Öffnet die Details"))
        .contextMenu {
            DiscoverFrameMenu(media: card.media, isSaved: library.isTracked(card.key), hasClubs: !clubs.myClubs.isEmpty)
        }
    }
}
