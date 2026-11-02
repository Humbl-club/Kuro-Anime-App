import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Anime detail page (prototype fidelity, Task 6; spec §5.2; ref-detail-anime-390.png)
// The one anime detail for everybody (series flags on or off). Data comes from the existing owners:
// | Read                                   | Owner                       | Feeds                                      |
// | -------------------------------------- | --------------------------- | ------------------------------------------ |
// | `fetchMediaLadder` (+ cached chain walk) | CatalogStore              | seasons, the original story                |
// | studios / staff / characters (credits_cast_v1) | CatalogStore        | characters, "Behind the frames."           |
// | `fetchEpisodesNext` / `fetchEpisodesPage` | CatalogStore             | Up next, episode rows, "More episodes"     |
// | `mediaSchedule` / `themes`             | ReleasesStore (`.detailReleases`) | next airing line, "The sound of it."  |
// | `detailBundle` (series flags on only)  | HomeStore                   | `detail_copy` hook, manga coverage, songs  |
// | `resolveWatchLinks`                    | ProviderAvailabilityStore   | Where to watch                             |
// | friend activity (`FriendsActivitySection`) | SocialActivityStore     | club presence, "Between us." (social_activity_v1) |
// | `clubActivityForMedia` (cached bundles) | ClubsStore                 | club rails holding this title ("Between us.") |
// Loading: the hero and story draw at once; the other sections wait behind `KuroSkeleton(.detailSection)`
// until the ladder walk, the first units and credits settle (no pop-in), and an offline band with Try
// again sits under the hero. A failed ladder read (`DetailReadState.ladderFailed`: no coverage status)
// shows the branded failed state with Try again under the story. The episode, credit and link owners
// still answer a failed read with an empty list, which the page cannot tell from "none" (open item:
// those owners need a throwing read).
// Tracking writes go through `LibraryActions.apply` (`DetailAdvance`: a +1 on a Planned title also
// makes it Watching), `LibraryActions.remove` (asked first, with Undo) and the shared tracking editor
// route; the page acts only on the entry that is open.
// Navigation (contract 2026-11-02, DetailNavigation.swift): a journey page with the shrinking header
// (`.detailJourneyChrome`); every tap inside pushes through `\.kuroRoutes`; folds remember their state.

/// Everything the page shows besides the catalogue row and the Library entry. Fixture renders pass a
/// complete value; the live page fills it from the owners above.
struct AnimeDetailContent {
    var numbered: [LadderSeason] = []
    var extras: [LadderSeason] = []
    /// The chain walk reached the first season: numbers are real. Otherwise tiles show no numbers.
    var chainIsProven = false
    var source: MediaLadderItem? = nil
    var characters: [(character: Character, role: String)] = []
    var staff: [(staff: Staff, role: String)] = []
    var studios: [Studio] = []
    var episodes: [Episode] = []
    var songs: [ThemeSong] = []
    var schedule: [ReleaseScheduleItem] = []
    var bundle: SeriesDetailBundle? = nil
    var friendsPreview: SocialActivityStore.FriendActivityResponse? = nil
}

/// A credit row of "Behind the frames." (only rows with a real name exist).
struct DetailCreditRow: Identifiable {
    /// `media`: the ladder's original work when it maps to a catalogue title (pushed like a source card).
    enum Target { case staff(Staff), studio(Studio), author(Author), media(MediaKey), none }
    let role: String
    let name: String
    let target: Target
    var id: String { "\(role)|\(name)" }

    /// Only a row with a record to open is a button (an "Original work" name from the ladder that maps to
    /// no title is text).
    var isInteractive: Bool {
        if case .none = target { return false }
        return true
    }

    /// - Parameter sourceKey: the ladder's original work as a title (`DetailNavigation.ladderKey`): the
    ///   ladder-sourced "Original work" row opens it (N9); nil keeps the row plain text.
    static func anime(staff: [(staff: Staff, role: String)], studios: [Studio], sourceAuthor: String?,
                      sourceKey: MediaKey? = nil, german: Bool) -> [DetailCreditRow] {
        var rows: [DetailCreditRow] = []
        let original = staff.first { CreditRole.from(raw: $0.role) == .originalCreator }
        if let original, let name = original.staff.nameFull, !name.isEmpty {
            rows.append(DetailCreditRow(role: german ? "Vorlage" : "Original work", name: name, target: .staff(original.staff)))
        } else if let sourceAuthor = sourceAuthor?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceAuthor.isEmpty {
            rows.append(DetailCreditRow(role: german ? "Vorlage" : "Original work", name: sourceAuthor,
                                        target: sourceKey.map { .media($0) } ?? .none))
        }
        if let director = staff.first(where: { CreditRole.from(raw: $0.role) == .director }),
           let name = director.staff.nameFull, !name.isEmpty {
            rows.append(DetailCreditRow(role: german ? "Regie" : "Director", name: name, target: .staff(director.staff)))
        }
        let studio = studios.first(where: { $0.isAnimationStudio == true }) ?? studios.first
        if let studio, let name = studio.name, !name.isEmpty {
            rows.append(DetailCreditRow(role: "Animation", name: name, target: .studio(studio)))
        }
        return rows
    }
}

struct AnimeDetailPage: View {
    let anime: Anime
    private let preview: AnimeDetailContent?

    init(anime: Anime, preview: AnimeDetailContent? = nil) {
        self.anime = anime
        self.preview = preview
        self._content = State(initialValue: preview ?? AnimeDetailContent())
        self._pending = State(initialValue: preview == nil ? DetailLoadPart.anime : [])
    }

    @Environment(CatalogStore.self) private var catalog
    @Environment(FeatureFlags.self) private var flags
    @Environment(HomeStore.self) private var home
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @Environment(ArtworkMaterialStore.self) private var materials
    @Environment(ClubsStore.self) private var clubs
    @Environment(SocialActivityStore.self) private var social
    @Environment(ProviderAvailabilityStore.self) private var availability
    @Environment(OutboundLinkTelemetry.self) private var outboundLinks
    @Environment(\.kuroRoutes) private var routes
    @Environment(\.kuroFoldMemory) private var folds
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Optional: fixture hosts may not inject one (then the page counts as online).
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?

    @State private var content: AnimeDetailContent
    /// The shrinking header's progress (read by the chrome only).
    @State private var collapse = DetailCollapseState()
    /// Foldable sections whose top has scrolled above the view (F2: a collapse scrolls them back).
    @State private var foldsAbove: Set<DetailSection> = []
    @State private var releaseItems: [ReleaseScheduleItem]?
    @State private var releaseSongs: [ThemeSong]?
    @State private var roster: [SocialActivityStore.FriendTitleActivity] = []
    @State private var toast: KuroToastState?
    @State private var toastTask: Task<Void, Never>?
    @State private var showVerdict = false
    @State private var showProviders = false
    @State private var watchLinks: ProviderLinkSnapshot?
    @State private var actionScope = AccountActionScope()
    @State private var confirmTrigger = 0
    @State private var savingNext = false
    @State private var loadGeneration = UUID()
    @State private var creditsGeneration = UUID()
    /// First loads still pending (the skeleton holds the page's lower sections until they settle).
    @State private var pending: Set<DetailLoadPart>
    /// Try again (offline band) and a reconnect reload the page's reads.
    @State private var reloadToken = 0
    /// The ladder read failed (not "no relations"): the failed state with Try again shows.
    @State private var ladderFailed = false
    /// The entry a confirmed "Remove from list" will remove.
    @State private var pendingRemoval: LibraryEntry?

    private var german: Bool { KuroLocale.isGerman }
    private var entry: LibraryEntry? { library.entry(for: anime.libraryKey) }
    private var progress: Int { entry?.progress ?? 0 }
    private var total: Int? { anime.episodeCount.flatMap { $0 > 0 ? $0 : nil } }
    /// The schedule's upcoming rows (the catalogue's own next airing until the schedule answers).
    private var upcoming: [ReleaseScheduleItem] {
        DetailNextReleaseSection.upcoming((releaseItems?.isEmpty == false ? releaseItems : nil)
                                          ?? DetailNextReleaseSection.seed(for: anime))
    }

    private var nextUnit: Int? {
        DetailSectionPolicy.nextUnit(progress: progress, total: total,
                                     airedThrough: DetailSectionPolicy.airedThrough(status: anime.status,
                                                                                    nextEpisode: anime.nextEpisodeNumber,
                                                                                    nextAiringAt: anime.nextAiringAt,
                                                                                    scheduledNext: DetailSectionPolicy.scheduledNext(upcoming, kind: .episode)))
    }

    private var heroURL: URL? {
        [anime.bannerImage, anime.coverImageLarge, anime.coverImageMedium]
            .compactMap { $0.flatMap(Self.webURL) }.first
    }

    private var coverURL: URL? {
        [anime.coverImageLarge, anime.coverImageMedium].compactMap { $0.flatMap(Self.webURL) }.first
    }

    private var material: ArtworkMaterial {
        materials.material(for: heroURL, seedHex: anime.coverImageColor)
    }

    private var hook: String? {
        guard let copy = content.bundle?.copy, copy.storyState == "present" || copy.storyState == "source" else { return nil }
        return copy.hook?.trimmingCharacters(in: .whitespacesAndNewlines).detailNonEmpty
    }

    private var songs: [ThemeSong] {
        if let releaseSongs, !releaseSongs.isEmpty { return releaseSongs }
        if !content.songs.isEmpty { return content.songs }
        return SeriesDetailFallback.songs(from: content.bundle?.themes ?? [])
    }

    private var seasonNumber: Int? {
        content.chainIsProven ? LadderSeasons.currentNumber(content.numbered) : nil
    }

