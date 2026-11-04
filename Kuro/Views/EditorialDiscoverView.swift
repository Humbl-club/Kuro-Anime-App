// Discover (Discover + Clubs redesign §6, "Discover is an issue"; spec D8, D2; rulebook §14.5)
// A daily issue in Home's grammar on Home's warm paper (`kuroCanvasHome`, the manga canvas on the
// Manga issue; the header paints the same canvas through `KuroMainView.Section.canvas`): the opening
// row ("TODAY'S ISSUE · TUE 3 NOV" / "Edited for you."), the three-word issue switch, one cover story
// on the title's own artwork material with the Plan key, the Airing today glance, the contents line
// with Browse, then sections in different forms: a feature plus three covers, a numbered index, one
// rail with its local refinement, the fold (session memory, F3), Home's footer. The curated order,
// every source and every flag gate are unchanged; a rail refinement stays a local filter.
// The page reads the `discover_bundle` once per launch (`DiscoveryStore.ensureDiscoverBundle`); only
// pull to refresh asks for a fresh one. "Airing today" is ordered by the stated air time where the
// catalogue states one (never estimated). States: the issue skeleton on first paint, then the branded
// offline, failed and empty states, and the quiet offline band over earlier content.

import KuroCore
import KuroLibrary
import SwiftUI

