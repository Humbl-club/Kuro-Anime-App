import SwiftUI

// MARK: - GuestSignUpSheet (W5)
// A tool sheet over the current page: the auth form on its email step with the "Kuro keeps nothing on this
// phone" note. Appearing registers the intent with `GuestSession`; closing it while still signed out
// (✕, swipe-down, a deep-link collapse) discards the intent. A successful sign-up rebuilds the tree, so
// `onDisappear` also runs then: `signUpSheetClosed` keeps the intent once the account is authenticated.

struct GuestSignUpSheet: View {
    let request: GuestSignUpRequest
    @Environment(GuestSession.self) private var guest: GuestSession?
    @Environment(\.dismiss) private var dismiss
    @State private var isDirty = false
    @State private var confirmingDiscard = false

    var body: some View {
        AuthView(
            entry: .guestSheet(mode: request.mode),
            guestNote: GuestCopy.sheetNote(for: request.intent, german: KuroLocale.isGerman),
            onDirtyChange: { isDirty = $0 },
            onClose: {
                if isDirty { confirmingDiscard = true } else { dismiss() }
            })
            .onAppear { guest?.begin(request.intent) }
            .onDisappear { guest?.signUpSheetClosed() }
            .kuroDiscardGuard(isDirty: isDirty, isConfirming: $confirmingDiscard) { dismiss() }
    }
}
