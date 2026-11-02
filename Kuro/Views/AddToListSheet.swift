import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Add To List Sheet

struct AddToListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @Environment(NetworkMonitor.self) private var networkMonitor
    @State private var actionScope = AccountActionScope()
    let media: any MediaDisplayable
    /// Status, progress, score (1...10, 0 = unrated) and notes as the editor shows them.
    @State private var draft = TrackingDraft(entry: nil)
    /// The draft as the editor was filled: anything else is unsaved input (N7).
    @State private var baseline = TrackingDraft(entry: nil)
    @State private var confirmDiscard = false
    @State private var isEditingProgress = false
    @State private var isExistingEntry: Bool = false
    @State private var isSaving: Bool = false
    @State private var saveError: String? = nil

    private struct EditorIdentity: Equatable {
        let media: MediaKey
        let origin: AccountActionScope.Ticket?
    }

    private var mediaType: String {
        media.kind.rawValue
    }

    private var maxProgress: Int {
        let total = media.episodes ?? media.chapters ?? 0
        return max(0, total)
    }

    private var showsProgress: Bool {
        (draft.status == .current || draft.status == .completed || draft.status == .repeating) && maxProgress > 0
    }

    private var german: Bool { KuroLocale.isGerman }

    private var progressUnitLabel: String {
        switch (mediaType == "manga", german) {
        case (true, false): return "chapters"
        case (true, true): return "Kapiteln"
        case (false, false): return "episodes"
        case (false, true): return "Folgen"
        }
    }

    private func statusLabel(_ status: ListStatus) -> String {
        if status == .repeating {
            switch (media.kind, german) {
            case (.manga, false): return "Rereading"
            case (.manga, true): return "Lese ich erneut"
            case (.anime, false): return "Rewatching"
            case (.anime, true): return "Schaue ich erneut"
            }
        }
        return FolioStatus(listStatus: status).title(medium: media.kind, german: german)
    }

    private var offlineMutationMessage: String {
        german ? "Du bist offline. Verbinde dich, um deine Liste zu ändern." : "You're offline. Reconnect to update your list."
    }

    private var mutationStatusMessage: String? {
        if !networkMonitor.isConnected { return offlineMutationMessage }
        return saveError
    }

    private var mutationStatusColor: Color {
        networkMonitor.isConnected ? .kuroDestructiveInk : .kuroInkSecondary
    }

    private var scoreLabel: String {
        AddToListCopy.scoreWord(draft.score, german: german)
    }

    /// Unsaved input (N7): swipe-down is blocked and ✕ asks "Discard changes?" first.
    private var isDirty: Bool { draft.hasChanges(from: baseline) }

    /// ✕ / Cancel: a clean editor closes; unsaved input asks first.
    private func cancel() {
        switch KuroDiscardGuard.cancelStep(isDirty: isDirty) {
        case .close: dismiss()
        case .confirm: confirmDiscard = true
        }
    }

    var body: some View {
        let origin = actionScope.capture(session: libraryActions.accountSession)
        return GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    SpreadHeroSection(media: media, containerWidth: geometry.size.width)

                    SpreadStatusRow(
                        selectedStatus: $draft.status,
                        mediaType: mediaType,
                        statusLabel: statusLabel
                    )

                    EditorialLayout.divider()
                        .padding(.horizontal, KuroSpacing.lg)

                    if showsProgress {
                        SpreadProgressSection(
                            progress: $draft.progress,
                            isEditing: $isEditingProgress,
                            maxProgress: maxProgress,
                            unitLabel: progressUnitLabel,
                            german: german
                        )

                        EditorialLayout.divider()
                            .padding(.horizontal, KuroSpacing.lg)
                    }

                    SpreadScoreSection(score: $draft.score, scoreLabel: scoreLabel, german: german)

                    EditorialLayout.divider()
                        .padding(.horizontal, KuroSpacing.lg)

                    SpreadNotesSection(notes: $draft.notes, german: german)

                    Color.clear.frame(height: KuroSpacing.xl)
                }
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                SpreadSaveDock(
                    german: german,
                    isExistingEntry: isExistingEntry,
                    isSaving: isSaving,
                    isOffline: !networkMonitor.isConnected,
                    mutationMessage: mutationStatusMessage,
                    mutationColor: mutationStatusColor,
                    onSave: { saveToList(origin: origin) },
                    onRemove: { removeFromList(origin: origin) }
                )
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    KuroAccessibility.impactHaptic(.light)
                    cancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.kuroCustom(15, weight: .medium, relativeTo: .body, maxSize: 22))
                        .foregroundStyle(Color.kuroInk)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.kuroWhite).overlay(Circle().strokeBorder(Color.kuroHairline, lineWidth: 0.5)))
                }
                .buttonStyle(KuroPressStyle())
                .accessibilityLabel(german ? "Schließen" : "Close")
                .padding(.trailing, 12)
                .padding(.top, 12)
            }
        }
        .background(Color.kuroCanvasPage)
        .presentationDragIndicator(.visible)
        .kuroDiscardGuard(isDirty: isDirty, isBusy: isSaving, isConfirming: $confirmDiscard) { dismiss() }
        .onAppear { actionScope.activate(session: libraryActions.accountSession) }
        .onDisappear { actionScope.deactivate(); isSaving = false }
        .task(id: EditorIdentity(media: media.libraryKey, origin: origin)) {
            guard actionScope.capture(session: libraryActions.accountSession) != nil, !Task.isCancelled else { return }
            // The Library projection is authoritative (kept current by the session refresh and
            // realtime hints): fill the editor from it without a network round trip.
            let entry = library.entry(for: media.libraryKey)
            isExistingEntry = entry != nil
            draft = TrackingDraft(entry: entry)
            baseline = draft
        }
        .onChange(of: networkMonitor.isConnected) { _, isConnected in
            if isConnected, saveError == offlineMutationMessage {
                saveError = nil
            }
        }
    }

    private func saveToList(origin: AccountActionScope.Ticket?) {
        guard actionScope.isCurrent(origin, session: libraryActions.accountSession) else { return }
        guard networkMonitor.isConnected else {
            saveError = offlineMutationMessage
            return
        }
        saveError = nil
        isSaving = true

        // One explicit edit of what the editor shows; the verdict is left as stored.
        let key = media.libraryKey
        let edit = draft.edit(maxProgress: maxProgress)
        let createIfMissing = draft.createIfMissing

        actionScope.launch(origin: origin, session: libraryActions.accountSession) { ticket in
            let outcome = await libraryActions.apply(edit, to: key, createIfMissing: createIfMissing)
            guard actionScope.isCurrent(ticket, session: libraryActions.accountSession) else { return }
            isSaving = false
            if let error = outcome.error {
                saveError = friendlyListMutationMessage(error, isGerman: german)
                return
            }
            KuroAccessibility.successHaptic()
            dismiss()
        }
    }

    private func removeFromList(origin: AccountActionScope.Ticket?) {
        guard actionScope.isCurrent(origin, session: libraryActions.accountSession) else { return }
        guard networkMonitor.isConnected else {
            saveError = offlineMutationMessage
            return
        }
        saveError = nil
        isSaving = true
        let key = media.libraryKey
        actionScope.launch(origin: origin, session: libraryActions.accountSession) { ticket in
            let outcome = await libraryActions.remove(key)
            guard actionScope.isCurrent(ticket, session: libraryActions.accountSession) else { return }
            isSaving = false
            if let error = outcome.error {
                saveError = friendlyListMutationMessage(error, isGerman: german)
                return
            }
            KuroAccessibility.successHaptic()
            dismiss()
        }
    }
}

