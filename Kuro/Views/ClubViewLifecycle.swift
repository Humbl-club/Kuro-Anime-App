import Foundation

// MARK: - Club detail lifecycle rules

/// The decisions of `ClubDetailView`'s lifecycle, as a pure value the view keeps in `@State`: when
/// to open and close the club's realtime channel, and how to answer a membership loss or a
/// revocation of the club (`ClubsStore.revocationEpoch`). The view feeds it events and performs
/// what it returns; strings, toasts and the 0.5 s dismissal stay in the view.
///
/// Realtime:
/// - The channel is opened after the initial load, only if the task was not cancelled (the view did
///   not disappear) and the membership has not ended.
/// - On disappear the view stops ITS club's channel (keyed: another club's channel is never touched).
/// - When the subscribe returns, the channel is stopped again if the membership ended meanwhile, or if
///   the task was cancelled and the view is off screen. A view that is back on screen keeps the
///   channel: its new task owns it.
///
/// Membership loss and revocation:
/// - Every response drops the view's copies of the club's data: bundle, loading snapshot, optimistic
///   votes and shared providers, and closes the club's sheets. The rails' optimistic reactions live
///   inside the bundle's content and go with it.
/// - A notice and a dismissal happen at most once per view; after that, loads are not run again and
///   later answers or signals only drop residual state.
/// - A revocation while no club is shown only drops state (the load in flight reports its own
///   answer).
/// - A revocation during a leave from the settings sheet closes the club without the "removed" toast.
struct ClubDetailLifecycle: Equatable {
    /// What the view shows when the membership ends.
    enum Notice: Equatable {
        /// "You're no longer a member of this club." plus the "You were removed" toast.
        case removed
        /// "You're not a member of this club yet — ask for an invite." (phase and toast).
        case notYetMember
        /// "You're no longer a member of this club." without a toast (left from the settings sheet).
        case left
        /// "This club no longer exists." without a toast; the view stays open.
        case clubGone

        /// Whether the notice comes with a toast.
        var showsToast: Bool {
            switch self {
            case .removed, .notYetMember: return true
            case .left, .clubGone: return false
            }
        }
    }

    /// The answer to a membership loss or a revocation.
    struct LossResponse: Equatable {
        /// Drop the view's copies of the club's data and close its sheets.
        var dropsLocalState: Bool
        /// The notice to show; nil keeps what is on screen.
        var notice: Notice?
        /// Dismiss the club view (after the view's short delay).
        var dismisses: Bool

        /// Nothing new to show: only the residual state is dropped.
        static let dropOnly = LossResponse(dropsLocalState: true, notice: nil, dismisses: false)
    }

    /// What the task does after the realtime subscribe returned.
    struct AfterSubscribe: Equatable {
        /// Stop this club's channel.
        var stopsOwnChannel: Bool
        /// Go on with the rest of the task (shared providers).
        var continuesTask: Bool
    }

    /// Whether the view is on screen (`onAppear` / `onDisappear`).
    private(set) var isOnScreen = false
    /// The membership ended (or the club is gone) while this view was open: the club is closing.
    private(set) var membershipEnded = false
    /// The settings sheet is leaving the club (a voluntary leave, not a removal).
    private(set) var isLeaving = false

    // MARK: Realtime

    mutating func appeared() {
        isOnScreen = true
    }

    /// The view disappeared. Returns whether to stop this club's channel: always (the stop is keyed
    /// by the club, so it never closes another club's channel).
    mutating func disappeared() -> Bool {
        isOnScreen = false
        return true
    }

    /// Whether the task opens the club's channel after its initial load.
    func shouldSubscribe(taskCancelled: Bool) -> Bool {
        !taskCancelled && !membershipEnded
    }

    /// What the task does once the subscribe returned.
    func afterSubscribe(taskCancelled: Bool) -> AfterSubscribe {
        AfterSubscribe(
            stopsOwnChannel: membershipEnded || (taskCancelled && !isOnScreen),
            continuesTask: !taskCancelled && !membershipEnded
        )
    }

