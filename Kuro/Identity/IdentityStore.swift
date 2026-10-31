import Foundation
import Observation

// MARK: - Identity (E6c1)
// The ONLY holder of the signed-in identity the UI shows. Written exclusively by the session funnel
// (`SessionController`) and the auth transport (`AuthService`, missing-configuration messages); views
// read it from the environment (`@Environment(IdentityStore.self)`). Moved from `SupabaseService`
// (auth state + `configError`), values unchanged. `isAuthBootstrapping` starts false here; the
// production launch sets it before the first frame (`SessionController.startLaunchRestore()`), so the
// app still starts on the loading screen and KuroTests' graphs never do.

@MainActor
@Observable
final class IdentityStore {
    /// The SDK configuration error (missing SUPABASE_URL / SUPABASE_ANON_KEY); nil when the app has a
    /// client. Fixed at launch.
    let configError: String?
    /// True while the launch restore runs (the root shows its loading screen meanwhile; set by
    /// `SessionController.startLaunchRestore()`).
    var isAuthBootstrapping: Bool = false
    var isAuthenticated: Bool = false
    /// The last auth failure shown on the auth screen (and the rejected-callback message).
    var authErrorMessage: String? = nil
    /// Lightweight identity for UI (header menus, etc.).
    var currentUserEmail: String? = nil
    /// Used for local-only UI labeling (e.g. Clubs member list "You").
    var currentUserId: String? = nil

    /// - Parameter configError: the configuration error when the app has no SDK client.
    init(configError: String? = nil) {
        self.configError = configError
    }

    var currentUserInitial: String {
        let c = currentUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines).first
        return c.map { String($0).uppercased() } ?? "M"
    }
}