// MARK: - Hero Section

private struct SpreadHeroSection: View {
    let media: any MediaDisplayable
    let containerWidth: CGFloat

    private var heroHeight: CGFloat { min(300, max(200, floor(containerWidth * 0.66))) }

    private var metaText: String {
        let german = KuroLocale.isGerman
        var parts: [String] = media.year.isEmpty ? [] : [media.year]
        if let eps = media.episodes, eps > 0 {
            parts.append(german ? "\(eps) Folgen" : "\(eps) episodes")
        } else if let chs = media.chapters, chs > 0 {
            parts.append(german ? "\(chs) Kapitel" : "\(chs) chapters")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            KuroCachedAsyncImage(url: URL(string: media.imageURL ?? ""), maxPixelSize: 1100) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: containerWidth, height: heroHeight)
                        .clipped()
                case .failure, .empty:
                    Rectangle()
                        .fill(Color.kuroInk)
                @unknown default:
                    EmptyView()
                }
            }
            .accessibilityHidden(true)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.35),
                    .init(color: Color.kuroInk.opacity(0.78), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: KuroSpacing.xs) {
                Text(media.title)
                    .font(.kuroHeadline())
                    .foregroundStyle(Color.kuroWhite)
                    .lineLimit(3)
                    .accessibilityAddTraits(.isHeader)

                if !metaText.isEmpty {
                    Text(metaText)
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroWhite.opacity(0.85))
                }
            }
            .padding(.horizontal, KuroDesignSpacing.padding)
            .padding(.bottom, KuroSpacing.lg)
            .padding(.trailing, 44)
        }
        .frame(height: heroHeight)
        .clipped()
    }
}