struct EditorialDiscoverView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(SocialActivityStore.self) private var social
    @Environment(CatalogStore.self) private var catalog
    @Environment(DiscoveryStore.self) private var discovery
    @Environment(ReleasesStore.self) private var releases
    @Environment(TasteStore.self) private var taste
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(FeatureFlags.self) private var flags
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.kuroRoutes) private var routes
    @Environment(\.kuroFoldMemory) private var folds
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var vm = DiscoverViewModel()
    @State private var isLoadingSections = false
    @State private var didInitialLoad = false
    @State private var bannerMessage: String? = nil
    @State private var bannerTask: Task<Void, Never>? = nil
    @State private var loadError = false
    /// The page's Plan keys (plan / unplan with Undo; a tracked title opens the editor).
    @State private var plans = TastePlanController()
    /// Top rated's local refinement (folded section).
    @State private var topRatedFilter: DiscoverRailFilter = .all

    /// The issue lives in `KuroMainView` (so the header canvas follows it); hosts without one (tests,
    /// previews) keep it here.
    private let externalIssue: Binding<DiscoverMediaTypeFilter>?
    @State private var localIssue: DiscoverMediaTypeFilter = .all

    init(issue: Binding<DiscoverMediaTypeFilter>? = nil) {
        self.externalIssue = issue
    }

    enum DiscoverMediaTypeFilter: String, CaseIterable {
        case all = "ALL"
        case anime = "ANIME"
        case manga = "MANGA"

        func title(german: Bool) -> String {
            switch self {
            case .all: return german ? "Alle" : "All"
            case .anime: return "Anime"
            case .manga: return "Manga"
            }
        }
    }

    private var selectedMediaType: DiscoverMediaTypeFilter { externalIssue?.wrappedValue ?? localIssue }
    private var issueBinding: Binding<DiscoverMediaTypeFilter> { externalIssue ?? $localIssue }

    private var showsAnime: Bool { selectedMediaType != .manga }
    private var showsManga: Bool { selectedMediaType != .anime }

    /// The page canvas, the same token `KuroMainView.Section.canvas` paints under the header (D2).
    private var canvas: Color { selectedMediaType == .manga ? Color.kuroCanvasHomeManga : Color.kuroCanvasHome }

    /// The fold's session memory (F3): one per app run, never persisted (replaces the device-wide
    /// `kuro_discover_show_more` default, which this page no longer reads).
    private var showMoreSections: Binding<Bool> {
        folds.binding(page: DiscoverIssueCopy.foldPage, section: DiscoverIssueCopy.foldSection)
    }

    private var hasAnyContent: Bool {
        !vm.essentials.isEmpty ||
        !vm.classics.isEmpty ||
        !vm.newToYou.isEmpty ||
        !vm.airingToday.isEmpty ||
        !vm.currentSeason.isEmpty ||
        !vm.trending.isEmpty ||
        !vm.topRated.isEmpty ||
        !vm.newlyAdded.isEmpty ||
        !vm.essentialsManga.isEmpty ||
        !vm.classicsManga.isEmpty ||
        !vm.newToYouManga.isEmpty ||
        !vm.trendingManga.isEmpty ||
        !vm.topRatedManga.isEmpty ||
        !vm.newlyAddedManga.isEmpty
    }

    /// Browse is a pager page in the live order; where the pager has none (series Home), Discover
    /// offers the catalogue through the Browse route (spec D2).
    private var offersBrowseEntry: Bool { DiscoverBrowseEntry.isOffered(flags: flags) }

    /// Stated slots for the Airing today rail: the catalogue read, then the reader's own upcoming
    /// airings (the same `next_airing_at`) for titles the read has not covered.
    private var airingSlots: [Int: DiscoverAiringSlot] {
        var slots = discovery.airingSlots
        for airing in releases.upcomingAirings where slots[airing.anime_id] == nil {
            slots[airing.anime_id] = DiscoverAiringSlot(
                animeId: airing.anime_id,
                airingAt: airing.next_airing_at,
                episode: airing.next_episode_number
            )
        }
        return slots
    }

    var body: some View {
        GeometryReader { geo in
            let width = DiscoverLayout.contentWidth(
                container: geo.size.width,
                regularWidth: horizontalSizeClass == .regular
            )
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    content(width: width, minHeight: geo.size.height, proxy: proxy)
                        .frame(width: width)
                        .frame(maxWidth: .infinity)
                }
                // A parent `.scrollDisabled(true)` (e.g. on a paging container) can propagate via environment.
                // Keep Discover scrollable regardless.
                .scrollDisabled(false)
                .background(canvas)
                .animation(KuroMotion.playsMotionNow(reduceMotion: reduceMotion) ? KuroMotion.medium : nil, value: canvas)
                .refreshable {
                    // Pull-to-refresh is user-initiated: also re-read the Library projection
                    // (badges/progress), next to the bundle. The first load relies on the session refresh.
                    async let libraryRefresh: Void? = try? library.refresh()
                    await refreshSections(force: true)
                    _ = await libraryRefresh
                }
            }
            .overlay(alignment: .top) {
                if let bannerMessage {
                    KuroTransientBanner(message: bannerMessage)
                        .padding(.top, 10)
                        .transition(.opacity)
                }
            }
            .task {
                if !didInitialLoad {
                    didInitialLoad = true
                    await refreshSections(force: false)
                }
            }
            .onChange(of: networkMonitor.reconnectionGeneration) { _, _ in
                // Back online after a failed first load: read again (the launch bundle, if the
                // reconnect already brought one, or a new read).
                guard networkMonitor.isConnected, loadError || !hasAnyContent, !isLoadingSections else { return }
                Task { await refreshSections(force: false) }
            }
            .onDisappear {
                bannerTask?.cancel()
            }
        }
        // The Plan keys' toast, outside the ScrollView so it stays at the page foot.
        .tastePlanHost(plans)
        .environment(\.discoverMissingArt, HomeInk.posterFill)
    }

    // MARK: Page

    @ViewBuilder
    private func content(width: CGFloat, minHeight: CGFloat, proxy: ScrollViewProxy) -> some View {
        let gutter = DiscoverIssueLayout.gutter(container: width)
        let column = max(0, width - gutter * 2)
        // One switch on the branded state (`DiscoverPageRules.brandedState`, tested in RestyleLaneTests).
        switch DiscoverPageRules.brandedState(isLoading: isLoadingSections, hasContent: hasAnyContent,
                                              failed: loadError, isConnected: networkMonitor.isConnected) {
        case .loading:
            DiscoverIssueSkeleton(column: column)
                .padding(.horizontal, gutter)
                .padding(.top, DiscoverIssueLayout.top)
        case .failed(hasContent: false):
            KuroErrorView(headline: KuroLocale.text("Couldn't load Discover.", "Entdecken konnte nicht geladen werden."),
                          retry: { Task { await refreshSections(force: true) } })
                .frame(minHeight: minHeight * 0.8)
        case .offline(hasContent: false):
            KuroOfflineView(hasContent: false, retry: { Task { await refreshSections(force: true) } })
                .frame(minHeight: minHeight * 0.8)
        case .empty:
            VStack(spacing: KuroDesignSpacing.lg) {
                // The ink-rule retry, the same style as the offline and failed states (P13).
                KuroEmptyView(headline: DiscoverIssueCopy.emptyTitle(german: KuroLocale.isGerman),
                              message: DiscoverIssueCopy.emptyMessage(browseOffered: offersBrowseEntry,
                                                                      german: KuroLocale.isGerman)) {
                    KuroInkButton(KuroBrandedCopy.retryTitle(german: KuroLocale.isGerman), role: .secondary, haptic: false) {
                        Task { await refreshSections(force: true) }
                    }
                    .frame(maxWidth: 280)
                }
                if offersBrowseEntry {
                    DiscoverLinkRow(kicker: DiscoverIssueCopy.browseKicker(german: KuroLocale.isGerman),
                                    title: DiscoverIssueCopy.browseTitle(german: KuroLocale.isGerman),
                                    action: { routes.openBrowse() })
                        .padding(.horizontal, gutter)
                }
            }
            .frame(minHeight: minHeight * 0.8)
        case .offline(hasContent: true), .failed(hasContent: true), nil:
            issue(gutter: gutter, column: column, proxy: proxy)
        }
    }

    /// The issue: opening blocks, sections, fold, footer.
    private func issue(gutter: CGFloat, column: CGFloat, proxy: ScrollViewProxy) -> some View {
        let german = KuroLocale.isGerman
        let compact = DiscoverIssueLayout.isCompact(column: column)
        let lead = leadStory
        let main = mainSections
        let folded = foldSections
        return VStack(alignment: .leading, spacing: 0) {
            Group {
                if !networkMonitor.isConnected {
                    DiscoverOfflineBand(retry: { Task { await refreshSections(force: true) } })
                        .padding(.bottom, DiscoverIssueLayout.top)
                }

                HomeOpeningLineView(kicker: DiscoverIssueCopy.openingKicker(now: Date(), german: german),
                                    headline: DiscoverIssueCopy.openingHeadline(german: german),
                                    compact: compact)

                DiscoverIssueSwitch(selection: issueBinding, column: column, artRaw: lead?.artRaw)
                    .padding(.top, DiscoverIssueLayout.openingToSwitch)

                if let lead {
                    DiscoverCoverStory(story: lead, kind: .lead, column: column)
                        .padding(.top, DiscoverIssueLayout.openingStack)
                } else if showsLeadSkeleton {
                    DiscoverStorySkeleton(column: column)
                        .padding(.top, DiscoverIssueLayout.openingStack)
                }

                if showsAnime, !vm.airingToday.isEmpty {
                    airingGlance(compact: compact)
                        .padding(.top, DiscoverIssueLayout.openingStack)
                }

                let line = DiscoverContents.line(page: main.compactMap(contentsEntry), folded: folded.count)
                if line != nil || offersBrowseEntry {
                    DiscoverContentsLine(
                        line: line,
                        browseOffered: offersBrowseEntry,
                        onJump: { scroll(to: $0, proxy: proxy) },
                        onMore: { target in
                            if target == DiscoverContents.foldAnchor, !folded.isEmpty, !showMoreSections.wrappedValue {
                                withTransaction(KuroFold.transaction(reduceMotion: reduceMotion)) {
                                    showMoreSections.wrappedValue = true
                                }
                            }
                            scroll(to: target, proxy: proxy)
                        },
                        onBrowse: { routes.openBrowse() }
                    )
                    .padding(.top, DiscoverIssueLayout.openingStack)
                }
            }
            .padding(.horizontal, gutter)

            ForEach(Array(main.enumerated()), id: \.element) { index, section in
                mainSection(section, gutter: gutter, column: column)
                    .padding(.top, index == 0 ? DiscoverIssueLayout.firstSection : DiscoverIssueLayout.section)
            }

            if !folded.isEmpty {
                DiscoverFoldButton(isExpanded: showMoreSections, count: folded.count,
                                   names: folded.map { $0.title(german: german) })
                    .id(DiscoverContents.foldAnchor)
                    .padding(.horizontal, gutter)
                    .padding(.top, DiscoverIssueLayout.fold)
                if showMoreSections.wrappedValue {
                    ForEach(folded) { route in
                        foldSection(route, column: column)
                            .padding(.horizontal, gutter)
                            .padding(.top, DiscoverIssueLayout.section)
                    }
                }
            }

            HomeFooter()
                .padding(.horizontal, gutter)
        }
        .padding(.top, DiscoverIssueLayout.top)
    }

    // MARK: Lead

    /// The lead: today's pick for this issue, else (once it has resolved) the season / trending lead on
    /// All and Anime, or the first essential (or trending) manga on Manga, exactly as before.
    private var leadSource: DiscoverIssueSections.Lead {
        DiscoverIssueSections.lead(issue: selectedMediaType, dailyFeatureKind: vm.dailyFeature?.kind,
                                   dailyFeatureResolved: vm.dailyFeatureResolved, hasFeatured: vm.featured != nil,
                                   hasEssentialsManga: !vm.essentialsManga.isEmpty,
                                   hasTrendingManga: !vm.trendingManga.isEmpty)
    }

    private var leadStory: DiscoverStory? {
        switch leadSource {
        case .dailyFeature:
            guard let feature = vm.dailyFeature else { return nil }
            return DiscoverStory(feature: feature, eyebrow: DiscoverOneThingCard.defaultEyebrow)
        case .season:
            guard let featured = vm.featured else { return nil }
            return DiscoverStory(card: TasteCard(anime: featured),
                                 eyebrow: vm.currentSeason.isEmpty
                                    ? KuroLocale.text("Trending now", "Gerade beliebt")
                                    : KuroLocale.text("This season", "Diese Season"))
        case .manga:
            guard let manga = vm.essentialsManga.first ?? vm.trendingManga.first else { return nil }
            return DiscoverStory(card: TasteCard(manga: manga),
                                 eyebrow: vm.essentialsManga.isEmpty
                                    ? KuroLocale.text("Trending now", "Gerade beliebt")
                                    : KuroLocale.text("Essential reading", "Lesenswert"))
        case .skeleton, .none:
            return nil
        }
    }

    /// Today's pick is still resolving (not on Manga, where the lead never waits for it).
    private var showsLeadSkeleton: Bool { leadSource == .skeleton }

    // MARK: Airing today

    private func airingGlance(compact: Bool) -> some View {
        let now = Date()
        let ordered = DiscoverAiringOrder.ordered(vm.airingToday, id: \.id, slots: airingSlots, now: now)
        let today = todaysSlots(for: ordered)
        let german = KuroLocale.isGerman
        return DiscoverGlanceCard(
            title: DiscoverIssueCopy.glanceTitle(german: german),
            caption: DiscoverIssueCopy.glanceCaption(
                ordered.map { DiscoverIssueCopy.AiringEntry(title: $0.title, slot: today[$0.id]) },
                now: now, german: german),
            thumbs: ordered.prefix(3).map { URL(string: $0.imageURL ?? "") },
            count: ordered.count,
            countLabel: DiscoverIssueCopy.glanceCountLabel(german: german),
            compact: compact,
            action: { openSeeAll(.animeAiringToday) }
        )
    }

    // MARK: Sections

    /// The sections drawn on this issue, in the curated order (the contents line and the page read the
    /// same list, so they never disagree). The selection and its flag gates are `DiscoverIssueSections`.
    typealias PageSection = DiscoverIssueSections.Section

    private var sectionInputs: DiscoverIssueSections.Inputs {
        DiscoverIssueSections.Inputs(
            issue: selectedMediaType, realmRails: flags.discoverRealmRailsV1Enabled,
            newToYou: !vm.newToYou.isEmpty, becauseYou: !vm.becauseYou.isEmpty, tonightShelf: !vm.tonightShelf.isEmpty,
            essentials: !vm.essentials.isEmpty, hiddenGemKind: vm.hiddenGem?.kind, mangaNewToYou: !vm.newToYouManga.isEmpty,
            trending: !vm.trending.isEmpty, essentialsManga: !vm.essentialsManga.isEmpty,
            classics: !vm.classics.isEmpty, currentSeason: !vm.currentSeason.isEmpty, topRated: !vm.topRated.isEmpty,
            newlyAdded: !vm.newlyAdded.isEmpty, classicsManga: !vm.classicsManga.isEmpty,
            trendingManga: !vm.trendingManga.isEmpty, topRatedManga: !vm.topRatedManga.isEmpty,
            newlyAddedManga: !vm.newlyAddedManga.isEmpty)
    }

    private var mainSections: [PageSection] { DiscoverIssueSections.main(sectionInputs) }

    /// The folded sections, in their curated order.
    private var foldSections: [EditorialDiscoverRoute] { DiscoverIssueSections.fold(sectionInputs) }

    /// Index rows before "See all": three on All, five on Anime and Manga.
    private var indexRowLimit: Int { DiscoverIssueLayout.indexRows(onAll: selectedMediaType == .all) }

    private var tonightShelfName: String {
        vm.tonightShelfTitle ?? KuroLocale.text("Tonight's shelf", "Das Regal für heute Abend")
    }

    private static let tonightShelfAnchor = "discover.tonightShelf"
    private static let hiddenGemAnchor = "discover.hiddenGem"

    /// The section's contents entry (the Hidden gem is one title, not a section with a count).
    private func contentsEntry(_ section: PageSection) -> DiscoverContents.Entry? {
        switch section {
        case .newToYou: return entry(.animeNewToYou, count: vm.newToYou.count)
        case .becauseYou: return entry(.animeBecauseYou, count: vm.becauseYou.count)
        case .tonightShelf:
            return DiscoverContents.Entry(id: Self.tonightShelfAnchor, name: tonightShelfName, count: vm.tonightShelf.count)
        case .essentials: return entry(.animeEssentials, count: vm.essentials.count)
        case .hiddenGem: return nil
        case .mangaNewToYou: return entry(.mangaNewToYou, count: vm.newToYouManga.count)
        case .trending: return entry(.animeTrending, count: vm.trending.count)
        case .essentialsManga: return entry(.mangaEssentials, count: vm.essentialsManga.count)
        }
    }

    private func entry(_ route: EditorialDiscoverRoute, count: Int) -> DiscoverContents.Entry {
        DiscoverContents.Entry(id: anchor(route), name: sectionName(route), count: count)
    }

    private func anchor(_ route: EditorialDiscoverRoute) -> String { "discover.\(route.id)" }

    private func sectionName(_ route: EditorialDiscoverRoute) -> String {
        route.title(german: KuroLocale.isGerman, reason: route == .animeBecauseYou ? vm.becauseYouReason : nil)
    }

    @ViewBuilder
    private func mainSection(_ section: PageSection, gutter: CGFloat, column: CGFloat) -> some View {
        let german = KuroLocale.isGerman
        switch section {
        case .newToYou:
            DiscoverFeatureTrio(anchor: anchor(.animeNewToYou), title: headline(.animeNewToYou),
                                summary: DiscoverIssueCopy.newToYouSummary(german: german),
                                cards: vm.newToYou.map { TasteCard(anime: $0) }, column: column,
                                onSeeAll: { openSeeAll(.animeNewToYou) })
                .padding(.horizontal, gutter)
        case .becauseYou:
            DiscoverFeatureTrio(anchor: anchor(.animeBecauseYou), title: headline(.animeBecauseYou),
                                summary: DiscoverIssueCopy.becauseYouSummary(german: german),
                                cards: vm.becauseYou.map { TasteCard(media: $0) }, column: column,
                                onSeeAll: { openSeeAll(.animeBecauseYou) })
                .padding(.horizontal, gutter)
        case .tonightShelf:
            DiscoverIssueRail(anchor: Self.tonightShelfAnchor, title: DiscoverIssueCopy.heading(tonightShelfName),
                              summary: nil, cards: vm.tonightShelf.map { TasteCard(media: $0) },
                              column: column, gutter: gutter)
        case .essentials:
            DiscoverIndexSection(anchor: anchor(.animeEssentials), title: headline(.animeEssentials),
                                 summary: DiscoverIssueCopy.canonSummary(german: german),
                                 cards: vm.essentials.map { TasteCard(anime: $0) }, column: column,
                                 rowLimit: indexRowLimit,
                                 onSeeAll: { openSeeAll(.animeEssentials) })
                .padding(.horizontal, gutter)
        case .hiddenGem:
            if let gem = vm.hiddenGem {
                DiscoverCoverStory(story: DiscoverStory(feature: gem, eyebrow: DiscoverIssueCopy.hiddenGem(german: german)),
                                   kind: .gem, column: column)
                    .id(Self.hiddenGemAnchor)
                    .padding(.horizontal, gutter)
            }
        case .mangaNewToYou:
            DiscoverFeatureTrio(anchor: anchor(.mangaNewToYou), title: headline(.mangaNewToYou),
                                summary: DiscoverIssueCopy.newToYouSummary(german: german),
                                cards: vm.newToYouManga.map { TasteCard(manga: $0) }, column: column,
                                onSeeAll: { openSeeAll(.mangaNewToYou) })
                .padding(.horizontal, gutter)
        case .trending:
            DiscoverIssueRail(anchor: anchor(.animeTrending), title: headline(.animeTrending),
                              summary: DiscoverIssueCopy.trendingSummary(german: german),
                              cards: vm.trending.map { TasteCard(anime: $0) }, column: column, gutter: gutter,
                              refines: true, onSeeAll: { openSeeAll(.animeTrending) })
        case .essentialsManga:
            DiscoverIndexSection(anchor: anchor(.mangaEssentials), title: headline(.mangaEssentials),
                                 summary: DiscoverIssueCopy.canonSummary(german: german),
                                 cards: vm.essentialsManga.map { TasteCard(manga: $0) }, column: column,
                                 rowLimit: indexRowLimit,
                                 onSeeAll: { openSeeAll(.mangaEssentials) })
                .padding(.horizontal, gutter)
        }
    }

    /// A folded section, in index grammar (Top rated keeps its local refinement).
    private func foldSection(_ route: EditorialDiscoverRoute, column: CGFloat) -> some View {
        DiscoverIndexSection(anchor: anchor(route), title: headline(route), summary: nil,
                             cards: foldCards(route), column: column,
                             refinement: route == .animeTopRated ? $topRatedFilter : nil,
                             rowLimit: indexRowLimit,
                             onSeeAll: { openSeeAll(route) })
    }

    private func foldCards(_ route: EditorialDiscoverRoute) -> [TasteCard] {
        switch route {
        case .animeClassics: return vm.classics.map { TasteCard(anime: $0) }
        case .animeCurrentSeason: return vm.currentSeason.map { TasteCard(anime: $0) }
        case .animeTopRated: return vm.topRated.map { TasteCard(anime: $0) }
        case .animeNewlyAdded: return vm.newlyAdded.map { TasteCard(anime: $0) }
        case .mangaClassics: return vm.classicsManga.map { TasteCard(manga: $0) }
        case .mangaTrending: return vm.trendingManga.map { TasteCard(manga: $0) }
        case .mangaTopRated: return vm.topRatedManga.map { TasteCard(manga: $0) }
        case .mangaNewlyAdded: return vm.newlyAddedManga.map { TasteCard(manga: $0) }
        default: return []
        }
    }

    /// Scrolls a contents entry's section to the top (settle; instant under Reduce Motion).
    private func scroll(to id: String, proxy: ScrollViewProxy) {
        let animation = KuroMotion.playsMotionNow(reduceMotion: reduceMotion) ? KuroMotion.settle : nil
        Task { @MainActor in
            // One turn so a section the fold just opened is laid out first.
            await Task.yield()
            withAnimation(animation) { proxy.scrollTo(id, anchor: .top) }
        }
    }

    /// A section heading with the editorial full stop.
    private func headline(_ route: EditorialDiscoverRoute) -> String {
        route.title(german: KuroLocale.isGerman, reason: route == .animeBecauseYou ? vm.becauseYouReason : nil) + "."
    }

    /// The rail's slots that lie on today's rail day (a rolled-forward time is not shown).
    private func todaysSlots(for items: [AnimeCard]) -> [Int: DiscoverAiringSlot] {
        let now = Date()
        let slots = airingSlots
        var today: [Int: DiscoverAiringSlot] = [:]
        for item in items {
            if let slot = DiscoverAiringOrder.todaysSlot(slots[item.id], now: now) {
                today[item.id] = slot
            }
        }
        return today
    }

    // MARK: See all

    /// "See all" opens the section as a journey (navigation contract §1): its frames push their title,
    /// ✕ / swipe-down collapses back to Discover. The rail's items are the ones on screen at the tap.
    private func openSeeAll(_ route: EditorialDiscoverRoute) {
        let title = route.title(german: KuroLocale.isGerman, reason: route == .animeBecauseYou ? vm.becauseYouReason : nil)
        let page = fullSection(for: route)
        routes.openPage(.seeAll(AnyJourneyPage(id: DiscoverSeeAllPolicy.pageID(route), title: title) { page }))
    }

    @ViewBuilder
    private func fullSection(for route: EditorialDiscoverRoute) -> some View {
        let title = route.title(german: KuroLocale.isGerman, reason: route == .animeBecauseYou ? vm.becauseYouReason : nil)
        switch route {
        case .animeEssentials:
            FullSectionView(title: title, items: vm.essentials)
        case .animeClassics:
            FullSectionView(title: title, items: vm.classics)
        case .animeNewToYou:
            FullSectionView(title: title, items: vm.newToYou)
        case .animeBecauseYou:
            FullSectionView(title: title, items: vm.becauseYou)
        case .animeAiringToday:
            let ordered = DiscoverAiringOrder.ordered(vm.airingToday, id: \.id, slots: airingSlots, now: Date())
            FullSectionView(title: title, items: ordered, airingSlots: todaysSlots(for: ordered))
        case .animeCurrentSeason:
            FullSectionView(title: title, items: vm.currentSeason)
        case .animeTrending:
            FullSectionView(title: title, items: vm.trending)
        case .animeTopRated:
            FullSectionView(title: title, items: vm.topRated)
        case .animeNewlyAdded:
            FullSectionView(title: title, items: vm.newlyAdded)
        case .mangaEssentials:
            FullMangaSectionView(title: title, items: vm.essentialsManga)
        case .mangaClassics:
            FullMangaSectionView(title: title, items: vm.classicsManga)
        case .mangaNewToYou:
            FullMangaSectionView(title: title, items: vm.newToYouManga)
        case .mangaTrending:
            FullMangaSectionView(title: title, items: vm.trendingManga)
        case .mangaTopRated:
            FullMangaSectionView(title: title, items: vm.topRatedManga)
        case .mangaNewlyAdded:
            FullMangaSectionView(title: title, items: vm.newlyAddedManga)
        }
    }

    // MARK: Loading

    /// Loads the page. `force == false` (first appearance, reconnect) reuses the launch bundle;
    /// `force == true` (pull to refresh, Try again) asks for a fresh one.
    private func refreshSections(force: Bool) async {
        let perf = KuroPerf.begin("discover.refresh")
        guard !isLoadingSections else {
            KuroPerf.end(perf, message: "skipped (already loading)")
            return
        }
        isLoadingSections = true
        defer { isLoadingSections = false }

        let hadContentBefore = hasAnyContent

        // List state for badges/progress comes from the Library projection (session refresh +
        // realtime hints); only the server bundle is fetched here.
        async let dailyFeatureResult = discovery.fetchDailyFeature()
        let bundle = force
            ? await discovery.fetchDiscoverBundle(limit: 30, hours: 24, force: true)
            : await discovery.ensureDiscoverBundle(limit: 30, hours: 24)

        let gotAnyNew = bundle.map { b in
            !(b.anime.essentials.isEmpty && b.anime.classics.isEmpty && b.anime.newToYou.isEmpty &&
              b.anime.trending.isEmpty && b.anime.topRated.isEmpty && b.anime.newlyAdded.isEmpty &&
              b.anime.airingToday.isEmpty && b.anime.currentSeason.isEmpty &&
              b.manga.essentials.isEmpty && b.manga.classics.isEmpty && b.manga.newToYou.isEmpty &&
              b.manga.trending.isEmpty && b.manga.topRated.isEmpty && b.manga.newlyAdded.isEmpty)
        } ?? false

        if let bundle {
            loadError = false
            vm.essentials = bundle.anime.essentials
            vm.classics = bundle.anime.classics
            vm.newToYou = bundle.anime.newToYou
            vm.trending = bundle.anime.trending
            vm.topRated = bundle.anime.topRated
            vm.newlyAdded = bundle.anime.newlyAdded
            vm.airingToday = bundle.anime.airingToday
            vm.currentSeason = bundle.anime.currentSeason

            vm.essentialsManga = bundle.manga.essentials
            vm.classicsManga = bundle.manga.classics
            vm.newToYouManga = bundle.manga.newToYou
            vm.trendingManga = bundle.manga.trending
            vm.topRatedManga = bundle.manga.topRated
            vm.newlyAddedManga = bundle.manga.newlyAdded

            // Lead fallback: best available from the current season, else trending.
            let featuredCandidates = vm.currentSeason.isEmpty ? vm.trending : vm.currentSeason
            vm.featured = featuredCandidates
                .filter { ($0.averageScore ?? 0) > 80 }
                .sorted { ($0.averageScore ?? 0) > ($1.averageScore ?? 0) }
                .first ?? featuredCandidates.first

            if hadContentBefore && !gotAnyNew {
                showBanner(KuroLocale.text("Couldn't refresh. Try again.", "Konnte nicht aktualisiert werden. Versuch es noch einmal."))
            }
        } else if hadContentBefore {
            showBanner(KuroLocale.text("Couldn't refresh. Try again.", "Konnte nicht aktualisiert werden. Versuch es noch einmal."))
        } else {
            loadError = true
        }

        // Stated air times of today's rail (the bundle rows carry none).
        if let airingIds = bundle?.anime.airingToday.map(\.id), !airingIds.isEmpty {
            await discovery.loadAiringSlots(for: airingIds)
        }

        // The One Thing: resolve alongside the bundle; nil -> the lead fallback.
        vm.dailyFeature = await dailyFeatureResult
        vm.dailyFeatureResolved = true

        // Discover P1, flag-gated: Because-You replaces NEW TO YOU when the taste rail clears the
        // evidence floor (>= 4 cards). Otherwise the personalized NTY swap runs, failing that the
        // bundle rail.
        if flags.personalizedNewToYouV1Enabled {
            var becauseApplied = false
            if let rail = await discovery.fetchBecauseYouRail(limit: 12), rail.count >= 4 {
                vm.becauseYou = rail.map { $0.toMedia() }
                vm.becauseYouReason = rail.first?.reasonTitle
                becauseApplied = true
            }
            if !becauseApplied {
                vm.becauseYou = []
                vm.becauseYouReason = nil
                // Personalized NEW TO YOU (flag-gated): swap the rail's data source.
                // Any error or empty result quietly keeps the bundle rail.
                if let personalized = await taste.fetchPersonalizedNewToYou(limit: 20, mediaType: "ANIME"),
                   !personalized.isEmpty {
                    vm.newToYou = personalized.map { $0.toAnimeCard() }
                }
            }
        } else {
            vm.becauseYou = []
            vm.becauseYouReason = nil
        }

        // Stage 4 — The Shelf + Hidden Gem (flag-gated, independent of P1).
        if flags.discoverRealmRailsV1Enabled {
            async let shelfResult = discovery.fetchTonightShelf(limit: 12)
            async let gemResult = discovery.fetchRealmHiddenGem()
            let shelf = await shelfResult
            let gem = await gemResult
            if let shelf, !shelf.isEmpty {
                vm.tonightShelf = shelf.map { $0.toMedia() }
                vm.tonightShelfTitle = shelf.first?.displayName.map {
                    KuroLocale.text("Tonight's shelf: \($0)", "Das Regal für heute Abend: \($0)")
                }
                vm.tonightShelfSubtitle = shelf.first?.blurb
            } else {
                vm.tonightShelf = []
                vm.tonightShelfTitle = nil
                vm.tonightShelfSubtitle = nil
            }
            vm.hiddenGem = gem?.toDailyFeature()
        } else {
            vm.tonightShelf = []
            vm.tonightShelfTitle = nil
            vm.tonightShelfSubtitle = nil
            vm.hiddenGem = nil
        }

        KuroPerf.end(perf, message: gotAnyNew ? "ok" : "no new data")

        // Friend tracking counts for the frames' one line.
        if flags.isSocialActivityV1Enabled {
            let anime = (vm.essentials + vm.trending + vm.topRated + vm.newToYou + vm.newlyAdded + vm.currentSeason)
                .map { (mediaType: "ANIME", mediaId: $0.id) }
            let manga = (vm.essentialsManga + vm.trendingManga + vm.topRatedManga + vm.newToYouManga + vm.newlyAddedManga)
                .map { (mediaType: "MANGA", mediaId: $0.id) }
            let items = Array((anime + manga).prefix(100))
            if !items.isEmpty {
                social.prefetchFriendCounts(items: items)
            }
        }

        var ladderCandidates: [(mediaType: String, mediaId: Int)] = []
        if let featured = vm.featured {
            ladderCandidates.append((mediaType: "ANIME", mediaId: featured.id))
        }
        ladderCandidates += Array(vm.currentSeason.prefix(4)).map { ("ANIME", $0.id) }
        ladderCandidates += Array(vm.trending.prefix(4)).map { ("ANIME", $0.id) }
        ladderCandidates += Array(vm.essentialsManga.prefix(4)).map { ("MANGA", $0.id) }
        if !ladderCandidates.isEmpty {
            catalog.prefetchMediaRelationRefreshRequests(
                items: ladderCandidates,
                reason: "discover_primary"
            )
        }

        // Prefetch covers at the frames' decode size so the next scroll feels instant.
        let anime = (vm.essentials.prefix(14) + vm.newToYou.prefix(14) + vm.trending.prefix(14) + vm.topRated.prefix(10))
            .compactMap { URL(string: $0.imageURL ?? "") }
        let manga = (vm.essentialsManga.prefix(14) + vm.newToYouManga.prefix(14) + vm.trendingManga.prefix(14) + vm.topRatedManga.prefix(10))
            .compactMap { URL(string: $0.imageURL ?? "") }
        let urls = Array((anime + manga).prefix(70))
        if !urls.isEmpty {
            Task { await ImagePipeline.shared.prefetch(urls: urls, maxPixelSize: 360) }
        }
    }

    private func showBanner(_ message: String) {
        bannerTask?.cancel()
        withAnimation(KuroMotion.resolve(KuroMotion.settle)) {
            bannerMessage = message
        }
        bannerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(KuroMotion.resolve(KuroMotion.settle)) {
                bannerMessage = nil
            }
        }
    }
}

