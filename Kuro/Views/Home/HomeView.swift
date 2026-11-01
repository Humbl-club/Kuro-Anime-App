import KuroCore
import KuroLibrary
import SwiftUI

/// Accepted Home (rulebook §14.1), composed as the prototype's Poster Home (prototype-fidelity Task 4,
/// `ref-home-{busy,full,undated,quiet}-anime-390.png`, PROTOTYPE_SPEC.md §4): the medium switch with the
/// lead title's artwork clipped into the selected word, the Coming up glance, the opening line (with
/// the caught-up quiet card), two anime scene cards on their artwork material, a 2-column Also
/// watching grid (manga: the "Now reading" leaves), then quiet rows for planned titles, the calendar
/// card, the private club room only for a real club, and the page footer. A new account sees the
/// prototype's new-account block (`HomeNewAccount`) instead. Suggestions stay on Taste.
///
/// Planned titles never take an in-progress slot (a scene, a book or a +1 key). Coming up and the
/// calendar read the account's release schedule from `ReleasesStore` and say how certain each date
/// is (`KuroReleaseLine`). Copy is EN/DE through `KuroLocale`; dates follow `de_DE`/Europe/Berlin
/// for German readers. Layout derives from the measured container (320–430 pt phones, a readable
/// column on iPad), never from the screen.
struct HomeView: View {
    @Environment(HomeStore.self) private var home
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @Environment(ImportsService.self) private var imports
    @Environment(ReleasesStore.self) private var releases
    @Environment(NetworkMonitor.self) private var network
    @Environment(ArtworkMaterialStore.self) private var materials
    @Environment(ClubsStore.self) private var clubs
    @State private var actionScope = AccountActionScope()
    /// The new-account block's Plan results (toast with Undo at the screen foot, `tastePlanHost`).
    @State private var plans = TastePlanController()
    @Environment(\.kuroRoutes) private var routes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var seasonCard: HomeCard?
    @State private var showImportRecovery = false
    @State private var showImportChooser = false
    @State private var importRecoveryJob: ImportOutcome?
    @State private var animeScrollOffset: CGFloat = 0
    @State private var mangaScrollOffset: CGFloat = 0
    @State private var presentationAccount: AccountContext?
    @State private var containerSize: CGSize = .zero
    /// The release schedule has been asked for at least once (until then Coming up says so).
    @State private var scheduleChecked: Bool
    /// Extra Home pages fetched by Home itself to find a title in progress, per "medium|revision".
    @State private var inProgressPages: [String: Int] = [:]
    /// Home is fetching a page to find a title in progress (the scene keeps its loading shape).
    @State private var pagingForInProgress = false
    /// Durable +1 saves per "medium|mediaId": each change plays the key's confirm / restore stamp.
    @State private var confirmations: [String: Int] = [:]
    @AccessibilityFocusState private var calendarFocused: Bool
    private let skipNetworkLoad: Bool
    private let onOpenImport: (() -> Void)?
    private let onFindTitle: ((String) -> Void)?
    private let onOpenCollection: (() -> Void)?
    private let onImportNavigation: ((ImportResultDestination) -> Void)?
    private let onExploreTaste: (() -> Void)?
    private let onOpenClubs: (() -> Void)?
    /// `TastePageCopy.latchNewAccount` over the whole Library, held by the pager (`ContentView`) so
    /// its background and this page agree; nil when not known (previews, fixtures).
    private let newAccountLatch: Bool?

    init(skipNetworkLoad: Bool = false, onOpenImport: (() -> Void)? = nil,
         onFindTitle: ((String) -> Void)? = nil,
         onOpenCollection: (() -> Void)? = nil,
         onImportNavigation: ((ImportResultDestination) -> Void)? = nil,
         onExploreTaste: (() -> Void)? = nil,
         onOpenClubs: (() -> Void)? = nil,
         newAccountLatch: Bool? = nil) {
        self.skipNetworkLoad = skipNetworkLoad
        self.onOpenImport = onOpenImport
        self.onFindTitle = onFindTitle
        self.onOpenCollection = onOpenCollection
        self.onImportNavigation = onImportNavigation
        self.onExploreTaste = onExploreTaste
        self.onOpenClubs = onOpenClubs
        self.newAccountLatch = newAccountLatch
        self._scheduleChecked = State(initialValue: skipNetworkLoad)
    }

    var body: some View {
        ScrollViewReader { proxy in
            HomeMediumScroll(offset: scrollBinding) {
                VStack(alignment: .leading, spacing: 12) {
                    mediumSwitch
                    importRecoveryBanner
                    shelfBody(proxy: proxy)
                    if showsFooter {
                        // The page footer, last in the scroll content (PROTOTYPE_SPEC.md §4 "Footer"),
                        // on the paper feed's side padding.
                        HomeFooter()
                            .padding(.horizontal, HomeFeedInsets.feed)
                    }
                }
                .padding(.horizontal, gutter)
                .padding(.top, 7)
                .padding(.bottom, showsFooter ? 0 : 40)
                .frame(maxWidth: .infinity, minHeight: showsInvitation ? invitationHeight : 0, alignment: .topLeading)
                .kuroReadableWidth()
            }
            .id(home.medium)
        }
        // The container is measured outside anything the content can widen: a frame with both bounds
        // takes the proposed size whatever its child asks. Measured on the scroll view itself, a
        // fixed-width child laid out from the 375 pt fallback (the manga leaves' grid) held the scroll
        // view at 374 pt on a 320 pt phone, so the page never shrank to the real column.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { containerSize = $0 }
        .background(Color.clear)
        .tint(Color.kuroInk)
        // Outside the scroll view, so the new-account block's Plan toast sits at the screen foot.
        .tastePlanHost(plans)
        .onAppear {
            resetPresentationForAccount()
            actionScope.activate(session: libraryActions.accountSession)
        }
        .onChange(of: home.privacyEpoch) { _, _ in resetPresentationForAccount() }
        // Leaving `.loaded` (sign-out, account switch, reload) ends the Plan toast and its Undo.
        .onChange(of: library.loadState) { _, state in
            if state != .loaded { plans.dismiss() }
        }
        // The private club room's clubs (`ClubsStore` keeps a 60 s window, so a revisit costs nothing).
        .task(id: "\(home.privacyEpoch)|\(home.bundle?.homeRevision ?? -1)") {
            guard !skipNetworkLoad else { return }
            await clubs.refreshMyClubsIfStale()
        }
        .onDisappear {
            actionScope.deactivate()
        }
        // The account's release schedule: on first appearance, after an account change and after a
        // Library change reached Home (a new revision). `ReleasesStore` caches per account for five
        // minutes and drops that cache on membership changes, so a repeat costs nothing.
        // Also on every return to the foreground: the store's five-minute answer is re-read when it is
        // stale or holds a release whose moment has passed, so the next unit appears.
        .task(id: "\(home.privacyEpoch)|\(home.bundle?.homeRevision ?? -1)|\(scenePhase == .active)") {
            guard !skipNetworkLoad, scenePhase == .active else { return }
            await releases.loadSchedule()
            guard !Task.isCancelled else { return }
            scheduleChecked = true
        }
        .sheet(item: $seasonCard) { card in HomeSeasonOverview(card: card).routePresenter() }
        .sheet(isPresented: $showImportChooser) {
            ImportSourceChooser { destination in
                showImportChooser = false
                onImportNavigation?(destination)
            }
        }
        .sheet(isPresented: $showImportRecovery) {
            ImportWorkflowSheet(imports: imports, job: importRecoveryJob) { destination in
                showImportRecovery = false
                onImportNavigation?(destination)
            }
        }
        .task {
            guard !skipNetworkLoad else { return }
            home.restoreMedium()
            #if DEBUG
            if let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--kuro-home-medium=") }),
               let value = raw.split(separator: "=", maxSplits: 1).last {
                home.selectMedium(String(value))
            }
            if ProcessInfo.processInfo.arguments.contains("--kuro-show-import") {
                showImportChooser = true
            }
            if ProcessInfo.processInfo.arguments.contains("--kuro-seed-samples") {
                let samples: [(MediaKind, Int, ListStatus)] = [
                    (.anime, 117, .current),
                    (.anime, 758, .planning),
                    (.anime, 4525, .planning),
                    (.manga, 5, .current),
                    (.manga, 11, .planning)
                ]
                for sample in samples {
                    let outcome = await libraryActions.save(MediaKey(kind: sample.0, id: sample.1), status: sample.2)
                    if case .failed(let error) = outcome {
                        print("Home sample \(sample.1) was not saved: \(error)")
                    }
                }
            }
            #endif
            await home.load()
            await home.drain()
            _ = try? await imports.discoverPendingImports()
        }
    }

