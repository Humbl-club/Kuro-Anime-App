import Foundation
import KuroCore
import KuroLibrary
import KuroSupabase
import Observation

#if canImport(Supabase)
import Supabase

// MARK: - Releases
// Owner of the account's airing schedule: the `user_airing_next` rows of the signed-in user's
// tracked anime for the next days (`upcomingAirings`) and the formatted countdowns derived from them
// (`countdownByAnimeId`, refreshed by a 60 s timer). Device reminders are ReminderDelivery's
// (`reminders`); this owner triggers them from the Library change sink.
//
// Account scope: every value here is the current account's. The upcoming fetch captures its
// `AccountContext`, runs as one account-scoped load (joined only by the same account), publishes only
// while that context is current, and filters `user_airing_next` with `UserIdText.value(for:)` (the
// single user-id decision point). Throttle and backoff belong to the account and are reset with it.
// The session funnel cancels the load, stops the countdown timer (`cancelAccountWork`) and clears
// the schedule (`clearPrivateState`) on every transition; the timer is (re)started only for the
// current account.
//
// Release schedule and themes (spec §3.1–3.4, `ReleasesStore+Schedule` section below): the account's
// next release per tracked title (`schedule`, `loadSchedule`), one title's upcoming units
// (`mediaSchedule`) and an anime's songs (`themes`). The three RPCs are prepared, not deployed: a
// "not deployed" answer (PGRST202/PGRST205/404/undecodable payload) is remembered for a while and the
// owner falls back silently (anime next episode from `user_airing_next` / `anime.next_airing_at`;
// manga and themes empty, so the UI hides the section). Results are cached per account for 5 min;
// transient failures (offline, 5xx) are never cached. A release whose moment has passed is never
// served as upcoming (spec D10): reads, cache hits and `nextRelease` keep only rows still ahead of
// now, a cache holding an elapsed row is stale, and the 60 s clock tick drops elapsed rows and
// re-reads so the next unit appears (`releaseClockDidTick`; `refreshScheduleIfStale` on foreground).
// `scheduleCoverage(for:)` says whether an empty schedule is an answer or unknown (rulebook §9).

@MainActor
@Observable
final class ReleasesStore: AccountScopedState {
    // Upcoming airings for user's saved anime (next X days)
    struct UpcomingAiring: Decodable, Sendable {
        let anime_id: Int
        let title_english: String?
        let title_romaji: String?
        let next_episode_number: Int?
        let next_airing_at: Date
    }

    struct BackoffState: Sendable {
        var failures: Int = 0
        var until: Date? = nil

        mutating func canAttempt(now: Date = Date()) -> Bool {
            guard let until else { return true }
            return now >= until
        }

        mutating func recordSuccess() {
            failures = 0
            until = nil
        }

        mutating func recordFailure(now: Date = Date()) {
            failures = min(failures + 1, 6)
            let base: Double = 2.0
            let delay = min(60.0, base * pow(2.0, Double(failures - 1)))
            until = now.addingTimeInterval(delay)
        }
    }

    /// The app's single SDK client (shared by every owner); nil when the configuration is
    /// missing, and then every request fails like a transport error (`requiredClient()`).
    let client: SupabaseClient?
    /// The shared account coordinator (every completion is checked against it).
    let accountSession: AccountSessionCoordinator
    /// ReminderDelivery: re-armed / cancelled by the Library change sink below.
    let reminders: ReminderScheduler

    init(client: SupabaseClient?, accountSession: AccountSessionCoordinator, reminders: ReminderScheduler) {
        self.client = client
        self.accountSession = accountSession
        self.reminders = reminders
    }

    /// The SDK client, or `MissingSupabaseConfiguration` when the app has none.
    private func requiredClient() throws -> SupabaseClient {
        guard let client else { throw MissingSupabaseConfiguration() }
        return client
    }

