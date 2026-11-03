import Foundation
import KuroCore

#if canImport(Supabase)

// MARK: - Release notifications (device side)
// The account's release-notification preference and the commit of a `ReleaseNotificationPlanner`
// plan, on the SAME ownership chain and owner marker as the airing reminders (F05): every pending
// `release-*` request is removed with the `airing-*` ones when the owning account's session ends or
// another account takes over (`enqueueAiringRemindersRemoval`), and a commit re-checks its account
// after waiting for the chain. Nothing here ever prompts for permission
// (`requestNotificationPermission` is the one explicit, user-initiated call).
//
// Preference per account (app defaults, keyed by the lower-cased user id like the owner marker):
//   nil   → follows the system permission (an account that already allowed notifications keeps
//           getting its reminders after this update; nobody is opted in without having allowed them);
//   true  → on (set by the Profile toggle / a detail bell after permission was granted);
//   false → off (nothing automatic is scheduled, not even the airing reminders).
// Muted titles (the detail bell off) are a per-account set.

extension ReminderScheduler {
    /// What a plan commit did.
    enum ReleaseSyncOutcome: Equatable, Sendable {
        /// The system holds `scheduled` release notifications for the account (stale ones removed).
        case synced(scheduled: Int)
        /// Not allowed (permission missing / revoked, or the account turned them off): nothing added.
        case notAuthorized
        /// Signed out, or the account ended meanwhile: nothing changed.
        case obsolete
    }

    nonisolated static func isDeviceReminderId(_ id: String) -> Bool {
        id.hasPrefix("airing-") || id.hasPrefix(ReleaseNotificationPlanner.identifierPrefix)
    }

    private nonisolated static func preferenceKey(_ userId: String) -> String {
        "com.kuro.releaseNotifications.enabled.\(userId.lowercased())"
    }

    private nonisolated static func mutedKey(_ userId: String) -> String {
        "com.kuro.releaseNotifications.muted.\(userId.lowercased())"
    }

    // MARK: Preference

    /// The account's stored choice (nil: never chosen; follows the system permission).
    func releaseNotificationPreference(for context: AccountContext) -> Bool? {
        userDefaults.object(forKey: Self.preferenceKey(context.userId)) as? Bool
    }

    func setReleaseNotificationPreference(_ enabled: Bool, for context: AccountContext) {
        guard accountSession.isCurrent(context) else { return }
        userDefaults.set(enabled, forKey: Self.preferenceKey(context.userId))
    }

    /// Titles whose release notifications the account muted (detail bell off).
    func mutedReleaseNotificationKeys(for context: AccountContext) -> Set<MediaKey> {
        let raw = userDefaults.stringArray(forKey: Self.mutedKey(context.userId)) ?? []
        return Set(raw.compactMap { text in
            let parts = text.split(separator: ":")
            guard parts.count == 2, let kind = MediaKind(rawValue: String(parts[0])), let id = Int(parts[1]) else { return nil }
            return MediaKey(kind: kind, id: id)
        })
    }

    func setMutedReleaseNotificationKeys(_ keys: Set<MediaKey>, for context: AccountContext) {
        guard accountSession.isCurrent(context) else { return }
        let raw = keys.map { "\($0.kind.rawValue):\($0.id)" }.sorted()
        userDefaults.set(raw, forKey: Self.mutedKey(context.userId))
    }

    /// Account deletion: the account's choices go with it.
    func removeReleaseNotificationPreferences(userId: String) {
        userDefaults.removeObject(forKey: Self.preferenceKey(userId))
        userDefaults.removeObject(forKey: Self.mutedKey(userId))
    }

    // MARK: Permission

    /// The permission now, never prompting.
    func notificationPermission() async -> NotificationPermission {
        await notificationCenter.currentPermission()
    }

    /// THE explicit permission request (call only from a user action: the Profile toggle or a detail
    /// bell). The system prompt appears only while the permission is undecided.
    func requestNotificationPermission() async -> NotificationPermission {
        await notificationCenter.requestAuthorizationIfNeeded()
    }

    // MARK: Commit

    /// Commits `plan` for the account in `context`: adds or replaces its requests and removes pending
    /// `release-*` requests it no longer contains. The budget is the system's 64 minus the device
    /// reminders it does not own (e.g. the airing path's "in 1 hour" requests), soonest first.
    @discardableResult
    func syncReleaseNotifications(_ plan: [PlannedReleaseNotification], context: AccountContext) async -> ReleaseSyncOutcome {
        guard accountSession.isCurrent(context) else { return .obsolete }
        let center = notificationCenter
        return await serialized { [weak self] () -> ReleaseSyncOutcome in
            guard let self, self.accountSession.isCurrent(context) else { return .obsolete }
            guard self.releaseNotificationPreference(for: context) != false,
                  await center.currentPermission() == .authorized else { return .notAuthorized }
            let pending = await center.pendingRequestIdentifiers()
            guard self.accountSession.isCurrent(context) else { return .obsolete }
            let planIds = Set(plan.map(\.id))
            let foreign = pending.filter { !planIds.contains($0) && !$0.hasPrefix(ReleaseNotificationPlanner.identifierPrefix) }
            let budget = max(0, ReleaseNotificationPlanner.maxPending - foreign.count)
            let kept = Array(plan.prefix(budget))
            let keptIds = Set(kept.map(\.id))
            let stale = pending.filter { $0.hasPrefix(ReleaseNotificationPlanner.identifierPrefix) && !keptIds.contains($0) }
            if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
            var scheduled = 0
            for item in kept {
                guard self.accountSession.isCurrent(context), !Task.isCancelled else { return .obsolete }
                if await center.schedule(id: item.id, title: item.title, body: item.body, at: item.fireDate,
                                         userInfo: item.userInfo) {
                    scheduled += 1
                }
            }
            if scheduled > 0 { self.userDefaults.set(context.userId.lowercased(), forKey: Self.airingRemindersOwnerKey) }
            return .synced(scheduled: scheduled)
        }.value
    }

    /// The account turned release notifications off: every pending `airing-*` / `release-*` request
    /// goes (ordered on the chain like any cleanup).
    @discardableResult
    func removeAllReleaseNotifications() -> Task<Void, Never> {
        enqueueAiringRemindersRemoval()
    }
}
#endif
