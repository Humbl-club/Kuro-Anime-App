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

    private var progressUnitLabel: String {
        mediaType == "manga" ? "CHAPTERS" : "EPISODES"
    }

    private func statusLabel(_ status: ListStatus) -> String {
        if mediaType == "manga" {
            switch status {
            case .current: return "Reading"
            case .planning: return "Planned"
            case .completed: return "Completed"
            case .dropped: return "Dropped"
            case .paused: return "Paused"
            case .repeating: return "Rereading"
            }
        }
        return status.displayName
    }

    private var offlineMutationMessage: String {
        "You're offline. Reconnect to update your list."
    }

    private var mutationStatusMessage: String? {
        if !networkMonitor.isConnected { return offlineMutationMessage }
        return saveError
    }

    private var mutationStatusColor: Color {
        networkMonitor.isConnected ? .red : .kuroTextTertiary
    }

    private var scoreLabel: String {
        switch draft.score {
        case 1: return "SKIP"
        case 2: return "WEAK"
        case 3: return "FLAT"
        case 4: return "MEH"
        case 5: return "DECENT"
        case 6: return "GOOD"
        case 7: return "STANDOUT"
        case 8: return "MUST-SEE"
        case 9: return "BRILLIANT"
        case 10: return "CANON"
        default: return "TAP TO RATE"
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
                            unitLabel: progressUnitLabel
                        )

                        EditorialLayout.divider()
                            .padding(.horizontal, KuroSpacing.lg)
                    }

                    SpreadScoreSection(score: $draft.score, scoreLabel: scoreLabel)

                    EditorialLayout.divider()
                        .padding(.horizontal, KuroSpacing.lg)

                    SpreadNotesSection(notes: $draft.notes)

                    Color.clear.frame(height: KuroSpacing.xl)
                }
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                SpreadSaveDock(
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
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.black.opacity(0.35))
                        .clipShape(Circle())
                }
                .padding(.trailing, KuroSpacing.lg)
                .padding(.top, KuroSpacing.md)
            }
        }
        .background(Color.kuroBackground)
        .onAppear { actionScope.activate(session: libraryActions.accountSession) }
        .onDisappear { actionScope.deactivate(); isSaving = false }
        .task(id: EditorIdentity(media: media.libraryKey, origin: origin)) {
            guard actionScope.capture(session: libraryActions.accountSession) != nil, !Task.isCancelled else { return }
            // The Library projection is authoritative (kept current by the session refresh and
            // realtime hints): fill the editor from it without a network round trip.
            let entry = library.entry(for: media.libraryKey)
            isExistingEntry = entry != nil
            draft = TrackingDraft(entry: entry)
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
                saveError = friendlyListMutationMessage(error, isGerman: false)
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
                saveError = friendlyListMutationMessage(error, isGerman: false)
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

    private var metaText: String {
        var parts: [String] = [media.year]
        if let eps = media.episodes {
            parts.append("\(eps) EPISODES")
        } else if let chs = media.chapters {
            parts.append("\(chs) CHAPTERS")
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
                        .frame(width: containerWidth, height: 280)
                        .clipped()
                case .failure, .empty:
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.17), Color(white: 0.25), Color(white: 0.17)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                @unknown default:
                    EmptyView()
                }
            }

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.35),
                    .init(color: Color.black.opacity(0.7), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: KuroSpacing.xs) {
                Text(media.title)
                    .font(.kuroHeadline())
                    .foregroundColor(.white)
                    .lineLimit(2)

                Text(metaText)
                    .font(.kuroMicro(weight: .regular))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.65))
            }
            .padding(KuroSpacing.lg)
        }
        .frame(height: 280)
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
                Button {
                    selectedStatus = status
                    KuroAccessibility.impactHaptic(.light)
                } label: {
                    Text(statusLabel(status))
                        .font(.kuroMicro(weight: selectedStatus == status ? .medium : .regular))
                        .tracking(1.2)
                        .foregroundColor(selectedStatus == status ? .kuroBlack80 : .kuroTextTertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(selectedStatus == status ? Color.black.opacity(0.06) : Color.clear)
                        )
                        .overlay(
                            Capsule()
                                .stroke(
                                    selectedStatus == status ? Color.black.opacity(0.3) : Color.black.opacity(0.1),
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
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

    var body: some View {
        VStack(spacing: KuroSpacing.sm) {
            if isEditing {
                TextField("", value: $progress, format: .number)
                    .font(.system(size: 34, weight: .light, design: .serif))
                    .foregroundColor(.kuroBlack80)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 80)

                Button {
                    progress = min(max(0, progress), maxProgress)
                    isEditing = false
                } label: {
                    Text("DONE")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.5)
                        .foregroundColor(.kuroBlack80)
                        .padding(.horizontal, KuroSpacing.md)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.06))
                        .clipShape(Capsule())
                }
            } else {
                Button {
                    isEditing = true
                } label: {
                    Text("\(progress)")
                        .font(.system(size: 34, weight: .light, design: .serif))
                        .foregroundColor(.kuroBlack80)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Progress: \(progress) of \(maxProgress). Tap to edit.")
            }

            Text("OF \(maxProgress) \(unitLabel)")
                .font(.kuroMicro(weight: .medium))
                .tracking(1.5)
                .foregroundColor(.kuroTextTertiary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.08))
                        .frame(height: 2)
                    Capsule()
                        .fill(Color.black.opacity(0.5))
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
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.kuroTextSecondary)
                        .frame(width: 32, height: 32)
                        .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 1))
                }

                Button {
                    progress = min(maxProgress, progress + 1)
                    KuroAccessibility.impactHaptic(.light)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.kuroTextSecondary)
                        .frame(width: 32, height: 32)
                        .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 1))
                }
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

    var body: some View {
        VStack(spacing: KuroSpacing.sm) {
            Text(score > 0 ? "\(score)" : "—")
                .font(.system(size: 44, weight: .light, design: .serif))
                .foregroundColor(.kuroBlack80)
                .contentTransition(.numericText())
                .animation(KuroAnimation.fast, value: score)

            Text(scoreLabel)
                .font(.kuroMicro(weight: .medium))
                .tracking(2)
                .foregroundColor(.kuroTextSecondary)
                .animation(KuroAnimation.fast, value: score)

            HStack(spacing: 6) {
                ForEach(1...10, id: \.self) { dot in
                    Button {
                        if score == dot {
                            score = 0
                        } else {
                            score = dot
                        }
                        KuroAccessibility.impactHaptic(.light)
                    } label: {
                        Circle()
                            .fill(dot <= score ? Color.black.opacity(0.7) : Color.black.opacity(0.1))
                            .frame(width: 10, height: 10)
                            .animation(KuroAnimation.fast, value: score)
                    }
                }
            }
            .padding(.top, KuroSpacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, KuroSpacing.lg)
        .padding(.vertical, KuroSpacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Score: \(scoreLabel)")
    }
}

// MARK: - Notes Section (Pull-Quote)

private struct SpreadNotesSection: View {
    @Binding var notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.sm) {
            Text("YOUR TAKE")
                .font(.kuroMicro(weight: .medium))
                .tracking(1.8)
                .foregroundColor(.kuroTextTertiary)

            HStack(alignment: .top, spacing: KuroSpacing.md) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.black.opacity(0.15))
                    .frame(width: 2)

                ZStack(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("What would you tell a friend?")
                            .font(.system(size: 15, weight: .light, design: .serif))
                            .foregroundColor(.kuroTextTertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $notes)
                        .font(.system(size: 15, weight: .light, design: .serif))
                        .foregroundColor(.kuroBlack80)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 60)
                }
            }
        }
        .padding(.horizontal, KuroSpacing.lg)
        .padding(.vertical, KuroSpacing.lg)
    }
}

