import AuthenticationServices
import KuroCore
import KuroLibrary
import SwiftUI
import UniformTypeIdentifiers

// Profile: the account hub (rulebook §14.3). Order: identity, Your numbers (details-songs spec §12:
// counted on the device), Your library (counts + "Your lists"),
// Imports and connections (incl. pending and resumable imports), Clubs, Preferences, Account and
// privacy, About (Data sources and credits, Contact us, Terms once confirmed, version), then a quiet Advanced disclosure (cache tools; the streaming freshness card when that
// feature is on). Rows: serif title, sans subtitle in secondary ink, hairlines, no chevrons.
// Preferences carries the release-reminders toggle (spec §11.4) after "Refresh your lists".
//
// Navigation contract (2026-11-02): Profile is the root of a journey (`ShellJourneyPages.profile`).
// Your clubs, Data sources, Find, Concierge and the import review PUSH inside it (back chevron + edge
// swipe-back); Contact, the import chooser, the AniList/MAL imports, the review workflow and the
// streaming picker stay tool sheets that close back to Profile. Your lists cannot be shown inside the
// journey (Collection's one shared feed), so its rows say "Opens Collection" and the journey collapses
// like ✕ before the pager switches (N11). A push fires `onDisappear` here: the account-scoped import
// work keeps running while Profile is covered and stops when the journey ends (`\.shellPageLifetime`).
struct ProfileView: View {
    var onImportNavigation: ((ImportResultDestination) -> Void)? = nil
    var onOpenCollection: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.kuroRoutes) private var routes
    @Environment(\.kuroJourney) private var journey
    /// Session fold memory (F3: Advanced stays open when coming back to Profile).
    @Environment(\.kuroFoldMemory) private var folds
    @Environment(\.shellPageLifetime) private var pageLifetime
    @Environment(LibraryStore.self) private var library
    @Environment(IdentityStore.self) private var identity
    @Environment(AuthService.self) private var auth
    @Environment(SessionController.self) private var session
    @Environment(CollectionStore.self) private var collection
    @Environment(ReleasesStore.self) private var releases
    @Environment(ProviderAvailabilityStore.self) private var availability
    @Environment(ClubsStore.self) private var clubs
    @Environment(ImportsService.self) private var imports
    @Environment(FeatureFlags.self) private var flags
    @Environment(ArtworkMaterialStore.self) private var artworkMaterials
    @Environment(CatalogStore.self) private var catalog: CatalogStore?
    @State private var profileActionScope = AccountActionScope()
    @State private var canonArtworkByKey: [MediaKey: Media] = [:]
    @State private var canonArtworkAccount: String? = nil
    @State private var deleteConfirmationTicket: AccountActionScope.Ticket?
    @State private var importCoordinator: ProfileImportCoordinator?
    @State private var isSyncing: Bool = false
    /// The account this Profile's import work was set up for (`ProfileLifecyclePolicy.needsSetup`): a
    /// page popped back to keeps its import coordinator, toast and result card.
    @State private var setUpAccount: String?? = nil
    /// The shrinking header's progress (the scenery band scrolls under the compact bar, H1).
    @State private var collapse: CGFloat = 0
    @State private var toast: KuroToastState? = nil
    @State private var showDeleteConfirmation: Bool = false
    @State private var isDeleting: Bool = false
    @State private var showServicePicker: Bool = false
    @State private var showAniListImportSheet: Bool = false
    @State private var pendingAniListReview: ImportOutcome?
    @State private var pendingAniListTicket: AccountActionScope.Ticket?
    @State private var showMALImporter: Bool = false
    @State private var malPresentationAnchor: ASPresentationAnchor?
    @State private var showImportWorkflow = false
    @State private var importWorkflowJob: ImportOutcome?
    @State private var showContact = false
    @State private var showExport = false
    @State private var showImportChooser = false
    @State private var streamingObservability: ProviderAvailabilityStore.StreamingObservabilitySnapshot? = nil
    @State private var isRefreshingStreamingObservability: Bool = false

    private var isGermanLocale: Bool { KuroLocale.isGerman }
    /// The still scenery band at the top (the shrinking header's hero).
    static let bandHeight: CGFloat = 132

    /// Opens a page inside Profile's journey (pushed: Back + edge swipe-back; ✕ collapses all).
    private func push(_ page: JourneyPage) {
        KuroAccessibility.impactHaptic(.light)
        routes.openPage(page)
    }

    var body: some View {
        let profileImports = importCoordinator
        let anchor = malPresentationAnchor
        let ticket = profileActionScope.capture(session: imports.accountSession)
        let confirmationTicket = deleteConfirmationTicket
        ZStack {
            Color.kuroCanvasPage
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.xl) {
                    identityHeader

                    // Details-songs spec §12.1: "Your numbers." after Identity, before Library.
                    ProfileStatsSection()
                        .padding(.horizontal, KuroDesignSpacing.padding)

                    librarySection
                        .padding(.horizontal, KuroDesignSpacing.padding)

                    importsSection(profileImports, anchor: anchor)
                        .padding(.horizontal, KuroDesignSpacing.padding)

                    clubsSection
                        .padding(.horizontal, KuroDesignSpacing.padding)

                    preferencesSection
                        .padding(.horizontal, KuroDesignSpacing.padding)

                    accountSection(ticket: ticket, confirmationTicket: confirmationTicket)
                        .padding(.horizontal, KuroDesignSpacing.padding)

                    aboutSection
                        .padding(.horizontal, KuroDesignSpacing.padding)

                    advancedSection
                        .padding(.horizontal, KuroDesignSpacing.padding)
                }
                .padding(.bottom, KuroDesignSpacing.xxl)
                .kuroReadableWidth()
            }
            .kuroCollapseTracking($collapse, start: 0, distance: Self.bandHeight - KuroJourneyChrome.barHeight)
            // Ensure the last rows can scroll fully above the home indicator / tab chrome.
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 24)
            }
        }
        .background(ProfileMALWindowAnchor { malPresentationAnchor = $0 }.frame(width: 0, height: 0))
        .scrollContentBackground(.hidden)
        // Kept from the native polish pass: Profile mutations and toasts change rows in place without
        // implicit motion (rulebook §8 asks to keep this suppression). Fold toggles (Advanced) are
        // exempt: they keep the prototype easing (navigation contract F1).
        .transaction { if !$0.isKuroFold { $0.animation = nil } }
        .task(id: identity.currentUserId) {
            // Back from a pushed page (Clubs, Data sources, Find, Concierge): the import work kept
            // running for this account, so only the list preview is read again (its own TTL).
            guard ProfileLifecyclePolicy.needsSetup(setUpFor: setUpAccount, current: identity.currentUserId,
                                                    hasCoordinator: importCoordinator != nil) else {
                await collection.loadListPreview()
                return
            }
            setUpAccount = .some(identity.currentUserId)
            profileActionScope.deactivate()
            profileActionScope.activate(session: imports.accountSession)
            deleteConfirmationTicket = nil
            showDeleteConfirmation = false
            isDeleting = false
            importCoordinator?.stop()
            let coordinator = ProfileImportCoordinator(imports: imports, library: library,
                collection: collection, releases: releases, flags: flags, isGermanLocale: isGermanLocale)
            importCoordinator = coordinator
            // Inside the journey the teardown waits for the sheet to end (a push is not an exit).
            let scope = profileActionScope
            pageLifetime?.onJourneyEnd {
                scope.deactivate()
                coordinator.stop()
            }
            await importCoordinator?.refreshMALIdentity()
            await collection.loadListPreview()
            // Keep the profile "club context" warm so Clubs opens instantly.
            await clubs.refreshMyClubsIfStale()
            if flags.isStreamingAvailabilityV1Enabled {
                await refreshStreamingObservability()
            }
        }
        .onDisappear {
            // Covered by a pushed page: keep the import work (it ends with the journey).
            if pageLifetime?.isStillInJourney == true { return }
            pageLifetime?.didTearDown()
            setUpAccount = nil
            profileActionScope.deactivate()
            deleteConfirmationTicket = nil
            importCoordinator?.stop()
            importCoordinator = nil
        }
        .onChange(of: identity.currentUserId) { _, _ in
            showAniListImportSheet = false; pendingAniListReview = nil; pendingAniListTicket = nil
            showMALImporter = false
            showImportWorkflow = false
            importWorkflowJob = nil
            showDeleteConfirmation = false
            deleteConfirmationTicket = nil
            canonArtworkByKey = [:]
            canonArtworkAccount = nil
        }
        // Journey root: ✕ only (N3), the round key over the scenery band, then the compact bar (H1).
        .kuroJourneyChrome(title: ShellJourneyPages.profileTitle, collapseProgress: collapse)
        .overlay(alignment: .top) {
            if let toast = profileImports?.toast ?? toast {
                KuroToast(toast: toast)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // Tool sheets close back to Profile (N7). Their content is not a Profile journey page: it
        // never inherits Profile's page lifetime.
        .sheet(isPresented: $showContact) {
            ContactSheet()
                .environment(\.shellPageLifetime, nil)
        }
        // Export your list (W2): a tool sheet over Profile, registered as a navigation layer (N10).
        .sheet(isPresented: $showExport) {
            LibraryExportSheet()
                .kuroLeavesJourney()
                .environment(\.shellPageLifetime, nil)
        }
        .kuroNavigationLayer("profile.export", isPresented: $showExport)
        .sheet(isPresented: $showImportChooser) {
            ImportSourceChooser { destination in
                showImportChooser = false
                guard profileActionScope.capture(session: imports.accountSession) != nil else { return }
                onImportNavigation?(destination)
            }
            .environment(\.shellPageLifetime, nil)
        }
        .fileImporter(isPresented: $showMALImporter, allowedContentTypes: [.xml]) { result in
            profileImports?.receiveMALFile(result)
        }
        .sheet(isPresented: $showAniListImportSheet, onDismiss: {
            guard let job = pendingAniListReview else { return }
            pendingAniListReview = nil
            let origin = pendingAniListTicket; pendingAniListTicket = nil
            guard profileActionScope.isCurrent(origin, session: imports.accountSession) else { return }
            importWorkflowJob = job; showImportWorkflow = true
        }) {
            let origin = profileActionScope.capture(session: imports.accountSession)
            ConciergeAniListImportSheet(
                imports: imports,
                isGermanLocale: isGermanLocale,
                usesStructuredImport: flags.seriesFoundationV1Enabled,
                onPrepared: { job in
                    guard profileActionScope.isCurrent(origin, session: imports.accountSession) else { return }
                    pendingAniListReview = job; pendingAniListTicket = origin
                }
            ) { response in
                await profileImports?.receiveAniList(response)
            }
            .environment(\.shellPageLifetime, nil)
        }
        .onChange(of: profileImports?.workflowJob) { _, job in
            guard let job, profileActionScope.capture(session: imports.accountSession) != nil else { return }
            importWorkflowJob = job; showImportWorkflow = true
        }
        .sheet(isPresented: $showImportWorkflow, onDismiss: { profileImports?.dismissWorkflow() }) {
            ImportWorkflowSheet(imports: imports, job: importWorkflowJob) { destination in
                guard profileActionScope.capture(session: imports.accountSession) != nil else { return }
                onImportNavigation?(destination)
            }
            .environment(\.shellPageLifetime, nil)
        }
    }

    // MARK: Identity

    /// Monochrome Collector Bookplate header on gallery white (2026-11-20 Phase 5).
    private var identityHeader: some View {
        let german = isGermanLocale
        return VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: max(60, Self.bandHeight - 44))
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [Color.kuroControlFill.opacity(0.65), Color.kuroCanvasPage],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .accessibilityHidden(true)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 14) {
                Text(german ? "KURO · MITGLIEDSAUSWEIS" : "KURO · COLLECTOR PASS")
                    .kuroKicker()

                HStack(alignment: .center, spacing: KuroDesignSpacing.md) {
                    Text(identity.currentUserInitial)
                        .font(.kuroEditorial(size: 24))
                        .foregroundStyle(Color.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color.kuroControlInk))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(accountHeadline)
                            .font(.kuroCustom(19, weight: .semibold, relativeTo: .title3, maxSize: 32))
                            .tracking(-0.3)
                            .foregroundStyle(Color.kuroInk)
                            .fixedSize(horizontal: false, vertical: true)
                        if let address = accountAddress {
                            Text(address)
                                .font(.kuroMeta())
                                .foregroundStyle(Color.kuroInkSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, KuroDesignSpacing.padding)
            .padding(.bottom, KuroDesignSpacing.md)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.kuroHairline)
                    .frame(height: 0.5)
                    .padding(.horizontal, KuroDesignSpacing.padding)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }

    /// The real account, never a slogan or a generic account label, and never the raw address as the
    /// headline (rulebook §14.3). Only a fact the app knows locally: an Apple private relay address
    /// can only come from Sign in with Apple; anything else is plainly "Signed in" (an Apple account
    /// that shared its real address is not called an e-mail sign-in).
    private var accountHeadline: String {
        if let email = identity.currentUserEmail, Self.isAppleRelay(email) {
            return isGermanLocale ? "Mit Apple angemeldet" : "Signed in with Apple"
        }
        return isGermanLocale ? "Angemeldet" : "Signed in"
    }

    /// The address on the quiet secondary line (middle-truncated); an Apple private relay address
    /// says nothing to the person and is not shown.
    private var accountAddress: String? {
        guard let email = identity.currentUserEmail, !email.isEmpty, !Self.isAppleRelay(email) else { return nil }
        return email
    }

    private static func isAppleRelay(_ email: String) -> Bool {
        email.lowercased().hasSuffix("privaterelay.appleid.com")
    }

    // MARK: Library

    private var librarySection: some View {
        let entries = library.allEntries
        let german = isGermanLocale
        return VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            sectionHeader(german ? "Deine Bibliothek." : "Your library.")
            switch ProfileListsPolicy.libraryState(entryCount: entries.count, loadState: library.loadState) {
            case .loading:
                KuroLoadingView(scope: .inline,
                                label: german ? "Deine Bibliothek wird geladen." : "Loading your library.")
            case .failed, .offline:
                // Nothing on screen: the branded error, whose Try again is the same account-scoped
                // re-read as "Refresh your lists".
                KuroErrorView(headline: german ? "Bibliothek konnte nicht geladen werden." : "Your library couldn't load.",
                              retry: { if !isSyncing { syncLists() } })
            case .empty:
                newAccountLibrary
            case nil:
                Text(ProfileListsPolicy.summary(entries, german: german))
                    .font(.kuroBody())
                    .foregroundStyle(Color.kuroInkSecondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                canonStrip(entries: entries, german: german)
                ProfileListsPreview(
                    entries: entries,
                    previews: collection.listPreview,
                    previewFailed: collection.listPreviewFailed,
                    onOpen: { request in
                        collection.requestList(request)
                        onOpenCollection?()
                    },
                    onOpenCollection: {
                        collection.clearImportedTitles()
                        onOpenCollection?()
                    }
                )
                .padding(.top, KuroDesignSpacing.xs)
            }
        }
        .task(id: ProfileCanon.taskId(account: identity.currentUserId, entries: entries)) {
            await loadCanonArtwork(for: entries)
        }
    }

    @ViewBuilder
    private func canonStrip(entries: [LibraryEntry], german: Bool) -> some View {
        let top = ProfileCanon.topEntries(entries, limit: 4)
        let previewMap = ProfileCanon.mediaMap(previews: collection.listPreview, extra: canonArtworkByKey)
        let items = top.compactMap { entry -> (entry: LibraryEntry, media: Media)? in
            guard let media = previewMap[entry.key],
                  let raw = media.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { return nil }
            return (entry, media)
        }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(german ? "DEIN KANON" : "YOUR CANON")
                    .font(.kuroCustom(9, weight: .medium, relativeTo: .caption2, maxSize: 16))
                    .tracking(1.1)
                    .foregroundStyle(Color.kuroInkQuiet)
                    .padding(.top, 6)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(items, id: \.entry.key) { item in
                            Button {
                                KuroAccessibility.impactHaptic(.light)
                                routes.openMedia(MediaRoute(item.entry.key))
                            } label: {
                                ZStack(alignment: .bottomLeading) {
                                    FolioArtwork(url: item.media.imageURL, width: 72, height: 104,
                                                 cornerRadius: 6, maxPixelSize: 220, topBiased: true)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                                        )
                                    if let stars = item.entry.rating?.value {
                                        Text("★ \(stars)")
                                            .font(.kuroCustom(9, weight: .semibold, relativeTo: .caption2, maxSize: 16))
                                            .monospacedDigit()
                                            .foregroundStyle(Color.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.kuroControlInk.opacity(0.86), in: Capsule(style: .continuous))
                                            .padding(4)
                                    }
                                }
                                .frame(width: 72, height: 104)
                                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(HomeContactStyle())
                            .accessibilityLabel(item.entry.rating.map { "\(item.media.title), \($0.value) / 10" } ?? item.media.title)
                            .accessibilityHint(german ? "Öffnet die Details" : "Opens details")
                        }
                    }
                }
            }
        }
    }

    private func loadCanonArtwork(for entries: [LibraryEntry]) async {
        let account = identity.currentUserId
        if canonArtworkAccount != account {
            canonArtworkByKey = [:]
            canonArtworkAccount = account
        }
        guard let account, let catalog else { return }
        let top = ProfileCanon.topEntries(entries, limit: 4)
        let previewMap = ProfileCanon.mediaMap(previews: collection.listPreview, extra: canonArtworkByKey)
        let missing = top.map(\.key).filter { previewMap[$0] == nil }
        guard !missing.isEmpty else { return }

        var fetched: [MediaKey: Media] = [:]
        let animeIds = missing.filter { $0.kind == .anime }.map(\.id)
        let mangaIds = missing.filter { $0.kind == .manga }.map(\.id)
        if !animeIds.isEmpty, let rows = await catalog.fetchAnimeByIdsPreservingOrder(animeIds) {
            for row in rows {
                fetched[MediaKey(kind: .anime, id: row.id)] = Media(
                    id: row.id, kind: .anime, title: row.title, imageURL: row.imageURL, year: row.year,
                    displayDescription: row.displayDescription, episodes: row.episodes, chapters: nil,
                    rating: row.rating, genres: row.genres, statusRaw: row.statusRaw,
                    formatRaw: row.formatRaw, popularityValue: row.popularityValue,
                    trendingValue: row.trendingValue, createdAtValue: row.createdAtValue
                )
            }
        }
        if !mangaIds.isEmpty, let rows = await catalog.fetchMangaByIdsPreservingOrder(mangaIds) {
            for row in rows {
                fetched[MediaKey(kind: .manga, id: row.id)] = Media(
                    id: row.id, kind: .manga, title: row.title, imageURL: row.imageURL, year: row.year,
                    displayDescription: row.displayDescription, episodes: nil, chapters: row.chapters,
                    rating: row.rating, genres: row.genres, statusRaw: row.statusRaw,
                    formatRaw: row.formatRaw, popularityValue: row.popularityValue,
                    trendingValue: row.trendingValue, createdAtValue: row.createdAtValue
                )
            }
        }
        guard !Task.isCancelled, identity.currentUserId == account, canonArtworkAccount == account else { return }
        canonArtworkByKey.merge(fetched) { _, new in new }
    }

    /// A new account (amendment 10, spec §5.3): no zero tiles or counts. "Your library." stays the
    /// section's only heading; under it "Nothing saved yet." sits on the row-title ramp (15 w600,
    /// −0.2), one muted line, then Import (the import chooser) and Find (Search) as the prototype's
    /// outlined buttons.
    private var newAccountLibrary: some View {
        let german = isGermanLocale
        return VStack(alignment: .leading, spacing: 0) {
            Text(ProfileListsPolicy.newAccountHeadline(german: german))
                .font(.kuroCustom(15, weight: .semibold, relativeTo: .headline, maxSize: 30))
                .tracking(-0.2)
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
            Text(ProfileListsPolicy.newAccountLine(german: german))
                .font(.kuroCustom(13, relativeTo: .footnote, maxSize: 26))
                .foregroundStyle(Color.kuroMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: KuroDesignSpacing.sm) { newAccountActions }
                VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) { newAccountActions }
            }
            .padding(.top, 16)
        }
        .padding(.vertical, KuroDesignSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var newAccountActions: some View {
        let german = isGermanLocale
        KuroOutlineButton(ProfileListsPolicy.importTitle(german: german)) { showImportChooser = true }
        KuroOutlineButton(ProfileListsPolicy.findTitle(german: german)) { push(ShellJourneyPages.search()) }
    }

    // MARK: Imports and connections

    private func importsSection(_ coordinator: ProfileImportCoordinator?, anchor: ASPresentationAnchor?) -> some View {
        let german = isGermanLocale
        return VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            sectionHeader(german ? "Importe und Verbindungen." : "Imports & connections.")
            profileGroup {
                ProfileQuietRow(
                    title: "AniList",
                    subtitle: german ? "Per Benutzername importieren" : "Import by username",
                    icon: "arrow.down.circle",
                    isEnabled: coordinator?.isProcessingAniListImport != true,
                    showsChevron: true
                ) {
                    // A new import gesture does not replay an unresolved action.
                    if coordinator?.beginAniListSelection() == true { showAniListImportSheet = true }
                }

                if imports.malAccountAvailable {
                    rowHairline
                    if let malIdentity = imports.malAccountIdentity {
                        ProfileQuietRow(
                            title: "MyAnimeList",
                            subtitle: german ? "Verbunden · Erneut synchronisieren" : "Connected · Tap to sync again",
                            badge: malIdentity,
                            icon: "link",
                            isEnabled: coordinator?.isProcessingAniListImport != true && !imports.importBusy,
                            showsChevron: true
                        ) {
                            coordinator?.prepareConnectedMAL()
                        }
                        rowHairline
                        ProfileQuietRow(
                            title: german ? "MyAnimeList trennen" : "Disconnect MyAnimeList",
                            icon: "xmark.circle",
                            titleColor: Color.kuroInkSecondary
                        ) {
                            coordinator?.disconnectMALAccount()
                        }
                    } else {
                        ProfileQuietRow(
                            title: "MyAnimeList",
                            subtitle: german ? "Konto verbinden" : "Connect account",
                            icon: "link",
                            isEnabled: anchor != nil && coordinator?.isProcessingAniListImport != true,
                            showsChevron: true
                        ) {
                            guard let anchor else { return }
                            coordinator?.connectAndImportMAL(presentationAnchor: anchor)
                        }
                    }
                }

                rowHairline
                ProfileQuietRow(
                    title: german ? "MAL-XML-Datei" : "MAL XML file",
                    subtitle: german ? "Aus Datei importieren" : "Import from file",
                    icon: "doc.text",
                    showsChevron: true
                ) {
                    if coordinator?.beginMALFileSelection() == true { showMALImporter = true }
                }

                if coordinator?.profileRetryOffered == true {
                    rowHairline
                    ProfileQuietRow(
                        title: german ? "Import wiederholen" : "Retry import",
                        subtitle: german ? "Dieselbe Übernahme erneut senden" : "Send the same import again",
                        icon: "arrow.clockwise"
                    ) {
                        coordinator?.retry()
                    }
                }

                if coordinator?.isProcessingAniListImport == true {
                    rowHairline
                    statusLine(german ? "AniList wird importiert …" : "Importing from AniList …")
                }
            }

            if flags.seriesFoundationV1Enabled {
                ImportHistorySection(imports: imports) { job in
                    guard profileActionScope.capture(session: imports.accountSession) != nil else { return }
                    importWorkflowJob = job; showImportWorkflow = true
                }
                .padding(.top, KuroDesignSpacing.sm)
            }
            if let importResult = coordinator?.importResult {
                importResultPreview(importResult)
                    .padding(.top, KuroDesignSpacing.sm)
            }
        }
    }

    // MARK: Clubs

    private var clubsSection: some View {
        let german = isGermanLocale
        let count = clubs.myClubs.count
        return VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            sectionHeader(german ? "Clubs." : "Clubs.")
            profileGroup {
                ProfileQuietRow(
                    title: german ? "Deine Clubs" : "Your clubs",
                    subtitle: german ? "Private Gruppen mit Freunden" : "Private watch & read groups",
                    trailing: count > 0 ? "\(count)" : nil,
                    icon: "person.2",
                    showsChevron: true
                ) {
                    push(ShellJourneyPages.clubs)
                }
            }
        }
    }

    // MARK: Preferences

    private var preferencesSection: some View {
        let german = isGermanLocale
        return VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            sectionHeader(german ? "Einstellungen." : "Preferences.")
            profileGroup {
                // Release reminders (spec §12.3): asks for permission only when turned on.
                ProfileRemindersRow()

                if flags.isStreamingAvailabilityV1Enabled {
                    rowHairline
                    streamingServicesRow
                }
            }
            .sheet(isPresented: $showServicePicker) {
                StreamingServicePickerSheet()
                    .environment(\.shellPageLifetime, nil)
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func syncLists() {
        let german = isGermanLocale
        Task {
            guard let context = imports.accountSession.current else { return }
            isSyncing = true
            defer { if imports.accountSession.isCurrent(context) { isSyncing = false } }
            do {
                try await library.refresh()
                guard imports.accountSession.isCurrent(context) else { return }
                // Keep the filter the Collection page is showing (a nil status would reset it).
                await collection.fetchCollectionFeed(status: collection.currentCollectionStatusFilter)
                guard imports.accountSession.isCurrent(context) else { return }
                await collection.loadListPreview(force: true)
                guard imports.accountSession.isCurrent(context) else { return }
                if collection.collectionErrorMessage != nil {
                    showToast(.error,
                              title: german ? "Sammlung nicht verfügbar" : "Collection unavailable",
                              subtitle: german ? "Deine Listen sind aktuell, die Sammlung konnte nicht geladen werden."
                                               : "Your lists are current, but Collection couldn't load.")
                    return
                }
                await releases.fetchUpcomingForUser(days: 7)
                await releases.loadSchedule(force: true)
                guard imports.accountSession.isCurrent(context) else { return }
                KuroAccessibility.successHaptic()
                showToast(.success, title: german ? "Aktualisiert" : "Refreshed",
                          subtitle: german ? "Deine Listen sind aktuell." : "Your lists are current.")
            } catch is CancellationError {
                return
            } catch {
                guard imports.accountSession.isCurrent(context) else { return }
                showToast(.error, title: german ? "Nicht aktualisiert" : "Couldn't refresh",
                          subtitle: german ? "Versuch es gleich noch einmal." : "Try again in a moment.")
            }
        }
    }

    private var streamingServicesRow: some View {
        let german = isGermanLocale
        let services = availability.userStreamingServices
        let names = services.compactMap { slug in
            availability.streamingServiceRegistry.first(where: { $0.slug == slug })?.display_name
        }
        let subtitle = services.isEmpty
            ? (german ? "Dienste wählen" : "Choose services")
            : names.joined(separator: ", ")
        return ProfileQuietRow(
            title: german ? "Streamingdienste" : "Streaming services",
            subtitle: subtitle,
            trailing: services.isEmpty ? nil : "\(services.count)",
            icon: "tv",
            showsChevron: true
        ) {
            showServicePicker = true
        }
    }

    // MARK: Account and privacy

    private func accountSection(
        ticket: AccountActionScope.Ticket?,
        confirmationTicket: AccountActionScope.Ticket?
    ) -> some View {
        let german = isGermanLocale
        return VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            sectionHeader(german ? "Konto und Datenschutz." : "Account & privacy.")
            profileGroup {
                ProfileQuietRow(
                    title: german ? "Abmelden" : "Sign out",
                    icon: "rectangle.portrait.and.arrow.right"
                ) {
                    profileActionScope.launch(origin: ticket, session: imports.accountSession) { origin in
                        await session.signOut(expectedAccount: origin.account)
                    }
                }

                // W2: behind `library_export_v1` (default off); the owner checks the flag again before it
                // sends anything.
                if flags.libraryExportV1Enabled {
                    rowHairline
                    ProfileQuietRow(
                        title: LibraryExportCopy.rowTitle(german: german),
                        subtitle: LibraryExportCopy.rowSubtitle(german: german),
                        icon: "square.and.arrow.up",
                        showsChevron: true
                    ) {
                        showExport = true
                    }
                }

                rowHairline

                ProfileQuietRow(
                    title: german ? "Konto löschen" : "Delete account",
                    subtitle: german ? "Konto und Daten dauerhaft löschen" : "Permanently delete account & data",
                    icon: "trash",
                    titleColor: Color.kuroDestructiveInk
                ) {
                    guard profileActionScope.isCurrent(ticket, session: imports.accountSession) else { return }
                    deleteConfirmationTicket = ticket
                    showDeleteConfirmation = true
                }

                if let privacy = KuroLegalLinks.privacy {
                    rowHairline
                    ProfileLinkRow(title: german ? "Datenschutz" : "Privacy policy", icon: "hand.raised", url: privacy)
                }
            }
            .alert(german ? "Konto löschen?" : "Delete your account?", isPresented: $showDeleteConfirmation) {
                Button(german ? "Abbrechen" : "Cancel", role: .cancel) { }
                Button(german ? "Alles löschen" : "Delete everything", role: .destructive) {
                    profileActionScope.launch(origin: confirmationTicket, session: imports.accountSession) { origin in
                        guard profileActionScope.isCurrent(origin, session: imports.accountSession) else { return }
                        isDeleting = true
                        defer {
                            if profileActionScope.isCurrent(origin, session: imports.accountSession) { isDeleting = false }
                        }
                        do {
                            let isApple = await auth.isAppleUser
                            guard profileActionScope.isCurrent(origin, session: imports.accountSession) else { return }
                            let appleCode = isApple ? await obtainAppleAuthorizationCode() : nil
                            guard profileActionScope.isCurrent(origin, session: imports.accountSession) else { return }
                            try await session.deleteAccount(appleAuthorizationCode: appleCode, expectedAccount: origin.account)
                            guard profileActionScope.isCurrent(origin, session: imports.accountSession) else { return }
                            if let journey { journey.close() } else { dismiss() }
                        } catch {
                            guard profileActionScope.isCurrent(origin, session: imports.accountSession) else { return }
                            showToast(.error, title: german ? "Konto nicht gelöscht" : "Account not deleted",
                                      subtitle: Self.deletionFailureLine(error, german: german))
                        }
                    }
                }
            } message: {
                Text(german
                     ? "Dein Konto, deine Listen, Clubmitgliedschaften und alle zugehörigen Daten werden dauerhaft gelöscht. Das lässt sich nicht rückgängig machen."
                     : "This permanently deletes your account, lists, club memberships and all associated data. It cannot be undone.")
            }

            if isDeleting {
                statusLine(german ? "Konto wird gelöscht …" : "Deleting account …")
            }
        }
    }

    /// A plain EN/DE line for a failed deletion (never the raw, English-only error text).
    private static func deletionFailureLine(_ error: Error, german: Bool) -> String {
        if error is URLError {
            return german ? "Versuch es erneut, wenn du online bist." : "Try again when you're online."
        }
        return german ? "Versuch es gleich noch einmal." : "Try again in a moment."
    }

    // MARK: About

    /// Spec D11: Profile > About holds Data sources and credits, Contact us (the contact form, the
    /// Impressum's second contact channel), the Terms link (once confirmed) and the version.
    private var aboutSection: some View {
        let german = isGermanLocale
        return VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            sectionHeader(german ? "Über Kuro." : "About.")
            profileGroup {
                ProfileQuietRow(
                    title: german ? "Datenquellen und Danksagung" : "Data sources and credits",
                    subtitle: "AniList · MangaDex · MangaUpdates · AnimeThemes",
                    icon: "books.vertical",
                    showsChevron: true
                ) {
                    push(ShellJourneyPages.dataSources)
                }
                rowHairline
                ProfileQuietRow(
                    title: german ? "Kontakt" : "Contact us",
                    subtitle: german ? "Support & Feedback" : "Support & feedback",
                    icon: "envelope",
                    showsChevron: true
                ) {
                    showContact = true
                }
                if let terms = KuroLegalLinks.terms {
                    rowHairline
                    ProfileLinkRow(title: german ? "Nutzungsbedingungen" : "Terms of service", icon: "doc.plaintext", url: terms)
                }
            }
            versionLine
        }
    }

    // MARK: Advanced

    private var advancedSection: some View {
        let german = isGermanLocale
        // F1–F3: the shared fold control (prototype easing, instant with Reduce Motion, says what it
        // does, remembered for the session).
        let advanced = folds.binding(page: "profile", section: "advanced")
        return profileGroup {
            VStack(alignment: .leading, spacing: 0) {
                KuroFoldButton(isExpanded: advanced,
                               expandLabel: KuroLocale.text("Show advanced", "Erweitert anzeigen"),
                               collapseLabel: KuroLocale.text("Hide advanced", "Erweitert ausblenden")) { title, open in
                    HStack {
                        Text(title)
                            .font(.kuroBody(weight: .regular))
                            .foregroundStyle(Color.kuroInkSecondary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.kuroCaption(weight: .medium))
                            .foregroundStyle(Color.kuroInk)
                            .rotationEffect(.degrees(open ? 90 : 0))
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("profile.advanced")
                if advanced.wrappedValue {
                    VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                        ProfileQuietRow(
                            title: german ? "Cache leeren" : "Clear cache",
                            subtitle: german ? "Bild- und Detail-Caches zurücksetzen" : "Reset image & detail caches",
                            icon: "internaldrive",
                            horizontalPadding: 0
                        ) {
                            Task {
                                await KuroDiskDetailCache.clearAll()
                                await artworkMaterials.clearAll()
                                URLCache.shared.removeAllCachedResponses()
                                KuroAccessibility.successHaptic()
                                showToast(.success, title: german ? "Cache geleert" : "Cache cleared", subtitle: nil)
                            }
                        }
                        if flags.isStreamingAvailabilityV1Enabled {
                            streamingFreshnessPreview
                        }
                    }
                    .padding(.bottom, KuroDesignSpacing.sm)
                    .transition(.opacity)
                }
            }
        }
    }

    private var streamingFreshnessPreview: some View {
        ProfileFreshnessCard(
            snapshot: streamingObservability,
            isRefreshing: isRefreshingStreamingObservability
        ) {
            Task { await refreshStreamingObservability() }
        }
    }

    @MainActor
    private func refreshStreamingObservability() async {
        isRefreshingStreamingObservability = true
        defer { isRefreshingStreamingObservability = false }
        await availability.fetchStreamingServiceRegistry()
        await availability.fetchUserStreamingServices()
        streamingObservability = await availability.streamingObservabilitySnapshot()
    }

    @ViewBuilder
    private func importResultPreview(_ result: ProfileImportResult) -> some View {
        ProfileImportResultCard(
            result: result,
            isGermanLocale: isGermanLocale,
            onDismiss: { importCoordinator?.dismissImportResult() },
            onUndo: {
                importCoordinator?.undo()
            }
        )
    }

    private func obtainAppleAuthorizationCode() async -> String? {
        await withCheckedContinuation { continuation in
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = []
            let delegate = AppleAuthCodeDelegate { code in
                continuation.resume(returning: code)
            }
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = delegate
            // Keep delegate alive until callback fires.
            objc_setAssociatedObject(controller, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
            controller.performRequests()
        }
    }

    private func showToast(_ kind: KuroToastState.Kind, title: String, subtitle: String?) {
        withAnimation(.easeInOut(duration: 0.18)) {
            toast = KuroToastState(kind: kind, title: title, subtitle: subtitle, actionTitle: nil, onAction: nil)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(.easeInOut(duration: 0.18)) {
                toast = nil
            }
        }
    }

    private var versionLine: some View {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"
        return Text(isGermanLocale ? "Kuro \(version) (Build \(build))" : "Kuro \(version) (build \(build))")
            .font(.kuroMeta())
            .foregroundStyle(Color.kuroInkQuiet)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityLabel(isGermanLocale ? "Version \(version), Build \(build)" : "Version \(version), build \(build)")
    }

    private func sectionHeader(_ title: String) -> some View {
        // The prototype's in-page section heading ("Seasons": SF 18 w550, −0.7), not the shared
        // header's regular-weight title.
        Text(title)
            .kuroRoleText(.title)
            .foregroundStyle(Color.kuroInk)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private func profileGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.kuroControlFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var rowHairline: some View {
        Rectangle()
            .fill(Color.black.opacity(0.07))
            .frame(height: 0.5)
    }

    private func statusLine(_ text: String) -> some View {
        HStack(spacing: 10) {
            KuroBusyMark(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.kuroMeta())
                .foregroundStyle(Color.kuroInkSecondary)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Profile's lifecycle inside its journey (pure, tested in NavshellTests).
nonisolated enum ProfileLifecyclePolicy {
    /// Whether Profile sets its account-scoped import work up again on appear: the first appearance,
    /// another account, or after a teardown. Coming back from a pushed page keeps what is running.
    static func needsSetup(setUpFor: String??, current: String?, hasCoordinator: Bool) -> Bool {
        guard hasCoordinator, let setUpFor else { return true }
        return setUpFor != current
    }
}

/// An outbound link row (privacy, terms): same geometry as the quiet rows, an arrow marks "leaves Kuro".
private struct ProfileLinkRow: View {
    let title: String
    var icon: String? = nil
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.kuroControlInk)
                        .frame(width: 30, height: 30)
                        .background(Color.white, in: Circle())
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.kuroCustom(15, weight: .medium, relativeTo: .headline, maxSize: 30)).tracking(-0.2)
                    .foregroundStyle(Color.kuroInk)
                Spacer(minLength: KuroDesignSpacing.sm)
                Image(systemName: "arrow.up.right")
                    .font(.kuroCustom(12, weight: .medium, relativeTo: .caption1, maxSize: 18))
                    .foregroundStyle(Color.kuroInkSecondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .accessibilityHint(KuroLocale.text("Opens in your browser", "Öffnet sich im Browser"))
    }
}

private struct ProfileQuietRow: View {
    let title: String
    var subtitle: String? = nil
    var trailing: String? = nil
    var badge: String? = nil
    var icon: String? = nil
    var titleColor: Color = Color.kuroInk
    var isEnabled: Bool = true
    var showsChevron: Bool = false
    var horizontalPadding: CGFloat = 0
    let action: () -> Void

    var body: some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            action()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(titleColor == Color.kuroDestructiveInk ? Color.kuroDestructiveInk : Color.kuroControlInk)
                        .frame(width: 30, height: 30)
                        .background(Color.white, in: Circle())
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.kuroCustom(15, weight: .medium, relativeTo: .headline, maxSize: 30)).tracking(-0.2)
                            .foregroundStyle(titleColor)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if let badge, !badge.isEmpty {
                            Text(badge)
                                .font(.kuroCustom(10.5, weight: .semibold, relativeTo: .caption2, maxSize: 18))
                                .foregroundStyle(Color.kuroControlInk)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.white, in: Capsule(style: .continuous))
                                .lineLimit(1)
                        }
                    }
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.kuroMeta())
                            .foregroundStyle(Color.kuroInkSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: KuroDesignSpacing.sm)
                if let trailing, !trailing.isEmpty {
                    Text(trailing)
                        .font(.kuroMeta(weight: .medium))
                        .foregroundStyle(Color.kuroInkSecondary)
                        .monospacedDigit()
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.kuroInkQuiet)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(KuroPressStyle(pressedScale: 0.99))
        .disabled(!isEnabled)
    }
}