    private var credits: [DetailCreditRow] {
        DetailCreditRow.anime(staff: content.staff, studios: content.studios,
                              sourceAuthor: content.source?.sourceAuthorName,
                              sourceKey: content.source.flatMap(DetailNavigation.ladderKey), german: german)
    }

    /// `social_activity_v1`: the server kill switch for notes, reactions and the club roster.
    private var socialEnabled: Bool { flags.isSocialActivityV1Enabled }

    private var clubPeople: Int {
        socialEnabled && !clubs.myClubs.isEmpty ? roster.count : 0
    }

    private var clubRails: [ClubMediaActivity] {
        clubs.clubActivityForMedia(mediaId: anime.id, mediaType: "ANIME")
    }

    private var input: DetailInput {
        DetailInput(kind: .anime,
                    hasSynopsis: anime.hasMeaningfulSynopsis,
                    hasHook: hook != nil,
                    clubPeopleCount: clubPeople,
                    seasonCount: content.numbered.count + content.extras.count,
                    isTracked: entry != nil,
                    unitCount: content.episodes.count,
                    hasNextUnit: nextUnit != nil,
                    hasSource: content.source != nil,
                    songCount: songs.count,
                    // The rail's own filter (no background roles): never an empty "The characters.".
                    characterCount: DetailCharactersRail.shown(content.characters).count,
                    creditCount: credits.count,
                    hasClubs: !clubs.myClubs.isEmpty,
                    socialEnabled: socialEnabled,
                    clubRailCount: clubRails.count)
    }

    private var isOffline: Bool { network?.isConnected == false }

    /// Try again, or the network coming back, reloads the reads.
    private var reloadKey: String { "\(reloadToken)-\(network?.reconnectionGeneration ?? 0)" }