// MARK: - See all

/// A Discover section in full: the loaded titles as an equal-frame grid with an in-place filter.
/// A journey page (`routes.openPage(.seeAll(...))`): its frames push their title inside the journey.
struct FullSectionView<Item: MediaDisplayable>: View {
    let title: String
    let items: [Item]
    var airingSlots: [Int: DiscoverAiringSlot] = [:]

    var body: some View {
        DiscoverFullSectionSheet(title: title, items: items, airingSlots: airingSlots)
    }
}

/// The manga "See all" page (same grammar as `FullSectionView`).
struct FullMangaSectionView<Item: MediaDisplayable>: View {
    let title: String
    let items: [Item]

    var body: some View {
        DiscoverFullSectionSheet(title: title, items: items)
    }
}

private struct DiscoverFullSectionSheet<Item: MediaDisplayable>: View {
    let title: String
    let items: [Item]
    var airingSlots: [Int: DiscoverAiringSlot] = [:]

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var searchText = ""
    /// The headline scrolls under the compact bar (H1).
    @State private var collapse: CGFloat = 0

    private var filtered: [Item] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { media in
            media.title.localizedCaseInsensitiveContains(query) ||
            media.displayDescription.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        // A journey's root page (opened from a Discover rail): ✕ only; the frames push their title.
        GeometryReader { geo in
            let width = DiscoverLayout.contentWidth(container: geo.size.width, regularWidth: horizontalSizeClass == .regular)
            let gutter = DiscoverLayout.gutter(for: width)
            let inner = max(0, width - gutter * 2)
            let columns = DiscoverLayout.columnCount(for: inner, accessibilitySize: dynamicTypeSize.isAccessibilitySize)
            let frameWidth = DiscoverLayout.gridFrameWidth(for: inner, columns: columns)
            let shown = filtered

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                    VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                        Text(title)
                            .kuroRoleText(.headline)
                            .foregroundStyle(Color.kuroInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(KuroLocale.text(
                            shown.count == 1 ? "1 title" : "\(shown.count) titles",
                            "\(shown.count) Titel"
                        ))
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroInkQuiet)
                    }

                    DiscoverFilterField(
                        text: $searchText,
                        prompt: KuroLocale.text("Filter these titles", "Diese Titel filtern")
                    )

                    if shown.isEmpty {
                        KuroStateView(
                            .empty,
                            title: KuroLocale.text("No titles match \u{201C}\(searchText)\u{201D}.",
                                                   "Keine Titel passen zu \u{201E}\(searchText)\u{201C}."),
                            layout: .inline
                        )
                    } else {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.fixed(frameWidth), spacing: DiscoverLayout.frameSpacing, alignment: .top), count: columns),
                            alignment: .leading,
                            spacing: KuroDesignSpacing.lg
                        ) {
                            ForEach(shown, id: \.id) { item in
                                DiscoverFrame(media: item, width: frameWidth, airing: airingSlots[item.id])
                            }
                        }
                    }
                }
                .padding(.horizontal, gutter)
                // Clears the ✕ key row; the headline then scrolls under the compact bar.
                .padding(.top, KuroJourneyChrome.barHeight)
                .padding(.bottom, KuroDesignSpacing.xl)
                .frame(width: width)
                .frame(maxWidth: .infinity)
            }
            .kuroCollapseTracking($collapse, start: 0, distance: KuroJourneyChrome.barHeight)
            // Home's warm paper, and Home's poster fill behind missing art (§6.3); nothing else changes.
            .background(Color.kuroCanvasHome)
            .environment(\.discoverMissingArt, HomeInk.posterFill)
        }
        .kuroJourneyChrome(title: title, collapseProgress: collapse)
    }
}