// MARK: - Streaming Service Picker Sheet

private struct StreamingServicePickerSheet: View {
    @Environment(IdentityStore.self) private var identity
    @Environment(ProviderAvailabilityStore.self) private var availability
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSlugs: Set<String> = []
    @State private var isSaving: Bool = false
    @State private var actionScope = AccountActionScope()
    @State private var saveFailed = false

    private var animeServices: [ProviderAvailabilityStore.StreamingServiceRecord] {
        availability.streamingServiceRegistry.filter { $0.media_types.contains("ANIME") }
    }

    private var mangaServices: [ProviderAvailabilityStore.StreamingServiceRecord] {
        availability.streamingServiceRegistry.filter { $0.media_types.contains("MANGA") }
    }

    var body: some View {
        let ticket = actionScope.capture(session: availability.accountSession)
        return NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                    Text(KuroLocale.text("Choose the services you use. Kuro uses them to show where a title is available.",
                                         "Wähle die Dienste, die du nutzt. Kuro zeigt damit, wo ein Titel verfügbar ist."))
                        .font(.kuroBody())
                        .foregroundStyle(Color.kuroInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)

                    if !animeServices.isEmpty {
                        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                            KuroSectionHeader("Anime", size: .title)
                                .padding(.horizontal, 20)

                            ForEach(animeServices) { svc in
                                ServiceToggleRow(
                                    name: svc.display_name,
                                    isSelected: selectedSlugs.contains(svc.slug)
                                ) {
                                    if selectedSlugs.contains(svc.slug) {
                                        selectedSlugs.remove(svc.slug)
                                    } else {
                                        selectedSlugs.insert(svc.slug)
                                    }
                                }
                            }
                        }
                    }

