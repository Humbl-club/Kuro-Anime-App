import Foundation
import KuroCore
import KuroLibrary
import Observation

#if canImport(Supabase)
import Supabase

// MARK: - Clubs
// Owner of the caller's clubs: the "My Clubs" list, the unseen-activity badge, club bundles (cache +
// in-flight loads), the club writes (create/join/leave, rail items, rails, polls, votes, reactions),
// the account-scoped club preferences and the club realtime channel (`realtime`).
//
// Account scope (G1): everything here belongs to the signed-in account. Bundles are cached per
// (account, club) for 300 s; every completion captures its `AccountContext` and publishes only while
// it is current; the session funnel cancels the in-flight loads, clears the state
// (`AccountScopedState`) and detaches the channel (`detachRealtime()`) on every transition.
//
// Permission scope: a membership can end while the account stays signed in (the caller left the club,
// was removed, or the club was deleted). `invalidateClub(_:)` then drops everything derived from it.
// It runs when `leaveClub` succeeds and when a club RPC of the current account answers with a
// membership-loss error (`ClubError.isMembershipLoss`) that is not older than the club's last
// revocation. Server push (F42): the open club's channel listens to `club_membership_signals` for this
// user and `club_activity_signals` for the club, and re-reads the bundle on either. A removal revokes
// the club through that re-read once `20261005160000` is applied. Until then the legacy content
// streams (deployment bridge) are the live signal, and a removed member otherwise keeps the cached
// state until the next club request fails or the 300 s bundle TTL ends. `club_members` is not subscribed.
//
// Every club write runs as a credential lease of its account (F33) and every completion, success or
// failure, is handed out only while its account and, for a known club, its membership (the club's
// revocation signal) are still the ones it was sent under (F04); otherwise it ends in
// `CancellationError`. Bundle loads are ordered by request (F07): a superseded load's caller gets the
// accepted newest snapshot, and a read after a write never joins a load started before it.
//
// Library (G2): the bundle copies the caller's tracking of each rail title (`my_status`,
// `my_progress`, `my_rating`). `libraryDidChange(_:)` (via `ClubsLibrarySink`) re-reads the current
// account's bundles holding a title after an applied list change of it.
//
// Failures (G3: no SDK payload at the capability boundary): every throwing method throws a
// `ClubError` for every server answer and every SDK, decoding or configuration failure (the store is
// the one classifier, `ClubError(_:)`, and revocation reads its cases). Two Foundation/stdlib errors
// keep their types: a transport failure (`URLError`, which the club views read for their offline and
// timeout copy) and `CancellationError` (the store dropped an answer: account transition or
// revocation while the request was in flight).

@MainActor
@Observable
final class ClubsStore: AccountScopedState {
    @ObservationIgnored weak var home: HomeStore?
    /// A bundle cache entry belongs to one account and one club.
    struct BundleKey: Hashable, Sendable {
        /// Lower-cased user id, or "anon" (DEBUG preview without an account context).
        let account: String
        let clubId: String

        init(context: AccountContext?, clubId: String) {
            account = context?.userId.lowercased() ?? "anon"
            self.clubId = clubId
        }
    }

    /// Bundle cache lifetime (5 min per spec).
    static let bundleTTL: TimeInterval = 300

    /// The app's single SDK client (shared by every owner); nil when the configuration is
    /// missing, and then every request fails like a transport error (`requiredClient()`).
    private let client: SupabaseClient?
    /// The shared account coordinator (every completion is checked against it).
    let accountSession: AccountSessionCoordinator
    /// The device store of the account-scoped club preferences (the object graph's instance).
    let userDefaults: UserDefaults
    /// Friend counts derive from club memberships: a revocation drops them.
    @ObservationIgnored private let social: SocialActivityStore
    /// Club-shared provider aggregates: a revocation drops the club's entry.
    @ObservationIgnored private let availability: ProviderAvailabilityStore
    /// The club realtime channel (one owner).
    let realtime: ClubRealtimeCoordinator
    private var disclosureChannel: (any ClubRealtimeChannel)?
    private var disclosureJoin: Task<Void,Never>?
    private var disclosureReloadTask: Task<Void,Never>?
    /// The app's runtime flags (composition's single instance): `clubs_notifications_v1`,
    /// `clubs_realtime_v1`.
    @ObservationIgnored private let flags: FeatureFlags

    init(
        client: SupabaseClient?,
        accountSession: AccountSessionCoordinator,
        userDefaults: UserDefaults,
        social: SocialActivityStore,
        availability: ProviderAvailabilityStore,
        flags: FeatureFlags,
        channels: any ClubChannelFactory,
        refreshDebounce: Duration = ClubRealtimeCoordinator.defaultRefreshDebounce
    ) {
        self.client = client
        self.accountSession = accountSession
        self.userDefaults = userDefaults
        self.flags = flags
        self.social = social
        self.availability = availability
        realtime = ClubRealtimeCoordinator(
            channels: channels,
            accountSession: accountSession,
            refreshDebounce: refreshDebounce
        )
        realtime.refresh = { [weak self] clubId in
            guard let self else { return }
            // An activity signal can mean another member was removed/downgraded.
            // Erase the old disclosure projection BEFORE awaiting a fresh bundle.
            self.invalidateSharedDisclosure()
            _ = try? await self.refreshClubBundle(clubId: clubId)
        }
    }

    /// The SDK client, or (no client: missing configuration) the `ClubError` of
    /// `MissingSupabaseConfiguration`.
    private func requiredClient() throws -> SupabaseClient {
        guard let client else { throw ClubError(MissingSupabaseConfiguration()) }
        return client
    }

