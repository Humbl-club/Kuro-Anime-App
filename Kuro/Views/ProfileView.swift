import AuthenticationServices
import SwiftUI

// Dedicated profile/settings page (moved out of the header to keep the top bar clean).
struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseService.self) private var supabaseService
    @State private var isSyncing: Bool = false
    @State private var showClubs: Bool = false
    @State private var toast: KuroToastState? = nil
    @State private var showDeleteConfirmation: Bool = false
    @State private var isDeleting: Bool = false

    var body: some View {
        ZStack {
            ProfileBackdrop()
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: KuroDesignSpacing.lg) {
                    header
                        .padding(.top, KuroDesignSpacing.md)

                    stats
                        .padding(.horizontal, KuroDesignSpacing.padding)

                    clubsPreview
                        .padding(.horizontal, KuroDesignSpacing.padding)

                    Rectangle()
                        .fill(Color.black.opacity(0.08))
                        .frame(height: 0.5)
                        .padding(.horizontal, KuroDesignSpacing.padding)

                    actions
                        .padding(.horizontal, KuroDesignSpacing.padding)

                    footer
                        .padding(.top, 6)

                    Spacer(minLength: 24)
                }
                .padding(.bottom, 48)
            }
            // Ensure the last rows can scroll fully above the home indicator / tab chrome.
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 24)
            }
        }
        .scrollContentBackground(.hidden)
        .transaction { $0.animation = nil }
        .task(id: supabaseService.currentUserEmail) {
            // Keep the profile "club context" warm so Clubs opens instantly.
            await supabaseService.fetchMyClubs()
        }
        .overlay(alignment: .topTrailing) {
            Button(action: {
                KuroAccessibility.impactHaptic(.light)
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .light))
                    .foregroundColor(.kuroBlack80)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.kuroSecondaryBackground.opacity(0.92))
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
                            )
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .padding(.trailing, 14)
        }
        .overlay(alignment: .top) {
            if let toast {
                KuroToast(toast: toast)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showClubs) {
            ClubsView()
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 92, height: 92)
                    .overlay(
                        LinearGradient(
                            colors: [Color.white.opacity(0.55), Color.black.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(Circle())
                        .opacity(0.95)
                    )
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.75), lineWidth: 0.8)
                            .blendMode(.overlay)
                    )
                    .overlay(
                        Circle().stroke(Color.black.opacity(0.10), lineWidth: 0.7)
                    )

                Text(supabaseService.currentUserInitial)
                    .font(.kuroFeature(weight: .light))
                    .foregroundColor(.kuroBlack80)
            }

            Text((supabaseService.currentUserEmail == nil ? "GUEST" : "KURO USER").uppercased())
                .font(.kuroCaption(weight: .medium))
                .tracking(2.0)
                .foregroundColor(.kuroBlack80)

            if let email = supabaseService.currentUserEmail, !email.isEmpty {
                Text(email.contains("privaterelay.appleid.com") ? "Signed in with Apple" : email)
                    .font(.kuroBody(weight: .light))
                    .foregroundColor(.kuroBlack60)
            } else {
                Text("Discover, track, enjoy.")
                    .font(.kuroBody(weight: .light))
                    .foregroundColor(.kuroBlack60)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var stats: some View {
        let animeLists = supabaseService.userLists.filter { $0.mediaType == "anime" }
        let mangaLists = supabaseService.userLists.filter { $0.mediaType == "manga" }
        let doneCount = supabaseService.userLists.filter { $0.status == .completed }.count
        let episodesWatched = animeLists.reduce(0) { $0 + $1.progress }
        let chaptersRead = mangaLists.reduce(0) { $0 + $1.progress }
        let scoredEntries = supabaseService.userLists.compactMap(\.score).filter { $0 > 0 }
        let avgRating = scoredEntries.isEmpty ? 0.0 : Double(scoredEntries.reduce(0, +)) / Double(scoredEntries.count)

        return VStack(spacing: 10) {
            HStack(spacing: 14) {
                ProfileStatTile(value: "\(animeLists.count)", label: "ANIME")
                ProfileStatTile(value: "\(mangaLists.count)", label: "MANGA")
                ProfileStatTile(value: "\(doneCount)", label: "DONE")
            }
            HStack(spacing: 14) {
                ProfileStatTile(value: "\(episodesWatched)", label: "EPISODES")
                ProfileStatTile(value: "\(chaptersRead)", label: "CHAPTERS")
                ProfileStatTile(value: scoredEntries.isEmpty ? "—" : String(format: "%.0f", avgRating), label: "AVG SCORE")
            }
        }
    }

    private var clubsPreview: some View {
        let clubs = supabaseService.myClubs

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("CLUBS")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(2.0)
                    .foregroundColor(.kuroBlack60)

                Spacer(minLength: 0)

                Text("\(clubs.count)")
                    .font(.kuroMicro(weight: .medium))
                    .foregroundColor(.kuroBlack30)
                    .monospacedDigit()
            }

            if clubs.isEmpty {
                Text("Private clubs with shared rails. No feeds.")
                    .font(.kuroCaption(weight: .light))
                    .foregroundColor(.kuroBlack60)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(clubs.prefix(3)) { c in
                        Text(c.name)
                            .font(.kuroBody(weight: .light))
                            .foregroundColor(.kuroBlack80)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                .fill(Color.kuroSecondaryBackground.opacity(0.90))
                .overlay(
                    RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                )
        )
    }

    private var actions: some View {
        VStack(spacing: 12) {
            ProfileActionRow(
                icon: "person.2",
                title: "Clubs",
                subtitle: "Shared rails, no feeds",
                trailing: "\(supabaseService.myClubs.count)"
            ) {
                showClubs = true
            }

            ProfileActionRow(
                icon: "arrow.triangle.2.circlepath",
                title: "Sync Data",
                subtitle: "Refresh your lists & rails"
            ) {
                Task {
                    isSyncing = true
                    defer { isSyncing = false }
                    await supabaseService.fetchUserLists()
                    await supabaseService.fetchCollectionItems()
                    await supabaseService.fetchUpcomingForUser(days: 7)
                    KuroAccessibility.successHaptic()
                    showToast(.success, title: "Synced", subtitle: "Lists updated")
                }
            }

            ProfileActionRow(
                icon: "trash",
                title: "Clear Cache",
                subtitle: "Reset image + detail caches",
                isDestructive: true
            ) {
                Task {
                    await KuroDiskDetailCache.clearAll()
                    URLCache.shared.removeAllCachedResponses()
                    KuroAccessibility.successHaptic()
                }
            }

            ProfileActionRow(
                icon: "arrow.right.circle",
                title: "Sign Out",
                subtitle: "Log out of your account",
                isDestructive: true
            ) {
                Task { await supabaseService.signOut() }
            }

            ProfileActionRow(
                icon: "person.crop.circle.badge.minus",
                title: "Delete Account",
                subtitle: "Permanently remove all data",
                isDestructive: true
            ) {
                showDeleteConfirmation = true
            }
            .alert("Delete Account", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete Everything", role: .destructive) {
                    Task {
                        isDeleting = true
                        defer { isDeleting = false }
                        do {
                            // For Apple users, obtain a fresh authorization code for token revocation.
                            var appleCode: String? = nil
                            if await supabaseService.isAppleUser {
                                appleCode = await obtainAppleAuthorizationCode()
                            }
                            try await supabaseService.deleteAccount(appleAuthorizationCode: appleCode)
                            dismiss()
                        } catch {
                            showToast(.error, title: "Deletion failed", subtitle: error.localizedDescription)
                        }
                    }
                }
            } message: {
                Text("This will permanently delete your account, lists, club memberships, and all associated data. This action cannot be undone.")
            }

            if isDeleting {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.9)
                        .tint(.black.opacity(0.55))
                    Text("Deleting account...")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.black.opacity(0.55))
                    Spacer(minLength: 0)
                }
                .padding(.top, 6)
                .padding(.horizontal, 8)
            }

            if isSyncing {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.9)
                        .tint(.kuroBlack60)
                    Text("Syncing…")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroBlack60)
                    Spacer(minLength: 0)
                }
                .padding(.top, 6)
                .padding(.horizontal, 8)
            }
        }
    }

    private func obtainAppleAuthorizationCode() async -> String? {
        await withCheckedContinuation { continuation in
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = []
            let delegate = AppleAuthCodeDelegate { code in
                continuation.resume(returning: code)
            }
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = delegate
            // Keep delegate alive until callback fires.
            objc_setAssociatedObject(controller, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
            controller.performRequests()
        }
    }

    private func showToast(_ kind: KuroToastState.Kind, title: String, subtitle: String?) {
        withAnimation(.easeInOut(duration: 0.18)) {
            toast = KuroToastState(kind: kind, title: title, subtitle: subtitle, actionTitle: nil, onAction: nil)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(.easeInOut(duration: 0.18)) {
                toast = nil
            }
        }
    }

    private var footer: some View {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"

        return VStack(spacing: 10) {
            if let url = URL(string: "https://kuro.app/privacy") {
                Link(destination: url) {
                    Text("Privacy Policy")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroBlack60)
                        .underline(color: .kuroBlack30)
                }
                .buttonStyle(.plain)
            }

            Text("KURO  •  v\(version) (\(build))")
                .font(.kuroMicro(weight: .light))
                .tracking(1.6)
                .foregroundColor(.kuroBlack30)
        }
    }
}

