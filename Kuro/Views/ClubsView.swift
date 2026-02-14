// MARK: - CLUBS VIEW (Main Clubs Page)
// Entry point for the Clubs section (6th page in the swipe pager).
// Shows joined clubs, create/join flows, and empty state.

import SwiftUI

struct ClubsView: View {
    @Environment(SupabaseService.self) private var supabaseService

    @State private var showCreateSheet = false
    @State private var showJoinSheet = false
    @State private var didInitialLoad = false
    @State private var isInitialLoading = false
    @State private var toast: KuroToastState? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kuroBackground.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: KuroDesignSpacing.lg) {
                        if isInitialLoading {
                            loadingState
                                .padding(.top, KuroDesignSpacing.xl)
                        } else if supabaseService.myClubs.isEmpty {
                            emptyState
                                .padding(.top, KuroDesignSpacing.xxl)
                        } else {
                            clubList
                                .padding(.top, KuroDesignSpacing.md)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, KuroDesignSpacing.xxl)
                }
                .refreshable {
                    await supabaseService.fetchMyClubs()
                }
                // Keep final rows clear of home-indicator chrome.
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 24)
                }

                if let toast {
                    VStack {
                        Spacer()
                        KuroToast(toast: toast)
                            .padding(.horizontal, KuroDesignSpacing.md)
                            .padding(.bottom, 92)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
                }
            }
            .task {
                guard !didInitialLoad else { return }
                didInitialLoad = true
                isInitialLoading = true
                await supabaseService.fetchMyClubs()
                isInitialLoading = false
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateClubSheet { response in
                    showToast(.success, title: "Club created", subtitle: response.name)
                }
                .environment(supabaseService)
            }
            .sheet(isPresented: $showJoinSheet) {
                JoinClubSheet { response in
                    showToast(.success, title: "Joined club", subtitle: response.club_name)
                }
                .environment(supabaseService)
            }
        }
    }

    // MARK: - Empty State

    private var loadingState: some View {
        VStack(spacing: KuroDesignSpacing.md) {
            ForEach(0..<3, id: \.self) { _ in
                KuroGlassCard(cornerRadius: KuroRadius.lg) {
                    HStack(spacing: KuroDesignSpacing.md) {
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.black.opacity(0.10))
                                .frame(width: 140, height: 12)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.black.opacity(0.06))
                                .frame(width: 82, height: 8)
                        }
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 8, height: 12)
                    }
                    .padding(.horizontal, KuroDesignSpacing.md)
                    .padding(.vertical, KuroDesignSpacing.md)
                }
            }
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.black.opacity(0.45))
                Text("Loading clubs...")
                    .font(.kuroCaption(weight: .light))
                    .foregroundColor(.black.opacity(0.50))
            }
        }
    }

    private var emptyState: some View {
        KuroGlassCard(cornerRadius: 22) {
            VStack(spacing: KuroDesignSpacing.md) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(.black.opacity(0.55))
                    .padding(.top, KuroDesignSpacing.lg)

                Text("CLUBS")
                    .font(.kuroCaption(weight: .medium))
                    .tracking(2.4)
                    .foregroundColor(.black.opacity(0.80))

                Text("Watch together. Private by design.")
                    .font(.kuroBody(weight: .light))
                    .foregroundColor(.black.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, KuroDesignSpacing.xs)

                KuroGlassPill(
                    title: "Create a club",
                    subtitle: "Invite friends to watch together",
                    systemImage: "person.2.badge.gearshape"
                ) {
                    KuroAccessibility.impactHaptic(.light)
                    showCreateSheet = true
                }

                KuroGlassPill(
                    title: "Join with code",
                    subtitle: "Enter an invite code",
                    systemImage: "ticket"
                ) {
                    KuroAccessibility.impactHaptic(.light)
                    showJoinSheet = true
                }
            }
            .padding(.horizontal, KuroDesignSpacing.md)
            .padding(.bottom, KuroDesignSpacing.lg)
        }
    }

    // MARK: - Club List

    private var clubList: some View {
        VStack(spacing: KuroDesignSpacing.md) {
            // Action row
            HStack(spacing: KuroDesignSpacing.sm) {
                Button {
                    KuroAccessibility.impactHaptic(.light)
                    showCreateSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("CREATE")
                            .font(.kuroCaption(weight: .medium))
                            .tracking(1.6)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Capsule().fill(Color.black)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    KuroAccessibility.impactHaptic(.light)
                    showJoinSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "ticket")
                            .font(.system(size: 11, weight: .semibold))
                        Text("JOIN")
                            .font(.kuroCaption(weight: .medium))
                            .tracking(1.6)
                    }
                    .foregroundColor(.black.opacity(0.80))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .stroke(Color.black.opacity(0.18), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)

                Spacer()
            }

            EditorialLayout.divider()

            // Club cards
            LazyVStack(spacing: KuroDesignSpacing.md) {
                ForEach(supabaseService.myClubs) { club in
                    NavigationLink(value: club.id) {
                        ClubCardRow(club: club)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationDestination(for: String.self) { clubId in
            ClubDetailView(clubId: clubId)
                .environment(supabaseService)
        }
    }

    // MARK: - Toast helper

    private func showToast(_ kind: KuroToastState.Kind, title: String, subtitle: String?) {
        toastDismissTask?.cancel()
        withAnimation(KuroAnimation.fast) {
            toast = KuroToastState(kind: kind, title: title, subtitle: subtitle, actionTitle: nil, onAction: nil)
        }
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(KuroAnimation.fast) { toast = nil }
        }
    }
}

// MARK: - Club Card Row

private struct ClubCardRow: View {
    let club: SupabaseService.ClubListRow

    private var sharingBadge: String {
        switch club.sharing_level {
        case "private": return "PRIVATE"
        case "status": return "STATUS"
        case "progress": return "PROGRESS"
        default: return club.sharing_level.uppercased()
        }
    }

    var body: some View {
        KuroGlassCard(cornerRadius: KuroRadius.lg) {
            HStack(spacing: KuroDesignSpacing.md) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(club.name)
                        .font(.kuroHeadline(weight: .light))
                        .foregroundColor(.black.opacity(0.90))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(sharingBadge)
                            .font(.kuroMicro(weight: .medium))
                            .tracking(1.0)
                            .foregroundColor(.black.opacity(0.45))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .stroke(Color.black.opacity(0.12), lineWidth: 0.6)
                            )
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.black.opacity(0.25))
            }
            .padding(.horizontal, KuroDesignSpacing.md)
            .padding(.vertical, KuroDesignSpacing.md)
        }
    }
}