    var upcomingAirings: [UpcomingAiring] = []
    // Formatted countdowns keyed by anime_id
    var countdownByAnimeId: [Int: String] = [:]
    @ObservationIgnored var countdownTimer: Timer?
    var upcomingBackoff = BackoffState()
    var lastUpcomingFetchAt: Date? = nil
    var lastUpcomingDays: Int = 7
    /// The account's in-flight upcoming fetch (joined only by the same account).
    let upcomingLoads = AccountScopedLoads<String, Void>()
    /// Latest follow-up work started by the Library change sink (reminders, upcoming refresh).
    @ObservationIgnored var libraryChangeTask: Task<Void, Never>? = nil

    // MARK: Release schedule state (spec §3.1–3.4; methods in ReleasesStore+Schedule.swift)

    /// Where `schedule` came from.
    enum ScheduleSource: Sendable, Equatable {
        /// Nothing loaded for this account yet.
        case none
        /// `user_release_schedule_v1` (anime and manga, all bases).
        case schedule
        /// The contract is not available: anime next episodes from `user_airing_next` only.
        case airingFallback
    }

    /// The account's next release per tracked title (all media), soonest first, undated last.
    /// Only displayable rows (estimates need confidence ≥ 0.7).
    var schedule: [ReleaseScheduleItem] = []
    /// Where `schedule` came from (`.airingFallback`: manga dates are unknown, not absent).
    var scheduleSource: ScheduleSource = .none
    /// What the last schedule answer can claim per medium (read `scheduleCoverage(for:)`). Empty until
    /// the first answer for this account.
    var scheduleCoverageByMedium: [MediaKind: ReleaseScheduleCoverage] = [:]
    /// The reader's local day ("yyyy-MM-dd") at the last clock tick. Read by the schedule accessors, so
    /// "Today"/"Tomorrow" phrases re-render when the day changes.
    var releaseClockDay: String = ""
    /// The re-read started when a loaded release has passed (the next unit is fetched).
    @ObservationIgnored var scheduleRefreshTask: Task<Void, Never>? = nil
    /// Per-account response caches (5 min), keyed by "<user>|<call>|<arguments>". Cleared on every
    /// account transition.
    @ObservationIgnored var scheduleCache: [String: TimedCache<[ReleaseScheduleItem]>] = [:]
    @ObservationIgnored var themesCache: [String: TimedCache<[ThemeSong]>] = [:]
    /// Contracts that answered "not deployed", with the moment they did. Server state, not account
    /// state: kept across account transitions, retried after `undeployedRetryInterval`.
    @ObservationIgnored var undeployedContracts: [ReleaseContract: Date] = [:]
    /// In-flight schedule reads (joined only by the same account and arguments).
    let scheduleLoads = AccountScopedLoads<String, [ReleaseScheduleItem]>()
    /// In-flight theme reads.
    let themeLoads = AccountScopedLoads<String, [ThemeSong]>()

    // MARK: Release notification state (ReleasesStore+Notifications.swift)

    /// Whether the Profile toggle is on for the current account (every watching / reading title
    /// notifies). Default off (spec D14); a detail bell can still turn single titles on.
    var releaseNotificationsEnabled = false
    /// The device permission as last read (never prompts; `refreshReleaseNotificationState`).
    var notificationPermission: NotificationPermission = .notDetermined
    /// Titles whose notifications the account muted (detail bell off).
    var mutedReleaseNotificationKeys: Set<MediaKey> = []
    /// Titles the account turned on with a detail bell (on even while the toggle is off).
    var allowedReleaseNotificationKeys: Set<MediaKey> = []
    /// The Library projection (watching / reading statuses decide what notifies). Wired by composition.
    @ObservationIgnored weak var library: LibraryStore?
    /// The pending debounced re-plan.
    @ObservationIgnored var releaseNotificationTask: Task<Void, Never>? = nil
    /// Whether the last commit for this account left release notifications pending (an empty plan
    /// then still needs one commit to remove them).
    @ObservationIgnored var hasCommittedReleaseNotifications = false

    // MARK: AccountScopedState