    // MARK: State

    private var scrollBinding: Binding<CGFloat> {
        let medium = home.medium
        return Binding(get: { medium == "manga" ? mangaScrollOffset : animeScrollOffset }, set: {
            if medium == "manga" { mangaScrollOffset = $0 } else { animeScrollOffset = $0 }
        })
    }

    private func resetPresentationForAccount() {
        let account = libraryActions.accountSession.current
        guard presentationAccount != account else { return }
        presentationAccount = account
        animeScrollOffset = 0; mangaScrollOffset = 0
        calendarFocused = false
        // The new account's schedule is not known yet: "Checking dates", never "Nothing scheduled".
        scheduleChecked = skipNetworkLoad
        inProgressPages = [:]; pagingForInProgress = false
        confirmations = [:]
        plans.dismiss()
        seasonCard = nil; showImportRecovery = false; importRecoveryJob = nil; showImportChooser = false
    }

    private var mediumKind: MediaKind { home.medium == "manga" ? .manga : .anime }

    private var shelfScene: HomeShelfScene {
        let statuses = library.allEntries.filter { $0.key.kind == mediumKind }.map(\.status)
        return HomeShelfPolicy.scene(
            activeListTypes: home.bundle?.active.map(\.listType) ?? [],
            libraryStatuses: statuses
        )
    }

    private var otherMediumOccupied: Bool {
        let other: MediaKind = mediumKind == .manga ? .anime : .manga
        let libraryCount = library.allEntries.filter { $0.key.kind == other }.count
        let bundleCount = (other == .manga ? home.manga : home.anime)?.active.count ?? 0
        return HomeShelfPolicy.otherMediumOccupied(
            selectedMedium: home.medium,
            animeCount: other == .anime ? max(libraryCount, bundleCount) : 0,
            mangaCount: other == .manga ? max(libraryCount, bundleCount) : 0
        )
    }

    /// The prototype's new-account block instead of the shelf (`HomeShelfPolicy.showsNewAccount`).
    private var showsNewAccount: Bool {
        HomeShelfPolicy.showsNewAccount(latched: newAccountLatch,
                                        onlyPlannedTitles: HomeShelfPolicy.onlyBarePlans(library.allEntries),
                                        scene: shelfScene, otherMediumOccupied: otherMediumOccupied)
    }

    /// The approved invitation (this medium empty, the other occupied): the page picture runs behind it.
    private var showsInvitation: Bool { shelfScene == .invitation && !showsNewAccount }

    /// The footer closes the populated shelf and the new-account block, once Home has a page.
    private var showsFooter: Bool { home.bundle != nil && !showsInvitation }

    // MARK: Geometry (from the measured container, never the screen)

    /// 20 pt outer gutter; 16 pt at 320 pt content widths (rulebook §5).
    private var gutter: CGFloat {
        containerSize.width > 0 && containerSize.width <= 330 ? KuroDesignSpacing.md : KuroDesignSpacing.padding
    }

    /// The content column's width: the container, capped to the readable column on regular width.
    private var contentWidth: CGFloat {
        let measured = containerSize.width > 40 ? containerSize.width : 375
        let column = horizontalSizeClass == .regular ? min(measured, KuroReadableWidth.maxWidth) : measured
        return max(240, column - gutter * 2)
    }

    /// The invitation fills one visible page (its picture runs behind it). Derived from the visible
    /// height, so landscape iPad and short phones keep a composed first screen.
    private var invitationHeight: CGFloat {
        containerSize.height > 120 ? containerSize.height : 560
    }

    private func perform(origin: AccountActionScope.Ticket?, operation: @escaping @MainActor () async -> Void) {
        actionScope.launch(origin: origin, session: libraryActions.accountSession) { _ in await operation() }
    }

    /// `perform`, handing the operation its ticket so it can check the account again after an await
    /// (`AccountActionScope`: callers check again after awaits).
    private func performTicketed(origin: AccountActionScope.Ticket?,
                                 operation: @escaping @MainActor (AccountActionScope.Ticket) async -> Void) {
        actionScope.launch(origin: origin, session: libraryActions.accountSession) { ticket in await operation(ticket) }
    }

    // MARK: Import recovery

