import Foundation
import KuroCore

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

/// Pure display rules for the club rooms on the Clubs list page.
nonisolated enum ClubsListCardRules {
    /// Private clubs show member count only (clubs spec): never list member name initials.
    /// Status and progress clubs keep up to the names the list row already carries.
    static func memberInitials(sharingLevel: String, memberNames: [String]?) -> [String] {
        guard sharingLevel.lowercased() != "private" else { return [] }
        return (memberNames ?? []).map { String($0.prefix(1)).uppercased() }
    }
}

nonisolated extension ClubsListCardRules {
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

    /// The one recent line a card may show, localized. The server builds `activity_preview` as English
    /// text from three known prefixes ('Added: ', 'Poll: ', 'Vote on: ' plus a title or question);
    /// those are re-worded in EN/DE around the label. Anything else is nil: raw server text never shows.
    static func recentLine(_ preview: String?, german: Bool) -> String? {
        guard let trimmed = preview?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        func label(after prefix: String) -> String? {
            guard trimmed.hasPrefix(prefix) else { return nil }
            let rest = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            return rest.isEmpty ? nil : rest
        }
        if let title = label(after: "Added:") {
            return german ? "Neu: \(title)" : "Added \(title)"
        }
        if let question = label(after: "Vote on:") {
            return german ? "Abstimmung: \(question)" : "Vote on \(question)"
        }
        if let question = label(after: "Poll:") {
            return german ? "Umfrage: \(question)" : "Poll: \(question)"
        }
        return nil
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

// MARK: - Leave confirmation copy

/// The confirmation text before leaving a club (settings sheet). Pure, so the deletion and successor
/// lines are decided from what the server actually disclosed.
///
/// `fetch_club_bundle` lists only the caller in `members` for a private club or a club with fewer
/// than three members, so the list alone cannot tell "only member" from "list withheld":
/// - deletion is announced only when `memberCount <= 1` (the server deletes a club whose last member
///   leaves);
/// - a successor is named only when the list is complete (`members.count == memberCount`), using
///   the server's rule (`_club_member_depart`: oldest admin, else oldest member);
/// - otherwise the line stays generic ("Another member will become the owner.").
enum ClubLeaveCopy {
    static func message(clubName: String, myRole: String, memberCount: Int,
                        members: [ClubMember], german: Bool) -> String {
        let rejoin = german ? "Zum Wiederkommen brauchst du einen neuen Einladungscode." : "You'll need a new invite code to rejoin."
        guard myRole == "owner" else {
            return german ? "\(clubName) verlassen? \(rejoin)" : "Leave \(clubName)? \(rejoin)"
        }
        if memberCount <= 1 {
            return german ? "Du bist das einzige Mitglied. Der Club wird gelöscht." : "You're the only member. The club will be deleted."
        }
        let generic = german ? "Ein anderes Mitglied wird Inhaber:in des Clubs. \(rejoin)" : "Another member will become the owner. \(rejoin)"
        guard members.count == memberCount else { return generic }
        let others = members.filter { $0.role != "owner" }
        let admins = others.filter { $0.role == "admin" }.sorted { $0.joined_at < $1.joined_at }
        let successor = admins.first ?? others.sorted { $0.joined_at < $1.joined_at }.first
        if let name = successor?.display_name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return german ? "\(name) wird Inhaber:in des Clubs. \(rejoin)" : "\(name) will become the owner. \(rejoin)"
        }
        return generic
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

extension ClubsListState {
    /// The branded state (prototype-fidelity Task 9) the Clubs page draws for this list state; `nil`
    /// draws the clubs with no notice. The invitation is `.empty`; a failed or offline read keeps its
    /// own state and never becomes the invitation. `ClubsView.content` switches on this value.
    var brandedState: KuroBrandedState? {
        switch self {
        case .loading: return .loading
        case .empty: return .empty
        case .offline: return .offline(hasContent: false)
        case .failed: return .failed(hasContent: false)
        case .list(notice: nil): return nil
        case .list(notice: .offline): return .offline(hasContent: true)
        case .list(notice: .failed): return .failed(hasContent: true)
        }
    }
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

    /// The branded state of a club that could not open with nothing on screen (prototype-fidelity
    /// Task 9): offline, or a failure (the ridge drawn once, Try again). `nil` for a membership answer,
    /// which is a notice (`KuroStateView(.denied)`) with no Retry. `ClubDetailInitialState` switches on it.
    var brandedState: KuroBrandedState? {
        switch self {
        case .offline: return .offline(hasContent: false)
        case .timedOut, .failed: return .failed(hasContent: false)
        case .removed, .notYetMember, .left, .clubGone: return nil
        }
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

    /// The symbol when the reaction is yours (filled where SF Symbols has a filled form).
    static func selectedSymbol(for key: String) -> String? {
        switch key {
        case "fire": return "flame.fill"
        case "heart": return "heart.fill"
        case "eyes": return "eyes.inverse"
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

// MARK: - Room and rail copy (EN/DE)

nonisolated enum ClubRoomCopy {
    /// "5 members · 3 rails · 1 open poll" (only real, non-zero counts after members).
    static func summary(memberCount: Int, railCount: Int, openPolls: Int, german: Bool) -> String {
        var parts: [String] = []
        if let members = ClubsListCardRules.memberCountText(memberCount, german: german) { parts.append(members) }
        if railCount > 0 {
            parts.append(german ? (railCount == 1 ? "1 Liste" : "\(railCount) Listen")
                                : (railCount == 1 ? "1 rail" : "\(railCount) rails"))
        }
        if openPolls > 0 {
            parts.append(german ? (openPolls == 1 ? "1 offene Umfrage" : "\(openPolls) offene Umfragen")
                                : (openPolls == 1 ? "1 open poll" : "\(openPolls) open polls"))
        }
        return parts.joined(separator: " · ")
    }

    struct Note: Equatable, Sendable {
        let text: String
        let author: String?
        let title: String
        let itemId: String
    }

    /// Member notes of a rail, in rail order (non-empty only). `author` is the adding member's
    /// display name when the bundle discloses it.
    static func notes(in rail: ClubRail, members: [ClubMember]) -> [Note] {
        rail.items.compactMap { item in
            guard let text = item.note?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            let author = item.added_by.flatMap { id in
                members.first { $0.user_id == id }?.display_name?.trimmingCharacters(in: .whitespacesAndNewlines)
            }.flatMap { $0.isEmpty ? nil : $0 }
            return Note(text: text, author: author, title: item.title_display, itemId: item.id)
        }
    }

    /// The room's one pull-quote: the first member note in rail order, or nothing.
    static func firstNote(in bundle: ClubBundle) -> Note? {
        for rail in bundle.rails {
            if let note = notes(in: rail, members: bundle.members).first { return note }
        }
        return nil
    }

    static func titleCount(_ count: Int, german: Bool) -> String {
        german ? (count == 1 ? "1 Titel" : "\(count) Titel") : (count == 1 ? "1 title" : "\(count) titles")
    }

    /// "Ep. 3 of 12" / "F. 3 von 12", "Ch. 40" / "Kap. 40"; nil without progress.
    static func progress(_ progress: Int?, total: Int?, isManga: Bool, german: Bool) -> String? {
        guard let progress, progress > 0 else { return nil }
        let unit = isManga ? (german ? "Kap." : "Ch.") : (german ? "F." : "Ep.")
        if let total, total > 0 {
            return german ? "\(unit) \(progress) von \(total)" : "\(unit) \(progress) of \(total)"
        }
        return "\(unit) \(progress)"
    }

    /// "Mia, Jo watching" / "Mia, Jo +3"; nil when nobody is current. Names come only from the
    /// statuses the server disclosed for this club's sharing level.
    static func membersCurrent(names: [String?], isManga: Bool, german: Bool) -> String? {
        guard !names.isEmpty else { return nil }
        let known = names.prefix(2).compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let verb: String = isManga ? (german ? "lesen" : "reading") : (german ? "schauen" : "watching")
        let verbOne: String = isManga ? (german ? "liest" : "reading") : (german ? "schaut" : "watching")
        if known.isEmpty { return "\(names.count) \(verb)" }
        if names.count > 2 { return known.joined(separator: ", ") + " +\(names.count - 2)" }
        return known.joined(separator: ", ") + " " + (names.count == 1 ? verbOne : verb)
    }
}

/// The sentence of one member activity row, split around the title so the title can be set apart.
nonisolated enum ClubActivityProse {
    struct Parts: Equatable, Sendable {
        let beforeTitle: String
        let afterTitle: String
    }

    static func parts(status: String?, progress: Int?, isManga: Bool, german: Bool) -> Parts {
        let unit = isManga ? (german ? "Kapitel" : "chapter") : (german ? "Folge" : "episode")
        switch status?.uppercased() ?? "" {
        case "COMPLETED":
            return german ? Parts(beforeTitle: " hat ", afterTitle: " beendet") : Parts(beforeTitle: " finished ", afterTitle: "")
        case "CURRENT", "WATCHING", "READING":
            if let progress, progress > 0 {
                return german ? Parts(beforeTitle: " ist bei \(unit) \(progress) von ", afterTitle: "")
                              : Parts(beforeTitle: " reached \(unit) \(progress) of ", afterTitle: "")
            }
            if german { return Parts(beforeTitle: isManga ? " liest jetzt " : " schaut jetzt ", afterTitle: "") }
            return Parts(beforeTitle: isManga ? " started reading " : " started watching ", afterTitle: "")
        case "PAUSED":
            return german ? Parts(beforeTitle: " pausiert ", afterTitle: "") : Parts(beforeTitle: " paused ", afterTitle: "")
        case "DROPPED":
            return german ? Parts(beforeTitle: " hat ", afterTitle: " abgebrochen") : Parts(beforeTitle: " dropped ", afterTitle: "")
        case "PLANNING", "PLANNED":
            if german { return Parts(beforeTitle: " hat ", afterTitle: " vorgemerkt") }
            return Parts(beforeTitle: isManga ? " plans to read " : " plans to watch ", afterTitle: "")
        default:
            return german ? Parts(beforeTitle: " hat ", afterTitle: " aktualisiert") : Parts(beforeTitle: " updated ", afterTitle: "")
        }
    }
}

// MARK: - Club room rules (Discover + Clubs redesign, spec §7)

/// ISO-8601 timestamps as the club RPCs send them (with or without fractional seconds); nil when
/// unreadable. A nonisolated twin of `ClubsStore.parseISO8601` for the pure rules below.
nonisolated enum ClubDates {
    /// Built once: the club page parses these on every body pass and in the list's sort comparator.
    /// `ISO8601DateFormatter` is thread-safe for parsing once configured.
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let basic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ raw: String) -> Date? {
        fractional.date(from: raw) ?? basic.date(from: raw)
    }
}

/// Who sees what on a club, and the list's order (pure; DCclubsTests).
nonisolated enum ClubRoomRules {
    /// Owners and admins: the roles `fetch_club_bundle` sends `invite_code` to and that may lock rails,
    /// start rails and ask polls.
    static func isAdmin(role: String) -> Bool {
        ["owner", "admin"].contains(role.lowercased())
    }

    /// The existing add rule: an unlocked rail takes titles from anyone; a locked one only from admins.
    static func canAddToRail(_ rail: ClubRail, role: String) -> Bool {
        !rail.is_locked || isAdmin(role: role)
    }

    /// The rails the viewer may add to, in rail order.
    static func addableRails(_ bundle: ClubBundle) -> [ClubRail] {
        bundle.rails.filter { canAddToRail($0, role: bundle.my_role) }
    }

    /// The labelled keys on the club page (D9, D10), in this order.
    enum Key: Equatable, Sendable, CaseIterable {
        case addTitle, startRail, invite, ask
    }

    /// Add a title when some rail takes the viewer's titles; Start a rail for admins of a club without
    /// rails; Invite only with an invite code (the server sends it to owners and admins only); Ask for
    /// admins. A member who can add nothing sees no keys.
    static func keys(role: String, rails: [ClubRail], hasInviteCode: Bool) -> [Key] {
        var keys: [Key] = []
        if rails.contains(where: { canAddToRail($0, role: role) }) { keys.append(.addTitle) }
        if rails.isEmpty, isAdmin(role: role) { keys.append(.startRail) }
        if hasInviteCode { keys.append(.invite) }
        if isAdmin(role: role) { keys.append(.ask) }
        return keys
    }

    /// Where "Add a title" goes: straight to the only eligible rail, or a chooser of several. Never a
    /// guessed `rails.first`.
    enum AddTarget: Equatable, Sendable {
        case none
        case rail(String)
        case chooser([String])
    }

    static func addTarget(rails: [ClubRail], role: String) -> AddTarget {
        let ids = rails.filter { canAddToRail($0, role: role) }.map(\.id)
        switch ids.count {
        case 0: return .none
        case 1: return .rail(ids[0])
        default: return .chooser(ids)
        }
    }

    /// User ids are compared case-insensitively (the app lowercases them elsewhere).
    static func isViewer(_ userId: String?, viewerId: String?) -> Bool {
        guard let userId, let viewerId, !viewerId.isEmpty else { return false }
        return userId.lowercased() == viewerId.lowercased()
    }

    /// The members other than the viewer, in the server's order (D13: "You" is its own ring).
    static func otherMembers(_ members: [ClubMember], viewerId: String?) -> [ClubMember] {
        members.filter { !isViewer($0.user_id, viewerId: viewerId) }
    }

    /// The list's order (D7): newest `last_activity_at` first; clubs without a date last, in the
    /// server's order.
    static func sortedForList(_ rows: [ClubListRow]) -> [ClubListRow] {
        rows.enumerated().sorted { lhs, rhs in
            let l = lhs.element.last_activity_at.flatMap(ClubDates.parse)
            let r = rhs.element.last_activity_at.flatMap(ClubDates.parse)
            switch (l, r) {
            case let (l?, r?) where l != r: return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    /// How a rail item shows its member note (D11): the first note in rail order lives in the hero
    /// card, so its tile links up to it; every other note sits under its own tile, spoiler-gated.
    enum NotePlacement: Equatable, Sendable {
        case none
        case linkToHero
        case inline
    }

    static func notePlacement(itemId: String, note: String?, firstNoteItemId: String?) -> NotePlacement {
        guard let text = note?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return .none }
        return itemId == firstNoteItemId ? .linkToHero : .inline
    }
}

// MARK: - This week (D12)

/// The club's member updates as "This week" groups them (pure; DCclubsTests). Updates within the last
/// 7 × 24 h of device time are grouped by calendar day in Europe/Berlin; older ones, and updates
/// without a readable `updated_at`, go under "Earlier". Nothing is dropped.
nonisolated enum ClubWeekRules {
    static let window: TimeInterval = 7 * 24 * 60 * 60

    /// The club time zone does not exist; days are Berlin days (spec D12). Built once (a value).
    static let berlin: Calendar = KuroLocale.calendar(locale: Locale(identifier: "de_DE"),
                                                      timeZone: TimeZone(identifier: "Europe/Berlin") ?? .autoupdatingCurrent)

    struct Entry: Equatable, Identifiable, Sendable {
        let id: String
        let userId: String
        let displayName: String?
        let isViewer: Bool
        let titleDisplay: String
        let status: String?
        let progress: Int?
        let mediaType: String
        let mediaId: Int
        let coverImage: String?
        let updatedAt: Date?

        var isManga: Bool { mediaType.uppercased() == "MANGA" }
        /// The title the entry is about (N9: the entry opens it).
        var mediaKey: MediaKey { ClubActivityTarget.key(mediaType: mediaType, mediaId: mediaId) }
    }

    struct Day: Equatable, Identifiable, Sendable {
        /// The Berlin start of the day.
        let start: Date
        let entries: [Entry]
        var id: Date { start }
    }

    struct Partition: Equatable, Sendable {
        let thisWeek: [Day]
        let earlier: [Day]
        /// Updates without a readable date (shown last under "Earlier").
        let undated: [Entry]

        var thisWeekCount: Int { thisWeek.reduce(0) { $0 + $1.entries.count } }
        var earlierCount: Int { earlier.reduce(0) { $0 + $1.entries.count } + undated.count }
        var isEmpty: Bool { thisWeek.isEmpty && earlier.isEmpty && undated.isEmpty }
    }

    /// Every member status of every rail item, newest first.
    static func entries(in bundle: ClubBundle, viewerId: String?) -> [Entry] {
        var result: [Entry] = []
        for rail in bundle.rails {
            for item in rail.items {
                for status in item.member_statuses ?? [] {
                    let name = status.display_name?.trimmingCharacters(in: .whitespacesAndNewlines)
                    result.append(Entry(
                        id: "\(item.id)-\(status.user_id)",
                        userId: status.user_id,
                        displayName: (name?.isEmpty ?? true) ? nil : name,
                        isViewer: ClubRoomRules.isViewer(status.user_id, viewerId: viewerId),
                        titleDisplay: item.title_display,
                        status: status.status,
                        progress: status.progress,
                        mediaType: item.media_type,
                        mediaId: item.media_id,
                        coverImage: item.cover_image_medium,
                        updatedAt: status.updated_at.flatMap(ClubDates.parse)
                    ))
                }
            }
        }
        return result.enumerated().sorted { lhs, rhs in
            switch (lhs.element.updatedAt, rhs.element.updatedAt) {
            case let (l?, r?) where l != r: return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    static func partition(_ entries: [Entry], now: Date, calendar: Calendar = berlin) -> Partition {
        var week: [Entry] = []
        var older: [Entry] = []
        var undated: [Entry] = []
        for entry in entries {
            guard let date = entry.updatedAt else { undated.append(entry); continue }
            if now.timeIntervalSince(date) < window { week.append(entry) } else { older.append(entry) }
        }
        return Partition(thisWeek: days(week, calendar: calendar), earlier: days(older, calendar: calendar), undated: undated)
    }

    /// Entries (already newest first) grouped by their Berlin day, newest day first.
    private static func days(_ entries: [Entry], calendar: Calendar) -> [Day] {
        var order: [Date] = []
        var groups: [Date: [Entry]] = [:]
        for entry in entries {
            guard let date = entry.updatedAt else { continue }
            let start = calendar.startOfDay(for: date)
            if groups[start] == nil { order.append(start) }
            groups[start, default: []].append(entry)
        }
        return order.map { Day(start: $0, entries: groups[$0] ?? []) }
    }

    /// The start of the 7-day window ("since Mon 27 Oct").
    static func windowStart(now: Date) -> Date { now.addingTimeInterval(-window) }
}

/// This week's copy (EN/DE; spec §8). Dates are Berlin dates in `de_DE` / `en_GB` patterns.
nonisolated enum ClubWeekCopy {
    static func formatLocale(german: Bool) -> Locale { Locale(identifier: german ? "de_DE" : "en_GB") }

    /// Formatters are built once per template, language and time zone (the language can change while
    /// the app runs, so it is part of the key). `NSCache` is thread-safe; a configured `DateFormatter`
    /// is safe to use from any thread.
    private static let formatters = NSCache<NSString, DateFormatter>()

    private static func cached(_ key: String, make: () -> DateFormatter) -> DateFormatter {
        if let formatter = formatters.object(forKey: key as NSString) { return formatter }
        let formatter = make()
        formatters.setObject(formatter, forKey: key as NSString)
        return formatter
    }

    private static func formatter(_ template: String, german: Bool, calendar: Calendar) -> DateFormatter {
        cached("\(template)|\(german ? "de" : "en")|\(calendar.timeZone.identifier)") {
            let f = DateFormatter()
            f.locale = formatLocale(german: german)
            f.timeZone = calendar.timeZone
            f.setLocalizedDateFormatFromTemplate(template)
            return f
        }
    }

    /// "Mon 3 Nov" / "Mo. 3. Nov." (no commas).
    static func shortDate(_ date: Date, german: Bool, calendar: Calendar = ClubWeekRules.berlin) -> String {
        formatter("EEEdMMM", german: german, calendar: calendar).string(from: date).replacingOccurrences(of: ",", with: "")
    }

    /// "Today" / "Yesterday" / the weekday.
    static func dayLabel(_ day: Date, now: Date, german: Bool, calendar: Calendar = ClubWeekRules.berlin) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return german ? "Heute" : "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return german ? "Gestern" : "Yesterday"
        }
        return weekday(day, german: german, calendar: calendar)
    }

    static func weekday(_ date: Date, german: Bool, calendar: Calendar = ClubWeekRules.berlin) -> String {
        formatter("EEEE", german: german, calendar: calendar).string(from: date)
    }

    /// The date chip: day number and the 3-letter month, uppercased by the view.
    static func chip(_ date: Date, german: Bool, calendar: Calendar = ClubWeekRules.berlin) -> (day: String, month: String) {
        let day = String(calendar.component(.day, from: date))
        let month = formatter("MMM", german: german, calendar: calendar).string(from: date)
            .replacingOccurrences(of: ".", with: "")
        return (day, month)
    }

    /// 24 h "HH:mm" in Berlin.
    static func time(_ date: Date, calendar: Calendar = ClubWeekRules.berlin) -> String {
        cached("HH:mm|fixed|\(calendar.timeZone.identifier)") {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_GB")
            f.timeZone = calendar.timeZone
            f.dateFormat = "HH:mm"
            return f
        }.string(from: date)
    }

    static func updates(_ count: Int, german: Bool) -> String {
        german ? (count == 1 ? "1 Neuigkeit" : "\(count) Neuigkeiten") : (count == 1 ? "1 update" : "\(count) updates")
    }

    static func heading(german: Bool) -> String { german ? "Diese Woche." : "This week." }

    /// "5 updates since Mon 27 Oct" / "5 Neuigkeiten seit Mo. 27. Okt."
    static func summary(count: Int, since: Date, german: Bool, calendar: Calendar = ClubWeekRules.berlin) -> String {
        let date = shortDate(since, german: german, calendar: calendar)
        return german ? "\(updates(count, german: true)) seit \(date)" : "\(updates(count, german: false)) since \(date)"
    }

    /// "Since Tue 27 Oct" (a quiet week's summary: no "0 updates").
    static func since(_ date: Date, german: Bool, calendar: Calendar = ClubWeekRules.berlin) -> String {
        let day = shortDate(date, german: german, calendar: calendar)
        return german ? "Seit \(day)" : "Since \(day)"
    }

    static func earlier(german: Bool) -> String { german ? "Früher" : "Earlier" }

    static func showOlder(_ count: Int, german: Bool) -> String {
        if german { return count == 1 ? "1 ältere Neuigkeit zeigen" : "\(count) ältere Neuigkeiten zeigen" }
        return count == 1 ? "Show 1 older update" : "Show \(count) older updates"
    }

    static func hideOlder(german: Bool) -> String { german ? "Weniger zeigen" : "Show fewer" }

    /// "Quiet week. Nobody has moved on since Monday."
    static func quietWeek(since: Date, german: Bool, calendar: Calendar = ClubWeekRules.berlin) -> String {
        let day = weekday(since, german: german, calendar: calendar)
        return german ? "Ruhige Woche. Seit \(day) ist niemand weitergekommen."
                      : "Quiet week. Nobody has moved on since \(day)."
    }

    /// One update as a sentence without its title (the title is the row's second line): the subject
    /// ("You" for the viewer) and what they did.
    static func line(subject: String?, isViewer: Bool, status: String?, progress: Int?, isManga: Bool,
                     german: Bool) -> (subject: String, predicate: String) {
        let name = isViewer ? (german ? "Du" : "You")
                            : (subject ?? (german ? "Ein Mitglied" : "A member"))
        let unit = isManga ? (german ? "Kapitel" : "chapter") : (german ? "Folge" : "episode")
        let you = isViewer
        let predicate: String
        switch status?.uppercased() ?? "" {
        case "COMPLETED":
            predicate = german ? (you ? "hast es beendet" : "hat es beendet") : "finished it"
        case "CURRENT", "WATCHING", "READING":
            if let progress, progress > 0 {
                predicate = german ? (you ? "bist bei \(unit) \(progress)" : "ist bei \(unit) \(progress)")
                                   : "reached \(unit) \(progress)"
            } else if german {
                predicate = isManga ? (you ? "liest es jetzt" : "liest es jetzt") : (you ? "schaust es jetzt" : "schaut es jetzt")
            } else {
                predicate = isManga ? "started reading" : "started watching"
            }
        case "PAUSED":
            predicate = german ? (you ? "pausierst es" : "pausiert es") : "paused it"
        case "DROPPED":
            predicate = german ? (you ? "hast es abgebrochen" : "hat es abgebrochen") : "dropped it"
        case "PLANNING", "PLANNED":
            predicate = german ? (you ? "hast es vorgemerkt" : "hat es vorgemerkt")
                               : (isManga ? (you ? "plan to read it" : "plans to read it")
                                          : (you ? "plan to watch it" : "plans to watch it"))
        default:
            predicate = german ? (you ? "hast es aktualisiert" : "hat es aktualisiert") : "updated it"
        }
        return (name, predicate)
    }
}

// MARK: - Pace (existing rule, new wording)

/// The existing pace rule (a progress club with at least 3 members; the viewer is behind the median of
/// the member progress on an item), as numbers for the pace glance (pure; DCclubsTests).
nonisolated enum ClubPaceRules {
    struct Gap: Equatable, Sendable {
        let behind: Int
        let groupAt: Int
    }

    static func applies(sharingLevel: String, memberCount: Int, enabled: Bool) -> Bool {
        enabled && sharingLevel == "progress" && memberCount >= 3
    }

    /// nil when the viewer has no progress, nobody else does, or the viewer is not behind.
    static func gap(_ item: ClubRailItem) -> Gap? {
        guard let mine = item.my_progress, let statuses = item.member_statuses, !statuses.isEmpty else { return nil }
        let others = statuses.compactMap(\.progress).sorted()
        guard !others.isEmpty else { return nil }
        let count = others.count
        let median = count % 2 == 0 ? (others[count / 2 - 1] + others[count / 2]) / 2 : others[count / 2]
        let behind = median - mine
        return behind > 0 ? Gap(behind: behind, groupAt: median) : nil
    }

    static func title(_ gap: Gap, isManga: Bool, german: Bool) -> String {
        let n = gap.behind
        if german {
            let unit = isManga ? "Kapitel" : (n == 1 ? "Folge" : "Folgen")
            return "Du bist \(n) \(unit) zurück"
        }
        let unit = isManga ? (n == 1 ? "chapter" : "chapters") : (n == 1 ? "episode" : "episodes")
        return "You're \(n) \(unit) behind"
    }

    static func caption(_ gap: Gap, rail: String, title: String, isManga: Bool, german: Bool) -> String {
        if german {
            return "\(rail) · die Gruppe ist bei \(isManga ? "Kapitel" : "Folge") \(gap.groupAt) von \(title)"
        }
        return "\(rail) · the group is on \(isManga ? "Ch." : "Ep.") \(gap.groupAt) of \(title)"
    }

    static func countLabel(german: Bool) -> String { german ? "zurück" : "behind" }
}

// MARK: - Polls

/// The polls tab's copy and closed-poll summary (pure; DCclubsTests).
nonisolated enum ClubPollCopy {
    /// "YOU ASKED · CLOSES SUN 9 NOV" / "MINA ASKED" (uppercased by the view); nil without an asker.
    static func kicker(askerName: String?, isViewer: Bool, closesAt: Date?, german: Bool,
                       calendar: Calendar = ClubWeekRules.berlin) -> String? {
        let who: String?
        if isViewer { who = german ? "Deine Frage" : "You asked" }
        else if let askerName, !askerName.isEmpty { who = german ? "\(askerName) fragt" : "\(askerName) asked" }
        else { who = nil }
        let closes = closesAt.map { date in
            let day = ClubWeekCopy.shortDate(date, german: german, calendar: calendar)
            return german ? "Endet \(day)" : "Closes \(day)"
        }
        let parts = [who, closes].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func votes(_ count: Int, german: Bool) -> String {
        german ? (count == 1 ? "1 Stimme" : "\(count) Stimmen") : (count == 1 ? "1 vote" : "\(count) votes")
    }

    static func yours(german: Bool) -> String { german ? " · deine" : " · yours" }

    static func askLinkKicker(german: Bool) -> String { german ? "Admins" : "Admins" }
    static func askLinkTitle(german: Bool) -> String { german ? "Frag den Club." : "Ask the club." }

    /// "Mina asked: Sub or dub? · Sub won, 4 to 1"; "· Tied" on a tie; no outcome without votes.
    static func closedSummary(askerName: String?, isViewer: Bool, question: String,
                              options: [ClubPollOption], german: Bool) -> String {
        let prefix: String
        if isViewer { prefix = german ? "Du fragtest: " : "You asked: " }
        else if let askerName, !askerName.isEmpty { prefix = german ? "\(askerName) fragte: " : "\(askerName) asked: " }
        else { prefix = "" }
        let ranked = options.sorted { $0.vote_count > $1.vote_count }
        guard let top = ranked.first, top.vote_count > 0 else { return prefix + question }
        let second = ranked.dropFirst().first?.vote_count ?? 0
        if second == top.vote_count { return prefix + question + " · " + (german ? "Unentschieden" : "Tied") }
        // Non-breaking spaces keep the result ("Sunday won, 4 to 1") on one line.
        let outcome = german ? "\(top.label)\u{00A0}gewann,\u{00A0}\(top.vote_count)\u{00A0}zu\u{00A0}\(second)"
                             : "\(top.label)\u{00A0}won,\u{00A0}\(top.vote_count)\u{00A0}to\u{00A0}\(second)"
        return prefix + question + " · " + outcome
    }
}

// MARK: - Join (D14)

/// The join sheet's rules (pure; DCclubsTests).
nonisolated enum ClubJoinRules {
    /// Unsaved input is a typed code that differs from the deep-link prefill (a link-prefilled sheet
    /// can still be swiped away untouched).
    static func isDirty(code: String, initialCode: String) -> Bool {
        let typed = ClubInviteCode.normalize(code)
        return !typed.isEmpty && typed != ClubInviteCode.normalize(initialCode)
    }
}

// MARK: - Invite payload

/// The invite's share text, shared by Settings and the invite tool (strings unchanged from Settings).
nonisolated enum ClubInviteCopy {
    static func shareText(clubName: String, code: String, german: Bool) -> String {
        german ? "Tritt meinem Club „\(clubName)“ in Kuro bei: kuro://join/\(code). Oder gib den Code \(code) in der App ein."
               : "Join my club \u{201C}\(clubName)\u{201D} in Kuro: kuro://join/\(code). Or enter the code \(code) in the app."
    }

    static func shareSubject(clubName: String, german: Bool) -> String {
        german ? "Tritt \(clubName) in Kuro bei" : "Join \(clubName) on Kuro"
    }

    static func shareMessage(code: String, german: Bool) -> String {
        german ? "Einladungscode: \(code)" : "Invite code: \(code)"
    }
}

// MARK: - Room copy additions (EN/DE; spec §8)

extension ClubRoomCopy {
    /// "YOUR PRIVATE CLUBS · 3" (uppercased by the view; the count is left out when unknown).
    static func listKicker(count: Int?, german: Bool) -> String {
        let base = german ? "Deine privaten Clubs" : "Your private clubs"
        guard let count else { return base }
        return "\(base) · \(count)"
    }

    /// "2 with something new." / "All caught up."
    static func listHeadline(unread: Int, german: Bool) -> String {
        if unread > 0 { return german ? "\(unread) mit Neuem." : "\(unread) with something new." }
        return german ? "Alles gesehen." : "All caught up."
    }

    static func emptyHeadline(german: Bool) -> String { german ? "Nur deine Leute." : "Just your people." }

    static func sharingLevelsNote(german: Bool) -> String {
        german ? "Du bestimmst, was Mitglieder sehen: nur Summen, Status oder deinen Fortschritt. Das kannst du später in den Club-Einstellungen ändern."
               : "You choose what members see: totals only, statuses, or your progress. You can change it later in the club's settings."
    }

    /// The list room's meta: "5 members · 3 rails · 2 polls". `poll_count` counts every poll (open and
    /// closed; `fetch_my_clubs_*`), so the list says "polls", not "open polls". Unknown counts are left
    /// out; a known zero rail count reads "no rails yet".
    static func listMeta(memberCount: Int?, railCount: Int?, pollCount: Int?, german: Bool) -> String {
        var parts: [String] = []
        if let members = ClubsListCardRules.memberCountText(memberCount, german: german) { parts.append(members) }
        if let railCount {
            if railCount == 0 { parts.append(german ? "noch keine Listen" : "no rails yet") }
            else { parts.append(german ? (railCount == 1 ? "1 Liste" : "\(railCount) Listen")
                                       : (railCount == 1 ? "1 rail" : "\(railCount) rails")) }
        }
        if let pollCount, pollCount > 0 {
            parts.append(german ? (pollCount == 1 ? "1 Umfrage" : "\(pollCount) Umfragen")
                                : (pollCount == 1 ? "1 poll" : "\(pollCount) polls"))
        }
        return parts.joined(separator: " · ")
    }

    /// "YOUR PRIVATE CLUB · PROGRESS SHARED" (uppercased by the view).
    static func heroKicker(sharingLevel: String, german: Bool) -> String {
        let base = german ? "Dein privater Club" : "Your private club"
        return "\(base) · \(ClubsListCardRules.audienceLabel(sharingLevel: sharingLevel, german: german))"
    }

    static func you(german: Bool) -> String { german ? "Du" : "You" }

    /// VoiceOver for the member row: "You and 4 members".
    static func youAndMembers(memberCount: Int, german: Bool) -> String {
        let others = max(0, memberCount - 1)
        if others == 0 { return german ? "Nur du" : "Just you" }
        if german { return others == 1 ? "Du und 1 Mitglied" : "Du und \(others) Mitglieder" }
        return others == 1 ? "You and 1 member" : "You and \(others) members"
    }

    /// "You · Ep. 7 of 24" / "Du · F. 7 von 24".
    static func viewerProgress(_ progress: Int?, total: Int?, isManga: Bool, german: Bool) -> String? {
        guard let line = self.progress(progress, total: total, isManga: isManga, german: german) else { return nil }
        return "\(you(german: german)) · \(line)"
    }

    static func addedBy(_ name: String, german: Bool) -> String {
        german ? "Hinzugefügt von \(name)" : "Added by \(name)"
    }

    static func noteOn(_ title: String, german: Bool) -> String {
        german ? "Eine Notiz zu \(title)" : "A note on \(title)"
    }

    /// "Mina's note ↑" (the note is in the hero card above).
    static func noteLinkUp(author: String?, german: Bool) -> String {
        guard let author else { return german ? "Notiz ↑" : "Note ↑" }
        return german ? "Notiz von \(author) ↑" : "\(author)’s note ↑"
    }

    /// "Mina's note · may contain spoilers ⌄".
    static func noteInline(author: String?, german: Bool) -> String {
        guard let author else { return german ? "Notiz · kann Spoiler enthalten" : "A note · may contain spoilers" }
        return german ? "Notiz von \(author) · kann Spoiler enthalten" : "\(author)’s note · may contain spoilers"
    }

    /// " · locked" after a rail's title count.
    static func locked(german: Bool) -> String { german ? " · gesperrt" : " · locked" }

    static func addToRail(_ rail: String, german: Bool) -> String {
        german ? "Titel zu \(rail) hinzufügen" : "Add a title to \(rail)"
    }

    static func chooserTitle(german: Bool) -> String { german ? "Zu welcher Liste hinzufügen?" : "Add to which rail?" }

    static func offlineBand(german: Bool) -> (lead: String, rest: String) {
        german ? ("Du bist offline.", "Du siehst deine Clubs von vorhin.")
               : ("You're offline.", "Showing your clubs from earlier.")
    }

    static func keyTitle(_ key: ClubRoomRules.Key, german: Bool) -> String {
        switch key {
        case .addTitle: return german ? "Titel hinzufügen" : "Add a title"
        case .startRail: return german ? "Liste anlegen" : "Start a rail"
        case .invite: return german ? "Einladen" : "Invite"
        case .ask: return german ? "Fragen" : "Ask"
        }
    }

}

extension ClubDetailView.Tab {
    /// The count VoiceOver reads after the tab's name ("This week, 5 updates").
    func countLabel(_ count: Int, german: Bool) -> String {
        switch self {
        case .rails: return german ? (count == 1 ? "1 Liste" : "\(count) Listen") : (count == 1 ? "1 rail" : "\(count) rails")
        case .active: return ClubWeekCopy.updates(count, german: german)
        case .polls: return german ? (count == 1 ? "1 offene Umfrage" : "\(count) offene Umfragen")
                                   : (count == 1 ? "1 open poll" : "\(count) open polls")
        }
    }
}
