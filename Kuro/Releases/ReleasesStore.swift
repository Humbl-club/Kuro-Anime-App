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
    private let client: SupabaseClient?
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

    // MARK: AccountScopedState

    func cancelAccountWork() {
        libraryChangeTask?.cancel()
        libraryChangeTask = nil
        upcomingLoads.cancelAll()
        stopCountdownUpdates()
    }

    func clearPrivateState() {
        upcomingAirings = []
        countdownByAnimeId = [:]
        upcomingBackoff = BackoffState()
        lastUpcomingFetchAt = nil
        lastUpcomingDays = 7
    }

    // MARK: - Upcoming Airings (user-scoped)
    /// `upcomingLoads` key for the single upcoming-airings fetch.
    static let upcomingLoadKey = "upcoming_airings"

    func fetchUpcomingForUser(days: Int = 7) async {
        guard let context = accountSession.current else { return }
        // Joining this account's in-flight fetch skips the throttle, as before.
        if !upcomingLoads.isRunning(Self.upcomingLoadKey, for: context) {
            // Don't hammer the API when multiple screens mount or when realtime emits bursts.
            let now = Date()
            if days == lastUpcomingDays, let last = lastUpcomingFetchAt, now.timeIntervalSince(last) < 20 {
                return
            }
            guard upcomingBackoff.canAttempt(now: now) else { return }
            lastUpcomingDays = days
        }
        _ = try? await upcomingLoads.run(key: Self.upcomingLoadKey, context: context) { [weak self] in
            try await self?._fetchUpcomingForUserImpl(days: days, context: context)
        }
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
        let previous = Set(upcomingAirings.map(\.anime_id))
        try await upcomingLoads.runFresh(key: Self.upcomingLoadKey, context: context) { [self] in
            try await _fetchUpcomingForUserImpl(days: lastUpcomingDays, context: context)
        }
        guard accountSession.isCurrent(context) else { throw CancellationError() }
        let eligible = Set(entries.filter { $0.key.kind == .anime && $0.status != .completed && $0.status != .dropped }.map { $0.key.id })
        let current = Set(upcomingAirings.map(\.anime_id)).intersection(eligible)
        for id in previous.subtracting(current) { reminders.cancelAiringNotifications(animeId: id) }
        // iOS has a finite pending-notification budget; refresh a bounded visible schedule.
        for row in upcomingAirings.filter({ current.contains($0.anime_id) }).prefix(32) {
            guard accountSession.isCurrent(context), !Task.isCancelled else { throw CancellationError() }
            _ = await reminders.scheduleAiringNotifications(airing: row, context: context)
        }
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
        countdownTimer?.invalidate()
        // Avoid passing an actor-isolated closure to Timer (Swift 6 strict concurrency warning).
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.updateCountdowns()
            }
        }
    }

    func stopCountdownUpdates() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    // MARK: - Library change sink (registered by AppComposition, see LibraryChangeSinks.swift)

    /// An anime that is tracked after the change (added, or edited e.g. +1 EP) re-arms its
    /// next-episode reminder for the account that made the change, as every anime write did before
    /// E3 (one `anime` read per write, R-E3-3); an added anime also refreshes upcoming airings
    /// (throttled as before; the realtime echo refreshes them for edits). A removed anime, also one
    /// the projection did not hold, loses its reminders, countdown and upcoming rows.
    func libraryDidChange(_ change: LibraryChange) {
        guard change.key.kind == .anime, accountSession.isCurrent(change.account) else { return }
        guard !change.isProgressOnly else { return }
        let animeId = change.key.id
        guard change.current != nil else {
            animeDidLeave(animeId)
            return
        }
        if change.current?.status == .completed || change.current?.status == .dropped {
            animeDidLeave(animeId)
            return
        }
        let context = change.account
        let refreshUpcoming = change.kind == .added
        libraryChangeTask = Task { [weak self] in
            guard let self else { return }
            await self.reminders.scheduleAiringNotifications(animeId: animeId, context: context)
            if refreshUpcoming { await self.fetchUpcomingForUser(days: 7) }
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
