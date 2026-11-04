import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - See all, a real page (spec 2026-11-04 §5.5; replaces `DiscoverFullSectionSheet`)
// A journey root (✕ only, the H1 collapse) on Home's warm canvas. Top to bottom: the 24 pt heading, the
// purpose line and "{n} titles"; the sort words (`DiscoverRefineRow` grammar, VoiceOver "Sort"); the
// chips (format / length / status / Hide my list, groups split by a hairline); the match line while a
// chip is on; the rows (`DiscoverJourneyRow`: Plan key, status word when owned, the preview); then
// Loading more, the paging failure, or "That's all {n}.". Filtering never resets the page: the heading
// and chips stay put and only the list below them changes (no identity change above the list, so the
// scroll offset holds). Tapping a row pushes the title inside this journey (N9, N5).
//
// Data: `DiscoveryStore.seeAllPage` (prepared `discover_section_page_v1` first; live Browse keyset
// pages for the catalogue lists, the section's loaded rows sorted and filtered on the device for the
// bounded lists while the reader is not deployed), every page through `DiscoveryStore.accumulate`.

enum DiscoverSeeAllSource: Hashable {
    case route(EditorialDiscoverRoute)
}

struct DiscoverSeeAllPage: View {
    let source: DiscoverSeeAllSource
    let title: String
    let purpose: String
    let animeItems: [AnimeCard]
    let mangaItems: [MangaCard]
    let airingSlots: [Int: DiscoverAiringSlot]

    @Environment(DiscoveryStore.self) private var discovery
    @Environment(TasteStore.self) private var taste
    @Environment(LibraryStore.self) private var library
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?
    @Environment(InteractionTelemetry.self) private var telemetry: InteractionTelemetry?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var plans = TastePlanController()
    @State private var feedback = DiscoverFeedbackController()
    @State private var feed: DiscoverJourneyFeed
    @State private var selection: DiscoverSeeAllSelection
    /// Franchises hidden as Not interested during this journey (D16), by the answer's title.
    @State private var hiddenFranchises: [MediaKey: Set<DiscoverFranchiseKey>] = [:]
    @State private var collapse: CGFloat = 0
    @State private var opened = false

    private let section: DiscoverSeeAllSection

    /// `initialSelection` (renders, tests): the sort and chips the page opens with; nil = the list's own
    /// order, no chip.
    init(source: DiscoverSeeAllSource, title: String, purpose: String,
         animeItems: [AnimeCard], mangaItems: [MangaCard],
         airingSlots: [Int: DiscoverAiringSlot] = [:],
         initialSelection: DiscoverSeeAllSelection? = nil) {
        self.source = source
        self.title = title
        self.purpose = purpose
        self.animeItems = animeItems
        self.mangaItems = mangaItems
        self.airingSlots = airingSlots
        let section: DiscoverSeeAllSection
        switch source {
        case .route(let route): section = .of(route)
        }
        self.section = section
        _feed = State(initialValue: DiscoverJourneyFeed(policy: section.ownedPolicy))
        _selection = State(initialValue: initialSelection ?? DiscoverSeeAllSelection(sort: section.defaultSort))
    }

    private var german: Bool { KuroLocale.isGerman }

    private var sectionID: String {
        switch source {
        case .route(let route): return route.id
        }
    }

    private var loadedRows: [DiscoverCardValue] {
        animeItems.map(DiscoverCardValue.anime) + mangaItems.map(DiscoverCardValue.manga)
    }

    private var query: DiscoverSeeAllQuery { selection.query(for: section) }

