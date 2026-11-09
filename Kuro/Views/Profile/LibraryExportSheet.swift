import KuroLibrary
import SwiftUI

// MARK: - Profile > Export your list (W2)
// The tool sheet of the list export, in the Contact sheet's grammar: white page, headline with an ink
// rule, three quiet format rows, one ink primary button. State and files live in `LibraryExportService`
// (account-scoped; the files hold private notes, so they are deleted when the sheet goes away). This
// view only chooses a format, asks the owner to prepare it and shows what came back.
//
// - Preparing shows the branded busy mark in the button. Offline is a quiet band: the export still
//   works from the library on the device, only catalogue ids may be missing (the summary names them).
// - A result is Share (the system share sheet for the files) plus one line per fact the files lack.
//   A request that built no file shows the summary and no Share.
// - A failure is the ridge with one plain sentence. Nothing is red, nothing is a coloured status.
// - Closing (the ✕, swipe-down, or the journey ending) stops a run in flight and deletes the files.

/// The pure decisions of the sheet (KuroTests).
nonisolated enum LibraryExportSheetRules {
    /// The files Share offers: only a finished export that wrote some. A request that built none (for
    /// example a MyAnimeList file while no title has a MyAnimeList id) offers no Share.
    static func shareableFiles(in state: LibraryExportState) -> [URL] {
        if case .ready(let result) = state { return result.files }
        return []
    }

    /// Whether choosing `format` makes the shown state stale: a result made for another format (its files
    /// and summary describe a different export) or a failure. A run in flight is never dropped; the
    /// format rows are disabled while it runs.
    static func dropsResult(in state: LibraryExportState, whenSelecting format: LibraryExportFormat) -> Bool {
        switch state {
        case .ready(let result): return result.format != format
        case .failed: return true
        case .idle, .preparing: return false
        }
    }
}

