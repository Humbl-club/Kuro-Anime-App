// Discover (spec D8, D2; rulebook §14.5)
// Issue-style frames on the white page: one lead frame (today's pick), then rails and equal-frame
// grids of picture, title and one line. Section heads are serif, sentence case, EN/DE. The page
// reads the `discover_bundle` once per launch (`DiscoveryStore.ensureDiscoverBundle`); only pull to
// refresh asks for a fresh one. "Airing today" is ordered by the stated air time where the
// catalogue states one (never estimated). States: stable skeleton on first paint, then
// `KuroStateView` for offline, failed and empty.

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
    @State private var vm = DiscoverViewModel()
    @State private var isLoadingSections = false
    @State private var didInitialLoad = false
    @State private var bannerMessage: String? = nil
    @State private var bannerTask: Task<Void, Never>? = nil
    @State private var loadError = false


    @State private var showMoreSections = UserDefaults.standard.bool(forKey: "kuro_discover_show_more")
    @State private var selectedMediaType: DiscoverMediaTypeFilter = .all

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

    private var showsAnime: Bool { selectedMediaType != .manga }
    private var showsManga: Bool { selectedMediaType != .anime }

    private var secondarySectionCount: Int {
        var count = 0
        if showsAnime {
            if !vm.classics.isEmpty { count += 1 }
            if !vm.currentSeason.isEmpty { count += 1 }
            if !vm.topRated.isEmpty { count += 1 }
            if !vm.newlyAdded.isEmpty { count += 1 }
        }
        if showsManga {
            if !vm.classicsManga.isEmpty { count += 1 }
            if !vm.trendingManga.isEmpty { count += 1 }
            if !vm.topRatedManga.isEmpty { count += 1 }
            if !vm.newlyAddedManga.isEmpty { count += 1 }
        }
        return count
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
            ScrollView(.vertical, showsIndicators: false) {
                content(width: width, minHeight: geo.size.height)
                    .frame(width: width)
                    .frame(maxWidth: .infinity)
            }
            // A parent `.scrollDisabled(true)` (e.g. on a paging container) can propagate via environment.
            // Keep Discover scrollable regardless.
            .scrollDisabled(false)
            .background(Color.kuroCanvasPage)
            .refreshable {
                // Pull-to-refresh is user-initiated: also re-read the Library projection
                // (badges/progress), next to the bundle. The first load relies on the session refresh.
                async let libraryRefresh: Void? = try? library.refresh()
                await refreshSections(force: true)
                _ = await libraryRefresh
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
    }

    // MARK: Page

    @ViewBuilder
    private func content(width: CGFloat, minHeight: CGFloat) -> some View {
        let gutter = DiscoverLayout.gutter(for: width)
        // One switch on the branded state (`DiscoverPageRules.brandedState`, tested in RestyleLaneTests).
        switch DiscoverPageRules.brandedState(isLoading: isLoadingSections, hasContent: hasAnyContent,
                                              failed: loadError, isConnected: networkMonitor.isConnected) {
        case .loading:
            DiscoverLoadingSkeleton(containerWidth: width)
        case .failed(hasContent: false):
            KuroErrorView(headline: KuroLocale.text("Couldn't load Discover.", "Entdecken konnte nicht geladen werden."),
                          retry: { Task { await refreshSections(force: true) } })
                .frame(minHeight: minHeight * 0.8)
        case .offline(hasContent: false):
            KuroOfflineView(hasContent: false, retry: { Task { await refreshSections(force: true) } })
                .frame(minHeight: minHeight * 0.8)
        case .empty:
            VStack(spacing: KuroDesignSpacing.lg) {
                KuroStateView(
                    .empty,
                    title: KuroLocale.text("Nothing to show yet.", "Noch nichts zu zeigen."),
                    message: KuroLocale.text("Pull to refresh, or browse the catalogue.",
                                             "Zieh zum Aktualisieren, oder durchstöbere den Katalog."),
                    retry: { Task { await refreshSections(force: true) } }
                )
                if offersBrowseEntry {
                    browseEntry
                        .padding(.horizontal, gutter)
                }
            }
            .frame(minHeight: minHeight * 0.8)
        case .offline(hasContent: true), .failed(hasContent: true), nil:
            sections(width: width, gutter: gutter)
        }
    }

    private func sections(width: CGFloat, gutter: CGFloat) -> some View {
        let leadWidth = max(0, width - gutter * 2)
        return VStack(alignment: .leading, spacing: KuroDesignSpacing.xl) {
            VStack(alignment: .leading, spacing: 0) {
                if !networkMonitor.isConnected {
                    // The branded offline band over earlier content.
                    KuroOfflineView(hasContent: true)
                        .padding(.horizontal, gutter)
                }

                DiscoverWordPicker(
                    options: DiscoverMediaTypeFilter.allCases.map { ($0, $0.title(german: KuroLocale.isGerman)) },
                    selection: $selectedMediaType,
                    accessibilityLabel: KuroLocale.text("Show", "Anzeigen")
                )
                .contentMargins(.horizontal, gutter, for: .scrollContent)
            }

            lead(width: leadWidth)
                .padding(.horizontal, gutter)

            if showsAnime, !vm.airingToday.isEmpty {
                let ordered = DiscoverAiringOrder.ordered(vm.airingToday, id: \.id, slots: airingSlots, now: Date())
                DiscoverRail(
                    title: headline(.animeAiringToday),
                    items: Array(ordered.prefix(10)),
                    containerWidth: width,
                    onSeeAll: { openSeeAll(.animeAiringToday) },
                    airingSlots: todaysSlots(for: ordered)
                )
            }

            // Because-You replaces NEW TO YOU when the taste rail has enough signal (mixed anime +
            // manga feed: All only).
            if !vm.becauseYou.isEmpty && selectedMediaType == .all {
                DiscoverGridSection(
                    title: headline(.animeBecauseYou),
                    items: Array(vm.becauseYou.prefix(8)),
                    containerWidth: width,
                    onSeeAll: { openSeeAll(.animeBecauseYou) }
                )
            } else if showsAnime, !vm.newToYou.isEmpty {
                DiscoverGridSection(
                    title: headline(.animeNewToYou),
                    items: Array(vm.newToYou.prefix(8)),
                    containerWidth: width,
                    onSeeAll: { openSeeAll(.animeNewToYou) }
                )
            }

            // Stage 4 — The Shelf (tonight's realm), flag-gated.
            if flags.discoverRealmRailsV1Enabled, showsAnime, !vm.tonightShelf.isEmpty {
                DiscoverRail(
                    title: (vm.tonightShelfTitle ?? KuroLocale.text("Tonight's shelf", "Das Regal für heute Abend")) + ".",
                    items: Array(vm.tonightShelf.prefix(10)),
                    containerWidth: width
                )
            }

            if showsAnime, !vm.essentials.isEmpty {
                DiscoverRail(
                    title: headline(.animeEssentials),
                    items: Array(vm.essentials.prefix(10)),
                    containerWidth: width,
                    onSeeAll: { openSeeAll(.animeEssentials) }
                )
            }

            // Stage 4 — Hidden Gem (the lead frame grammar).
            if flags.discoverRealmRailsV1Enabled,
               let gem = vm.hiddenGem,
               selectedMediaType == .all
                || (selectedMediaType == .anime && gem.kind == .anime)
                || (selectedMediaType == .manga && gem.kind == .manga) {
                DiscoverOneThingCard(
                    feature: gem,
                    width: leadWidth,
                    eyebrow: KuroLocale.text("Hidden gem", "Verborgenes Juwel")
                )
                .padding(.horizontal, gutter)
            }

            if showsManga, !vm.newToYouManga.isEmpty {
                DiscoverGridSection(
                    title: headline(.mangaNewToYou),
                    items: Array(vm.newToYouManga.prefix(8)),
                    containerWidth: width,
                    onSeeAll: { openSeeAll(.mangaNewToYou) }
                )
            }

            if showsAnime, !vm.trending.isEmpty {
                DiscoverRail(
                    title: headline(.animeTrending),
                    items: Array(vm.trending.prefix(20)),
                    containerWidth: width,
                    onSeeAll: { openSeeAll(.animeTrending) },
                    showsFilters: true
                )
            }

            if showsManga, !vm.essentialsManga.isEmpty {
                DiscoverRail(
                    title: headline(.mangaEssentials),
                    items: Array(vm.essentialsManga.prefix(10)),
                    containerWidth: width,
                    onSeeAll: { openSeeAll(.mangaEssentials) }
                )
            }

            if !showMoreSections && secondarySectionCount > 0 {
                KuroInkButton(
                    KuroLocale.text(
                        secondarySectionCount == 1 ? "1 more section" : "\(secondarySectionCount) more sections",
                        secondarySectionCount == 1 ? "1 weiterer Bereich" : "\(secondarySectionCount) weitere Bereiche"
                    ),
                    role: .secondary,
                    haptic: false
                ) {
                    withAnimation(KuroMotion.resolve(KuroMotion.contextChange)) {
                        showMoreSections = true
                    }
                    UserDefaults.standard.set(true, forKey: "kuro_discover_show_more")
                }
                .padding(.horizontal, gutter)
            }

            if showMoreSections {
                secondarySections(width: width)
            }

            if offersBrowseEntry {
                browseEntry
                    .padding(.horizontal, gutter)
            }
        }
        .padding(.top, KuroDesignSpacing.sm)
        .padding(.bottom, KuroDesignSpacing.xxl)
    }

    @ViewBuilder
    private func secondarySections(width: CGFloat) -> some View {
        if showsAnime, !vm.classics.isEmpty {
            DiscoverGridSection(
                title: headline(.animeClassics),
                items: Array(vm.classics.prefix(8)),
                containerWidth: width,
                onSeeAll: { openSeeAll(.animeClassics) }
            )
        }

        if showsAnime, !vm.currentSeason.isEmpty {
            DiscoverRail(
                title: headline(.animeCurrentSeason),
                items: Array(vm.currentSeason.prefix(10)),
                containerWidth: width,
                onSeeAll: { openSeeAll(.animeCurrentSeason) }
            )
        }

        if showsAnime, !vm.topRated.isEmpty {
            DiscoverGridSection(
                title: headline(.animeTopRated),
                items: Array(vm.topRated.prefix(8)),
                containerWidth: width,
                onSeeAll: { openSeeAll(.animeTopRated) },
                showsFilters: true
            )
        }

        if showsAnime, !vm.newlyAdded.isEmpty {
            DiscoverGridSection(
                title: headline(.animeNewlyAdded),
                items: Array(vm.newlyAdded.prefix(8)),
                containerWidth: width,
                onSeeAll: { openSeeAll(.animeNewlyAdded) }
            )
        }

        if showsManga, !vm.classicsManga.isEmpty {
            DiscoverGridSection(
                title: headline(.mangaClassics),
                items: Array(vm.classicsManga.prefix(8)),
                containerWidth: width,
                onSeeAll: { openSeeAll(.mangaClassics) }
            )
        }

        if showsManga, !vm.trendingManga.isEmpty {
            DiscoverRail(
                title: headline(.mangaTrending),
                items: Array(vm.trendingManga.prefix(10)),
                containerWidth: width,
                onSeeAll: { openSeeAll(.mangaTrending) }
            )
        }

        if showsManga, !vm.topRatedManga.isEmpty {
            DiscoverGridSection(
                title: headline(.mangaTopRated),
                items: Array(vm.topRatedManga.prefix(8)),
                containerWidth: width,
                onSeeAll: { openSeeAll(.mangaTopRated) }
            )
        }

        if showsManga, !vm.newlyAddedManga.isEmpty {
            DiscoverRail(
                title: headline(.mangaNewlyAdded),
                items: Array(vm.newlyAddedManga.prefix(10)),
                containerWidth: width,
                onSeeAll: { openSeeAll(.mangaNewlyAdded) }
            )
        }
    }

    /// The lead frame: today's pick, its skeleton while it resolves, or the season/trending lead.
    @ViewBuilder
    private func lead(width: CGFloat) -> some View {
        if let feature = vm.dailyFeature,
           selectedMediaType == .all
            || (selectedMediaType == .anime && feature.kind == .anime)
            || (selectedMediaType == .manga && feature.kind == .manga) {
            DiscoverOneThingCard(feature: feature, width: width)
        } else if !vm.dailyFeatureResolved && selectedMediaType != .manga {
            DiscoverOneThingSkeleton(width: width)
        } else if let featured = vm.featured, showsAnime {
            DiscoverLeadFrame(
                kicker: vm.currentSeason.isEmpty
                    ? KuroLocale.text("Trending now", "Gerade beliebt")
                    : KuroLocale.text("This season", "Diese Season"),
                title: featured.title,
                line: DiscoverFrameCopy.line(
                    kind: .anime,
                    year: featured.year,
                    episodes: featured.episodes,
                    chapters: nil,
                    statusRaw: featured.statusRaw,
                    formatRaw: featured.formatRaw,
                    german: KuroLocale.isGerman,
                    locale: KuroLocale.locale,
                    timeZone: KuroLocale.timeZone
                ),
                imageURL: URL(string: (featured.bannerImage?.isEmpty == false ? featured.bannerImage : featured.imageURL) ?? ""),
                isWideArt: featured.bannerImage?.isEmpty == false,
                route: MediaRoute(kind: .anime, id: featured.id),
                width: width
            )
        } else if selectedMediaType == .manga, let manga = vm.essentialsManga.first ?? vm.trendingManga.first {
            // The manga page leads with its first essential (or trending) title: a cover crop.
            DiscoverLeadFrame(
                kicker: vm.essentialsManga.isEmpty
                    ? KuroLocale.text("Trending now", "Gerade beliebt")
                    : KuroLocale.text("Essential reading", "Lesenswert"),
                title: manga.title,
                line: DiscoverFrameCopy.line(
                    kind: .manga,
                    year: manga.year,
                    episodes: nil,
                    chapters: manga.chapters,
                    statusRaw: manga.statusRaw,
                    formatRaw: manga.formatRaw,
                    german: KuroLocale.isGerman,
                    locale: KuroLocale.locale,
                    timeZone: KuroLocale.timeZone
                ),
                imageURL: URL(string: manga.imageURL ?? ""),
                isWideArt: false,
                route: MediaRoute(kind: .manga, id: manga.id),
                width: width
            )
        }
    }

    /// "Browse the catalogue": opens the catalogue as a journey (spec D2; navigation contract §1).
    private var browseEntry: some View {
        KuroInkButton(KuroLocale.text("Browse the catalogue", "Den Katalog durchstöbern"), role: .secondary) {
            routes.openBrowse()
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
            .background(Color.kuroCanvasPage)
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
