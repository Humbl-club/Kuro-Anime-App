import Foundation

// MARK: - Onboarding completion (per account; spec D7)
// Read by the onboarding gate (`OnboardingView.hasCompletedOnboarding(for:)`), written when onboarding
// finishes, and removed by the session funnel when the account is deleted (GDPR: nothing keyed by a
// deleted account stays on the device). Lives with Identity so the funnel does not depend on a view.

/// Whether onboarding ran for an account. Keyed by the lower-cased user id; the pre-2026-11-01
/// device-wide flag counts once for the first account that signs in afterwards (so existing users
/// are not shown onboarding again after the update) and is then retired. Without a user id (the
/// DEBUG `--kuro-skip-auth` preview) the device-wide flag is used.
nonisolated enum OnboardingCompletion {
    static let legacyDeviceKey = "kuro_onboarding_completed"
    static let keyPrefix = "kuro_onboarding_completed."

    static func key(for userId: String) -> String {
        keyPrefix + userId.lowercased()
    }

    static func isCompleted(userId: String?, defaults: UserDefaults = .standard) -> Bool {
        guard let userId, !userId.isEmpty else { return defaults.bool(forKey: legacyDeviceKey) }
        if defaults.bool(forKey: key(for: userId)) { return true }
        if defaults.bool(forKey: legacyDeviceKey) {
            defaults.set(true, forKey: key(for: userId))
            defaults.removeObject(forKey: legacyDeviceKey)
            return true
        }
        return false
    }

    static func markCompleted(userId: String?, defaults: UserDefaults = .standard) {
        guard let userId, !userId.isEmpty else {
            defaults.set(true, forKey: legacyDeviceKey)
            return
        }
        defaults.set(true, forKey: key(for: userId))
    }

    /// Account deletion: forgets the deleted account's completion (the device-wide legacy flag is
    /// not per account and stays as it is).
    static func remove(userId: String, defaults: UserDefaults = .standard) {
        guard !userId.isEmpty else { return }
        defaults.removeObject(forKey: key(for: userId))
    }
}
