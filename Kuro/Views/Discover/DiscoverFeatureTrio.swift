import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Feature + three (Discover + Clubs redesign §6.2 item 6, D6)
// New to you, Because you… and Manga new to you: the page section heading, the first title as a
// feature in cover-story grammar (3.25 : 1, or the 160 pt spread without a banner), then the next
// three as covers 14 pt apart (four on the iPad column, two columns at accessibility sizes), then
// "See all {n} ›" when the section holds more than it shows. A trio cover: 2 : 3, radius 4, Home's
// leaf drop, a 12 pt medium title (two lines, no reserved second line), one 10 pt line ("{n} in your
// clubs", else "{year} · {format}"), and "On your list" when the title is tracked. No key on the
// trio; a long press keeps `DiscoverFrameMenu`.

struct DiscoverFeatureTrio: View {
    let anchor: String
    let title: String
    let summary: String?
    let cards: [TasteCard]
    let column: CGFloat
    let onSeeAll: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let compact = DiscoverIssueLayout.isCompact(column: column)
        let columns = DiscoverIssueLayout.trioColumns(regularWidth: horizontalSizeClass == .regular,
                                                      accessibility: dynamicTypeSize.isAccessibilitySize)
        let trio = Array(cards.dropFirst().prefix(columns))
        let coverWidth = DiscoverIssueLayout.trioCoverWidth(column: column, columns: columns)
        let shown = (cards.isEmpty ? 0 : 1) + trio.count
        VStack(alignment: .leading, spacing: 0) {
            DiscoverPageHeading(title: title, summary: summary, compact: compact)
                .padding(.bottom, DiscoverIssueLayout.headingToContent)
            if let first = cards.first {
                DiscoverCoverStory(story: DiscoverStory(card: first, eyebrow: title), kind: .feature, column: column)
            }
            if !trio.isEmpty {
                // No trailing Spacer: the stack's 14 pt spacing would apply before it too, making the
                // row 14 pt wider than the column and shifting the whole issue off centre.
                HStack(alignment: .top, spacing: DiscoverIssueLayout.trioSpacing) {
                    ForEach(trio) { card in
                        DiscoverCoverTile(card: card, width: coverWidth, height: (coverWidth * 1.5).rounded())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14)
            }
            if DiscoverIssueLayout.offersSeeAll(total: cards.count, shown: shown) {
                DiscoverTextAction(title: DiscoverIssueCopy.seeAll(cards.count, german: KuroLocale.isGerman),
                                   spoken: DiscoverIssueCopy.seeAllSpoken(cards.count, section: title, german: KuroLocale.isGerman),
                                   action: onSeeAll)
                    .padding(.top, 4)
            }
        }
        .id(anchor)
    }
}

/// One cover with its title and one line (the trio, and the rail at 106 × 150). The whole tile is one
/// button that opens the title; VoiceOver hears one element with the tracked state as its value.
struct DiscoverCoverTile: View {
    let card: TasteCard
    let width: CGFloat
    let height: CGFloat
    /// A stated airing slot ("Ep. 7 · 21:30") replaces the line (Airing today only).
    var airing: DiscoverAiringSlot? = nil

    @Environment(LibraryStore.self) private var library
    @Environment(ClubsStore.self) private var clubs
    @Environment(SocialActivityStore.self) private var social
    @Environment(FeatureFlags.self) private var flags
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    @Environment(\.kuroRoutes) private var routes

    private var german: Bool { KuroLocale.isGerman }

    private var line: String? {
        if let airing {
            return DiscoverFrameCopy.line(kind: card.media.kind, year: card.media.year, episodes: nil, chapters: nil,
                                          statusRaw: nil, formatRaw: nil, airing: airing, german: german,
                                          locale: KuroLocale.locale, timeZone: KuroLocale.timeZone)
        }
        if flags.isSocialActivityV1Enabled {
            let count = social.friendCount(mediaId: card.media.id, mediaType: card.media.kind.rawValue.uppercased())
            if count > 0 { return DiscoverFrameCopy.clubCount(count, german: german) }
        }
        return DiscoverIssueCopy.facts(kind: card.media.kind, year: card.media.year, formatRaw: card.media.formatRaw,
                                       episodes: nil, chapters: nil, length: false, german: german)
    }

    var body: some View {
        let tracked = library.isTracked(card.key)
        let line = line
        Button {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            routes.openMedia(MediaRoute(card.key))
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HomeArtwork(url: card.media.imageURL.flatMap { URL(string: $0) }, maxPixelSize: 360,
                            placeholder: HomeInk.posterFill)
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .shadow(color: Color(hex: "242C25", opacity: Double(0x14) / 255), radius: 1.5, y: 2)
                Text(KuroCardText.sanitizeTitleForCard(card.media.title))
                    .font(.kuroCustom(12, weight: .medium, relativeTo: .footnote, maxSize: 24))
                    .foregroundStyle(Color.kuroInk)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                if let line {
                    Text(line)
                        .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                        .foregroundStyle(Color.kuroMuted)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
                if tracked {
                    Text(DiscoverIssueCopy.onYourList(german: german))
                        .font(.kuroCustom(9, weight: .medium, relativeTo: .caption2, maxSize: 18))
                        .foregroundStyle(Color.kuroInk)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(hex: "D7DBD5"), lineWidth: 1))
                        .padding(.top, 5)
                }
            }
            .frame(width: width, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeArtworkPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text([card.media.title, line].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityValue(tracked ? DiscoverIssueCopy.onYourList(german: german) : "")
        .accessibilityHint(KuroLocale.text("Opens details", "Öffnet die Details"))
        .contextMenu {
            DiscoverFrameMenu(media: card.media, isSaved: tracked, hasClubs: !clubs.myClubs.isEmpty)
        }
    }
}