                    if !mangaServices.isEmpty {
                        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                            KuroSectionHeader("Manga", size: .title)
                                .padding(.horizontal, 20)

                            ForEach(mangaServices) { svc in
                                ServiceToggleRow(
                                    name: svc.display_name,
                                    isSelected: selectedSlugs.contains(svc.slug)
                                ) {
                                    if selectedSlugs.contains(svc.slug) {
                                        selectedSlugs.remove(svc.slug)
                                    } else {
                                        selectedSlugs.insert(svc.slug)
                                    }
                                }
                            }
                        }
                    }

                    Spacer(minLength: 24)
                }
                .padding(.top, KuroDesignSpacing.md)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(KuroLocale.text("Streaming services", "Streamingdienste"))
                        .font(.kuroCustom(15, weight: .semibold, relativeTo: .headline, maxSize: 28)).tracking(-0.2)
                        .foregroundStyle(Color.kuroInk)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let selection = Array(selectedSlugs).sorted()
                        actionScope.launch(origin: ticket, session: availability.accountSession) { origin in
                            guard actionScope.isCurrent(origin, session: availability.accountSession) else { return }
                            isSaving = true
                            let saved = await availability.saveUserStreamingServices(selection)
                            guard actionScope.isCurrent(origin, session: availability.accountSession) else { return }
                            isSaving = false
                            if saved { dismiss() } else { saveFailed = true }
                        }
                    } label: {
                        if isSaving {
                            KuroBusyMark(width: 28)
                                .frame(minWidth: 44, minHeight: 44)
                                .accessibilityLabel(KuroLocale.text("Saving", "Wird gesichert"))
                        } else {
                            Text(KuroLocale.text("Save", "Sichern"))
                                .font(.kuroBody(weight: .medium))
                                .foregroundStyle(Color.kuroInk)
                        }
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(KuroLocale.text("Cancel", "Abbrechen")) { dismiss() }
                        .font(.kuroBody(weight: .regular))
                        .foregroundStyle(Color.kuroInk)
                }
            }
        }
        .task(id: identity.currentUserId) {
            actionScope.deactivate()
            actionScope.activate(session: availability.accountSession)
            selectedSlugs = Set(availability.userStreamingServices)
            isSaving = false; saveFailed = false
        }
        .alert(KuroLocale.text("Services weren't saved", "Dienste wurden nicht gesichert"), isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(KuroLocale.text("Your selection is still here. Try again when you're online.",
                                 "Deine Auswahl ist noch da. Versuch es erneut, sobald du online bist."))
        }
        .onDisappear { actionScope.deactivate() }
    }
}