struct LibraryExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryExportService.self) private var export
    @Environment(NetworkMonitor.self) private var network
    @State private var format: LibraryExportFormat = .csv
    @State private var prepareTask: Task<Void, Never>?

    /// Row order: the format most people want first, then the re-import file, then the full backup.
    private static let formats: [LibraryExportFormat] = [.csv, .malXML, .json]

    /// `nil` follows the device language; tests pin one.
    private let germanOverride: Bool?

    init(german: Bool? = nil) {
        germanOverride = german
    }

    private var german: Bool { germanOverride ?? KuroLocale.isGerman }

    private var isPreparing: Bool {
        if case .preparing = export.state { return true }
        return false
    }

    var body: some View {
        let german = self.german
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                header(german: german)
                if !network.isConnected {
                    offlineBand(german: german)
                }
                formatPicker(german: german)
                resultBlock(german: german)
                actions(german: german)
            }
            .padding(.horizontal, KuroDesignSpacing.padding)
            .padding(.top, 64)
            .padding(.bottom, KuroDesignSpacing.xxl)
            .kuroReadableWidth()
        }
        .background(Color.kuroCanvasPage.ignoresSafeArea())
        .overlay(alignment: .topTrailing) { closeButton(german: german) }
        .presentationDragIndicator(.visible)
        .onChange(of: format) { _, chosen in
            if LibraryExportSheetRules.dropsResult(in: export.state, whenSelecting: chosen) {
                export.discardFiles()
            }
        }
        .onChange(of: export.state) { _, state in
            if !LibraryExportSheetRules.shareableFiles(in: state).isEmpty { KuroAccessibility.successHaptic() }
        }
        .onDisappear {
            prepareTask?.cancel()
            prepareTask = nil
            export.discardFiles()
        }
    }

    // MARK: Parts

    private func header(german: Bool) -> some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
            Text(LibraryExportCopy.heading(german: german))
                .kuroRoleText(.headline)
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Rectangle().fill(Color.kuroInk).frame(width: 46, height: 2)
            Text(LibraryExportCopy.intro(german: german))
                .font(.kuroBody())
                .foregroundStyle(Color.kuroInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Quiet band over the sheet's content: the export works offline, some ids may be missing.
    private func offlineBand(german: Bool) -> some View {
        HStack(spacing: KuroDesignSpacing.md) {
            KuroRidgeStroke(draws: false, lineWidth: 1)
                .frame(width: 36, height: 10)
            Text(LibraryExportCopy.offlineNote(german: german))
                .font(.kuroMeta())
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, KuroDesignSpacing.md)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .background(Color.kuroPaper)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.kuroLine).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    private func formatPicker(german: Bool) -> some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
            Text(LibraryExportCopy.formatLabel(german: german))
                .font(.kuroMeta(weight: .semibold))
                .foregroundStyle(Color.kuroInkSecondary)
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                ForEach(Self.formats, id: \.self) { option in
                    if option != Self.formats.first {
                        Rectangle().fill(Color.kuroHairline).frame(height: 0.5)
                    }
                    ExportFormatRow(
                        title: LibraryExportCopy.formatTitle(option, german: german),
                        subtitle: LibraryExportCopy.formatSubtitle(option, german: german),
                        isSelected: format == option,
                        isEnabled: !isPreparing
                    ) {
                        format = option
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func resultBlock(german: Bool) -> some View {
        switch export.state {
        case .idle, .preparing:
            EmptyView()
        case .failed(let failure):
            VStack(alignment: .leading, spacing: 6) {
                KuroRidgeStroke(draws: true, lineWidth: 1.2)
                    .frame(width: 120, height: 18)
                Text(LibraryExportCopy.failure(failure, german: german))
                    .font(.kuroBody())
                    .foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        case .ready(let result):
            readyBlock(result, german: german)
        }
    }

    private func readyBlock(_ result: LibraryExportResult, german: Bool) -> some View {
        let lines = LibraryExportCopy.summaryLines(result.summary, format: result.format, german: german)
        let headline = result.files.isEmpty
            ? LibraryExportCopy.emptyResultNote(german: german)
            : LibraryExportCopy.readyNote(fileCount: result.files.count, german: german)
        return VStack(alignment: .leading, spacing: 6) {
            KuroRidgeStroke(draws: true, lineWidth: 1.2)
                .frame(width: 120, height: 18)
            Text(headline)
                .font(.kuroCustom(15, weight: .semibold, relativeTo: .headline, maxSize: 30))
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.kuroMeta())
                    .foregroundStyle(Color.kuroInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if result.format == .csv, !result.files.isEmpty {
                Text(LibraryExportCopy.csvSafetyNote(german: german))
                    .font(.kuroMeta())
                    .foregroundStyle(Color.kuroInkQuiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private func actions(german: Bool) -> some View {
        let files = LibraryExportSheetRules.shareableFiles(in: export.state)
        if files.isEmpty {
            KuroInkButton(LibraryExportCopy.prepareTitle(german: german), isLoading: isPreparing) { prepare() }
        } else {
            ShareLink(items: files, preview: { SharePreview($0.lastPathComponent) }) {
                Text(LibraryExportCopy.shareTitle(german: german))
                    .font(.kuroButtonLabel())
                    .foregroundStyle(Color.kuroWhite)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .padding(.horizontal, KuroDesignSpacing.lg)
                    .background(Capsule().fill(Color.kuroInk))
                    .contentShape(Capsule())
            }
            .buttonStyle(KuroPressStyle())
            KuroInkButton(LibraryExportCopy.prepareAgainTitle(german: german), role: .secondary, haptic: false) { prepare() }
        }
    }

    private func closeButton(german: Bool) -> some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.kuroCustom(15, weight: .medium, relativeTo: .body, maxSize: 22))
                .foregroundStyle(Color.kuroInk)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.kuroWhite).overlay(Circle().strokeBorder(Color.kuroHairline, lineWidth: 0.5)))
        }
        .buttonStyle(KuroPressStyle())
        .accessibilityLabel(LibraryExportCopy.closeLabel(german: german))
        .padding(.top, 12)
        .padding(.trailing, 12)
    }

    // MARK: Actions

    private func prepare() {
        let chosen = format
        prepareTask?.cancel()
        prepareTask = Task { await export.export(chosen) }
    }
}

/// One quiet format row: serif-weight title, one line of what it is for, a radio mark. 44 pt tall at least.
private struct ExportFormatRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            action()
        } label: {
            HStack(alignment: .top, spacing: KuroDesignSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.kuroCustom(15, weight: .medium, relativeTo: .headline, maxSize: 30)).tracking(-0.2)
                        .foregroundStyle(Color.kuroInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroInkSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: KuroDesignSpacing.sm)
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.kuroCustom(22, weight: .regular, relativeTo: .body, maxSize: 32))
                    .foregroundStyle(isSelected ? Color.kuroInk : Color.kuroInkQuiet)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .opacity(isEnabled || isSelected ? 1 : 0.45)
        }
        .buttonStyle(KuroPressStyle(pressedScale: 0.99))
        .disabled(!isEnabled)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
