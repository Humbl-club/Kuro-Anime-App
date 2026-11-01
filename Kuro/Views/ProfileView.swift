import AuthenticationServices
import KuroCore
import KuroLibrary
import SwiftUI
import UniformTypeIdentifiers

// Profile: the account hub (rulebook §14.3). Order: identity, Your library (counts + "Your lists"),
// Imports and connections (incl. pending and resumable imports), Clubs, Preferences, Account and
// privacy, About (Data sources and credits, Terms once confirmed, version), then a quiet Advanced disclosure (cache tools; the streaming freshness card when that
// feature is on). Rows: serif title, sans subtitle in secondary ink, hairlines, no chevrons.
struct ProfileView: View {
    var onOpenConciergeImportReview: ((String) -> Void)? = nil
    var onImportNavigation: ((ImportResultDestination) -> Void)? = nil
    var onOpenCollection: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
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
    @State private var profileActionScope = AccountActionScope()
    @State private var deleteConfirmationTicket: AccountActionScope.Ticket?
    @State private var importCoordinator: ProfileImportCoordinator?
    @State private var isSyncing: Bool = false
    @State private var showClubs: Bool = false
    @State private var toast: KuroToastState? = nil
    @State private var showDeleteConfirmation: Bool = false
    @State private var isDeleting: Bool = false
    @State private var showServicePicker: Bool = false
    @State private var showAniListImportSheet: Bool = false
    @State private var pendingAniListReview: ImportOutcome?
    @State private var pendingAniListTicket: AccountActionScope.Ticket?
    @State private var showMALImporter: Bool = false
    @State private var malPresentationAnchor: ASPresentationAnchor?
    @State private var showConciergeSheet: Bool = false
    @State private var showImportWorkflow = false
    @State private var importWorkflowJob: ImportOutcome?
    @State private var showDataSources = false
    @State private var showImportChooser = false
    @State private var showFindSheet = false
    @State private var streamingObservability: ProviderAvailabilityStore.StreamingObservabilitySnapshot? = nil
    @State private var isRefreshingStreamingObservability: Bool = false