    @ViewBuilder
    private var importRecoveryBanner: some View {
        if let pending = imports.pendingImports.first(where: {
            ![ImportPhase.ready, .cancelled, .failed, .undone].contains($0.phase)
                || $0.outcome?.projectionReady == false
        }) {
            let origin = actionScope.capture(session: libraryActions.accountSession)
            Button {
                perform(origin: origin) {
                    importRecoveryJob = pending.outcome
                    showImportRecovery = true
                }
            } label: {
                HStack(spacing: KuroDesignSpacing.sm) {
                    Image(systemName: "arrow.clockwise")
                        .font(.kuroMeta(weight: .medium))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                        Text(KuroLocale.text("Resume import", "Import fortsetzen"))
                            .font(.kuroBody(weight: .medium))
                            .foregroundStyle(Color.kuroInk)
                        Text(pending.selection.sourceIdentity)
                            .font(.kuroMeta())
                            .foregroundStyle(Color.kuroInkSecondary)
                    }
                    Spacer(minLength: KuroDesignSpacing.sm)
                    Image(systemName: "arrow.right")
                        .font(.kuroMeta(weight: .medium))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Color.kuroInk)
                .padding(KuroDesignSpacing.md)
                .frame(minHeight: 44)
                .background(Color.kuroCanvasQuiet, in: RoundedRectangle(cornerRadius: KuroRadius.md))
                .contentShape(Rectangle())
            }
            .buttonStyle(HomeContactStyle())
            .accessibilityLabel(KuroLocale.text("Resume import from \(pending.selection.sourceIdentity)",
                                                "Import von \(pending.selection.sourceIdentity) fortsetzen"))
        }
    }

    // MARK: Medium switch (prototype Poster switch; LANE_AMENDMENTS 7)

    /// The prototype's switch (`KuroPosterMediumSwitch`, shared with Taste): the selected word shows the
    /// lead title's artwork clipped into its letters with a contrast floor (`HomeMediumWordInk`), so it
    /// never reads lighter than the unselected word; an empty shelf shows the mountain.
    private var mediumSwitch: some View {
        KuroPosterMediumSwitch(selection: mediumKind, contentWidth: contentWidth,
                               onSelect: { home.selectMedium($0 == .manga ? "manga" : "anime") }) {
            HomePagePictureFill(fallback: shelfScene == .invitation ? .mountain : .solid)
        }
    }

    // MARK: Shelf

    @ViewBuilder
    private func shelfBody(proxy: ScrollViewProxy) -> some View {
        let origin = actionScope.capture(session: libraryActions.accountSession)
        let renderedMedium = home.medium
        switch home.loadState {
        case .idle, .loading:
            if home.bundle != nil {
                loadedShelf(proxy: proxy, origin: origin, renderedMedium: renderedMedium)
            } else {
                loadingShelf
            }
        case .failed(let message):
            if home.bundle != nil {
                loadedShelf(proxy: proxy, origin: origin, renderedMedium: renderedMedium)
                KuroStateView(home.failureIsOffline ? .offline(hasCachedContent: true) : .failed(hasCachedContent: true),
                              layout: .inline) {
                    perform(origin: origin) { await home.load() }
                }
            } else {
                KuroStateView(home.failureIsOffline ? .offline(hasCachedContent: false) : .failed(hasCachedContent: false),
                              title: message, layout: .inline) {
                    perform(origin: origin) { await home.load() }
                }
            }
        case .loaded:
            loadedShelf(proxy: proxy, origin: origin, renderedMedium: renderedMedium)
        }
    }

    @ViewBuilder
    private func loadedShelf(proxy: ScrollViewProxy, origin: AccountActionScope.Ticket?, renderedMedium: String) -> some View {
        if showsNewAccount {
            newAccountShelf
        } else if shelfScene == .invitation {
            Spacer().frame(height: min(max(0, invitationHeight * 0.3), 280))
            invitationCopy
            invitationActions
            Text(KuroLocale.text("Dates and club activity appear after you save a title.",
                                 "Termine und Club-Aktivität erscheinen, wenn du einen Titel speicherst."))
                .font(.kuroMeta())
                .foregroundStyle(Color.kuroInkQuiet)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, KuroDesignSpacing.sm)
        } else {
            populatedShelf(proxy: proxy, origin: origin)
            shelfStatus(origin: origin, renderedMedium: renderedMedium)
        }
    }

    /// The prototype's new-account Home (PROTOTYPE_SPEC.md §4 "New-account Home"; amendment 5): the
    /// opening row ("YOUR COLLECTION / Begin here."), then `HomeNewAccount` (＋, the two lines, Explore
    /// Taste, Import, "A first favourite."). No Coming up glance for a new account (§8.3). The block
    /// lays out its own gutters, so it runs the full column width.
    private var newAccountShelf: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeOpeningLineView(
                kicker: HomeOpeningLine.kicker(newAccount: true, medium: mediumKind),
                headline: HomeOpeningLine.headline(available: 0, caughtUp: false, newAccount: true, medium: mediumKind),
                compact: compactColumn)
            HomeNewAccount(medium: mediumKind,
                           onImport: { showImportChooser = true },
                           onExploreTaste: { onExploreTaste?() })
                .padding(.horizontal, -gutter)
        }
    }

    /// Stable geometry while the first page loads (rulebook §9): the branded skeletons shaped like the
    /// scene card (or manga leaves) and a list row, with the travelling scrub line.
    private var loadingShelf: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
            sceneLoadingShape
            KuroSkeleton(kind: .row)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KuroLocale.text("Loading your Home", "Dein Home wird geladen"))
    }

    private var inProgressPagesKey: String {
        "\(home.medium)|\(home.bundle?.homeRevision ?? -1)"
    }

    private func populatedShelf(proxy: ScrollViewProxy, origin: AccountActionScope.Ticket?) -> some View {
        let split = HomeShelfPolicy.partition(home.bundle?.active ?? [])
        let scene = shelfScene
        // The Home page mixes titles in progress and planned ones (most recently updated first): after
        // an import page 1 can hold only planned titles while the Library has one in progress. Home
        // then fetches up to `maxInProgressPages` pages by itself and keeps the scene's loading shape.
        let wantsPage = HomeShelfPolicy.shouldPageForInProgress(
            partition: split, scene: scene, nextCursor: home.bundle?.nextCursor,
            pagesFetched: inProgressPages[inProgressPagesKey] ?? 0)
        let awaitingInProgress = split.inProgress.isEmpty && scene == .inProgress
            && (wantsPage || pagingForInProgress) && !skipNetworkLoad
        let opening = openingState(split.inProgress)
        return VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
            // The prototype's opening block: glance, 12, opening line, then 18 to the feed; the
            // caught-up quiet card opens the feed with 20 under it.
            VStack(alignment: .leading, spacing: 12) {
                comingUpLine(proxy: proxy)
                if !split.inProgress.isEmpty {
                    HomeOpeningLineView(
                        kicker: HomeOpeningLine.kicker(newAccount: false, medium: mediumKind),
                        headline: HomeOpeningLine.headline(available: opening.available, caughtUp: opening.caughtUp,
                                                           newAccount: false, medium: mediumKind),
                        compact: compactColumn)
                    .padding(.bottom, 6)
                    if HomeOpeningLine.showsQuietLine(available: opening.available, caughtUp: opening.caughtUp, newAccount: false) {
                        HomeQuietCard(text: HomeOpeningLine.quietLine())
                            .padding(.bottom, 8)
                    }
                    if mediumKind == .anime {
                        let lanes = HomeShelfPolicy.scenes(split.inProgress)
                        animeScenes(lanes.scenes)
                        animeAlsoWatching(lanes.alsoWatching)
                    } else if containerSize.width > 0 {
                        // The manga activity stage has no top margin: the covers start 21 pt under the
                        // opening row (the stack's 12 plus the opening's 6 and the line box).
                        mangaLeaves(split.inProgress)
                    } else {
                        // Covers are sized from the measured column: wait for the first measurement.
                        sceneLoadingShape
                    }
                }
            }
            if split.inProgress.isEmpty, awaitingInProgress {
                sceneLoadingShape
            } else if split.inProgress.isEmpty, scene != .inProgress {
                restingBand(hasPlanned: !split.planned.isEmpty, hasPaused: !split.paused.isEmpty)
            }
            quietShelf(title: KuroLocale.text("Planned", "Geplant"), cards: split.planned,
                       state: KuroLocale.text("planned", "geplant"))
            quietShelf(title: KuroLocale.text("Paused", "Pausiert"), cards: split.paused,
                       state: KuroLocale.text("paused", "pausiert"))
            quietShelf(title: KuroLocale.text("Saved", "Gespeichert"), cards: split.saved, state: nil)
            moreTitlesButton(origin: origin)
            calendarSection
            clubSection(origin: origin)
        }
        .task(id: "\(inProgressPagesKey)|\(home.bundle?.nextCursor ?? "")|\(split.inProgress.isEmpty)|\(scene == .inProgress)") {
            guard !skipNetworkLoad else { return }
            let key = inProgressPagesKey
            let cursor = home.bundle?.nextCursor
            let fetched = inProgressPages[key] ?? 0
            guard HomeShelfPolicy.shouldPageForInProgress(partition: split, scene: scene, nextCursor: cursor,
                                                          pagesFetched: fetched) else {
                pagingForInProgress = false
                return
            }
            inProgressPages[key] = fetched + 1
            pagingForInProgress = true
            await home.loadMore()
            guard !Task.isCancelled else { return }
            // A failed page leaves the cursor as it was: stop waiting (More titles stays available).
            if home.bundle?.nextCursor == cursor { pagingForInProgress = false }
        }
    }

    /// The scene's loading shape (the branded scene-card or cover-leaf skeleton) while its titles arrive.
    private var sceneLoadingShape: some View {
        Group {
            if mediumKind == .manga {
                HomeMangaLeavesLoading(containerWidth: contentWidth)
            } else {
                KuroSkeleton(kind: .sceneCard)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KuroLocale.text("Loading your titles in progress", "Deine laufenden Titel werden geladen"))
    }

    /// The next Home page, directly under the quiet shelves it extends.
    @ViewBuilder
    private func moreTitlesButton(origin: AccountActionScope.Ticket?) -> some View {
        if home.bundle?.nextCursor?.isEmpty == false {
            KuroInkButton(KuroLocale.text("More titles", "Weitere Titel"), role: .secondary) {
                perform(origin: origin) { await home.loadMore() }
            }
        }
    }

    /// Nothing in progress in this medium: the saved shelf, never "you have nothing" (rulebook §9).
    private func restingBand(hasPlanned: Bool, hasPaused: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(hasPlanned || hasPaused
                 ? KuroLocale.text("Ready when you are.", "Bereit, wenn du es bist.")
                 : KuroLocale.text("You're caught up.", "Du bist auf dem neuesten Stand."))
                .font(.kuroDisplay(weight: .light))
                .tracking(-0.8)
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Rectangle()
                .fill(Color.kuroInk)
                .frame(width: 46, height: 2)
            if hasPlanned {
                Text(mediumKind == .manga
                     ? KuroLocale.text("Start a planned book from its page.", "Starte ein geplantes Buch auf seiner Seite.")
                     : KuroLocale.text("Start a planned title from its page.", "Starte einen geplanten Titel auf seiner Seite."))
                    .font(.kuroBody())
                    .foregroundStyle(Color.kuroInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if hasPaused {
                Text(KuroLocale.text("Paused titles wait here. Pick one up from its page.",
                                     "Pausierte Titel warten hier. Mach auf ihrer Seite weiter."))
                    .font(.kuroBody())
                    .foregroundStyle(Color.kuroInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                invitationAction(
                    kicker: KuroLocale.text("Collection", "Sammlung"),
                    title: KuroLocale.text("Everything you saved", "Alles, was du gespeichert hast"),
                    label: KuroLocale.text("Open Collection", "Sammlung öffnen")
                ) {
                    onOpenCollection?()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Planned, paused and other saved titles: a picture, the title, one tap to its page. No +1 key.
    /// `state` ("planned", "paused") is spoken with each row, so the kicker never carries it alone.
    @ViewBuilder
    private func quietShelf(title: String, cards: [HomeCard], state: String?) -> some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                Text(title)
                    .kuroKicker()
                    .accessibilityAddTraits(.isHeader)
                ForEach(cards) { card in
                    Button { open(card) } label: {
                        HStack(alignment: .center, spacing: KuroDesignSpacing.md) {
                            cover(card.coverImage ?? card.bannerImage)
                                .frame(width: 40, height: 60)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                                .accessibilityHidden(true)
                            Text(card.title)
                                .font(.kuroTitleName(weight: .regular))
                                .foregroundStyle(Color.kuroInk)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 60)
                        .padding(.vertical, KuroDesignSpacing.xs)
                        .overlay(alignment: .bottom) { Rectangle().fill(Color.kuroHairline).frame(height: 0.5) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(HomeContactStyle())
                    .accessibilityLabel(state.map { KuroLocale.text("Open \(card.title), \($0)", "\(card.title) öffnen, \($0)") }
                                        ?? KuroLocale.text("Open \(card.title)", "\(card.title) öffnen"))
                }
            }
        }
    }

    @ViewBuilder
    private func shelfStatus(origin: AccountActionScope.Ticket?, renderedMedium: String) -> some View {
        if let status = home.statusMessage {
            HStack(spacing: KuroDesignSpacing.sm) {
                Text(HomeCopy.display(status))
                    .font(.kuroMeta())
                    .foregroundStyle(Color.kuroInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Undo keys on Library's raw message, never on the displayed (translated) text.
                if status == HomeCopy.librarySavedOnDevice,
                   home.lastAdvancedKey?.kind.rawValue.lowercased() == home.medium,
                   let card = home.bundle?.active.first(where: {
                       $0.mediaId == home.lastAdvancedKey?.id
                           && UUID(uuidString: $0.lifecycleId) == home.lastAdvancedLifecycle
                   }) {
                    Button {
                        perform(origin: origin) {
                            guard home.medium == renderedMedium else { return }
                            await home.undo(card)
                        }
                    } label: {
                        Text(KuroLocale.text("Undo", "Rückgängig"))
                            .font(.kuroMeta(weight: .semibold))
                            .foregroundStyle(Color.kuroInk)
                            .underline()
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(HomeContactStyle())
                }
            }
            .accessibilityElement(children: .combine)
        }
        if let conflict = home.conflict, let token = home.conflictToken {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                Text(KuroLocale.text("\(conflict.title) is at \(conflict.serverPosition) on another device.",
                                     "\(conflict.title) steht auf einem anderen Gerät bei \(conflict.serverPosition)."))
                    .font(.kuroBody())
                    .foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
                KuroInkButton(KuroLocale.text("Keep that", "Das behalten"), role: .secondary) {
                    perform(origin: origin) { await home.keepServerProgress(expected: token) }
                }
                KuroInkButton(KuroLocale.text("Keep mine (\(conflict.localPosition))", "Meins behalten (\(conflict.localPosition))"),
                              role: .secondary) {
                    perform(origin: origin) { await home.reapplyLocalProgress(expected: token) }
                }
            }
        }
    }

    // MARK: Anime (prototype scene cards and Also watching)

    /// A 320 pt phone's column (the prototype's `@media(max-width:360px)` sizes).
    private var compactColumn: Bool { HomeSceneMetrics.isCompact(columnWidth: contentWidth) }

    private func artworkURL(_ card: HomeCard) -> URL? {
        (card.bannerImage ?? card.coverImage).flatMap(URL.init(string:))
    }

    /// The title's artwork material: the server's seed (or the neutral base) at once, then the material
    /// derived on device from the scene artwork (the prototype tints a title by its scene art).
    private func material(_ card: HomeCard) -> ArtworkMaterial {
        materials.material(for: artworkURL(card), seedHex: card.material?.base)
    }

    /// Units released so far (`HomeShelfPolicy.availableUnits`), from the catalogue status and total
    /// and the next known, non-estimated release of this title.
    private func availableUnits(_ card: HomeCard) -> Int? {
        let total = mediumKind == .manga ? card.chapters : card.episodes
        let key = MediaKey(kind: mediumKind, id: card.mediaId)
        // The title's next release first, then its other rows still ahead (soonest first), so a
        // volume or season row never decides how many chapters or episodes are out.
        let candidates = [releases.nextRelease(for: key)].compactMap { $0 }
            + releases.scheduleItems(for: mediumKind).filter { $0.key == key }
        let nextUnit = HomeShelfPolicy.nextUnitNumber(candidates, medium: mediumKind)
        return HomeShelfPolicy.availableUnits(catalogueStatus: card.catalogueStatus, total: total, nextUnit: nextUnit)
    }

    /// What the opening line may claim (`HomeShelfPolicy.opening`), over every title in progress in
    /// this medium (scenes and Also watching alike): released units not reached yet, summed, and
    /// whether nothing is new and nothing unknown (the quiet card).
    private func openingState(_ inProgress: [HomeCard]) -> (available: Int, caughtUp: Bool) {
        let entries = inProgress.map { card in
            HomeShelfPolicy.OpeningEntry(progress: home.displayedProgress(for: card), available: availableUnits(card),
                                         catalogueStatus: card.catalogueStatus)
        }
        let opening = HomeShelfPolicy.opening(entries)
        return (opening.newUnits, opening.nothingNew)
    }

    /// Club members who wrote about this title, in this medium (real display names only, never invented).
    private func clubNames(_ card: HomeCard) -> [String] {
        HomeShelfPolicy.clubNames(home.bundle?.club.items ?? [], mediaId: card.mediaId, medium: home.medium)
    }

    private func animeScenes(_ cards: [HomeCard]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(cards) { card in animeScene(card) }
        }
    }

    private func animeScene(_ card: HomeCard) -> some View {
        let state = keyState(card)
        let units = availableUnits(card)
        let fact = HomeSceneFact.make(
            hasNew: HomeShelfPolicy.hasNewUnit(progress: state.progress, available: units, catalogueStatus: card.catalogueStatus),
            // The same rule as the key and the readout, so the card never says "Up to date" beside a +1.
            knownCaughtUp: state.caughtUp,
            clubNames: clubNames(card), medium: mediumKind)
        return HomeSceneCard(
            title: card.title,
            artURL: artworkURL(card),
            material: material(card),
            season: HomeSeasonTab.make(card),
            readout: readout(card, state: state),
            fact: fact,
            compact: compactColumn,
            onOpen: { open(card) },
            onSeason: { seasonCard = card },
            onClub: { open(card) }
        ) {
            advanceKey(card, style: .light, onArt: true)
        }
    }

    @ViewBuilder
    private func animeAlsoWatching(_ cards: [HomeCard]) -> some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HomeAlsoWatchingHeading(count: cards.count, medium: mediumKind)
                HomeAlsoWatchingGrid(compact: compactColumn) {
                    ForEach(cards) { card in
                        let state = keyState(card)
                        HomeAlsoWatchingTile(
                            title: card.title,
                            posterURL: (card.coverImage ?? card.bannerImage).flatMap(URL.init(string:)),
                            material: material(card),
                            stamp: HomeSeasonTab.make(card),
                            readout: readout(card, state: state, onTile: true),
                            compact: compactColumn,
                            onOpen: { open(card) }
                        ) {
                            advanceKey(card, style: .material(material(card)), onArt: false)
                        }
                    }
                }
            }
            // 25 pt under the last scene (the opening block's 12 pt spacing plus 13), to the heading
            // row's 21 pt line box.
            .padding(.top, 13)
        }
    }

    // MARK: Manga ("Now reading" leaves: equal covers, the chapter count and the solid manga key)

    private func mangaLeaves(_ cards: [HomeCard]) -> some View {
        HomeMangaLeaves(cards: cards, containerWidth: contentWidth,
                        readout: { card in mangaReadout(card) },
                        onOpen: { open($0) }) { card in
            advanceKey(card, style: .dark)
        }
    }

    /// One leaf's "Ch. N" readout: the same count, caught-up rule and spoken label as the key.
    private func mangaReadout(_ card: HomeCard) -> HomeMangaLeafReadout {
        let state = keyState(card)
        return HomeMangaLeafReadout(label: state.label, caughtUp: state.caughtUp,
                                    spoken: progressSpoken(card, state: state))
    }

    // MARK: Progress and the advance key

    private struct KeyState {
        let progress: Int
        let label: String
        let cap: Int?
        let caughtUp: Bool
        let needsChoice: Bool
    }

    private func keyState(_ card: HomeCard) -> KeyState {
        let progress = home.displayedProgress(for: card)
        let label = home.displayedProgressLabel(medium: home.medium, mediaId: card.mediaId,
            serverLabel: card.progressLabel, lifecycleId: UUID(uuidString: card.lifecycleId)) ?? String(progress)
        let cap = mediumKind == .manga ? card.chapters : card.episodes
        // Both media: also caught up when every released unit is reached (the next episode has not
        // aired, the next chapter is not out), so Home never offers a +1 for an unreleased unit. The
        // same released count the opening line and the manga detail page's Up next read
        // (`availableUnits`: nil without a schedule, so an unknown count never reads caught up).
        let caughtUp = HomeShelfPolicy.homeKeyCaughtUp(progress: progress, total: cap, available: availableUnits(card))
        let unitId = home.displayedUnitId(medium: home.medium, mediaId: card.mediaId,
            serverUnitId: card.unitId, lifecycleId: UUID(uuidString: card.lifecycleId))
        return KeyState(progress: progress, label: label, cap: cap, caughtUp: caughtUp,
                        needsChoice: unitId != nil || Int(label) != progress)
    }

    /// The prototype readout's values for a scene or tile: "Ep." (or "Caught up" on a scene; a tile
    /// keeps "Ep.", as the prototype hides the completion word there), the count, the catalogue total
    /// when known, and how far along the scrub is. One caught-up string for the readout, the key and
    /// the spoken label (`KuroAdvanceCopy.caughtUpLabel`).
    private func readout(_ card: HomeCard, state: KeyState, onTile: Bool = false) -> HomeProgressReadout {
        let unit = mediumKind == .manga ? KuroLocale.text("Ch.", "Kap.") : KuroLocale.text("Ep.", "Folge")
        let fraction = state.cap.flatMap { $0 > 0 ? min(1, Double(state.progress) / Double($0)) : nil }
        return HomeProgressReadout(
            unit: state.caughtUp && !onTile ? KuroAdvanceCopy.caughtUpLabel(title: nil, german: KuroLocale.isGerman) : unit,
            value: state.label,
            total: state.cap,
            caughtUp: state.caughtUp,
            // A tile shows no total: caught up, its trace is full (everything out so far is watched),
            // as the prototype's tiles read; a scene keeps the catalogue fraction beside "N / total".
            fraction: onTile && state.caughtUp ? 1 : fraction,
            spoken: progressSpoken(card, state: state))
    }

    /// "Episode 7 of 26" / "Folge 7 von 26"; "Caught up" when there is nothing left.
    private func progressSpoken(_ card: HomeCard, state: KeyState) -> String {
        if state.caughtUp { return KuroAdvanceCopy.caughtUpLabel(title: nil, german: KuroLocale.isGerman) }
        let word = mediumKind == .manga ? KuroLocale.text("Chapter", "Kapitel") : KuroLocale.text("Episode", "Folge")
        guard let cap = state.cap, cap > 0 else { return "\(word) \(state.label)" }
        return KuroLocale.text("\(word) \(state.label) of \(cap)", "\(word) \(state.label) von \(cap)")
    }

    private func confirmationKey(_ card: HomeCard) -> String { "\(home.medium)|\(card.mediaId)" }

    /// The +1 key (shared `KuroAdvanceKey`): a sibling of the title's detail target, never nested.
    /// `onArt` set (anime scenes and tiles): a caught-up key is the prototype's disabled step, a quiet
    /// ✓ with no face. After a durable save (the displayed progress rose) the key plays its confirm /
    /// restore stamp; a refused or failed advance never stamps.
    @ViewBuilder
    private func advanceKey(_ card: HomeCard, style: KuroAdvanceKey.Style, onArt: Bool? = nil) -> some View {
        let origin = actionScope.capture(session: libraryActions.accountSession)
        let renderedMedium = home.medium
        let state = keyState(card)
        let phase: KuroAdvanceKey.Phase = state.needsChoice ? .needsChoice : (state.caughtUp ? .caughtUp : .advance)
        let label: String = {
            switch phase {
            case .needsChoice:
                return mediumKind == .manga
                    ? KuroLocale.text("Choose the next chapter of \(card.title)", "Nächstes Kapitel von \(card.title) auswählen")
                    : KuroLocale.text("Choose the next episode of \(card.title)", "Nächste Folge von \(card.title) auswählen")
            case .caughtUp:
                return KuroAdvanceCopy.caughtUpLabel(title: card.title, german: KuroLocale.isGerman)
            case .advance, .pending:
                return KuroAdvanceCopy.label(medium: mediumKind, nextUnit: state.progress + 1, title: card.title,
                                             current: state.progress, total: state.cap, german: KuroLocale.isGerman)
            }
        }()
        let stampKey = confirmationKey(card)
        if phase == .caughtUp, let onArt {
            HomeCaughtUpKey(onArt: onArt, accessibilityText: label)
        } else if phase == .caughtUp, style == .dark {
            // The manga leaf: the prototype's disabled light raised key (pale face, grey rule, thin ✓);
            // the solid #2b342e face is only the active +1 (`ref-home-quiet-manga-390.png`).
            HomeLeafCaughtUpKey(accessibilityText: label)
        } else {
            KuroAdvanceKey(style: style, phase: phase, accessibilityText: label,
                           confirmTrigger: confirmations[stampKey] ?? 0) {
                if state.needsChoice {
                    open(card)
                } else {
                    performTicketed(origin: origin) { ticket in
                        guard home.medium == renderedMedium else { return }
                        let before = home.displayedProgress(for: card)
                        await home.advance(card)
                        // The account can change during the save (`resetPresentationForAccount` clears the
                        // stamps): stamp only for the same presentation, medium, and a raised count.
                        let current = actionScope.isCurrent(ticket, session: libraryActions.accountSession)
                        guard HomeShelfPolicy.shouldStamp(
                            before: before, after: current ? home.displayedProgress(for: card) : before,
                            ticketCurrent: current, mediumUnchanged: home.medium == renderedMedium) else { return }
                        confirmations[stampKey, default: 0] += 1
                    }
                }
            }
        }
    }

    // MARK: Invitation (approved 2026-10-09; copy frozen)

    private var invitationActions: some View {
        VStack(alignment: .leading, spacing: 22) {
            invitationAction(
                kicker: KuroLocale.text("Find", "Finden"),
                title: KuroLocale.text("Your first title", "Deinen ersten Titel"),
                label: KuroLocale.text("Find your first title", "Finde deinen ersten Titel")
            ) {
                onFindTitle?(home.medium)
            }
            invitationAction(
                kicker: "Import",
                title: KuroLocale.text("Your list", "Deine Liste"),
                label: KuroLocale.text("Import your list", "Importiere deine Liste")
            ) {
                showImportChooser = true
            }
            if otherMediumOccupied {
                invitationAction(
                    kicker: mediumKind == .manga ? "Anime" : "Manga",
                    title: mediumKind == .manga
                        ? KuroLocale.text("Go to your anime", "Zu deinen Anime")
                        : KuroLocale.text("Go to your manga", "Zu deinen Manga"),
                    label: mediumKind == .manga
                        ? KuroLocale.text("Go to your anime", "Zu deinen Anime")
                        : KuroLocale.text("Go to your manga", "Zu deinen Manga")
                ) {
                    home.selectMedium(mediumKind == .manga ? "anime" : "manga")
                }
            }
        }
    }

    private func invitationAction(
        kicker: String,
        title: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(kicker)
                    .kuroKicker()
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title)
                        .font(.kuroTitle())
                        .foregroundStyle(Color.kuroInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.right")
                        .font(.kuroCustom(13, weight: .medium, relativeTo: .footnote, maxSize: 22))
                        .foregroundStyle(Color.kuroInk)
                        .accessibilityHidden(true)
                }
                Rectangle()
                    .fill(Color.kuroInk)
                    .frame(height: 1)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityLabel(label)
    }

    private var invitationCopy: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(KuroLocale.text("Your next story starts here.", "Deine nächste Geschichte beginnt hier."))
                .font(.kuroDisplay(weight: .light))
                .tracking(-0.8)
                .lineSpacing(-4)
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Rectangle()
                .fill(Color.kuroInk)
                .frame(width: 46, height: 2)
            Text(KuroLocale.text("Find something to watch or read, or bring the list you already have.",
                                 "Finde etwas zum Schauen oder Lesen, oder bring die Liste mit, die du schon hast."))
                .font(.kuroBody())
                .foregroundStyle(Color.kuroInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Coming up and the calendar (the account's release schedule, with certainty)

    private var scheduleItems: [ReleaseScheduleItem] {
        releases.scheduleItems(for: mediumKind)
    }

    /// The row's cover: the schedule's own, else the matching Home card's (fallback rows carry none).
    private func coverURL(for item: ReleaseScheduleItem) -> String? {
        if let own = item.coverImage, !own.isEmpty { return own }
        let card = home.bundle?.active.first { $0.mediaId == item.mediaId }
        return card?.coverImage ?? card?.bannerImage
    }

    /// What the schedule can claim for the selected medium (previews and snapshots: an answer).
    private var scheduleCoverage: ReleaseScheduleCoverage {
        skipNetworkLoad ? .complete : releases.scheduleCoverage(for: mediumKind)
    }

    private func comingUpLine(proxy: ScrollViewProxy) -> some View {
        let items = scheduleItems
        let offline = !network.isConnected
        let copy = ReleaseCopy.current()
        let coverage = scheduleCoverage
        let summary = HomeGlanceSummary.make(items: items, copy: copy, offline: offline, coverage: coverage,
                                             checked: scheduleChecked)
        let retry = scheduleChecked
            && HomeCalendarPresentation.offersRetry(items: items, copy: copy, offline: offline, coverage: coverage)
        let origin = actionScope.capture(session: libraryActions.accountSession)
        let glance = HomeComingUpGlance(summary: summary, compact: compactColumn) { item in
            coverURL(for: item).flatMap(URL.init(string:))
        }
        return VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
            if summary.linksToCalendar {
                Button {
                    if reduceMotion { proxy.scrollTo("upcoming-calendar", anchor: .top) }
                    else { withAnimation(KuroMotion.settle) { proxy.scrollTo("upcoming-calendar", anchor: .top) } }
                    calendarFocused = true
                } label: {
                    glance
                }
                .buttonStyle(HomeContactStyle())
                .accessibilityLabel(summary.spoken(german: copy.german))
                .accessibilityHint(KuroLocale.text("Shows the calendar", "Zeigt den Kalender"))
            } else {
                glance
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(summary.spoken(german: copy.german))
            }
            if retry {
                // Failed refresh (rulebook §9): scoped to this section, with the action that fixes it.
                Button {
                    perform(origin: origin) { await releases.loadSchedule(force: true) }
                } label: {
                    Text(KuroLocale.text("Try again", "Erneut versuchen"))
                        .font(.kuroMeta(weight: .medium))
                        .foregroundStyle(Color.kuroInk)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HomeContactStyle())
            }
        }
    }

    /// The prototype's calendar card (`HomeCalendarCard`: the "Coming up." heading and its summary, the
    /// day groups, "Dates to come"), only when it has rows or the schedule is still being asked (its
    /// in-place loading shape): an empty schedule is said once, by Coming up, never again under a
    /// second heading. The glance scrolls here and moves VoiceOver focus to it.
    @ViewBuilder
    private var calendarSection: some View {
        let groups = HomeCalendarPresentation.groups(scheduleItems, copy: ReleaseCopy.current())
        let coverage = scheduleCoverage
        if !groups.isEmpty || HomeCalendarCard.showsLoading(groups: groups, coverage: coverage) {
            HomeCalendarCard(groups: groups, coverage: coverage,
                             coverFor: { coverURL(for: $0) },
                             titleFor: { item in home.bundle?.active.first { $0.mediaId == item.mediaId }?.title ?? "" },
                             seasonFor: { item in seasonPrefix(for: item) },
                             medium: mediumKind)
                // 32 pt above the heading (the shelf's 24 pt spacing plus 8).
                .padding(.top, 8)
                // The paper feed's 22 pt side padding (18 on small phones): 2 pt inside the gutter.
                .padding(.horizontal, HomeFeedInsets.feed)
                .id("upcoming-calendar")
                .accessibilityFocused($calendarFocused)
        }
    }

    /// "S2" for an anime row whose title's season number Home holds (the card's ladder section);
    /// nil for manga and when the number is unknown (never "S1" by default).
    private func seasonPrefix(for item: ReleaseScheduleItem) -> String? {
        guard item.medium == .anime,
              let card = home.bundle?.active.first(where: { $0.mediaId == item.mediaId }),
              let tab = HomeSeasonTab.make(card), tab.word != nil else { return nil }
        return "S\(tab.number)"
    }

    // MARK: Private club room (only with real clubs and real, authorized notes)

    /// The prototype's club room (`HomeClubRoom`) for the club with the latest real activity
    /// (`HomeClubRoom.pick` over `ClubsStore.myClubs`); nothing without one. Notes come from Home's club
    /// slice and are shown only when the reader has one club (`roomNotes`: the slice carries no club
    /// id), so "Couldn't load club notes." is said only then. A failed clubs read with no club known is
    /// the branded failure (or offline), never "no clubs".
    @ViewBuilder
    private func clubSection(origin: AccountActionScope.Ticket?) -> some View {
        let rows = clubs.myClubs.compactMap { ClubSummary(row: $0) }
        let clubCount = rows.count
        let slice = home.bundle?.club
        let readFailure: (failed: Bool, transport: Bool) = {
            if case .failed(let transport) = clubs.myClubsPhase.settled { return (true, transport) }
            return (false, false)
        }()
        let offline = readFailure.transport || !network.isConnected
        let presentation = HomeClubRoom.presentation(
            picked: HomeClubRoom.pick(clubs: rows), clubsReadFailed: readFailure.failed,
            notesFailed: slice?.state == "error" && clubCount <= 1, offline: offline)
        switch presentation {
        case .hidden:
            EmptyView()
        case .room(let club, let notesFailed):
            HomeClubRoom(club: club, notes: roomNotes(slice, club: club, clubCount: clubCount),
                         otherClubCount: max(0, clubCount - 1), medium: mediumKind,
                         notesFailed: notesFailed, notesOffline: notesFailed && !network.isConnected,
                         onRetry: { perform(origin: origin) { await home.load() } },
                         onOpenClubs: onOpenClubs)
                // `.club-room` margin 32/-5/0: 32 pt under the calendar (the shelf's 24 + 8) and 5 pt
                // past the paper feed on each side (3 pt past the page gutter).
                .padding(.top, 8)
                .padding(.horizontal, HomeFeedInsets.room)
        case .failed, .offline:
            HomeClubRoomFailure(medium: mediumKind, offline: presentation == .offline) {
                perform(origin: origin) { await clubs.fetchMyClubs() }
            }
        }
    }

    /// The room's notes with the title and cover Home holds for each (either medium's page).
    private func roomNotes(_ slice: HomeClubSlice?, club: ClubSummary, clubCount: Int) -> [HomeClubRoom.Note] {
        HomeClubRoom.roomNotes(slice?.items ?? [], club: club, clubCount: clubCount).map { item in
            let manga = item.mediaType.lowercased() == "manga"
            let card = (manga ? home.manga : home.anime)?.active.first { $0.mediaId == item.mediaId }
            return HomeClubRoom.Note(item: item, title: card?.title, coverImage: card?.coverImage ?? card?.bannerImage)
        }
    }

    // MARK: Helpers

    private func open(_ card: HomeCard) {
        routes.openMedia(MediaRoute(kind: mediumKind, id: card.mediaId))
    }

    @ViewBuilder
    private func cover(_ raw: String?) -> some View {
        if let raw, let url = URL(string: raw) {
            KuroCachedAsyncImage(url: url, maxPixelSize: 800) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Color.kuroMissingArt
                }
            }
        } else {
            Color.kuroMissingArt
        }
    }
}

