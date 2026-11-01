import AuthenticationServices
import KuroCore
import KuroLibrary
import SwiftUI
import UniformTypeIdentifiers

/// Focused AniList / MAL account / MAL XML choice. Uses the existing Profile import coordinator.
/// Does not create a credential store or skip review.
/// Renders every coordinator outcome itself (it is offered from Onboarding, the empty Collection and
/// Profile's new-account block; it owns its own coordinator instance, so it never relies on Profile's):
/// the progress line, the toast, a retry for an uncertain delivery, and
/// the result card with Undo (an applied legacy AniList import) or the Concierge review handoff (an
/// import that needs review). The sheet cannot be closed while an import runs, because closing stops
/// the coordinator and would cancel the write without a word.
struct ImportSourceChooser: View {
    /// What the result card's primary button does: open the lists, or (Onboarding, which cannot show
    /// the lists yet) continue the presenter's own flow. Either way it calls `onNavigate`.
    enum ResultAction {
        case seeLists
        case continueFlow
    }

    var resultAction: ResultAction = .seeLists
    var onNavigate: (ImportResultDestination) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ImportsService.self) private var imports
    @Environment(LibraryStore.self) private var library
    @Environment(CollectionStore.self) private var collection
    @Environment(ReleasesStore.self) private var releases
    @Environment(FeatureFlags.self) private var flags

    @State private var coordinator: ProfileImportCoordinator?
    @State private var actionScope = AccountActionScope()
    @State private var showMALImporter = false
    @State private var showAniList = false
    @State private var malAnchor: ASPresentationAnchor?
    @State private var pendingAniListReview: ImportOutcome?
    @State private var pendingAniListTicket: AccountActionScope.Ticket?
    @State private var showWorkflow = false
    @State private var workflowJob: ImportOutcome?
    @State private var sheetDetent: PresentationDetent = .large
    /// From confirming the AniList sheet until the coordinator returns (covers the gap before its own
    /// processing flag is set).
    @State private var aniListInFlight = false
    /// The review handed to Concierge (an item sheet, so the prompt is never read stale).
    @State private var conciergeReview: ConciergeReview?
    /// From the Undo tap until the coordinator's undo finishes: closing would cancel it mid-write.
    @State private var undoInFlight = false
    /// From the Retry tap until the resend finishes (covers the gap before the coordinator's own
    /// processing flag is set).
    @State private var retryInFlight = false

    private var isGerman: Bool { KuroLocale.isGerman }

    var body: some View {
        let owner = coordinator
        let undoing = undoInFlight
        let busy = aniListInFlight || retryInFlight || undoing || owner?.isProcessingAniListImport == true
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Text(isGerman ? "Schließen" : "Close")
                            .font(.kuroMeta(weight: .medium))
                            .foregroundStyle(busy ? Color.kuroInkQuiet : Color.kuroInk)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }
                Text(isGerman ? "Importiere deine Liste" : "Import your list")
                    .kuroRoleText(.feature)
                    .foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                Rectangle()
                    .fill(Color.kuroInk)
                    .frame(width: 46, height: 2)
                // True in both worlds: an import only adds titles at once when none of them is in the
                // lists yet (`ImportReconciler.qualifiesForAutoApply`); anything else goes to review.
                Text(isGerman
                     ? "Wähle eine Quelle. Titel, die schon in deinen Listen sind, ändern sich erst, wenn du bestätigst."
                     : "Choose a source. Titles already in your lists change only after you confirm.")
                    .font(.kuroBody())
                    .foregroundStyle(Color.kuroInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if undoing {
                    statusLine(isGerman ? "Import wird rückgängig gemacht …" : "Undoing the import …")
                } else if busy {
                    statusLine(isGerman ? "Deine Liste wird importiert …" : "Importing your list …")
                }

                if let result = owner?.importResult {
                    ImportChooserResultCard(
                        result: result,
                        isGermanLocale: isGerman,
                        primaryTitle: resultAction == .continueFlow
                            ? (isGerman ? "Weiter" : "Continue")
                            : (isGerman ? "Zu deinen Listen" : "See your lists"),
                        isBusy: busy,
                        onDismiss: { owner?.dismissImportResult() },
                        onUndo: {
                            guard let task = owner?.undo() else { return }
                            undoInFlight = true
                            Task { @MainActor in
                                await task.value
                                undoInFlight = false
                            }
                        },
                        onReview: {
                            guard case .needsReview(_, _, _, let importText) = result else { return }
                            owner?.dismissImportResult()
                            conciergeReview = ConciergeReview(text: importText)
                        },
                        onSeeLists: { onNavigate(.fullCollection) }
                    )
                }

                if owner?.profileRetryOffered == true, !busy {
                    sourceButton(
                        kicker: isGerman ? "Unterbrochen" : "Interrupted",
                        title: isGerman ? "Import wiederholen" : "Retry import",
                        label: isGerman ? "Dieselbe Übernahme erneut senden" : "Send the same import again"
                    ) {
                        guard let task = owner?.retry() else { return }
                        retryInFlight = true
                        Task { @MainActor in
                            await task.value
                            retryInFlight = false
                        }
                    }
                }

                // Flags off, the legacy AniList path adds new titles at once when nothing needs review.
                sourceButton(
                    kicker: "AniList",
                    title: flags.seriesFoundationV1Enabled
                        ? (isGerman ? "Benutzername, dann Prüfung" : "Username, then review")
                        : (isGerman ? "Benutzername, dann Import" : "Username, then import"),
                    label: isGerman ? "AniList importieren" : "Import from AniList"
                ) {
                    if owner?.beginAniListSelection() == true { showAniList = true }
                }
                .disabled(busy)

                // Without `series_foundation_v1` the coordinator refuses both MAL paths: AniList only.
                if flags.seriesFoundationV1Enabled {
                    sourceButton(
                        kicker: isGerman ? "MAL-Datei" : "MAL file",
                        title: isGerman ? "XML von diesem Gerät" : "XML from this device",
                        label: isGerman ? "MAL-Datei importieren" : "Import a MAL file"
                    ) {
                        if owner?.beginMALFileSelection() == true { showMALImporter = true }
                    }
                    .disabled(busy)

                    if imports.malAccountAvailable {
                        if let identity = imports.malAccountIdentity {
                            Text(isGerman ? "Verbunden: \(identity)" : "Connected: \(identity)")
                                .font(.kuroMeta())
                                .foregroundStyle(Color.kuroInkSecondary)
                            sourceButton(
                                kicker: "MAL",
                                title: isGerman ? "Verbundenes Konto" : "Connected account",
                                label: isGerman ? "Verbundenes MAL-Konto importieren" : "Import the connected MAL account"
                            ) {
                                owner?.prepareConnectedMAL()
                            }
                            .disabled(busy)
                        }
                        sourceButton(
                            kicker: "MAL",
                            title: isGerman ? "Konto verbinden" : "Connect an account",
                            label: isGerman ? "MAL-Konto verbinden" : "Connect a MAL account"
                        ) {
                            guard let malAnchor else { return }
                            owner?.connectAndImportMAL(presentationAnchor: malAnchor)
                        }
                        .disabled(malAnchor == nil || busy)
                        Text(ImportCopy.malNotesLimitation(german: isGerman))
                            .font(.kuroMeta())
                            .foregroundStyle(Color.kuroInkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(isGerman ? "MAL-Konto" : "MAL account")
                                .kuroKicker()
                            Text(isGerman
                                 ? "Die Kontoverbindung ist noch nicht verfügbar. AniList und die XML-Datei funktionieren trotzdem."
                                 : "Account connection is not available yet. AniList and the XML file still work.")
                                .font(.kuroBody())
                                .foregroundStyle(Color.kuroInkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .kuroReadableWidth()
        }
        .background(Color.kuroCanvasPage)
        .overlay(alignment: .top) {
            if let toast = owner?.toast {
                KuroToast(toast: toast)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .transition(.opacity)
            }
        }
        .presentationDetents([.medium, .large], selection: $sheetDetent)
        .presentationDragIndicator(.visible)
        // Closing stops the coordinator, which would cancel a running import mid-write.
        .interactiveDismissDisabled(busy)
        .onChange(of: owner?.importResult?.id) { _, id in
            // The result card (Undo, review) must be in view, not below a medium detent.
            if id != nil { sheetDetent = .large }
        }
        .background(ImportWindowAnchor { malAnchor = $0 }.frame(width: 0, height: 0))
        .task {
            actionScope.activate(session: imports.accountSession)
            coordinator?.stop()
            coordinator = ProfileImportCoordinator(
                imports: imports, library: library, collection: collection,
                releases: releases, flags: flags, isGermanLocale: isGerman
            )
            await coordinator?.refreshMALIdentity()
        }
        .onDisappear {
            actionScope.deactivate()
            coordinator?.stop()
            coordinator = nil
        }
        .fileImporter(isPresented: $showMALImporter, allowedContentTypes: [.xml]) { result in
            owner?.receiveMALFile(result)
        }
        .sheet(isPresented: $showAniList, onDismiss: {
            guard let job = pendingAniListReview else { return }
            pendingAniListReview = nil
            let origin = pendingAniListTicket
            pendingAniListTicket = nil
            guard actionScope.isCurrent(origin, session: imports.accountSession) else { return }
            workflowJob = job
            showWorkflow = true
        }) {
            let origin = actionScope.capture(session: imports.accountSession)
            ConciergeAniListImportSheet(
                imports: imports,
                isGermanLocale: isGerman,
                usesStructuredImport: flags.seriesFoundationV1Enabled,
                onPrepared: { job in
                    guard actionScope.isCurrent(origin, session: imports.accountSession) else { return }
                    pendingAniListReview = job
                    pendingAniListTicket = origin
                }
            ) { response in
                aniListInFlight = true
                await owner?.receiveAniList(response)
                aniListInFlight = false
            }
        }
        .onChange(of: owner?.workflowJob?.id) { _, _ in
            guard let job = owner?.workflowJob else { return }
            guard actionScope.capture(session: imports.accountSession) != nil else { return }
            workflowJob = job
            showWorkflow = true
        }
        .sheet(isPresented: $showWorkflow, onDismiss: { coordinator?.dismissWorkflow() }) {
            ImportWorkflowSheet(imports: imports, job: workflowJob) { destination in
                guard actionScope.capture(session: imports.accountSession) != nil else { return }
                onNavigate(destination)
            }
        }
        .sheet(item: $conciergeReview) { review in
            // The same review Profile hands to Concierge, presented here because neither Onboarding
            // nor Collection has a Concierge page to hand it to.
            NavigationStack {
                ConciergeView(assistantEnabled: true, initialPrompt: review.text) { destination in
                    conciergeReview = nil
                    onNavigate(destination)
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isGerman ? "Fertig" : "Done") { conciergeReview = nil }
                            .font(.kuroBody(weight: .light))
                    }
                }
                // The review sheet's own presentation context (ConciergeView reads its routes).
                .routePresenter()
            }
        }
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

    private func sourceButton(kicker: String, title: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(kicker)
                    .kuroKicker()
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title)
                        .font(.kuroCustom(15, weight: .medium, relativeTo: .headline, maxSize: 30)).tracking(-0.2)
                        .foregroundStyle(Color.kuroInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.right")
                        .font(.kuroCustom(13, weight: .medium, relativeTo: .footnote, maxSize: 20))
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
}

/// An import text handed to the Concierge review sheet.
private struct ConciergeReview: Identifiable {
    let id = UUID()
    let text: String
}

/// The coordinator's import result inside the chooser: what was saved (with Undo while the server
/// still offers it) or the review the import needs. Same content as Profile's card.
private struct ImportChooserResultCard: View {
    let result: ProfileImportResult
    let isGermanLocale: Bool
    /// "See your lists", or "Continue" where the presenter cannot show the lists (Onboarding).
    let primaryTitle: String
    /// An import or its undo is running: every action here would close the chooser or cancel it.
    let isBusy: Bool
    let onDismiss: () -> Void
    let onUndo: () -> Void
    let onReview: () -> Void
    let onSeeLists: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(isReview ? (isGermanLocale ? "Prüfung" : "Review") : "Import")
                        .kuroKicker()
                        .accessibilityHidden(true)
                    Text(result.titleText)
                        .font(.kuroCustom(15, weight: .medium, relativeTo: .headline, maxSize: 30)).tracking(-0.2)
                        .foregroundStyle(Color.kuroInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
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
                .disabled(isBusy)
                .accessibilityLabel(isGermanLocale ? "Hinweis schließen" : "Dismiss")
            }

            if isReview {
                primaryButton(isGermanLocale ? "Im Concierge prüfen" : "Review in Concierge", action: onReview)
            } else {
                primaryButton(primaryTitle, action: onSeeLists)
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
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                .fill(Color.kuroCanvasQuiet)
                .overlay(
                    RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                        .stroke(Color.kuroHairline, lineWidth: 0.5)
                )
        )
    }

    private var isReview: Bool {
        if case .needsReview = result { return true }
        return false
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.kuroButtonLabel(weight: .medium))
                .foregroundStyle(Color.kuroWhite)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                        .fill(Color.kuroInk)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }
}

/// Window anchor for the MAL browser session. No global screen lookup.
private struct ImportWindowAnchor: UIViewControllerRepresentable {
    let receive: (UIWindow?) -> Void
    func makeUIViewController(context: Context) -> AnchorController {
        let controller = AnchorController()
        controller.receive = receive
        return controller
    }
    func updateUIViewController(_ controller: AnchorController, context: Context) {
        controller.receive = receive
    }
    final class AnchorController: UIViewController {
        var receive: ((UIWindow?) -> Void)?
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            receive?(view.window)
        }
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            receive?(nil)
        }
    }
}
