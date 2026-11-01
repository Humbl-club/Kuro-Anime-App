import KuroCore
import KuroLibrary
import SwiftUI

/// Accepted Home (rulebook §14.1), composed as the prototype's Poster Home (prototype-fidelity Task 4,
/// `ref-home-{busy,full,undated,quiet}-anime-390.png`, PROTOTYPE_SPEC.md §4): the medium switch with the
/// lead title's artwork clipped into the selected word, the Coming up glance, the opening line (with
/// the caught-up quiet card), two anime scene cards on their artwork material, a 2-column Also
/// watching grid, then quiet rows for planned titles, the calendar and the private club room only
/// when real notes exist. Suggestions stay on Taste.
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
    @State private var actionScope = AccountActionScope()
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
    @State private var calendarExpansion: [String: Bool] = [:]
    @State private var expandedDayItems: Set<String> = []
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

    init(skipNetworkLoad: Bool = false, onOpenImport: (() -> Void)? = nil,
         onFindTitle: ((String) -> Void)? = nil,
         onOpenCollection: (() -> Void)? = nil,
         onImportNavigation: ((ImportResultDestination) -> Void)? = nil) {
        self.skipNetworkLoad = skipNetworkLoad
        self.onOpenImport = onOpenImport
        self.onFindTitle = onFindTitle
        self.onOpenCollection = onOpenCollection
        self.onImportNavigation = onImportNavigation
        self._scheduleChecked = State(initialValue: skipNetworkLoad)
    }

    var body: some View {
        ScrollViewReader { proxy in
            HomeMediumScroll(offset: scrollBinding) {
                VStack(alignment: .leading, spacing: 12) {
                    mediumSwitch
                    importRecoveryBanner
                    shelfBody(proxy: proxy)
                }
                .padding(.horizontal, gutter)
                .padding(.top, 7)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, minHeight: shelfScene == .invitation ? invitationHeight : 0, alignment: .topLeading)
                .kuroReadableWidth()
            }
            .id(home.medium)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { containerSize = $0 }
        }
        .background(Color.clear)
        .tint(Color.kuroInk)
        .onAppear {
            resetPresentationForAccount()
            actionScope.activate(session: libraryActions.accountSession)
        }
        .onChange(of: home.privacyEpoch) { _, _ in resetPresentationForAccount() }
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
        calendarExpansion = [:]; expandedDayItems = []; calendarFocused = false
        // The new account's schedule is not known yet: "Checking dates", never "Nothing scheduled".
        scheduleChecked = skipNetworkLoad
        inProgressPages = [:]; pagingForInProgress = false
        confirmations = [:]
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

    /// The prototype's switch (PROTOTYPE_SPEC.md §4 "Medium switch"): two equal columns 12 pt apart over
    /// a 1 pt `#20302744` hairline; heavy sans uppercase words (36 pt, 30 on phones ≤ 360 pt, tracking
    /// −1.9 / −1.55); the selected word shows the lead title's artwork clipped into its letters with
    /// a 28 × 2 `#203027` rule on the hairline; the other word is solid `#6e786f`. The artwork fill
    /// keeps a contrast floor (`HomeMediumWordInk`), so it never reads lighter than the unselected word.
    private var mediumSwitch: some View {
        // At accessibility sizes the words stack, so each keeps the full width and neither is cut to
        // "Ma…" (rulebook §4).
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: 12))
        return layout {
            mediumButton("anime", title: "Anime", stacked: stacked)
            mediumButton("manga", title: "Manga", stacked: stacked)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(HomeInk.switchHairline).frame(height: 1).accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }

    private func mediumButton(_ value: String, title: String, stacked: Bool) -> some View {
        let selected = home.medium == value
        let size = KuroMediumSwitch.wordSize(for: .large, containerWidth: contentWidth)
        let lettering = Text(title)
            .kuroMediumWordStyle(size: size)
            .lineLimit(1)
            // The single-word switch is the one place a scale factor is allowed (rulebook §4).
            .minimumScaleFactor(0.6)
        return Button {
            if !selected { KuroAccessibility.impactHaptic(.light); home.selectMedium(value) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // The fill takes the word's own frame (an overlay), so the artwork never sizes the row.
                lettering
                    .foregroundStyle(selected ? Color.clear : HomeInk.switchUnselected)
                    .overlay {
                        if selected {
                            HomePagePictureFill(fallback: shelfScene == .invitation ? .mountain : .solid)
                                .mask(lettering)
                        }
                    }
                    .padding(.top, 4)
                Spacer(minLength: 4)
                // A fixed rule that fades in place on the hairline: it never travels between the words.
                Rectangle()
                    .fill(HomeInk.switchMark)
                    .frame(width: 28, height: 2)
                    .opacity(selected ? 1 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: stacked ? 52 : 56, alignment: .leading)
            .padding(.bottom, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(title)
        .accessibilityHint(selected ? "" : KuroLocale.text("Shows your \(title.lowercased()).", "Zeigt deine \(title)-Titel."))
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
        if shelfScene == .invitation {
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
                    }
                }
            }
            if !split.inProgress.isEmpty, mediumKind == .manga {
                // Covers are sized from the measured column: wait for the first measurement.
                if containerSize.width > 0 {
                    mangaLibrary(split.inProgress)
                } else {
                    sceneLoadingShape
                }
            } else if split.inProgress.isEmpty, awaitingInProgress {
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
            clubSection
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
                HStack(alignment: .top, spacing: KuroDesignSpacing.md) {
                    ForEach(0..<2, id: \.self) { _ in KuroSkeleton(kind: .coverLeaf) }
                }
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

    /// What the opening line may claim: titles with a released unit the reader has not reached, and
    /// whether every lead title is known to be caught up (the quiet card). Anime counts the two scene
    /// titles, as the prototype; manga counts every book in progress.
    private func openingState(_ inProgress: [HomeCard]) -> (available: Int, caughtUp: Bool) {
        let lead = mediumKind == .manga ? inProgress : HomeShelfPolicy.scenes(inProgress).scenes
        guard !lead.isEmpty else { return (0, false) }
        var available = 0
        var allCaughtUp = true
        for card in lead {
            let progress = home.displayedProgress(for: card)
            let units = availableUnits(card)
            if HomeShelfPolicy.hasNewUnit(progress: progress, available: units, catalogueStatus: card.catalogueStatus) {
                available += 1
            }
            if !HomeShelfPolicy.isKnownCaughtUp(progress: progress, available: units) { allCaughtUp = false }
        }
        return (available, allCaughtUp)
    }

    /// Club members who wrote about this title (real display names only, never invented).
    private func clubNames(_ card: HomeCard) -> [String] {
        var names: [String] = []
        for item in home.bundle?.club.items ?? [] where item.mediaId == card.mediaId {
            guard let name = item.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  !names.contains(name) else { continue }
            names.append(name)
        }
        return names
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
            knownCaughtUp: HomeShelfPolicy.isKnownCaughtUp(progress: state.progress, available: units),
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
                            readout: readout(card, state: state),
                            compact: compactColumn,
                            onOpen: { open(card) }
                        ) {
                            advanceKey(card, style: .material(material(card)), onArt: false)
                        }
                    }
                }
            }
            // 25 pt under the last scene (the opening block's 12 pt spacing plus 13).
            .padding(.top, 13)
        }
    }

    // MARK: Manga (equal covers, each book's own chapter ticket and dark raised key)

    /// Two columns on phones (D5), more on a wide column; every frame equal (rulebook §6).
    private var mangaSpacing: CGFloat { contentWidth < 300 ? 14 : 20 }

    private var mangaColumns: Int {
        let spacing = mangaSpacing
        let minCover: CGFloat = 150
        return max(2, Int((contentWidth + spacing) / (minCover + spacing)))
    }

    private func mangaLibrary(_ cards: [HomeCard]) -> some View {
        let columns = mangaColumns
        let spacing = mangaSpacing
        let columnWidth = max(100, (contentWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: columns),
            alignment: .leading,
            spacing: 26
        ) {
            ForEach(cards) { card in mangaBook(card, columnWidth: columnWidth) }
        }
    }

    private func mangaBook(_ card: HomeCard, columnWidth: CGFloat) -> some View {
        // The cover fills an equal 0.7 frame (top-biased crop); the paper edge peeks 5 pt behind it.
        let artWidth = max(80, columnWidth - 5)
        let artHeight = (artWidth / KuroCardMetrics.imageAspectRatio).rounded()
        return VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.kuroHairline, lineWidth: 1)
                    .background(Color.kuroWhite)
                    .padding(.leading, 5)
                    .padding(.top, 5)
                    .padding(.bottom, 24)
                Button { open(card) } label: {
                    mangaArt(card.coverImage)
                        .frame(width: artWidth, height: artHeight, alignment: .top)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(HomeContactStyle())
                .accessibilityLabel(KuroLocale.text("Open \(card.title)", "\(card.title) öffnen"))
                chapterTicket(card)
                    .padding(.horizontal, 9)
            }
            Button { open(card) } label: {
                Text(card.title)
                    .font(.kuroBody(weight: .medium))
                    .tracking(-0.3)
                    .foregroundStyle(Color.kuroInk)
                    .multilineTextAlignment(.leading)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HomeContactStyle())
            .accessibilityHidden(true) // The cover button above carries "Open <title>".
        }
    }

    private func chapterTicket(_ card: HomeCard) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 9, topTrailingRadius: 3)
        // At accessibility sizes the readout sits above the key so a four-digit chapter never truncates
        // in a 137 pt column (320 pt phone, two columns).
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            progressReadout(card, large: true)
            if !stacked { Spacer(minLength: 4) }
            advanceKey(card, style: .dark)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        .padding(.trailing, 3)
        .padding(.vertical, 6)
        .frame(minHeight: 56)
        .background(Color.kuroWhite)
        .overlay(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.kuroKeyRim, lineWidth: 1)
                .background(Color.kuroWhite)
                .frame(width: 13, height: 4)
                .offset(x: -14, y: -4)
                .accessibilityHidden(true)
        }
        .clipShape(shape)
        .overlay(shape.stroke(Color.kuroKeyRim, lineWidth: 1))
        .shadow(color: Color.kuroInk.opacity(0.06), radius: 2, y: 1)
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
        let caughtUp = cap.map { progress >= $0 } ?? false
        let unitId = home.displayedUnitId(medium: home.medium, mediaId: card.mediaId,
            serverUnitId: card.unitId, lifecycleId: UUID(uuidString: card.lifecycleId))
        return KeyState(progress: progress, label: label, cap: cap, caughtUp: caughtUp,
                        needsChoice: unitId != nil || Int(label) != progress)
    }

    private func progressReadout(_ card: HomeCard, large: Bool) -> some View {
        let state = keyState(card)
        let unit = mediumKind == .manga ? KuroLocale.text("Ch.", "Kap.") : KuroLocale.text("Ep.", "F.")
        return VStack(alignment: .leading, spacing: 1) {
            Text(state.caughtUp ? KuroLocale.text("Caught up", "Aktuell") : unit)
                .font(.kuroCustom(11, relativeTo: .caption1, maxSize: 20))
                .foregroundStyle(Color.kuroInkQuiet)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(state.caughtUp ? " " : state.label)
                    .font(.kuroCustom(large ? 28 : 19, relativeTo: large ? .title1 : .title3, maxSize: large ? 36 : 30))
                    .tracking(large ? -0.9 : -0.4)
                    .monospacedDigit()
                    .lineLimit(1)
                if let cap = state.cap, mediumKind == .anime, !state.caughtUp {
                    Text("/ \(cap)")
                        .font(.kuroCustom(12, relativeTo: .caption1, maxSize: 20))
                        .foregroundStyle(Color.kuroInkQuiet)
                }
            }
            .foregroundStyle(Color.kuroInk)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progressSpoken(card, state: state))
    }

    /// The prototype readout's values for a scene or tile: "Ep." (or "Caught up"), the count, the
    /// catalogue total when known, and how far along the scrub is.
    private func readout(_ card: HomeCard, state: KeyState) -> HomeProgressReadout {
        let unit = mediumKind == .manga ? KuroLocale.text("Ch.", "Kap.") : KuroLocale.text("Ep.", "Folge")
        let fraction = state.cap.flatMap { $0 > 0 ? min(1, Double(state.progress) / Double($0)) : nil }
        return HomeProgressReadout(
            unit: state.caughtUp ? KuroLocale.text("Caught up", "Aktuell") : unit,
            value: state.label,
            total: state.cap,
            caughtUp: state.caughtUp,
            fraction: fraction,
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
        } else {
            KuroAdvanceKey(style: style, phase: phase, accessibilityText: label,
                           confirmTrigger: confirmations[stampKey] ?? 0) {
                if state.needsChoice {
                    open(card)
                } else {
                    perform(origin: origin) {
                        guard home.medium == renderedMedium else { return }
                        let before = home.displayedProgress(for: card)
                        await home.advance(card)
                        guard home.medium == renderedMedium, home.displayedProgress(for: card) > before else { return }
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

    private func calendarArt(_ items: [ReleaseScheduleItem]) -> some View {
        HStack(spacing: -7) {
            ForEach(Array(items.prefix(3))) { item in
                cover(coverURL(for: item)).frame(width: 27, height: 38).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.kuroWhite, lineWidth: 1))
            }
        }.accessibilityHidden(true)
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

    /// The full calendar, only when it has rows: an empty schedule is said once, by Coming up, never
    /// again under a second heading.
    @ViewBuilder
    private var calendarSection: some View {
        let copy = ReleaseCopy.current()
        let groups = HomeCalendarPresentation.groups(scheduleItems, copy: copy)
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                KuroSectionHeader(KuroLocale.text("Calendar.", "Kalender."), size: .title)
                    .accessibilityFocused($calendarFocused)
                VStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, day in
                        calendarDay(day, initiallyOpen: index == 0)
                    }
                }
            }
            .id("upcoming-calendar")
            .accessibilityElement(children: .contain)
        }
    }

    private func calendarBinding(_ id: String, initiallyOpen: Bool) -> Binding<Bool> {
        let key = home.medium + "|" + id
        return Binding(get: { calendarExpansion[key] ?? initiallyOpen }, set: { calendarExpansion[key] = $0 })
    }

    private func releaseCount(_ count: Int) -> String {
        count == 1
            ? KuroLocale.text("1 release", "1 Termin")
            : KuroLocale.text("\(count) releases", "\(count) Termine")
    }

    private func calendarDay(_ day: HomeCalendarDay, initiallyOpen: Bool) -> some View {
        let key = home.medium + "|" + day.id
        let all = expandedDayItems.contains(key)
        let hidden = day.items.count - 3
        return DisclosureGroup(isExpanded: calendarBinding(day.id, initiallyOpen: initiallyOpen)) {
            ForEach(Array(day.items.prefix(all ? day.items.count : 3))) { item in calendarEvent(item) }
            if hidden > 0 {
                Button {
                    if all { expandedDayItems.remove(key) } else { expandedDayItems.insert(key) }
                } label: {
                    Text(all
                         ? KuroLocale.text("Show fewer", "Weniger zeigen")
                         : KuroLocale.text("Show \(hidden) more", "\(hidden) weitere zeigen"))
                        .font(.kuroMeta(weight: .medium))
                        .foregroundStyle(Color.kuroInk)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HomeContactStyle())
            }
        } label: {
            HStack(spacing: 12) {
                VStack(spacing: 1) {
                    Text(day.day).font(.kuroTitle()).monospacedDigit()
                    if !day.month.isEmpty {
                        Text(day.month).font(.kuroCustom(11, relativeTo: .caption1, maxSize: 18))
                    }
                }
                .foregroundStyle(Color.kuroInk)
                .frame(minWidth: 36)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(day.label)
                        .font(.kuroBody(weight: .medium))
                        .foregroundStyle(Color.kuroInk)
                    Text(releaseCount(day.items.count))
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroInkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !dynamicTypeSize.isAccessibilitySize { calendarArt(day.items) }
            }
            .frame(minHeight: 60)
            .accessibilityElement(children: .combine)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.kuroHairline).frame(height: 0.5) }
    }

    private func calendarEvent(_ item: ReleaseScheduleItem) -> some View {
        Button { routes.openMedia(MediaRoute(kind: item.medium, id: item.mediaId)) } label: {
            HStack(spacing: 10) {
                cover(coverURL(for: item)).frame(width: 32, height: 48).clipped().accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title.isEmpty ? (home.bundle?.active.first { $0.mediaId == item.mediaId }?.title ?? "") : item.title)
                        .font(.kuroBody(weight: .medium))
                        .foregroundStyle(Color.kuroInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    KuroReleaseLine(item, undatedFallback: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 44)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(HomeContactStyle())
    }

    // MARK: Private club room (only with real, authorized notes)

    @ViewBuilder
    private var clubSection: some View {
        let club = home.bundle?.club
        if club?.state == "error" {
            Text(KuroLocale.text("Couldn't load club notes.", "Club-Notizen konnten nicht geladen werden."))
                .font(.kuroMeta())
                .foregroundStyle(Color.kuroInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let club, !club.items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(KuroLocale.text("Your private club", "Euer privater Club"))
                    .font(.kuroMicro(weight: .medium))
                    .tracking(2.1)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.kuroRoomTextSecondary)
                // The server's own label, or the section's name. Never an invented club name.
                Text(club.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? KuroLocale.text("Between us.", "Unter uns.")
                     : club.label)
                    .font(.kuroTitle())
                    .foregroundStyle(Color.kuroRoomText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                ForEach(club.items) { item in
                    clubNote(item)
                }
            }
            .padding(KuroDesignSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.kuroRoom, in: RoundedRectangle(cornerRadius: KuroRadius.md))
        }
    }

    private func clubNote(_ item: HomeClubItem) -> some View {
        let kind: MediaKind = item.mediaType.lowercased() == "manga" ? .manga : .anime
        let art = home.bundle?.active.first { $0.mediaId == item.mediaId && kind == mediumKind }
        let hidden = item.spoilerScope != nil && item.spoilerScope != "none" && item.text == nil
        return Button {
            routes.openMedia(MediaRoute(kind: kind, id: item.mediaId))
        } label: {
            HStack(alignment: .top, spacing: 12) {
                cover(art?.coverImage)
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? 40 : 60,
                           height: dynamicTypeSize.isAccessibilitySize ? 60 : 90)
                    .clipped()
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.displayName ?? KuroLocale.text("A club member", "Ein Clubmitglied"))
                        .font(.kuroMeta(weight: .semibold))
                        .foregroundStyle(Color.kuroRoomText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(hidden ? KuroLocale.text("Spoiler hidden", "Spoiler verborgen") : (item.text ?? ""))
                        .font(.kuroBody())
                        .foregroundStyle(hidden ? Color.kuroRoomTextSecondary : Color.kuroRoomText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.kuroWhite15).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityHint(KuroLocale.text("Opens this title's private discussion", "Öffnet die private Diskussion zu diesem Titel"))
    }

    // MARK: Helpers

    @ViewBuilder private func mangaArt(_ raw: String?) -> some View {
        if let raw, let url = URL(string: raw) {
            KuroCachedAsyncImage(url: url, maxPixelSize: 800) { phase in
                // Top-biased crop into the equal cover frame (rulebook §6).
                if case .success(let image) = phase { image.resizable().scaledToFill() }
                else { Color.kuroMissingArt }
            }
        } else { Color.kuroMissingArt }
    }

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
