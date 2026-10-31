import KuroCore
import KuroLibrary
import SwiftUI

/// Account-keyed Profile discovery. Durable continuation stays in the Imports owner.
struct ImportHistorySection: View {
    let imports: ImportsService
    let onOpen: (ImportOutcome?) -> Void
    @State private var model: ImportWorkflowPresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
            Text("Recent and pending imports").font(.kuroTitle())
            if let model, model.isCurrentAccount {
                if model.busy { ProgressView("Reading saved imports") }
                if let failure = model.failure { Text(failure.localizedDescription).font(.kuroCaption()) }
                ForEach(model.manifests) { manifest in
                    VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                        Button {
                            guard model.isCurrentAccount else { return }
                            onOpen(model.jobs.first { $0.jobId == manifest.jobId })
                        } label: {
                            VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                                Text("\(manifest.selection.provider.rawValue) · \(manifest.selection.sourceIdentity)").font(.kuroBody())
                                Text("Saved on this device · \(manifest.phase.rawValue) · Resume or inspect")
                                    .font(.kuroCaption()).foregroundStyle(Color.kuroTextSecondary)
                            }
                        }.foregroundStyle(Color.kuroBlack80)
                        if manifest.jobId == nil {
                            Button("Stop preparation", role: .destructive) { Task { await model.stopPreparation(actionId: manifest.actionId) } }
                                .disabled(model.busy || imports.importBusy)
                        }
                    }
                }
                ForEach(model.jobs.filter { job in !model.manifests.contains(where: { $0.jobId == job.jobId }) }) { job in
                    Button {
                        guard model.isCurrentAccount else { return }; onOpen(job)
                    } label: {
                        VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                            Text("\(job.selection.provider.rawValue) · \(job.selection.sourceIdentity)").font(.kuroBody())
                            Text("\(job.phase.rawValue) · \(job.counts.applied) saved · \(job.counts.needsReview) need review")
                                .font(.kuroCaption()).foregroundStyle(Color.kuroTextSecondary)
                        }
                    }.foregroundStyle(Color.kuroBlack80)
                }
                if !model.busy, model.jobs.isEmpty, model.manifests.isEmpty, model.failure == nil {
                    Text("No saved imports yet.").font(.kuroCaption()).foregroundStyle(Color.kuroTextSecondary)
                }
                Button("Refresh imports") { Task { await model.load() } }.disabled(model.busy)
            }
        }
        .task(id: imports.accountSession.current) {
            model?.close()
            let current = ImportWorkflowPresentation(imports: imports)
            model = current; current.activate(); await current.load()
        }
        .onDisappear { model?.close() }
        .accessibilityIdentifier("profile.import.history")
    }
}
