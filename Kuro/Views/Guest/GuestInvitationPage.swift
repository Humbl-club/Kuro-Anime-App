import SwiftUI

// MARK: - GuestInvitationPage (W5)
// What Taste, Home, Collection and Clubs show a guest: a branded invitation to make an account. It sends no
// request and holds nothing; the buttons open the sign-up sheet (Create account / Sign in).

struct GuestInvitationPage: View {
    let section: KuroMainView.Section

    @Environment(GuestSession.self) private var guest: GuestSession?
    @Environment(\.kuroRoutes) private var routes

    var body: some View {
        let german = KuroLocale.isGerman
        ScrollView {
            KuroEmptyView(headline: GuestCopy.invitationTitle(section, german: german),
                          message: GuestCopy.invitationBody(german: german)) {
                KuroOutlineButton(german ? GuestCopy.createAccount.german : GuestCopy.createAccount.english) {
                    _ = GuestGate.allows(nil, guest: guest, routes: routes, mode: .signUp)
                }
                .accessibilityIdentifier("guest.invitation.createAccount")
                KuroOutlineButton(german ? GuestCopy.signIn.german : GuestCopy.signIn.english) {
                    _ = GuestGate.allows(nil, guest: guest, routes: routes, mode: .signIn)
                }
                .accessibilityIdentifier("guest.invitation.signIn")
            }
            .padding(.top, 60)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("guest.invitation.\(String(describing: section))")
    }
}