    func cancelAccountWork() {
        libraryChangeTask?.cancel()
        libraryChangeTask = nil
        releaseNotificationTask?.cancel()
        releaseNotificationTask = nil
        scheduleRefreshTask?.cancel()
        scheduleRefreshTask = nil
        upcomingLoads.cancelAll()
        scheduleLoads.cancelAll()
        themeLoads.cancelAll()
        stopCountdownUpdates()
    }

    func clearPrivateState() {
        upcomingAirings = []
        countdownByAnimeId = [:]
        upcomingBackoff = BackoffState()
        lastUpcomingFetchAt = nil
        lastUpcomingDays = 7
        schedule = []
        scheduleSource = .none
        scheduleCoverageByMedium = [:]
        scheduleCache = [:]
        themesCache = [:]
        releaseNotificationsEnabled = false
        notificationPermission = .notDetermined
        mutedReleaseNotificationKeys = []
        allowedReleaseNotificationKeys = []
        hasCommittedReleaseNotifications = false
    }

    func removeDeletedAccountData(userId: String) async throws {
        reminders.removeReleaseNotificationPreferences(userId: userId)
    }

    // MARK: - Upcoming Airings (user-scoped)
    /// `upcomingLoads` key for the single upcoming-airings fetch.
    static let upcomingLoadKey = "upcoming_airings"

    /// Minimum spacing of two upcoming-airings reads for the same window.
    nonisolated static let upcomingThrottle: TimeInterval = 20

    /// Refreshes `upcomingAirings` for the current account (throttled, backed off, joined).
    func fetchUpcomingForUser(days: Int = 7) async {
        _ = await refreshUpcomingForUser(days: days)
    }

    /// `fetchUpcomingForUser`, reporting whether `upcomingAirings` now holds a successful read for
    /// this account: true after a fresh success, or when the throttle skipped the call because a
    /// success landed within the last `upcomingThrottle` seconds; false on failure, backoff or no
    /// account (the rows are then stale or empty and must not be cached). `ignoringBackoff`: a user
    /// action (Try again) sends the read even inside the failure backoff window.
    func refreshUpcomingForUser(days: Int = 7, ignoringBackoff: Bool = false) async -> Bool {
        guard let context = accountSession.current else { return false }
        // Joining this account's in-flight fetch skips the throttle, as before.
        if !upcomingLoads.isRunning(Self.upcomingLoadKey, for: context) {
            // Don't hammer the API when multiple screens mount or when realtime emits bursts.
            let now = Date()
            if days == lastUpcomingDays, let last = lastUpcomingFetchAt, now.timeIntervalSince(last) < Self.upcomingThrottle {
                return true
            }
            guard ignoringBackoff || upcomingBackoff.canAttempt(now: now) else { return false }
            lastUpcomingDays = days
        }
        do {
            try await upcomingLoads.run(key: Self.upcomingLoadKey, context: context) { [weak self] in
                try await self?._fetchUpcomingForUserImpl(days: days, context: context)
            }
        } catch {
            return false
        }
        return accountSession.isCurrent(context)
    }

