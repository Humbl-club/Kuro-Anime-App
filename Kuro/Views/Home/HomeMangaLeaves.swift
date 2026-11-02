import KuroCore
import SwiftUI

// MARK: - Manga Home "Now reading" leaves (PROTOTYPE_SPEC.md §4 "Manga leaf", §5 width changes)
// Three equal columns of books. Each leaf is the cover (fixed height, top-biased crop, radius 4,
// shadow 0 2 3 #242c2514), the title centred in a 44 pt box (SF 11 w500, −0.2, two lines then
// truncated), a #d8ddd2 rule, then one row: "Ch." over the count (SF 24 w500, −0.8) and the solid
// manga key in a fixed 44 pt column, so a long or German title never reaches the key.
// Measured: 390 → columns 106, gaps 26 row / 14 column, cover 138; ≤ 360 → 88, 24 / 11, cover 119;
// 430 → the columns widen and the cover stays 138 (the manga Home is fixed in height).
// At accessibility text sizes the title still wraps to two lines and then truncates (every leaf
// then reserves both lines, so the rules and "Ch." rows stay level), and the count sits above the
// key so a long count never truncates.
//
// Tracking stays in Home: the caller passes each card's readout and its `KuroAdvanceKey` (style
// `.dark`, built through Home's own advance path with the caught-up guard and Undo). This view never
// writes. `HomeView.mangaLeaves` embeds it for the manga titles in progress, and `HomeMangaLeavesLoading`
// is its loading shape.

/// What one leaf's row says: the chapter label ("24", or a unit label) and whether it is caught up.
struct HomeMangaLeafReadout: Equatable {
    let label: String
    let caughtUp: Bool
    /// VoiceOver: "Chapter 24 of 120" / "Caught up".
    let spoken: String
}

struct HomeMangaLeaves<Key: View>: View {
    typealias Readout = HomeMangaLeafReadout

    let cards: [HomeCard]
    let containerWidth: CGFloat
    let readout: (HomeCard) -> Readout
    let onOpen: (HomeCard) -> Void
    let key: (HomeCard) -> Key

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(cards: [HomeCard], containerWidth: CGFloat,
         readout: @escaping (HomeCard) -> Readout,
         onOpen: @escaping (HomeCard) -> Void,
         @ViewBuilder key: @escaping (HomeCard) -> Key) {
        self.cards = cards
        self.containerWidth = containerWidth
        self.readout = readout
        self.onOpen = onOpen
        self.key = key
    }