// MARK: - Status Pill Row

private struct SpreadStatusRow: View {
    @Binding var selectedStatus: ListStatus
    let mediaType: String
    let statusLabel: (ListStatus) -> String

    var body: some View {
        FlowLayout(spacing: KuroSpacing.sm) {
            ForEach(ListStatus.allCases, id: \.self) { status in
                let selected = selectedStatus == status
                Button {
                    selectedStatus = status
                    KuroAccessibility.impactHaptic(.light)
                } label: {
                    Text(statusLabel(status))
                        .font(.kuroMeta(weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.kuroWhite : Color.kuroInk)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(selected ? Color.kuroInk : Color.clear))
                        .overlay(Capsule().strokeBorder(selected ? Color.kuroInk : Color.kuroKeyRim, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(KuroPressStyle())
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, KuroSpacing.lg)
        .padding(.vertical, KuroSpacing.lg)
    }
}

// MARK: - Progress Section

private struct SpreadProgressSection: View {
    @Binding var progress: Int
    @Binding var isEditing: Bool
    let maxProgress: Int
    let unitLabel: String
    let german: Bool
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: KuroSpacing.sm) {
            if isEditing {
                TextField("", value: $progress, format: .number)
                    .font(.kuroCustom(34, weight: .light, design: .serif, relativeTo: .largeTitle, maxSize: 56))
                    .foregroundStyle(Color.kuroInk)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 80)
                    .fixedSize()
                    .focused($fieldFocused)
                    .onAppear { fieldFocused = true }
                    .accessibilityLabel(german ? "Fortschritt" : "Progress")

                Button {
                    progress = min(max(0, progress), maxProgress)
                    isEditing = false
                } label: {
                    Text(german ? "Fertig" : "Done")
                        .font(.kuroMeta(weight: .semibold))
                        .foregroundStyle(Color.kuroInk)
                        .padding(.horizontal, KuroSpacing.md)
                        .frame(minHeight: 44)
                        .overlay(Capsule().strokeBorder(Color.kuroKeyRim, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(KuroPressStyle())
            } else {
                Button {
                    isEditing = true
                } label: {
                    Text("\(progress)")
                        .font(.kuroCustom(34, weight: .light, design: .serif, relativeTo: .largeTitle, maxSize: 56))
                        .foregroundStyle(Color.kuroInk)
                        .monospacedDigit()
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(german ? "Fortschritt: \(progress) von \(maxProgress)" : "Progress: \(progress) of \(maxProgress)")
                .accessibilityHint(german ? "Zum Eingeben tippen" : "Tap to type a number")
            }

            Text(german ? "von \(maxProgress) \(unitLabel)" : "of \(maxProgress) \(unitLabel)")
                .font(.kuroMeta())
                .foregroundStyle(Color.kuroInkSecondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.kuroHairline)
                        .frame(height: 2)
                    Capsule()
                        .fill(Color.kuroInk)
                        .frame(
                            width: maxProgress > 0
                                ? geo.size.width * CGFloat(min(progress, maxProgress)) / CGFloat(maxProgress)
                                : 0,
                            height: 2
                        )
                        .animation(KuroAnimation.fast, value: progress)
                }
            }
            .frame(height: 2)
            .padding(.horizontal, KuroSpacing.xxl)

            HStack(spacing: KuroSpacing.xxl) {
                Button {
                    progress = max(0, progress - 1)
                    KuroAccessibility.impactHaptic(.light)
                } label: {
                    Image(systemName: "minus")
                        .font(.kuroCustom(15, weight: .medium, relativeTo: .body, maxSize: 22))
                        .foregroundStyle(Color.kuroInk)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().strokeBorder(Color.kuroKeyRim, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(KuroPressStyle())
                .disabled(progress <= 0)
                .accessibilityLabel(german ? "Eins weniger" : "One less")

                Button {
                    progress = min(maxProgress, progress + 1)
                    KuroAccessibility.impactHaptic(.light)
                } label: {
                    Image(systemName: "plus")
                        .font(.kuroCustom(15, weight: .medium, relativeTo: .body, maxSize: 22))
                        .foregroundStyle(Color.kuroInk)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().strokeBorder(Color.kuroKeyRim, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(KuroPressStyle())
                .disabled(progress >= maxProgress)
                .accessibilityLabel(german ? "Eins mehr" : "One more")
            }
            .padding(.top, KuroSpacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, KuroSpacing.lg)
        .padding(.vertical, KuroSpacing.lg)
    }
}

// MARK: - Score Section

private struct SpreadScoreSection: View {
    @Binding var score: Int
    let scoreLabel: String
    let german: Bool

    var body: some View {
        VStack(spacing: KuroSpacing.sm) {
            Text(score > 0 ? "\(score)" : "—")
                .font(.kuroCustom(44, weight: .light, design: .serif, relativeTo: .largeTitle, maxSize: 64))
                .foregroundStyle(Color.kuroInk)
                .contentTransition(.numericText())
                .kuroAnimation(KuroMotion.contact, value: score)

            Text(scoreLabel)
                .font(.kuroMeta(weight: .medium))
                .foregroundStyle(Color.kuroInkSecondary)

            // Ten dots in two rows of five, each a full 44 x 44 pt target (220 pt wide, fits 320 pt);
            // VoiceOver adjusts the score as one control instead.
            VStack(spacing: 0) {
                ForEach([1, 6], id: \.self) { first in
                    HStack(spacing: 0) {
                        ForEach(first..<(first + 5), id: \.self) { dot in
                            Button {
                                score = score == dot ? 0 : dot
                                KuroAccessibility.impactHaptic(.light)
                            } label: {
                                Circle()
                                    .fill(dot <= score ? Color.kuroInk : Color.kuroHairline)
                                    .frame(width: 10, height: 10)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, KuroSpacing.lg)
        .padding(.vertical, KuroSpacing.lg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(german ? "Wertung" : "Score")
        .accessibilityValue(score > 0 ? "\(score), \(scoreLabel)" : scoreLabel)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: score = min(10, score + 1)
            case .decrement: score = max(0, score - 1)
            @unknown default: break
            }
        }
    }
}

// MARK: - Notes Section (Pull-Quote)

private struct SpreadNotesSection: View {
    @Binding var notes: String
    let german: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.sm) {
            Text(german ? "Deine Notiz" : "Your take")
                .font(.kuroTitle())
                .foregroundStyle(Color.kuroInk)
                .accessibilityAddTraits(.isHeader)

            HStack(alignment: .top, spacing: KuroSpacing.md) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.kuroKeyRim)
                    .frame(width: 2)
                    .accessibilityHidden(true)

                ZStack(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text(german ? "Was würdest du einer Freundin oder einem Freund erzählen?" : "What would you tell a friend?")
                            .font(.kuroCustom(15, weight: .light, design: .serif, relativeTo: .body))
                            .foregroundStyle(Color.kuroInkQuiet)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }

                    TextEditor(text: $notes)
                        .font(.kuroCustom(15, weight: .light, design: .serif, relativeTo: .body))
                        .foregroundStyle(Color.kuroInk)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 60)
                        .accessibilityLabel(german ? "Notiz" : "Note")
                }
            }
        }
        .padding(.horizontal, KuroSpacing.lg)
        .padding(.vertical, KuroSpacing.lg)
    }
}

// MARK: - Pinned Save Dock

private struct SpreadSaveDock: View {
    let german: Bool
    let isExistingEntry: Bool
    let isSaving: Bool
    let isOffline: Bool
    var mutationMessage: String?
    var mutationColor: Color
    let onSave: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: KuroSpacing.xs) {
            KuroInkButton(isExistingEntry ? (german ? "Sichern" : "Save") : (german ? "Zur Liste hinzufügen" : "Add to list"),
                          isLoading: isSaving, action: onSave)
                .disabled(isSaving || isOffline)
                .opacity(isOffline ? 0.45 : 1)

            if isExistingEntry {
                Button(action: onRemove) {
                    Text(german ? "Aus der Liste entfernen" : "Remove from list")
                        .font(.kuroMeta(weight: .medium))
                        .foregroundStyle(Color.kuroDestructiveInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(KuroPressStyle())
                .disabled(isSaving || isOffline)
                .opacity(isSaving || isOffline ? 0.45 : 1)
            }

            if let message = mutationMessage {
                Text(message)
                    .font(.kuroMeta(weight: .medium))
                    .foregroundStyle(mutationColor)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, KuroDesignSpacing.padding)
        .padding(.top, KuroSpacing.md)
        .padding(.bottom, KuroSpacing.sm)
        .background(
            Color.kuroCanvasPage
                .overlay(alignment: .top) { Rectangle().fill(Color.kuroHairline).frame(height: 0.5) }
                .ignoresSafeArea()
        )
    }
}

// MARK: - Copy

/// EN/DE words of the tracking editor (pure).
enum AddToListCopy {
    static func scoreWord(_ score: Int, german: Bool) -> String {
        let english = ["Tap to rate", "Skip", "Weak", "Flat", "Meh", "Decent", "Good", "Standout", "Must-see", "Brilliant", "Canon"]
        let deutsch = ["Zum Bewerten tippen", "Auslassen", "Schwach", "Flach", "Naja", "Ordentlich", "Gut", "Herausragend", "Pflicht", "Brillant", "Kanon"]
        let index = (1...10).contains(score) ? score : 0
        return german ? deutsch[index] : english[index]
    }
}

// MARK: - Quick List Actions

struct QuickVerdictBadge: View {
    let verdict: Verdict?
    let isGermanLocale: Bool

    private var title: String {
        guard let verdict else { return isGermanLocale ? "Ohne Urteil" : "Unsorted" }
        return isGermanLocale ? verdict.displayNameDE : verdict.displayName
    }

    var body: some View {
        Text(title)
            .font(.kuroMeta(weight: .medium))
            .foregroundStyle(verdict == nil ? Color.kuroInkSecondary : Color.kuroInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(verdict == nil ? Color.kuroBlack04 : Color.kuroBlack08)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(verdict == nil ? Color.kuroBlack10 : Color.kuroBlack20, lineWidth: 0.8)
            )
    }
}