    // MARK: Loads

    /// Whether a load may run, and whether a load's answer may still change what is shown.
    var acceptsLoads: Bool {
        !membershipEnded
    }

    // MARK: Membership loss and revocation

    /// The settings sheet started (`true`) or failed (`false`) to leave the club.
    mutating func leavingChanged(_ leaving: Bool) {
        isLeaving = leaving
    }

    /// A club request answered with a membership loss (NOT_A_MEMBER or permission denied).
    /// `showsClub`: a bundle is on screen (the caller was a member and lost access); otherwise the
    /// caller was never a member (e.g. a `kuro://club/<uuid>` link).
    mutating func membershipLost(showsClub: Bool) -> LossResponse {
        guard !membershipEnded else { return .dropOnly }
        membershipEnded = true
        return LossResponse(dropsLocalState: true, notice: showsClub ? .removed : .notYetMember, dismisses: true)
    }

    /// A club request answered CLUB_NOT_FOUND: the club was deleted. The view stays open with the notice.
    mutating func clubGone() -> LossResponse {
        guard !membershipEnded else { return .dropOnly }
        membershipEnded = true
        return LossResponse(dropsLocalState: true, notice: .clubGone, dismisses: false)
    }

    /// `ClubsStore` revoked the club (its revocation epoch changed). `showsClub`: a bundle is on screen.
    mutating func revoked(showsClub: Bool) -> LossResponse {
        guard showsClub, !membershipEnded else { return .dropOnly }
        guard isLeaving else { return membershipLost(showsClub: true) }
        membershipEnded = true
        return LossResponse(dropsLocalState: true, notice: .left, dismisses: true)
    }
}

// MARK: - Add-to-club sheet revocation rule

/// `AddToClubRailSheet` watches the selected club's revocation epoch, which also changes when the
/// user picks another club. Only a change of the selected club's own epoch, compared with the epoch
/// captured when it was selected, is a revocation.
enum ClubSelectionRevocation {
    /// `current`: the selected club's epoch now (nil: no club selected); `captured`: its epoch when
    /// it was selected.
    static func isRevocation<Epoch: Equatable>(current: Epoch?, captured: Epoch?) -> Bool {
        guard let current else { return false }
        return current != captured
    }
}

// MARK: - Clubs list card display rules

/// Pure display rules for `JournalClubCard` on the Clubs list page.
enum ClubsListCardRules {
    /// Private clubs show member count only (clubs spec): never list member name initials.
    /// Status and progress clubs keep up to the names the list row already carries.
    static func memberInitials(sharingLevel: String, memberNames: [String]?) -> [String] {
        guard sharingLevel.lowercased() != "private" else { return [] }
        return (memberNames ?? []).map { String($0.prefix(1)).uppercased() }
    }
}

extension ClubsListCardRules {
    /// The honest audience label of a club (what members can see of each other), EN/DE.
    static func audienceLabel(sharingLevel: String, german: Bool) -> String {
        switch sharingLevel.lowercased() {
        case "private": return german ? "Nur Summen" : "Totals only"
        case "status": return german ? "Status geteilt" : "Statuses shared"
        case "progress": return german ? "Fortschritt geteilt" : "Progress shared"
        default: return german ? "Privat" : "Private"
        }
    }

    /// "1 member" / "5 members" (DE "1 Mitglied" / "5 Mitglieder"); nil when the count is unknown.
    static func memberCountText(_ count: Int?, german: Bool) -> String? {
        guard let count, count > 0 else { return nil }
        if german { return count == 1 ? "1 Mitglied" : "\(count) Mitglieder" }
        return count == 1 ? "1 member" : "\(count) members"
    }

