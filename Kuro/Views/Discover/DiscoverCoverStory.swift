import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Cover story (Discover + Clubs redesign §6.2 items 3, 6 and 9; Home grammar G§8.3)
// One title in Home's scene-card anatomy, on the title's own artwork material:
//   lead     Today's pick (or the season / essential lead when there is none): the banner at 2.2 : 1
//            with the season-style tab ("TODAY'S" + "pick"), the material foot (title 17 semibold
//            −0.35, the argument 11 pt, a 1 pt divider, the Plan key), then a fact row ("2016 · Movie",
//            "{n} in your clubs ›").
//   gem      the Hidden gem: the same at 3.25 : 1 with "HIDDEN" + "gem" in the tab.
//   feature  the first title of a section: 3.25 : 1, no tab, the facts in the foot, no fact row.
// Without a banner each becomes the capped spread: the cover beside a material panel (132 × 198,
// 104 × 156 compact; a feature 107 × 160), never taller than 220 pt outside accessibility sizes (P14).
// The art and the title open the title (`routes.openMedia`, honouring the pager's tap suppression);
// the Plan key is the existing `TastePlanKey` (plan / unplan with Undo; a tracked title opens the
// editor); a long press opens the card menu (`discoverMenu(for:)`: Plan, Seen it, Not interested, Add
// to club, Open; `DiscoverFrameMenu` outside the Discover page). On the All issue the kind leads the
// fact row ("ANIME · 2016 · Movie", usability §5.11). No score or genre (rulebook §14.5).

/// What a cover story shows (pure). Built from the daily feature, the Hidden gem, a season / trending
/// lead or a section's first title; nothing is shown that the row does not carry.
struct DiscoverStory {
    let card: TasteCard
    /// The tab's words ("Today's pick", "Hidden gem", "This season"…).
    let eyebrow: String
    /// The editorial argument (the daily feature's), if any.
    let argument: String?

    var key: MediaKey { card.key }
    var bannerRaw: String? { card.bannerURL }
    var coverRaw: String? { card.media.imageURL }
    /// The art the page's switch word and material follow: the banner, else the cover.
    var artRaw: String? { bannerRaw ?? coverRaw }

    func facts(length: Bool, german: Bool) -> String? {
        DiscoverIssueCopy.facts(kind: card.media.kind, year: card.media.year, formatRaw: card.media.formatRaw,
                                episodes: card.media.episodes, chapters: card.media.chapters,
                                length: length, german: german)
    }
}

extension DiscoverStory {
    /// The daily feature (or the Hidden gem). Its `Media` is built with the internal memberwise init
    /// (spec D5), so `TastePicksView`'s private factory is not needed.
    init(feature: DailyFeature, eyebrow: String) {
        let media = Media(id: feature.mediaId, kind: feature.kind, title: feature.title,
                          imageURL: feature.coverImageLarge, year: feature.year.map(String.init) ?? "TBA",
                          displayDescription: "", episodes: nil, chapters: nil,
                          rating: feature.score.map { Double($0) / 10 }, genres: feature.genres,
                          statusRaw: nil, formatRaw: feature.format, popularityValue: nil,
                          trendingValue: nil, createdAtValue: nil)
        self.init(card: TasteCard(media: media, bannerURL: feature.bannerImage), eyebrow: eyebrow,
                  argument: feature.displayArgument)
    }

    init(card: TasteCard, eyebrow: String) {
        self.init(card: card, eyebrow: eyebrow, argument: nil)
    }
}

struct DiscoverCoverStory: View {
    enum Kind { case lead, gem, feature }

    let story: DiscoverStory
    let kind: Kind
    /// The content column's width.
    let column: CGFloat

    @Environment(ArtworkMaterialStore.self) private var materials: ArtworkMaterialStore?
    @Environment(SocialActivityStore.self) private var social
    @Environment(FeatureFlags.self) private var flags
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    @Environment(\.kuroRoutes) private var routes
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(DiscoverPageFeedback.self) private var feedback: DiscoverPageFeedback?
    @Environment(\.discoverSection) private var section
    @Environment(\.discoverKindKicker) private var kindKicker

    private var compact: Bool { DiscoverIssueLayout.isCompact(column: column) }

    /// "ANIME · 2016 · Movie" on the All issue: the kind leads the fact row (usability §5.11).
    private func withKind(_ facts: String?) -> String? {
        guard kindKicker else { return facts }
        let kind = DiscoverIssueCopy.kindKicker(story.card.media.kind)
        guard let facts else { return kind }
        return kind + " · " + facts
    }
    private var german: Bool { KuroLocale.isGerman }

    private var material: ArtworkMaterial {
        let url = story.artRaw.flatMap { URL(string: $0) }
        return materials?.material(for: url, seedHex: nil) ?? .neutral
    }

    private var friendCount: Int {
        guard kind != .feature, flags.isSocialActivityV1Enabled else { return 0 }
        return social.friendCount(mediaId: story.card.media.id, mediaType: story.card.media.kind.rawValue.uppercased())
    }

