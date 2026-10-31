import AuthenticationServices
import KuroCore
import KuroLibrary
import SwiftUI
import UniformTypeIdentifiers

// Dedicated profile/settings page (moved out of the header to keep the top bar clean).
struct ProfileView: View {
    var onOpenConciergeImportReview: ((String) -> Void)? = nil
    var onImportNavigation: ((ImportResultDestination) -> Void)? = nil
    var onOpenCollection: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var streamingObservability: ProviderAvailabilityStore.StreamingObservabilitySnapshot? = nil
    @State private var isRefreshingStreamingObservability: Bool = false
    @State private var sceneryActive = false

    var body: some View {
        let profileImports = importCoordinator
        let anchor = malPresentationAnchor
        let ticket = profileActionScope.capture(session: imports.accountSession)
        let confirmationTicket = deleteConfirmationTicket
        ZStack {
            Color.kuroCanvasPage
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                    identityHeader

                    librarySection
                        .padding(.horizontal, KuroDesignSpacing.padding)

                    importsSection(profileImports, anchor: anchor)
                        .padding(.horizontal, KuroDesignSpacing.padding)

                    if flags.seriesFoundationV1Enabled || profileImports?.importResult != nil {
                        pendingSection(profileImports)
                            .padding(.horizontal, KuroDesignSpacing.padding)
                    }

                    clubsSection
                        .padding(.horizontal, KuroDesignSpacing.padding)

                    preferencesSection
                        .padding(.horizontal, KuroDesignSpacing.padding)

                    accountSection(ticket: ticket, confirmationTicket: confirmationTicket)
                        .padding(.horizontal, KuroDesignSpacing.padding)

                    Spacer(minLength: 24)
                }
                .padding(.bottom, 48)
            }
            // Ensure the last rows can scroll fully above the home indicator / tab chrome.
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 24)
            }
        }
        .background(ProfileMALWindowAnchor { malPresentationAnchor = $0 }.frame(width: 0, height: 0))
        .scrollContentBackground(.hidden)
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
            // Keep the profile "club context" warm so Clubs opens instantly.
            await clubs.fetchMyClubs()
            if flags.isStreamingAvailabilityV1Enabled {
                await refreshStreamingObservability()
            }
        }
        .onAppear { sceneryActive = true }
        .onDisappear {
            sceneryActive = false
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
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.kuroInk)
                    .frame(width: 44, height: 44)
                    .background {
                        Circle()
                            .fill(Color.white)
                            .overlay(Circle().stroke(Color.kuroHairline, lineWidth: 0.5))
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
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
                            Text("CLUBS")
                                .font(.kuroNavigation(weight: .regular))
                                .tracking(1.5)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showClubs = false }
                                .font(.kuroBody(weight: .light))
                        }
                    }
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
                            Button("Done") { showConciergeSheet = false }
                                .font(.kuroBody(weight: .light))
                        }
                    }
                    // The Concierge sheet's own presentation context (ConciergeView reads its routes).
                    .routePresenter()
            }
        }
    }

    private var identityHeader: some View {
        ZStack(alignment: .bottomLeading) {
            KuroSceneryLoop(tone: .neutralCanvas, isActive: sceneryActive && !reduceMotion, magnify: 1.7)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.2),
                    .init(color: Color.white.opacity(0.72), location: 0.72),
                    .init(color: Color.kuroCanvasPage, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 2) {
                Text(identity.currentUserInitial)
                    .font(.system(size: 72, weight: .thin, design: .serif))
                    .foregroundStyle(Color.kuroInk)
                    .accessibilityHidden(true)
                Text(isGermanLocale ? "Dein Konto" : "Your account")
                    .font(.kuroDisplay())
                    .foregroundStyle(Color.kuroInk)
                    .accessibilityAddTraits(.isHeader)
                Text(accountCaption)
                    .font(.kuroBody())
                    .foregroundStyle(Color.kuroInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, KuroDesignSpacing.padding)
            .padding(.bottom, 8)
        }
        .frame(height: 280)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private func libraryFigure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.kuroFeature())
                .foregroundStyle(Color.kuroInk)
                .monospacedDigit()
            Text(label)
                .font(.kuroCaption())
                .foregroundStyle(Color.kuroInkSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private var accountCaption: String {
        if let email = identity.currentUserEmail, !email.isEmpty {
            return email.contains("privaterelay.appleid.com") ? "Signed in with Apple" : email
        }
        return "Discover, track, enjoy."
    }

    private var librarySection: some View {
        let entries = library.allEntries
        let animeLists = entries.filter { $0.key.kind == .anime }
        let mangaLists = entries.filter { $0.key.kind == .manga }
        let doneCount = entries.filter { $0.status == .completed }.count
        let episodesWatched = animeLists.reduce(0) { $0 + $1.progress }
        let chaptersRead = mangaLists.reduce(0) { $0 + $1.progress }
        let scoredEntries = entries.compactMap { $0.rating?.score100 }
        let avgRating = scoredEntries.isEmpty ? 0.0 : Double(scoredEntries.reduce(0, +)) / Double(scoredEntries.count)
        let avgText = scoredEntries.isEmpty ? "—" : String(format: "%.0f", avgRating)
        let summary = isGermanLocale
            ? "\(animeLists.count) Anime · \(mangaLists.count) Manga · \(doneCount) abgeschlossen"
            : "\(animeLists.count) anime · \(mangaLists.count) manga · \(doneCount) completed"

        return VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            sectionHeader(isGermanLocale ? "Bibliothek" : "Library")
            profileGroup {
                HStack(alignment: .top, spacing: 0) {
                    libraryFigure("\(animeLists.count)", isGermanLocale ? "Anime" : "Anime")
                    libraryFigure("\(mangaLists.count)", isGermanLocale ? "Manga" : "Manga")
                    libraryFigure("\(doneCount)", isGermanLocale ? "Fertig" : "Done")
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(summary)
                .padding(.vertical, 4)

                rowHairline

                ProfileQuietRow(
                    title: isGermanLocale ? "Sammlung öffnen" : "Open Collection"
                ) {
                    onOpenCollection?()
                }

                rowHairline

                DisclosureGroup {
                    HStack(spacing: 0) {
                        ProfileProgressMetric(value: "\(episodesWatched)", label: "EPISODES")
                        ProfileProgressMetric(value: "\(chaptersRead)", label: "CHAPTERS")
                        ProfileProgressMetric(value: avgText, label: "AVG SCORE")
                    }
                    .padding(.bottom, KuroDesignSpacing.sm)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isGermanLocale ? "Fortschritt auf diesem Gerät" : "Progress on this device")
                            .font(.kuroBody(weight: .regular))
                            .foregroundStyle(Color.kuroInk)
                        Text(isGermanLocale
                             ? "Das sind aktuelle Listensummen, keine Lebenszeit-Historie."
                             : "These are current list totals, not lifetime history.")
                            .font(.kuroCaption())
                            .foregroundStyle(Color.kuroInkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, KuroDesignSpacing.md)
                .tint(Color.kuroInk)
            }
        }
    }

    private func importsSection(_ coordinator: ProfileImportCoordinator?, anchor: ASPresentationAnchor?) -> some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            sectionHeader("Imports")
            profileGroup {
                ProfileQuietRow(
                    title: isGermanLocale ? "MAL-Export importieren" : "Import a MAL export",
                    subtitle: isGermanLocale
                        ? "XML von deinem Gerät. Kein Konto-API."
                        : "XML from this device. No account API."
                ) {
                    if coordinator?.beginMALFileSelection() == true { showMALImporter = true }
                }

                if imports.malAccountAvailable {
                    if let malIdentity = imports.malAccountIdentity {
                        rowHairline
                        groupCaption("Connected MAL account: \(malIdentity)")
                        ProfileQuietRow(
                            title: "Import connected MAL account again",
                            subtitle: "Read Anime and Manga, then review before saving",
                            isEnabled: coordinator?.isProcessingAniListImport != true && !imports.importBusy
                        ) {
                            coordinator?.prepareConnectedMAL()
                        }
                        rowHairline
                        ProfileQuietRow(
                            title: isGermanLocale ? "MAL trennen" : "Disconnect MAL",
                            subtitle: isGermanLocale
                                ? "Entfernt die Zugangsdaten auf diesem Gerät"
                                : "Remove credentials from this device"
                        ) {
                            coordinator?.disconnectMALAccount()
                        }
                    }
                    rowHairline
                    ProfileQuietRow(
                        title: isGermanLocale ? "MAL verbinden und importieren" : "Connect and import MAL",
                        subtitle: isGermanLocale
                            ? "Anime und Manga. Bestehende Notizen bleiben erhalten."
                            : "Anime and Manga. Existing notes are preserved.",
                        isEnabled: anchor != nil && coordinator?.isProcessingAniListImport != true
                    ) {
                        guard let anchor else { return }
                        coordinator?.connectAndImportMAL(presentationAnchor: anchor)
                    }
                    groupCaption(MALAccountList.notesLimitation)
                } else {
                    groupCaption(isGermanLocale
                                 ? "Die MAL-Kontoverbindung ist noch nicht verfügbar."
                                 : "MAL account connection is not available yet.")
                }

                rowHairline
                ProfileQuietRow(
                    title: isGermanLocale ? "Aus AniList importieren" : "Import from AniList",
                    subtitle: isGermanLocale
                        ? "Vorschau und Import fur Anime- oder Manga-Listen"
                        : "Preview and import your anime or manga lists"
                ) {
                    // A new import gesture does not replay an unresolved action.
                    if coordinator?.beginAniListSelection() == true { showAniListImportSheet = true }
                }

                if importCoordinator?.profileRetryOffered == true {
                    rowHairline
                    ProfileQuietRow(
                        title: isGermanLocale ? "Import wiederholen" : "Retry import",
                        subtitle: isGermanLocale
                            ? "Dieselbe Übernahme erneut senden"
                            : "Send the same import again"
                    ) {
                        coordinator?.retry()
                    }
                }

                if importCoordinator?.isProcessingAniListImport == true {
                    statusLine(isGermanLocale ? "AniList wird importiert..." : "Importing from AniList...")
                }
            }
        }
    }

    private func pendingSection(_ profileImports: ProfileImportCoordinator?) -> some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            sectionHeader("Pending")
            if flags.seriesFoundationV1Enabled {
                ImportHistorySection(imports: imports) { job in
                    guard profileActionScope.capture(session: imports.accountSession) != nil else { return }
                    importWorkflowJob = job; showImportWorkflow = true
                }
            }
            if let importResult = profileImports?.importResult {
                importResultPreview(importResult)
            }
        }
    }

    private var clubsSection: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            sectionHeader("Clubs")
            profileGroup {
                ProfileQuietRow(
                    title: "Clubs",
                    subtitle: "Shared rails, no feeds",
                    trailing: "\(clubs.myClubs.count)"
                ) {
                    showClubs = true
                }
            }
        }
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            sectionHeader("Preferences")
            profileGroup {
                ProfileQuietRow(
                    title: "Sync Data",
                    subtitle: "Refresh your lists & rails"
                ) {
                    Task {
                        guard let context = imports.accountSession.current else { return }
                        isSyncing = true
                        defer { isSyncing = false }
                        do {
                            try await library.refresh()
                            guard imports.accountSession.isCurrent(context) else { return }
                            await collection.fetchCollectionFeed()
                            guard imports.accountSession.isCurrent(context) else { return }
                            if collection.collectionErrorMessage != nil {
                                showToast(.error, title: "Collection unavailable", subtitle: "Your list was refreshed, but Collection could not be loaded.")
                                return
                            }
                            await releases.fetchUpcomingForUser(days: 7)
                            guard imports.accountSession.isCurrent(context) else { return }
                            KuroAccessibility.successHaptic()
                            showToast(.success, title: "Synced", subtitle: "Lists updated")
                        } catch is CancellationError {
                            return
                        } catch {
                            guard imports.accountSession.isCurrent(context) else { return }
                            showToast(.error, title: "Sync failed", subtitle: "Your lists were not refreshed.")
                        }
                    }
                }

                rowHairline

                ProfileQuietRow(
                    title: "Concierge",
                    subtitle: isGermanLocale
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

            if flags.isStreamingAvailabilityV1Enabled {
                streamingFreshnessPreview
                    .sheet(isPresented: $showServicePicker) {
                        StreamingServicePickerSheet()
                    }
            }

            if isSyncing {
                statusLine("Syncing…")
            }
        }
    }

    private var streamingServicesRow: some View {
        let services = availability.userStreamingServices
        let names = services.compactMap { slug in
            availability.streamingServiceRegistry.first(where: { $0.slug == slug })?.display_name
        }
        let subtitle: String = {
            if services.isEmpty {
                return "Set your streaming services to filter your collection."
            }
            return names.joined(separator: ", ")
        }()
        return ProfileQuietRow(
            title: "Streaming services",
            subtitle: subtitle,
            trailing: "\(services.count)"
        ) {
            showServicePicker = true
        }
    }

    private func accountSection(
        ticket: AccountActionScope.Ticket?,
        confirmationTicket: AccountActionScope.Ticket?
    ) -> some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            sectionHeader("Account")
            profileGroup {
                ProfileQuietRow(
                    title: "Sign Out",
                    subtitle: "Log out of your account"
                ) {
                    profileActionScope.launch(origin: ticket, session: imports.accountSession) { origin in
                        await session.signOut(expectedAccount: origin.account)
                    }
                }

                rowHairline

                ProfileQuietRow(
                    title: "Delete Account",
                    subtitle: "Permanently remove all data",
                    titleColor: Color.kuroError
                ) {
                    guard profileActionScope.isCurrent(ticket, session: imports.accountSession) else { return }
                    deleteConfirmationTicket = ticket
                    showDeleteConfirmation = true
                }
            }
            .alert("Delete Account", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete Everything", role: .destructive) {
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
                            showToast(.error, title: "Deletion failed", subtitle: error.localizedDescription)
                        }
                    }
                }
            } message: {
                Text("This will permanently delete your account, lists, club memberships, and all associated data. This action cannot be undone.")
            }

            if isDeleting {
                statusLine("Deleting account...")
            }

            footer

            profileGroup {
                DisclosureGroup {
                    ProfileQuietRow(
                        title: "Clear Cache",
                        subtitle: "Reset image + detail caches",
                        horizontalPadding: 0
                    ) {
                        Task {
                            await KuroDiskDetailCache.clearAll()
                            URLCache.shared.removeAllCachedResponses()
                            KuroAccessibility.successHaptic()
                        }
                    }
                } label: {
                    Text("Advanced")
                        .font(.kuroBody(weight: .regular))
                        .foregroundStyle(Color.kuroInk)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .padding(.horizontal, KuroDesignSpacing.md)
                .tint(Color.kuroInk)
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

    private var isGermanLocale: Bool {
        let language = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        return language.hasPrefix("de")
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

    private var footer: some View {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"

        return VStack(spacing: 10) {
            if let url = URL(string: "https://kuro.app/privacy") {
                Link(destination: url) {
                    Text("Privacy Policy")
                        .font(.kuroCaption(weight: .light))
                        .foregroundStyle(Color.kuroInkSecondary)
                        .underline(color: Color.kuroHairline)
                }
                .buttonStyle(.plain)
            }

            Text("KURO  •  v\(version) (\(build))")
                .font(.kuroMicro(weight: .light))
                .tracking(1.6)
                .foregroundStyle(Color.kuroInkQuiet)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.kuroTitle())
            .foregroundStyle(Color.kuroInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
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
            .padding(.leading, KuroDesignSpacing.md)
    }

    private func groupCaption(_ text: String) -> some View {
        Text(text)
            .font(.kuroCaption())
            .foregroundStyle(Color.kuroInkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, KuroDesignSpacing.md)
            .padding(.vertical, 8)
    }

    private func statusLine(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.9)
                .tint(Color.kuroInkSecondary)
            Text(text)
                .font(.kuroCaption())
                .foregroundStyle(Color.kuroInkSecondary)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44, alignment: .leading)
        .padding(.horizontal, KuroDesignSpacing.md)
    }
}

private struct ProfileProgressMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.kuroTitle())
                .foregroundStyle(Color.kuroInk)
                .monospacedDigit()
            Text(label)
                .font(.kuroMicro(weight: .medium))
                .foregroundStyle(Color.kuroInkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

private struct ProfileQuietRow: View {
    let title: String
    var subtitle: String? = nil
    var trailing: String? = nil
    var titleColor: Color = Color.kuroInk
    var isEnabled: Bool = true
    var horizontalPadding: CGFloat = KuroDesignSpacing.md
    let action: () -> Void

    var body: some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            action()
        } label: {
            HStack(alignment: .center, spacing: KuroDesignSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.kuroTitle())
                        .foregroundStyle(titleColor)
                        .multilineTextAlignment(.leading)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.kuroCaption())
                            .foregroundStyle(Color.kuroInkSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: KuroDesignSpacing.sm)
                if let trailing, !trailing.isEmpty {
                    Text(trailing)
                        .font(.kuroCaption())
                        .foregroundStyle(Color.kuroInkSecondary)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    Text("Select the services you use. This filters your collection and enables shared availability in clubs.")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroBlack60)
                        .padding(.horizontal, 20)

                    if !animeServices.isEmpty {
                        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                            Text("ANIME")
                                .font(.kuroMicro(weight: .medium))
                                .tracking(2.0)
                                .foregroundColor(.kuroBlack60)
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
                            Text("MANGA")
                                .font(.kuroMicro(weight: .medium))
                                .tracking(2.0)
                                .foregroundColor(.kuroBlack60)
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
                    Text("SERVICES")
                        .font(.kuroNavigation(weight: .regular))
                        .tracking(1.5)
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
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.kuroBlack60)
                        } else {
                            Text("Save")
                                .font(.kuroBody(weight: .light))
                        }
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.kuroBody(weight: .light))
                }
            }
        }
        .task(id: identity.currentUserId) {
            actionScope.deactivate()
            actionScope.activate(session: availability.accountSession)
            selectedSlugs = Set(availability.userStreamingServices)
            isSaving = false; saveFailed = false
        }
        .alert("Services were not saved", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: { Text("Your selection is still here. Retry when the connection is available.") }
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
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(isSelected ? .kuroBlack80 : .kuroBlack30)

                Text(name)
                    .font(.kuroBody(weight: .regular))
                    .foregroundColor(.kuroBlack80)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
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
            return isGermanLocale ? "IMPORT" : "IMPORT"
        case .needsReview:
            return isGermanLocale ? "PRUFUNG" : "REVIEW"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(eyebrow)
                        .font(.kuroMicro(weight: .medium))
                        .tracking(2.0)
                        .foregroundStyle(Color.kuroInkSecondary)

                    Text(result.titleText)
                        .font(.kuroBody(weight: .regular))
                        .foregroundStyle(Color.kuroInk)

                    Text(result.summaryText)
                        .font(.kuroCaption(weight: .light))
                        .foregroundStyle(Color.kuroInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let detail = result.detailText {
                        Text(detail)
                            .font(.kuroCaption(weight: .light))
                            .foregroundStyle(Color.kuroInkQuiet)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.kuroInkSecondary)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.kuroCanvasPage)
                        )
                }
                .buttonStyle(.plain)
            }

            if result.undoSessionId != nil {
                Button(action: onUndo) {
                    Text(isGermanLocale ? "RÜCKGÄNGIG" : "UNDO")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.2)
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
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.system(size: 12, weight: .semibold))
                        Text(isGermanLocale ? "IN CONCIERGE PRUFEN" : "REVIEW IN CONCIERGE")
                            .font(.kuroMicro(weight: .medium))
                            .tracking(1.2)
                    }
                    .foregroundStyle(Color.white)
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
