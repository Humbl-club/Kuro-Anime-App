import KuroCore
import KuroLibrary
import SwiftUI

/// Accepted Home: Poster medium switch, Coming Up, shallow anime scenes or equal manga covers,
/// the same calendar, and a private club slice. Suggestions stay on Taste.
struct HomeView: View {
    @Environment(HomeStore.self) private var home
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @Environment(ImportsService.self) private var imports
    @State private var actionScope = AccountActionScope()
    @Environment(\.kuroRoutes) private var routes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var seasonCard: HomeCard?
    @State private var showImportRecovery = false
    @State private var showImportChooser = false
    @State private var importRecoveryJob: ImportOutcome?
    @State private var animeScrollOffset: CGFloat = 0
    @State private var mangaScrollOffset: CGFloat = 0
    @State private var presentationAccount: AccountContext?
    @State private var calendarExpansion: [String: Bool] = [:]
    @State private var expandedDayItems: Set<String> = []
    @State private var containerWidth: CGFloat = 0
    @AccessibilityFocusState private var calendarFocused: Bool
    private let skipNetworkLoad:Bool
    private let onOpenImport: (() -> Void)?
    private let onFindTitle: ((String) -> Void)?
    private let onOpenCollection: (() -> Void)?
    private let onImportNavigation: ((ImportResultDestination) -> Void)?
    init(skipNetworkLoad:Bool=false, onOpenImport: (() -> Void)? = nil,
         onFindTitle: ((String) -> Void)? = nil,
         onOpenCollection: (() -> Void)? = nil,
         onImportNavigation: ((ImportResultDestination) -> Void)? = nil) {
        self.skipNetworkLoad=skipNetworkLoad
        self.onOpenImport=onOpenImport
        self.onFindTitle=onFindTitle
        self.onOpenCollection=onOpenCollection
        self.onImportNavigation = onImportNavigation
    }

