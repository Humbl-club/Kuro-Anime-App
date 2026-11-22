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
    /// The section's one question (R1).
    let purpose: String?
    /// "3 new since Tue" (§5.6), nil without NEW titles.
    var newMarker: String? = nil
    /// The section's titles still on the page, in claim order (a hide refills from the reserve).
    let cards: [TasteCard]
    /// What "See all {n}" counts (after dedupe and hiding).
    let total: Int
    /// false: the section's See all is open-ended (it pages past the loaded rows): "See all ›", no number.
    var exactCount: Bool = true
    let column: CGFloat
    /// This season draws the cover row without a feature (§4).
    var feature: Bool = true
    /// This season's first block, the Airing-today glance (D8), between the purpose and the covers.
    var glance: AnyView? = nil
    var airingSlots: [Int: DiscoverAiringSlot] = [:]
    var showsEpisodeBadge: Bool = false
    let onSeeAll: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let compact = DiscoverIssueLayout.isCompact(column: column)
        let columns = DiscoverIssueLayout.trioColumns(regularWidth: horizontalSizeClass == .regular,
                                                      accessibility: dynamicTypeSize.isAccessibilitySize)
        let lead = feature ? cards.first : nil
        let trio = Array(cards.dropFirst(feature ? 1 : 0).prefix(columns))
        let coverWidth = DiscoverIssueLayout.trioCoverWidth(column: column, columns: columns)
        let shown = (lead == nil ? 0 : 1) + trio.count
        let motion = KuroMotion.playsMotionNow(reduceMotion: reduceMotion)
        VStack(alignment: .leading, spacing: 0) {
            DiscoverSectionHeader(title: title, purpose: purpose, newMarker: newMarker, compact: compact)
                .padding(.bottom, purpose == nil ? DiscoverIssueLayout.headingToContent : 0)
            if let glance {
                glance.padding(.bottom, 14)
            }
            if let lead {
                DiscoverCoverStory(story: DiscoverStory(card: lead, eyebrow: title), kind: .feature, column: column)
                    .id(lead.id)
                    .transition(DiscoverCardMotion.transition(motion: motion))
            }
            if !trio.isEmpty {
                // No trailing Spacer: the stack's 14 pt spacing would apply before it too, making the
                // row 14 pt wider than the column and shifting the whole issue off centre.
                HStack(alignment: .top, spacing: DiscoverIssueLayout.trioSpacing) {
                    ForEach(Array(trio.enumerated()), id: \.element.id) { index, card in
                        DiscoverCoverTile(
                            card: card,
                            width: coverWidth,
                            height: (coverWidth * 1.5).rounded(),
                            position: index + (lead == nil ? 0 : 1),
                            airing: card.media.kind == .anime ? airingSlots[card.media.id] : nil,
                            showsEpisodeBadge: showsEpisodeBadge
                        )
                            .transition(DiscoverCardMotion.transition(motion: motion))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, lead == nil ? 0 : 14)
            }
            if DiscoverIssueLayout.offersSeeAll(total: total, shown: shown) {
                DiscoverTextAction(title: DiscoverIssueCopy.seeAll(exactCount ? total : nil, german: KuroLocale.isGerman),
                                   spoken: DiscoverIssueCopy.seeAllSpoken(exactCount ? total : nil, section: title, german: KuroLocale.isGerman),
                                   action: onSeeAll)
                    .padding(.top, 4)
            }
        }
        .animation(motion ? KuroMotion.settle : nil, value: cards.map(\.id))
        .id(anchor)
    }
}

/// How a card leaves and enters on a hide or Undo (§5.3 step 2): it shrinks to 0.9 and fades over
/// `KuroMotion.contact`; the gap closes over `settle`. Under Reduce Motion or Low Power a cross-fade.
enum DiscoverCardMotion {
    static func transition(motion: Bool) -> AnyTransition {
        guard motion else { return .opacity }
        return .asymmetric(insertion: .opacity.animation(KuroMotion.settle),
                           removal: .scale(scale: 0.9).combined(with: .opacity).animation(KuroMotion.contact))
    }
}

