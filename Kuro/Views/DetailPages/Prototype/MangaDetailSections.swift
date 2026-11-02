import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Manga detail page (prototype fidelity, Task 7; spec §5.2; ref-detail-manga-390.png)
// The one manga detail for everybody (series flags on or off). Data comes from the existing owners:
// | Read                                         | Owner                       | Feeds                                        |
// | -------------------------------------------- | --------------------------- | -------------------------------------------- |
// | `fetchMediaLadder`                           | CatalogStore                | "Seen the anime?" (the ladder's adaptation)  |
// | authors / characters (credits_cast_v1)       | CatalogStore                | "Behind the pages.", "The characters."       |
// | `fetchChaptersNext` / `fetchChaptersPage`    | CatalogStore                | chapter rows (only when real), More chapters |
// | `resolveReadLinks`                           | ProviderAvailabilityStore   | Where to read, "Read legally", chapter rows  |
// | `fetchExternalLinks` (the adaptation's)      | CatalogStore                | "Official anime site ↗"                      |
// | `clubActivityForMedia` (cached bundles)      | ClubsStore                  | club rails holding this title ("Between us.") |
// | `mediaSchedule`                              | ReleasesStore (`.detailReleases`) | the next release line under Chapters   |
// | `detailBundle` (series flags on only)        | HomeStore                   | `detail_copy` hook/premise, watched guide    |
// | friend activity (`FriendsActivitySection`)   | SocialActivityStore         | club presence, "Between us." (social_activity_v1) |
// Loading: the hero and story draw at once; the other sections wait behind `KuroSkeleton(.detailSection)`
// until the ladder, the first chapters, credits and read links settle, and an offline band with Try
// again sits under the hero. A failed ladder read shows the branded failed state with Try again; the
// chapter, credit and link owners still answer a failed read with an empty list (open item).
// Tracking writes go through `LibraryActions.apply` (`DetailAdvance`: a +1 on a Planned title also
// makes it Reading), `LibraryActions.remove` (asked first, with Undo) and the shared tracking editor
// route; the page acts only on the entry that is open.
//
// Look (PROTOTYPE_SPEC.md §4 manga tables, instrument.css `dialog[data-rich=true][data-medium=manga]`):
// paper `#f6f5ef`; the intro band is the artwork `wash → #faf9f2` with a faint 7 pt ruling (the
// prototype's measured band; the anime band is `base → deep`); the serif appears on the title, the
// hook, "Your bookmark", chapter numbers (italic) and "Seen the anime?".

/// Everything the page shows besides the catalogue row and the Library entry. Fixture renders pass a
/// complete value; the live page fills it from the owners above.
struct MangaDetailContent {
    var adaptation: MediaLadderItem? = nil
    var characters: [(character: Character, role: String)] = []
    var authors: [(author: Author, role: String)] = []
    var chapters: [MangaChapter] = []
    var readLinks: [ProviderSheetItem] = []
    /// Availability freshness for the provider sheet ("Checked 2 days ago."), when there is one.
    var readStatusCaption: String? = nil
    /// The anime adaptation's official site (its external links), when it has a valid one.
    var adaptationSite: URL? = nil
    var bundle: SeriesDetailBundle? = nil
    var friendsPreview: SocialActivityStore.FriendActivityResponse? = nil
}

/// The manga sheet's measured colours.
enum MangaInk {
    static let paper = Color(hex: "F6F5EF")
    static let bandEnd = Color(hex: "FAF9F2")
    static let bandRule = Color(hex: "D2D4C6")
    static let ruling = Color(hex: "242920", opacity: Double(0x03) / 255)
    static let kicker = Color(hex: "62695B")
    static let closeFill = Color(hex: "EDEEDF", opacity: Double(0xEF) / 255)
    static let closeInk = Color(hex: "394631")
    static let bodyGlow = Color(hex: "ADB497", opacity: Double(0x16) / 255)
    static let adaptationCaption = Color(hex: "687668")
    static let symbolFill = Color(hex: "F7F8F0")
    static let guideShadow = Color(hex: "E0E4D9", opacity: Double(0x66) / 255)
    static let publisherRule = Color(hex: "BFC7B7")
    static let publisherCaption = Color(hex: "6F7769")
    static let guideText = Color(hex: "65745E")
}

struct MangaDetailPage: View {
    let manga: Manga
    private let preview: MangaDetailContent?

    init(manga: Manga, preview: MangaDetailContent? = nil) {
        self.manga = manga
        self.preview = preview
        self._content = State(initialValue: preview ?? MangaDetailContent())
        self._pending = State(initialValue: preview == nil ? DetailLoadPart.manga : [])
    }

    @Environment(CatalogStore.self) private var catalog
    @Environment(FeatureFlags.self) private var flags
    @Environment(HomeStore.self) private var home
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @Environment(ArtworkMaterialStore.self) private var materials
    @Environment(ClubsStore.self) private var clubs
    @Environment(ProviderAvailabilityStore.self) private var availability
    @Environment(OutboundLinkTelemetry.self) private var outboundLinks
    @Environment(\.kuroRoutes) private var routes
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Optional: fixture hosts may not inject one (then the page counts as online).
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?

    @State private var content: MangaDetailContent
    @State private var releaseItems: [ReleaseScheduleItem]?
    @State private var releaseSongs: [ThemeSong]?
    @State private var roster: [SocialActivityStore.FriendTitleActivity] = []
    @State private var toast: KuroToastState?
    @State private var toastTask: Task<Void, Never>?
    @State private var showVerdict = false
    @State private var showProviders = false
    @State private var actionScope = AccountActionScope()
    @State private var confirmTrigger = 0
    @State private var savingNext = false
    @State private var loadGeneration = UUID()
    @State private var creditsGeneration = UUID()
    /// First loads still pending (the skeleton holds the page's lower sections until they settle).
    @State private var pending: Set<DetailLoadPart>
    /// Try again (offline band) and a reconnect reload the page's reads.
    @State private var reloadToken = 0
    /// The ladder read failed (not "no adaptation"): the failed state with Try again shows.
    @State private var ladderFailed = false
    /// The entry a confirmed "Remove from list" will remove.
    @State private var pendingRemoval: LibraryEntry?