    private var isGermanLocale: Bool { KuroLocale.isGerman }

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
            // Ensure the last rows can scroll fully above the home indicator / tab chrome.
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 24)
            }
        }
        .background(ProfileMALWindowAnchor { malPresentationAnchor = $0 }.frame(width: 0, height: 0))
        .scrollContentBackground(.hidden)
        // Kept from the native polish pass: Profile mutations and toasts change rows in place without
        // implicit motion (rulebook §8 asks to keep this suppression).
        .transaction { $0.animation = nil }
        .task(id: identity.currentUserId) {
            profileActionScope.deactivate()
            profileActionScope.activate(session: imports.accountSession)
            deleteConfirmationTicket = nil
            showDeleteConfirmation = false
            isDeleting = false
            importCoordinator?.stop()
            importCoordinator = ProfileImportCoordinator(imports: imports, library: library,
                collection: collection, releases: releases, flags: flags, isGermanLocale: isGermanLocale)
            await importCoordinator?.refreshMALIdentity()
            await collection.loadListPreview()
            // Keep the profile "club context" warm so Clubs opens instantly.
            await clubs.refreshMyClubsIfStale()
            if flags.isStreamingAvailabilityV1Enabled {
                await refreshStreamingObservability()
            }
        }
        .onDisappear {
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
        }
        .overlay(alignment: .topTrailing) {
            Button(action: {
                KuroAccessibility.impactHaptic(.light)
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.kuroCustom(15, weight: .medium, relativeTo: .body, maxSize: 22))
                    .foregroundStyle(Color.kuroInk)
                    .frame(width: 44, height: 44)
                    .background {
                        Circle()
                            .fill(Color.kuroWhite)
                            .overlay(Circle().stroke(Color.kuroHairline, lineWidth: 0.5))
                    }
            }
            .buttonStyle(KuroPressStyle())
            .accessibilityLabel(isGermanLocale ? "Schließen" : "Close")
            .padding(.top, 12)
            .padding(.trailing, 12)
        }
        .overlay(alignment: .top) {
            if let toast = profileImports?.toast ?? toast {
                KuroToast(toast: toast)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showClubs) {
            NavigationStack {
                ClubsView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text(isGermanLocale ? "Clubs" : "Clubs")
                                .font(.kuroCustom(15, weight: .semibold, relativeTo: .headline, maxSize: 28)).tracking(-0.2)
                                .foregroundStyle(Color.kuroInk)
                                .accessibilityAddTraits(.isHeader)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(isGermanLocale ? "Fertig" : "Done") { showClubs = false }
                                .font(.kuroBody(weight: .regular))
                                .foregroundStyle(Color.kuroInk)
                        }
                    }
            }
        }
        .sheet(isPresented: $showDataSources) {
            DataSourcesView()
        }
        .sheet(isPresented: $showImportChooser) {
            ImportSourceChooser { destination in
                showImportChooser = false
                guard profileActionScope.capture(session: imports.accountSession) != nil else { return }
                onImportNavigation?(destination)
            }
        }
        .sheet(isPresented: $showFindSheet) {
            NavigationStack {
                EditorialSearchView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(isGermanLocale ? "Fertig" : "Done") { showFindSheet = false }
                                .font(.kuroBody(weight: .regular))
                                .foregroundStyle(Color.kuroInk)
                        }
                    }
                    // Search's own presentation context (its cards open details through routes).
                    .routePresenter()
            }
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
        }
        .sheet(isPresented: $showConciergeSheet) {
            NavigationStack {
                ConciergeView(assistantEnabled: true, onImportNavigation: onImportNavigation)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(isGermanLocale ? "Fertig" : "Done") { showConciergeSheet = false }
                                .font(.kuroBody(weight: .regular))
                                .foregroundStyle(Color.kuroInk)
                        }
                    }
                    // The Concierge sheet's own presentation context (ConciergeView reads its routes).
                    .routePresenter()
            }
        }
    }

    // MARK: Identity

    /// A restrained, still mountain band (rulebook §8: the Profile band is a still image), then a
    /// compact initial and the real account identity. Nothing is clipped at large text sizes.
    private var identityHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            KuroSceneryLoop(tone: .neutralCanvas, isActive: false, magnify: 1.7)
                .frame(height: 132)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.25),
                            .init(color: Color.kuroCanvasPage.opacity(0.7), location: 0.7),
                            .init(color: Color.kuroCanvasPage, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .accessibilityHidden(true)
                .allowsHitTesting(false)

            HStack(alignment: .center, spacing: KuroDesignSpacing.md) {
                Text(identity.currentUserInitial)
                    .font(.kuroCustom(24, weight: .semibold, relativeTo: .title2, maxSize: 38)).tracking(-0.6)
                    .foregroundStyle(Color.kuroInk)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.kuroWhite))
                    .overlay(Circle().strokeBorder(Color.kuroKeyRim, lineWidth: 1))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(accountHeadline)
                        .font(.kuroTitleName())
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
            .padding(.horizontal, KuroDesignSpacing.padding)
            .padding(.top, -28)
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
                KuroStateView(.failed(hasCachedContent: false),
                              title: german ? "Bibliothek konnte nicht geladen werden." : "Your library couldn't load.",
                              layout: .inline)
            case .empty:
                newAccountLibrary
            case nil:
                Text(ProfileListsPolicy.summary(entries, german: german))
                    .font(.kuroBody())
                    .foregroundStyle(Color.kuroInkSecondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
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
    }

    /// A new account (amendment 10, spec §5.3): no zero tiles or counts, the line "Nothing saved yet."
    /// in the prototype's empty-headline voice, then Import (the import chooser) and Find (Search).
    private var newAccountLibrary: some View {
        let german = isGermanLocale
        return VStack(alignment: .leading, spacing: 0) {
            Text(ProfileListsPolicy.newAccountHeadline(german: german))
                .font(.kuroCustom(20, weight: .bold, relativeTo: .title3, maxSize: 36))
                .tracking(-0.6)
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
        KuroOutlineButton(ProfileListsPolicy.findTitle(german: german)) { showFindSheet = true }
    }

    // MARK: Imports and connections

    private func importsSection(_ coordinator: ProfileImportCoordinator?, anchor: ASPresentationAnchor?) -> some View {
        let german = isGermanLocale
        return VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            sectionHeader(german ? "Importe und Verbindungen." : "Imports and connections.")
            profileGroup {
                ProfileQuietRow(
                    title: german ? "Aus AniList importieren" : "Import from AniList",
                    subtitle: german
                        ? "Benutzername, dann Vorschau vor dem Speichern"
                        : "Username, then a preview before saving",
                    isEnabled: coordinator?.isProcessingAniListImport != true
                ) {
                    // A new import gesture does not replay an unresolved action.
                    if coordinator?.beginAniListSelection() == true { showAniListImportSheet = true }
                }

                if imports.malAccountAvailable {
                    rowHairline
                    if let malIdentity = imports.malAccountIdentity {
                        groupCaption(german ? "Verbundenes MAL-Konto: \(malIdentity)" : "Connected MAL account: \(malIdentity)")
                        ProfileQuietRow(
                            title: german ? "Verbundenes MAL-Konto erneut importieren" : "Import the connected MAL account again",
                            subtitle: german
                                ? "Anime und Manga lesen, dann vor dem Speichern prüfen"
                                : "Read Anime and Manga, then review before saving",
                            isEnabled: coordinator?.isProcessingAniListImport != true && !imports.importBusy
                        ) {
                            coordinator?.prepareConnectedMAL()
                        }
                        rowHairline
                        ProfileQuietRow(
                            title: german ? "MAL trennen" : "Disconnect MAL",
                            subtitle: german
                                ? "Entfernt die Zugangsdaten auf diesem Gerät"
                                : "Removes the credentials from this device"
                        ) {
                            coordinator?.disconnectMALAccount()
                        }
                    } else {
                        ProfileQuietRow(
                            title: german ? "MAL-Konto verbinden" : "Connect a MAL account",
                            subtitle: german
                                ? "Anime und Manga. Bestehende Notizen bleiben erhalten."
                                : "Anime and Manga. Existing notes are kept.",
                            isEnabled: anchor != nil && coordinator?.isProcessingAniListImport != true
                        ) {
                            guard let anchor else { return }
                            coordinator?.connectAndImportMAL(presentationAnchor: anchor)
                        }
                    }
                    groupCaption(ImportCopy.malNotesLimitation(german: german))
                }

                rowHairline
                ProfileQuietRow(
                    title: german ? "MAL-Datei importieren" : "Import a MAL file",
                    subtitle: german
                        ? "XML-Export von diesem Gerät"
                        : "An XML export from this device"
                ) {
                    if coordinator?.beginMALFileSelection() == true { showMALImporter = true }
                }

                if coordinator?.profileRetryOffered == true {
                    rowHairline
                    ProfileQuietRow(
                        title: german ? "Import wiederholen" : "Retry import",
                        subtitle: german
                            ? "Dieselbe Übernahme erneut senden"
                            : "Send the same import again"
                    ) {
                        coordinator?.retry()
                    }
                }

                if coordinator?.isProcessingAniListImport == true {
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
                    subtitle: german ? "Private Gruppen mit 2 bis 20 Mitgliedern" : "Private groups of 2 to 20 people",
                    trailing: count > 0 ? "\(count)" : nil
                ) {
                    showClubs = true
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
                ProfileQuietRow(
                    title: german ? "Listen aktualisieren" : "Refresh your lists",
                    subtitle: german ? "Liest deine Listen und Termine neu" : "Reads your lists and dates again",
                    isEnabled: !isSyncing
                ) {
                    syncLists()
                }

                rowHairline

                ProfileQuietRow(
                    title: "Concierge",
                    subtitle: german
                        ? "Beschreibe eine Stimmung oder füge eine Liste ein"
                        : "Describe a mood or paste a list"
                ) {
                    showConciergeSheet = true
                }

                if flags.isStreamingAvailabilityV1Enabled {
                    rowHairline
                    streamingServicesRow
                }
            }
            .sheet(isPresented: $showServicePicker) {
                StreamingServicePickerSheet()
            }

            if isSyncing {
                statusLine(german ? "Wird aktualisiert …" : "Refreshing …")
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
            ? (german ? "Wähle deine Streamingdienste." : "Choose your streaming services.")
            : names.joined(separator: ", ")
        return ProfileQuietRow(
            title: german ? "Streamingdienste" : "Streaming services",
            subtitle: subtitle,
            trailing: services.isEmpty ? nil : "\(services.count)"
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
            sectionHeader(german ? "Konto und Datenschutz." : "Account and privacy.")
            profileGroup {
                ProfileQuietRow(
                    title: german ? "Abmelden" : "Sign out",
                    subtitle: german ? "Deine Listen bleiben in deinem Konto" : "Your lists stay in your account"
                ) {
                    profileActionScope.launch(origin: ticket, session: imports.accountSession) { origin in
                        await session.signOut(expectedAccount: origin.account)
                    }
                }

                rowHairline

                ProfileQuietRow(
                    title: german ? "Konto löschen" : "Delete account",
                    subtitle: german ? "Entfernt dein Konto und alle Daten dauerhaft" : "Permanently removes your account and all data",
                    titleColor: Color.kuroDestructiveInk
                ) {
                    guard profileActionScope.isCurrent(ticket, session: imports.accountSession) else { return }
                    deleteConfirmationTicket = ticket
                    showDeleteConfirmation = true
                }

                if let privacy = KuroLegalLinks.privacy {
                    rowHairline
                    ProfileLinkRow(title: german ? "Datenschutz" : "Privacy policy", url: privacy)
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
                            dismiss()
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

    /// Spec D11: Profile > About holds Data sources and credits, the Terms link (once confirmed) and
    /// the version.
    private var aboutSection: some View {
        let german = isGermanLocale
        return VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            sectionHeader(german ? "Über Kuro." : "About.")
            profileGroup {
                ProfileQuietRow(
                    title: german ? "Datenquellen und Danksagung" : "Data sources and credits",
                    subtitle: "AniList, MangaDex, MangaUpdates, AnimeThemes"
                ) {
                    showDataSources = true
                }
                if let terms = KuroLegalLinks.terms {
                    rowHairline
                    ProfileLinkRow(title: german ? "Nutzungsbedingungen" : "Terms of service", url: terms)
                }
            }
            versionLine
        }
    }

    // MARK: Advanced

    private var advancedSection: some View {
        let german = isGermanLocale
        return profileGroup {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                    ProfileQuietRow(
                        title: german ? "Cache leeren" : "Clear cache",
                        subtitle: german ? "Setzt Bild- und Detail-Caches zurück" : "Resets image and detail caches",
                        horizontalPadding: 0
                    ) {
                        Task {
                            await KuroDiskDetailCache.clearAll()
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
            } label: {
                Text(german ? "Erweitert" : "Advanced")
                    .font(.kuroBody(weight: .regular))
                    .foregroundStyle(Color.kuroInkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .tint(Color.kuroInk)
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
            },
            onContinueToConcierge: {
                guard case .needsReview(_, _, _, let importText) = result else { return }
                importCoordinator?.dismissImportResult()
                onOpenConciergeImportReview?(importText)
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowHairline: some View {
        Rectangle()
            .fill(Color.kuroHairline)
            .frame(height: 0.5)
    }

    private func groupCaption(_ text: String) -> some View {
        Text(text)
            .font(.kuroMeta())
            .foregroundStyle(Color.kuroInkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
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

/// An outbound link row (privacy, terms): same geometry as the quiet rows, an arrow marks "leaves Kuro".
private struct ProfileLinkRow: View {
    let title: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: KuroDesignSpacing.sm) {
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
    var titleColor: Color = Color.kuroInk
    var isEnabled: Bool = true
    var horizontalPadding: CGFloat = 0
    let action: () -> Void

    var body: some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            action()
        } label: {
            HStack(alignment: .center, spacing: KuroDesignSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.kuroCustom(15, weight: .medium, relativeTo: .headline, maxSize: 30)).tracking(-0.2)
                        .foregroundStyle(titleColor)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
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
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroInkSecondary)
                        .monospacedDigit()
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
    let onContinueToConcierge: () -> Void

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

            if case .needsReview = result {
                Button(action: onContinueToConcierge) {
                    HStack(spacing: 8) {
                        Text(isGermanLocale ? "Im Concierge prüfen" : "Review in Concierge")
                            .font(.kuroButtonLabel(weight: .medium))
                    }
                    .foregroundStyle(Color.kuroWhite)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                            .fill(Color.kuroInk)
                    )
                }
                .buttonStyle(.plain)
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
