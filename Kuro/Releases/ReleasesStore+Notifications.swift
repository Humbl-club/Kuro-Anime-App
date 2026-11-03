import Foundation
import KuroCore
import KuroLibrary

#if canImport(Supabase)

// MARK: - Release notifications (view-facing API; state in ReleasesStore)
// Profile toggle and detail bell call these; nothing else may ask for notification permission.
// The plan (`ReleaseNotificationPlanner`) is rebuilt from the account's loaded schedule and its
// watching / reading rows whenever either changes (debounced) and on every foreground, and committed
// on the reminder chain (`ReminderScheduler.syncReleaseNotifications`). Estimates never notify; a time
// is used only for an instant; day-precision releases notify at 09:00 local on their day. Everything
// is cleared on sign-out / account switch (the session funnel's reminder removal covers `release-*`).

/// What a toggle did (the caller shows its own copy).
enum ReleaseNotificationToggleResult: Equatable, Sendable {
    /// On, and the system lets Kuro deliver notifications.
    case enabled
    /// Off: every pending release notification was removed.
    case disabled
    /// The user declined (or turned them off in Settings): nothing changed. The UI offers Settings.
    case permissionDenied
    /// No account is current.
    case signedOut
}

@MainActor
extension ReleasesStore {
    /// Delay between a schedule / Library change and the re-plan.
    nonisolated static let releaseNotificationDebounce: Duration = .seconds(1)

    // MARK: Reading (views)

    /// Whether `key` notifies for the current account (detail bell state).
    func releaseNotificationsOn(for key: MediaKey) -> Bool {
        releaseNotificationsEnabled && !mutedReleaseNotificationKeys.contains(key)
    }

    // MARK: Explicit user actions (the only permission requests)

    /// The Profile toggle. On: asks for permission (the system prompt appears only while undecided),
    /// stores the choice and schedules the account's plan. Off: stores the choice and removes every
    /// pending release notification and airing reminder.
    @discardableResult
    func setReleaseNotificationsEnabled(_ enabled: Bool) async -> ReleaseNotificationToggleResult {
        guard let context = accountSession.current else { return .signedOut }
        guard enabled else {
            reminders.setReleaseNotificationPreference(false, for: context)
            releaseNotificationsEnabled = false
            releaseNotificationTask?.cancel()
            hasCommittedReleaseNotifications = false
            await reminders.removeAllReleaseNotifications().value
            return .disabled
        }
        let permission = await reminders.requestNotificationPermission()
        guard accountSession.isCurrent(context) else { return .signedOut }
        notificationPermission = permission
        guard permission == .authorized else {
            releaseNotificationsEnabled = false
            return .permissionDenied
        }
        reminders.setReleaseNotificationPreference(true, for: context)
        releaseNotificationsEnabled = true
        // A title the user follows should not stay silent because its schedule was never loaded.
        if scheduleCoverageByMedium.isEmpty { _ = await loadSchedule() }
        await syncReleaseNotificationsNow()
        return .enabled
    }

    /// The detail bell for one title. On: turns release notifications on first when they are off
    /// (an explicit action, so it may show the permission prompt), then unmutes the title. Off: mutes
    /// the title (its pending notifications go on the next re-plan; its airing reminders now).
    @discardableResult
    func setReleaseNotification(_ enabled: Bool, for key: MediaKey) async -> ReleaseNotificationToggleResult {
        guard let context = accountSession.current else { return .signedOut }
        var muted = reminders.mutedReleaseNotificationKeys(for: context)
        if enabled {
            if !releaseNotificationsEnabled {
                let result = await setReleaseNotificationsEnabled(true)
                guard result == .enabled else { return result }
            }
            muted.remove(key)
        } else {
            muted.insert(key)
            if key.kind == .anime { reminders.cancelAiringNotifications(animeId: key.id) }
        }
        guard accountSession.isCurrent(context) else { return .signedOut }
        reminders.setMutedReleaseNotificationKeys(muted, for: context)
        mutedReleaseNotificationKeys = muted
        await syncReleaseNotificationsNow()
        return enabled ? .enabled : .disabled
    }

    // MARK: State and plan

    /// Re-reads the permission (no prompt) and the account's choices into the observable state.
    func refreshReleaseNotificationState() async {
        guard let context = accountSession.current else { return }
        let permission = await reminders.notificationPermission()
        guard accountSession.isCurrent(context) else { return }
        notificationPermission = permission
        mutedReleaseNotificationKeys = reminders.mutedReleaseNotificationKeys(for: context)
        let preference = reminders.releaseNotificationPreference(for: context)
        releaseNotificationsEnabled = permission == .authorized && (preference ?? true)
    }

    /// Foreground / bootstrap: state, then (when on) the schedule (cached 5 min) and the plan.
    func refreshReleaseNotifications() async {
        await refreshReleaseNotificationState()
        guard releaseNotificationsEnabled, let context = accountSession.current else { return }
        // An account that turned them on explicitly gets its schedule read even when no screen asked
        // yet; otherwise the plan follows whatever the screens loaded.
        if scheduleCoverageByMedium.isEmpty, reminders.releaseNotificationPreference(for: context) == true {
            _ = await loadSchedule()
        }
        await syncReleaseNotificationsNow()
    }

    /// Re-plans after `releaseNotificationDebounce` (a newer request replaces a waiting one).
    func scheduleReleaseNotificationsSoon() {
        guard releaseNotificationsEnabled, accountSession.current != nil else { return }
        releaseNotificationTask?.cancel()
        releaseNotificationTask = Task { [weak self] in
            try? await Task.sleep(for: Self.releaseNotificationDebounce)
            guard !Task.isCancelled else { return }
            await self?.syncReleaseNotificationsNow()
        }
    }

    /// The current plan for the account (pure inputs; tests read it).
    func plannedReleaseNotifications(now: Date = Date()) -> [PlannedReleaseNotification] {
        let following = Set((library?.allEntries ?? [])
            .filter { $0.status == .current || $0.status == .repeating }
            .map(\.key))
        return ReleaseNotificationPlanner.plan(
            items: scheduleItems(for: nil, now: now), following: following, muted: mutedReleaseNotificationKeys,
            now: now, german: KuroLocale.isGerman, locale: KuroLocale.locale, timeZone: KuroLocale.timeZone)
    }

    /// Commits the current plan now (no-op when off or signed out).
    @discardableResult
    func syncReleaseNotificationsNow(now: Date = Date()) async -> ReminderScheduler.ReleaseSyncOutcome {
        guard let context = accountSession.current else { return .obsolete }
        guard releaseNotificationsEnabled else { return .notAuthorized }
        let plan = plannedReleaseNotifications(now: now)
        // Nothing to add and nothing of ours committed for this account: no device round trip.
        guard !plan.isEmpty || hasCommittedReleaseNotifications else { return .synced(scheduled: 0) }
        let outcome = await reminders.syncReleaseNotifications(plan, context: context)
        if accountSession.isCurrent(context), case .synced(let count) = outcome {
            hasCommittedReleaseNotifications = count > 0
        }
        return outcome
    }
}
#endif