    private var german: Bool { KuroLocale.isGerman }
    private var entry: LibraryEntry? { library.entry(for: manga.libraryKey) }
    private var progress: Int { entry?.progress ?? 0 }
    private var total: Int? { MangaDetailSections.bookmarkTotal(chapterCount: manga.chapterCount) }
    private var upcoming: [ReleaseScheduleItem] { DetailNextReleaseSection.upcoming(releaseItems ?? []) }
    private var nextChapter: Int? {
        MangaDetailSections.nextChapter(progress: progress, chapterCount: manga.chapterCount, status: manga.status,
                                        scheduledNext: DetailSectionPolicy.scheduledNext(upcoming, kind: .chapter))
    }
    /// The best legal read link (chapter rows open it, as the legacy rows did).
    private var readLink: ProviderSheetItem? { MangaDetailSections.publisherLink(from: content.readLinks) }

    private var coverURL: URL? {
        [manga.coverImageLarge, manga.coverImageMedium].compactMap { $0.flatMap(AnimeDetailPage.webURL) }.first
    }

    private var material: ArtworkMaterial {
        materials.material(for: coverURL, seedHex: manga.coverImageColor)
    }

    private var copy: SeriesDetailBundle.Copy? {
        guard let copy = content.bundle?.copy, copy.storyState == "present" || copy.storyState == "source" else { return nil }
        return copy
    }

    private var hook: String? { copy?.hook?.detailNonEmpty }

    private var credits: [DetailCreditRow] { DetailCreditRow.manga(authors: content.authors, german: german) }
    private var publisher: ProviderSheetItem? { readLink }
    /// `social_activity_v1`: the server kill switch for notes, reactions and the club roster.
    private var socialEnabled: Bool { flags.isSocialActivityV1Enabled }
    private var clubPeople: Int { socialEnabled && !clubs.myClubs.isEmpty ? roster.count : 0 }
    private var clubRails: [ClubMediaActivity] { clubs.clubActivityForMedia(mediaId: manga.id, mediaType: "MANGA") }
    private var isOffline: Bool { network?.isConnected == false }
    private var reloadKey: String { "\(reloadToken)-\(network?.reconnectionGeneration ?? 0)" }

    private var input: DetailInput {
        MangaDetailSections.input(hasSynopsis: manga.hasMeaningfulSynopsis, hasHook: hook != nil,
                                  clubPeople: clubPeople, isTracked: entry != nil, chapters: content.chapters,
                                  nextChapter: nextChapter, hasAdaptation: content.adaptation != nil,
                                  characterCount: DetailCharactersRail.shown(content.characters).count,
                                  creditRows: credits.count,
                                  hasPublisherLink: publisher != nil, hasClubs: !clubs.myClubs.isEmpty,
                                  socialEnabled: socialEnabled, clubRailCount: clubRails.count)
    }