private struct ServiceToggleRow: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            action()
        }) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.kuroCustom(20, weight: .light, relativeTo: .title3, maxSize: 30))
                    .foregroundStyle(isSelected ? Color.kuroInk : Color.kuroInkQuiet)
                    .accessibilityHidden(true)

                Text(name)
                    .font(.kuroBody(weight: .regular))
                    .foregroundStyle(Color.kuroInk)

                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct ProfileImportResultCard: View {
    let result: ProfileImportResult
    let isGermanLocale: Bool
    let onDismiss: () -> Void
    let onUndo: () -> Void

    private var eyebrow: String {
        switch result {
        case .applied:
            return "Import"
        case .needsReview:
            return isGermanLocale ? "Prüfung" : "Review"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(eyebrow)
                        .kuroKicker()
                        .accessibilityHidden(true)

                    Text(result.titleText)
                        .font(.kuroCustom(15, weight: .semibold, relativeTo: .headline, maxSize: 28)).tracking(-0.2)
                        .foregroundStyle(Color.kuroInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(result.summaryText)
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let detail = result.detailText {
                        Text(detail)
                            .font(.kuroMeta())
                            .foregroundStyle(Color.kuroInkQuiet)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.kuroCustom(13, weight: .medium, relativeTo: .footnote, maxSize: 20))
                        .foregroundStyle(Color.kuroInkSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isGermanLocale ? "Hinweis schließen" : "Dismiss")
            }

            if result.undoSessionId != nil {
                Button(action: onUndo) {
                    Text(isGermanLocale ? "Import rückgängig machen" : "Undo import")
                        .font(.kuroButtonLabel(weight: .medium))
                        .foregroundStyle(Color.kuroInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                                .stroke(Color.kuroHairline, lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isGermanLocale ? "Import rückgängig machen" : "Undo import")
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                .fill(Color.kuroCanvasQuiet)
                .overlay(
                    RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                        .stroke(Color.kuroHairline, lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Apple Auth Code Delegate (for token revocation on account deletion)

private final class AppleAuthCodeDelegate: NSObject, ASAuthorizationControllerDelegate {
    private let completion: (String?) -> Void
    private var didComplete = false

    init(completion: @escaping (String?) -> Void) {
        self.completion = completion
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard !didComplete else { return }
        didComplete = true
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
           let codeData = credential.authorizationCode,
           let code = String(data: codeData, encoding: .utf8) {
            completion(code)
        } else {
            completion(nil)
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        guard !didComplete else { return }
        didComplete = true
        completion(nil)
    }
}


/// The actual mounted window supplies the browser anchor; no global-screen lookup is used.
private struct ProfileMALWindowAnchor: UIViewControllerRepresentable {
    let receive: (UIWindow?) -> Void
    func makeUIViewController(context: Context) -> AnchorController {
        let controller = AnchorController(); controller.receive = receive; return controller
    }
    func updateUIViewController(_ controller: AnchorController, context: Context) { controller.receive = receive }
    final class AnchorController: UIViewController {
        var receive: ((UIWindow?) -> Void)?
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); receive?(view.window) }
        override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); receive?(nil) }
    }
}

/// Pure rules selecting the account's up to four canon covers on Profile (highest-rated / completed).
nonisolated enum ProfileCanon {
    static func topEntries(_ entries: [LibraryEntry], limit: Int = 4) -> [LibraryEntry] {
        guard limit > 0 else { return [] }
        let eligible = entries.filter { $0.status == .completed || ($0.rating?.value ?? 0) > 0 }
        let sorted = eligible.sorted { lhs, rhs in
            let lScore = lhs.rating?.value ?? 0
            let rScore = rhs.rating?.value ?? 0
            if lScore != rScore { return lScore > rScore }
            let lDone = lhs.status == .completed ? 1 : 0
            let rDone = rhs.status == .completed ? 1 : 0
            if lDone != rDone { return lDone > rDone }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            if lhs.key.kind != rhs.key.kind { return lhs.key.kind == .anime }
            return lhs.key.id < rhs.key.id
        }
        return Array(sorted.prefix(limit))
    }

    static func taskId(account: String?, entries: [LibraryEntry]) -> String {
        let ids = topEntries(entries, limit: 4).map { "\($0.key.kind.rawValue)-\($0.key.id)" }.joined(separator: ",")
        return "\(account ?? "")|\(ids)"
    }

    static func mediaMap(previews: [ListStatus: [Media]], extra: [MediaKey: Media]) -> [MediaKey: Media] {
        var map = extra
        for list in previews.values {
            for media in list where map[media.libraryKey] == nil {
                map[media.libraryKey] = media
            }
        }
        return map
    }
}