private struct ProfileBackdrop: View {
    var body: some View {
        ZStack {
            Color.kuroBackground

            // Subtle "editorial" atmosphere so glass surfaces read as intentional, not flat.
            Circle()
                .fill(Color.black.opacity(0.035))
                .frame(width: 420, height: 420)
                .blur(radius: 70)
                .offset(x: -180, y: -260)

            Circle()
                .fill(Color.black.opacity(0.025))
                .frame(width: 520, height: 520)
                .blur(radius: 90)
                .offset(x: 220, y: -180)
        }
    }
}

private struct ProfileStatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 10) {
            Text(value)
                .font(.kuroHeadline(weight: .light))
                .foregroundColor(.kuroBlack80)

            Text(label)
                .font(.kuroMicro(weight: .medium))
                .tracking(2.2)
                .foregroundColor(.kuroTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.kuroSecondaryBackground.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

private struct ProfileActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var trailing: String? = nil
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            action()
        }) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(isDestructive ? .red.opacity(0.85) : .kuroBlack60)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.kuroBody(weight: .regular))
                        .foregroundColor(isDestructive ? .red.opacity(0.92) : .kuroBlack80)
                    Text(subtitle)
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroBlack60)
                }

                Spacer()

                if let trailing, !trailing.isEmpty {
                    Text(trailing)
                        .font(.kuroMicro(weight: .medium))
                        .foregroundColor(.kuroBlack30)
                        .monospacedDigit()
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.kuroTextTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.75), lineWidth: 0.8)
                            .blendMode(.overlay)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 10)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Apple Auth Code Delegate (for token revocation on account deletion)

private final class AppleAuthCodeDelegate: NSObject, ASAuthorizationControllerDelegate {
    private let completion: (String?) -> Void
    private var didComplete = false

    init(completion: @escaping (String?) -> Void) {
        self.completion = completion
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard !didComplete else { return }
        didComplete = true
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
           let codeData = credential.authorizationCode,
           let code = String(data: codeData, encoding: .utf8) {
            completion(code)
        } else {
            completion(nil)
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        guard !didComplete else { return }
        didComplete = true
        completion(nil)
    }
}
