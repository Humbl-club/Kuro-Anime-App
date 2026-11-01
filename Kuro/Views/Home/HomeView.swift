import KuroCore
import KuroLibrary
import SwiftUI

/// Accepted Home (rulebook §14.1): Poster medium switch, the Coming up glance, shallow anime scenes or
/// equal manga covers for the titles in progress, a quiet row for planned titles, the calendar, and the
/// private club room only when real notes exist. Suggestions stay on Taste.
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
    @State private var actionScope = AccountActionScope()
    @Environment(\.kuroRoutes) private var routes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
                VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                    mediumSwitch
                    importRecoveryBanner
                    shelfBody(proxy: proxy)
                }
                .padding(.horizontal, gutter)
                .padding(.top, 12)
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
            await releases.loadSchedule()
            scheduleChecked = true
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

    // MARK: Medium switch (approved Poster switch: the selected word masks the Home picture)

    private var mediumSwitch: some View {
        HStack(alignment: .bottom, spacing: 18) {
            mediumButton("anime", title: "Anime")
            mediumButton("manga", title: "Manga")
        }
        .accessibilityElement(children: .contain)
    }

    private func mediumButton(_ value: String, title: String) -> some View {
        let selected = home.medium == value
        let base: CGFloat = dynamicTypeSize.isAccessibilitySize ? 32 : 40
        // The same scaled, capped size drives the lettering and the frames around it.
        let size = min(KuroTypeScale.current.scaled(base, relativeTo: .largeTitle), 48)
        let lettering = Text(title)
            .font(.kuroCustom(base, weight: .heavy, design: .serif, relativeTo: .largeTitle, maxSize: 48))
            .tracking(-1.1)
            .lineLimit(1)
            // The single-word switch is the one place a scale factor is allowed (rulebook §4).
            .minimumScaleFactor(0.6)
        return Button {
            if !selected { KuroAccessibility.impactHaptic(.light); home.selectMedium(value) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .leading) {
                    lettering.foregroundStyle(selected ? Color.clear : (shelfScene == .invitation ? Color.kuroInk : Color.kuroInkQuiet))
                    if selected {
                        if shelfScene == .invitation {
                            lettering
                                .foregroundStyle(Color.kuroWhite92)
                                .offset(x: 0.7, y: 0.8)
                        }
                        HomePagePictureFill()
                            .frame(height: size + 10)
                            .mask(lettering.frame(maxWidth: .infinity, alignment: .leading))
                    }
                }
                .frame(height: size + 4, alignment: .leading)
                Rectangle()
                    .fill(selected ? Color.kuroInk : Color.clear)
                    .frame(width: selected ? 46 : 0, height: 2)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
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
            populatedShelf(proxy: proxy)
            shelfStatus(origin: origin, renderedMedium: renderedMedium)
        }
    }

    /// Stable geometry while the first page loads (rulebook §9): the glance, one scene, two rows.
    private var loadingShelf: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
            RoundedRectangle(cornerRadius: 2).fill(Color.kuroBlack05).frame(height: 56)
            RoundedRectangle(cornerRadius: 5).fill(Color.kuroBlack05)
                .aspectRatio(mediumKind == .manga ? 1.4 : 2.4, contentMode: .fit)
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: KuroDesignSpacing.md) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.kuroBlack05).frame(width: 44, height: 66)
                    RoundedRectangle(cornerRadius: 2).fill(Color.kuroBlack05).frame(height: 18)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KuroLocale.text("Loading your Home", "Dein Home wird geladen"))
    }

    private func populatedShelf(proxy: ScrollViewProxy) -> some View {
        let split = HomeShelfPolicy.partition(home.bundle?.active ?? [])
        return VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
            comingUpLine(proxy: proxy)
            if !split.inProgress.isEmpty {
                if mediumKind == .manga {
                    mangaLibrary(split.inProgress)
                } else {
                    animeScenes(Array(split.inProgress.prefix(2)))
                    animeAlsoWatching(Array(split.inProgress.dropFirst(2)))
                }
            } else if shelfScene != .inProgress {
                restingBand(hasPlanned: !split.planned.isEmpty || !split.saved.isEmpty)
            }
            quietShelf(title: KuroLocale.text("Planned", "Geplant"), cards: split.planned)
            quietShelf(title: KuroLocale.text("Saved", "Gespeichert"), cards: split.saved)
            calendarSection
            clubSection
        }
    }

    /// Nothing in progress in this medium: the saved shelf, never "you have nothing" (rulebook §9).
    private func restingBand(hasPlanned: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(hasPlanned
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

    /// Planned (and other saved) titles: a picture, the title, one tap to its page. No +1 key.
    @ViewBuilder
    private func quietShelf(title: String, cards: [HomeCard]) -> some View {
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
                    .accessibilityLabel(KuroLocale.text("Open \(card.title)", "\(card.title) öffnen"))
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
                if status == LibraryProgressMessage.savedOnDevice,
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
        if home.bundle?.nextCursor?.isEmpty == false {
            KuroInkButton(KuroLocale.text("More titles", "Weitere Titel"), role: .secondary) {
                perform(origin: origin) { await home.loadMore() }
            }
        }
    }

    // MARK: Anime

    private func animeScenes(_ cards: [HomeCard]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(cards) { card in animeScene(card) }
        }
    }

    private func animeScene(_ card: HomeCard) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Button { open(card) } label: {
                    Color.clear
                        .aspectRatio(3.15, contentMode: .fit)
                        .overlay { sceneStill(card) }
                        .clipped()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(KuroLocale.text("Open \(card.title)", "\(card.title) öffnen"))
                seasonTab(card)
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 5))
            sceneFoot(card)
                .background(Color.kuroWhite)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .shadow(color: Color.kuroInk.opacity(0.06), radius: 2, y: 1)
    }

    /// The white ink foot: title left, "Ep. N / total" and the light raised key right. At
    /// accessibility sizes the readout and key move under the title instead of squeezing it.
    @ViewBuilder
    private func sceneFoot(_ card: HomeCard) -> some View {
        let title = Button { open(card) } label: {
            Text(card.title)
                .font(.kuroTitleName())
                .tracking(-0.35)
                .foregroundStyle(Color.kuroInk)
                .multilineTextAlignment(.leading)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(KuroLocale.text("Open \(card.title)", "\(card.title) öffnen"))
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                title
                HStack {
                    progressReadout(card, large: false)
                    Spacer(minLength: KuroDesignSpacing.sm)
                    advanceKey(card, style: .light)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, KuroDesignSpacing.sm)
        } else {
            HStack(alignment: .center, spacing: 0) {
                title
                    .padding(.leading, 12)
                Rectangle().fill(Color.kuroHairline).frame(width: 1, height: 36)
                progressReadout(card, large: false)
                    .padding(.leading, 10)
                    .padding(.trailing, 6)
                advanceKey(card, style: .light)
                    .padding(.trailing, 6)
            }
            .frame(minHeight: 64)
        }
    }

    /// White "Season N" tab on the main artwork (approved 2026-10-02). Opening it never changes progress.
    @ViewBuilder
    private func seasonTab(_ card: HomeCard) -> some View {
        if let season = card.seasonTitle {
            let isFilm = card.sectionKind == "film"
            Button { seasonCard = card } label: {
                VStack(alignment: .leading, spacing: 0) {
                    if !isFilm, card.sectionOrdinal != nil {
                        Text(KuroLocale.text("Season", "Staffel"))
                            .font(.kuroMicro(weight: .semibold))
                            .tracking(0.6)
                            .textCase(.uppercase)
                    }
                    Text(isFilm ? "Film" : (card.sectionOrdinal.map(String.init) ?? season))
                        .font(.kuroCustom(17, design: .serif, relativeTo: .headline, maxSize: 28))
                        .lineLimit(1)
                }
                .foregroundStyle(Color.kuroInk)
                .padding(.horizontal, 8)
                .padding(.top, 5)
                .padding(.bottom, 3)
                .frame(minWidth: 44, minHeight: 44, alignment: .bottomLeading)
                .background(Color.kuroWhite, in: UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 10)
            .accessibilityLabel(KuroLocale.text("\(card.title), \(season). Show seasons",
                                                "\(card.title), \(season). Staffeln zeigen"))
        }
    }

    @ViewBuilder
    private func animeAlsoWatching(_ cards: [HomeCard]) -> some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(KuroLocale.text("Also watching", "Auch dabei"))
                    .kuroKicker()
                    .accessibilityAddTraits(.isHeader)
                ForEach(cards) { card in
                    HStack(alignment: .center, spacing: 12) {
                        Button { open(card) } label: {
                            HStack(alignment: .center, spacing: 12) {
                                ZStack(alignment: .bottomTrailing) {
                                    cover(card.coverImage ?? card.bannerImage)
                                        .frame(width: 44, height: 66)
                                        .clipped()
                                    if let stamp = card.seasonStamp {
                                        Text(stamp)
                                            .font(.kuroCustom(11, weight: .semibold, relativeTo: .caption1, maxSize: 16))
                                            .foregroundStyle(Color.kuroInk)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.kuroWhite)
                                    }
                                }
                                .accessibilityHidden(true)
                                Text(card.title)
                                    .font(.kuroTitleName(weight: .regular))
                                    .foregroundStyle(Color.kuroInk)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HomeContactStyle())
                        .accessibilityLabel(KuroLocale.text("Open \(card.title)", "\(card.title) öffnen"))
                        progressReadout(card, large: false)
                        advanceKey(card, style: .light)
                    }
                    .frame(minHeight: 66)
                }
            }
        }
    }

    @ViewBuilder
    private func sceneStill(_ card: HomeCard) -> some View {
        let raw = card.bannerImage ?? card.coverImage
        if let raw, let url = URL(string: raw) {
            KuroCachedAsyncImage(url: url, maxPixelSize: 1200) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
                else { Color.kuroMissingArt }
            }
        } else { Color.kuroMissingArt }
    }

    // MARK: Manga (equal covers, each book's own chapter ticket and dark raised key)

    /// Two columns on phones (D5), more on a wide column; every frame equal (rulebook §6).
    private var mangaColumns: Int {
        let spacing: CGFloat = 20
        let minCover: CGFloat = 150
        return max(2, Int((contentWidth + spacing) / (minCover + spacing)))
    }

    private func mangaLibrary(_ cards: [HomeCard]) -> some View {
        let columns = mangaColumns
        let spacing: CGFloat = contentWidth < 300 ? 14 : 20
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
        return HStack(spacing: 4) {
            progressReadout(card, large: true)
            Spacer(minLength: 4)
            advanceKey(card, style: .dark)
        }
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

    /// "Episode 7 of 26" / "Folge 7 von 26"; "Caught up" when there is nothing left.
    private func progressSpoken(_ card: HomeCard, state: KeyState) -> String {
        if state.caughtUp { return KuroAdvanceCopy.caughtUpLabel(title: nil, german: KuroLocale.isGerman) }
        let word = mediumKind == .manga ? KuroLocale.text("Chapter", "Kapitel") : KuroLocale.text("Episode", "Folge")
        guard let cap = state.cap, cap > 0 else { return "\(word) \(state.label)" }
        return KuroLocale.text("\(word) \(state.label) of \(cap)", "\(word) \(state.label) von \(cap)")
    }

    /// The +1 key (shared `KuroAdvanceKey`): a sibling of the title's detail target, never nested.
    private func advanceKey(_ card: HomeCard, style: KuroAdvanceKey.Style) -> some View {
        let origin = actionScope.capture(session: libraryActions.accountSession)
        let renderedMedium = home.medium
        let state = keyState(card)
        let phase: KuroAdvanceKey.Phase = state.needsChoice ? .needsChoice : (state.caughtUp ? .caughtUp : .advance)
        let label: String
        switch phase {
        case .needsChoice:
            label = mediumKind == .manga
                ? KuroLocale.text("Choose the next chapter of \(card.title)", "Nächstes Kapitel von \(card.title) auswählen")
                : KuroLocale.text("Choose the next episode of \(card.title)", "Nächste Folge von \(card.title) auswählen")
        case .caughtUp:
            label = KuroAdvanceCopy.caughtUpLabel(title: card.title, german: KuroLocale.isGerman)
        case .advance, .pending:
            label = KuroAdvanceCopy.label(medium: mediumKind, nextUnit: state.progress + 1, title: card.title,
                                          current: state.progress, total: state.cap, german: KuroLocale.isGerman)
        }
        return KuroAdvanceKey(style: style, phase: phase, accessibilityText: label) {
            if state.needsChoice {
                open(card)
            } else {
                perform(origin: origin) {
                    guard home.medium == renderedMedium else { return }
                    await home.advance(card)
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

    private func comingUpLine(proxy: ScrollViewProxy) -> some View {
        let items = scheduleItems
        let german = KuroLocale.isGerman
        let caption = scheduleChecked
            ? HomeCalendarPresentation.glanceCaption(items: items, now: Date(), german: german)
            : KuroLocale.text("Checking dates", "Termine werden geprüft")
        return Button {
            if reduceMotion { proxy.scrollTo("upcoming-calendar", anchor: .top) }
            else { withAnimation(KuroMotion.settle) { proxy.scrollTo("upcoming-calendar", anchor: .top) } }
            calendarFocused = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(KuroLocale.text("Coming up", "Demnächst"))
                    .kuroKicker()
                HStack(alignment: .center, spacing: 12) {
                    Text(caption)
                        .font(.kuroTitle())
                        .foregroundStyle(Color.kuroInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !dynamicTypeSize.isAccessibilitySize { calendarArt(items) }
                    Image(systemName: "arrow.down")
                        .font(.kuroCustom(13, weight: .medium, relativeTo: .footnote, maxSize: 22))
                        .foregroundStyle(Color.kuroInk)
                        .accessibilityHidden(true)
                }
                Rectangle().fill(Color.kuroInk).frame(height: 1)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityLabel(KuroLocale.text("Coming up: \(caption)", "Demnächst: \(caption)"))
        .accessibilityHint(KuroLocale.text("Shows the calendar", "Zeigt den Kalender"))
    }

    private var calendarSection: some View {
        let copy = ReleaseCopy.current()
        let groups = HomeCalendarPresentation.groups(scheduleItems, copy: copy)
        return VStack(alignment: .leading, spacing: 10) {
            KuroSectionHeader(KuroLocale.text("Calendar.", "Kalender."), size: .title)
                .accessibilityFocused($calendarFocused)
            if groups.isEmpty {
                if scheduleChecked {
                    Text(KuroLocale.text("Nothing scheduled.", "Nichts angekündigt."))
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, day in
                        calendarDay(day, initiallyOpen: index == 0)
                    }
                }
            }
        }
        .id("upcoming-calendar")
        .accessibilityElement(children: .contain)
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
    @State private var attempt = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                Text(card.title)
                    .font(.kuroFeature())
                    .foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
                KuroSectionHeader(KuroLocale.text("Seasons", "Staffeln"), size: .title)
                if let detail {
                    if detail.sections.isEmpty {
                        Text(KuroLocale.text("Seasons aren't grouped for this title yet.",
                                             "Für diesen Titel sind noch keine Staffeln zusammengestellt."))
                            .font(.kuroBody())
                            .foregroundStyle(Color.kuroInkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        KuroInkButton(KuroLocale.text("Open title", "Titel öffnen"), role: .secondary) {
                            routes.openMedia(MediaRoute(kind: .anime, id: card.mediaId))
                        }
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
            }
            catch is CancellationError {} catch {
                guard epoch == home.privacyEpoch, !Task.isCancelled else { return }
                failed = true
            }
            #endif
        }
        .onChange(of: home.privacyEpoch) { _, _ in detail = nil; failed = false }
        .presentationDetents([.medium, .large])
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
