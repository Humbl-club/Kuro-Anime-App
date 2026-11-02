import KuroCore
import KuroLibrary
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

func quickVerdictChoice(for entry: LibraryEntry?) -> QuickVerdictChoice {
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

func quickStatusCapsuleLabel(for entry: LibraryEntry?, mediaKind: MediaKind, isGerman: Bool) -> String {
    guard let entry else { return isGerman ? "HINZUFUEGEN" : "ADD" }
    let base = quickStatusLabel(for: entry.status, mediaKind: mediaKind, isGerman: isGerman).uppercased()
    let verdict = quickVerdictChoice(for: entry)
    return verdict == .unsorted ? base : "\(base) · \(verdict.displayName(isGerman: isGerman).uppercased())"
}

/// User-facing copy for a failed Library write, by typed error.
func friendlyListMutationMessage(_ error: LibraryError, isGerman: Bool) -> String {
    switch error {
    case .notAuthenticated:
        return isGerman ? "Du bist abgemeldet. Melde dich an und versuch es erneut." : "You're signed out. Sign in and try again."
    case .notFound:
        return isGerman ? "Dieser Titel ist nicht mehr in deiner Liste." : "This title is no longer in your list."
    case .invalidValue:
        return isGerman ? "Speichern fehlgeschlagen. Versuch es erneut." : "Couldn't save your changes. Try again."
    case .conflict:
        return isGerman ? "Dieser Eintrag wurde woanders geaendert. Versuch es erneut." : "This entry changed elsewhere. Try again."
    case .retryable:
        return isGerman ? "Deine Liste konnte gerade nicht aktualisiert werden. Versuch es erneut." : "Couldn't update your list right now. Try again."
    case .unavailable:
        return isGerman ? "Deine Liste konnte nicht aktualisiert werden." : "Couldn't update your list."
    }
}

struct QuickVerdictActionCard: View {
    let media: any MediaDisplayable
    var onToast: ((KuroToastState) -> Void)? = nil
    var onDone: (() -> Void)? = nil

    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @State private var actionScope = AccountActionScope()
    @Environment(NetworkMonitor.self) private var networkMonitor

    @State private var showAdvancedEdit = false
    @State private var showVerdictOptions = false
    @State private var isMutating = false
    @State private var mutationMessage: String? = nil
    private var isGermanLocale: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("de") == true
    }

    private let quickStatuses: [ListStatus] = [.planning, .current, .completed, .paused, .dropped]

    private var entry: LibraryEntry? {
        library.entry(for: media.libraryKey)
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
        let origin = actionScope.capture(session: libraryActions.accountSession)
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
                    KuroBusyMark(width: 24)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(KuroLocale.text("Saving", "Wird gespeichert"))
                }
            }

            actionSectionTitle(isGermanLocale ? "STATUS" : "STATUS")
            chipScroller {
                ForEach(quickStatuses, id: \.self) { status in
                    quickChip(
                        title: quickStatusLabel(for: status, mediaKind: media.kind, isGerman: isGermanLocale).uppercased(),
                        isSelected: currentStatus == status,
                        action: { applyStatus(status, origin: origin) }
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
                            action: { applyVerdict(verdict, origin: origin) }
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
                        removeFromList(origin: origin)
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
        .onAppear { actionScope.activate(session: libraryActions.accountSession) }
        .onDisappear { actionScope.deactivate() }
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

    /// Status chip: changes the status (plus the completion progress when completing a title with a
    /// known total); progress otherwise, rating, notes and verdict stay as stored.
    private func applyStatus(_ status: ListStatus, origin: AccountActionScope.Ticket?) {
        guard actionScope.isCurrent(origin, session: libraryActions.accountSession) else { return }
        mutate(
            origin: origin,
            statusEdit(to: status),
            createIfMissing: status,
            successTitle: isGermanLocale ? "Status aktualisiert" : "Status updated"
        )
    }

    private func applyVerdict(_ verdict: QuickVerdictChoice, origin: AccountActionScope.Ticket?) {
        guard actionScope.isCurrent(origin, session: libraryActions.accountSession) else { return }
        let verdictChange: FieldChange<Verdict> = verdict.verdict.map { .set($0) } ?? .clear
        let successTitle = verdict == .unsorted
            ? (isGermanLocale ? "Urteil entfernt" : "Verdict cleared")
            : (isGermanLocale ? "Urteil gespeichert" : "Verdict saved")

        guard entry != nil else {
            // Not tracked yet: a verdict adds the title as completed, in one write.
            var edit = statusEdit(to: .completed)
            edit.verdict = verdictChange
            mutate(
                origin: origin,
                edit,
                createIfMissing: .completed,
                successTitle: isGermanLocale ? "Status aktualisiert" : "Status updated"
            )
            return
        }

        // Tracked: only the verdict changes; a title removed meanwhile is not recreated.
        mutate(origin: origin, LibraryEdit(verdict: verdictChange), createIfMissing: nil, successTitle: successTitle)
    }

    private func removeFromList(origin: AccountActionScope.Ticket?) {
        guard actionScope.isCurrent(origin, session: libraryActions.accountSession) else { return }
        guard !isOffline else {
            mutationMessage = isGermanLocale ? "Du bist offline. Verbinde dich erneut, um deine Liste zu aktualisieren." : "You're offline. Reconnect to update your list."
            KuroAccessibility.errorHaptic()
            return
        }

        isMutating = true
        mutationMessage = nil
        let key = media.libraryKey

        actionScope.launch(origin: origin, session: libraryActions.accountSession) { ticket in
            let outcome = await libraryActions.remove(key)
            guard actionScope.isCurrent(ticket, session: libraryActions.accountSession) else { return }
            isMutating = false
            if let error = outcome.error {
                mutationMessage = friendlyListMutationMessage(error, isGerman: isGermanLocale)
                emitErrorToast()
                return
            }
            KuroAccessibility.successHaptic()
            emitSuccessToast(
                title: isGermanLocale ? "Aus Liste entfernt" : "Removed from list",
                subtitle: media.title
            )
            onDone?()
        }
    }

    /// One Library edit naming only the fields the action changes; success and failure come from
    /// that write's own outcome.
    private func mutate(origin: AccountActionScope.Ticket?, _ edit: LibraryEdit, createIfMissing: ListStatus?, successTitle: String) {
        guard actionScope.isCurrent(origin, session: libraryActions.accountSession) else { return }
        guard !isOffline else {
            mutationMessage = isGermanLocale ? "Du bist offline. Verbinde dich erneut, um deine Liste zu aktualisieren." : "You're offline. Reconnect to update your list."
            KuroAccessibility.errorHaptic()
            return
        }

        isMutating = true
        mutationMessage = nil
        let key = media.libraryKey

        actionScope.launch(origin: origin, session: libraryActions.accountSession) { ticket in
            let outcome = await libraryActions.apply(edit, to: key, createIfMissing: createIfMissing)
            guard actionScope.isCurrent(ticket, session: libraryActions.accountSession) else { return }
            isMutating = false
            if let error = outcome.error {
                mutationMessage = friendlyListMutationMessage(error, isGerman: isGermanLocale)
                emitErrorToast()
                return
            }
            KuroAccessibility.successHaptic()
            emitSuccessToast(title: successTitle, subtitle: media.title)
            onDone?()
        }
    }

    private func statusEdit(to status: ListStatus) -> LibraryEdit {
        QuickStatusChange.edit(
            to: status,
            currentProgress: entry?.progress,
            total: media.episodes ?? media.chapters ?? 0
        )
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
            // N8: the system grabber is visible and Cancel closes the sheet (back to its page).
            HStack {
                Spacer(minLength: 0)
                QuickVerdictCancelButton { dismiss() }
            }
            .padding(.top, 14)

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
        .presentationDetents([.height(290), .medium])
        .presentationDragIndicator(.visible)
    }
}

/// The verdict sheets' Cancel (N8): every sheet has a visible close control, never swipe-down alone.
private struct QuickVerdictCancelButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(KuroLocale.text("Cancel", "Abbrechen"))
                .font(.kuroBody(weight: .regular))
                .foregroundStyle(Color.kuroInk)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct QuickVerdictPickerSheet: View {
    let media: any MediaDisplayable
    var onToast: ((KuroToastState) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @State private var actionScope = AccountActionScope()
    @Environment(NetworkMonitor.self) private var networkMonitor

    @State private var isMutating = false
    @State private var errorMessage: String? = nil

    private var isGermanLocale: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("de") == true
    }

    private var entry: LibraryEntry? {
        library.entry(for: media.libraryKey)
    }

    private var currentChoice: QuickVerdictChoice {
        quickVerdictChoice(for: entry)
    }

    private var availableChoices: [QuickVerdictChoice] {
        entry == nil ? [.masterpiece, .okay, .bad] : QuickVerdictChoice.allCases
    }

    var body: some View {
        let origin = actionScope.capture(session: libraryActions.accountSession)
        VStack(alignment: .leading, spacing: 16) {
            // N8: the system grabber is visible and Cancel closes the sheet (back to its page).
            HStack(alignment: .center) {
                Text(isGermanLocale ? "URTEIL" : "VERDICT")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.6)
                    .foregroundColor(.kuroTextTertiary)
                Spacer(minLength: 0)
                QuickVerdictCancelButton { dismiss() }
            }
            .padding(.top, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableChoices) { choice in
                        Button {
                            KuroAccessibility.impactHaptic(.light)
                            apply(choice, origin: origin)
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
        .onAppear { actionScope.activate(session: libraryActions.accountSession) }
        .onDisappear { actionScope.deactivate() }
        .presentationDetents([.height(220)])
        .presentationDragIndicator(.visible)
    }

    private func apply(_ choice: QuickVerdictChoice, origin: AccountActionScope.Ticket?) {
        guard actionScope.isCurrent(origin, session: libraryActions.accountSession) else { return }
        guard networkMonitor.isConnected else {
            errorMessage = isGermanLocale ? "Du bist offline. Verbinde dich erneut, um dein Urteil zu speichern." : "You're offline. Reconnect to save your verdict."
            KuroAccessibility.errorHaptic()
            return
        }

        isMutating = true
        errorMessage = nil

        // ONE write: a title that is not tracked yet is added as completed (all known
        // episodes/chapters) with the verdict; a tracked title changes only its verdict.
        let verdictChange: FieldChange<Verdict> = choice.verdict.map { .set($0) } ?? .clear
        let edit: LibraryEdit
        let createIfMissing: ListStatus?
        if entry == nil {
            var completing = QuickStatusChange.edit(
                to: .completed,
                currentProgress: nil,
                total: media.episodes ?? media.chapters ?? 0
            )
            completing.verdict = verdictChange
            edit = completing
            createIfMissing = .completed
        } else {
            edit = LibraryEdit(verdict: verdictChange)
            createIfMissing = nil
        }
        let key = media.libraryKey

        actionScope.launch(origin: origin, session: libraryActions.accountSession) { ticket in
            let outcome = await libraryActions.apply(edit, to: key, createIfMissing: createIfMissing)
            guard actionScope.isCurrent(ticket, session: libraryActions.accountSession) else { return }
            isMutating = false
            if let error = outcome.error {
                KuroAccessibility.errorHaptic()
                errorMessage = friendlyListMutationMessage(error, isGerman: isGermanLocale)
                onToast?(
                    .init(
                        kind: .error,
                        title: isGermanLocale ? "Urteil konnte nicht gespeichert werden" : "Couldn't save verdict",
                        subtitle: errorMessage,
                        actionTitle: nil,
                        onAction: nil
                    )
                )
                return
            }
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
        }
    }
}

struct QuickVerdictTriggerButton: View {
    let media: any MediaDisplayable
    var action: () -> Void

    @Environment(LibraryStore.self) private var library
    private var isGermanLocale: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("de") == true
    }

    private var entry: LibraryEntry? {
        library.entry(for: media.libraryKey)
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
