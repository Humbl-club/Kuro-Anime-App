// Settings View
// Profile and app settings
// Clean, refined interface

import SwiftUI

struct SettingsView: View {
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 32) {
                    // Profile Section
                    VStack(spacing: 16) {
                        Circle()
                            .fill(Color.black.opacity(0.08))
                            .frame(width: 80, height: 80)
                            .overlay(
                                Text("M")
                                    .font(.system(size: 32, weight: .light))
                                    .foregroundColor(.black)
                            )

                        Text("KURO USER")
                            .font(.system(size: 16, weight: .medium))
                            .tracking(1.0)
                            .foregroundColor(.black)

                        Text("Discover, Track, Enjoy")
                            .font(.system(size: 12, weight: .light))
                            .tracking(0.5)
                            .foregroundColor(.black.opacity(0.5))
                    }
                    .padding(.top, 40)

                    // Stats Section
                    HStack(spacing: 24) {
                        StatBox(
                            value: "\(supabaseService.userLists.filter { $0.mediaType == "anime" }.count)",
                            label: "ANIME"
                        )
                        StatBox(
                            value: "\(supabaseService.userLists.filter { $0.mediaType == "manga" }.count)",
                            label: "MANGA"
                        )
                        StatBox(
                            value: "\(supabaseService.userLists.filter { $0.status == .completed }.count)",
                            label: "COMPLETED"
                        )
                    }

                    Rectangle()
                        .fill(Color.black.opacity(0.08))
                        .frame(height: 0.5)
                        .padding(.horizontal, 20)

                    // Settings Options
                    VStack(spacing: 0) {
                        SettingsRow(
                            icon: "bell",
                            title: "Notifications",
                            subtitle: "Airing reminders"
                        ) { }

                        SettingsRow(
                            icon: "arrow.triangle.2.circlepath",
                            title: "Sync Data",
                            subtitle: "Update from AniList"
                        ) {
                            Task {
                                await supabaseService.fetchUserLists()
                                await supabaseService.fetchCollectionItems()
                                await supabaseService.fetchUpcomingForUser(days: 7)
                                supabaseService.resetAnimePaging()
                                await supabaseService.fetchNextAnimePage()
                                supabaseService.resetMangaPaging()
                                await supabaseService.fetchNextMangaPage()
                                KuroAccessibility.successHaptic()
                            }
                        }

                        SettingsRow(
                            icon: "paintbrush",
                            title: "Appearance",
                            subtitle: "Theme settings"
                        ) { }

                        SettingsRow(
                            icon: "info.circle",
                            title: "About",
                            subtitle: "Version 1.0"
                        ) { }
                    }

                    Rectangle()
                        .fill(Color.black.opacity(0.08))
                        .frame(height: 0.5)
                        .padding(.horizontal, 20)

                    // Danger Zone
                    VStack(spacing: 0) {
                        SettingsRow(
                            icon: "trash",
                            title: "Clear Cache",
                            subtitle: "Free up space",
                            isDestructive: true
                        ) { }

                        SettingsRow(
                            icon: "arrow.right.circle",
                            title: "Sign Out",
                            subtitle: "Log out of account",
                            isDestructive: true
                        ) {
                            Task { await supabaseService.signOut() }
                            dismiss()
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .background(Color.white)
            .navigationTitle("SETTINGS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        KuroAccessibility.impactHaptic(.light)
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .light))
                            .foregroundColor(.black)
                    }
                }
            }
        }
    }
}

// MARK: - Stat Box
struct StatBox: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.black)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .tracking(1.5)
                .foregroundColor(.black.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.04))
        )
    }
}

// MARK: - Settings Row
struct SettingsRow: View {
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
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(isDestructive ? .red.opacity(0.8) : .black.opacity(0.6))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isDestructive ? .red.opacity(0.9) : .black)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.black.opacity(0.5))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.black.opacity(0.3))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    SettingsView()
        .environment(SupabaseService.shared)
}
