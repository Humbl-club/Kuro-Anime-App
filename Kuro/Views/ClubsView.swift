// MARK: - CLUBS VIEW (Main Clubs Page)
// Entry point for the Clubs section (5th page in the swipe pager).
// Shows joined clubs, create/join flows, and empty state.

import SwiftUI
import PostgREST

struct ClubsView: View {
    @Environment(SupabaseService.self) private var supabaseService

    @Binding var pendingJoinCode: String?

    @State private var showCreateSheet = false
    @State private var showJoinSheet = false
    @State private var joinPrefillCode = ""
    @State private var selectedClubId: String? = nil
    @State private var didInitialLoad = false
    @State private var isInitialLoading = false
    @State private var toast: KuroToastState? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil

    init(pendingJoinCode: Binding<String?> = .constant(nil)) {
        _pendingJoinCode = pendingJoinCode
    }

    var body: some View {
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
            supabaseService.clearClubNotificationBadge()
        }
        .onAppear { consumePendingJoinCode() }
        .onChange(of: pendingJoinCode) { _, _ in consumePendingJoinCode() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await supabaseService.fetchMyClubs()
                await supabaseService.checkClubNotifications()
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateClubSheet { response in
                showToast(.success, title: "Club created", subtitle: response.name)
            }
            .environment(supabaseService)
        }
        .sheet(isPresented: $showJoinSheet, onDismiss: { joinPrefillCode = "" }) {
            JoinClubSheet(initialCode: joinPrefillCode) { response in
                showToast(.success, title: "Joined club", subtitle: response.club_name)
            }
            .environment(supabaseService)
        }
        .sheet(isPresented: Binding(
            get: { selectedClubId != nil },
            set: { if !$0 { selectedClubId = nil } }
        )) {
            if let clubId = selectedClubId {
                NavigationStack {
                    ClubDetailView(clubId: clubId)
                        .environment(supabaseService)
                }
            }
        }
    }

    // MARK: - Empty State

    private var loadingState: some View {
        JournalLoadingSkeleton()
    }

    private var emptyState: some View {
        JournalEmptyState(
            onCreateTapped: {
                KuroAccessibility.impactHaptic(.light)
                showCreateSheet = true
            },
            onJoinTapped: {
                KuroAccessibility.impactHaptic(.light)
                showJoinSheet = true
            }
        )
    }

    /// Deep-link entry (kuro://join/<code>): open the join sheet prefilled, then clear the stash.
    private func consumePendingJoinCode() {
        guard let code = pendingJoinCode else { return }
        pendingJoinCode = nil
        joinPrefillCode = code
        showJoinSheet = true
        #if DEBUG
        print("[Clubs] Opened join sheet from deep link (code prefilled)")
        #endif
    }

    // MARK: - Club List

    private var clubList: some View {
        VStack(spacing: 0) {
            JournalActionRow(
                onCreateTapped: {
                    KuroAccessibility.impactHaptic(.light)
                    showCreateSheet = true
                },
                onJoinTapped: {
                    KuroAccessibility.impactHaptic(.light)
                    showJoinSheet = true
                }
            )

            LazyVStack(spacing: 16) {
                ForEach(supabaseService.myClubs) { club in
                    Button {
                        KuroAccessibility.impactHaptic(.light)
                        selectedClubId = club.id
                    } label: {
                        JournalClubCard(club: club, hasUnseen: supabaseService.hasUnseenActivity(club: club))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityLabel("\(club.name), \(club.member_count ?? 0) member\((club.member_count ?? 0) == 1 ? "" : "s")\(supabaseService.hasUnseenActivity(club: club) ? ", new activity" : "")")
                }
            }
        }
        .animation(KuroAnimation.editorial, value: isInitialLoading)
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

// MARK: - Journal Empty State

private struct JournalEmptyState: View {
    let onCreateTapped: () -> Void
    let onJoinTapped: () -> Void

    var body: some View {
        VStack(spacing: KuroDesignSpacing.md) {
            Rectangle()
                .fill(Color.kuroBlack80)
                .frame(width: 40, height: 2)

            Text("CLUBS")
                .font(.kuroMicro(weight: .medium))
                .tracking(2.4)
                .foregroundColor(.kuroBlack80)

            Text("Watch together.\nPrivate by design.")
                .font(.kuroFeature(weight: .light))
                .foregroundColor(.kuroBlack80)
                .multilineTextAlignment(.center)
                .lineSpacing(6)

            Spacer().frame(height: 24)

            Button(action: onCreateTapped) {
                VStack(spacing: 4) {
                    Text("CREATE A CLUB")
                        .font(.kuroCaption(weight: .medium))
                        .tracking(1.6)
                        .foregroundColor(.white)
                    Text("Invite friends to watch together")
                        .font(.kuroMicro())
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                        .fill(Color.black)
                )
            }
            .buttonStyle(.plain)

            Button(action: onJoinTapped) {
                VStack(spacing: 4) {
                    Text("JOIN WITH CODE")
                        .font(.kuroCaption(weight: .medium))
                        .tracking(1.6)
                        .foregroundColor(.kuroBlack80)
                    Text("Enter an invite code")
                        .font(.kuroMicro())
                        .foregroundColor(.kuroTextTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                        .stroke(Color.black.opacity(0.18), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.kuroBlack80)
                .frame(width: 40, height: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No clubs yet. Create a club or join with an invite code.")
    }
}

// MARK: - Journal Loading Skeleton

private struct JournalLoadingSkeleton: View {
    var body: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 0) {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Color.black.opacity(0.04))
                        .frame(height: 140)

                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 160, height: 14)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.black.opacity(0.04))
                            .frame(width: 100, height: 10)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
            }
            .kuroShimmer()

            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.black.opacity(0.45))
                Text("Loading clubs...")
                    .font(.kuroCaption(weight: .light))
                    .foregroundColor(.black.opacity(0.50))
            }
        }
        .accessibilityLabel("Loading clubs")
    }
}