    var body: some View {
        ScrollViewReader { proxy in
            HomeMediumScroll(offset: scrollBinding) {
                VStack(alignment: .leading, spacing: 16) {
                    mediumSwitch
                    if shelfScene == .invitation { seasonChip }
                    importRecoveryBanner
                    shelfBody(proxy: proxy)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, minHeight: shelfScene == .invitation ? sceneryHeight : 0, alignment: .topLeading)
            }
            .id(home.medium)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
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
                    let outcome = await library.save(MediaKey(kind: sample.0, id: sample.1), status: sample.2)
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
                    VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                        Text("Resume import").font(.kuroBody(weight: .medium))
                        Text(pending.selection.sourceIdentity).font(.kuroCaption())
                            .foregroundStyle(Color.kuroTextSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .padding(KuroDesignSpacing.md)
                .background(Color.kuroBlack08, in: RoundedRectangle(cornerRadius: KuroRadius.md))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Resume import from \(pending.selection.sourceIdentity)")
        }
    }

    private var shelfScene: HomeShelfScene {
        let kind: MediaKind = home.medium == "manga" ? .manga : .anime
        let statuses = library.allEntries.filter { $0.key.kind == kind }.map(\.status)
        return HomeShelfPolicy.scene(
            activeListTypes: home.bundle?.active.map(\.listType) ?? [],
            libraryStatuses: statuses
        )
    }

    private var otherMediumCount: Int {
        let kind: MediaKind = home.medium == "manga" ? .anime : .manga
        let libraryCount = library.allEntries.filter { $0.key.kind == kind }.count
        let bundleCount = (kind == .manga ? home.manga : home.anime)?.active.count ?? 0
        return libraryCount + bundleCount
    }

    private var isGerman: Bool {
        Locale.current.language.languageCode?.identifier.lowercased().hasPrefix("de") == true
    }

    private var sceneryHeight: CGFloat {
        let width = containerWidth > 40 ? containerWidth : 320
        return max(520, width * 1.45)
    }

    private func perform(origin: AccountActionScope.Ticket?, operation: @escaping @MainActor () async -> Void) {
        actionScope.launch(origin: origin, session: libraryActions.accountSession) { _ in await operation() }
    }

    private var coverCard: HomeCard? {
        home.bundle?.active.first
    }

    private var paperCards: [HomeCard] {
        Array((home.bundle?.active ?? []).dropFirst())
    }

    @ViewBuilder
    private var seasonChip: some View {
        if let card = coverCard, let season = card.seasonTitle {
            Button { seasonCard = card } label: {
                Text(season)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.kuroInk)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Color.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(card.title), \(season). View seasons")
        }
    }

    private var mediumSwitch: some View {
        HStack(alignment: .bottom, spacing: 18) {
            mediumButton("anime", title: "Anime")
            mediumButton("manga", title: "Manga")
        }
        .accessibilityElement(children: .contain)
    }

    private func mediumButton(_ value: String, title: String) -> some View {
        let selected = home.medium == value
        let size: CGFloat = dynamicTypeSize.isAccessibilitySize ? 32 : 40
        let lettering = Text(title)
            .font(.system(size: size, weight: .heavy, design: .serif))
            .tracking(-1.1)
            .lineLimit(1)
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
                                .foregroundStyle(Color.white.opacity(0.92))
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
    }

    @ViewBuilder
    private func shelfBody(proxy: ScrollViewProxy) -> some View {
        let origin = actionScope.capture(session: libraryActions.accountSession)
        let renderedMedium = home.medium
        switch home.loadState {
        case .idle, .loading:
            ProgressView("Loading your Home")
                .frame(maxWidth: .infinity, minHeight: 120)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message).font(.kuroBody())
                Button("Try again") { perform(origin: origin) { await home.load() } }
                    .frame(minHeight: 44)
            }
        case .loaded:
            if shelfScene == .invitation {
                Spacer().frame(height: max(0, sceneryHeight * 0.38))
                coverTypeBand(coverCard)
                coverActionLine(coverCard)
                shelfStatus(origin: origin, renderedMedium: renderedMedium)
                Text(isGerman
                     ? "Termine und Club-Aktivität erscheinen, wenn du einen Titel speicherst."
                     : "Dates and club activity appear after you save a title.")
                    .font(.kuroCaption())
                    .foregroundStyle(Color.kuroInkQuiet)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            } else {
                populatedShelf(proxy: proxy)
                shelfStatus(origin: origin, renderedMedium: renderedMedium)
            }
        }
    }

    private func calendarArt(_ events: [HomeEvent]) -> some View {
        HStack(spacing: -7) {
            ForEach(Array(events.prefix(3))) { event in
                cover(event.coverImage).frame(width: 27, height: 38).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.white, lineWidth: 1))
            }
        }.accessibilityHidden(true)
    }

    @ViewBuilder
    private func coverTypeBand(_ card: HomeCard?) -> some View {
        if let card {
            Button { open(card) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(card.title)
                        .font(.kuroHero())
                        .foregroundStyle(Color.kuroInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if shelfScene == .saved {
                        Text(isGerman
                             ? "Nichts ist gerade in Arbeit. Abgeschlossene und gespeicherte Titel bleiben in der Sammlung."
                             : "Nothing in progress. Completed and saved titles stay in Collection.")
                            .font(.kuroBody())
                            .foregroundStyle(Color.kuroInk)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if home.medium == "anime" {
                        Text(coverStatusLine(card))
                            .font(.kuroCaption())
                            .foregroundStyle(Color.kuroInkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if shelfScene == .saved {
            VStack(alignment: .leading, spacing: 10) {
                Text(isGerman ? "Nichts ist gerade in Arbeit." : "Nothing in progress.")
                    .font(.kuroHero())
                    .foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(isGerman
                     ? "Abgeschlossene und gespeicherte Titel bleiben in der Sammlung."
                     : "Completed and saved titles stay in Collection.")
                    .font(.kuroBody())
                    .foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            invitationCopy
        }
    }

    @ViewBuilder
    private func coverActionLine(_ card: HomeCard?) -> some View {
        if shelfScene == .invitation {
            invitationActions
        } else if shelfScene == .saved {
            VStack(alignment: .leading, spacing: 8) {
                Rectangle().fill(Color.kuroInk.opacity(0.18)).frame(height: 1)
                coverWord(isGerman ? "Sammlung öffnen" : "Open Collection") {
                    onOpenCollection?()
                }
            }
        } else if let card {
            VStack(alignment: .leading, spacing: 8) {
                Rectangle().fill(Color.kuroInk.opacity(0.18)).frame(height: 1)
                progressKey(card, ink: .kuroInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func shelfStatus(origin: AccountActionScope.Ticket?, renderedMedium: String) -> some View {
            if let status = home.statusMessage {
                HStack {
                    Text(status)
                        .font(.kuroCaption())
                        .foregroundStyle(Color.kuroTextSecondary)
                    if status == "Saved on this device",
                       home.lastAdvancedKey?.kind.rawValue.lowercased() == home.medium,
                       let card = home.bundle?.active.first(where: {
                           $0.mediaId == home.lastAdvancedKey?.id
                               && UUID(uuidString: $0.lifecycleId) == home.lastAdvancedLifecycle
                       }) {
                        Button("Undo") {
                            perform(origin: origin) {
                                guard home.medium == renderedMedium else { return }
                                await home.undo(card)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if let conflict = home.conflict, let token = home.conflictToken {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(conflict.title) is at \(conflict.serverPosition) on the server.")
                        .font(.kuroBody())
                    HStack(alignment: .center) {
                        Button { perform(origin: origin) { await home.keepServerProgress(expected: token) } } label: {
                            Text("Keep server")
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(minHeight: 44)
                        }
                        Button { perform(origin: origin) { await home.reapplyLocalProgress(expected: token) } } label: {
                            Text("Reapply \(conflict.localPosition)")
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(minHeight: 44)
                        }
                    }
                }
            }
            if home.bundle?.nextCursor?.isEmpty == false {
                Button("More") { perform(origin: origin) { await home.loadMore() } }
                    .frame(minHeight: 44)
            }
    }

    private func populatedShelf(proxy: ScrollViewProxy) -> some View {
        let cards = home.bundle?.active ?? []
        return VStack(alignment: .leading, spacing: 22) {
            comingUpLine(proxy: proxy)
            if cards.isEmpty {
                coverTypeBand(nil)
                coverActionLine(nil)
            } else if home.medium == "manga" {
                mangaLibrary(cards)
            } else {
                animeScenes(Array(cards.prefix(2)))
                animeAlsoWatching(Array(cards.dropFirst(2)))
            }
            calendarSection
            clubSection
        }
    }

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
                .accessibilityLabel("Open \(card.title)")
                if let season = card.seasonTitle {
                    Button { seasonCard = card } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("SEASON").font(.system(size: 7, weight: .semibold)).tracking(0.6)
                            Text(season.replacingOccurrences(of: "Season ", with: ""))
                                .font(.system(size: 17, weight: .regular, design: .serif))
                        }
                        .foregroundStyle(Color.kuroInk)
                        .padding(.horizontal, 8)
                        .padding(.top, 5)
                        .padding(.bottom, 3)
                        .background(Color.white, in: UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 10)
                    .accessibilityLabel("\(card.title), \(season). View seasons")
                }
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 5))
            HStack(alignment: .center, spacing: 0) {
                Button { open(card) } label: {
                    Text(card.title)
                        .font(.system(size: 17, weight: .medium))
                        .tracking(-0.35)
                        .foregroundStyle(Color.kuroInk)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
                Rectangle().fill(Color.kuroHairline).frame(width: 1, height: 36)
                progressReadout(card, large: false)
                    .padding(.leading, 10)
                raisedKey(card, dark: false)
                    .padding(.trailing, 6)
            }
            .frame(minHeight: 64)
            .background(Color.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .shadow(color: Color.kuroInk.opacity(0.06), radius: 2, y: 1)
    }

    private func animeAlsoWatching(_ cards: [HomeCard]) -> some View {
        Group {
            if cards.isEmpty == false {
                VStack(alignment: .leading, spacing: 12) {
                    Text(isGerman ? "Auch dabei" : "Also watching")
                        .kuroKicker()
                    ForEach(cards) { card in
                        HStack(alignment: .center, spacing: 12) {
                            ZStack(alignment: .bottomTrailing) {
                                cover(card.coverImage ?? card.bannerImage)
                                    .frame(width: 44, height: 66)
                                    .clipped()
                                if let stamp = card.seasonStamp {
                                    Text(stamp)
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(Color.kuroInk)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.white)
                                }
                            }
                            Text(card.title)
                                .font(.kuroTitle())
                                .foregroundStyle(Color.kuroInk)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            progressKey(card, ink: .kuroInk)
                        }
                    }
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

    private func mangaLibrary(_ cards: [HomeCard]) -> some View {
        let narrow = containerWidth > 0 && containerWidth < 360
        let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: columns),
            spacing: 26
        ) {
            ForEach(cards) { card in mangaBook(card, artHeight: narrow ? 180 : 216) }
        }
    }

    private func mangaBook(_ card: HomeCard, artHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color(hex: "DCDDD7"), lineWidth: 1)
                    .background(Color.white)
                    .padding(.leading, 5)
                    .padding(.top, 5)
                    .padding(.bottom, 24)
                Button { open(card) } label: {
                    fittedCover(card.coverImage)
                        .frame(maxWidth: .infinity)
                        .frame(height: artHeight, alignment: .bottom)
                }
                .buttonStyle(HomeContactStyle())
                .accessibilityLabel("Open \(card.title)")
                chapterTicket(card)
                    .padding(.horizontal, 9)
                    .offset(y: 0)
            }
            .padding(.bottom, 0)
            Button { open(card) } label: {
                Text(card.title)
                    .font(.system(size: 15, weight: .medium))
                    .tracking(-0.3)
                    .foregroundStyle(Color.kuroInk)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            }
            .buttonStyle(HomeContactStyle())
        }
    }

    private func chapterTicket(_ card: HomeCard) -> some View {
        HStack(spacing: 4) {
            progressReadout(card, large: true)
            Spacer(minLength: 4)
            raisedKey(card, dark: true)
        }
        .padding(.leading, 12)
        .padding(.trailing, 3)
        .frame(height: 56)
        .background(Color.white)
        .overlay(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color(hex: "D7D9D2"), lineWidth: 1)
                .background(Color.white)
                .frame(width: 13, height: 4)
                .offset(x: -14, y: -4)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 9, topTrailingRadius: 3))
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 9, topTrailingRadius: 3)
                .stroke(Color(hex: "D7D9D2"), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 2, y: 1)
    }

    private func progressReadout(_ card: HomeCard, large: Bool) -> some View {
        let progress = home.displayedProgress(for: card)
        let label = home.displayedProgressLabel(medium: home.medium, mediaId: card.mediaId,
            serverLabel: card.progressLabel, lifecycleId: UUID(uuidString: card.lifecycleId)) ?? String(progress)
        let cap = home.medium == "manga" ? card.chapters : card.episodes
        let caughtUp = cap.map { progress >= $0 } ?? false
        return VStack(alignment: .leading, spacing: 1) {
            Text(caughtUp ? (isGerman ? "Aktuell" : "Caught up") : (home.medium == "manga" ? "Ch." : "Ep."))
                .font(.system(size: 9))
                .foregroundStyle(Color(hex: "60645E"))
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(caughtUp ? " " : label)
                    .font(.system(size: large ? 28 : 19, weight: .regular))
                    .tracking(large ? -0.9 : -0.4)
                    .lineLimit(1)
                if let cap, home.medium == "anime", caughtUp == false {
                    Text("/ \(cap)").font(.system(size: 11)).foregroundStyle(Color.kuroInkQuiet)
                }
            }
            .foregroundStyle(Color.kuroInk)
        }
    }

    private func raisedKey(_ card: HomeCard, dark: Bool) -> some View {
        let origin = actionScope.capture(session: libraryActions.accountSession)
        let renderedMedium = home.medium
        let progress = home.displayedProgress(for: card)
        let label = home.displayedProgressLabel(medium: home.medium, mediaId: card.mediaId,
            serverLabel: card.progressLabel, lifecycleId: UUID(uuidString: card.lifecycleId)) ?? String(progress)
        let cap = home.medium == "manga" ? card.chapters : card.episodes
        let caughtUp = cap.map { progress >= $0 } ?? false
        let unitId = home.displayedUnitId(medium: home.medium, mediaId: card.mediaId,
            serverUnitId: card.unitId, lifecycleId: UUID(uuidString: card.lifecycleId))
        let needsUnitChoice = unitId != nil || Int(label) != progress
        return Button {
            if needsUnitChoice { open(card) }
            else { perform(origin: origin) {
                guard home.medium == renderedMedium else { return }
                await home.advance(card)
            } }
        } label: {
            Image(systemName: needsUnitChoice ? "list.number" : (caughtUp ? "checkmark" : "plus"))
                .font(.system(size: 15, weight: .medium))
                .frame(width: 44, height: 44)
                .foregroundStyle(dark ? Color.white : Color(hex: "30352E"))
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(dark ? Color(hex: "2C322F") : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(dark ? Color.white.opacity(0.18) : Color(hex: "D7DAD2"), lineWidth: 1)
                        .padding(3)
                )
        }
        .buttonStyle(HomeContactStyle())
        .disabled(caughtUp && !needsUnitChoice)
        .accessibilityLabel(needsUnitChoice ? "Choose the next \(home.medium == "manga" ? "chapter" : "episode") of \(card.title)" : (caughtUp ? "Caught up on \(card.title)" : "Mark next \(home.medium == "manga" ? "chapter" : "episode") of \(card.title)"))
    }

    @ViewBuilder
    private func fittedCover(_ raw: String?) -> some View {
        if let raw, let url = URL(string: raw) {
            KuroCachedAsyncImage(url: url, maxPixelSize: 800) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFit() }
                else { Color.kuroMissingArt }
            }
        } else { Color.kuroMissingArt }
    }

    private func inkIndex(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if home.medium == "manga" {
                mangaPaper
            } else {
                animePaper
            }
            comingUpLine(proxy: proxy)
            calendarSection
            clubSection
        }
        .padding(.top, 8)
    }

    private func comingUpLine(proxy: ScrollViewProxy) -> some View {
        let bundle = home.bundle
        let groups = HomeCalendarPresentation.groups(bundle?.upcoming ?? [])
        let count = bundle?.upcomingTotal ?? bundle?.upcoming.count ?? 0
        let pendingCount = bundle?.pendingTotal ?? bundle?.pending.count ?? 0
        let caption: String = {
            if case .failed = home.loadState { return "Could not load dates" }
            if let first = groups.first { return "\(first.label) · \(first.events.count)" }
            if bundle?.scheduleState == "no_verified_schedule" { return "Dates still to come" }
            return count == 0 && pendingCount == 0 ? "Nothing scheduled" : "Dates still to come"
        }()
        return Button {
            if reduceMotion { proxy.scrollTo("upcoming-calendar", anchor: .top) }
            else { withAnimation(.easeOut(duration: 0.22)) { proxy.scrollTo("upcoming-calendar", anchor: .top) } }
            calendarFocused = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(isGerman ? "Demnächst" : "Coming up")
                    .kuroKicker()
                HStack(alignment: .center, spacing: 12) {
                    Text(caption)
                        .font(.kuroTitle())
                        .foregroundStyle(Color.kuroInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    calendarArt(bundle?.upcoming ?? [])
                    Image(systemName: "arrow.down")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.kuroInk)
                        .accessibilityHidden(true)
                }
                Rectangle().fill(Color.kuroInk).frame(height: 1)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityLabel("Coming up: \(caption). Open the calendar")
    }

    private var animePaper: some View {
        let cards = paperCards
        return Group {
            if cards.isEmpty == false {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(cards) { card in
                        animeIndexRow(card)
                    }
                }
            }
        }
    }

    private func animeIndexRow(_ card: HomeCard) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button { open(card) } label: {
                cover(card.coverImage ?? card.bannerImage)
                    .frame(width: 48, height: 72)
                    .clipped()
            }
            .buttonStyle(HomeContactStyle())
            .accessibilityLabel("Open \(card.title)")
            VStack(alignment: .leading, spacing: 2) {
                Button { open(card) } label: {
                    Text(card.title)
                        .font(.kuroTitle())
                        .foregroundStyle(Color.kuroInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(HomeContactStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            progressKey(card, ink: .kuroInk)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.kuroHairline).frame(height: 0.5)
        }
        .padding(.bottom, 10)
    }

    private var mangaPaper: some View {
        let cards = paperCards
        let narrow = containerWidth > 0 && containerWidth < 360
        let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        let height: CGFloat = dynamicTypeSize.isAccessibilitySize ? 260 : (narrow ? 168 : 196)
        return Group {
            if cards.isEmpty == false {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: narrow ? 11 : 14), count: columns),
                    spacing: narrow ? 24 : 26
                ) {
                    ForEach(cards) { card in
                        mangaIndexCover(card, artHeight: height)
                    }
                }
            }
        }
    }

    private func mangaIndexCover(_ card: HomeCard, artHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { open(card) } label: {
                VStack(spacing: 8) {
                    GeometryReader { geometry in
                        mangaArt(card.coverImage)
                            .frame(width: geometry.size.width, height: artHeight)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.kuroHairline))
                    }
                    .frame(height: artHeight)
                    Text(card.title)
                        .font(.kuroTitle())
                        .foregroundStyle(Color.kuroInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(HomeContactStyle())
            .accessibilityLabel("Open \(card.title)")
            progressKey(card, ink: .kuroInk)
        }
    }

    private var invitationActions: some View {
        VStack(alignment: .leading, spacing: 22) {
            invitationAction(
                kicker: isGerman ? "Finden" : "Find",
                title: isGerman ? "Deinen ersten Titel" : "Your first title",
                label: isGerman ? "Finde deinen ersten Titel" : "Find your first title"
            ) {
                onFindTitle?(home.medium)
            }
            invitationAction(
                kicker: "Import",
                title: isGerman ? "Deine Liste" : "Your list",
                label: isGerman ? "Importiere deine Liste" : "Import your list"
            ) {
                showImportChooser = true
            }
            if otherMediumCount > 0 {
                coverWord(home.medium == "manga"
                          ? (isGerman ? "Dein Anime" : "Your anime")
                          : (isGerman ? "Dein Manga" : "Your manga")) {
                    home.selectMedium(home.medium == "manga" ? "anime" : "manga")
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
                        .font(.system(size: 13, weight: .medium))
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
            Text(isGerman ? "Deine nächste Geschichte beginnt hier." : "Your next story starts here.")
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
            Text(isGerman
                 ? "Finde etwas zum Schauen oder Lesen, oder bring die Liste mit, die du schon hast."
                 : "Find something to watch or read, or bring the list you already have.")
                .font(.kuroBody())
                .foregroundStyle(Color.kuroInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func coverWord(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.kuroTitle())
                .foregroundStyle(Color.kuroInk)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
    }

    private var calendarSection: some View {
        let origin = actionScope.capture(session: libraryActions.accountSession)
        let groups = HomeCalendarPresentation.groups(home.bundle?.upcoming ?? [])
        return VStack(alignment: .leading, spacing: 10) {
            if groups.isEmpty {
                Text(home.bundle?.scheduleState == "no_verified_schedule" ? "Dates to come. No verified schedule yet." : "No confirmed dates in this window.")
                    .font(.kuroCaption())
                    .foregroundStyle(Color.kuroInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused($calendarFocused)
            } else {
                Color.clear.frame(height: 0).accessibilityFocused($calendarFocused)
                VStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, day in calendarDay(day, initiallyOpen: index == 0) }
                }
            }
            if home.bundle?.eventsCursor != nil {
                Button("More dates") { perform(origin: origin) { await home.loadMoreEvents() } }
                    .frame(minHeight: 44).buttonStyle(HomeContactStyle())
            }
            if let pending = home.bundle?.pending, !pending.isEmpty {
                DisclosureGroup(isExpanded: calendarBinding("pending", initiallyOpen: false)) {
                    ForEach(pending) { event in calendarEvent(event, pending: true) }
                    if home.bundle?.pendingCursor != nil {
                        Button("More announcements") { perform(origin: origin) { await home.loadMorePending() } }
                            .frame(minHeight: 44).buttonStyle(HomeContactStyle())
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text("…").font(.kuroTitle()).frame(minWidth: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Dates to come").font(.kuroBody(weight: .medium))
                            Text("\(home.bundle?.pendingTotal ?? pending.count) announcements").font(.kuroCaption()).foregroundStyle(Color.kuroTextSecondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if !dynamicTypeSize.isAccessibilitySize { calendarArt(pending) }
                    }.frame(minHeight: 60)
                }.padding(12)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.kuroHairline).frame(height: 0.5) }
            }
        }.id("upcoming-calendar").accessibilityElement(children: .contain)
    }

    private func calendarBinding(_ id: String, initiallyOpen: Bool) -> Binding<Bool> {
        let key = home.medium + "|" + id
        return Binding(get: { calendarExpansion[key] ?? initiallyOpen }, set: { calendarExpansion[key] = $0 })
    }

    private func calendarDay(_ day: HomeCalendarDay, initiallyOpen: Bool) -> some View {
        let key = home.medium + "|" + day.id
        let all = expandedDayItems.contains(key)
        return DisclosureGroup(isExpanded: calendarBinding(day.id, initiallyOpen: initiallyOpen)) {
            ForEach(Array(day.events.prefix(all ? day.events.count : 3))) { event in calendarEvent(event) }
            if day.events.count > 3 {
                Button(all ? "Show fewer releases" : "Show \(day.events.count - 3) more releases") {
                    if all { expandedDayItems.remove(key) } else { expandedDayItems.insert(key) }
                }.font(.kuroCaption()).frame(minHeight: 44).buttonStyle(HomeContactStyle())
            }
        } label: {
            HStack(spacing: 12) {
                VStack(spacing: 1) {
                    Text(day.day).font(.kuroTitle()).monospacedDigit()
                    Text(day.month).font(.kuroMicro())
                }.frame(minWidth: 36).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(day.label).font(.kuroBody(weight: .medium))
                    Text("\(day.events.count) releases").font(.kuroCaption()).foregroundStyle(Color.kuroTextSecondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !dynamicTypeSize.isAccessibilitySize { calendarArt(day.events) }
            }.frame(minHeight: 60)
        }.padding(12).overlay(alignment: .bottom) { Divider() }
    }

    private func calendarEvent(_ event: HomeEvent, pending: Bool = false) -> some View {
        let medium = home.medium
        return Button { routes.openMedia(MediaRoute(kind: medium == "manga" ? .manga : .anime, id: event.mediaId)) } label: {
            HStack(spacing: 10) {
                cover(event.coverImage).frame(width: 32, height: 48).clipped().accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.kuroBody(weight: .medium))
                        .foregroundStyle(Color.kuroInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(event.unitLabel ?? (pending ? "Announcement" : "Release")).font(.kuroCaption()).foregroundStyle(Color.kuroInkSecondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(pending ? "Date TBA" : eventDate(event)).font(.kuroCaption()).foregroundStyle(Color.kuroTextSecondary)
                Image(systemName: "chevron.right").font(.kuroMicro()).accessibilityHidden(true)
            }.frame(minHeight: 44).padding(.vertical, 4)
        }.buttonStyle(HomeContactStyle())
    }

    @ViewBuilder
    private var clubSection: some View {
        let club = home.bundle?.club
        if club?.state == "error" {
            Text("Club activity needs a fresh connection.")
                .font(.kuroCaption())
                .foregroundStyle(Color.kuroInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let items = club?.items, !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(isGerman ? "Euer Club" : "Your private club")
                    .kuroKicker()
                    .foregroundStyle(Color.white.opacity(0.62))
                Text(club?.label ?? "Sunday Club")
                    .font(.kuroTitle())
                    .foregroundStyle(Color.white)
                    .accessibilityAddTraits(.isHeader)
                ForEach(items) { item in
                    Button {
                        routes.openMedia(MediaRoute(kind: item.mediaType.lowercased() == "manga" ? .manga : .anime, id: item.mediaId))
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            let art = home.bundle?.active.first { $0.mediaId == item.mediaId && item.mediaType.lowercased() == home.medium }
                            cover(art?.coverImage).frame(width: dynamicTypeSize.isAccessibilitySize ? 40 : 60, height: dynamicTypeSize.isAccessibilitySize ? 60 : 90).clipped().accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.displayName ?? "Someone in your clubs")
                                    .font(.system(size: 12, weight: .semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                if item.spoilerScope != nil && item.spoilerScope != "none" && item.text == nil {
                                    Text("Spoiler hidden")
                                        .fixedSize(horizontal: false, vertical: true)
                                } else {
                                    Text(item.text ?? "")
                                        .font(.kuroBody())
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.16)).frame(height: 0.5) }
                    }
                    .buttonStyle(HomeContactStyle())
                    .accessibilityHint("Opens this title's private discussion")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "252B28"), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func progressKey(_ card: HomeCard, ink: Color) -> some View {
        let origin = actionScope.capture(session: libraryActions.accountSession)
        let renderedMedium = home.medium
        let progress = home.displayedProgress(for: card)
        let label = home.displayedProgressLabel(medium: home.medium, mediaId: card.mediaId,
            serverLabel: card.progressLabel, lifecycleId: UUID(uuidString: card.lifecycleId)) ?? String(progress)
        let cap = home.medium == "manga" ? card.chapters : card.episodes
        let caughtUp = cap.map { progress >= $0 } ?? false
        let unitId = home.displayedUnitId(medium: home.medium, mediaId: card.mediaId,
            serverUnitId: card.unitId, lifecycleId: UUID(uuidString: card.lifecycleId))
        let needsUnitChoice = unitId != nil || Int(label) != progress
        return HStack(spacing: 4) {
            VStack(alignment: .leading,spacing: 1) {
                Text(home.medium == "manga" ? "Ch." : "Ep.").font(.system(size: 9)).foregroundStyle(ink.opacity(0.8))
                HStack(alignment: .lastTextBaseline,spacing: 3) {
                    Text(label).font(home.medium == "manga" ? .kuroHeadline() : .kuroTitle()).minimumScaleFactor(0.8).lineLimit(1)
                    if let cap, home.medium == "anime" { Text("/ \(cap)").font(.system(size: 10)) }
                }.foregroundStyle(ink)
            }.frame(maxWidth: home.medium == "manga" ? .infinity : nil,alignment: .leading)
            Button {
                if needsUnitChoice { open(card) }
                else { perform(origin: origin) {
                    guard home.medium == renderedMedium else { return }
                    await home.advance(card)
                } }
            } label: {
                Image(systemName: needsUnitChoice ? "list.number" : (caughtUp ? "checkmark" : "plus"))
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(home.medium == "manga" ? Color.white : Color.kuroInk)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(home.medium == "manga" ? Color.kuroInk : Color.white)
                            .shadow(color: Color.kuroInk.opacity(0.14), radius: 2, y: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(home.medium == "manga" ? Color.clear : Color.kuroHairline)
                    )
            }
            .buttonStyle(HomeContactStyle())
            .disabled(caughtUp && !needsUnitChoice)
            .accessibilityLabel(needsUnitChoice ? "Choose the next \(home.medium == "manga" ? "chapter" : "episode") of \(card.title)" : (caughtUp ? "Caught up on \(card.title)" : "Mark next \(home.medium == "manga" ? "chapter" : "episode") of \(card.title)"))
        }
    }

    private func eventDate(_ event: HomeEvent) -> String {
        if event.precision == "day", let date=event.sourceLocalDate {
            let parser=DateFormatter(); parser.locale=Locale(identifier:"en_US_POSIX"); parser.dateFormat="yyyy-MM-dd"
            if let parsed=parser.date(from:date) { parser.dateFormat="EEE, d MMM"; return parser.string(from:parsed) }
        }
        if let raw=event.at,let date=ClubsStore.parseISO8601(raw) { return date.formatted(.dateTime.weekday(.abbreviated).hour().minute()) }
        return event.sourceLocalDate ?? "Date to come"
    }

    @ViewBuilder private func mangaArt(_ raw: String?) -> some View {
        if let raw, let url = URL(string: raw) {
            KuroCachedAsyncImage(url: url, maxPixelSize: 800) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
                else { Color.kuroMissingArt }
            }
        } else { Color.kuroMissingArt }
    }

    private func coverStatusLine(_ card: HomeCard) -> String {
        if let club = home.bundle?.club, club.items.isEmpty == false {
            return club.label
        }
        return availability(card)
    }

    private func availability(_ card: HomeCard) -> String {
        if let episodes = card.episodes, home.displayedProgress(for: card) >= episodes { return "Up to date" }
        return home.medium == "manga" ? "Reading" : "Watching"
    }

    private func open(_ card: HomeCard) {
        routes.openMedia(MediaRoute(kind: home.medium == "manga" ? .manga : .anime, id: card.mediaId))
    }

    @ViewBuilder
    private func cover(_ raw: String?) -> some View {
        if let raw, let url = URL(string: raw) {
            KuroCachedAsyncImage(url: url, maxPixelSize: 800) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFit()
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


/// A small amount of contact feedback; Reduce Motion keeps the control stationary.
struct HomeContactStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14),value: configuration.isPressed)
    }
}

private struct HomeSeasonOverview: View {
    let card: HomeCard
    @Environment(HomeStore.self) private var home
    @Environment(\.kuroRoutes) private var routes
    @State private var detail: SeriesDetailBundle?
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Text(card.title).font(.kuroFeature())
                Text("Seasons").font(.kuroCaption()).accessibilityAddTraits(.isHeader)
                if let detail {
                    if detail.sections.isEmpty {
                        Text("No approved season grouping.").font(.kuroBody())
                        Button("Open title") { routes.openMedia(MediaRoute(kind: .anime, id: card.mediaId)) }
                            .frame(minHeight: 44).buttonStyle(HomeContactStyle())
                    }
                    ForEach(detail.sections) { section in
                        ForEach(section.entries ?? []) { entry in
                            Button { routes.openMedia(MediaRoute(kind:.anime,id:entry.mediaId)) } label: {
                                HStack(spacing:12) {
                                    if let raw=entry.bannerImage ?? entry.coverImage,let url=URL(string:raw) {
                                        KuroCachedAsyncImage(url:url,maxPixelSize:600) { phase in
                                            if case .success(let image)=phase { image.resizable().scaledToFill() }
                                            else { Color.kuroMissingArt }
                                        }.frame(width:96,height:54).clipped()
                                    }
                                    VStack(alignment:.leading,spacing:4) {
                                        Text(section.name).font(.kuroBody())
                                        if let episodes=entry.episodes { Text("\(episodes) episodes").font(.kuroCaption()).foregroundStyle(Color.kuroTextSecondary) }
                                    }
                                    Spacer()
                                    Image(systemName:entry.mediaId == card.mediaId ? "bookmark.fill" : "chevron.right")
                                }.frame(minHeight:64).contentShape(Rectangle())
                            }.buttonStyle(HomeContactStyle())
                        }
                    }
                } else if let error { Text(error).font(.kuroBody()) }
                else { ProgressView() }
            }.padding(20)
        }.background(Color.kuroCanvasPage)
        .task(id: home.privacyEpoch) {
            let epoch = home.privacyEpoch
            #if canImport(Supabase)
            do {
                let loaded = try await home.detailBundle(medium:"anime",mediaId:card.mediaId,sectionId:nil)
                guard epoch == home.privacyEpoch, !Task.isCancelled else { return }
                detail = loaded
                error = nil
            }
            catch is CancellationError {} catch {
                guard epoch == home.privacyEpoch, !Task.isCancelled else { return }
                self.error="Seasons could not be loaded."
            }
            #endif
        }
        .onChange(of:home.privacyEpoch) { _,_ in detail=nil; error=nil }
        .presentationDetents([.medium,.large])
    }
}
