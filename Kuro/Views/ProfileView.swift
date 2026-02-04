import SwiftUI

// Dedicated profile/settings page (moved out of the header to keep the top bar clean).
struct ProfileView: View {
    @Environment(SupabaseService.self) private var supabaseService

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 22) {
                header
                    .padding(.top, 18)

                stats
                    .padding(.horizontal, 20)

                Divider()
                    .overlay(Color.black.opacity(0.08))
                    .padding(.horizontal, 20)

                actions
                    .padding(.horizontal, 20)

                Spacer(minLength: 24)
            }
            .padding(.bottom, 48)
        }
        .background(Color.white)
        .scrollContentBackground(.hidden)
        .transaction { $0.animation = nil }
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

                Text("M")
                    .font(.system(size: 34, weight: .light))
                    .foregroundColor(.black.opacity(0.86))
            }

            Text("KURO USER")
                .font(.system(size: 15, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(.black.opacity(0.88))

            Text("Discover, track, enjoy.")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.black.opacity(0.52))
        }
        .frame(maxWidth: .infinity)
    }

    private var stats: some View {
        let animeCount = supabaseService.userLists.filter { $0.mediaType == "anime" }.count
        let mangaCount = supabaseService.userLists.filter { $0.mediaType == "manga" }.count
        let doneCount = supabaseService.userLists.filter { $0.status == .completed }.count

        return HStack(spacing: 14) {
            StatBox(
                value: "\(animeCount)",
                label: "ANIME"
            )
            StatBox(
                value: "\(mangaCount)",
                label: "MANGA"
            )
            StatBox(
                value: "\(doneCount)",
                label: "DONE"
            )
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            ProfileActionRow(
                icon: "arrow.triangle.2.circlepath",
                title: "Sync Data",
                subtitle: "Refresh your lists & rails"
            ) {
                Task {
                    await supabaseService.fetchUserLists()
                    await supabaseService.fetchCollectionItems()
                    await supabaseService.fetchUpcomingForUser(days: 7)
                    KuroAccessibility.successHaptic()
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
        }
    }
}

private struct ProfileActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
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
                    .foregroundColor(isDestructive ? .red.opacity(0.85) : .black.opacity(0.65))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isDestructive ? .red.opacity(0.92) : .black.opacity(0.9))
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.black.opacity(0.52))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.black.opacity(0.25))
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