// MARK: - Journal Action Row

private struct JournalActionRow: View {
    let onCreateTapped: () -> Void
    let onJoinTapped: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: KuroDesignSpacing.sm) {
                Button(action: onCreateTapped) {
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

                Button(action: onJoinTapped) {
                    HStack(spacing: 6) {
                        Image(systemName: "ticket")
                            .font(.system(size: 11, weight: .semibold))
                        Text("JOIN")
                            .font(.kuroCaption(weight: .medium))
                            .tracking(1.6)
                    }
                    .foregroundColor(.kuroBlack80)
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
            .padding(.bottom, KuroDesignSpacing.sm)

            EditorialLayout.divider()
        }
    }
}

// MARK: - Journal Club Card

private struct JournalClubCard: View {
    let club: SupabaseService.ClubListRow
    let hasUnseen: Bool

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var coverURL: URL? {
        (club.cover_images ?? []).first.flatMap(URL.init)
    }

    private var sharingBadge: String {
        switch club.sharing_level.lowercased() {
        case "private": return "PRIVATE"
        case "status": return "STATUS"
        case "progress": return "PROGRESS"
        default: return club.sharing_level.uppercased()
        }
    }

    private var initials: [String] {
        (club.member_names ?? []).map { name in
            String(name.prefix(1)).uppercased()
        }
    }

    private var memberCountText: String {
        let count = club.member_count ?? 0
        return "\(count) member\(count == 1 ? "" : "s")"
    }