    var body: some View {
        let sections = DetailSectionPolicy.sections(for: input)
        let origin = actionScope.capture(session: libraryActions.accountSession)
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    if isOffline {
                        KuroOfflineView(hasContent: true) { reloadToken += 1 }
                            .padding(.horizontal, 24)
                            .padding(.top, 14)
                            .kuroReadableWidth()
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(DetailLoadPart.visibleSections(sections, settled: pending.isEmpty), id: \.self) { section in
                            sectionView(section, sections: sections, origin: origin, proxy: proxy)
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
                    .background(alignment: .topLeading) {
                        // The prototype body's faint olive light from the top-left corner.
                        EllipticalGradient(colors: [MangaInk.bodyGlow, .clear], center: .topLeading,
                                           startRadiusFraction: 0, endRadiusFraction: 0.5)
                            .frame(height: 400)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(MangaInk.paper.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            DetailCloseButton(material: material, fill: MangaInk.closeFill, ink: MangaInk.closeInk)
        }
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
        .task(id: "\(manga.id)-\(reloadKey)") { await loadPage() }
        .task(id: "\(manga.id)-\(flags.isCreditsCastV1Enabled)-\(reloadKey)") { await loadCredits() }
        .task(id: "\(manga.id)-chapters-\(progress)-\(reloadKey)") { await loadChapters() }
        .task(id: "\(manga.id)-links-\(reloadKey)") { await loadReadLinks() }
        // A cold open (deep link) before the Clubs page ran: warm the clubs so "Between us." can show.
        .task(id: manga.id) {
            guard preview == nil, clubs.myClubs.isEmpty else { return }
            await clubs.refreshMyClubsIfStale()
        }
        .detailReleases(kind: .manga, id: manga.id, schedule: $releaseItems, songs: $releaseSongs)
        .sheet(isPresented: $showVerdict) {
            QuickVerdictPickerSheet(media: manga, onToast: showToast)
        }
        .confirmationDialog(DetailRemoval.confirmTitle(german: german),
                            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                            titleVisibility: .visible, presenting: pendingRemoval) { removed in
            Button(DetailRemoval.confirmAction(german: german), role: .destructive) { remove(removed) }
            Button(KuroLocale.text("Cancel", "Abbrechen"), role: .cancel) {}
        } message: { _ in
            Text(DetailRemoval.confirmMessage(kind: .manga, german: german))
        }
        .sheet(isPresented: $showProviders) {
            ProviderSelectionSheet(title: KuroLocale.text("Read on", "Lesen bei"),
                                   links: content.readLinks, statusCaption: content.readStatusCaption) { link in
                if let url = ProviderAvailabilityStore.validatedOutboundURL(link.url) {
                    outboundLinks.recordOutboundLink(mediaType: "MANGA", mediaId: manga.id, linkKind: "provider_sheet", provider: link.title)
                    openURL(url)
                }
            }
        }
        // The page's own presentation context: the adaptation card and the editor open here.
        .routePresenter()
    }

    // MARK: Sections

    @ViewBuilder
    private func sectionView(_ section: DetailSection, sections: [DetailSection],
                             origin: AccountActionScope.Ticket?, proxy: ScrollViewProxy) -> some View {
        switch section {
        case .hero, .seasons, .songs:
            EmptyView()
        case .story:
            DetailStorySection(eyebrow: MangaDetailCopy.seriesOverview(german: german),
                               hook: hook,
                               synopsis: manga.hasMeaningfulSynopsis ? manga.displayDescription : copy?.synopsis?.detailNonEmpty,
                               aboutTitle: DetailPageCopy.aboutTitle(isSeason: false, german: german),
                               expectation: nil,
                               serifHook: true,
                               premise: hook == nil ? nil : copy?.premise?.detailNonEmpty)
        case .clubPresence:
            DetailClubPresence(names: DetailBetweenUs.rosterNames(roster), count: clubPeople) {
                // Reduce Motion: the jump is instant (prototype §6).
                withAnimation(KuroMotion.detail(KuroMotion.medium, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(DetailSection.betweenUs, anchor: .top)
                }
            }
            .padding(.bottom, 15)
        case .progress:
            MangaBookmarkCard(progress: progress, total: total,
                              caption: MangaDetailSections.bookmarkCaption(total: total,
                                                                           releasing: manga.status?.uppercased() == "RELEASING",
                                                                           german: german),
                              material: material)
                .padding(.top, 16)
                .overlay(alignment: .top) {
                    // The prototype's season-workspace rule (`--art-edge`) above the bookmark.
                    Rectangle().fill(material.edge.color).frame(height: 1).padding(.horizontal, -8)
                }
                .padding(.top, 13)
                .padding(.bottom, 16)
        case .units:
            MangaChaptersSection(manga: manga, chapters: content.chapters, progress: progress, total: total,
                                 isTracked: entry != nil, nextChapter: nextChapter,
                                 nextRelease: DetailNextReleaseSection.upcoming(releaseItems ?? []).first,
                                 material: material, coverURL: coverURL, savingNext: savingNext,
                                 confirmTrigger: confirmTrigger,
                                 readLinkTitle: readLink?.title,
                                 onReadChapter: readLink == nil ? nil : { openChapter($0) }) { next in
                advance(to: next, origin: origin)
            }
            .padding(.top, sections.contains(.progress) ? 6 : 0)
        case .source:
            if let adaptation = content.adaptation {
                MangaAdaptationCard(item: adaptation, guides: content.bundle?.adaptations ?? [], material: material,
                                    officialSite: content.adaptationSite,
                                    onOpenSite: { openOfficialSite(adaptation) }) { id in
                    routes.openMedia(MediaRoute(kind: .anime, id: id))
                }
            }
        case .characters:
            DetailCharactersRail(characters: content.characters, bookish: true)
        case .credits:
            DetailCreditsList(title: KuroLocale.text("Behind the pages.", "Hinter den Seiten."), rows: credits,
                              footer: publisher.map { link in
                                  AnyView(MangaPublisherRow(caption: MangaDetailSections.publisherCaption(link, count: content.readLinks.count,
                                                                                                        german: german),
                                                            action: openProviders)
                                      .padding(.top, credits.isEmpty ? 0 : 28))
                              })
        case .betweenUs:
            DetailBetweenUs(mediaType: "MANGA", mediaId: manga.id, coverURL: coverURL,
                            socialEnabled: socialEnabled, clubRails: clubRails,
                            onRoster: { roster = $0 }, preview: content.friendsPreview, bookish: true)
                .padding(.top, 28)
                .padding(.bottom, 18)
                .id(DetailSection.betweenUs)
        }
    }

    private var hero: some View {
        MangaDetailHero(coverURL: coverURL, title: content.bundle?.header.title ?? manga.displayTitle, material: material) {
            DetailStatusMark(entry: entry, kind: .manga,
                             onListSettings: { routes.presentTrackingEditor(TrackingEditorRequest(media: manga)) },
                             onFavourite: toggleSaved,
                             onVerdict: { showVerdict = true },
                             onProviders: openProviders,
                             onAddToClub: { routes.presentAddToClub(manga.libraryKey) },
                             onShare: share,
                             tone: .onPaper)
        }
    }

    // MARK: Actions (the anime page's paths, on the entry that is open)

    private func advance(to next: Int, origin: AccountActionScope.Ticket?) {
        guard !savingNext, actionScope.isCurrent(origin, session: libraryActions.accountSession) else { return }
        let key = manga.libraryKey
        let status = entry?.status
        let capped = total.map { min(next, $0) } ?? next
        savingNext = true
        let launched = actionScope.launch(origin: origin, session: libraryActions.accountSession) { ticket in
            // A Planned title becomes Reading in the same edit (Home's in-progress scene follows).
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
        let key = manga.libraryKey
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
        let key = manga.libraryKey
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
        let key = manga.libraryKey
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
        let key = manga.libraryKey
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
        // The read-links answer is still out: say so, never "no link" before the answer.
        guard !pending.contains(.links) else {
            showToast(KuroToastState(kind: .info,
                                     title: KuroLocale.text("Still checking where to read. Try again in a moment.",
                                                            "Wir prüfen noch, wo du lesen kannst. Versuch es gleich noch einmal."),
                                     subtitle: nil, actionTitle: nil, onAction: nil))
            return
        }
        guard let primary = publisher, let url = ProviderAvailabilityStore.validatedOutboundURL(primary.url) else {
            showToast(KuroToastState(kind: .info,
                                     title: KuroLocale.text("No legal provider link is available yet.", "Noch kein legaler Anbieter-Link verfügbar."),
                                     subtitle: nil, actionTitle: nil, onAction: nil))
            return
        }
        if content.readLinks.count > 1 {
            showProviders = true
        } else {
            outboundLinks.recordOutboundLink(mediaType: "MANGA", mediaId: manga.id, linkKind: "read", provider: primary.title)
            openURL(url)
        }
    }

    /// A chapter row opens the best legal read link (the legacy rows' behaviour: the catalogue has no
    /// per-chapter reader URL).
    private func openChapter(_ chapter: MangaChapter) {
        guard let link = readLink, let url = ProviderAvailabilityStore.validatedOutboundURL(link.url) else { return }
        KuroAccessibility.impactHaptic(.light)
        outboundLinks.recordOutboundLink(mediaType: "MANGA", mediaId: manga.id, linkKind: "chapter", provider: link.title)
        openURL(url)
    }

    private func openOfficialSite(_ adaptation: MediaLadderItem) {
        guard let url = content.adaptationSite.flatMap({ ProviderAvailabilityStore.validatedOutboundURL($0.absoluteString) }) else { return }
        outboundLinks.recordOutboundLink(mediaType: "ANIME", mediaId: adaptation.mediaId, linkKind: "official_site", provider: url.host ?? "official")
        openURL(url)
    }

    private func share() {
        guard let url = URL(string: "kuro://manga/\(manga.id)") else { return }
        DetailShare.present(url: url, subject: manga.displayTitle)
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
        // Series flags on: the bundle adds `detail_copy` hooks and the watched-anime guide when it has
        // them. Read alongside the ladder, not after it.
        async let bundleRead = readBundle()
        #endif
        let ladder = await catalog.fetchMediaLadder(mediaType: "MANGA", mediaId: manga.id)
        guard !Task.isCancelled, loadGeneration == generation else { return }
        ladderFailed = DetailReadState.ladderFailed(ladder)
        let adaptation = MangaDetailSections.animeAdaptation(in: ladder)
        content.adaptation = adaptation
        if let adaptation {
            let links = await catalog.fetchExternalLinks(mediaType: "ANIME", mediaId: adaptation.mediaId)
            guard !Task.isCancelled, loadGeneration == generation else { return }
            content.adaptationSite = MangaDetailSections.officialSite(in: links)
        }
        #if canImport(Supabase)
        if let bundle = await bundleRead {
            guard !Task.isCancelled, loadGeneration == generation else { return }
            content.bundle = bundle
        }
        #endif
        await catalog.enqueueMediaRelationRefreshIfNeeded(mediaType: "MANGA", mediaId: manga.id, ladder: ladder, reason: "detail_open")
    }

    #if canImport(Supabase)
    private func readBundle() async -> SeriesDetailBundle? {
        guard flags.seriesHomeNativeV1Enabled else { return nil }
        return try? await home.detailBundle(medium: "manga", mediaId: manga.id, sectionId: nil)
    }
    #endif

    private func loadCredits() async {
        guard preview == nil else { return }
        defer { pending.remove(.credits) }
        let generation = UUID()
        creditsGeneration = generation
        guard flags.isCreditsCastV1Enabled else {
            // The flag turned off: the sections go with it.
            content.authors = []
            content.characters = []
            return
        }
        async let authors = catalog.fetchAuthorsForManga(mangaId: manga.id)
        async let cast = catalog.fetchCharactersForManga(mangaId: manga.id)
        let (loadedAuthors, loadedCast) = await (authors, cast)
        guard !Task.isCancelled, creditsGeneration == generation, flags.isCreditsCastV1Enabled else { return }
        content.authors = loadedAuthors
        content.characters = loadedCast
    }

    private func loadChapters() async {
        guard preview == nil else { return }
        defer { pending.remove(.units) }
        let loaded = await catalog.fetchChaptersNext(mangaId: manga.id, fromNumber: max(1, progress), limit: 10)
        guard !Task.isCancelled else { return }
        content.chapters = loaded
    }

    private func loadReadLinks() async {
        guard preview == nil else { return }
        defer { pending.remove(.links) }
        let snapshot = await availability.resolveReadLinks(mangaId: manga.id)
        guard !Task.isCancelled, let snapshot else { return }
        content.readLinks = snapshot.all
        content.readStatusCaption = snapshot.statusCaption
    }
}

// MARK: - D1 Hero (manga)

/// The folio intro band: the cover as a book (stacked page edges) beside the kicker, the serif title
/// and the status mark, on `wash → #faf9f2` with the prototype's faint horizontal ruling.
struct MangaDetailHero<Mark: View>: View {
    let coverURL: URL?
    let title: String
    let material: ArtworkMaterial
    @ViewBuilder let mark: () -> Mark
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    LinearGradient(colors: [material.wash.color, MangaInk.bandEnd],
                                   startPoint: UnitPoint(x: 0, y: 0.32), endPoint: UnitPoint(x: 1, y: 0.68))
                    MangaRuling()
                }
                .ignoresSafeArea(edges: .top)
            }
            .overlay(alignment: .bottom) { Rectangle().fill(MangaInk.bandRule).frame(height: 1) }
    }

    @ViewBuilder
    private var content: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 18) {
                book.frame(width: 96)
                heading(titleSize: 29)
            }
            .padding(.top, 72)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        } else {
            ViewThatFits(in: .horizontal) {
                row(inset: 24, gap: 23, titleSize: 29, titleWidth: 176)
                // Small phones (prototype ≤360): tighter inset, 26 pt title.
                row(inset: 20, gap: 18, titleSize: 26, titleWidth: 125)
            }
        }
    }

    /// The prototype's folio band at its measured size (padding 28/24/24, a 107 × 161 cover, a heading
    /// column of at most 176 pt, so "Chainsaw Man" breaks onto two lines as in the reference). A wider
    /// sheet leaves the extra width beside the heading, under the close control.
    private func row(inset: CGFloat, gap: CGFloat, titleSize: CGFloat, titleWidth: CGFloat) -> some View {
        HStack(alignment: .center, spacing: gap) {
            // 35 % of the prototype's 306 pt content width (107 pt), smaller on narrower phones.
            book.containerRelativeFrame(.horizontal) { width, _ in min(107.1, max(0, width - inset * 2) * 0.35) }
            heading(titleSize: titleSize)
                .frame(minWidth: min(titleWidth, 125), maxWidth: titleWidth, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.top, 28)
        .padding(.horizontal, inset)
        .padding(.bottom, 24)
    }

    private func heading(titleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(DetailPageCopy.kindKicker(.manga, german: KuroLocale.isGerman).uppercased())
                .font(.detailSF(8, relativeTo: .caption2))
                .tracking(1.7)
                .foregroundStyle(MangaInk.kicker)
            Text(title)
                .font(.detailGeorgia(titleSize, relativeTo: .title1))
                .tracking(-1)
                .foregroundStyle(Color.kuroInk)
                // Review focus 1: three lines at most; a word wider than the column shrinks a little
                // before anything is cut (a two-line title such as "Chainsaw / Man" keeps its size).
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                // m 9/0/15 around a 31.9 pt CSS line; Georgia's own line box sits a little higher.
                .padding(.top, 11)
                .padding(.bottom, 19)
                .accessibilityAddTraits(.isHeader)
            mark()
        }
    }

    /// The cover as a closed book: the page block's offset edges on the right and below, a 3 pt spine
    /// shade, and the skewed page stack under it (prototype `.detail-object img` box-shadow
    /// `#f8f7ef 4 2, #bbb9ae 5 2, #f4f2e9 8 4, #c6c2b6 9 4` + drop shadow). Only the cover is clipped;
    /// the page edges and the shadow sit behind it, outside the clip.
    private var book: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2, bottomTrailingRadius: 5,
                                           topTrailingRadius: 5, style: .continuous)
        return Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                if let coverURL {
                    KuroCachedAsyncImage(url: coverURL, maxPixelSize: 600) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFill() } else { Color(hex: "E1E4DB") }
                    }
                } else {
                    Color(hex: "E1E4DB")
                }
            }
            .overlay(alignment: .leading) {
                LinearGradient(colors: [Color.black.opacity(0x22 / 255.0), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 3)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0x45 / 255.0), lineWidth: 1))
            .background {
                ZStack {
                    shape.fill(Color(hex: "C6C2B6")).offset(x: 9, y: 4)
                    shape.fill(Color(hex: "F4F2E9")).offset(x: 8, y: 4)
                    shape.fill(Color(hex: "BBB9AE")).offset(x: 5, y: 2)
                    shape.fill(Color(hex: "F8F7EF")).offset(x: 4, y: 2)
                }
                .shadow(color: Color(hex: "25281D", opacity: Double(0x18) / 255), radius: 12, x: 0, y: 16)
            }
            .accessibilityHidden(true)
    }
}