// MARK: - Create Club Sheet

private struct CreateClubSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseService.self) private var supabaseService

    @State private var name = ""
    @State private var description = ""
    @State private var sharingLevel = "status"
    @State private var isSubmitting = false
    @State private var errorText: String? = nil

    let onCreated: (SupabaseService.CreateClubResponse) -> Void

    private let sharingLevels = ["private", "status", "progress"]

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                    Text("CREATE CLUB")
                        .font(.kuroCaption(weight: .medium))
                        .tracking(2.4)
                        .foregroundColor(.black.opacity(0.60))
                        .padding(.top, KuroDesignSpacing.md)

                    VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                        Text("Name")
                            .font(.kuroCaption(weight: .medium))
                            .foregroundColor(.black.opacity(0.55))
                        TextField("Club name", text: $name)
                            .font(.kuroBody(weight: .regular))
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                        Text("Description (optional)")
                            .font(.kuroCaption(weight: .medium))
                            .foregroundColor(.black.opacity(0.55))
                        TextField("What's this club about?", text: $description, axis: .vertical)
                            .font(.kuroBody(weight: .light))
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...5)
                    }

                    VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                        Text("Sharing Level")
                            .font(.kuroCaption(weight: .medium))
                            .foregroundColor(.black.opacity(0.55))

                        Picker("Sharing Level", selection: $sharingLevel) {
                            Text("Private").tag("private")
                            Text("Status").tag("status")
                            Text("Progress").tag("progress")
                        }
                        .pickerStyle(.segmented)

                        Text(sharingLevelDescription)
                            .font(.kuroCaption(weight: .light))
                            .foregroundColor(.black.opacity(0.45))
                    }

                    if let errorText {
                        Text(errorText)
                            .font(.kuroCaption())
                            .foregroundColor(.red.opacity(0.85))
                    }

                    Button {
                        submit()
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            }
                            Text("CREATE")
                                .font(.kuroCaption(weight: .medium))
                                .tracking(1.6)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                                .fill(name.trimmingCharacters(in: .whitespaces).isEmpty ? Color.black.opacity(0.3) : Color.black)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, KuroDesignSpacing.xxl)
            }
            .background(Color.kuroBackground)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.kuroBody(weight: .light))
                }
            }
        }
    }

    private var sharingLevelDescription: String {
        switch sharingLevel {
        case "private": return "Only aggregates. Members can't see each other's data."
        case "status": return "Members can see watch/read status but not progress numbers."
        case "progress": return "Members can see full progress, status, and ratings."
        default: return ""
        }
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSubmitting = true
        errorText = nil

        Task {
            do {
                let desc = description.trimmingCharacters(in: .whitespaces)
                let resp = try await supabaseService.createClub(
                    name: trimmed,
                    description: desc.isEmpty ? nil : desc,
                    sharingLevel: sharingLevel
                )
                KuroAccessibility.impactHaptic(.medium)
                onCreated(resp)
                dismiss()
            } catch {
                let msg = "\(error)"
                if msg.contains("INVALID_NAME") {
                    errorText = "Name must be 1-80 characters."
                } else {
                    errorText = "Failed to create club. Please try again."
                }
                KuroAccessibility.errorHaptic()
            }
            isSubmitting = false
        }
    }
}

