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
