import Foundation
import KuroCore
import UserNotifications
#if canImport(Supabase)
import Supabase
#endif

// MARK: - Local notifications seam

/// Whether the device lets the app deliver local notifications (F19).
enum NotificationPermission: Sendable, Equatable {
    /// Authorized (also provisional / ephemeral: delivered).
    case authorized
    /// Denied or revoked in Settings: requests would not be delivered.
    case denied
    /// Still undecided (the prompt failed or could not be shown).
    case notDetermined
}

/// What account cleanup and airing reminders need from `UNUserNotificationCenter`.
@MainActor
protocol PendingNotificationCenter {
    func pendingRequestIdentifiers() async -> [String]
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    /// The permission in effect NOW (re-read on every call, so a revocation in Settings is seen). The
    /// user is asked only while undecided, so at most one prompt is ever shown, never one per schedule.
    func requestAuthorizationIfNeeded() async -> NotificationPermission
    /// Schedules a one-shot local notification; a pending request with the same id is replaced.
    /// `false` when the system refused the request.
    func schedule(id: String, title: String, body: String, at date: Date) async -> Bool
}

/// Production `PendingNotificationCenter` backed by `UNUserNotificationCenter.current()`.
struct LiveNotificationCenter: PendingNotificationCenter {
    func pendingRequestIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func requestAuthorizationIfNeeded() async -> NotificationPermission {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                return granted ? .authorized : .denied
            } catch {
                #if DEBUG
                print("⚠️ Notification permission request failed: \(error)")
                #endif
                return .notDetermined
            }
        @unknown default:
            return .denied
        }
    }

    func schedule(id: String, title: String, body: String, at date: Date) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            #if DEBUG
            print("❌ Schedule notif failed: \(error)")
            #endif
            return false
        }
    }
}

#if canImport(Supabase)

// MARK: - ReminderDelivery
// Owner of the device-side airing reminders (anime only): the `airing-<animeId>-start` and
// `airing-<animeId>-1h` local notifications for a title's next episode, scheduled through the
// `PendingNotificationCenter` seam, and the owner marker (`airingRemindersOwnerKey`) naming the
// account they were scheduled for. The schedule truth (`user_airing_next`, countdowns) is Releases'.
//
// Account scope (E1): reminder ids are not account-scoped, so the session funnel removes every
// pending `airing-*` request when the owning account's session ends or another account takes over;
// a restored launch of the same owner keeps them; a failed launch restore removes them only when the
// SDK holds no session any more. Nothing is scheduled for an account that is no longer current.
// Ownership transitions are serialized (F05): every cleanup and every schedule commit (owner marker +
// requests) runs on ONE chain in the order it was issued, and the session funnel issues a cleanup
// synchronously with the transition it belongs to. So a cleanup paused on its pending-request lookup
// can never remove reminders (or the owner marker) of an account that became current after it, and a
// schedule commit re-checks its account after waiting for the chain.
// Triggers (R-E3-3): Releases' Library sink re-arms them on every applied anime change that leaves
// the title tracked and cancels them on removal.
// Permission (F19): re-read on every schedule (a revocation in Settings is seen), asked for only while
// undecided (one prompt). The outcome is explicit (`ScheduleOutcome`): denied/revoked/undecided is
// `.notAuthorized` and adds nothing (no owner marker either); a request the system refused is
// `.failed`; only `.scheduled` means the system holds the reminders.

/// Not `@Observable`: it holds no state a view reads (and is not in the environment).
@MainActor
final class ReminderScheduler {
    /// What `scheduleAiringNotifications` did (F19).
    enum ScheduleOutcome: Equatable, Sendable {
        /// The system holds the title's reminders (start, and 1 h before when that is still ahead).
        case scheduled
        /// Notifications are denied, revoked or undecided: nothing was added.
        case notAuthorized
        /// The title has no upcoming airing: nothing to schedule.
        case notUpcoming
        /// Signed out, or the account ended meanwhile: nothing was added.
        case obsolete
        /// The airing could not be read, or the system refused a request.
        case failed
    }

    /// The app's single SDK client (shared by every owner); nil when the configuration is
    /// missing, and then every request fails like a transport error (`requiredClient()`).
    private let client: SupabaseClient?
    /// The shared account coordinator (a reminder is scheduled only for the current account).
    let accountSession: AccountSessionCoordinator
    /// The object graph's device store: the owner marker lives next to the other account preferences.
    let userDefaults: UserDefaults
    let notificationCenter: any PendingNotificationCenter

    init(
        client: SupabaseClient?,
        accountSession: AccountSessionCoordinator,
        userDefaults: UserDefaults,
        notificationCenter: any PendingNotificationCenter
    ) {
        self.client = client
        self.accountSession = accountSession
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter
    }

    /// The SDK client, or `MissingSupabaseConfiguration` when the app has none.
    private func requiredClient() throws -> SupabaseClient {
        guard let client else { throw MissingSupabaseConfiguration() }
        return client
    }

    /// The tail of the serialized reminder operations (F05): cleanups and schedule commits, in order.
    private var operationTail: Task<Void, Never>?