    private var aspect: CGFloat {
        kind == .lead ? DiscoverIssueLayout.coverBannerAspect : DiscoverIssueLayout.featureBannerAspect
    }

    var body: some View {
        let material = material
        Group {
            if let banner = story.bannerRaw, !banner.isEmpty {
                bannerStory(banner: banner, material: material)
            } else {
                spread(material: material)
            }
        }
        .background(
            LinearGradient(colors: [material.base.color, material.deep.color],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .shadow(color: Color(hex: "19221B", opacity: Double(0x0A) / 255), radius: 1, y: 1)
        .animation(KuroMotion.playsMotionNow(reduceMotion: reduceMotion) ? KuroMotion.medium : nil, value: material)
    }

    // MARK: Banner

    private func bannerStory(banner: String, material: ArtworkMaterial) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Button(action: open) {
                    Color.clear
                        .aspectRatio(aspect, contentMode: .fit)
                        .overlay { HomeArtwork(url: URL(string: banner), maxPixelSize: 1200, placeholder: material.base.color) }
                        .clipped()
                        .overlay {
                            // A 1 pt light rim and a soft shade over the lower half.
                            ZStack {
                                LinearGradient(colors: [.clear, Color.black.opacity(0.18)],
                                               startPoint: .center, endPoint: .bottom)
                                UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5)
                                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                            }
                            .allowsHitTesting(false)
                        }
                        .homeEntrance()
                }
                .buttonStyle(HomeArtworkPressStyle())
                .accessibilityHidden(true)
                .discoverMenu(for: DiscoverCardItem(card: story.card, position: 0))
                if kind != .feature { tab }
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5))
            foot
            if kind != .feature { factRow }
        }
    }

    /// The season-style tab on the art's bottom edge: the eyebrow's first word small, the rest large.
    private var tab: some View {
        let parts = DiscoverIssueCopy.tabParts(story.eyebrow)
        return HStack(alignment: .lastTextBaseline, spacing: 5) {
            if let small = parts.small {
                Text(small)
                    .font(.kuroCustom(7, relativeTo: .caption2, maxSize: 14))
                    .tracking(0.3)
                    .textCase(.uppercase)
            }
            Text(parts.large)
                .font(.kuroCustom(13, weight: .semibold, relativeTo: .headline, maxSize: 24))
                .lineLimit(1)
        }
        .foregroundStyle(HomeInk.tabInk)
        .padding(.horizontal, 8)
        .frame(minHeight: 31)
        .fixedSize(horizontal: false, vertical: true)
        .background(HomeInk.tabFace, in: UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8))
        .shadow(color: Color.white.opacity(Double(0x65) / 255), radius: 0, y: -1)
        .padding(.leading, 12)
        .accessibilityHidden(true)
    }

    private var secondaryLine: String? {
        kind == .feature ? withKind(story.facts(length: true, german: german)) : story.argument
    }

    private var titleButton: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 3) {
                Text(story.card.media.title)
                    .font(.kuroCustom(17, weight: .semibold, relativeTo: .headline, maxSize: 34))
                    .tracking(-0.35)
                    .foregroundStyle(HomeInk.footTitle)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                if let line = secondaryLine {
                    Text(line)
                        .font(.kuroCustom(kind == .feature ? 10 : 11, relativeTo: .caption1, maxSize: 22))
                        .foregroundStyle(kind == .feature ? HomeInk.footFact : HomeInk.footSecondary)
                        // Four lines, so the pick's argument is never cut mid-word beside the key.
                        .lineLimit(kind == .feature ? 1 : 4)
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .discoverMenu(for: DiscoverCardItem(card: story.card, position: 0))
        .accessibilityLabel(spoken)
        .accessibilityHint(KuroLocale.text("Opens details", "Öffnet die Details"))
    }

    private var planKey: some View {
        DiscoverPlanKey(card: story.card, variant: .landscape, compact: compact)
    }

    @ViewBuilder
    private var foot: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                titleButton
                planKey
            }
            .padding(.horizontal, compact ? 11 : 14)
            .padding(.bottom, 10)
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(Double(0x18) / 255)).frame(height: 1) }
        } else {
            HStack(alignment: .center, spacing: compact ? 7 : 8) {
                titleButton
                DiscoverAtLeastWidth(minimum: DiscoverIssueLayout.footKeyColumn(compact: compact) - (compact ? 8 : 12)) {
                    planKey
                }
                .padding(.leading, compact ? 8 : 12)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1, height: 48)
                }
            }
            .padding(.leading, compact ? 11 : 14)
            .padding(.trailing, 10)
            .frame(minHeight: 58)
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(Double(0x18) / 255)).frame(height: 1) }
        }
    }

    @ViewBuilder
    private var factRow: some View {
        let facts = withKind(story.facts(length: false, german: german))
        let friends = friendCount
        if facts != nil || friends > 0 {
            HStack(spacing: 8) {
                if let facts {
                    Text(facts)
                        .font(.kuroCustom(compact ? 9 : 10, relativeTo: .caption2, maxSize: 22))
                        .foregroundStyle(HomeInk.footFact)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 8)
                if friends > 0 {
                    Button(action: open) {
                        Text(DiscoverIssueCopy.friendLine(friends, german: german))
                            .font(.kuroCustom(compact ? 9 : 10, relativeTo: .caption2, maxSize: 22))
                            .foregroundStyle(HomeInk.footFact)
                            .lineLimit(1)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(DiscoverFrameCopy.clubCount(friends, german: german))
                    .accessibilityHint(KuroLocale.text("Opens details", "Öffnet die Details"))
                }
            }
            .frame(minHeight: 40)
            .padding(.leading, compact ? 11 : 14)
            .padding(.trailing, compact ? 10 : 12)
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(Double(0x0D) / 255)).frame(height: 1) }
        }
    }

    // MARK: Spread (no banner)

    private func spread(material: ArtworkMaterial) -> some View {
        let cover = kind == .feature
            ? DiscoverIssueLayout.featureSpreadCover(compact: compact)
            : DiscoverIssueLayout.spreadCover(compact: compact)
        return HStack(alignment: .top, spacing: 0) {
            Button(action: open) {
                HomeArtwork(url: story.coverRaw.flatMap { URL(string: $0) }, maxPixelSize: 600,
                            placeholder: HomeInk.posterFill)
                    .frame(width: cover.width, height: cover.height)
                    .clipped()
                    .homeEntrance()
            }
            .buttonStyle(HomeArtworkPressStyle())
            .accessibilityHidden(true)
            .discoverMenu(for: DiscoverCardItem(card: story.card, position: 0))

            VStack(alignment: .leading, spacing: 0) {
                Button(action: open) {
                    VStack(alignment: .leading, spacing: 6) {
                        if kind != .feature {
                            Text(story.eyebrow)
                                .font(.kuroCustom(7, relativeTo: .caption2, maxSize: 14))
                                .tracking(1.4)
                                .textCase(.uppercase)
                                .foregroundStyle(HomeInk.footSecondary)
                                .lineLimit(1)
                        }
                        Text(story.card.media.title)
                            .font(.kuroCustom(kind == .feature ? 17 : (compact ? 18 : 20), weight: .semibold,
                                              relativeTo: .headline, maxSize: 36))
                            .tracking(kind == .feature ? -0.35 : -0.5)
                            .foregroundStyle(HomeInk.footTitle)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : (compact ? 2 : 3))
                        if kind != .feature, let argument = story.argument {
                            Text(argument)
                                .font(.kuroCustom(11, relativeTo: .caption1, maxSize: 22))
                                .foregroundStyle(HomeInk.footSecondary)
                                .lineLimit(compact ? 2 : 3)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .discoverMenu(for: DiscoverCardItem(card: story.card, position: 0))
                .accessibilityLabel(spoken)
                .accessibilityHint(KuroLocale.text("Opens details", "Öffnet die Details"))

                Spacer(minLength: 8)

                let facts = withKind(story.facts(length: kind == .feature, german: german))
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 8) {
                        if let facts { factText(facts) }
                        Spacer(minLength: 0)
                        planKey.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        if let facts { factText(facts) }
                        planKey
                    }
                }
            }
            .padding(.horizontal, compact ? 11 : 14)
            .padding(.vertical, compact ? 10 : 12)
            .frame(maxWidth: .infinity, minHeight: cover.height, alignment: .topLeading)
        }
    }

    private func factText(_ facts: String) -> some View {
        Text(facts)
            .font(.kuroCustom(compact ? 9 : 10, relativeTo: .caption2, maxSize: 22))
            .foregroundStyle(HomeInk.footFact)
            .lineLimit(1)
            .accessibilityHidden(true)
    }

    // MARK: Actions

    private var spoken: String {
        let title = kindKicker ? DiscoverIssueCopy.kindSpoken(story.card.media.kind, title: story.card.media.title)
                               : story.card.media.title
        if kind == .feature {
            return DiscoverIssueCopy.featureSpoken(title: title, facts: story.facts(length: true, german: german))
        }
        return DiscoverIssueCopy.storySpoken(eyebrow: story.eyebrow, title: title,
                                             argument: story.argument, facts: story.facts(length: false, german: german))
    }

    private func open() {
        guard !suppressCardTaps else { return }
        KuroAccessibility.impactHaptic(.light)
        feedback?.trackOpen(story.key, slot: section.map { DiscoverCardSlot(section: $0.id, position: 0) }, via: "card")
        routes.openMedia(MediaRoute(story.key))
    }
}

/// Lays its one child out at its own ideal width, but never narrower than `minimum` (the key column
/// keeps Home's measured width and grows only for a longer label, never truncating it).
struct DiscoverAtLeastWidth: Layout {
    let minimum: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let ideal = child.sizeThatFits(.unspecified)
        let width = max(minimum, ideal.width)
        let fitted = child.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
        return CGSize(width: width, height: fitted.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                              proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}