    var body: some View {
        let metrics = HomeMangaLeafMetrics(width: containerWidth)
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(metrics.columnWidth), spacing: metrics.columnGap, alignment: .top),
                           count: metrics.columns),
            alignment: .leading,
            spacing: metrics.rowGap
        ) {
            ForEach(cards) { card in leaf(card, metrics: metrics) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func leaf(_ card: HomeCard, metrics: HomeMangaLeafMetrics) -> some View {
        let accessibility = dynamicTypeSize.isAccessibilitySize
        return VStack(spacing: 0) {
            Button { onOpen(card) } label: {
                VStack(spacing: metrics.storyGap) {
                    HomeLeafCover(raw: card.coverImage)
                        .frame(width: metrics.columnWidth, height: metrics.coverHeight, alignment: .top)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .shadow(color: Color(hex: "242C25", opacity: Double(0x14) / 255), radius: 1.5, y: 2)
                    HomeMangaLeafTitle(title: card.title, metrics: metrics)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(HomeContactStyle())
            .accessibilityLabel(KuroLocale.text("Open \(card.title)", "\(card.title) öffnen"))
            actionRow(card, accessibility: accessibility)
        }
        .frame(width: metrics.columnWidth)
    }

    private func actionRow(_ card: HomeCard, accessibility: Bool) -> some View {
        let state = readout(card)
        let layout = accessibility
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 0))
        return layout {
            let german = KuroLocale.isGerman
            let showsCount = HomeMangaLeafMetrics.showsCount(caughtUp: state.caughtUp, german: german)
            VStack(alignment: .leading, spacing: 0) {
                // "Caught up" takes the "Ch." slot and the count stays under it (the reference). The
                // German word ("Auf dem neuesten Stand") is too long for the 9 pt slot of a 62 pt
                // column: it takes the count's lines too, up to three, in the same row height
                // (LANE_AMENDMENTS 14), and the spoken label still carries the position.
                Text(HomeMangaLeafMetrics.readoutLabel(caughtUp: state.caughtUp, german: german))
                    .font(.kuroCustom(9, relativeTo: .caption2, maxSize: 18))
                    .foregroundStyle(Color(hex: "59665A"))
                    .lineLimit(showsCount ? 1 : 3)
                    // "Caught up" in a 44 pt readout at 320 pt phones: scale a little, never "Caught…".
                    .minimumScaleFactor(showsCount ? 0.8 : 1)
                    .fixedSize(horizontal: false, vertical: !showsCount)
                if showsCount {
                    Text(state.label)
                        .font(.kuroCustom(24, weight: .medium, relativeTo: .title2, maxSize: 40))
                        .tracking(-0.8)
                        .monospacedDigit()
                        .foregroundStyle(Color(hex: "27322B"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .kuroCountRoll(value: state.label, pageTurn: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: HomeMangaLeafMetrics.readoutHeight, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.spoken)
            key(card)
                .frame(width: HomeMangaLeafMetrics.keyColumn, height: HomeMangaLeafMetrics.keyColumn)
        }
        .padding(.top, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Color(hex: "D8DDD2")).frame(height: 1) }
    }
}

/// The leaf geometry for a measured content width (pure; PROTOTYPE_SPEC.md §4, §5).
struct HomeMangaLeafMetrics: Equatable {
    /// The key's column: a fixed 44 pt target the title and count never enter.
    static let keyColumn: CGFloat = 44
    /// The title's box under the cover.
    static let titleBox: CGFloat = 44
    /// The prototype's leaf column at 390 pt.
    static let regularColumn: CGFloat = 106

    let columns: Int
    let columnWidth: CGFloat
    let columnGap: CGFloat
    let rowGap: CGFloat
    let coverHeight: CGFloat
    let titleSize: CGFloat
    let storyGap: CGFloat

    /// Small phones follow the prototype's `@media(max-width:360px)`: the same breakpoint the medium
    /// switch uses (`KuroMediumSwitch.smallPhoneContainer`), so both change together.
    init(width: CGFloat) {
        let small = width > 0 && width <= KuroMediumSwitch.smallPhoneContainer
        columnGap = small ? 11 : 14
        rowGap = small ? 24 : 26
        coverHeight = small ? 119 : 138
        titleSize = small ? 10 : 11
        storyGap = small ? 6 : 8
        let usable = max(width, 0)
        // Three columns on phones; a wide readable column (iPad) adds columns of at least the
        // prototype's 106 pt rather than stretching three covers.
        columns = max(3, Int((usable + columnGap) / (Self.regularColumn + 40 + columnGap)))
        let raw = (usable - columnGap * CGFloat(columns - 1)) / CGFloat(columns)
        columnWidth = max(Self.keyColumn + 30, raw.rounded(.down))
    }

    /// Two lines, then truncated, at every text size (plan edge case 1); the box grows with the text.
    static let titleLineLimit = 2

    /// The small label over the count: "Ch." / "Kap.", or the app's one caught-up word, "Caught up" /
    /// "Auf dem neuesten Stand" (`KuroAdvanceCopy.caughtUpLabel`, PROTOTYPE_SPEC §7.1).
    static func readoutLabel(caughtUp: Bool, german: Bool) -> String {
        if caughtUp { return KuroAdvanceCopy.caughtUpLabel(title: nil, german: german) }
        return german ? "Kap." : "Ch."
    }

    /// Whether the count shows under the label: always, except a German caught-up leaf, whose long
    /// word takes the count's lines (LANE_AMENDMENTS 14).
    static func showsCount(caughtUp: Bool, german: Bool) -> Bool {
        !(caughtUp && german)
    }

    /// The readout column's height at regular sizes ("Ch." 9 pt over the 24 pt count), kept when the
    /// caught-up word replaces the count, so a caught-up leaf's row stays level with its neighbours.
    static let readoutHeight: CGFloat = 40

    /// One leaf's full height without accessibility sizes: cover, gap, title box, the "Ch." + key row.
    var leafHeight: CGFloat { coverHeight + storyGap + Self.titleBox + Self.actionRow }
    /// The "Ch. N" + key row under the rule (5 pt padding over the 44 pt key, as measured: 50).
    static let actionRow: CGFloat = 50

    /// Room left for the "Ch. N" count beside the key (never negative).
    var readoutWidth: CGFloat { max(0, columnWidth - Self.keyColumn) }
}

/// The leaf's title in its own box above the rule: two lines, then truncated, at every size. At
/// accessibility sizes both lines are reserved, so a short title takes the same height as a long
/// one and the rules and "Ch." rows of one grid row stay level.
struct HomeMangaLeafTitle: View {
    let title: String
    let metrics: HomeMangaLeafMetrics

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let accessibility = dynamicTypeSize.isAccessibilitySize
        Text(title)
            .font(Self.font(metrics))
            .tracking(-0.2)
            .foregroundStyle(Color(hex: "272C28"))
            .multilineTextAlignment(.center)
            // At regular sizes the 44 pt box keeps the rules level and a one-line title centres in
            // it (as the prototype's); at accessibility sizes both lines are reserved instead.
            .lineLimit(HomeMangaLeafMetrics.titleLineLimit, reservesSpace: accessibility)
            .truncationMode(.tail)
            // The lazy grid row must not hold a two-line title to one line.
            .fixedSize(horizontal: false, vertical: true)
            // 3 pt over and under; 5 under at accessibility sizes, so descenders clear the rule.
            .padding(.top, 3)
            .padding(.bottom, accessibility ? 5 : 3)
            .frame(maxWidth: .infinity, minHeight: HomeMangaLeafMetrics.titleBox)
    }

    static func font(_ metrics: HomeMangaLeafMetrics) -> Font {
        .kuroCustom(metrics.titleSize, weight: .medium, relativeTo: .caption1, maxSize: metrics.titleSize * 2)
    }
}

/// A caught-up manga leaf key: the prototype's disabled light raised key (`.step:disabled` on the
/// manga Home): a 40 pt pale face with a 1 pt grey rule, radius 6, and a thin 10 pt muted check. Not
/// interactive; VoiceOver hears the title and "Caught up".
struct HomeLeafCaughtUpKey: View {
    let accessibilityText: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Image(systemName: "checkmark")
            .font(.kuroCustom(10, weight: .light, relativeTo: .body, maxSize: 18))
            .foregroundStyle(HomeInk.caughtUpOnPaper)
            .frame(width: 44, height: 44)
            .background {
                shape.fill(Color(hex: "FAFAF7"))
                    .overlay(shape.strokeBorder(Color(hex: "C5CAC4"), lineWidth: 1))
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityValue(KuroAdvanceCopy.caughtUpLabel(title: nil, german: KuroLocale.isGerman))
    }
}

/// One equal cover; a missing cover keeps its frame.
private struct HomeLeafCover: View {
    let raw: String?

    var body: some View {
        if let raw, let url = URL(string: raw) {
            KuroCachedAsyncImage(url: url, maxPixelSize: 400) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
                else { Color.kuroMissingArt }
            }
        } else {
            Color.kuroMissingArt
        }
    }
}

/// The leaves' loading shape (spec §5.4): two rows of branded cover-leaf skeletons on the same grid
/// and in the same leaf height as the real leaves, so nothing jumps when they arrive. Shown while
/// Home's titles in progress load (the manga branch of `HomeView.sceneLoadingShape`).
struct HomeMangaLeavesLoading: View {
    let containerWidth: CGFloat

    var body: some View {
        let metrics = HomeMangaLeafMetrics(width: containerWidth)
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(metrics.columnWidth), spacing: metrics.columnGap, alignment: .top),
                           count: metrics.columns),
            alignment: .leading,
            spacing: metrics.rowGap
        ) {
            ForEach(0..<(metrics.columns * 2), id: \.self) { _ in
                KuroSkeleton(kind: .coverLeaf)
                    .frame(width: metrics.columnWidth, height: metrics.leafHeight, alignment: .top)
                    .clipped()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KuroLocale.text("Loading your titles in progress", "Deine laufenden Titel werden geladen"))
    }
}