/// The intro band's 1 pt rule every 7 pt (`#24292003`).
private struct MangaRuling: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 6
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(MangaInk.ruling))
                y += 7
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - D5 Your bookmark

struct MangaBookmarkCard: View {
    let progress: Int
    let total: Int?
    let caption: String?
    let material: ArtworkMaterial
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Large type: the count goes under "Your bookmark" so neither breaks inside a word.
                VStack(alignment: .leading, spacing: 10) {
                    label
                    count
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: 10) {
                    label
                    Spacer(minLength: 8)
                    count
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 13)
        .background(LinearGradient(colors: [material.wash.color, MangaInk.bandEnd],
                                   startPoint: UnitPoint(x: 0, y: 0.32), endPoint: UnitPoint(x: 1, y: 0.68)), in: shape)
        .overlay(alignment: .top) { Rectangle().fill(material.edge.color).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(material.edge.color).frame(height: 1) }
        .overlay(alignment: .leading) { Rectangle().fill(material.base.color).frame(width: 2) }
        .clipShape(shape)
        .background(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.5)).frame(height: 2).offset(y: 2)
        }
        .accessibilityElement(children: .combine)
    }

    private var label: some View {
        let german = KuroLocale.isGerman
        return VStack(alignment: .leading, spacing: 4) {
                Text(MangaDetailCopy.bookmark(german: german))
                    .font(.detailGeorgia(22))
                    .tracking(-0.5)
                    .foregroundStyle(DetailInk.progressLabel)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption {
                    Text(caption)
                        .font(.detailSF(9, relativeTo: .caption2))
                        .foregroundStyle(DetailInk.progressCaption)
                }
            }
    }

    private var count: some View {
        let german = KuroLocale.isGerman
        return HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(MangaDetailCopy.chapterUnit(german: german))
                    .font(.detailSF(10, relativeTo: .footnote))
                    .foregroundStyle(Color.kuroMuted)
                    .padding(.bottom, 1)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.kuroMuted.opacity(0.35)).frame(height: 1) }
                Text("\(progress)")
                    .font(.detailSF(21, .medium, relativeTo: .title2))
                    .monospacedDigit()
                    .foregroundStyle(Color.kuroInk)
                    .kuroCountRoll(value: progress, pageTurn: true)
                if let total {
                    Text("/ \(total)")
                        .font(.detailSF(11, relativeTo: .footnote))
                        .foregroundStyle(Color.kuroMuted.opacity(0.8))
                }
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(MangaDetailSections.bookmarkSpoken(progress: progress, total: total, german: german))
    }
}