    /// What a club method throws for `error` (the failure contract above): `URLError`,
    /// `CancellationError` and `ClubError` unchanged, anything else classified as a `ClubError`.
    static func boundaryError(_ error: any Error) -> any Error {
        if error is URLError || error is CancellationError || error is ClubError { return error }
        return ClubError(error)
    }

    /// The failure a club request of `scope` throws for `error` (`boundaryError`), after revoking the
    /// request's club when it is a membership loss (`revokeIfMembershipLost`). A failure of a request
    /// whose account ended, or whose club was revoked since it was sent, belongs to nobody current: it
    /// is `CancellationError` (F04: an obsolete error never reaches a newer screen state).
    private func requestFailure(_ error: any Error, scope: RequestScope) -> any Error {
        guard isCurrent(scope) else { return CancellationError() }
        let failure = Self.boundaryError(error)
        if let clubError = failure as? ClubError {
            revokeIfMembershipLost(clubError, scope: scope)
        }
        return failure
    }

    /// One club write of `scope`, run as a credential lease of its account (F33: never dispatched once
    /// that account ended, never with another account's token). Its success is handed out only while
    /// the account and, when `requiresMembership` and the club is known, the club's membership are
    /// still the ones it was sent under (F04); otherwise `CancellationError`. Failures go through
    /// `requestFailure`.
    private func clubWrite<T: Sendable>(
        _ scope: RequestScope,
        requiresMembership: Bool = true,
        _ write: @escaping @MainActor (SupabaseClient) async throws -> T
    ) async throws -> T {
        let value: T
        do {
            let client = try requiredClient()
            value = try await accountSession.withCredentialLease(for: scope.context) { try await write(client) }
        } catch {
            // A metadata invalidation can arrive before the RPC response of the
            // very write that emitted it. It must not turn a committed create/join
            // into apparent failure and invite a duplicate retry.
            guard isMembershipCurrent(scope) else { throw CancellationError() }
            let failure = Self.boundaryError(error)
            if let clubError = failure as? ClubError, clubError.isMembershipLoss {
                // A removal answer can be older than a later disclosure/rejoin.
                // A stale failure must not revoke that newer room membership.
                guard isCurrent(scope) else { throw CancellationError() }
                revokeIfMembershipLost(clubError, scope: scope)
            }
            throw failure
        }
        let stillCurrent = requiresMembership ? isMembershipCurrent(scope) : accountSession.isCurrent(scope.context)
        guard stillCurrent else { throw CancellationError() }
        return value
    }

    /// A club write of `scope` succeeded: the current account's cached bundle of the club is dropped and
    /// the club's write epoch moves on, so the next read never joins a load started before the write (F07).
    private func didWrite(_ scope: RequestScope) {
        guard let clubId = scope.clubId else { return }
        clubWriteEpochs[clubId, default: 0] += 1
        clubBundleCache.removeValue(forKey: BundleKey(context: scope.context, clubId: clubId))
    }

    // MARK: State

    var myClubs: [ClubListRow] = []
    var hasUnseenClubActivity: Bool = false
    /// Club bundles keyed by (account, club); read by `clubActivityForMedia` for the current account only.
    var clubBundleCache: [BundleKey: TimedCache<ClubBundle>] = [:]
    /// In-flight bundle reads, keyed "<account>|<club>|<revocation epoch>" (same account only).
    @ObservationIgnored let clubBundleLoads = AccountScopedLoads<String, ClubBundle>()
    /// Per-club revocation signal value, set by `invalidateClub`: a load started before the revocation
    /// is never joined again and its answer is dropped. Observed (E6a-V): club views read it through
    /// `revocationEpoch(_:)` and drop their own copies of the club's data when it changes.
    private var revocationEpochs: [String: Int] = [:]
    /// The signal value of every club not revoked under the current account; replaced on every account
    /// transition (`clearPrivateState`), so each club's signal changes then too. Observed.
    private var accountSignal = 0
    /// Source of signal values: monotonic, never reset, so a signal never returns to an earlier value.
    @ObservationIgnored private var signalCounter = 0
    /// Revocations so far (monotonic): a my-clubs read that saw one happen while it was in flight may
    /// predate it and is not published.
    @ObservationIgnored private var revocationCount = 0
    /// Privacy cache refresh is not membership loss. Views reload on this generation;
    /// only revocationEpoch dismisses a room that the caller actually lost.
    private(set) var disclosureGeneration = 0
    /// The background re-read of bundles after a Library change (`libraryDidChange`).
    @ObservationIgnored private(set) var libraryRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var pendingLibraryClubIds: Set<String> = []
    /// Request order of bundle loads (F07): monotonic, taken when a load starts. The cache keeps the
    /// order of the load whose answer it holds (`acceptedBundleOrder`); a load ordered before it never
    /// replaces it and its caller gets the accepted newest snapshot instead (no wall-clock comparison).
    @ObservationIgnored private var bundleLoadOrder = 0
    @ObservationIgnored private var acceptedBundleOrder: [BundleKey: Int] = [:]
    /// Per-club write epoch (F07): moves on with every successful club write, so a read after the write
    /// never joins a bundle load started before it.
    @ObservationIgnored private var clubWriteEpochs: [String: Int] = [:]

    private func nextSignal() -> Int {
        signalCounter += 1
        return signalCounter
    }

    // MARK: AccountScopedState

    func cancelAccountWork() {
        disclosureReloadTask?.cancel()
        disclosureReloadTask = nil
        clubBundleLoads.cancelAll()
        libraryRefreshTask?.cancel()
        libraryRefreshTask = nil
        pendingLibraryClubIds.removeAll()
    }

    func clearPrivateState() {
        clubBundleCache.removeAll()
        acceptedBundleOrder.removeAll()
        clubWriteEpochs.removeAll()
        revocationEpochs.removeAll()
        accountSignal = nextSignal()
        myClubs = []
        myClubsPhase = .idle
        hasUnseenClubActivity = false
        // Persisted club prefs are account-scoped; legacy unscoped values are dropped.
        removeLegacyUnscopedClubPrefs()
    }