/// The prototype's paper feed sits 2 pt inside Home's gutter (22 pt at 390/430, 18 pt at 320, the
/// `.paper-feed` padding 0/22/20); the club room bleeds 5 pt past the feed (`margin 32/-5/0`).
enum HomeFeedInsets {
    static let feed: CGFloat = 2
    static let room: CGFloat = -3
}

/// ScrollPosition alone discards its absolute point after a user drag. Keep the observed
/// offset in the account-keyed parent; each medium restores its own offset on remount.
private struct HomeMediumScroll<Content: View>: View {
    @Binding var offset: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var position = ScrollPosition(edge: .top)
    @State private var restored = false
    var body: some View {
        ScrollView { content() }
            .scrollContentBackground(.hidden)
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, value in
                if restored { offset = value }
            }
            .task {
                position.scrollTo(y: offset)
                restored = true
            }
    }
}

// Shared by Home and the season detail so the exact artwork material uses one parser.
extension Color {
    init?(hexString: String?) {
        guard var raw = hexString?.trimmingCharacters(in: .whitespacesAndNewlines), raw.hasPrefix("#"), raw.count == 7 else { return nil }
        raw.removeFirst()
        guard Int(raw, radix: 16) != nil else { return nil }
        self.init(hex: raw)
    }
}

