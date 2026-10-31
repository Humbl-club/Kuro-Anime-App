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
        case new = "New titles", existing = "Already in Kuro", changes = "Changes available", needsReview = "Needs review"
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
                            Text("Imports").font(.kuroDisplay())
                            if let failure = model.failure { failureCard(failure) }
                            history
                        }
                    }
                }
                .padding(KuroDesignSpacing.lg)
            }
            .background(Color.kuroBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Stay here") { model.close(); dismiss() }
                }
            }
            .overlay { if model.busy && model.job == nil { ProgressView("Reading import history") } }
        }
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
        .confirmationDialog("Stop remaining import work?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop remaining work", role: .destructive) { Task { await model.stop() } }
        } message: { Text("Titles already saved stay in your Library. You can undo eligible saved changes separately.") }
        .confirmationDialog("Undo saved changes?", isPresented: $confirmUndo, titleVisibility: .visible) {
            Button("Undo saved changes", role: .destructive) { Task { await model.undo() } }
        } message: { Text("Later edits and replaced titles are kept. Pending local changes must be synchronized first.") }
    }

    private func summary(_ job: ImportOutcome) -> some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            Text(heading(job)).font(.kuroHeadline())
            Text("\(job.selection.provider.rawValue) · \(job.selection.sourceIdentity)")
                .font(.kuroCaption()).foregroundStyle(Color.kuroTextSecondary)
            Text("Anime and Manga keep their own identities. Existing Kuro values are kept unless you approve individual updates.")
                .font(.kuroBody()).foregroundStyle(Color.kuroTextSecondary)
            if !job.selection.media.allSatisfy({ job.exhaustedMedia[$0] == true }) {
                Text("Reading is incomplete. Resume the same import before confirming.")
                    .font(.kuroBody()).accessibilityIdentifier("import.read.incomplete")
            }
            Text("\(job.counts.added) added · \(job.counts.updated) updated · \(job.counts.unchanged) kept · \(job.counts.needsReview) need review · \(job.counts.pending) pending")
                .font(.kuroBody()).accessibilityIdentifier("import.saved.counts")
            if job.phase == .undone || job.phase == .undoing {
                let sameActiveJob = imports.activeImport?.jobId == job.jobId
                let reverted = sameActiveJob ? imports.importUndoReverted : (model.manifest?.undoReverted ?? 0)
                let skipped = sameActiveJob ? imports.importUndoSkipped : (model.manifest?.undoSkipped ?? 0)
                Text("Undo: \(reverted) reverted · \(skipped) kept with their later changes. The saved counts above describe the original import.")
                    .font(.kuroBody())
            }
            if job.counts.applied > 0, !job.projectionReady, job.phase != .undone {
                Text("Saved; refreshing your Library. The committed titles are safe.")
                    .font(.kuroBody()).accessibilityIdentifier("import.projection.pending")
            }
            if model.busy || imports.importBusy { ProgressView("Working on this import") }
        }
        .accessibilityElement(children: .contain)
    }

    private func heading(_ job: ImportOutcome) -> String {
        if job.phase == .undone { return "Import undone" }
        if job.phase == .reviewing { return "Review before saving" }
        if job.allRejected { return "Nothing was applied" }
        if job.isTerminal, job.counts.applied == 0, job.counts.unchanged > 0 { return "Already in your Library" }
        switch job.phase {
        case .preparing: return "Reading your source"
        case .applying: return "Saving approved titles"
        case .finalizing: return "Saved; refreshing your Library"
        case .cancelled: return "Import stopped"
        case .failed: return "Import needs attention"
        case .undoing: return "Undoing saved changes"
        case .ready: return job.counts.needsReview > 0 ? "Saved with items to review" : "Import results"
        case .reviewing, .undone: return "Import"
        }
    }

    @ViewBuilder private func controls(_ job: ImportOutcome) -> some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
            if job.phase == .reviewing, model.manifest == nil {
                Text("This review started on another device. Inspect or stop it here; approve changes on the device with the original source input.").font(.kuroBody())
            }
            if job.phase == .reviewing, let manifest = model.manifest, manifest.decisions != nil {
                Text("Your approved choices are already saved for this action. Resume them without approving a second time.").font(.kuroBody())
            }
            if job.phase == .reviewing, model.manifest?.phase == .reviewing, model.manifest?.decisions == nil {
                Text("Nothing from this review is saved until you confirm.").font(.kuroBody())
                Toggle("Review updates to existing titles", isOn: $reviewUpdates)
                    .font(.kuroBody())
                    .disabled(model.busy || imports.importBusy)
                Button("Save reviewed choices") { Task { await model.apply() } }
                    .buttonStyle(.borderedProminent).tint(Color.kuroBlack80)
                    .disabled(!model.mayApply)
                    .accessibilityIdentifier("import.approve")
            }
            if let manifest = model.manifest, (!job.isTerminal || !job.projectionReady),
               job.phase != .reviewing || manifest.phase != .reviewing || manifest.decisions != nil {
                Button("Resume this import") { Task { await model.resume(actionId: manifest.actionId) } }
                    .disabled(model.busy || imports.importBusy)
                    .accessibilityIdentifier("import.resume")
            } else if !job.isTerminal, job.phase != .reviewing {
                Text("This job can be inspected or stopped here. Continue source reading on the device that started it.")
                    .font(.kuroCaption()).foregroundStyle(Color.kuroTextSecondary)
            }
            if !job.isTerminal {
                Button("Stop remaining work", role: .destructive) { confirmStop = true }
            }
            if job.undoAvailable {
                Button("Undo saved changes") { confirmUndo = true }
                    .disabled(model.busy || imports.importBusy)
                    .accessibilityIdentifier("import.undo")
            } else if !job.historyAvailable {
                Text("Detailed history and Undo are no longer available for this older import.").font(.kuroCaption())
            }
            if job.isTerminal, job.counts.needsReview > 0, job.historyAvailable {
                Button("Review unresolved items in a new import") {
                    reviewUpdates = false; visibleCount = 50
                    Task { await model.reviewUnresolved() }
                }.disabled(model.busy || imports.importBusy)
            }
            if job.counts.applied > 0 || job.isTerminal {
                Button("View imported titles") { navigate(.importedTitles(model.affectedKeys)) }
                    .disabled(model.affectedKeys.isEmpty || !job.projectionReady || model.busy)
                    .accessibilityIdentifier("import.view.titles")
                Button("View full Collection") { navigate(.fullCollection) }
                    .disabled(!job.projectionReady || model.busy)
                    .accessibilityIdentifier("import.view.collection")
            }
            Button("Refresh status and Library") { Task { await model.refreshPresentation() } }
                .disabled(model.busy || imports.importBusy)
        }
    }

    private func navigate(_ destination: ImportResultDestination) {
        guard model.isCurrentAccount else { return }
        model.close(); dismiss(); onNavigate(destination)
    }

    private func failureCard(_ failure: ImportFailure) -> some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            Text(failure.localizedDescription).font(.kuroBody())
            if failure == .reconnect {
                Text("Reconnect MAL in Profile, then resume this same saved job.").font(.kuroCaption())
            } else if case .invalidInput = failure {
                Text("Choose another source or file in Profile. This job's saved changes remain available.").font(.kuroCaption())
            }
        }
        .padding(KuroDesignSpacing.md).background(Color.kuroBlack04, in: RoundedRectangle(cornerRadius: KuroRadius.md))
        .accessibilityIdentifier("import.failure")
    }

    @ViewBuilder private func titlePages(_ job: ImportOutcome) -> some View {
        if !model.items.isEmpty {
            Text(job.phase == .reviewing ? "Titles to review" : "Title results").font(.kuroTitle())
            if job.phase == .reviewing {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                    Button("All titles (\(model.items.count))") { reviewGroup = nil; visibleCount = 50 }
                    ForEach(ReviewGroup.allCases, id: \.self) { group in
                        Button("\(group.rawValue) (\(model.items.filter(group.includes).count))") {
                            reviewGroup = group; visibleCount = 50
                        }.accessibilityAddTraits(reviewGroup == group ? .isSelected : [])
                    }
                }.font(.kuroCaption())
            }
            let displayed = model.items.filter { job.phase != .reviewing || reviewGroup?.includes($0) != false }
            LazyVStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                ForEach(Array(displayed.prefix(visibleCount))) { item in reviewRow(item, job: job) }
            }
            if displayed.count > visibleCount {
                Button("Show next \(min(50, displayed.count - visibleCount)) titles") { visibleCount += 50 }
                    .accessibilityIdentifier("import.titles.next")
            }
        }
    }

    private func reviewRow(_ item: ImportReviewItem, job: ImportOutcome) -> some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            Text(item.title).font(.kuroTitle()).fixedSize(horizontal: false, vertical: true)
            Text("\(item.medium.capitalized) · \(dispositionLabel(item.disposition))")
                .font(.kuroCaption()).foregroundStyle(Color.kuroTextSecondary)
            if let detail = item.detail { Text(detail).font(.kuroCaption()) }
            if let undo = item.undoDisposition { Text("Undo: \(undo)").font(.kuroCaption()) }
            if job.phase == .reviewing {
                if item.current == nil {
                    Text(ImportFieldCopy.overview(item.incoming)).font(.kuroCaption())
                    DisclosureGroup("Incoming fields") {
                        ForEach(ImportFieldCopy.presentFields(in: item.incoming), id: \.self) { field in
                            Text("\(ImportFieldCopy.label(field).capitalized): \(ImportFieldCopy.value(field, in: item.incoming))")
                                .font(.kuroCaption()).fixedSize(horizontal: false, vertical: true)
                        }
                    }.font(.kuroCaption())
                } else if item.changedFields.isEmpty {
                    Text("Already in Kuro. Your values will be kept.").font(.kuroCaption())
                } else {
                    Text("Existing Kuro values will be kept by default.").font(.kuroCaption())
                    if reviewUpdates {
                        ForEach(item.changedFields, id: \.self) { field in
                            VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                                Text("Kuro: \(ImportFieldCopy.value(field, in: item.current))")
                                Text("Incoming: \(ImportFieldCopy.value(field, in: item.incoming))")
                                Toggle("Update \(ImportFieldCopy.label(field))", isOn: Binding(
                                    get: { model.approval.contains(field, for: item) },
                                    set: { model.approval.set(field, approved: $0, for: item) }
                                ))
                                .disabled(model.busy || imports.importBusy)
                            }.font(.kuroCaption())
                        }
                    }
                }
                if !item.incoming.unavailableFields.isEmpty {
                    Text("Unavailable from this source: \(item.incoming.unavailableFields.joined(separator: ", ")). Missing values never clear Kuro fields.")
                        .font(.kuroCaption()).foregroundStyle(Color.kuroTextSecondary)
                }
                if item.disposition == .unmatched, item.mediaId == nil {
                    Button("Match to a catalog title") { matchingItem = item }
                        .disabled(model.busy || imports.importBusy)
                }
            }
        }
        .padding(KuroDesignSpacing.md)
        .background(Color.kuroBlack04, in: RoundedRectangle(cornerRadius: KuroRadius.md))
        .accessibilityElement(children: .contain)
    }

    private func dispositionLabel(_ disposition: ImportDisposition) -> String {
        switch disposition {
        case .new: return "New title"
        case .existing: return "Already in Kuro"
        case .changes: return "Changes available"
        case .added: return "Added"
        case .updated: return "Updated"
        case .unchanged: return "Kept / unchanged"
        case .pending: return "Pending"
        case .unmatched, .conflict, .invalid, .sourceChanged: return "Needs review"
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
            ForEach(model.manifests.filter { manifest in
                manifest.jobId == nil || !model.jobs.contains(where: { $0.jobId == manifest.jobId })
            }) { manifest in
                VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                    Text("\(manifest.selection.provider.rawValue) · \(manifest.selection.sourceIdentity)").font(.kuroTitle())
                    Text("Saved on this device · \(manifest.phase.rawValue)").font(.kuroCaption())
                    Button(manifest.phase == .preparing ? "Resume source reading" : "Open saved import") { Task { await model.resume(actionId: manifest.actionId) } }
                        .disabled(model.busy || imports.importBusy)
                    if manifest.jobId == nil {
                        Text("Stopping discards this retained source input. Your Library is kept.").font(.kuroCaption())
                        Button("Stop preparation", role: .destructive) { Task { await model.stopPreparation(actionId: manifest.actionId) } }
                            .disabled(model.busy || imports.importBusy)
                    }
                }
            }
            ForEach(model.jobs) { job in
                Button { Task { visibleCount = 50; await model.inspect(job) } } label: {
                    VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                        Text("\(job.selection.provider.rawValue) · \(job.selection.sourceIdentity)").font(.kuroTitle())
                        Text("\(job.phase.rawValue) · \(job.counts.applied) saved · \(job.counts.needsReview) need review").font(.kuroCaption())
                    }.foregroundStyle(Color.kuroBlack80)
                }.disabled(model.busy)
            }
            if model.jobs.isEmpty, model.manifests.isEmpty, !model.busy {
                Text("No recent imports. Choose AniList or MAL in Profile.").font(.kuroBody())
            }
        }
    }
}

