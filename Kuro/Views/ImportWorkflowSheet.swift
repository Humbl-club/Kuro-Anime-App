import KuroCore
import KuroLibrary
import SwiftUI

/// Navigation intent; the app shell owns the destination and Collection's Library filter.
enum ImportResultDestination {
    case importedTitles(Set<MediaKey>)
    case fullCollection
}

/// Reusable from Profile, Concierge and Home recovery. Closing keeps the durable job.
struct ImportWorkflowSheet: View {
    let imports: ImportsService
    let onNavigate: (ImportResultDestination) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var model: ImportWorkflowPresentation
    @State private var visibleCount = 50
    @State private var reviewUpdates = false
    @State private var matchingItem: ImportReviewItem?
    @State private var confirmStop = false
    @State private var confirmUndo = false
    @State private var reviewGroup: ReviewGroup?

    private enum ReviewGroup: String, CaseIterable {
        case new, existing, changes, needsReview
        func title(german: Bool) -> String {
            switch (self, german) {
            case (.new, false): return "New titles"
            case (.new, true): return "Neue Titel"
            case (.existing, false): return "Already in Kuro"
            case (.existing, true): return "Schon in Kuro"
            case (.changes, false): return "Changes available"
            case (.changes, true): return "Änderungen verfügbar"
            case (.needsReview, false): return "Needs review"
            case (.needsReview, true): return "Zu prüfen"
            }
        }
        func includes(_ item: ImportReviewItem) -> Bool {
            switch self {
            case .new: return item.disposition == .new
            case .existing: return item.disposition == .existing
            case .changes: return item.disposition == .changes
            case .needsReview: return [.unmatched, .conflict, .invalid, .sourceChanged].contains(item.disposition)
            }
        }
    }

    init(imports: ImportsService, job: ImportOutcome? = nil,
         onNavigate: @escaping (ImportResultDestination) -> Void) {
        self.imports = imports; self.onNavigate = onNavigate
        _model = State(initialValue: ImportWorkflowPresentation(imports: imports, job: job))
    }

