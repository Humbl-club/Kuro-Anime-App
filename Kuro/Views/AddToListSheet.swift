import SwiftUI

// MARK: - Add To List Sheet

struct AddToListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(NetworkMonitor.self) private var networkMonitor
    let media: any MediaDisplayable
    @State private var selectedStatus: ListStatus = .planning
    @State private var progress: Int = 0
    @State private var score: Int = 0
    @State private var notes: String = ""
    @State private var isExistingEntry: Bool = false
    @State private var isSaving: Bool = false
    @State private var saveError: String? = nil

    private var mediaType: String {
        media.kind.rawValue
    }

    private var maxProgress: Int {
        let total = media.episodes ?? media.chapters ?? 0
        return max(0, total)
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

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: KuroDesignSpacing.adaptive(KuroSpacing.xl, for: geometry.size.width)) {
                        // Media Preview
                        MediaPreview(media: media)

                        // Status Selection
                        VStack(alignment: .leading, spacing: KuroSpacing.md) {
                            Text("STATUS")
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.5)
                                .foregroundColor(.kuroBlack80)

                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ],
                                spacing: KuroSpacing.md
                            ) {
                                ForEach(ListStatus.allCases, id: \.self) { status in
                                    StatusCard(
                                        status: status,
                                        isSelected: selectedStatus == status,
                                        label: statusLabel(status)
                                    ) {
                                        selectedStatus = status
                                        KuroAccessibility.impactHaptic(.light)
                                    }
                                }
                            }
                        }

                        // Progress
                        if (selectedStatus == .current || selectedStatus == .completed || selectedStatus == .repeating) && maxProgress > 0 {
                            VStack(alignment: .leading, spacing: KuroSpacing.md) {
                                Text("PROGRESS")
                                    .font(.kuroMicro(weight: .medium))
                                    .tracking(1.5)
                                    .foregroundColor(.kuroBlack80)

                                HStack {
                                    Stepper(value: $progress, in: 0...maxProgress) {
                                        Text("\(progress) / \(maxProgress)")
                                            .font(.kuroBody(weight: .light))
                                            .foregroundColor(.kuroBlack80)
                                    }
                                }
                                .padding(KuroSpacing.md)
                                .background(Color.kuroBlack08)
                                .cornerRadius(KuroRadius.sm)
                            }
                        }

                        // Score
                        VStack(alignment: .leading, spacing: KuroSpacing.md) {
                            Text("YOUR SCORE")
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.5)
                                .foregroundColor(.kuroBlack80)

                            HStack(spacing: KuroSpacing.sm) {
                                ForEach(1...10, id: \.self) { star in
                                    Button(action: {
                                        score = star
                                        KuroAccessibility.impactHaptic(.light)
                                    }) {
                                        Image(systemName: star <= score ? "star.fill" : "star")
                                            .font(.kuroBody())
                                            .foregroundColor(star <= score ? .kuroBlack : .kuroBlack30)
                                    }
                                }
                            }
                        }

                        // Notes
                        VStack(alignment: .leading, spacing: KuroSpacing.md) {
                            Text("NOTES")
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.5)
                                .foregroundColor(.kuroBlack80)

                            TextEditor(text: $notes)
                                .font(.kuroMicro(weight: .light))
                                .foregroundColor(.kuroBlack80)
                                .frame(height: 100)
                                .padding(KuroSpacing.sm)
                                .background(Color.kuroBlack08)
                                .cornerRadius(KuroRadius.sm)
                        }

                        // Save Button
                        Button(action: saveToList) {
                            Text(isExistingEntry ? "SAVE" : "ADD TO LIST")
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.5)
                                .foregroundColor(.kuroWhite)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, KuroSpacing.lg)
                                .background(Color.kuroBlack)
                                .cornerRadius(KuroRadius.sm)
                        }
                        .disabled(isSaving || !networkMonitor.isConnected)

                        if isExistingEntry {
                            Button(role: .destructive, action: removeFromList) {
                                Text("REMOVE FROM LIST")
                                    .font(.kuroMicro(weight: .medium))
                                    .tracking(1.5)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, KuroSpacing.lg)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isSaving || !networkMonitor.isConnected)
                        }

                        if let mutationStatusMessage {
                            Text(mutationStatusMessage)
                                .font(.kuroMicro(weight: networkMonitor.isConnected ? .light : .medium))
                                .tracking(networkMonitor.isConnected ? 0 : 1.0)
                                .foregroundColor(mutationStatusColor)
                                .multilineTextAlignment(.center)
                                .padding(.top, KuroSpacing.sm)
                        }
                    }
                    .padding(ResponsiveLayout.padding())
                }
            }
            .background(Color.kuroBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.kuroMicro(weight: .light))
                    .foregroundColor(.kuroBlack80)
                }
            }
        }
        .task(id: media.id) {
            // Ensure we have latest list state for pre-filling.
            await supabaseService.fetchUserLists()
            if let entry = supabaseService.userLists.first(where: { $0.mediaId == media.id && $0.mediaType.lowercased() == mediaType }) {
                isExistingEntry = true
                selectedStatus = entry.status
                progress = entry.progress
                score = (entry.score ?? 0) / 10
                notes = entry.notes ?? ""
            } else {
                isExistingEntry = false
                selectedStatus = .planning
                progress = 0
                score = 0
                notes = ""
            }
        }
        .onChange(of: networkMonitor.isConnected) { _, isConnected in
            if isConnected, saveError == offlineMutationMessage {
                saveError = nil
            }
        }
    }

    private func saveToList() {
        guard networkMonitor.isConnected else {
            saveError = offlineMutationMessage
            return
        }
        saveError = nil
        isSaving = true

        // If user marks as completed and hasn't set progress, default progress to the end when we know totals.
        let finalProgress: Int
        if selectedStatus == .completed && maxProgress > 0 && progress == 0 {
            finalProgress = maxProgress
        } else {
            finalProgress = progress
        }

        let rating: Int? = score > 0 ? score : nil
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesValue: String? = trimmedNotes.isEmpty ? nil : trimmedNotes

        Task {
            await supabaseService.upsertUserListEntry(
                mediaId: media.id,
                mediaType: mediaType,
                status: selectedStatus,
                progress: finalProgress,
                rating: rating,
                notes: notesValue
            )
            await MainActor.run {
                isSaving = false
                if let msg = supabaseService.errorMessage, !msg.isEmpty {
                    saveError = msg
                    return
                }
                KuroAccessibility.successHaptic()
                dismiss()
            }
        }
    }

    private func removeFromList() {
        guard networkMonitor.isConnected else {
            saveError = offlineMutationMessage
            return
        }
        saveError = nil
        isSaving = true
        Task {
            await supabaseService.removeFromList(mediaId: media.id, mediaType: mediaType)
            await MainActor.run {
                isSaving = false
                if let msg = supabaseService.errorMessage, !msg.isEmpty {
                    saveError = msg
                    return
                }
                KuroAccessibility.successHaptic()
                dismiss()
            }
        }
    }
}