/// One cover with its title, one line and its Plan key (the trio and the rails; R3). The cover and the
/// title are one button that opens the title; the key is its own element. A long press opens the menu.
struct DiscoverCoverTile: View {
    let card: TasteCard
    let width: CGFloat
    let height: CGFloat
    /// The tile's place in its section (telemetry, the menu).
    var position: Int = 0
    /// A stated airing slot ("Ep. 7 · 21:30") replaces the line (Airing today only).
    var airing: DiscoverAiringSlot? = nil
    /// Ongoing/scheduled chapter metadata for Manga tiles.
    var mangaSlot: DiscoverMangaSlot? = nil
    /// Draws bottom-leading episode status pills and latest-episode lines on This season / Just added.
    var showsEpisodeBadge: Bool = false
    /// R3: the quick action under the cover (off only where a page has its own key).
    var showsPlanKey: Bool = true

    @Environment(SocialActivityStore.self) private var social
    @Environment(FeatureFlags.self) private var flags
    @Environment(DiscoverPageFeedback.self) private var feedback: DiscoverPageFeedback?
    @Environment(\.discoverSection) private var section
    @Environment(\.discoverKindKicker) private var kindKicker
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    @Environment(\.kuroRoutes) private var routes
    @Environment(\.kuroZoomNamespace) private var zoomNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var zoomID: String? {
        guard zoomNamespace != nil, !reduceMotion else { return nil }
        return "discover-tile-\(section?.id ?? "rail")-\(position)-\(card.id)"
    }

    private var german: Bool { KuroLocale.isGerman }

    private func episodeDisplay(now: Date) -> DiscoverIssueCopy.SeasonEpisodeDisplay? {
        if card.media.kind == .manga, let mangaSlot {
            return DiscoverIssueCopy.mangaChapterPresentation(
                slot: mangaSlot,
                now: now,
                german: german,
                locale: KuroLocale.locale,
                timeZone: KuroLocale.timeZone
            )
        }
        guard showsEpisodeBadge, card.media.kind == .anime else { return nil }
        return DiscoverIssueCopy.seasonEpisodePresentation(
            slot: airing,
            now: now,
            german: german,
            locale: KuroLocale.locale,
            timeZone: KuroLocale.timeZone
        )
    }