    private var german: Bool { KuroLocale.isGerman }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                    if model.isCurrentAccount {
                        if let job = model.visibleJob {
                            summary(job)
                            if let failure = model.failure { failureCard(failure) }
                            controls(job)
                            titlePages(job)
                        } else {
                            Text(german ? "Importe." : "Imports.")
                                .font(.kuroHeadline(weight: .light))
                                .foregroundStyle(Color.kuroInk)
                                .accessibilityAddTraits(.isHeader)
                            if let failure = model.failure { failureCard(failure) }
                            history
                        }
                    }
                }
                .padding(.horizontal, KuroDesignSpacing.padding)
                .padding(.vertical, KuroDesignSpacing.lg)
                .kuroReadableWidth()
            }
            .background(Color.kuroCanvasPage.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // Closing keeps the saved job; it can be resumed from Profile.
                    Button(ImportCopy.close(german: german)) { model.close(); dismiss() }
                        .foregroundStyle(Color.kuroInk)
                }
            }
            .overlay {
                if model.busy && model.job == nil {
                    KuroStateView(.loading, title: german ? "Importverlauf wird gelesen." : "Reading import history.")
                }
            }
        }
        .tint(Color.kuroInk)
        .presentationDetents([.large])
        .task { model.activate(); await model.load() }
        .onDisappear { model.close() }
        .onChange(of: imports.accountSession.current) { _, _ in model.close(); dismiss() }
        .onChange(of: reviewUpdates) { _, enabled in if !enabled { model.approval = ImportReviewApproval() } }
        .sheet(item: $matchingItem) { item in
            ImportCatalogMatchPicker(imports: imports, item: item) { mediaId in
                matchingItem = nil
                Task { await model.match(item, mediaId: mediaId) }
            }
        }
        .confirmationDialog(german ? "Restliche Arbeit anhalten?" : "Stop remaining import work?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button(german ? "Restliche Arbeit anhalten" : "Stop remaining work", role: .destructive) { Task { await model.stop() } }
        } message: {
            Text(german ? "Bereits gespeicherte Titel bleiben in deiner Bibliothek. Gespeicherte Änderungen kannst du separat rückgängig machen."
                        : "Titles already saved stay in your Library. You can undo eligible saved changes separately.")
        }
        .confirmationDialog(german ? "Gespeicherte Änderungen rückgängig machen?" : "Undo saved changes?", isPresented: $confirmUndo, titleVisibility: .visible) {
            Button(german ? "Änderungen rückgängig machen" : "Undo saved changes", role: .destructive) { Task { await model.undo() } }
        } message: {
            Text(german ? "Spätere Änderungen und ersetzte Titel bleiben erhalten. Offene Änderungen müssen zuerst synchronisiert sein."
                        : "Later edits and replaced titles are kept. Pending local changes must be synchronized first.")
        }
    }

    private func summary(_ job: ImportOutcome) -> some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            Text(heading(job))
                .font(.kuroHeadline(weight: .light))
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(ImportCopy.source(job.selection, german: german))
                .font(.kuroMeta()).foregroundStyle(Color.kuroInkSecondary)
            Text(german ? "Anime und Manga bleiben getrennt. Deine Kuro-Werte bleiben, solange du keine Änderung bestätigst."
                        : "Anime and Manga stay separate. Your Kuro values stay unless you confirm a change.")
                .font(.kuroBody()).foregroundStyle(Color.kuroInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !job.selection.media.allSatisfy({ job.exhaustedMedia[$0] == true }) {
                Text(german ? "Noch nicht alles gelesen. Setz denselben Import fort, bevor du bestätigst."
                            : "Reading isn't finished. Resume the same import before confirming.")
                    .font(.kuroBody()).foregroundStyle(Color.kuroInk)
                    .accessibilityIdentifier("import.read.incomplete")
            }
            Text(ImportCopy.counts(job.counts, german: german))
                .font(.kuroBody()).foregroundStyle(Color.kuroInk)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("import.saved.counts")
            if job.phase == .undone || job.phase == .undoing {
                let sameActiveJob = imports.activeImport?.jobId == job.jobId
                let reverted = sameActiveJob ? imports.importUndoReverted : (model.manifest?.undoReverted ?? 0)
                let skipped = sameActiveJob ? imports.importUndoSkipped : (model.manifest?.undoSkipped ?? 0)
                Text(german ? "Rückgängig: \(reverted) zurückgesetzt · \(skipped) mit späteren Änderungen behalten. Die Zahlen oben beschreiben den ursprünglichen Import."
                            : "Undo: \(reverted) reverted · \(skipped) kept with their later changes. The counts above describe the original import.")
                    .font(.kuroBody()).foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if job.counts.applied > 0, !job.projectionReady, job.phase != .undone {
                Text(german ? "Gespeichert. Deine Bibliothek wird aktualisiert; die Titel sind sicher."
                            : "Saved. Your Library is refreshing; the saved titles are safe.")
                    .font(.kuroBody()).foregroundStyle(Color.kuroInk)
                    .accessibilityIdentifier("import.projection.pending")
            }
            if model.busy || imports.importBusy {
                KuroStateView(.loading, title: german ? "Import läuft." : "Working on this import.", layout: .inline)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func heading(_ job: ImportOutcome) -> String {
        let g = german
        if job.phase == .undone { return g ? "Import rückgängig gemacht." : "Import undone." }
        if job.phase == .reviewing { return g ? "Vor dem Speichern prüfen." : "Review before saving." }
        if job.allRejected { return g ? "Nichts übernommen." : "Nothing was applied." }
        if job.isTerminal, job.counts.applied == 0, job.counts.unchanged > 0 { return g ? "Schon in deiner Bibliothek." : "Already in your Library." }
        switch job.phase {
        case .preparing: return g ? "Deine Quelle wird gelesen." : "Reading your source."
        case .applying: return g ? "Die bestätigten Titel werden gespeichert." : "Saving the titles you confirmed."
        case .finalizing: return g ? "Gespeichert. Bibliothek wird aktualisiert." : "Saved. Refreshing your Library."
        case .cancelled: return g ? "Import angehalten." : "Import stopped."
        case .failed: return g ? "Der Import braucht dich." : "The import needs attention."
        case .undoing: return g ? "Änderungen werden rückgängig gemacht." : "Undoing saved changes."
        case .ready: return job.counts.needsReview > 0
            ? (g ? "Gespeichert, einiges ist zu prüfen." : "Saved, with items to review.")
            : (g ? "Import abgeschlossen." : "Import complete.")
        case .reviewing, .undone: return "Import"
        }
    }

    @ViewBuilder private func controls(_ job: ImportOutcome) -> some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
            let g = german
            if job.phase == .reviewing, model.manifest == nil {
                note(g ? "Diese Prüfung begann auf einem anderen Gerät. Hier kannst du sie ansehen oder anhalten; bestätigen kannst du sie auf dem Gerät mit der ursprünglichen Quelle."
                       : "This review started on another device. Inspect or stop it here; confirm changes on the device that has the original source.")
            }
            if job.phase == .reviewing, let manifest = model.manifest, manifest.decisions != nil {
                note(g ? "Deine bestätigte Auswahl ist schon gesichert. Setz fort, ohne erneut zu bestätigen."
                       : "The choices you confirmed are already saved. Resume without confirming again.")
            }
            if job.phase == .reviewing, model.manifest?.phase == .reviewing, model.manifest?.decisions == nil {
                note(g ? "Aus dieser Prüfung wird nichts gespeichert, bis du bestätigst." : "Nothing from this review is saved until you confirm.")
                Toggle(g ? "Änderungen an vorhandenen Titeln prüfen" : "Review updates to existing titles", isOn: $reviewUpdates)
                    .font(.kuroBody())
                    .foregroundStyle(Color.kuroInk)
                    .disabled(model.busy || imports.importBusy)
                KuroInkButton(g ? "Geprüfte Auswahl speichern" : "Save reviewed choices", isLoading: model.busy) {
                    Task { await model.apply() }
                }
                .disabled(!model.mayApply)
                .accessibilityIdentifier("import.approve")
            }
            if let manifest = model.manifest, (!job.isTerminal || !job.projectionReady),
               job.phase != .reviewing || manifest.phase != .reviewing || manifest.decisions != nil {
                KuroInkButton(g ? "Diesen Import fortsetzen" : "Resume this import", role: .secondary) {
                    Task { await model.resume(actionId: manifest.actionId) }
                }
                .disabled(model.busy || imports.importBusy)
                .accessibilityIdentifier("import.resume")
            } else if !job.isTerminal, job.phase != .reviewing {
                note(g ? "Hier kannst du den Import ansehen oder anhalten. Weiterlesen geht auf dem Gerät, das ihn begonnen hat."
                       : "You can inspect or stop this import here. Reading continues on the device that started it.", quiet: true)
            }
            if job.counts.applied > 0 || job.isTerminal {
                KuroInkButton(g ? "Importierte Titel ansehen" : "View imported titles", role: .secondary) {
                    navigate(.importedTitles(model.affectedKeys))
                }
                .disabled(model.affectedKeys.isEmpty || !job.projectionReady || model.busy)
                .accessibilityIdentifier("import.view.titles")
                KuroInkButton(g ? "Ganze Sammlung ansehen" : "View full Collection", role: .secondary) {
                    navigate(.fullCollection)
                }
                .disabled(!job.projectionReady || model.busy)
                .accessibilityIdentifier("import.view.collection")
            }
            if job.isTerminal, job.counts.needsReview > 0, job.historyAvailable {
                KuroInkButton(g ? "Offene Titel in neuem Import prüfen" : "Review unresolved titles in a new import", role: .secondary) {
                    reviewUpdates = false; visibleCount = 50
                    Task { await model.reviewUnresolved() }
                }
                .disabled(model.busy || imports.importBusy)
            }
            textAction(g ? "Status und Bibliothek aktualisieren" : "Refresh status and Library") {
                Task { await model.refreshPresentation() }
            }
            .disabled(model.busy || imports.importBusy)
            if job.undoAvailable {
                textAction(g ? "Gespeicherte Änderungen rückgängig machen" : "Undo saved changes") { confirmUndo = true }
                    .disabled(model.busy || imports.importBusy)
                    .accessibilityIdentifier("import.undo")
            } else if !job.historyAvailable {
                note(g ? "Für diesen älteren Import gibt es keinen Verlauf und kein Rückgängig mehr."
                       : "History and Undo are no longer available for this older import.", quiet: true)
            }
            if !job.isTerminal {
                textAction(g ? "Restliche Arbeit anhalten" : "Stop remaining work", destructive: true) { confirmStop = true }
            }
        }
    }

    private func navigate(_ destination: ImportResultDestination) {
        guard model.isCurrentAccount else { return }
        model.close(); dismiss(); onNavigate(destination)
    }

    private func note(_ text: String, quiet: Bool = false) -> some View {
        Text(text)
            .font(quiet ? .kuroMeta() : .kuroBody())
            .foregroundStyle(quiet ? Color.kuroInkSecondary : Color.kuroInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func textAction(_ title: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.kuroMeta(weight: .medium))
                .foregroundStyle(destructive ? Color.kuroDestructiveInk : Color.kuroInk)
                .underline(!destructive, color: Color.kuroInk)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle(pressedScale: 0.99))
    }

    private func failureCard(_ failure: ImportFailure) -> some View {
        let g = german
        return HStack(alignment: .top, spacing: KuroDesignSpacing.sm) {
            Image(systemName: "exclamationmark.circle")
                .font(.kuroCustom(15, relativeTo: .body, maxSize: 24))
                .foregroundStyle(Color.kuroError)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                Text(ImportCopy.failure(failure, german: g))
                    .font(.kuroBody()).foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
                if failure == .reconnect {
                    Text(g ? "Verbinde MAL in deinem Profil neu und setz dann denselben Import fort."
                           : "Reconnect MAL in Profile, then resume this same import.")
                        .font(.kuroMeta()).foregroundStyle(Color.kuroInkSecondary)
                } else if case .invalidInput = failure {
                    Text(g ? "Wähle in deinem Profil eine andere Quelle oder Datei. Bereits Gespeichertes bleibt."
                           : "Choose another source or file in Profile. Anything already saved stays.")
                        .font(.kuroMeta()).foregroundStyle(Color.kuroInkSecondary)
                }
            }
        }
        .padding(KuroDesignSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.kuroCanvasQuiet, in: RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("import.failure")
    }

    @ViewBuilder private func titlePages(_ job: ImportOutcome) -> some View {
        if !model.items.isEmpty {
            let g = german
            Text(job.phase == .reviewing ? (g ? "Titel zum Prüfen" : "Titles to review") : (g ? "Ergebnis je Titel" : "Results by title"))
                .font(.kuroTitle())
                .foregroundStyle(Color.kuroInk)
                .accessibilityAddTraits(.isHeader)
            if job.phase == .reviewing {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: KuroDesignSpacing.md) {
                        groupWord(g ? "Alle (\(model.items.count))" : "All (\(model.items.count))", selected: reviewGroup == nil) {
                            reviewGroup = nil; visibleCount = 50
                        }
                        ForEach(ReviewGroup.allCases, id: \.self) { group in
                            groupWord("\(group.title(german: g)) (\(model.items.filter(group.includes).count))", selected: reviewGroup == group) {
                                reviewGroup = group; visibleCount = 50
                            }
                        }
                    }
                }
            }
            let displayed = model.items.filter { job.phase != .reviewing || reviewGroup?.includes($0) != false }
            LazyVStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                ForEach(Array(displayed.prefix(visibleCount))) { item in reviewRow(item, job: job) }
            }
            if displayed.count > visibleCount {
                let next = min(50, displayed.count - visibleCount)
                textAction(german ? "Nächste \(next) Titel zeigen" : "Show the next \(next) titles") { visibleCount += 50 }
                    .accessibilityIdentifier("import.titles.next")
            }
        }
    }

    private func groupWord(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.kuroMeta(weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.kuroInk : Color.kuroInkQuiet)
                .underline(selected, color: Color.kuroInk)
                .lineLimit(1)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func reviewRow(_ item: ImportReviewItem, job: ImportOutcome) -> some View {
        let g = german
        return VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            Text(item.title).font(.kuroTitle()).foregroundStyle(Color.kuroInk).fixedSize(horizontal: false, vertical: true)
            Text("\(ImportCopy.medium(item.medium, german: g)) · \(ImportCopy.disposition(item.disposition, german: g))")
                .font(.kuroMeta()).foregroundStyle(Color.kuroInkSecondary)
            if let detail = item.detail { Text(detail).font(.kuroMeta()).foregroundStyle(Color.kuroInk) }
            if let undo = item.undoDisposition { Text((g ? "Rückgängig: " : "Undo: ") + undo).font(.kuroMeta()).foregroundStyle(Color.kuroInk) }
            if job.phase == .reviewing {
                if item.current == nil {
                    Text(ImportFieldCopy.overview(item.incoming)).font(.kuroMeta()).foregroundStyle(Color.kuroInk)
                    DisclosureGroup(g ? "Übernommene Felder" : "Incoming fields") {
                        ForEach(ImportFieldCopy.presentFields(in: item.incoming), id: \.self) { field in
                            Text("\(ImportFieldCopy.label(field).capitalized): \(ImportFieldCopy.value(field, in: item.incoming))")
                                .font(.kuroMeta()).foregroundStyle(Color.kuroInk).fixedSize(horizontal: false, vertical: true)
                        }
                    }.font(.kuroMeta()).tint(Color.kuroInk)
                } else if item.changedFields.isEmpty {
                    Text(g ? "Schon in Kuro. Deine Werte bleiben." : "Already in Kuro. Your values stay.")
                        .font(.kuroMeta()).foregroundStyle(Color.kuroInkSecondary)
                } else {
                    Text(g ? "Deine Kuro-Werte bleiben, wenn du nichts änderst." : "Your Kuro values stay unless you change them.")
                        .font(.kuroMeta()).foregroundStyle(Color.kuroInkSecondary)
                    if reviewUpdates {
                        ForEach(item.changedFields, id: \.self) { field in
                            VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                                Text("Kuro: \(ImportFieldCopy.value(field, in: item.current))")
                                Text((g ? "Neu: " : "Incoming: ") + ImportFieldCopy.value(field, in: item.incoming))
                                Toggle((g ? "Übernehmen: " : "Update ") + ImportFieldCopy.label(field), isOn: Binding(
                                    get: { model.approval.contains(field, for: item) },
                                    set: { model.approval.set(field, approved: $0, for: item) }
                                ))
                                .disabled(model.busy || imports.importBusy)
                            }
                            .font(.kuroMeta())
                            .foregroundStyle(Color.kuroInk)
                        }
                    }
                }
                if !item.incoming.unavailableFields.isEmpty {
                    Text(g ? "Diese Quelle liefert nicht: \(item.incoming.unavailableFields.joined(separator: ", ")). Fehlende Werte löschen nie etwas in Kuro."
                           : "This source doesn't provide: \(item.incoming.unavailableFields.joined(separator: ", ")). Missing values never clear anything in Kuro.")
                        .font(.kuroMeta()).foregroundStyle(Color.kuroInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if item.disposition == .unmatched, item.mediaId == nil {
                    textAction(g ? "Einem Katalogtitel zuordnen" : "Match to a catalogue title") { matchingItem = item }
                        .disabled(model.busy || imports.importBusy)
                }
            }
        }
        .padding(.vertical, KuroDesignSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.kuroHairline).frame(height: 0.5) }
        .accessibilityElement(children: .contain)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
            ForEach(model.manifests.filter { manifest in
                manifest.jobId == nil || !model.jobs.contains(where: { $0.jobId == manifest.jobId })
            }) { manifest in
                let g = german
                VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                    Text(ImportCopy.source(manifest.selection, german: g)).font(.kuroTitle()).foregroundStyle(Color.kuroInk)
                    Text((g ? "Auf diesem Gerät gesichert · " : "Saved on this device · ") + ImportCopy.phase(manifest.phase, german: g))
                        .font(.kuroMeta()).foregroundStyle(Color.kuroInkSecondary)
                    textAction(manifest.phase == .preparing ? (g ? "Weiterlesen" : "Resume reading") : (g ? "Gesicherten Import öffnen" : "Open saved import")) {
                        Task { await model.resume(actionId: manifest.actionId) }
                    }
                    .disabled(model.busy || imports.importBusy)
                    if manifest.jobId == nil {
                        Text(g ? "Anhalten verwirft die gesicherte Quelle. Deine Bibliothek bleibt." : "Stopping discards the saved source. Your Library stays.")
                            .font(.kuroMeta()).foregroundStyle(Color.kuroInkSecondary)
                        textAction(g ? "Vorbereitung anhalten" : "Stop preparation", destructive: true) {
                            Task { await model.stopPreparation(actionId: manifest.actionId) }
                        }
                        .disabled(model.busy || imports.importBusy)
                    }
                }
                .padding(.vertical, KuroDesignSpacing.sm)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.kuroHairline).frame(height: 0.5) }
            }
            ForEach(model.jobs) { job in
                Button { Task { visibleCount = 50; await model.inspect(job) } } label: {
                    VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                        Text(ImportCopy.source(job.selection, german: german)).font(.kuroTitle()).foregroundStyle(Color.kuroInk)
                        Text(ImportCopy.phase(job.phase, german: german) + " · "
                             + ImportCopy.savedSummary(applied: job.counts.applied, needsReview: job.counts.needsReview, german: german))
                            .font(.kuroMeta()).foregroundStyle(Color.kuroInkSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.vertical, KuroDesignSpacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(KuroPressStyle(pressedScale: 0.99))
                .disabled(model.busy)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.kuroHairline).frame(height: 0.5) }
            }
            if model.jobs.isEmpty, model.manifests.isEmpty, !model.busy {
                KuroStateView(.empty, title: german ? "Keine letzten Importe." : "No recent imports.",
                              message: german ? "Wähle AniList oder MAL in deinem Profil." : "Choose AniList or MAL in Profile.",
                              layout: .inline)
            }
        }
    }
}

