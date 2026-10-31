import AuthenticationServices
import KuroCore
import KuroLibrary
import SwiftUI
import UniformTypeIdentifiers

/// Focused AniList / MAL account / MAL XML choice. Uses the existing Profile import coordinator.
/// Does not create a credential store or skip review.
struct ImportSourceChooser: View {
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

    private var isGerman: Bool {
        Locale.current.language.languageCode?.identifier.lowercased().hasPrefix("de") == true
    }

    var body: some View {
        let owner = coordinator
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Spacer()
                    Button(isGerman ? "Schließen" : "Close") { dismiss() }
                        .kuroKicker()
                        .frame(minHeight: 44)
                }
                Text(isGerman ? "Importiere deine Liste" : "Import your list")
                    .font(.kuroDisplay(weight: .light))
                    .tracking(-0.8)
                    .foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                Rectangle()
                    .fill(Color.kuroInk)
                    .frame(width: 46, height: 2)
                Text(isGerman
                     ? "Wähle eine Quelle. Bestehende Titel bleiben, bis du eine Änderung bestätigst."
                     : "Choose a source. Existing titles stay until you approve a change.")
                    .font(.kuroBody())
                    .foregroundStyle(Color.kuroInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300, alignment: .leading)

                sourceButton(
                    kicker: "AniList",
                    title: isGerman ? "Benutzername, dann Prüfung" : "Username, then review",
                    label: isGerman ? "AniList importieren" : "Import from AniList"
                ) {
                    if owner?.beginAniListSelection() == true { showAniList = true }
                }

                sourceButton(
                    kicker: isGerman ? "MAL-Datei" : "MAL file",
                    title: isGerman ? "XML von diesem Gerät" : "XML from this device",
                    label: isGerman ? "MAL-Datei importieren" : "Import a MAL file"
                ) {
                    if owner?.beginMALFileSelection() == true { showMALImporter = true }
                }

                if imports.malAccountAvailable {
                    if let identity = imports.malAccountIdentity {
                        Text(isGerman ? "Verbunden: \(identity)" : "Connected: \(identity)")
                            .font(.kuroCaption())
                            .foregroundStyle(Color.kuroInkSecondary)
                        sourceButton(
                            kicker: "MAL",
                            title: isGerman ? "Verbundenes Konto" : "Connected account",
                            label: isGerman ? "Verbundenes MAL-Konto importieren" : "Import the connected MAL account"
                        ) {
                            owner?.prepareConnectedMAL()
                        }
                    }
                    sourceButton(
                        kicker: "MAL",
                        title: isGerman ? "Konto verbinden" : "Connect an account",
                        label: isGerman ? "MAL-Konto verbinden" : "Connect a MAL account"
                    ) {
                        guard let malAnchor else { return }
                        owner?.connectAndImportMAL(presentationAnchor: malAnchor)
                    }
                    .disabled(malAnchor == nil)
                    Text(MALAccountList.notesLimitation)
                        .font(.kuroCaption())
                        .foregroundStyle(Color.kuroInkQuiet)
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
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Color.kuroCanvasPage)
        .presentationDetents([.medium, .large], selection: $sheetDetent)
        .presentationDragIndicator(.visible)
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
                await owner?.receiveAniList(response)
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
    }

    private func sourceButton(kicker: String, title: String, label: String, action: @escaping () -> Void) -> some View {
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
