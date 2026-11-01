import Foundation

// MARK: - Auth copy and form rules (EN/DE)
// Every user-facing auth string, keyed by what happened, in both languages (spec D4: inline EN/DE
// pairs, German informal "du"). Pure: the language is a parameter, so tests never depend on the host
// language; callers pass `KuroLocale.isGerman`. Voice (rulebook §9/§10): short, plain, true; no
// apologies, no internal words; name the action that fixes the state.

nonisolated enum AuthCopy {

    // MARK: Server error codes (GoTrue `error_code`, read from the SDK's `AuthError.errorCode`)

    /// The message for a GoTrue error code, or nil when the code has no specific copy.
    static func message(forCode code: String?, weakPasswordReasons: [String] = [], german: Bool) -> String? {
        guard let code = code?.lowercased(), !code.isEmpty else { return nil }
        switch code {
        case "invalid_credentials":
            return german ? "E-Mail-Adresse oder Passwort ist falsch." : "Incorrect email or password."
        case "user_already_exists", "email_exists":
            return german
                ? "Für diese E-Mail-Adresse gibt es schon ein Konto. Melde dich stattdessen an."
                : "An account with this email already exists. Sign in instead."
        case "weak_password":
            if weakPasswordReasons.contains(where: { $0.lowercased() == "pwned" }) {
                return german
                    ? "Dieses Passwort ist in einem Datenleck aufgetaucht. Wähle ein anderes."
                    : "This password appeared in a data breach. Choose another one."
            }
            return german
                ? "Wähle ein stärkeres Passwort mit mindestens 8 Zeichen."
                : "Choose a stronger password with at least 8 characters."
        case "same_password":
            return german
                ? "Wähle ein anderes Passwort als dein bisheriges."
                : "Choose a password that's different from your current one."
        case "over_email_send_rate_limit":
            return german
                ? "Zu viele E-Mails angefordert. Versuche es in ein paar Minuten erneut."
                : "Too many emails requested. Try again in a few minutes."
        case "over_request_rate_limit", "http_429":
            return german
                ? "Zu viele Versuche. Warte einen Moment und versuche es erneut."
                : "Too many attempts. Wait a moment and try again."
        case "email_not_confirmed":
            return german
                ? "Bestätige zuerst deine E-Mail-Adresse. Der Link ist in deinem Postfach."
                : "Confirm your email first. The link is in your inbox."
        case "otp_expired", "flow_state_expired", "flow_state_not_found", "bad_code_verifier",
             "pkce_grant_code_exchange", "access_denied":
            return linkMessage(.expired, german: german)
        case "signup_disabled":
            return german ? "Neue Konten können gerade nicht erstellt werden." : "New accounts can't be created right now."
        case "user_banned":
            return german ? "Mit diesem Konto ist keine Anmeldung möglich." : "This account can't sign in."
        case "session_not_found", "session_expired", "refresh_token_not_found", "refresh_token_already_used":
            return german ? "Deine Sitzung ist abgelaufen. Melde dich erneut an." : "Your session ended. Sign in again."
        case "reauthentication_needed", "reauthentication_not_valid":
            return german
                ? "Melde dich zur Sicherheit erneut an und ändere dann dein Passwort."
                : "For your security, sign in again, then change your password."
        case "validation_failed":
            return german ? "Prüfe E-Mail-Adresse und Passwort." : "Check your email and password."
        case "email_address_not_authorized":
            return german
                ? "An diese Adresse kann gerade keine E-Mail gesendet werden."
                : "Email can't be sent to this address right now."
        default:
            return nil
        }
    }

    /// The last resort for an error nothing else describes.
    static func generic(german: Bool) -> String {
        german ? "Etwas ist schiefgelaufen. Versuche es erneut." : "Something went wrong. Try again."
    }

    // MARK: Transport

    enum Transport: Sendable {
        case offline, connectionLost, timedOut, unreachable
    }

    static func transport(_ kind: Transport, german: Bool) -> String {
        switch kind {
        case .offline:
            return german
                ? "Keine Internetverbindung. Prüfe deine Verbindung und versuche es erneut."
                : "No internet connection. Check your connection and try again."
        case .connectionLost:
            return german
                ? "Die Verbindung wurde unterbrochen. Versuche es erneut."
                : "The network connection was lost. Try again."
        case .timedOut:
            return german ? "Die Anfrage hat zu lange gedauert. Versuche es erneut." : "The request timed out. Try again."
        case .unreachable:
            return german
                ? "Kuro ist gerade nicht erreichbar. Versuche es erneut."
                : "Can't reach Kuro right now. Try again."
        }
    }

    // MARK: Email links

    /// Why a `kuro://auth/callback` link was not applied.
    enum LinkFailure: Equatable, Sendable {
        /// The link expired, was already used, or its flow state is gone.
        case expired
        /// No flow this device started matches the link (opened on another device, or unsolicited).
        case notRequestedHere
        /// The link names another account than the signed-in one.
        case otherAccount
        /// The link was readable but could not be applied.
        case failed
    }

    static func linkMessage(_ failure: LinkFailure, german: Bool) -> String {
        switch failure {
        case .expired:
            return german
                ? "Dieser Link ist abgelaufen oder wurde auf einem anderen Gerät geöffnet. Fordere auf diesem Gerät einen neuen an."
                : "This link has expired or was opened on another device. Request a new one on this device."
        case .notRequestedHere:
            return german
                ? "Dieser Link wurde nicht auf diesem Gerät angefordert. Fordere hier einen neuen an und nutze die neueste E-Mail."
                : "This link wasn't requested on this device. Request a new one here and use the most recent email."
        case .otherAccount:
            return german
                ? "Dieser Link gehört nicht zum angemeldeten Konto. Melde dich zuerst ab und öffne den Link dann erneut."
                : "This link doesn't match the account you're signed in to. Sign out first, then open the link again."
        case .failed:
            return german
                ? "Der Link konnte nicht geöffnet werden. Fordere einen neuen an."
                : "The link couldn't be opened. Request a new one."
        }
    }

    // MARK: Neutral notices

    /// Enumeration-safe reset confirmation (shown whether or not an account exists).
    static func resetSent(email: String, german: Bool) -> String {
        german
            ? "Falls es ein Konto für \(email) gibt, ist ein Link unterwegs. Nutze die neueste E-Mail."
            : "If an account exists for \(email), a reset link is on its way. Use the most recent email."
    }

    static func signUpNeedsConfirmation(german: Bool) -> String {
        german
            ? "Schau in dein Postfach und bestätige deine E-Mail-Adresse. Melde dich danach an."
            : "Check your inbox to confirm your email, then sign in."
    }

    static func passwordUpdated(german: Bool) -> String {
        german ? "Passwort aktualisiert." : "Password updated."
    }

    static func appleDidNotComplete(german: Bool) -> String {
        german
            ? "Die Anmeldung mit Apple wurde nicht abgeschlossen. Versuche es erneut."
            : "Sign in with Apple didn't complete. Try again."
    }
}

