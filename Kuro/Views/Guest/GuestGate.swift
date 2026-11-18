import Foundation

// MARK: - GuestGate (W5)
// View-side helper every gated action calls first. For a signed-in person it answers `true` and the action
// goes on; for a guest it opens the sign-up tool sheet (carrying the intent to finish after sign-up) and
// answers `false`, so the action stops. A guest leaves nothing behind: the intent lives in memory only.

@MainActor
enum GuestGate {
    static func allows(_ intent: PendingGuestIntent?, guest: GuestSession?, routes: KuroRoutes,
                       mode: AuthFormRules.Mode = .signUp) -> Bool {
        guard let guest, guest.isGuest else { return true }
        routes.presentSignUp(GuestSignUpRequest(intent: intent, mode: mode))
        return false
    }
}