// MARK: - Join Club Sheet

private struct JoinClubSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseService.self) private var supabaseService

    @State private var inviteCode = ""
    @State private var isSubmitting = false
    @State private var errorText: String? = nil

    let onJoined: (SupabaseService.JoinClubResponse) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                Text("JOIN CLUB")
                    .font(.kuroCaption(weight: .medium))
                    .tracking(2.4)
                    .foregroundColor(.black.opacity(0.60))
                    .padding(.top, KuroDesignSpacing.md)

                VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                    Text("Invite Code")
                        .font(.kuroCaption(weight: .medium))
                        .foregroundColor(.black.opacity(0.55))
                    TextField("8-character code", text: $inviteCode)
                        .font(.kuroBody(weight: .regular))
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .onChange(of: inviteCode) { _, newValue in
                            // Limit to 8 chars, strip whitespace
                            let cleaned = newValue.trimmingCharacters(in: .whitespaces)
                            if cleaned.count > 8 {
                                inviteCode = String(cleaned.prefix(8))
                            }
                        }
                }

                if let errorText {
                    Text(errorText)
                        .font(.kuroCaption())
                        .foregroundColor(.red.opacity(0.85))
                }

                Button {
                    submit()
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        }
                        Text("JOIN")
                            .font(.kuroCaption(weight: .medium))
                            .tracking(1.6)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                            .fill(inviteCode.count < 8 ? Color.black.opacity(0.3) : Color.black)
                    )
                }
                .buttonStyle(.plain)
                .disabled(inviteCode.count < 8 || isSubmitting)

                Spacer()
            }
            .padding(.horizontal, 20)
            .background(Color.kuroBackground)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.kuroBody(weight: .light))
                }
            }
        }
    }

    private func submit() {
        let code = inviteCode.trimmingCharacters(in: .whitespaces)
        guard code.count == 8 else { return }
        isSubmitting = true
        errorText = nil

        Task {
            do {
                let resp = try await supabaseService.joinClub(inviteCode: code)
                KuroAccessibility.impactHaptic(.medium)
                onJoined(resp)
                dismiss()
            } catch {
                let msg = "\(error)"
                if msg.contains("INVALID_CODE") {
                    errorText = "Invalid invite code."
                } else if msg.contains("CODE_EXPIRED") {
                    errorText = "This invite code has expired."
                } else if msg.contains("CODE_EXHAUSTED") {
                    errorText = "This invite code has reached its usage limit."
                } else if msg.contains("CLUB_FULL") {
                    errorText = "This club is full."
                } else if msg.contains("ALREADY_MEMBER") {
                    errorText = "You're already a member of this club."
                } else {
                    errorText = "Failed to join. Please check the code and try again."
                }
                KuroAccessibility.errorHaptic()
            }
            isSubmitting = false
        }
    }
}