// MARK: - Pinned Save Dock

private struct SpreadSaveDock: View {
    let isExistingEntry: Bool
    let isSaving: Bool
    let isOffline: Bool
    var mutationMessage: String?
    var mutationColor: Color
    let onSave: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: KuroSpacing.sm) {
            Button(action: onSave) {
                Text(isExistingEntry ? "SAVE" : "ADD TO LIST")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.8)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.black.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: KuroRadius.sm))
            }
            .disabled(isSaving || isOffline)
            .opacity(isSaving || isOffline ? 0.4 : 1)

            if isExistingEntry {
                Button(action: onRemove) {
                    Text("REMOVE")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.5)
                        .foregroundColor(.red.opacity(0.65))
                }
                .disabled(isSaving || isOffline)
            }

            if let message = mutationMessage {
                Text(message)
                    .font(.kuroMicro(weight: .medium))
                    .tracking(0.8)
                    .foregroundColor(mutationColor)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, KuroSpacing.lg)
        .padding(.top, KuroSpacing.md)
        .padding(.bottom, KuroSpacing.md)
        .background(
            Rectangle()
                .fill(Color.kuroBackground.opacity(0.92))
                .ignoresSafeArea()
        )
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
        Text(title.uppercased())
            .font(.kuroMicro(weight: .medium))
            .tracking(1.0)
            .foregroundColor(verdict == nil ? .kuroTextSecondary : .kuroBlack80)
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