    var body: some View {
        let sections = DetailSectionPolicy.sections(for: input)
        let origin = actionScope.capture(session: libraryActions.accountSession)
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                        .detailCollapseHero(collapse)
                    if isOffline {
                        KuroOfflineView(hasContent: true) { reloadToken += 1 }
                            .padding(.horizontal, 24)
                            .padding(.top, 14)
                            .kuroReadableWidth()
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(DetailLoadPart.visibleSections(sections, settled: pending.isEmpty), id: \.self) { section in
                            sectionView(section, sections: sections, origin: origin, proxy: proxy)
                                .detailFoldAnchor(section, above: $foldsAbove)
                                // The seasons' selection dot sits on the rule above the progress card.
                                .zIndex(section == .seasons ? 1 : 0)
                        }
                        if pending.isEmpty, ladderFailed, !isOffline {
                            KuroStateView(.failed(hasCachedContent: true), layout: .inline) { reloadToken += 1 }
                                .padding(.top, 12)
                        }
                        if !pending.isEmpty {
                            VStack(alignment: .leading, spacing: 28) {
                                KuroSkeleton(kind: .detailSection)
                                KuroSkeleton(kind: .detailSection)
                            }
                            .padding(.top, 12)
                            .transition(.opacity)
                        }
                    }
                    .animation(KuroMotion.detail(KuroMotion.settle, reduceMotion: reduceMotion), value: pending.isEmpty)
                    .padding(.horizontal, 24)
                    .padding(.top, 23)
                    .padding(.bottom, 24)
                    .kuroReadableWidth()
                }
            }
            .detailCollapseTracking(collapse)
        }
        // The hero reaches the sheet's top edge (no paper cap above the artwork).
        .ignoresSafeArea(edges: .top)
        .background(Color.kuroPaper.ignoresSafeArea())
        // Back (pushed) and ✕ over the hero, then the compact bar (navigation contract N1-N3, H1-H4).
        .detailJourneyChrome(title: pageTitle, material: material, collapse: collapse)
        .modifier(DetailToastOverlay(toast: $toast))
        .tint(Color.kuroInk)
        .onAppear { actionScope.activate(session: libraryActions.accountSession) }
        .onDisappear {
            actionScope.deactivate()
            toastTask?.cancel()
            loadGeneration = UUID()
            creditsGeneration = UUID()
            savingNext = false
        }
        .task(id: "\(anime.id)-\(reloadKey)") { await loadPage() }
        .task(id: "\(anime.id)-\(flags.isCreditsCastV1Enabled)-\(reloadKey)") { await loadCredits() }
        .task(id: "\(anime.id)-episodes-\(progress)-\(reloadKey)") { await loadEpisodes() }
        .task(id: "\(anime.id)-links-\(progress)-\(reloadKey)") { await loadWatchLinks() }
        // A cold open (deep link) before the Clubs page ran: warm the clubs so "Between us." can show.
        .task(id: anime.id) {
            guard preview == nil, clubs.myClubs.isEmpty else { return }
            await clubs.refreshMyClubsIfStale()
        }
        .detailReleases(kind: .anime, id: anime.id, schedule: $releaseItems, songs: $releaseSongs)
        // Tool sheets (N7): they close back to this page; their own close never collapses the journey.
        .sheet(isPresented: $showVerdict) {
            QuickVerdictPickerSheet(media: anime, onToast: showToast)
                .kuroLeavesJourney()
        }
        // N10: a deep link to this title (already on top) keeps the journey and closes these tools.
        .kuroNavigationLayer("detail.verdict", isPresented: $showVerdict)
        .confirmationDialog(DetailRemoval.confirmTitle(german: german),
                            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                            titleVisibility: .visible, presenting: pendingRemoval) { removed in
            Button(DetailRemoval.confirmAction(german: german), role: .destructive) { remove(removed) }
            Button(KuroLocale.text("Cancel", "Abbrechen"), role: .cancel) {}
        } message: { _ in
            Text(DetailRemoval.confirmMessage(kind: .anime, german: german))
        }
        .sheet(isPresented: $showProviders) {
            ProviderSelectionSheet(title: KuroLocale.text("Watch on", "Ansehen bei"),
                                   links: watchLinks?.all ?? [],
                                   statusCaption: watchLinks?.statusCaption) { link in
                if let url = ProviderAvailabilityStore.validatedOutboundURL(link.url) {
                    outboundLinks.recordOutboundLink(mediaType: "ANIME", mediaId: anime.id, linkKind: "provider_sheet", provider: link.title)
                    openURL(url)
                }
            }
            .kuroLeavesJourney()
        }
        .kuroNavigationLayer("detail.providers", isPresented: $showProviders)
        // No page-local presenter: inside a journey every tap pushes and tools open from the journey's
        // tool slot (navigation contract; `\.kuroRoutes` comes from the journey host).
    }

    private var pageTitle: String { content.bundle?.header.title ?? anime.displayTitle }

    /// F2: after a fold closes, its section comes back into view when its top had scrolled away.
    private func foldCollapsed(_ section: DetailSection, proxy: ScrollViewProxy) {
        guard foldsAbove.contains(section) else { return }
        withAnimation(KuroFold.animation(reduceMotion: reduceMotion)) { proxy.scrollTo(section, anchor: .top) }
    }

    // MARK: Sections

    @ViewBuilder
    private func sectionView(_ section: DetailSection, sections: [DetailSection],
                             origin: AccountActionScope.Ticket?, proxy: ScrollViewProxy) -> some View {
        switch section {
        case .hero:
            EmptyView()
        case .progress:
            // With unit rows (or an Up next) the units case draws progress inside the same block.
            if !sections.contains(.units) {
                seasonContent(showsProgress: true, showsUnits: false, origin: origin, proxy: proxy)
            }
        case .story:
            DetailStorySection(eyebrow: seasonNumber.map { DetailPageCopy.seasonEyebrow($0, german: german) },
                               hook: hook,
                               synopsis: anime.hasMeaningfulSynopsis ? anime.displayDescription : nil,
                               aboutTitle: DetailPageCopy.aboutTitle(isSeason: seasonNumber != nil, german: german),
                               expectation: (anime.genreList ?? []).prefix(3).joined(separator: " · ").detailNonEmpty,
                               expanded: folds.binding(page: DetailFold.page(anime.libraryKey), section: DetailFold.story),
                               onCollapse: { foldCollapsed(.story, proxy: proxy) })
        case .clubPresence:
            DetailClubPresence(names: DetailBetweenUs.rosterNames(roster), count: clubPeople) {
                // Reduce Motion: the jump is instant (prototype §6).
                withAnimation(KuroMotion.detail(KuroMotion.medium, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(DetailSection.betweenUs, anchor: .top)
                }
            }
            .padding(.bottom, 15)
        case .seasons:
            DetailSeasonsSection(numbered: content.numbered, extras: content.extras,
                                 numbersAreReal: content.chainIsProven, material: material) { id in
                routes.openPage(DetailNavigation.seasonPage(id: id))
            }
        case .units:
            seasonContent(showsProgress: sections.contains(.progress), showsUnits: true, origin: origin, proxy: proxy)
        case .source:
            if let source = content.source {
                DetailSourceCard(item: source, coverage: content.bundle?.coverage, seasonNumber: seasonNumber,
                                 showsCoverage: folds.binding(page: DetailFold.page(anime.libraryKey), section: DetailFold.coverage),
                                 onCollapse: { foldCollapsed(.source, proxy: proxy) }) {
                    if let page = DetailNavigation.ladderPage(source) { routes.openPage(page) }
                }
            }
        case .songs:
            DetailSoundPanel(songs: songs, material: material,
                             showsAll: folds.binding(page: DetailFold.page(anime.libraryKey), section: DetailFold.songs),
                             onCollapse: { foldCollapsed(.songs, proxy: proxy) })
        case .characters:
            DetailCharactersRail(characters: content.characters)
        case .credits:
            DetailCreditsList(title: KuroLocale.text("Behind the frames.", "Hinter den Bildern."), rows: credits)
        case .betweenUs:
            DetailBetweenUs(mediaType: "ANIME", mediaId: anime.id, coverURL: coverURL,
                            socialEnabled: socialEnabled, clubRails: clubRails,
                            onRoster: { roster = $0 }, preview: content.friendsPreview)
                .padding(.top, 28)
                .padding(.bottom, 18)
                .id(DetailSection.betweenUs)
        }
    }

    /// Progress (tracked) and units share the prototype's `season-content` block: the material `wash`
    /// fades down from its top edge.
    @ViewBuilder
    private func seasonContent(showsProgress: Bool, showsUnits: Bool, origin: AccountActionScope.Ticket?,
                               proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsProgress {
                DetailProgressCard(label: DetailPageCopy.progressLabel(season: seasonNumber, german: german),
                                   caption: DetailPageCopy.progressCaption(total: total, releasing: anime.status?.uppercased() == "RELEASING", german: german),
                                   progress: progress, total: total)
            }
            if showsUnits {
            AnimeUnitsSection(anime: anime, episodes: content.episodes, progress: progress, total: total,
                              isTracked: entry != nil, nextUnit: nextUnit, seasonNumber: seasonNumber,
                              nextRelease: upcoming.first,
                              material: material, coverURL: coverURL, savingNext: savingNext,
                              confirmTrigger: confirmTrigger,
                              showsAll: folds.binding(page: DetailFold.page(anime.libraryKey), section: DetailFold.units),
                              onCollapse: { foldCollapsed(.units, proxy: proxy) }) { next in
                advance(to: next, origin: origin)
            }
            .padding(.top, showsProgress ? 22 : 0)
            }
        }
        .padding(.top, 15)
        .background(alignment: .top) {
            LinearGradient(colors: [material.wash.color, material.wash.color.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 250)
                .allowsHitTesting(false)
        }
    }

    private var hero: some View {
        DetailHero(artworkURL: heroURL, kicker: DetailPageCopy.kindKicker(.anime, german: german),
                   title: content.bundle?.header.title ?? anime.displayTitle, material: material) {
            DetailStatusMark(entry: entry, kind: .anime,
                             onListSettings: { routes.presentTrackingEditor(TrackingEditorRequest(media: anime)) },
                             onFavourite: toggleSaved,
                             onVerdict: { showVerdict = true },
                             onProviders: openProviders,
                             onAddToClub: { routes.presentAddToClub(anime.libraryKey) },
                             onShare: share)
        }
    }

    // MARK: Actions

    private func advance(to next: Int, origin: AccountActionScope.Ticket?) {
        guard !savingNext, actionScope.isCurrent(origin, session: libraryActions.accountSession) else { return }
        let key = anime.libraryKey
        let status = entry?.status
        let capped = total.map { min(next, $0) } ?? next
        savingNext = true
        let launched = actionScope.launch(origin: origin, session: libraryActions.accountSession) { ticket in
            // A Planned title becomes Watching in the same edit (Home's in-progress scene follows).
            let outcome = await DetailAdvance.advance(key, from: status, to: capped, actions: libraryActions)
            savingNext = false
            guard actionScope.isCurrent(ticket, session: libraryActions.accountSession) else { return }
            guard let change = outcome.change else {
                KuroAccessibility.errorHaptic()
                showToast(KuroToastState(kind: .error,
                                         title: KuroLocale.text("Not saved. Your progress is unchanged.", "Nicht gespeichert. Dein Fortschritt ist unverändert."),
                                         subtitle: nil, actionTitle: nil, onAction: nil))
                return
            }
            KuroAccessibility.successHaptic()
            confirmTrigger += 1
            let caughtUp = total.map { capped >= $0 } ?? false
            showToast(KuroToastState(kind: .success,
                                     title: caughtUp ? KuroLocale.text("Caught up.", "Auf dem neuesten Stand.")
                                                     : KuroLocale.text("Progress saved.", "Fortschritt gespeichert."),
                                     subtitle: nil,
                                     actionTitle: KuroLocale.text("Undo", "Rückgängig"),
                                     onAction: { undo(change, saved: capped) }))
        }
        // The key never stays on "Saving": not launched, or cancelled before the write ran.
        guard let launched else { savingNext = false; return }
        Task { @MainActor in
            await launched.value
            savingNext = false
        }
    }

    /// Undo reverts the whole +1 (the count and a promoted status; a row the +1 created goes again),
    /// only while the entry still shows the saved position.
    private func undo(_ change: LibraryChange, saved: Int) {
        let origin = actionScope.capture(session: libraryActions.accountSession)
        guard progress == saved else { return }
        let key = anime.libraryKey
        actionScope.launch(origin: origin, session: libraryActions.accountSession) { ticket in
            let outcome: LibraryOutcome
            if change.kind == .added {
                outcome = await libraryActions.remove(key)
            } else if let edit = DetailAdvance.undoEdit(change) {
                outcome = await libraryActions.apply(edit, to: key, createIfMissing: nil)
            } else {
                return
            }
            guard actionScope.isCurrent(ticket, session: libraryActions.accountSession) else { return }
            showToast(KuroToastState(kind: outcome.error == nil ? .success : .error,
                                     title: outcome.error == nil ? KuroLocale.text("Undone.", "Rückgängig gemacht.")
                                                                 : KuroLocale.text("Not saved. Your progress is unchanged.", "Nicht gespeichert. Dein Fortschritt ist unverändert."),
                                     subtitle: nil, actionTitle: nil, onAction: nil))
        }
    }

    /// The live dock's heart: saves to Planned, or removes a saved title. Removing asks first when the
    /// entry holds anything beyond a bare plan; the toast then offers Undo.
    private func toggleSaved() {
        let origin = actionScope.capture(session: libraryActions.accountSession)
        guard actionScope.isCurrent(origin, session: libraryActions.accountSession) else { return }
        if let entry {
            if DetailRemoval.needsConfirmation(entry) { pendingRemoval = entry } else { remove(entry) }
            return
        }
        let key = anime.libraryKey
        actionScope.launch(origin: origin, session: libraryActions.accountSession) { ticket in
            let outcome = await libraryActions.save(key, status: .planning)
            guard actionScope.isCurrent(ticket, session: libraryActions.accountSession) else { return }
            savedToast(outcome, removed: nil)
        }
    }

    private func remove(_ removed: LibraryEntry) {
        pendingRemoval = nil
        let origin = actionScope.capture(session: libraryActions.accountSession)
        guard actionScope.isCurrent(origin, session: libraryActions.accountSession) else { return }
        let key = anime.libraryKey
        actionScope.launch(origin: origin, session: libraryActions.accountSession) { ticket in
            let outcome = await libraryActions.remove(key)
            guard actionScope.isCurrent(ticket, session: libraryActions.accountSession) else { return }
            savedToast(outcome, removed: removed)
        }
    }

    /// Undo after a removal: the removed row comes back with every field.
    private func restore(_ removed: LibraryEntry) {
        let origin = actionScope.capture(session: libraryActions.accountSession)
        guard entry == nil else { return }
        let key = anime.libraryKey
        actionScope.launch(origin: origin, session: libraryActions.accountSession) { ticket in
            let outcome = await libraryActions.apply(DetailRemoval.restoreEdit(removed), to: key, createIfMissing: removed.status)
            guard actionScope.isCurrent(ticket, session: libraryActions.accountSession) else { return }
            showToast(KuroToastState(kind: outcome.error == nil ? .success : .error,
                                     title: outcome.error == nil ? KuroLocale.text("Back in your list.", "Wieder in deiner Liste.")
                                                                 : KuroLocale.text("Not restored. Try again from List settings.", "Nicht wiederhergestellt. Versuch es über die Listeneinstellungen."),
                                     subtitle: nil, actionTitle: nil, onAction: nil))
        }
    }

    private func savedToast(_ outcome: LibraryOutcome, removed: LibraryEntry?) {
        if outcome.change != nil {
            KuroAccessibility.successHaptic()
            showToast(KuroToastState(kind: .success,
                                     title: removed != nil ? KuroLocale.text("Removed from your list.", "Von deiner Liste entfernt.")
                                                           : KuroLocale.text("Added to your list.", "Zu deiner Liste hinzugefügt."),
                                     subtitle: nil,
                                     actionTitle: removed != nil ? KuroLocale.text("Undo", "Rückgängig") : nil,
                                     onAction: removed.map { row in { restore(row) } }))
        } else {
            KuroAccessibility.errorHaptic()
            showToast(KuroToastState(kind: .error,
                                     title: KuroLocale.text("Not saved. Your list is unchanged.", "Nicht gespeichert. Deine Liste ist unverändert."),
                                     subtitle: outcome.error.map { friendlyListMutationMessage($0, isGerman: KuroLocale.isGerman) },
                                     actionTitle: nil, onAction: nil))
        }
    }

    private func openProviders() {
        // The links read is still running: say so, never "no link" before the answer.
        guard let watchLinks else {
            showToast(KuroToastState(kind: .info,
                                     title: KuroLocale.text("Still checking where to watch. Try again in a moment.",
                                                            "Wir prüfen noch, wo du schauen kannst. Versuch es gleich noch einmal."),
                                     subtitle: nil, actionTitle: nil, onAction: nil))
            return
        }
        let links = watchLinks.all
        guard let primary = watchLinks.primary, let url = ProviderAvailabilityStore.validatedOutboundURL(primary.url) else {
            showToast(KuroToastState(kind: .info,
                                     title: KuroLocale.text("No legal provider link is available yet.", "Noch kein legaler Anbieter-Link verfügbar."),
                                     subtitle: nil, actionTitle: nil, onAction: nil))
            return
        }
        if links.count > 1 {
            showProviders = true
        } else {
            outboundLinks.recordOutboundLink(mediaType: "ANIME", mediaId: anime.id, linkKind: "watch", provider: primary.title)
            openURL(url)
        }
    }

    private func share() {
        guard let url = URL(string: "kuro://anime/\(anime.id)") else { return }
        DetailShare.present(url: url, subject: anime.displayTitle)
    }

    @MainActor
    private func showToast(_ next: KuroToastState) {
        toastTask?.cancel()
        let motion = KuroMotion.detail(KuroMotion.settle, reduceMotion: reduceMotion)
        withAnimation(motion) { toast = next }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(motion) { toast = nil }
        }
    }

    // MARK: Loading

    private func loadPage() async {
        guard preview == nil else { return }
        defer { pending.remove(.ladder) }
        let generation = UUID()
        loadGeneration = generation
        #if canImport(Supabase)
        // Series flags on: the bundle adds `detail_copy` hooks, manga coverage and songs when it has
        // them. Read alongside the ladder walk, not after it.
        async let bundleRead = readBundle()
        #endif
        let ladder = await catalog.fetchMediaLadder(mediaType: "ANIME", mediaId: anime.id)
        guard !Task.isCancelled, loadGeneration == generation else { return }
        ladderFailed = DetailReadState.ladderFailed(ladder)
        content.source = ladder.primarySource ?? ladder.sourceMaterial.first
        let current = LadderChainEntry(mediaId: anime.id, title: anime.displayTitle, format: anime.format,
                                       year: anime.seasonYear, coverImage: anime.coverImageLarge)
        let chain = await LadderSeasons.walk(from: ladder, current: current) { id in
            await catalog.fetchMediaLadder(mediaType: "ANIME", mediaId: id)
        }
        guard !Task.isCancelled, loadGeneration == generation else { return }
        let seasons = LadderSeasons.seasons(chain: chain.entries, current: anime.id)
        content.numbered = seasons.numbered
        content.extras = seasons.extras
        content.chainIsProven = chain.proven
        #if canImport(Supabase)
        if let bundle = await bundleRead {
            guard !Task.isCancelled, loadGeneration == generation else { return }
            content.bundle = bundle
        }
        #endif
        await catalog.enqueueMediaRelationRefreshIfNeeded(mediaType: "ANIME", mediaId: anime.id, ladder: ladder, reason: "detail_open")
    }

    #if canImport(Supabase)
    private func readBundle() async -> SeriesDetailBundle? {
        guard flags.seriesHomeNativeV1Enabled else { return nil }
        return try? await home.detailBundle(medium: "anime", mediaId: anime.id, sectionId: nil)
    }
    #endif

    private func loadCredits() async {
        guard preview == nil else { return }
        defer { pending.remove(.credits) }
        let generation = UUID()
        creditsGeneration = generation
        guard flags.isCreditsCastV1Enabled else {
            // The flag turned off: the sections go with it.
            content.studios = []
            content.staff = []
            content.characters = []
            return
        }
        async let studios = catalog.fetchStudiosForAnime(animeId: anime.id)
        async let staff = catalog.fetchStaffForAnime(animeId: anime.id)
        async let cast = catalog.fetchCharactersForAnime(animeId: anime.id)
        let (loadedStudios, loadedStaff, loadedCast) = await (studios, staff, cast)
        guard !Task.isCancelled, creditsGeneration == generation, flags.isCreditsCastV1Enabled else { return }
        content.studios = loadedStudios
        content.staff = loadedStaff
        content.characters = loadedCast
    }

    private func loadEpisodes() async {
        guard preview == nil else { return }
        defer { pending.remove(.units) }
        let loaded = await catalog.fetchEpisodesNext(animeId: anime.id, fromNumber: max(1, progress), limit: 10)
        guard !Task.isCancelled else { return }
        content.episodes = loaded
    }

    private func loadWatchLinks() async {
        guard preview == nil else { return }
        let snapshot = await availability.resolveWatchLinks(animeId: anime.id,
                                                            originalLanguage: anime.inferredOriginalLanguageCode,
                                                            progress: entry?.progress)
        guard !Task.isCancelled, let snapshot else { return }
        watchLinks = snapshot
    }

    nonisolated static func webURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false else { return nil }
        return url
    }
}

