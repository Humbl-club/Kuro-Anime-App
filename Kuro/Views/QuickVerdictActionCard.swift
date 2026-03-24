import SwiftUI

enum QuickVerdictChoice: String, CaseIterable, Identifiable {
    case unsorted = "UNSORTED"
    case masterpiece = "MASTERPIECE"
    case okay = "OKAY"
    case bad = "BAD"

    var id: String { rawValue }

    func displayName(isGerman: Bool) -> String {
        switch self {
        case .unsorted: return isGerman ? "Ohne Urteil" : "Unsorted"
        case .masterpiece: return isGerman ? "Meisterwerk" : "Masterpiece"
        case .okay: return "Okay"
        case .bad: return isGerman ? "Schwach" : "Bad"
        }
    }

    var verdict: Verdict? {
        switch self {
        case .unsorted: return nil
        case .masterpiece: return .masterpiece
        case .okay: return .okay
        case .bad: return .bad
        }
    }

    static func fromVerdict(_ verdict: Verdict?) -> QuickVerdictChoice {
        switch verdict {
        case .none: return .unsorted
        case .masterpiece: return .masterpiece
        case .okay: return .okay
        case .bad: return .bad
        }
    }
}

func quickVerdictChoice(for entry: UserList?) -> QuickVerdictChoice {
    QuickVerdictChoice.fromVerdict(entry?.verdict)
}

func quickStatusLabel(for status: ListStatus, mediaKind: MediaKind, isGerman: Bool = false) -> String {
    switch status {
    case .planning:
        return isGerman ? "Merken" : "Want"
    case .current:
        if isGerman {
            return mediaKind == .anime ? "Schauen" : "Lesen"
        }
        return mediaKind == .anime ? "Watching" : "Reading"
    case .completed:
        return isGerman ? "Fertig" : "Completed"
    case .paused:
        return isGerman ? "Pausiert" : "Paused"
    case .dropped:
        return isGerman ? "Abgebrochen" : "Dropped"
    case .repeating:
        if isGerman {
            return mediaKind == .anime ? "Nochmal schauen" : "Nochmal lesen"
        }
        return mediaKind == .anime ? "Rewatching" : "Rereading"
    }
}

func quickStatusCapsuleLabel(for entry: UserList?, mediaKind: MediaKind, isGerman: Bool) -> String {
    guard let entry else { return isGerman ? "HINZUFUEGEN" : "ADD" }
    let base = quickStatusLabel(for: entry.status, mediaKind: mediaKind, isGerman: isGerman).uppercased()
    let verdict = quickVerdictChoice(for: entry)
    return verdict == .unsorted ? base : "\(base) · \(verdict.displayName(isGerman: isGerman).uppercased())"
}

func friendlyListMutationMessage(_ raw: String?, isGerman: Bool) -> String {
    guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return isGerman ? "Deine Liste konnte nicht aktualisiert werden." : "Couldn't update your list."
    }

    let lowered = raw.lowercased()
    if lowered.contains("row-level security") {
        return isGerman ? "Deine Liste konnte gerade nicht aktualisiert werden. Versuch es erneut." : "Couldn't update your list right now. Try again."
    }
    if lowered.contains("failed to save") {
        return isGerman ? "Speichern fehlgeschlagen. Versuch es erneut." : "Couldn't save your changes. Try again."
    }
    return raw
}

struct QuickVerdictActionCard: View {
    let media: any MediaDisplayable
    var onToast: ((KuroToastState) -> Void)? = nil
    var onDone: (() -> Void)? = nil

    @Environment(SupabaseService.self) private var supabaseService
    @Environment(NetworkMonitor.self) private var networkMonitor