/// The "See all" journey pages' identity (pure, tested in NavshellTests): one page per rail, so a
/// second tap on the same rail's "See all" never stacks a copy (N5).
enum DiscoverSeeAllPolicy {
    static func pageID(_ route: EditorialDiscoverRoute) -> String { "discover:\(route.id)" }
}

/// A quiet filter field: magnifier, text, a labelled clear key, an ink hairline under it.
struct DiscoverFilterField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: KuroDesignSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.kuroBody(weight: .regular))
                .foregroundStyle(Color.kuroInkQuiet)
                .accessibilityHidden(true)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Color.kuroInkQuiet))
                .font(.kuroBody(weight: .regular))
                .foregroundStyle(Color.kuroInk)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.kuroMeta(weight: .medium))
                        .foregroundStyle(Color.kuroInkQuiet)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(KuroLocale.text("Clear", "Leeren"))
            }
        }
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.kuroHairline)
                .frame(height: 1)
        }
    }
}

// MARK: - Genre Picker Sheet (unreferenced; kept for the owner's dead-code pass)
struct GenrePickerSheet: View {
    let genres: [String]
    let onSelect: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    FilterChip(
                        title: KuroLocale.text("Cancel", "Abbrechen"),
                        isSelected: false,
                        action: {
                            onSelect(nil)
                            dismiss()
                        }
                    )