    private func captionLine(now: Date, episodeDisplay: DiscoverIssueCopy.SeasonEpisodeDisplay?) -> String? {
        if let airing, airing.airingAt > now {
            let item = ReleaseScheduleItem(
                medium: .anime,
                mediaId: card.media.id,
                title: card.media.title,
                coverImage: card.media.imageURL,
                unitKind: .episode,
                unitNumber: airing.episode.map(Double.init),
                unitLabel: airing.episode.map { "Ep. \($0)" },
                releaseAt: airing.airingAt,
                basis: .confirmed,
                confidence: nil,
                source: "anilist",
                sourceURL: nil,
                isPast: false,
                precision: .instant
            )
            if let countdown = ReleaseCopy(now: now, german: german, locale: KuroLocale.locale, timeZone: KuroLocale.timeZone)
                .countdownPhrase(item) {
                if let episode = airing.episode, episode > 0 {
                    return german ? "Folge \(episode) · \(countdown)" : "Ep. \(episode) · \(countdown)"
                }
                return countdown
            }
        }
        if let epLine = episodeDisplay?.line {
            return epLine
        }
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
                                       episodes: nil, chapters: nil, length: false, german: german,
                                       kindShown: kindKicker)
    }

    var body: some View {
        if card.media.kind == .anime, let airing, abs(airing.airingAt.timeIntervalSinceNow) <= 86_400 {
            TimelineView(.everyMinute) { context in
                tileBody(now: context.date)
            }
        } else {
            tileBody(now: Date())
        }
    }

    @ViewBuilder
    private func tileBody(now: Date) -> some View {
        let epDisplay = episodeDisplay(now: now)
        let line = captionLine(now: now, episodeDisplay: epDisplay)
        let isNew = section?.newKeys.contains(card.key) ?? false
        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard !suppressCardTaps else { return }
                KuroAccessibility.impactHaptic(.light)
                feedback?.trackOpen(card.key, slot: section.map { DiscoverCardSlot(section: $0.id, position: position) }, via: "card")
                routes.openMedia(MediaRoute(card.key, zoomSourceID: zoomID))
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HomeArtwork(url: card.media.imageURL.flatMap { URL(string: $0) }, maxPixelSize: 360,
                                placeholder: HomeInk.posterFill, seedHex: card.media.coverImageColor,
                                usesMaterialWash: true)
                        .frame(width: width, height: height)
                        .clipShape(RoundedRectangle(cornerRadius: DiscoverCoverTile.coverRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DiscoverCoverTile.coverRadius, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                        )
                        .kuroZoomSource(zoomID)
                        .overlay(alignment: .topLeading) { if isNew { DiscoverNewTab() } }
                        .overlay(alignment: .bottomLeading) {
                            if let badge = epDisplay?.badge {
                                Text(badge)
                                    .font(.kuroCustom(8, weight: .bold, relativeTo: .caption2, maxSize: 14))
                                    .tracking(0.25)
                                    .monospacedDigit()
                                    .foregroundStyle(Color.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2.5)
                                    .background(Color.kuroControlInk.opacity(0.86), in: Capsule(style: .continuous))
                                    .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.20), lineWidth: 0.5))
                                    .frame(maxWidth: max(48, width - 42), alignment: .leading)
                                    .padding(5)
                                    .accessibilityHidden(true)
                            }
                        }
                    if kindKicker {
                        DiscoverKindKicker(kind: card.media.kind)
                            .padding(.top, 9)
                    }
                    Text(KuroCardText.sanitizeTitleForCard(card.media.title))
                        .font(.kuroCustom(13, weight: .semibold, relativeTo: .footnote, maxSize: 24))
                        .tracking(-0.1)
                        .foregroundStyle(Color.kuroInk)
                        // Two lines reserved and one line of facts always: every tile of a rail or
                        // trio has the same height (the corner badge sits on the cover, R3).
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, kindKicker ? 3 : 9)
                    Text(line ?? " ")
                        .font(.kuroCustom(11, relativeTo: .caption2, maxSize: 20))
                        .monospacedDigit()
                        .foregroundStyle(Color.kuroMuted)
                        .lineLimit(1)
                        .padding(.top, 2)
                        .accessibilityHidden(line == nil)
                }
                .frame(width: width, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(HomeArtworkPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(DiscoverCardSpoken.label(title: card.media.title, kind: card.media.kind,
                                                               kindKicker: kindKicker, line: line, isNew: isNew)))
            .accessibilityHint(KuroLocale.text("Opens details", "Öffnet die Details"))
            .discoverMenu(for: DiscoverCardItem(card: card, position: position))
            .overlay(alignment: .topLeading) {
                // The quick add floats on the cover's corner, a sibling of the open button (never
                // nested in it); only the badge itself takes touches.
                if showsPlanKey {
                    DiscoverPlanKey(card: card, variant: .leaf, compact: true, badge: true)
                        .padding(.trailing, 1)
                        .padding(.bottom, 1)
                        .frame(width: width, height: height, alignment: .bottomTrailing)
                }
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    /// The cover's continuous corner radius (2026-11-20: 8 pt, was 4).
    static let coverRadius: CGFloat = 8
}

/// The ANIME / MANGA kicker over a card's title on the All issue (§5.11): 8 pt, 1.05, `kuroMuted`.
struct DiscoverKindKicker: View {
    let kind: MediaKind

    var body: some View {
        Text(DiscoverIssueCopy.kindKicker(kind))
            .font(.kuroCustom(8, weight: .medium, relativeTo: .caption2, maxSize: 16))
            .tracking(1.05)
            .foregroundStyle(Color.kuroMuted)
            .accessibilityHidden(true)
    }
}

/// VoiceOver for a Discover card: "Anime: Frieren" on All (§5.11), then its line, then "new".
enum DiscoverCardSpoken {
    static func label(title: String, kind: MediaKind, kindKicker: Bool, line: String?, isNew: Bool) -> String {
        var parts = [kindKicker ? DiscoverIssueCopy.kindSpoken(kind, title: title) : title]
        if let line { parts.append(line) }
        if isNew { parts.append(DiscoverIssueCopy.newTab(german: KuroLocale.isGerman).lowercased()) }
        return parts.joined(separator: ", ")
    }
}