// MARK: - Media Preview

struct MediaPreview: View {
    let media: any MediaDisplayable

    var body: some View {
        HStack(spacing: KuroSpacing.md) {
            KuroCachedAsyncImage(url: URL(string: media.imageURL ?? ""), maxPixelSize: 260) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.kuroBlack08)
            }
            .frame(width: 80, height: 120)
            .clipped()
            .cornerRadius(KuroRadius.sm)

            VStack(alignment: .leading, spacing: KuroSpacing.xs) {
                Text(media.title.uppercased())
                    .font(.kuroBody(weight: .medium))
                    .tracking(0.5)
                    .foregroundColor(.kuroBlack)
                    .lineLimit(2)

                Text(media.year)
                    .font(.kuroMicro(weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.kuroBlack60)

                if let episodes = media.episodes {
                    Text("\(episodes) EPISODES")
                        .font(.kuroMicro(weight: .light))
                        .tracking(0.5)
                        .foregroundColor(.kuroBlack60)
                } else if let chapters = media.chapters {
                    Text("\(chapters) CHAPTERS")
                        .font(.kuroMicro(weight: .light))
                        .tracking(0.5)
                        .foregroundColor(.kuroBlack60)
                }
            }

            Spacer()
        }
        .padding(KuroSpacing.md)
        .background(Color.kuroBlack08)
        .cornerRadius(KuroRadius.sm)
    }
}

// MARK: - Status Card

struct StatusCard: View {
    let status: ListStatus
    let isSelected: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: KuroSpacing.sm) {
                Image(systemName: statusIcon)
                    .font(.kuroCardTitle())
                    .foregroundColor(isSelected ? .kuroBlack : .kuroBlack30)

                Text(label.uppercased())
                    .font(.kuroMicro(weight: isSelected ? .medium : .light))
                    .tracking(0.5)
                    .foregroundColor(isSelected ? .kuroBlack : .kuroBlack60)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, KuroSpacing.lg)
            .background(isSelected ? Color.kuroBlack08 : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: KuroRadius.sm)
                    .stroke(isSelected ? Color.kuroBlack : Color.kuroBlack.opacity(0.15), lineWidth: 1)
            )
            .cornerRadius(KuroRadius.sm)
        }
    }

    private var statusIcon: String {
        switch status {
        case .current: return "play.circle.fill"
        case .planning: return "clock.fill"
        case .completed: return "checkmark.circle.fill"
        case .dropped: return "xmark.circle.fill"
        case .paused: return "pause.circle.fill"
        case .repeating: return "arrow.clockwise.circle.fill"
        }
    }
}