enum ImportFieldCopy {
    static func label(_ field: ImportField) -> String {
        switch field {
        case .status: return "status"
        case .progress: return "progress and unit identity"
        case .score: return "rating and score provenance"
        case .notes: return "notes"
        case .privacy: return "privacy"
        case .volumes: return "volume progress"
        case .repeats: return "repeat count"
        case .dates: return "start and finish dates"
        case .memberships: return "list memberships"
        case .sourceOptions: return "source list options"
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
        guard let values else { return "Not provided" }
        switch field {
        case .status: return values.status ?? "Not provided"
        case .progress: return values.progress.map { "\($0)\(values.progressLabel.map { " (\($0))" } ?? "")" } ?? "Not provided"
        case .score: return values.scoreRaw.map { "\($0) / \(values.scoreScale ?? "source scale") · Kuro \(values.normalizedRating.map(String.init) ?? "unrated")" } ?? values.normalizedRating.map { "Kuro \($0); no stored source score" } ?? "Not provided"
        case .notes: return values.notes?.isEmpty == false ? values.notes! : "No supplied note; keep Kuro"
        case .privacy: return values.isPrivate.map { $0 ? "Private" : "Public" } ?? "Not provided"
        case .volumes: return values.volumesProgress.map(String.init) ?? "Not provided"
        case .repeats: return values.repeatCount.map(String.init) ?? "Not provided"
        case .dates: return "\(values.startedRaw ?? "No start") → \(values.finishedRaw ?? "No finish")"
        case .memberships: return values.customLists?.joined(separator: ", ") ?? "Not provided"
        case .sourceOptions:
            let hidden = values.hiddenFromStatusLists.map { $0 ? "Hidden from status lists" : "Visible in status lists" }
            let parts = [values.sourceListOptions, hidden].compactMap { $0 }
            return parts.isEmpty ? "Not provided" : parts.joined(separator: " · ")
        }
    }
}