                    ForEach(genres, id: \.self) { genre in
                        FilterChip(
                            title: genre,
                            isSelected: false,
                            action: {
                                onSelect(genre)
                                dismiss()
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .navigationTitle(KuroLocale.text("Genres", "Genres"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(KuroLocale.text("Done", "Fertig")) { dismiss() }
                        .foregroundStyle(Color.kuroInk)
                }
            }
        }
    }
}

#Preview {
    EditorialDiscoverView()
        .environment(AppComposition.shared.identity)
        .environment(AppComposition.shared.library)
        .environment(AppComposition.shared.catalog)
        .environment(AppComposition.shared.discovery)
        .environment(AppComposition.shared.releases)
        .environment(AppComposition.shared.social)
        .environment(AppComposition.shared.availability)
        .environment(AppComposition.shared.clubs)
        .environment(AppComposition.shared.taste)
        .environment(AppComposition.shared.flags)
        .environment(AppComposition.shared.libraryActions)
        .environment(NetworkMonitor())
}

// MARK: - Branded state (prototype-fidelity Task 9)

/// What the Discover page draws instead of its sections. Pure. The order is the page's own: content
/// always wins (with the offline band when the connection is gone), then a first load in flight, then
/// a failed first load (offline when the connection is gone), then the empty invitation.
nonisolated enum DiscoverPageRules {
    static func brandedState(isLoading: Bool, hasContent: Bool, failed: Bool, isConnected: Bool) -> KuroBrandedState? {
        if hasContent { return isConnected ? nil : .offline(hasContent: true) }
        if isLoading { return .loading }
        if failed { return isConnected ? .failed(hasContent: false) : .offline(hasContent: false) }
        return .empty
    }
}