    @State private var showAdvancedEdit = false
    @State private var showVerdictOptions = false
    @State private var isMutating = false
    @State private var mutationMessage: String? = nil
    private var isGermanLocale: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("de") == true
    }

    private let quickStatuses: [ListStatus] = [.planning, .current, .completed, .paused, .dropped]

    private var entry: UserList? {
        supabaseService.userListEntry(mediaType: media.kind.rawValue, mediaId: media.id)
    }

    private var isOffline: Bool {
        !networkMonitor.isConnected
    }

    private var currentStatus: ListStatus? {
        entry?.status
    }

    private var currentVerdict: QuickVerdictChoice {
        quickVerdictChoice(for: entry)
    }

    private var shouldShowVerdictSection: Bool {
        showVerdictOptions || currentStatus == .completed || currentVerdict != .unsorted
    }

    private var progressUnit: String {
        media.kind == .anime ? "EP" : "CH"
    }

    private var progressSummary: String? {
        guard let entry else { return nil }
        let total = media.episodes ?? media.chapters ?? 0
        guard entry.progress > 0 || total > 0 else { return nil }
        if total > 0 {
            return "\(entry.progress)/\(total) \(progressUnit)"
        }
        return "\(entry.progress) \(progressUnit)"
    }

    private var summaryLine: String {
        guard let entry else { return isGermanLocale ? "Noch nicht in deiner Liste" : "Not in your list yet" }
        var parts: [String] = [quickStatusLabel(for: entry.status, mediaKind: media.kind, isGerman: isGermanLocale)]
        if currentVerdict != .unsorted {
            parts.append(currentVerdict.displayName(isGerman: isGermanLocale))
        }
        if let progressSummary {
            parts.append(progressSummary)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isGermanLocale ? "LISTE" : "LIST")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.7)
                        .foregroundColor(.kuroTextTertiary)

                    Text(summaryLine)
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroBlack70)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if isMutating {
                    ProgressView()
                        .scaleEffect(0.85)
                        .tint(.kuroBlack60)
                }
            }

            actionSectionTitle(isGermanLocale ? "STATUS" : "STATUS")
            chipScroller {
                ForEach(quickStatuses, id: \.self) { status in
                    quickChip(
                        title: quickStatusLabel(for: status, mediaKind: media.kind, isGerman: isGermanLocale).uppercased(),
                        isSelected: currentStatus == status,
                        action: { applyStatus(status) }
                    )
                }
            }

            if shouldShowVerdictSection {
                actionSectionTitle(isGermanLocale ? "URTEIL" : "VERDICT")
                chipScroller {
                    ForEach(QuickVerdictChoice.allCases) { verdict in
                        quickChip(
                            title: verdict.displayName(isGerman: isGermanLocale).uppercased(),
                            isSelected: currentVerdict == verdict,
                            action: { applyVerdict(verdict) }
                        )
                    }
                }
            } else {
                Button {
                    KuroAccessibility.impactHaptic(.light)
                    withAnimation(KuroAnimation.fast) {
                        showVerdictOptions = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tag")
                            .font(.system(size: 10, weight: .semibold))
                        Text(isGermanLocale ? "URTEIL" : "VERDICT")
                            .font(.kuroMicro(weight: .medium))
                            .tracking(1.0)
                    }
                    .foregroundColor(.kuroBlack70)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.kuroBlack06)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.kuroBlack12, lineWidth: 0.6)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isMutating)
            }

            HStack(spacing: 10) {
                if entry != nil {
                    Button(role: .destructive) {
                        removeFromList()
                    } label: {
                        Text(isGermanLocale ? "ENTFERNEN" : "REMOVE")
                            .font(.kuroMicro(weight: .medium))
                            .tracking(1.1)
                            .foregroundColor(.red.opacity(0.78))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.red.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isMutating)
                }

                Spacer(minLength: 0)

                Button {
                    KuroAccessibility.impactHaptic(.light)
                    showAdvancedEdit = true
                } label: {
                    Text(isGermanLocale ? "MEHR" : "MORE")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.1)
                        .foregroundColor(.kuroBlack70)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.kuroBlack06)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.kuroBlack12, lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isMutating)
            }

            if let mutationMessage {
                Text(mutationMessage)
                    .font(.kuroMicro(weight: .light))
                    .foregroundColor(isOffline ? .kuroTextTertiary : .red.opacity(0.72))
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.kuroBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
                )
        )
        .sheet(isPresented: $showAdvancedEdit) {
            AddToListSheet(media: media)
        }
        .onChange(of: networkMonitor.isConnected) { _, isConnected in
            if isConnected {
                mutationMessage = nil
            }
        }
    }

    @ViewBuilder
    private func chipScroller<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                content()
            }
            .padding(.vertical, 1)
        }
        .kuroSwipeExclusionZone()
    }

    private func actionSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.kuroMicro(weight: .medium))
            .tracking(1.6)
            .foregroundColor(.kuroTextTertiary)
    }

    private func quickChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            action()
        } label: {
            Text(title)
                .font(.kuroMicro(weight: .medium))
                .tracking(1.0)
                .foregroundColor(isSelected ? .white : .kuroBlack70)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.kuroBlack : Color.kuroBlack06)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isSelected ? Color.kuroBlack : Color.kuroBlack12, lineWidth: 0.6)
                )
        }
        .buttonStyle(.plain)
        .disabled(isMutating)
    }

    private func applyStatus(_ status: ListStatus) {
        mutate(
            status: status,
            progress: resolvedProgress(for: status),
            rating: entry?.score.map { $0 / 10 },
            verdict: entry?.verdict
        )
    }

    private func applyVerdict(_ verdict: QuickVerdictChoice) {
        guard !isOffline else {
            mutationMessage = isGermanLocale ? "Du bist offline. Verbinde dich erneut, um deine Liste zu aktualisieren." : "You're offline. Reconnect to update your list."
            KuroAccessibility.errorHaptic()
            return
        }

        guard entry != nil else {
            mutate(
                status: .completed,
                progress: resolvedProgress(for: .completed),
                rating: entry?.score.map { $0 / 10 },
                verdict: verdict.verdict
            )
            return
        }

        isMutating = true
        mutationMessage = nil

        Task {
            await supabaseService.setUserVerdict(
                mediaId: media.id,
                mediaType: media.kind.rawValue,
                verdict: verdict.verdict
            )
            await MainActor.run {
                isMutating = false
                if let error = supabaseService.errorMessage, !error.isEmpty {
                    mutationMessage = friendlyListMutationMessage(error, isGerman: isGermanLocale)
                    emitErrorToast()
                    return
                }
                KuroAccessibility.successHaptic()
                emitSuccessToast(
                    title: verdict == .unsorted
                        ? (isGermanLocale ? "Urteil entfernt" : "Verdict cleared")
                        : (isGermanLocale ? "Urteil gespeichert" : "Verdict saved"),
                    subtitle: media.title
                )
                onDone?()
            }
        }
    }

    private func removeFromList() {
        guard !isOffline else {
            mutationMessage = isGermanLocale ? "Du bist offline. Verbinde dich erneut, um deine Liste zu aktualisieren." : "You're offline. Reconnect to update your list."
            KuroAccessibility.errorHaptic()
            return
        }

        isMutating = true
        mutationMessage = nil

        Task {
            let removed = await supabaseService.removeFromList(
                mediaId: media.id,
                mediaType: media.kind.rawValue
            )
            await MainActor.run {
                isMutating = false
                if removed {
                    KuroAccessibility.successHaptic()
                    emitSuccessToast(
                        title: isGermanLocale ? "Aus Liste entfernt" : "Removed from list",
                        subtitle: media.title
                    )
                    onDone?()
                } else {
                    mutationMessage = friendlyListMutationMessage(
                        supabaseService.errorMessage,
                        isGerman: isGermanLocale
                    )
                    emitErrorToast()
                }
            }
        }
    }

    private func mutate(status: ListStatus, progress: Int, rating: Int?, verdict: Verdict?) {
        guard !isOffline else {
            mutationMessage = isGermanLocale ? "Du bist offline. Verbinde dich erneut, um deine Liste zu aktualisieren." : "You're offline. Reconnect to update your list."
            KuroAccessibility.errorHaptic()
            return
        }

        isMutating = true
        mutationMessage = nil
        let notes = entry?.notes

        Task {
            await supabaseService.upsertUserListEntry(
                mediaId: media.id,
                mediaType: media.kind.rawValue,
                status: status,
                progress: progress,
                rating: rating,
                notes: notes,
                verdict: verdict
            )

            await MainActor.run {
                isMutating = false
                if let error = supabaseService.errorMessage, !error.isEmpty {
                    mutationMessage = friendlyListMutationMessage(error, isGerman: isGermanLocale)
                    emitErrorToast()
                    return
                }
                KuroAccessibility.successHaptic()
                emitSuccessToast(
                    title: isGermanLocale ? "Status aktualisiert" : "Status updated",
                    subtitle: media.title
                )
                onDone?()
            }
        }
    }

    private func resolvedProgress(for status: ListStatus) -> Int {
        let total = media.episodes ?? media.chapters ?? 0
        let currentProgress = entry?.progress ?? 0

        if status == .completed, total > 0 {
            return max(total, currentProgress)
        }
        return currentProgress
    }

    private func emitErrorToast() {
        guard let onToast else { return }
        onToast(
            .init(
                kind: .error,
                title: isGermanLocale ? "Liste konnte nicht aktualisiert werden" : "Couldn't update list",
                subtitle: mutationMessage,
                actionTitle: nil,
                onAction: nil
            )
        )
    }

    private func emitSuccessToast(title: String, subtitle: String?) {
        guard let onToast else { return }
        onToast(
            .init(
                kind: .success,
                title: title,
                subtitle: subtitle,
                actionTitle: nil,
                onAction: nil
            )
        )
    }
}

