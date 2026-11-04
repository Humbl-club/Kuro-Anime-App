import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Mood keys (usability spec §5.4, D9)
// "IN THE MOOD FOR" (9 / 1.05), then a 2 × 2 grid, 10 pt gaps, each key 56 pt tall on the
// `KuroKeyFace(.light)` recipe, pressing with `HomeContactStyle` and a light haptic: a 15 pt symbol
// (timer, cup.and.saucer, bolt, heart), a 13 pt medium label and a 10 pt `kuroMuted` subtitle. The
// medium follows the issue (All and Anime: anime; Manga: manga). "Like {title}" shows only with a
// seed (the Library's latest well-rated Completed title); without one the grid keeps its shape with
// the last cell empty. At accessibility sizes, or a compact column with German, one column.
// A key opens the mood journey (a journey root, ✕ only; N3) through `DiscoverMoodBridge`, the swap
// point for lane B's `DiscoverMoodRoute.page(_:kind:german:)`.

struct DiscoverMoodKeys: View {
    let kind: MediaKind
    /// The "Like {title}" seed's title (nil: three keys).
    let likeTitle: String?
    let column: CGFloat
    let onOpen: (DiscoverMood) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var german: Bool { KuroLocale.isGerman }

    static let keyHeight: CGFloat = 56
    static let gap: CGFloat = 10

    /// One column at accessibility sizes, or a compact column in German (long labels).
    static func columns(accessibility: Bool, compact: Bool, german: Bool) -> Int {
        accessibility || (compact && german) ? 1 : 2
    }

    /// The moods shown: the four, without "Like" when there is no seed.
    static func moods(hasSeed: Bool) -> [DiscoverMood] {
        hasSeed ? DiscoverMood.allCases : DiscoverMood.allCases.filter { $0 != .likeLastLoved }
    }

    var body: some View {
        let compact = DiscoverIssueLayout.isCompact(column: column)
        let columns = Self.columns(accessibility: dynamicTypeSize.isAccessibilitySize, compact: compact, german: german)
        let moods = Self.moods(hasSeed: likeTitle != nil)
        VStack(alignment: .leading, spacing: 8) {
            Text(DiscoverIssueCopy.moodsEyebrow(german: german))
                .font(.kuroCustom(9, relativeTo: .caption2, maxSize: 18))
                .tracking(1.05)
                .textCase(.uppercase)
                .foregroundStyle(HomeInk.kicker)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.gap, alignment: .top), count: columns),
                      alignment: .leading, spacing: Self.gap) {
                ForEach(moods, id: \.self) { mood in
                    key(mood, compact: compact)
                }
            }
        }
    }

    /// In the compact column the words take two lines instead of truncating (288 pt, two columns).
    private func key(_ mood: DiscoverMood, compact: Bool) -> some View {
        let face = KuroKeyFace(style: .light)
        let title = DiscoverIssueCopy.moodTitle(mood, likeTitle: likeTitle, german: german)
        let subtitle = DiscoverIssueCopy.moodSubtitle(mood, german: german)
        return Button {
            KuroAccessibility.impactHaptic(.light)
            onOpen(mood)
        } label: {
            HStack(spacing: compact ? 8 : 10) {
                Image(systemName: DiscoverIssueCopy.moodSymbol(mood))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(face.ink)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.kuroCustom(13, weight: .medium, relativeTo: .footnote, maxSize: 26))
                        .foregroundStyle(face.ink)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : (compact ? 2 : 1))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                        .foregroundStyle(Color.kuroMuted)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : (compact ? 2 : 1))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: Self.keyHeight, alignment: .leading)
            .background(
                LinearGradient(colors: [face.top, face.bottom], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: face.radius + 3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: face.radius + 3, style: .continuous).strokeBorder(face.border, lineWidth: 1))
            .overlay(alignment: .top) {
                Rectangle().fill(face.highlight).frame(height: 1).padding(.horizontal, 8).padding(.top, 1)
            }
            .shadow(color: face.drop, radius: 1, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: face.radius + 3, style: .continuous))
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Mood journey bridge (swap point for lane B)

