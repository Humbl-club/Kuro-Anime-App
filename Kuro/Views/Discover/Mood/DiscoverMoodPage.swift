import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - A mood journey (spec 2026-11-04 §5.4; lane A draws the keys, this is the page they open)
// A journey root (✕ only, N3), opened with
//     routes.openPage(.custom(DiscoverMoodRoute.page(mood, kind: kind, german: german)))
// Top to bottom: the mood switch row (the four mood words; the current one selected; switching replaces
// the content in place, no push); the heading "{Mood}." with its purpose line (Like: the eyebrow
// "BECAUSE YOU FINISHED {TITLE}"); the Anime · Manga pair; the chips Films · Series (format, from the
// rows) and, for anime, "Up to 13 episodes"; the rows (`DiscoverJourneyRow`, the first under "Start
// here"); "That's all {n}." at the end. Empty: Home's quiet card (+ "Clear filters" while a chip is on).
//
// Data: `DiscoveryStore.moodPage` (prepared `discover_mood_v1` first; while it is not deployed the live
// fallbacks: short = Browse FINISHED with 1–13 episodes / 1–50 chapters, cozy / intense = one Browse
// genre, like = similar titles to the Library's latest Completed title, rated 8+ first). Hidden and
// owned titles never show (the owned rule of a mood journey is "hide", R2).

enum DiscoverMoodRoute {
    /// The journey page for a mood key (`seedTitle`: the "Like {title}" seed's title when the caller
    /// knows it; the page reads it itself otherwise).
    static func page(_ mood: DiscoverMood, kind: MediaKind, german: Bool, seedTitle: String? = nil) -> AnyJourneyPage {
        AnyJourneyPage(id: pageID(mood), title: DiscoverMoodCopy.pageTitle(mood, seedTitle: seedTitle, german: german)) {
            DiscoverMoodPage(mood: mood, kind: kind)
        }
    }

    /// The same page as a `JourneyPage` (`routes.openPage(DiscoverMoodRoute.journeyPage(...))`).
    static func journeyPage(_ mood: DiscoverMood, kind: MediaKind, german: Bool, seedTitle: String? = nil) -> JourneyPage {
        .custom(page(mood, kind: kind, german: german, seedTitle: seedTitle))
    }

    /// One page per mood (N5: a second tap on the same key never stacks a copy).
    static func pageID(_ mood: DiscoverMood) -> String { "discover:mood:\(mood.rawValue)" }

    /// The moods the switch row offers: Like only with a seed (D9).
    static func moods(hasSeed: Bool) -> [DiscoverMood] {
        DiscoverMood.allCases.filter { $0 != .likeLastLoved || hasSeed }
    }
}

/// The mood journey's local chips (pure): format (exclusive) and the anime length rule (≤ 13).
struct DiscoverMoodFilters: Hashable {
    enum Format: Hashable { case films, series }

    var format: Format?
    var upTo13 = false

    var activeCount: Int { (format == nil ? 0 : 1) + (upTo13 ? 1 : 0) }

    mutating func clear() {
        format = nil
        upTo13 = false
    }

    /// Films are MOVIE; series are TV, TV_SHORT and ONA (anime) and every non-film manga format.
    func includes(kind: MediaKind, formatRaw: String?, episodes: Int?) -> Bool {
        let format = formatRaw?.uppercased() ?? ""
        switch self.format {
        case .films?: if format != "MOVIE" { return false }
        case .series?:
            if kind == .anime {
                if !["TV", "TV_SHORT", "ONA"].contains(format) { return false }
            } else if format == "MOVIE" { return false }
        case nil: break
        }
        if upTo13, kind == .anime {
            guard let episodes, episodes >= 1, episodes <= 13 else { return false }
        }
        return true
    }
}

struct DiscoverMoodPage: View {
    @Environment(DiscoveryStore.self) private var discovery
    @Environment(TasteStore.self) private var taste
    @Environment(CatalogStore.self) private var catalog
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?
    @Environment(InteractionTelemetry.self) private var telemetry: InteractionTelemetry?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var mood: DiscoverMood
    @State private var kind: MediaKind
    @State private var filters = DiscoverMoodFilters()
    @State private var plans = TastePlanController()
    @State private var feedback = DiscoverFeedbackController()
    @State private var feed = DiscoverJourneyFeed(policy: .hide)
    @State private var hiddenFranchises: [MediaKey: Set<DiscoverFranchiseKey>] = [:]
    @State private var seedTitles: [MediaKind: String] = [:]
    @State private var collapse: CGFloat = 0
    @State private var trackedOpen: Set<String> = []

    /// `filters` (renders, tests): the chips the page opens with.
    init(mood: DiscoverMood, kind: MediaKind, filters: DiscoverMoodFilters = DiscoverMoodFilters()) {
        _mood = State(initialValue: mood)
        _kind = State(initialValue: kind)
        _filters = State(initialValue: filters)
    }

    private var german: Bool { KuroLocale.isGerman }

    private struct Load: Hashable {
        let mood: DiscoverMood
        let kind: MediaKind
    }