    private func _fetchUpcomingForUserImpl(days: Int, context: AccountContext) async throws {
        // Same `user_id` text as the list tables (single decision point for finding F1).
        let userId = UserIdText.value(for: context)
        do {
            let nowISO = ISO8601DateFormatter().string(from: Date())
            let untilISO = ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(days) * 24 * 60 * 60))
            let client = try requiredClient()
            let rows: [UpcomingAiring] = try await accountSession.withCredentialLease(for: context) {
                try await client
                .from("user_airing_next")
                .select()
                .eq("user_id", value: userId)
                .gte("next_airing_at", value: nowISO)
                .lt("next_airing_at", value: untilISO)
                .order("next_airing_at", ascending: true)
                .limit(500)
                .execute()
                .value
            }
            guard accountSession.isCurrent(context) else { return }
            self.upcomingAirings = rows
            updateCountdowns()
            lastUpcomingFetchAt = Date()
            upcomingBackoff.recordSuccess()
        } catch {
            guard accountSession.isCurrent(context) else { return }
            upcomingBackoff.recordFailure()
            #if DEBUG
            print("❌ Failed to fetch upcoming airings: \(error)")
            #endif
            throw error
        }
    }

    func publishImport(for context: AccountContext, entries: [LibraryEntry]) async throws {
        guard accountSession.isCurrent(context) else { throw CancellationError() }
        try await upcomingLoads.runFresh(key: Self.upcomingLoadKey, context: context) { [self] in
            try await _fetchUpcomingForUserImpl(days: lastUpcomingDays, context: context)
        }
        guard accountSession.isCurrent(context) else { throw CancellationError() }
        // Release notifications are planned from the schedule (spec D14); the retired per-airing
        // reminders are no longer scheduled here.
        scheduleReleaseNotificationsSoon()
    }

    private func formatInterval(_ interval: TimeInterval) -> String {
        if interval <= 0 { return "Now" }
        let minutes = Int(interval / 60)
        let days = minutes / (60 * 24)
        let hours = (minutes % (60 * 24)) / 60
        let mins = minutes % 60
        if days > 0 { return "\(days)d \(hours)h \(mins)m" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    private func updateCountdowns() {
        let now = Date()
        var map: [Int: String] = [:]
        for u in upcomingAirings {
            let interval = u.next_airing_at.timeIntervalSince(now)
            map[u.anime_id] = formatInterval(interval)
        }
        countdownByAnimeId = map
    }

    /// Starts the 60 s countdown refresh for the account in `context` (the session funnel's
    /// bootstrap). A start for an account that is no longer current is ignored, so a bootstrap that
    /// outlives its account never re-arms the timer stopped by `cancelAccountWork`.
    func startCountdownUpdates(for context: AccountContext) {
        guard accountSession.isCurrent(context) else { return }
        // The account's notification state (and plan) once it is current (no prompt).
        releaseNotificationTask?.cancel()
        releaseNotificationTask = Task { [weak self] in await self?.refreshReleaseNotifications() }
        countdownTimer?.invalidate()
        // Avoid passing an actor-isolated closure to Timer (Swift 6 strict concurrency warning).
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.updateCountdowns()
                strongSelf.releaseClockDidTick()
            }
        }
    }

    func stopCountdownUpdates() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    // MARK: - Library change sink (registered by AppComposition, see LibraryChangeSinks.swift)

    /// Every membership / status change re-plans the release notifications (spec D14; the retired
    /// per-airing reminder and its per-write `anime` read are gone). An added anime, or one whose status changed (e.g.
    /// dropped -> watching, which `animeDidLeave` had emptied), also refreshes upcoming airings here
    /// (throttled and backed off as before): this device's own realtime echo is suppressed
    /// (LibraryRealtimeEcho.swift), so it no longer refreshes them. A removed anime, also one the
    /// projection did not hold, loses its countdown and upcoming rows (and any retired reminder left).
    func libraryDidChange(_ change: LibraryChange) {
        guard accountSession.isCurrent(change.account), !change.isProgressOnly else { return }
        // Membership or status changed: the account's schedule is re-read on its next load, and what
        // notifies (watching / reading only) is re-planned.
        scheduleMembershipDidChange(change)
        scheduleReleaseNotificationsSoon()
        guard change.key.kind == .anime else { return }
        let animeId = change.key.id
        guard change.current != nil else {
            animeDidLeave(animeId)
            return
        }
        if change.current?.status == .completed || change.current?.status == .dropped {
            animeDidLeave(animeId)
            return
        }
        let refreshUpcoming = change.kind == .added || change.previous?.status != change.current?.status
        // What notifies is re-planned above (`scheduleReleaseNotificationsSoon`, watching / reading
        // only); the retired per-airing reminders are no longer armed here (spec D14).
        guard refreshUpcoming else { return }
        libraryChangeTask = Task { [weak self] in
            await self?.fetchUpcomingForUser(days: 7)
        }
    }

    /// An anime left the library: its reminders, countdown and upcoming rows go.
    func animeDidLeave(_ animeId: Int) {
        reminders.cancelAiringNotifications(animeId: animeId)
        countdownByAnimeId[animeId] = nil
        upcomingAirings.removeAll { $0.anime_id == animeId }
    }
}
#endif