    /// Runs `operation` after every reminder operation issued before it (the ownership chain).
    private func serialized<T: Sendable>(_ operation: @escaping @MainActor () async -> T) -> Task<T, Never> {
        let previous = operationTail
        let task = Task { @MainActor () -> T in
            await previous?.value
            return await operation()
        }
        operationTail = Task { @MainActor in _ = await task.value }
        return task
    }

    // MARK: - Local Notifications for Airings (Anime only)
    /// Schedules the next-episode reminders for `animeId` on behalf of the account in `context`.
    /// Nothing is scheduled without a signed-in account, after that account's session ended, or without
    /// notification permission; the outcome says which (F19). The commit (owner marker + requests)
    /// waits for every reminder cleanup issued before it (F05).
    @discardableResult
    func scheduleAiringNotifications(animeId: Int, context: AccountContext?) async -> ScheduleOutcome {
        guard let context, accountSession.isCurrent(context) else { return .obsolete }
        struct Row: Decodable { let id: Int; let title_english: String?; let title_romaji: String?; let next_episode_number: Int?; let next_airing_at: Date? }
        let row: Row
        do {
            let client = try requiredClient()
            row = try await client
                .from("anime")
                .select("id,title_english,title_romaji,next_episode_number,next_airing_at")
                .eq("id", value: animeId)
                .single()
                .execute()
                .value
        } catch {
            #if DEBUG
            print("⚠️ Could not schedule notifications: \(error)")
            #endif
            return accountSession.isCurrent(context) ? .failed : .obsolete
        }
        guard let airAt = row.next_airing_at else { return .notUpcoming }
        return await scheduleAiringNotifications(airing: ReleasesStore.UpcomingAiring(anime_id: animeId,
            title_english: row.title_english, title_romaji: row.title_romaji,
            next_episode_number: row.next_episode_number, next_airing_at: airAt), context: context)
    }

    /// Releases already read this schedule under the account lease; reuse it without a per-title read.
    @discardableResult
    func scheduleAiringNotifications(airing: ReleasesStore.UpcomingAiring, context: AccountContext?) async -> ScheduleOutcome {
        guard let context, accountSession.isCurrent(context), !Task.isCancelled else { return .obsolete }
        let animeId = airing.anime_id, airAt = airing.next_airing_at
        guard airAt > Date() else { return .notUpcoming }
        // Re-read on every schedule; asks only while undecided (F19).
        guard await notificationCenter.requestAuthorizationIfNeeded() == .authorized else { return .notAuthorized }
        let title = airing.title_english ?? airing.title_romaji ?? "Upcoming Episode"
        let ep = airing.next_episode_number.map { "E\($0)" } ?? "Next"
        let center = notificationCenter
        return await serialized { [weak self] () -> ScheduleOutcome in
            // Reminders belong to the account that saved the title, still current after the chain.
            guard let self, self.accountSession.isCurrent(context) else { return .obsolete }
            // Schedule "now airing"; the owner marker names the account once the system holds a request.
            guard await center.schedule(id: "airing-\(animeId)-start", title: "\(title) airs now", body: "\(ep) is starting.", at: airAt) else {
                return .failed
            }
            self.userDefaults.set(context.userId.lowercased(), forKey: Self.airingRemindersOwnerKey)
            // Schedule 1 hour before if applicable
            let oneHourBefore = airAt.addingTimeInterval(-3600)
            if oneHourBefore > Date(), self.accountSession.isCurrent(context) {
                guard await center.schedule(id: "airing-\(animeId)-1h", title: "In 1 hour: \(title)", body: "\(ep) airs soon.", at: oneHourBefore) else {
                    return .failed
                }
            }
            return .scheduled
        }.value
    }

    func cancelAiringNotifications(animeId: Int) {
        let ids = ["airing-\(animeId)-start", "airing-\(animeId)-1h"]
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// User id (lower-case) of the account whose `airing-*` reminders are pending.
    static let airingRemindersOwnerKey = "com.kuro.airingReminders.owner"

    /// Airing reminder ids are not account-scoped, so every pending `airing-*` request (and the owner
    /// marker) is removed when the owning account's session ends or another account takes over.
    func removePendingAiringNotifications() async {
        await enqueueAiringRemindersRemoval().value
    }

    /// Issues the removal of every pending `airing-*` request and the owner marker NOW, on the ownership
    /// chain (F05): it runs after every reminder operation issued before it and before every one issued
    /// after it, so the session funnel calls this synchronously with the transition it belongs to, and
    /// awaits the returned task in its asynchronous tail.
    @discardableResult
    func enqueueAiringRemindersRemoval() -> Task<Void, Never> {
        let defaults = userDefaults
        let center = notificationCenter
        return serialized {
            defaults.removeObject(forKey: Self.airingRemindersOwnerKey)
            let ids = await center.pendingRequestIdentifiers().filter { $0.hasPrefix("airing-") }
            guard !ids.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// Whether pending reminders were scheduled by an account other than `userId`.
    func airingRemindersBelongToAnotherAccount(than userId: String) -> Bool {
        guard let owner = userDefaults.string(forKey: Self.airingRemindersOwnerKey) else { return false }
        return !AccountSessionCoordinator.sameUser(owner, userId)
    }
}
#endif
