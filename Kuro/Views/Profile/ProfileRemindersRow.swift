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