// MARK: - Issue sections (pure)

/// Which lead and sections the Discover issue draws, in the curated order and behind the page's flag
/// gates (pure; DCdiscoverTests pins All / Anime / Manga with the flags on and off).
enum DiscoverIssueSections {
    typealias Issue = EditorialDiscoverView.DiscoverMediaTypeFilter

    enum Section: Hashable {
        case newToYou, becauseYou, tonightShelf, essentials, hiddenGem, mangaNewToYou, trending, essentialsManga
    }

    /// Where the lead story comes from.
    enum Lead: Equatable {
        /// Today's pick (it matches the issue).
        case dailyFeature
        /// Today's pick is still resolving (never on Manga).
        case skeleton
        /// The season / trending lead (All and Anime).
        case season
        /// The first essential (else trending) manga (Manga).
        case manga
        case none
    }

    /// Which rails hold content (and the Hidden gem's medium), as the page read them.
    struct Inputs {
        var issue: Issue
        var realmRails: Bool
        var newToYou = false, becauseYou = false, tonightShelf = false, essentials = false
        var hiddenGemKind: MediaKind? = nil
        var mangaNewToYou = false, trending = false, essentialsManga = false
        var classics = false, currentSeason = false, topRated = false, newlyAdded = false
        var classicsManga = false, trendingManga = false, topRatedManga = false, newlyAddedManga = false
    }

