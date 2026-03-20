import SwiftUI

extension View {
    func aniListImportSheet(
        supabaseService: SupabaseService,
        isGermanLocale: Bool,
        onImportCompleted: @escaping (SupabaseService.ConciergeAniListImportResponse) async -> Void
    ) -> some View {
        ConciergeAniListImportSheet(
            supabaseService: supabaseService,
            isGermanLocale: isGermanLocale,
            onImportCompleted: onImportCompleted
        )
    }
}

struct ConciergeAniListImportSheet: View {
    let supabaseService: SupabaseService
    let isGermanLocale: Bool
    let onImportCompleted: (SupabaseService.ConciergeAniListImportResponse) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var coordinator = ConciergeAniListImportCoordinator()
    @State private var username: String = ""
    @State private var includeAnime: Bool = true
    @State private var includeManga: Bool = true
    @State private var includeCurrent: Bool = true
    @State private var includeCompleted: Bool = true
    @State private var includePlanning: Bool = true
    @State private var includePaused: Bool = false
    @State private var includeDropped: Bool = false
    @FocusState private var usernameFocused: Bool

    private var canPreview: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (includeAnime || includeManga)
            && (includeCurrent || includeCompleted || includePlanning || includePaused || includeDropped)
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
            .background(Color.kuroBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isGermanLocale ? "Fertig" : "Done") {
                        dismiss()
                    }
                    .font(.kuroCaption(weight: .medium))
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            usernameFocused = true
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isGermanLocale ? "AniList importieren" : "Import from AniList")
                .font(.kuroCustom(26, weight: .ultraLight, design: .serif, relativeTo: .title2))
                .foregroundStyle(Color.kuroBlack.opacity(0.84))

            Text(isGermanLocale
                ? "Erst Vorschau, dann Import. So siehst du Titel, Status und Umfang, bevor Kuro etwas übernimmt."
                : "Preview first, then confirm. See titles, status, and scope before Kuro imports anything."
            )
            .font(.kuroBody(weight: .light))
            .foregroundStyle(Color.kuroBlack.opacity(0.62))
            .lineSpacing(3)
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
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
                        coordinator.reset()
                        usernameFocused = true
                    }
                )
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
                            coordinator.reset()
                            usernameFocused = true
                        }
                    )
                } else {
                    errorCard
                    actionButtons(
                        primaryTitle: isGermanLocale ? "VORSCHAU ERNEUT VERSUCHEN" : "TRY PREVIEW AGAIN",
                        primaryAction: { Task { await startPreview() } },
                        secondaryTitle: isGermanLocale ? "FORMULAR ÄNDERN" : "EDIT FORM",
                        secondaryAction: {
                            coordinator.reset()
                            usernameFocused = true
                        }
                    )
                }
            }
        }
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            fieldSectionTitle(isGermanLocale ? "Benutzername" : "Username")

            TextField(isGermanLocale ? "z.B. maxmustermann" : "e.g. yourname", text: $username)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($usernameFocused)
                .font(.kuroBody())
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                        .fill(Color.kuroWhite92)
                        .overlay(
                            RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                                .stroke(Color.kuroBlack08, lineWidth: 0.7)
                        )
                )

            fieldSectionTitle(isGermanLocale ? "Typ" : "Type")
            HStack(spacing: 10) {
                togglePill(title: "Anime", isOn: $includeAnime)
                togglePill(title: "Manga", isOn: $includeManga)
            }

            fieldSectionTitle(isGermanLocale ? "Status" : "Status")
            HStack(spacing: 10) {
                togglePill(title: isGermanLocale ? "Aktuell" : "Current", isOn: $includeCurrent)
                togglePill(title: isGermanLocale ? "Fertig" : "Completed", isOn: $includeCompleted)
                togglePill(title: isGermanLocale ? "Plan" : "Planning", isOn: $includePlanning)
            }
            HStack(spacing: 10) {
                togglePill(title: isGermanLocale ? "Pausiert" : "On hold", isOn: $includePaused)
                togglePill(title: isGermanLocale ? "Abgebrochen" : "Dropped", isOn: $includeDropped)
            }

            Button {
                Task { await startPreview() }
            } label: {
                HStack(spacing: 10) {
                    if coordinator.isPreviewing {
                        ProgressView()
                            .tint(Color.kuroWhite)
                    }
                    Text(isGermanLocale ? "VORSCHAU" : "PREVIEW")
                        .font(.kuroCaption(weight: .medium))
                        .tracking(2.0)
                }
                .foregroundStyle(Color.kuroWhite)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule(style: .continuous)
                        .fill(canPreview ? Color.kuroBlack.opacity(0.88) : Color.kuroBlack10)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canPreview || coordinator.isPreviewing || coordinator.isImporting)
            .padding(.top, 4)

            Text(isGermanLocale
                ? "Nur öffentliche Listen sind im MVP vorgesehen. Private Einträge brauchen später OAuth."
                : "This MVP uses public lists only. Private entries will need OAuth later."
            )
            .font(.kuroMicro())
            .foregroundColor(.kuroTextTertiary)
            .padding(.top, 2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.black.opacity(0.07), lineWidth: 0.8)
                )
        )
    }

    private var selectionSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isGermanLocale ? "Vorschau für" : "Preview for")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.8)
                        .foregroundColor(.kuroTextTertiary)
                    Text("@\(username.trimmingCharacters(in: .whitespacesAndNewlines))")
                        .font(.kuroCaption(weight: .medium))
                        .foregroundColor(.kuroBlack80)
                }
                Spacer(minLength: 0)
                Button {
                    coordinator.reset()
                    usernameFocused = true
                } label: {
                    Text(isGermanLocale ? "ÄNDERN" : "EDIT")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.6)
                        .foregroundColor(.kuroTextTertiary)
                }
                .buttonStyle(.plain)
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
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.kuroWhite92)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.7)
                )
        )
    }

    private func previewCard(
        preview: SupabaseService.ConciergeAniListPreviewResponse,
        errorMessage: String?,
        isImporting: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isGermanLocale ? "VORSCHAU" : "PREVIEW")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.8)
                        .foregroundColor(.kuroTextTertiary)

                    Text(countSummary(preview))
                        .font(.kuroHeadline(weight: .ultraLight))
                        .foregroundColor(.kuroBlack.opacity(0.84))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if let truncated = preview.truncated {
                    summaryPill(truncated ? (isGermanLocale ? "Gekürzt" : "Truncated") : (isGermanLocale ? "Vollständig" : "Full"))
                }
            }

            if let text = preview.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                Text(text)
                    .font(.kuroBody(weight: .light))
                    .foregroundColor(.kuroBlack60)
                    .lineSpacing(3)
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
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.kuroBlack45)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isGermanLocale ? "Etwas ist schiefgelaufen" : "Something went wrong")
                            .font(.kuroCaption(weight: .medium))
                            .foregroundColor(.kuroBlack80)
                        Text(errorMessage)
                            .font(.kuroCaption(weight: .light))
                            .foregroundColor(.kuroTextSecondary)
                            .lineSpacing(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.03))
                )
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
                VStack(alignment: .leading, spacing: 8) {
                    Text(isGermanLocale ? "Beispiele" : "Samples")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.6)
                        .foregroundColor(.kuroTextTertiary)

                    VStack(spacing: 8) {
                        ForEach(samples.prefix(4)) { sample in
                            sampleRow(sample)
                        }
                    }
                }
            }

            if isImporting {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.black.opacity(0.45))
                    Text(isGermanLocale ? "Import läuft..." : "Importing...")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.black.opacity(0.50))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.black.opacity(0.07), lineWidth: 0.8)
                )
        )
    }

    private var previewLoadingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(0.95)
                    .tint(.black.opacity(0.45))
                Text(isGermanLocale ? "Vorschau wird geladen..." : "Loading preview...")
                    .font(.kuroCaption(weight: .light))
                    .foregroundColor(.kuroBlack60)
            }

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.05))
                .frame(height: 120)
                .kuroShimmer()

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.05))
                .frame(height: 88)
                .kuroShimmer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.black.opacity(0.07), lineWidth: 0.8)
                )
        )
    }

    private var errorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isGermanLocale ? "Vorschau fehlgeschlagen" : "Preview failed")
                .font(.kuroHeadline(weight: .ultraLight))
                .foregroundColor(.kuroBlack.opacity(0.84))

            Text(coordinator.errorMessage ?? (isGermanLocale ? "Bitte versuche es erneut." : "Please try again."))
                .font(.kuroBody(weight: .light))
                .foregroundColor(.kuroBlack60)
                .lineSpacing(3)

            if let retryAfter = coordinator.retryAfterSeconds {
                Text(isGermanLocale
                    ? "Erneut versuchen in etwa \(retryAfter) Sekunden."
                    : "Try again in about \(retryAfter) seconds."
                )
                .font(.kuroMicro())
                .foregroundColor(.kuroTextTertiary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.black.opacity(0.07), lineWidth: 0.8)
                )
        )
    }

    private func actionButtons(
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 10) {
            Button(action: primaryAction) {
                HStack(spacing: 10) {
                    if coordinator.isImporting || coordinator.isPreviewing {
                        ProgressView()
                            .tint(Color.kuroWhite)
                    }
                    Text(primaryTitle)
                        .font(.kuroCaption(weight: .medium))
                        .tracking(2.0)
                }
                .foregroundStyle(Color.kuroWhite)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.kuroBlack.opacity(0.88))
                )
            }
            .buttonStyle(.plain)
            .disabled(coordinator.isPreviewing || coordinator.isImporting)

            Button(action: secondaryAction) {
                Text(secondaryTitle)
                    .font(.kuroCaption(weight: .medium))
                    .tracking(1.4)
                    .foregroundColor(.kuroTextTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private func togglePill(title: String, isOn: Binding<Bool>) -> some View {
        Button(action: { isOn.wrappedValue.toggle() }) {
            Text(title)
                .font(.kuroCaption(weight: .medium))
                .foregroundStyle(isOn.wrappedValue ? Color.kuroWhite : Color.kuroBlack.opacity(0.68))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(isOn.wrappedValue ? Color.kuroBlack.opacity(0.86) : Color.kuroBlack04)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.kuroBlack10, lineWidth: 0.6)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
        .accessibilityHint(isGermanLocale ? "Schaltet den Filter um" : "Toggles this filter")
    }

    private func stepPill(title: String, isActive: Bool) -> some View {
        Text(title)
            .font(.kuroMicro(weight: .medium))
            .tracking(1.8)
            .foregroundColor(isActive ? .white : .kuroTextTertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? Color.black.opacity(0.88) : Color.black.opacity(0.04))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.black.opacity(isActive ? 0.0 : 0.08), lineWidth: 0.7)
                    )
            )
    }

    private func fieldSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.kuroMicro(weight: .medium))
            .tracking(1.8)
            .foregroundColor(.kuroTextTertiary)
    }

    private func summaryPill(_ text: String) -> some View {
        Text(text)
            .font(.kuroMicro(weight: .medium))
            .tracking(1.1)
            .foregroundColor(.kuroBlack70)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.04))
            )
    }

    private func countSection(title: String, counts: [String: Int]) -> some View {
        let rows = counts
            .map { (key: $0.key, value: $0.value) }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }

        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.kuroMicro(weight: .medium))
                .tracking(1.6)
                .foregroundColor(.kuroTextTertiary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(rows, id: \.key) { row in
                    summaryPill("\(row.key): \(row.value)")
                }
            }
        }
    }

    private func sampleRow(_ sample: SupabaseService.ConciergeAniListPreviewItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(sample.titleDisplay)
                    .font(.kuroCaption(weight: .medium))
                    .foregroundColor(.kuroBlack80)
                    .lineLimit(2)

                Text(sampleMeta(sample))
                    .font(.kuroMicro())
                    .foregroundColor(.kuroTextTertiary)
            }
            Spacer(minLength: 0)
            Text(sample.type.uppercased())
                .font(.kuroMicro(weight: .medium))
                .tracking(1.2)
                .foregroundColor(.kuroTextTertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.03))
        )
    }

    private func sampleMeta(_ sample: SupabaseService.ConciergeAniListPreviewItem) -> String {
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

    private func countSummary(_ preview: SupabaseService.ConciergeAniListPreviewResponse) -> String {
        let count = preview.itemCount ?? 0
        let truncated = preview.truncated == true
        if isGermanLocale {
            return truncated ? "\(count) Titel, gekürzt" : "\(count) Titel"
        }
        return truncated ? "\(count) items, truncated" : "\(count) items"
    }

    private func startPreview() async {
        guard canPreview else { return }
        await coordinator.loadPreview(
            using: supabaseService,
            isGermanLocale: isGermanLocale,
            username: username,
            types: selectedTypes,
            statuses: selectedStatuses
        )
    }

    private func confirmImport() async {
        guard let response = await coordinator.confirmImport(using: supabaseService, isGermanLocale: isGermanLocale) else {
            return
        }
        dismiss()
        await onImportCompleted(response)
    }
}