    private var seed: MediaKey? { discovery.likeLastLovedSeed(medium: kind) }

    /// The seed's title: the page reason (the server / fallback name it), else the catalogue read.
    private var seedTitle: String? { feed.accumulator.reason?.title ?? seedTitles[kind] }

    private var moods: [DiscoverMood] { DiscoverMoodRoute.moods(hasSeed: seed != nil) }

    private var visible: [DiscoverPlacedItem<DiscoverPageItem>] {
        let franchises = DiscoverJourneyVisible.activeFranchises(hiddenFranchises, isHidden: taste.isHiddenOnDiscover)
        let filters = filters
        return DiscoverJourneyVisible.rows(
            feed.accumulator.items,
            isHidden: taste.isHiddenOnDiscover,
            hiddenFranchises: franchises,
            franchiseKeys: { discovery.franchiseKeys(for: $0) },
            include: { placed in
                let display = placed.item.card.display
                return filters.includes(kind: placed.item.key.kind, formatRaw: display.formatRaw, episodes: display.episodes)
            })
    }

    var body: some View {
        GeometryReader { geo in
            let width = DiscoverLayout.contentWidth(container: geo.size.width, regularWidth: horizontalSizeClass == .regular)
            let gutter = DiscoverLayout.gutter(for: width)
            let column = max(0, width - gutter * 2)
            let rows = visible
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if network?.isConnected == false, !rows.isEmpty {
                        KuroOfflineView(hasContent: true)
                            .padding(.bottom, 12)
                    }
                    DiscoverWordRow(words: moods, selection: mood, label: DiscoverMoodCopy.moodsLabel(german: german),
                                    title: { DiscoverMoodCopy.word($0, seedTitle: $0 == .likeLastLoved ? seedTitle : nil,
                                                                   german: german) },
                                    onSelect: { mood = $0 })
                    heading
                        .padding(.top, 10)
                    DiscoverWordRow(words: [MediaKind.anime, .manga], selection: kind,
                                    label: DiscoverMoodCopy.mediumLabel(german: german),
                                    title: { DiscoverMoodCopy.medium($0) },
                                    onSelect: { next in
                                        kind = next
                                        if next == .manga { filters.upTo13 = false }
                                        if mood == .likeLastLoved, discovery.likeLastLovedSeed(medium: next) == nil { mood = .short }
                                    })
                        .padding(.top, 8)
                    chips
                        .padding(.top, 2)
                    list(rows: rows, column: column)
                        .padding(.top, 8)
                }
                .padding(.horizontal, gutter)
                .padding(.top, KuroJourneyChrome.barHeight)
                .padding(.bottom, KuroDesignSpacing.xl + 56)
                .frame(width: width)
                .frame(maxWidth: .infinity)
            }
            .kuroCollapseTracking($collapse, start: 0, distance: KuroJourneyChrome.barHeight)
            .background(kind == .manga ? Color.kuroCanvasHomeManga : Color.kuroCanvasHome)
            .environment(\.discoverMissingArt, HomeInk.posterFill)
        }
        .discoverFeedbackHost(feedback, plans: plans)
        .kuroJourneyChrome(title: DiscoverMoodCopy.pageTitle(mood, seedTitle: seedTitle, german: german),
                           collapseProgress: collapse)
        .onAppear { taste.restoreDiscoverMemory() }
        .task { await taste.loadDiscoverHidden() }
        .task(id: Load(mood: mood, kind: kind)) { await start() }
        .onChange(of: plans.lastResult) { _, result in
            guard let result, let telemetry else { return }
            let position = visible.firstIndex { $0.item.key == result.key } ?? -1
            DiscoverPlanTelemetry.track(telemetry, result: result, surface: "discover_mood", section: sectionID,
                                        position: position, via: feedback.consumeMenuPlan(result.key) ? "menu" : "key")
        }
    }

    private var sectionID: String { "mood:\(mood.rawValue)" }

    // MARK: Sections

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            if mood == .likeLastLoved, let seedTitle {
                Text(DiscoverMoodCopy.becauseEyebrow(seedTitle, german: german))
                    .font(.kuroCustom(9, weight: .semibold, relativeTo: .caption2, maxSize: 18))
                    .tracking(1.05)
                    .foregroundStyle(Color.kuroMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(DiscoverMoodCopy.word(mood, seedTitle: seedTitle, german: german) + ".")
                .font(.kuroCustom(24, weight: .semibold, relativeTo: .title2, maxSize: 40))
                .tracking(-0.5)
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(DiscoverMoodCopy.purpose(mood, seedTitle: seedTitle, german: german))
                .font(.kuroCustom(12, relativeTo: .footnote, maxSize: 24))
                .foregroundStyle(Color.kuroMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var chips: some View {
        DiscoverChipFlow {
            DiscoverChip(title: DiscoverMoodCopy.films(german: german), selected: filters.format == .films) {
                filters.format = filters.format == .films ? nil : .films
            }
            DiscoverChip(title: DiscoverMoodCopy.series(german: german), selected: filters.format == .series) {
                filters.format = filters.format == .series ? nil : .series
            }
            if kind == .anime {
                DiscoverChipSeparator()
                DiscoverChip(title: DiscoverSeeAllCopy.chip(.upTo13, medium: .anime, german: german),
                             selected: filters.upTo13) { filters.upTo13.toggle() }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(DiscoverSeeAllCopy.filtersLabel(german: german))
    }

    @ViewBuilder
    private func list(rows: [DiscoverPlacedItem<DiscoverPageItem>], column: CGFloat) -> some View {
        switch feed.phase {
        case .loading:
            DiscoverJourneySkeleton()
        case .offline:
            KuroOfflineView(hasContent: false) { Task { await start(force: true) } }
        case .failed:
            KuroStateView(.failed(hasCachedContent: false), layout: .inline) { Task { await start(force: true) } }
        case .ready:
            if rows.isEmpty, !feed.hasMore, !feed.isLoadingMore {
                VStack(alignment: .leading, spacing: 4) {
                    HomeQuietCard(text: DiscoverMoodCopy.empty(mood, seedTitle: seedTitle, german: german))
                    if filters.activeCount > 0 {
                        DiscoverInkRuleLink(title: DiscoverSeeAllCopy.clearFilters(german: german)) { filters.clear() }
                    }
                }
            } else {
                let compact = DiscoverIssueLayout.isCompact(column: column)
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.item.id) { index, placed in
                        VStack(alignment: .leading, spacing: 0) {
                            if index == 0 {
                                Text(DiscoverMoodCopy.startHere(german: german).uppercased())
                                    .font(.kuroCustom(9, weight: .semibold, relativeTo: .caption2, maxSize: 18))
                                    .tracking(1.05)
                                    .foregroundStyle(Color.kuroMuted)
                                    .padding(.top, 6)
                            }
                            DiscoverJourneyRow(card: placed.item.card.tasteCard, ownedStatus: nil, compact: compact,
                                               menu: menuItem(placed, position: index))
                        }
                        .transition(.discoverHide(reduceMotion: reduceMotion))
                    }
                    if feed.hasMore, !feed.isLoadingMore, !feed.pageFailed {
                        DiscoverPageTrigger(itemCount: feed.accumulator.items.count) { Task { await loadMore() } }
                    }
                    DiscoverJourneyFooter(isLoadingMore: feed.isLoadingMore, pageFailed: feed.pageFailed,
                                          finished: feed.isFinished, count: rows.count) { Task { await loadMore() } }
                }
                .kuroAnimation(KuroMotion.settle, value: rows.map(\.item.id))
            }
        }
    }

    private func menuItem(_ placed: DiscoverPlacedItem<DiscoverPageItem>, position: Int) -> DiscoverMenuItem {
        let item = placed.item
        let reason = mood == .likeLastLoved
            ? seedTitle.map { DiscoverMenuCopy.Reason.closeTo($0).text(german: german) }
            : DiscoverMoodCopy.subtitle(mood, german: german).lowercased()
        return DiscoverMenuItem(
            card: item.card.tasteCard, section: sectionID, position: position, reason: reason,
            sectionTitle: DiscoverMoodCopy.word(mood, seedTitle: seedTitle, german: german), surface: "discover_mood",
            onHidden: { receipt in
                guard receipt.feedback == .notInterested else { return }
                hiddenFranchises[receipt.key] = discovery.franchiseKeys(for: item)
            })
    }

    // MARK: Loading

    private func start(force: Bool = false) async {
        let mood = mood
        let kind = kind
        let discovery = discovery
        await loadSeedTitle(kind: kind)
        await feed.start(
            key: Load(mood: mood, kind: kind), force: force,
            policy: .hide,
            fetch: { cursor in await discovery.moodPage(mood, medium: kind, cursor: cursor, limit: 24) },
            discovery: discovery, taste: taste,
            isOffline: { network?.isConnected == false },
            visibleCount: { visible.count })
        guard feed.phase == .ready, mood == self.mood, kind == self.kind else { return }
        let key = "\(mood.rawValue):\(kind.rawValue)"
        guard !trackedOpen.contains(key) else { return }
        trackedOpen.insert(key)
        let count = visible.count
        telemetry?.trackInteractionEvent(
            "discover_mood_open", surface: "discover_mood", result: count == 0 ? "empty" : "opened",
            extra: ["mood": mood.rawValue, "medium": kind.rawValue.uppercased(), "count": count])
    }

    private func loadMore() async {
        await feed.loadMore(discovery: discovery, taste: taste, visibleCount: { visible.count })
    }

    /// The "Like {title}" seed's title from the catalogue (cached), for the switch word before a page.
    private func loadSeedTitle(kind: MediaKind) async {
        guard seedTitles[kind] == nil, let seed = discovery.likeLastLovedSeed(medium: kind) else { return }
        let title: String?
        switch kind {
        case .anime: title = (try? await catalog.fetchAnimeById(seed.id))?.map(\.title)
        case .manga: title = (try? await catalog.fetchMangaById(seed.id))?.map(\.title)
        }
        if let title, !title.isEmpty { seedTitles[kind] = KuroCardText.sanitizeTitleForCard(title) }
    }
}