/// Field names and values of an import row, EN/DE (pure apart from the reader's language).
enum ImportFieldCopy {
    private static var german: Bool { KuroLocale.isGerman }

    static func label(_ field: ImportField) -> String {
        let g = german
        switch field {
        case .status: return g ? "Status" : "status"
        case .progress: return g ? "Fortschritt" : "progress"
        case .score: return g ? "Wertung" : "rating"
        case .notes: return g ? "Notizen" : "notes"
        case .privacy: return g ? "Sichtbarkeit" : "privacy"
        case .volumes: return g ? "Bände" : "volume progress"
        case .repeats: return g ? "Wiederholungen" : "repeat count"
        case .dates: return g ? "Start- und Enddatum" : "start and finish dates"
        case .memberships: return g ? "Listen" : "list memberships"
        case .sourceOptions: return g ? "Listenoptionen der Quelle" : "source list options"
        }
    }
    static func presentFields(in values: ImportValues) -> [ImportField] {
        ImportField.allCases.filter { field in
            switch field {
            case .status: return values.status != nil
            case .progress: return values.progress != nil
            case .score: return values.scoreRaw != nil || values.normalizedRating != nil
            case .notes: return values.notes != nil
            case .privacy: return values.isPrivate != nil
            case .volumes: return values.volumesProgress != nil
            case .repeats: return values.repeatCount != nil
            case .dates: return values.startedRaw != nil || values.finishedRaw != nil
            case .memberships: return values.customLists != nil
            case .sourceOptions: return values.sourceListOptions != nil || values.hiddenFromStatusLists != nil
            }
        }
    }
    static func overview(_ values: ImportValues) -> String {
        [value(.status, in: values), value(.progress, in: values), value(.score, in: values)].joined(separator: " · ")
    }
    static func value(_ field: ImportField, in values: ImportValues?) -> String {
        let g = german
        let none = g ? "Nicht angegeben" : "Not provided"
        guard let values else { return none }
        switch field {
        case .status: return values.status ?? none
        case .progress: return values.progress.map { "\($0)\(values.progressLabel.map { " (\($0))" } ?? "")" } ?? none
        case .score:
            let kuro = values.normalizedRating.map(String.init) ?? (g ? "ohne Wertung" : "unrated")
            if let raw = values.scoreRaw {
                return "\(raw) / \(values.scoreScale ?? (g ? "Skala der Quelle" : "source scale")) · Kuro \(kuro)"
            }
            return values.normalizedRating.map { g ? "Kuro \($0); keine Wertung der Quelle" : "Kuro \($0); no source score" } ?? none
        case .notes: return values.notes.flatMap { $0.isEmpty ? nil : $0 } ?? (g ? "Keine Notiz; Kuro bleibt" : "No note; Kuro's stays")
        case .privacy: return values.isPrivate.map { $0 ? (g ? "Privat" : "Private") : (g ? "Öffentlich" : "Public") } ?? none
        case .volumes: return values.volumesProgress.map(String.init) ?? none
        case .repeats: return values.repeatCount.map(String.init) ?? none
        case .dates: return "\(values.startedRaw ?? (g ? "Kein Start" : "No start")) → \(values.finishedRaw ?? (g ? "Kein Ende" : "No finish"))"
        case .memberships: return values.customLists?.joined(separator: ", ") ?? none
        case .sourceOptions:
            let hidden = values.hiddenFromStatusLists.map {
                $0 ? (g ? "In Statuslisten versteckt" : "Hidden from status lists") : (g ? "In Statuslisten sichtbar" : "Visible in status lists")
            }
            let parts = [values.sourceListOptions, hidden].compactMap { $0 }
            return parts.isEmpty ? none : parts.joined(separator: " · ")
        }
    }
}
