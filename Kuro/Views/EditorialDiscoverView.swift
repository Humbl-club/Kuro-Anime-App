// Discover (Discover + Clubs redesign §6, "Discover is an issue"; usability spec 2026-11-04, Rule 6)
// A daily issue in Home's grammar on Home's warm paper (`kuroCanvasHome`, the manga canvas on the
// Manga issue; the header paints the same canvas through `KuroMainView.Section.canvas`): the opening
// row, the three-word issue switch, the mood keys, one cover story with the Plan key, the contents
// (numbered jump links) with Browse, then at most six sections (R7, D7) in different forms, each with
// its one question under the heading (R1), then the end of the issue ("You're caught up for today."
// with Browse, Search and More lists) and Home's footer. The fold is retired (D17).
// The Discover contract (docs/superpowers/specs/2026-11-04-discover-usability-design.md):
//   R2 one build per visit (first load, pull to refresh, issue change, a new visit) claims titles
//      once across the page (`DiscoverIssueBuilder`: the lead, then Essentials, then page order),
//      one title per franchise; owned titles are hidden in personal sections, marked elsewhere.
//      Claims never move mid-visit: a hide removes the title and its section's reserve slides up.
//   R3 every card is one tap (open) plus its Plan key; the rest is the long-press menu, which is also
//      every card's VoiceOver actions (`discoverMenu(for:)`, the swap point for lane B).
//   R5 Not interested / Seen it leave the page at once (the data lane's `TasteStore` memory), teach
//      Taste ('skip' / 'known') and toast with Undo.
//   R8 the scroll position (held in `KuroMainView`) and the issue survive journeys; the pinned index
//      appears once the contents scroll under the header; the header title scrolls to the top.
// The page reads the `discover_bundle` once per launch (`DiscoveryStore.ensureDiscoverBundle`); only
// pull to refresh asks for a fresh one. Every source and flag gate is unchanged. States: the issue
// skeleton on first paint, then the branded offline, failed and empty states, and the quiet offline
// band over earlier content.

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
    @Environment(IdentityStore.self) private var identity
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(FeatureFlags.self) private var flags
    @Environment(InteractionTelemetry.self) private var telemetry: InteractionTelemetry?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.kuroRoutes) private var routes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.discoverVisitDefaults) private var visitDefaults
    @State private var vm = DiscoverViewModel()
    @State private var isLoadingSections = false
    @State private var didInitialLoad = false
    @State private var bannerMessage: String? = nil
    @State private var bannerTask: Task<Void, Never>? = nil
    @State private var loadError = false
    /// The page's Plan keys (plan / unplan with Undo; a tracked title opens the editor).
    @State private var plans = TastePlanController()
    /// The session tallies and the page's own events (opens, jumps, Plan results).
    @State private var feedback = DiscoverPageFeedback()
    /// Not interested / Seen it: the hide toast with Undo and "Add as Completed ›" (lane B, D12).
    @State private var hides = DiscoverFeedbackController()
    /// This visit's claims (R2, D5); rebuilt only at the build points, never mid-visit.
    @State private var build = DiscoverIssueBuild.empty
    @State private var hasBuilt = false
    /// Scroll geometry per section anchor (pinned index, "seen" for visit memory).
    @State private var sectionGeometry: [String: DiscoverSectionGeometry] = [:]
    @State private var contentsPassed = false
    @State private var reachedEnd = false
    @State private var maxDepth = 0
    @State private var visit = DiscoverVisitSession()
    /// The tallies already reported by `discover_visit_end` this visit (a resumed visit reports deltas).
    @State private var reportedTally = DiscoverVisitSession.Tally()
    /// "Like {title}": the seed's title for the issue's medium (nil: three mood keys).
    @State private var likeSeed: DiscoverLikeSeed? = nil
    @State private var localScroll = ScrollPosition(edge: .top)
    @State private var localIssue: DiscoverMediaTypeFilter = .all
    /// A pinned-index jump, handed to the scroll reader (the band sits above the scroll view, so the
    /// system's top scroll-edge effect never blurs it).
    @State private var pendingJump: String? = nil

    /// The issue and the scroll position live in `KuroMainView` (so the header canvas follows the issue
    /// and both survive journeys, R8); hosts without one (tests, previews) keep them here.
    private let externalIssue: Binding<DiscoverMediaTypeFilter>?
    private let externalScroll: Binding<ScrollPosition>?
    /// Discover is the pager's current page (visit boundaries, D18).
    private let isCurrent: Bool
    /// The header title's tap (scroll to top), counted by `KuroMainView`.
    private let scrollToTopTick: Int
    /// The header Search sheet, gated by the pager's tap guard in `KuroMainView`.
    private let onOpenSearch: (() -> Void)?

    init(issue: Binding<DiscoverMediaTypeFilter>? = nil, scrollPosition: Binding<ScrollPosition>? = nil,
         isCurrent: Bool = true, scrollToTopTick: Int = 0, onOpenSearch: (() -> Void)? = nil) {
        self.externalIssue = issue
        self.externalScroll = scrollPosition
        self.isCurrent = isCurrent
        self.scrollToTopTick = scrollToTopTick
        self.onOpenSearch = onOpenSearch
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
    private var scrollBinding: Binding<ScrollPosition> { externalScroll ?? $localScroll }

    private var showsAnime: Bool { selectedMediaType != .manga }

    /// The issue's medium for the mood keys and the mood journeys (All and Anime: anime).
    private var moodKind: MediaKind { selectedMediaType == .manga ? .manga : .anime }

    /// The page canvas, the same token `KuroMainView.Section.canvas` paints under the header (D2).
    private var canvas: Color { selectedMediaType == .manga ? Color.kuroCanvasHomeManga : Color.kuroCanvasHome }

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

    /// A visit runs while Discover is the current page and the app is active (D18).
    private var visitIsLive: Bool { isCurrent && scenePhase == .active }

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
                .scrollPosition(scrollBinding)
                // A parent `.scrollDisabled(true)` (e.g. on a paging container) can propagate via environment.
                // Keep Discover scrollable regardless.
                .scrollDisabled(false)
                .background(canvas)
                .animation(KuroMotion.playsMotionNow(reduceMotion: reduceMotion) ? KuroMotion.medium : nil, value: canvas)
                .onScrollGeometryChange(for: Int.self) { geometry in
                    DiscoverVisitSession.depthBucket(offset: geometry.contentOffset.y,
                                                     visible: geometry.containerSize.height,
                                                     content: geometry.contentSize.height)
                } action: { _, depth in
                    maxDepth = max(maxDepth, depth)
                }
                .refreshable {
                    // Pull-to-refresh is user-initiated: also re-read the Library projection
                    // (badges/progress), next to the bundle. The first load relies on the session refresh.
                    async let libraryRefresh: Void? = try? library.refresh()
                    await refreshSections(force: true)
                    _ = await libraryRefresh
                }
                .onChange(of: pendingJump) { _, target in
                    guard let target else { return }
                    pendingJump = nil
                    scroll(to: target, proxy: proxy)
                }
                .onChange(of: scrollToTopTick) { _, _ in
                    feedback.trackJump("header_top", target: "top")
                    let animation = KuroMotion.playsMotionNow(reduceMotion: reduceMotion) ? KuroMotion.settle : nil
                    withAnimation(animation) { scrollBinding.wrappedValue.scrollTo(edge: .top) }
                }
            }
            .overlay(alignment: .top) {
                pinnedIndex
            }
            .overlay(alignment: .top) {
                if let bannerMessage {
                    KuroTransientBanner(message: bannerMessage)
                        .padding(.top, 10)
                        .transition(.opacity)
                }
            }
            .task {
                feedback.telemetry = telemetry
                hides.onUndone = { [feedback] receipt in feedback.noteUndone(receipt) }
                // The device memory first, so a hidden title never flashes back after a launch.
                taste.restoreDiscoverMemory()
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
            .onChange(of: selectedMediaType) { _, _ in
                // A new issue is a new build (D5); the seed follows the medium.
                rebuild()
                Task { await loadLikeSeed() }
            }
            .onChange(of: library.loadState) { _, state in
                // The Library answered after the first build: build once more while nothing was done
                // on the page yet (owned titles leave the personal sections, R2), never mid-visit.
                guard state == .loaded,
                      DiscoverPageRules.lateRebuildAllowed(hasBuilt: hasBuilt, taps: feedback.taps, depth: maxDepth)
                else { return }
                rebuild()
                Task { await loadLikeSeed() }
            }
            .onChange(of: visitIsLive, initial: true) { _, live in
                if live { beginVisit() } else { endVisit() }
            }
            .onDisappear {
                bannerTask?.cancel()
            }
        }
        // The page's two toasts share one slot at the page foot (D12), outside the ScrollView.
        .discoverPageHost(feedback, hides: hides, plans: plans)
        .environment(\.discoverMissingArt, HomeInk.posterFill)
        .environment(\.discoverKindKicker, selectedMediaType == .all)
    }

    // MARK: Page

    @ViewBuilder
    private func content(width: CGFloat, minHeight: CGFloat, proxy: ScrollViewProxy) -> some View {
        let gutter = DiscoverIssueLayout.gutter(container: width)
        let column = max(0, width - gutter * 2)
        // One switch on the branded state (`DiscoverPageRules.brandedState`, tested in RestyleLaneTests).
        switch DiscoverPageRules.brandedState(isLoading: isLoadingSections, hasContent: hasAnyContent && hasBuilt,
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

    /// The issue: opening blocks, sections, the end, the footer.
    private func issue(gutter: CGFloat, column: CGFloat, proxy: ScrollViewProxy) -> some View {
        let german = KuroLocale.isGerman
        let compact = DiscoverIssueLayout.isCompact(column: column)
        let sections = visibleSections
        let lead = visibleLead
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

                DiscoverMoodKeys(kind: moodKind, likeTitle: likeSeed?.kind == moodKind ? likeSeed?.title : nil,
                                 column: column, onOpen: openMood)
                    .padding(.top, DiscoverIssueLayout.moods)

                if let lead {
                    DiscoverCoverStory(story: lead, kind: .lead, column: column)
                        .id(lead.key)
                        .transition(DiscoverCardMotion.transition(motion: KuroMotion.playsMotionNow(reduceMotion: reduceMotion)))
                        .environment(\.discoverSection, DiscoverSectionContext(id: DiscoverIssueSections.leadID))
                        .padding(.top, DiscoverIssueLayout.openingStack)
                }

                let entries = sections.map(contentsEntry)
                if DiscoverContents.shows(entries) || offersBrowseEntry {
                    DiscoverContentsLine(entries: entries, browseOffered: offersBrowseEntry, column: column,
                                         onJump: { target in
                                             feedback.trackJump("contents", target: target)
                                             scroll(to: target, proxy: proxy)
                                         },
                                         onBrowse: { routes.openBrowse() })
                        .padding(.top, DiscoverIssueLayout.openingStack)
                        .onGeometryChange(for: Bool.self) { proxy in
                            proxy.frame(in: .scrollView).maxY <= 0
                        } action: { passed in
                            let animation = KuroMotion.playsMotionNow(reduceMotion: reduceMotion) ? KuroMotion.settle : nil
                            withAnimation(animation) { contentsPassed = passed }
                        }
                }
            }
            .padding(.horizontal, gutter)

            ForEach(Array(sections.enumerated()), id: \.element.id) { index, built in
                sectionView(built, gutter: gutter, column: column)
                    .environment(\.discoverSection, sectionContext(built))
                    .background(alignment: .top) { jumpTarget(anchor(built.section)) }
                    .onGeometryChange(for: DiscoverSectionGeometry.self) { proxy in
                        DiscoverSectionGeometry.make(frame: proxy.frame(in: .scrollView),
                                                     viewport: proxy.bounds(of: .scrollView)?.height ?? 0,
                                                     band: DiscoverPinnedIndex.bandHeight)
                    } action: { geometry in
                        sectionGeometry[anchor(built.section)] = geometry
                        if geometry.halfVisible { markSeen(built) }
                    }
                    .padding(.top, index == 0 ? DiscoverIssueLayout.firstSection : DiscoverIssueLayout.section)
            }

            DiscoverIssueEnd(
                sections: sections.count,
                titles: shownTitleCount(sections) + (lead == nil ? 0 : 1),
                planned: feedback.planned, hidden: feedback.hidden, seen: feedback.seen,
                seenWord: selectedMediaType == .manga ? .read : (selectedMediaType == .all ? .seenOrRead : .seen),
                browseOffered: offersBrowseEntry,
                moreLists: moreListLinks,
                onBrowse: { routes.openBrowse() },
                onSearch: { onOpenSearch?() })
                .padding(.horizontal, gutter)
                .padding(.top, DiscoverIssueLayout.end)
                .onGeometryChange(for: Bool.self) { proxy in
                    let frame = proxy.frame(in: .scrollView)
                    let viewport = proxy.bounds(of: .scrollView)?.height ?? 0
                    return viewport > 0 && frame.minY < viewport
                } action: { visible in
                    if visible { reachedEnd = true }
                }

            HomeFooter()
                .padding(.horizontal, gutter)
        }
        .padding(.top, DiscoverIssueLayout.top)
    }

    /// A 1 pt target above a section, so a jump lands its heading under the pinned band (§5.10).
    private func jumpTarget(_ id: String) -> some View {
        Color.clear
            .frame(height: 1)
            .alignmentGuide(.top) { _ in DiscoverPinnedIndex.bandHeight + DiscoverIssueLayout.headingToPurpose }
            .id(DiscoverIssueSections.jumpID(id))
            .accessibilityHidden(true)
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

    /// The lead as built (claimed first, D5), unless it has been hidden since.
    private var visibleLead: DiscoverStory? {
        guard let story = leadStory, let claimed = build.lead, claimed.key == story.key,
              !isLiveHidden(story.key) else { return nil }
        return story
    }

    // MARK: Sections

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

    /// Index rows before "See all": three on All, five on Anime and Manga (the shipped owner decision).
    private var indexRowLimit: Int { DiscoverIssueLayout.indexRows(onAll: selectedMediaType == .all) }

    private var trioColumns: Int {
        DiscoverIssueLayout.trioColumns(regularWidth: horizontalSizeClass == .regular,
                                        accessibility: dynamicTypeSize.isAccessibilitySize)
    }

    private var tonightShelfName: String {
        vm.tonightShelfTitle ?? KuroLocale.text("Tonight's shelf", "Das Regal für heute Abend")
    }

    /// A title hidden on Discover right now: its own answer, or Not interested on another title of its
    /// franchise on this page (D16, within the visit's build).
    private func isLiveHidden(_ key: MediaKey) -> Bool {
        build.isLiveHidden(key, isHidden: { taste.isHiddenOnDiscover($0) },
                           notInterested: { taste.discoverHidden[$0] == .notInterested })
    }

    /// The built sections with their titles still on the page (a section emptied by hides leaves the
    /// page and the contents; the cap is not refilled mid-visit, §7).
    private var visibleSections: [DiscoverIssueBuild.Built] {
        build.visibleSections(isHidden: { taste.isHiddenOnDiscover($0) },
                              notInterested: { taste.discoverHidden[$0] == .notInterested })
    }

    private func shownTitleCount(_ sections: [DiscoverIssueBuild.Built]) -> Int {
        sections.reduce(0) { sum, built in
            sum + min(built.cards.count, shownCount(built.section))
        }
    }

    private func shownCount(_ section: PageSection) -> Int {
        DiscoverIssueSections.shownCount(section, issue: selectedMediaType, trioColumns: trioColumns, indexRows: indexRowLimit)
    }

    /// The titles a section shows now (the NEW marks and the visit's "seen" snapshot read these).
    private func shownKeys(_ built: DiscoverIssueBuild.Built) -> [MediaKey] {
        built.cards.prefix(shownCount(built.section)).map(\.key)
    }

    private func newKeys(_ built: DiscoverIssueBuild.Built) -> Set<MediaKey> {
        visit.baseline.newKeys(section: built.section.id, shown: shownKeys(built))
    }

    private func newMarker(_ built: DiscoverIssueBuild.Built) -> String? {
        let count = newKeys(built).count
        guard count > 0 else { return nil }
        let now = Date()
        return DiscoverIssueCopy.newSince(count, lastVisit: visit.baseline.lastVisitDate(section: built.section.id) ?? now,
                                          now: now, german: KuroLocale.isGerman)
    }

    private func sectionContext(_ built: DiscoverIssueBuild.Built) -> DiscoverSectionContext {
        DiscoverSectionContext(id: built.section.id, newKeys: newKeys(built), reason: reason(built.section),
                               title: sectionName(built.section))
    }

    /// The section's reason words for the preview (bare words: `DiscoverMenuCopy.whyItsHere` adds
    /// "Why it's here: " and the full stop).
    private func reason(_ section: PageSection) -> String? {
        let german = KuroLocale.isGerman
        switch section {
        case .newToYou: return DiscoverMenuCopy.Reason.unseen.text(german: german)
        case .mangaNewToYou: return DiscoverMenuCopy.Reason.unread.text(german: german)
        case .becauseYou:
            return vm.becauseYouReason.map { DiscoverMenuCopy.Reason.closeTo($0).text(german: german) }
        case .essentials, .essentialsManga: return DiscoverMenuCopy.Reason.canon.text(german: german)
        case .currentSeason: return DiscoverMenuCopy.Reason.airing.text(german: german)
        case .trending, .trendingManga: return DiscoverMenuCopy.Reason.popular.text(german: german)
        case .classics, .classicsManga: return DiscoverMenuCopy.Reason.classic.text(german: german)
        case .tonightShelf, .hiddenGem: return nil
        }
    }

    private func anchor(_ section: PageSection) -> String { "discover.\(section.id)" }

    private func sectionName(_ section: PageSection) -> String {
        if section == .tonightShelf { return tonightShelfName }
        if section == .hiddenGem { return DiscoverIssueCopy.hiddenGem(german: KuroLocale.isGerman) }
        guard let route = section.route else { return "" }
        return route.title(german: KuroLocale.isGerman, reason: route == .animeBecauseYou ? vm.becauseYouReason : nil)
    }

    /// A section heading with the editorial full stop.
    private func headline(_ section: PageSection) -> String { DiscoverIssueCopy.heading(sectionName(section)) }

    private func contentsEntry(_ built: DiscoverIssueBuild.Built) -> DiscoverContents.Entry {
        DiscoverContents.Entry(id: anchor(built.section), name: sectionName(built.section),
                               count: built.section == .hiddenGem ? 1 : built.total, newCount: newKeys(built).count)
    }

    /// The section's one question (R1, §8).
    private func purpose(_ section: PageSection) -> String {
        // The canon counts are the ones "See all {n}" and the contents show (after the R2 rules).
        DiscoverIssueSections.purpose(section, airingToday: showsAnime ? vm.airingToday.count : 0,
                                      essentials: build.built(.essentials)?.total ?? vm.essentials.count,
                                      essentialsManga: build.built(.essentialsManga)?.total ?? vm.essentialsManga.count,
                                      shelfBlurb: vm.tonightShelfSubtitle, german: KuroLocale.isGerman)
    }

    @ViewBuilder
    private func sectionView(_ built: DiscoverIssueBuild.Built, gutter: CGFloat, column: CGFloat) -> some View {
        let section = built.section
        let title = headline(section)
        let marker = newMarker(built)
        switch section {
        case .newToYou, .becauseYou:
            DiscoverFeatureTrio(anchor: anchor(section), title: title, purpose: purpose(section), newMarker: marker,
                                cards: built.cards, total: built.total, column: column,
                                onSeeAll: { openSeeAll(section) })
                .padding(.horizontal, gutter)
        case .mangaNewToYou:
            if DiscoverIssueSections.drawsMangaNewToYouAsRail(selectedMediaType) {
                // All (§14.2): one rail in Trending's anatomy, up to ten, then "See all {n} ›".
                DiscoverIssueRail(anchor: anchor(section), title: title, purpose: purpose(section), newMarker: marker,
                                  cards: built.cards, total: built.total, column: column, gutter: gutter,
                                  onSeeAll: { openSeeAll(section) })
            } else {
                DiscoverFeatureTrio(anchor: anchor(section), title: title, purpose: purpose(section), newMarker: marker,
                                    cards: built.cards, total: built.total, column: column,
                                    onSeeAll: { openSeeAll(section) })
                    .padding(.horizontal, gutter)
            }
        case .currentSeason:
            // D8: the Airing-today glance is This season's first block (All and Anime).
            DiscoverFeatureTrio(anchor: anchor(section), title: title, purpose: purpose(section), newMarker: marker,
                                cards: built.cards, total: built.total, column: column, feature: false,
                                glance: showsAnime && !vm.airingToday.isEmpty
                                    ? AnyView(airingGlance(compact: DiscoverIssueLayout.isCompact(column: column)))
                                    : nil,
                                onSeeAll: { openSeeAll(section) })
                .padding(.horizontal, gutter)
        case .tonightShelf:
            DiscoverIssueRail(anchor: anchor(section), title: title, purpose: purpose(section), newMarker: marker,
                              cards: built.cards, total: built.total, column: column, gutter: gutter,
                              onSeeAll: { openShelfSeeAll() })
        case .essentials, .essentialsManga:
            DiscoverIndexSection(anchor: anchor(section), title: title, purpose: purpose(section), newMarker: marker,
                                 cards: built.cards, total: built.total, column: column,
                                 hook: progressModel(section), hookIsManga: section == .essentialsManga,
                                 rowLimit: indexRowLimit,
                                 onSeeAll: { openSeeAll(section) })
                .padding(.horizontal, gutter)
        case .classics, .classicsManga:
            DiscoverIndexSection(anchor: anchor(section), title: title, purpose: purpose(section), newMarker: marker,
                                 cards: built.cards, total: built.total, column: column,
                                 rowLimit: indexRowLimit,
                                 onSeeAll: { openSeeAll(section) })
                .padding(.horizontal, gutter)
        case .trending, .trendingManga:
            DiscoverIssueRail(anchor: anchor(section), title: title, purpose: purpose(section), newMarker: marker,
                              cards: built.cards, total: built.total, column: column, gutter: gutter,
                              refines: section == .trending, ownCards: built.ownCards, refinePool: built.refinePool,
                              onSeeAll: { openSeeAll(section) },
                              onSeeAllRefined: { filter in openSeeAll(section, refine: filter) })
        case .hiddenGem:
            if let gem = vm.hiddenGem {
                VStack(alignment: .leading, spacing: 0) {
                    DiscoverSectionHeader(title: title, purpose: purpose(section), newMarker: marker,
                                          compact: DiscoverIssueLayout.isCompact(column: column))
                    DiscoverCoverStory(story: DiscoverStory(feature: gem, eyebrow: DiscoverIssueCopy.hiddenGem(german: KuroLocale.isGerman)),
                                       kind: .gem, column: column)
                }
                .id(anchor(section))
                .padding(.horizontal, gutter)
            }
        }
    }

    /// The Essentials hook's numbers over the full curated list (§5.9).
    private func progressModel(_ section: PageSection) -> DiscoverProgressModel {
        let items: [(key: MediaKey, title: String)] = section == .essentialsManga
            ? vm.essentialsManga.map { (MediaKey(kind: .manga, id: $0.id), $0.title) }
            : vm.essentials.map { (MediaKey(kind: .anime, id: $0.id), $0.title) }
        return DiscoverProgressModel.make(items: items, status: { library.entry(for: $0)?.status },
                                          hidden: { taste.discoverHidden[$0] })
    }

    // MARK: Airing today (This season's first block, D8)

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
            action: { openSeeAll(route: .animeAiringToday) }
        )
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

    // MARK: Pinned index and jumps

    @ViewBuilder
    private var pinnedIndex: some View {
        let sections = visibleSections
        if contentsPassed, sections.count >= 2 {
            let german = KuroLocale.isGerman
            let entries = sections.map { built in
                DiscoverPinnedEntry(id: anchor(built.section),
                                    word: DiscoverIssueCopy.pinnedWord(built.section, issue: selectedMediaType, german: german),
                                    hasNew: !newKeys(built).isEmpty)
            }
            DiscoverPinnedIndex(entries: entries,
                                current: DiscoverSectionGeometry.current(order: entries.map(\.id), geometry: sectionGeometry),
                                canvas: canvas,
                                onJump: { target in
                                    feedback.trackJump("pinned", target: target)
                                    pendingJump = target
                                })
                .transition(.opacity)
        }
    }

    /// Scrolls a section's heading under the pinned band (settle; instant under Reduce Motion).
    private func scroll(to id: String, proxy: ScrollViewProxy) {
        let animation = KuroMotion.playsMotionNow(reduceMotion: reduceMotion) ? KuroMotion.settle : nil
        withAnimation(animation) { proxy.scrollTo(DiscoverIssueSections.jumpID(id), anchor: .top) }
    }

    // MARK: Moods

    private func openMood(_ mood: DiscoverMood) {
        // `discover_mood_open` (with its count) is the mood journey's own event (lane B).
        let german = KuroLocale.isGerman
        routes.openPage(DiscoverMoodRoute.journeyPage(mood, kind: moodKind, german: german,
                                                      seedTitle: likeSeed?.kind == moodKind ? likeSeed?.title : nil))
    }

    /// "Like {title}": the Library's latest well-rated Completed title of the issue's medium (D9), with
    /// its title from the catalogue (cached). Without one the key is not shown.
    private func loadLikeSeed() async {
        let kind = moodKind
        guard let key = discovery.likeLastLovedSeed(medium: kind) else {
            if likeSeed?.kind == kind { likeSeed = nil }
            return
        }
        if likeSeed?.key == key { return }
        let title: String?
        switch kind {
        case .anime: title = (try? await catalog.fetchAnimeById(key.id))??.title
        case .manga: title = (try? await catalog.fetchMangaById(key.id))??.title
        }
        guard let title, !title.isEmpty, moodKind == kind else { return }
        likeSeed = DiscoverLikeSeed(key: key, kind: kind, title: KuroCardText.sanitizeTitleForCard(title))
    }

    // MARK: See all and More lists

    private var moreListLinks: [DiscoverIssueEnd.MoreLink] {
        DiscoverIssueSections.moreLists(sectionInputs, dropped: build.dropped).map { link in
            switch link {
            case .route(let route):
                return DiscoverIssueEnd.MoreLink(id: route.id, name: route.title(german: KuroLocale.isGerman)) {
                    openSeeAll(route: route)
                }
            case .tonightShelf:
                return DiscoverIssueEnd.MoreLink(id: "tonightShelf", name: tonightShelfName) { openShelfSeeAll() }
            case .hiddenGem:
                return DiscoverIssueEnd.MoreLink(id: "hiddenGem", name: DiscoverIssueCopy.hiddenGem(german: KuroLocale.isGerman)) {
                    if let gem = vm.hiddenGem { routes.openMedia(MediaRoute(MediaKey(kind: gem.kind, id: gem.mediaId))) }
                }
            }
        }
    }

    private func openSeeAll(_ section: PageSection, refine: DiscoverRailFilter = .all) {
        guard let route = section.route else { return }
        openSeeAll(route: route, refine: refine)
    }

    /// "See all" opens the section as a journey (navigation contract §1): its frames push their title,
    /// ✕ / swipe-down collapses back to Discover. Hidden titles stay out (R5). A rail's local refinement
    /// opens the page with the same choice selected (R6: the choice is never lost on the way).
    private func openSeeAll(route: EditorialDiscoverRoute, refine: DiscoverRailFilter = .all) {
        // `discover_see_all` ("opened", sorts, filters, pages) is the See all page's own event (lane B).
        let title = route.title(german: KuroLocale.isGerman, reason: route == .animeBecauseYou ? vm.becauseYouReason : nil)
        let page = fullSection(for: route, title: title,
                               selection: DiscoverSeeAllSelection.opening(DiscoverSeeAllSection.of(route), refine: refine))
        routes.openPage(.seeAll(AnyJourneyPage(id: DiscoverSeeAllPolicy.pageID(route), title: title) { page }))
    }

    private func openShelfSeeAll() {
        let title = tonightShelfName
        let items = vm.tonightShelf.filter { !isLiveHidden($0.libraryKey) }
        routes.openPage(.seeAll(AnyJourneyPage(id: "discover:tonightShelf", title: title) {
            FullSectionView(title: title, items: items)
        }))
    }

    private func visibleAnime(_ items: [AnimeCard]) -> [AnimeCard] {
        items.filter { !isLiveHidden(MediaKey(kind: .anime, id: $0.id)) }
    }

    private func visibleManga(_ items: [MangaCard]) -> [MangaCard] {
        items.filter { !isLiveHidden(MediaKey(kind: .manga, id: $0.id)) }
    }

    /// The section's See all page (§5.5): lane B's `DiscoverSeeAllPage` (sorts, chips, Plan keys, the
    /// preview, paging where the source pages), seeded with the section's loaded rows minus the titles
    /// hidden right now (R5). The page applies the owned rule and the hidden memory itself.
    private func fullSection(for route: EditorialDiscoverRoute, title: String,
                             selection: DiscoverSeeAllSelection? = nil) -> some View {
        let purpose = PageSection.allCases.first { $0.route == route }.map(purpose) ?? ""
        let anime: [AnimeCard]
        let manga: [MangaCard]
        var slots: [Int: DiscoverAiringSlot] = [:]
        switch route {
        case .animeEssentials: anime = visibleAnime(vm.essentials); manga = []
        case .animeClassics: anime = visibleAnime(vm.classics); manga = []
        case .animeNewToYou: anime = visibleAnime(vm.newToYou); manga = []
        case .animeBecauseYou:
            // Because-you rows are generic media: the page's rows as catalogue cards, so See all can sort
            // and filter them on the device while the prepared section reader is not deployed.
            let rows = vm.becauseYou.filter { !isLiveHidden($0.libraryKey) }
            anime = rows.filter { $0.kind == .anime }.map(DiscoverSeeAllRows.animeCard)
            manga = rows.filter { $0.kind == .manga }.map(DiscoverSeeAllRows.mangaCard)
        case .animeAiringToday:
            let ordered = DiscoverAiringOrder.ordered(visibleAnime(vm.airingToday), id: \.id, slots: airingSlots, now: Date())
            anime = ordered; manga = []
            slots = todaysSlots(for: ordered)
        case .animeCurrentSeason: anime = visibleAnime(vm.currentSeason); manga = []
        case .animeTrending: anime = visibleAnime(vm.trending); manga = []
        case .animeTopRated: anime = visibleAnime(vm.topRated); manga = []
        case .animeNewlyAdded: anime = visibleAnime(vm.newlyAdded); manga = []
        case .mangaEssentials: anime = []; manga = visibleManga(vm.essentialsManga)
        case .mangaClassics: anime = []; manga = visibleManga(vm.classicsManga)
        case .mangaNewToYou: anime = []; manga = visibleManga(vm.newToYouManga)
        case .mangaTrending: anime = []; manga = visibleManga(vm.trendingManga)
        case .mangaTopRated: anime = []; manga = visibleManga(vm.topRatedManga)
        case .mangaNewlyAdded: anime = []; manga = visibleManga(vm.newlyAddedManga)
        }
        return DiscoverSeeAllPage(source: .route(route), title: title, purpose: purpose,
                                  animeItems: anime, mangaItems: manga, airingSlots: slots,
                                  initialSelection: selection)
    }

    // MARK: Build (R2, D5)

    /// One build: the lead, then Essentials, then the page order claim titles once across the page.
    private func rebuild() {
        let issue = selectedMediaType
        var sources: [DiscoverIssueBuilder.Source] = []
        for section in DiscoverIssueSections.candidates(sectionInputs) {
            sources.append(DiscoverIssueBuilder.Source(section: section, cards: cards(for: section),
                                                       shown: shownCount(section)))
        }
        let notInterested = Set(taste.discoverHidden.filter { $0.value == .notInterested }.keys)
        build = DiscoverIssueBuilder.build(
            lead: leadStory?.card, sources: sources, hiddenKeys: taste.discoverHiddenKeys, notInterested: notInterested,
            owned: { library.entry(for: $0)?.status },
            franchise: { discovery.franchiseKeys(for: $0.key, title: $0.media.title) },
            issue: issue)
        var slots: [MediaKey: DiscoverCardSlot] = [:]
        if let lead = build.lead { slots[lead.key] = DiscoverCardSlot(section: DiscoverIssueSections.leadID, position: 0) }
        for built in build.sections {
            for (index, card) in built.cards.enumerated() where slots[card.key] == nil {
                slots[card.key] = DiscoverCardSlot(section: built.section.id, position: index)
            }
        }
        feedback.slots = slots
        hasBuilt = true
    }

    private func cards(for section: PageSection) -> [TasteCard] {
        switch section {
        case .becauseYou: return vm.becauseYou.map { TasteCard(media: $0) }
        case .newToYou: return vm.newToYou.map { TasteCard(anime: $0) }
        case .tonightShelf: return vm.tonightShelf.map { TasteCard(media: $0) }
        case .currentSeason: return vm.currentSeason.map { TasteCard(anime: $0) }
        case .essentials: return vm.essentials.map { TasteCard(anime: $0) }
        case .hiddenGem:
            guard let gem = vm.hiddenGem else { return [] }
            return [DiscoverStory(feature: gem, eyebrow: DiscoverIssueCopy.hiddenGem(german: KuroLocale.isGerman)).card]
        case .mangaNewToYou: return vm.newToYouManga.map { TasteCard(manga: $0) }
        case .trending: return vm.trending.map { TasteCard(anime: $0) }
        case .classics: return vm.classics.map { TasteCard(anime: $0) }
        case .essentialsManga: return vm.essentialsManga.map { TasteCard(manga: $0) }
        case .trendingManga: return vm.trendingManga.map { TasteCard(manga: $0) }
        case .classicsManga: return vm.classicsManga.map { TasteCard(manga: $0) }
        }
    }

    // MARK: Visits (D18)

    private func beginVisit() {
        guard let userId = identity.currentUserId else { return }
        let now = Date()
        let starts = visit.begin(userId: userId, defaults: visitDefaults, now: now)
        if starts {
            feedback.resetSession()
            reportedTally = DiscoverVisitSession.Tally()
            maxDepth = 0
            reachedEnd = false
            // A new visit is a new build (D5), once the page has content; on a new rail day it reads
            // the new day's bundle first (`refreshSections` builds when it lands).
            switch DiscoverPageRules.visitStart(hasBuilt: hasBuilt, bundleIsToday: discovery.hasCurrentDayBundle(now: now)) {
            case .readNewIssue?: Task { await refreshSections(force: false) }
            case .rebuild?: rebuild()
            case nil: break
            }
        }
    }

    private func endVisit() {
        guard let summary = visit.end(defaults: visitDefaults, now: Date()) else { return }
        // A visit resumed within 30 minutes ends again: each event carries only what happened since
        // the last one, so summing events never double-counts (depth and sections reached are maxima).
        let now = DiscoverVisitSession.Tally(taps: feedback.taps, plans: feedback.planned,
                                             hides: feedback.hidden, seen: feedback.seen)
        let delta = now.minus(reportedTally)
        reportedTally = now
        telemetry?.trackInteractionEvent("discover_visit_end", surface: "discover", result: "ended", extra: [
            "issue": selectedMediaType.rawValue.lowercased(),
            "sections_total": visibleSections.count,
            "sections_reached": summary.sectionsSeen,
            "reached_end": reachedEnd,
            "depth_pct": min(100, maxDepth * 10),
            "taps": delta.taps,
            "plans": delta.plans,
            "hides": delta.hides,
            "seen": delta.seen,
            "dwell": DiscoverVisitSession.dwellBucket(summary.seconds)
        ])
    }

    /// A section at least half on screen counts as seen this visit (its shown titles, §5.8).
    private func markSeen(_ built: DiscoverIssueBuild.Built) {
        guard visit.active else { return }
        visit.seen[built.section.id] = shownKeys(built)
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

        // First paint: build at once from the bundle with the device memory of the account's answers
        // (restored synchronously in `.task`) and the stem franchise rule. Then the server's answers and
        // the franchise components (silent while the prepared reader is not deployed) are read side by
        // side and the page builds once more while nothing was done on it yet (D5), as for the Library.
        rebuild()
        let hiddenBefore = taste.discoverHidden
        let franchisesBefore = discovery.knownFranchiseCount
        let keys = allKeys
        async let hiddenRead = taste.loadDiscoverHidden()
        async let franchiseRead: Void = discovery.loadFranchiseIds(for: keys)
        _ = await hiddenRead
        await franchiseRead
        if taste.discoverHidden != hiddenBefore || discovery.knownFranchiseCount != franchisesBefore,
           DiscoverPageRules.lateRebuildAllowed(hasBuilt: hasBuilt, taps: feedback.taps, depth: maxDepth) {
            rebuild()
        }
        await loadLikeSeed()

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
        let anime = (vm.essentials.prefix(14) + vm.newToYou.prefix(14) + vm.trending.prefix(14) + vm.currentSeason.prefix(10))
            .compactMap { URL(string: $0.imageURL ?? "") }
        let manga = (vm.essentialsManga.prefix(14) + vm.newToYouManga.prefix(14) + vm.trendingManga.prefix(14) + vm.classicsManga.prefix(10))
            .compactMap { URL(string: $0.imageURL ?? "") }
        let urls = Array((anime + manga).prefix(70))
        if !urls.isEmpty {
            Task { await ImagePipeline.shared.prefetch(urls: urls, maxPixelSize: 360) }
        }
    }

    /// Every title the page could show (the franchise reader's batch).
    private var allKeys: [MediaKey] {
        var keys: [MediaKey] = []
        keys += (vm.essentials + vm.classics + vm.newToYou + vm.trending + vm.currentSeason).map { MediaKey(kind: .anime, id: $0.id) }
        keys += (vm.essentialsManga + vm.classicsManga + vm.newToYouManga + vm.trendingManga).map { MediaKey(kind: .manga, id: $0.id) }
        keys += (vm.becauseYou + vm.tonightShelf).map(\.libraryKey)
        if let featured = vm.featured { keys.append(MediaKey(kind: .anime, id: featured.id)) }
        if let feature = vm.dailyFeature { keys.append(MediaKey(kind: feature.kind, id: feature.mediaId)) }
        if let gem = vm.hiddenGem { keys.append(MediaKey(kind: gem.kind, id: gem.mediaId)) }
        return keys
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

/// The "Like {title}" mood key's seed.
struct DiscoverLikeSeed: Equatable {
    let key: MediaKey
    let kind: MediaKind
    let title: String
}

// MARK: - See all

/// A Discover section in full: the loaded titles as an equal-frame grid with an in-place filter.
/// A journey page (`routes.openPage(.seeAll(...))`): its frames push their title inside the journey.
/// The shipped grid "See all", kept for Tonight's shelf only (no `EditorialDiscoverRoute`, so it has no
/// `DiscoverSeeAllSource`; the shelf is behind `discover_realm_rails_v1`, 0% live). Every routed section
/// opens lane B's `DiscoverSeeAllPage`.
struct FullSectionView<Item: MediaDisplayable>: View {
    let title: String
    let items: [Item]
    var airingSlots: [Int: DiscoverAiringSlot] = [:]

    var body: some View {
        DiscoverFullSectionSheet(title: title, items: items, airingSlots: airingSlots)
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

    /// What a new visit does with a page that already has an issue (D5, D18): read the bundle again
    /// when the one in memory is from an earlier rail day (the page stayed alive overnight, so its
    /// kicker, "a new set each morning" and NEW markers would otherwise describe yesterday), else
    /// rebuild the claims over the data in memory. nil: nothing built yet (the first load builds).
    enum VisitStart: Equatable { case readNewIssue, rebuild }

    static func visitStart(hasBuilt: Bool, bundleIsToday: Bool) -> VisitStart? {
        guard hasBuilt else { return nil }
        return bundleIsToday ? .rebuild : .readNewIssue
    }

    /// Whether a late input (the Library, the server's hidden set, franchise ids) may rebuild the page:
    /// only while nothing was done on it yet in this visit (no tap, no scroll past the first screen),
    /// so claims never move under the user's finger (D5).
    static func lateRebuildAllowed(hasBuilt: Bool, taps: Int, depth: Int) -> Bool {
        hasBuilt && taps == 0 && depth <= 1
    }
}

// MARK: - Issue sections (pure)

/// Which lead and sections the Discover issue draws, in the curated order, behind the page's flag
/// gates and the R7 cap (pure; DUpageTests and DCdiscoverTests pin All / Anime / Manga with the flags
/// on and off).
enum DiscoverIssueSections {
    typealias Issue = EditorialDiscoverView.DiscoverMediaTypeFilter

    enum Section: Hashable, CaseIterable {
        case becauseYou, newToYou, tonightShelf, currentSeason, essentials, hiddenGem, mangaNewToYou, trending,
             classics, essentialsManga, trendingManga, classicsManga

        /// The section's See all route (nil: Tonight's shelf and the Hidden gem have none).
        var route: EditorialDiscoverRoute? {
            switch self {
            case .becauseYou: return .animeBecauseYou
            case .newToYou: return .animeNewToYou
            case .currentSeason: return .animeCurrentSeason
            case .essentials: return .animeEssentials
            case .mangaNewToYou: return .mangaNewToYou
            case .trending: return .animeTrending
            case .classics: return .animeClassics
            case .essentialsManga: return .mangaEssentials
            case .trendingManga: return .mangaTrending
            case .classicsManga: return .mangaClassics
            case .tonightShelf, .hiddenGem: return nil
            }
        }

        /// The id used by visit memory, telemetry and the policy (`EditorialDiscoverRoute.id`, plus
        /// "tonightShelf" and "hiddenGem").
        var id: String {
            switch self {
            case .tonightShelf: return "tonightShelf"
            case .hiddenGem: return "hiddenGem"
            default: return route?.id ?? ""
            }
        }

        /// R2: personal and "new" sections hide owned titles; the rest mark them.
        var ownedRule: DiscoverOwnedPolicy {
            switch self {
            case .newToYou, .becauseYou, .mangaNewToYou: return .hide
            default: return .mark
            }
        }

        /// Essentials is the fixed canon: it claims right after the lead (D5).
        var isCanon: Bool { self == .essentials || self == .essentialsManga }
    }

    /// A More-lists link in the end block (D7, D17).
    enum MoreLink: Hashable {
        case route(EditorialDiscoverRoute)
        case tonightShelf
        case hiddenGem
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

    /// The lead's section id (visit memory, telemetry).
    static let leadID = "lead"
    /// The 1 pt jump target above a section (so its heading lands under the pinned band).
    static func jumpID(_ anchor: String) -> String { "jump." + anchor }

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

    /// The D7 cap candidates in page order (sections with content only; flagged ones behind their flag).
    static func candidates(_ input: Inputs) -> [Section] {
        var sections: [Section] = []
        let gem = input.realmRails && input.hiddenGemKind.map { matches(input.issue, kind: $0) } == true
        switch input.issue {
        case .manga:
            if input.mangaNewToYou { sections.append(.mangaNewToYou) }
            if input.essentialsManga { sections.append(.essentialsManga) }
            if gem { sections.append(.hiddenGem) }
            if input.trendingManga { sections.append(.trendingManga) }
            if input.classicsManga { sections.append(.classicsManga) }
        case .all, .anime:
            // Because-You replaces New to you when the taste rail has enough signal (mixed anime +
            // manga feed: All only).
            if input.issue == .all, input.becauseYou {
                sections.append(.becauseYou)
            } else if input.newToYou {
                sections.append(.newToYou)
            }
            if input.realmRails, input.tonightShelf { sections.append(.tonightShelf) }
            if input.currentSeason { sections.append(.currentSeason) }
            if input.essentials { sections.append(.essentials) }
            if gem { sections.append(.hiddenGem) }
            if input.issue == .all, input.mangaNewToYou { sections.append(.mangaNewToYou) }
            if input.trending { sections.append(.trending) }
            if input.classics { sections.append(.classics) }
        }
        return sections
    }

    /// D7: while more than `limit` remain, drop Classics, then Manga new to you, then the Hidden gem,
    /// then Tonight's shelf (then the last section, which no candidate list reaches today).
    static func cap(_ sections: [Section], limit: Int = DiscoverIssueLayout.sectionCap) -> (shown: [Section], dropped: [Section]) {
        var shown = sections
        var dropped: [Section] = []
        let order: [Section] = [.classics, .classicsManga, .mangaNewToYou, .hiddenGem, .tonightShelf]
        while shown.count > limit {
            let victim = order.first(where: shown.contains) ?? shown.last
            guard let victim, let index = shown.lastIndex(of: victim) else { break }
            shown.remove(at: index)
            dropped.append(victim)
        }
        // Dropped sections keep their page order in More lists.
        dropped.sort { (sections.firstIndex(of: $0) ?? 0) < (sections.firstIndex(of: $1) ?? 0) }
        return (shown, dropped)
    }

    /// The sections on the page before dedupe (the page itself caps after dedupe; see the builder).
    static func main(_ input: Inputs) -> [Section] { cap(candidates(input)).shown }

    /// The end block's More lists (D7, D17): the issue's fixed lists, then every section the cap
    /// dropped. On All, Essential manga is the first (details-songs §14.2).
    static func moreLists(_ input: Inputs, dropped: [Section]) -> [MoreLink] {
        var links: [MoreLink] = []
        switch input.issue {
        case .all:
            if input.essentialsManga { links.append(.route(.mangaEssentials)) }
            if input.topRated { links.append(.route(.animeTopRated)) }
            if input.newlyAdded { links.append(.route(.animeNewlyAdded)) }
        case .anime:
            if input.topRated { links.append(.route(.animeTopRated)) }
            if input.newlyAdded { links.append(.route(.animeNewlyAdded)) }
        case .manga:
            if input.topRatedManga { links.append(.route(.mangaTopRated)) }
            if input.newlyAddedManga { links.append(.route(.mangaNewlyAdded)) }
        }
        for section in dropped {
            switch section {
            case .tonightShelf: links.append(.tonightShelf)
            case .hiddenGem: links.append(.hiddenGem)
            default: if let route = section.route { links.append(.route(route)) }
            }
        }
        return links
    }

    /// Every section's one question under its heading (R1, §8; pure so tests cover every section).
    static func purpose(_ section: Section, airingToday: Int, essentials: Int, essentialsManga: Int,
                        shelfBlurb: String?, german: Bool) -> String {
        switch section {
        case .newToYou: return DiscoverIssueCopy.purposeNewToYou(german: german)
        case .becauseYou: return DiscoverIssueCopy.purposeBecauseYou(german: german)
        case .tonightShelf:
            if let shelfBlurb, !shelfBlurb.trimmingCharacters(in: .whitespaces).isEmpty { return shelfBlurb }
            return DiscoverIssueCopy.purposeTonightShelf(german: german)
        case .currentSeason: return DiscoverIssueCopy.purposeSeason(airingToday: airingToday, german: german)
        case .essentials: return DiscoverIssueCopy.purposeEssentials(count: essentials, manga: false, german: german)
        case .essentialsManga: return DiscoverIssueCopy.purposeEssentials(count: essentialsManga, manga: true, german: german)
        case .hiddenGem: return DiscoverIssueCopy.purposeHiddenGem(german: german)
        case .mangaNewToYou: return DiscoverIssueCopy.purposeMangaNewToYou(german: german)
        case .trending: return DiscoverIssueCopy.purposeTrending(manga: false, german: german)
        case .trendingManga: return DiscoverIssueCopy.purposeTrending(manga: true, german: german)
        case .classics: return DiscoverIssueCopy.purposeClassics(manga: false, german: german)
        case .classicsManga: return DiscoverIssueCopy.purposeClassics(manga: true, german: german)
        }
    }

    /// How Manga new to you is drawn: one rail on All (§14.2), the feature trio on Manga.
    static func drawsMangaNewToYouAsRail(_ issue: Issue) -> Bool { issue == .all }

    /// The titles a section shows (its claims are these plus the reserve): trio feature + covers,
    /// This season's cover row, index rows, a rail's ten, the Hidden gem's one.
    static func shownCount(_ section: Section, issue: Issue, trioColumns: Int, indexRows: Int) -> Int {
        switch section {
        case .becauseYou, .newToYou: return 1 + trioColumns
        case .mangaNewToYou: return drawsMangaNewToYouAsRail(issue) ? DiscoverIssueLayout.railCap : 1 + trioColumns
        case .currentSeason: return trioColumns
        case .essentials, .essentialsManga, .classics, .classicsManga: return indexRows
        case .trending, .trendingManga, .tonightShelf: return DiscoverIssueLayout.railCap
        case .hiddenGem: return 1
        }
    }
}

// MARK: - One build of the page (pure; R2, D5, D7)

/// The page's claims for one visit: the lead, the capped sections in page order (each its shown
/// titles followed by up to `reserve` unclaimed ones), what the cap dropped, and every card's franchise.
struct DiscoverIssueBuild {
    struct Built: Identifiable {
        let section: DiscoverIssueSections.Section
        /// Shown + reserve, in the section's order (a hide lets the reserve slide up).
        let cards: [TasteCard]
        /// What "See all {n}" counts: the section's own list after the R2 rules (`ownCards.count`).
        let total: Int
        /// The section's own list as its See all page draws it (hidden, owned, sequel rules, franchise
        /// dedupe within the list only).
        var ownCards: [TasteCard] = []
        /// `ownCards` minus every title and franchise another section (or the lead) shows: what a local
        /// refinement may draw without repeating a series on the page (R2, R6).
        var refinePool: [TasteCard] = []
        var id: DiscoverIssueSections.Section { section }
    }

    var lead: TasteCard?
    var sections: [Built]
    var dropped: [DiscoverIssueSections.Section]
    var franchises: [MediaKey: Set<DiscoverFranchiseKey>]

    static let empty = DiscoverIssueBuild(lead: nil, sections: [], dropped: [], franchises: [:])

    func built(_ section: DiscoverIssueSections.Section) -> Built? { sections.first { $0.section == section } }

    /// R5 mid-visit: hidden by its own answer, or (D16) by Not interested on another title of its
    /// franchise in this build.
    func isLiveHidden(_ key: MediaKey, isHidden: (MediaKey) -> Bool, notInterested: (MediaKey) -> Bool) -> Bool {
        isHidden(key) || isFranchiseHidden(key, notInterested: notInterested)
    }

    /// The sections as the page draws them now: hidden titles out, so each section's reserve slides
    /// up; See all counts lose the removed titles; a section emptied by hides (or a hidden Hidden gem)
    /// leaves the page and the contents, and the cap is not refilled mid-visit (§7). Claims never move.
    func visibleSections(isHidden: (MediaKey) -> Bool, notInterested: (MediaKey) -> Bool) -> [Built] {
        sections.compactMap { built in
            let visible: (TasteCard) -> Bool = { !isLiveHidden($0.key, isHidden: isHidden, notInterested: notInterested) }
            let cards = built.cards.filter(visible)
            guard !cards.isEmpty else { return nil }
            let removed = built.cards.count - cards.count
            return Built(section: built.section, cards: cards, total: max(cards.count, built.total - removed),
                         ownCards: built.ownCards.filter(visible), refinePool: built.refinePool.filter(visible))
        }
    }

    /// D16 within the build: a title shares a franchise with a title answered Not interested.
    func isFranchiseHidden(_ key: MediaKey, notInterested: (MediaKey) -> Bool) -> Bool {
        guard let mine = franchises[key], !mine.isEmpty else { return false }
        for (other, keys) in franchises where other != key && notInterested(other) && !keys.isDisjoint(with: mine) {
            return true
        }
        return false
    }
}

enum DiscoverIssueBuilder {
    struct Source {
        let section: DiscoverIssueSections.Section
        let cards: [TasteCard]
        let shown: Int
    }

    /// One build. Claim order (D5): the lead, then Essentials (the canon), then the page order. Hidden
    /// titles (and, for Not interested, their franchise; D16) are out; each section's owned rule
    /// applies; one title per franchise across the page. The cap (D7) counts sections that still hold
    /// titles after the rules, then the shown sections are claimed again without the dropped ones.
    static func build(lead: TasteCard?, sources: [Source], hiddenKeys: Set<MediaKey>, notInterested: Set<MediaKey>,
                      owned: (MediaKey) -> ListStatus?, franchise: (TasteCard) -> Set<DiscoverFranchiseKey>,
                      isSequel: (TasteCard) -> Bool = { DiscoverSequel.isSequel($0.media.title) },
                      issue: DiscoverIssueSections.Issue,
                      reserve: Int = DiscoverIssueLayout.reserve,
                      cap: Int = DiscoverIssueLayout.sectionCap) -> DiscoverIssueBuild {
        var franchises: [MediaKey: Set<DiscoverFranchiseKey>] = [:]
        for card in ([lead].compactMap { $0 } + sources.flatMap(\.cards)) where franchises[card.key] == nil {
            franchises[card.key] = franchise(card)
        }
        var hiddenFranchises: Set<DiscoverFranchiseKey> = []
        for key in notInterested { hiddenFranchises.formUnion(franchises[key] ?? []) }
        let isHidden: (MediaKey) -> Bool = { key in
            hiddenKeys.contains(key) || !(franchises[key] ?? []).isDisjoint(with: hiddenFranchises)
        }

        func claim(_ list: [Source]) -> [String: DiscoverPlacedSection<TasteCard>] {
            var inputs: [DiscoverSectionInput<TasteCard>] = []
            if let lead {
                inputs.append(DiscoverSectionInput(id: DiscoverIssueSections.leadID, policy: .mark, items: [lead], displayCount: 1))
            }
            let ordered = list.filter { $0.section.isCanon } + list.filter { !$0.section.isCanon }
            for source in ordered {
                inputs.append(DiscoverSectionInput(id: source.section.id, policy: source.section.ownedRule,
                                                   items: source.cards, displayCount: source.shown + reserve))
            }
            let placed = DiscoverPageComposer.compose(inputs, key: \.key, franchiseKeys: { franchises[$0.key] ?? [] },
                                                      isHidden: isHidden, ownedStatus: owned, isSequel: isSequel)
            return Dictionary(placed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }

        /// What the section's See all page draws from the same rows: its own list after the hidden,
        /// owned and sequel rules and franchise dedupe WITHIN the list (no other section's claims; See
        /// all is its own page). "See all {n}", the contents count and the purpose line all say this.
        func ownCards(_ source: Source) -> [TasteCard] {
            let input = DiscoverSectionInput(id: source.section.id, policy: source.section.ownedRule,
                                             items: source.cards, displayCount: source.cards.count)
            return DiscoverPageComposer.compose([input], key: \.key, franchiseKeys: { franchises[$0.key] ?? [] },
                                                isHidden: isHidden, ownedStatus: owned, isSequel: isSequel)
                .first?.items.map(\.item) ?? []
        }

        let first = claim(sources)
        let filled = sources.filter { !(first[$0.section.id]?.items.isEmpty ?? true) }
        let capped = DiscoverIssueSections.cap(filled.map(\.section), limit: cap)
        let kept = filled.filter { capped.shown.contains($0.section) }
        let second = claim(kept)
        // Every claimed title and franchise by the claim that holds it (the lead under its own id).
        var claims: [String: (keys: Set<MediaKey>, franchises: Set<DiscoverFranchiseKey>)] = [:]
        for (id, placed) in second {
            let keys = Set(placed.items.map(\.item.key))
            claims[id] = (keys, keys.reduce(into: Set<DiscoverFranchiseKey>()) { $0.formUnion(franchises[$1] ?? []) })
        }
        let sections: [DiscoverIssueBuild.Built] = kept.compactMap { source in
            guard let placed = second[source.section.id], !placed.items.isEmpty else { return nil }
            let own = ownCards(source)
            let others = claims.filter { $0.key != source.section.id }.values
            let pool = own.filter { card in
                others.allSatisfy { !$0.keys.contains(card.key) && $0.franchises.isDisjoint(with: franchises[card.key] ?? []) }
            }
            return DiscoverIssueBuild.Built(section: source.section, cards: placed.items.map(\.item),
                                            total: max(placed.items.count, own.count), ownCards: own, refinePool: pool)
        }
        return DiscoverIssueBuild(lead: second[DiscoverIssueSections.leadID]?.items.first?.item,
                                  sections: sections, dropped: capped.dropped, franchises: franchises)
    }
}

// MARK: - Scroll geometry (pure; the pinned index and visit memory)

/// A section's place in the viewport, bucketed so the page only hears changes that matter.
nonisolated struct DiscoverSectionGeometry: Equatable, Sendable {
    /// The section's top has reached the pinned band (it is the current section or above it).
    let passedTop: Bool
    /// At least half of the section (or of the viewport, for a tall one) is on screen.
    let halfVisible: Bool

    static func make(frame: CGRect, viewport: CGFloat, band: CGFloat) -> DiscoverSectionGeometry {
        let height = max(0, frame.height)
        let visible = max(0, min(frame.maxY, viewport) - max(frame.minY, 0))
        let needed = min(height, viewport) * 0.5
        return DiscoverSectionGeometry(passedTop: frame.minY <= band + 1,
                                       halfVisible: viewport > 0 && height > 0 && visible >= needed)
    }

    /// The current section: the last one in page order whose top has passed the band.
    static func current(order: [String], geometry: [String: DiscoverSectionGeometry]) -> String? {
        order.last { geometry[$0]?.passedTop == true }
    }
}

// MARK: - Visit (D18)

/// The page's visit: the persisted ledger, the snapshot NEW marks compare against (taken when the
/// visit began, so marks never blink), and the titles seen in it.
struct DiscoverVisitSession {
    struct Summary: Equatable {
        let sectionsSeen: Int
        let seconds: TimeInterval
    }

    /// The page's session counts at one moment (telemetry deltas).
    struct Tally: Equatable {
        var taps = 0, plans = 0, hides = 0, seen = 0

        func minus(_ other: Tally) -> Tally {
            Tally(taps: max(0, taps - other.taps), plans: max(0, plans - other.plans),
                  hides: max(0, hides - other.hides), seen: max(0, seen - other.seen))
        }
    }

    var ledger = DiscoverVisitLedger()
    var baseline = DiscoverVisitLedger()
    var seen: [String: [MediaKey]] = [:]
    var active = false
    var startedAt: Date? = nil
    var startedThisLaunch = false
    var account: String? = nil

    /// Starts or resumes a visit; true when a new visit started (D18).
    mutating func begin(userId: String, defaults: UserDefaults, now: Date) -> Bool {
        if account != userId.lowercased() {
            account = userId.lowercased()
            ledger = DiscoverVisitLedger.load(defaults: defaults, userId: userId)
            startedThisLaunch = false
            active = false
        }
        guard !active else { return false }
        let starts = DiscoverVisitLedger.startsVisit(firstThisLaunch: !startedThisLaunch, lastEnd: ledger.lastEnd, now: now)
        if starts {
            baseline = ledger
            seen = [:]
            startedAt = now
        }
        startedThisLaunch = true
        active = true
        return starts
    }

    /// Ends the visit: its seen titles are committed and saved. nil when no visit was running.
    mutating func end(defaults: UserDefaults, now: Date) -> Summary? {
        guard active, let account else { return nil }
        active = false
        ledger.commit(seen: seen, at: now)
        ledger.save(defaults: defaults, userId: account)
        return Summary(sectionsSeen: seen.values.filter { !$0.isEmpty }.count,
                       seconds: startedAt.map { now.timeIntervalSince($0) } ?? 0)
    }

    /// Scroll depth in tenths of the page (0 ... 10).
    static func depthBucket(offset: CGFloat, visible: CGFloat, content: CGFloat) -> Int {
        guard content > 0 else { return 0 }
        return min(10, max(0, Int(((offset + visible) / content * 10).rounded(.down))))
    }

    /// `discover_visit_end`'s dwell bucket (§5.12).
    static func dwellBucket(_ seconds: TimeInterval) -> String {
        if seconds < 10 { return "lt10s" }
        if seconds < 60 { return "10to60s" }
        if seconds < 300 { return "1to5m" }
        return "gt5m"
    }
}

extension EnvironmentValues {
    /// Where visit memory is stored (`.standard`; tests pass a throwaway suite).
    @Entry var discoverVisitDefaults: UserDefaults = .standard
}

/// See all seeds for the rows the bundle hands over as generic `Media` (Because you loved…).
enum DiscoverSeeAllRows {
    static func animeCard(_ media: Media) -> AnimeCard {
        AnimeCard(id: media.id, titleEnglish: media.title, titleRomaji: nil, titleNative: nil,
                  coverImageLarge: media.imageURL, coverImageMedium: nil, bannerImage: nil,
                  format: media.formatRaw, status: media.statusRaw, episodeCount: media.episodes,
                  seasonYear: Int(media.year), startDateYear: nil,
                  averageScore: media.rating.map { Int(($0 * 10).rounded()) },
                  popularity: media.popularityValue, trending: media.trendingValue, favourites: nil,
                  genreList: media.genres, createdAt: media.createdAtValue, rank: nil)
    }

    static func mangaCard(_ media: Media) -> MangaCard {
        MangaCard(id: media.id, titleEnglish: media.title, titleRomaji: nil, titleNative: nil,
                  coverImageLarge: media.imageURL, coverImageMedium: nil,
                  format: media.formatRaw, status: media.statusRaw, chapterCount: media.chapters,
                  startDateYear: Int(media.year),
                  averageScore: media.rating.map { Int(($0 * 10).rounded()) },
                  popularity: media.popularityValue, trending: media.trendingValue, favourites: nil,
                  genreList: media.genres, createdAt: media.createdAtValue, rank: nil)
    }
}