    // MARK: - Revocation

    /// Club revocation: the caller left `clubId` or lost access to it while staying signed in. Drops
    /// everything derived from that membership:
    /// - the club's cached bundle; its in-flight bundle load is detached (never joined again; its late
    ///   answer is dropped, not network-cancelled);
    /// - its row in `myClubs`;
    /// - the friend projection (a friend is a member of a shared club: `SocialActivityStore`);
    /// - the club's shared-provider aggregate (`ProviderAvailabilityStore`);
    /// - its realtime channel, if it is the open one (and a subscribe of it still in flight);
    /// - its last-seen timestamp and, if it was the remembered Add-to-Club choice, that choice.
    /// Optimistic vote/reaction state is held by the club views, which observe `revocationEpoch(_:)`.
    func invalidateSharedDisclosure() {
        availability.invalidateAllClubSharedProviders()
        // Enriched list cards contain peer names, artwork and activity too. A
        // failed reload must leave none of that old disclosure on screen.
        myClubs.removeAll()
        // The rows are gone until the reload answers: never "no clubs", never fresh.
        myClubsPhase = .idle
        hasUnseenClubActivity = false
        clubBundleLoads.cancelAll()
        clubBundleCache.removeAll()
        acceptedBundleOrder.removeAll()
        disclosureGeneration += 1
        revocationCount += 1
        social.invalidateFriendProjection()
        home?.invalidateClubContent()
        disclosureReloadTask?.cancel()
        let account = accountSession.current
        disclosureReloadTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let self, !Task.isCancelled, self.accountSession.isCurrent(account) else { return }
            await self.fetchMyClubs()
        }
    }

    func invalidateClub(_ clubId: String) {
        revocationEpochs[clubId] = nextSignal()
        revocationCount += 1
        clubBundleCache = clubBundleCache.filter { $0.key.clubId != clubId }
        acceptedBundleOrder = acceptedBundleOrder.filter { $0.key.clubId != clubId }
        myClubs.removeAll { $0.id == clubId }
        social.invalidateFriendProjection()
        home?.invalidateClubContent()
        availability.invalidateClubSharedProviders(clubId: clubId)
        realtime.stop(clubId: clubId)
        if let key = accountScopedDefaultsKey("clubLastSeen." + clubId) {
            userDefaults.removeObject(forKey: key)
        }
        if rememberedAddToClubId() == clubId {
            setRememberedAddToClubId(nil)
        }
    }

    /// The membership a club request was sent under: its account, its club (if known) and that club's
    /// revocation signal when the request started.
    private struct RequestScope {
        let context: AccountContext?
        let clubId: String?
        let epoch: Int
        let disclosure: Int
    }

    private func requestScope(clubId: String?) -> RequestScope {
        RequestScope(context: accountSession.current, clubId: clubId,
            epoch: clubId.map(revocationEpoch) ?? 0, disclosure: disclosureGeneration)
    }

    /// The request's account is still current and its club (if known) has not been revoked since.
    private func isCurrent(_ scope: RequestScope) -> Bool {
        guard disclosureGeneration == scope.disclosure else { return false }
        return isMembershipCurrent(scope)
    }

    /// Write acknowledgements are scoped to account and actual membership loss,
    /// independently of changes to a private read's disclosure generation.
    private func isMembershipCurrent(_ scope: RequestScope) -> Bool {
        guard accountSession.isCurrent(scope.context) else { return false }
        guard let clubId = scope.clubId else { return true }
        return revocationEpoch(clubId) == scope.epoch
    }

    /// Revokes the request's club when `error` is a membership-loss answer of the still-current account
    /// (a late answer for an ended account never touches the next account's state), unless the club
    /// was revoked since the request started: that answer predates the revocation (and a rejoin since
    /// then must not be undone by it).
    private func revokeIfMembershipLost(_ error: ClubError, scope: RequestScope) {
        guard let clubId = scope.clubId,
              accountSession.isCurrent(scope.context),
              revocationEpoch(clubId) == scope.epoch,
              error.isMembershipLoss else { return }
        invalidateClub(clubId)
    }

    /// The revocation signal of `clubId` for views (compare for equality only): it changes whenever the
    /// club is revoked and on every account transition, and never returns to an earlier value.
    func revocationEpoch(_ clubId: String) -> Int {
        let base = accountSignal
        return revocationEpochs[clubId] ?? base
    }

    // MARK: - Account-scoped club preferences
    // Stored as `com.kuro.account.<userId>.<name>`; nothing is read or written while signed out.

    /// Legacy unscoped key; the preference is now stored per account.
    static let rememberedClubIdKey = "com.kuro.rememberedAddToClubId"
    private static var accountPrefsPrefix: String { "com.kuro.account." }
    private static var legacyClubLastSeenPrefix: String { "com.kuro.clubLastSeen." }
    private static var legacyClubNotificationLastCheckKey: String { "com.kuro.clubNotificationLastCheck" }

    private func accountScopedDefaultsKey(_ name: String) -> String? {
        guard let userId = accountSession.current?.userId else { return nil }
        return Self.accountPrefsPrefix + userId.lowercased() + "." + name
    }

    /// Removes the device-global keys used before preferences were scoped per account.
    func removeLegacyUnscopedClubPrefs() {
        userDefaults.removeObject(forKey: Self.rememberedClubIdKey)
        userDefaults.removeObject(forKey: Self.legacyClubNotificationLastCheckKey)
        for key in userDefaults.dictionaryRepresentation().keys where key.hasPrefix(Self.legacyClubLastSeenPrefix) {
            userDefaults.removeObject(forKey: key)
        }
    }

    /// Removes every preference stored for `userId` (account deletion).
    func removeAccountScopedPrefs(userId: String) {
        let prefix = Self.accountPrefsPrefix + userId.lowercased() + "."
        for key in userDefaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            userDefaults.removeObject(forKey: key)
        }
    }

    func rememberedAddToClubId() -> String? {
        guard let key = accountScopedDefaultsKey("rememberedAddToClubId") else { return nil }
        return userDefaults.string(forKey: key)
    }

    func setRememberedAddToClubId(_ clubId: String?) {
        guard let key = accountScopedDefaultsKey("rememberedAddToClubId") else { return }
        if let clubId, !clubId.isEmpty {
            userDefaults.set(clubId, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    // MARK: - My clubs

    /// How long a successful my-clubs read counts as fresh for `refreshMyClubsIfStale()` (revisiting
    /// the Clubs page inside this window does not ask the server again).
    nonisolated static let myClubsStaleness: TimeInterval = 60

    /// The state of the current account's my-clubs read (observed by the club list views).
    private(set) var myClubsPhase: MyClubsPhase = .idle

    /// Reads the current account's clubs (always asks the server: writes and the disclosure reload
    /// call it right after a change). Uses `fetch_my_clubs_loading`; `fetch_my_clubs_enriched` only
    /// when the server answers that the first function does not exist (`MyClubsReadFallback`). A
    /// failure keeps the rows on screen and records `.failed`; an answer of an ended account, or one
    /// that may predate a revocation, publishes nothing and restores the phase it found.
    func fetchMyClubs() async {
        let context = accountSession.current
        let revocations = revocationCount
        let previous = myClubsPhase
        myClubsPhase = .loading(previous: previous.settled)
        /// This read may still publish (same account, no revocation or disclosure reset since it
        /// started: both move `revocationCount`).
        func ownsPhase() -> Bool {
            accountSession.isCurrent(context) && revocationCount == revocations
        }
        do {
            let client = try requiredClient()
            let clubs: [ClubListRow] = try await accountSession.withCredentialLease(for: context) {
                do {
                    return try await client.rpc("fetch_my_clubs_loading").execute().value
                } catch {
                    // Only a missing function falls back (older server); a transport failure,
                    // cancellation, decoding error or any other server answer is the read's failure.
                    guard MyClubsReadFallback.shouldUseEnriched(after: error) else { throw error }
                    return try await client.rpc("fetch_my_clubs_enriched").execute().value
                }
            }
            // Another account, or a revocation while in flight (this answer may predate it and would
            // bring the club back): publish nothing.
            guard ownsPhase() else {
                if accountSession.isCurrent(context), myClubsPhase.isLoading { myClubsPhase = previous.settled }
                return
            }
            myClubs = clubs
            myClubsPhase = .loaded(at: Date())
        } catch {
            #if DEBUG
            print("❌ fetchMyClubs: \(error)")
            #endif
            guard ownsPhase() else {
                if accountSession.isCurrent(context), myClubsPhase.isLoading { myClubsPhase = previous.settled }
                return
            }
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                myClubsPhase = previous.settled
                return
            }
            myClubsPhase = .failed(transport: error is URLError)
        }
    }

    /// The Clubs page's read: asks the server only when the last successful read of this account is
    /// older than `myClubsStaleness` (or there is none, or the last read failed).
    func refreshMyClubsIfStale(now: Date = Date()) async {
        guard MyClubsPhase.needsRefresh(myClubsPhase, now: now, staleness: Self.myClubsStaleness) else { return }
        await fetchMyClubs()
    }

    // MARK: - Club last-seen (account-scoped per-club timestamps)

    func clubLastSeenAt(clubId: String) -> Date? {
        guard let key = accountScopedDefaultsKey("clubLastSeen." + clubId) else { return nil }
        let ts = userDefaults.double(forKey: key)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    func markClubSeen(clubId: String) {
        guard let key = accountScopedDefaultsKey("clubLastSeen." + clubId) else { return }
        userDefaults.set(Date().timeIntervalSince1970, forKey: key)
    }

    func hasUnseenActivity(club: ClubListRow) -> Bool {
        guard let activityStr = club.last_activity_at else { return false }
        guard let activityDate = Self.parseISO8601(activityStr) else { return false }
        guard let lastSeen = clubLastSeenAt(clubId: club.id) else { return true }
        return activityDate > lastSeen
    }

    private static var isoFractional: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    private static var isoBasic: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    static func parseISO8601(_ str: String) -> Date? {
        isoFractional.date(from: str) ?? isoBasic.date(from: str)
    }

    // MARK: - Membership writes

    /// Creates a club for the current account. A success or failure of an account that ended meanwhile
    /// ends in `CancellationError` (no my-clubs refresh, no outcome handed out).
    func createClub(name: String, description: String? = nil, sharingLevel: String = "status") async throws -> CreateClubResponse {
        let scope = requestScope(clubId: nil)
        let params = RPCCreateClubParams(p_name: name, p_description: description, p_sharing_level: sharingLevel)
        let resp: CreateClubResponse = try await clubWrite(scope) { client in
            try await client
                .rpc("create_club", params: params)
                .execute()
                .value
        }
        await fetchMyClubs()
        return resp
    }

    /// Joins a club with an invite code (same account rule as `createClub`).
    func joinClub(inviteCode: String) async throws -> JoinClubResponse {
        let scope = requestScope(clubId: nil)
        let params = RPCJoinClubParams(p_invite_code: inviteCode)
        let resp: JoinClubResponse = try await clubWrite(scope) { client in
            try await client
                .rpc("join_club", params: params)
                .execute()
                .value
        }
        await fetchMyClubs()
        return resp
    }

    /// Leaves a club. Its success needs only the account to be current (the membership ends either way);
    /// everything derived from the membership is dropped.
    func leaveClub(clubId: String) async throws {
        let scope = requestScope(clubId: clubId)
        let params = RPCClubIdParams(p_club_id: clubId)
        let _: SimpleSuccessResponse = try await clubWrite(scope, requiresMembership: false) { client in
            try await client
                .rpc("leave_club", params: params)
                .execute()
                .value
        }
        // The membership ended: drop everything derived from it.
        invalidateClub(clubId)
        await fetchMyClubs()
    }

    // MARK: - Bundles

    func fetchClubBundle(clubId: String, forceRefresh: Bool = false) async throws -> ClubBundle {
        try await loadClubBundle(clubId: clubId, forceRefresh: forceRefresh, afterWrite: false)
    }

    /// `afterWrite`: the read must observe a write that completed after a load in flight started (a
    /// Library change), so it never joins that load.
    private func loadClubBundle(clubId: String, forceRefresh: Bool, afterWrite: Bool) async throws -> ClubBundle {
        let now = Date()
        // The bundle carries the caller's role and `my_*` fields: shared in flight and cached
        // only for the account that requested it.
        let scope = requestScope(clubId: clubId)
        let context = scope.context
        let cacheKey = BundleKey(context: context, clubId: clubId)
        if !forceRefresh, let cached = clubBundleCache[cacheKey], now.timeIntervalSince(cached.storedAt) < Self.bundleTTL {
            return cached.value
        }

        let epoch = scope.epoch
        bundleLoadOrder += 1
        let order = bundleLoadOrder
        let writeEpoch = clubWriteEpochs[clubId] ?? 0
        let client = self.client
        let cid = clubId
        let work: @MainActor () async throws -> ClubBundle = {
            guard let client else { throw MissingSupabaseConfiguration() }
            let params = RPCClubIdParams(p_club_id: cid)
            let bundle: ClubBundle = try await self.accountSession.withCredentialLease(for: context) {
                try await client.rpc("fetch_club_bundle", params: params).execute().value
            }
            return bundle
        }
        let loadKey = "\(cacheKey.account)|\(clubId)|\(epoch)|\(scope.disclosure)|\(writeEpoch)"
        let bundle: ClubBundle
        do {
            bundle = afterWrite
                ? try await clubBundleLoads.runFresh(key: loadKey, context: context, priority: .userInitiated, work: work)
                : try await clubBundleLoads.run(key: loadKey, context: context, priority: .userInitiated, work: work)
        } catch {
            throw requestFailure(error, scope: scope)
        }
        // Neither another account's nor a revoked membership's bundle is handed out or cached.
        guard isCurrent(scope) else { throw CancellationError() }
        // F07: a load that started earlier (request order) never replaces the accepted answer of one that
        // started later (the re-read after a Library change or a club write), and its caller gets that
        // accepted newest snapshot, never its superseded one.
        if let accepted = acceptedBundleOrder[cacheKey], accepted > order, let newest = clubBundleCache[cacheKey] {
            return newest.value
        }
        clubBundleCache[cacheKey] = TimedCache(value: bundle, storedAt: now)
        acceptedBundleOrder[cacheKey] = order
        return bundle
    }

    func fetchClubBundleLoading(clubId: String) async throws -> ClubBundleLoading {
        let scope = requestScope(clubId: clubId)
        let params = RPCClubIdParams(p_club_id: clubId)
        let snapshot: ClubBundleLoading
        do {
            let client = try requiredClient()
            snapshot = try await accountSession.withCredentialLease(for: scope.context) {
                try await client.rpc("fetch_club_bundle_loading", params: params).execute().value
            }
        } catch {
            throw requestFailure(error, scope: scope)
        }
        // Neither another account's nor a revoked membership's snapshot is handed out.
        guard isCurrent(scope) else { throw CancellationError() }
        return snapshot
    }

    func refreshClubBundle(clubId: String) async throws -> ClubBundle {
        try await fetchClubBundle(clubId: clubId, forceRefresh: true)
    }

    /// The current account's cached bundles.
    private var currentAccountBundles: [(key: BundleKey, value: TimedCache<ClubBundle>)] {
        let account = BundleKey(context: accountSession.current, clubId: "").account
        return clubBundleCache.filter { $0.key.account == account }.map { ($0.key, $0.value) }
    }

    /// The club (of the current account's cached bundles) that holds `railId`.
    private func clubId(containingRailId railId: String) -> String? {
        guard !railId.isEmpty else { return nil }
        return currentAccountBundles.first { $0.value.value.rails.contains(where: { $0.id == railId }) }?.key.clubId
    }

    /// The club (of the current account's cached bundles) that holds `pollId`.
    private func clubId(containingPollId pollId: String) -> String? {
        guard !pollId.isEmpty else { return nil }
        return currentAccountBundles.first { $0.value.value.polls.contains(where: { $0.id == pollId }) }?.key.clubId
    }

    /// The club (of the current account's cached bundles) that holds the rail item `railItemId`.
    private func clubId(containingRailItemId railItemId: String) -> String? {
        guard !railItemId.isEmpty else { return nil }
        return currentAccountBundles.first { entry in
            entry.value.value.rails.contains { rail in rail.items.contains { $0.id == railItemId } }
        }?.key.clubId
    }

    // MARK: - Rails, polls, votes, reactions

    // Every write runs through `clubWrite` (credential lease, account + membership recheck) and, on
    // success, `didWrite` (the club's cached bundle dropped, its write epoch moved on). The club is
    // resolved from the current account's cached bundles before the request (rail, poll, item ids).

    func addRailItem(railId: String, mediaType: String, mediaId: Int, note: String? = nil) async throws -> AddRailItemResponse {
        let scope = requestScope(clubId: clubId(containingRailId: railId))
        let params = RPCAddRailItemParams(p_rail_id: railId, p_media_type: mediaType, p_media_id: mediaId, p_note: note)
        let response: AddRailItemResponse = try await clubWrite(scope) { client in
            try await client
                .rpc("add_club_rail_item", params: params)
                .execute()
                .value
        }
        didWrite(scope)
        return response
    }

    func castVote(pollId: String, optionId: String) async throws {
        let scope = requestScope(clubId: clubId(containingPollId: pollId))
        let params = RPCCastVoteParams(p_poll_id: pollId, p_option_id: optionId)
        let _: SimpleSuccessResponse = try await clubWrite(scope) { client in
            try await client
                .rpc("cast_club_vote", params: params)
                .execute()
                .value
        }
        didWrite(scope)
    }

    func createClubRail(clubId: String, title: String, description: String? = nil) async throws -> CreateRailResponse {
        let scope = requestScope(clubId: clubId)
        let params = RPCCreateClubRailParams(p_club_id: clubId, p_title: title, p_description: description)
        let resp: CreateRailResponse = try await clubWrite(scope) { client in
            try await client
                .rpc("create_club_rail", params: params)
                .execute()
                .value
        }
        didWrite(scope)
        return resp
    }

    func createClubPoll(clubId: String, question: String, options: [String]) async throws -> CreatePollResponse {
        let scope = requestScope(clubId: clubId)
        let params = RPCCreateClubPollParams(p_club_id: clubId, p_question: question, p_options: options)
        let resp: CreatePollResponse = try await clubWrite(scope) { client in
            try await client
                .rpc("create_club_poll", params: params)
                .execute()
                .value
        }
        didWrite(scope)
        return resp
    }

    /// A reaction on a rail item. The bundle is not evicted (as before: the views keep their optimistic
    /// reaction state), but the outcome follows the same account + membership rule.
    func toggleReaction(railItemId: String, emoji: String) async throws -> ToggleReactionResponse {
        let scope = requestScope(clubId: clubId(containingRailItemId: railItemId))
        let params = RPCToggleReactionParams(p_rail_item_id: railItemId, p_emoji: emoji)
        return try await clubWrite(scope) { client in
            try await client
                .rpc("toggle_club_reaction", params: params)
                .execute()
                .value
        }
    }

    // MARK: - Library changes (G2)

    /// An applied list change of the current account: the cached bundles holding that title (anime and
    /// manga told apart by `MediaKey`) are marked expired, so the next read goes to the server, and are
    /// re-read in the background; the cached copy stays visible until the fresh one replaces it. The
    /// re-read never joins a load that started before the change. A change of another account (late
    /// delivery after a transition) is ignored.
    func libraryDidChange(_ change: LibraryChange) {
        guard accountSession.isCurrent(change.account) else { return }
        let mediaType = change.key.kind == .anime ? "ANIME" : "MANGA"
        let affected = currentAccountBundles.filter { entry in
            entry.value.value.rails.contains { rail in
                rail.items.contains { $0.media_id == change.key.id && $0.media_type.uppercased() == mediaType }
            }
        }
        guard !affected.isEmpty else { return }
        for entry in affected {
            clubBundleCache[entry.key] = TimedCache(value: entry.value.value, storedAt: .distantPast)
        }
        pendingLibraryClubIds.formUnion(affected.map(\.key.clubId))
        let context = change.account
        libraryRefreshTask?.cancel()
        libraryRefreshTask = Task { [weak self] in
            do { try await Task.sleep(for:.milliseconds(150)) } catch { return }
            guard let self,self.accountSession.isCurrent(context) else { return }
            let clubIds=self.pendingLibraryClubIds.sorted()
            for clubId in clubIds {
                guard !Task.isCancelled, self.accountSession.isCurrent(context) else { return }
                _ = try? await self.loadClubBundle(clubId: clubId, forceRefresh: true, afterWrite: true)
                if !Task.isCancelled { self.pendingLibraryClubIds.remove(clubId) }
            }
        }
    }

    // MARK: - Club activity for a title

    /// Scans the current account's cached club bundles to find clubs that have this media item in a rail.
    func clubActivityForMedia(mediaId: Int, mediaType: String) -> [ClubMediaActivity] {
        let mt = mediaType.uppercased()
        var results: [ClubMediaActivity] = []
        for (_, cached) in currentAccountBundles {
            let bundle = cached.value
            var matches: [ClubMediaActivityMatch] = []
            for rail in bundle.rails {
                for item in rail.items {
                    if item.media_id == mediaId && item.media_type.uppercased() == mt {
                        matches.append(ClubMediaActivityMatch(rail: rail, item: item))
                    }
                }
            }
            if !matches.isEmpty {
                results.append(ClubMediaActivity(
                    club: bundle.club,
                    memberCount: bundle.member_count,
                    sharingLevel: bundle.club.sharing_level,
                    members: bundle.members,
                    matchingItems: matches
                ))
            }
        }
        return results
    }

    // MARK: - Club Notifications

    func checkClubNotifications() async {
        guard flags.isClubsNotificationsV1Enabled else { return }
        let context = accountSession.current
        let lastCheck = accountScopedDefaultsKey("clubNotificationLastCheck").map { userDefaults.double(forKey: $0) } ?? 0
        let since = lastCheck > 0 ? Date(timeIntervalSince1970: lastCheck) : Date().addingTimeInterval(-86400)

        struct CheckParams: Encodable, Sendable {
            let p_since: String

            enum CodingKeys: String, CodingKey { case p_since }
            nonisolated func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(p_since, forKey: .p_since)
            }
        }

        let isoStr = ISO8601DateFormatter().string(from: since)
        let params = CheckParams(p_since: isoStr)

        do {
            let client = try requiredClient()
            let resp: ClubActivityCheckResponse = try await client
                .rpc("check_club_activity_since", params: params)
                .execute()
                .value
            guard accountSession.isCurrent(context) else { return }
            hasUnseenClubActivity = resp.has_new_activity
        } catch {
            #if DEBUG
            print("❌ checkClubNotifications: \(error)")
            #endif
        }
    }

    func clearClubNotificationBadge() {
        hasUnseenClubActivity = false
        guard let key = accountScopedDefaultsKey("clubNotificationLastCheck") else { return }
        userDefaults.set(Date().timeIntervalSince1970, forKey: key)
    }

    // MARK: - Realtime

    /// Opens the realtime channel of the club on screen (`clubs_realtime_v1`).
    func subscribeToClubUpdates(clubId: String) async {
        guard flags.isClubsRealtimeV1Enabled else { return }
        await realtime.subscribe(clubId: clubId)
    }

    /// Synchronous half of a session end/switch (session funnel): the channel, detached, for removal.
    func startSharedDisclosureUpdates() {
        guard disclosureChannel == nil,flags.isClubsRealtimeV1Enabled,
            let client,let account=accountSession.current else { return }
        let channel=SupabaseDisclosureChannel(client:client,userId:account.userId.lowercased()) { [weak self] in
            guard let self,self.accountSession.isCurrent(account) else { return }
            self.invalidateSharedDisclosure()
        }
        disclosureChannel=channel
        disclosureJoin=Task {
            do { try await accountSession.withCredentialLease(for: account) { await channel.subscribe() } }
            catch { channel.stopListening() }
        }
    }

    func detachRealtime() -> (any ClubRealtimeChannel)? {
        disclosureJoin?.cancel(); disclosureJoin=nil
        let channels=[realtime.detach(),disclosureChannel].compactMap { $0 }
        disclosureChannel=nil
        return channels.isEmpty ? nil : DetachedClubChannels(channels)
    }
}

// MARK: - My-clubs read fallback

/// When the my-clubs read may switch from `fetch_my_clubs_loading` to `fetch_my_clubs_enriched`:
/// only when the server says the first function does not exist (an older deployment). PostgREST
/// answers a missing function with PGRST202 (HTTP 404); PostgreSQL's undefined-function SQLSTATE is
/// 42883. Everything else (offline, timeout, cancellation, an undecodable payload, any other server
/// answer) is the read's own failure: falling back then doubled the traffic and hid the real error.
nonisolated enum MyClubsReadFallback {
    static let functionMissingCodes: Set<String> = ["PGRST202", "42883"]

    static func shouldUseEnriched(after error: any Error) -> Bool {
        if let postgrest = error as? PostgrestError {
            return postgrest.code.map(functionMissingCodes.contains) ?? false
        }
        if let http = error as? HTTPError {
            return http.response.statusCode == 404
        }
        return false
    }
}

// MARK: - Club errors

/// A failed club request, as `ClubsStore` throws it (the one classifier; G3: views never handle SDK
/// error types) and as the club views branch on it.
///
/// Where the server's code travels: most club RPCs raise it as the message (`RAISE EXCEPTION
/// 'NOT_A_MEMBER'`, or `'<CODE>: <text>'`: `fetch_club_bundle`, `leave_club`, `cast_club_vote`,
/// `create_club`, `join_club`, ...); `add_club_rail_item` puts it in DETAIL with a prose message.
/// supabase-swift 2.54.1 decodes `PostgrestError.detail` from a `detail` key while PostgREST sends
/// `details`, so DETAIL-only codes never reach the client (F17). HINT is decoded, so the server-side
/// repair (lane L3) carries such codes in HINT; until then `add_club_rail_item`'s answers arrive as their
/// prose message plus the SQLSTATE (`23505` for a duplicate) unless this translator recovers `details`.
///
/// Classification by `ClubError(error)`, the ONE translator, in this order (F17):
/// 1. A `ClubError` passes through unchanged.
/// 2. The first known code carried by hint, then message, then detail-or-details: the leading token
///    before ':', trimmed, matched case-sensitively against the EXACT vocabulary below (the server's
///    codes are upper-case identifiers; prose such as `add_club_rail_item`'s "Unauthenticated" message,
///    or a hint that merely mentions membership, is not a code). HINT first: it is the reliable wire
///    carrier. When `detail` is empty the translator reads PostgREST's `details` (see
///    `init(postgrestJSON:)` and the PostgREST decoder that maps `details` → `detail` for SDK throws).
/// 3. SQLSTATE 42501 without a code: `permissionDenied` (RLS or GRANT; a membership loss).
/// 4. SQLSTATE 23505 without a code: `uniqueViolation` (`add_club_rail_item`'s duplicate whose DETAIL
///    code never reached the translator).
/// 5. Anything else: `other(message:)` (any other server answer, SDK, decoding, configuration; the
///    store itself lets `URLError` and `CancellationError` through unclassified). Unknown stays unknown:
///    `other` is never a membership loss, so arbitrary text can never revoke a club.
nonisolated enum ClubError: LocalizedError, Equatable, Sendable {
    // Session and membership
    case unauthenticated
    case notAMember
    case clubNotFound
    // Create and join
    case invalidName
    case descriptionTooLong
    case tooManyClubs
    case rateLimited
    case invalidCode
    case codeExpired
    case codeExhausted
    case clubArchived
    case clubFull
    case alreadyMember
    // Rails, items and polls
    case railNotFound
    case railLocked
    case mediaNotFound
    case invalidMediaType
    case noteTooLong
    case duplicateItem
    case pollClosed
    // SQLSTATE without a code
    case permissionDenied
    case uniqueViolation
    /// Any other failure; the message is for diagnostics (views show their own copy).
    case other(message: String)

    /// PostgreSQL `insufficient_privilege` ("permission denied": RLS or GRANT).
    static let permissionDeniedSQLState = "42501"
    /// PostgreSQL `unique_violation`.
    static let uniqueViolationSQLState = "23505"

    /// The server's machine-readable codes (`RAISE EXCEPTION '<CODE>'`, or DETAIL in `add_club_rail_item`).
    private static let serverCodes: [String: ClubError] = [
        "UNAUTHENTICATED": .unauthenticated,
        "NOT_A_MEMBER": .notAMember,
        "CLUB_NOT_FOUND": .clubNotFound,
        "INVALID_NAME": .invalidName,
        "DESCRIPTION_TOO_LONG": .descriptionTooLong,
        "TOO_MANY_CLUBS": .tooManyClubs,
        "RATE_LIMITED": .rateLimited,
        "INVALID_CODE": .invalidCode,
        "CODE_EXPIRED": .codeExpired,
        "CODE_EXHAUSTED": .codeExhausted,
        "CLUB_ARCHIVED": .clubArchived,
        "CLUB_FULL": .clubFull,
        "ALREADY_MEMBER": .alreadyMember,
        "RAIL_NOT_FOUND": .railNotFound,
        "RAIL_LOCKED": .railLocked,
        "MEDIA_NOT_FOUND": .mediaNotFound,
        "INVALID_MEDIA_TYPE": .invalidMediaType,
        "NOTE_TOO_LONG": .noteTooLong,
        "DUPLICATE_ITEM": .duplicateItem,
        "POLL_CLOSED": .pollClosed,
    ]

    /// The server's message for the answer this case stands for, so a view that shows
    /// `localizedDescription` shows what it showed for the SDK's error (`PostgrestError`'s description
    /// is its message): the code as the club RPCs raise it (DESCRIPTION_TOO_LONG with its one deployed
    /// text, as `create_club` and `create_club_rail` raise it), the message itself for `other`. The
    /// SQLSTATE cases name their condition (their prose is not kept).
    var errorDescription: String? {
        switch self {
        case .descriptionTooLong: return "DESCRIPTION_TOO_LONG: max 500 characters"
        case .permissionDenied: return "permission denied"
        case .uniqueViolation: return "duplicate key value violates unique constraint"
        case .other(let message): return message
        default: return Self.serverCodes.first { $0.value == self }?.key
        }
    }

    /// Whether the caller is not (or no longer) a member of the club the request addressed:
    /// NOT_A_MEMBER, CLUB_NOT_FOUND (the club is gone) or permission denied (SQLSTATE 42501 without a
    /// code). Session errors (UNAUTHENTICATED), missing rails/polls and validation errors are not.
    /// `ClubsStore` revokes the club on it (`invalidateClub`).
    var isMembershipLoss: Bool {
        switch self {
        case .notAMember, .clubNotFound, .permissionDenied: return true
        default: return false
        }
    }

    /// PostgREST error body. The live key is `details`; the SDK's `PostgrestError` only fills `detail`.
    private struct WirePayload: Decodable {
        let message: String
        let code: String?
        let hint: String?
        let detail: String?
        let details: String?
    }

    private struct DetailCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
        static let detail = DetailCodingKey(stringValue: "detail")!
    }

    /// Decoder for PostgREST responses that maps the live `details` key onto the SDK's `detail` so
    /// `ClubError(PostgrestError)` sees DETAIL-only codes. Date strategy matches the SDK default.
    static func postgrestDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = PostgrestClient.Configuration.jsonDecoder.dateDecodingStrategy
        decoder.keyDecodingStrategy = .custom { path in
            let key = path[path.count - 1]
            if key.stringValue == "details" { return DetailCodingKey.detail }
            return key
        }
        return decoder
    }

    private static func nonempty(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Classifies carriers in order: hint, message, then detail (falling back to PostgREST `details`).
    private static func classify(
        hint: String?,
        message: String,
        detail: String?,
        details: String?,
        code: String?
    ) -> ClubError {
        let detailCarrier = nonempty(detail) ?? nonempty(details)
        for raw in [hint, message, detailCarrier] {
            guard let raw else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let token = trimmed.split(separator: ":", maxSplits: 1).first.map(String.init) ?? trimmed
            let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if let known = serverCodes[normalized] { return known }
        }
        switch code {
        case permissionDeniedSQLState: return .permissionDenied
        case uniqueViolationSQLState: return .uniqueViolation
        default: return .other(message: message)
        }
    }

    /// Classifies a realistic PostgREST JSON error body. Reads `details` when `detail` is empty.
    init(postgrestJSON data: Data) {
        if let wire = try? JSONDecoder().decode(WirePayload.self, from: data) {
            self = Self.classify(
                hint: wire.hint,
                message: wire.message,
                detail: wire.detail,
                details: wire.details,
                code: wire.code
            )
            return
        }
        self = .other(message: String(data: data, encoding: .utf8) ?? "Unknown error")
    }

    /// Classifies `error` (see the type's documentation). `ClubsStore` throws the result (through
    /// `boundaryError`) and the club views read the thrown error as `ClubError` directly. A `ClubError`
    /// passed here is kept; a `URLError` or `CancellationError` passed here is `other`.
    init(_ error: any Error) {
        if let clubError = error as? ClubError {
            self = clubError
            return
        }
        guard let pgError = error as? PostgrestError else {
            self = .other(message: error.localizedDescription)
            return
        }
        // SDK `PostgrestError` has no `details` field. Production clients use `postgrestDecoder()` so
        // PostgREST's `details` lands in `detail` before this runs; when `detail` is still empty the
        // SQLSTATE fallback below keeps unknown text as `.other` / `.uniqueViolation`.
        self = Self.classify(
            hint: pgError.hint,
            message: pgError.message,
            detail: pgError.detail,
            details: nil,
            code: pgError.code
        )
    }
}
#endif