// MARK: - D2 Story

struct DetailStorySection: View {
    let eyebrow: String?
    let hook: String?
    let synopsis: String?
    let aboutTitle: String
    let expectation: String?
    /// Manga: the hook is one of the prototype's Georgia lines (serif 25, tracking −0.6).
    var serifHook = false
    /// The `detail_copy` premise under the hook (manga prototype; SF 12/19.8).
    var premise: String? = nil
    /// Open or closed, kept for the session per title (navigation contract F3, `DetailFold.story`).
    @Binding var expanded: Bool
    /// F2: the page scrolls the story back into view after it closes, when needed.
    var onCollapse: () -> Void = {}
    /// Heights of the synopsis at five lines and in full (hidden probes), to know whether it is cut.
    @State private var limitedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    /// Without a `detail_copy` hook the synopsis opens the section (spec §4), at most five lines.
    private var opensWithSynopsis: Bool { hook == nil }
    private var truncated: Bool { fullHeight > limitedHeight + 0.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let eyebrow {
                DetailEyebrow(text: eyebrow).padding(.bottom, 10)
            }
            if let hook {
                Text(hook)
                    .font(serifHook ? .detailGeorgia(25) : .detailSF(22, .medium, relativeTo: .title2))
                    .tracking(serifHook ? -0.6 : -0.65)
                    .lineSpacing(serifHook ? 31.25 - 28.4 : 27.06 - 26.25)
                    .foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, serifHook ? 9 : 3)
                if let premise {
                    Text(premise)
                        .font(.detailSF(12, relativeTo: .footnote))
                        .lineSpacing(19.8 - 14.3)
                        .foregroundStyle(Color(hex: "555F59"))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 6)
                }
            } else if let synopsis {
                synopsisText(synopsis)
                    .lineLimit(expanded ? nil : 5)
                    .background { probe(synopsis) }
                    .padding(.bottom, 4)
            }
            if let synopsis, DetailStoryDisclosure.showsToggle(hasHook: !opensWithSynopsis, truncated: truncated,
                                                               hasExpectation: expectation != nil) {
                // A real fold (F1-F3): prototype easing, VoiceOver's expanded/collapsed value, session memory.
                KuroFoldButton(isExpanded: $expanded,
                               expandLabel: DetailStoryDisclosure.label(hasHook: !opensWithSynopsis, expanded: false,
                                                                        about: aboutTitle, german: KuroLocale.isGerman),
                               collapseLabel: DetailStoryDisclosure.label(hasHook: !opensWithSynopsis, expanded: true,
                                                                          about: aboutTitle, german: KuroLocale.isGerman),
                               onCollapse: onCollapse) { title, open in
                    HStack {
                        Text(title)
                            .font(.detailSF(10, relativeTo: .footnote))
                        Spacer()
                        Text(open ? "−" : "+")
                            .font(.detailSF(17, .light, relativeTo: .body))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(DetailInk.disclosure)
                    .frame(minHeight: 44)
                }
                if expanded, !opensWithSynopsis {
                    synopsisText(synopsis).padding(.top, 13)
                }
                // The prototype keeps the expectation line inside the open disclosure, after the
                // synopsis: the collapsed story is the hook and "About this season +" only.
                if expanded, let expectation {
                    Text(expectation)
                        .font(.detailSF(10, relativeTo: .footnote))
                        .tracking(0.05)
                        .foregroundStyle(DetailInk.expectation)
                        .padding(.top, 12)
                }
            }
            // The section's foot: the open expectation line's 18 pt margin; otherwise the hook block's
            // 4 pt (anime) or the folio's 15 pt before the club row (manga), as measured.
            Spacer().frame(height: expanded && expectation != nil ? 18 : (serifHook ? 15 : 4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func synopsisText(_ text: String) -> some View {
        Text(text)
            .font(.detailSF(13, relativeTo: .callout))
            .lineSpacing(21.45 - 15.5)
            .foregroundStyle(DetailInk.synopsis)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Hidden copies at the visible text's width: five lines and the whole text.
    private func probe(_ text: String) -> some View {
        GeometryReader { box in
            ZStack(alignment: .topLeading) {
                synopsisText(text).lineLimit(5)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { limitedHeight = $0 }
                synopsisText(text)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
            }
            .frame(width: box.size.width, alignment: .topLeading)
            .hidden()
        }
        .accessibilityHidden(true)
    }
}

// MARK: - D3 Club presence

struct DetailClubPresence: View {
    let names: [String]
    let count: Int
    let onJump: () -> Void

    var body: some View {
        Button(action: onJump) {
            HStack(spacing: 10) {
                if !names.isEmpty { DetailAvatars(names: names) }
                Text(DetailPageCopy.clubPeople(count, german: KuroLocale.isGerman))
                    .font(.detailSF(11, relativeTo: .footnote))
                    .foregroundStyle(DetailInk.clubRow)
                Spacer()
                Image(systemName: "arrow.down")
                    .font(.detailSF(11, relativeTo: .footnote))
                    .foregroundStyle(DetailInk.clubRow)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(KuroLocale.text("Goes to Between us.", "Springt zu Unter uns."))
    }
}

// MARK: - D4 Seasons

struct DetailSeasonsSection: View {
    let numbered: [LadderSeason]
    let extras: [LadderSeason]
    let numbersAreReal: Bool
    let material: ArtworkMaterial
    let onOpen: (Int) -> Void

    private var all: [LadderSeason] { numbered + extras }
    private var seasonCount: Int { numbered.filter { $0.number != nil }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailSectionHeading(title: KuroLocale.text("Seasons", "Staffeln"), size: 18, tracking: -0.7,
                                 note: showsNumbers ? DetailPageCopy.seasonsCount(seasonCount, german: KuroLocale.isGerman) : nil)
                .padding(.bottom, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(all) { season in
                        VStack(spacing: 0) {
                            tile(season)
                                .containerRelativeFrame(.horizontal, count: all.count > 2 ? 5 : 2, span: all.count > 2 ? 2 : 1, spacing: 8)
                            // The selection thread: a stem from the current tile down to its dot.
                            ZStack(alignment: .bottom) {
                                if season.isCurrent {
                                    Rectangle().fill(DetailInk.threadStem).frame(width: 1, height: 18)
                                    Circle().fill(material.base.color).frame(width: 6, height: 6)
                                        .overlay(Circle().strokeBorder(Color(hex: "F1F3EF"), lineWidth: 3).frame(width: 12, height: 12))
                                        .offset(y: 3)
                                }
                            }
                            .frame(height: 18)
                        }
                    }
                }
                .padding(.top, 2)
                .padding(.horizontal, 1)
            }
            .scrollClipDisabled()
            // The dot and its halo sit over the rule (the rule is drawn first).
            .zIndex(1)
            Rectangle().fill(DetailInk.thread).frame(height: 1)
        }
        .padding(.bottom, 0)
    }

    /// Numbers only for a proven chain with more than one numbered season: a lone TV entry beside a
    /// film is never labelled "1" (no invented "Season 1").
    private var showsNumbers: Bool { numbersAreReal && seasonCount > 1 }

    private func label(_ season: LadderSeason) -> String {
        if let number = season.number, showsNumbers { return "\(number)" }
        if let part = season.partLabel { return KuroLocale.isGerman ? part.replacingOccurrences(of: "Part", with: "Teil") : part }
        return DetailPageCopy.formatWord(season.entry.format, german: KuroLocale.isGerman)
    }

    private func tile(_ season: LadderSeason) -> some View {
        let current = season.isCurrent
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        let text = label(season)
        let isNumber = Int(text) != nil
        return Button {
            guard !current else { return }
            KuroAccessibility.impactHaptic(.light)
            onOpen(season.entry.mediaId)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(text)
                    .font(.detailSF(isNumber ? 33 : 15, isNumber ? .light : .medium, relativeTo: .title1))
                    .tracking(isNumber ? -2 : -0.3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !isNumber {
                    Text(season.entry.title)
                        .font(.detailSF(9, relativeTo: .caption2))
                        .lineLimit(2)
                        .padding(.top, 3)
                }
                Spacer(minLength: 4)
                if current {
                    Text(KuroLocale.text("Current", "Aktuell"))
                        .font(.detailSF(8, .medium, relativeTo: .caption2))
                        .tracking(0.1)
                        .frame(maxWidth: .infinity)
                } else {
                    // The tile's ::after foot dash, as rendered in `ref-detail-anime-390.png`: 12 × 1 and
                    // composited to about `#d2d6d4` (tile ink at 40 % inside the tile's 0.72 opacity).
                    DetailSnappedRule(width: 12, color: DetailInk.tileInk.opacity(0.4))
                }
            }
            .foregroundStyle(current ? Color.white : DetailInk.tileInk)
            .padding(.top, 11)
            .padding(.horizontal, 12)
            .padding(.bottom, 9)
            .frame(maxWidth: .infinity, minHeight: 87, alignment: .topLeading)
            .background {
                ZStack(alignment: .topTrailing) {
                    if current {
                        LinearGradient(colors: [material.base.color, material.deep.color], startPoint: .topLeading, endPoint: .bottomTrailing)
                    } else {
                        LinearGradient(colors: [Color.white, DetailInk.tileFillBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                    DetailStripes(ink: current ? Color.white.opacity(0x06 / 255.0) : Color(hex: "232C24", opacity: 0x05 / 255.0))
                        // The ruling gathers toward the foot, as the prototype's light tiles read.
                        .mask(LinearGradient(colors: [Color.black.opacity(current ? 1 : 0.35), .black],
                                             startPoint: .top, endPoint: .bottom))
                    if current {
                        // The bookmark ribbon (::after 7×18 in `base`) with a V cut at its foot.
                        DetailRibbon().fill(material.base.color).frame(width: 7, height: 18).padding(.trailing, 12)
                    }
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(current ? material.base.color : DetailInk.tileBorder, lineWidth: 1))
            .overlay {
                // The current tile's inset ring (`#718478 0 0 0 1px inset`), just inside its border.
                if current { shape.inset(by: 1).strokeBorder(Color(hex: "718478"), lineWidth: 1) }
            }
            .shadow(color: current ? Color(hex: "273B30", opacity: 0x10 / 255.0) : Color(hex: "202923", opacity: 0x05 / 255.0),
                    radius: current ? 3.5 : 1, x: 0, y: current ? 3 : 2)
            .opacity(current ? 1 : 0.72)
            .contentShape(shape)
        }
        .buttonStyle(KuroPressStyle())
        .accessibilityLabel(season.number.map { showsNumbers ? KuroLocale.text("Season \($0), \(season.entry.title)", "Staffel \($0), \(season.entry.title)") : season.entry.title }
                            ?? season.entry.title)
        .accessibilityValue(current ? KuroLocale.text("Current", "Aktuell") : "")
        .accessibilityHint(current ? "" : KuroLocale.text("Opens this entry without changing your progress",
                                                           "Öffnet diesen Eintrag, ohne deinen Fortschritt zu ändern"))
    }
}

/// A 1 pt rule moved onto a whole point, so it draws as one crisp row instead of two half-tone rows
/// when its line falls on a half point (the season tiles sit on one). Whole points are pixel-aligned
/// at every screen scale; the offset does not change layout, so the reader never loops.
struct DetailSnappedRule: View {
    let width: CGFloat
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let y = proxy.frame(in: .global).minY
            Rectangle().fill(color)
                .frame(width: width, height: 1)
                .offset(y: y.rounded() - y)
        }
        .frame(width: width, height: 1)
        .accessibilityHidden(true)
    }
}

/// A ribbon with a V notch cut into its foot.
struct DetailRibbon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.width * 0.55))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The prototype tiles' faint vertical ruling (1 pt every 6 pt).
struct DetailStripes: View {
    let ink: Color
    var body: some View {
        Canvas { context, size in
            var x: CGFloat = 5
            while x < size.width {
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(ink))
                x += 6
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - D5 Progress

struct DetailProgressCard: View {
    let label: String
    let caption: String?
    let progress: Int
    let total: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.detailSF(10, .medium, relativeTo: .footnote))
                        .foregroundStyle(DetailInk.progressLabel)
                    if let caption {
                        Text(caption)
                            .font(.detailSF(9, relativeTo: .caption2))
                            .foregroundStyle(DetailInk.progressCaption)
                    }
                }
                Spacer(minLength: 8)
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(KuroLocale.text("Ep.", "Folge"))
                        .font(.detailSF(10, relativeTo: .footnote))
                        .foregroundStyle(Color.kuroMuted)
                    Text("\(progress)")
                        .font(.detailSF(21, .medium, relativeTo: .title2))
                        .monospacedDigit()
                        .foregroundStyle(Color.kuroInk)
                        .kuroCountRoll(value: progress)
                    if let total {
                        Text("/ \(total)")
                            .font(.detailSF(11, relativeTo: .footnote))
                            .foregroundStyle(Color.kuroMuted.opacity(0.8))
                    }
                }
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(SeriesCopy.position(isManga: false, label: "\(progress)", total: total))
            }
            .padding(.bottom, 12)
            // The prototype row's bottom border (`#344a3914`); its scrub track measures 0 × 1, so no
            // trace is drawn (the count carries the position).
            Rectangle().fill(DetailInk.rowRule).frame(height: 1)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - D6 Episodes

struct AnimeUnitsSection: View {
    let anime: Anime
    let episodes: [Episode]
    let progress: Int
    let total: Int?
    let isTracked: Bool
    let nextUnit: Int?
    let seasonNumber: Int?
    let nextRelease: ReleaseScheduleItem?
    let material: ArtworkMaterial
    let coverURL: URL?
    let savingNext: Bool
    let confirmTrigger: Int
    /// "More episodes" open or closed, kept for the session per title (F3, `DetailFold.units`).
    @Binding var showsAll: Bool
    /// F2: the page scrolls the episodes back into view after they fold, when needed.
    var onCollapse: () -> Void = {}
    let onAdvance: (Int) -> Void

    @Environment(CatalogStore.self) private var catalog
    @Environment(\.openURL) private var openURL
    @State private var allEpisodes: [Episode] = []
    @State private var hasMore = true
    @State private var loadingMore = false
    @State private var openEpisode: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var upNext: Int? { isTracked ? nextUnit : nil }

    /// Collapsed: the last finished episode and the one after Up next (tracked), or the first three.
    private var shownRows: [Episode] {
        if showsAll { return allEpisodes.isEmpty ? episodes : allEpisodes }
        guard isTracked else { return Array(episodes.prefix(3)) }
        let finished = episodes.last { $0.number <= progress }
        let later = episodes.first { $0.number > progress + 1 }
        return [finished, later].compactMap { $0 }
    }

    private var hasMoreToShow: Bool {
        if showsAll { return false }
        if let total { return total > shownRows.count + (upNext == nil ? 0 : 1) }
        return episodes.count > shownRows.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let seasonNumber {
                DetailEyebrow(text: DetailPageCopy.seasonEyebrow(seasonNumber, german: KuroLocale.isGerman), tracking: 1.2)
                    .padding(.bottom, 14)
            }
            DetailSectionHeading(title: KuroLocale.text("Episodes", "Folgen"))
            if let nextRelease {
                KuroReleaseLine(nextRelease, font: .detailSF(10, relativeTo: .footnote), color: DetailInk.progressCaption)
                    .padding(.top, 4)
            }
            if let upNext {
                upNextRow(upNext).padding(.top, 6)
            }
            ForEach(shownRows, id: \.id) { episode in
                row(episode)
            }
            if loadingMore {
                KuroSkeleton(kind: .row).padding(.vertical, 8)
            }
            if hasMoreToShow || showsAll {
                KuroFoldButton(isExpanded: $showsAll,
                               expandLabel: KuroLocale.text("More episodes", "Mehr Folgen"),
                               collapseLabel: KuroLocale.text("Fewer episodes", "Weniger Folgen"),
                               onCollapse: onCollapse) { title, open in
                    HStack {
                        Text(title)
                            .font(.detailSF(11, relativeTo: .footnote))
                        Spacer()
                        Image(systemName: open ? "arrow.up" : "arrow.down")
                            .font(.detailSF(14, .light, relativeTo: .body))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(DetailInk.moreLink)
                    .frame(minHeight: 44)
                }
                .padding(.top, 4)
            }
            if showsAll, hasMore, !allEpisodes.isEmpty, !loadingMore {
                Color.clear.frame(height: 1).onAppear { Task { await loadAll() } }
            }
        }
        .padding(.bottom, 8)
        // Opened by the fold, or restored open from the session's memory (F3): load the full list.
        .task(id: showsAll) {
            guard DetailFold.loadsAllUnits(expanded: showsAll, loadedCount: allEpisodes.count,
                                           hasMore: hasMore, loading: loadingMore) else { return }
            await loadAll()
        }
    }

    private func upNextRow(_ number: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let episode = episodes.first { $0.number == number }
        let thumb = episode?.thumbnail.flatMap(AnimeDetailPage.webURL) ?? coverURL
        return HStack(spacing: 12) {
            Color.clear
                .frame(width: 32, height: 44)
                .overlay {
                    if let thumb {
                        KuroCachedAsyncImage(url: thumb, maxPixelSize: 160) { phase in
                            if case .success(let image) = phase { image.resizable().scaledToFill() } else { Color.clear }
                        }
                    }
                }
                .background(material.edge.color)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(KuroLocale.text("UP NEXT", "ALS NÄCHSTES"))
                    .font(.detailSF(7, .semibold, relativeTo: .caption2))
                    .tracking(1.4)
                    .foregroundStyle(DetailInk.upNextKicker)
                Text(DetailPageCopy.episode(number, german: KuroLocale.isGerman))
                    .font(.detailSF(12, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color.kuroInk)
                if let title = episode.flatMap({ $0.title ?? $0.titleRomaji })?.detailNonEmpty {
                    Text(title)
                        .font(.detailSF(9, relativeTo: .caption2))
                        .foregroundStyle(DetailInk.progressCaption)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            DetailUpNextKey(material: material, pending: savingNext, confirmTrigger: confirmTrigger,
                            accessibilityText: KuroAdvanceCopy.label(medium: .anime, nextUnit: number, title: anime.displayTitle,
                                                                     current: progress, total: total, german: KuroLocale.isGerman)) {
                onAdvance(number)
            }
        }
        // The prototype's 58 pt summary (padding 7/9 → 74): the key sits centred, 14 pt from each edge.
        .frame(minHeight: 58)
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background {
            // The shadow belongs to the row's shape only (on the container it would shadow every child).
            shape.fill(material.wash.color)
                .shadow(color: Color(hex: "344D38", opacity: 0x05 / 255.0), radius: 4, x: 0, y: 3)
        }
        .overlay(shape.strokeBorder(material.edge.color, lineWidth: 1))
        .overlay(alignment: .top) {
            shape.stroke(Color.white, lineWidth: 1).mask(alignment: .top) { Rectangle().frame(height: 1) }
        }
        .padding(.horizontal, -9)
    }

    private func row(_ episode: Episode) -> some View {
        let finished = isTracked && episode.number <= progress
        let description = episode.description?.trimmingCharacters(in: .whitespacesAndNewlines).detailNonEmpty
        let streamURL = ProviderAvailabilityStore.validatedOutboundURL(episode.streamUrl)
        let expandable = Self.isExpandable(description: description, streamURL: streamURL)
        let isOpen = openEpisode == episode.number
        let ink = finished ? DetailInk.finished : Color.kuroInk
        let line = HStack(spacing: 12) {
            Text(String(format: "%02d", episode.number))
                .font(.detailSF(18, .light, relativeTo: .title3))
                .tracking(-1)
                .monospacedDigit()
                .foregroundStyle(DetailInk.finished)
                .frame(minWidth: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(episode.title?.detailNonEmpty ?? DetailPageCopy.episode(episode.number, german: KuroLocale.isGerman))
                    .font(.detailSF(12, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(ink)
                    .lineLimit(2)
                if let state = stateLine(finished: finished, expandable: expandable, episode: episode) {
                    Text(state)
                        .font(.detailSF(9, relativeTo: .caption2))
                        .foregroundStyle(DetailInk.finishedState)
                }
            }
            Spacer(minLength: 8)
            if finished {
                Image(systemName: "checkmark")
                    .font(.detailSF(11, relativeTo: .footnote))
                    .foregroundStyle(DetailInk.finished)
            } else if expandable {
                Image(systemName: "chevron.down")
                    .font(.detailSF(9, relativeTo: .caption2))
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .foregroundStyle(DetailInk.finished)
            }
        }
        // 57 pt as measured; at large type the padding keeps text off the row rules.
        .padding(.vertical, 10)
        .frame(minHeight: 57)
        .contentShape(Rectangle())
        return VStack(alignment: .leading, spacing: 0) {
            // Only a row with details to show is a button (no dead press feedback, no button trait).
            if expandable {
                Button {
                    withAnimation(KuroMotion.detail(KuroMotion.settle, reduceMotion: reduceMotion)) { openEpisode = isOpen ? nil : episode.number }
                } label: { line }
                .buttonStyle(.plain)
                .accessibilityHint(KuroLocale.text("Shows the episode's details", "Zeigt Details zur Folge"))
            } else {
                line.accessibilityElement(children: .combine)
            }
            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    if let description {
                        Text(description)
                            .font(.detailSF(12, relativeTo: .footnote))
                            .foregroundStyle(DetailInk.synopsis)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let streamURL {
                        Button {
                            openURL(streamURL)
                        } label: {
                            Text(KuroLocale.text("Watch ↗", "Ansehen ↗"))
                                .font(.detailSF(11, .medium, relativeTo: .footnote))
                                .foregroundStyle(Color.kuroInk)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 38)
                .padding(.bottom, 10)
            }
        }
        // The prototype's B:1px under every unit row (the last one closes before "More episodes").
        .overlay(alignment: .bottom) { Rectangle().fill(DetailInk.rowRule).frame(height: 1) }
    }

    /// An episode row opens only when it has something to show.
    static func isExpandable(description: String?, streamURL: URL?) -> Bool {
        description?.detailNonEmpty != nil || streamURL != nil
    }

    private func stateLine(finished: Bool, expandable: Bool, episode: Episode) -> String? {
        if finished { return KuroLocale.text("Completed", "Gesehen") }
        if expandable { return KuroLocale.text("Tap for details", "Für Details tippen") }
        return nil
    }

    private func loadAll() async {
        guard !loadingMore, hasMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        let page = await catalog.fetchEpisodesPage(animeId: anime.id, offset: allEpisodes.count, limit: 50)
        guard !Task.isCancelled else { return }
        allEpisodes += page.filter { item in !allEpisodes.contains(where: { $0.id == item.id }) }
        hasMore = page.count == 50
    }
}

/// The detail's Up next key (prototype `.unit-complete`): 44 × 44, radius 12, `base → deep`, white +.
struct DetailUpNextKey: View {
    let material: ArtworkMaterial
    let pending: Bool
    let confirmTrigger: Int
    let accessibilityText: String
    /// 12 on anime; the manga key is 11 (prototype `.unit-complete`).
    var radius: CGFloat = 12
    let action: () -> Void

    var body: some View {
        Button {
            guard !pending else { return }
            KuroAccessibility.selectionHaptic()
            action()
        } label: {
            ZStack {
                Image(systemName: "plus")
                    .font(.kuroCustom(15, weight: .regular, relativeTo: .body, maxSize: 22))
                    .opacity(pending ? 0.4 : 1)
                    .kuroRestore(trigger: confirmTrigger)
                Image(systemName: "checkmark")
                    .font(.kuroCustom(15, weight: .regular, relativeTo: .body, maxSize: 22))
                    .kuroConfirmStamp(trigger: confirmTrigger)
            }
            .foregroundStyle(Color.white)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(DetailUpNextKeyStyle(material: material, trigger: confirmTrigger, radius: radius))
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(pending ? KuroLocale.text("Saving", "Wird gespeichert") : "")
    }
}

private struct DetailUpNextKeyStyle: ButtonStyle {
    let material: ArtworkMaterial
    let trigger: Int
    var radius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let gradient = LinearGradient(colors: [material.base.color, material.deep.color], startPoint: .top, endPoint: .bottom)
        return configuration.label
            .background {
                shape
                    .fill(gradient.shadow(.inner(color: pressed ? Color(hex: "14261B", opacity: 0x25 / 255.0) : Color.white.opacity(0x36 / 255.0),
                                                 radius: pressed ? 1.5 : 0, x: 0, y: pressed ? 2 : 1)))
                    .overlay(shape.strokeBorder(material.base.color, lineWidth: 1))
                    .shadow(color: pressed ? .clear : Color(hex: "23392A", opacity: 0x16 / 255.0), radius: 1, x: 0, y: 2)
                    .kuroPressSettle(trigger: trigger)
            }
            .scaleEffect(pressed ? 0.96 : 1)
            .offset(y: pressed ? 1 : 0)
            .kuroAnimation(KuroMotion.contact, value: pressed)
    }
}

// MARK: - D7 The original story

struct DetailSourceCard: View {
    let item: MediaLadderItem
    let coverage: SeriesDetailBundle.Coverage?
    let seasonNumber: Int?
    /// "Where this season meets the manga" open or closed (F3, `DetailFold.coverage`).
    @Binding var showsCoverage: Bool
    /// F2: the page scrolls the card back into view after the guide folds, when needed.
    var onCollapse: () -> Void = {}
    let onOpen: () -> Void

    private var mapped: SeriesDetailBundle.Coverage? {
        guard let coverage, coverage.mappingState == "exact" || coverage.mappingState == "partial" else { return nil }
        return coverage
    }

    var body: some View {
        let german = KuroLocale.isGerman
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 18) {
                book
                VStack(alignment: .leading, spacing: 0) {
                    DetailEyebrow(text: KuroLocale.text("The original story", "Die Vorlage"), size: 7)
                    Text(item.title)
                        .font(.detailSF(17, .semibold, relativeTo: .title3))
                        .tracking(-0.4)
                        .foregroundStyle(Color.kuroInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .detailLineHeight(23.8, size: 17, relativeTo: .title3)
                        .padding(.top, 6)
                        .padding(.bottom, 2)
                    if let author = item.sourceAuthorName?.detailNonEmpty {
                        Text(author)
                            .font(.detailSF(10, relativeTo: .footnote))
                            .foregroundStyle(DetailInk.author)
                            .detailLineHeight(14, size: 10, relativeTo: .footnote)
                    }
                    Button(action: onOpen) {
                        HStack(spacing: 16) {
                            Text(DetailPageCopy.sourceExplore(format: item.format, german: german))
                                .font(.detailSF(11, relativeTo: .footnote))
                            Image(systemName: "arrow.right")
                                .font(.detailSF(13, .light, relativeTo: .body))
                        }
                        .foregroundStyle(Color.kuroInk)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if mapped != nil, let seasonNumber {
                        Text(german ? "Staffel \(seasonNumber) → Manga" : "Season \(seasonNumber) → manga")
                            .font(.detailSF(8, relativeTo: .caption2))
                            .foregroundStyle(DetailInk.note)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 19)
            .padding(.trailing, 8)
            .overlay(alignment: .top) { Rectangle().fill(DetailInk.sourceRule).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(DetailInk.sourceRule).frame(height: 1) }

            if let mapped {
                let guideTitle = KuroLocale.text("Where this season meets the manga", "Wo diese Staffel im Manga steht")
                KuroFoldButton(isExpanded: $showsCoverage, expandLabel: guideTitle, collapseLabel: guideTitle,
                               onCollapse: onCollapse) { title, open in
                    HStack {
                        Text(title)
                            .font(.detailSF(11, relativeTo: .footnote))
                        Spacer()
                        Text(open ? "−" : "+").font(.detailSF(17, .light, relativeTo: .body))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Color.kuroInk)
                    .frame(minHeight: 48)
                }
                .padding(.horizontal, 4)
                if showsCoverage {
                    VStack(alignment: .leading, spacing: 6) {
                        if let starts = mapped.startsAt { coverageLine(KuroLocale.text("Starts at", "Beginnt bei"), starts) }
                        if let ends = mapped.endsAt { coverageLine(KuroLocale.text("Ends at", "Endet bei"), ends) }
                        if let next = mapped.readNext { coverageLine(KuroLocale.text("Read next", "Weiterlesen ab"), next) }
                        if mapped.mappingState == "partial" {
                            Text(KuroLocale.text("Some chapters differ from the anime.", "Einige Kapitel weichen vom Anime ab."))
                                .font(.detailSF(10, relativeTo: .footnote))
                                .foregroundStyle(DetailInk.author)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 12)
                }
                Rectangle().fill(DetailInk.sourceRule).frame(height: 1)
            }
        }
        .padding(.top, 27)
        .padding(.bottom, 0)
    }

    private func coverageLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.detailSF(11, relativeTo: .footnote)).foregroundStyle(DetailInk.creditRole)
            Spacer()
            Text(value).font(.detailSF(11, .medium, relativeTo: .footnote)).foregroundStyle(Color.kuroInk)
        }
    }

    /// The 原作 book: a page block with a spine, three offset page edges and a short rule.
    /// Prototype `.bridge-book`: page `linear-gradient(100deg, #d6dbce 5px, #fafaf0 5px)` (the 5 pt
    /// spine band runs at 100°, so it shows only as a wedge at the top-left corner), the glyph stack
    /// centred at 14 pt from the top, and a 12 × 1 rule at the foot's trailing edge (measured in
    /// `ref-detail-anime-390.png`: ~7 pt from the right, ~12 pt above the foot, `#516149` at ~65 %).
    private var book: some View {
        ZStack {
            Rectangle().fill(Color(hex: "EDEEDF")).offset(x: 6, y: 2)
            Rectangle().fill(Color(hex: "C7CEBD")).offset(x: 4, y: 1)
            Rectangle().fill(Color(hex: "F6F5E9")).offset(x: 3, y: 1)
            Rectangle().fill(DetailInk.bookPage)
                .overlay(alignment: .topLeading) { DetailBookSpine().fill(DetailInk.bookSpine) }
                .overlay(Rectangle().strokeBorder(DetailInk.bookBorder, lineWidth: 1))
            VStack(spacing: 0) {
                Text("原").font(.detailSF(13, relativeTo: .body))
                Text("作").font(.detailSF(13, relativeTo: .body))
            }
            .foregroundStyle(DetailInk.bookInk)
            .padding(.top, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Rectangle().fill(DetailInk.bookInk.opacity(0.65))
                .frame(width: 12, height: 1)
                .padding(.trailing, 7)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: 57, height: 77)
        .rotationEffect(.degrees(-4))
        .accessibilityHidden(true)
    }
}

/// The 原作 book's spine band: the part of a 100° gradient's first 5 pt that falls inside the page,
/// a wedge from the top-left corner (5.08 pt along the top edge, 28.8 pt down the left edge).
struct DetailBookSpine: Shape {
    func path(in rect: CGRect) -> Path {
        let angle = 100.0 * Double.pi / 180
        // CSS gradient direction (sin a, -cos a); the band holds points whose projection is ≤ 5.
        let dx = sin(angle), dy = -cos(angle)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + min(rect.width, 5 / dx), y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + min(rect.height, 5 / dy)))
        path.closeSubpath()
        return path
    }
}

// MARK: - D8 The sound of it.

struct DetailSoundPanel: View {
    let songs: [ThemeSong]
    let material: ArtworkMaterial
    /// "Show all N songs" open or closed (F3, `DetailFold.songs`).
    @Binding var showsAll: Bool
    /// F2: the page scrolls the panel back into view after it folds, when needed.
    var onCollapse: () -> Void = {}
    @State private var revealed: Set<ThemeSong> = []
    @Environment(\.openURL) private var openURL

    private static let collapsed = 4

    var body: some View {
        let shown = showsAll ? songs : Array(songs.prefix(Self.collapsed))
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(KuroLocale.text("The sound of it.", "So klingt es."))
                    .font(.detailSF(17, .semibold, relativeTo: .title3))
                    .tracking(-0.4)
                    .foregroundStyle(DetailInk.soundInk)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                HStack(alignment: .center, spacing: 3) {
                    ForEach([9.0, 14, 18, 12, 7], id: \.self) { height in
                        Capsule().fill(Color(hex: "A4BAA9")).frame(width: 2, height: height)
                    }
                }
                .accessibilityHidden(true)
            }
            .padding(.bottom, 8)
            ForEach(Array(shown.enumerated()), id: \.offset) { _, song in
                // The prototype's B:1px #ffffff14 under every song row, the last one included.
                row(song)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0x14 / 255.0)).frame(height: 1) }
            }
            if songs.count > Self.collapsed {
                KuroFoldButton(isExpanded: $showsAll,
                               expandLabel: KuroLocale.text("Show all \(songs.count) songs", "Alle \(songs.count) Songs zeigen"),
                               collapseLabel: KuroLocale.text("Show fewer", "Weniger zeigen"),
                               onCollapse: onCollapse) { title, _ in
                    Text(title)
                        .font(.detailSF(11, .medium, relativeTo: .footnote))
                        .foregroundStyle(DetailInk.soundInk)
                        .frame(minHeight: 44)
                }
            }
            if songs.allSatisfy({ $0.source.lowercased() == "animethemes" }) {
                Text(KuroLocale.text("via AnimeThemes", "über AnimeThemes"))
                    .font(.detailSF(9, relativeTo: .caption2))
                    .foregroundStyle(DetailInk.soundNote)
                    .padding(.top, 13)
            }
        }
        .padding(.top, 19)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background {
            // The shadow sits on the panel's shape, not on its rows and keys.
            shape.fill(LinearGradient(colors: [material.base.color, material.deep.color], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: Color(hex: "14291C", opacity: 0x0B / 255.0), radius: 7, x: 0, y: 6)
        }
        .overlay(shape.strokeBorder(material.base.color, lineWidth: 1))
        .padding(.top, 25)
    }

    private func kicker(_ song: ThemeSong) -> String {
        let german = KuroLocale.isGerman
        let kind: String
        switch song.kind {
        case .opening: kind = "Opening"
        case .ending: kind = "Ending"
        case .insert: kind = german ? "Insert-Song" : "Insert song"
        }
        var parts = [song.sequence.map { "\(kind) \($0)" } ?? kind]
        if let episodes = song.episodes?.detailNonEmpty { parts.append(Self.episodes(episodes, german: german)) }
        return parts.joined(separator: " · ")
    }

    /// "Ep. 1–5" / "Folge 3" / "Folgen 1–5" (§7.1 uses "Folge N"; "F." is not a German abbreviation).
    static func episodes(_ value: String, german: Bool) -> String {
        guard german else { return "Ep. " + value }
        let plural = value.contains(where: { "–-—,&".contains($0) }) || value.lowercased().contains("bis")
        return (plural ? "Folgen " : "Folge ") + value
    }

    private func row(_ song: ThemeSong) -> some View {
        let hidden = song.isSpoiler && !revealed.contains(song)
        return HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(song.kind.rawValue)
                    .font(.detailSF(12, .medium, relativeTo: .subheadline))
                    .tracking(-0.8)
                    .foregroundStyle(material.base.color)
                    .padding(.vertical, 4)
                    .overlay(alignment: .top) { Rectangle().fill(Color(hex: "546B52", opacity: 0x35 / 255.0)).frame(height: 1) }
                    .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: "546B52", opacity: 0x35 / 255.0)).frame(height: 1) }
            }
            .frame(width: 43, height: 43)
            .background(material.wash.color, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color(hex: "E5ECD8", opacity: 0x4C / 255.0), lineWidth: 1))
            .accessibilityLabel(song.spokenLabel(german: KuroLocale.isGerman))

            VStack(alignment: .leading, spacing: 0) {
                Text(kicker(song))
                    .font(.detailSF(8, relativeTo: .caption2))
                    .tracking(0.2)
                    .foregroundStyle(DetailInk.soundKicker)
                    .detailLineHeight(11.2, size: 8, relativeTo: .caption2)
                if hidden {
                    Button {
                        revealed.insert(song)
                    } label: {
                        Text(KuroLocale.text("Spoiler. Tap to show.", "Spoiler. Zum Anzeigen tippen."))
                            .font(.detailSF(13, .medium, relativeTo: .subheadline))
                            .foregroundStyle(DetailInk.soundInk)
                            .frame(minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(song.title)
                        .font(.detailSF(13, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(DetailInk.soundInk)
                        .lineLimit(2)
                        .detailLineHeight(16.25, size: 13, relativeTo: .subheadline)
                        .padding(.vertical, 4)
                    if let artist = song.artist?.detailNonEmpty {
                        Text(artist)
                            .font(.detailSF(10, relativeTo: .footnote))
                            .foregroundStyle(DetailInk.soundArtist)
                            .lineLimit(1)
                            .detailLineHeight(14, size: 10, relativeTo: .footnote)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: hidden ? .contain : .combine)

            if !hidden { listen(song) }
        }
        // 78 pt rows as measured (padding 12/0 around a 54 pt line block).
        .frame(minHeight: 54)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func listen(_ song: ThemeSong) -> some View {
        let apple = song.appleMusicSearchURL
        let spotify = song.spotifySearchURL
        if apple != nil || spotify != nil {
            Menu {
                if let apple { Button("Apple Music") { openURL(apple) } }
                if let spotify { Button("Spotify") { openURL(spotify) } }
            } label: {
                Image(systemName: "arrow.up.right")
                    .font(.detailSF(12, relativeTo: .footnote))
                    .foregroundStyle(DetailInk.soundArrow)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0x18 / 255.0), lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(KuroLocale.text("Listen to \(song.title)", "\(song.title) anhören"))
            .accessibilityHint(KuroLocale.text("Searches Apple Music or Spotify.", "Sucht in Apple Music oder Spotify."))
        }
    }
}

// MARK: - D9 The characters.

struct DetailCharactersRail: View {
    let characters: [(character: Character, role: String)]
    /// Manga: square-cut portraits (radius 2) at the prototype's 0.6 saturation.
    var bookish = false
    @Environment(\.kuroRoutes) private var routes
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 67 pt cards (prototype); wider at accessibility sizes so names never break inside a word.
    private var cardWidth: CGFloat { dynamicTypeSize.isAccessibilitySize ? 124 : 67 }

    private var shown: [(character: Character, role: String)] { Self.shown(characters) }

    /// The rail's cards: background roles dropped, main then supporting, at most 12. The page's section
    /// input counts this same list, so a cast of only background roles shows no heading.
    static func shown(_ characters: [(character: Character, role: String)]) -> [(character: Character, role: String)] {
        let rank: (String) -> Int = { role in
            switch role.uppercased() { case "MAIN": return 0; case "SUPPORTING": return 1; default: return 2 }
        }
        return characters
            .filter { $0.role.lowercased() != "background" }
            .enumerated()
            .sorted { lhs, rhs in
                let l = rank(lhs.element.role), r = rank(rhs.element.role)
                return l == r ? lhs.offset < rhs.offset : l < r
            }
            .prefix(12)
            .map(\.element)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailSectionHeading(title: KuroLocale.text("The characters.", "Die Figuren."),
                                 note: KuroLocale.text("Tap to meet", "Zum Kennenlernen tippen"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(shown, id: \.character.id) { item in
                        Button {
                            // Pushed inside the journey (navigation contract N9); Back returns here.
                            routes.openPage(DetailNavigation.characterPage(item.character))
                        } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                Color.clear
                                    .frame(width: cardWidth, height: cardWidth * 84 / 67)
                                    .overlay {
                                        if let url = item.character.imageLarge.flatMap(AnimeDetailPage.webURL) {
                                            KuroCachedAsyncImage(url: url, maxPixelSize: 240) { phase in
                                                if case .success(let image) = phase {
                                                    image.resizable().scaledToFill().saturation(bookish ? 0.6 : 1)
                                                } else { Color.clear }
                                            }
                                        }
                                    }
                                    .background(DetailInk.portrait)
                                    .clipShape(RoundedRectangle(cornerRadius: bookish ? 2 : 8, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: bookish ? 2 : 8, style: .continuous).strokeBorder(Color.black.opacity(0x11 / 255.0), lineWidth: 1))
                                // The prototype's name box: 9 pt above two 15 pt lines (44 pt), kept for
                                // one-line names so the rail ends at the same depth.
                                Text(item.character.nameFull ?? DetailCopy.unknown(german: KuroLocale.isGerman))
                                    .font(.detailSF(10, relativeTo: .footnote))
                                    .lineSpacing(15 - 12)
                                    .foregroundStyle(Color.kuroInk)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(width: cardWidth, alignment: .topLeading)
                                    .frame(minHeight: 35, alignment: .topLeading)
                                    .padding(.top, 9)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(KuroPressStyle())
                        .accessibilityLabel(item.character.nameFull ?? DetailCopy.unknown(german: KuroLocale.isGerman))
                    }
                }
                .padding(.top, 5)
                .padding(.bottom, 7)
                .padding(.horizontal, 1)
            }
            .scrollClipDisabled()
            .padding(.top, 13)
        }
        // 30 pt above the heading: the prototype's section margin (the card above it, when there is one,
        // collapses its own 30 pt bottom margin into this one).
        .padding(.top, 30)
    }
}

// MARK: - D10 Behind the frames.

struct DetailCreditsList: View {
    let title: String
    let rows: [DetailCreditRow]
    /// Drawn under the rows (the manga page's "Read with the publisher").
    var footer: AnyView? = nil
    @Environment(\.kuroRoutes) private var routes

    /// A row with a target pushes its page inside the journey (staff, studio, author, or the ladder's
    /// original work as a title; navigation contract N9).
    private func open(_ target: DetailCreditRow.Target) {
        guard let page = DetailNavigation.creditPage(target) else { return }
        routes.openPage(page)
    }

    /// 40.4 pt as measured (padding 12/0, 11/15.4); the row's 44 pt target reaches 2 pt past each rule.
    private func creditLine(_ row: DetailCreditRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 15) {
            Text(row.role)
                .font(.detailSF(11, relativeTo: .footnote))
                .foregroundStyle(DetailInk.creditRole)
            Spacer(minLength: 8)
            Text(row.name)
                .font(.detailSF(11, .semibold, relativeTo: .footnote))
                .foregroundStyle(Color.kuroInk)
                .multilineTextAlignment(.trailing)
        }
        .detailLineHeight(15.4, size: 11, relativeTo: .footnote)
        .padding(.vertical, 12)
        .contentShape(Rectangle().inset(by: -2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailSectionHeading(title: title).padding(.bottom, 13)
            ForEach(rows) { row in
                Group {
                    if row.isInteractive {
                        Button { open(row.target) } label: { creditLine(row) }
                            .buttonStyle(.plain)
                    } else {
                        creditLine(row)
                    }
                }
                .overlay(alignment: .bottom) { Rectangle().fill(DetailInk.creditRule).frame(height: 1) }
                .accessibilityElement(children: .combine)
            }
            if let footer { footer }
        }
        .padding(.top, 30)
    }
}

// MARK: - Share

/// Presents the system share sheet for the page's deep link (the live dock's Share).
@MainActor
enum DetailShare {
    static func present(url: URL, subject: String) {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.keyWindow?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        controller.popoverPresentationController?.sourceView = top.view
        top.present(controller, animated: true)
    }
}

extension String {
    /// nil for an empty or whitespace-only string.
    var detailNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
