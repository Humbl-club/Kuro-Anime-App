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
// Preference per account (app defaults, keyed by the lower-cased user id like the owner marker;
// spec D14: default OFF):
//   nil / false → off (only titles the account turned on with a detail bell notify);
//   true        → on for every watching / reading title (set by the Profile toggle after permission).
// Per-title overrides (the detail bell): an "allowed" set (on even while the toggle is off) and a
// "muted" set (off even while the toggle is on).

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

    private nonisolated static func allowedKey(_ userId: String) -> String {
        "com.kuro.releaseNotifications.allowed.\(userId.lowercased())"
    }

    /// Set once the retired `airing-*` reminders were removed from this device.
    nonisolated static let legacyAiringRetiredKey = "com.kuro.releaseNotifications.legacyAiringRetired"

    // MARK: Preference

    /// The account's stored choice (nil: never chosen, which is off).
    func releaseNotificationPreference(for context: AccountContext) -> Bool? {
        userDefaults.object(forKey: Self.preferenceKey(context.userId)) as? Bool
    }

    func setReleaseNotificationPreference(_ enabled: Bool, for context: AccountContext) {
        guard accountSession.isCurrent(context) else { return }
        userDefaults.set(enabled, forKey: Self.preferenceKey(context.userId))
    }

    /// Titles whose release notifications the account muted (detail bell off).
    func mutedReleaseNotificationKeys(for context: AccountContext) -> Set<MediaKey> {
        keys(forKey: Self.mutedKey(context.userId))
    }

    func setMutedReleaseNotificationKeys(_ keys: Set<MediaKey>, for context: AccountContext) {
        guard accountSession.isCurrent(context) else { return }
        store(keys, forKey: Self.mutedKey(context.userId))
    }

    /// Titles the account turned on with a detail bell (they notify even while the toggle is off).
    func allowedReleaseNotificationKeys(for context: AccountContext) -> Set<MediaKey> {
        keys(forKey: Self.allowedKey(context.userId))
    }

    func setAllowedReleaseNotificationKeys(_ keys: Set<MediaKey>, for context: AccountContext) {
        guard accountSession.isCurrent(context) else { return }
        store(keys, forKey: Self.allowedKey(context.userId))
    }

    /// Whether anything can notify for the account: the toggle is on, or a bell turned a title on.
    func releaseNotificationsWanted(for context: AccountContext) -> Bool {
        releaseNotificationPreference(for: context) == true || !allowedReleaseNotificationKeys(for: context).isEmpty
    }

    private func keys(forKey key: String) -> Set<MediaKey> {
        let raw = userDefaults.stringArray(forKey: key) ?? []
        return Set(raw.compactMap { text in
            let parts = text.split(separator: ":")
            guard parts.count == 2, let kind = MediaKind(rawValue: String(parts[0])), let id = Int(parts[1]) else { return nil }
            return MediaKey(kind: kind, id: id)
        })
    }

    private func store(_ keys: Set<MediaKey>, forKey key: String) {
        userDefaults.set(keys.map { "\($0.kind.rawValue):\($0.id)" }.sorted(), forKey: key)
    }

    /// Account deletion: the account's choices go with it.
    func removeReleaseNotificationPreferences(userId: String) {
        userDefaults.removeObject(forKey: Self.preferenceKey(userId))
        userDefaults.removeObject(forKey: Self.mutedKey(userId))
        userDefaults.removeObject(forKey: Self.allowedKey(userId))
    }

    // MARK: Legacy cleanup

    /// Removes the retired `airing-*` reminders ("… airs now" / "In 1 hour: …", English only) once per
    /// device (spec §11.2). Ordered on the reminder chain; never prompts.
    @discardableResult
    func retireLegacyAiringRemindersOnce() -> Task<Void, Never>? {
        guard !userDefaults.bool(forKey: Self.legacyAiringRetiredKey) else { return nil }
        let center = notificationCenter
        return serialized { [weak self] in
            let pending = await center.pendingRequestIdentifiers()
            let legacy = pending.filter { $0.hasPrefix(ReleaseNotificationPlanner.legacyAiringPrefix) }
            if !legacy.isEmpty { center.removePendingNotificationRequests(withIdentifiers: legacy) }
            self?.userDefaults.set(true, forKey: Self.legacyAiringRetiredKey)
        }
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
    /// reminders it does not own, soonest first.
    @discardableResult
    func syncReleaseNotifications(_ plan: [PlannedReleaseNotification], context: AccountContext) async -> ReleaseSyncOutcome {
        guard accountSession.isCurrent(context) else { return .obsolete }
        let center = notificationCenter
        return await serialized { [weak self] () -> ReleaseSyncOutcome in
            guard let self, self.accountSession.isCurrent(context) else { return .obsolete }
            guard self.releaseNotificationsWanted(for: context),
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
