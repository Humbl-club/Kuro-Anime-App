import SwiftUI
import UIKit

// MARK: - Release reminders row (details-songs spec §11.4, §12.3; item 10)
// A Profile preference row with a toggle: the row title (15 medium −0.2) and its subtitle (meta,
// secondary ink), the system toggle tinted ink. It is one of the two places that may ask iOS for
// notification permission (the other is the detail bell), and it asks only when turned ON while the
// permission is still undecided (`ReleasesStore.setReleaseNotificationsEnabled`). Reading the state
// on appear never prompts. A refusal keeps the toggle off and shows one line with "Open Settings".

struct ProfileRemindersRow: View {
    @Environment(ReleasesStore.self) private var releases
    @Environment(\.openURL) private var openURL

    /// The last explicit change was refused by the system (or could not be set).
    @State private var notice: ProfileReminderNotice?
    @State private var isChanging = false

    private var german: Bool { KuroLocale.isGerman }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: Binding(
                get: { releases.releaseNotificationsEnabled },
                set: { change(to: $0) }
            )) {
                HStack(spacing: 12) {
                    Image(systemName: releases.releaseNotificationsEnabled ? "bell.badge" : "bell")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.kuroControlInk)
                        .frame(width: 30, height: 30)
                        .background(Color.white, in: Circle())
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(ProfileStatsCopy.remindersTitle(german: german))
                            .font(.kuroCustom(15, weight: .medium, relativeTo: .headline, maxSize: 30)).tracking(-0.2)
                            .foregroundStyle(Color.kuroInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(ProfileStatsCopy.remindersSubtitle(german: german))
                            .font(.kuroMeta())
                            .foregroundStyle(Color.kuroInkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .tint(Color.kuroInk)
            .disabled(isChanging)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 8)
            .accessibilityIdentifier("profile.releaseReminders")

            if let notice {
                VStack(alignment: .leading, spacing: 0) {
                    Text(notice.line(german: german))
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if notice == .denied, let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        Button {
                            openURL(url)
                        } label: {
                            Text(ProfileStatsCopy.openSettings(german: german))
                                .font(.kuroMeta(weight: .medium))
                                .foregroundStyle(Color.kuroInk)
                                .underline(true, color: Color.kuroInk)
                                .frame(minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(HomeContactStyle())
                    }
                }
                .padding(.bottom, 8)
            }

            if releases.releaseNotificationsEnabled {
                Divider()
                    .overlay(Color.kuroInk.opacity(0.08))
                Toggle(isOn: Binding(
                    get: { releases.mangaDayAlertsEnabled },
                    set: { enabled in
                        Task { await releases.setMangaDayAlertsEnabled(enabled) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(KuroLocale.text("Manga morning alerts (09:00)", "Manga-Morgenhinweise (09:00)"))
                            .font(.kuroCustom(15, weight: .medium, relativeTo: .headline, maxSize: 30))
                            .tracking(-0.2)
                            .foregroundStyle(Color.kuroInk)
                        Text(KuroLocale.text(
                            "Send a 09:00 reminder on confirmed manga release days.",
                            "Erinnert um 09:00 Uhr an bestätigten Manga-Erscheinungstagen."
                        ))
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Color.kuroInk)
                .disabled(isChanging)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.vertical, 8)
                .accessibilityIdentifier("profile.mangaDayAlerts")
            }

            Divider()
                .overlay(Color.kuroInk.opacity(0.08))
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(KuroLocale.text("Audio track", "Sprachfassung"))
                        .font(.kuroCustom(15, weight: .medium, relativeTo: .headline, maxSize: 30))
                        .tracking(-0.2)
                        .foregroundStyle(Color.kuroInk)
                    Text(KuroLocale.text(
                        "Preferred airing schedule variant",
                        "Bevorzugte Ausstrahlungsfassung"
                    ))
                    .font(.kuroMeta())
                    .foregroundStyle(Color.kuroInkSecondary)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    ForEach(["sub", "dub"], id: \.self) { variant in
                        let selected = releases.preferredAudioVariant == variant
                        Button {
                            releases.setPreferredAudioVariant(variant)
                        } label: {
                            Text(variant.uppercased())
                                .font(.kuroCustom(11, weight: .semibold, relativeTo: .caption1, maxSize: 16))
                                .foregroundStyle(selected ? Color.white : Color.kuroInk)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .frame(minHeight: 32)
                                .background(selected ? Color.kuroInk : Color.black.opacity(0.05), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.audioVariant.\(variant)")
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .task { await releases.refreshReleaseNotificationState() }
    }

    private func change(to enabled: Bool) {
        guard !isChanging else { return }
        KuroAccessibility.impactHaptic(.light)
        isChanging = true
        Task { @MainActor in
            let result = await releases.setReleaseNotificationsEnabled(enabled)
            isChanging = false
            notice = ProfileReminderNotice(result)
        }
    }
}

/// What the row says after an explicit change (pure, tested).
nonisolated enum ProfileReminderNotice: Equatable, Sendable {
    case denied

    /// Nil: nothing to say (on, off, or no account; the toggle shows the state).
    init?(_ result: ReleaseNotificationToggleResult) {
        switch result {
        case .permissionDenied: self = .denied
        case .enabled, .disabled, .signedOut: return nil
        }
    }

    func line(german: Bool) -> String {
        switch self {
        case .denied: return ProfileStatsCopy.remindersDenied(german: german)
        }
    }
}
