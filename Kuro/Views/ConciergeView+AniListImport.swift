import SwiftUI
import KuroCore
import KuroLibrary

// AniList import in Home's grammar (details-songs spec §13, D16): the eyebrow "IMPORT · ANILIST" over the
// EXISTING title (24 semibold −0.85) and description (13 pt); "Form / Preview" as refine words on the same
// phase; a glance-style username field; check rows (type, statuses; several can be on) in the calendar-card
// shell; `KuroInkButton` with the shipped upper-case literal. Behaviour, bindings, busy states, Stop (N7)
// and every string are unchanged.
struct ConciergeAniListImportSheet: View {
    let imports: ImportsService
    let isGermanLocale: Bool
    let onImportCompleted: (ConciergeAniListImportResponse) async -> Void
    let usesStructuredImport: Bool
    let onPrepared: ((ImportOutcome) -> Void)?

    init(imports: ImportsService, isGermanLocale: Bool, usesStructuredImport: Bool = false,
         onPrepared: ((ImportOutcome) -> Void)? = nil,
         onImportCompleted: @escaping (ConciergeAniListImportResponse) async -> Void) {
        self.imports = imports; self.isGermanLocale = isGermanLocale
        self.usesStructuredImport = usesStructuredImport; self.onPrepared = onPrepared
        self.onImportCompleted = onImportCompleted
    }

    @Environment(\.dismiss) private var dismiss

    @State private var coordinator = ConciergeAniListImportCoordinator()
    @State private var selectedImportMode: Bool?
    private var usesStructuredPath: Bool { selectedImportMode ?? usesStructuredImport }
    @State private var username: String = ""
    @State private var includeAnime: Bool = true
    @State private var includeManga: Bool = true
    @State private var includeCurrent: Bool = true
    @State private var includeCompleted: Bool = true
    @State private var includePlanning: Bool = true
    @State private var includePaused: Bool = false
    @State private var includeDropped: Bool = false
    @State private var includeRepeating: Bool = false
    @FocusState private var usernameFocused: Bool
    /// The Stop confirmation is showing (N7).
    @State private var confirmStop = false

    /// AniList is being read or the import is being sent: closing would cancel it (N7).
    private var isBusy: Bool { coordinator.isPreviewing || coordinator.isImporting }