/// A small amount of contact feedback (120 ms); Reduce Motion keeps the control stationary.
struct HomeContactStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : KuroMotion.contact, value: configuration.isPressed)
    }
}

/// The season overview opened from the artwork's season tab. Inspecting a season never changes
/// progress.
private struct HomeSeasonOverview: View {
    let card: HomeCard
    @Environment(HomeStore.self) private var home
    @Environment(\.kuroRoutes) private var routes
    @State private var detail: SeriesDetailBundle?
    @State private var failed = false
    /// The season read is not deployed (or answers another contract): seasons are not grouped yet.
    @State private var notGrouped = false
    @State private var attempt = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                Text(card.title)
                    .font(.kuroFeature())
                    .foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
                KuroSectionHeader(KuroLocale.text("Seasons", "Staffeln"), size: .title)
                if notGrouped {
                    notGroupedState
                } else if let detail {
                    if detail.sections.isEmpty {
                        notGroupedState
                    }
                    ForEach(detail.sections) { section in
                        ForEach(section.entries ?? []) { entry in
                            seasonRow(section: section, entry: entry)
                        }
                    }
                } else if failed {
                    KuroStateView(.failed(hasCachedContent: false),
                                  title: KuroLocale.text("Couldn't load the seasons.", "Die Staffeln konnten nicht geladen werden."),
                                  layout: .inline) { attempt += 1 }
                } else {
                    KuroStateView(.loading, layout: .inline)
                }
            }
            .padding(KuroDesignSpacing.padding)
            .kuroReadableWidth()
        }
        .background(Color.kuroCanvasPage)
        .tint(Color.kuroInk)
        .task(id: "\(home.privacyEpoch)|\(attempt)") {
            let epoch = home.privacyEpoch
            #if canImport(Supabase)
            do {
                let loaded = try await home.detailBundle(medium: "anime", mediaId: card.mediaId, sectionId: nil)
                guard epoch == home.privacyEpoch, !Task.isCancelled else { return }
                detail = loaded
                failed = false
                notGrouped = false
            }
            catch is CancellationError {} catch {
                guard epoch == home.privacyEpoch, !Task.isCancelled else { return }
                // A missing contract is not a failure a Retry could fix (spec §3.4): say what is true.
                switch ReleaseFailure.classify(error) {
                case .cancelled: return
                case .notDeployed: notGrouped = true; failed = false
                case .transient: failed = true
                }
            }
            #endif
        }
        .onChange(of: home.privacyEpoch) { _, _ in detail = nil; failed = false; notGrouped = false }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var notGroupedState: some View {
        Text(KuroLocale.text("Seasons aren't grouped for this title yet.",
                             "Für diesen Titel sind noch keine Staffeln zusammengestellt."))
            .font(.kuroBody())
            .foregroundStyle(Color.kuroInkSecondary)
            .fixedSize(horizontal: false, vertical: true)
        KuroInkButton(KuroLocale.text("Open title", "Titel öffnen"), role: .secondary) {
            routes.openMedia(MediaRoute(kind: .anime, id: card.mediaId))
        }
    }

    private func seasonRow(section: SeriesDetailBundle.Section, entry: SeriesDetailBundle.Section.Entry) -> some View {
        let isCurrent = entry.mediaId == card.mediaId
        return Button { routes.openMedia(MediaRoute(kind: .anime, id: entry.mediaId)) } label: {
            HStack(spacing: 12) {
                if let raw = entry.bannerImage ?? entry.coverImage, let url = URL(string: raw) {
                    KuroCachedAsyncImage(url: url, maxPixelSize: 600) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFill() }
                        else { Color.kuroMissingArt }
                    }
                    .frame(width: 96, height: 54)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.name)
                        .font(.kuroBody(weight: .medium))
                        .foregroundStyle(Color.kuroInk)
                    if let episodes = entry.episodes {
                        Text(episodes == 1 ? KuroLocale.text("1 episode", "1 Folge")
                                           : KuroLocale.text("\(episodes) episodes", "\(episodes) Folgen"))
                            .font(.kuroMeta())
                            .foregroundStyle(Color.kuroInkSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isCurrent {
                    Image(systemName: "bookmark.fill")
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroInk)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 64)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.kuroHairline).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityLabel(isCurrent
            ? KuroLocale.text("\(section.name), the one you're watching", "\(section.name), die du gerade schaust")
            : section.name)
    }
}
