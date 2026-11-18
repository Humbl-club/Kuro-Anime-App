import Foundation

// MARK: - W5 guest copy (EN / DE)
// Spec §6 wording, used verbatim: Kuro keeps nothing on this phone until the person has an account.

enum GuestCopy {
    static func sheetNote(for intent: PendingGuestIntent?, german: Bool) -> String {
        switch intent {
        case .plan:
            return german
                ? "Kuro speichert nichts auf diesem Gerät, bis du ein Konto hast; der Titel, den du gewählt hast, wird hinzugefügt, sobald du dich registrierst."
                : "Kuro keeps nothing on this phone until you have an account; the title you picked is added as soon as you sign up."
        case nil:
            return german
                ? "Kuro speichert nichts auf diesem Gerät, bis du ein Konto hast."
                : "Kuro keeps nothing on this phone until you have an account."
        case .some:
            return german
                ? "Kuro speichert nichts auf diesem Gerät, bis du ein Konto hast; wir erledigen das, sobald du dich registrierst."
                : "Kuro keeps nothing on this phone until you have an account; we finish this as soon as you sign up."
        }
    }

    static func planned(_ title: String, german: Bool) -> String {
        german ? "„\(title)“ steht jetzt auf deiner Planliste." : "Added “\(title)” to Planning."
    }

    static func alreadyListed(_ title: String, german: Bool) -> String {
        german ? "„\(title)“ ist schon in deiner Liste." : "“\(title)” is already in your list."
    }

    static func replayFailed(_ title: String, german: Bool) -> String {
        german
            ? "„\(title)“ konnte nicht hinzugefügt werden. Versuch es auf der Titelseite noch einmal."
            : "Couldn't add “\(title)”. Try again from its page."
    }

    static func joinedClub(german: Bool) -> String {
        german ? "Du bist dem Club beigetreten." : "Joined the club."
    }

    static func joinClubFailed(german: Bool) -> String {
        german ? "Der Club konnte nicht betreten werden." : "Couldn't join the club."
    }

    static let createAccount: (english: String, german: String) = ("Create account", "Konto erstellen")
    static let signIn: (english: String, german: String) = ("Sign in", "Anmelden")
    static let close: (english: String, german: String) = ("Close", "Schließen")

    /// Invitation page title per section (the pager's guest pages).
    static func invitationTitle(_ section: KuroMainView.Section, german: Bool) -> String {
        switch section {
        case .taste:
            return german ? "Dein Geschmack beginnt mit einem Konto" : "Your taste starts with an account"
        case .home:
            return german ? "Dein Start beginnt mit einem Konto" : "Your Home starts with an account"
        case .collection:
            return german ? "Deine Sammlung beginnt mit einem Konto" : "Your collection starts with an account"
        case .clubs:
            return german ? "Clubs beginnen mit einem Konto" : "Clubs start with an account"
        case .concierge, .discover, .browse:
            return german ? "Erstelle ein Konto" : "Create an account"
        }
    }

    static func invitationBody(german: Bool) -> String {
        german
            ? "Kuro speichert nichts auf diesem Gerät, bis du ein Konto hast. Entdecken und Suchen funktionieren schon jetzt."
            : "Kuro keeps nothing on this phone until you have an account. Discover and Search already work."
    }
}