    private var visible: [DiscoverPlacedItem<DiscoverPageItem>] {
        let franchises = DiscoverJourneyVisible.activeFranchises(hiddenFranchises, isHidden: taste.isHiddenOnDiscover)
        let selection = selection
        return DiscoverJourneyVisible.rows(
            feed.accumulator.items,
            isHidden: taste.isHiddenOnDiscover,
            hiddenFranchises: franchises,
            franchiseKeys: { discovery.franchiseKeys(for: $0) },
            include: { placed in
                let display = placed.item.card.display
                return selection.includes(kind: placed.item.key.kind, episodes: display.episodes,
                                          formatRaw: display.formatRaw, statusRaw: display.statusRaw,
                                          onList: library.entry(for: placed.item.key) != nil)
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
                    heading(rows: rows)
                    DiscoverWordRow(words: section.sortWords, selection: selection.sort,
                                    label: DiscoverSeeAllCopy.sortLabel(german: german),
                                    title: { DiscoverSeeAllCopy.sortWord($0, german: german) },
                                    onSelect: { word in
                                        selection.sort = word
                                        track("sorted")
                                    })
                        .padding(.top, 10)
                    DiscoverChipGroups(groups: section.chipGroups, medium: section.medium, selection: selection) { chip in
                        selection.toggle(chip)
                        track("filtered")
                    }
                    .padding(.top, 2)
                    if selection.activeCount > 0 {
                        matchLine(count: rows.count)
                    }
                    list(rows: rows, column: column)
                        .padding(.top, 8)
                }
                .padding(.horizontal, gutter)
                // Clears the ✕ key row; the headline then scrolls under the compact bar.
                .padding(.top, KuroJourneyChrome.barHeight)
                .padding(.bottom, KuroDesignSpacing.xl + 56)
                .frame(width: width)
                .frame(maxWidth: .infinity)
            }
            .kuroCollapseTracking($collapse, start: 0, distance: KuroJourneyChrome.barHeight)
            .background(Color.kuroCanvasHome)
            .environment(\.discoverMissingArt, HomeInk.posterFill)
        }
        .discoverFeedbackHost(feedback, plans: plans)
        .kuroJourneyChrome(title: title, collapseProgress: collapse)
        .onAppear {
            taste.restoreDiscoverMemory()
            guard !opened else { return }
            opened = true
            track("opened")
        }
        .task { await taste.loadDiscoverHidden() }
        .task(id: query) { await start() }
        .onChange(of: plans.lastResult) { _, result in trackPlan(result) }
    }

    // MARK: Sections

    private func heading(rows: [DiscoverPlacedItem<DiscoverPageItem>]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.kuroCustom(24, weight: .semibold, relativeTo: .title2, maxSize: 40))
                .tracking(-0.5)
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !purpose.isEmpty {
                Text(purpose)
                    .font(.kuroCustom(12, relativeTo: .footnote, maxSize: 24))
                    .foregroundStyle(Color.kuroMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if feed.phase == .ready, !rows.isEmpty, feed.isFinished || !section.isCatalogue {
                Text(DiscoverSeeAllCopy.titles(rows.count, german: german))
                    .font(.kuroCustom(11, relativeTo: .caption1, maxSize: 22))
                    .foregroundStyle(Color.kuroMuted)
            }
        }
    }

    private func matchLine(count: Int) -> some View {
        HStack(spacing: 6) {
            Text(DiscoverSeeAllCopy.matches(count, german: german))
                .font(.kuroCustom(12, relativeTo: .footnote, maxSize: 24))
                .foregroundStyle(Color.kuroMuted)
            Text(verbatim: "·")
                .font(.kuroCustom(12, relativeTo: .footnote, maxSize: 24))
                .foregroundStyle(Color.kuroMuted)
                .accessibilityHidden(true)
            DiscoverInkRuleLink(title: DiscoverSeeAllCopy.clearFilters(german: german)) {
                selection.clearFilters()
                track("filtered")
            }
        }
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
                    HomeQuietCard(text: selection.activeCount > 0
                                  ? DiscoverSeeAllCopy.nothingMatches(german: german)
                                  : DiscoverSeeAllCopy.nothingHere(unseenOnly: section.ownedPolicy == .hide, german: german))
                    if selection.activeCount > 0 {
                        DiscoverInkRuleLink(title: DiscoverSeeAllCopy.clearFilters(german: german)) {
                            selection.clearFilters()
                            track("filtered")
                        }
                    }
                }
            } else {
                let compact = DiscoverIssueLayout.isCompact(column: column)
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.item.id) { index, placed in
                        DiscoverJourneyRow(card: placed.item.card.tasteCard,
                                           ownedStatus: ownedStatus(placed),
                                           compact: compact,
                                           menu: menuItem(placed, position: index))
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

    // MARK: Rows

    private func ownedStatus(_ placed: DiscoverPlacedItem<DiscoverPageItem>) -> ListStatus? {
        guard section.ownedPolicy == .mark else { return nil }
        return library.entry(for: placed.item.key)?.status ?? placed.ownedStatus
    }

    private func menuItem(_ placed: DiscoverPlacedItem<DiscoverPageItem>, position: Int) -> DiscoverMenuItem {
        let item = placed.item
        return DiscoverMenuItem(
            card: item.card.tasteCard, section: sectionID, position: position,
            reason: DiscoverSeeAllCopy.reason(section.order, section: section.key, german: german),
            sectionTitle: title, surface: "discover_see_all",
            onHidden: { receipt in
                guard receipt.feedback == .notInterested else { return }
                hiddenFranchises[receipt.key] = discovery.franchiseKeys(for: item)
            })
    }

    // MARK: Loading

    private func start(force: Bool = false) async {
        let query = query
        let rows = loadedRows
        let discovery = discovery
        await feed.start(
            key: query, force: force,
            policy: section.ownedPolicy,
            fetch: { cursor in await discovery.seeAllPage(query, cursor: cursor, limit: 30, loadedRows: rows) },
            discovery: discovery, taste: taste,
            isOffline: { network?.isConnected == false },
            visibleCount: { visible.count })
    }

    private func loadMore() async {
        let before = feed.pages
        await feed.loadMore(discovery: discovery, taste: taste, visibleCount: { visible.count })
        if feed.pages > before { track("paged") }
    }

    // MARK: Telemetry (§5.12)

    private func track(_ result: String) {
        telemetry?.trackInteractionEvent(
            "discover_see_all", surface: "discover_see_all", result: result,
            extra: ["section": sectionID, "sort": selection.sort.telemetryName,
                    "filters": selection.activeCount, "pages": feed.pages])
    }

    private func trackPlan(_ result: TastePlanController.Result?) {
        guard let result, let telemetry else { return }
        let position = visible.firstIndex { $0.item.key == result.key } ?? -1
        DiscoverPlanTelemetry.track(telemetry, result: result, surface: "discover_see_all", section: sectionID,
                                    position: position, via: feedback.consumeMenuPlan(result.key) ? "menu" : "key")
    }
}

/// `discover_plan` from a page's Plan controller (§5.12).
enum DiscoverPlanTelemetry {
    static func resultName(_ outcome: TastePlanController.Result.Outcome) -> String {
        switch outcome {
        case .added: return "added"
        case .removed: return "removed"
        case .failed: return "failed"
        case .undone: return "undone"
        }
    }

    static func track(_ telemetry: InteractionTelemetry, result: TastePlanController.Result, surface: String,
                      section: String, position: Int, via: String) {
        var extra = DiscoverMenuTelemetry.titleExtra(section: section, position: position, key: result.key)
        extra["via"] = via
        telemetry.trackInteractionEvent("discover_plan", surface: surface, result: resultName(result.outcome), extra: extra)
    }
}