    /// The one recent line a card may show: the server's activity preview, trimmed, or nothing.
    static func recentLine(_ preview: String?) -> String? {
        guard let trimmed = preview?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// The VoiceOver label of a club card: name, members, audience, unread, then the recent line.
    static func accessibilityLabel(name: String, memberCount: Int?, sharingLevel: String,
                                   hasUnseen: Bool, recentLine: String?, german: Bool) -> String {
        var parts = [name]
        if let members = memberCountText(memberCount, german: german) { parts.append(members) }
        parts.append(audienceLabel(sharingLevel: sharingLevel, german: german))
        if hasUnseen { parts.append(german ? "Neue Aktivität" : "New activity") }
        if let recentLine { parts.append(recentLine) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Clubs list states

/// What the Clubs list shows. A failed or offline read never shows the "create your first club"
/// invitation (rulebook §9: a failure never renders as a successful empty state).
nonisolated enum ClubsListState: Equatable, Sendable {
    case loading
    /// A successful read returned no clubs: the Create / Join invitation.
    case empty
    /// The clubs, optionally with an inline notice above them (the last refresh failed).
    case list(notice: Notice?)
    /// No connection and no clubs on screen.
    case offline
    /// The read failed and no clubs are on screen.
    case failed

    nonisolated enum Notice: Equatable, Sendable { case offline, failed }
}

nonisolated enum ClubsListRules {
    static func state(phase: MyClubsPhase, hasClubs: Bool, isConnected: Bool) -> ClubsListState {
        let settled = phase.settled
        if hasClubs {
            if case let .failed(transport) = settled {
                return .list(notice: (!isConnected || transport) ? .offline : .failed)
            }
            return .list(notice: nil)
        }
        switch phase {
        case .loading, .idle:
            // Offline with nothing read yet: say so instead of spinning.
            if !isConnected, !phase.isLoading { return .offline }
            return .loading
        case .loaded:
            return .empty
        case let .failed(transport):
            return (!isConnected || transport) ? .offline : .failed
        }
    }
}

// MARK: - Invite codes

/// Invite codes are 8 characters from [A-Za-z0-9], compared exactly (case-sensitive) by `join_club`.
nonisolated enum ClubInviteCode {
    static let length = 8

    /// The code inside typed or pasted text: the part after `join/` in an invite link, else the one
    /// 8-character alphanumeric word in a message, else the text's letters and digits. Case is kept;
    /// the result is at most `length` characters.
    static func normalize(_ raw: String) -> String {
        if let range = raw.range(of: "join/", options: .caseInsensitive) {
            let tail = raw[range.upperBound...]
            let code = String(tail.prefix { isCodeCharacter($0) })
            if !code.isEmpty { return String(code.prefix(length)) }
        }
        let words = raw.split { !isCodeCharacter($0) }.map(String.init)
        let candidates = Set(words.filter { $0.count == length })
        if words.count > 1, candidates.count == 1, let only = candidates.first {
            return only
        }
        return String(raw.filter(isCodeCharacter).prefix(length))
    }

    static func isValid(_ code: String) -> Bool {
        code.count == length && code.allSatisfy(isCodeCharacter)
    }

    /// Inline guidance while typing; nil when empty or complete.
    static func hint(for code: String, german: Bool) -> String? {
        guard !code.isEmpty, code.count < length else { return nil }
        let missing = length - code.count
        if german { return missing == 1 ? "Noch 1 Zeichen." : "Noch \(missing) Zeichen." }
        return missing == 1 ? "1 more character." : "\(missing) more characters."
    }

    private static func isCodeCharacter(_ c: Swift.Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber)
    }
}

// MARK: - Club copy (EN/DE)

/// User-facing club copy for typed failures. Never shows a server code or SDK text.
nonisolated enum ClubCopy {
    static func joinError(_ error: ClubError?, german: Bool) -> String {
        switch error {
        case .invalidCode?: return german ? "Diesen Code gibt es nicht. Prüf Groß- und Kleinschreibung." : "That code doesn't exist. Check upper and lower case."
        case .codeExpired?: return german ? "Dieser Code ist abgelaufen. Bitte um einen neuen." : "This code has expired. Ask for a new one."
        case .codeExhausted?: return german ? "Dieser Code wurde zu oft benutzt. Bitte um einen neuen." : "This code has been used up. Ask for a new one."
        case .clubArchived?: return german ? "Dieser Club ist nicht mehr aktiv." : "This club is no longer active."
        case .clubFull?: return german ? "Dieser Club ist voll." : "This club is full."
        case .alreadyMember?: return german ? "Du bist schon Mitglied." : "You're already a member."
        case .rateLimited?: return german ? "Zu viele Versuche. Warte kurz." : "Too many tries. Wait a moment."
        default: return german ? "Beitreten hat nicht geklappt. Versuch es noch einmal." : "Couldn't join. Try again."
        }
    }

    static func createClubError(_ error: ClubError?, german: Bool) -> String {
        switch error {
        case .invalidName?: return german ? "Der Name braucht 1 bis 80 Zeichen." : "The name needs 1 to 80 characters."
        case .descriptionTooLong?: return german ? "Die Beschreibung darf höchstens 500 Zeichen haben." : "The description can have up to 500 characters."
        case .rateLimited?: return german ? "Zu viele Versuche. Warte kurz." : "Too many tries. Wait a moment."
        case .tooManyClubs?: return german ? "Du hast die Höchstzahl an Clubs erreicht." : "You've reached the club limit."
        default: return german ? "Der Club wurde nicht erstellt. Versuch es noch einmal." : "Couldn't create the club. Try again."
        }
    }

    static func createRailError(_ error: ClubError?, german: Bool) -> String {
        switch error {
        case .descriptionTooLong?: return german ? "Die Beschreibung darf höchstens 500 Zeichen haben." : "The description can have up to 500 characters."
        case .notAMember?, .permissionDenied?: return german ? "Nur Admins können Listen anlegen." : "Only admins can create rails."
        case .rateLimited?: return german ? "Zu viele Versuche. Warte kurz." : "Too many tries. Wait a moment."
        default: return german ? "Die Liste wurde nicht erstellt. Versuch es noch einmal." : "Couldn't create the rail. Try again."
        }
    }

    static func createPollError(_ error: ClubError?, german: Bool) -> String {
        switch error {
        case .notAMember?, .permissionDenied?: return german ? "Nur Admins können Umfragen starten." : "Only admins can start polls."
        case .rateLimited?: return german ? "Zu viele Versuche. Warte kurz." : "Too many tries. Wait a moment."
        default: return german ? "Die Umfrage wurde nicht erstellt. Versuch es noch einmal." : "Couldn't create the poll. Try again."
        }
    }

    static func addRailItemError(_ error: ClubError?, german: Bool) -> String {
        switch error {
        case .duplicateItem?, .uniqueViolation?: return german ? "Der Titel ist schon in dieser Liste." : "This title is already in this rail."
        case .notAMember?: return german ? "Du bist nicht mehr Mitglied dieses Clubs." : "You're no longer a member of this club."
        case .railLocked?: return german ? "Diese Liste ist gesperrt. Nur Admins können etwas hinzufügen." : "This rail is locked. Only admins can add to it."
        case .mediaNotFound?: return german ? "Diesen Titel gibt es im Katalog nicht." : "This title isn't in the catalogue."
        case .unauthenticated?: return german ? "Melde dich erneut an." : "Sign in again to continue."
        case .noteTooLong?: return german ? "Die Notiz ist zu lang." : "The note is too long."
        case .railNotFound?: return german ? "Diese Liste gibt es nicht mehr." : "This rail no longer exists."
        default: return german ? "Hinzufügen hat nicht geklappt. Versuch es noch einmal." : "Couldn't add it. Try again."
        }
    }

    /// The "members can see" sentence for a sharing level.
    static func sharingDescription(_ sharingLevel: String, german: Bool) -> String {
        switch sharingLevel.lowercased() {
        case "private": return german ? "Mitglieder sehen nur Summen, keine Einzelheiten." : "Members see totals only, never each other's details."
        case "status": return german ? "Mitglieder sehen, was jemand schaut oder liest, aber keine Folgen." : "Members see what each other is watching or reading, not episode numbers."
        case "progress": return german ? "Mitglieder sehen Status, Fortschritt und Bewertungen." : "Members see status, progress and ratings."
        default: return ""
        }
    }
}

// MARK: - Club detail issues

/// Why the club detail cannot show the club (initial load) or could not refresh it.
nonisolated enum ClubDetailIssue: Equatable, Sendable {
    case offline
    case timedOut
    case failed
    /// The caller was a member and lost access.
    case removed
    /// The caller was never a member (e.g. a `kuro://club/<id>` link).
    case notYetMember
    /// The caller left from the settings sheet.
    case left
    case clubGone

    /// A load failure that is not a membership answer.
    static func forLoadError(_ error: any Error, isConnected: Bool) -> ClubDetailIssue {
        if !isConnected { return .offline }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: return .offline
            case .timedOut: return .timedOut
            default: return .failed
            }
        }
        return .failed
    }

    /// A membership answer: the state view kind is `.denied`, not a failure with Retry.
    var isMembership: Bool {
        switch self {
        case .removed, .notYetMember, .left, .clubGone: return true
        case .offline, .timedOut, .failed: return false
        }
    }

    func title(german: Bool) -> String {
        switch self {
        case .offline: return "Offline."
        case .timedOut: return german ? "Das hat zu lange gedauert." : "That took too long."
        case .failed: return german ? "Der Club konnte nicht geladen werden." : "Couldn't load this club."
        case .removed, .left: return german ? "Du bist nicht mehr Mitglied." : "You're no longer a member."
        case .notYetMember: return german ? "Du bist noch kein Mitglied." : "You're not a member yet."
        case .clubGone: return german ? "Diesen Club gibt es nicht mehr." : "This club no longer exists."
        }
    }

    func message(german: Bool, hasContent: Bool) -> String? {
        switch self {
        case .offline:
            if hasContent { return german ? "Du siehst den letzten Stand." : "Showing what you saw last." }
            return german ? "Verbinde dich, um den Club zu laden." : "Connect to load this club."
        case .timedOut, .failed:
            if hasContent { return german ? "Deine bisherigen Daten bleiben erhalten." : "What you had is still here." }
            return german ? "Versuch es gleich noch einmal." : "Try again in a moment."
        case .removed, .left: return german ? "Clubaktivität ist nur für Mitglieder sichtbar." : "Club activity is private to members."
        case .notYetMember: return german ? "Bitte um eine Einladung." : "Ask a member for an invite."
        case .clubGone: return nil
        }
    }
}

// MARK: - Reactions

/// The four stored reaction keys and how they are drawn: monochrome SF Symbols (rulebook §11: no
/// emoji), with spoken names. The keys are the server contract and never change.
nonisolated enum ClubReactionGlyph {
    static let keys = ["fire", "heart", "eyes", "100"]

    /// SF Symbol for a key; nil for "100", which is drawn as the number itself.
    static func symbol(for key: String) -> String? {
        switch key {
        case "fire": return "flame"
        case "heart": return "heart"
        case "eyes": return "eyes"
        default: return nil
        }
    }

    static func spokenName(for key: String, german: Bool) -> String {
        switch key {
        case "fire": return german ? "Feuer" : "Fire"
        case "heart": return german ? "Herz" : "Heart"
        case "eyes": return german ? "Augen" : "Eyes"
        case "100": return german ? "Hundert" : "Hundred"
        default: return key
        }
    }
}