/// Opens a mood journey. Until lane B's `DiscoverMoodPage` lands this is an interim list over the
/// data lane's reader (`DiscoveryStore.moodPage`, accumulated with the hidden and owned rules); the
/// integrator replaces `page(_:kind:likeTitle:german:)`'s body with `DiscoverMoodRoute.page(...)`.
enum DiscoverMoodBridge {
    /// The journey's identity, so a second tap never stacks a copy (N5); B's page uses the same id.
    static func pageID(_ mood: DiscoverMood) -> String { "discover:mood:\(mood.rawValue)" }

    @MainActor
    static func page(_ mood: DiscoverMood, kind: MediaKind, likeTitle: String?, german: Bool) -> JourneyPage {
        let title = DiscoverIssueCopy.moodTitle(mood, likeTitle: likeTitle, german: german)
        return .custom(AnyJourneyPage(id: pageID(mood), title: title) {
            DiscoverMoodInterimPage(mood: mood, kind: kind, title: title)
        })
    }
}

/// The interim mood journey: heading, rows in index grammar with Plan keys, paging, the end line.
private struct DiscoverMoodInterimPage: View {
    let mood: DiscoverMood
    let kind: MediaKind
    let title: String

    @Environment(DiscoveryStore.self) private var discovery
    @Environment(TasteStore.self) private var taste
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var accumulator = DiscoverPageAccumulator(policy: .hide)
    @State private var loading = false
    @State private var failed = false
    @State private var collapse: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let width = DiscoverLayout.contentWidth(container: geo.size.width, regularWidth: horizontalSizeClass == .regular)
            let gutter = DiscoverIssueLayout.gutter(container: width)
            let column = max(0, width - gutter * 2)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    DiscoverPageHeading(title: DiscoverIssueCopy.heading(title))
                    let rows = accumulator.items.filter { !taste.isHiddenOnDiscover($0.item.key) }
                    if rows.isEmpty {
                        if loading || !accumulator.started {
                            VStack(spacing: 10) { ForEach(0..<6, id: \.self) { _ in KuroSkeleton(kind: .row) } }
                                .padding(.top, DiscoverIssueLayout.headingToContent)
                        } else {
                            KuroStateView(failed ? .failed(hasCachedContent: false) : .empty, layout: .inline,
                                          retry: failed ? { Task { await load(next: nil) } } : nil)
                                .padding(.top, DiscoverIssueLayout.headingToContent)
                        }
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.element.item.id) { index, placed in
                            DiscoverIndexRow(position: index + 1, card: Self.card(placed.item.card),
                                             compact: DiscoverIssueLayout.isCompact(column: column))
                        }
                        KuroLoadMoreSentinel(itemCount: rows.count, hasMore: accumulator.next != nil, isLoading: loading) {
                            await load(next: accumulator.next)
                        }
                    }
                }
                .padding(.horizontal, gutter)
                .padding(.top, KuroJourneyChrome.barHeight)
                .padding(.bottom, KuroDesignSpacing.xl)
                .frame(width: width)
                .frame(maxWidth: .infinity)
            }
            .kuroCollapseTracking($collapse, start: 0, distance: KuroJourneyChrome.barHeight)
            .background(Color.kuroCanvasHome)
        }
        .kuroJourneyChrome(title: title, collapseProgress: collapse)
        .task { if !accumulator.started { await load(next: nil) } }
    }

    private func load(next: DiscoverPageCursor?) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        guard let page = await discovery.moodPage(mood, medium: kind, cursor: next) else {
            failed = true
            return
        }
        failed = false
        var acc = accumulator
        discovery.accumulate(page, into: &acc, hidden: taste.discoverHiddenKeys)
        accumulator = acc
    }

    static func card(_ value: DiscoverCardValue) -> TasteCard {
        switch value {
        case .anime(let anime): return TasteCard(anime: anime)
        case .manga(let manga): return TasteCard(manga: manga)
        }
    }
}