// MARK: - Form rules

nonisolated enum AuthFormRules {
    /// Sign-up minimum (sign-in accepts any non-empty password: older accounts may predate the rule).
    static let minimumPasswordLength = 8

    private static let emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/

    static func trimmedEmail(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func emailLooksValid(_ raw: String) -> Bool {
        trimmedEmail(raw).wholeMatch(of: emailPattern) != nil
    }

    static func passwordMeetsSignUpRule(_ password: String) -> Bool {
        password.count >= minimumPasswordLength
    }

    enum Mode: Sendable { case signIn, signUp }

    /// Why the form can't be submitted yet, or nil when it can.
    enum Problem: Equatable, Sendable {
        case emailMissing, emailInvalid, passwordMissing, passwordTooShort
    }

    static func problem(mode: Mode, email: String, password: String) -> Problem? {
        let email = trimmedEmail(email)
        if email.isEmpty { return .emailMissing }
        if !emailLooksValid(email) { return .emailInvalid }
        if password.isEmpty { return .passwordMissing }
        if mode == .signUp, !passwordMeetsSignUpRule(password) { return .passwordTooShort }
        return nil
    }

    static func message(for problem: Problem, german: Bool) -> String {
        switch problem {
        case .emailMissing: return german ? "Gib deine E-Mail-Adresse ein." : "Enter your email to continue."
        case .emailInvalid: return german ? "Gib eine gültige E-Mail-Adresse ein." : "Enter a valid email address."
        case .passwordMissing: return german ? "Gib dein Passwort ein." : "Enter your password."
        case .passwordTooShort: return german ? "Verwende mindestens 8 Zeichen." : "Use at least 8 characters."
        }
    }

    /// The set-new-password form.
    enum NewPasswordProblem: Equatable, Sendable {
        case tooShort, mismatch
    }

    static func newPasswordProblem(_ password: String, confirmation: String) -> NewPasswordProblem? {
        if !passwordMeetsSignUpRule(password) { return .tooShort }
        if password != confirmation { return .mismatch }
        return nil
    }

    static func message(for problem: NewPasswordProblem, german: Bool) -> String {
        switch problem {
        case .tooShort: return german ? "Verwende mindestens 8 Zeichen." : "Use at least 8 characters."
        case .mismatch: return german ? "Die Passwörter stimmen nicht überein." : "The passwords don't match."
        }
    }
}
