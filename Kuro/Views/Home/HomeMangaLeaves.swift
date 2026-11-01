import KuroCore
import SwiftUI

// MARK: - Manga Home "Now reading" leaves (PROTOTYPE_SPEC.md §4 "Manga leaf", §5 width changes)
// Three equal columns of books. Each leaf is the cover (fixed height, top-biased crop, radius 4,
// shadow 0 2 3 #242c2514), the title centred in a 44 pt box (SF 11 w500, −0.2, two lines then
// truncated), a #d8ddd2 rule, then one row: "Ch." over the count (SF 24 w500, −0.8) and the solid
// manga key in a fixed 44 pt column, so a long or German title never reaches the key.
// Measured: 390 → columns 106, gaps 26 row / 14 column, cover 138; ≤ 360 → 88, 24 / 11, cover 119;
// 430 → the columns widen and the cover stays 138 (the manga Home is fixed in height).
// At accessibility text sizes the count sits above the key so a long count never truncates.
//
// Tracking stays in Home: the caller passes each card's readout and its `KuroAdvanceKey` (style
// `.dark`, built through Home's own advance path with the caught-up guard and Undo). This view never
// writes. Integration: `HomeView` (lane 4) embeds
//   HomeMangaLeaves(cards: split.inProgress, containerWidth: contentWidth,
//                   readout: { card in … }, onOpen: { card in open(card) }) { card in advanceKey(card, style: .dark) }

struct HomeMangaLeaves<Key: View>: View {
    /// What one leaf's row says: the chapter label ("24", or a unit label) and whether it is caught up.
    struct Readout: Equatable {
        let label: String
        let caughtUp: Bool
        /// VoiceOver: "Chapter 24 of 120" / "Caught up".
        let spoken: String
    }

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
                    Text(card.title)
                        .font(.kuroCustom(metrics.titleSize, weight: .medium, relativeTo: .caption1,
                                          maxSize: metrics.titleSize * 2))
                        .tracking(-0.2)
                        .foregroundStyle(Color(hex: "272C28"))
                        .multilineTextAlignment(.center)
                        .lineLimit(HomeMangaLeafMetrics.titleLineLimit(accessibility: accessibility))
                        .truncationMode(.tail)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity, minHeight: HomeMangaLeafMetrics.titleBox)
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
            VStack(alignment: .leading, spacing: 0) {
                Text(state.caughtUp ? KuroLocale.text("Caught up", "Aktuell") : KuroLocale.text("Ch.", "Kap."))
                    .font(.kuroCustom(9, relativeTo: .caption2, maxSize: 18))
                    .foregroundStyle(Color(hex: "59665A"))
                    .lineLimit(1)
                Text(state.caughtUp ? " " : state.label)
                    .font(.kuroCustom(24, weight: .medium, relativeTo: .title2, maxSize: 40))
                    .tracking(-0.8)
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: "27322B"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .kuroCountRoll(value: state.label, pageTurn: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Two lines, then truncated; three at accessibility sizes (the box grows with the text).
    static func titleLineLimit(accessibility: Bool) -> Int { accessibility ? 3 : 2 }

    /// Room left for the "Ch. N" count beside the key (never negative).
    var readoutWidth: CGFloat { max(0, columnWidth - Self.keyColumn) }
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

/// The leaves' loading shape (spec §5.4): three branded cover-leaf skeletons on the same grid as the
/// real leaves, shown while Home's titles in progress arrive. Integration: replaces the manga branch
/// of `HomeView.sceneLoadingShape`.
struct HomeMangaLeavesLoading: View {
    let containerWidth: CGFloat

    var body: some View {
        let metrics = HomeMangaLeafMetrics(width: containerWidth)
        HStack(alignment: .top, spacing: metrics.columnGap) {
            ForEach(0..<3, id: \.self) { _ in
                KuroSkeleton(kind: .coverLeaf)
                    .frame(width: metrics.columnWidth)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KuroLocale.text("Loading your titles in progress", "Deine laufenden Titel werden geladen"))
    }
}