struct QuickVerdictActionSheet: View {
    let media: any MediaDisplayable
    var onToast: ((KuroToastState) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule(style: .continuous)
                .fill(Color.kuroBlack12)
                .frame(width: 40, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 14)

            QuickVerdictActionCard(
                media: media,
                onToast: onToast,
                onDone: { dismiss() }
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(Color.kuroBackground.ignoresSafeArea())
        .presentationDetents([.height(250), .medium])
        .presentationDragIndicator(.hidden)
    }
}

struct QuickVerdictPickerSheet: View {
    let media: any MediaDisplayable
    var onToast: ((KuroToastState) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(NetworkMonitor.self) private var networkMonitor

    @State private var isMutating = false
    @State private var errorMessage: String? = nil

    private var isGermanLocale: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("de") == true
    }

    private var entry: UserList? {
        supabaseService.userListEntry(mediaType: media.kind.rawValue, mediaId: media.id)
    }

    private var currentChoice: QuickVerdictChoice {
        quickVerdictChoice(for: entry)
    }

    private var availableChoices: [QuickVerdictChoice] {
        entry == nil ? [.masterpiece, .okay, .bad] : QuickVerdictChoice.allCases
    }

    private var completedProgress: Int {
        let total = media.episodes ?? media.chapters ?? 0
        return total > 0 ? total : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule(style: .continuous)
                .fill(Color.kuroBlack12)
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            Text(isGermanLocale ? "URTEIL" : "VERDICT")
                .font(.kuroMicro(weight: .medium))
                .tracking(1.6)
                .foregroundColor(.kuroTextTertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableChoices) { choice in
                        Button {
                            KuroAccessibility.impactHaptic(.light)
                            apply(choice)
                        } label: {
                            Text(choice.displayName(isGerman: isGermanLocale).uppercased())
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.0)
                                .foregroundColor(currentChoice == choice ? .white : .kuroBlack70)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(currentChoice == choice ? Color.kuroBlack : Color.kuroBlack06)
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(currentChoice == choice ? Color.kuroBlack : Color.kuroBlack12, lineWidth: 0.6)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isMutating)
                    }
                }
                .padding(.vertical, 1)
            }
            .kuroSwipeExclusionZone()

            Text(
                entry == nil
                    ? (isGermanLocale ? "Waehlt direkt dein Urteil und legt den Titel als fertig in deiner Liste an." : "Pick a verdict to add this title as completed immediately.")
                    : (isGermanLocale ? "Urteil sofort speichern." : "Save your verdict immediately.")
            )
            .font(.kuroMicro(weight: .light))
            .foregroundColor(.kuroTextTertiary)
            .lineLimit(2)

            if let errorMessage {
                Text(errorMessage)
                    .font(.kuroMicro(weight: .light))
                    .foregroundColor(.red.opacity(0.72))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(Color.kuroBackground.ignoresSafeArea())
        .presentationDetents([.height(188)])
        .presentationDragIndicator(.hidden)
    }

    private func apply(_ choice: QuickVerdictChoice) {
        guard networkMonitor.isConnected else {
            errorMessage = isGermanLocale ? "Du bist offline. Verbinde dich erneut, um dein Urteil zu speichern." : "You're offline. Reconnect to save your verdict."
            KuroAccessibility.errorHaptic()
            return
        }

        isMutating = true
        errorMessage = nil

        Task {
            var success = true

            if entry == nil {
                success = await supabaseService.addToList(
                    mediaId: media.id,
                    mediaType: media.kind.rawValue,
                    status: .completed
                )
                if success, completedProgress > 0 {
                    await supabaseService.setUserProgress(
                        mediaId: media.id,
                        mediaType: media.kind.rawValue,
                        progress: completedProgress
                    )
                    success = supabaseService.errorMessage?.isEmpty ?? true
                }
            }

            if success {
                await supabaseService.setUserVerdict(
                    mediaId: media.id,
                    mediaType: media.kind.rawValue,
                    verdict: choice.verdict
                )
                success = supabaseService.errorMessage?.isEmpty ?? true
            }

            await MainActor.run {
                isMutating = false
                if success {
                    KuroAccessibility.successHaptic()
                    onToast?(
                        .init(
                            kind: .success,
                            title: choice == .unsorted
                                ? (isGermanLocale ? "Urteil entfernt" : "Verdict cleared")
                                : (isGermanLocale ? "Urteil gespeichert" : "Verdict saved"),
                            subtitle: media.title,
                            actionTitle: nil,
                            onAction: nil
                        )
                    )
                    dismiss()
                } else {
                    KuroAccessibility.errorHaptic()
                    errorMessage = friendlyListMutationMessage(
                        supabaseService.errorMessage,
                        isGerman: isGermanLocale
                    )
                    onToast?(
                        .init(
                            kind: .error,
                            title: isGermanLocale ? "Urteil konnte nicht gespeichert werden" : "Couldn't save verdict",
                            subtitle: errorMessage,
                            actionTitle: nil,
                            onAction: nil
                        )
                    )
                }
            }
        }
    }
}

struct QuickVerdictTriggerButton: View {
    let media: any MediaDisplayable
    var action: () -> Void

    @Environment(SupabaseService.self) private var supabaseService
    private var isGermanLocale: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("de") == true
    }

    private var entry: UserList? {
        supabaseService.userListEntry(mediaType: media.kind.rawValue, mediaId: media.id)
    }

    var body: some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            action()
        } label: {
            HStack(spacing: 6) {
                Text(quickStatusCapsuleLabel(for: entry, mediaKind: media.kind, isGerman: isGermanLocale))
                    .font(.kuroMicro(weight: .medium))
                    .tracking(0.9)
                    .lineLimit(1)
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(.kuroBlack70)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.kuroBlack06)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.kuroBlack12, lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
    }
}