    private var canPreview: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (includeAnime || includeManga)
            && (includeCurrent || includeCompleted || includePlanning || includePaused || includeDropped || includeRepeating)
    }

    private var selectedTypes: [String] {
        var values: [String] = []
        if includeAnime { values.append("ANIME") }
        if includeManga { values.append("MANGA") }
        return values
    }

    private var selectedStatuses: [String] {
        var values: [String] = []
        if includeCurrent { values.append("CURRENT") }
        if includeCompleted { values.append("COMPLETED") }
        if includePlanning { values.append("PLANNING") }
        if includePaused { values.append("PAUSED") }
        if includeDropped { values.append("DROPPED") }
        if includeRepeating { values.append("REPEATING") }
        return values
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection
                    stepIndicator
                    workflowSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .background(Color.kuroCanvasPage.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // N7: while AniList is read or the import is sent, closing would cancel it without a
                    // word, so the control becomes Stop (confirmed), as in the import chooser.
                    Button(isBusy ? ImportChooserTopControl.stopAction(german: isGermanLocale)
                                  : (isGermanLocale ? "Fertig" : "Done")) {
                        if isBusy { confirmStop = true } else { dismiss() }
                    }
                    .font(.kuroMeta(weight: .medium))
                    .foregroundStyle(Color.kuroInk)
                    .accessibilityHint(isBusy
                                       ? (isGermanLocale ? "Hält den laufenden Import an." : "Stops the running import.")
                                       : "")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isBusy)
        .confirmationDialog(ImportChooserTopControl.stopTitle(german: isGermanLocale),
                            isPresented: $confirmStop, titleVisibility: .visible) {
            Button(ImportChooserTopControl.stopAction(german: isGermanLocale), role: .destructive) { stopImport() }
            Button(isGermanLocale ? "Weiter importieren" : "Keep importing", role: .cancel) {}
        } message: {
            Text(ImportChooserTopControl.stopMessage(german: isGermanLocale))
        }
        .onAppear {
            coordinator.activate(using: imports)
            usernameFocused = true
        }
        .onDisappear { coordinator.stop() }
        .onChange(of: imports.accountSession.current) { _, _ in coordinator.stop(); dismiss() }
    }

    private var headerSection: some View {
        ImportPageHeading(
            eyebrow: ImportRestyleCopy.aniListEyebrow(german: isGermanLocale),
            title: isGermanLocale ? "AniList importieren" : "Import from AniList",
            description: usesStructuredPath
                ? (isGermanLocale
                    ? "Kuro liest die ganze ausgewählte Liste, du prüfst jeden Titel und bestätigst dann, was gespeichert wird. Deine Kuro-Werte bleiben, solange du keine Änderung wählst."
                    : "Kuro reads the complete selected list, you review every title, then confirm what to save. Existing Kuro values stay unless you choose updates.")
                : (isGermanLocale
                    ? "Erst Vorschau, dann Import. So siehst du Titel, Status und Umfang, bevor Kuro etwas übernimmt."
                    : "Preview first, then confirm. See titles, status, and scope before Kuro imports anything.")
        )
    }

    /// The phase as refine words (the same binding as the old step pills: the coordinator's phase).
    private var stepIndicator: some View {
        HStack(spacing: 16) {
            stepPill(
                title: isGermanLocale ? "Formular" : "Form",
                isActive: coordinator.phase == .form
            )
            stepPill(
                title: isGermanLocale ? "Vorschau" : "Preview",
                isActive: coordinator.phase != .form
            )
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var workflowSection: some View {
        switch coordinator.phase {
        case .form:
            formCard
        case .previewing:
            VStack(alignment: .leading, spacing: 14) {
                selectionSummaryCard
                previewLoadingCard
            }
        case .ready:
            if usesStructuredPath {
                KuroLoadingView(scope: .inline, label: isGermanLocale ? "Prüfung wird geöffnet …" : "Opening your review …")
            } else {
            VStack(alignment: .leading, spacing: 14) {
                selectionSummaryCard
                if let preview = coordinator.preview {
                    previewCard(preview: preview, errorMessage: nil, isImporting: false)
                }
                actionButtons(
                    primaryTitle: isGermanLocale ? "IMPORT BESTÄTIGEN" : "CONFIRM IMPORT",
                    primaryAction: { Task { await confirmImport() } },
                    secondaryTitle: isGermanLocale ? "FORMULAR ÄNDERN" : "EDIT FORM",
                    secondaryAction: {
                        resetForm()
                        usernameFocused = true
                    }
                )
            }
            }
        case .importing:
            VStack(alignment: .leading, spacing: 14) {
                selectionSummaryCard
                if let preview = coordinator.preview {
                    previewCard(
                        preview: preview,
                        errorMessage: nil,
                        isImporting: true
                    )
                } else {
                    previewLoadingCard
                }
            }
        case .error:
            VStack(alignment: .leading, spacing: 14) {
                if let preview = coordinator.preview {
                    selectionSummaryCard
                    previewCard(
                        preview: preview,
                        errorMessage: coordinator.errorMessage,
                        isImporting: false
                    )
                    actionButtons(
                        primaryTitle: isGermanLocale ? "IMPORT ERNEUT VERSUCHEN" : "RETRY IMPORT",
                        primaryAction: { Task { await confirmImport() } },
                        secondaryTitle: isGermanLocale ? "FORMULAR ÄNDERN" : "EDIT FORM",
                        secondaryAction: {
                            resetForm()
                            usernameFocused = true
                        }
                    )
                } else {
                    errorCard
                    actionButtons(
                        primaryTitle: usesStructuredPath ? "RESUME SOURCE READING" : (isGermanLocale ? "VORSCHAU ERNEUT VERSUCHEN" : "TRY PREVIEW AGAIN"),
                        primaryAction: { Task { await startPreview() } },
                        secondaryTitle: isGermanLocale ? "FORMULAR ÄNDERN" : "EDIT FORM",
                        secondaryAction: {
                            resetForm()
                            usernameFocused = true
                        }
                    )
                }
            }
        }
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ImportCardShell {
                VStack(alignment: .leading, spacing: 6) {
                    fieldSectionTitle(isGermanLocale ? "Benutzername" : "Username")
                    TextField(isGermanLocale ? "z.B. maxmustermann" : "e.g. yourname", text: $username)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .focused($usernameFocused)
                        .importGlanceField()
                }

                VStack(alignment: .leading, spacing: 2) {
                    fieldSectionTitle(isGermanLocale ? "Typ" : "Type")
                    ImportCheckGrid(options: [
                        togglePill(title: "Anime", isOn: $includeAnime),
                        togglePill(title: "Manga", isOn: $includeManga)
                    ], hint: isGermanLocale ? "Schaltet den Filter um" : "Toggles this filter")
                }

                VStack(alignment: .leading, spacing: 2) {
                    fieldSectionTitle(isGermanLocale ? "Status" : "Status")
                    ImportCheckGrid(options: [
                        togglePill(title: isGermanLocale ? "Aktuell" : "Current", isOn: $includeCurrent),
                        togglePill(title: isGermanLocale ? "Fertig" : "Completed", isOn: $includeCompleted),
                        togglePill(title: isGermanLocale ? "Plan" : "Planning", isOn: $includePlanning),
                        togglePill(title: isGermanLocale ? "Pausiert" : "On hold", isOn: $includePaused),
                        togglePill(title: isGermanLocale ? "Abgebrochen" : "Dropped", isOn: $includeDropped),
                        togglePill(title: isGermanLocale ? "Wiederholung" : "Repeating", isOn: $includeRepeating)
                    ], hint: isGermanLocale ? "Schaltet den Filter um" : "Toggles this filter")
                }

                // The shipped upper-case literal is kept (D16; sentence case is an owner choice).
                KuroInkButton(usesStructuredPath ? "READ COMPLETE LIST FOR REVIEW" : (isGermanLocale ? "VORSCHAU" : "PREVIEW"),
                              role: .primary, isLoading: coordinator.isPreviewing) {
                    Task { await startPreview() }
                }
                .disabled(!canPreview || coordinator.isPreviewing || coordinator.isImporting)
                .padding(.top, 4)

                ImportNote(text: isGermanLocale
                    ? "Kuro liest öffentliche AniList-Listen. Private Einträge bleiben privat und werden nicht übernommen."
                    : "Kuro reads public AniList lists. Private entries stay private and are not imported."
                )
            }
            if usesStructuredPath {
                ImportNote(text: isGermanLocale
                    ? "Alle ausgewählten Seiten werden gelesen, bevor du bestätigst. Status, Fortschritt, Bewertung und Notizen bleiben standardmäßig unverändert. Fehlende Felder siehst du in der Prüfung; eine öffentliche Liste kann keine privaten AniList-Einträge zeigen."
                    : "All selected pages are read before you confirm. Existing status, progress, rating and notes stay unchanged by default. Unavailable fields are shown in review; a public list cannot expose private AniList entries.")
            }
        }
    }

    private var selectionSummaryCard: some View {
        ImportGlanceCard {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    ImportEyebrow(text: isGermanLocale ? "Vorschau für" : "Preview for")
                    Text("@\(username.trimmingCharacters(in: .whitespacesAndNewlines))")
                        .font(.kuroCustom(14, weight: .semibold, relativeTo: .subheadline, maxSize: 28))
                        .tracking(-0.3)
                        .foregroundStyle(HomeInk.glanceInk)
                }
                Spacer(minLength: 0)
                Button {
                    resetForm()
                    usernameFocused = true
                } label: {
                    Text(isGermanLocale ? "ÄNDERN" : "EDIT")
                        .font(.kuroCustom(11, weight: .medium, relativeTo: .caption1, maxSize: 22))
                        .foregroundStyle(Color.kuroInk)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HomeContactStyle())
            }

            HStack(spacing: 8) {
                if includeAnime {
                    summaryPill("Anime")
                }
                if includeManga {
                    summaryPill("Manga")
                }
                summaryPill(isGermanLocale ? "Filter aktiv" : "Filters on")
            }

            HStack(spacing: 8) {
                if includeCurrent { summaryPill(isGermanLocale ? "Aktuell" : "Current") }
                if includeCompleted { summaryPill(isGermanLocale ? "Fertig" : "Completed") }
                if includePlanning { summaryPill(isGermanLocale ? "Plan" : "Planning") }
                if includePaused { summaryPill(isGermanLocale ? "Pausiert" : "Paused") }
                if includeDropped { summaryPill(isGermanLocale ? "Abgebrochen" : "Dropped") }
                if includeRepeating { summaryPill(isGermanLocale ? "Wiederholung" : "Repeating") }
            }
        }
    }

    private func previewCard(
        preview: ConciergeAniListPreviewResponse,
        errorMessage: String?,
        isImporting: Bool
    ) -> some View {
        ImportGlanceCard {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    ImportEyebrow(text: isGermanLocale ? "VORSCHAU" : "PREVIEW")

                    Text(countSummary(preview))
                        .font(.kuroCustom(24, weight: .semibold, relativeTo: .title2, maxSize: 40))
                        .tracking(-0.85)
                        .foregroundStyle(Color.kuroInk)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if let truncated = preview.truncated {
                    summaryPill(truncated ? (isGermanLocale ? "Gekürzt" : "Truncated") : (isGermanLocale ? "Vollständig" : "Full"))
                }
            }

            if let text = preview.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                Text(text)
                    .font(.kuroCustom(13, relativeTo: .footnote, maxSize: 26))
                    .foregroundStyle(ImportInk.description)
                    .lineSpacing(2)
            }

            HStack(spacing: 8) {
                if let itemCount = preview.itemCount {
                    summaryPill("\(itemCount)")
                }
                if let publicListOnly = preview.publicListOnly {
                    summaryPill(publicListOnly
                                ? (isGermanLocale ? "Nur öffentlich" : "Public only")
                                : (isGermanLocale ? "Mehr als öffentlich" : "Includes private"))
                }
                if let retryAfter = preview.retry_after_s {
                    summaryPill(isGermanLocale ? "Retry in \(retryAfter)s" : "Retry in \(retryAfter)s")
                }
            }

            if let errorMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.kuroCustom(13, relativeTo: .footnote, maxSize: 22))
                        .foregroundStyle(Color.kuroInk)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isGermanLocale ? "Etwas ist schiefgelaufen" : "Something went wrong")
                            .font(.kuroCustom(13, weight: .semibold, relativeTo: .footnote, maxSize: 26))
                            .foregroundStyle(Color.kuroInk)
                        Text(errorMessage)
                            .font(.kuroCustom(12, relativeTo: .caption1, maxSize: 24))
                            .foregroundStyle(ImportInk.description)
                            .lineSpacing(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .overlay(alignment: .top) { Rectangle().fill(ImportInk.rule).frame(height: 1) }
                .accessibilityElement(children: .combine)
            }

            if let counts = preview.countsByType, !counts.isEmpty {
                countSection(
                    title: isGermanLocale ? "Typen" : "Types",
                    counts: counts
                )
            }

            if let counts = preview.countsByStatus, !counts.isEmpty {
                countSection(
                    title: isGermanLocale ? "Status" : "Status",
                    counts: counts
                )
            }

            if let samples = preview.sampleItems, !samples.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ImportEyebrow(text: isGermanLocale ? "Beispiele" : "Samples")

                    VStack(spacing: 0) {
                        ForEach(samples.prefix(4)) { sample in
                            sampleRow(sample)
                        }
                    }
                }
            }

            if isImporting {
                HStack(spacing: 8) {
                    KuroBusyMark(width: 24)
                    Text(isGermanLocale ? "Import läuft..." : "Importing...")
                        .font(.kuroCustom(12, relativeTo: .caption1, maxSize: 24))
                        .foregroundStyle(Color.kuroMuted)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var previewLoadingCard: some View {
        ImportGlanceCard {
            HStack(spacing: 10) {
                KuroBusyMark(width: 24)
                Text(isGermanLocale ? "Vorschau wird geladen..." : "Loading preview...")
                    .font(.kuroCustom(12, relativeTo: .caption1, maxSize: 24))
                    .foregroundStyle(Color.kuroMuted)
            }
            .accessibilityElement(children: .combine)

            KuroSkeleton(kind: .row)
            KuroSkeleton(kind: .row)
        }
    }

    private var errorCard: some View {
        ImportGlanceCard {
            Text(isGermanLocale ? "Vorschau fehlgeschlagen" : "Preview failed")
                .font(.kuroCustom(17, weight: .semibold, relativeTo: .headline, maxSize: 32))
                .tracking(-0.4)
                .foregroundStyle(Color.kuroInk)
                .accessibilityAddTraits(.isHeader)

            Text(coordinator.errorMessage ?? (isGermanLocale ? "Bitte versuche es erneut." : "Please try again."))
                .font(.kuroCustom(13, relativeTo: .footnote, maxSize: 26))
                .foregroundStyle(ImportInk.description)
                .lineSpacing(2)

            if let retryAfter = coordinator.retryAfterSeconds {
                ImportNote(text: isGermanLocale
                    ? "Erneut versuchen in etwa \(retryAfter) Sekunden."
                    : "Try again in about \(retryAfter) seconds."
                )
            }
        }
    }

    private func actionButtons(
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 4) {
            KuroInkButton(primaryTitle, role: .primary,
                          isLoading: coordinator.isImporting || coordinator.isPreviewing, action: primaryAction)
                .disabled(coordinator.isPreviewing || coordinator.isImporting)

            Button(action: secondaryAction) {
                Text(secondaryTitle)
                    .font(.kuroCustom(11, weight: .medium, relativeTo: .caption1, maxSize: 22))
                    .tracking(0.8)
                    .foregroundStyle(Color.kuroInk)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HomeContactStyle())
        }
    }

    /// One check row's option (the type and status toggles; several can be on).
    private func togglePill(title: String, isOn: Binding<Bool>) -> ImportCheckOption {
        ImportCheckOption(title: title, isOn: isOn)
    }

    private func stepPill(title: String, isActive: Bool) -> some View {
        ImportRefineWord(title: title, isSelected: isActive)
    }

    private func fieldSectionTitle(_ title: String) -> some View {
        ImportEyebrow(text: title)
    }

    private func summaryPill(_ text: String) -> some View {
        ImportTag(text: text)
    }

    private func countSection(title: String, counts: [String: Int]) -> some View {
        let rows = counts
            .map { (key: $0.key, value: $0.value) }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }

        return VStack(alignment: .leading, spacing: 8) {
            ImportEyebrow(text: title)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(rows, id: \.key) { row in
                    summaryPill("\(row.key): \(row.value)")
                }
            }
        }
    }

    /// A Home quiet row (no cover: the preview carries none): title 15 pt, the meta 10 pt muted.
    private func sampleRow(_ sample: ConciergeAniListPreviewItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(sample.titleDisplay)
                    .font(.kuroCustom(15, weight: .medium, relativeTo: .headline, maxSize: 30)).tracking(-0.2)
                    .foregroundStyle(Color.kuroInk)
                    .lineLimit(2)

                Text(sampleMeta(sample))
                    .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 22))
                    .foregroundStyle(Color.kuroMuted)
            }
            Spacer(minLength: 0)
            ImportEyebrow(text: sample.type.uppercased())
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.kuroHairline).frame(height: 0.5) }
        .accessibilityElement(children: .combine)
    }

    private func sampleMeta(_ sample: ConciergeAniListPreviewItem) -> String {
        var parts: [String] = []
        parts.append(sample.status.uppercased())
        if let progress = sample.progress {
            parts.append("\(progress)")
        }
        if let year = sample.year {
            parts.append("\(year)")
        }
        return parts.joined(separator: " • ")
    }

    private func countSummary(_ preview: ConciergeAniListPreviewResponse) -> String {
        let count = preview.itemCount ?? 0
        let truncated = preview.truncated == true
        if isGermanLocale {
            return truncated ? "\(count) Titel, gekürzt" : "\(count) Titel"
        }
        return truncated ? "\(count) items, truncated" : "\(count) items"
    }

    /// Stop (confirmed): the running read or import is dropped and the form is shown again; the sheet
    /// stays open.
    private func stopImport() {
        resetForm()
        KuroAccessibility.impactHaptic(.light)
        AccessibilityNotification.Announcement(ImportChooserTopControl.stoppedLine(german: isGermanLocale)).post()
    }

    private func resetForm() {
        coordinator.stop()
        coordinator.activate(using: imports)
        selectedImportMode = nil
    }

    private func startPreview() async {
        guard canPreview else { return }
        let structured = usesStructuredPath
        selectedImportMode = structured
        if structured {
            guard usesStructuredImport else { coordinator.pauseForDisabledFoundation(); return }
            if let job = await coordinator.prepare(using: imports, username: username,
                types: selectedTypes, statuses: selectedStatuses) {
                dismiss(); onPrepared?(job)
            }
            return
        }
        await coordinator.loadPreview(
            using: imports,
            isGermanLocale: isGermanLocale,
            username: username,
            types: selectedTypes,
            statuses: selectedStatuses
        )
    }

    private func confirmImport() async {
        guard !usesStructuredPath else { return }
        guard let response = await coordinator.confirmImport(using: imports, isGermanLocale: isGermanLocale) else {
            return
        }
        dismiss()
        await onImportCompleted(response)
    }
}
