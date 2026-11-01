import KuroCore
import KuroLibrary
import SwiftUI

/// Account-keyed Profile discovery of saved and resumable imports. Durable continuation stays in the
/// Imports owner; this section only lists what exists and opens it.
struct ImportHistorySection: View {
    let imports: ImportsService
    let onOpen: (ImportOutcome?) -> Void
    @State private var model: ImportWorkflowPresentation?

    var body: some View {
        let german = KuroLocale.isGerman
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(german ? "Laufende und letzte Importe" : "Recent and pending imports")
                    .kuroRoleText(.title)
                    .foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: KuroDesignSpacing.sm)
                if let model, model.isCurrentAccount {
                    Button {
                        Task { await model.load() }
                    } label: {
                        Text(german ? "Aktualisieren" : "Refresh")
                            .font(.kuroMeta(weight: .medium))
                            .foregroundStyle(Color.kuroInk)
                            .underline(true, color: Color.kuroInk)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.busy)
                }
            }
            if let model, model.isCurrentAccount {
                if model.busy && model.jobs.isEmpty && model.manifests.isEmpty {
                    KuroStateView(.loading, title: german ? "Gespeicherte Importe werden gelesen." : "Reading saved imports.",
                                  layout: .inline)
                }
                if let failure = model.failure {
                    KuroStateView(.failed(hasCachedContent: !model.jobs.isEmpty || !model.manifests.isEmpty),
                                  message: ImportCopy.failure(failure, german: german), layout: .inline) {
                        Task { await model.load() }
                    }
                }
                ForEach(model.manifests) { manifest in
                    VStack(alignment: .leading, spacing: 0) {
                        historyRow(
                            title: ImportCopy.source(manifest.selection, german: german),
                            subtitle: (german ? "Auf diesem Gerät gesichert · " : "Saved on this device · ")
                                + ImportCopy.phase(manifest.phase, german: german)
                        ) {
                            guard model.isCurrentAccount else { return }
                            onOpen(model.jobs.first { $0.jobId == manifest.jobId })
                        }
                        if manifest.jobId == nil {
                            Button(role: .destructive) {
                                Task { await model.stopPreparation(actionId: manifest.actionId) }
                            } label: {
                                Text(german ? "Vorbereitung anhalten" : "Stop preparation")
                                    .font(.kuroMeta(weight: .medium))
                                    .foregroundStyle(Color.kuroDestructiveInk)
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(model.busy || imports.importBusy)
                        }
                        Rectangle().fill(Color.kuroHairline).frame(height: 0.5)
                    }
                }
                ForEach(model.jobs.filter { job in !model.manifests.contains(where: { $0.jobId == job.jobId }) }) { job in
                    historyRow(
                        title: ImportCopy.source(job.selection, german: german),
                        subtitle: ImportCopy.phase(job.phase, german: german) + " · "
                            + ImportCopy.savedSummary(applied: job.counts.applied, needsReview: job.counts.needsReview, german: german)
                    ) {
                        guard model.isCurrentAccount else { return }
                        onOpen(job)
                    }
                    Rectangle().fill(Color.kuroHairline).frame(height: 0.5)
                }
                if !model.busy, model.jobs.isEmpty, model.manifests.isEmpty, model.failure == nil {
                    Text(german ? "Noch keine gesicherten Importe." : "No saved imports yet.")
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroInkSecondary)
                        .frame(minHeight: 44, alignment: .leading)
                }
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

    private func historyRow(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.kuroBody(weight: .medium))
                    .foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.kuroMeta())
                    .foregroundStyle(Color.kuroInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, KuroDesignSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle(pressedScale: 0.99))
        .accessibilityHint(KuroLocale.text("Opens this import", "Öffnet diesen Import"))
    }
}