// MARK: - D6 Chapters

struct MangaChaptersSection: View {
    let manga: Manga
    let chapters: [MangaChapter]
    let progress: Int
    let total: Int?
    let isTracked: Bool
    let nextChapter: Int?
    let nextRelease: ReleaseScheduleItem?
    let material: ArtworkMaterial
    let coverURL: URL?
    let savingNext: Bool
    let confirmTrigger: Int
    /// The reading service a chapter row opens; nil leaves the rows inert.
    var readLinkTitle: String? = nil
    var onReadChapter: ((MangaChapter) -> Void)? = nil
    let onAdvance: (Int) -> Void

    @Environment(CatalogStore.self) private var catalog
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsAll = false
    @State private var allChapters: [MangaChapter] = []
    @State private var hasMore = true
    @State private var loadingMore = false

    private var upNext: Int? { isTracked ? nextChapter : nil }
    private var real: Bool { MangaDetailSections.chaptersAreReal(chapters) }

    /// Collapsed: the last finished chapter under Up next (tracked; the prototype shows no later row),
    /// or the first three. Placeholder lists show no rows at all.
    private var shownRows: [MangaChapter] {
        guard real else { return [] }
        if showsAll { return allChapters.isEmpty ? chapters : allChapters }
        guard isTracked else { return Array(chapters.prefix(3)) }
        return Self.collapsedRows(chapters, progress: progress)
    }