    private var activityPreviewText: String? {
        club.activity_preview?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private var relativeTime: String? {
        guard let str = club.last_activity_at,
              let date = SupabaseService.parseISO8601(str) else { return nil }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date()).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover image
            coverImage

            // Card body
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(club.name)
                        .font(.kuroTitle(weight: .medium))
                        .foregroundColor(.kuroBlack80)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(sharingBadge)
                            .font(.kuroMicro(weight: .medium))
                            .tracking(1.2)
                            .foregroundColor(.kuroBlack60)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.kuroBlack04)
                            )

                        Text(memberCountText.uppercased())
                            .font(.kuroMicro(weight: .medium))
                            .tracking(1.0)
                            .foregroundColor(.kuroTextSecondary)

                        if let time = relativeTime {
                            Text(time)
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.0)
                                .foregroundColor(.kuroTextTertiary)
                        }
                    }

                    HStack(alignment: .center, spacing: 12) {
                        avatarStack

                        if let preview = activityPreviewText {
                            Text(preview)
                                .font(.kuroCaption(weight: .light))
                                .foregroundColor(.kuroTextSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.black.opacity(0.30))
                    .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        .overlay(alignment: .topTrailing) {
            if hasUnseen {
                Circle()
                    .fill(Color.kuroBlack80)
                    .frame(width: 8, height: 8)
                    .padding(14)
            }
        }
    }

    // MARK: - Cover Image

    private var coverImage: some View {
        Group {
            if let url = coverURL {
                KuroCachedAsyncImage(url: url, maxPixelSize: 800) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .frame(height: 140)
                            .clipped()
                    default:
                        Rectangle().fill(Color.black.opacity(0.06))
                            .frame(height: 140)
                    }
                }
            } else {
                Rectangle().fill(Color.black.opacity(0.06))
                    .frame(height: 140)
            }
        }
    }

    // MARK: - Avatar Stack

    private var avatarStack: some View {
        let displayed = Array(initials.prefix(4))
        let totalCount = club.member_count ?? displayed.count
        let overflow = totalCount - displayed.count

        return HStack(spacing: 0) {
            if displayed.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "person.2")
                        .font(.system(size: 11, weight: .medium))
                    Text(memberCountText)
                        .font(.kuroMicro(weight: .medium))
                }
                .foregroundColor(.kuroTextSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.05))
                )
            } else {
                ZStack(alignment: .leading) {
                    ForEach(Array(displayed.enumerated()), id: \.offset) { index, initial in
                        Circle()
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle().stroke(Color.white, lineWidth: 2)
                            )
                            .overlay(
                                Text(initial)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.kuroTextSecondary)
                            )
                            .offset(x: CGFloat(index) * 18)
                    }
                    if overflow > 0 {
                        Circle()
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle().stroke(Color.white, lineWidth: 2)
                            )
                            .overlay(
                                Text("+\(overflow)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.kuroTextTertiary)
                            )
                            .offset(x: CGFloat(displayed.count) * 18)
                    }
                }
                .frame(
                    width: CGFloat(displayed.count + (overflow > 0 ? 1 : 0)) * 18 + 8,
                    alignment: .leading
                )
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
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
                let code = errorCode(from: error)
                if code == .invalidName {
                    errorText = "Name must be 1-80 characters."
                } else if code == .descriptionTooLong {
                    errorText = "Description must be 500 characters or fewer."
                } else if code == .rateLimited {
                    errorText = "Too many create attempts. Please wait a moment."
                } else if code == .tooManyClubs {
                    errorText = "You've reached the club limit."
                } else {
                    errorText = "Failed to create club. Please try again."
                }
                KuroAccessibility.errorHaptic()
            }
            isSubmitting = false
        }
    }

    private enum CreateClubErrorCode: String {
        case invalidName = "INVALID_NAME"
        case descriptionTooLong = "DESCRIPTION_TOO_LONG"
        case rateLimited = "RATE_LIMITED"
        case tooManyClubs = "TOO_MANY_CLUBS"
    }

    private func errorCode(from error: Error) -> CreateClubErrorCode? {
        guard let pgError = error as? PostgrestError else { return nil }
        let candidates = [pgError.detail, pgError.hint, pgError.message]
        for raw in candidates {
            guard let raw else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let token = trimmed.split(separator: ":", maxSplits: 1).first.map(String.init) ?? trimmed
            let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if let code = CreateClubErrorCode(rawValue: normalized) { return code }
        }
        return nil
    }
}

// MARK: - Join Club Sheet

private struct JoinClubSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseService.self) private var supabaseService

    @State private var inviteCode: String
    @State private var isSubmitting = false
    @State private var errorText: String? = nil

    let onJoined: (SupabaseService.JoinClubResponse) -> Void

    init(initialCode: String = "", onJoined: @escaping (SupabaseService.JoinClubResponse) -> Void) {
        _inviteCode = State(initialValue: initialCode)
        self.onJoined = onJoined
    }

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
                switch errorCode(from: error) {
                case .invalidCode:
                    errorText = "Invalid invite code."
                case .codeExpired:
                    errorText = "This invite code has expired."
                case .codeExhausted:
                    errorText = "This invite code has reached its usage limit."
                case .clubArchived:
                    errorText = "This club is no longer active."
                case .clubFull:
                    errorText = "This club is full."
                case .alreadyMember:
                    errorText = "You're already a member of this club."
                case .rateLimited:
                    errorText = "Too many attempts. Please wait a moment and try again."
                case .none:
                    errorText = "Failed to join. Please check the code and try again."
                }
                KuroAccessibility.errorHaptic()
            }
            isSubmitting = false
        }
    }

    private enum JoinClubErrorCode: String {
        case invalidCode = "INVALID_CODE"
        case codeExpired = "CODE_EXPIRED"
        case codeExhausted = "CODE_EXHAUSTED"
        case clubArchived = "CLUB_ARCHIVED"
        case clubFull = "CLUB_FULL"
        case alreadyMember = "ALREADY_MEMBER"
        case rateLimited = "RATE_LIMITED"
    }

    private func errorCode(from error: Error) -> JoinClubErrorCode? {
        guard let pgError = error as? PostgrestError else { return nil }
        let candidates = [pgError.detail, pgError.hint, pgError.message]
        for raw in candidates {
            guard let raw else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let token = trimmed.split(separator: ":", maxSplits: 1).first.map(String.init) ?? trimmed
            let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if let mapped = JoinClubErrorCode(rawValue: normalized) { return mapped }
        }
        return nil
    }
}
