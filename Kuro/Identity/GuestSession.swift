import Foundation
import KuroCore
import KuroLibrary
import Observation

#if canImport(Supabase)

// MARK: - GuestSession (W5)
// Derives "is this person a guest" from the identity plus the `guest_browsing_v1` release switch, holds
// the ONE in-memory `PendingGuestIntent` and replays it once, inside a credential lease of the new
// account, at the end of `SessionController.bootstrapAfterAuth`.
// Not an `AccountScopedState`: it holds no account data and its intent exists only while signed out.
// A guest leaves nothing on the device or the server: no UserDefaults keys, no telemetry, no requests
// beyond the allowlisted public reads.

/// How long a signed-out launch waits for the one `feature_flags` read that decides the switch.
enum GuestLaunchPolicy {
    static let flagWait: Duration = .milliseconds(1500)
}

@MainActor
@Observable
final class GuestSession {
    @ObservationIgnored private let identity: IdentityStore
    @ObservationIgnored private let flags: FeatureFlags
    @ObservationIgnored private let libraryActions: LibraryActions
    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let taste: TasteStore
    @ObservationIgnored private let clubs: ClubsStore
    @ObservationIgnored private let banner: BannerCenter

    /// The action the person tried as a guest (newest wins); nil once replayed, cancelled or dropped.
    private(set) var pendingIntent: PendingGuestIntent?
    /// A title to re-open in the signed-in tree after sign-up (observable: the replay sets it after the
    /// tree appeared).
    private(set) var reopenAfterSignUp: (key: MediaKey, account: AccountContext)?

    init(identity: IdentityStore, flags: FeatureFlags, libraryActions: LibraryActions, library: LibraryStore,
         taste: TasteStore, clubs: ClubsStore, banner: BannerCenter) {
        self.identity = identity
        self.flags = flags
        self.libraryActions = libraryActions
        self.library = library
        self.taste = taste
        self.clubs = clubs
        self.banner = banner
    }

    private var accountSession: AccountSessionCoordinator { libraryActions.accountSession }

    var presentation: RootPresentation {
        RootPresentation.resolve(
            configError: identity.configError != nil,
            isBootstrapping: identity.isAuthBootstrapping,
            isAuthenticated: identity.isAuthenticated,
            requiresPasswordUpdate: identity.requiresPasswordUpdate,
            userId: identity.currentUserId,
            guestEnabled: flags.guestBrowsingV1Enabled)
    }

    var isGuest: Bool { presentation == .guest }

    /// Called by the sign-up sheet on appear. Newest intent wins.
    func begin(_ intent: PendingGuestIntent?) {
        pendingIntent = intent
    }

    /// The sheet closed. The account switch rebuilds the tree, so `onDisappear` also runs after a
    /// successful sign-up: the intent is discarded only while the person is still signed out.
    func signUpSheetClosed() {
        guard !identity.isAuthenticated else { return }
        pendingIntent = nil
    }

    /// Take-and-clear, once. Runs at the end of the new account's bootstrap.
    func replayPendingIntent(for context: AccountContext) async {
        // Taking the intent before any suspension is what makes "exactly once" hold across repeated bootstraps.
        guard let intent = pendingIntent else { return }
        pendingIntent = nil
        let german = KuroLocale.isGerman

        if library.loadState != .loaded {
            await libraryActions.startLibraryRefresh(for: context).value
        }
        guard accountSession.isCurrent(context) else { return }

        do {
            switch intent {
            case .plan(let key, let title):
                // The Library write takes no lease of its own; the outer lease binds it to this account.
                let outcome = try await accountSession.withCredentialLease(for: context) { [libraryActions] in
                    await libraryActions.save(key, status: .planning)
                }
                guard accountSession.isCurrent(context) else { return }
                switch outcome {
                case .applied(let change):
                    banner.show(change.kind == .added
                        ? GuestCopy.planned(title, german: german)
                        : GuestCopy.alreadyListed(title, german: german))
                case .failed:
                    banner.show(GuestCopy.replayFailed(title, german: german))
                }
            case .discoverAnswer(let key, let feedback, _):
                // Synchronous enqueue into the Taste outbox; the later drain leases the account current at send time.
                try await accountSession.withCredentialLease(for: context) { [taste] in
                    _ = taste.recordDiscoverFeedback(feedback, for: key)
                }
            case .joinClub(let code):
                do {
                    _ = try await clubs.joinClub(inviteCode: code)
                    guard accountSession.isCurrent(context) else { return }
                    banner.show(GuestCopy.joinedClub(german: german))
                } catch is CancellationError {
                    return
                } catch {
                    guard accountSession.isCurrent(context) else { return }
                    banner.show(GuestCopy.joinClubFailed(german: german))
                }
            case .openTitle(let key):
                reopenAfterSignUp = (key, context)
            }
        } catch is CancellationError {
            // A refused or revoked lease drops the intent silently: it is never replayed into another account.
            return
        } catch {
            return
        }
    }

    /// The key to re-open, for the same account only; cleared either way so it never reaches another account.
    func takeReopenTitle(for current: AccountContext?) -> MediaKey? {
        defer { reopenAfterSignUp = nil }
        guard let pending = reopenAfterSignUp, let current, pending.account == current else { return nil }
        return pending.key
    }
}

#endif