    /// The tracked, collapsed list: the last finished chapter only (ref-detail-manga-390.png).
    static func collapsedRows(_ chapters: [MangaChapter], progress: Int) -> [MangaChapter] {
        chapters.last { $0.number <= progress }.map { [$0] } ?? []
    }

    private var hasMoreToShow: Bool {
        guard real, !showsAll else { return false }
        if let total { return total > shownRows.count + (upNext == nil ? 0 : 1) }
        return chapters.count > shownRows.count
    }

    var body: some View {
        let german = KuroLocale.isGerman
        VStack(alignment: .leading, spacing: 0) {
            DetailSectionHeading(title: KuroLocale.text("Chapters", "Kapitel"))
            if let nextRelease {
                KuroReleaseLine(nextRelease, font: .detailSF(10, relativeTo: .footnote), color: DetailInk.progressCaption)
                    .padding(.top, 4)
            }
            if let upNext {
                upNextRow(upNext, german: german).padding(.top, 12)
            }
            ForEach(shownRows, id: \.id) { chapter in
                row(chapter, german: german)
            }
            if loadingMore {
                KuroSkeleton(kind: .row).padding(.vertical, 8)
            }
            if hasMoreToShow || showsAll {
                Button {
                    if showsAll {
                        withAnimation(KuroMotion.detail(KuroMotion.settle, reduceMotion: reduceMotion)) { showsAll = false }
                    } else {
                        showsAll = true
                        Task { await loadAll() }
                    }
                } label: {
                    HStack {
                        Text(showsAll ? KuroLocale.text("Fewer chapters", "Weniger Kapitel") : KuroLocale.text("More chapters", "Mehr Kapitel"))
                            .font(.detailSF(11, relativeTo: .footnote))
                        Spacer()
                        Image(systemName: showsAll ? "arrow.up" : "arrow.down")
                            .font(.detailSF(14, .light, relativeTo: .body))
                    }
                    .foregroundStyle(DetailInk.moreLink)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { Rectangle().fill(DetailInk.rowRule).frame(height: 1) }
            }
            if showsAll, hasMore, !allChapters.isEmpty, !loadingMore {
                Color.clear.frame(height: 1).onAppear { Task { await loadAll() } }
            }
        }
        .padding(.bottom, 8)
    }

    private func upNextRow(_ number: Int, german: Bool) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4, bottomTrailingRadius: 13,
                                           topTrailingRadius: 13, style: .continuous)
        let chapter = chapters.first { $0.number == number }
        let thumb = chapter?.thumbnail.flatMap(AnimeDetailPage.webURL) ?? coverURL
        let realTitle = chapter.flatMap(MangaDetailSections.realTitle)
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
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(KuroLocale.text("UP NEXT", "ALS NÄCHSTES"))
                    .font(.detailSF(7, .semibold, relativeTo: .caption2))
                    .tracking(1.4)
                    .foregroundStyle(DetailInk.upNextKicker)
                Text(MangaDetailCopy.chapter(number, german: german))
                    .font(.detailSF(12, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color.kuroInk)
                if let realTitle {
                    Text(realTitle)
                        .font(.detailSF(9, relativeTo: .caption2))
                        .foregroundStyle(DetailInk.progressCaption)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            DetailUpNextKey(material: material, pending: savingNext, confirmTrigger: confirmTrigger,
                            accessibilityText: KuroAdvanceCopy.label(medium: .manga, nextUnit: number, title: manga.displayTitle,
                                                                     current: progress, total: total, german: german),
                            radius: 11) {
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
                .shadow(color: Color(hex: "292A20", opacity: 0x08 / 255.0), radius: 2.5, x: 0, y: 2)
        }
        .overlay(shape.strokeBorder(material.edge.color, lineWidth: 1))
        .padding(.horizontal, -9)
        .padding(.bottom, 4)
    }

    private func row(_ chapter: MangaChapter, german: Bool) -> some View {
        let finished = isTracked && chapter.number <= progress
        let ink = finished ? DetailInk.finished : Color.kuroInk
        let title = MangaDetailSections.realTitle(chapter) ?? MangaDetailCopy.chapter(chapter.number, german: german)
        let date = (chapter.releaseAt ?? chapter.releaseDate).map { $0.formatted(.dateTime.day().month(.abbreviated).year()) }
        let content = HStack(spacing: 12) {
            Text("\(chapter.number)")
                .font(.detailGeorgia(18, italic: true, relativeTo: .title3))
                .tracking(-1)
                .monospacedDigit()
                .foregroundStyle(DetailInk.finished)
                .frame(minWidth: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.detailSF(12, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(ink)
                    .lineLimit(2)
                if finished {
                    Text(KuroLocale.text("Completed", "Gelesen"))
                        .font(.detailSF(9, relativeTo: .caption2))
                        .foregroundStyle(DetailInk.finishedState)
                } else if let date {
                    Text(date)
                        .font(.detailSF(9, relativeTo: .caption2))
                        .foregroundStyle(DetailInk.finishedState)
                }
            }
            Spacer(minLength: 8)
            // The prototype's only row keys are ✓ and Up next's +: an unread row that opens the
            // reading service says so to VoiceOver (hint) without a ↗ key.
            if finished {
                Image(systemName: "checkmark")
                    .font(.detailSF(11, relativeTo: .footnote))
                    .foregroundStyle(DetailInk.finished)
            }
        }
        // 57 pt as measured; at large type the padding keeps text off the row rules.
        .padding(.vertical, 10)
        .frame(minHeight: 57)
        .contentShape(Rectangle())
        return Group {
            if let onReadChapter {
                Button { onReadChapter(chapter) } label: { content }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(KuroLocale.text("Opens \(readLinkTitle ?? "the reading service").",
                                                       "Öffnet \(readLinkTitle ?? "den Lesedienst")."))
            } else {
                content.accessibilityElement(children: .combine)
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(DetailInk.rowRule).frame(height: 1) }
    }

    private func loadAll() async {
        guard !loadingMore, hasMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        let page = await catalog.fetchChaptersPage(mangaId: manga.id, offset: allChapters.count, limit: 50)
        guard !Task.isCancelled else { return }
        allChapters += page.filter { item in !allChapters.contains(where: { $0.id == item.id }) }
        hasMore = page.count == 50
    }
}

// MARK: - D7 Seen the anime?

/// "From screen to page · Seen the anime?": the ladder's anime adaptation. Its one link is the
/// prototype's "Official anime site ↗" when the adaptation's external links have one; the 映 tile and
/// title open the anime in the app (the live route, kept without an extra link). Without a site the
/// link reads "Explore the anime →" (the in-app route), so the card always leads somewhere.
/// "I've watched the anime" opens the bundle's season guide and only exists when the bundle has one
/// (series flags on): without coverage it could only say "unknown". The guide never marks chapters read.
struct MangaAdaptationCard: View {
    let item: MediaLadderItem
    let guides: [SeriesDetailBundle.Coverage]
    let material: ArtworkMaterial
    /// The adaptation's official site ("Official anime site ↗"), when its external links have one.
    var officialSite: URL? = nil
    var onOpenSite: () -> Void = {}
    let onOpen: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsGuide = false
    @State private var choice: Int?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let german = KuroLocale.isGerman
        let shape = UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4, bottomTrailingRadius: 4,
                                           topTrailingRadius: 18, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            DetailEyebrow(text: KuroLocale.text("From screen to page", "Vom Bildschirm aufs Papier"))
            Text(KuroLocale.text("Seen the anime?", "Den Anime gesehen?"))
                .font(.detailGeorgia(27))
                .tracking(-0.7)
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.bottom, 18)
                .accessibilityAddTraits(.isHeader)
            let stacked = dynamicTypeSize.isAccessibilitySize
            let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                                 : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
            layout {
                // The 映 tile and the title open the anime in the app (the live route, no extra link).
                Button { onOpen(item.mediaId) } label: {
                    Text("映")
                        .font(.detailMincho(25))
                        .foregroundStyle(material.base.color)
                        .frame(width: 62, height: 76)
                        .background(MangaInk.symbolFill)
                        .overlay(Rectangle().strokeBorder(material.edge.color, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(KuroPressStyle())
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Button { onOpen(item.mediaId) } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.title)
                                .font(.detailSF(15, .semibold, relativeTo: .headline))
                                .foregroundStyle(Color.kuroInk)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(KuroLocale.text("Anime adaptation", "Anime-Adaption"))
                                .font(.detailSF(9, relativeTo: .caption2))
                                .foregroundStyle(MangaInk.adaptationCaption)
                                .padding(.top, 5)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(KuroLocale.text("Opens the anime.", "Öffnet den Anime."))
                    link(german: german)
                }
                if !stacked { Spacer(minLength: 0) }
            }
            if !guides.isEmpty {
                guide(german: german)
            }
        }
        .padding(.top, 21)
        .padding(.horizontal, 18)
        .padding(.bottom, guides.isEmpty ? 21 : 15)
        .background(LinearGradient(colors: [material.wash.color, Color(hex: "F8F8F0")],
                                   startPoint: UnitPoint(x: 0, y: 0.2), endPoint: UnitPoint(x: 1, y: 0.8)), in: shape)
        .overlay(shape.strokeBorder(material.edge.color, lineWidth: 1))
        .background { shape.fill(MangaInk.guideShadow).offset(x: 3, y: 3) }
        .padding(.top, 27)
        // The card's 30 pt bottom margin collapses into the next section's own 30 pt top (CSS).
        .padding(.bottom, 0)
    }

    /// The card's one link: the official site when known, else the in-app route.
    @ViewBuilder
    private func link(german: Bool) -> some View {
        if officialSite != nil {
            Button(action: onOpenSite) {
                Text(KuroLocale.text("Official anime site ↗", "Offizielle Anime-Seite ↗"))
                    .font(.detailSF(11, relativeTo: .footnote))
                    .foregroundStyle(Color.kuroInk)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(KuroLocale.text("Opens the anime's official website.", "Öffnet die offizielle Website des Anime."))
        } else {
            Button { onOpen(item.mediaId) } label: {
                HStack(spacing: 16) {
                    Text(KuroLocale.text("Explore the anime", "Zum Anime"))
                        .font(.detailSF(11, relativeTo: .footnote))
                    Image(systemName: "arrow.right")
                        .font(.detailSF(13, .light, relativeTo: .body))
                }
                .foregroundStyle(Color.kuroInk)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func label(_ guide: SeriesDetailBundle.Coverage, german: Bool) -> String {
        guide.season?.detailNonEmpty ?? (german ? "Anime-Adaption" : "Anime adaptation")
    }

    @ViewBuilder
    private func guide(german: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(KuroMotion.detail(KuroMotion.settle, reduceMotion: reduceMotion)) { showsGuide.toggle() }
            } label: {
                HStack {
                    Text(KuroLocale.text("I've watched the anime", "Ich habe den Anime gesehen"))
                        .font(.detailSF(12, .medium, relativeTo: .subheadline))
                    Spacer()
                    Text("+")
                        .font(.detailSF(20, .light, relativeTo: .body))
                        .rotationEffect(.degrees(showsGuide ? 45 : 0))
                }
                .foregroundStyle(Color.kuroInk)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(showsGuide ? .isSelected : [])
            if showsGuide {
                VStack(alignment: .leading, spacing: 10) {
                    Text(KuroLocale.text("Which season did you finish?", "Welche Staffel hast du beendet?"))
                        .font(.detailSF(11, relativeTo: .footnote))
                        .foregroundStyle(Color.kuroInk)
                    Picker(KuroLocale.text("Choose a season", "Staffel wählen"), selection: $choice) {
                        Text(KuroLocale.text("Choose a season", "Staffel wählen")).tag(Int?.none)
                        ForEach(guides.indices, id: \.self) { index in
                            Text(label(guides[index], german: german)).tag(Optional(index))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                    .padding(.horizontal, 8)
                    .background(Color(hex: "FBFCF6"), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(material.edge.color, lineWidth: 1))
                    if let choice, guides.indices.contains(choice) {
                        result(guides[choice], german: german)
                    } else {
                        Text(KuroLocale.text("Choose a finished season to find your place on the page.",
                                             "Wähle eine beendete Staffel, um deine Stelle im Manga zu finden."))
                            .font(.detailSF(11, relativeTo: .footnote))
                            .foregroundStyle(MangaInk.guideText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(KuroLocale.text("This guide never marks manga chapters as read.",
                                         "Diese Hilfe markiert keine Kapitel als gelesen."))
                        .font(.detailSF(9, relativeTo: .caption2))
                        .foregroundStyle(MangaInk.guideText)
                }
                .padding(.bottom, 8)
            }
        }
        .padding(.top, 16)
        .overlay(alignment: .top) { Rectangle().fill(material.edge.color).frame(height: 1).padding(.top, 16) }
    }

    @ViewBuilder
    private func result(_ guide: SeriesDetailBundle.Coverage, german: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if guide.mappingState == "exact" || guide.mappingState == "partial" {
                if let start = guide.startsAt { line(KuroLocale.text("Starts at", "Beginnt bei"), start) }
                if let end = guide.endsAt { line(KuroLocale.text("Ends at", "Endet bei"), end) }
                if let next = guide.readNext { line(KuroLocale.text("Read next", "Weiterlesen ab"), next) }
            }
            Text(guide.mappingState == "exact"
                 ? KuroLocale.text("The season ends exactly here.", "Die Staffel endet genau hier.")
                 : (guide.mappingState == "partial"
                    ? KuroLocale.text("Some chapters differ from the anime.", "Einige Kapitel weichen vom Anime ab.")
                    : SeriesCopy.boundaryUnknown(sourceKind: "manga")))
                .font(.detailSF(11, relativeTo: .footnote))
                .foregroundStyle(MangaInk.guideText)
                .fixedSize(horizontal: false, vertical: true)
            if let id = guide.animeId, id != item.mediaId {
                Button { onOpen(id) } label: {
                    Text(KuroLocale.text("Open this season →", "Diese Staffel öffnen →"))
                        .font(.detailSF(11, relativeTo: .footnote))
                        .foregroundStyle(Color.kuroInk)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func line(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.detailSF(11, relativeTo: .footnote)).foregroundStyle(DetailInk.creditRole)
            Spacer()
            Text(value).font(.detailSF(11, .medium, relativeTo: .footnote)).foregroundStyle(Color.kuroInk)
        }
    }
}

// MARK: - D10 Read with the publisher

/// "Read legally ↗" with the real service's name under it (one link opens directly; more open the
/// provider sheet). The prototype says "Read with the publisher", but the legal read links carry no
/// publisher marker (a store or catalogue entry may come first), so the row never claims one.
struct MangaPublisherRow: View {
    let caption: String
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 15) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(KuroLocale.text("Read legally", "Legal lesen"))
                        .font(.detailSF(12, relativeTo: .subheadline))
                        .foregroundStyle(Color.kuroInk)
                    Text(caption)
                        .font(.detailSF(10, relativeTo: .footnote))
                        .foregroundStyle(MangaInk.publisherCaption)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.detailSF(12, relativeTo: .footnote))
                    .foregroundStyle(Color.kuroInk)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Rectangle().fill(MangaInk.publisherRule).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(MangaInk.publisherRule).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityHint(KuroLocale.text("Opens the reading service.", "Öffnet den Lesedienst."))
    }
}