    static func showsAnime(_ issue: Issue) -> Bool { issue != .manga }
    static func showsManga(_ issue: Issue) -> Bool { issue != .anime }

    static func matches(_ issue: Issue, kind: MediaKind) -> Bool {
        issue == .all || (issue == .anime && kind == .anime) || (issue == .manga && kind == .manga)
    }

    static func lead(issue: Issue, dailyFeatureKind: MediaKind?, dailyFeatureResolved: Bool, hasFeatured: Bool,
                     hasEssentialsManga: Bool, hasTrendingManga: Bool) -> Lead {
        if let kind = dailyFeatureKind, matches(issue, kind: kind) { return .dailyFeature }
        if !dailyFeatureResolved && issue != .manga { return .skeleton }
        if hasFeatured, showsAnime(issue) { return .season }
        if issue == .manga, hasEssentialsManga || hasTrendingManga { return .manga }
        return .none
    }

    static func main(_ input: Inputs) -> [Section] {
        let anime = showsAnime(input.issue)
        var sections: [Section] = []
        if input.issue == .manga {
            // Manga new to you takes New to you's place on the Manga issue (§6.1 row 6).
            if input.mangaNewToYou { sections.append(.mangaNewToYou) }
        } else if input.becauseYou && input.issue == .all {
            // Because-You replaces NEW TO YOU when the taste rail has enough signal (mixed anime +
            // manga feed: All only).
            sections.append(.becauseYou)
        } else if anime, input.newToYou {
            sections.append(.newToYou)
        }
        // Stage 4: The Shelf (tonight's realm), flag-gated.
        if input.realmRails, anime, input.tonightShelf { sections.append(.tonightShelf) }
        if anime, input.essentials { sections.append(.essentials) }
        // Stage 4: Hidden Gem (the cover-story grammar), flag-gated.
        if input.realmRails, let kind = input.hiddenGemKind, matches(input.issue, kind: kind) { sections.append(.hiddenGem) }
        if input.issue == .all, input.mangaNewToYou { sections.append(.mangaNewToYou) }
        if anime, input.trending { sections.append(.trending) }
        if showsManga(input.issue), input.essentialsManga { sections.append(.essentialsManga) }
        return sections
    }

    static func fold(_ input: Inputs) -> [EditorialDiscoverRoute] {
        var routes: [EditorialDiscoverRoute] = []
        if showsAnime(input.issue) {
            if input.classics { routes.append(.animeClassics) }
            if input.currentSeason { routes.append(.animeCurrentSeason) }
            if input.topRated { routes.append(.animeTopRated) }
            if input.newlyAdded { routes.append(.animeNewlyAdded) }
        }
        if showsManga(input.issue) {
            if input.classicsManga { routes.append(.mangaClassics) }
            if input.trendingManga { routes.append(.mangaTrending) }
            if input.topRatedManga { routes.append(.mangaTopRated) }
            if input.newlyAddedManga { routes.append(.mangaNewlyAdded) }
        }
        return routes
    }
}
